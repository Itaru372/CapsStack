import CapsStackLocalization
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
        case .codex: CapsStackText.resolve(.cliDesktopIDE)
        case .opencode: CapsStackText.resolve(.cliDesktopIDEOfficialExport)
        default: CapsStackText.resolve(.cli)
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
        case .codex: CapsStackText.resolve(.codexModelHint)
        case .claudeCode: CapsStackText.resolve(.claudeModelHint)
        case .opencode: CapsStackText.resolve(.opencodeModelHint)
        case .pi: CapsStackText.resolve(.piModelHint)
        case .githubCopilot: CapsStackText.resolve(.copilotModelHint)
        case .kiloCode: CapsStackText.resolve(.kiloModelHint)
        case .goose: CapsStackText.resolve(.gooseModelHint)
        case .qwenCode: CapsStackText.resolve(.qwenModelHint)
        case .continueCLI: CapsStackText.resolve(.continueModelHint)
        case .geminiCLI: CapsStackText.resolve(.collectionOnly)
        }
    }

    var reasoningHint: String {
        switch self {
        case .codex: CapsStackText.resolve(.codexReasoningHint)
        case .claudeCode: CapsStackText.resolve(.claudeReasoningHint)
        case .opencode: CapsStackText.resolve(.opencodeReasoningHint)
        case .pi: CapsStackText.resolve(.piReasoningHint)
        case .githubCopilot: CapsStackText.resolve(.copilotReasoningHint)
        case .kiloCode: CapsStackText.resolve(.kiloReasoningHint)
        case .goose: CapsStackText.resolve(.gooseReasoningHint)
        case .qwenCode: CapsStackText.resolve(.modelDefaultReasoningHint)
        case .continueCLI: CapsStackText.resolve(.modelDefaultReasoningHint)
        case .geminiCLI: CapsStackText.resolve(.collectionOnly)
        }
    }

    var supportsCollection: Bool { true }

    var supportsSummarization: Bool {
        // Kilo's public non-interactive CLI contract has no tool-deny, read-only, or
        // customization-isolation flag. Treat it as collection-only until that boundary is
        // available rather than relying on an agent name such as `ask` for safety.
        self != .geminiCLI && self != .continueCLI && self != .kiloCode
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
        case .codex, .opencode, .pi:
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
            return CapsStackText.resolve(.openCodeDesktopRequiresCLI)
        }

        var detected: [String] = []
        if isInstalled { detected.append(CapsStackText.resolve(.cli)) }
        if isDesktopAppInstalled { detected.append(CapsStackText.resolve(.desktop)) }
        if canReadLogs { detected.append(CapsStackText.resolve(.history)) }
        let detectedText = detected.isEmpty
            ? CapsStackText.resolve(.notDetected)
            : CapsStackText.format(.detectedSources, detected.joined(separator: " / "))

        if kind == .opencode, isInstalled {
            return CapsStackText.format(.collectionStatus, kind.collectionClientDescription, detectedText)
        }
        if kind == .codex {
            return CapsStackText.format(.collectionStatus, kind.collectionClientDescription, detectedText)
        }
        return detectedText
    }
}
