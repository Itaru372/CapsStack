import Foundation

enum CLIKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case codex
    case claudeCode
    case opencode
    case pi

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .codex: "Codex CLI"
        case .claudeCode: "Claude Code CLI"
        case .opencode: "OpenCode CLI"
        case .pi: "Pi coding agent"
        }
    }

    var executableName: String {
        switch self {
        case .codex: "codex"
        case .claudeCode: "claude"
        case .opencode: "opencode"
        case .pi: "pi"
        }
    }

    /// OpenCode 2 uses a different client/server API and does not expose the v1
    /// `session list` / `export` boundary used by this app. Detect only the supported stable CLI
    /// until a dedicated v2 collector/provider is implemented.
    var executableNames: [String] {
        [executableName]
    }

    var systemImage: String {
        switch self {
        case .codex: "terminal"
        case .claudeCode: "sparkles"
        case .opencode: "chevron.left.forwardslash.chevron.right"
        case .pi: "circle.hexagongrid"
        }
    }

    var modelHint: String {
        switch self {
        case .codex: "例: gpt-5.5（空欄ならCodexの既定値）"
        case .claudeCode: "例: sonnet または claude-sonnet-4-5（空欄なら既定値）"
        case .opencode: "例: anthropic/claude-sonnet-4-5（provider/model）"
        case .pi: "例: openai/gpt-5.5 またはモデルID"
        }
    }

    var reasoningHint: String {
        switch self {
        case .codex: "minimal / low / medium / high / xhigh / none"
        case .claudeCode: "low / medium / high / max / xhigh（CLIのバージョン依存）"
        case .opencode: "モデルに存在するvariant名（モデル依存）"
        case .pi: "off / minimal / low / medium / high / xhigh / max"
        }
    }
}

struct CLIStatus: Equatable, Sendable {
    let kind: CLIKind
    let executablePath: String?
    let version: String?
    let logDirectory: String
    let canReadLogs: Bool

    var isInstalled: Bool { executablePath != nil }
}
