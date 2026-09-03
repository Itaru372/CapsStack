import XCTest
@testable import CapsStack

final class ModelTests: XCTestCase {
    func testHistoryExportFilenameIsPortableAndDeterministic() throws {
        let utc = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let date = Date(timeIntervalSince1970: 1_700_000_000)

        let fileName = HistoryExportNaming.fileName(for: date, timeZone: utc)

        XCTAssertEqual(fileName, "CapsStack-2023-11-14_22-13.md")
        XCTAssertFalse(fileName.contains("/"))
        XCTAssertFalse(fileName.contains(":"))
    }

    func testSummaryMarkdownExportsEntriesWithoutSummary() {
        let entry = HistoryEntry(
            interval: AwayInterval(
                start: Date(timeIntervalSince1970: 1_700_000_000),
                end: Date(timeIntervalSince1970: 1_700_000_120)
            ),
            status: .pending,
            sessionCount: 2,
            sources: [.codex, .claudeCode],
            collectionIssues: [
                CollectionIssue(provider: .claudeCode, message: "ログディレクトリがありません")
            ],
            errorMessage: "要約CLIがタイムアウトしました。",
            quickMemo: "復帰後に確認する"
        )

        let markdown = SummaryMarkdown.document(for: entry)

        XCTAssertTrue(markdown.contains("状態**: 要約待ち"))
        XCTAssertTrue(markdown.contains("収集元**: Codex, Claude Code"))
        XCTAssertTrue(markdown.contains("要約CLIがタイムアウトしました。"))
        XCTAssertTrue(markdown.contains("退席前メモ**: 復帰後に確認する"))
        XCTAssertTrue(markdown.contains("Claude Code: ログディレクトリがありません"))
    }

    func testBrandAssetsArePackaged() {
        XCTAssertNotNil(BrandAssets.nsImage(named: "CapsStackAppIcon"))
        XCTAssertNotNil(BrandAssets.nsImage(named: "CapsStackMenuBar"))
        for name in ["AgentKilo", "AgentGoose", "AgentQwen", "AgentContinue", "AgentGemini"] {
            XCTAssertNotNil(Bundle.module.url(forResource: name, withExtension: "png"))
        }
    }

    @MainActor
    func testInMemoryDemoDataNeverWritesToHistoryStore() throws {
        let suiteName = "CapsStackDemoDataTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(suiteName, isDirectory: true)
        let store = HistoryStore(directoryURL: directory)
        let controller = AppController(
            defaults: defaults,
            historyStore: store,
            notifications: EmptyNotificationService(),
            showsInMemoryDemoData: true
        )

        controller.reloadHistory()
        XCTAssertEqual(controller.history.count, 7)
        XCTAssertTrue(controller.isShowingDemoData)

        controller.delete(try XCTUnwrap(controller.history.first))
        XCTAssertEqual(controller.history.count, 6)
        XCTAssertTrue(try store.load().isEmpty)

        let normalController = AppController(
            defaults: defaults,
            historyStore: store,
            notifications: EmptyNotificationService(),
            showsInMemoryDemoData: false
        )
        _ = try store.save(
            HistoryEntry(
                interval: AwayInterval(start: .now.addingTimeInterval(-60), end: .now),
                status: .empty,
                sessionCount: 0,
                sources: []
            )
        )
        normalController.reloadHistory()
        XCTAssertEqual(normalController.history.count, 1)
        XCTAssertFalse(normalController.isShowingDemoData)
    }

    @MainActor
    func testAppControllerAppliesCapsStackEnabledImmediately() throws {
        let suiteName = "CapsStackFeatureToggleTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let controller = AppController(
            defaults: defaults,
            historyStore: HistoryStore(
                directoryURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent(suiteName, isDirectory: true)
            ),
            notifications: EmptyNotificationService()
        )

        XCTAssertTrue(controller.isCapsStackEnabled)
        controller.setCapsStackEnabled(false)
        XCTAssertFalse(controller.isCapsStackEnabled)
        XCTAssertEqual(controller.phase, .disabled)

        controller.setCapsStackEnabled(true)
        XCTAssertTrue(controller.isCapsStackEnabled)
        XCTAssertEqual(controller.phase, .idle)
    }

    @MainActor
    func testProviderTestCanBeCancelledWithoutLeavingBusyState() async throws {
        let suiteName = "CapsStackProviderTestCancellation.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let controller = AppController(
            defaults: defaults,
            resolver: TestCLIResolver(),
            runner: BlockingProcessRunner(),
            historyStore: HistoryStore(
                directoryURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent(suiteName, isDirectory: true)
            ),
            notifications: EmptyNotificationService()
        )

        controller.startProviderTest(.codex)
        for _ in 0..<100 {
            if controller.testingProvider != nil { break }
            await Task.yield()
        }
        XCTAssertEqual(controller.testingProvider, .codex)

        controller.cancelProviderTest()
        XCTAssertNil(controller.testingProvider)
        XCTAssertEqual(controller.providerTestMessages[.codex], "キャンセルしました")
        await Task.yield()
    }

    func testCollectorAndSummarizerPreferencesAreIndependent() throws {
        let suiteName = "CapsStackTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(false, forKey: PreferenceKeys.collectCodex)
        defaults.set(true, forKey: PreferenceKeys.collectClaude)
        defaults.set(CLIKind.codex.rawValue, forKey: PreferenceKeys.primarySummarizer)
        defaults.set("gpt-test", forKey: PreferenceKeys.codexModel)
        defaults.set("high", forKey: PreferenceKeys.codexReasoning)

        let collectors = CollectorPreferences(defaults: defaults)
        let summarizer = SummarizerPreferences(defaults: defaults)

        XCTAssertEqual(collectors.enabledSources, [.claudeCode])
        XCTAssertEqual(summarizer.primary, .codex)
        XCTAssertEqual(summarizer.modelOverride(for: .codex), "gpt-test")
        XCTAssertEqual(summarizer.reasoningOverride(for: .codex), "high")
        XCTAssertNil(summarizer.modelOverride(for: .pi))
    }

    func testRepeatedPreferenceReadsDoNotRepostDefaultsChanges() throws {
        let suiteName = "CapsStackPreferenceNotificationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        // Prime registration before observing. Reads that follow must not call
        // register(defaults:) again and must therefore not feed AppController's observer loop.
        _ = AwayThresholdPreferences(defaults: defaults)
        _ = CapsStackFeaturePreferences(defaults: defaults)
        _ = CollectorPreferences(defaults: defaults)
        _ = SummarizerPreferences(defaults: defaults)

        var changeCount = 0
        let token = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: defaults,
            queue: nil
        ) { _ in
            changeCount += 1
        }
        defer { NotificationCenter.default.removeObserver(token) }

        for _ in 0..<100 {
            _ = AwayThresholdPreferences(defaults: defaults)
            _ = CapsStackFeaturePreferences(defaults: defaults)
            _ = CollectorPreferences(defaults: defaults)
            _ = SummarizerPreferences(defaults: defaults)
        }

        XCTAssertEqual(changeCount, 0)
    }

    func testCollectorOnlyAgentCannotBecomePrimarySummarizer() throws {
        let suiteName = "CapsStackCollectorOnlyPrimaryTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(CLIKind.geminiCLI.rawValue, forKey: PreferenceKeys.primarySummarizer)

        XCTAssertEqual(SummarizerPreferences(defaults: defaults).primary, .codex)
    }

    func testSummaryDocumentRoundTripsAsJSON() throws {
        let document = SummaryDocument(
            overview: "認証フローを整理しました。",
            progress: ["API接続を完了"],
            currentState: ["テスト中"],
            decisions: ["Keychainを使用"],
            blockers: [],
            nextSteps: ["回帰テスト"],
            sessions: [
                SessionSummary(sessionID: "session-1", source: "Codex CLI", summary: "実装を進行")
            ]
        )

        let data = try JSONEncoder().encode(document)
        XCTAssertEqual(try JSONDecoder().decode(SummaryDocument.self, from: data), document)
    }

    func testDurationFormatterUsesClockStyle() {
        XCTAssertEqual(DurationFormatter.string(from: 65), "01:05")
        XCTAssertEqual(DurationFormatter.string(from: 3_661), "01:01:01")
        XCTAssertEqual(DurationFormatter.string(from: -4), "00:00")
    }

    func testAwayThresholdPreferencesClampValues() {
        XCTAssertEqual(AwayThresholdPreferences(minimumAwaySeconds: -10).minimumAwaySeconds, 0)
        XCTAssertEqual(AwayThresholdPreferences(minimumAwaySeconds: 30).minimumAwaySeconds, 30)
        XCTAssertEqual(AwayThresholdPreferences(minimumAwaySeconds: 7200).minimumAwaySeconds, 3600)
    }

    func testQuickMemoPreferencesTrimsAndSaves() throws {
        let suiteName = "CapsStackQuickMemoTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let memo = QuickMemoPreferences(text: "  ChatGPTデスクトップで資料を整理中\n")
        memo.save(to: defaults)

        let loaded = QuickMemoPreferences(defaults: defaults)
        XCTAssertEqual(loaded.text, "ChatGPTデスクトップで資料を整理中")
        XCTAssertEqual(loaded.trimmedText, "ChatGPTデスクトップで資料を整理中")
    }

    func testQuickMemoPreferencesCapsUTF8SizeWithoutBreakingCharacters() {
        let memo = QuickMemoPreferences(text: String(repeating: "進捗", count: 20_000))

        XCTAssertLessThanOrEqual(memo.text.utf8.count, QuickMemoPreferences.maximumUTF8Bytes)
        XCTAssertNotNil(memo.text.data(using: .utf8))
        XCTAssertFalse(memo.text.isEmpty)
    }

    func testCollectionBatchDecodesLegacyJSONWithoutQuickMemo() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let batch = CollectionBatch(
            interval: AwayInterval(start: start, end: start.addingTimeInterval(60)),
            sessions: [],
            issues: [],
            quickMemo: nil
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(batch)
        let formatter = ISO8601DateFormatter()
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        XCTAssertNil(try decoder.decode(CollectionBatch.self, from: data).quickMemo)

        // Also verify a manually constructed JSON with dates as ISO strings works.
        let json = """
        {
          "id": "11111111-2222-3333-4444-555555555555",
          "interval": {"start": "\(formatter.string(from: start))", "end": "\(formatter.string(from: start.addingTimeInterval(60)))"},
          "sessions": [],
          "issues": [],
          "quickMemo": "GUIエージェントのメモ"
        }
        """.data(using: .utf8)!
        XCTAssertEqual(try decoder.decode(CollectionBatch.self, from: json).quickMemo, "GUIエージェントのメモ")
    }
}

private struct TestCLIResolver: CLIResolving {
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

private final class BlockingProcessRunner: ProcessRunning, @unchecked Sendable {
    func run(_ specification: ProcessSpecification, timeout: TimeInterval) async throws -> ProcessResult {
        try await Task.sleep(nanoseconds: 10_000_000_000)
        return ProcessResult(
            terminationStatus: 0,
            standardOutput: Data(
                #"{"overview":"test","progress":[],"currentState":[],"decisions":[],"blockers":[],"nextSteps":[],"sessions":[]}"#.utf8
            ),
            standardError: Data(),
            didTruncateOutput: false
        )
    }
}

private final class EmptyNotificationService: NotificationServicing, @unchecked Sendable {
    func requestAuthorization() async -> Bool { false }
    func notify(outcome: SummaryOutcome, interval: AwayInterval, sessionCount: Int) async {}
    func notifyFailure(message: String, interval: AwayInterval?) async {}
}
