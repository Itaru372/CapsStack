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
- Copy and Markdown export remain useful for pending or empty intervals by exporting their state,
  diagnostics, and memo; retry is visibly unavailable while CapsStack is disabled or another
  workflow is running.
- The large 復帰ブリーフ heading is followed by compact 進捗 / 決定 / 次の一手 sections.
- Supplemental current-state, blocker, memo, collection-issue, creation-time, model, fallback, and character-count data remain available without inventing per-section CLI timing that the summary model does not provide.
- Empty intervals now use a compact explanatory card instead of leaving a large ambiguous void. Collection diagnostics are collapsed by default with a visible issue count, so recovery information remains available without outranking the return brief.
- Day cards use a wider content measure, improving scanability of session counts and durations while preserving the horizontal timeline.

### Settings

- The fixed-width dark sidebar contains 収集元, 要約担当, 一般, 通知, ホットキー, データ管理, and 詳細設定.
- The search field filters categories and keeps the detail pane synchronized with the visible selection.
- Collector rows preserve independent toggles plus runtime log-directory/readability status.
- Kilo Code、Goose、Qwen Code、Continue、Gemini CLIのcollector rowsは、各公式サイトまたは公式GitHub組織から取得して同梱した正方形画像を表示し、画像を読めない場合はSF Symbolsへフォールバックする。
- Each collector card is a full-width toggle target, and provider tests show an in-progress state,
  prevent competing tests, expose a cancel action, and keep the result visible after completion.
- Summary assignment, automatic fallback, general feature/background/accessibility controls, notification authorization/system-settings handoff, built-in shortcuts, local-data management, executable overrides, model overrides, reasoning overrides, and provider tests remain functional.
- Anonymous telemetry is no longer a persistent settings toggle; consent is presented during initial setup.
- General settings can reopen setup so collector, summarizer, and telemetry consent choices remain revisable.
- The settings window enforces a practical minimum height, keeping the complete data-management page and other long pages reachable even when macOS restores a previously small window.

### Setup

- First launch presents a four-step setup wizard in the main window before history.
- Detected collectors are preselected and the summarizer can be chosen from installed CLIs. A summarizer is required, while memo-only use remains available when no collector history is detected.
- Anonymous telemetry is explicitly shown as opt-in and defaults to OFF; builds without a configured destination explain that no events are sent.
- The final section explains the Caps Lock ON/OFF workflow before entering history.
- Each step fits the default 1120×740 window without scrolling and uses Back/Next navigation instead of placing every setting on one page.
- Detected collector and summarizer choices use uniform-height rows so their control frames remain visually aligned.
- The selected summarizer uses a restrained signal wash and stroked outline instead of a heavy full-card accent fill.

### Native chrome

- CapsStack now runs as a regular app with its main history window, Dock presence, and native menu bar.
- The application uses SwiftUI/AppKit's stable native order: `CapsStack`, `ファイル`, `編集`, `表示`, `履歴`, `設定`, `ウインドウ`, `ヘルプ`. Custom reordering was removed because moving SwiftUI-owned top-level menus during scene changes can violate AppKit submenu ownership.
- The menu-bar extra uses SwiftUI's standard `.menu` style and system menu items instead of a custom fixed-width popover.
- The standard menu contains the current state, 退席を開始 / 今すぐ復帰, 退席前メモ..., 履歴を開く ⌘O, 設定... ⌘,, and CapsStackを終了 ⌘Q.
- 退席前メモ... opens a small dedicated editor because native menu items do not support an embedded text editor. It is also available from the 設定 menu and with ⇧⌘M.
- The memo editor now shares the history/settings dark surface, includes a useful empty prompt, and makes its on-device auto-save behavior visible.

## Demo data

The demo history is opt-in and memory-only. It is enabled for this local verification run by launching with `CAPSSTACK_DEMO_DATA=1` (which passes `--capsstack-demo-data`). Normal launches read only the real history store; demo deletion/clearing never writes to that store. A regression test proves the real store remains empty during demo deletion.

## Verification

- `swift build --product CapsStack -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors` passed.
- `swift test` passed: 88 tests, 0 failures. This includes controller end-to-end success/failure/empty-source/manual-away flows, corrupted history, bounded process I/O and timeout termination, summary fallback/chunk limits, UTF-8 limits, portable export naming, agent collector/provider safety boundaries, and view rendering.
- `CAPSSTACK_DEMO_DATA=1 ./script/build_and_run.sh --verify` built and launched the packaged app successfully.
- The development app bundle and the app staged for the isolated Release package passed deep code-signature verification. The unsigned test PKG contains the app, bundled `capsstack` helper, icon, resource bundle, and Info.plist; Developer ID signing/notarization requires external identities.
- Real isolated Codex execution and OpenCode session collection succeeded. OpenCode summary invocation reached the configured provider and reported its unavailable local endpoint rather than hanging or corrupting history.
- Runtime capture showed the demo badge, August 19–24 cards, selected 8/24 session (`02:18:42`, four sessions), and the three compact brief sections.
- Native interaction covered history selection and month navigation, export panel naming, all seven settings sections and search, CLI status/details, top-level menus, and quick-memo input/clear/dismiss. A native open/dismiss control run completed without AppKit menu errors.
