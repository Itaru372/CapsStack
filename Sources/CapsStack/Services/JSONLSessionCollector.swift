import Foundation

final class JSONLSessionCollector: SessionCollector {
    let provider: CLIKind
    private let rootDirectory: URL
    private let fileManager: FileManager
    private let maxFileBytes: Int
    private let maxLineBytes: Int
    private let maxFiles: Int
    private let allowedFileNames: Set<String>?
    private let allowedTopLevelDirectories: Set<String>?

    /// `allowedTopLevelDirectories` prevents a provider root that also contains configuration
    /// state from being treated as an archive of transcripts.
    init(
        provider: CLIKind,
        rootDirectory: URL,
        fileManager: FileManager = .default,
        maxFileBytes: Int = 4 * 1024 * 1024,
        maxLineBytes: Int = 512 * 1024,
        maxFiles: Int = 2_000,
        allowedFileNames: Set<String>? = nil,
        allowedTopLevelDirectories: Set<String>? = nil
    ) {
        self.provider = provider
        self.rootDirectory = rootDirectory
        self.fileManager = fileManager
        self.maxFileBytes = max(64 * 1024, maxFileBytes)
        self.maxLineBytes = max(4 * 1024, maxLineBytes)
        self.maxFiles = max(1, maxFiles)
        self.allowedFileNames = allowedFileNames
        self.allowedTopLevelDirectories = allowedTopLevelDirectories
    }

    func collect(interval: AwayInterval) -> CollectionResult {
        guard fileManager.fileExists(atPath: rootDirectory.path) else {
            return CollectionResult(
                provider: provider,
                sessions: [],
                issues: [CollectionIssue(
                    provider: provider,
                    message: "Log directory not found: \(rootDirectory.path)"
                )]
            )
        }
        guard let files = enumerateLogFiles() else {
            return CollectionResult(
                provider: provider,
                sessions: [],
                issues: [CollectionIssue(
                    provider: provider,
                    message: "Could not read log directory: \(rootDirectory.path)"
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
                message: "There are too many log files to inspect; only the latest \(maxFiles) were read."
            ))
        }

        var grouped: [String: MutableSession] = [:]
        for file in filesToRead {
            do {
                let read = try read(file: file)
                var groupingKeysBySessionID: [String: Set<String>] = [:]
                if read.wasTruncated {
                    issues.append(CollectionIssue(
                        provider: provider,
                        message: "Large log was limited to the last \(maxFileBytes / 1024 / 1024) MB: \(file.lastPathComponent)"
                    ))
                }
                var invalidLines = 0
                var oversizedLines = 0
                let records = structuredRecords(in: read.data)
                for rawLine in records.lines {
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
                    let groupingKey: String
                    if let workingDirectory = record.workingDirectory {
                        let projectKey = URL(
                            fileURLWithPath: workingDirectory,
                            isDirectory: true
                        ).standardizedFileURL.path
                        groupingKey = "\(projectKey)\u{1f}\(sessionID)"
                        if let provisionalKey = groupingKeysBySessionID[sessionID]?.onlyElement,
                           provisionalKey.hasPrefix("file:"),
                           let provisional = grouped.removeValue(forKey: provisionalKey) {
                            grouped[groupingKey] = provisional
                            groupingKeysBySessionID[sessionID] = [groupingKey]
                        }
                    } else if let onlyKey = groupingKeysBySessionID[sessionID]?.onlyElement {
                        groupingKey = onlyKey
                    } else {
                        groupingKey = "file:\(file.path)\u{1f}\(sessionID)"
                    }
                    groupingKeysBySessionID[sessionID, default: []].insert(groupingKey)
                    var session = grouped[groupingKey] ?? MutableSession(
                        id: sessionID,
                        workingDirectory: record.workingDirectory,
                        wasTruncated: false,
                        client: read.client
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
                    if session.client == nil || session.client == .unknown {
                        session.client = read.client
                    }
                    grouped[groupingKey] = session
                }
                for object in records.objects {
                    guard let record = parse(
                        dictionary: object,
                        fallbackDate: read.modificationDate,
                        interval: interval
                    ) else { continue }
                    append(
                        record,
                        file: file,
                        wasTruncated: read.wasTruncated,
                        client: read.client,
                        grouped: &grouped,
                        groupingKeysBySessionID: &groupingKeysBySessionID
                    )
                }
                if invalidLines > 0 {
                    issues.append(CollectionIssue(
                        provider: provider,
                        message: "Skipped \(invalidLines) invalid JSONL lines in \(file.lastPathComponent)."
                    ))
                }
                if oversizedLines > 0 {
                    issues.append(CollectionIssue(
                        provider: provider,
                        message: "Skipped \(oversizedLines) oversized lines in \(file.lastPathComponent)."
                    ))
                }
            } catch {
                issues.append(CollectionIssue(
                    provider: provider,
                    message: "Could not read log (\(file.lastPathComponent)): \(error.localizedDescription)"
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
                wasTruncated: mutable.wasTruncated,
                client: mutable.client
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
            if let allowedFileNames, !allowedFileNames.contains(url.lastPathComponent) { continue }
            if let allowedTopLevelDirectories,
               !isUnderAllowedTopLevelDirectory(url, directories: allowedTopLevelDirectories) {
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

    private func isUnderAllowedTopLevelDirectory(_ url: URL, directories: Set<String>) -> Bool {
        let rootPath = rootDirectory.standardizedFileURL.path
        let filePath = url.standardizedFileURL.path
        let separator = rootPath == "/" ? "/" : rootPath + "/"
        guard filePath.hasPrefix(separator) else { return false }
        let relativePath = String(filePath.dropFirst(separator.count))
        guard let firstComponent = relativePath.split(separator: "/").first else { return false }
        return directories.contains(String(firstComponent))
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
        let prefixData: Data
        if startOffset == 0 {
            prefixData = Data(data.prefix(64 * 1_024))
        } else {
            try handle.seek(toOffset: 0)
            prefixData = try handle.read(upToCount: 64 * 1_024) ?? Data()
        }
        return ReadFile(
            data: Data(data.prefix(maxFileBytes)),
            modificationDate: modificationDate,
            wasTruncated: wasTruncated,
            client: clientKind(fromPrefix: prefixData)
        )
    }

    private func clientKind(fromPrefix data: Data) -> AgentClientKind? {
        guard provider == .codex else { return .cli }
        for line in data.split(separator: 10, omittingEmptySubsequences: true) {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line)),
                  let dictionary = object as? [String: Any],
                  (dictionary["type"] as? String) == "session_meta",
                  let payload = dictionary["payload"] as? [String: Any] else {
                continue
            }
            return AgentClientKind.codex(
                originator: payload["originator"] as? String,
                source: payload["source"] as? String
            )
        }
        return .unknown
    }

    private func parse(line: Data, fallbackDate: Date, interval: AwayInterval) -> ParsedRecord? {
        guard let object = try? JSONSerialization.jsonObject(with: line, options: []),
              let dictionary = object as? [String: Any] else {
            return nil
        }

        return parse(dictionary: dictionary, fallbackDate: fallbackDate, interval: interval)
    }

    private func parse(
        dictionary: [String: Any],
        fallbackDate: Date,
        interval: AwayInterval
    ) -> ParsedRecord? {

        let timestamp = dateValue(Self.findValue(in: dictionary, named: Self.timestampKeys)) ?? fallbackDate
        guard timestamp >= interval.start && timestamp <= interval.end else { return nil }

        let kind = stringValue(Self.findValue(in: dictionary, named: Self.kindKeys)) ?? "event"
        let sessionID = stringValue(Self.findValue(in: dictionary, named: Self.sessionKeys))
        let workingDirectory = stringValue(Self.findValue(in: dictionary, named: Self.workingDirectoryKeys))
        let content = Self.contentValue(in: dictionary)
            ?? (try? JSONSerialization.data(withJSONObject: dictionary, options: [.sortedKeys]))
                .map { String(decoding: $0, as: UTF8.self) }
            ?? ""
        return ParsedRecord(
            timestamp: timestamp,
            kind: kind,
            content: Self.truncatedUTF8(content, limit: 32_768),
            sessionID: sessionID,
            workingDirectory: workingDirectory
        )
    }

    private func structuredRecords(in data: Data) -> (lines: [Data.SubSequence], objects: [[String: Any]]) {
        guard let object = try? JSONSerialization.jsonObject(with: data, options: []) else {
            return (data.split(separator: 10, omittingEmptySubsequences: true), [])
        }

        var objects: [[String: Any]] = []
        if let dictionary = object as? [String: Any] {
            let inherited = dictionary.filter { key, _ in
                Self.sessionKeys.contains(key.lowercased())
                    || Self.workingDirectoryKeys.contains(key.lowercased())
            }
            if let messages = dictionary["messages"] as? [[String: Any]] {
                objects = messages.map { inherited.merging($0) { _, child in child } }
            } else {
                objects = [dictionary]
            }
        } else if let array = object as? [[String: Any]] {
            objects = array
        }
        return ([], objects)
    }

    private func append(
        _ record: ParsedRecord,
        file: URL,
        wasTruncated: Bool,
        client: AgentClientKind?,
        grouped: inout [String: MutableSession],
        groupingKeysBySessionID: inout [String: Set<String>]
    ) {
        let sessionID = record.sessionID ?? file.deletingPathExtension().lastPathComponent
        let groupingKey: String
        if let workingDirectory = record.workingDirectory {
            let projectKey = URL(fileURLWithPath: workingDirectory, isDirectory: true)
                .standardizedFileURL.path
            groupingKey = "\(projectKey)\u{1f}\(sessionID)"
        } else if let onlyKey = groupingKeysBySessionID[sessionID]?.onlyElement {
            groupingKey = onlyKey
        } else {
            groupingKey = "file:\(file.path)\u{1f}\(sessionID)"
        }
        groupingKeysBySessionID[sessionID, default: []].insert(groupingKey)
        var session = grouped[groupingKey] ?? MutableSession(
            id: sessionID,
            workingDirectory: record.workingDirectory,
            wasTruncated: false,
            client: client
        )
        session.events.append(CollectedEvent(
            timestamp: record.timestamp,
            kind: record.kind,
            content: record.content
        ))
        if session.workingDirectory == nil { session.workingDirectory = record.workingDirectory }
        session.wasTruncated = session.wasTruncated || wasTruncated
        if session.client == nil || session.client == .unknown { session.client = client }
        grouped[groupingKey] = session
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

private extension Set {
    var onlyElement: Element? {
        count == 1 ? first : nil
    }
}

private struct ReadFile {
    let data: Data
    let modificationDate: Date
    let wasTruncated: Bool
    let client: AgentClientKind?
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
    var client: AgentClientKind?
}
