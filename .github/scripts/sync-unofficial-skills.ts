#!/usr/bin/env bun

import { execSync } from "node:child_process";
import { readFileSync, writeFileSync } from "node:fs";
import path from "node:path";

interface TrackedRepo {
	owner: string;
	repo: string;
}

interface Tracklist {
	official?: TrackedRepo[];
	unofficial?: TrackedRepo[];
}

interface SourceEntry {
	owner: string;
	repo: string;
	rev: string;
	sha256: string;
}

interface Sources {
	updatedAt: string;
	providers: {
		[key: string]: {
			[key: string]: {
				[key: string]: SourceEntry;
			};
		};
	};
}

const projectRoot = path.join(import.meta.dir, "../..");
const tracklistPath = path.join(projectRoot, "tracklist.json");
const sourcesPath = path.join(projectRoot, "sources.json");

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

function calculateNixHash(owner: string, repo: string, rev: string): string {
	try {
		const archiveUrl = `https://github.com/${owner}/${repo}/archive/${rev}.tar.gz`;

		try {
			const sriHash = execSync(
				`nix hash to-sri --type sha256 $(nix-prefetch-url --unpack "${archiveUrl}" --print-path 2>/dev/null | head -1)`,
				{ encoding: "utf-8", stdio: ["pipe", "pipe", "pipe"], timeout: 30000 },
			).trim();

			const base32 = execSync(`nix hash convert --to base32 "${sriHash}"`, {
				encoding: "utf-8",
				stdio: ["pipe", "pipe", "pipe"],
			}).trim();

			return base32;
		} catch {
			const hashOutput = execSync(
				`nix-prefetch-url --unpack "${archiveUrl}" 2>/dev/null`,
				{ encoding: "utf-8", stdio: ["pipe", "pipe", "pipe"], timeout: 30000 },
			).trim();

			if (hashOutput) {
				return hashOutput;
			}
			throw new Error("nix-prefetch-url failed");
		}
	} catch {
		console.warn(`⚠️  Could not calculate sha256 for ${owner}/${repo}`);
		return "";
	}
}

async function sync() {
	const tracklistContent = readFileSync(tracklistPath, "utf-8");
	const tracklist: Tracklist = JSON.parse(tracklistContent);

	const sourcesContent = readFileSync(sourcesPath, "utf-8");
	const sources: Sources = JSON.parse(sourcesContent);

	if (!sources.providers.unofficial) {
		sources.providers.unofficial = {};
	}

	const trackedMap = new Map<string, TrackedRepo>();
	for (const entry of tracklist.unofficial || []) {
		const key = `${entry.owner}/${entry.repo}`;
		trackedMap.set(key, entry);
	}

	// Track all existing owner/repo combinations for cleanup
	const existingOwnerRepos = new Set<string>();
	for (const owner of Object.keys(sources.providers.unofficial)) {
		for (const repo of Object.keys(sources.providers.unofficial[owner] || {})) {
			existingOwnerRepos.add(`${owner}/${repo}`);
		}
	}

	for (const [key, entry] of trackedMap) {
		if (!sources.providers.unofficial[entry.owner]) {
			sources.providers.unofficial[entry.owner] = {};
		}

		try {
			const rev = await fetchLatestRev(entry.owner, entry.repo);
			const sha256 = calculateNixHash(entry.owner, entry.repo, rev);

			sources.providers.unofficial[entry.owner][entry.repo] = {
				owner: entry.owner,
				repo: entry.repo,
				rev,
				sha256,
			};

			existingOwnerRepos.delete(key);
		} catch (error) {
			console.error(
				`Failed to sync ${key}:`,
				error instanceof Error ? error.message : error,
			);
			process.exit(1);
		}
	}

	// Clean up repos that are no longer tracked
	for (const ownerRepoKey of existingOwnerRepos) {
		const [owner, repo] = ownerRepoKey.split("/");
		if (sources.providers.unofficial[owner]) {
			delete sources.providers.unofficial[owner][repo];
			// Remove owner if empty
			if (Object.keys(sources.providers.unofficial[owner]).length === 0) {
				delete sources.providers.unofficial[owner];
			}
		}
	}

	sources.updatedAt = new Date().toISOString();

	writeFileSync(sourcesPath, JSON.stringify(sources, null, 2) + "\n");
}

sync().catch((error) => {
	console.error("Fatal error:", error);
	process.exit(1);
});
