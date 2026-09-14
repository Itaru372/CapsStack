import CapsStackLocalization
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

enum SummaryHighlightKind: String, Codable, CaseIterable, Sendable {
    case nextAction
    case waiting
    case blocker
    case progress
    case decision
    case currentState
    case discovery
    case verification
    case risk
    case change
}

/// One useful, source-attributed fact selected by the summarizer. Unlike the legacy top-level
/// string arrays, every item carries enough context to remain understandable when several
/// projects and agent sessions were active during the same away interval.
struct SummaryHighlight: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let kind: SummaryHighlightKind
    let text: String
    let projectID: String
    let projectName: String
    let sessionID: String?
    let source: String?

    init(
        id: UUID = UUID(),
        kind: SummaryHighlightKind,
        text: String,
        projectID: String,
        projectName: String,
        sessionID: String? = nil,
        source: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.text = text
        self.projectID = projectID
        self.projectName = projectName
        self.sessionID = sessionID
        self.source = source
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, text, projectID, projectName, sessionID, source
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        kind = try container.decode(SummaryHighlightKind.self, forKey: .kind)
        text = try container.decode(String.self, forKey: .text)
        projectID = try container.decode(String.self, forKey: .projectID)
        projectName = try container.decode(String.self, forKey: .projectName)
        sessionID = try container.decodeIfPresent(String.self, forKey: .sessionID)
        source = try container.decodeIfPresent(String.self, forKey: .source)
    }
}

enum SummaryHighlightLimits {
    static let total = 12
    static let perKind = 3

    static func bounded(_ highlights: [SummaryHighlight]) -> [SummaryHighlight] {
        var counts: [SummaryHighlightKind: Int] = [:]
        var result: [SummaryHighlight] = []
        for highlight in highlights {
            guard result.count < total else { break }
            let count = counts[highlight.kind, default: 0]
            guard count < perKind else { continue }
            counts[highlight.kind] = count + 1
            result.append(highlight)
        }
        return result
    }
}

struct SummaryDocument: Codable, Equatable, Sendable {
    let overview: String
    let progress: [String]
    let currentState: [String]
    let decisions: [String]
    let blockers: [String]
    let nextSteps: [String]
    let highlights: [SummaryHighlight]
    let sessions: [SessionSummary]
    let projects: [ProjectSummary]

    init(
        overview: String,
        progress: [String],
        currentState: [String],
        decisions: [String],
        blockers: [String],
        nextSteps: [String],
        highlights: [SummaryHighlight] = [],
        sessions: [SessionSummary],
        projects: [ProjectSummary] = []
    ) {
        self.overview = overview
        self.progress = progress
        self.currentState = currentState
        self.decisions = decisions
        self.blockers = blockers
        self.nextSteps = nextSteps
        self.highlights = SummaryHighlightLimits.bounded(highlights)
        self.sessions = sessions
        self.projects = projects
    }

    private enum CodingKeys: String, CodingKey {
        case overview, progress, currentState, decisions, blockers, nextSteps, highlights, sessions, projects
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        overview = try container.decode(String.self, forKey: .overview)
        progress = try container.decode([String].self, forKey: .progress)
        currentState = try container.decode([String].self, forKey: .currentState)
        decisions = try container.decode([String].self, forKey: .decisions)
        blockers = try container.decode([String].self, forKey: .blockers)
        nextSteps = try container.decode([String].self, forKey: .nextSteps)
        highlights = SummaryHighlightLimits.bounded(
            try container.decodeIfPresent([SummaryHighlight].self, forKey: .highlights) ?? []
        )
        projects = try container.decodeIfPresent([ProjectSummary].self, forKey: .projects) ?? []
        sessions = try container.decodeIfPresent([SessionSummary].self, forKey: .sessions)
            ?? projects.flatMap(\.sessions)
    }

    static let empty = SummaryDocument(
        overview: CapsStackText.resolve(.noProgressSummary),
        progress: [],
        currentState: [],
        decisions: [],
        blockers: [],
        nextSteps: [],
        highlights: [],
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
            CapsStackText.format(.providerNotFound, kind.displayName)
        case .processFailed(let kind, let message):
            CapsStackText.format(.providerFailed, kind.displayName, message)
        case .timedOut(let kind):
            CapsStackText.format(.providerTimedOut, kind.displayName)
        case .invalidOutput(let kind):
            CapsStackText.format(.providerInvalidOutput, kind.displayName)
        case .noProviderAvailable:
            CapsStackText.resolve(.noProviderAvailable)
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
        "highlights": {
          "type": "array",
          "maxItems": 12,
          "items": {
            "type": "object",
            "additionalProperties": false,
            "properties": {
              "kind": {
                "type": "string",
                "enum": ["nextAction", "waiting", "blocker", "progress", "decision", "currentState", "discovery", "verification", "risk", "change"]
              },
              "text": { "type": "string" },
              "projectID": { "type": "string" },
              "projectName": { "type": "string" },
              "sessionID": { "type": ["string", "null"] },
              "source": { "type": ["string", "null"] }
            },
            "required": ["kind", "text", "projectID", "projectName", "sessionID", "source"]
          }
        },
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
      "required": ["overview", "progress", "currentState", "decisions", "blockers", "nextSteps", "highlights", "projects"]
    }
    """#
}
