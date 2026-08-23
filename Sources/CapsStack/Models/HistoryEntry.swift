import Foundation

enum HistoryStatus: String, Codable, Sendable {
    case completed
    case pending
    case empty
}

struct HistoryEntry: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let interval: AwayInterval
    let status: HistoryStatus
    let summary: SummaryDocument?
    let provider: CLIKind?
    let fallbackUsed: Bool
    let sessionCount: Int
    let sources: [CLIKind]
    let collectionIssues: [CollectionIssue]
    let errorMessage: String?
    let pendingArtifactID: UUID?
    let quickMemo: String?

    init(
        id: UUID = UUID(),
        interval: AwayInterval,
        status: HistoryStatus,
        summary: SummaryDocument? = nil,
        provider: CLIKind? = nil,
        fallbackUsed: Bool = false,
        sessionCount: Int,
        sources: [CLIKind],
        collectionIssues: [CollectionIssue] = [],
        errorMessage: String? = nil,
        pendingArtifactID: UUID? = nil,
        quickMemo: String? = nil
    ) {
        self.id = id
        self.interval = interval
        self.status = status
        self.summary = summary
        self.provider = provider
        self.fallbackUsed = fallbackUsed
        self.sessionCount = sessionCount
        self.sources = sources
        self.collectionIssues = collectionIssues
        self.errorMessage = errorMessage
        self.pendingArtifactID = pendingArtifactID
        self.quickMemo = quickMemo
    }
}
