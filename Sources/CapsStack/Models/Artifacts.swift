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

    init(
        id: UUID = UUID(),
        interval: AwayInterval,
        sessions: [CollectedSessionArtifact],
        issues: [CollectionIssue]
    ) {
        self.id = id
        self.interval = interval
        self.sessions = sessions
        self.issues = issues
    }
}
