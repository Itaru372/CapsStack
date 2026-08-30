import Foundation

protocol CLIResolving: Sendable {
    func executableURL(for kind: CLIKind, override: String?) -> URL?
    func status(for kind: CLIKind, override: String?) -> CLIStatus
    func logDirectory(for kind: CLIKind) -> URL
}

/// Applies environment-aware defaults and a one-time compatibility migration, without taking
/// ownership of the user's settings.
///
/// The old registration defaults enabled both Codex and Claude Code unconditionally and selected
/// Codex as the summarizer. That made a machine with only one of those tools look partially
/// broken on every away interval. This bootstrap runs before the app registers its fallback
/// defaults, checks the persistent/volatile domains to distinguish an explicit choice from a
/// missing value, and only fills in values that have never been set.
enum CLIInitialPreferences {
    private static let currentVersion = 3

    static func applyIfNeeded(defaults: UserDefaults, resolver: CLIResolving) {
        let storedMarker = defaults.object(forKey: PreferenceKeys.cliDefaultsInitialized)
        guard defaults.integer(forKey: PreferenceKeys.cliDefaultsInitialized) < currentVersion else {
            return
        }

        let statuses = Dictionary(uniqueKeysWithValues: CLIKind.allCases.map { kind in
            (kind, resolver.status(for: kind, override: executableOverride(for: kind, defaults: defaults)))
        })

        if storedMarker != nil, defaults.bool(forKey: PreferenceKeys.cliDefaultsInitialized) {
            // Version 1 wrote only a Boolean marker and could leave the old unconditional
            // Codex/Claude collector selection behind. Reconcile that one legacy state without
            // changing an explicitly disabled source or any source that still has usable data.
            disableUnavailableCollectors(defaults: defaults, statuses: statuses)
            defaults.set(currentVersion, forKey: PreferenceKeys.cliDefaultsInitialized)
            return
        }

        // If any collector preference already exists, the user has configured this part of the
        // app (or is upgrading from an older release). Preserve that configuration wholesale so
        // adding a new source such as GitHub Copilot cannot silently enable it. Only a truly fresh
        // collector configuration receives environment-aware defaults.
        let hasExplicitCollectorConfiguration = collectorKeys.contains { _, key in
            hasStoredValue(forKey: key, in: defaults)
        }
        if !hasExplicitCollectorConfiguration {
            for (kind, key) in collectorKeys {
                let status = statuses[kind]
                // A CLI may be absent while its local archive is still useful (for example after
                // an uninstall). Conversely, an installed CLI with no archive yet is worth
                // enabling so the next run is captured without another settings visit.
                let enabled = status?.isInstalled == true || status?.canReadLogs == true
                defaults.set(enabled, forKey: key)
            }
        }

        if !hasStoredValue(forKey: PreferenceKeys.primarySummarizer, in: defaults) {
            let preferred = CLIKind.summarizerCases.first { statuses[$0]?.isInstalled == true }
            // CLIKind is intentionally non-optional for persisted/history compatibility. When no
            // summarizer is installed, retain the stable legacy value; the orchestrator reports a
            // clear `.noProviderAvailable` error instead of attempting unrelated CLIs.
            defaults.set((preferred ?? .codex).rawValue, forKey: PreferenceKeys.primarySummarizer)
        }

        defaults.set(currentVersion, forKey: PreferenceKeys.cliDefaultsInitialized)
    }

    private static func executableOverride(for kind: CLIKind, defaults: UserDefaults) -> String? {
        let key: String?
        switch kind {
        case .codex: key = PreferenceKeys.codexExecutablePath
        case .claudeCode: key = PreferenceKeys.claudeExecutablePath
        case .opencode: key = PreferenceKeys.opencodeExecutablePath
        case .pi: key = PreferenceKeys.piExecutablePath
        case .githubCopilot: key = PreferenceKeys.copilotExecutablePath
        case .kiloCode: key = PreferenceKeys.kiloExecutablePath
        case .goose: key = PreferenceKeys.gooseExecutablePath
        case .qwenCode: key = PreferenceKeys.qwenExecutablePath
        case .continueCLI: key = PreferenceKeys.continueExecutablePath
        case .geminiCLI: key = nil
        }
        guard let key,
              let value = defaults.string(forKey: key),
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return value
    }

    private static func disableUnavailableCollectors(
        defaults: UserDefaults,
        statuses: [CLIKind: CLIStatus]
    ) {
        for (kind, key) in collectorKeys {
            guard defaults.bool(forKey: key), let status = statuses[kind] else { continue }
            guard status.isInstalled || status.canReadLogs else {
                defaults.set(false, forKey: key)
                continue
            }
        }
    }

    private static let collectorKeys: [(CLIKind, String)] = [
        (.codex, PreferenceKeys.collectCodex),
        (.claudeCode, PreferenceKeys.collectClaude),
        (.opencode, PreferenceKeys.collectOpenCode),
        (.pi, PreferenceKeys.collectPi),
        (.githubCopilot, PreferenceKeys.collectGitHubCopilot),
        (.kiloCode, PreferenceKeys.collectKilo),
        (.goose, PreferenceKeys.collectGoose),
        (.qwenCode, PreferenceKeys.collectQwen),
        (.continueCLI, PreferenceKeys.collectContinue),
        (.geminiCLI, PreferenceKeys.collectGemini)
    ]

    /// `UserDefaults` registration values are process-wide and can already be present when a
    /// separate suite is initialized (notably in tests and previews). Temporarily mask only the
    /// requested registration fallback so `object(forKey:)` can distinguish it from a value the
    /// user actually stored.
    private static func hasStoredValue(forKey key: String, in defaults: UserDefaults) -> Bool {
        let registration = defaults.volatileDomain(forName: UserDefaults.registrationDomain)
        guard registration[key] != nil else {
            return defaults.object(forKey: key) != nil
        }

        var maskedRegistration = registration
        maskedRegistration.removeValue(forKey: key)
        defaults.setVolatileDomain(maskedRegistration, forName: UserDefaults.registrationDomain)
        defer {
            defaults.setVolatileDomain(registration, forName: UserDefaults.registrationDomain)
        }
        return defaults.object(forKey: key) != nil
    }
}

/// Resolves CLI executables without invoking a login shell.
struct CLIResolver: CLIResolving, @unchecked Sendable {
    private let fileManager: FileManager
    private let homeDirectory: URL
    private let environment: [String: String]

    init(
        fileManager: FileManager = .default,
        homeDirectory: URL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true),
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.fileManager = fileManager
        self.homeDirectory = homeDirectory
        self.environment = environment
    }

    func executableURL(for kind: CLIKind, override: String? = nil) -> URL? {
        let requested = override?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let requested, !requested.isEmpty {
            if requested.contains("/") {
                let url = URL(fileURLWithPath: requested).standardizedFileURL
                return fileManager.isExecutableFile(atPath: url.path) ? url : nil
            }
            if let found = findOnPath(requested) { return found }
        }

        for name in kind.executableNames {
            if let found = findOnPath(name) { return found }
        }

        // GUI-launched apps often receive a much smaller PATH than a terminal. These are
        // common locations for Homebrew, npm, and user-installed CLIs on macOS.
        let conventionalPaths = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            homeDirectory.appendingPathComponent(".local/bin").path,
            homeDirectory.appendingPathComponent(".npm-global/bin").path,
            homeDirectory.appendingPathComponent(".bun/bin").path,
            homeDirectory.appendingPathComponent(".pnpm").path,
            homeDirectory.appendingPathComponent(".yarn/bin").path,
            homeDirectory.appendingPathComponent("Library/pnpm").path,
            homeDirectory.appendingPathComponent(".volta/bin").path,
            homeDirectory.appendingPathComponent(".nvm/current/bin").path
        ]
        for directory in conventionalPaths {
            for name in kind.executableNames {
                let url = URL(fileURLWithPath: directory, isDirectory: true)
                    .appendingPathComponent(name)
                if fileManager.isExecutableFile(atPath: url.path) { return url }
            }
        }
        return nil
    }

    func status(for kind: CLIKind, override: String? = nil) -> CLIStatus {
        let path = executableURL(for: kind, override: override)
        let logURL = logDirectory(for: kind)
        var isDirectory = ObjCBool(false)
        let canRead = fileManager.fileExists(atPath: logURL.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
            && fileManager.isReadableFile(atPath: logURL.path)
        return CLIStatus(
            kind: kind,
            executablePath: path?.path,
            version: nil,
            logDirectory: logURL.path,
            canReadLogs: canRead
        )
    }

    func logDirectory(for kind: CLIKind) -> URL {
        switch kind {
        case .codex:
            return (environmentDirectory("CODEX_HOME")
                ?? homeDirectory.appendingPathComponent(".codex", isDirectory: true))
                .appendingPathComponent("sessions", isDirectory: true)
        case .claudeCode:
            return (environmentDirectory("CLAUDE_CONFIG_DIR")
                ?? homeDirectory.appendingPathComponent(".claude", isDirectory: true))
                .appendingPathComponent("projects", isDirectory: true)
        case .opencode:
            return (environmentDirectory("XDG_DATA_HOME")
                ?? homeDirectory
                    .appendingPathComponent(".local", isDirectory: true)
                    .appendingPathComponent("share", isDirectory: true))
                .appendingPathComponent("opencode", isDirectory: true)
        case .pi:
            return environmentDirectory("PI_CODING_AGENT_SESSION_DIR")
                ?? homeDirectory
                    .appendingPathComponent(".pi", isDirectory: true)
                    .appendingPathComponent("agent", isDirectory: true)
                    .appendingPathComponent("sessions", isDirectory: true)
        case .githubCopilot:
            return (environmentDirectory("COPILOT_HOME")
                ?? homeDirectory.appendingPathComponent(".copilot", isDirectory: true))
                .appendingPathComponent("session-state", isDirectory: true)
        case .kiloCode:
            return (environmentDirectory("XDG_DATA_HOME")
                ?? homeDirectory.appendingPathComponent(".local/share", isDirectory: true))
                .appendingPathComponent("kilo", isDirectory: true)
        case .goose:
            return (environmentDirectory("XDG_DATA_HOME")
                ?? homeDirectory.appendingPathComponent(".local/share", isDirectory: true))
                .appendingPathComponent("goose/sessions", isDirectory: true)
        case .qwenCode:
            let runtimeRoot = environmentDirectory("QWEN_RUNTIME_DIR")
                ?? environmentDirectory("QWEN_HOME")
                ?? homeDirectory.appendingPathComponent(".qwen", isDirectory: true)
            // Current Qwen stores chats below projects/, while older compatible releases used
            // tmp/<project-hash>/. The Qwen collector restricts this root to those subdirectories
            // so settings and credentials at the runtime root are never treated as transcripts.
            return runtimeRoot
        case .continueCLI:
            return homeDirectory
                .appendingPathComponent(".continue", isDirectory: true)
                .appendingPathComponent("sessions", isDirectory: true)
        case .geminiCLI:
            return (environmentDirectory("GEMINI_CLI_HOME") ?? homeDirectory)
                .appendingPathComponent(".gemini", isDirectory: true)
                .appendingPathComponent("tmp", isDirectory: true)
        }
    }

    private func environmentDirectory(_ key: String) -> URL? {
        guard let value = environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        return URL(
            fileURLWithPath: (value as NSString).expandingTildeInPath,
            isDirectory: true
        ).standardizedFileURL
    }

    private func findOnPath(_ name: String) -> URL? {
        let path = environment["PATH"] ?? ""
        for component in path.split(separator: ":", omittingEmptySubsequences: true) {
            let directory = String(component)
            let url = URL(fileURLWithPath: directory, isDirectory: true)
                .appendingPathComponent(name)
            if fileManager.isExecutableFile(atPath: url.path) { return url }
        }
        return nil
    }
}
