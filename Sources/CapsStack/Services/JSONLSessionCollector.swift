import Foundation

final class JSONLSessionCollector: SessionCollector {
    let provider: CLIKind
    private let rootDirectory: URL
    private let fileManager: FileManager
    private let maxFileBytes: Int
    private let maxLineBytes: Int
    private let maxFiles: Int

    init(
        provider: CLIKind,
        rootDirectory: URL,
        fileManager: FileManager = .default,
        maxFileBytes: Int = 4 * 1024 * 1024,
        maxLineBytes: Int = 512 * 1024,
        maxFiles: Int = 2_000
    ) {
        self.provider = provider
        self.rootDirectory = rootDirectory
        self.fileManager = fileManager
        self.maxFileBytes = max(64 * 1024, maxFileBytes)
        self.maxLineBytes = max(4 * 1024, maxLineBytes)
        self.maxFiles = max(1, maxFiles)
    }

    func collect(interval: AwayInterval) -> CollectionResult {
        guard fileManager.fileExists(atPath: rootDirectory.path) else {
            return CollectionResult(
                provider: provider,
                sessions: [],
                issues: [CollectionIssue(
                    provider: provider,
                    message: "ログディレクトリが見つかりません: \(rootDirectory.path)"
                )]
            )
        }
        guard let files = enumerateLogFiles() else {
            return CollectionResult(
                provider: provider,
                sessions: [],
                issues: [CollectionIssue(
                    provider: provider,
                    message: "ログディレクトリを読み取れません: \(rootDirectory.path)"
                )]
            )
        }

        // A session that was already running at `start` may have an old creation date, while
        // its modification date is updated as it appends. Keep a generous lower bound to avoid
        // traversing an indefinitely growing archive on every Caps Lock transition.
        let lowerBound = interval.start.addingTimeInterval(-max(86_400, interval.duration + 60))
        let upperBound = interval.end.addingTimeInterval(60)
        let candidates = files.filter { file in
            let modified = modificationDate(of: file) ?? interval.start
            return modified >= lowerBound && modified <= upperBound
        }

        var issues: [CollectionIssue] = []
        var filesToRead = candidates
        if filesToRead.count > maxFiles {
            filesToRead = Array(filesToRead.prefix(maxFiles))
            issues.append(CollectionIssue(
                provider: provider,
                message: "対象ログが多いため、最新の\(maxFiles)ファイルだけを読み取りました。"
            ))
        }

        var grouped: [String: MutableSession] = [:]
        for file in filesToRead {
            do {
                let read = try read(file: file)
                if read.wasTruncated {
                    issues.append(CollectionIssue(
                        provider: provider,
                        message: "巨大なログを末尾\(maxFileBytes / 1024 / 1024)MBに制限しました: \(file.lastPathComponent)"
                    ))
                }
                var invalidLines = 0
                var oversizedLines = 0
                for rawLine in read.data.split(separator: 10, omittingEmptySubsequences: true) {
                    if rawLine.count > maxLineBytes {
                        oversizedLines += 1
                        continue
                    }
                    let line = Data(rawLine)
                    guard let record = parse(line: line, fallbackDate: read.modificationDate, interval: interval) else {
                        // A valid JSON record outside the interval is not an error; only malformed
                        // JSON increments the count.
                        if (try? JSONSerialization.jsonObject(with: line, options: [])) == nil {
                            invalidLines += 1
                        }
                        continue
                    }

                    let sessionID = record.sessionID ?? file.deletingPathExtension().lastPathComponent
                    var session = grouped[sessionID] ?? MutableSession(
                        id: sessionID,
                        workingDirectory: record.workingDirectory,
                        wasTruncated: false
                    )
                    session.events.append(CollectedEvent(
                        timestamp: record.timestamp,
                        kind: record.kind,
                        content: record.content
                    ))
                    if session.workingDirectory == nil {
                        session.workingDirectory = record.workingDirectory
                    }
                    session.wasTruncated = session.wasTruncated || read.wasTruncated
                    grouped[sessionID] = session
                }
                if invalidLines > 0 {
                    issues.append(CollectionIssue(
                        provider: provider,
                        message: "\(file.lastPathComponent) の不正なJSONLを\(invalidLines)行スキップしました。"
                    ))
                }
                if oversizedLines > 0 {
                    issues.append(CollectionIssue(
                        provider: provider,
                        message: "\(file.lastPathComponent) の巨大な行を\(oversizedLines)行スキップしました。"
                    ))
                }
            } catch {
                issues.append(CollectionIssue(
                    provider: provider,
                    message: "ログを読み取れませんでした (\(file.lastPathComponent)): \(error.localizedDescription)"
                ))
            }
        }

        let artifacts = grouped.values.map { (mutable: MutableSession) -> CollectedSessionArtifact in
            var mutable = mutable
            mutable.events.sort { $0.timestamp < $1.timestamp }
            return CollectedSessionArtifact(
                id: "\(provider.rawValue):\(mutable.id)",
                provider: provider,
                workingDirectory: mutable.workingDirectory,
                events: mutable.events,
                wasTruncated: mutable.wasTruncated
            )
        }.filter { !$0.events.isEmpty }
            .sorted { ($0.firstEventAt ?? .distantPast) < ($1.firstEventAt ?? .distantPast) }

        return CollectionResult(provider: provider, sessions: artifacts, issues: issues)
    }

    private func enumerateLogFiles() -> [URL]? {
        guard let enumerator = fileManager.enumerator(
            at: rootDirectory,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        var result: [URL] = []
        for case let url as URL in enumerator {
            guard url.pathExtension.lowercased() == "jsonl" || url.pathExtension.lowercased() == "json" else {
                continue
            }
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
                continue
            }
            result.append(url)
        }
        return result.sorted {
            (modificationDate(of: $0) ?? .distantPast) > (modificationDate(of: $1) ?? .distantPast)
        }
    }

    private func modificationDate(of file: URL) -> Date? {
        try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    private func read(file: URL) throws -> ReadFile {
        let values = try file.resourceValues(forKeys: [.contentModificationDateKey])
        let modificationDate = values.contentModificationDate ?? Date()
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }

        // Re-read the live size from the open descriptor and request at most one byte beyond the
        // limit. A log can grow after resource values are fetched; `readToEnd()` would otherwise
        // allocate the newly appended tail without a bound.
        let liveSize = try handle.seekToEnd()
        let startOffset = liveSize > UInt64(maxFileBytes)
            ? liveSize - UInt64(maxFileBytes)
            : 0
        try handle.seek(toOffset: startOffset)
        let data = try handle.read(upToCount: maxFileBytes + 1) ?? Data()
        let wasTruncated = startOffset > 0 || data.count > maxFileBytes
        return ReadFile(
            data: Data(data.prefix(maxFileBytes)),
            modificationDate: modificationDate,
            wasTruncated: wasTruncated
        )
    }

    private func parse(line: Data, fallbackDate: Date, interval: AwayInterval) -> ParsedRecord? {
        guard let object = try? JSONSerialization.jsonObject(with: line, options: []),
              let dictionary = object as? [String: Any] else {
            return nil
        }

        let timestamp = dateValue(Self.findValue(in: dictionary, named: Self.timestampKeys)) ?? fallbackDate
        guard timestamp >= interval.start && timestamp <= interval.end else { return nil }

        let kind = stringValue(Self.findValue(in: dictionary, named: Self.kindKeys)) ?? "event"
        let sessionID = stringValue(Self.findValue(in: dictionary, named: Self.sessionKeys))
        let workingDirectory = stringValue(Self.findValue(in: dictionary, named: Self.workingDirectoryKeys))
        let content = Self.contentValue(in: dictionary) ?? String(data: line, encoding: .utf8) ?? ""
        return ParsedRecord(
            timestamp: timestamp,
            kind: kind,
            content: Self.truncatedUTF8(content, limit: 32_768),
            sessionID: sessionID,
            workingDirectory: workingDirectory
        )
    }

    private static func truncatedUTF8(_ value: String, limit: Int) -> String {
        let data = Data(value.utf8)
        guard data.count > limit else { return value }
        var end = limit
        while end > 0 {
            if let result = String(data: data.prefix(end), encoding: .utf8) { return result }
            end -= 1
        }
        return ""
    }

    private func stringValue(_ value: Any?) -> String? {
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }

    private func dateValue(_ value: Any?) -> Date? {
        if let number = value as? NSNumber {
            let raw = number.doubleValue
            return Date(timeIntervalSince1970: raw > 10_000_000_000 ? raw / 1_000 : raw)
        }
        guard let string = value as? String else { return nil }
        if let number = Double(string) {
            return Date(timeIntervalSince1970: number > 10_000_000_000 ? number / 1_000 : number)
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }

    private static func findValue(in dictionary: [String: Any], named names: Set<String>) -> Any? {
        for (key, value) in dictionary where names.contains(key.lowercased()) {
            return value
        }
        for value in dictionary.values {
            if let child = value as? [String: Any], let found = findValue(in: child, named: names) {
                return found
            }
        }
        return nil
    }

    private static func contentValue(in dictionary: [String: Any]) -> String? {
        let keys = ["text", "content", "output", "summary", "message"]
        for key in keys {
            if let value = findValue(in: dictionary, named: [key]) {
                if let string = value as? String, !string.isEmpty { return string }
                if let array = value as? [Any] {
                    let strings = array.compactMap { item -> String? in
                        if let text = item as? String { return text }
                        if let child = item as? [String: Any] {
                            return (child["text"] as? String) ?? (child["content"] as? String)
                        }
                        return nil
                    }
                    if !strings.isEmpty { return strings.joined(separator: "\n") }
                }
                if let child = value as? [String: Any],
                   let data = try? JSONSerialization.data(withJSONObject: child, options: [.sortedKeys]),
                   let string = String(data: data, encoding: .utf8) {
                    return string
                }
            }
        }
        return nil
    }

    private static let timestampKeys: Set<String> = [
        "timestamp", "created_at", "createdat", "time", "ts", "event_time", "eventtime"
    ]
    private static let kindKeys: Set<String> = ["type", "event", "role", "kind", "subtype"]
    private static let sessionKeys: Set<String> = [
        "session_id", "sessionid", "conversation_id", "conversationid", "thread_id", "threadid"
    ]
    private static let workingDirectoryKeys: Set<String> = [
        "cwd", "working_directory", "workingdirectory", "project_dir", "projectdir"
    ]
}

private struct ReadFile {
    let data: Data
    let modificationDate: Date
    let wasTruncated: Bool
}

private struct ParsedRecord {
    let timestamp: Date
    let kind: String
    let content: String
    let sessionID: String?
    let workingDirectory: String?
}

private struct MutableSession {
    let id: String
    var workingDirectory: String?
    var events: [CollectedEvent] = []
    var wasTruncated: Bool
}
