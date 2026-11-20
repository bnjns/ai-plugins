---
name: dual-platform-agents
description: >-
  Add or change repo-level agent instructions, skills, or agent definitions for
  both Cursor and Claude Code. Use when creating or editing AGENTS.md, CLAUDE.md,
  .agents/, or .claude/ in any repository.
license: MIT
---

# Dual-platform agent files (Cursor + Claude)

Whenever you add or change repo-level agent instructions or skills in **any** repository, wire **both** platforms. Edit canonical files once; expose Claude via symlinks.

## Canonical paths (edit these)

| Path | Purpose |
|------|---------|
| `AGENTS.md` | Repo-wide agent instructions |
| `.agents/skills/<name>/SKILL.md` | Repo-level skills |
| `.agents/agents/<name>.md` | Repo-level agent definitions (when used) |

## Claude adapter paths (symlinks only)

| Path | Symlink target |
|------|----------------|
| `CLAUDE.md` | `AGENTS.md` |
| `.claude/skills` | `../.agents/skills` |
| `.claude/agents` | `../.agents/agents` (when `.agents/agents` exists) |

Never duplicate content under `.claude/`. Never edit symlink targets in place — change the canonical file under `AGENTS.md` or `.agents/`.

If `.claude/skills` already uses per-skill symlinks (e.g. `.claude/skills/foo` → `../../.agents/skills/foo`), add a matching symlink for each new skill instead of replacing the layout.

## MUST: dual-platform checklist

When the user asks to add `AGENTS.md`, `CLAUDE.md`, a skill, or an agent file:

1. Create or update the **canonical** path under `AGENTS.md` or `.agents/`.
2. Ensure `CLAUDE.md` symlinks to `AGENTS.md` (create the symlink if missing).
3. Ensure `.claude/skills` exposes `.agents/skills` (directory symlink or per-skill symlinks matching the repo's existing pattern).
4. When adding `.agents/agents/`, ensure `.claude/agents` symlinks to `../.agents/agents`.
5. Do not create Claude-only copies of skills or instructions.

## Adding a repo-level skill

```bash
mkdir -p .agents/skills/my-skill
# write .agents/skills/my-skill/SKILL.md

# if .claude/skills does not exist yet:
mkdir -p .claude
ln -s ../.agents/skills .claude/skills

# if the repo already uses per-skill symlinks under .claude/skills:
ln -s ../../.agents/skills/my-skill .claude/skills/my-skill
```

## Adding repo-wide instructions

```bash
# edit AGENTS.md (canonical)
ln -sf AGENTS.md CLAUDE.md
```

Use `ln -sf` only when creating or fixing the symlink — do not overwrite an existing `AGENTS.md`.

## Plugin marketplace skills

Skills shipped inside Cursor/Claude **plugins** (`plugins/<name>/skills/` in a marketplace repo) follow separate manifest rules. This skill applies to **application repo** roots, not to plugin authoring unless you are adding repo-level agent files there too.
