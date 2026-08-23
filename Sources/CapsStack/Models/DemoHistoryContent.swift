import Foundation

enum DemoHistoryContent {
    static func entries() -> [HistoryEntry] {
        [
            entry(
                dayOffset: 0,
                start: .init(hour: 19, minute: 41, second: 18),
                duration: 8_322,
                sessionCount: 4,
                summary: SummaryDocument(
                    overview: "退席中の作業を、完了した実装・確定した仕様・次に動く項目に整理しました。",
                    progress: [
                        "ユーザー認証フローにパスキー認証を追加し、バックエンド連携を完了",
                        "チーム招待APIの権限チェックとエラーハンドリングを実装",
                        "ダッシュボードのフィルタ保存機能を追加（ローカル永続化）",
                        "E2Eテストを3件追加し、CIでの実行を安定化"
                    ],
                    currentState: [],
                    decisions: [
                        "パスキーは WebAuthn（プラットフォーム認証優先）で進める",
                        "招待リンクの有効期限は7日間とする",
                        "ダッシュボードのデフォルト期間は「過去7日間」に統一",
                        "エラーメッセージはユーザー向けに簡潔化し、詳細はログに出力"
                    ],
                    blockers: [],
                    nextSteps: [
                        "招待メールのテンプレート文面をレビュー",
                        "パスキーのリカバリーフローを設計・実装",
                        "ダッシュボードのエクスポート機能を追加",
                        "E2Eテストのカバレッジを確認し、不足ケースを追加"
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
                    overview: "履歴画面の再設計に向けた構成案を整理しました。",
                    progress: ["日別サマリーの情報階層を整理", "復帰ブリーフの表示順を固定"],
                    currentState: [],
                    decisions: ["主要セクションは進捗・決定・次の一手の3つに絞る"],
                    blockers: [],
                    nextSteps: ["設定画面のサイドバー構成を反映する"],
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
                    overview: "通知まわりの挙動を確認し、権限要求のタイミングを整理しました。",
                    progress: ["初回起動時の権限要求条件を明確化"],
                    currentState: [],
                    decisions: ["許可が拒否された場合は設定から再度要求できる形にする"],
                    blockers: [],
                    nextSteps: ["失敗通知の文面を見直す"],
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
                    overview: "収集元ごとのログ読み取り境界を確認しました。",
                    progress: ["OpenCodeの公式CLI経由の収集経路を検証"],
                    currentState: [],
                    decisions: ["DB-backed storageは直接解釈しない"],
                    blockers: [],
                    nextSteps: ["Piのログ形式テストを追加する"],
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
                    overview: "認証フローの要件を整理し、実装順を決めました。",
                    progress: ["パスキー認証のユーザーフローを整理"],
                    currentState: [],
                    decisions: ["まずプラットフォーム認証を優先する"],
                    blockers: [],
                    nextSteps: ["WebAuthnの詳細設計を行う"],
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
                    overview: "招待APIの権限まわりを実装しました。",
                    progress: ["招待APIの権限チェックを追加", "エラーレスポンスを統一"],
                    currentState: [],
                    decisions: ["期限切れ招待は404に統一"],
                    blockers: [],
                    nextSteps: ["権限チェックのE2Eテストを追加"],
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
                    overview: "短い退席中に軽微な修正だけを行いました。",
                    progress: ["タイマー表示の桁揃えを修正"],
                    currentState: [],
                    decisions: [],
                    blockers: [],
                    nextSteps: ["空状態のコピーを確認する"],
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
