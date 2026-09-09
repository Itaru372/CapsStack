import CapsStackLocalization
import Foundation

/// The actionable reason recorded for a pending summary.
///
/// This is intentionally derived from the already persisted diagnostic string rather than stored
/// as a new field in `HistoryEntry`. Older history files therefore remain readable, and changing
/// the classifier never rewrites a user's history or raw pending artifact.
enum PendingBriefCause: String, CaseIterable, Equatable, Identifiable, Sendable {
    case timeout
    case authentication
    case usageLimit
    case other
    case unknown

    var id: String { rawValue }

    /// Only timeouts are safe for an unattended bulk retry. Authentication and usage-limit
    /// failures require an external state change, while an unclassified failure needs review.
    var isBulkRetryable: Bool {
        self == .timeout
    }

    var displayName: String {
        CapsStackText.resolve(localizationKey)
    }

    var systemImageName: String {
        switch self {
        case .timeout: "clock.badge.exclamationmark"
        case .authentication: "person.crop.circle.badge.exclamationmark"
        case .usageLimit: "chart.bar.xaxis"
        case .other: "exclamationmark.circle"
        case .unknown: "questionmark.circle"
        }
    }

    static func classify(errorMessage: String?) -> Self {
        guard let errorMessage else { return .unknown }
        let message = errorMessage
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !message.isEmpty else { return .unknown }

        // Prefer a provider/account limit over a generic authentication or timeout word when a
        // CLI reports several diagnostics in one message.
        if containsAny(message, [
            "usage limit", "rate limit", "rate-limit", "quota", "credit limit", "credits",
            "token limit", "too many requests", "429", "capacity", "利用上限", "使用上限",
            "レート制限", "クォータ", "クレジット", "リクエストが多すぎ", "上限"
        ]) {
            return .usageLimit
        }

        if containsAny(message, [
            "authentication", "authenticated", "unauthorized", "not authorized", "forbidden",
            "permission denied", "access denied", "not logged in", "login", "log in", "sign in",
            "credentials", "api key", "access token", "認証", "未認証", "ログイン", "サインイン",
            "資格情報", "apiキー", "アクセストークン", "権限がありません", "権限エラー"
        ]) {
            return .authentication
        }

        if containsAny(message, [
            "timed out", "timeout", "time out", "timedout", "タイムアウト", "時間切れ"
        ]) {
            return .timeout
        }

        return .other
    }

    private var localizationKey: CapsStackText.Key {
        switch self {
        case .timeout: .pendingCauseTimeout
        case .authentication: .pendingCauseAuthentication
        case .usageLimit: .pendingCauseUsageLimit
        case .other: .pendingCauseOther
        case .unknown: .pendingCauseUnknown
        }
    }

    private static func containsAny(_ message: String, _ needles: [String]) -> Bool {
        needles.contains { message.contains($0) }
    }
}

enum PendingArtifactAvailability: Equatable, Sendable {
    case available
    case missing
    case malformed
}

/// A pending history row plus the non-mutating assessment used by the recovery UI.
struct PendingBriefAssessment: Equatable, Identifiable, Sendable {
    let entry: HistoryEntry
    let cause: PendingBriefCause
    let artifactAvailability: PendingArtifactAvailability

    var id: UUID { entry.id }

    var hasArtifact: Bool {
        artifactAvailability == .available
    }

    /// This is the strict policy used by the bulk action.
    var isBulkRetryable: Bool {
        entry.status == .pending
            && entry.pendingArtifactID != nil
            && hasArtifact
            && cause.isBulkRetryable
    }

    /// Preserve the existing one-row retry affordance whenever the pending artifact is still
    /// present and decodable. The stricter cause policy applies only to unattended bulk retries.
    var isManuallyRetryable: Bool {
        guard entry.status == .pending, entry.pendingArtifactID != nil, hasArtifact else { return false }
        return true
    }
}

struct PendingRetryProgress: Equatable, Sendable {
    let total: Int
    let completed: Int
    let succeeded: Int
    let failed: Int
    let currentEntryID: UUID?

    init(
        total: Int,
        completed: Int = 0,
        succeeded: Int = 0,
        failed: Int = 0,
        currentEntryID: UUID? = nil
    ) {
        self.total = max(0, total)
        self.completed = max(0, completed)
        self.succeeded = max(0, succeeded)
        self.failed = max(0, failed)
        self.currentEntryID = currentEntryID
    }
}
