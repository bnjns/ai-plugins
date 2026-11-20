# Agent guide — bnjns ai-plugins

This repo ships one `plugins/` tree for **Cursor** and **Claude Code**. Manifests and adapter paths differ; follow the rules below so Claude never silently drops skills or hooks.

`CLAUDE.md` is a symlink to this file so Claude Code picks up the same instructions.

## Keep everything generic

Every skill, rule, hook, test, example and doc in this repo must be abstracted away from specific implementations. Never name or reference a particular company, client, employer, job, repository, organisation, team, product, internal service, domain or ticket. Use generic placeholders instead (e.g. `@<scope>/*`, `my-app`, "a shared auth package"), and write anything that varies between setups as conditional (e.g. "the repo's minimum score", "if the repo auto-reviews on push") rather than assuming one setup's values.

## Canonical vs generated files

| Path | Role |
|------|------|
| `plugins/<name>/.cursor-plugin/plugin.json` | **Edit here** — Cursor manifest (skills, rules, hooks dirs, etc.) |
| `plugins/<name>/.claude-plugin/plugin.json` | **Generated** — run `node scripts/sync-claude-manifests.mjs` after changing the Cursor manifest |
| `plugins/<name>/mcp.json` | **Edit here** — canonical MCP config |
| `plugins/<name>/.mcp.json` | Symlink → `mcp.json` (Claude reads this path) |

Never symlink `.claude-plugin/plugin.json` to the Cursor manifest. Cursor and Claude use different manifest specs.

## Claude manifest rules (mandatory)

When editing or reviewing `.claude-plugin/plugin.json` (or the sync script that emits it):

1. **Include only:** `name`, `displayName`, `version`, `description`, `author`, `license`, `keywords`, and optionally `logo`.
2. **Hooks:** only if the plugin ships `hooks/hooks.json`, set `"hooks": "./hooks/hooks.json"` — a path to the **file**, not the directory name `"hooks"`.
3. **Never emit:** `skills`, `rules`, `commands`, `agents`, or `mcpServers`. Claude auto-discovers `skills/` and `commands/` from directories; `rules` is Cursor-only.
4. **Never copy** Cursor manifest fields verbatim into the Claude manifest.

Plugins that omit `skills` in the Claude manifest load skills correctly. Plugins that set `"skills": "skills"` register **zero** skills.

## Cursor manifest rules

Keep using directory fields in `.cursor-plugin/plugin.json` as needed:

- `"skills": "skills"` — Cursor skill discovery
- `"rules": "rules"` — Cursor always-on / path-scoped rules
- `"hooks": "hooks"` — Cursor hook wiring (if used)
- `"commands": "commands"` — Cursor slash commands

## Marketplace manifests

- `.cursor-plugin/marketplace.json` — Cursor team marketplace; may reference `skills`, `rules`, `hooks`, `commands` on plugin entries.
- `.claude-plugin/marketplace.json` — Claude marketplace; plugin entries should list only `name`, `source`, `description`, and optionally `version`. Do **not** put `skills`, `rules`, `hooks`, or `commands` on Claude marketplace entries.

## When to add a plugin

Plugins = distribution/enablement units — the smallest thing a user can turn on or off. Skills/rules/hooks = capabilities.

Before creating a new marketplace plugin, read `.agents/skills/plugin-packaging/SKILL.md`. Give each independent capability its own plugin. Group skills into one plugin only when they depend on each other (e.g. `coding-conventions` and `typescript-conventions`, gated by the same write hook).

## Conventions skills

`code-reviewer` discovers conventions skills by name, so a new one (e.g. `nestjs-conventions`) is reviewed against without changing the reviewer, provided it:

- is named `<topic>-conventions`;
- says in its description which files or stack it applies to (e.g. "Use when writing, refactoring, or reviewing TypeScript");
- writes rules as **MUST** (blocking in reviews) or **SHOULD** (suggestions), like `coding-conventions` and `typescript-conventions`.

Leave anything a linter or formatter can enforce deterministically (e.g. an ESLint rule) to each repo's own config. Conventions skills only cover rules that need judgment.

## Skills that ask the user

A skill that asks the user anything must tell the agent to use the client's question tool — `AskQuestion` in Cursor, `AskUserQuestion` in Claude Code — never plain chat text the user has to type a reply to. For a question too complex for the tool's options, it uses the tool first to ask whether to discuss it in chat. Copy the **Asking the user** section from an existing skill (e.g. `code-reviewer`).

## Workflow after changing a plugin

1. Edit `plugins/<name>/.cursor-plugin/plugin.json` (and plugin content as needed).
2. Bump `version` when shipping a fix users should pick up on sync. **One net bump per PR**, measured against the version on `main` and sized by the largest change in the PR (a patch fix plus a later minor feature is one minor bump). Do not increment again on follow-up commits unless they need a larger bump than the one already set.
3. Run:

```bash
node scripts/sync-claude-manifests.mjs
node scripts/link-claude-adapters.mjs
node scripts/validate.mjs
```

4. Commit both the Cursor manifest and the generated `.claude-plugin/plugin.json`.
5. Update `.claude-plugin/marketplace.json` plugin `version` if you bumped the plugin version (keep it aligned with the single PR bump).

CI runs the same checks (`--check` modes). PRs that skip the sync step will fail validation.

## Hooks (coding-conventions, create-pull-request, dual-platform-agents)

Claude PreToolUse guards live in each plugin's `hooks/hooks.json`. They only register when the Claude manifest points at the file:

```json
"hooks": "./hooks/hooks.json"
```

If `hooks` is missing or set to `"hooks"`, guards never run and agents can skip reading the skill even when a hook script exists.

### Hook script layout

- `hooks/lib.sh` — shared helpers, **byte-identical across every plugin that ships hooks**. Edit the `coding-conventions` copy and copy it over the others (listed in `validateSharedHookLib` in `validate.mjs`); `validate.mjs` fails the build if they diverge. They are duplicated rather than sourced across plugins because each plugin installs on its own and `CLAUDE_PLUGIN_ROOT` is the plugin directory.
- `hooks/gates.sh` — per-plugin `GATED_SKILLS` plus that plugin's path predicates. Sourced by `lib.sh`.

### Gate rules

Skill reads are recorded from **`PostToolUse` on `Read|Skill`**. Keep `Skill` in that matcher — a gate satisfiable only by `Read` forces agents to re-read `SKILL.md` after already loading the skill natively, which `validate.mjs` now rejects.

Write guards only apply to files inside the session `cwd`, and never to agent-owned state: `~/.claude`, `~/.cursor`, `$TMPDIR`, `/tmp`, or any `.claude/` path outside the wiring dirs (`skills`, `agents`, `commands`, `hooks`, `rules`). That keeps plan, memory, and session-scratch writes ungated — do not widen these guards back to bare path substrings.

Run every suite after touching any guard or `lib.sh`:

```bash
bash plugins/coding-conventions/hooks/test-hooks.sh
bash plugins/create-pull-request/hooks/test-hooks.sh
bash plugins/dual-platform-agents/hooks/test-hooks.sh
```

## Adding a new plugin

For each independent capability (see **When to add a plugin** / `plugin-packaging` skill):

1. Add `plugins/<name>/.cursor-plugin/plugin.json` with Cursor fields as needed.
2. Add entries to both marketplace manifests.
3. Run `node scripts/sync-claude-manifests.mjs` to create `.claude-plugin/plugin.json`.
4. If the plugin uses MCP, ensure `mcp.json` exists and run `node scripts/link-claude-adapters.mjs` for `.mcp.json`.
5. If the plugin ships hooks, copy `lib.sh` from `plugins/coding-conventions/hooks/`, add the copy to `validateSharedHookLib` and the plugin to `hooksRequiredByName` in `validate.mjs`, and add its `test-hooks.sh` to `.github/workflows/validate.yml`.
6. Run `node scripts/validate.mjs` before pushing.

## Dual-platform agent files (any application repo)

The **dual-platform-agents** plugin ships the `dual-platform-agents` skill, Cursor rule, and Claude hook. When adding `AGENTS.md`, `CLAUDE.md`, `.agents/`, or `.claude/` in any repo, agents must read that skill and wire both platforms:

- **Cursor:** `AGENTS.md`, `.agents/skills/`
- **Claude:** `CLAUDE.md` → `AGENTS.md`, `.claude/skills` → `../.agents/skills`

Do not duplicate content under `.claude/`. This repo follows the same pattern for its own `AGENTS.md` / `CLAUDE.md` and `.agents/skills` / `.claude/skills`.
