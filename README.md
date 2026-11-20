# bnjns AI Plugins

Personal plugin marketplace for **Cursor** and **Claude Code + Cowork**. Each plugin is one independent capability, so you can turn on only what you want.

One `plugins/` tree serves both platforms. Plugin manifests are shared; Claude adapter paths use symlinks where content is identical.

Changes ship through this Git repo — push, and clients sync (Claude: marketplace update or marketplace auto-update).

## Plugins

| Plugin | Skills | Enforcement | Setup |
|--------|--------|-------------|-------|
| **Coding Conventions** | `coding-conventions`, `typescript-conventions` | Cursor rules; Claude hook blocks project edits until loaded | None |
| **Dual-Platform Agents** | `dual-platform-agents` | Cursor rule; Claude hook blocks agent-file edits until loaded | None |
| **Git Commit** | `git-commit` | — | None |
| **Create Pull Request** | `create-pull-request` | Cursor rule; Claude hook blocks `gh pr create\|edit\|ready` until loaded | gh CLI auth |
| **Code Reviewer** | `code-reviewer` | — | None |
| **Address Greptile Reviews** | `address-greptile-reviews` | — | gh CLI auth |

Plugins = distribution/enablement units. Skills, rules, and hooks = capabilities inside a plugin. Each independent capability gets its own plugin; skills share one only when they depend on each other (see `.agents/skills/plugin-packaging/SKILL.md` and [AGENTS.md](AGENTS.md)).

`create-pull-request` offers a `code-reviewer` review before pushing, and `code-reviewer` checks against any installed `*-conventions` skills. Both still work when the other plugin isn't installed.

## Repository structure

```
.cursor-plugin/marketplace.json   # Cursor marketplace manifest
.claude-plugin/marketplace.json  # Claude marketplace manifest
.agents/skills/                  # repo-local skills (this marketplace repo only)
.claude/skills → ../.agents/skills
plugins/
  <name>/
    .cursor-plugin/plugin.json   # canonical plugin manifest (edit here)
    .claude-plugin/plugin.json   # generated — node scripts/sync-claude-manifests.mjs
    skills/
    rules/                       # Cursor always-on + path-scoped .mdc rules (if any)
    hooks/                       # Claude PreToolUse / PostToolUse / SessionEnd guards (if any)
scripts/
  validate.mjs                   # validates Cursor + Claude manifests and symlinks
  sync-claude-manifests.mjs      # generate .claude-plugin/plugin.json from Cursor manifest
  link-claude-adapters.mjs       # create/verify Claude .mcp.json symlinks
AGENTS.md                        # agent/contributor rules for dual Cursor + Claude manifests
CLAUDE.md                        # symlink → AGENTS.md (Claude Code reads this path)
```

After clone, sync Claude adapter files:

```bash
node scripts/sync-claude-manifests.mjs
node scripts/link-claude-adapters.mjs
```

## Install

### Claude Code

```text
/plugin marketplace add bnjns/ai-plugins
/plugin install <plugin>@bnjns-claude-plugins
```

### Claude Cowork

1. **Customize → Plugins → Add marketplace** → `https://github.com/bnjns/ai-plugins`
2. Click **Update** on the marketplace after repo pushes.

### Cursor

Cursor only imports Git marketplaces as **Team Marketplaces** (Teams and Enterprise plans): **Dashboard → Plugins & MCPs → Team Marketplaces → Add Marketplace → Import from Repo**.

Otherwise, install a plugin locally: copy `plugins/<plugin>` to `~/.cursor/plugins/local/<plugin>`, then restart Cursor (or run **Developer: Reload Window**).

## Validate before pushing

```bash
node scripts/sync-claude-manifests.mjs --check
node scripts/link-claude-adapters.mjs --check
node scripts/validate.mjs
bash plugins/coding-conventions/hooks/test-hooks.sh
bash plugins/create-pull-request/hooks/test-hooks.sh
bash plugins/dual-platform-agents/hooks/test-hooks.sh
```

See [AGENTS.md](AGENTS.md) for Cursor vs Claude manifest rules (do not copy `skills`/`rules` into Claude manifests).

## Skills vs rules vs hooks

**Skills** only expose a short description until `SKILL.md` is read. Agents can match the description and still skip reading it — which is why enforced workflows get improvised.

**Cursor:** plugin rules (`.mdc` under `rules/`) inject gates:

- **coding-conventions** — `alwaysApply: true` for generic conventions; path-scoped rule on `**/*.{ts,tsx}` for TypeScript.
- **dual-platform-agents** — path-scoped on `AGENTS.md`, `CLAUDE.md`, `.agents/**`, and the `.claude/` wiring dirs (`skills`, `agents`, `commands`, `hooks`, `rules`); read the skill before editing repo-level agent files in any application repo.
- **create-pull-request** — `alwaysApply: true`; read the skill before `gh pr create|edit|ready` (not read-only commands like `gh pr view`).
- **git-commit**, **code-reviewer**, **address-greptile-reviews** — skill only (no rule/hook gate).

**Claude hooks:** no `.mdc` rules in Claude — each enforcing plugin ships `hooks/hooks.json`:

- **Read|Skill** (Post): record when the plugin's gated skills were loaded. Loading a skill with the **Skill tool** satisfies the gate — no separate `Read` of `SKILL.md` is needed.
- **coding-conventions** — **Write|Edit|MultiEdit|NotebookEdit**: blocks edits to project files until `coding-conventions` is read (and `typescript-conventions` for `.ts`/`.tsx`/`.mts`/`.cts`).
- **dual-platform-agents** — **Write|Edit|MultiEdit|NotebookEdit**: blocks repo agent-file edits until `dual-platform-agents` is read.
- **create-pull-request** — **Shell|Bash**: blocks `gh pr create|edit|ready` until `create-pull-request` is read.
- **SessionEnd**: clears the plugin's skill acks. Acks also expire — 12h when the payload carries a session identity, 15m when it does not (that fallback key is derived from `cwd` and cannot separate two conversations in the same project), so a crashed session cannot leave one behind.

Write gates apply only inside the session's `cwd`, and never to agent-owned state — `~/.claude`, `$TMPDIR`, `/tmp`, or any `.claude/` path that is not `skills`, `agents`, `commands`, `hooks` or `rules` (so plan, memory and session-scratch files are untouched).

## Symlinks on Windows

Git symlinks need Developer Mode or elevated `mklink` on Windows. macOS/Linux and CI are fine. If a symlink appears as a plain text file, re-clone with `git config core.symlinks true`.

## Further reading

- [Cursor Plugins docs](https://cursor.com/docs/plugins)
- [Claude plugin marketplaces](https://code.claude.com/docs/en/plugin-marketplaces)
