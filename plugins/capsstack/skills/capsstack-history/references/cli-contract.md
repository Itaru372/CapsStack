# CLI contract for return briefs

## Commands

```text
capsstack status --json
capsstack history list --limit 10 --json
capsstack history latest --json
capsstack history latest --markdown
capsstack history show <UUID> --json
capsstack history show <UUID> --markdown
```

JSON goes to stdout. Diagnostics go to stderr. A nonzero exit means the requested operation did not complete.

History is read from `~/Library/Application Support/CapsStack/history.json`. Entries are newest first and use the same persisted schema as the macOS app.

## Entry states

- `completed`: A summary document is available. Report its sections and metadata.
- `pending`: Summarization failed but a retryable artifact may remain. Report the error; do not present it as completed work.
- `empty`: The interval completed without collected session content.

The `fallbackUsed` flag means a provider other than the selected primary generated the summary. `collectionIssues` describes skipped or unreadable source material and should be retained when assessing completeness.

## Output selection

Use JSON for reliable field-level analysis and Markdown for direct human presentation. `history list` is metadata-oriented; call `history show` before making detailed claims about a selected entry.
