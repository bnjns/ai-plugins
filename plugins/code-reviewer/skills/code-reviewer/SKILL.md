---
name: code-reviewer
description: >-
  Read-only structured code review — blocking issues vs suggestions, checked against coding-conventions, every other applicable *-conventions skill (e.g. typescript-conventions), and the repo's own rules in AGENTS.md/CLAUDE.md and .greptile/. Use when the user wants a code, PR, branch or pre-merge review (e.g. before pushing or opening a PR, to catch what Greptile would flag), compares a branch to its base, or checks a diff for risks before merge; informal asks like "review these changes", "review this change", "review my changes", "please review this", "can you review?" or "what do you think of this code/diff?" mean the same. Do NOT use for triaging or replying to existing PR review comments, including Greptile's (use address-greptile-reviews), or for creating PRs (use create-pull-request).
metadata:
  version: 1.0.0
---

# Code Reviewer

## Asking the user

Ask every question with the client's question tool — `AskQuestion` in Cursor, `AskUserQuestion` in Claude Code — never as plain chat text the user has to type a reply to. If a question is too complex for the tool's options, use the tool first to ask whether they want to discuss it in chat.

## Scope

If the request is vague (e.g. **"review these changes"**), **still run this skill**—do not substitute a short informal critique unless the user explicitly asked for something else.

Review one of:

1. **The branch (default):** `git diff <base>...HEAD` (three dots: the diff a PR would show), where `<base>` is the branch the user named; otherwise the repo's default branch from `gh repo view --json defaultBranchRef --jq .defaultBranchRef.name`, or `git symbolic-ref --short refs/remotes/origin/HEAD` without the `origin/` prefix if that fails; then the first of `dev`, `main` and `master` that exists on the remote (`git show-ref --verify --quiet refs/remotes/origin/<name>`). If there are no commits ahead of `<base>` (`git log <base>..HEAD` is empty), review the **uncommitted** changes instead: `git diff HEAD` (staged and unstaged) plus any untracked files (`git status --short`).
2. **Changes since a commit or the last review:** when the user asks for that, diff from that commit—or the `HEAD` the last review in this conversation covered—to the working tree: `git diff <commit>`, plus any untracked files.

If it is unclear which the user means, ask **one** short question (see **Asking the user**); otherwise review the branch.

## Read-only mode (required)

The review **must** run in **read-only mode**. The **only** file you may write is the review markdown, when **Step 3** says to save it. Otherwise:

- **Do not** create, edit, delete, or move project files. No drive-by fixes, refactors, formatting, or “while I’m here” changes to application code, tests, config, or `.gitignore`.
- **Do not** run mutating git commands (e.g. commit, merge, rebase, checkout that switches branches, reset, cherry-pick, stash push/pop).
- **Do not** run fix/write variants of tooling (e.g. `eslint --fix`, `gofmt -w`, `ruff check --fix`, `spotlessApply`) or install dependencies unless the user explicitly asked for that **outside** a normal review.

**Allowed:** reading files and docs; inspection-only git (`log`, `diff`, `show`, `branch`, `status`, `ls-files`, `check-ignore`); **check-only** scripts that do not write (see **Tooling** in [references/criteria.md](references/criteria.md)).

## Review process

### Step 1: Understand context

Before reviewing, establish:

- What is this code supposed to do?
- What language, framework, and conventions does the project use?
- Is this a new feature, a bug fix, or a refactor?

#### Conventions

Load these before reviewing. They are the **only** sources for convention findings (see **Conventions** in [references/criteria.md](references/criteria.md)):

1. The `coding-conventions` skill (coding-conventions plugin)—always, when it is available in the session.
2. Every other available skill whose name ends in `-conventions` and whose description covers the language, framework, or area of a changed file—e.g. `typescript-conventions` for `.ts`, `.tsx`, `.mts`, or `.cts` files, or a framework’s `<framework>-conventions` skill for code built on it. Check every skill available in the session, whether it comes from a plugin or the repo’s `.agents/skills/`. If it is unclear whether one applies, load it.
3. Every `AGENTS.md` and `CLAUDE.md` on the path from the repo root to each changed file (skip a `CLAUDE.md` that is a symlink to the `AGENTS.md` beside it).

If sources conflict, the agent file nearest the changed file wins.

#### Repo review rules

Repo-specific review guidance—product context, where to be strict or lenient, extra checks—can live in two places. Greptile reads both, so one set of rules calibrates Greptile and this review alike:

1. **Agent files:** the `AGENTS.md` and `CLAUDE.md` files loaded above. Treat what they say about reviewing, risk, or product context (e.g. “internal tool used by staff”) as repo review rules, alongside their coding conventions.
2. **Greptile config:** for each changed file, walk from the repo root to the file’s directory and read every `.greptile/` folder on the way, or a legacy `greptile.json` where a directory has no `.greptile/` (`git ls-files '*.greptile/*' '*greptile.json'` lists them):
   - `rules.md`: plain-markdown rules for that directory and everything below it.
   - `config.json`: its rules and instructions. Apply a rule that has `scope` globs only to changed files they match; skip rules turned off with `enabled: false` or listed in a deeper folder’s `disabledRules`; don’t review files matched by its ignore patterns.
   - `files.json`: read the files it lists (paths are relative to the directory that contains the `.greptile/` folder).

Rules nearer the changed file add to and override those above it. Apply them on top of [references/criteria.md](references/criteria.md) (see **Repo review rules** there).

### Step 2: Run the review

Load [references/criteria.md](references/criteria.md), then:

1. **Launch independent reviewers:** have the change reviewed by several reviewers working independently, launched together as **subagents** so they run in parallel. Scale the number with the size and risk of the diff:
   - **1** for a small, simple change (e.g. a few lines in one file) or when the user asks for a **quick** review—you can do this one yourself.
   - **3** by default.
   - **More** (e.g. 4–5) for a large, complex, or high-risk diff.

   Give every reviewer the same brief, and have each review against **all** the criteria: the scope and `<base>`; the convention and repo-rule sources from **Step 1** (skill names and file paths); and the absolute path to `references/criteria.md`. Tell them to stay read-only, skip the format, lint and type checks (including running those tools themselves with other configs), and return findings only, each tagged `[BLOCKING]` or `[SUGGESTION]` with **Where**, **Why**, and **Fix**.

   If your client can't run subagents, do one thorough pass yourself against all the criteria, whatever the size of the diff, and say in the **Summary** that the review was a single pass.
2. **Run checks** once yourself while the reviewers work, from the repository root, when possible: the repo’s check-only format, lint and type-check commands (see **Tooling** in criteria.md, including when failures also block). Report the results in **Linting and Formatting**.
3. **Merge** the findings into **one** review: remove duplicates and combine related points. A finding several reviewers raised independently is likely real; before keeping one that only a single reviewer raised, or where reviewers disagree, check it against the code.
4. **Classify and number:** **only** findings that map to a `[BLOCKING]` criterion (or a blocking repo review rule) go in **Blocking Issues**; findings that map to `[SUGGESTION]` (or discretionary notes) go in **Suggestions**. Number them with a **single running sequence** starting at `1` in **Blocking Issues** and **continuing** into **Suggestions** (e.g. blockers `1`–`2`, then suggestions `3`–`5`) so each finding has a **unique id** for follow-up. Use the same one-line pattern for every finding: `N. **[Short title]** — **Where:** [file, symbol, or location]. **Why:** [rationale; for blockers, the criterion or repo rule it breaks]. **Fix:** [the code change].`

### Step 3: Structure the output

**Decision (PASS/FAIL):** **FAIL** if **Blocking Issues** lists one or more findings; **PASS** only when it is exactly `None found.` The Summary should align with this decision.

1. **Chat:** Always paste the full review as structured markdown in the chat.
2. **Save:** Skip this if the user opted out (e.g. “chat only”, “don’t save a file”). Otherwise write the same content to the path the user gave, or to `.claude/reviews/YYYY-MM-DD-HHMMSS.md` under the repository root (creating the directory if needed). Unless the user asked for a file, only write it if `git check-ignore -q <that path>` exits `0`; if not, end the chat reply with: `Not saved — .claude/reviews/ isn't gitignored in this repo. Add .claude/reviews/* to .gitignore to keep reviews.` After saving, state the **file path** in the chat.

Use this structure for the review body (chat and file):

```markdown
## Summary
[2-3 sentence overview and overall assessment]

Decision: [PASS or FAIL]

## Blocking Issues
[`None found.`, or numbered findings per Step 2.]

## Suggestions
[Numbered findings per Step 2, continuing the numbering.]

## Linting and Formatting
[Report errors from the repo’s format, lint and type checks. If none: `No issues`. If not run: `Not run`.]

## Positive Notes
[What the code does well. Always include at least one.]
```
