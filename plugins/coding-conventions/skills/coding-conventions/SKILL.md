---
name: coding-conventions
description: "Coding conventions — lint and format config, comments, change scope, and simplicity. Use when writing, refactoring, or reviewing any code. Read before making edits."
license: MIT
---

# Coding conventions

Rules use **MUST** (never bypass) and **SHOULD** (deviate only with justification).

Also read the nearest `AGENTS.md` for repo- or package-specific rules not covered here.

## Linters and formatters

The repo's lint and format config owns mechanical style (braces, import style, quoting, ordering, and so on). This skill does not repeat it.

### MUST: Follow the repo's lint and format config when writing

Before the first edit to a kind of file, read the lint and format config that covers it — e.g. `eslint.config.*` or `.eslintrc*` and Prettier config for JS/TS, `[tool.ruff]` or `[tool.black]` in `pyproject.toml` for Python, `.golangci.yml` for Go, `.editorconfig` for any language — and write code that already follows it. When a config extends a preset and a specific rule matters, check the resolved config for that file (e.g. `eslint --print-config <file>`) rather than guessing.

### MUST: Check changed files before finishing

After editing, run the repo's check-only lint and format commands on the files you changed and fix what they report. Use the commands named in `AGENTS.md`/`CLAUDE.md`, otherwise the tools the repo configures (e.g. `eslint --quiet <files>`, `prettier --check <files>`, `ruff check <files>`, `gofmt -l <files>`). If the repo configures none, skip this step.

## Comments

Prefer self-documenting code (clean naming, small focused functions, clear structure) over comments. Reach for a comment only when the code cannot express the intent itself.

### MUST: Keep comments minimal

Make the code self-explanatory first; a comment is a fallback, not the default. When one is needed, it explains **why** — intent, trade-off, or constraint that is not obvious from the code — never **what** the code does.

### MUST: No comments that restate the code

If the comment repeats what the code already says, delete it.

### SHOULD: Prefer single-line comments

When a comment is genuinely needed, one line is usually enough. Use more lines only when every extra line is worth the extra reading — not to narrate or pad.

```typescript
// Bad — restates the code
// Increment the counter by one
counter += 1;

// Avoid — two lines where one would do
// We cache here because the upstream API is slow and
// the same key is requested many times per request.

// Good — non-obvious constraint
// Upstream rate-limits to 10 req/s; cache avoids duplicate calls within a handler.
```

## Change scope

### MUST: Minimize scope

Use the simplest correct diff. Do not add or change unrelated code.

### SHOULD: Avoid over-engineering

Do not add thin helpers, excessive abstraction, or error handling for edges that are impossible or extremely unlikely.

### MUST: No discriminator fields for transparent APIs

If a function is meant to look the same for every input (enrichment, not a gate), do not add flags such as `recognised`, `isKnown`, or `isPassthrough` so callers can branch. Callers use the returned value; they do not inspect how it was produced.

### SHOULD: Prefer domain vocabulary

Use the domain's own nouns. Do not coin parallel taxonomy (`family` when the domain says `carrier`). Names that sound exhaustive (`CARRIERS`) are wrong for open sets — prefer `RECOGNISED_*` / `KNOWN_*`.

### SHOULD: Use existing conventions

Read surrounding code before writing. Match naming, types, imports, and abstractions. Reuse and extend existing functions rather than reimplementing.

### SHOULD: Useful tests only

Add tests when requested or when they cover real behavior. Do not add tests that trivially assert the obvious.

## Module boundaries

### MUST: Keep consumer-specific adapters with the consumer

Logic that maps a shared domain value into one consumer's wire format lives in that consumer's module. Do not create a shared helper that knows about multiple consumers (e.g. one file that maps carriers for two different marketplace integrations). Each consumer owns its own adapter.
