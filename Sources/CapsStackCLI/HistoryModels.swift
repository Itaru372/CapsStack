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
    case githubCopilot
    case kiloCode
    case goose
    case qwenCode
    case continueCLI
    case geminiCLI

    var displayName: String {
        switch self {
        case .codex: "Codex CLI"
        case .claudeCode: "Claude Code CLI"
        case .opencode: "OpenCode CLI"
        case .pi: "Pi coding agent"
        case .githubCopilot: "GitHub Copilot CLI"
        case .kiloCode: "Kilo Code CLI"
        case .goose: "Goose CLI"
        case .qwenCode: "Qwen Code"
        case .continueCLI: "Continue CLI"
        case .geminiCLI: "Gemini CLI"
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

struct CLIProjectSummary: Codable, Equatable, Identifiable, Sendable {
    var id: String { projectID }
    let projectID: String
    let name: String
    let summary: String
    let sessions: [CLISessionSummary]
}

struct CLISummaryDocument: Codable, Equatable, Sendable {
    let overview: String
    let progress: [String]
    let currentState: [String]
    let decisions: [String]
    let blockers: [String]
    let nextSteps: [String]
    let sessions: [CLISessionSummary]
    let projects: [CLIProjectSummary]

    init(
        overview: String,
        progress: [String],
        currentState: [String],
        decisions: [String],
        blockers: [String],
        nextSteps: [String],
        sessions: [CLISessionSummary],
        projects: [CLIProjectSummary] = []
    ) {
        self.overview = overview
        self.progress = progress
        self.currentState = currentState
        self.decisions = decisions
        self.blockers = blockers
        self.nextSteps = nextSteps
        self.sessions = sessions
        self.projects = projects
    }

    private enum CodingKeys: String, CodingKey {
        case overview, progress, currentState, decisions, blockers, nextSteps, sessions, projects
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        overview = try container.decode(String.self, forKey: .overview)
        progress = try container.decode([String].self, forKey: .progress)
        currentState = try container.decode([String].self, forKey: .currentState)
        decisions = try container.decode([String].self, forKey: .decisions)
        blockers = try container.decode([String].self, forKey: .blockers)
        nextSteps = try container.decode([String].self, forKey: .nextSteps)
        projects = try container.decodeIfPresent([CLIProjectSummary].self, forKey: .projects) ?? []
        sessions = try container.decodeIfPresent([CLISessionSummary].self, forKey: .sessions)
            ?? projects.flatMap(\.sessions)
    }
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
