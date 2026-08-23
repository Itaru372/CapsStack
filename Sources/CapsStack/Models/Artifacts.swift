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

struct CollectedSessionArtifact: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let provider: CLIKind
    let workingDirectory: String?
    let events: [CollectedEvent]
    let wasTruncated: Bool

    var firstEventAt: Date? { events.first?.timestamp }
    var lastEventAt: Date? { events.last?.timestamp }
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
