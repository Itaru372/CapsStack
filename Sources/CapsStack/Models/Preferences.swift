import Foundation

enum PreferenceKeys {
    static let capsStackEnabled = "capsStackEnabled"
    static let keepRunningInBackground = "keepRunningInBackground"
    static let suppressOriginalCapsLock = "suppressOriginalCapsLock"
    static let collectCodex = "collectCodex"
    static let collectClaude = "collectClaude"
    static let collectOpenCode = "collectOpenCode"
    static let collectPi = "collectPi"
    static let primarySummarizer = "primarySummarizer"
    static let automaticFallback = "automaticFallback"
    static let codexExecutablePath = "codexExecutablePath"
    static let claudeExecutablePath = "claudeExecutablePath"
    static let opencodeExecutablePath = "opencodeExecutablePath"
    static let piExecutablePath = "piExecutablePath"
    static let codexModel = "codexModel"
    static let claudeModel = "claudeModel"
    static let opencodeModel = "opencodeModel"
    static let piModel = "piModel"
    static let codexReasoning = "codexReasoning"
    static let claudeReasoning = "claudeReasoning"
    static let opencodeReasoning = "opencodeReasoning"
    static let piReasoning = "piReasoning"
    static let awayStart = "awayStart"
    static let minimumAwayDuration = "minimumAwayDuration"
    static let quickMemo = "quickMemo"
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
            PreferenceKeys.collectCodex: true,
            PreferenceKeys.collectClaude: true,
            PreferenceKeys.collectOpenCode: false,
            PreferenceKeys.collectPi: false,
            PreferenceKeys.primarySummarizer: CLIKind.codex.rawValue,
            PreferenceKeys.automaticFallback: true,
            PreferenceKeys.minimumAwayDuration: 0
        ])
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
    var text: String

    init(text: String = "") {
        self.text = text
    }

    init(defaults: UserDefaults = .standard) {
        text = defaults.string(forKey: PreferenceKeys.quickMemo) ?? ""
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(trimmedText ?? "", forKey: PreferenceKeys.quickMemo)
    }

    var trimmedText: String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
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
        primary = CLIKind(rawValue: defaults.string(forKey: PreferenceKeys.primarySummarizer) ?? "") ?? .codex
        automaticFallback = defaults.bool(forKey: PreferenceKeys.automaticFallback)
        executableOverrides = [
            .codex: defaults.string(forKey: PreferenceKeys.codexExecutablePath) ?? "",
            .claudeCode: defaults.string(forKey: PreferenceKeys.claudeExecutablePath) ?? "",
            .opencode: defaults.string(forKey: PreferenceKeys.opencodeExecutablePath) ?? "",
            .pi: defaults.string(forKey: PreferenceKeys.piExecutablePath) ?? ""
        ]
        modelOverrides = [
            .codex: defaults.string(forKey: PreferenceKeys.codexModel) ?? "",
            .claudeCode: defaults.string(forKey: PreferenceKeys.claudeModel) ?? "",
            .opencode: defaults.string(forKey: PreferenceKeys.opencodeModel) ?? "",
            .pi: defaults.string(forKey: PreferenceKeys.piModel) ?? ""
        ]
        reasoningOverrides = [
            .codex: defaults.string(forKey: PreferenceKeys.codexReasoning) ?? "",
            .claudeCode: defaults.string(forKey: PreferenceKeys.claudeReasoning) ?? "",
            .opencode: defaults.string(forKey: PreferenceKeys.opencodeReasoning) ?? "",
            .pi: defaults.string(forKey: PreferenceKeys.piReasoning) ?? ""
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
