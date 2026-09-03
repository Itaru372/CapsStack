import Foundation

/// Reads GitHub Copilot CLI's local session-state archive without invoking or resuming Copilot.
/// Each UUID directory is one session and contains `events.jsonl` plus optional workspace metadata.
final class GitHubCopilotSessionCollector: SessionCollector {
    let provider: CLIKind = .githubCopilot
    private let rootDirectory: URL
    private let fileManager: FileManager
    private let maxSessions: Int

    init(
        rootDirectory: URL,
        fileManager: FileManager = .default,
        maxSessions: Int = 2_000
    ) {
        self.rootDirectory = rootDirectory
        self.fileManager = fileManager
        self.maxSessions = max(1, maxSessions)
    }

    func collect(interval: AwayInterval) -> CollectionResult {
        guard let directories = try? fileManager.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return CollectionResult(
                provider: provider,
                sessions: [],
                issues: [CollectionIssue(
                    provider: provider,
                    message: "GitHub Copilotのセッション保存先を読み取れません: \(rootDirectory.path)"
                )]
            )
        }

        let candidates = directories.filter {
            (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                && fileManager.fileExists(atPath: $0.appendingPathComponent("events.jsonl").path)
        }.sorted {
            modificationDate(of: $0) > modificationDate(of: $1)
        }

        var issues: [CollectionIssue] = []
        let selected = Array(candidates.prefix(maxSessions))
        if candidates.count > selected.count {
            issues.append(CollectionIssue(
                provider: provider,
                message: "対象セッションが多いため、最新の\(maxSessions)件だけを確認しました。"
            ))
        }

        var sessions: [CollectedSessionArtifact] = []
        for directory in selected {
            let result = JSONLSessionCollector(
                provider: provider,
                rootDirectory: directory,
                allowedFileNames: ["events.jsonl"]
            )
                .collect(interval: interval)
            let workspace = workspaceDirectory(in: directory)
            sessions.append(contentsOf: result.sessions.map { session in
                CollectedSessionArtifact(
                    id: "\(provider.rawValue):\(directory.lastPathComponent)",
                    provider: provider,
                    workingDirectory: session.workingDirectory ?? workspace,
                    events: session.events,
                    wasTruncated: session.wasTruncated,
                    client: .cli
                )
            })
            issues.append(contentsOf: result.issues)
        }

        sessions.sort {
            ($0.firstEventAt ?? interval.start, $0.id) < ($1.firstEventAt ?? interval.start, $1.id)
        }
        return CollectionResult(provider: provider, sessions: sessions, issues: issues)
    }

    private func modificationDate(of directory: URL) -> Date {
        (try? directory.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
            ?? .distantPast
    }

    private func workspaceDirectory(in sessionDirectory: URL) -> String? {
        let url = sessionDirectory.appendingPathComponent("workspace.yaml")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2, parts[0].trimmingCharacters(in: .whitespaces) == "cwd" else { continue }
            let value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            return value.isEmpty ? nil : value
        }
        return nil
    }
}
