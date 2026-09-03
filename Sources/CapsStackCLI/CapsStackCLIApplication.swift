import Foundation

struct CLIResult: Equatable {
    let exitCode: Int32
    let stdout: String
    let stderr: String

    static func success(_ output: String = "") -> CLIResult {
        CLIResult(exitCode: 0, stdout: output, stderr: "")
    }
}

struct CLIMemoResponse: Encodable, Equatable {
    let memo: String?
    var hasMemo: Bool { memo != nil }

    enum CodingKeys: String, CodingKey { case memo, hasMemo }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let memo { try container.encode(memo, forKey: .memo) } else { try container.encodeNil(forKey: .memo) }
        try container.encode(hasMemo, forKey: .hasMemo)
    }
}

struct CapsStackCLIApplication {
    let history: CLIHistoryRepository
    let memo: CLIMemoStore
    let environment: [String: String]
    let version: String
    let readStandardInput: () throws -> String

    init(
        history: CLIHistoryRepository = CLIHistoryRepository(),
        memo: CLIMemoStore = CLIMemoStore(),
        environment: [String: String] = ProcessInfo.processInfo.environment,
        version: String = CapsStackCLIApplication.detectedVersion,
        readStandardInput: @escaping () throws -> String = {
            String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self)
        }
    ) {
        self.history = history
        self.memo = memo
        self.environment = environment
        self.version = version
        self.readStandardInput = readStandardInput
    }

    func run(arguments: [String]) -> CLIResult {
        let command: CLICommand
        do {
            command = try CLIArgumentParser.parse(arguments)
        } catch {
            return CLIResult(exitCode: 2, stdout: "", stderr: diagnostic(error) + "\n\n" + Self.helpText)
        }

        do {
            return try execute(command)
        } catch {
            return CLIResult(exitCode: 1, stdout: "", stderr: diagnostic(error))
        }
    }

    private func execute(_ command: CLICommand) throws -> CLIResult {
        switch command {
        case .help:
            return .success(Self.helpText)
        case .version:
            return .success("capsstack \(version)")
        case .status(let json):
            let report = try CLIStatusService.report(
                history: history,
                memo: memo,
                path: environment["PATH"] ?? ""
            )
            if json { return .success(try CLIFormatting.json(report)) }
            var lines = [
                "CapsStack status",
                "History: \(report.historyPath)",
                "History file: \(report.historyExists ? "present" : "missing") / \(report.historyCount) entries",
                "Away memo: \(report.hasMemo ? "present" : "none")",
                "Agent CLIs:"
            ]
            lines.append(contentsOf: report.agents.map {
                "  \($0.isAvailable ? "✓" : "-") \($0.executable)\($0.path.map { "  \($0)" } ?? "")"
            })
            return .success(lines.joined(separator: "\n"))
        case .historyList(let limit, let json):
            let entries = try history.load()
            let selected = limit.map { Array(entries.prefix($0)) } ?? entries
            if json { return .success(try CLIFormatting.json(selected)) }
            return .success(selected.isEmpty ? "No history yet." : selected.map(CLIFormatting.listLine).joined(separator: "\n"))
        case .historyLatest(let mode):
            return try render(history.latest(), mode: mode)
        case .historyShow(let id, let mode):
            return try render(history.entry(id: id), mode: mode)
        case .memoGet(let json):
            return try renderMemo(memo.get(), json: json)
        case .memoSet(let text, let stdin, let json):
            let value = stdin ? try readStandardInput() : (text ?? "")
            memo.set(value)
            return try renderMemo(memo.get(), json: json)
        case .memoClear(let json):
            memo.clear()
            return try renderMemo(nil, json: json, cleared: true)
        }
    }

    private func render(_ entry: CLIHistoryEntry, mode: CLIOutputMode) throws -> CLIResult {
        switch mode {
        case .human: return .success(CLIFormatting.human(entry))
        case .json: return .success(try CLIFormatting.json(entry))
        case .markdown: return .success(CLIFormatting.markdown(entry))
        }
    }

    private func renderMemo(_ value: String?, json: Bool, cleared: Bool = false) throws -> CLIResult {
        if json { return .success(try CLIFormatting.json(CLIMemoResponse(memo: value))) }
        if let value { return .success(value) }
        return .success(cleared ? "Away memo cleared." : "No away memo.")
    }

    private func diagnostic(_ error: Error) -> String {
        if let localized = error as? LocalizedError, let description = localized.errorDescription {
            return "error: \(description)"
        }
        return "error: \(error.localizedDescription)"
    }

    static var detectedVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.2.0"
    }

    static let helpText = """
    CapsStack CLI

    Usage:
      capsstack help
      capsstack version
      capsstack status [--json]
      capsstack history list [--limit N] [--json]
      capsstack history latest [--json|--markdown]
      capsstack history show <UUID> [--json|--markdown]
      capsstack memo get [--json]
      capsstack memo set <text> [--json]
      capsstack memo set --stdin [--json]
      capsstack memo clear [--json]

    Aliases:
      capsstack --help, capsstack -h, capsstack --version, capsstack -V
    """
}
