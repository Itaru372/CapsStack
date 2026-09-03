import AppKit
import Combine
import Foundation

enum AppPhase: Equatable {
    case idle
    case away
    case summarizing
    case failed
    case disabled
}

@MainActor
final class AppController: ObservableObject {
    @Published private(set) var phase: AppPhase = .idle
    @Published private(set) var awayStartedAt: Date?
    @Published private(set) var activeSessionCount = 0
    @Published private(set) var history: [HistoryEntry] = []
    @Published private(set) var cliStatuses: [CLIKind: CLIStatus] = [:]
    @Published private(set) var cliModels: [CLIKind: [CLIModel]] = [:]
    @Published private(set) var cliModelFetchStates: [CLIKind: CLIModelFetchState] = [:]
    @Published private(set) var cliModelErrors: [CLIKind: String] = [:]
    @Published private(set) var providerTestMessages: [CLIKind: String] = [:]
    @Published private(set) var testingProvider: CLIKind?
    @Published private(set) var lastError: String?
    @Published private(set) var isCapsStackEnabled: Bool
    @Published private(set) var isSuppressingOriginalCapsLock: Bool
    @Published private(set) var capsLockSuppressionError: String?
    @Published private(set) var isNotificationAuthorized: Bool?
    @Published private(set) var isShowingDemoData = false
    @Published private(set) var isTelemetryEnabled: Bool
    @Published private(set) var isTelemetryConfigured: Bool

    private let defaults: UserDefaults
    private let monitor: CapsLockMonitor
    private let collector: MultiSessionCollector
    private let resolver: CLIResolving
    private let runner: ProcessRunning
    private let modelListing: CLIModelListing
    private let summarizer: SummaryOrchestrator
    private let historyStore: HistoryStore
    private let notifications: NotificationServicing
    private let telemetry: TelemetryClient
    private var hasStarted = false
    private var sessionCountTask: Task<Void, Never>?
    /// The currently running collection/summary workflow, if any. Keeping one handle lets
    /// settings/history actions cancel stale work before it can publish a late state update.
    private var activeWorkflowTask: Task<Void, Never>?
    /// Keeps the long-running provider test cancellable from the settings UI.
    private var providerTestTask: Task<Void, Never>?
    private var providerTestGeneration: UInt = 0
    private var workflowGeneration: UInt = 0
    private var isRefreshingCLIStatuses = false
    private var refreshingModelKinds: Set<CLIKind> = []
    private var backgroundActivity: NSObjectProtocol?
    private var defaultsObserver: NSObjectProtocol?
    private let showsInMemoryDemoData: Bool
    private lazy var demoEntries = DemoHistoryContent.entries()

    init(
        defaults: UserDefaults = .standard,
        monitor: CapsLockMonitor = CapsLockMonitor(),
        resolver: CLIResolving = CLIResolver(),
        runner: ProcessRunning = ProcessRunner(),
        modelListing: CLIModelListing? = nil,
        historyStore: HistoryStore = HistoryStore(),
        notifications: NotificationServicing = NotificationService(),
        telemetry: TelemetryClient? = nil,
        showsInMemoryDemoData: Bool = ProcessInfo.processInfo.arguments.contains("--capsstack-demo-data")
    ) {
        // Resolve CLI-specific defaults before any preference type registers its fallback domain.
        // This keeps a fresh install independent from whichever of Codex or Claude Code happens
        // to be present, while preserving every value already stored by the user.
        CLIInitialPreferences.applyIfNeeded(defaults: defaults, resolver: resolver)
        self.defaults = defaults
        self.monitor = monitor
        self.resolver = resolver
        self.runner = runner
        self.modelListing = modelListing ?? CLIModelCatalogService(resolver: resolver, runner: runner)
        self.collector = MultiSessionCollector(factory: SessionCollectorFactory(resolver: resolver))
        self.summarizer = SummaryOrchestrator(resolver: resolver, runner: runner)
        self.historyStore = historyStore
        self.notifications = notifications
        let telemetry = telemetry ?? PostHogTelemetryClient(defaults: defaults)
        self.telemetry = telemetry
        self.showsInMemoryDemoData = showsInMemoryDemoData
        let feature = CapsStackFeaturePreferences(defaults: defaults)
        let telemetryPreferences = TelemetryPreferences(defaults: defaults)
        self.isCapsStackEnabled = feature.isEnabled
        self.isSuppressingOriginalCapsLock = feature.suppressOriginalCapsLock
        self.capsLockSuppressionError = nil
        self.isTelemetryConfigured = telemetry.isConfigured
        self.isTelemetryEnabled = telemetry.isConfigured && telemetryPreferences.isEnabled
        telemetry.setEnabled(self.isTelemetryEnabled)
    }

    var stateTitle: String {
        if !isCapsStackEnabled { return "一時停止中" }
        switch phase {
        case .idle: return "待機中"
        case .away: return "退席中"
        case .summarizing: return "進捗を要約中"
        case .failed: return "要約できませんでした"
        case .disabled: return "一時停止中"
        }
    }

    var stateDetail: String {
        if !isCapsStackEnabled { return "設定でCapsStackを有効にすると再開します" }
        switch phase {
        case .idle: return "Caps LockをONにすると収集を開始します"
        case .away: return "Caps LockをOFFにすると要約します"
        case .summarizing: return "収集元と要約担当は別々に処理されます"
        case .failed: return lastError ?? "履歴から再要約できます"
        case .disabled: return "設定でCapsStackを有効にすると再開します"
        }
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true

        telemetry.capture(.applicationStarted)

        reloadHistory()
        observeDefaults()
        applyBackgroundKeepAlive()
        applyCapsLockSuppression()
        monitor.onChange = { [weak self] isOn in
            Task { @MainActor in
                self?.handleCapsLock(isOn: isOn)
            }
        }
        if isCapsStackEnabled {
            monitor.start()
        } else {
            phase = .disabled
        }

        Task {
            isNotificationAuthorized = await notifications.requestAuthorization()
            await refreshCLIStatuses()
        }

        guard isCapsStackEnabled else { return }
        // Restore a persisted interval before any current-state transition can overwrite it.
        // `refreshEnabledState()` intentionally handles later preference toggles, but using it
        // during startup would call `beginAway(Date())` first when Caps Lock is already ON.
        if let storedStart = defaults.object(forKey: PreferenceKeys.awayStart) as? Date {
            if monitor.isCapsLockOn {
                beginAway(at: storedStart)
            } else {
                awayStartedAt = storedStart
                phase = .away
                finishAway(at: Date())
            }
        } else if monitor.isCapsLockOn {
            beginAway(at: Date())
        }
    }

    func beginAwayManually() {
        guard isCapsStackEnabled else { return }
        beginAway(at: Date())
    }

    func endAwayManually() {
        guard isCapsStackEnabled else { return }
        finishAway(at: Date())
    }

    func setCapsStackEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: PreferenceKeys.capsStackEnabled)
        guard isCapsStackEnabled != enabled else { return }

        // Settings writes are normally observed through UserDefaults.didChangeNotification, but
        // updating the published state synchronously keeps the toggle and menu-bar status in
        // lockstep even when the Settings scene is the first scene to mutate this preference.
        isCapsStackEnabled = enabled
        refreshEnabledState()
    }

    func setKeepRunningInBackground(_ enabled: Bool) {
        defaults.set(enabled, forKey: PreferenceKeys.keepRunningInBackground)
        applyBackgroundKeepAlive()
    }

    func setTelemetryEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: PreferenceKeys.telemetryEnabled)
        guard isTelemetryConfigured else {
            isTelemetryEnabled = false
            return
        }

        telemetry.setEnabled(enabled)
        isTelemetryEnabled = telemetry.isEnabled
        if isTelemetryEnabled {
            telemetry.capture(.telemetryEnabled)
        }
    }

    func recordHistoryAction(_ action: TelemetryConsumptionAction, for entry: HistoryEntry) {
        telemetry.capture(.briefConsumed(action: action, status: entry.status))
    }

    func setSuppressOriginalCapsLock(_ enabled: Bool) {
        defaults.set(enabled, forKey: PreferenceKeys.suppressOriginalCapsLock)
        applyCapsLockSuppression()
    }

    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func openNotificationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings") {
            NSWorkspace.shared.open(url)
        }
    }

    private func applyCapsLockSuppression() {
        let want = CapsStackFeaturePreferences(defaults: defaults).suppressOriginalCapsLock
        let success = monitor.setSuppressionEnabled(want)
        // Publish state for UI
        isSuppressingOriginalCapsLock = want && success
        capsLockSuppressionError = monitor.suppressionError
        // If activation failed, revert preference so toggle reflects reality
        if want && !success {
            defaults.set(false, forKey: PreferenceKeys.suppressOriginalCapsLock)
            isSuppressingOriginalCapsLock = false
        }
    }

    func retry(_ entry: HistoryEntry) {
        guard isCapsStackEnabled,
              phase != .summarizing,
              phase != .away,
              phase != .disabled,
              let pendingID = entry.pendingArtifactID else { return }

        // Set the phase before the first suspension point. Without this synchronous guard,
        // repeated clicks on "再要約" could enqueue multiple tasks before the first one loaded
        // its artifact, and both tasks would append a completed history row.
        phase = .summarizing
        lastError = nil
        let workflowID = beginWorkflow()
        telemetry.capture(.summaryRetryStarted)
        let task = Task { [weak self] in
            guard let self else { return }
            defer { self.finishWorkflow(workflowID) }

            do {
                guard let batch = try historyStore.loadPending(pendingID) else {
                    throw HistoryStoreError.pendingArtifactNotFound(pendingID)
                }
                guard !Task.isCancelled, isCurrentWorkflow(workflowID) else { return }
                await summarize(batch: batch, replacing: entry, workflowID: workflowID, isRetry: true)
            } catch {
                guard !Task.isCancelled, isCurrentWorkflow(workflowID) else { return }
                telemetry.capture(.summaryRetryFailed(
                    stage: .retry,
                    code: TelemetryFailureCode.from(error: error),
                    provider: entry.provider
                ))
                phase = .failed
                lastError = error.localizedDescription
                await notifications.notifyFailure(message: error.localizedDescription, interval: entry.interval)
            }
        }
        activeWorkflowTask = task
    }

    func requestNotificationAuthorization() async {
        isNotificationAuthorized = await notifications.requestAuthorization()
    }

    func clearAllHistory() {
        cancelActiveWorkflow()
        if showsInMemoryDemoData {
            demoEntries.removeAll()
            reloadHistory()
            return
        }

        do {
            try historyStore.deleteAll()
            reloadHistory()
        } catch {
            lastError = error.localizedDescription
            phase = .failed
        }
    }

    func clearQuickMemo() {
        QuickMemoPreferences(text: "").save(to: defaults)
    }

    var historyDirectoryURL: URL {
        historyStore.directoryURL
    }

    func revealHistoryFolder() {
        // The folder is lazily created on the first history write. Create it here as well so the
        // first-use "表示" button always has a concrete location to reveal.
        do {
            try FileManager.default.createDirectory(
                at: historyDirectoryURL,
                withIntermediateDirectories: true
            )
        } catch {
            lastError = error.localizedDescription
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([historyDirectoryURL])
    }

    func delete(_ entry: HistoryEntry) {
        cancelActiveWorkflow()
        if showsInMemoryDemoData {
            demoEntries.removeAll { $0.id == entry.id }
            reloadHistory()
            return
        }

        do {
            try historyStore.delete(entry.id)
            reloadHistory()
        } catch {
            lastError = error.localizedDescription
            phase = .failed
        }
    }

    func refreshCLIStatuses() async {
        // Menu-bar, history, and settings scenes can all trigger a refresh when they appear.
        // Avoid running several CLI probes concurrently and allowing an older result to win the
        // race when the user opens/closes settings repeatedly.
        guard !isRefreshingCLIStatuses else { return }
        isRefreshingCLIStatuses = true
        defer { isRefreshingCLIStatuses = false }

        let preferences = SummarizerPreferences(defaults: defaults)
        var refreshed: [CLIKind: CLIStatus] = [:]

        for kind in CLIKind.allCases {
            let override = preferences.executableOverride(for: kind)
            var status = resolver.status(for: kind, override: override)
            if let path = status.executablePath {
                let specification = ProcessSpecification(
                    executableURL: URL(fileURLWithPath: path),
                    arguments: ["--version"]
                )
                if let result = try? await runner.run(specification, timeout: 5), result.succeeded {
                    let output = String(data: result.standardOutput, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    status = CLIStatus(
                        kind: status.kind,
                        executablePath: status.executablePath,
                        version: output?.isEmpty == false ? output : nil,
                        logDirectory: status.logDirectory,
                        canReadLogs: status.canReadLogs,
                        isDesktopAppInstalled: status.isDesktopAppInstalled
                    )
                }
            }
            refreshed[kind] = status
        }
        cliStatuses = refreshed
    }

    func models(for kind: CLIKind) -> [CLIModel] {
        cliModels[kind] ?? []
    }

    func modelFetchState(for kind: CLIKind) -> CLIModelFetchState {
        cliModelFetchStates[kind] ?? .idle
    }

    /// Refreshes one CLI's account/configuration-aware model catalog. This is intentionally
    /// separate from `refreshCLIStatuses()` because model listing may contact a provider and
    /// should not delay app startup or a simple version probe.
    func refreshCLIModels(for kind: CLIKind) async {
        guard kind.supportsModelListing else { return }
        guard !refreshingModelKinds.contains(kind) else { return }

        refreshingModelKinds.insert(kind)
        cliModelFetchStates[kind] = .loading
        cliModelErrors.removeValue(forKey: kind)
        defer { refreshingModelKinds.remove(kind) }

        let preferences = SummarizerPreferences(defaults: defaults)
        do {
            let models = try await modelListing.models(
                for: kind,
                executableOverride: preferences.executableOverride(for: kind)
            )
            guard !Task.isCancelled else { return }
            cliModels[kind] = models
            cliModelFetchStates[kind] = .loaded
        } catch is CancellationError {
            // Cancellation is a normal part of closing settings or changing an executable path;
            // do not replace a useful existing catalog with an error state.
        } catch {
            guard !Task.isCancelled else { return }
            cliModelFetchStates[kind] = .failed
            cliModelErrors[kind] = error.localizedDescription
        }
    }

    func refreshAvailableModels() async {
        for kind in CLIKind.modelListingCases {
            await refreshCLIModels(for: kind)
        }
    }

    func startProviderTest(_ kind: CLIKind) {
        guard kind.supportsSummarization else { return }
        guard testingProvider == nil else { return }
        providerTestGeneration &+= 1
        let generation = providerTestGeneration
        providerTestTask = Task { [weak self] in
            await self?.performProviderTest(kind, generation: generation)
        }
    }

    func cancelProviderTest() {
        guard testingProvider != nil else { return }
        providerTestGeneration &+= 1
        providerTestTask?.cancel()
        providerTestTask = nil
        if let kind = testingProvider {
            providerTestMessages[kind] = "キャンセルしました"
        }
        testingProvider = nil
    }

    func testProvider(_ kind: CLIKind) async {
        guard testingProvider == nil else { return }
        providerTestGeneration &+= 1
        await performProviderTest(kind, generation: providerTestGeneration)
    }

    private func performProviderTest(_ kind: CLIKind, generation: UInt) async {
        guard isCurrentProviderTest(generation) else { return }
        guard testingProvider == nil else { return }
        testingProvider = kind
        providerTestMessages[kind] = "確認中..."
        defer {
            if isCurrentProviderTest(generation) {
                testingProvider = nil
                providerTestTask = nil
            }
        }

        let now = Date()
        let sample = CollectionBatch(
            interval: AwayInterval(start: now.addingTimeInterval(-5), end: now),
            sessions: [
                CollectedSessionArtifact(
                    id: "capsstack-connection-test",
                    provider: kind,
                    workingDirectory: nil,
                    events: [CollectedEvent(
                        timestamp: now,
                        kind: "test",
                        content: "CapsStackの接続試験です。この内容だけを短く要約してください。"
                    )],
                    wasTruncated: false
                )
            ],
            issues: []
        )
        let preferences = SummarizerPreferences(defaults: defaults)
        var succeeded = false

        do {
            _ = try await summarizer.summarize(
                batch: sample,
                primary: kind,
                automaticFallback: false,
                executableOverrides: preferences.executableOverrides,
                modelOverrides: preferences.modelOverrides,
                reasoningOverrides: preferences.reasoningOverrides
            )
            guard !Task.isCancelled, isCurrentProviderTest(generation) else { return }
            succeeded = true
            providerTestMessages[kind] = "成功"
        } catch {
            guard !Task.isCancelled, isCurrentProviderTest(generation) else { return }
            providerTestMessages[kind] = "失敗: \(error.localizedDescription)"
        }
        guard !Task.isCancelled, isCurrentProviderTest(generation) else { return }
        telemetry.capture(.providerTested(provider: kind, succeeded: succeeded))
        await refreshCLIStatuses()
    }

    private func isCurrentProviderTest(_ generation: UInt) -> Bool {
        providerTestGeneration == generation
    }

    private func handleCapsLock(isOn: Bool) {
        guard isCapsStackEnabled else { return }
        if isOn {
            beginAway(at: Date())
        } else {
            finishAway(at: Date())
        }
    }

    private func observeDefaults() {
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleDefaultsChange()
            }
        }
    }

    private func handleDefaultsChange() {
        let feature = CapsStackFeaturePreferences(defaults: defaults)
        if feature.isEnabled != isCapsStackEnabled {
            isCapsStackEnabled = feature.isEnabled
            refreshEnabledState()
        }
        if feature.suppressOriginalCapsLock != isSuppressingOriginalCapsLock || feature.suppressOriginalCapsLock {
            // Re-evaluate suppression error (e.g. permission granted after prompt)
            applyCapsLockSuppression()
        }
        applyBackgroundKeepAlive()
        applyTelemetryPreference()
    }

    private func applyTelemetryPreference() {
        let desired = TelemetryPreferences(defaults: defaults).isEnabled
        guard desired != isTelemetryEnabled else { return }
        telemetry.setEnabled(desired)
        isTelemetryEnabled = telemetry.isEnabled
    }

    private func refreshEnabledState() {
        if isCapsStackEnabled {
            if hasStarted, !monitor.isRunning {
                monitor.start()
                if phase == .disabled { phase = .idle }
                // Resume away if Caps Lock is currently on
                if monitor.isCapsLockOn, phase == .idle {
                    beginAway(at: Date())
                }
            } else if phase == .disabled {
                phase = .idle
            }
        } else {
            // Do not let a collection/summary task started before the setting change publish
            // `.idle` or `.failed` after the controller has entered the disabled state.
            cancelActiveWorkflow()
            monitor.stop()
            sessionCountTask?.cancel()
            sessionCountTask = nil
            if phase == .away {
                defaults.removeObject(forKey: PreferenceKeys.awayStart)
                awayStartedAt = nil
                activeSessionCount = 0
            }
            phase = .disabled
        }
    }

    private func applyBackgroundKeepAlive() {
        let feature = CapsStackFeaturePreferences(defaults: defaults)
        if feature.keepRunningInBackground {
            if backgroundActivity == nil {
                backgroundActivity = ProcessInfo.processInfo.beginActivity(
                    options: [.automaticTerminationDisabled],
                    reason: "CapsStack background monitoring"
                )
            }
        } else {
            if let activity = backgroundActivity {
                ProcessInfo.processInfo.endActivity(activity)
                backgroundActivity = nil
            }
        }
    }

    private func beginAway(at date: Date) {
        guard isCapsStackEnabled else { return }
        guard phase != .away, phase != .summarizing else { return }
        phase = .away
        awayStartedAt = date
        activeSessionCount = 0
        lastError = nil
        defaults.set(date, forKey: PreferenceKeys.awayStart)
        startSessionCounting(from: date)
    }

    private func finishAway(at end: Date) {
        guard phase == .away, let start = awayStartedAt else { return }
        sessionCountTask?.cancel()
        sessionCountTask = nil
        defaults.removeObject(forKey: PreferenceKeys.awayStart)
        awayStartedAt = nil

        let interval = AwayInterval(start: start, end: end)
        let threshold = AwayThresholdPreferences(defaults: defaults)
        guard interval.duration >= 1 else {
            phase = .idle
            activeSessionCount = 0
            return
        }

        if interval.duration < TimeInterval(threshold.minimumAwaySeconds) {
            phase = .idle
            activeSessionCount = 0
            return
        }

        phase = .summarizing
        let quickMemo = QuickMemoPreferences(defaults: defaults).trimmedText
        let summarizerPreferences = SummarizerPreferences(defaults: defaults)
        let primary = summarizerPreferences.primary
        let sources = CollectorPreferences(defaults: defaults).enabledSources
        telemetry.capture(.briefRequested(
            awayDuration: interval.duration,
            sourceCount: sources.count,
            memoPresent: quickMemo != nil
        ))
        let workflowID = beginWorkflow()
        let task = Task { [weak self] in
            guard let self else { return }
            defer { self.finishWorkflow(workflowID) }

            var batch = await collect(interval: interval, sources: sources)
            guard !Task.isCancelled, isCurrentWorkflow(workflowID) else { return }
            batch.quickMemo = quickMemo
            let memoProvider = summarizer.preferredProvider(for: summarizerPreferences) ?? primary
            batch = AwayBatchPreparation.addingSyntheticMemoSession(batch, provider: memoProvider)

            activeSessionCount = batch.sessions.count

            if batch.sessions.isEmpty {
                guard !Task.isCancelled, isCurrentWorkflow(workflowID) else { return }
                telemetry.capture(.briefEmpty(
                    awayDuration: interval.duration,
                    sourceCount: sources.count,
                    issueCount: batch.issues.count
                ))
                do {
                    try saveEmptyHistory(batch: batch, requestedSources: sources)
                    phase = .idle
                } catch {
                    telemetry.capture(.briefFailed(
                        stage: .persistence,
                        code: TelemetryFailureCode.from(error: error),
                        provider: primary
                    ))
                    lastError = error.localizedDescription
                    phase = .failed
                    await notifications.notifyFailure(
                        message: error.localizedDescription,
                        interval: interval
                    )
                }
                activeSessionCount = 0
                return
            }

            do {
                let pending = try historyStore.savePending(batch: batch)
                // Keep the memo until its raw batch is safely persisted. If collection or
                // persistence is cancelled, the user's note remains available for the next run.
                if quickMemo != nil {
                    QuickMemoPreferences(text: "").save(to: defaults)
                }
                guard !Task.isCancelled, isCurrentWorkflow(workflowID) else { return }
                reloadHistory()
                await summarize(batch: batch, replacing: pending, workflowID: workflowID)
            } catch {
                guard !Task.isCancelled, isCurrentWorkflow(workflowID) else { return }
                telemetry.capture(.briefFailed(
                    stage: .persistence,
                    code: TelemetryFailureCode.from(error: error),
                    provider: primary
                ))
                lastError = error.localizedDescription
                phase = .failed
                reloadHistory()
                await notifications.notifyFailure(message: error.localizedDescription, interval: interval)
            }
            activeSessionCount = 0
        }
        activeWorkflowTask = task
    }

    private func summarize(
        batch: CollectionBatch,
        replacing pendingEntry: HistoryEntry,
        workflowID: UInt,
        isRetry: Bool = false
    ) async {
        let summaryStartedAt = Date()
        var failureStage: TelemetryFailureStage = .summarization
        do {
            let outcome = try await summarizer.summarize(
                batch: batch,
                preferences: SummarizerPreferences(defaults: defaults)
            )
            guard !Task.isCancelled, isCurrentWorkflow(workflowID) else { return }
            failureStage = .persistence
            _ = try historyStore.saveCompleted(
                batch: batch,
                outcome: outcome,
                replacingPendingID: pendingEntry.pendingArtifactID
            )
            let summaryDuration = Date().timeIntervalSince(summaryStartedAt)
            if isRetry {
                telemetry.capture(.summaryRetryCompleted(
                    provider: outcome.provider,
                    fallbackUsed: outcome.fallbackUsed,
                    summaryDuration: summaryDuration
                ))
            } else {
                telemetry.capture(.briefCompleted(
                    provider: outcome.provider,
                    fallbackUsed: outcome.fallbackUsed,
                    awayDuration: batch.interval.duration,
                    sessionCount: batch.sessions.count,
                    summaryDuration: summaryDuration
                ))
            }
            reloadHistory()
            phase = .idle
            lastError = nil
            await notifications.notify(
                outcome: outcome,
                interval: batch.interval,
                sessionCount: batch.sessions.count
            )
        } catch {
            let summaryErrorMessage = error.localizedDescription
            let failed = HistoryEntry(
                id: pendingEntry.id,
                interval: pendingEntry.interval,
                status: .pending,
                sessionCount: pendingEntry.sessionCount,
                sources: pendingEntry.sources,
                collectionIssues: pendingEntry.collectionIssues,
                errorMessage: summaryErrorMessage,
                pendingArtifactID: pendingEntry.pendingArtifactID,
                quickMemo: pendingEntry.quickMemo
            )
            guard !Task.isCancelled, isCurrentWorkflow(workflowID) else { return }
            let failureCode = TelemetryFailureCode.from(error: error)
            if isRetry {
                telemetry.capture(.summaryRetryFailed(
                    stage: failureStage,
                    code: failureCode,
                    provider: SummarizerPreferences(defaults: defaults).primary
                ))
            } else {
                telemetry.capture(.briefFailed(
                    stage: failureStage,
                    code: failureCode,
                    provider: SummarizerPreferences(defaults: defaults).primary
                ))
            }
            var presentedErrorMessage = summaryErrorMessage
            do {
                _ = try historyStore.replace(failed)
            } catch {
                presentedErrorMessage += "\n再試行状態を保存できませんでした: \(error.localizedDescription)"
            }
            reloadHistory()
            phase = .failed
            lastError = presentedErrorMessage
            await notifications.notifyFailure(message: presentedErrorMessage, interval: batch.interval)
        }
    }

    private func saveEmptyHistory(batch: CollectionBatch, requestedSources: Set<CLIKind>) throws {
        let entry = HistoryEntry(
            interval: batch.interval,
            status: .empty,
            sessionCount: 0,
            sources: requestedSources.sorted { $0.rawValue < $1.rawValue },
            collectionIssues: batch.issues,
            errorMessage: requestedSources.isEmpty ? "収集元が選択されていません。" : nil
        )
        _ = try historyStore.save(entry)
        reloadHistory()
    }

    /// Starts a new serialized collection/summary workflow and invalidates any older one. The
    /// generation check is still required after cancellation because synchronous collectors may
    /// finish after their parent task has been cancelled.
    private func beginWorkflow() -> UInt {
        activeWorkflowTask?.cancel()
        workflowGeneration &+= 1
        return workflowGeneration
    }

    private func isCurrentWorkflow(_ id: UInt) -> Bool {
        workflowGeneration == id
    }

    private func finishWorkflow(_ id: UInt) {
        guard isCurrentWorkflow(id) else { return }
        activeWorkflowTask = nil
        activeSessionCount = 0
    }

    /// Cancels in-flight work before a destructive/history or settings action changes the state.
    /// The active task may still be draining a detached collector, but its generation is stale so
    /// it cannot mutate history or phase when it returns.
    private func cancelActiveWorkflow() {
        activeWorkflowTask?.cancel()
        activeWorkflowTask = nil
        workflowGeneration &+= 1
        if phase == .summarizing {
            phase = isCapsStackEnabled ? .idle : .disabled
            activeSessionCount = 0
        }
    }

    private func collect(interval: AwayInterval, sources: Set<CLIKind>) async -> CollectionBatch {
        let collector = self.collector
        let executableOverrides = SummarizerPreferences(defaults: defaults).executableOverrides
        return await Task.detached(priority: .utility) {
            collector.collect(
                interval: interval,
                sources: sources,
                executableOverrides: executableOverrides
            )
        }.value
    }

    private func startSessionCounting(from start: Date) {
        sessionCountTask?.cancel()
        let sources = CollectorPreferences(defaults: defaults).enabledSources
        sessionCountTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let batch = await self.collect(
                    interval: AwayInterval(start: start, end: Date()),
                    sources: sources
                )
                guard self.phase == .away else { return }
                self.activeSessionCount = batch.sessions.count
                try? await Task.sleep(nanoseconds: 10_000_000_000)
            }
        }
    }

    func reloadHistory() {
        guard !showsInMemoryDemoData else {
            history = demoEntries
            isShowingDemoData = true
            return
        }

        do {
            history = try historyStore.load()
        } catch {
            history = []
            lastError = error.localizedDescription
            phase = .failed
        }
    }
}
