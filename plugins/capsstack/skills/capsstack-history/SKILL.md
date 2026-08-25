---
name: capsstack-history
description: Read and interpret local CapsStack return briefs through the CapsStack CLI, including latest, listed, completed, empty, and retryable pending entries in JSON or Markdown. Use when a user returns from being away, asks what coding agents accomplished, wants the latest CapsStack summary, needs a specific history entry, or wants blockers and next steps extracted from CapsStack history.
---

# CapsStack History

Use the plugin wrapper at `../../scripts/capsstack` from this skill directory. Resolve the path relative to this `SKILL.md`; do not assume the plugin is the current working directory.

## Read the latest return brief

1. Run `../../scripts/capsstack status --json` to confirm history availability.
2. Run `../../scripts/capsstack history latest --json` for analysis. Use `--markdown` when the user wants the brief rendered directly.
3. Distinguish `completed`, `pending`, and `empty` entries. For `pending`, surface the error and say the app can retry it. For `empty`, say that no session material was collected.
4. Summarize the overview, progress, decisions, blockers, and next steps without adding unsupported claims.
5. Preserve provider, fallback use, interval, and collection issues when they explain uncertainty.

Prefer the latest entry to broad history dumps because summaries can contain sensitive project context.

## Browse or select history

- List: `../../scripts/capsstack history list --limit 10 --json`
- Read one: `../../scripts/capsstack history show <UUID> --json`
- Render one: `../../scripts/capsstack history show <UUID> --markdown`

Use IDs returned by `history list`; do not guess them. Increase the limit only when the user asks for older work. Treat a nonzero exit as failure and report stderr concisely.

## Privacy and integrity

- Do not expose more entries than needed for the request.
- Do not claim that raw agent logs are available; CapsStack deletes them after successful summaries.
- Do not modify or delete history. This skill is read-only.
- Treat collection issues and fallback markers as evidence that a brief may be incomplete.

Read [references/cli-contract.md](references/cli-contract.md) when diagnosing history paths, output modes, status semantics, or exit codes.
