# CLI contract for context handoff

## Resolution

The plugin wrapper resolves the executable in this order:

1. Executable path in `CAPSSTACK_CLI`
2. An existing local `capsstack-cli` build in the repository containing this plugin
3. `capsstack` on `PATH`
4. `/Applications/CapsStack.app/Contents/Helpers/capsstack`
5. `swift run capsstack-cli` in the repository containing this plugin

If none exists, it exits nonzero and prints installation guidance to stderr.

## Commands

```text
capsstack status --json
capsstack memo get --json
capsstack memo set --stdin --json
capsstack memo clear --json
```

JSON goes to stdout. Diagnostics go to stderr. A nonzero exit means the requested operation did not complete.

`status` reports the history location, whether history exists, its entry count, whether a memo is present, and detected supported coding-agent CLIs. It does not prove the CapsStack GUI process is currently running.

`memo set` updates the `quickMemo` preference in the `com.capsstack.CapsStack` persistent domain. Whitespace-only input clears it.
