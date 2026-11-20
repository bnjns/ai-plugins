---
name: plugin-packaging
description: >-
  When to add or split marketplace plugins in this ai-plugins repo. Use when
  creating a new plugin, moving skills between plugins, or editing plugins/ or
  marketplace manifests.
license: MIT
---

# Plugin packaging (this repo only)

Applies when working in **bnjns/ai-plugins**. Not for application repos.

## MUST: Plugins are enablement units

Plugins = distribution / enablement — the smallest thing a user can turn on or off. Skills, rules, and hooks = capabilities inside a plugin.

## MUST: One plugin per independent capability

1. A new skill that works on its own gets its own plugin, so users can enable it without anything else.
2. Add a skill/rule/hook to an existing plugin only when it depends on that plugin's skills or hooks (e.g. `typescript-conventions` lives in `coding-conventions`: it builds on that skill and shares its write guard).
3. Soft references between plugins are fine (e.g. `create-pull-request` offers `code-reviewer`), but the skill must still work when the other plugin is not installed.
4. Follow [AGENTS.md](../../../AGENTS.md) for Cursor vs Claude manifests, sync, and hooks path (`"./hooks/hooks.json"`).

## MUST: One plugin version bump per PR

When a PR changes a plugin users sync, bump that plugin's `version` **once** for the whole PR (Cursor manifest + both marketplace entries + generated Claude manifest), measured against the version on `main`. Size the bump by the largest change in the PR: if it starts with a patch-level fix and a later commit adds a minor-level feature, the PR's net bump is minor (e.g. `1.0.0` → `1.1.0`, not `1.0.1` or `1.1.1`). Do **not** re-bump on every follow-up commit — only raise the target when a later commit needs a larger bump than the one already set.

## Adding a marketplace plugin

1. Add `plugins/<name>/.cursor-plugin/plugin.json`.
2. Add entries to both marketplace manifests.
3. Run `node scripts/sync-claude-manifests.mjs` (and `link-claude-adapters.mjs` if MCP).
4. Run `node scripts/validate.mjs`.
