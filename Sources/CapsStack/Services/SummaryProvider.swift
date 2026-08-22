import Foundation

/// A provider receives a normalized collection artifact and returns only a structured summary.
/// Implementations never resume a source session and never use a source session's working
/// directory.
protocol SummaryProvider: AnyObject {
    var kind: CLIKind { get }
    func summarize(
        batch: CollectionBatch,
        executableOverride: String?,
        modelOverride: String?,
        reasoningOverride: String?
    ) async throws -> SummaryDocument
}

enum SummaryPromptFactory {
    static func prompt(for batch: CollectionBatch, provider: CLIKind) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let payload = try encoder.encode(batch)
        guard let payloadText = String(data: payload, encoding: .utf8) else {
            throw SummaryProviderError.invalidOutput(provider)
        }
        let text = """
        あなたはCapsStackの要約専用プロセスです。BEGIN_CAPSSTACK_ARTIFACTとEND_CAPSSTACK_ARTIFACTの間のJSONだけを読み、退席中の進捗を要約してください。
        コード変更、コマンド実行、ファイル探索、ネットワークアクセス、元セッションのresumeやcontinueは禁止です。
        ログにない事実は推測せず、不明な項目は空配列にしてください。
        次のキーをすべて持つJSONオブジェクトだけを返してください: overview, progress, currentState, decisions, blockers, nextSteps, sessions。
        sessionsの各要素はsessionID, source, summaryを持つ必要があります。Markdownフェンスや説明文は出力しないでください。

        BEGIN_CAPSSTACK_ARTIFACT
        \(payloadText)
        END_CAPSSTACK_ARTIFACT
        """
        return Data(text.utf8)
    }
}

final class CodexSummaryProvider: SummaryProvider {
    let kind: CLIKind = .codex
    private let resolver: CLIResolving
    private let runner: ProcessRunning
    private let timeout: TimeInterval
    private let fileManager: FileManager

    init(
        resolver: CLIResolving = CLIResolver(),
        runner: ProcessRunning = ProcessRunner(),
        timeout: TimeInterval = 120,
        fileManager: FileManager = .default
    ) {
        self.resolver = resolver
        self.runner = runner
        self.timeout = max(0.1, timeout)
        self.fileManager = fileManager
    }

    func summarize(
        batch: CollectionBatch,
        executableOverride: String? = nil,
        modelOverride: String? = nil,
        reasoningOverride: String? = nil
    ) async throws -> SummaryDocument {
        guard let executable = resolver.executableURL(for: .codex, override: executableOverride) else {
            throw SummaryProviderError.executableNotFound(.codex)
        }

        let tempDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("CapsStack-codex-\(UUID().uuidString)", isDirectory: true)
        do {
            try fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
            defer { try? fileManager.removeItem(at: tempDirectory) }

            let schemaURL = tempDirectory.appendingPathComponent("summary-schema.json")
            guard let schemaData = SummarySchema.json.data(using: .utf8) else {
                throw SummaryProviderError.invalidOutput(.codex)
            }
            try schemaData.write(to: schemaURL, options: .atomic)

            let input: Data
            do {
                input = try SummaryPromptFactory.prompt(for: batch, provider: .codex)
            } catch {
                throw SummaryProviderError.invalidOutput(.codex)
            }

            // Keep every input in stdin. The temporary cwd is not a source workspace and the
            // flags prevent repository checks, user config, and rule files from being loaded.
            var arguments = ["exec"]
            if let model = modelOverride?.trimmingCharacters(in: .whitespacesAndNewlines), !model.isEmpty {
                arguments += ["--model", model]
            }
            if let reasoning = reasoningOverride?.trimmingCharacters(in: .whitespacesAndNewlines), !reasoning.isEmpty {
                // Process receives argv directly, so shell quoting from CLI examples must not
                // be included in the value itself.
                arguments += ["--config", "model_reasoning_effort=\(reasoning)"]
            }
            arguments += [
                "--ephemeral",
                "--sandbox", "read-only",
                "--skip-git-repo-check",
                "--ignore-user-config",
                "--ignore-rules",
                "--output-schema", schemaURL.path
            ]

            let specification = ProcessSpecification(
                executableURL: executable,
                arguments: arguments,
                standardInput: input,
                currentDirectoryURL: tempDirectory
            )
            let result = try await run(specification, provider: .codex)
            guard result.succeeded else {
                throw SummaryProviderError.processFailed(
                    .codex,
                    Self.errorMessage(from: result, fallback: "終了コード \(result.terminationStatus)")
                )
            }
            guard let document = SummaryOutputParser.parse(
                stdout: result.standardOutput,
                provider: .codex
            ) else {
                throw SummaryProviderError.invalidOutput(.codex)
            }
            return document
        } catch let error as SummaryProviderError {
            throw error
        } catch {
            throw SummaryProviderError.processFailed(.codex, error.localizedDescription)
        }
    }

    private func run(_ specification: ProcessSpecification, provider: CLIKind) async throws -> ProcessResult {
        do {
            return try await runner.run(specification, timeout: timeout)
        } catch let error as ProcessRunnerError {
            switch error {
            case .timedOut:
                throw SummaryProviderError.timedOut(provider)
            default:
                throw SummaryProviderError.processFailed(provider, error.localizedDescription)
            }
        } catch {
            throw SummaryProviderError.processFailed(provider, error.localizedDescription)
        }
    }

    private static func errorMessage(from result: ProcessResult, fallback: String) -> String {
        let text = String(data: result.standardError, encoding: .utf8)
            ?? String(data: result.standardOutput, encoding: .utf8)
            ?? fallback
        return String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1_000))
    }
}

final class ClaudeCodeSummaryProvider: SummaryProvider {
    let kind: CLIKind = .claudeCode
    private let resolver: CLIResolving
    private let runner: ProcessRunning
    private let timeout: TimeInterval
    private let helpTimeout: TimeInterval
    private let fileManager: FileManager

    init(
        resolver: CLIResolving = CLIResolver(),
        runner: ProcessRunning = ProcessRunner(),
        timeout: TimeInterval = 120,
        helpTimeout: TimeInterval = 10,
        fileManager: FileManager = .default
    ) {
        self.resolver = resolver
        self.runner = runner
        self.timeout = max(0.1, timeout)
        self.helpTimeout = max(0.1, helpTimeout)
        self.fileManager = fileManager
    }

    func summarize(
        batch: CollectionBatch,
        executableOverride: String? = nil,
        modelOverride: String? = nil,
        reasoningOverride: String? = nil
    ) async throws -> SummaryDocument {
        guard let executable = resolver.executableURL(for: .claudeCode, override: executableOverride) else {
            throw SummaryProviderError.executableNotFound(.claudeCode)
        }

        let tempDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("CapsStack-claude-\(UUID().uuidString)", isDirectory: true)
        do {
            try fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
            defer { try? fileManager.removeItem(at: tempDirectory) }

            let help = await detectHelp(executable: executable, currentDirectory: tempDirectory)
            let input: Data
            do {
                input = try SummaryPromptFactory.prompt(for: batch, provider: .claudeCode)
            } catch {
                throw SummaryProviderError.invalidOutput(.claudeCode)
            }

            var arguments = ["-p"]
            let capabilities = help.lowercased()
            if let model = modelOverride?.trimmingCharacters(in: .whitespacesAndNewlines), !model.isEmpty {
                arguments += ["--model", model]
            }
            // -p is the stable non-interactive entry point. The optional flags are appended only
            // when this installed Claude Code advertises them in --help.
            if capabilities.contains("--output-format") {
                arguments += ["--output-format", "json"]
            }
            if capabilities.contains("--tools") {
                arguments += ["--tools", ""]
            } else if capabilities.contains("--disallowedtools") {
                arguments += ["--disallowedTools", "Bash,Edit,Write,NotebookEdit"]
            }
            if capabilities.contains("--permission-mode") {
                arguments += ["--permission-mode", "plan"]
            }
            if let reasoning = reasoningOverride?.trimmingCharacters(in: .whitespacesAndNewlines),
               !reasoning.isEmpty,
               capabilities.contains("--effort") {
                arguments += ["--effort", reasoning]
            }
            if capabilities.contains("--no-session-persistence") {
                arguments.append("--no-session-persistence")
            }
            // Claude Code documents combining a prompt argument with piped stdin; the artifact
            // remains the complete context while this short argument guarantees print mode has
            // an explicit query on versions that require one.
            arguments.append("Return the required JSON using the supplied CapsStack artifact.")

            let specification = ProcessSpecification(
                executableURL: executable,
                arguments: arguments,
                standardInput: input,
                currentDirectoryURL: tempDirectory
            )
            let result = try await run(specification, provider: .claudeCode)
            guard result.succeeded else {
                throw SummaryProviderError.processFailed(
                    .claudeCode,
                    Self.errorMessage(from: result, fallback: "終了コード \(result.terminationStatus)")
                )
            }
            guard let document = SummaryOutputParser.parse(
                stdout: result.standardOutput,
                provider: .claudeCode
            ) else {
                throw SummaryProviderError.invalidOutput(.claudeCode)
            }
            return document
        } catch let error as SummaryProviderError {
            throw error
        } catch {
            throw SummaryProviderError.processFailed(.claudeCode, error.localizedDescription)
        }
    }

    private func detectHelp(executable: URL, currentDirectory: URL) async -> String {
        let specification = ProcessSpecification(
            executableURL: executable,
            arguments: ["--help"],
            currentDirectoryURL: currentDirectory
        )
        do {
            let result = try await runner.run(specification, timeout: helpTimeout)
            let stdout = String(data: result.standardOutput, encoding: .utf8) ?? ""
            let stderr = String(data: result.standardError, encoding: .utf8) ?? ""
            return stdout + "\n" + stderr
        } catch {
            // A help probe must not hide a usable CLI. The stable -p flag is still used, while
            // optional flags are omitted because their support could not be verified.
            return ""
        }
    }

    private func run(_ specification: ProcessSpecification, provider: CLIKind) async throws -> ProcessResult {
        do {
            return try await runner.run(specification, timeout: timeout)
        } catch let error as ProcessRunnerError {
            switch error {
            case .timedOut:
                throw SummaryProviderError.timedOut(provider)
            default:
                throw SummaryProviderError.processFailed(provider, error.localizedDescription)
            }
        } catch {
            throw SummaryProviderError.processFailed(provider, error.localizedDescription)
        }
    }

    private static func errorMessage(from result: ProcessResult, fallback: String) -> String {
        let text = String(data: result.standardError, encoding: .utf8)
            ?? String(data: result.standardOutput, encoding: .utf8)
            ?? fallback
        return String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1_000))
    }
}

final class OpenCodeSummaryProvider: SummaryProvider {
    let kind: CLIKind = .opencode
    private let resolver: CLIResolving
    private let runner: ProcessRunning
    private let timeout: TimeInterval
    private let fileManager: FileManager

    init(
        resolver: CLIResolving = CLIResolver(),
        runner: ProcessRunning = ProcessRunner(),
        timeout: TimeInterval = 120,
        fileManager: FileManager = .default
    ) {
        self.resolver = resolver
        self.runner = runner
        self.timeout = max(0.1, timeout)
        self.fileManager = fileManager
    }

    func summarize(
        batch: CollectionBatch,
        executableOverride: String? = nil,
        modelOverride: String? = nil,
        reasoningOverride: String? = nil
    ) async throws -> SummaryDocument {
        guard let executable = resolver.executableURL(for: .opencode, override: executableOverride) else {
            throw SummaryProviderError.executableNotFound(.opencode)
        }

        let tempDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("CapsStack-opencode-\(UUID().uuidString)", isDirectory: true)
        do {
            try fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
            defer { try? fileManager.removeItem(at: tempDirectory) }

            let prompt: String
            do {
                prompt = String(
                    decoding: try SummaryPromptFactory.prompt(for: batch, provider: .opencode),
                    as: UTF8.self
                )
            } catch {
                throw SummaryProviderError.invalidOutput(.opencode)
            }

            var arguments = ["run", "--format", "json", "--pure", "--dir", tempDirectory.path]
            if let model = modelOverride?.trimmingCharacters(in: .whitespacesAndNewlines), !model.isEmpty {
                arguments += ["--model", model]
            }
            if let reasoning = reasoningOverride?.trimmingCharacters(in: .whitespacesAndNewlines), !reasoning.isEmpty {
                arguments += ["--variant", reasoning]
            }
            arguments.append(prompt)

            let specification = ProcessSpecification(
                executableURL: executable,
                arguments: arguments,
                currentDirectoryURL: tempDirectory,
                environment: isolatedOpenCodeEnvironment(for: executable, temporaryDirectory: tempDirectory)
            )
            let result = try await run(specification)
            guard result.succeeded else {
                throw SummaryProviderError.processFailed(
                    .opencode,
                    Self.errorMessage(from: result, fallback: "終了コード \(result.terminationStatus)")
                )
            }
            guard let document = SummaryOutputParser.parse(
                stdout: result.standardOutput,
                provider: .opencode
            ) else {
                throw SummaryProviderError.invalidOutput(.opencode)
            }
            return document
        } catch let error as SummaryProviderError {
            throw error
        } catch {
            throw SummaryProviderError.processFailed(.opencode, error.localizedDescription)
        }
    }

    private func run(_ specification: ProcessSpecification) async throws -> ProcessResult {
        do {
            return try await runner.run(specification, timeout: timeout)
        } catch let error as ProcessRunnerError {
            switch error {
            case .timedOut:
                throw SummaryProviderError.timedOut(.opencode)
            default:
                throw SummaryProviderError.processFailed(.opencode, error.localizedDescription)
            }
        } catch {
            throw SummaryProviderError.processFailed(.opencode, error.localizedDescription)
        }
    }

    private func isolatedOpenCodeEnvironment(for executable: URL, temporaryDirectory: URL) -> [String: String] {
        let isVersionTwo = executable.lastPathComponent == "opencode2"
        let config: String
        if isVersionTwo {
            config = #"{"$schema":"https://opencode.ai/config.json","permissions":[{"action":"*","resource":"*","effect":"deny"}]}"#
        } else {
            config = #"{"$schema":"https://opencode.ai/config.json","permission":{"*":"deny"}}"#
        }
        return [
            "OPENCODE_CONFIG_CONTENT": config,
            // Keep one-shot summaries out of the user's normal OpenCode history. The CLI
            // supports overriding its database location; the temporary cwd is also used for
            // project-scoped state and is removed after the provider finishes.
            "OPENCODE_DB": temporaryDirectory.appendingPathComponent("summary.db").path,
            "OPENCODE_DISABLE_AUTOUPDATE": "1"
        ]
    }

    private static func errorMessage(from result: ProcessResult, fallback: String) -> String {
        let text = String(data: result.standardError, encoding: .utf8)
            ?? String(data: result.standardOutput, encoding: .utf8)
            ?? fallback
        return String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1_000))
    }
}

final class PiSummaryProvider: SummaryProvider {
    let kind: CLIKind = .pi
    private let resolver: CLIResolving
    private let runner: ProcessRunning
    private let timeout: TimeInterval
    private let fileManager: FileManager

    init(
        resolver: CLIResolving = CLIResolver(),
        runner: ProcessRunning = ProcessRunner(),
        timeout: TimeInterval = 120,
        fileManager: FileManager = .default
    ) {
        self.resolver = resolver
        self.runner = runner
        self.timeout = max(0.1, timeout)
        self.fileManager = fileManager
    }

    func summarize(
        batch: CollectionBatch,
        executableOverride: String? = nil,
        modelOverride: String? = nil,
        reasoningOverride: String? = nil
    ) async throws -> SummaryDocument {
        guard let executable = resolver.executableURL(for: .pi, override: executableOverride) else {
            throw SummaryProviderError.executableNotFound(.pi)
        }

        let tempDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("CapsStack-pi-\(UUID().uuidString)", isDirectory: true)
        do {
            try fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
            defer { try? fileManager.removeItem(at: tempDirectory) }

            let input: Data
            do {
                input = try SummaryPromptFactory.prompt(for: batch, provider: .pi)
            } catch {
                throw SummaryProviderError.invalidOutput(.pi)
            }

            var arguments = [
                "--print",
                "--no-session",
                "--no-tools",
                "--no-context-files",
                "--no-extensions",
                "--no-skills",
                "--no-prompt-templates",
                "--no-themes"
            ]
            if let model = modelOverride?.trimmingCharacters(in: .whitespacesAndNewlines), !model.isEmpty {
                arguments += ["--model", model]
            }
            if let reasoning = reasoningOverride?.trimmingCharacters(in: .whitespacesAndNewlines), !reasoning.isEmpty {
                arguments += ["--thinking", reasoning]
            }
            // Keep a short positional prompt so Pi also enters print mode when stdin is piped.
            arguments.append("Return the required JSON using the supplied CapsStack artifact.")

            let specification = ProcessSpecification(
                executableURL: executable,
                arguments: arguments,
                standardInput: input,
                currentDirectoryURL: tempDirectory
            )
            let result = try await run(specification)
            guard result.succeeded else {
                throw SummaryProviderError.processFailed(
                    .pi,
                    Self.errorMessage(from: result, fallback: "終了コード \(result.terminationStatus)")
                )
            }
            guard let document = SummaryOutputParser.parse(
                stdout: result.standardOutput,
                provider: .pi
            ) else {
                throw SummaryProviderError.invalidOutput(.pi)
            }
            return document
        } catch let error as SummaryProviderError {
            throw error
        } catch {
            throw SummaryProviderError.processFailed(.pi, error.localizedDescription)
        }
    }

    private func run(_ specification: ProcessSpecification) async throws -> ProcessResult {
        do {
            return try await runner.run(specification, timeout: timeout)
        } catch let error as ProcessRunnerError {
            switch error {
            case .timedOut:
                throw SummaryProviderError.timedOut(.pi)
            default:
                throw SummaryProviderError.processFailed(.pi, error.localizedDescription)
            }
        } catch {
            throw SummaryProviderError.processFailed(.pi, error.localizedDescription)
        }
    }

    private static func errorMessage(from result: ProcessResult, fallback: String) -> String {
        let text = String(data: result.standardError, encoding: .utf8)
            ?? String(data: result.standardOutput, encoding: .utf8)
            ?? fallback
        return String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1_000))
    }
}

enum SummaryOutputParser {
    static func parse(stdout: Data, provider: CLIKind) -> SummaryDocument? {
        guard !stdout.isEmpty else { return nil }
        let text = String(decoding: stdout, as: UTF8.self)
        var candidates: [Any] = []
        if let object = try? JSONSerialization.jsonObject(with: stdout, options: []) {
            candidates.append(object)
        }
        for line in text.split(whereSeparator: { $0.isNewline }) {
            let lineText = String(line)
            if let object = try? JSONSerialization.jsonObject(with: Data(lineText.utf8), options: []) {
                candidates.append(object)
            }
            candidates.append(contentsOf: jsonObjects(in: lineText))
        }
        candidates.append(contentsOf: jsonObjects(in: text))

        for candidate in candidates {
            if let result = parse(candidate, provider: provider) { return result }
        }
        return nil
    }

    private static func parse(_ candidate: Any, provider: CLIKind) -> SummaryDocument? {
        if let dictionary = candidate as? [String: Any] {
            if let result = parse(dictionary: dictionary, provider: provider) { return result }
            for value in dictionary.values {
                if let result = parse(value, provider: provider) { return result }
            }
        } else if let array = candidate as? [Any] {
            for value in array {
                if let result = parse(value, provider: provider) { return result }
            }
        } else if let string = candidate as? String {
            if let object = try? JSONSerialization.jsonObject(with: Data(string.utf8), options: []),
               let result = parse(object, provider: provider) {
                return result
            }
            for object in jsonObjects(in: string) {
                if let result = parse(object, provider: provider) { return result }
            }
        }
        return nil
    }

    private static func parse(dictionary: [String: Any], provider: CLIKind) -> SummaryDocument? {
        let normalized = Dictionary(uniqueKeysWithValues: dictionary.map { ($0.key.lowercased(), $0.value) })
        let knownKeys = ["overview", "progress", "currentstate", "current_state", "decisions", "blockers", "nextsteps", "next_steps", "sessions"]
        guard knownKeys.contains(where: { normalized[$0] != nil }) else { return nil }

        let overview = stringValue(normalized["overview"])
            ?? stringValue(normalized["summary"])
            ?? stringValue(normalized["result"])
            ?? stringValue(normalized["output"])
        guard let overview, !overview.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        return SummaryDocument(
            overview: overview,
            progress: stringArray(normalized["progress"]),
            currentState: stringArray(normalized["currentstate"] ?? normalized["current_state"]),
            decisions: stringArray(normalized["decisions"]),
            blockers: stringArray(normalized["blockers"] ?? normalized["issues"]),
            nextSteps: stringArray(normalized["nextsteps"] ?? normalized["next_steps"]),
            sessions: sessionArray(normalized["sessions"], provider: provider)
        )
    }

    private static func stringValue(_ value: Any?) -> String? {
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }

    private static func stringArray(_ value: Any?) -> [String] {
        if let array = value as? [Any] {
            return array.compactMap { stringValue($0) }.filter { !$0.isEmpty }
        }
        if let string = value as? String, !string.isEmpty { return [string] }
        return []
    }

    private static func sessionArray(_ value: Any?, provider: CLIKind) -> [SessionSummary] {
        guard let array = value as? [Any] else { return [] }
        return array.compactMap { item in
            guard let dictionary = item as? [String: Any] else { return nil }
            let normalized = Dictionary(uniqueKeysWithValues: dictionary.map { ($0.key.lowercased(), $0.value) })
            guard let id = stringValue(normalized["sessionid"] ?? normalized["session_id"]),
                  let summary = stringValue(normalized["summary"] ?? normalized["overview"]),
                  !id.isEmpty, !summary.isEmpty else { return nil }
            return SessionSummary(
                sessionID: id,
                source: stringValue(normalized["source"]) ?? provider.displayName,
                summary: summary
            )
        }
    }

    private static func jsonObjects(in text: String) -> [Any] {
        var result: [Any] = []
        var depth = 0
        var start: String.Index?
        var inString = false
        var escaped = false

        for index in text.indices {
            let character = text[index]
            if inString {
                if escaped { escaped = false }
                else if character == "\\" { escaped = true }
                else if character == "\"" { inString = false }
                continue
            }
            if character == "\"" {
                inString = true
            } else if character == "{" {
                if depth == 0 { start = index }
                depth += 1
            } else if character == "}" && depth > 0 {
                depth -= 1
                if depth == 0, let start {
                    let candidate = String(text[start...index])
                    if let object = try? JSONSerialization.jsonObject(with: Data(candidate.utf8), options: []) {
                        result.append(object)
                    }
                }
            }
        }
        return result
    }
}
