import Foundation
import XCTest
@testable import CapsStack

final class BackendTests: XCTestCase {
    func testJSONLCollectorUsesTimeWindowAndKeepsMalformedLineIssue() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("CapsStack-collector-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: root) }

        let codexRoot = root.appendingPathComponent("codex", isDirectory: true)
        let claudeRoot = root.appendingPathComponent("claude", isDirectory: true)
        try fileManager.createDirectory(at: codexRoot, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: claudeRoot, withIntermediateDirectories: true)

        let now = Date()
        let interval = AwayInterval(
            start: now.addingTimeInterval(-5),
            end: now.addingTimeInterval(5)
        )
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        func stamp(_ date: Date) -> String { formatter.string(from: date) }

        let codexLines = [
            "{\"timestamp\":\"\(stamp(now.addingTimeInterval(-10)))\",\"session_id\":\"codex-1\",\"type\":\"user\",\"message\":\"outside\"}",
            "{\"timestamp\":\"\(stamp(now))\",\"session_id\":\"codex-1\",\"type\":\"assistant\",\"message\":\"inside codex\"}",
            "{malformed-json",
            "{\"timestamp\":\"\(stamp(now.addingTimeInterval(10)))\",\"session_id\":\"codex-1\",\"type\":\"assistant\",\"message\":\"outside again\"}"
        ].joined(separator: "\n")
        try Data(codexLines.utf8).write(
            to: codexRoot.appendingPathComponent("codex-session.jsonl"),
            options: .atomic
        )

        let claudeLine = "{\"timestamp\":\"\(stamp(now.addingTimeInterval(1)))\",\"sessionId\":\"claude-1\",\"role\":\"assistant\",\"content\":\"inside claude\"}\n"
        try Data(claudeLine.utf8).write(
            to: claudeRoot.appendingPathComponent("claude-session.jsonl"),
            options: .atomic
        )

        let codexResult = JSONLSessionCollector(provider: .codex, rootDirectory: codexRoot)
            .collect(interval: interval)
        let claudeResult = JSONLSessionCollector(provider: .claudeCode, rootDirectory: claudeRoot)
            .collect(interval: interval)

        XCTAssertEqual(codexResult.provider, .codex)
        XCTAssertEqual(codexResult.sessions.count, 1)
        XCTAssertEqual(codexResult.sessions[0].provider, .codex)
        XCTAssertEqual(codexResult.sessions[0].events.count, 1)
        XCTAssertEqual(codexResult.sessions[0].events[0].content, "inside codex")
        XCTAssertTrue(codexResult.issues.contains { $0.message.contains("不正なJSONL") })

        XCTAssertEqual(claudeResult.provider, .claudeCode)
        XCTAssertEqual(claudeResult.sessions.count, 1)
        XCTAssertEqual(claudeResult.sessions[0].provider, .claudeCode)
        XCTAssertEqual(claudeResult.sessions[0].events.count, 1)
        XCTAssertEqual(claudeResult.sessions[0].events[0].content, "inside claude")
    }

    func testSummaryOrchestratorUsesPrimaryProvider() async throws {
        let codex = FakeSummaryProvider(kind: .codex, document: makeDocument("primary"))
        let claude = FakeSummaryProvider(kind: .claudeCode, document: makeDocument("fallback"))
        let orchestrator = SummaryOrchestrator(providers: [
            .codex: codex,
            .claudeCode: claude
        ])

        let outcome = try await orchestrator.summarize(
            batch: makeBatch(),
            preferences: SummarizerPreferences(primary: .codex, automaticFallback: true)
        )

        XCTAssertEqual(outcome.provider, .codex)
        XCTAssertFalse(outcome.fallbackUsed)
        XCTAssertEqual(outcome.document.overview, "primary")
        XCTAssertEqual(codex.callCount, 1)
        XCTAssertEqual(claude.callCount, 0)
    }

    func testSummaryOrchestratorFallsBackAfterPrimaryFailure() async throws {
        let codex = FakeSummaryProvider(
            kind: .codex,
            error: SummaryProviderError.processFailed(.codex, "fake failure")
        )
        let claude = FakeSummaryProvider(kind: .claudeCode, document: makeDocument("fallback"))
        let orchestrator = SummaryOrchestrator(providers: [
            .codex: codex,
            .claudeCode: claude
        ])

        let outcome = try await orchestrator.summarize(
            batch: makeBatch(),
            preferences: SummarizerPreferences(primary: .codex, automaticFallback: true)
        )

        XCTAssertEqual(outcome.provider, .claudeCode)
        XCTAssertTrue(outcome.fallbackUsed)
        XCTAssertEqual(outcome.document.overview, "fallback")
        XCTAssertEqual(codex.callCount, 1)
        XCTAssertEqual(claude.callCount, 1)
    }

    func testSummaryOrchestratorDoesNotFallbackWhenDisabled() async throws {
        let codex = FakeSummaryProvider(
            kind: .codex,
            error: SummaryProviderError.timedOut(.codex)
        )
        let claude = FakeSummaryProvider(kind: .claudeCode, document: makeDocument("fallback"))
        let orchestrator = SummaryOrchestrator(providers: [
            .codex: codex,
            .claudeCode: claude
        ])

        do {
            _ = try await orchestrator.summarize(
                batch: makeBatch(),
                preferences: SummarizerPreferences(primary: .codex, automaticFallback: false)
            )
            XCTFail("expected primary provider error")
        } catch let error as SummaryProviderError {
            XCTAssertEqual(error, .timedOut(.codex))
        }
        XCTAssertEqual(codex.callCount, 1)
        XCTAssertEqual(claude.callCount, 0)
    }

    func testAllSummaryProvidersPassModelAndReasoningToTheirCLI() async throws {
        let batch = makeBatch()
        let cases: [(CLIKind, (CLIResolving, ProcessRunning) -> SummaryProvider)] = [
            (.codex, { resolver, runner in
                CodexSummaryProvider(resolver: resolver, runner: runner, fileManager: .default)
            }),
            (.claudeCode, { resolver, runner in
                ClaudeCodeSummaryProvider(resolver: resolver, runner: runner, fileManager: .default)
            }),
            (.opencode, { resolver, runner in
                OpenCodeSummaryProvider(resolver: resolver, runner: runner, fileManager: .default)
            }),
            (.pi, { resolver, runner in
                PiSummaryProvider(resolver: resolver, runner: runner, fileManager: .default)
            })
        ]

        for (kind, makeProvider) in cases {
            let runner = RecordingProcessRunner()
            let provider = makeProvider(StaticCLIResolver(), runner)
            _ = try await provider.summarize(
                batch: batch,
                executableOverride: nil,
                modelOverride: "test-model",
                reasoningOverride: "high"
            )

            let specification = try XCTUnwrap(runner.nonHelpSpecifications.last)
            switch kind {
            case .codex:
                XCTAssertTrue(specification.arguments.contains(where: { $0 == "--model" }))
                XCTAssertTrue(specification.arguments.contains(where: { $0 == "test-model" }))
                XCTAssertTrue(specification.arguments.contains(where: { $0 == "model_reasoning_effort=high" }))
                XCTAssertTrue(specification.arguments.contains(where: { $0 == "--output-schema" }))
            case .claudeCode:
                XCTAssertTrue(specification.arguments.contains(where: { $0 == "--model" }))
                XCTAssertTrue(specification.arguments.contains(where: { $0 == "--effort" }))
                XCTAssertTrue(specification.arguments.contains(where: { $0 == "high" }))
                XCTAssertTrue(specification.arguments.contains(where: { $0 == "--disallowedTools" }))
            case .opencode:
                XCTAssertTrue(specification.arguments.contains(where: { $0 == "run" }))
                XCTAssertTrue(specification.arguments.contains(where: { $0 == "--format" }))
                XCTAssertTrue(specification.arguments.contains(where: { $0 == "--variant" }))
                XCTAssertTrue(specification.arguments.contains(where: { $0 == "high" }))
                XCTAssertNotNil(specification.environment?["OPENCODE_CONFIG_CONTENT"])
                XCTAssertNotNil(specification.environment?["OPENCODE_DB"])
            case .pi:
                XCTAssertTrue(specification.arguments.contains(where: { $0 == "--print" }))
                XCTAssertTrue(specification.arguments.contains(where: { $0 == "--no-session" }))
                XCTAssertTrue(specification.arguments.contains(where: { $0 == "--thinking" }))
                XCTAssertTrue(specification.arguments.contains(where: { $0 == "high" }))
            }
        }
    }

    func testOpenCodeCollectorUsesSessionListAndExport() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("CapsStack-opencode-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        let now = Date()
        let interval = AwayInterval(start: now.addingTimeInterval(-5), end: now.addingTimeInterval(5))
        let stamp = Int(now.timeIntervalSince1970 * 1_000)
        let listData = Data("[{\"id\":\"session-1\",\"directory\":\"/tmp/project\",\"time\":{\"created\":\(stamp),\"updated\":\(stamp)}}]".utf8)
        let exportData = Data("{\"sessionID\":\"session-1\",\"messages\":[{\"role\":\"assistant\",\"time\":{\"created\":\(stamp)},\"parts\":[{\"type\":\"text\",\"text\":\"OpenCodeの進捗\"}]}]}".utf8)
        var calls: [[String]] = []
        let collector = OpenCodeSessionCollector(
            rootDirectory: root,
            executableURL: URL(fileURLWithPath: "/usr/bin/true"),
            commandRunner: { _, arguments, _, _ in
                calls.append(arguments)
                return arguments.first == "session" ? listData : exportData
            }
        )

        let result = collector.collect(interval: interval)

        XCTAssertEqual(result.sessions.count, 1)
        XCTAssertEqual(result.sessions.first?.events.first?.content, "OpenCodeの進捗")
        XCTAssertEqual(calls.first, ["session", "list", "--max-count", "2000", "--format", "json"])
        XCTAssertEqual(calls.last, ["export", "session-1"])
    }

    func testProcessRunnerDrainsLargeOutputWithoutDeadlocking() async throws {
        let runner = ProcessRunner(outputLimit: 1_024)
        let result = try await runner.run(
            ProcessSpecification(
                executableURL: URL(fileURLWithPath: "/bin/sh"),
                arguments: ["-c", "head -c 200000 /dev/zero"]
            ),
            timeout: 5
        )

        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(result.standardOutput.count, 1_024)
        XCTAssertTrue(result.didTruncateOutput)
    }

    func testSummaryOutputParserReadsOpenCodeTextEvent() throws {
        let event = """
        [{"type":"text","sessionID":"opencode-session","part":{"type":"text","text":"{\\"overview\\":\\"OpenCode event\\",\\"progress\\":[],\\"currentState\\":[],\\"decisions\\":[],\\"blockers\\":[],\\"nextSteps\\":[],\\"sessions\\":[]}"}}]
        """

        let document = try XCTUnwrap(
            SummaryOutputParser.parse(stdout: Data(event.utf8), provider: .opencode)
        )
        XCTAssertEqual(document.overview, "OpenCode event")
    }

    func testHistoryStoreDeletesRawAfterCompletionAndKeepsFailedPendingArtifact() throws {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("CapsStack-history-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: directory) }

        let store = HistoryStore(directoryURL: directory)
        let batch = makeBatch()
        let pending = try store.savePending(batch: batch, errorMessage: "summary failed")
        let pendingID = try XCTUnwrap(pending.pendingArtifactID)
        let pendingURL = directory
            .appendingPathComponent("Pending", isDirectory: true)
            .appendingPathComponent("\(pendingID.uuidString).json")

        XCTAssertTrue(fileManager.fileExists(atPath: pendingURL.path))
        XCTAssertEqual(try store.loadPending(pendingID), batch)
        XCTAssertEqual(try store.load().first?.status, .pending)

        let outcome = SummaryOutcome(
            document: makeDocument("completed"),
            provider: .codex,
            fallbackUsed: false
        )
        let completed = try store.saveCompleted(
            batch: batch,
            outcome: outcome,
            replacingPendingID: pendingID
        )

        XCTAssertEqual(completed.status, .completed)
        XCTAssertNil(completed.pendingArtifactID)
        XCTAssertFalse(fileManager.fileExists(atPath: pendingURL.path))
        XCTAssertNil(try store.loadPending(pendingID))
        XCTAssertEqual(try store.load().count, 1)

        let failedPending = try store.savePending(batch: batch, errorMessage: "timeout")
        let failedID = try XCTUnwrap(failedPending.pendingArtifactID)
        let failedURL = directory
            .appendingPathComponent("Pending", isDirectory: true)
            .appendingPathComponent("\(failedID.uuidString).json")
        XCTAssertTrue(fileManager.fileExists(atPath: failedURL.path))
        XCTAssertEqual(try store.loadPending(failedID), batch)
        let failedEntry = try XCTUnwrap(
            try store.load().first(where: { $0.pendingArtifactID == failedID })
        )
        XCTAssertEqual(failedEntry.status, .pending)
        XCTAssertEqual(failedEntry.errorMessage, "timeout")
    }

    private func makeBatch() -> CollectionBatch {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let event = CollectedEvent(
            timestamp: start.addingTimeInterval(1),
            kind: "assistant",
            content: "progress"
        )
        let session = CollectedSessionArtifact(
            id: "codex:test",
            provider: .codex,
            workingDirectory: nil,
            events: [event],
            wasTruncated: false
        )
        return CollectionBatch(
            interval: AwayInterval(start: start, end: start.addingTimeInterval(60)),
            sessions: [session],
            issues: []
        )
    }

    private func makeDocument(_ overview: String) -> SummaryDocument {
        SummaryDocument(
            overview: overview,
            progress: [],
            currentState: [],
            decisions: [],
            blockers: [],
            nextSteps: [],
            sessions: []
        )
    }
}

private final class FakeSummaryProvider: SummaryProvider, @unchecked Sendable {
    let kind: CLIKind
    private let document: SummaryDocument?
    private let error: Error?
    private(set) var callCount = 0

    init(kind: CLIKind, document: SummaryDocument) {
        self.kind = kind
        self.document = document
        self.error = nil
    }

    init(kind: CLIKind, error: Error) {
        self.kind = kind
        self.document = nil
        self.error = error
    }

    private(set) var lastModel: String?
    private(set) var lastReasoning: String?

    func summarize(
        batch: CollectionBatch,
        executableOverride: String?,
        modelOverride: String?,
        reasoningOverride: String?
    ) async throws -> SummaryDocument {
        callCount += 1
        lastModel = modelOverride
        lastReasoning = reasoningOverride
        if let error { throw error }
        return document ?? .empty
    }
}

private struct StaticCLIResolver: CLIResolving {
    func executableURL(for kind: CLIKind, override: String?) -> URL? {
        URL(fileURLWithPath: "/usr/bin/true")
    }

    func status(for kind: CLIKind, override: String?) -> CLIStatus {
        CLIStatus(
            kind: kind,
            executablePath: "/usr/bin/true",
            version: "test",
            logDirectory: "/tmp",
            canReadLogs: true
        )
    }

    func logDirectory(for kind: CLIKind) -> URL {
        URL(fileURLWithPath: "/tmp", isDirectory: true)
    }
}

private final class RecordingProcessRunner: ProcessRunning, @unchecked Sendable {
    private(set) var specifications: [ProcessSpecification] = []

    var nonHelpSpecifications: [ProcessSpecification] {
        return specifications.filter { $0.arguments != ["--help"] }
    }

    func run(_ specification: ProcessSpecification, timeout: TimeInterval) async throws -> ProcessResult {
        specifications.append(specification)

        if specification.arguments == ["--help"] {
            return ProcessResult(
                terminationStatus: 0,
                standardOutput: Data("--output-format --disallowedTools --permission-mode --no-session-persistence --effort".utf8),
                standardError: Data(),
                didTruncateOutput: false
            )
        }

        let document = "{\"overview\":\"provider test\",\"progress\":[],\"currentState\":[],\"decisions\":[],\"blockers\":[],\"nextSteps\":[],\"sessions\":[]}".data(using: .utf8)!
        return ProcessResult(
            terminationStatus: 0,
            standardOutput: document,
            standardError: Data(),
            didTruncateOutput: false
        )
    }
}
