import Foundation
import XCTest
@testable import CapsStack

final class BackendTests: XCTestCase {
    func testCLIResolverHonorsCustomSessionDirectories() {
        let resolver = CLIResolver(
            homeDirectory: URL(fileURLWithPath: "/Users/test", isDirectory: true),
            environment: [
                "CODEX_HOME": "/custom/codex",
                "CLAUDE_CONFIG_DIR": "/custom/claude",
                "XDG_DATA_HOME": "/custom/data",
                "PI_CODING_AGENT_SESSION_DIR": "/custom/pi-sessions"
            ]
        )

        XCTAssertEqual(resolver.logDirectory(for: .codex).path, "/custom/codex/sessions")
        XCTAssertEqual(resolver.logDirectory(for: .claudeCode).path, "/custom/claude/projects")
        XCTAssertEqual(resolver.logDirectory(for: .opencode).path, "/custom/data/opencode")
        XCTAssertEqual(resolver.logDirectory(for: .pi).path, "/custom/pi-sessions")
    }

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

    func testJSONLCollectorCapsMultibyteEventByUTF8Bytes() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("CapsStack-jsonl-utf8-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        let now = Date()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let object: [String: Any] = [
            "timestamp": formatter.string(from: now),
            "session_id": "large",
            "type": "assistant",
            "message": String(repeating: "進捗", count: 20_000)
        ]
        let line = try JSONSerialization.data(withJSONObject: object)
        try line.write(to: root.appendingPathComponent("large.jsonl"), options: .atomic)

        let result = JSONLSessionCollector(provider: .codex, rootDirectory: root).collect(
            interval: AwayInterval(start: now.addingTimeInterval(-1), end: now.addingTimeInterval(1))
        )
        let content = try XCTUnwrap(result.sessions.first?.events.first?.content)
        XCTAssertLessThanOrEqual(content.utf8.count, 32_768)
        XCTAssertNotNil(content.data(using: .utf8))
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
                XCTAssertTrue(specification.arguments.contains(where: { $0 == "--tools" }))
                XCTAssertTrue(specification.arguments.contains(where: { $0 == "--setting-sources" }))
                XCTAssertTrue(specification.arguments.contains(where: { $0 == "--strict-mcp-config" }))
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

    func testSummaryProviderRejectsTruncatedStructuredOutput() async throws {
        let provider = CodexSummaryProvider(
            resolver: StaticCLIResolver(),
            runner: TruncatedProcessRunner(),
            fileManager: .default
        )

        do {
            _ = try await provider.summarize(
                batch: makeBatch(),
                executableOverride: nil,
                modelOverride: nil,
                reasoningOverride: nil
            )
            XCTFail("expected invalid output")
        } catch let error as SummaryProviderError {
            XCTAssertEqual(error, .invalidOutput(.codex))
        }
    }

    func testOpenCode2OverrideFailsBeforeUsingIncompatibleArguments() async throws {
        let runner = RecordingProcessRunner()
        let provider = OpenCodeSummaryProvider(
            resolver: OpenCode2CLIResolver(),
            runner: runner,
            fileManager: .default
        )

        do {
            _ = try await provider.summarize(
                batch: makeBatch(),
                executableOverride: "/usr/local/bin/opencode2",
                modelOverride: nil,
                reasoningOverride: nil
            )
            XCTFail("expected unsupported OpenCode 2 error")
        } catch let error as SummaryProviderError {
            guard case .processFailed(.opencode, let message) = error else {
                return XCTFail("unexpected error: \(error)")
            }
            XCTAssertTrue(message.contains("互換性がありません"))
        }
        XCTAssertTrue(runner.specifications.isEmpty)
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

    func testOpenCodeCollectorDrainsLargeStandardError() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("CapsStack-opencode-stderr-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        let now = Date()
        let stamp = Int(now.timeIntervalSince1970 * 1_000)
        let executable = root.appendingPathComponent("fake-opencode")
        let script = """
        #!/bin/sh
        head -c 200000 /dev/zero >&2
        if [ "$1" = "session" ]; then
          printf '[{"id":"session-1","directory":"/tmp/project","time":{"created":\(stamp),"updated":\(stamp)}}]'
        else
          printf '{"sessionID":"session-1","messages":[{"role":"assistant","time":{"created":\(stamp)},"parts":[{"type":"text","text":"stderr drained"}]}]}'
        fi
        """
        try Data(script.utf8).write(to: executable, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)

        let collector = OpenCodeSessionCollector(
            rootDirectory: root,
            executableURL: executable,
            maxSessions: 10,
            collectionTimeout: 5
        )
        let result = collector.collect(
            interval: AwayInterval(start: now.addingTimeInterval(-5), end: now.addingTimeInterval(5))
        )

        XCTAssertEqual(result.sessions.first?.events.first?.content, "stderr drained")
        XCTAssertTrue(result.issues.isEmpty)
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

    func testProcessRunnerTimeoutKillsTermIgnoringProcess() async throws {
        let runner = ProcessRunner(outputLimit: 1_024)
        let startedAt = Date()

        do {
            _ = try await runner.run(
                ProcessSpecification(
                    executableURL: URL(fileURLWithPath: "/bin/sh"),
                    arguments: ["-c", "trap '' TERM; while :; do sleep 1; done"]
                ),
                timeout: 0.1
            )
            XCTFail("expected timeout")
        } catch let error as ProcessRunnerError {
            XCTAssertEqual(error, .timedOut)
        }

        XCTAssertLessThan(Date().timeIntervalSince(startedAt), 3)
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

    func testSummaryOutputParserRejectsPartialAndCaseCollidingObjects() {
        let partial = Data(#"{"overview":"missing required arrays"}"#.utf8)
        XCTAssertNil(SummaryOutputParser.parse(stdout: partial, provider: .codex))

        let wrongTypes = Data(
            #"{"overview":"wrong types","progress":"not an array","currentState":[],"decisions":[],"blockers":[],"nextSteps":[],"sessions":[]}"#.utf8
        )
        XCTAssertNil(SummaryOutputParser.parse(stdout: wrongTypes, provider: .codex))

        let collision = Data(
            #"{"overview":"first","OVERVIEW":"second","progress":[],"currentState":[],"decisions":[],"blockers":[],"nextSteps":[],"sessions":[]}"#.utf8
        )
        XCTAssertNil(SummaryOutputParser.parse(stdout: collision, provider: .codex))
    }

    func testSummaryOrchestratorPreservesMemoWhenLargeUTF8EventIsSplit() async throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let provider = FakeSummaryProvider(kind: .codex, document: makeDocument("chunk"))
        let orchestrator = SummaryOrchestrator(
            maxInputBytes: 16 * 1_024,
            providers: [.codex: provider]
        )
        let batch = CollectionBatch(
            interval: AwayInterval(start: start, end: start.addingTimeInterval(60)),
            sessions: [CollectedSessionArtifact(
                id: "large-session",
                provider: .codex,
                workingDirectory: "/tmp/project",
                events: [CollectedEvent(
                    timestamp: start,
                    kind: "assistant",
                    content: String(repeating: "進捗", count: 10_000)
                )],
                wasTruncated: false
            )],
            issues: [],
            quickMemo: "GUIで仕様を整理した"
        )

        _ = try await orchestrator.summarize(
            batch: batch,
            preferences: SummarizerPreferences(primary: .codex, automaticFallback: false)
        )

        XCTAssertEqual(provider.callCount, 2)
        XCTAssertNil(provider.receivedBatches.first?.quickMemo)
        XCTAssertEqual(provider.receivedBatches.last?.quickMemo, "GUIで仕様を整理した")
        XCTAssertTrue(provider.receivedBatches.first?.sessions.first?.wasTruncated == true)
        XCTAssertLessThan(
            provider.receivedBatches.first?.sessions.first?.events.first?.content.utf8.count ?? .max,
            16 * 1_024
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        for receivedBatch in provider.receivedBatches {
            XCTAssertLessThanOrEqual(try encoder.encode(receivedBatch).count, 16 * 1_024)
        }
    }

    func testSummaryOrchestratorBoundsPaidChunkCallsAndReportsOmission() async throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let provider = FakeSummaryProvider(kind: .codex, document: makeDocument("bounded"))
        let orchestrator = SummaryOrchestrator(
            maxInputBytes: 16 * 1_024,
            maxChunkCount: 4,
            providers: [.codex: provider]
        )
        let sessions = (0..<12).map { index in
            CollectedSessionArtifact(
                id: "session-\(index)",
                provider: .codex,
                workingDirectory: nil,
                events: [CollectedEvent(
                    timestamp: start.addingTimeInterval(TimeInterval(index)),
                    kind: "assistant",
                    content: String(repeating: "x", count: 12_000)
                )],
                wasTruncated: false
            )
        }
        let batch = CollectionBatch(
            interval: AwayInterval(start: start, end: start.addingTimeInterval(60)),
            sessions: sessions,
            issues: []
        )

        let outcome = try await orchestrator.summarize(
            batch: batch,
            preferences: SummarizerPreferences(primary: .codex, automaticFallback: false)
        )

        XCTAssertEqual(provider.callCount, 5)
        XCTAssertEqual(provider.receivedBatches.first?.sessions.first?.id, "session-0")
        XCTAssertEqual(provider.receivedBatches[3].sessions.first?.id, "session-11")
        XCTAssertTrue(outcome.document.blockers.contains { $0.contains("8個省略") })

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        for receivedBatch in provider.receivedBatches {
            XCTAssertLessThanOrEqual(try encoder.encode(receivedBatch).count, 16 * 1_024)
        }
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

    func testHistoryStorePreservesQuickMemoAcrossPendingAndCompleted() throws {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("CapsStack-memo-history-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: directory) }

        let store = HistoryStore(directoryURL: directory)
        var batch = makeBatch()
        batch.quickMemo = "ChatGPT GUIで仕様を確認中"
        let pending = try store.savePending(batch: batch, errorMessage: nil)
        XCTAssertEqual(pending.quickMemo, "ChatGPT GUIで仕様を確認中")

        let outcome = SummaryOutcome(
            document: makeDocument("completed"),
            provider: .codex,
            fallbackUsed: false
        )
        let completed = try store.saveCompleted(
            batch: batch,
            outcome: outcome,
            replacingPendingID: try XCTUnwrap(pending.pendingArtifactID)
        )
        XCTAssertEqual(completed.quickMemo, "ChatGPT GUIで仕様を確認中")
        XCTAssertEqual(try XCTUnwrap(store.load().first).quickMemo, "ChatGPT GUIで仕様を確認中")
    }

    func testHistoryStoreDoesNotResurrectDeletedPendingEntry() throws {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("CapsStack-deleted-pending-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: directory) }

        let store = HistoryStore(directoryURL: directory)
        let batch = makeBatch()
        let pending = try store.savePending(batch: batch)
        let pendingID = try XCTUnwrap(pending.pendingArtifactID)
        try store.delete(pending.id)

        XCTAssertThrowsError(
            try store.saveCompleted(
                batch: batch,
                outcome: SummaryOutcome(
                    document: makeDocument("late completion"),
                    provider: .codex,
                    fallbackUsed: false
                ),
                replacingPendingID: pendingID
            )
        ) { error in
            XCTAssertEqual(error as? HistoryStoreError, .pendingArtifactNotFound(pendingID))
        }
        XCTAssertThrowsError(try store.replace(pending)) { error in
            XCTAssertEqual(error as? HistoryStoreError, .invalidHistoryData)
        }
        XCTAssertTrue(try store.load().isEmpty)
    }

    func testHistoryStoreDeleteAllRemovesOrphanPendingArtifacts() throws {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("CapsStack-orphan-pending-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: directory) }

        let store = HistoryStore(directoryURL: directory)
        let orphanID = try store.savePendingArtifact(makeBatch())
        let orphanURL = directory
            .appendingPathComponent("Pending", isDirectory: true)
            .appendingPathComponent("\(orphanID.uuidString).json")
        XCTAssertTrue(fileManager.fileExists(atPath: orphanURL.path))

        try store.deleteAll()

        XCTAssertFalse(fileManager.fileExists(atPath: orphanURL.path))
        XCTAssertTrue(try store.load().isEmpty)
    }

    @MainActor
    func testAppControllerSurfacesCorruptedHistoryInsteadOfHidingIt() throws {
        let suiteName = "CapsStackCorruptHistoryTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(suiteName, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("not-json".utf8).write(
            to: directory.appendingPathComponent("history.json"),
            options: .atomic
        )

        let controller = AppController(
            defaults: defaults,
            resolver: StaticCLIResolver(),
            runner: RecordingProcessRunner(),
            historyStore: HistoryStore(directoryURL: directory),
            notifications: SilentBackendNotificationService()
        )

        controller.reloadHistory()

        XCTAssertEqual(controller.phase, .failed)
        XCTAssertTrue(controller.history.isEmpty)
        XCTAssertEqual(controller.lastError, HistoryStoreError.invalidHistoryData.localizedDescription)
    }

    @MainActor
    func testAppControllerRetrySetsSynchronousBusyGuard() async throws {
        let suiteName = "CapsStackRetryGuardTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(suiteName, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = HistoryStore(directoryURL: directory)
        let batch = makeBatch()
        let pending = try store.savePending(batch: batch)
        let runner = DelayedProcessRunner()
        let controller = AppController(
            defaults: defaults,
            resolver: StaticCLIResolver(),
            runner: runner,
            historyStore: store,
            notifications: SilentBackendNotificationService()
        )
        controller.reloadHistory()

        controller.retry(pending)
        XCTAssertEqual(controller.phase, .summarizing)
        // A second click arrives before the first async task has reached the provider. It must
        // be ignored rather than creating another summary task for the same pending artifact.
        controller.retry(pending)
        XCTAssertEqual(controller.phase, .summarizing)

        try await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertEqual(runner.callCount, 1)
        XCTAssertEqual(try store.load().count, 1)
        XCTAssertEqual(try store.load().first?.status, .completed)
    }

    @MainActor
    func testAppControllerRestoresPersistedAwayStartWithoutChangingCapsLock() async throws {
        let suiteName = "CapsStackRestoreAwayTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: PreferenceKeys.capsStackEnabled)
        defaults.set(false, forKey: PreferenceKeys.keepRunningInBackground)
        defaults.set(false, forKey: PreferenceKeys.suppressOriginalCapsLock)
        defaults.set(false, forKey: PreferenceKeys.collectCodex)
        defaults.set(false, forKey: PreferenceKeys.collectClaude)
        defaults.set(false, forKey: PreferenceKeys.collectOpenCode)
        defaults.set(false, forKey: PreferenceKeys.collectPi)
        let storedStart = Date().addingTimeInterval(-300)
        defaults.set(storedStart, forKey: PreferenceKeys.awayStart)

        let monitor = CapsLockMonitor(
            pollingInterval: 60,
            systemStateReader: { true },
            systemStateSetter: { _ in
                XCTFail("suppression was already disabled, so Caps Lock must not be changed")
            }
        )
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(suiteName, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let controller = AppController(
            defaults: defaults,
            monitor: monitor,
            resolver: StaticCLIResolver(),
            runner: RecordingProcessRunner(),
            historyStore: HistoryStore(directoryURL: directory),
            notifications: SilentBackendNotificationService()
        )

        controller.start()

        XCTAssertEqual(controller.phase, .away)
        XCTAssertEqual(controller.awayStartedAt, storedStart)
        XCTAssertEqual(defaults.object(forKey: PreferenceKeys.awayStart) as? Date, storedStart)

        controller.setCapsStackEnabled(false)
        await Task.yield()
    }

    @MainActor
    func testAppControllerCompletesPersistedAwayWorkflowEndToEnd() async throws {
        let suiteName = "CapsStackEndToEndTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: PreferenceKeys.capsStackEnabled)
        defaults.set(false, forKey: PreferenceKeys.keepRunningInBackground)
        defaults.set(false, forKey: PreferenceKeys.suppressOriginalCapsLock)
        defaults.set(true, forKey: PreferenceKeys.collectCodex)
        defaults.set(false, forKey: PreferenceKeys.collectClaude)
        defaults.set(false, forKey: PreferenceKeys.collectOpenCode)
        defaults.set(false, forKey: PreferenceKeys.collectPi)
        defaults.set(CLIKind.codex.rawValue, forKey: PreferenceKeys.primarySummarizer)
        defaults.set(false, forKey: PreferenceKeys.automaticFallback)
        defaults.set("GUIで統合テストを確認", forKey: PreferenceKeys.quickMemo)

        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent(suiteName, isDirectory: true)
        let logs = root.appendingPathComponent("logs", isDirectory: true)
        let historyDirectory = root.appendingPathComponent("history", isDirectory: true)
        try fileManager.createDirectory(at: logs, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        let now = Date()
        let storedStart = now.addingTimeInterval(-60)
        defaults.set(storedStart, forKey: PreferenceKeys.awayStart)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let line = """
        {"timestamp":"\(formatter.string(from: now.addingTimeInterval(-30)))","session_id":"e2e","type":"assistant","message":"統合テストの進捗"}
        """
        try Data(line.utf8).write(
            to: logs.appendingPathComponent("session.jsonl"),
            options: .atomic
        )

        let runner = RecordingProcessRunner()
        let controller = AppController(
            defaults: defaults,
            monitor: CapsLockMonitor(
                pollingInterval: 60,
                systemStateReader: { false },
                systemStateSetter: { _ in XCTFail("Caps Lock must not be changed") }
            ),
            resolver: FixedDirectoryCLIResolver(logDirectory: logs),
            runner: runner,
            historyStore: HistoryStore(directoryURL: historyDirectory),
            notifications: SilentBackendNotificationService()
        )

        controller.start()
        for _ in 0..<200 where controller.phase == .summarizing || controller.phase == .away {
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTAssertEqual(controller.phase, .idle)
        let entry = try XCTUnwrap(controller.history.first)
        XCTAssertEqual(entry.status, .completed)
        XCTAssertEqual(entry.summary?.overview, "provider test")
        XCTAssertEqual(entry.sessionCount, 1)
        XCTAssertEqual(entry.quickMemo, "GUIで統合テストを確認")
        XCTAssertEqual(defaults.string(forKey: PreferenceKeys.quickMemo), "")
        XCTAssertNil(defaults.object(forKey: PreferenceKeys.awayStart))
        XCTAssertTrue(runner.nonHelpSpecifications.contains { $0.arguments.first == "exec" })
        let pendingFiles = try fileManager.contentsOfDirectory(
            at: historyDirectory.appendingPathComponent("Pending", isDirectory: true),
            includingPropertiesForKeys: nil
        )
        XCTAssertTrue(pendingFiles.isEmpty)

        controller.setCapsStackEnabled(false)
        await Task.yield()
    }

    @MainActor
    func testAppControllerSavesEmptyHistoryWhenNoSourceIsSelected() async throws {
        let suiteName = "CapsStackEmptyWorkflowTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: PreferenceKeys.capsStackEnabled)
        defaults.set(false, forKey: PreferenceKeys.keepRunningInBackground)
        defaults.set(false, forKey: PreferenceKeys.suppressOriginalCapsLock)
        defaults.set(false, forKey: PreferenceKeys.collectCodex)
        defaults.set(false, forKey: PreferenceKeys.collectClaude)
        defaults.set(false, forKey: PreferenceKeys.collectOpenCode)
        defaults.set(false, forKey: PreferenceKeys.collectPi)
        defaults.set(Date().addingTimeInterval(-30), forKey: PreferenceKeys.awayStart)

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(suiteName, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let controller = AppController(
            defaults: defaults,
            monitor: CapsLockMonitor(
                pollingInterval: 60,
                systemStateReader: { false },
                systemStateSetter: { _ in XCTFail("Caps Lock must not be changed") }
            ),
            resolver: FixedDirectoryCLIResolver(logDirectory: root),
            runner: RecordingProcessRunner(),
            historyStore: HistoryStore(directoryURL: root.appendingPathComponent("history")),
            notifications: SilentBackendNotificationService()
        )

        controller.start()
        for _ in 0..<200 where controller.phase == .summarizing || controller.phase == .away {
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTAssertEqual(controller.phase, .idle)
        let entry = try XCTUnwrap(controller.history.first)
        XCTAssertEqual(entry.status, .empty)
        XCTAssertEqual(entry.sessionCount, 0)
        XCTAssertEqual(entry.errorMessage, "収集元が選択されていません。")

        controller.setCapsStackEnabled(false)
        await Task.yield()
    }

    @MainActor
    func testAppControllerManualAwayAndReturnCompletesWorkflow() async throws {
        let suiteName = "CapsStackManualAwayTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: PreferenceKeys.capsStackEnabled)
        defaults.set(false, forKey: PreferenceKeys.keepRunningInBackground)
        defaults.set(false, forKey: PreferenceKeys.suppressOriginalCapsLock)
        defaults.set(false, forKey: PreferenceKeys.collectCodex)
        defaults.set(false, forKey: PreferenceKeys.collectClaude)
        defaults.set(false, forKey: PreferenceKeys.collectOpenCode)
        defaults.set(false, forKey: PreferenceKeys.collectPi)

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(suiteName, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let controller = AppController(
            defaults: defaults,
            monitor: CapsLockMonitor(
                pollingInterval: 60,
                systemStateReader: { false },
                systemStateSetter: { _ in XCTFail("Caps Lock must not be changed") }
            ),
            resolver: FixedDirectoryCLIResolver(logDirectory: root),
            runner: RecordingProcessRunner(),
            historyStore: HistoryStore(directoryURL: root.appendingPathComponent("history")),
            notifications: SilentBackendNotificationService()
        )
        controller.start()

        controller.beginAwayManually()
        XCTAssertEqual(controller.phase, .away)
        XCTAssertNotNil(defaults.object(forKey: PreferenceKeys.awayStart) as? Date)

        // Sub-second toggles are intentionally ignored as accidental input.
        try await Task.sleep(nanoseconds: 1_050_000_000)
        controller.endAwayManually()
        for _ in 0..<200 where controller.phase == .summarizing || controller.phase == .away {
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTAssertEqual(controller.phase, .idle)
        XCTAssertNil(defaults.object(forKey: PreferenceKeys.awayStart))
        XCTAssertEqual(controller.history.first?.status, .empty)
        XCTAssertEqual(controller.history.first?.errorMessage, "収集元が選択されていません。")

        controller.setCapsStackEnabled(false)
        await Task.yield()
    }

    @MainActor
    func testAppControllerKeepsPendingArtifactAfterSummaryFailure() async throws {
        let suiteName = "CapsStackFailedWorkflowTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: PreferenceKeys.capsStackEnabled)
        defaults.set(false, forKey: PreferenceKeys.keepRunningInBackground)
        defaults.set(false, forKey: PreferenceKeys.suppressOriginalCapsLock)
        defaults.set(true, forKey: PreferenceKeys.collectCodex)
        defaults.set(false, forKey: PreferenceKeys.collectClaude)
        defaults.set(false, forKey: PreferenceKeys.collectOpenCode)
        defaults.set(false, forKey: PreferenceKeys.collectPi)
        defaults.set(CLIKind.codex.rawValue, forKey: PreferenceKeys.primarySummarizer)
        defaults.set(false, forKey: PreferenceKeys.automaticFallback)
        defaults.set("失敗後も残すメモ", forKey: PreferenceKeys.quickMemo)

        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent(suiteName, isDirectory: true)
        let logs = root.appendingPathComponent("logs", isDirectory: true)
        let historyDirectory = root.appendingPathComponent("history", isDirectory: true)
        try fileManager.createDirectory(at: logs, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }
        let now = Date()
        defaults.set(now.addingTimeInterval(-60), forKey: PreferenceKeys.awayStart)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let line = """
        {"timestamp":"\(formatter.string(from: now.addingTimeInterval(-30)))","session_id":"failed","type":"assistant","message":"保存すべき進捗"}
        """
        try Data(line.utf8).write(
            to: logs.appendingPathComponent("session.jsonl"),
            options: .atomic
        )

        let historyStore = HistoryStore(directoryURL: historyDirectory)
        let controller = AppController(
            defaults: defaults,
            monitor: CapsLockMonitor(
                pollingInterval: 60,
                systemStateReader: { false },
                systemStateSetter: { _ in XCTFail("Caps Lock must not be changed") }
            ),
            resolver: FixedDirectoryCLIResolver(logDirectory: logs),
            runner: FailingSummaryProcessRunner(),
            historyStore: historyStore,
            notifications: SilentBackendNotificationService()
        )

        controller.start()
        for _ in 0..<200 where controller.phase == .summarizing || controller.phase == .away {
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTAssertEqual(controller.phase, .failed)
        let entry = try XCTUnwrap(controller.history.first)
        XCTAssertEqual(entry.status, .pending)
        XCTAssertTrue(entry.errorMessage?.contains("synthetic failure") == true)
        XCTAssertEqual(entry.quickMemo, "失敗後も残すメモ")
        let pendingID = try XCTUnwrap(entry.pendingArtifactID)
        XCTAssertEqual(try historyStore.loadPending(pendingID)?.quickMemo, "失敗後も残すメモ")
        XCTAssertEqual(defaults.string(forKey: PreferenceKeys.quickMemo), "")

        controller.setCapsStackEnabled(false)
        await Task.yield()
    }

    func testSummaryMarkdownIncludesMemoAndSections() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let document = SummaryDocument(
            overview: "要約の概要",
            progress: ["実装を進めた"],
            currentState: [],
            decisions: ["設計を確定"],
            blockers: [],
            nextSteps: ["テストを追加"],
            sessions: []
        )
        let entry = HistoryEntry(
            interval: AwayInterval(start: start, end: start.addingTimeInterval(125)),
            status: .completed,
            summary: document,
            provider: .claudeCode,
            fallbackUsed: true,
            sessionCount: 2,
            sources: [.codex],
            collectionIssues: [],
            errorMessage: nil,
            pendingArtifactID: nil,
            quickMemo: "GUI版エージェントも動いていた"
        )

        let markdown = SummaryMarkdown.document(document, entry: entry)

        XCTAssertTrue(markdown.contains("要約の概要"))
        XCTAssertTrue(markdown.contains("## 進んだ内容"))
        XCTAssertTrue(markdown.contains("- 実装を進めた"))
        XCTAssertTrue(markdown.contains("## 重要な判断"))
        XCTAssertTrue(markdown.contains("## 次の予定"))
        XCTAssertTrue(markdown.contains("**退席前メモ**: GUI版エージェントも動いていた"))
        XCTAssertTrue(markdown.contains("Claude Code CLI（フォールバック）"))
        XCTAssertTrue(markdown.contains("02:05"))
    }

    func testSummaryPromptIncludesQuickMemo() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        var batch = CollectionBatch(
            interval: AwayInterval(start: start, end: start.addingTimeInterval(60)),
            sessions: [],
            issues: []
        )
        batch.quickMemo = "Cursorでリファクタリングしていた"
        let promptData = try SummaryPromptFactory.prompt(for: batch, provider: .codex)
        let prompt = String(decoding: promptData, as: UTF8.self)

        XCTAssertTrue(prompt.contains("quickMemo"))
        XCTAssertTrue(prompt.contains("Cursorでリファクタリングしていた"))
    }

    func testAwayBatchPreparationAddsMemoOnlySessionWhenNoCLILogExists() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let empty = CollectionBatch(
            interval: AwayInterval(start: start, end: start.addingTimeInterval(60)),
            sessions: [],
            issues: [],
            quickMemo: "GUIエージェントだけ使っていた"
        )

        let prepared = AwayBatchPreparation.addingSyntheticMemoSession(empty, provider: .codex)

        XCTAssertEqual(prepared.sessions.count, 1)
        XCTAssertEqual(prepared.sessions.first?.id, "capsstack-quick-memo")
        XCTAssertEqual(prepared.sessions.first?.events.first?.kind, "user-note")
        XCTAssertEqual(prepared.sessions.first?.events.first?.content, "GUIエージェントだけ使っていた")
    }

    func testAwayBatchPreparationDoesNotOverrideCollectedSessions() {
        let collected = makeBatch()
        var batchWithMemo = collected
        batchWithMemo.quickMemo = "補足メモ"

        let prepared = AwayBatchPreparation.addingSyntheticMemoSession(batchWithMemo, provider: .codex)

        XCTAssertEqual(prepared.sessions, collected.sessions)
        XCTAssertEqual(prepared.quickMemo, "補足メモ")
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
    private(set) var receivedBatches: [CollectionBatch] = []

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
        receivedBatches.append(batch)
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

private struct OpenCode2CLIResolver: CLIResolving {
    func executableURL(for kind: CLIKind, override: String?) -> URL? {
        URL(fileURLWithPath: "/usr/local/bin/opencode2")
    }

    func status(for kind: CLIKind, override: String?) -> CLIStatus {
        CLIStatus(
            kind: kind,
            executablePath: "/usr/local/bin/opencode2",
            version: "2.0.0-beta",
            logDirectory: "/tmp",
            canReadLogs: false
        )
    }

    func logDirectory(for kind: CLIKind) -> URL {
        URL(fileURLWithPath: "/tmp", isDirectory: true)
    }
}

private struct FixedDirectoryCLIResolver: CLIResolving {
    let logDirectory: URL

    func executableURL(for kind: CLIKind, override: String?) -> URL? {
        URL(fileURLWithPath: "/usr/bin/true")
    }

    func status(for kind: CLIKind, override: String?) -> CLIStatus {
        CLIStatus(
            kind: kind,
            executablePath: "/usr/bin/true",
            version: "test",
            logDirectory: logDirectory.path,
            canReadLogs: true
        )
    }

    func logDirectory(for kind: CLIKind) -> URL {
        logDirectory
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

private final class DelayedProcessRunner: ProcessRunning, @unchecked Sendable {
    private let stateQueue = DispatchQueue(label: "CapsStackTests.DelayedProcessRunner")
    private var invocations = 0

    var callCount: Int {
        stateQueue.sync { invocations }
    }

    func run(_ specification: ProcessSpecification, timeout: TimeInterval) async throws -> ProcessResult {
        stateQueue.sync { invocations += 1 }
        try await Task.sleep(nanoseconds: 100_000_000)

        let document = "{\"overview\":\"retry\",\"progress\":[],\"currentState\":[],\"decisions\":[],\"blockers\":[],\"nextSteps\":[],\"sessions\":[]}".data(using: .utf8)!
        return ProcessResult(
            terminationStatus: 0,
            standardOutput: document,
            standardError: Data(),
            didTruncateOutput: false
        )
    }
}

private final class TruncatedProcessRunner: ProcessRunning, @unchecked Sendable {
    func run(_ specification: ProcessSpecification, timeout: TimeInterval) async throws -> ProcessResult {
        ProcessResult(
            terminationStatus: 0,
            standardOutput: Data(
                #"{"overview":"partial","progress":[],"currentState":[],"decisions":[],"blockers":[],"nextSteps":[],"sessions":[]}"#.utf8
            ),
            standardError: Data(),
            didTruncateOutput: true
        )
    }
}

private final class FailingSummaryProcessRunner: ProcessRunning, @unchecked Sendable {
    func run(_ specification: ProcessSpecification, timeout: TimeInterval) async throws -> ProcessResult {
        if specification.arguments == ["--version"] {
            return ProcessResult(
                terminationStatus: 0,
                standardOutput: Data("test".utf8),
                standardError: Data(),
                didTruncateOutput: false
            )
        }
        return ProcessResult(
            terminationStatus: 1,
            standardOutput: Data(),
            standardError: Data("synthetic failure".utf8),
            didTruncateOutput: false
        )
    }
}

private final class SilentBackendNotificationService: NotificationServicing, @unchecked Sendable {
    func requestAuthorization() async -> Bool { false }

    func notify(
        outcome: SummaryOutcome,
        interval: AwayInterval,
        sessionCount: Int
    ) async {}

    func notifyFailure(message: String, interval: AwayInterval?) async {}
}
