import Foundation

struct AwayInterval: Codable, Equatable, Sendable {
    let start: Date
    let end: Date

    var duration: TimeInterval { max(0, end.timeIntervalSince(start)) }
}

struct CollectedEvent: Codable, Equatable, Sendable {
    let timestamp: Date
    let kind: String
    let content: String
}

enum AgentClientKind: String, Codable, Equatable, Sendable {
    case cli
    case desktop
    case ideExtension
    case sdk
    case shared
    case unknown

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self = Self(rawValue: (try? container.decode(String.self)) ?? "") ?? .unknown
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    static func codex(originator: String?, source: String?) -> AgentClientKind {
        let origin = originator?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        let source = source?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""

        if origin == "codex desktop" || origin == "codex_work_desktop" { return .desktop }
        if origin.hasPrefix("codex_sdk") { return .sdk }
        if origin.hasPrefix("codex"),
           origin.contains("extension") || origin.contains("sidepanel") || origin.contains("vscode") {
            return .ideExtension
        }
        let cliOrigins: Set<String> = ["codex", "codex_cli", "codex_cli_rs", "codex-tui", "codex_exec"]
        if cliOrigins.contains(origin) || origin.hasPrefix("codex_cli_") { return .cli }
        if source == "cli" || source == "exec" || source == "codex_rollout" { return .cli }
        return .unknown
    }

    func sourceDisplayName(for provider: CLIKind) -> String {
        switch self {
        case .cli: "\(provider.collectionDisplayName) CLI"
        case .desktop: "\(provider.collectionDisplayName) Desktop"
        case .ideExtension: "\(provider.collectionDisplayName) IDE"
        case .sdk: "\(provider.collectionDisplayName) SDK"
        case .shared: "\(provider.collectionDisplayName) 共有セッション"
        case .unknown: provider.collectionDisplayName
        }
    }
}

struct CollectedSessionArtifact: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let provider: CLIKind
    let workingDirectory: String?
    let events: [CollectedEvent]
    let wasTruncated: Bool
    let client: AgentClientKind?

    init(
        id: String,
        provider: CLIKind,
        workingDirectory: String?,
        events: [CollectedEvent],
        wasTruncated: Bool,
        client: AgentClientKind? = nil
    ) {
        self.id = id
        self.provider = provider
        self.workingDirectory = workingDirectory
        self.events = events
        self.wasTruncated = wasTruncated
        self.client = client
    }

    var firstEventAt: Date? { events.first?.timestamp }
    var lastEventAt: Date? { events.last?.timestamp }
    var effectiveClient: AgentClientKind { client ?? .unknown }
    var sourceDisplayName: String { effectiveClient.sourceDisplayName(for: provider) }
}

/// A stable, presentation-ready project grouping derived from the source session's working
/// directory. The identifier is intentionally local to one collection batch so paths do not
/// need to be copied into generated summaries.
struct CollectedProjectArtifact: Codable, Equatable, Identifiable, Sendable {
    let projectID: String
    let name: String
    let workingDirectory: String?
    let sessions: [CollectedSessionArtifact]

    var id: String { projectID }
}

enum CollectionProjectGrouping {
    static func projects(in batch: CollectionBatch) -> [CollectedProjectArtifact] {
        let grouped = Dictionary(grouping: batch.sessions, by: projectKey(for:))
        let ordered = grouped.map { key, sessions in
            let sortedSessions = sessions.sorted {
                ($0.firstEventAt ?? batch.interval.start, $0.id)
                    < ($1.firstEventAt ?? batch.interval.start, $1.id)
            }
            return (key: key, sessions: sortedSessions)
        }.sorted {
            let lhsDate = $0.sessions.first?.firstEventAt ?? batch.interval.start
            let rhsDate = $1.sessions.first?.firstEventAt ?? batch.interval.start
            return (lhsDate, $0.key) < (rhsDate, $1.key)
        }

        return ordered.enumerated().map { index, item in
            let directory = item.sessions.compactMap(\.workingDirectory).first
            return CollectedProjectArtifact(
                projectID: "project-\(index + 1)",
                name: projectName(for: directory),
                workingDirectory: directory,
                sessions: item.sessions
            )
        }
    }

    static func projectKey(for session: CollectedSessionArtifact) -> String {
        guard let directory = normalizedDirectory(session.workingDirectory) else {
            return "unknown:\(session.provider.rawValue)"
        }
        return "directory:\(directory)"
    }

    private static func normalizedDirectory(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: value, isDirectory: true).standardizedFileURL.path
    }

    private static func projectName(for directory: String?) -> String {
        guard let directory = normalizedDirectory(directory) else { return "プロジェクト不明" }
        let name = URL(fileURLWithPath: directory, isDirectory: true).lastPathComponent
        return name.isEmpty ? directory : name
    }
}

struct CollectionIssue: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let provider: CLIKind
    let message: String

    init(id: UUID = UUID(), provider: CLIKind, message: String) {
        self.id = id
        self.provider = provider
        self.message = message
    }
}

struct CollectionResult: Sendable {
    let provider: CLIKind
    let sessions: [CollectedSessionArtifact]
    let issues: [CollectionIssue]
}

struct CollectionBatch: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let interval: AwayInterval
    let sessions: [CollectedSessionArtifact]
    let issues: [CollectionIssue]
    /// Optional user-written context recorded before stepping away. Travels inside the batch
    /// artifact so retries preserve it and the summary prompt includes it naturally.
    var quickMemo: String?

    init(
        id: UUID = UUID(),
        interval: AwayInterval,
        sessions: [CollectedSessionArtifact],
        issues: [CollectionIssue],
        quickMemo: String? = nil
    ) {
        self.id = id
        self.interval = interval
        self.sessions = sessions
        self.issues = issues
        self.quickMemo = quickMemo
    }
}

/// Prepares a collected batch for summarization without mutating the collector result.
enum AwayBatchPreparation {
    /// GUI agents do not write the JSONL logs CapsStack reads. When only a quick memo exists,
    /// represent it as one synthetic input so the summarizer still runs.
    static func addingSyntheticMemoSession(
        _ batch: CollectionBatch,
        provider: CLIKind
    ) -> CollectionBatch {
        guard batch.sessions.isEmpty, let memo = batch.quickMemo else { return batch }

        return CollectionBatch(
            id: batch.id,
            interval: batch.interval,
            sessions: [
                CollectedSessionArtifact(
                    id: "capsstack-quick-memo",
                    provider: provider,
                    workingDirectory: nil,
                    events: [CollectedEvent(
                        timestamp: batch.interval.start,
                        kind: "user-note",
                        content: memo
                    )],
                    wasTruncated: false
                )
            ],
            issues: batch.issues,
            quickMemo: batch.quickMemo
        )
    }
}
