import Foundation
import PostHog

/// The small, privacy-reviewed event vocabulary sent by CapsStack.
///
/// This type intentionally stores only aggregate values or enums. Session content, quick memos,
/// paths, session IDs, model IDs, and raw error messages never enter the telemetry layer.
/// New activation events use stable snake_case names; the existing human-readable event names
/// remain unchanged so historical PostHog funnels do not split.
enum TelemetryEvent: Equatable, Sendable {
    case applicationStarted
    case telemetryEnabled
    case setupCompleted(collectorCount: Int, summarizer: CLIKind)
    case briefRequested(awayDuration: TimeInterval, sourceCount: Int, memoPresent: Bool)
    case briefCompleted(
        provider: CLIKind,
        fallbackUsed: Bool,
        awayDuration: TimeInterval,
        sessionCount: Int,
        summaryDuration: TimeInterval
    )
    case briefEmpty(awayDuration: TimeInterval, sourceCount: Int, issueCount: Int)
    case briefFailed(
        stage: TelemetryFailureStage,
        code: TelemetryFailureCode,
        provider: CLIKind?
    )
    case summaryRetryStarted
    case summaryRetryCompleted(
        provider: CLIKind,
        fallbackUsed: Bool,
        summaryDuration: TimeInterval
    )
    case summaryRetryFailed(
        stage: TelemetryFailureStage,
        code: TelemetryFailureCode,
        provider: CLIKind?
    )
    case providerTested(provider: CLIKind, succeeded: Bool)
    case briefConsumed(action: TelemetryConsumptionAction, status: HistoryStatus)
    case firstReturnBriefCompleted(
        provider: CLIKind,
        fallbackUsed: Bool,
        awayDuration: TimeInterval,
        summaryDuration: TimeInterval
    )
    case briefFeedbackSubmitted(reason: TelemetryFeedbackReason)

    var name: String {
        switch self {
        case .applicationStarted: "app launched"
        case .telemetryEnabled: "telemetry enabled"
        case .setupCompleted: "setup_completed"
        case .briefRequested: "return brief requested"
        case .briefCompleted: "return brief completed"
        case .briefEmpty: "return brief empty"
        case .briefFailed: "return brief failed"
        case .summaryRetryStarted: "summary retry started"
        case .summaryRetryCompleted: "summary retry completed"
        case .summaryRetryFailed: "summary retry failed"
        case .providerTested: "provider connection tested"
        case .briefConsumed: "return brief consumed"
        case .firstReturnBriefCompleted: "first_return_brief_completed"
        case .briefFeedbackSubmitted: "brief_feedback_submitted"
        }
    }

    /// Converts the reviewed event into PostHog properties without exposing free-form strings.
    var properties: [String: Any] {
        switch self {
        case .applicationStarted, .telemetryEnabled, .summaryRetryStarted:
            return [:]
        case let .setupCompleted(collectorCount, summarizer):
            return [
                "collector_count_bucket": TelemetryBuckets.count(collectorCount),
                "summarizer": summarizer.rawValue,
                // This event is only emitted after the explicit opt-in succeeds.
                "telemetry_enabled": true
            ]
        case let .briefRequested(awayDuration, sourceCount, memoPresent):
            return [
                "away_duration_bucket": TelemetryBuckets.awayDuration(awayDuration),
                "source_count": max(0, sourceCount),
                "memo_present": memoPresent
            ]
        case let .briefCompleted(provider, fallbackUsed, awayDuration, sessionCount, summaryDuration):
            return [
                "provider": provider.rawValue,
                "fallback_used": fallbackUsed,
                "away_duration_bucket": TelemetryBuckets.awayDuration(awayDuration),
                "session_count_bucket": TelemetryBuckets.count(sessionCount),
                "summary_duration_bucket": TelemetryBuckets.summaryDuration(summaryDuration)
            ]
        case let .briefEmpty(awayDuration, sourceCount, issueCount):
            return [
                "away_duration_bucket": TelemetryBuckets.awayDuration(awayDuration),
                "source_count": max(0, sourceCount),
                "issue_count_bucket": TelemetryBuckets.count(issueCount)
            ]
        case let .briefFailed(stage, code, provider):
            return failureProperties(stage: stage, code: code, provider: provider)
        case let .summaryRetryCompleted(provider, fallbackUsed, summaryDuration):
            return [
                "provider": provider.rawValue,
                "fallback_used": fallbackUsed,
                "summary_duration_bucket": TelemetryBuckets.summaryDuration(summaryDuration)
            ]
        case let .summaryRetryFailed(stage, code, provider):
            return failureProperties(stage: stage, code: code, provider: provider)
        case let .providerTested(provider, succeeded):
            return [
                "provider": provider.rawValue,
                "succeeded": succeeded
            ]
        case let .briefConsumed(action, status):
            return [
                "action": action.rawValue,
                "status": status.rawValue
            ]
        case let .firstReturnBriefCompleted(provider, fallbackUsed, awayDuration, summaryDuration):
            return [
                "provider": provider.rawValue,
                "fallback_used": fallbackUsed,
                "away_duration_bucket": TelemetryBuckets.awayDuration(awayDuration),
                "summary_duration_bucket": TelemetryBuckets.summaryDuration(summaryDuration)
            ]
        case let .briefFeedbackSubmitted(reason):
            return [
                "rating_reason": reason.rawValue,
                "status": HistoryStatus.completed.rawValue
            ]
        }
    }

    private func failureProperties(
        stage: TelemetryFailureStage,
        code: TelemetryFailureCode,
        provider: CLIKind?
    ) -> [String: Any] {
        var properties: [String: Any] = [
            "stage": stage.rawValue,
            "code": code.rawValue
        ]
        if let provider {
            properties["provider"] = provider.rawValue
        }
        return properties
    }
}

enum TelemetryFailureStage: String, Equatable, Sendable {
    case retry
    case persistence
    case summarization
}

enum TelemetryFailureCode: String, Equatable, Sendable {
    case executableNotFound = "executable_not_found"
    case processFailed = "process_failed"
    case timedOut = "timed_out"
    case invalidOutput = "invalid_output"
    case noProviderAvailable = "no_provider_available"
    case invalidHistoryData = "invalid_history_data"
    case pendingArtifactNotFound = "pending_artifact_not_found"
    case cancelled
    case unknown

    static func from(error: Error) -> Self {
        if error is CancellationError {
            return .cancelled
        }
        if let error = error as? SummaryProviderError {
            switch error {
            case .executableNotFound: return .executableNotFound
            case .processFailed: return .processFailed
            case .timedOut: return .timedOut
            case .invalidOutput: return .invalidOutput
            case .noProviderAvailable: return .noProviderAvailable
            }
        }
        if let error = error as? HistoryStoreError {
            switch error {
            case .invalidHistoryData: return .invalidHistoryData
            case .pendingArtifactNotFound: return .pendingArtifactNotFound
            }
        }
        return .unknown
    }
}

enum TelemetryConsumptionAction: String, Equatable, Sendable {
    case viewed
    case copied
    case exported
}

/// Fixed, one-click reasons keep the quality signal useful without accepting free-form text.
enum TelemetryFeedbackReason: String, CaseIterable, Equatable, Hashable, Sendable {
    case helpful
    case missingImportantContext = "missing_important_context"
    case tooVerbose = "too_verbose"
    case incorrectOrMisleading = "incorrect_or_misleading"
}

/// The SDK supports a richer range of data, but CapsStack deliberately uses coarse buckets so
/// useful timing trends do not reveal a user's exact schedule or workload.
enum TelemetryBuckets {
    static func awayDuration(_ seconds: TimeInterval) -> String {
        switch max(0, seconds) {
        case ..<60: "under_1m"
        case ..<300: "1_to_5m"
        case ..<1_800: "5_to_30m"
        case ..<7_200: "30m_to_2h"
        default: "over_2h"
        }
    }

    static func summaryDuration(_ seconds: TimeInterval) -> String {
        switch max(0, seconds) {
        case ..<5: "under_5s"
        case ..<15: "5_to_15s"
        case ..<60: "15_to_60s"
        case ..<180: "1_to_3m"
        default: "over_3m"
        }
    }

    static func count(_ value: Int) -> String {
        switch max(0, value) {
        case 0: "0"
        case 1: "1"
        case 2...5: "2_to_5"
        default: "6_plus"
        }
    }
}

@MainActor
protocol TelemetryClient: AnyObject {
    var isConfigured: Bool { get }
    var isEnabled: Bool { get }

    func setEnabled(_ enabled: Bool)
    func capture(_ event: TelemetryEvent)
}

@MainActor
final class NoopTelemetryClient: TelemetryClient {
    let isConfigured = false
    private(set) var isEnabled = false

    func setEnabled(_ enabled: Bool) {
        isEnabled = false
    }

    func capture(_ event: TelemetryEvent) {}
}

enum PostHogTelemetryConfiguration {
    static let projectTokenInfoKey = "CapsStackPostHogProjectToken"
    static let hostInfoKey = "CapsStackPostHogHost"
    static let projectTokenEnvironmentKey = "CAPSSTACK_POSTHOG_PROJECT_TOKEN"
    static let hostEnvironmentKey = "CAPSSTACK_POSTHOG_HOST"
    static let defaultHost = "https://us.i.posthog.com"

    static func projectToken(
        bundle: Bundle = .main,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String? {
        firstNonEmpty([
            environment[projectTokenEnvironmentKey],
            bundle.object(forInfoDictionaryKey: projectTokenInfoKey) as? String
        ])
    }

    static func host(
        bundle: Bundle = .main,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String {
        firstNonEmpty([
            environment[hostEnvironmentKey],
            bundle.object(forInfoDictionaryKey: hostInfoKey) as? String,
            defaultHost
        ]) ?? defaultHost
    }

    private static func firstNonEmpty(_ values: [String?]) -> String? {
        values
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }
}

/// PostHog adapter configured for explicit, manual, aggregate-only events on macOS.
@MainActor
final class PostHogTelemetryClient: TelemetryClient {
    private var sdk: PostHogSDK?
    private let projectToken: String?
    private let host: String
    private(set) var isEnabled: Bool

    var isConfigured: Bool { projectToken != nil }

    init(
        defaults: UserDefaults = .standard,
        bundle: Bundle = .main,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        let token = PostHogTelemetryConfiguration.projectToken(
            bundle: bundle,
            environment: environment
        )
        projectToken = token
        host = PostHogTelemetryConfiguration.host(bundle: bundle, environment: environment)
        sdk = nil
        isEnabled = false

        // Do not even initialize the SDK while consent is off. PostHog loads remote configuration
        // during setup, so lazy setup keeps a token-configured but opted-out build network-silent.
        if token != nil && TelemetryPreferences(defaults: defaults).isEnabled {
            setEnabled(true)
        }
    }

    func setEnabled(_ enabled: Bool) {
        guard isConfigured else {
            isEnabled = false
            return
        }
        guard isEnabled != enabled else { return }
        if enabled {
            if let sdk {
                sdk.optIn()
            } else {
                sdk = makeSDK()
            }
            isEnabled = sdk != nil
        } else {
            sdk?.optOut()
            isEnabled = false
        }
    }

    func capture(_ event: TelemetryEvent) {
        guard isEnabled, let sdk else { return }
        sdk.capture(event.name, properties: event.properties)
    }

    private func makeSDK() -> PostHogSDK? {
        guard let projectToken else { return nil }
        let config = PostHogConfig(projectToken: projectToken, host: host)
        // Every event is explicit. Disable lifecycle/screen/autocapture and all SDK surfaces
        // that could observe UI or error details outside the reviewed event vocabulary.
        config.captureApplicationLifecycleEvents = false
        config.captureScreenViews = false
        config.enableSwizzling = false
        config.sendFeatureFlagEvent = false
        config.preloadFeatureFlags = false
        config.personProfiles = .never
        config.setDefaultPersonProperties = false
        config.errorTrackingConfig.autoCapture = false
        #if os(macOS)
            config.capturePushNotificationSubscriptions = false
            config.capturePushNotificationOpened = false
        #endif
        config.optOut = false
        return PostHogSDK.with(config)
    }
}
