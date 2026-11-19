import AppKit
import CapsStackLocalization
import SwiftUI
import XCTest
@testable import CapsStack

/// Renders the real `HistoryView` in an `NSHostingView` and reads back what it exposes through
/// the macOS accessibility tree, which is what VoiceOver and XCUITest would query.
@MainActor
final class HistoryInProgressRenderingTests: XCTestCase {
    func testPendingEntryShowsInProgressWhileSummaryRunsThenFailureAfterItFails() async throws {
        let suiteName = "CapsStackHistoryInProgressTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.set(true, forKey: PreferenceKeys.capsStackEnabled)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(suiteName, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = HistoryStore(directoryURL: directory)
        let pending = try store.savePending(batch: makeBatch())
        let runner = GatedSummaryRunner()
        let controller = AppController(
            defaults: defaults,
            resolver: InProgressTestResolver(),
            runner: runner,
            historyStore: store,
            notifications: InProgressSilentNotifications()
        )
        controller.reloadHistory()

        controller.retry(pending)
        try await waitUntil { runner.hasStartedSummary }
        XCTAssertEqual(controller.phase, .summarizing)
        XCTAssertEqual(controller.summarizingEntryID, pending.id)

        let inProgress = try await renderedAccessibility(of: controller)
        XCTAssertTrue(inProgress.identifiers.contains("history.summaryInProgress"), "\(inProgress)")
        XCTAssertFalse(inProgress.identifiers.contains("history.summaryUnavailable"), "\(inProgress)")
        XCTAssertTrue(inProgress.containsText(CapsStackText.resolve(.summaryInProgress)), "\(inProgress)")
        XCTAssertTrue(inProgress.containsText(CapsStackText.resolve(.summarizing)), "\(inProgress)")
        XCTAssertFalse(inProgress.containsText(CapsStackText.resolve(.summaryUnavailable)), "\(inProgress)")
        XCTAssertFalse(inProgress.containsText(CapsStackText.resolve(.retrySummary)), "\(inProgress)")
        XCTAssertFalse(inProgress.containsText(CapsStackText.resolve(.pendingBriefs)), "\(inProgress)")

        runner.release()
        try await waitUntil { controller.phase == .failed }
        XCTAssertNil(controller.summarizingEntryID)

        let failed = try await renderedAccessibility(of: controller)
        XCTAssertTrue(failed.identifiers.contains("history.summaryUnavailable"), "\(failed)")
        XCTAssertFalse(failed.identifiers.contains("history.summaryInProgress"), "\(failed)")
        XCTAssertTrue(failed.containsText(CapsStackText.resolve(.summaryUnavailable)), "\(failed)")
        XCTAssertTrue(failed.containsText(CapsStackText.resolve(.retrySummary)), "\(failed)")
    }

    // MARK: - Helpers

    private struct AccessibilitySnapshot: CustomStringConvertible {
        var texts: [String] = []
        var identifiers: Set<String> = []

        func containsText(_ text: String) -> Bool {
            texts.contains { $0.contains(text) }
        }

        var description: String {
            "texts: \(texts), identifiers: \(identifiers.sorted())"
        }
    }

    private func renderedAccessibility(of controller: AppController) async throws -> AccessibilitySnapshot {
        enableSwiftUIAccessibilityTree()
        let size = CGSize(width: 1120, height: 740)
        let hostingView = NSHostingView(
            rootView: HistoryView(controller: controller).frame(width: size.width, height: size.height)
        )
        hostingView.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.orderFrontRegardless()
        defer {
            window.orderOut(nil)
            window.contentView = nil
        }

        // Let `onAppear` select the newest entry and SwiftUI publish the updated tree.
        for _ in 0..<5 {
            hostingView.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        var snapshot = AccessibilitySnapshot()
        collect(hostingView, into: &snapshot, depth: 0)
        return snapshot
    }

    /// SwiftUI builds its AppKit accessibility nodes only once an assistive client asks for
    /// them. Setting `AXEnhancedUserInterface` on the app (what VoiceOver and UI automation set)
    /// does that in-process, without requiring the test runner to have Accessibility permission.
    private func enableSwiftUIAccessibilityTree() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.finishLaunching()
        app.accessibilitySetValue(
            true,
            forAttribute: NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface")
        )
    }

    private func collect(_ element: Any, into snapshot: inout AccessibilitySnapshot, depth: Int) {
        guard depth < 64, let object = element as? NSObject else { return }
        for selector in ["accessibilityLabel", "accessibilityTitle", "accessibilityValue"] {
            if let text = accessibilityAttribute(selector, of: object) as? String, !text.isEmpty {
                snapshot.texts.append(text)
            }
        }
        if let identifier = accessibilityAttribute("accessibilityIdentifier", of: object) as? String,
           !identifier.isEmpty {
            snapshot.identifiers.insert(identifier)
        }
        for child in accessibilityAttribute("accessibilityChildren", of: object) as? [Any] ?? [] {
            collect(child, into: &snapshot, depth: depth + 1)
        }
    }

    /// SwiftUI's accessibility nodes are private `NSObject` subclasses, so read the
    /// `NSAccessibility` getters dynamically instead of through a concrete AppKit type.
    private func accessibilityAttribute(_ name: String, of object: NSObject) -> Any? {
        let selector = NSSelectorFromString(name)
        guard object.responds(to: selector) else { return nil }
        return object.perform(selector)?.takeUnretainedValue()
    }

    private func waitUntil(
        timeout: TimeInterval = 5,
        _ condition: @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else {
                XCTFail("Timed out waiting for condition")
                return
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    private func makeBatch() -> CollectionBatch {
        let start = Date().addingTimeInterval(-600)
        let session = CollectedSessionArtifact(
            id: "codex:in-progress",
            provider: .codex,
            workingDirectory: nil,
            events: [CollectedEvent(timestamp: start.addingTimeInterval(1), kind: "assistant", content: "progress")],
            wasTruncated: false
        )
        return CollectionBatch(
            interval: AwayInterval(start: start, end: start.addingTimeInterval(300)),
            sessions: [session],
            issues: []
        )
    }
}

/// Holds every summary request until `release()` and then fails it, so the test can observe the
/// in-flight UI and the failure UI for the same history entry.
private final class GatedSummaryRunner: ProcessRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var started = false
    private var released = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    var hasStartedSummary: Bool {
        lock.withLock { started }
    }

    func release() {
        let pending = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
            released = true
            defer { waiters = [] }
            return waiters
        }
        pending.forEach { $0.resume() }
    }

    func run(_ specification: ProcessSpecification, timeout: TimeInterval) async throws -> ProcessResult {
        if specification.arguments == ["--version"] {
            return ProcessResult(terminationStatus: 0, standardOutput: Data("test".utf8),
                                 standardError: Data(), didTruncateOutput: false)
        }
        await withCheckedContinuation { continuation in
            let resumeNow = lock.withLock { () -> Bool in
                started = true
                if released { return true }
                waiters.append(continuation)
                return false
            }
            if resumeNow { continuation.resume() }
        }
        return ProcessResult(terminationStatus: 1, standardOutput: Data(),
                             standardError: Data("synthetic failure".utf8), didTruncateOutput: false)
    }
}

private struct InProgressTestResolver: CLIResolving {
    func executableURL(for kind: CLIKind, override: String?) -> URL? {
        URL(fileURLWithPath: "/usr/bin/true")
    }

    func status(for kind: CLIKind, override: String?) -> CLIStatus {
        CLIStatus(kind: kind, executablePath: "/usr/bin/true", version: "test",
                  logDirectory: "/tmp", canReadLogs: true)
    }

    func logDirectory(for kind: CLIKind) -> URL {
        URL(fileURLWithPath: "/tmp", isDirectory: true)
    }
}

private final class InProgressSilentNotifications: NotificationServicing, @unchecked Sendable {
    func requestAuthorization() async -> Bool { false }
    func notify(outcome: SummaryOutcome, interval: AwayInterval, sessionCount: Int) async {}
    func notifyFailure(message: String, interval: AwayInterval?) async {}
}
