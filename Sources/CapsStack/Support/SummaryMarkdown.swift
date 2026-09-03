import Foundation

enum SummaryMarkdown {
    /// Returns a useful Markdown representation for every history state.
    ///
    /// Pending and empty entries do not have a `SummaryDocument`, but they still contain
    /// useful diagnostics (the selected sources, collection issues, memo, and an error). Keeping
    /// those entries exportable makes the History actions honest instead of silently doing
    /// nothing when the selected row has not produced a summary yet.
    static func document(for entry: HistoryEntry) -> String {
        guard let summary = entry.summary else {
            return statusDocument(for: entry)
        }
        return document(summary, entry: entry)
    }

    static func document(_ summary: SummaryDocument, entry: HistoryEntry) -> String {
        var lines: [String] = []
        let start = entry.interval.start
        lines.append("# CapsStack 要約 — \(start.formatted(.dateTime.year().month().day().hour().minute()))")
        lines.append("")
        lines.append("- **所要時間**: \(DurationFormatter.string(from: entry.interval.duration))")
        lines.append("- **セッション数**: \(entry.sessionCount)")
        if let provider = entry.provider {
            lines.append("- **要約CLI**: \(provider.displayName)\(entry.fallbackUsed ? "（フォールバック）" : "")")
        }
        if let memo = entry.quickMemo, !memo.isEmpty {
            lines.append("- **退席前メモ**: \(memo)")
        }
        lines.append("")
        lines.append(summary.overview)
        appendSection("進んだ内容", items: summary.progress, to: &lines)
        appendSection("現在の状態", items: summary.currentState, to: &lines)
        appendSection("重要な判断", items: summary.decisions, to: &lines)
        appendSection("問題・確認待ち", items: summary.blockers, to: &lines)
        appendSection("次の予定", items: summary.nextSteps, to: &lines)

        if !summary.projects.isEmpty {
            lines.append("")
            lines.append("## プロジェクト別")
            for project in summary.projects {
                lines.append("")
                lines.append("### \(project.name)")
                lines.append(project.summary)
                for session in project.sessions {
                    lines.append("")
                    lines.append("**\(session.source) — \(session.sessionID)**")
                    lines.append(session.summary)
                }
            }
        } else if !summary.sessions.isEmpty {
            lines.append("")
            lines.append("## セッション別")
            for session in summary.sessions {
                lines.append("")
                lines.append("**\(session.source) — \(session.sessionID)**")
                lines.append(session.summary)
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func statusDocument(for entry: HistoryEntry) -> String {
        let start = entry.interval.start
        var lines = [
            "# CapsStack 履歴 — \(start.formatted(.dateTime.year().month().day().hour().minute()))",
            "",
            "- **所要時間**: \(DurationFormatter.string(from: entry.interval.duration))",
            "- **セッション数**: \(entry.sessionCount)",
            "- **状態**: \(statusTitle(for: entry.status))"
        ]

        if !entry.sources.isEmpty {
            lines.append("- **収集元**: \(entry.sources.map(\.collectionDisplayName).joined(separator: ", "))")
        }
        if let memo = entry.quickMemo, !memo.isEmpty {
            lines.append("- **退席前メモ**: \(memo)")
        }
        if let error = entry.errorMessage, !error.isEmpty {
            lines.append("")
            lines.append("## エラー")
            lines.append(error)
        }
        if !entry.collectionIssues.isEmpty {
            lines.append("")
            lines.append("## 収集時の注意")
            lines.append(contentsOf: entry.collectionIssues.map { "- \($0.provider.collectionDisplayName): \($0.message)" })
        }
        return lines.joined(separator: "\n")
    }

    private static func statusTitle(for status: HistoryStatus) -> String {
        switch status {
        case .completed: "完了"
        case .pending: "要約待ち"
        case .empty: "対象セッションなし"
        }
    }

    private static func appendSection(
        _ title: String,
        items: [String],
        to lines: inout [String]
    ) {
        guard !items.isEmpty else { return }
        lines.append("")
        lines.append("## \(title)")
        for item in items {
            lines.append("- \(item)")
        }
    }
}
