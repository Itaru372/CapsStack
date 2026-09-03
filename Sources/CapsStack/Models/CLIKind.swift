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

    /// Agent-facing name used when selecting and reporting collection sources. Collection can
    /// span terminal, desktop, and IDE clients, while `displayName` remains the exact CLI name
    /// used by the summarizer settings and errors.
    var collectionDisplayName: String {
        switch self {
        case .codex: "Codex"
        case .claudeCode: "Claude Code"
        case .opencode: "OpenCode"
        case .pi: "Pi coding agent"
        case .githubCopilot: "GitHub Copilot"
        case .kiloCode: "Kilo Code"
        case .goose: "Goose"
        case .qwenCode: "Qwen Code"
        case .continueCLI: "Continue"
        case .geminiCLI: "Gemini"
        }
    }

    var collectionClientDescription: String {
        switch self {
        case .codex: "CLI / Desktop / IDE"
        case .opencode: "CLI / Desktop / IDE (via official export)"
        default: "CLI"
        }
    }

    var desktopBundleIdentifier: String? {
        switch self {
        case .codex: "com.openai.codex"
        case .opencode: "ai.opencode.desktop"
        default: nil
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
        case .codex: "e.g. gpt-5.5 (leave blank for Codex's default)"
        case .claudeCode: "e.g. sonnet or claude-sonnet-4-5 (leave blank for the default)"
        case .opencode: "e.g. anthropic/claude-sonnet-4-5 (provider/model)"
        case .pi: "e.g. openai/gpt-5.5 or a model ID"
        case .githubCopilot: "e.g. gpt-5.4 (leave blank for Copilot's default)"
        case .kiloCode: "e.g. anthropic/claude-sonnet-4-6 (leave blank for the default)"
        case .goose: "e.g. claude-sonnet-4-6 (leave blank for Goose's default)"
        case .qwenCode: "e.g. qwen3-coder-plus (leave blank for the default)"
        case .continueCLI: "e.g. claude-sonnet-4-6 (leave blank for the default)"
        case .geminiCLI: "Collection only (not available as a summarizer)"
        }
    }

    var reasoningHint: String {
        switch self {
        case .codex: "minimal / low / medium / high / xhigh / none"
        case .claudeCode: "low / medium / high / max / xhigh (depends on the CLI version)"
        case .opencode: "A variant name supported by the selected model"
        case .pi: "off / minimal / low / medium / high / xhigh / max"
        case .githubCopilot: "low / medium / high / xhigh / max"
        case .kiloCode: "Uses the Ask agent for summaries (no reasoning override)"
        case .goose: "Uses Chat mode for summaries (no reasoning override)"
        case .qwenCode: "Uses the model's default (no reasoning override)"
        case .continueCLI: "Uses the model's default (no reasoning override)"
        case .geminiCLI: "Collection only (not available as a summarizer)"
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

    /// Whether this CLI exposes a documented, non-interactive model listing command that
    /// CapsStack can invoke without starting a session. CLIs without such a boundary keep the
    /// existing free-form model override so we do not invent or stale-cache a catalog for them.
    var supportsModelListing: Bool {
        switch self {
        case .codex, .opencode, .pi, .kiloCode:
            true
        default:
            false
        }
    }

    static var modelListingCases: [CLIKind] {
        allCases.filter(\.supportsModelListing)
    }
}

/// A model exposed by an installed CLI. The ID is the value passed back to that CLI; the optional
/// display name is only presentation metadata and is intentionally not persisted.
struct CLIModel: Equatable, Hashable, Identifiable, Sendable {
    let id: String
    let displayName: String

    init(id: String, displayName: String? = nil) {
        self.id = id
        let trimmedName = displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.displayName = trimmedName.isEmpty ? id : trimmedName
    }
}

enum CLIModelFetchState: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case failed
}

struct CLIStatus: Equatable, Sendable {
    let kind: CLIKind
    let executablePath: String?
    let version: String?
    let logDirectory: String
    let canReadLogs: Bool
    let isDesktopAppInstalled: Bool

    init(
        kind: CLIKind,
        executablePath: String?,
        version: String?,
        logDirectory: String,
        canReadLogs: Bool,
        isDesktopAppInstalled: Bool = false
    ) {
        self.kind = kind
        self.executablePath = executablePath
        self.version = version
        self.logDirectory = logDirectory
        self.canReadLogs = canReadLogs
        self.isDesktopAppInstalled = isDesktopAppInstalled
    }

    var isInstalled: Bool { executablePath != nil }

    /// OpenCode Desktop still needs its official CLI export command. Codex Desktop writes the
    /// same readable local session archive as the other Codex clients.
    var canCollect: Bool {
        switch kind {
        case .codex:
            isInstalled || canReadLogs || isDesktopAppInstalled
        case .opencode:
            isInstalled
        default:
            isInstalled || canReadLogs
        }
    }

    var collectionStatusDescription: String {
        if kind == .opencode, isDesktopAppInstalled, !isInstalled {
            return "Desktop detected · OpenCode CLI is required for collection"
        }

        var detected: [String] = []
        if isInstalled { detected.append("CLI") }
        if isDesktopAppInstalled { detected.append("Desktop") }
        if canReadLogs { detected.append("History") }
        let detectedText = detected.isEmpty ? "Not detected" : detected.joined(separator: " / ") + " detected"

        if kind == .opencode, isInstalled {
            return "\(kind.collectionClientDescription) · \(detectedText)"
        }
        if kind == .codex {
            return "\(kind.collectionClientDescription) · \(detectedText)"
        }
        return detectedText
    }
}
