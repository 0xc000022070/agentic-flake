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

const PROJECT_ROOT = path.dirname(
	path.dirname(import.meta.url.replace("file://", "")),
);
const SOURCES_FILE = path.join(PROJECT_ROOT, "sources.json");
const SKILLS_SH_BASE = "https://skills.sh";

let existingSourcesJson: SourcesJson | null = null;
try {
	const content = readFileSync(SOURCES_FILE, "utf-8");
	existingSourcesJson = JSON.parse(content);
} catch {} // not fouund, i don't care

const log = {
	info: (msg: string) => console.log(`✓ ${msg}`),
	warn: (msg: string) => console.warn(`⚠ ${msg}`),
	task: (msg: string) => console.log(`\n📋 ${msg}`),
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

async function fetchSha256(
	owner: string,
	repo: string,
	rev: string,
): Promise<string> {
	const timeoutPromise = new Promise<"">((resolve) => {
		setTimeout(() => {
			resolve("");
		}, 5000);
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

async function fetchHashWithRev(
	owner: string,
	repo: string,
): Promise<{
	rev: string;
	sha256: string;
	skipped?: boolean;
	skippedReason?: string;
}> {
	const rev = await fetchRev(owner, repo);

	if (!rev) {
		log.warn(`${owner}/${repo}: failed to fetch rev`);
		return { rev: "", sha256: "", skipped: false };
	}

	const existingRev =
		existingSourcesJson?.providers?.official?.[owner]?.[repo]?.rev;
	if (existingRev === rev) {
		return {
			rev,
			sha256: existingSourcesJson.providers.official[owner][repo].sha256,
			skipped: true,
			skippedReason: "rev-unchanged",
		};
	}

	const sha256 = await fetchSha256(owner, repo, rev);

	if (!sha256) {
		log.warn(`${owner}/${repo}: timeout on sha256 fetch`);
		return { rev, sha256: "", skipped: true, skippedReason: "timeout" };
	}

	return { rev, sha256, skipped: false };
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

	// Phase 3: Fetch revisions and hashes
	log.task("Phase 3: Fetching revisions and hashes");

	const limit = pLimit(5);
	let processed = 0;
	let skippedRevUnchanged = 0;
	let skippedTimeout = 0;

	const hashResults: Record<
		string,
		Record<
			string,
			{ rev: string; sha256: string; skipped?: boolean; skippedReason?: string }
		>
	> = {};

	for (const org of orgs) {
		hashResults[org] = {};

		const promises = discovered[org].map((repo) =>
			limit(async () => {
				const hash = await fetchHashWithRev(org, repo);
				hashResults[org][repo] = hash;
				if (hash.skipped) {
					if (hash.skippedReason === "rev-unchanged") {
						skippedRevUnchanged++;
					} else if (hash.skippedReason === "timeout") {
						skippedTimeout++;
					}
				}
				processed++;
				log.progress(processed, totalRepos, `${org}/${repo}`);
			}),
		);

		await Promise.all(promises);
	}

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
			const hash = hashResults[org][repo] || { rev: "", sha256: "" };

			// don't create empty entry
			if (!hash.rev) {
				skippedNoRev++;
				continue;
			}

			// If timeout on sha256, keep existing entry if it has meaningful content
			if (hash.skippedReason === "timeout") {
				const existing =
					existingSourcesJson?.providers?.official?.[org]?.[repo];
				if (existing && existing.rev && existing.sha256) {
					sources.providers.official[org][repo] = existing;
				}
				continue;
			}

			if (hash.rev) withRev++;
			if (hash.sha256) withHash++;

			sources.providers.official[org][repo] = {
				owner: org,
				repo: repo,
				rev: hash.rev,
				sha256: hash.sha256,
			};
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
