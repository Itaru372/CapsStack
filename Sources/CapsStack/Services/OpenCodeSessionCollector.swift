import Foundation

/// Collects OpenCode sessions through its documented CLI export boundary.
///
/// OpenCode's current storage is a database-backed project store rather than a stable JSONL
/// transcript directory. The CLI exposes `session list --format json` and `export`, so reading
/// through that boundary keeps this adapter compatible with storage migrations and both the
/// stable `opencode` and beta `opencode2` binaries.
final class OpenCodeSessionCollector: SessionCollector {
    typealias CommandRunner = (URL, [String], URL?, TimeInterval) -> Data?

    let provider: CLIKind = .opencode
    private let rootDirectory: URL
    private let executableURL: URL?
    private let fileManager: FileManager
    private let maxSessions: Int
    private let commandRunner: CommandRunner

    init(
        rootDirectory: URL,
        executableURL: URL?,
        fileManager: FileManager = .default,
        maxSessions: Int = 2_000,
        commandRunner: @escaping CommandRunner = OpenCodeSessionCollector.runCommand
    ) {
        self.rootDirectory = rootDirectory
        self.executableURL = executableURL
        self.fileManager = fileManager
        self.maxSessions = max(1, maxSessions)
        self.commandRunner = commandRunner
    }

    func collect(interval: AwayInterval) -> CollectionResult {
        guard fileManager.fileExists(atPath: rootDirectory.path) else {
            return CollectionResult(
                provider: provider,
                sessions: [],
                issues: [CollectionIssue(
                    provider: provider,
                    message: "ログ保存先が見つかりません: \(rootDirectory.path)"
                )]
            )
        }

        guard let executableURL else {
            return fallbackToFiles(
                interval: interval,
                reason: "OpenCode CLIが見つからないため、保存ファイルを補助的に走査しました。"
            )
        }

        let listData = commandRunner(
            executableURL,
            ["session", "list", "--max-count", String(maxSessions), "--format", "json"],
            rootDirectory,
            15
        )
        guard let listData else {
            return fallbackToFiles(
                interval: interval,
                reason: "OpenCodeのセッション一覧を取得できないため、保存ファイルを補助的に走査しました。"
            )
        }

        let descriptors = Self.sessionDescriptors(from: listData)
        guard !descriptors.isEmpty else {
            if (try? JSONSerialization.jsonObject(with: listData, options: [])) != nil {
                return CollectionResult(provider: provider, sessions: [], issues: [])
            }
            return fallbackToFiles(
                interval: interval,
                reason: "OpenCodeのセッション一覧を解釈できないため、保存ファイルを補助的に走査しました。"
            )
        }

        let lowerBound = interval.start.addingTimeInterval(-max(86_400, interval.duration + 60))
        let upperBound = interval.end.addingTimeInterval(60)
        var sessions: [CollectedSessionArtifact] = []
        var issues: [CollectionIssue] = []

        for descriptor in descriptors where descriptor.overlaps(lowerBound: lowerBound, upperBound: upperBound) {
            guard let exportData = commandRunner(
                executableURL,
                ["export", descriptor.id],
                rootDirectory,
                30
            ) else {
                issues.append(CollectionIssue(
                    provider: provider,
                    message: "OpenCodeセッションを書き出せませんでした: \(descriptor.id)"
                ))
                continue
            }

            let fallbackDate = descriptor.updatedAt ?? descriptor.createdAt ?? interval.start
            let records = Self.records(
                from: exportData,
                fallbackSessionID: descriptor.id,
                fallbackDirectory: descriptor.directory,
                fallbackDate: fallbackDate
            )
            let events = Self.unique(records)
                .filter { $0.timestamp >= interval.start && $0.timestamp <= interval.end }
                .sorted { $0.timestamp < $1.timestamp }

            guard !events.isEmpty else { continue }
            sessions.append(CollectedSessionArtifact(
                id: "\(provider.rawValue):\(descriptor.id)",
                provider: provider,
                workingDirectory: descriptor.directory ?? records.first?.workingDirectory,
                events: events.map {
                    CollectedEvent(timestamp: $0.timestamp, kind: $0.kind, content: $0.content)
                },
                wasTruncated: false
            ))
        }

        sessions.sort {
            ($0.firstEventAt ?? interval.start, $0.id) < ($1.firstEventAt ?? interval.start, $1.id)
        }
        return CollectionResult(provider: provider, sessions: sessions, issues: issues)
    }

    private func fallbackToFiles(interval: AwayInterval, reason: String) -> CollectionResult {
        let fileResult = JSONLSessionCollector(provider: provider, rootDirectory: rootDirectory)
            .collect(interval: interval)
        return CollectionResult(
            provider: provider,
            sessions: fileResult.sessions,
            issues: [CollectionIssue(provider: provider, message: reason)] + fileResult.issues
        )
    }

    private static func sessionDescriptors(from data: Data) -> [SessionDescriptor] {
        guard let object = try? JSONSerialization.jsonObject(with: data, options: []) else {
            return []
        }

        var dictionaries: [[String: Any]] = []
        collectDictionaries(from: object, into: &dictionaries)
        var seen = Set<String>()
        return dictionaries.compactMap { dictionary in
            guard let id = stringValue(value(in: dictionary, keys: ["id", "sessionID", "session_id"])),
                  !id.isEmpty,
                  value(in: dictionary, keys: ["directory", "cwd", "title", "time", "projectID"]) != nil,
                  seen.insert(id).inserted else {
                return nil
            }

            return SessionDescriptor(
                id: id,
                directory: stringValue(value(in: dictionary, keys: ["directory", "cwd", "workingDirectory"])),
                createdAt: dateValue(
                    value(in: dictionary, keys: ["createdAt", "created_at", "created", "time"]),
                    prefer: ["created", "createdAt", "created_at"]
                ),
                updatedAt: dateValue(
                    value(in: dictionary, keys: ["updatedAt", "updated_at", "updated", "time"]),
                    prefer: ["updated", "updatedAt", "updated_at"]
                )
            )
        }
    }

    private static func collectDictionaries(from value: Any, into result: inout [[String: Any]]) {
        if let dictionary = value as? [String: Any] {
            result.append(dictionary)
            for child in dictionary.values {
                collectDictionaries(from: child, into: &result)
            }
        } else if let array = value as? [Any] {
            for child in array {
                collectDictionaries(from: child, into: &result)
            }
        }
    }

    private static func records(
        from data: Data,
        fallbackSessionID: String,
        fallbackDirectory: String?,
        fallbackDate: Date
    ) -> [ExtractedRecord] {
        guard let object = try? JSONSerialization.jsonObject(with: data, options: []) else {
            return []
        }

        var result: [ExtractedRecord] = []
        walk(
            object,
            fallbackSessionID: fallbackSessionID,
            fallbackDirectory: fallbackDirectory,
            fallbackDate: fallbackDate,
            into: &result
        )
        return result
    }

    private static func walk(
        _ node: Any,
        fallbackSessionID: String,
        fallbackDirectory: String?,
        fallbackDate: Date,
        into result: inout [ExtractedRecord]
    ) {
        if let dictionary = node as? [String: Any] {
            let sessionID = stringValue(Self.value(in: dictionary, keys: ["sessionID", "session_id"]))
                ?? fallbackSessionID
            let directory = stringValue(Self.value(in: dictionary, keys: ["directory", "cwd", "workingDirectory", "working_directory"]))
                ?? fallbackDirectory
            let timestamp = dateValue(
                Self.value(in: dictionary, keys: ["timestamp", "createdAt", "created_at", "time"]),
                prefer: ["created", "timestamp", "createdAt", "created_at"]
            ) ?? fallbackDate
            let keys = Set(dictionary.keys.map { $0.lowercased() })
            let looksLikeRecord = !keys.isDisjoint(with: [
                "role", "type", "content", "text", "output", "summary", "message", "parts"
            ])

            if looksLikeRecord,
               let content = textualValue(in: dictionary),
               !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                result.append(ExtractedRecord(
                    timestamp: timestamp,
                    kind: stringValue(Self.value(in: dictionary, keys: ["role", "type", "kind", "event"])) ?? "event",
                    content: String(content.prefix(32_768)),
                    sessionID: sessionID,
                    workingDirectory: directory
                ))
            }

            for (key, child) in dictionary where !["content", "text", "output", "summary"].contains(key.lowercased()) {
                walk(
                    child,
                    fallbackSessionID: sessionID,
                    fallbackDirectory: directory,
                    fallbackDate: timestamp,
                    into: &result
                )
            }
        } else if let array = node as? [Any] {
            for child in array {
                walk(
                    child,
                    fallbackSessionID: fallbackSessionID,
                    fallbackDirectory: fallbackDirectory,
                    fallbackDate: fallbackDate,
                    into: &result
                )
            }
        }
    }

    private static func unique(_ records: [ExtractedRecord]) -> [ExtractedRecord] {
        var seen = Set<String>()
        return records.filter { record in
            let fingerprint = "\(record.timestamp.timeIntervalSince1970)|\(record.kind)|\(record.content)"
            return seen.insert(fingerprint).inserted
        }
    }

    private static func textualValue(in dictionary: [String: Any]) -> String? {
        for key in ["text", "content", "output", "summary", "message"] {
            guard let value = value(in: dictionary, keys: [key]) else { continue }
            if let text = textualValue(value) { return text }
        }
        return nil
    }

    private static func textualValue(_ value: Any) -> String? {
        if let string = value as? String, !string.isEmpty { return string }
        if let array = value as? [Any] {
            let strings = array.compactMap(textualValue)
            return strings.isEmpty ? nil : strings.joined(separator: "\n")
        }
        if let dictionary = value as? [String: Any] {
            return textualValue(in: dictionary)
        }
        return nil
    }

    private static func value(in dictionary: [String: Any], keys: [String]) -> Any? {
        let normalized = Dictionary(uniqueKeysWithValues: dictionary.map { ($0.key.lowercased(), $0.value) })
        for key in keys where normalized[key.lowercased()] != nil {
            return normalized[key.lowercased()]
        }
        for child in dictionary.values {
            if let nested = child as? [String: Any], let found = value(in: nested, keys: keys) {
                return found
            }
        }
        return nil
    }

    private static func stringValue(_ value: Any?) -> String? {
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }

    private static func dateValue(_ value: Any?, prefer: [String]) -> Date? {
        if let number = value as? NSNumber {
            let raw = number.doubleValue
            return Date(timeIntervalSince1970: raw > 10_000_000_000 ? raw / 1_000 : raw)
        }
        if let string = value as? String {
            if let number = Double(string) {
                return Date(timeIntervalSince1970: number > 10_000_000_000 ? number / 1_000 : number)
            }
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: string) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            return formatter.date(from: string)
        }
        if let dictionary = value as? [String: Any] {
            let normalized = Dictionary(uniqueKeysWithValues: dictionary.map { ($0.key.lowercased(), $0.value) })
            for key in prefer {
                if let date = dateValue(normalized[key.lowercased()], prefer: prefer) { return date }
            }
            for child in dictionary.values {
                if let date = dateValue(child, prefer: prefer) { return date }
            }
        }
        return nil
    }

    private static func runCommand(
        executableURL: URL,
        arguments: [String],
        currentDirectoryURL: URL?,
        timeout: TimeInterval
    ) -> Data? {
        guard FileManager.default.isExecutableFile(atPath: executableURL.path) else { return nil }

        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectoryURL
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return nil
        }

        let deadline = Date().addingTimeInterval(max(0.1, timeout))
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            process.terminate()
            process.waitUntilExit()
            return nil
        }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else { return nil }
        return data.count > 8 * 1024 * 1024 ? Data(data.prefix(8 * 1024 * 1024)) : data
    }
}

private struct SessionDescriptor {
    let id: String
    let directory: String?
    let createdAt: Date?
    let updatedAt: Date?

    func overlaps(lowerBound: Date, upperBound: Date) -> Bool {
        if let updatedAt, updatedAt < lowerBound { return false }
        if let createdAt, createdAt > upperBound { return false }
        return true
    }
}

private struct ExtractedRecord {
    let timestamp: Date
    let kind: String
    let content: String
    let sessionID: String
    let workingDirectory: String?
}
