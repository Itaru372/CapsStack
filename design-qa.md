# CapsStack Selected Design QA

final result: passed

## Scope

- Reference visual: the approved dark return-brief composition selected from the 4–6 direction set.
- Implementation target: native macOS history window, settings window, application menu bar, standard menu-bar menu, and quick-memo window.
- Adjustment applied: the progress, decision, and next-step section headings and marks use compact hierarchy rather than oversized claims.

## Verified behavior

### History

- The dark history surface opens as a regular macOS window at launch.
- August date cards show per-day session counts, durations, activity bars, and selected state.
- The selected interval card shows start/end time, total duration, session count, copy action, export/retry/delete actions, and brief metadata.
- The large 復帰ブリーフ heading is followed by compact 進捗 / 決定 / 次の一手 sections.
- Supplemental current-state, blocker, memo, collection-issue, creation-time, model, fallback, and character-count data remain available without inventing per-section CLI timing that the summary model does not provide.

### Settings

- The fixed-width dark sidebar contains 収集元, 要約担当, 一般, 通知, ホットキー, データ管理, and 詳細設定.
- The search field filters categories and keeps the detail pane synchronized with the visible selection.
- Collector rows preserve independent toggles plus runtime log-directory/readability status.
- Summary assignment, automatic fallback, general feature/background/accessibility controls, notification authorization, built-in shortcuts, local-data management, executable overrides, model overrides, reasoning overrides, and provider tests remain functional.

### Native chrome

- CapsStack now runs as a regular app with its main history window, Dock presence, and native menu bar.
- The application uses SwiftUI/AppKit's stable native order: `CapsStack`, `ファイル`, `編集`, `表示`, `履歴`, `設定`, `ウインドウ`, `ヘルプ`. Custom reordering was removed because moving SwiftUI-owned top-level menus during scene changes can violate AppKit submenu ownership.
- The menu-bar extra uses SwiftUI's standard `.menu` style and system menu items instead of a custom fixed-width popover.
- The standard menu contains the current state, 退席を開始 / 今すぐ復帰, 退席前メモ..., 履歴を開く ⌘O, 設定... ⌘,, and CapsStackを終了 ⌘Q.
- 退席前メモ... opens a small dedicated editor because native menu items do not support an embedded text editor. It is also available from the 設定 menu and with ⇧⌘M.

## Demo data

The demo history is opt-in and memory-only. It is enabled for this local verification run by launching with `CAPSSTACK_DEMO_DATA=1` (which passes `--capsstack-demo-data`). Normal launches read only the real history store; demo deletion/clearing never writes to that store. A regression test proves the real store remains empty during demo deletion.

## Verification

- `swift build --product CapsStack -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors` passed.
- `swift test` passed: 57 tests, 0 failures. This includes controller end-to-end success/failure/empty-source/manual-away flows, corrupted history, bounded process I/O and timeout termination, summary fallback/chunk limits, UTF-8 limits, portable export naming, and view rendering.
- `CAPSSTACK_DEMO_DATA=1 ./script/build_and_run.sh --verify` built and launched the packaged app successfully.
- The development app bundle and the app staged for the isolated Release package passed deep code-signature verification. The unsigned test PKG contains the app, bundled `capsstack` helper, icon, resource bundle, and Info.plist; Developer ID signing/notarization requires external identities.
- Real isolated Codex execution and OpenCode session collection succeeded. OpenCode summary invocation reached the configured provider and reported its unavailable local endpoint rather than hanging or corrupting history.
- Runtime capture showed the demo badge, August 19–24 cards, selected 8/24 session (`02:18:42`, four sessions), and the three compact brief sections.
- Native interaction covered history selection and month navigation, export panel naming, all seven settings sections and search, CLI status/details, top-level menus, and quick-memo input/clear/dismiss. A native open/dismiss control run completed without AppKit menu errors.
