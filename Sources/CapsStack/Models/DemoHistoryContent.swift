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
                    overview: "Organized the work completed while you were away into shipped changes, settled decisions, and next actions.",
                    progress: [
                        "Added passkey authentication to the user sign-in flow and completed the backend integration",
                        "Implemented permission checks and error handling for the team invitation API",
                        "Added locally persisted dashboard filter preferences",
                        "Added three E2E tests and stabilized their CI runs"
                    ],
                    currentState: [],
                    decisions: [
                        "Use WebAuthn for passkeys, preferring platform authenticators",
                        "Set invitation links to expire after seven days",
                        "Standardize the dashboard's default range to the last seven days",
                        "Keep user-facing errors concise and write details to the logs"
                    ],
                    blockers: [],
                    nextSteps: [
                        "Review the invitation email template",
                        "Design and implement passkey recovery",
                        "Add dashboard export",
                        "Review E2E coverage and add missing cases"
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
                    overview: "Outlined the structure for redesigning the History screen.",
                    progress: ["Restructured the information hierarchy for daily summaries", "Fixed the order of sections in the return brief"],
                    currentState: [],
                    decisions: ["Keep the main sections focused on progress, decisions, and next steps"],
                    blockers: [],
                    nextSteps: ["Apply the sidebar structure to the Settings screen"],
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
                    overview: "Verified notification behavior and clarified when permission should be requested.",
                    progress: ["Clarified the conditions for requesting permission on first launch"],
                    currentState: [],
                    decisions: ["If permission is denied, let the user request it again from Settings"],
                    blockers: [],
                    nextSteps: ["Review the wording of failure notifications"],
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
                    overview: "Verified the log-reading boundary for each collection source.",
                    progress: ["Validated the OpenCode collection path through its official CLI"],
                    currentState: [],
                    decisions: ["Do not parse DB-backed storage directly"],
                    blockers: [],
                    nextSteps: ["Add tests for the Pi log format"],
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
                    overview: "Clarified the authentication requirements and set the implementation order.",
                    progress: ["Mapped the passkey authentication user flow"],
                    currentState: [],
                    decisions: ["Prioritize platform authentication first"],
                    blockers: [],
                    nextSteps: ["Complete the WebAuthn detail design"],
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
                    overview: "Implemented authorization for the invitation API.",
                    progress: ["Added invitation API permission checks", "Standardized error responses"],
                    currentState: [],
                    decisions: ["Return 404 for all expired invitations"],
                    blockers: [],
                    nextSteps: ["Add E2E tests for permission checks"],
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
                    overview: "Made a small fix during a short away interval.",
                    progress: ["Fixed timer digit alignment"],
                    currentState: [],
                    decisions: [],
                    blockers: [],
                    nextSteps: ["Review the empty-state copy"],
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
