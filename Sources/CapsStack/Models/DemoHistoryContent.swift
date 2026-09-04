import Foundation

enum DemoHistoryContent {
    static func entries(locale: Locale = .current) -> [HistoryEntry] {
        let copy: (String, String) -> String = { english, japanese in
            locale.language.languageCode?.identifier == "ja" ? japanese : english
        }

        return [
            entry(
                dayOffset: 0,
                start: .init(hour: 19, minute: 41, second: 18),
                duration: 8_322,
                sessionCount: 4,
                summary: SummaryDocument(
                    overview: copy(
                        "Organized the work completed while you were away into shipped changes, settled decisions, and next actions.",
                        "退席中の作業を、完了した実装・確定した仕様・次に動く項目に整理しました。"
                    ),
                    progress: [
                        copy("Added passkey authentication to the user sign-in flow and completed the backend integration", "ユーザー認証フローにパスキー認証を追加し、バックエンド連携を完了"),
                        copy("Implemented permission checks and error handling for the team invitation API", "チーム招待APIの権限チェックとエラーハンドリングを実装"),
                        copy("Added locally persisted dashboard filter preferences", "ダッシュボードのフィルタ保存機能を追加（ローカル永続化）"),
                        copy("Added three E2E tests and stabilized their CI runs", "E2Eテストを3件追加し、CIでの実行を安定化")
                    ],
                    currentState: [],
                    decisions: [
                        copy("Use WebAuthn for passkeys, preferring platform authenticators", "パスキーは WebAuthn（プラットフォーム認証優先）で進める"),
                        copy("Set invitation links to expire after seven days", "招待リンクの有効期限は7日間とする"),
                        copy("Standardize the dashboard's default range to the last seven days", "ダッシュボードのデフォルト期間は「過去7日間」に統一"),
                        copy("Keep user-facing errors concise and write details to the logs", "エラーメッセージはユーザー向けに簡潔化し、詳細はログに出力")
                    ],
                    blockers: [],
                    nextSteps: [
                        copy("Review the invitation email template", "招待メールのテンプレート文面をレビュー"),
                        copy("Design and implement passkey recovery", "パスキーのリカバリーフローを設計・実装"),
                        copy("Add dashboard export", "ダッシュボードのエクスポート機能を追加"),
                        copy("Review E2E coverage and add missing cases", "E2Eテストのカバレッジを確認し、不足ケースを追加")
                    ],
                    sessions: []
                ),
                sources: [.codex, .claudeCode, .opencode, .pi]
            ),
            entry(
                dayOffset: -1,
                start: .init(hour: 10, minute: 4),
                duration: 3_600,
                sessionCount: 1,
                summary: SummaryDocument(
                    overview: copy("Outlined the structure for redesigning the History screen.", "履歴画面の再設計に向けた構成案を整理しました。"),
                    progress: [
                        copy("Restructured the information hierarchy for daily summaries", "日別サマリーの情報階層を整理"),
                        copy("Fixed the order of sections in the return brief", "復帰ブリーフの表示順を固定")
                    ],
                    currentState: [],
                    decisions: [copy("Keep the main sections focused on progress, decisions, and next steps", "主要セクションは進捗・決定・次の一手の3つに絞る")],
                    blockers: [],
                    nextSteps: [copy("Apply the sidebar structure to the Settings screen", "設定画面のサイドバー構成を反映する")],
                    sessions: []
                ),
                sources: [.codex]
            ),
            entry(
                dayOffset: -1,
                start: .init(hour: 15, minute: 30),
                duration: 3_900,
                sessionCount: 1,
                summary: SummaryDocument(
                    overview: copy("Verified notification behavior and clarified when permission should be requested.", "通知まわりの挙動を確認し、権限要求のタイミングを整理しました。"),
                    progress: [copy("Clarified the conditions for requesting permission on first launch", "初回起動時の権限要求条件を明確化")],
                    currentState: [],
                    decisions: [copy("If permission is denied, let the user request it again from Settings", "許可が拒否された場合は設定から再度要求できる形にする")],
                    blockers: [],
                    nextSteps: [copy("Review the wording of failure notifications", "失敗通知の文面を見直す")],
                    sessions: []
                ),
                sources: [.claudeCode]
            ),
            entry(
                dayOffset: -2,
                start: .init(hour: 18, minute: 22),
                duration: 4_500,
                sessionCount: 1,
                summary: SummaryDocument(
                    overview: copy("Verified the log-reading boundary for each collection source.", "収集元ごとのログ読み取り境界を確認しました。"),
                    progress: [copy("Validated the OpenCode collection path through its official CLI", "OpenCodeの公式CLI経由の収集経路を検証")],
                    currentState: [],
                    decisions: [copy("Do not parse DB-backed storage directly", "DB-backed storageは直接解釈しない")],
                    blockers: [],
                    nextSteps: [copy("Add tests for the Pi log format", "Piのログ形式テストを追加する")],
                    sessions: []
                ),
                sources: [.opencode]
            ),
            entry(
                dayOffset: -5,
                start: .init(hour: 21, minute: 10),
                duration: 2_820,
                sessionCount: 1,
                summary: SummaryDocument(
                    overview: copy("Clarified the authentication requirements and set the implementation order.", "認証フローの要件を整理し、実装順を決めました。"),
                    progress: [copy("Mapped the passkey authentication user flow", "パスキー認証のユーザーフローを整理")],
                    currentState: [],
                    decisions: [copy("Prioritize platform authentication first", "まずプラットフォーム認証を優先する")],
                    blockers: [],
                    nextSteps: [copy("Complete the WebAuthn detail design", "WebAuthnの詳細設計を行う")],
                    sessions: []
                ),
                sources: [.codex]
            ),
            entry(
                dayOffset: -4,
                start: .init(hour: 20, minute: 2),
                duration: 5_160,
                sessionCount: 2,
                summary: SummaryDocument(
                    overview: copy("Implemented authorization for the invitation API.", "招待APIの権限まわりを実装しました。"),
                    progress: [
                        copy("Added invitation API permission checks", "招待APIの権限チェックを追加"),
                        copy("Standardized error responses", "エラーレスポンスを統一")
                    ],
                    currentState: [],
                    decisions: [copy("Return 404 for all expired invitations", "期限切れ招待は404に統一")],
                    blockers: [],
                    nextSteps: [copy("Add E2E tests for permission checks", "権限チェックのE2Eテストを追加")],
                    sessions: []
                ),
                sources: [.claudeCode, .opencode]
            ),
            entry(
                dayOffset: -3,
                start: .init(hour: 11, minute: 8),
                duration: 2_280,
                sessionCount: 1,
                summary: SummaryDocument(
                    overview: copy("Made a small fix during a short away interval.", "短い退席中に軽微な修正だけを行いました。"),
                    progress: [copy("Fixed timer digit alignment", "タイマー表示の桁揃えを修正")],
                    currentState: [],
                    decisions: [],
                    blockers: [],
                    nextSteps: [copy("Review the empty-state copy", "空状態のコピーを確認する")],
                    sessions: []
                ),
                sources: [.pi]
            )
        ].sorted { $0.interval.end > $1.interval.end }
    }

    private static func entry(
        dayOffset: Int,
        start: Time,
        duration: TimeInterval,
        sessionCount: Int,
        summary: SummaryDocument,
        sources: [CLIKind]
    ) -> HistoryEntry {
        let calendar = Calendar.current
        let day = calendar.date(byAdding: .day, value: dayOffset, to: calendar.startOfDay(for: .now)) ?? .now
        let startDate = calendar.date(
            bySettingHour: start.hour,
            minute: start.minute,
            second: start.second,
            of: day
        ) ?? .now

        return HistoryEntry(
            interval: AwayInterval(start: startDate, end: startDate.addingTimeInterval(duration)),
            status: .completed,
            summary: summary,
            provider: sources.first ?? .codex,
            fallbackUsed: false,
            sessionCount: sessionCount,
            sources: sources,
            quickMemo: nil
        )
    }

    private struct Time {
        let hour: Int
        let minute: Int
        var second: Int = 0
    }
}
