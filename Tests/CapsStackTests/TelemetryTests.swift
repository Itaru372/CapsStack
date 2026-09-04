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

    func testActivationEventPropertiesUseTheReviewedSchema() {
        XCTAssertEqual(
            Set(TelemetryFeedbackReason.allCases.map(\.rawValue)),
            ["helpful", "missing_important_context", "too_verbose", "incorrect_or_misleading"]
        )

        let setup = TelemetryEvent.setupCompleted(collectorCount: 7, summarizer: .codex)
        XCTAssertEqual(setup.name, "setup_completed")
        XCTAssertEqual(
            Set(setup.properties.keys),
            ["collector_count_bucket", "summarizer", "telemetry_enabled"]
        )
        XCTAssertEqual(setup.properties["collector_count_bucket"] as? String, "6_plus")
        XCTAssertEqual(setup.properties["summarizer"] as? String, "codex")
        XCTAssertEqual(setup.properties["telemetry_enabled"] as? Bool, true)

        let firstBrief = TelemetryEvent.firstReturnBriefCompleted(
            provider: .claudeCode,
            fallbackUsed: true,
            awayDuration: 600,
            summaryDuration: 18
        )
        XCTAssertEqual(firstBrief.name, "first_return_brief_completed")
        XCTAssertEqual(
            Set(firstBrief.properties.keys),
            ["provider", "fallback_used", "away_duration_bucket", "summary_duration_bucket"]
        )
        XCTAssertEqual(firstBrief.properties["provider"] as? String, "claudeCode")
        XCTAssertEqual(firstBrief.properties["fallback_used"] as? Bool, true)
        XCTAssertEqual(firstBrief.properties["away_duration_bucket"] as? String, "5_to_30m")
        XCTAssertEqual(firstBrief.properties["summary_duration_bucket"] as? String, "15_to_60s")

        let feedback = TelemetryEvent.briefFeedbackSubmitted(reason: .missingImportantContext)
        XCTAssertEqual(feedback.name, "brief_feedback_submitted")
        XCTAssertEqual(Set(feedback.properties.keys), ["rating_reason", "status"])
        XCTAssertEqual(feedback.properties["rating_reason"] as? String, "missing_important_context")
        XCTAssertEqual(feedback.properties["status"] as? String, HistoryStatus.completed.rawValue)

        for event in [setup, firstBrief, feedback] {
            XCTAssertFalse(event.properties.keys.contains { key in
                ["content", "memo", "working_directory", "path", "session_id", "model_id", "error_message", "feedback"].contains(key)
            })
        }
    }

    func testExistingEventNamesRemainCompatible() {
        XCTAssertEqual(TelemetryEvent.applicationStarted.name, "app launched")
        XCTAssertEqual(TelemetryEvent.telemetryEnabled.name, "telemetry enabled")
        let consumed = TelemetryEvent.briefConsumed(action: .viewed, status: .completed)
        XCTAssertEqual(consumed.name, "return brief consumed")
        XCTAssertEqual(Set(consumed.properties.keys), ["action", "status"])
        XCTAssertEqual(consumed.properties["action"] as? String, "viewed")
        XCTAssertEqual(consumed.properties["status"] as? String, HistoryStatus.completed.rawValue)
        XCTAssertEqual(
            TelemetryEvent.briefCompleted(
                provider: .codex,
                fallbackUsed: false,
                awayDuration: 60,
                sessionCount: 1,
                summaryDuration: 5
            ).name,
            "return brief completed"
        )
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

    @MainActor
    func testControllerRecordsSetupAndStructuredFeedbackOnlyAfterOptIn() throws {
        let suiteName = "CapsStackTelemetryActivationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(true, forKey: PreferenceKeys.collectCodex)
        defaults.set(CLIKind.codex.rawValue, forKey: PreferenceKeys.primarySummarizer)

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
        let entry = HistoryEntry(
            interval: AwayInterval(start: .now.addingTimeInterval(-60), end: .now),
            status: .completed,
            provider: .codex,
            sessionCount: 1,
            sources: [.codex]
        )

        controller.recordHistoryAction(.viewed, for: entry)
        XCTAssertFalse(controller.recordBriefFeedback(.helpful, for: entry))
        controller.recordFirstReturnBriefCompleted(for: entry, summaryDuration: 18)
        controller.completeSetup()
        XCTAssertTrue(defaults.bool(forKey: PreferenceKeys.setupCompleted))
        XCTAssertTrue(telemetry.events.isEmpty)

        controller.setTelemetryEnabled(true)
        defaults.set(false, forKey: PreferenceKeys.setupCompleted)
        controller.completeSetup()
        controller.completeSetup()
        XCTAssertEqual(
            telemetry.events,
            [
                .telemetryEnabled,
                .setupCompleted(collectorCount: 1, summarizer: .codex)
            ]
        )
        XCTAssertTrue(defaults.bool(forKey: PreferenceKeys.telemetrySetupCompletedRecorded))

        controller.recordFirstReturnBriefCompleted(for: entry, summaryDuration: 18)
        controller.recordFirstReturnBriefCompleted(for: entry, summaryDuration: 18)
        XCTAssertEqual(
            telemetry.events.last,
            .firstReturnBriefCompleted(
                provider: .codex,
                fallbackUsed: false,
                awayDuration: entry.interval.duration,
                summaryDuration: 18
            )
        )
        XCTAssertEqual(
            telemetry.events.filter { $0.name == "first_return_brief_completed" }.count,
            1
        )
        XCTAssertTrue(defaults.bool(forKey: PreferenceKeys.telemetryFirstReturnBriefRecorded))

        let pendingBrief = HistoryEntry(
            interval: entry.interval,
            status: .pending,
            provider: .codex,
            sessionCount: 1,
            sources: [.codex]
        )
        controller.recordFirstReturnBriefCompleted(for: pendingBrief, summaryDuration: 18)
        XCTAssertEqual(
            telemetry.events.filter { $0.name == "first_return_brief_completed" }.count,
            1
        )

        XCTAssertTrue(controller.recordBriefFeedback(.helpful, for: entry))
        XCTAssertFalse(controller.recordBriefFeedback(.tooVerbose, for: entry))
        XCTAssertEqual(
            telemetry.events.last,
            .briefFeedbackSubmitted(reason: .helpful)
        )

        let pending = HistoryEntry(
            interval: entry.interval,
            status: .pending,
            sessionCount: 1,
            sources: [.codex]
        )
        XCTAssertFalse(controller.recordBriefFeedback(.helpful, for: pending))
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
