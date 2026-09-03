import Foundation

struct SessionSummary: Codable, Equatable, Identifiable, Sendable {
    var id: String { sessionID }
    let sessionID: String
    let source: String
    let summary: String
}

struct ProjectSummary: Codable, Equatable, Identifiable, Sendable {
    var id: String { projectID }
    let projectID: String
    let name: String
    let summary: String
    let sessions: [SessionSummary]
}

struct SummaryDocument: Codable, Equatable, Sendable {
    let overview: String
    let progress: [String]
    let currentState: [String]
    let decisions: [String]
    let blockers: [String]
    let nextSteps: [String]
    let sessions: [SessionSummary]
    let projects: [ProjectSummary]

    init(
        overview: String,
        progress: [String],
        currentState: [String],
        decisions: [String],
        blockers: [String],
        nextSteps: [String],
        sessions: [SessionSummary],
        projects: [ProjectSummary] = []
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
        projects = try container.decodeIfPresent([ProjectSummary].self, forKey: .projects) ?? []
        sessions = try container.decodeIfPresent([SessionSummary].self, forKey: .sessions)
            ?? projects.flatMap(\.sessions)
    }

    static let empty = SummaryDocument(
        overview: "No progress could be summarized.",
        progress: [],
        currentState: [],
        decisions: [],
        blockers: [],
        nextSteps: [],
        sessions: [],
        projects: []
    )
}

struct SummaryOutcome: Equatable, Sendable {
    let document: SummaryDocument
    let provider: CLIKind
    let fallbackUsed: Bool
}

enum SummaryProviderError: LocalizedError, Equatable {
    case executableNotFound(CLIKind)
    case processFailed(CLIKind, String)
    case timedOut(CLIKind)
    case invalidOutput(CLIKind)
    case noProviderAvailable

    var errorDescription: String? {
        switch self {
        case .executableNotFound(let kind):
            "\(kind.displayName) was not found."
        case .processFailed(let kind, let message):
            "\(kind.displayName) failed to run: \(message)"
        case .timedOut(let kind):
            "\(kind.displayName) summary timed out."
        case .invalidOutput(let kind):
            "\(kind.displayName) returned an unreadable summary."
        case .noProviderAvailable:
            "No summarizer CLI is available."
        }
    }
}

enum SummarySchema {
    static let json: String = #"""
    {
      "$schema": "https://json-schema.org/draft/2020-12/schema",
      "type": "object",
      "additionalProperties": false,
      "properties": {
        "overview": { "type": "string" },
        "progress": { "type": "array", "items": { "type": "string" } },
        "currentState": { "type": "array", "items": { "type": "string" } },
        "decisions": { "type": "array", "items": { "type": "string" } },
        "blockers": { "type": "array", "items": { "type": "string" } },
        "nextSteps": { "type": "array", "items": { "type": "string" } },
        "projects": {
          "type": "array",
          "items": {
            "type": "object",
            "additionalProperties": false,
            "properties": {
              "projectID": { "type": "string" },
              "name": { "type": "string" },
              "summary": { "type": "string" },
              "sessions": {
                "type": "array",
                "items": {
                  "type": "object",
                  "additionalProperties": false,
                  "properties": {
                    "sessionID": { "type": "string" },
                    "source": { "type": "string" },
                    "summary": { "type": "string" }
                  },
                  "required": ["sessionID", "source", "summary"]
                }
              }
            },
            "required": ["projectID", "name", "summary", "sessions"]
          }
        }
      },
      "required": ["overview", "progress", "currentState", "decisions", "blockers", "nextSteps", "projects"]
    }
    """#
}
