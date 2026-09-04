import CapsStackLocalization
import Foundation

enum CLIOutputMode: Equatable {
    case human
    case json
    case markdown
}

enum CLIFormatting {
    static func json<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    static func markdown(_ entry: CLIHistoryEntry, locale: Locale = .current) -> String {
        var lines = [
            CapsStackText.format(.capsStackSummary, date(entry.interval.start, locale: locale), locale: locale),
            "",
            "- **\(CapsStackText.resolve(.durationLabel, locale: locale))**: \(duration(entry.interval.duration))",
            "- **\(CapsStackText.resolve(.sessionsLabel, locale: locale))**: \(entry.sessionCount)"
        ]
        if let provider = entry.provider {
            let fallback = entry.fallbackUsed ? " \(CapsStackText.resolve(.fallbackSuffix, locale: locale))" : ""
            lines.append("- **\(CapsStackText.resolve(.summarizerCLIMetadata, locale: locale))**: \(provider.displayName)\(fallback)")
        }
        if !entry.sources.isEmpty {
            lines.append("- **\(CapsStackText.resolve(.sourcesMetadata, locale: locale))**: \(entry.sources.map(\.collectionDisplayName).joined(separator: ", "))")
        }
        if let memo = normalized(entry.quickMemo) {
            lines.append("- **\(CapsStackText.resolve(.awayMemoMetadata, locale: locale))**: \(memo)")
        }
        guard let summary = entry.summary else {
            lines.append("")
            lines.append("**\(CapsStackText.resolve(.statusLabel, locale: locale))**: \(entry.status.rawValue)")
            if let error = normalized(entry.errorMessage) {
                lines.append("")
                lines.append("## \(CapsStackText.resolve(.error, locale: locale))")
                lines.append(error)
            }
            return lines.joined(separator: "\n")
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

    static func human(_ entry: CLIHistoryEntry, locale: Locale = .current) -> String {
        var lines = [
            "\(entry.id.uuidString)  \(date(entry.interval.start, locale: locale))  [\(entry.status.rawValue)]",
            CapsStackText.format(.duration, duration(entry.interval.duration), entry.sessionCount, locale: locale)
        ]
        if let overview = normalized(entry.summary?.overview) { lines.append(overview) }
        if let memo = normalized(entry.quickMemo) {
            lines.append("\(CapsStackText.resolve(.awayMemoMetadata, locale: locale)): \(memo)")
        }
        if let error = normalized(entry.errorMessage) {
            lines.append("\(CapsStackText.resolve(.error, locale: locale)): \(error)")
        }
        return lines.joined(separator: "\n")
    }

    static func listLine(_ entry: CLIHistoryEntry, locale: Locale = .current) -> String {
        let overview = normalized(entry.summary?.overview)
            ?? normalized(entry.errorMessage)
            ?? CapsStackText.resolve(.noSummary, locale: locale)
        return "\(entry.id.uuidString)  \(date(entry.interval.start, locale: locale))  [\(entry.status.rawValue)]  \(overview)"
    }

    private static func date(_ date: Date, locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy/MM/dd HH:mm"
        return formatter.string(from: date)
    }

    private static func duration(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded()))
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        let seconds = total % 60
        return hours > 0
            ? String(format: "%02d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%02d:%02d", minutes, seconds)
    }

    private static func normalized(_ text: String?) -> String? {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func appendSection(_ title: String, items: [String], to lines: inout [String]) {
        guard !items.isEmpty else { return }
        lines.append("")
        lines.append("## \(title)")
        lines.append(contentsOf: items.map { "- \($0)" })
    }
}
