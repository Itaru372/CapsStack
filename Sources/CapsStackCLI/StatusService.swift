import Foundation

struct CLIAgentStatus: Encodable, Equatable {
    let name: String
    let executable: String
    let path: String?
    var isAvailable: Bool { path != nil }

    enum CodingKeys: String, CodingKey {
        case name
        case executable
        case path
        case isAvailable
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(executable, forKey: .executable)
        try container.encode(path, forKey: .path)
        try container.encode(isAvailable, forKey: .isAvailable)
    }
}

struct CLIStatusReport: Encodable, Equatable {
    let historyPath: String
    let historyExists: Bool
    let historyCount: Int
    let hasMemo: Bool
    let agents: [CLIAgentStatus]
}

enum CLIStatusService {
    private static let agents: [(String, String)] = [
        ("Codex CLI", "codex"),
        ("Claude Code CLI", "claude"),
        ("OpenCode CLI", "opencode"),
        ("OpenCode 2 CLI", "opencode2"),
        ("Pi coding agent", "pi")
    ]

    static func report(
        history: CLIHistoryRepository,
        memo: CLIMemoStore,
        path: String,
        fileManager: FileManager = .default
    ) throws -> CLIStatusReport {
        let entries = try history.load()
        return CLIStatusReport(
            historyPath: history.historyURL.path,
            historyExists: history.exists,
            historyCount: entries.count,
            hasMemo: memo.get() != nil,
            agents: agents.map { name, executable in
                CLIAgentStatus(
                    name: name,
                    executable: executable,
                    path: executablePath(executable, path: path, fileManager: fileManager)
                )
            }
        )
    }

    private static func executablePath(_ executable: String, path: String, fileManager: FileManager) -> String? {
        for directory in path.split(separator: ":", omittingEmptySubsequences: true) {
            let candidate = URL(fileURLWithPath: String(directory), isDirectory: true)
                .appendingPathComponent(executable).path
            if fileManager.isExecutableFile(atPath: candidate) { return candidate }
        }
        return nil
    }
}
