#!/usr/bin/env node

import { promises as fs } from "node:fs";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";

const repoRoot = process.cwd();
const pluginsRoot = path.join(repoRoot, "plugins");

const CLAUDE_MANIFEST_FIELDS = [
  "name",
  "displayName",
  "version",
  "description",
  "author",
  "license",
  "keywords",
  "logo",
];

const CLAUDE_FORBIDDEN_MANIFEST_FIELDS = new Set(["rules", "skills", "commands", "agents", "mcpServers"]);
const HOOKS_JSON_RELATIVE = "./hooks/hooks.json";

async function pathExists(targetPath) {
  try {
    await fs.access(targetPath);
    return true;
  } catch {
    return false;
  }
}

async function readSymlinkTarget(linkPath) {
  try {
    return await fs.readlink(linkPath);
  } catch {
    return null;
  }
}

async function readJsonFile(filePath) {
  const raw = await fs.readFile(filePath, "utf8");
  return JSON.parse(raw);
}

export function stableStringify(value) {
  return `${JSON.stringify(value, null, 2)}\n`;
}

export async function buildClaudeManifest(cursorManifest, pluginDir) {
  const claude = {};

  for (const field of CLAUDE_MANIFEST_FIELDS) {
    if (cursorManifest[field] !== undefined) {
      claude[field] = cursorManifest[field];
    }
  }

  const hooksPath = path.join(pluginDir, "hooks", "hooks.json");
  if (await pathExists(hooksPath)) {
    claude.hooks = HOOKS_JSON_RELATIVE;
  }

  return claude;
}

export function validateClaudeManifestShape(manifest, pluginName) {
  const errors = [];

  for (const field of CLAUDE_FORBIDDEN_MANIFEST_FIELDS) {
    if (manifest[field] !== undefined) {
      errors.push(
        `${pluginName}: Claude manifest must not include "${field}" (auto-discovered or Cursor-only).`
      );
    }
  }

  if (manifest.hooks !== undefined) {
    if (manifest.hooks !== HOOKS_JSON_RELATIVE) {
      errors.push(
        `${pluginName}: Claude manifest "hooks" must be "${HOOKS_JSON_RELATIVE}" (got "${manifest.hooks}").`
      );
    }
  }

  return errors;
}

async function ensureClaudeManifestFile(pluginDir, pluginName, checkOnly) {
  const cursorManifestPath = path.join(pluginDir, ".cursor-plugin", "plugin.json");
  const claudeManifestPath = path.join(pluginDir, ".claude-plugin", "plugin.json");

  if (!(await pathExists(cursorManifestPath))) {
    throw new Error(`${pluginName}: missing canonical manifest at .cursor-plugin/plugin.json`);
  }

  const cursorManifest = await readJsonFile(cursorManifestPath);
  const expectedManifest = await buildClaudeManifest(cursorManifest, pluginDir);
  const expectedContent = stableStringify(expectedManifest);

  if (await pathExists(claudeManifestPath)) {
    const stat = await fs.lstat(claudeManifestPath);
    if (stat.isSymbolicLink()) {
      if (checkOnly) {
        return {
          ok: false,
          message: `${pluginName}: .claude-plugin/plugin.json is still a symlink; run node scripts/sync-claude-manifests.mjs`,
        };
      }
      await fs.unlink(claudeManifestPath);
    }
  }

  if (checkOnly) {
    if (!(await pathExists(claudeManifestPath))) {
      return {
        ok: false,
        message: `${pluginName}: missing .claude-plugin/plugin.json; run node scripts/sync-claude-manifests.mjs`,
      };
    }

    const actualContent = await fs.readFile(claudeManifestPath, "utf8");
    if (actualContent !== expectedContent) {
      return {
        ok: false,
        message: `${pluginName}: .claude-plugin/plugin.json is out of date; run node scripts/sync-claude-manifests.mjs`,
      };
    }

    return { ok: true, message: `${pluginName}: manifest in sync` };
  }

  const previousContent = (await pathExists(claudeManifestPath))
    ? await fs.readFile(claudeManifestPath, "utf8")
    : null;
  await fs.mkdir(path.dirname(claudeManifestPath), { recursive: true });
  await fs.writeFile(claudeManifestPath, expectedContent, "utf8");

  const status = previousContent === expectedContent ? "ok" : "updated";
  return { ok: true, message: `${pluginName}: .claude-plugin/plugin.json ${status}` };
}

async function listPluginDirs() {
  const entries = await fs.readdir(pluginsRoot, { withFileTypes: true });
  return entries
    .filter((entry) => entry.isDirectory() && !entry.name.startsWith("."))
    .map((entry) => entry.name);
}

async function main() {
  const checkOnly = process.argv.includes("--check");
  const pluginNames = await listPluginDirs();
  const failures = [];
  const messages = [];

  for (const pluginName of pluginNames.sort()) {
    const pluginDir = path.join(pluginsRoot, pluginName);
    const result = await ensureClaudeManifestFile(pluginDir, pluginName, checkOnly);
    if (result.ok) {
      messages.push(result.message);
    } else {
      failures.push(result.message);
    }
  }

  if (messages.length > 0) {
    console.log(checkOnly ? "Claude manifest check passed:" : "Claude manifests synced:");
    for (const message of messages) {
      console.log(`- ${message}`);
    }
  }

  if (failures.length > 0) {
    console.error(checkOnly ? "Claude manifest check failed:" : "Claude manifest sync failed:");
    for (const failure of failures) {
      console.error(`- ${failure}`);
    }
    process.exit(1);
  }

  if (!checkOnly) {
    console.log("All Claude plugin manifests are in sync.");
  }
}

const isMain = process.argv[1] === fileURLToPath(import.meta.url);
if (isMain) {
  await main();
}
