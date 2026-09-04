import CapsStackLocalization
import Foundation

enum SummaryMarkdown {
    /// Returns a useful Markdown representation for every history state.
    ///
    /// Pending and empty entries do not have a `SummaryDocument`, but they still contain
    /// useful diagnostics (the selected sources, collection issues, memo, and an error). Keeping
    /// those entries exportable makes the History actions honest instead of silently doing
    /// nothing when the selected row has not produced a summary yet.
    static func document(for entry: HistoryEntry, locale: Locale = .current) -> String {
        guard let summary = entry.summary else {
            return statusDocument(for: entry, locale: locale)
        }
        return document(summary, entry: entry, locale: locale)
    }

    static func document(_ summary: SummaryDocument, entry: HistoryEntry, locale: Locale = .current) -> String {
        var lines: [String] = []
        let start = entry.interval.start
        lines.append(CapsStackText.format(
            .capsStackSummary,
            start.formatted(.dateTime.year().month().day().hour().minute()),
            locale: locale
        ))
        lines.append("")
        lines.append("- **\(CapsStackText.resolve(.durationLabel, locale: locale))**: \(DurationFormatter.string(from: entry.interval.duration))")
        lines.append("- **\(CapsStackText.resolve(.sessionsLabel, locale: locale))**: \(entry.sessionCount)")
        if let provider = entry.provider {
            let fallback = entry.fallbackUsed ? " \(CapsStackText.resolve(.fallbackSuffix, locale: locale))" : ""
            lines.append("- **\(CapsStackText.resolve(.summarizerCLIMetadata, locale: locale))**: \(provider.displayName)\(fallback)")
        }
        if let memo = entry.quickMemo, !memo.isEmpty {
            lines.append("- **\(CapsStackText.resolve(.awayMemoMetadata, locale: locale))**: \(memo)")
        }
        lines.append("")
        lines.append(summary.overview)
        appendSection(CapsStackText.resolve(.progress, locale: locale), items: summary.progress, to: &lines)
        appendSection(CapsStackText.resolve(.currentState, locale: locale), items: summary.currentState, to: &lines)
        appendSection(CapsStackText.resolve(.decisions, locale: locale), items: summary.decisions, to: &lines)
        appendSection(CapsStackText.resolve(.blockers, locale: locale), items: summary.blockers, to: &lines)
        appendSection(CapsStackText.resolve(.nextSteps, locale: locale), items: summary.nextSteps, to: &lines)

        if !summary.projects.isEmpty {
            lines.append("")
            lines.append("## \(CapsStackText.resolve(.byProjectMetadata, locale: locale))")
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
            lines.append("## \(CapsStackText.resolve(.bySessionMetadata, locale: locale))")
            for session in summary.sessions {
                lines.append("")
                lines.append("**\(session.source) — \(session.sessionID)**")
                lines.append(session.summary)
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func statusDocument(for entry: HistoryEntry, locale: Locale) -> String {
        let start = entry.interval.start
        var lines = [
            CapsStackText.format(
                .capsStackHistory,
                start.formatted(.dateTime.year().month().day().hour().minute()),
                locale: locale
            ),
            "",
            "- **\(CapsStackText.resolve(.durationLabel, locale: locale))**: \(DurationFormatter.string(from: entry.interval.duration))",
            "- **\(CapsStackText.resolve(.sessionsLabel, locale: locale))**: \(entry.sessionCount)",
            "- **\(CapsStackText.resolve(.statusLabel, locale: locale))**: \(statusTitle(for: entry.status, locale: locale))"
        ]

        if !entry.sources.isEmpty {
            lines.append("- **\(CapsStackText.resolve(.sourcesMetadata, locale: locale))**: \(entry.sources.map(\.collectionDisplayName).joined(separator: ", "))")
        }
        if let memo = entry.quickMemo, !memo.isEmpty {
            lines.append("- **\(CapsStackText.resolve(.awayMemoMetadata, locale: locale))**: \(memo)")
        }
        if let error = entry.errorMessage, !error.isEmpty {
            lines.append("")
            lines.append("## \(CapsStackText.resolve(.error, locale: locale))")
            lines.append(error)
        }
        if !entry.collectionIssues.isEmpty {
            lines.append("")
            lines.append("## \(CapsStackText.resolve(.collectionNotesMetadata, locale: locale))")
            lines.append(contentsOf: entry.collectionIssues.map { "- \($0.provider.collectionDisplayName): \($0.message)" })
        }
        return lines.joined(separator: "\n")
    }

    private static func statusTitle(for status: HistoryStatus, locale: Locale) -> String {
        switch status {
        case .completed: CapsStackText.resolve(.completed, locale: locale)
        case .pending: CapsStackText.resolve(.pendingSummary, locale: locale)
        case .empty: CapsStackText.resolve(.noSessions, locale: locale)
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
