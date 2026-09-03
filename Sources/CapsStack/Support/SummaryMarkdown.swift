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
        lines.append("# CapsStack Summary — \(start.formatted(.dateTime.year().month().day().hour().minute()))")
        lines.append("")
        lines.append("- **Duration**: \(DurationFormatter.string(from: entry.interval.duration))")
        lines.append("- **Sessions**: \(entry.sessionCount)")
        if let provider = entry.provider {
            lines.append("- **Summarizer CLI**: \(provider.displayName)\(entry.fallbackUsed ? " (fallback)" : "")")
        }
        if let memo = entry.quickMemo, !memo.isEmpty {
            lines.append("- **Away memo**: \(memo)")
        }
        lines.append("")
        lines.append(summary.overview)
        appendSection("Progress", items: summary.progress, to: &lines)
        appendSection("Current state", items: summary.currentState, to: &lines)
        appendSection("Decisions", items: summary.decisions, to: &lines)
        appendSection("Blockers", items: summary.blockers, to: &lines)
        appendSection("Next steps", items: summary.nextSteps, to: &lines)

        if !summary.projects.isEmpty {
            lines.append("")
            lines.append("## By project")
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
            lines.append("## By session")
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
            "# CapsStack History — \(start.formatted(.dateTime.year().month().day().hour().minute()))",
            "",
            "- **Duration**: \(DurationFormatter.string(from: entry.interval.duration))",
            "- **Sessions**: \(entry.sessionCount)",
            "- **Status**: \(statusTitle(for: entry.status))"
        ]

        if !entry.sources.isEmpty {
            lines.append("- **Sources**: \(entry.sources.map(\.collectionDisplayName).joined(separator: ", "))")
        }
        if let memo = entry.quickMemo, !memo.isEmpty {
            lines.append("- **Away memo**: \(memo)")
        }
        if let error = entry.errorMessage, !error.isEmpty {
            lines.append("")
            lines.append("## Error")
            lines.append(error)
        }
        if !entry.collectionIssues.isEmpty {
            lines.append("")
            lines.append("## Collection notes")
            lines.append(contentsOf: entry.collectionIssues.map { "- \($0.provider.collectionDisplayName): \($0.message)" })
        }
        return lines.joined(separator: "\n")
    }

    private static func statusTitle(for status: HistoryStatus) -> String {
        switch status {
        case .completed: "Completed"
        case .pending: "Pending summary"
        case .empty: "No sessions"
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
