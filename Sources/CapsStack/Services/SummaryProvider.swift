import Foundation

/// A provider receives a normalized collection artifact and returns only a structured summary.
/// Implementations never resume a source session and never use a source session's working
/// directory.
protocol SummaryProvider: AnyObject, Sendable {
    var kind: CLIKind { get }
    /// Returns whether this provider can be invoked with the current executable override.
    /// Implementations use a filesystem-only check; no CLI process is started here.
    func isAvailable(executableOverride: String?) -> Bool
    func summarize(
        batch: CollectionBatch,
        executableOverride: String?,
        modelOverride: String?,
        reasoningOverride: String?
    ) async throws -> SummaryDocument
}

extension SummaryProvider {
    /// Test doubles and third-party providers remain usable without an availability probe. The
    /// built-in providers override this with their resolver-backed check.
    func isAvailable(executableOverride: String?) -> Bool { true }
}

enum SummaryPromptFactory {
    static func prompt(for batch: CollectionBatch, provider: CLIKind) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let payload = try encoder.encode(ProjectGroupedPromptArtifact(
            interval: batch.interval,
            projects: CollectionProjectGrouping.projects(in: batch).map(PromptProjectArtifact.init),
            issues: batch.issues,
            quickMemo: batch.quickMemo
        ))
        guard let payloadText = String(data: payload, encoding: .utf8) else {
            throw SummaryProviderError.invalidOutput(provider)
        }
        let text = """
        あなたはCapsStackの要約専用プロセスです。BEGIN_CAPSSTACK_ARTIFACTとEND_CAPSSTACK_ARTIFACTの間のJSONだけを読み、退席中の進捗を要約してください。
        コード変更、コマンド実行、ファイル探索、ネットワークアクセス、元セッションのresumeやcontinueは禁止です。
        ログにない事実は推測せず、不明な項目は空配列にしてください。
        JSONにquickMemoフィールドがある場合は、それはユーザーが退席前に書いた補足メモです。セッションログと併せて考慮し、要約のoverviewやnextStepsに反映してください。
        入力のeventsはCaps LockがONだった区間だけに絞られています。projectsごとに、その中のsessionsをまとめているため、この階層を維持し、プロジェクトをまたいでセッションを混ぜないでください。
        次のキーをすべて持つJSONオブジェクトだけを返してください: overview, progress, currentState, decisions, blockers, nextSteps, projects。
        projectsの出力各要素はprojectID、name、summary、sessionsを持ち、projectIDとnameは入力projectsの値を維持し、summaryはそのプロジェクト内のsessions/eventsを要約してください。出力sessionsの各要素はsessionID、source、summaryを持ち、sessionIDには入力sessionsのid、sourceには入力sessionsのsourceをそのまま使い、対応するeventsを要約してください。Markdownフェンスや説明文は出力しないでください。

        BEGIN_CAPSSTACK_ARTIFACT
        \(payloadText)
        END_CAPSSTACK_ARTIFACT
        """
        return Data(text.utf8)
    }
}

private struct ProjectGroupedPromptArtifact: Encodable {
    let interval: AwayInterval
    let projects: [PromptProjectArtifact]
    let issues: [CollectionIssue]
    let quickMemo: String?
}

private struct PromptProjectArtifact: Encodable {
    let projectID: String
    let name: String
    let workingDirectory: String?
    let sessions: [PromptSessionArtifact]

    init(_ project: CollectedProjectArtifact) {
        projectID = project.projectID
        name = project.name
        workingDirectory = project.workingDirectory
        sessions = project.sessions.map(PromptSessionArtifact.init)
    }
}

private struct PromptSessionArtifact: Encodable {
    let id: String
    let provider: CLIKind
    let client: AgentClientKind
    let source: String
    let workingDirectory: String?
    let events: [CollectedEvent]
    let wasTruncated: Bool

    init(_ session: CollectedSessionArtifact) {
        id = session.id
        provider = session.provider
        client = session.effectiveClient
        source = session.sourceDisplayName
        workingDirectory = session.workingDirectory
        events = session.events
        wasTruncated = session.wasTruncated
    }
}

final class CodexSummaryProvider: SummaryProvider, @unchecked Sendable {
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

    func isAvailable(executableOverride: String? = nil) -> Bool {
        resolver.executableURL(for: .codex, override: executableOverride) != nil
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
            guard !result.didTruncateOutput else {
                throw SummaryProviderError.invalidOutput(.codex)
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
        for data in [result.standardError, result.standardOutput] {
            let text = (String(data: data, encoding: .utf8) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { return String(text.prefix(1_000)) }
        }
        return fallback
    }
}

final class ClaudeCodeSummaryProvider: SummaryProvider, @unchecked Sendable {
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

    func isAvailable(executableOverride: String? = nil) -> Bool {
        resolver.executableURL(for: .claudeCode, override: executableOverride) != nil
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

            // These documented flags are part of the safety boundary, not optional UX sugar.
            // Disable tools, settings, and MCP discovery even when `--help` probing fails so a
            // summary cannot execute hooks or inspect the user's workspace implicitly.
            var arguments = [
                "-p",
                "--output-format", "json",
                "--tools", "",
                "--setting-sources", "",
                "--strict-mcp-config",
                "--mcp-config", "{}"
            ]
            let capabilities = help.lowercased()
            if let model = modelOverride?.trimmingCharacters(in: .whitespacesAndNewlines), !model.isEmpty {
                arguments += ["--model", model]
            }
            // -p is the stable non-interactive entry point. The optional flags are appended only
            // when this installed Claude Code advertises them in --help.
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
            guard !result.didTruncateOutput else {
                throw SummaryProviderError.invalidOutput(.claudeCode)
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
        for data in [result.standardError, result.standardOutput] {
            let text = (String(data: data, encoding: .utf8) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { return String(text.prefix(1_000)) }
        }
        return fallback
    }
}

final class OpenCodeSummaryProvider: SummaryProvider, @unchecked Sendable {
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

    func isAvailable(executableOverride: String? = nil) -> Bool {
        guard let executable = resolver.executableURL(for: .opencode, override: executableOverride) else {
            return false
        }
        return executable.lastPathComponent != "opencode2"
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
        guard executable.lastPathComponent != "opencode2" else {
            throw SummaryProviderError.processFailed(
                .opencode,
                "OpenCode 2 CLIは現在のOpenCode 1用アダプタと互換性がありません。"
            )
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
                environment: isolatedOpenCodeEnvironment(temporaryDirectory: tempDirectory)
            )
            let result = try await run(specification)
            guard result.succeeded else {
                throw SummaryProviderError.processFailed(
                    .opencode,
                    Self.errorMessage(from: result, fallback: "終了コード \(result.terminationStatus)")
                )
            }
            guard !result.didTruncateOutput else {
                throw SummaryProviderError.invalidOutput(.opencode)
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

    private func isolatedOpenCodeEnvironment(temporaryDirectory: URL) -> [String: String] {
        return [
            "OPENCODE_CONFIG_CONTENT": #"{"$schema":"https://opencode.ai/config.json","permission":{"*":"deny"}}"#,
            // Keep one-shot summaries out of the user's normal OpenCode history. The CLI
            // supports overriding its database location; the temporary cwd is also used for
            // project-scoped state and is removed after the provider finishes.
            "OPENCODE_DB": temporaryDirectory.appendingPathComponent("summary.db").path,
            "OPENCODE_DISABLE_AUTOUPDATE": "1"
        ]
    }

    private static func errorMessage(from result: ProcessResult, fallback: String) -> String {
        for data in [result.standardError, result.standardOutput] {
            let text = (String(data: data, encoding: .utf8) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { return String(text.prefix(1_000)) }
        }
        return fallback
    }
}

final class PiSummaryProvider: SummaryProvider, @unchecked Sendable {
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

    func isAvailable(executableOverride: String? = nil) -> Bool {
        resolver.executableURL(for: .pi, override: executableOverride) != nil
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
            guard !result.didTruncateOutput else {
                throw SummaryProviderError.invalidOutput(.pi)
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
        for data in [result.standardError, result.standardOutput] {
            let text = (String(data: data, encoding: .utf8) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { return String(text.prefix(1_000)) }
        }
        return fallback
    }
}

/// Runs newer agent CLIs only through their documented non-interactive, tool-disabled modes.
/// Every strategy receives the artifact as prompt text, uses an isolated temporary cwd, and
/// disables session persistence when the CLI exposes that boundary.
final class SafeHeadlessSummaryProvider: SummaryProvider, @unchecked Sendable {
    enum Strategy: Sendable {
        case githubCopilot
        case kiloCode
        case goose
        case qwenCode
    }

    let kind: CLIKind
    private let strategy: Strategy
    private let resolver: CLIResolving
    private let runner: ProcessRunning
    private let timeout: TimeInterval
    private let fileManager: FileManager

    init(
        kind: CLIKind,
        strategy: Strategy,
        resolver: CLIResolving = CLIResolver(),
        runner: ProcessRunning = ProcessRunner(),
        timeout: TimeInterval = 120,
        fileManager: FileManager = .default
    ) {
        self.kind = kind
        self.strategy = strategy
        self.resolver = resolver
        self.runner = runner
        self.timeout = max(0.1, timeout)
        self.fileManager = fileManager
    }

    func isAvailable(executableOverride: String? = nil) -> Bool {
        resolver.executableURL(for: kind, override: executableOverride) != nil
    }

    func summarize(
        batch: CollectionBatch,
        executableOverride: String? = nil,
        modelOverride: String? = nil,
        reasoningOverride: String? = nil
    ) async throws -> SummaryDocument {
        guard let executable = resolver.executableURL(for: kind, override: executableOverride) else {
            throw SummaryProviderError.executableNotFound(kind)
        }
        let temporaryDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("CapsStack-\(kind.rawValue)-\(UUID().uuidString)", isDirectory: true)
        do {
            try fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
            defer { try? fileManager.removeItem(at: temporaryDirectory) }

            let prompt = String(
                decoding: try SummaryPromptFactory.prompt(for: batch, provider: kind),
                as: UTF8.self
            )
            let invocation = arguments(
                prompt: prompt,
                modelOverride: modelOverride,
                reasoningOverride: reasoningOverride,
                temporaryDirectory: temporaryDirectory
            )
            let specification = ProcessSpecification(
                executableURL: executable,
                arguments: invocation.arguments,
                currentDirectoryURL: temporaryDirectory,
                environment: invocation.environment
            )
            let result: ProcessResult
            do {
                result = try await runner.run(specification, timeout: timeout)
            } catch ProcessRunnerError.timedOut {
                throw SummaryProviderError.timedOut(kind)
            } catch {
                throw SummaryProviderError.processFailed(kind, error.localizedDescription)
            }
            guard result.succeeded else {
                let text = String(data: result.standardError, encoding: .utf8)
                    ?? String(data: result.standardOutput, encoding: .utf8)
                    ?? "終了コード \(result.terminationStatus)"
                throw SummaryProviderError.processFailed(kind, String(text.prefix(1_000)))
            }
            guard !result.didTruncateOutput,
                  let document = SummaryOutputParser.parse(stdout: result.standardOutput, provider: kind) else {
                throw SummaryProviderError.invalidOutput(kind)
            }
            return document
        } catch let error as SummaryProviderError {
            throw error
        } catch {
            throw SummaryProviderError.processFailed(kind, error.localizedDescription)
        }
    }

    private func arguments(
        prompt: String,
        modelOverride: String?,
        reasoningOverride: String?,
        temporaryDirectory: URL
    ) -> (arguments: [String], environment: [String: String]?) {
        let model = modelOverride?.trimmingCharacters(in: .whitespacesAndNewlines)
        let reasoning = reasoningOverride?.trimmingCharacters(in: .whitespacesAndNewlines)
        switch strategy {
        case .githubCopilot:
            var arguments = [
                "-p", prompt,
                "--output-format=json",
                "--available-tools=",
                "--disable-builtin-mcps",
                "--no-custom-instructions"
            ]
            if let model, !model.isEmpty { arguments += ["--model", model] }
            if let reasoning, !reasoning.isEmpty { arguments += ["--effort", reasoning] }
            return (arguments, [
                // COPILOT_HOME contains session-state and other persistent CLI state. Keeping it
                // below the temporary cwd prevents the artifact from being retained after this
                // one-shot summary.
                "COPILOT_HOME": temporaryDirectory.appendingPathComponent("copilot-home", isDirectory: true).path,
                "COPILOT_CACHE_HOME": temporaryDirectory.appendingPathComponent("copilot-cache", isDirectory: true).path,
                "COPILOT_MCP_TOOL_CACHE": "false",
                "COPILOT_OTEL_ENABLED": "false",
                "COPILOT_AUTO_UPDATE": "false",
                "COPILOT_OTEL_FILE_EXPORTER_PATH": "",
                "OTEL_EXPORTER_OTLP_ENDPOINT": "",
                "OTEL_INSTRUMENTATION_GENAI_CAPTURE_MESSAGE_CONTENT": "false"
            ])
        case .kiloCode:
            var arguments = ["run", "--agent", "ask", "--format", "json"]
            if let model, !model.isEmpty { arguments += ["--model", model] }
            arguments.append(prompt)
            return (arguments, [
                // Kilo persists conversations in this database even for `run`; point it at a
                // throw-away file so the source artifact never enters the user's session store.
                // Keep the normal XDG data root so the CLI can still resolve its existing auth
                // records; KILO_DB is the session-bearing boundary we need to isolate.
                "KILO_DB": temporaryDirectory.appendingPathComponent("kilo.db").path
            ])
        case .goose:
            var arguments = [
                "run", "--no-session", "--quiet", "--output-format", "json", "-t", prompt
            ]
            if let model, !model.isEmpty { arguments += ["--model", model] }
            return (arguments, [
                "GOOSE_MODE": "chat",
                "GOOSE_TELEMETRY_ENABLED": "false",
                "GOOSE_DISABLE_SESSION_NAMING": "true"
            ])
        case .qwenCode:
            var arguments = [
                "-p", prompt,
                "--safe-mode",
                "--approval-mode", "plan",
                "--exclude-tools", "shell,write,edit,agent",
                "--max-tool-calls", "0",
                "--max-wall-time", String(Int(ceil(timeout))),
                "--output-format", "json"
            ]
            if let model, !model.isEmpty { arguments += ["--model", model] }
            return (arguments, [
                // Qwen keeps conversations/logs/todos below this runtime directory. QWEN_HOME is
                // intentionally left untouched so an existing authentication setup remains
                // available to the CLI.
                "QWEN_RUNTIME_DIR": temporaryDirectory.appendingPathComponent("qwen-runtime", isDirectory: true).path,
                "QWEN_TELEMETRY_ENABLED": "false",
                "QWEN_CODE_SAFE_MODE": "true"
            ])
        }
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
        guard let normalized = normalizedDictionary(dictionary) else { return nil }
        let hasCurrentState = normalized["currentstate"] != nil || normalized["current_state"] != nil
        let hasNextSteps = normalized["nextsteps"] != nil || normalized["next_steps"] != nil
        let hasProjects = normalized["projects"] != nil
        let hasLegacySessions = normalized["sessions"] != nil
        guard normalized["overview"] != nil,
              normalized["progress"] != nil,
              hasCurrentState,
              normalized["decisions"] != nil,
              normalized["blockers"] != nil,
              hasNextSteps,
              hasProjects || hasLegacySessions else {
            return nil
        }

        let overview = stringValue(normalized["overview"])
            ?? stringValue(normalized["summary"])
            ?? stringValue(normalized["result"])
            ?? stringValue(normalized["output"])
        guard let overview, !overview.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        guard let progress = stringArray(normalized["progress"]),
              let currentState = stringArray(normalized["currentstate"] ?? normalized["current_state"]),
              let decisions = stringArray(normalized["decisions"]),
              let blockers = stringArray(normalized["blockers"]),
              let nextSteps = stringArray(normalized["nextsteps"] ?? normalized["next_steps"]) else {
            return nil
        }

        let projects: [ProjectSummary]
        let sessions: [SessionSummary]
        if hasProjects {
            guard let parsedProjects = projectArray(normalized["projects"], provider: provider) else {
                return nil
            }
            if parsedProjects.isEmpty, hasLegacySessions {
                guard let parsedSessions = sessionArray(normalized["sessions"], provider: provider) else {
                    return nil
                }
                projects = []
                sessions = parsedSessions
            } else {
                projects = parsedProjects
                sessions = parsedProjects.flatMap(\.sessions)
            }
        } else {
            guard let parsedSessions = sessionArray(normalized["sessions"], provider: provider) else {
                return nil
            }
            projects = []
            sessions = parsedSessions
        }

        return SummaryDocument(
            overview: overview,
            progress: progress,
            currentState: currentState,
            decisions: decisions,
            blockers: blockers,
            nextSteps: nextSteps,
            sessions: sessions,
            projects: projects
        )
    }

    private static func stringValue(_ value: Any?) -> String? {
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }

    private static func stringArray(_ value: Any?) -> [String]? {
        guard let array = value as? [Any] else { return nil }
        var result: [String] = []
        result.reserveCapacity(array.count)
        for item in array {
            guard let string = item as? String else { return nil }
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { result.append(trimmed) }
        }
        return result
    }

    private static func sessionArray(_ value: Any?, provider: CLIKind) -> [SessionSummary]? {
        guard let array = value as? [Any] else { return nil }
        var result: [SessionSummary] = []
        result.reserveCapacity(array.count)
        for item in array {
            guard let dictionary = item as? [String: Any],
                  let normalized = normalizedDictionary(dictionary),
                  let id = stringValue(normalized["sessionid"] ?? normalized["session_id"]),
                  let summary = stringValue(normalized["summary"] ?? normalized["overview"]),
                  !id.isEmpty, !summary.isEmpty else { return nil }
            result.append(SessionSummary(
                sessionID: id,
                source: stringValue(normalized["source"]) ?? provider.displayName,
                summary: summary
            ))
        }
        return result
    }

    private static func projectArray(_ value: Any?, provider: CLIKind) -> [ProjectSummary]? {
        guard let array = value as? [Any] else { return nil }
        var result: [ProjectSummary] = []
        result.reserveCapacity(array.count)
        for item in array {
            guard let dictionary = item as? [String: Any],
                  let normalized = normalizedDictionary(dictionary),
                  let projectID = stringValue(normalized["projectid"] ?? normalized["project_id"]),
                  let name = stringValue(normalized["name"] ?? normalized["projectname"]),
                  let summary = stringValue(normalized["summary"] ?? normalized["overview"]),
                  let sessions = sessionArray(normalized["sessions"], provider: provider),
                  !projectID.isEmpty, !name.isEmpty, !summary.isEmpty else {
                return nil
            }
            result.append(ProjectSummary(
                projectID: projectID,
                name: name,
                summary: summary,
                sessions: sessions
            ))
        }
        return result
    }

    /// JSON keys are case-sensitive, but provider output is normalized for compatibility. Reject
    /// case-folding collisions rather than feeding untrusted duplicate keys into
    /// `Dictionary(uniqueKeysWithValues:)`, which traps and terminates the entire app.
    private static func normalizedDictionary(_ dictionary: [String: Any]) -> [String: Any]? {
        var normalized: [String: Any] = [:]
        for (key, value) in dictionary {
            let folded = key.lowercased()
            guard normalized[folded] == nil else { return nil }
            normalized[folded] = value
        }
        return normalized
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
