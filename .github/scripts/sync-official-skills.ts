#!/usr/bin/env -S bun run

import { readFileSync, writeFileSync } from "node:fs";
import path from "node:path";
import { spawn } from "bun";
import pLimit from "p-limit";

interface Repo {
	owner: string;
	repo: string;
	rev: string;
	sha256: string;
}

interface SourcesJson {
	version: string;
	updatedAt: string;
	namespace: string;
	providers: {
		official: Record<string, Record<string, Repo>>;
	};
}

const PROJECT_ROOT = path.join(import.meta.dir, "../..");
const SOURCES_FILE = path.join(PROJECT_ROOT, "sources.json");
const TRACKLIST_FILE = path.join(PROJECT_ROOT, "tracklist.json");
const SKILLS_SH_BASE = "https://skills.sh";

interface TrackedRepo {
	owner: string;
	repo: string;
	skillName?: string;
}

interface Tracklist {
	official?: TrackedRepo[];
	unofficial?: TrackedRepo[];
}

let existingSourcesJson: SourcesJson | null = null;
try {
	const content = readFileSync(SOURCES_FILE, "utf-8");
	existingSourcesJson = JSON.parse(content);
} catch {} // not fouund, i don't care

const log = {
	info: (msg: string) => console.log(`✓ ${msg}`),
	warn: (msg: string) => console.warn(`⚠ ${msg}`),
	task: (msg: string) => console.log(`\n[~] ${msg}`),
	progress: (current: number, total: number, step: string) =>
		process.stdout.write(`  [${current}/${total}] ${step}...\r`),
};

async function fetchOrganizations(): Promise<string[]> {
	try {
		const proc = spawn(
			[
				"bash",
				"-c",
				`curl -s '${SKILLS_SH_BASE}/official' --compressed -H 'User-Agent: Mozilla/5.0 (X11; Linux x86_64; rv:149.0) Gecko/20100101 Firefox/149.0' | htmlq 'a.group span.font-semibold' --text`,
			],
			{ stdout: "pipe", stderr: "pipe" },
		);

		const output = await new Response(proc.stdout).text();
		const orgs = output
			.split("\n")
			.map((line) => line.trim())
			.filter(Boolean);

		return orgs;
	} catch (error) {
		log.warn(`Error fetching organizations: ${error}`);
		return [];
	}
}

async function fetchOrgRepos(org: string): Promise<string[]> {
	try {
		const proc = spawn(
			[
				"bash",
				"-c",
				`curl -s '${SKILLS_SH_BASE}/${org}' --compressed -H 'User-Agent: Mozilla/5.0 (X11; Linux x86_64; rv:149.0) Gecko/20100101 Firefox/149.0' | htmlq 'h3.font-semibold' --text`,
			],
			{ stdout: "pipe", stderr: "pipe" },
		);

		const output = await new Response(proc.stdout).text();
		const repos = output
			.split("\n")
			.map((line) => line.trim())
			.filter(Boolean);

		return repos;
	} catch (error) {
		log.warn(`Error fetching repos for ${org}: ${error}`);
		return [];
	}
}

async function fetchRev(owner: string, repo: string): Promise<string> {
	try {
		const proc = spawn(
			[
				"bash",
				"-c",
				`git ls-remote https://github.com/${owner}/${repo}.git refs/heads/main | cut -f1`,
			],
			{ stdout: "pipe", stderr: "pipe" },
		);

		const output = await new Response(proc.stdout).text();
		return output.trim();
	} catch {
		return "";
	}
}

async function fetchLatestRev(owner: string, repo: string): Promise<string> {
	const response = await fetch(
		`https://api.github.com/repos/${owner}/${repo}/commits?per_page=1`,
	);
	if (!response.ok) {
		throw new Error(`GitHub API error: ${response.statusText}`);
	}
	const commits = await response.json();
	if (!commits[0]?.sha) {
		throw new Error(`No commits found for ${owner}/${repo}`);
	}
	return commits[0].sha;
}

async function fetchSha256(
	owner: string,
	repo: string,
	rev: string,
): Promise<string> {
	const timeoutPromise = new Promise<"">((resolve) => {
		setTimeout(() => {
			resolve("");
		}, 15000);
	});

	try {
		const proc = spawn(
			[
				"bash",
				"-c",
				`nix-prefetch-url --unpack "https://github.com/${owner}/${repo}/archive/${rev}.tar.gz" 2>/dev/null`,
			],
			{ stdout: "pipe", stderr: "pipe" },
		);

		const resultPromise = (async () => {
			const output = await new Response(proc.stdout).text();
			return output.trim();
		})();

		const result = await Promise.race([resultPromise, timeoutPromise]);
		return result;
	} catch {
		return "";
	}
}

async function main() {
	console.log(`\n${"═".repeat(40)}`);
	console.log("Sync Official Providers");
	console.log("═".repeat(40));

	// Phase 1: Discover
	log.task("Phase 1: Discovering organizations");
	const orgs = await fetchOrganizations();

	if (orgs.length === 0) {
		log.warn("No organizations found");
		return;
	}

	log.info(`Found ${orgs.length} organizations`);

	// Phase 2: Discover repos
	log.task("Phase 2: Discovering repositories");
	const discovered: Record<string, string[]> = {};
	let totalRepos = 0;

	for (const org of orgs) {
		const repos = await fetchOrgRepos(org);
		discovered[org] = repos;
		totalRepos += repos.length;
		log.info(`${org}: ${repos.length} repos`);
	}

	log.info(`Total: ${totalRepos} repositories`);

	// Phase 3: Fetch revisions and hashes (parallel pipeline)
	log.task("Phase 3: Fetching revisions and hashes");

	const revLimit = pLimit(10); // Higher concurrency for rev fetches (fast git ls-remote)
	const sha256Limit = pLimit(3); // Lower concurrency for heavy nix-prefetch-url
	let processed = 0;
	let skippedRevUnchanged = 0;
	let skippedTimeout = 0;

	const revResults: Record<string, Record<string, string>> = {};
	const sha256Results: Record<string, Record<string, string>> = {};
	const prefetchQueue: Array<{ org: string; repo: string; rev: string }> = [];

	// Phase 3a: Fetch all revisions in parallel, queue prefetches for new/changed revs
	for (const org of orgs) {
		revResults[org] = {};

		const promises = discovered[org].map((repo) =>
			revLimit(async () => {
				const rev = await fetchRev(org, repo);
				revResults[org][repo] = rev;

				if (rev) {
					const existingRev =
						existingSourcesJson?.providers?.official?.[org]?.[repo]?.rev;
					if (existingRev !== rev) {
						// New or changed rev, queue for prefetch
						prefetchQueue.push({ org, repo, rev });
					} else {
						// Rev unchanged, skip prefetch
						skippedRevUnchanged++;
					}
				}

				processed++;
				log.progress(processed, totalRepos, `${org}/${repo}`);
			}),
		);

		await Promise.all(promises);
	}

	// Phase 3b: Process prefetch queue in parallel (while rev fetching is done)
	const prefetchPromises = prefetchQueue.map(({ org, repo, rev }) =>
		sha256Limit(async () => {
			const sha256 = await fetchSha256(org, repo, rev);
			if (!sha256Results[org]) {
				sha256Results[org] = {};
			}
			sha256Results[org][repo] = sha256;

			if (!sha256) {
				skippedTimeout++;
				log.warn(`${org}/${repo}: timeout on sha256 fetch`);
			}
		}),
	);

	await Promise.all(prefetchPromises);

	console.log(); // newline after progress
	if (skippedRevUnchanged > 0) {
		log.info(`Skipped ${skippedRevUnchanged} repos (rev unchanged)`);
	}
	if (skippedTimeout > 0) {
		log.warn(`Skipped ${skippedTimeout} repos (timeout on sha256 fetch)`);
	}

	// Phase 4: Build sources.json
	log.task("Phase 4: Building sources.json");

	const sources: SourcesJson = {
		version: "1.0",
		updatedAt: new Date().toISOString(),
		namespace: "skills-sh",
		providers: {
			official: {},
		},
	};

	let withRev = 0;
	let withHash = 0;
	let skippedNoRev = 0;

	for (const org of orgs) {
		sources.providers.official[org] = {};

		for (const repo of discovered[org]) {
			const rev = revResults[org]?.[repo] || "";
			const sha256 = sha256Results[org]?.[repo] || "";

			// don't create empty entry if rev fetch failed
			if (!rev) {
				skippedNoRev++;
				continue;
			}

			// If sha256 is empty, keep existing entry if it has meaningful content
			if (!sha256) {
				const existing =
					existingSourcesJson?.providers?.official?.[org]?.[repo];
				if (existing?.rev && existing?.sha256) {
					sources.providers.official[org][repo] = existing;
				}
				continue;
			}

			if (rev) withRev++;
			if (sha256) withHash++;

			sources.providers.official[org][repo] = {
				owner: org,
				repo: repo,
				rev: rev,
				sha256: sha256,
			};
		}
	}

	// Phase 5: Process tracklist.json official repos
	log.task("Phase 5: Processing official repos from tracklist.json");

	let tracklistOfficial: TrackedRepo[] = [];
	try {
		const tracklistContent = readFileSync(TRACKLIST_FILE, "utf-8");
		const tracklist: Tracklist = JSON.parse(tracklistContent);
		tracklistOfficial = tracklist.official || [];
	} catch {
		log.warn(
			"Could not read tracklist.json, skipping individual official repos",
		);
	}

	for (const entry of tracklistOfficial) {
		const skillName = entry.skillName || entry.repo;
		try {
			const rev = await fetchLatestRev(entry.owner, entry.repo);
			const sha256 = await fetchSha256(entry.owner, entry.repo, rev);

			if (!sources.providers.official[skillName]) {
				sources.providers.official[skillName] = {};
			}

			sources.providers.official[skillName][entry.repo] = {
				owner: entry.owner,
				repo: entry.repo,
				rev: rev,
				sha256: sha256 || "",
			};

			log.info(`Synced official: ${skillName}/${entry.repo}`);
		} catch (error) {
			log.warn(
				`Failed to sync ${entry.owner}/${entry.repo}: ${error instanceof Error ? error.message : error}`,
			);
		}
	}

	writeFileSync(SOURCES_FILE, JSON.stringify(sources, null, 2));
	log.info(`Written: ${SOURCES_FILE}`);

	// Summary
	console.log(`\n${"═".repeat(40)}`);
	console.log("Sync Complete");
	console.log("═".repeat(40));
	console.log(`  Discovered: ${totalRepos} repositories`);
	console.log(
		`  Skipped (no rev): ${skippedNoRev} (${((skippedNoRev / totalRepos) * 100).toFixed(1)}%)`,
	);
	console.log(
		`  With Rev:   ${withRev} (${((withRev / totalRepos) * 100).toFixed(1)}%)`,
	);
	console.log(
		`  With Hash:  ${withHash} (${((withHash / totalRepos) * 100).toFixed(1)}%)`,
	);
	if (skippedRevUnchanged > 0) {
		console.log(`  Skipped (rev unchanged): ${skippedRevUnchanged}`);
	}
	if (skippedTimeout > 0) {
		console.log(`  Skipped (timeout on sha256): ${skippedTimeout}`);
	}
	console.log(`${"═".repeat(40)}\n`);
}

main().catch((error) => {
	console.error("Error:", error);
	process.exit(1);
});
