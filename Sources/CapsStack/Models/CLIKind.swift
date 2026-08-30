import Foundation

enum CLIKind: String, Codable, CaseIterable, Identifiable, Sendable {
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

    var id: String { rawValue }

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

    var executableName: String {
        switch self {
        case .codex: "codex"
        case .claudeCode: "claude"
        case .opencode: "opencode"
        case .pi: "pi"
        case .githubCopilot: "copilot"
        case .kiloCode: "kilo"
        case .goose: "goose"
        case .qwenCode: "qwen"
        case .continueCLI: "cn"
        case .geminiCLI: "gemini"
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
        case .githubCopilot: "chevron.left.forwardslash.chevron.right"
        case .kiloCode: "k.square"
        case .goose: "bird"
        case .qwenCode: "q.square"
        case .continueCLI: "arrow.forward.circle"
        case .geminiCLI: "sparkles.square.filled.on.square"
        }
    }

    var modelHint: String {
        switch self {
        case .codex: "例: gpt-5.5（空欄ならCodexの既定値）"
        case .claudeCode: "例: sonnet または claude-sonnet-4-5（空欄なら既定値）"
        case .opencode: "例: anthropic/claude-sonnet-4-5（provider/model）"
        case .pi: "例: openai/gpt-5.5 またはモデルID"
        case .githubCopilot: "例: gpt-5.4（空欄ならCopilotの既定値）"
        case .kiloCode: "例: anthropic/claude-sonnet-4-6（空欄なら既定値）"
        case .goose: "例: claude-sonnet-4-6（空欄ならGooseの既定値）"
        case .qwenCode: "例: qwen3-coder-plus（空欄なら既定値）"
        case .continueCLI: "例: claude-sonnet-4-6（空欄なら既定値）"
        case .geminiCLI: "収集専用（要約担当には使用しません）"
        }
    }

    var reasoningHint: String {
        switch self {
        case .codex: "minimal / low / medium / high / xhigh / none"
        case .claudeCode: "low / medium / high / max / xhigh（CLIのバージョン依存）"
        case .opencode: "モデルに存在するvariant名（モデル依存）"
        case .pi: "off / minimal / low / medium / high / xhigh / max"
        case .githubCopilot: "low / medium / high / xhigh / max"
        case .kiloCode: "要約時はAsk agentを使用（推論指定なし）"
        case .goose: "要約時はChat modeを使用（推論指定なし）"
        case .qwenCode: "モデル側の既定値（推論指定なし）"
        case .continueCLI: "モデル側の既定値（推論指定なし）"
        case .geminiCLI: "収集専用（要約担当には使用しません）"
        }
    }

    var supportsCollection: Bool { true }

    var supportsSummarization: Bool {
        self != .geminiCLI && self != .continueCLI
    }

    /// Images are bundled from each project's official site or official GitHub repository so
    /// settings remain useful offline and do not leak launches to third-party image hosts.
    var artworkResourceName: String? {
        switch self {
        case .kiloCode: "AgentKilo"
        case .goose: "AgentGoose"
        case .qwenCode: "AgentQwen"
        case .continueCLI: "AgentContinue"
        case .geminiCLI: "AgentGemini"
        default: nil
        }
    }

    static var collectorCases: [CLIKind] {
        allCases.filter(\.supportsCollection)
    }

    static var summarizerCases: [CLIKind] {
        allCases.filter(\.supportsSummarization)
    }

    var supportsReasoningOverride: Bool {
        switch self {
        case .codex, .claudeCode, .opencode, .pi, .githubCopilot: true
        default: false
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
