---
name: address-greptile-reviews
description: >
  Triage, verify, and resolve Greptile PR review feedback — scores, summaries, inline comments, thrashing, and evidence-backed pushback. Use when the user asks to review, address, or explain Greptile comments or reviews; pasted app.greptile.com or GitHub review-comment links; generic PR comment work (review PR comments, address review feedback, fix review comments) where Greptile may be among the authors; or babysit/watch a PR on Cursor or Claude (/babysit, /babysit-pr, Autopilot, keep this PR green). Also use for Greptile scores vs the repo's minimum score, auto-approval, PR stuck, mistaken failing-check diagnosis, or flip-flopping / endless new Greptile comments after each new review. Do NOT use for creating or updating PRs (use create-pull-request).
metadata:
  version: 1.0.0
---

# Address Greptile reviews

Greptile is an automated PR reviewer. Some repos gate merges on its score with a **score gate**: a status check or CI job that enforces a minimum score. A failed gate does **not** by itself mean infrastructure broke — it also fails on a score below the repo's minimum. Read the gate's output (for a CI job, its run logs) and Greptile's latest summary (see **Where Greptile surfaces findings**) to tell which. Without a gate, the score in that summary is the source of truth.

Whether Greptile re-reviews when commits are pushed depends on the repo's Greptile config. Don't assume either way: if an earlier push to this PR was followed by a new Greptile review, it auto-reviews on push; if there is no such evidence, ask the user. Without auto-review, a new review only runs when someone retriggers it — usually by tagging `@greptileai` in a PR comment, as the **Retrigger** link in Greptile's summary only works for members of the Greptile org. So after a code fix is pushed, its thread stays open and the score (and any score gate) stay as they were until a review is retriggered. Each review run **costs money**: **ask the user before retriggering one**, and only say Greptile "will re-review" or "will resolve the thread" after a push when the repo auto-reviews on push.

## Asking the user

Ask every question with the client's question tool — `AskQuestion` in Cursor, `AskUserQuestion` in Claude Code — never as plain chat text the user has to type a reply to. If a question is too complex for the tool's options, use the tool first to ask whether they want to discuss it in chat.

## Score policy

| Score | Meaning |
|-------|---------|
| **5/5** | Highest score — aim for this |
| **≥ minimum** | Passing — mergeable once other requirements are met |
| **&lt; minimum** | Below the repo's threshold — address findings or resolve with evidence-backed replies |

The minimum score is set per repo. Take it from the failing check's output or the repo's docs; if neither states it, ask the user — do not assume a value.

**Score gate (if the repo has one):** **passed** = completed review at or above the minimum. **Failed** = run failure **or** completed review below the minimum (see the gate's output + Greptile's summary to tell which).

## When to use / when not

**Use** when the user asks to review, address, or explain Greptile feedback; pasted Greptile or GitHub review-comment links; generic PR comment work where Greptile may be among the authors; babysit/watch a PR (Cursor or Claude); Greptile score or score-gate confusion; or thrashing on Greptile rounds.

**Do NOT use** for `gh pr create`, `gh pr edit`, or `gh pr ready` — read `create-pull-request` instead.

## Prerequisites

- `gh` CLI authenticated (`gh auth status`). If not, stop and tell the user.

## Where Greptile surfaces findings

1. **Summary** — contains the confidence score and summary when review completed. Where it goes depends on the repo's Greptile config:
   - **PR description** — wrapped in `<!-- greptile_comment -->` … `<!-- /greptile_comment -->`. Search the description for those markers first; works even when the PR does not use the `create-pull-request` template. On templated PRs, the block often also sits below the `---` separator.
   - **Dedicated comment or review** — otherwise, look for Greptile's own PR comment or review (`gh pr view --comments`, or the PR's reviews). Use the latest one.
2. **Inline review comments** — on specific lines in the diff.
3. **Score gate** (if the repo has one) — a status check or CI job enforcing the minimum score. **Failed** covers both a Greptile run failure and a completed review below the minimum. When it is failed or ambiguous, read its output (for a CI job, the run logs) and cross-read Greptile's latest summary above.

Inspect authors on every thread. Apply this skill to Greptile findings; handle human and other bot comments with normal judgment.

## Addressing ≠ code fix

"Addressing" a Greptile comment means **closing out the finding** — not automatically changing code.

Valid resolutions:

- **Fix** — when the finding is true and impact warrants a change in this PR.
- **Reply with evidence** — when the finding is wrong, overstated, behind a feature flag, or a deliberate trade-off. Greptile re-assesses replies.
- **Reaction** — GitHub thumbs up/down on the comment helps train Greptile. Use when appropriate; do not substitute empty dismissals.

Do **not** default to a code change. Do **not** reply with "don't care" or equivalent. Pushback must cite code, tests, or product constraints.

## Thread resolution

Who resolves the GitHub thread depends on how the finding was closed:

### Code fix — Greptile resolves

When the issue is fixed in code and pushed, the thread **stays open until Greptile's next review** — on the push if the repo auto-reviews, otherwise once a review is retriggered. Greptile marks the conversation resolved on that review, not on the push itself. **Do not resolve these threads yourself.**

Exception: **amend + force push** can break that flow. Avoid force push on open PRs unless the user explicitly requests it.

If the fix is on the branch and Greptile has not resolved the thread after its next review, **reply in the thread** asking whether it considers the issue resolved — point at the change (commit, line, or behaviour).

### Pushback accepted — agent resolves

When Greptile agrees a comment was wrong, unnecessary, overstated, or not applicable (via your reply, with no code fix in this PR), it **will not** auto-resolve the thread. **Resolve the conversation yourself** once Greptile has acknowledged.

## Per-finding verification (mandatory)

Before fixing, replying, or pushing, verify **each** Greptile comment:

1. **Claim** — read the cited code. Is the issue actually true?
2. **Priority** — compare Greptile's severity to real impact (user-facing, data, security, blast radius). It may over-emphasise impact when it lacks full product or runtime context; a nit is not a blocker.
3. **Act** — pick one:
   - True + impact matches → fix in this PR (or explain why fix is out of scope).
   - True but overstated → cheap local fix if it avoids thrashing; otherwise reply with actual impact and react as appropriate.
   - False or not applicable → reply with evidence; thumbs down if the finding is wrong. Once Greptile accepts, **resolve the thread yourself**. Do not rewrite code to silence a bad finding.

## Feature flags

Greptile may lack full flag or runtime context and treat gated code as a live breaking change. If a comment assumes user-visible impact from code behind a flag:

1. Identify the flag name from the diff or surrounding code.
2. Ask the user to confirm the flag is **off** in the relevant environment(s) — do not guess.
3. **Reply on the thread** with flag name, current state, and that the PR is a no-op until enablement. Do not “fix” behaviour Greptile cannot see is disabled.

## Thrashing (stop before another review)

Each Greptile review **costs money**. Detect thrashing before pushing again (when the repo auto-reviews on push) or asking the user to retrigger another review. To catch further issues without another Greptile review, run the `code-reviewer` skill at high effort, if it is available.

### Flip-flop

Fix A regresses B; the next review flags B, and the fix for B regresses A. **Stop** trading isolated patches. Read both areas together; make one coherent change or reply that the trade-off is intentional.

### Comment churn

Each new review yields a new batch of Greptile comments (same theme or expanding nits) instead of closing the previous set. **Stop** pushing or retriggering and hoping. Reply on remaining threads or batch remaining real issues into one considered change.

### Babysit loops (Cursor or Claude)

Same rule in `/babysit`, `/babysit-pr`, Autopilot, or "keep this PR green" loops. Do not treat every new Greptile comment as a must-fix that justifies another review cycle.

## Workflow

1. **Identify** — from link, `gh pr view`, review threads, or babysit loop. Attribute each finding: Greptile vs human vs other bot.
2. **Read** — Greptile's latest summary (PR description or its own comment/review) and all inline comments.
3. **Read the score gate** (if the repo has one) — `gh pr checks` (or the Checks UI). **Passed** = score at or above the minimum. **Failed** → read the gate's output and Greptile's latest summary:
   ```bash
   gh pr checks
   gh pr view --json statusCheckRollup --jq '.statusCheckRollup[] | select(.context | test("greptile"; "i"))'
   # if the gate is a GitHub Actions job:
   gh run list --branch "$(git branch --show-current)" --limit 5
   gh run view <run-id> --log
   ```
   The gate's output shows run failure vs completed rejection; the summary shows score and findings. Do not infer from failed alone.
4. **Check thrashing** — compare to prior Greptile rounds and recent pushes on this PR.
5. **Verify each finding** — claim + priority (above).
6. **Respond in batch** — prefer one batched pass (fixes and/or replies) over serial review rounds.
7. **Re-check** — Greptile score (and its gate's output, if any), other CI, merge state. Code fix but thread still open → expected until Greptile's next review; if the repo doesn't auto-review on push, ask the user whether to retrigger one. Pushback accepted → resolve the thread yourself.

## Diagnostics

**Greptile score gate failed** — read the gate's output first (for a CI job, its run logs). **Run failure** (timeout, error, incomplete review) vs **completed rejection** (score below the minimum, with findings in the summary and inline comments). Both show failed; only the gate's output + summary distinguish them.

**Score below the minimum, with inline findings** — completed rejection, not infrastructure failure. Read findings, verify each, fix or reply.

**Score unchanged after fixes** — expected until Greptile's next review. If the repo doesn't auto-review on push, the score, any score gate and threads stay as they were until a review is retriggered; ask the user whether to retrigger one. If a new review has run (check Greptile's latest summary, or the gate's output) and the fixed threads stay open, reply in-thread asking Greptile whether the issue is resolved.

**Agent says "check failed" or "PR stuck"** — inspect the Greptile score gate's output (if any) and Greptile's latest summary before treating as CI or infra failure. Confirm other checks with `gh pr checks` separately.

**Greptile flags breaking change on gated code** — confirm flag state with the user; reply with flag off + no-op context. Do not thrash on fixes for disabled paths.

**Greptile timeout / run failure** — the gate's output or Greptile's summary shows an incomplete run (large PRs may hit time limits). Splitting PRs can help but is not always sufficient. Not the same as a low-score rejection — confirm via the output, not check colour alone.

## Babysit integration

When babysitting (Cursor or Claude), apply this skill whenever Greptile comments or scores appear in the loop:

- Verify before auto-fixing Greptile findings.
- Prefer reply or feature-flag context over code when pushback is justified.
- After pushing a fix, only wait for an automatic Greptile re-review if the repo auto-reviews on push. Otherwise ask the user whether to retrigger one instead of looping on the unchanged score or open threads.
- Halt the loop when thrashing is detected; report to the user instead of pushing again.
