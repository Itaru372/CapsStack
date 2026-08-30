import XCTest
@testable import CapsStack

final class TelemetryTests: XCTestCase {
    func testTelemetryPreferencesAreOptInAndPersist() throws {
        let suiteName = "CapsStackTelemetryPreferencesTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertFalse(TelemetryPreferences(defaults: defaults).isEnabled)

        TelemetryPreferences(isEnabled: true).save(to: defaults)

        XCTAssertTrue(TelemetryPreferences(defaults: defaults).isEnabled)
    }

    func testTelemetryBucketsDoNotExposeExactDurationsOrCounts() {
        XCTAssertEqual(TelemetryBuckets.awayDuration(0), "under_1m")
        XCTAssertEqual(TelemetryBuckets.awayDuration(299), "1_to_5m")
        XCTAssertEqual(TelemetryBuckets.awayDuration(7_200), "over_2h")
        XCTAssertEqual(TelemetryBuckets.summaryDuration(14), "5_to_15s")
        XCTAssertEqual(TelemetryBuckets.count(0), "0")
        XCTAssertEqual(TelemetryBuckets.count(4), "2_to_5")
        XCTAssertEqual(TelemetryBuckets.count(99), "6_plus")
    }

    func testTelemetryEventPropertiesContainOnlyReviewedFields() {
        let event = TelemetryEvent.briefCompleted(
            provider: .codex,
            fallbackUsed: true,
            awayDuration: 600,
            sessionCount: 7,
            summaryDuration: 18
        )

        XCTAssertEqual(event.name, "return brief completed")
        XCTAssertEqual(event.properties["provider"] as? String, "codex")
        XCTAssertEqual(event.properties["fallback_used"] as? Bool, true)
        XCTAssertEqual(event.properties["away_duration_bucket"] as? String, "5_to_30m")
        XCTAssertEqual(event.properties["session_count_bucket"] as? String, "6_plus")
        XCTAssertEqual(event.properties["summary_duration_bucket"] as? String, "15_to_60s")
        XCTAssertFalse(event.properties.keys.contains { key in
            ["content", "memo", "working_directory", "path", "session_id", "error_message"].contains(key)
        })
    }

    func testTelemetryConfigurationPrefersTrimmedEnvironmentToken() {
        let environment = [
            PostHogTelemetryConfiguration.projectTokenEnvironmentKey: "  phc_test  ",
            PostHogTelemetryConfiguration.hostEnvironmentKey: " https://eu.i.posthog.com "
        ]

        XCTAssertEqual(
            PostHogTelemetryConfiguration.projectToken(bundle: Bundle(for: TelemetryTests.self), environment: environment),
            "phc_test"
        )
        XCTAssertEqual(
            PostHogTelemetryConfiguration.host(bundle: Bundle(for: TelemetryTests.self), environment: environment),
            "https://eu.i.posthog.com"
        )
    }

    func testFailureMappingNeverIncludesRawErrorText() {
        let error = SummaryProviderError.processFailed(.codex, "a path and secret-like message")
        XCTAssertEqual(TelemetryFailureCode.from(error: error), .processFailed)
        XCTAssertFalse(TelemetryFailureCode.from(error: error).rawValue.contains("secret"))
    }

    @MainActor
    func testControllerToggleRecordsConsentAndHistoryActions() throws {
        let suiteName = "CapsStackTelemetryControllerTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let telemetry = RecordingTelemetryClient()
        let controller = AppController(
            defaults: defaults,
            historyStore: HistoryStore(
                directoryURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent(suiteName, isDirectory: true)
            ),
            notifications: EmptyNotificationService(),
            telemetry: telemetry
        )

        XCTAssertTrue(controller.isTelemetryConfigured)
        XCTAssertFalse(controller.isTelemetryEnabled)
        XCTAssertTrue(telemetry.events.isEmpty)

        controller.setTelemetryEnabled(true)
        XCTAssertTrue(controller.isTelemetryEnabled)
        XCTAssertEqual(telemetry.events, [.telemetryEnabled])

        let entry = HistoryEntry(
            interval: AwayInterval(start: .now.addingTimeInterval(-60), end: .now),
            status: .completed,
            sessionCount: 1,
            sources: [.codex]
        )
        controller.recordHistoryAction(.copied, for: entry)
        XCTAssertEqual(telemetry.events.last, .briefConsumed(action: .copied, status: .completed))

        controller.setTelemetryEnabled(false)
        XCTAssertFalse(controller.isTelemetryEnabled)
        XCTAssertEqual(telemetry.events.count, 2)
    }
}

@MainActor
private final class RecordingTelemetryClient: TelemetryClient {
    let isConfigured = true
    private(set) var isEnabled = false
    private(set) var events: [TelemetryEvent] = []

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
    }

    func capture(_ event: TelemetryEvent) {
        guard isEnabled else { return }
        events.append(event)
    }
}

private final class EmptyNotificationService: NotificationServicing, @unchecked Sendable {
    func requestAuthorization() async -> Bool { false }
    func notify(outcome: SummaryOutcome, interval: AwayInterval, sessionCount: Int) async {}
    func notifyFailure(message: String, interval: AwayInterval?) async {}
}
