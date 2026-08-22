import Foundation

struct SessionSummary: Codable, Equatable, Identifiable, Sendable {
    var id: String { sessionID }
    let sessionID: String
    let source: String
    let summary: String
}

struct SummaryDocument: Codable, Equatable, Sendable {
    let overview: String
    let progress: [String]
    let currentState: [String]
    let decisions: [String]
    let blockers: [String]
    let nextSteps: [String]
    let sessions: [SessionSummary]

    static let empty = SummaryDocument(
        overview: "要約できる進捗はありませんでした。",
        progress: [],
        currentState: [],
        decisions: [],
        blockers: [],
        nextSteps: [],
        sessions: []
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
            "\(kind.displayName) が見つかりません。"
        case .processFailed(let kind, let message):
            "\(kind.displayName) の実行に失敗しました: \(message)"
        case .timedOut(let kind):
            "\(kind.displayName) の要約がタイムアウトしました。"
        case .invalidOutput(let kind):
            "\(kind.displayName) が読み取れない要約を返しました。"
        case .noProviderAvailable:
            "利用可能な要約CLIがありません。"
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
      "required": ["overview", "progress", "currentState", "decisions", "blockers", "nextSteps", "sessions"]
    }
    """#
}
