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

    static func markdown(_ entry: CLIHistoryEntry) -> String {
        var lines = [
            "# CapsStack Summary — \(date(entry.interval.start))",
            "",
            "- **Duration**: \(duration(entry.interval.duration))",
            "- **Sessions**: \(entry.sessionCount)"
        ]
        if let provider = entry.provider {
            lines.append("- **Summarizer CLI**: \(provider.displayName)\(entry.fallbackUsed ? " (fallback)" : "")")
        }
        if !entry.sources.isEmpty {
            lines.append("- **Sources**: \(entry.sources.map(\.collectionDisplayName).joined(separator: ", "))")
        }
        if let memo = normalized(entry.quickMemo) {
            lines.append("- **Away memo**: \(memo)")
        }
        guard let summary = entry.summary else {
            lines.append("")
            lines.append("**Status**: \(entry.status.rawValue)")
            if let error = normalized(entry.errorMessage) {
                lines.append("")
                lines.append("## Error")
                lines.append(error)
            }
            return lines.joined(separator: "\n")
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

    static func human(_ entry: CLIHistoryEntry) -> String {
        var lines = [
            "\(entry.id.uuidString)  \(date(entry.interval.start))  [\(entry.status.rawValue)]",
            "Duration: \(duration(entry.interval.duration)) / Sessions: \(entry.sessionCount)"
        ]
        if let overview = normalized(entry.summary?.overview) { lines.append(overview) }
        if let memo = normalized(entry.quickMemo) { lines.append("Away memo: \(memo)") }
        if let error = normalized(entry.errorMessage) { lines.append("Error: \(error)") }
        return lines.joined(separator: "\n")
    }

    static func listLine(_ entry: CLIHistoryEntry) -> String {
        let overview = normalized(entry.summary?.overview) ?? normalized(entry.errorMessage) ?? "No summary"
        return "\(entry.id.uuidString)  \(date(entry.interval.start))  [\(entry.status.rawValue)]  \(overview)"
    }

    private static func date(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
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
