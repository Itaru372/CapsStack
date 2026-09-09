import Foundation
import XCTest
@testable import CapsStack

final class PendingBriefTests: XCTestCase {
    func testPendingBriefCauseClassificationIsConservative() {
        XCTAssertEqual(
            PendingBriefCause.classify(errorMessage: "Codex CLI summary timed out."),
            .timeout
        )
        XCTAssertEqual(
            PendingBriefCause.classify(errorMessage: "認証状態を確認してください。"),
            .authentication
        )
        XCTAssertEqual(
            PendingBriefCause.classify(errorMessage: "ERROR: You've hit your usage limit."),
            .usageLimit
        )
        XCTAssertEqual(
            PendingBriefCause.classify(errorMessage: "Codex CLI failed to run: synthetic failure"),
            .other
        )
        XCTAssertEqual(PendingBriefCause.classify(errorMessage: nil), .unknown)
        XCTAssertTrue(PendingBriefCause.timeout.isBulkRetryable)
        XCTAssertFalse(PendingBriefCause.authentication.isBulkRetryable)
        XCTAssertFalse(PendingBriefCause.usageLimit.isBulkRetryable)
        XCTAssertFalse(PendingBriefCause.unknown.isBulkRetryable)
    }

    func testHistoryStoreAssessmentReadsWithoutChangingHistoryOrArtifact() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CapsStack-pending-assessment-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = HistoryStore(directoryURL: directory)
        let timeoutEntry = try store.savePending(
            batch: makeBatch(id: "timeout"),
            errorMessage: "Codex CLI summary timed out."
        )
        _ = try store.savePending(
            batch: makeBatch(id: "auth"),
            errorMessage: "Authentication required."
        )
        _ = try store.savePending(
            batch: makeBatch(id: "limit"),
            errorMessage: "You've hit your usage limit."
        )

        let pendingID = try XCTUnwrap(timeoutEntry.pendingArtifactID)
        let artifactURL = store.pendingDirectoryURL
            .appendingPathComponent("\(pendingID.uuidString).json")
        let artifactBefore = try Data(contentsOf: artifactURL)
        let historyBefore = try store.load()

        let assessments = store.pendingBriefAssessments(for: historyBefore)

        XCTAssertEqual(assessments.count, 3)
        XCTAssertEqual(assessments.filter { $0.cause == .timeout }.count, 1)
        XCTAssertEqual(assessments.filter { $0.cause == .authentication }.count, 1)
        XCTAssertEqual(assessments.filter { $0.cause == .usageLimit }.count, 1)
        XCTAssertEqual(assessments.filter { $0.isBulkRetryable }.map(\.entry.id), [timeoutEntry.id])
        XCTAssertTrue(assessments.first(where: { $0.entry.errorMessage == "Authentication required." })?.isManuallyRetryable == true)
        XCTAssertTrue(assessments.first(where: { $0.entry.errorMessage == "You've hit your usage limit." })?.isManuallyRetryable == true)
        XCTAssertEqual(try Data(contentsOf: artifactURL), artifactBefore)
        XCTAssertEqual(try store.load(), historyBefore)
    }

    func testMalformedPendingArtifactIsNotRetryable() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CapsStack-pending-malformed-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = HistoryStore(directoryURL: directory)
        let pending = try store.savePending(
            batch: makeBatch(id: "malformed"),
            errorMessage: "Codex CLI summary timed out."
        )
        let pendingID = try XCTUnwrap(pending.pendingArtifactID)
        let artifactURL = store.pendingDirectoryURL
            .appendingPathComponent("\(pendingID.uuidString).json")
        try Data("not-json".utf8).write(to: artifactURL, options: .atomic)

        XCTAssertEqual(store.pendingArtifactAvailability(for: pendingID), .malformed)
        let assessment = try XCTUnwrap(
            store.pendingBriefAssessments(for: try store.load()).first
        )

        XCTAssertEqual(assessment.artifactAvailability, .malformed)
        XCTAssertFalse(assessment.isBulkRetryable)
        XCTAssertFalse(assessment.isManuallyRetryable)
    }

    @MainActor
    func testBulkRetryCompletesOnlyTimeoutsAndKeepsBlockedArtifacts() async throws {
        let suiteName = "CapsStackPendingBulkRetryTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: PreferenceKeys.capsStackEnabled)
        defaults.set(false, forKey: PreferenceKeys.automaticFallback)
        defaults.set(CLIKind.codex.rawValue, forKey: PreferenceKeys.primarySummarizer)
        defaults.set(true, forKey: PreferenceKeys.cliDefaultsInitialized)

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(suiteName, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = HistoryStore(directoryURL: directory)
        let timeout = try store.savePending(
            batch: makeBatch(id: "timeout"),
            errorMessage: "Codex CLI summary timed out."
        )
        let authentication = try store.savePending(
            batch: makeBatch(id: "authentication"),
            errorMessage: "Authentication required."
        )
        let usageLimit = try store.savePending(
            batch: makeBatch(id: "usage-limit"),
            errorMessage: "You've hit your usage limit."
        )
        let runner = PendingBulkSummaryRunner()
        let controller = AppController(
            defaults: defaults,
            resolver: PendingBulkResolver(),
            runner: runner,
            historyStore: store,
            notifications: PendingBriefNoopNotifications(),
            locale: Locale(identifier: "en")
        )
        controller.reloadHistory()

        XCTAssertEqual(controller.pendingBriefAssessments.filter { $0.isBulkRetryable }.count, 1)
        controller.retryEligiblePendingBriefs()

        for _ in 0..<200 where controller.pendingRetryProgress != nil || controller.phase == .summarizing {
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        let entries = try store.load()
        XCTAssertEqual(controller.phase, .idle)
        XCTAssertEqual(runner.callCount, 1)
        XCTAssertEqual(entries.first(where: { $0.id == timeout.id })?.status, .completed)
        XCTAssertEqual(entries.first(where: { $0.id == authentication.id })?.status, .pending)
        XCTAssertEqual(entries.first(where: { $0.id == usageLimit.id })?.status, .pending)
        XCTAssertNil(entries.first(where: { $0.id == timeout.id })?.pendingArtifactID)
        XCTAssertNotNil(entries.first(where: { $0.id == authentication.id })?.pendingArtifactID)
        XCTAssertNotNil(entries.first(where: { $0.id == usageLimit.id })?.pendingArtifactID)
    }

    private func makeBatch(id: String) -> CollectionBatch {
        let start = Date(timeIntervalSince1970: 1_700_000_000 + Double(id.hashValue & 0xFF))
        return CollectionBatch(
            interval: AwayInterval(start: start, end: start.addingTimeInterval(60)),
            sessions: [CollectedSessionArtifact(
                id: id,
                provider: .codex,
                workingDirectory: nil,
                events: [CollectedEvent(timestamp: start, kind: "assistant", content: "progress")],
                wasTruncated: false
            )],
            issues: []
        )
    }
}

private struct PendingBulkResolver: CLIResolving {
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

private final class PendingBulkSummaryRunner: ProcessRunning, @unchecked Sendable {
    private let stateQueue = DispatchQueue(label: "CapsStackTests.PendingBulkSummaryRunner")
    private var invocations = 0

    var callCount: Int {
        stateQueue.sync { invocations }
    }

    func run(_ specification: ProcessSpecification, timeout: TimeInterval) async throws -> ProcessResult {
        stateQueue.sync { invocations += 1 }
        let output = Data(
            #"{"overview":"bulk retry","progress":[],"currentState":[],"decisions":[],"blockers":[],"nextSteps":[],"sessions":[]}"#.utf8
        )
        return ProcessResult(
            terminationStatus: 0,
            standardOutput: output,
            standardError: Data(),
            didTruncateOutput: false
        )
    }
}

private final class PendingBriefNoopNotifications: NotificationServicing, @unchecked Sendable {
    func requestAuthorization() async -> Bool { false }

    func notify(outcome: SummaryOutcome, interval: AwayInterval, sessionCount: Int) async {}

    func notifyFailure(message: String, interval: AwayInterval?) async {}
}
