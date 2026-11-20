# Code review criteria

## Severity labels (how to use this file)

Each criterion is a single list item prefixed with **`[BLOCKING]`** or **`[SUGGESTION]`**:

- **`[BLOCKING]`** — If the change **violates** this criterion, it belongs in the review’s **Blocking Issues** and makes the review **FAIL** until fixed. If the ticket explicitly accepts the risk, list it under **Suggestions** instead and cite the ticket.
- **`[SUGGESTION]`** — If the change **could improve** against this criterion, it belongs in **Suggestions**; it does **not** by itself justify FAIL.

This file is shared across repositories. Repo-specific conventions and review rules come from the sources in **Step 1** of `SKILL.md`, not from edits here; they can also add blockers to sections that have no `[BLOCKING]` lines.

## Findings are code changes

Every finding is a change to the code under review. Don’t report notes for the PR description, checks or comparisons to run before merging, rollout steps, or anything else that isn’t a code change.

## Repo review rules

Review rules from the repo’s agent files and Greptile config (**Step 1** of `SKILL.md`) extend and calibrate this file. Where one conflicts with a criterion here, the repo rule wins. Cite the rule in **Why** whenever it shapes a finding.

- **Extra checks:** a repo rule phrased as must, never, always, or do not, or given `high` (or higher) severity in `config.json`, is blocking; any other repo rule is a suggestion.
- **Leniency:** guidance such as “internal tool—accept unlikely edge cases” lowers the bar for Correctness, Error handling, Reliability, Performance, and Maintainability findings: drop the findings it covers, or keep them as suggestions when the risk is real but accepted. It never relaxes **Security** criteria unless the rule names the Security criterion it relaxes.

## Tooling

From the **repository root**, run the repo’s **check-only** format, lint and type-check commands: the ones named in the root or nearest `AGENTS.md`/`CLAUDE.md`, otherwise clearly check-only `justfile` recipes, `Makefile` targets, or the commands for the repo’s language(s) below. Read a script’s body before running it; skip anything that fixes or writes. Only errors count—ignore warnings, and run the linter in errors-only mode where it has one.

By language (run only the tools the repo actually configures):

- **Node**: check-only `package.json` scripts (e.g. `check:format`, `check:lint`, `check:types`), `prettier --check`, `eslint --quiet` (never `--fix`).
- **Go**: `gofmt -l .` (never `-w`; it exits 0, so any listed file is a failure), `go vet ./...`, `golangci-lint run` (never `--fix`).
- **Python**: `ruff check` (never `--fix`) and `ruff format --check`, or `black --check`; `mypy` or `pyright`.
- **Terraform**: `terraform fmt -check -recursive`, `tflint`, `terraform validate`. If a directory isn’t initialised, run `terraform init -backend=false -lockfile=readonly` first—never any other form of `terraform init`.
- **Kotlin/JVM (Gradle)**: the check tasks the build defines, e.g. `./gradlew ktlintCheck`, `detekt` or `spotlessCheck`—never `ktlintFormat` or `spotlessApply`.

**Process:** Those commands own format, lint and type rules, including which files they cover. **Do not** manually re-audit those rules, run the tools with other configs (e.g. a scratch config file), or report errors in files a command excludes—the exclusion is intentional. If they pass, do not invent extra style or type feedback. **Do not** change their **configuration**. Failing checks are not a merge blocker by default; if a repo rule makes one, also add a Blocking Issue that points to **Linting and Formatting**.

**Linting and Formatting output (not Blocking Issues or Suggestions):**

- Report pass/fail (or a concise summary of the errors) for each check command you ran.
- If a command could not be found or run, say so explicitly.

## Security

- [BLOCKING] **Secrets**: hardcoded API keys, passwords, database credentials, or tokens
- [BLOCKING] **Auth**: bypass or weakening of authentication or authorization
- [BLOCKING] **Data exposure**: PII, credentials, or sensitive business data leaked in responses, logs, or errors
- [BLOCKING] **Injection / unsafe access**: SQL injection, unsafe ORM/raw query usage, unsafe string concatenation into queries or commands
- [BLOCKING] **XSS** (where applicable): user-controlled output rendered or embedded without appropriate handling
- [BLOCKING] **Abuse**: paths that enable privilege escalation or misuse
- [BLOCKING] **Validation**: user or external input not validated on the trust boundary where it must be
- [BLOCKING] **Data handling**: sensitive reads/writes that skip intended layers; missing rate limiting where APIs are exposed; improper session handling; unencrypted storage of sensitive data where required
- [SUGGESTION] **Hardening**: extra defense-in-depth (headers, CSP, stricter validation) when not strictly required by policy

## Correctness

- [BLOCKING] **Intent**: change does not match the ticket or stated goal (if provided)
- [BLOCKING] **Logic**: clear bugs, wrong branches, incorrect assumptions that affect behaviour
- [BLOCKING] **Regressions**: existing behaviour broken where it should be preserved—only when no failing test already covers it
- [BLOCKING] **Async and errors**: async work that is never awaited or started (e.g. a missing `await` in JS/TS/Python), errors that are dropped or left unchecked (e.g. an ignored Go `err`), broken error paths, or swallowed failures that hide real errors
- [SUGGESTION] **Edge cases**: additional handling for empty or missing values (in whatever form the language uses, e.g. `null`, `None`, `nil`, zero values, empty collections), ordering, or integration quirks when behaviour is not clearly wrong
- [SUGGESTION] **Clarity**: small refactors that reduce ambiguity without changing behaviour

## Architecture

- [BLOCKING] **Layering**: business or domain logic placed in the wrong layer for this project (e.g. heavy logic in thin HTTP handlers when the codebase keeps it elsewhere)
- [BLOCKING] **Data access**: persistence scattered or bypassing the layer the project expects
- [SUGGESTION] **Consistency**: align names, folder layout, or module boundaries with surrounding code
- [SUGGESTION] **Refactors**: splitting large units or extracting helpers when behaviour is already correct
- [SUGGESTION] **Transactions**: multi-step writes that must succeed or fail together but are not wrapped in a database transaction (or equivalent) where the project would normally use one

## Conventions

Convention findings come only from the sources loaded in **Step 1** of `SKILL.md`. Don’t invent conventions: every MUST or SHOULD finding cites the source and rule it maps to.

- [BLOCKING] **MUST rules**: the change breaks a **MUST** rule—or, in a source that does not label rules MUST/SHOULD, a rule phrased as must, never, always, or do not
- [BLOCKING] **Documented bans**: new use of a library, API, or pattern the repo explicitly forbids—unless the ticket allows it and mitigations are documented
- [BLOCKING] **Masking root causes**: “fix-ups” in the wrong layer that hide upstream data or process problems instead of addressing them
- [SUGGESTION] **SHOULD rules**: the change departs from a **SHOULD** rule without a stated reason
- [SUGGESTION] **Deprecated patterns**: use of deprecated APIs or patterns in the changed code
- [SUGGESTION] **Stack idioms**: closer alignment with framework best practices when the current code works

## API & contracts

- [BLOCKING] **Response DTOs / serialization**: new or changed handlers returning raw persistence models or untyped shapes where the project uses response DTOs or serializers—follow existing patterns for public API outputs
- [BLOCKING] **Breaking API changes**: **removing** or **renaming** fields, changing a field’s **type** or **nested structure**, or otherwise breaking consumers’ expectations for JSON (or documented) responses—unless the ticket documents the break and an agreed migration path (versioning, compatibility layer, dual-read/write, or consumer coordination) is reflected in the change

## Error handling

- [BLOCKING] **Leaky errors**: user-facing messages expose stack traces, secrets, or internal implementation details
- [BLOCKING] **Missing handling**: async paths where failures are ignored and should propagate or be handled
- [SUGGESTION] **Layer boundaries**: errors are surfaced or mapped at the layer the project expects (e.g. domain vs HTTP) when the change crosses those boundaries but behaviour is not clearly wrong

## Logging

- [SUGGESTION] **Logging context**: extra structured fields or clearer messages for operators
- [SUGGESTION] **Severity levels**: tuning `info` / `warn` / `error` when nothing is wrong but logs could be clearer

## Reliability

- [SUGGESTION] **Retries**: retries on external I/O or message handling use bounded backoff and limits; avoid unbounded hot loops or thundering herds where the stack supports safer patterns
- [SUGGESTION] **Idempotency**: work that can run twice (retries, at-least-once delivery) is safe to repeat—use idempotency keys, deduplication, or natural idempotency; call out when partial failure could leave inconsistent state without a recovery path
- [SUGGESTION] **Partial failure**: multi-step external or cross-service flows document or handle what happens if a step fails mid-way (compensating action, retry from safe point, or explicit error surface)

## Performance

- [BLOCKING] **Serious performance defects**: unbounded queries, obvious **N+1** on hot paths, or work in tight loops that will clearly hurt production at expected load
- [BLOCKING] **Unindexed foreign keys**: new or changed schema introduces foreign-key (or join) columns without an index where the ORM or DB expects one for joins and cascades on non-trivial tables
- [BLOCKING] **Dangerous migrations**: migrations that drop columns or tables, truncate data, or otherwise risk **data loss** or destructive changes in production without a ticket-approved plan (backfill, rollout order, or explicit acceptance of risk)
- [SUGGESTION] **Micro-optimizations**: minor cost savings when not material
- [SUGGESTION] **Unindexed filter/sort columns**: frequent or large-table queries filter, join, or order by columns that have no supporting index—consider adding one if load warrants it

## Maintainability

- [SUGGESTION] **Oversized or overly complex functions**: new or heavily changed functions/methods that are **too long**, **deeply nested**, or combine **too many responsibilities**—break them into smaller units with clear names (helpers, private methods, or services) unless the ticket explicitly accepts the complexity
- [SUGGESTION] **Naming**: descriptive **variable** and **function** names that reflect intent and domain language (avoid vague names like `data`, `handle`, `process` when a precise term exists)
- [SUGGESTION] **Readability**: comments (where the project uses them), structure, and file organization—without duplicating linter rules
- [SUGGESTION] **Dead code**: removal when safe
- [SUGGESTION] **Duplicate logic**: same or near-identical behaviour in multiple places—extract or consolidate when it would reduce drift and bugs

## Tests

- [SUGGESTION] **New behaviour**: add or extend tests where the project normally would
- [SUGGESTION] **Beyond happy path**: edge cases and failure paths when risk warrants coverage
