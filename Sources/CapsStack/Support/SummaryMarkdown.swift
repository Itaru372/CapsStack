import Foundation

enum SummaryMarkdown {
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

        if !summary.sessions.isEmpty {
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
