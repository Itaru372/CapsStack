# CapsStack Selected Design QA

final result: passed

## Scope

- Reference visual: the approved dark return-brief composition selected from the 4–6 direction set.
- Implementation target: native macOS history window, settings window, application menu bar, and menu-bar popover.
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
- Menu order is `CapsStack`, `履歴`, `設定`, `編集`, `表示`, `ウインドウ`, `ヘルプ`.
- The menu-bar popover follows the approved native-menu composition: status dot plus away-state title with a right-aligned live timer, the 今すぐ復帰 / 退席前メモ... group, the 履歴を開く ⌘O / 設定... ⌘, group, and CapsStackを終了 ⌘Q.

## Demo data

The demo history is opt-in and memory-only. It is enabled for this local verification run by launching with `CAPSSTACK_DEMO_DATA=1` (which passes `--capsstack-demo-data`). Normal launches read only the real history store; demo deletion/clearing never writes to that store. A regression test proves the real store remains empty during demo deletion.

## Verification

- `swift build` passed.
- `swift test` passed: 23 tests, 0 failures.
- `CAPSSTACK_DEMO_DATA=1 ./script/build_and_run.sh --verify` built and launched the packaged app successfully.
- Runtime capture showed the demo badge, August 18–23 cards, selected 8/23 session (`02:18:42`, four sessions), and the three compact brief sections.
- A temporary AppKit diagnostic confirmed the final native menu order; it was removed before handoff.
