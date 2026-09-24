import CapsStackLocalization
import XCTest
@testable import CapsStack

final class CapsLockMonitorTests: XCTestCase {
    func testSuppressionRequestsInputMonitoringWhenEventPostingIsGranted() {
        let requests = CallCounter()
        let monitor = CapsLockMonitor(
            pollingInterval: 60,
            systemStateReader: { false },
            eventPostingAccessReader: { true },
            eventPostingAccessRequester: {
                XCTFail("Event posting permission should not be requested")
                return false
            },
            listenEventAccessReader: { false },
            listenEventAccessRequester: {
                requests.value += 1
                return false
            }
        )

        XCTAssertFalse(monitor.setSuppressionEnabled(true))
        XCTAssertEqual(requests.value, 1)
        XCTAssertEqual(monitor.suppressionIssue, .inputMonitoringPermission)
        XCTAssertEqual(
            monitor.suppressionError,
            CapsStackText.resolve(.inputMonitoringPermissionMessage)
        )
        XCTAssertFalse(monitor.isSuppressingOriginal)
    }

    func testFailedSuppressionKeepsRequestedStateForRetryWithoutChangingCapsLock() {
        let requests = CallCounter()
        let setterCalls = CallCounter()
        let monitor = CapsLockMonitor(
            pollingInterval: 60,
            systemStateReader: { true },
            systemStateSetter: { _ in setterCalls.value += 1 },
            eventPostingAccessReader: { true },
            listenEventAccessReader: { false },
            listenEventAccessRequester: {
                requests.value += 1
                return false
            }
        )

        XCTAssertFalse(monitor.setSuppressionEnabled(true))
        XCTAssertFalse(monitor.setSuppressionEnabled(true))
        XCTAssertEqual(requests.value, 2)

        XCTAssertTrue(monitor.setSuppressionEnabled(false))
        XCTAssertEqual(setterCalls.value, 0)
        XCTAssertNil(monitor.suppressionError)
    }

    func testEventPostingPermissionIsRequestedOnlyAfterExplicitRetry() {
        let requests = CallCounter()
        let monitor = CapsLockMonitor(
            pollingInterval: 60,
            systemStateReader: { false },
            eventPostingAccessReader: { false },
            eventPostingAccessRequester: {
                requests.value += 1
                return false
            },
            listenEventAccessReader: { true },
            listenEventAccessRequester: {
                XCTFail("Input Monitoring is already granted")
                return false
            }
        )

        XCTAssertFalse(monitor.setSuppressionEnabled(true, requestPermission: false))
        XCTAssertEqual(requests.value, 0)
        XCTAssertEqual(monitor.suppressionIssue, .eventPostingPermission)

        XCTAssertFalse(monitor.setSuppressionEnabled(true, requestPermission: true))
        XCTAssertEqual(requests.value, 1)
        XCTAssertEqual(
            monitor.suppressionError,
            CapsStackText.resolve(.eventPostingPermissionMessage)
        )
        XCTAssertFalse(monitor.isSuppressingOriginal)
    }

    @MainActor
    func testAppControllerKeepsSuppressionPreferenceWhenPermissionIsMissing() throws {
        let suiteName = "CapsLockSuppressionPreferenceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let historyDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(suiteName, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: historyDirectory) }

        let monitor = CapsLockMonitor(
            pollingInterval: 60,
            systemStateReader: { false },
            eventPostingAccessReader: { true },
            listenEventAccessReader: { false },
            listenEventAccessRequester: { false }
        )
        let controller = AppController(
            defaults: defaults,
            monitor: monitor,
            historyStore: HistoryStore(directoryURL: historyDirectory),
            notifications: SilentNotificationService()
        )

        controller.setSuppressOriginalCapsLock(true)

        XCTAssertTrue(defaults.bool(forKey: PreferenceKeys.suppressOriginalCapsLock))
        XCTAssertFalse(controller.isSuppressingOriginalCapsLock)
        XCTAssertEqual(
            controller.capsLockSuppressionError,
            CapsStackText.resolve(.inputMonitoringPermissionMessage)
        )
    }
}

private final class CallCounter: @unchecked Sendable {
    var value = 0
}

private final class SilentNotificationService: NotificationServicing, @unchecked Sendable {
    func requestAuthorization() async -> Bool { false }

    func notify(outcome: SummaryOutcome, interval: AwayInterval, sessionCount: Int) async {}

    func notifyFailure(message: String, interval: AwayInterval?) async {}
}
