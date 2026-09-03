import Foundation
import XCTest
@testable import CapsStack

final class CLIModelCatalogTests: XCTestCase {
    func testOnlyCLIsWithStableListingBoundariesAdvertiseModelSelection() {
        XCTAssertEqual(
            CLIKind.modelListingCases,
            [.codex, .opencode, .pi, .kiloCode]
        )
        XCTAssertFalse(CLIKind.claudeCode.supportsModelListing)
        XCTAssertFalse(CLIKind.githubCopilot.supportsModelListing)
        XCTAssertFalse(CLIKind.goose.supportsModelListing)
        XCTAssertFalse(CLIKind.qwenCode.supportsModelListing)
    }

    func testParserReadsProviderModelIDsFromText() {
        let output = """
        openai/gpt-5.4
        anthropic/claude-sonnet-4-5 [default]
        openai/gpt-5.4
        """

        let models = CLIModelCatalogParser.parse(
            stdout: Data(output.utf8),
            kind: .opencode
        )

        XCTAssertEqual(
            models,
            [
                CLIModel(id: "openai/gpt-5.4"),
                CLIModel(id: "anthropic/claude-sonnet-4-5")
            ]
        )
    }

    func testParserCombinesPiProviderAndModelColumns() {
        let output = """
        provider         model                    context    max-out  thinking  images
        anthropic        claude-sonnet-4-5        200K       8K       yes       yes
        openai            gpt-5.4                  128K       16K      no        yes
        custom            my-private-model        32K        4K       yes       no
        """

        let models = CLIModelCatalogParser.parse(
            stdout: Data(output.utf8),
            kind: .pi
        )

        XCTAssertEqual(
            models.map(\.id),
            ["anthropic/claude-sonnet-4-5", "openai/gpt-5.4", "custom/my-private-model"]
        )
    }

    func testParserReadsJSONDisplayNames() {
        let json = #"{"models":[{"slug":"openai/gpt-5.5","display_name":"GPT-5.5"},{"slug":"anthropic/claude-sonnet-4.6","display_name":"Claude Sonnet"}]}"#
        let models = CLIModelCatalogParser.parse(
            stdout: Data(json.utf8),
            kind: .opencode
        )

        XCTAssertEqual(models.first, CLIModel(id: "openai/gpt-5.5", displayName: "GPT-5.5"))
        XCTAssertTrue(models.contains(CLIModel(id: "anthropic/claude-sonnet-4.6", displayName: "Claude Sonnet")))
    }

    func testCatalogUsesTheCLIListingCommandAndPreservesOutputOrder() async throws {
        let runner = RecordingModelRunner(output: """
        provider         model                    context    max-out  thinking  images
        anthropic        claude-sonnet-4-5        200K       8K       yes       yes
        openai            gpt-5.4                  128K       16K      no        yes
        custom            my-private-model        32K        4K       yes       no
        """)
        let service = CLIModelCatalogService(
            resolver: ModelCatalogResolver(),
            runner: runner,
            timeout: 1
        )

        let models = try await service.models(for: .pi, executableOverride: nil)

        XCTAssertEqual(runner.specification?.arguments, ["--list-models"])
        XCTAssertEqual(
            models.map(\.id),
            ["anthropic/claude-sonnet-4-5", "openai/gpt-5.4", "custom/my-private-model"]
        )
    }

    func testCatalogUsesCodexBundledModelCatalog() async throws {
        let runner = RecordingModelRunner(output: #"{"models":[{"slug":"gpt-5.5","display_name":"GPT-5.5"}]}"#)
        let service = CLIModelCatalogService(
            resolver: ModelCatalogResolver(),
            runner: runner,
            timeout: 1
        )

        let models = try await service.models(for: .codex, executableOverride: nil)

        XCTAssertEqual(runner.specification?.arguments, ["debug", "models", "--bundled"])
        XCTAssertEqual(models, [CLIModel(id: "gpt-5.5", displayName: "GPT-5.5")])
    }

    @MainActor
    func testControllerPublishesFetchedModelsForAListingCapableCLI() async throws {
        let suiteName = "CapsStackModelCatalogControllerTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let listing = StubModelListing(models: [CLIModel(id: "openai/gpt-5.4")])
        let controller = AppController(
            defaults: defaults,
            resolver: ModelCatalogResolver(),
            modelListing: listing,
            historyStore: HistoryStore(
                directoryURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent(suiteName, isDirectory: true)
            ),
            notifications: ModelCatalogNotificationService()
        )

        await controller.refreshCLIModels(for: CLIKind.pi)

        XCTAssertEqual(controller.models(for: CLIKind.pi), [CLIModel(id: "openai/gpt-5.4")])
        XCTAssertEqual(controller.modelFetchState(for: CLIKind.pi), CLIModelFetchState.loaded)
        XCTAssertEqual(listing.requestedKinds, [CLIKind.pi])

        await controller.refreshCLIModels(for: CLIKind.claudeCode)
        XCTAssertEqual(controller.modelFetchState(for: CLIKind.claudeCode), CLIModelFetchState.idle)
    }
}

private struct ModelCatalogResolver: CLIResolving {
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

private final class RecordingModelRunner: ProcessRunning, @unchecked Sendable {
    let output: String
    private(set) var specification: ProcessSpecification?

    init(output: String) {
        self.output = output
    }

    func run(_ specification: ProcessSpecification, timeout: TimeInterval) async throws -> ProcessResult {
        self.specification = specification
        return ProcessResult(
            terminationStatus: 0,
            standardOutput: Data(output.utf8),
            standardError: Data(),
            didTruncateOutput: false
        )
    }
}

private final class StubModelListing: CLIModelListing, @unchecked Sendable {
    let modelsToReturn: [CLIModel]
    private(set) var requestedKinds: [CLIKind] = []

    init(models: [CLIModel]) {
        self.modelsToReturn = models
    }

    func models(for kind: CLIKind, executableOverride: String?) async throws -> [CLIModel] {
        requestedKinds.append(kind)
        return modelsToReturn
    }
}

private final class ModelCatalogNotificationService: NotificationServicing, @unchecked Sendable {
    func requestAuthorization() async -> Bool { false }

    func notify(
        outcome: SummaryOutcome,
        interval: AwayInterval,
        sessionCount: Int
    ) async {}

    func notifyFailure(message: String, interval: AwayInterval?) async {}
}
