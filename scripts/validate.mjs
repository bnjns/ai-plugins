#!/usr/bin/env node

import { promises as fs } from "node:fs";
import path from "node:path";
import process from "node:process";

import {
  buildClaudeManifest,
  stableStringify,
  validateClaudeManifestShape,
} from "./sync-claude-manifests.mjs";

const repoRoot = process.cwd();
const errors = [];
const warnings = [];
const seenWarnings = new Set();

const pluginNamePattern = /^[a-z0-9](?:[a-z0-9.-]*[a-z0-9])?$/;
const marketplaceNamePattern = /^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$/;
const MCP_PLUGINS = new Set([]);

const CLAUDE_MCP_LINK = "mcp.json";
const CLAUDE_MARKETPLACE_FORBIDDEN_FIELDS = new Set(["rules", "skills", "commands", "hooks", "agents"]);

function addError(message) {
  errors.push(message);
}

function addWarning(message) {
  if (seenWarnings.has(message)) {
    return;
  }
  seenWarnings.add(message);
  warnings.push(message);
}

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

async function ensureDirectory(targetPath, context) {
  try {
    const stat = await fs.stat(targetPath);
    if (!stat.isDirectory()) {
      addError(`${context} exists but is not a directory: ${targetPath}`);
      return false;
    }
    return true;
  } catch {
    addError(`${context} directory is missing: ${targetPath}`);
    return false;
  }
}

async function readJsonFile(filePath, context) {
  let raw;
  try {
    raw = await fs.readFile(filePath, "utf8");
  } catch {
    addError(`${context} is missing: ${filePath}`);
    return null;
  }

  try {
    return JSON.parse(raw);
  } catch (error) {
    addError(`${context} contains invalid JSON (${filePath}): ${error.message}`);
    return null;
  }
}

function normalizeNewlines(content) {
  return content.replace(/\r\n/g, "\n");
}

function parseFrontmatter(content) {
  const normalized = normalizeNewlines(content);
  if (!normalized.startsWith("---\n")) {
    return null;
  }

  const closingIndex = normalized.indexOf("\n---\n", 4);
  if (closingIndex === -1) {
    return null;
  }

  const frontmatterBlock = normalized.slice(4, closingIndex);
  const fields = {};

  for (const line of frontmatterBlock.split("\n")) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#")) {
      continue;
    }
    const separator = line.indexOf(":");
    if (separator === -1) {
      continue;
    }
    const key = line.slice(0, separator).trim();
    const value = line.slice(separator + 1).trim();
    fields[key] = value;
  }

  return fields;
}

async function walkFiles(dirPath) {
  const files = [];
  const stack = [dirPath];

  while (stack.length > 0) {
    const current = stack.pop();
    const entries = await fs.readdir(current, { withFileTypes: true });
    for (const entry of entries) {
      const entryPath = path.join(current, entry.name);
      if (entry.isDirectory()) {
        stack.push(entryPath);
      } else if (entry.isFile()) {
        files.push(entryPath);
      }
    }
  }

  return files;
}

function isSafeRelativePath(value) {
  if (typeof value !== "string" || value.length === 0) {
    return false;
  }
  if (value.startsWith("http://") || value.startsWith("https://")) {
    return true;
  }
  if (path.isAbsolute(value)) {
    return false;
  }
  const normalized = path.posix.normalize(value.replace(/\\/g, "/"));
  return !normalized.startsWith("../") && normalized !== "..";
}

function extractPathValues(value) {
  if (typeof value === "string") {
    return [value];
  }

  if (Array.isArray(value)) {
    return value.flatMap((entry) => extractPathValues(entry));
  }

  if (value && typeof value === "object") {
    const candidates = [];
    if (typeof value.path === "string") {
      candidates.push(value.path);
    }
    if (typeof value.file === "string") {
      candidates.push(value.file);
    }
    return candidates;
  }

  return [];
}

async function validateReferencedPath(pluginDir, fieldName, pathValue, pluginName) {
  if (pathValue.startsWith("http://") || pathValue.startsWith("https://")) {
    return;
  }

  if (!isSafeRelativePath(pathValue)) {
    addError(
      `${pluginName}: field "${fieldName}" has invalid path "${pathValue}". Use a relative path without ".." or absolute prefixes.`
    );
    return;
  }

  const resolved = path.resolve(pluginDir, pathValue);
  const exists = await pathExists(resolved);
  if (!exists) {
    addError(`${pluginName}: field "${fieldName}" references missing path "${pathValue}".`);
  }
}

async function validateFrontmatterFile(filePath, componentName, requiredKeys, pluginName) {
  const content = await fs.readFile(filePath, "utf8");
  const parsed = parseFrontmatter(content);
  const relativeFile = path.relative(repoRoot, filePath);

  if (!parsed) {
    addError(`${pluginName}: ${componentName} file missing YAML frontmatter: ${relativeFile}`);
    return;
  }

  for (const key of requiredKeys) {
    if (!parsed[key] || parsed[key].length === 0) {
      addError(`${pluginName}: ${componentName} file missing "${key}" in frontmatter: ${relativeFile}`);
    }
  }
}

async function validateComponentFrontmatter(pluginDir, pluginName) {
  const rulesDir = path.join(pluginDir, "rules");
  if (await pathExists(rulesDir)) {
    const files = await walkFiles(rulesDir);
    for (const file of files) {
      const ext = path.extname(file).toLowerCase();
      if (ext === ".md" || ext === ".mdc" || ext === ".markdown") {
        await validateFrontmatterFile(file, "rule", ["description"], pluginName);
      }
    }
  }

  const skillsDir = path.join(pluginDir, "skills");
  if (await pathExists(skillsDir)) {
    const files = await walkFiles(skillsDir);
    for (const file of files) {
      if (path.basename(file) === "SKILL.md") {
        await validateFrontmatterFile(file, "skill", ["name", "description"], pluginName);
      }
    }
  }

  const agentsDir = path.join(pluginDir, "agents");
  if (await pathExists(agentsDir)) {
    const files = await walkFiles(agentsDir);
    for (const file of files) {
      const ext = path.extname(file).toLowerCase();
      if (ext === ".md" || ext === ".mdc" || ext === ".markdown") {
        await validateFrontmatterFile(file, "agent", ["name", "description"], pluginName);
      }
    }
  }

  const commandsDir = path.join(pluginDir, "commands");
  if (await pathExists(commandsDir)) {
    const files = await walkFiles(commandsDir);
    for (const file of files) {
      const ext = path.extname(file).toLowerCase();
      if (ext === ".md" || ext === ".mdc" || ext === ".markdown" || ext === ".txt") {
        await validateFrontmatterFile(file, "command", ["name", "description"], pluginName);
      }
    }
  }
}

async function validateHooksJson(pluginDir, pluginName, requireHooks) {
  const hooksPath = path.join(pluginDir, "hooks", "hooks.json");
  const hooksExists = await pathExists(hooksPath);

  if (requireHooks && !hooksExists) {
    addError(`${pluginName}: hooks/hooks.json is required for this plugin.`);
    return;
  }

  if (!hooksExists) {
    addWarning(`${pluginName}: no hooks/hooks.json file found (only needed when using hooks).`);
    return;
  }

  const hooksConfig = await readJsonFile(hooksPath, `${pluginName} hooks/hooks.json`);
  if (!hooksConfig) {
    return;
  }

  if (!hooksConfig.hooks || typeof hooksConfig.hooks !== "object") {
    addError(`${pluginName}: hooks/hooks.json must contain a top-level "hooks" object.`);
    return;
  }

  const matchersByEvent = new Map();

  for (const [eventName, entries] of Object.entries(hooksConfig.hooks)) {
    if (!Array.isArray(entries)) {
      addError(`${pluginName}: hooks.${eventName} must be an array.`);
      continue;
    }

    for (const entry of entries) {
      if (entry?.matcher !== undefined) {
        if (typeof entry.matcher !== "string") {
          addError(`${pluginName}: hooks.${eventName} matcher must be a string.`);
        } else {
          try {
            new RegExp(entry.matcher);
            const seen = matchersByEvent.get(eventName) ?? [];
            seen.push(entry.matcher);
            matchersByEvent.set(eventName, seen);
          } catch (error) {
            addError(`${pluginName}: hooks.${eventName} matcher is not a valid regex ("${entry.matcher}"): ${error.message}`);
          }
        }
      }

      for (const hook of entry?.hooks ?? []) {
        if (hook?.timeout !== undefined && (!Number.isFinite(hook.timeout) || hook.timeout <= 0)) {
          addError(`${pluginName}: hooks.${eventName} timeout must be a positive number.`);
        }

        if (hook?.type !== "command" || typeof hook.command !== "string") {
          continue;
        }

        const scriptPath = hookCommandPath(hook.command, pluginDir);
        if (!scriptPath) {
          continue;
        }

        if (!(await pathExists(scriptPath))) {
          addError(`${pluginName}: hooks.${eventName} command references a missing script: ${hook.command}`);
          continue;
        }

        if (process.platform !== "win32") {
          const stat = await fs.stat(scriptPath);
          if ((stat.mode & 0o111) === 0) {
            addError(`${pluginName}: hook script is not executable: ${path.relative(pluginDir, scriptPath)}. Run: chmod +x`);
          }
        }
      }
    }
  }

  // A gate satisfiable only by Read forces the agent to re-read SKILL.md after
  // already loading the skill natively. Both recording paths must stay wired.
  if (requireHooks) {
    const postMatchers = matchersByEvent.get("PostToolUse") ?? [];
    for (const toolName of ["Read", "Skill"]) {
      const covered = postMatchers.some((matcher) => new RegExp(`^(?:${matcher})$`).test(toolName));
      if (!covered) {
        addError(`${pluginName}: no PostToolUse matcher covers the ${toolName} tool, so skill reads via ${toolName} are never recorded.`);
      }
    }
  }
}

// Strips the "${CLAUDE_PLUGIN_ROOT}" prefix and any arguments, returning the
// on-disk script path the hook will run.
function hookCommandPath(command, pluginDir) {
  const firstToken = command.trim().match(/^(?:"[^"]*"|'[^']*'|\S)+/);
  if (!firstToken) {
    return null;
  }

  let token = firstToken[0].replace(/["']/g, "");
  if (!token.includes("${CLAUDE_PLUGIN_ROOT}")) {
    return null;
  }

  token = token.replace("${CLAUDE_PLUGIN_ROOT}", "").replace(/^\/+/, "");
  return path.join(pluginDir, token);
}

async function validateSymlink(linkPath, expectedTarget, pluginName, label) {
  if (!(await pathExists(linkPath))) {
    addError(`${pluginName}: missing Claude adapter symlink at ${label}. Run: node scripts/link-claude-adapters.mjs`);
    return;
  }

  const stat = await fs.lstat(linkPath);
  if (!stat.isSymbolicLink()) {
    addError(`${pluginName}: ${label} must be a symlink to ${expectedTarget}, not a regular file.`);
    return;
  }

  const actualTarget = await readSymlinkTarget(linkPath);
  if (actualTarget !== expectedTarget) {
    addError(
      `${pluginName}: ${label} must symlink to "${expectedTarget}" (found "${actualTarget ?? "unknown"}").`
    );
    return;
  }

  const resolved = path.resolve(path.dirname(linkPath), expectedTarget);
  if (!(await pathExists(resolved))) {
    addError(`${pluginName}: ${label} target is missing: ${expectedTarget}`);
  }
}

async function validateClaudeManifest(pluginDir, pluginName, pluginManifest) {
  const claudeManifestPath = path.join(pluginDir, ".claude-plugin", "plugin.json");
  if (!(await pathExists(claudeManifestPath))) {
    addError(
      `${pluginName}: missing .claude-plugin/plugin.json. Run: node scripts/sync-claude-manifests.mjs`
    );
    return;
  }

  const stat = await fs.lstat(claudeManifestPath);
  if (stat.isSymbolicLink()) {
    addError(
      `${pluginName}: .claude-plugin/plugin.json must be a generated file, not a symlink to the Cursor manifest.`
    );
    return;
  }

  const cursorManifestPath = path.join(pluginDir, ".cursor-plugin", "plugin.json");
  const cursorManifest = await readJsonFile(cursorManifestPath, `${pluginName} Cursor plugin manifest`);
  if (!cursorManifest) {
    return;
  }

  const expectedManifest = await buildClaudeManifest(cursorManifest, pluginDir);
  const expectedContent = stableStringify(expectedManifest);
  const actualContent = await fs.readFile(claudeManifestPath, "utf8");
  if (actualContent !== expectedContent) {
    addError(
      `${pluginName}: .claude-plugin/plugin.json is out of date. Run: node scripts/sync-claude-manifests.mjs`
    );
  }

  for (const message of validateClaudeManifestShape(pluginManifest, pluginName)) {
    addError(message);
  }

  if (pluginManifest.hooks !== undefined) {
    await validateReferencedPath(pluginDir, "hooks", pluginManifest.hooks, pluginName);
  }
}

async function validateClaudeAdapters(pluginDir, pluginName) {
  if (MCP_PLUGINS.has(pluginName)) {
    const mcpLink = path.join(pluginDir, ".mcp.json");
    await validateSymlink(mcpLink, CLAUDE_MCP_LINK, pluginName, ".mcp.json");
  }
}

function resolveMarketplaceSource(source, pluginRoot) {
  if (typeof source !== "string" || source.length === 0) {
    return null;
  }

  const normalizedSource = source.replace(/\\/g, "/");
  if (normalizedSource.startsWith("./")) {
    return normalizedSource.slice(2).replace(/^\//, "");
  }

  if (!pluginRoot) {
    return normalizedSource;
  }
  const normalizedRoot = pluginRoot.replace(/\\/g, "/").replace(/\/+$/, "");
  if (normalizedSource === normalizedRoot || normalizedSource.startsWith(`${normalizedRoot}/`)) {
    return normalizedSource;
  }
  return `${normalizedRoot}/${normalizedSource}`;
}

async function validateMarketplace({
  marketplacePath,
  manifestSubdir,
  platformLabel,
  validateClaudeManifests,
  validateClaudeSymlinks,
  hooksRequiredByName,
}) {
  const marketplace = await readJsonFile(marketplacePath, `${platformLabel} marketplace manifest`);
  if (!marketplace) {
    return;
  }

  if (typeof marketplace.name !== "string" || !marketplaceNamePattern.test(marketplace.name)) {
    addError(
      `${platformLabel}: marketplace "name" must be lowercase kebab-case and start/end with an alphanumeric character.`
    );
  }

  if (!marketplace.owner || typeof marketplace.owner.name !== "string" || marketplace.owner.name.length === 0) {
    addError(`${platformLabel}: marketplace "owner.name" is required.`);
  }

  if (!Array.isArray(marketplace.plugins) || marketplace.plugins.length === 0) {
    addError(`${platformLabel}: marketplace "plugins" must be a non-empty array.`);
    return;
  }

  const pluginRoot = marketplace.metadata?.pluginRoot;
  if (pluginRoot !== undefined) {
    if (typeof pluginRoot !== "string" || !isSafeRelativePath(pluginRoot)) {
      addError(`${platformLabel}: marketplace "metadata.pluginRoot" must be a safe relative path.`);
    } else {
      const pluginRootAbs = path.join(repoRoot, pluginRoot);
      await ensureDirectory(pluginRootAbs, `${platformLabel} marketplace "metadata.pluginRoot"`);
    }
  }

  const seenNames = new Set();
  for (const [index, entry] of marketplace.plugins.entries()) {
    const label = `${platformLabel} plugins[${index}]`;

    if (!entry || typeof entry !== "object") {
      addError(`${label} must be an object.`);
      continue;
    }

    if (typeof entry.name !== "string" || !pluginNamePattern.test(entry.name)) {
      addError(`${label}.name must be lowercase and use only alphanumerics, hyphens, and periods.`);
      continue;
    }

    if (seenNames.has(entry.name)) {
      addError(`${platformLabel}: duplicate plugin name in marketplace manifest: "${entry.name}"`);
    }
    seenNames.add(entry.name);

    const sourcePath = resolveMarketplaceSource(entry.source, pluginRoot ?? "");
    if (!sourcePath) {
      addError(`${label}.source must be a string path.`);
      continue;
    }
    if (!isSafeRelativePath(sourcePath)) {
      addError(`${label}.source is not a safe relative path: "${sourcePath}"`);
      continue;
    }

    const pluginDir = path.join(repoRoot, sourcePath);
    const pluginDirExists = await ensureDirectory(pluginDir, `${label}.source`);
    if (!pluginDirExists) {
      continue;
    }

    const manifestPath = path.join(pluginDir, manifestSubdir, "plugin.json");
    const pluginManifest = await readJsonFile(manifestPath, `${entry.name} ${platformLabel} plugin manifest`);
    if (!pluginManifest) {
      continue;
    }

    if (typeof pluginManifest.name !== "string" || !pluginNamePattern.test(pluginManifest.name)) {
      addError(
        `${entry.name}: "name" in ${manifestSubdir}/plugin.json must be lowercase and use only alphanumerics, hyphens, and periods.`
      );
    }

    if (pluginManifest.name && pluginManifest.name !== entry.name) {
      addError(
        `${entry.name}: ${platformLabel} marketplace entry name does not match plugin.json name ("${pluginManifest.name}").`
      );
    }

    if (validateClaudeManifests) {
      for (const field of CLAUDE_MARKETPLACE_FORBIDDEN_FIELDS) {
        if (entry[field] !== undefined) {
          addError(
            `${entry.name}: Claude marketplace entry must not include "${field}". Claude auto-discovers directories; hooks belong in plugin.json only.`
          );
        }
      }
    }

    const manifestFields = ["logo", "rules", "skills", "agents", "commands", "hooks", "mcpServers"];
    for (const field of manifestFields) {
      const values = extractPathValues(entry[field] ?? pluginManifest[field]);
      for (const value of values) {
        await validateReferencedPath(pluginDir, field, value, entry.name);
      }
    }

    await validateComponentFrontmatter(pluginDir, entry.name);
    await validateHooksJson(pluginDir, entry.name, hooksRequiredByName.has(entry.name));

    if (validateClaudeManifests) {
      await validateClaudeManifest(pluginDir, entry.name, pluginManifest);
    }

    if (validateClaudeSymlinks) {
      await validateClaudeAdapters(pluginDir, entry.name);
    }

    const mcpPath = path.join(pluginDir, "mcp.json");
    if (MCP_PLUGINS.has(entry.name) && !(await pathExists(mcpPath))) {
      addError(`${entry.name}: MCP plugin is missing canonical mcp.json.`);
    } else if (!(await pathExists(mcpPath))) {
      addWarning(`${entry.name}: no mcp.json file found (only needed when using MCP servers).`);
    }
  }
}

async function validateRepoRootSymlinks() {
  const claudeMdLink = path.join(repoRoot, "CLAUDE.md");
  await validateSymlink(claudeMdLink, "AGENTS.md", "repo", "CLAUDE.md");
}

// hooks/lib.sh is duplicated rather than shared: each plugin installs on its own
// and CLAUDE_PLUGIN_ROOT is the plugin directory, so sourcing across plugins
// breaks at install time. Keep the copies identical instead.
async function validateSharedHookLib() {
  const canonical = path.join(repoRoot, "plugins", "coding-conventions", "hooks", "lib.sh");
  const copies = [
    path.join(repoRoot, "plugins", "create-pull-request", "hooks", "lib.sh"),
    path.join(repoRoot, "plugins", "dual-platform-agents", "hooks", "lib.sh"),
  ];

  if (!(await pathExists(canonical))) {
    addError(`repo: missing canonical hook library at ${path.relative(repoRoot, canonical)}.`);
    return;
  }

  const expected = await fs.readFile(canonical);
  for (const copy of copies) {
    if (!(await pathExists(copy))) {
      addError(`repo: missing hook library copy at ${path.relative(repoRoot, copy)}.`);
      continue;
    }

    const actual = await fs.readFile(copy);
    if (!actual.equals(expected)) {
      addError(
        `repo: ${path.relative(repoRoot, copy)} differs from the canonical hook library. Copy plugins/coding-conventions/hooks/lib.sh over it.`,
      );
    }
  }
}

async function main() {
  await validateRepoRootSymlinks();
  await validateSharedHookLib();

  await validateMarketplace({
    marketplacePath: path.join(repoRoot, ".cursor-plugin", "marketplace.json"),
    manifestSubdir: ".cursor-plugin",
    platformLabel: "Cursor",
    validateClaudeManifests: false,
    validateClaudeSymlinks: false,
    hooksRequiredByName: new Set(),
  });

  await validateMarketplace({
    marketplacePath: path.join(repoRoot, ".claude-plugin", "marketplace.json"),
    manifestSubdir: ".claude-plugin",
    platformLabel: "Claude",
    validateClaudeManifests: true,
    validateClaudeSymlinks: true,
    hooksRequiredByName: new Set(["coding-conventions", "create-pull-request", "dual-platform-agents"]),
  });

  summarizeAndExit();
}

function summarizeAndExit() {
  if (warnings.length > 0) {
    console.log("Warnings:");
    for (const warning of warnings) {
      console.log(`- ${warning}`);
    }
    console.log("");
  }

  if (errors.length > 0) {
    console.error("Validation failed:");
    for (const error of errors) {
      console.error(`- ${error}`);
    }
    process.exit(1);
  }

  console.log("Validation passed.");
}

await main();
