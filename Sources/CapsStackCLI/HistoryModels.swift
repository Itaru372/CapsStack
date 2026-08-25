import Foundation

enum CLIHistoryStatus: String, Codable, Sendable {
    case completed
    case pending
    case empty
}

enum CLIAgentKind: String, Codable, Sendable {
    case codex
    case claudeCode
    case opencode
    case pi

    var displayName: String {
        switch self {
        case .codex: "Codex CLI"
        case .claudeCode: "Claude Code CLI"
        case .opencode: "OpenCode CLI"
        case .pi: "Pi coding agent"
        }
    }
}

struct CLIAwayInterval: Codable, Equatable, Sendable {
    let start: Date
    let end: Date

    var duration: TimeInterval { max(0, end.timeIntervalSince(start)) }
}

struct CLICollectionIssue: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let provider: CLIAgentKind
    let message: String
}

struct CLISessionSummary: Codable, Equatable, Identifiable, Sendable {
    var id: String { sessionID }
    let sessionID: String
    let source: String
    let summary: String
}

struct CLISummaryDocument: Codable, Equatable, Sendable {
    let overview: String
    let progress: [String]
    let currentState: [String]
    let decisions: [String]
    let blockers: [String]
    let nextSteps: [String]
    let sessions: [CLISessionSummary]
}

struct CLIHistoryEntry: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let interval: CLIAwayInterval
    let status: CLIHistoryStatus
    let summary: CLISummaryDocument?
    let provider: CLIAgentKind?
    let fallbackUsed: Bool
    let sessionCount: Int
    let sources: [CLIAgentKind]
    let collectionIssues: [CLICollectionIssue]
    let errorMessage: String?
    let pendingArtifactID: UUID?
    let quickMemo: String?
}
