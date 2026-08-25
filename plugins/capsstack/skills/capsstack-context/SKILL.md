---
name: capsstack-context
description: Save, inspect, or clear the local CapsStack pre-away memo and check CapsStack CLI integration health. Use when a user is stepping away, asks an AI agent to leave a handoff for CapsStack, wants current work captured for a return brief, needs to inspect the saved memo, or asks whether CapsStack and supported coding-agent CLIs are available.
---

# CapsStack Context

Use the plugin wrapper at `../../scripts/capsstack` from this skill directory. Resolve the path relative to this `SKILL.md`; do not assume the plugin is the current working directory.

## Check readiness

Run `../../scripts/capsstack status --json` before changing the memo. Treat a nonzero exit as an integration failure and report its stderr concisely. Do not claim the app is installed merely because another agent CLI is present.

## Save a handoff

1. Derive a concise memo from the current conversation and verified workspace state.
2. Include the objective, what changed, the exact current state, and the next action or blocker. Prefer four short lines or fewer.
3. Exclude credentials, tokens, private keys, raw session logs, and unnecessary personal data.
4. Send the memo through stdin to `../../scripts/capsstack memo set --stdin --json`. Do not interpolate untrusted memo text into a shell command.
5. Verify with `../../scripts/capsstack memo get --json` and report that CapsStack will include it in the next return brief.

Do not invent progress. If workspace facts matter, inspect them before composing the memo. A new memo replaces the previous one; mention that only when it affects the user.

## Inspect or clear

- Read: `../../scripts/capsstack memo get --json`
- Clear: `../../scripts/capsstack memo clear --json`

Clear only when the user asks, or after they explicitly confirm the saved context is no longer needed. An empty memo means no GUI-agent context will be added to a future summary.

Read [references/cli-contract.md](references/cli-contract.md) when diagnosing command resolution, exit codes, or JSON fields.
