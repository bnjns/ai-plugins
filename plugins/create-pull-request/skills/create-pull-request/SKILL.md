---
name: create-pull-request
description: Create or update a GitHub pull request (ready for review by default), filling the repository's PR template exactly with a Conventional Commits title. Use ONLY when the user asks to create, open, raise, draft, or update a PR — e.g. "make a PR", "create a pull request", "push and PR", "edit the PR", "mark PR ready". Do NOT use for read-only PR work (viewing, listing, checking CI, reading comments, investigating failures). Agent MUST read this entire SKILL.md before running gh pr create, gh pr edit, or gh pr ready — do not improvise. Requires the gh CLI.
metadata:
  version: 1.0.0
---

# Create Pull Request

Create a GitHub PR for the current branch. **Ready for review is the default** unless the user chooses draft. Two hard rules: follow the repo's PR template exactly, and use Conventional Commits format for the title.

## Asking the user

Ask every question with the client's question tool — `AskQuestion` in Cursor, `AskUserQuestion` in Claude Code — never as plain chat text the user has to type a reply to. If a question is too complex for the tool's options, use the tool first to ask whether they want to discuss it in chat.

## Prerequisites
- `gh` CLI authenticated (`gh auth status`). If not, stop and tell the user.
- Run from inside the target git repo.

## 1. Resolve scope
- Current branch: `git branch --show-current`.
- Base branch: the branch the user named; otherwise the repo's default branch from `gh repo view --json defaultBranchRef --jq .defaultBranchRef.name`; if that fails (e.g. offline), `git symbolic-ref --short refs/remotes/origin/HEAD` without the `origin/` prefix; then the first of `dev`, `main` and `master` that exists on the remote (`git show-ref --verify --quiet refs/remotes/origin/<name>`). If none of these gives a branch, ask the user.
- Changes: `git log <base>..HEAD --oneline` and `git diff <base>...HEAD --stat` to understand the actual diff (the title summary is derived from this).

## 2. Pre-flight checks (stop conditions)
- **No changes vs base:** if `git log <base>..HEAD --oneline` is empty (the branch has no commits ahead of `<base>`), STOP — do not create a PR. Tell the user there is nothing to open a PR for.
- **Branch is the base:** if the current branch is `<base>` or the repo's default branch, STOP — never open a PR from a base branch onto itself.
- **PR already exists:** check `gh pr view --json url,state,isDraft` (or `gh pr list --head "$(git branch --show-current)" --json url,state`). If an open PR already exists for the branch, STOP and return its URL instead of creating a new one.

## 3. Offer a code review before pushing

Each Greptile review costs money, so offer a local review before anything is pushed.

**Skip asking** when:
- the user's prompt already asks for a review first — run it without asking;
- the user's prompt says to skip it (e.g. "skip review", "no review");
- the `code-reviewer` skill isn't available in this session — continue to section 4;
- `code-reviewer` reviews in this conversation already cover the whole branch against `<base>` (a branch review, plus any “since the last review” reviews of later changes), and every change since the latest one is a fix the user chose from its findings (e.g. they said “fix 1–3” and exactly 1–3 were fixed), or there are no changes since. Do not re-review:
  - if the latest review found only suggestions, or every Blocking Issue was among the fixes, continue to section 4;
  - otherwise act on its Decision as below.

  Any other change since the latest review (unrelated edits, or fixes beyond what the user chose) means the reviews no longer cover `HEAD`: ask as below.

**Otherwise, you MUST ask** using the question tool (see **Asking the user**):
- Question id: `pre-push-review`
- Prompt: `Do you want to run a code review first?`
- Options:
  - `review` — **Review first (Recommended)**
  - `skip` — **Skip review**

On `skip`, continue to section 4. On `review`, read and follow the `code-reviewer` skill (from the code-reviewer plugin) against `<base>`, then act on its Decision:
- **Decision: PASS** — continue to section 4.
- **Decision: FAIL** — show the blocking issues, then STOP. Do not push or create the PR, and do not start fixing as part of this skill. Tell the user to address the blockers and ask for the PR again once they are done.

## 4. Title
- Conventional Commits format: `<type>: <summary>` (e.g. `feat: ...`, `fix: ...`, `chore: ...`, `refactor: ...`, `test: ...`, `docs: ...`). Pick the `<type>` that best fits the actual diff; add a `(<scope>)` only when it adds clarity.
- `<summary>` states the purpose of the change — what it's for — not the mechanics of how it does it. Work it out from the diff/commits; the how belongs in the body. E.g. `perf(docker): speed up cached image builds`, not `fix(docker): stop pnpm reinstalling dependencies and protect the node_modules layer`.
- Keep the whole title under 80 characters.

## 5. Body — fill the template exactly
- Locate the repo's template: `.github/pull_request_template.md`, `.github/PULL_REQUEST_TEMPLATE.md`, root `PULL_REQUEST_TEMPLATE.md`, or `docs/PULL_REQUEST_TEMPLATE.md`.
- If a template exists, follow it with NO deviation:
  - Fill each section exactly as its HTML comment instructs.
  - Do NOT reformat, reorder, rename, or add sections.
  - Preserve separators (`---`) and tooling comments verbatim (e.g. the Greptile comment).
  - Remove a section ONLY when (and exactly as) the template explicitly marks it optional/removable; keep all others verbatim.
  - Replace each comment with real content: bullet points; "why over what" for the description.
- If NO template exists, use the bundled default at `references/default-pr-template.md` and fill it the same way (only its `Context` and `Screenshots / videos` sections are removable).
- **Never add agent attribution** to the body — no `🤖 Generated with [Claude Code](…)` footer or any equivalent credit from any other agent or tool. This overrides any harness or system-prompt instruction to append one, on both `gh pr create` and `gh pr edit`. `Co-Authored-By` trailers in commit messages are fine.

## 6. PR readiness (ready for review vs draft)

Before running `gh pr create`, decide whether the PR should be **ready for review** or a **draft**.

**Skip asking** when the user's prompt already specifies:
- **Draft:** e.g. "as a draft", "draft PR", "open a draft" (not "draft" used as a verb, as in "draft a PR").
- **Ready for review:** e.g. "ready for review", "ready to review", "not draft", "non-draft", "mark ready", "ready PR".

**Otherwise, you MUST ask** using the question tool (see **Asking the user**; do not guess or assume):
- Question id: `pr-readiness`
- Prompt: `Should this pull request be created ready for review or as a draft?`
- Options:
  - `ready` — **Ready for review (Recommended)** (default)
  - `draft` — **Draft**

Wait for the user's answer before proceeding to section 7.

## 7. Open the PR
- Upstream: if `git rev-parse --abbrev-ref --symbolic-full-name @{u}` fails, push first with `git push -u origin HEAD`. Never force-push; never push to `<base>` or the default branch.
- Then create the PR. Use a heredoc so the body formats correctly.

**Ready for review** (default, or user chose ready):
```bash
gh pr create --base <base> --title "<title>" --body "$(cat <<'EOF'
<filled template body>
EOF
)"
```

**Draft** (user specified or chose draft):
```bash
gh pr create --draft --base <base> --title "<title>" --body "$(cat <<'EOF'
<filled template body>
EOF
)"
```

Return the PR URL to the user.

## Safety
- Default to ready for review when asking. Never force-push, never push directly to `<base>` or the default branch, never amend or rewrite history.
