import Foundation

protocol CLIResolving: Sendable {
    func executableURL(for kind: CLIKind, override: String?) -> URL?
    func status(for kind: CLIKind, override: String?) -> CLIStatus
    func logDirectory(for kind: CLIKind) -> URL
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
        let canRead = fileManager.isReadableFile(atPath: logURL.path)
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
            return homeDirectory
                .appendingPathComponent(".codex", isDirectory: true)
                .appendingPathComponent("sessions", isDirectory: true)
        case .claudeCode:
            return homeDirectory
                .appendingPathComponent(".claude", isDirectory: true)
                .appendingPathComponent("projects", isDirectory: true)
        case .opencode:
            return homeDirectory
                .appendingPathComponent(".local", isDirectory: true)
                .appendingPathComponent("share", isDirectory: true)
                .appendingPathComponent("opencode", isDirectory: true)
        case .pi:
            return homeDirectory
                .appendingPathComponent(".pi", isDirectory: true)
                .appendingPathComponent("agent", isDirectory: true)
                .appendingPathComponent("sessions", isDirectory: true)
        }
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
