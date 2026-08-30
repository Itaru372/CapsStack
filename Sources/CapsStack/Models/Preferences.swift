import Foundation

enum PreferenceKeys {
    static let capsStackEnabled = "capsStackEnabled"
    static let keepRunningInBackground = "keepRunningInBackground"
    static let suppressOriginalCapsLock = "suppressOriginalCapsLock"
    static let collectCodex = "collectCodex"
    static let collectClaude = "collectClaude"
    static let collectOpenCode = "collectOpenCode"
    static let collectPi = "collectPi"
    static let collectGitHubCopilot = "collectGitHubCopilot"
    static let collectKilo = "collectKilo"
    static let collectGoose = "collectGoose"
    static let collectQwen = "collectQwen"
    static let collectContinue = "collectContinue"
    static let collectGemini = "collectGemini"
    static let primarySummarizer = "primarySummarizer"
    static let automaticFallback = "automaticFallback"
    static let codexExecutablePath = "codexExecutablePath"
    static let claudeExecutablePath = "claudeExecutablePath"
    static let opencodeExecutablePath = "opencodeExecutablePath"
    static let piExecutablePath = "piExecutablePath"
    static let copilotExecutablePath = "copilotExecutablePath"
    static let kiloExecutablePath = "kiloExecutablePath"
    static let gooseExecutablePath = "gooseExecutablePath"
    static let qwenExecutablePath = "qwenExecutablePath"
    static let continueExecutablePath = "continueExecutablePath"
    static let codexModel = "codexModel"
    static let claudeModel = "claudeModel"
    static let opencodeModel = "opencodeModel"
    static let piModel = "piModel"
    static let copilotModel = "copilotModel"
    static let kiloModel = "kiloModel"
    static let gooseModel = "gooseModel"
    static let qwenModel = "qwenModel"
    static let continueModel = "continueModel"
    static let codexReasoning = "codexReasoning"
    static let claudeReasoning = "claudeReasoning"
    static let opencodeReasoning = "opencodeReasoning"
    static let piReasoning = "piReasoning"
    static let copilotReasoning = "copilotReasoning"
    static let awayStart = "awayStart"
    static let minimumAwayDuration = "minimumAwayDuration"
    static let quickMemo = "quickMemo"
    static let telemetryEnabled = "telemetryEnabled"
    static let setupCompleted = "setupCompleted"
    /// Stores the version of the one-time CLI auto-configuration performed by AppController.
    ///
    /// This is intentionally persisted separately from the registered defaults. Registered
    /// values are only fallbacks and cannot tell whether a user explicitly changed a setting.
    static let cliDefaultsInitialized = "cliDefaultsInitialized"
}

/// Registers the app's UserDefaults domain once per UserDefaults instance. Calling
/// `register(defaults:)` from every preference read emits `UserDefaults.didChangeNotification`
/// on macOS; AppController observes that notification, so repeated reads can otherwise recurse
/// indefinitely while the settings/menu-bar scenes are open.
private enum PreferenceDefaults {
    private static let registrationMarker = "CapsStack.preferenceDefaultsRegistered"

    static func register(on defaults: UserDefaults) {
        guard defaults.object(forKey: registrationMarker) == nil else { return }

        defaults.register(defaults: [
            registrationMarker: true,
            PreferenceKeys.capsStackEnabled: true,
            PreferenceKeys.keepRunningInBackground: true,
            PreferenceKeys.suppressOriginalCapsLock: false,
            // CLI preferences are initialized from the local environment on first launch. Do not
            // register them here: the registration domain is shared by UserDefaults instances,
            // and a static CLI choice would make an unrelated test suite or app context inherit
            // a Codex/Claude dependency. Preference structs provide safe empty/fallback values
            // until `CLIInitialPreferences` persists the detected configuration.
            PreferenceKeys.automaticFallback: true,
            PreferenceKeys.minimumAwayDuration: 0,
            PreferenceKeys.setupCompleted: false,
            // Product analytics is an explicit opt-in and remains disabled by default.
            PreferenceKeys.telemetryEnabled: false
        ])
    }
}

/// Controls the optional anonymous product analytics integration. This preference never grants
/// access to session content: it only enables the reviewed event vocabulary in TelemetryEvent.
struct TelemetryPreferences: Equatable, Sendable {
    var isEnabled: Bool

    init(defaults: UserDefaults = .standard) {
        PreferenceDefaults.register(on: defaults)
        isEnabled = defaults.object(forKey: PreferenceKeys.telemetryEnabled) as? Bool ?? false
    }

    init(isEnabled: Bool) {
        self.isEnabled = isEnabled
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(isEnabled, forKey: PreferenceKeys.telemetryEnabled)
    }
}

/// Minimum seconds Caps Lock must stay ON before a summary is attempted.
struct AwayThresholdPreferences: Equatable, Sendable {
    var minimumAwaySeconds: Int

    static let `default` = AwayThresholdPreferences(minimumAwaySeconds: 0)

    init(defaults: UserDefaults = .standard) {
        PreferenceDefaults.register(on: defaults)
        let stored = defaults.integer(forKey: PreferenceKeys.minimumAwayDuration)
        self.init(minimumAwaySeconds: max(0, min(stored, 3600)))
    }

    init(minimumAwaySeconds: Int) {
        self.minimumAwaySeconds = max(0, min(max(0, minimumAwaySeconds), 3600))
    }
}

/// A user-written note captured before stepping away. GUI agents do not leave JSONL logs,
/// so this note is the only supplementary input for those sessions during summarization.
struct QuickMemoPreferences: Equatable, Sendable {
    static let maximumUTF8Bytes = 32 * 1_024
    var text: String

    init(text: String = "") {
        self.text = Self.boundedText(text)
    }

    init(defaults: UserDefaults = .standard) {
        self.init(text: defaults.string(forKey: PreferenceKeys.quickMemo) ?? "")
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(trimmedText ?? "", forKey: PreferenceKeys.quickMemo)
    }

    var trimmedText: String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func boundedText(_ value: String) -> String {
        let data = Data(value.utf8)
        guard data.count > maximumUTF8Bytes else { return value }
        var end = maximumUTF8Bytes
        while end > 0 {
            if let result = String(data: data.prefix(end), encoding: .utf8) {
                return result
            }
            end -= 1
        }
        return ""
    }
}

struct CapsStackFeaturePreferences: Equatable, Sendable {
    var isEnabled: Bool
    var keepRunningInBackground: Bool
    var suppressOriginalCapsLock: Bool

    init(defaults: UserDefaults = .standard) {
        PreferenceDefaults.register(on: defaults)
        isEnabled = defaults.object(forKey: PreferenceKeys.capsStackEnabled) as? Bool ?? true
        keepRunningInBackground = defaults.object(forKey: PreferenceKeys.keepRunningInBackground) as? Bool ?? true
        suppressOriginalCapsLock = defaults.object(forKey: PreferenceKeys.suppressOriginalCapsLock) as? Bool ?? false
    }

    init(isEnabled: Bool, keepRunningInBackground: Bool, suppressOriginalCapsLock: Bool = false) {
        self.isEnabled = isEnabled
        self.keepRunningInBackground = keepRunningInBackground
        self.suppressOriginalCapsLock = suppressOriginalCapsLock
    }
}

struct CollectorPreferences: Equatable, Sendable {
    var enabledSources: Set<CLIKind>

    init(defaults: UserDefaults = .standard) {
        PreferenceDefaults.register(on: defaults)
        var sources = Set<CLIKind>()
        if defaults.bool(forKey: PreferenceKeys.collectCodex) { sources.insert(.codex) }
        if defaults.bool(forKey: PreferenceKeys.collectClaude) { sources.insert(.claudeCode) }
        if defaults.bool(forKey: PreferenceKeys.collectOpenCode) { sources.insert(.opencode) }
        if defaults.bool(forKey: PreferenceKeys.collectPi) { sources.insert(.pi) }
        if defaults.bool(forKey: PreferenceKeys.collectGitHubCopilot) { sources.insert(.githubCopilot) }
        if defaults.bool(forKey: PreferenceKeys.collectKilo) { sources.insert(.kiloCode) }
        if defaults.bool(forKey: PreferenceKeys.collectGoose) { sources.insert(.goose) }
        if defaults.bool(forKey: PreferenceKeys.collectQwen) { sources.insert(.qwenCode) }
        if defaults.bool(forKey: PreferenceKeys.collectContinue) { sources.insert(.continueCLI) }
        if defaults.bool(forKey: PreferenceKeys.collectGemini) { sources.insert(.geminiCLI) }
        enabledSources = sources
    }

    init(enabledSources: Set<CLIKind>) {
        self.enabledSources = enabledSources
    }
}

struct SummarizerPreferences: Equatable, Sendable {
    var primary: CLIKind
    var automaticFallback: Bool
    var executableOverrides: [CLIKind: String]
    var modelOverrides: [CLIKind: String]
    var reasoningOverrides: [CLIKind: String]

    init(defaults: UserDefaults = .standard) {
        PreferenceDefaults.register(on: defaults)
        let storedPrimary = CLIKind(
            rawValue: defaults.string(forKey: PreferenceKeys.primarySummarizer) ?? ""
        )
        // Keep the persisted model non-optional for history compatibility. AppController
        // bootstraps this value from detected CLIs, and the orchestrator never invokes this
        // compatibility fallback unless no usable provider was selected.
        primary = storedPrimary?.supportsSummarization == true ? storedPrimary ?? .codex : .codex
        automaticFallback = defaults.object(forKey: PreferenceKeys.automaticFallback) as? Bool ?? true
        executableOverrides = [
            .codex: defaults.string(forKey: PreferenceKeys.codexExecutablePath) ?? "",
            .claudeCode: defaults.string(forKey: PreferenceKeys.claudeExecutablePath) ?? "",
            .opencode: defaults.string(forKey: PreferenceKeys.opencodeExecutablePath) ?? "",
            .pi: defaults.string(forKey: PreferenceKeys.piExecutablePath) ?? "",
            .githubCopilot: defaults.string(forKey: PreferenceKeys.copilotExecutablePath) ?? "",
            .kiloCode: defaults.string(forKey: PreferenceKeys.kiloExecutablePath) ?? "",
            .goose: defaults.string(forKey: PreferenceKeys.gooseExecutablePath) ?? "",
            .qwenCode: defaults.string(forKey: PreferenceKeys.qwenExecutablePath) ?? "",
            .continueCLI: defaults.string(forKey: PreferenceKeys.continueExecutablePath) ?? ""
        ]
        modelOverrides = [
            .codex: defaults.string(forKey: PreferenceKeys.codexModel) ?? "",
            .claudeCode: defaults.string(forKey: PreferenceKeys.claudeModel) ?? "",
            .opencode: defaults.string(forKey: PreferenceKeys.opencodeModel) ?? "",
            .pi: defaults.string(forKey: PreferenceKeys.piModel) ?? "",
            .githubCopilot: defaults.string(forKey: PreferenceKeys.copilotModel) ?? "",
            .kiloCode: defaults.string(forKey: PreferenceKeys.kiloModel) ?? "",
            .goose: defaults.string(forKey: PreferenceKeys.gooseModel) ?? "",
            .qwenCode: defaults.string(forKey: PreferenceKeys.qwenModel) ?? "",
            .continueCLI: defaults.string(forKey: PreferenceKeys.continueModel) ?? ""
        ]
        reasoningOverrides = [
            .codex: defaults.string(forKey: PreferenceKeys.codexReasoning) ?? "",
            .claudeCode: defaults.string(forKey: PreferenceKeys.claudeReasoning) ?? "",
            .opencode: defaults.string(forKey: PreferenceKeys.opencodeReasoning) ?? "",
            .pi: defaults.string(forKey: PreferenceKeys.piReasoning) ?? "",
            .githubCopilot: defaults.string(forKey: PreferenceKeys.copilotReasoning) ?? ""
        ]
    }

    init(
        primary: CLIKind,
        automaticFallback: Bool,
        executableOverrides: [CLIKind: String] = [:],
        modelOverrides: [CLIKind: String] = [:],
        reasoningOverrides: [CLIKind: String] = [:]
    ) {
        self.primary = primary
        self.automaticFallback = automaticFallback
        self.executableOverrides = executableOverrides
        self.modelOverrides = modelOverrides
        self.reasoningOverrides = reasoningOverrides
    }

    func executableOverride(for kind: CLIKind) -> String? {
        normalizedValue(executableOverrides[kind])
    }

    func modelOverride(for kind: CLIKind) -> String? {
        normalizedValue(modelOverrides[kind])
    }

    func reasoningOverride(for kind: CLIKind) -> String? {
        normalizedValue(reasoningOverrides[kind])
    }

    private func normalizedValue(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }
}
