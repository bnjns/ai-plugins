#!/usr/bin/env node

import { promises as fs } from "node:fs";
import path from "node:path";
import process from "node:process";

const repoRoot = process.cwd();
const pluginsRoot = path.join(repoRoot, "plugins");
const MCP_PLUGINS = new Set([]);

const MCP_LINK = {
  target: "mcp.json",
  path: ".mcp.json",
};

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

async function createSymlink(linkPath, relativeTarget) {
  const existingTarget = await readSymlinkTarget(linkPath);
  if (existingTarget === relativeTarget) {
    return "ok";
  }

  if (await pathExists(linkPath)) {
    const stat = await fs.lstat(linkPath);
    if (stat.isSymbolicLink()) {
      await fs.unlink(linkPath);
    } else {
      throw new Error(`${linkPath} exists and is not a symlink`);
    }
  }

  await fs.symlink(relativeTarget, linkPath);
  return "created";
}

async function verifySymlink(linkPath, expectedRelativeTarget) {
  if (!(await pathExists(linkPath))) {
    return { ok: false, message: `missing symlink: ${linkPath}` };
  }

  const stat = await fs.lstat(linkPath);
  if (!stat.isSymbolicLink()) {
    return { ok: false, message: `not a symlink: ${linkPath}` };
  }

  const actual = await readSymlinkTarget(linkPath);
  if (actual !== expectedRelativeTarget) {
    return {
      ok: false,
      message: `wrong symlink target for ${linkPath}: expected "${expectedRelativeTarget}", got "${actual}"`,
    };
  }

  const resolved = path.resolve(path.dirname(linkPath), actual);
  if (!(await pathExists(resolved))) {
    return { ok: false, message: `symlink target missing: ${linkPath} -> ${actual}` };
  }

  return { ok: true };
}

async function listPluginDirs() {
  const entries = await fs.readdir(pluginsRoot, { withFileTypes: true });
  return entries
    .filter((entry) => entry.isDirectory() && !entry.name.startsWith("."))
    .map((entry) => entry.name);
}

async function linkPlugin(pluginName, checkOnly) {
  const pluginDir = path.join(pluginsRoot, pluginName);
  const results = [];

  if (!MCP_PLUGINS.has(pluginName)) {
    return results;
  }

  const mcpCanonical = path.join(pluginDir, MCP_LINK.target);
  const mcpLinkPath = path.join(pluginDir, MCP_LINK.path);

  if (!(await pathExists(mcpCanonical))) {
    throw new Error(`${pluginName}: missing canonical MCP config at mcp.json`);
  }

  if (checkOnly) {
    results.push(await verifySymlink(mcpLinkPath, MCP_LINK.target));
  } else {
    const status = await createSymlink(mcpLinkPath, MCP_LINK.target);
    results.push({ ok: true, message: `${MCP_LINK.path}: ${status}` });
  }

  return results;
}

async function main() {
  const checkOnly = process.argv.includes("--check");

  const pluginNames = await listPluginDirs();
  const failures = [];
  const messages = [];

  for (const pluginName of pluginNames.sort()) {
    const results = await linkPlugin(pluginName, checkOnly);
    for (const result of results) {
      if (result.ok) {
        if (result.message) {
          messages.push(`${pluginName}: ${result.message}`);
        }
      } else {
        failures.push(`${pluginName}: ${result.message}`);
      }
    }
  }

  if (messages.length > 0) {
    console.log(checkOnly ? "Symlink check passed:" : "Symlinks linked:");
    for (const message of messages) {
      console.log(`- ${message}`);
    }
  }

  if (failures.length > 0) {
    console.error(checkOnly ? "Symlink check failed:" : "Symlink setup failed:");
    for (const failure of failures) {
      console.error(`- ${failure}`);
    }
    process.exit(1);
  }

  if (!checkOnly) {
    console.log("All Claude MCP symlinks are in place.");
  }
}

await main();
