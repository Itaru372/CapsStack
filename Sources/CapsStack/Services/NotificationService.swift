import Foundation
import UserNotifications

protocol NotificationServicing: AnyObject, Sendable {
    func requestAuthorization() async -> Bool
    func notify(outcome: SummaryOutcome, interval: AwayInterval, sessionCount: Int) async
    func notifyFailure(message: String, interval: AwayInterval?) async
}

/// Delivers short menu-bar notifications while keeping full details in HistoryStore/UI.
final class NotificationService: NotificationServicing, @unchecked Sendable {
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                continuation.resume(returning: granted)
            }
        }
    }

    func notify(outcome: SummaryOutcome, interval: AwayInterval, sessionCount: Int) async {
        guard await requestAuthorization() else { return }
        let content = UNMutableNotificationContent()
        content.title = "CapsStack — Away progress"
        content.subtitle = "\(outcome.provider.displayName) / \(sessionCount) sessions"
        content.body = clipped(outcome.document.overview, limit: 240)
        content.sound = .default
        await deliver(content, identifier: "summary-\(UUID().uuidString)")
    }

    func notifyFailure(message: String, interval: AwayInterval? = nil) async {
        guard await requestAuthorization() else { return }
        let content = UNMutableNotificationContent()
        content.title = "CapsStack — Summary failed"
        content.body = clipped(message, limit: 240)
        content.sound = .default
        await deliver(content, identifier: "failure-\(UUID().uuidString)")
    }

    // Short aliases keep controller call sites readable.
    func send(outcome: SummaryOutcome, interval: AwayInterval, sessionCount: Int) async {
        await notify(outcome: outcome, interval: interval, sessionCount: sessionCount)
    }

    func sendFailure(_ message: String, interval: AwayInterval? = nil) async {
        await notifyFailure(message: message, interval: interval)
    }

    private func deliver(_ content: UNNotificationContent, identifier: String) async {
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        await withCheckedContinuation { continuation in
            center.add(request) { _ in
                continuation.resume()
            }
        }
    }

    private func clipped(_ value: String, limit: Int) -> String {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count > limit else { return normalized }
        return String(normalized.prefix(max(1, limit - 1))) + "…"
    }
}
