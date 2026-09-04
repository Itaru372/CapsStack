import Foundation

/// Shared user-facing strings for the app and `capsstack-cli`.
///
/// English remains the key and fallback language so existing exports and diagnostics keep their
/// current contract. The Japanese translations live in the package's `ja.lproj` string table.
public enum CapsStackText {
    public enum Key: String, CaseIterable, Sendable {
        // App state and workflow
        case paused = "Paused"
        case ready = "Ready"
        case away = "Away"
        case summarizingProgress = "Summarizing progress"
        case summaryFailed = "Summary failed"
        case enableCapsStackResume = "Enable CapsStack in Settings to resume monitoring"
        case capsLockOnCollect = "Turn Caps Lock on to start collecting"
        case capsLockOffSummary = "Turn Caps Lock off to generate a summary"
        case collectionSummaryIndependent = "Collection and summarization run independently"
        case retrySummaryHistory = "Retry the summary from History"
        case cancelled = "Cancelled"
        case checking = "Checking…"
        case success = "Success"
        case providerTestFailed = "Failed: %@"
        case noCollectionSources = "No collection sources are selected."
        case couldNotSaveRetryData = "Could not save retry data"

        // App chrome and history
        case historyWindow = "CapsStack History"
        case history = "History"
        case openHistory = "Open History"
        case reload = "Reload"
        case settings = "Settings"
        case settingsEllipsis = "Settings…"
        case awayMemoWindow = "Away Memo"
        case awayMemo = "Away memo"
        case awayMemoEllipsis = "Away memo…"
        case editAwayMemoEllipsis = "Edit away memo…"
        case returnNow = "Return now"
        case reviewHistoryDetails = "Review the details in History"
        case quitCapsStack = "Quit CapsStack"
        case capsStackStatus = "CapsStack status: %@"
        case stepOf = "Step %lld of %lld · %@"
        case collectFrom = "Collect from %@"
        case on = "On"
        case off = "Off"
        case demoData = "Demo data"
        case noHistoryYet = "No history yet"
        case noHistoryYetPeriod = "No history yet."
        case startRecordingAway = "Turn Caps Lock on to start recording an away interval."
        case deleteSelectedHistory = "Delete the selected history entry?"
        case deleteAllHistoryConfirmation = "Delete all history and retry data?"
        case delete = "Delete"
        case deleteAll = "Delete All"
        case cancel = "Cancel"
        case copy = "Copy"
        case copyStatus = "Copy status"
        case exportMarkdown = "Export Markdown"
        case retrySummary = "Retry summary"
        case historyStatusCopied = "History status copied"
        case copied = "Copied"
        case historyStatusSaved = "History status saved"
        case saved = "Saved"
        case couldNotSave = "Could not save"
        case returnBrief = "Return brief"
        case summaryUnavailable = "Summary unavailable"
        case checkSummarizerTryAgain = "Check the summarizer CLI and try again."
        case noSourceSessions = "No source sessions"
        case noSourceSessionsDescription = "No supported sessions or away memo were captured for this interval."
        case collectionNotes = "Collection notes"
        case collectionNotesCount = "Collection notes (%lld)"
        case collectionNotesDetail = "Diagnostics from collection"
        case currentState = "Current state"
        case blockers = "Blockers"
        case progress = "Progress"
        case decisions = "Decisions"
        case nextSteps = "Next steps"
        case byProject = "By project"
        case bySession = "By session"
        case notSet = "Not set"
        case fallbackUsed = "Fallback used"
        case notificationAwayProgress = "CapsStack — Away progress"
        case notificationSummaryFailed = "CapsStack — Summary failed"
        case notificationSubtitle = "%@ / %lld sessions"
        case durationLabel = "Duration"
        case sessionsLabel = "Sessions"
        case statusLabel = "Status"
        case fallbackSuffix = "(fallback)"
        case sessionsCount = "%lld sessions"
        case created = "Created: %@"
        case modelMetadata = "Model: %@"
        case characters = "Characters: %@"
        case projectSessionsAccessibility = "%@, %lld sessions"
        case sharedSession = "%@ Shared Session"
        case unknownProject = "Unknown project"

        // Quick memo and setup
        case quickMemoDescription = "Add context for work that is not captured in logs, such as GUI apps."
        case quickMemoPlaceholder = "What should your return brief remember?"
        case savedAutomaticallyOnThisMac = "Saved automatically on this Mac"
        case clear = "Clear"
        case done = "Done"
        case setup = "Setup"
        case setupIntroduction = "Come back caught up.\nKnow your next move."
        case setupDescription = "Use Caps Lock as your away switch and build a return brief from local work history."
        case localProcessing = "Session content and memos are processed only on this Mac."
        case workHistorySources = "Work history sources"
        case noReadableHistory = "No supported agents or readable history were found yet. You can still use an away memo."
        case returnBriefSummarizer = "Return brief summarizer"
        case noSummarizerForSetup = "No CLI is available for summarization. Install one and check again, or set its executable path."
        case anonymousTelemetry = "Anonymous telemetry"
        case shareAnonymousUsage = "Share anonymous usage data"
        case anonymousEventsNotSent = "Anonymous events are not sent because this build has no telemetry destination configured."
        case aggregateTelemetry = "Only aggregate events such as setup completion, first brief success, brief consumption, and one-click helpfulness are sent. History, memos, session content, paths, credentials, and written feedback are never sent."
        case briefFeedbackPrompt = "Was this brief helpful?"
        case briefFeedbackDescription = "Optional one-click feedback. No written feedback is collected."
        case briefFeedbackHelpful = "Helpful"
        case briefFeedbackMissingContext = "Missing important context"
        case briefFeedbackTooVerbose = "Too verbose"
        case briefFeedbackIncorrect = "Incorrect or misleading"
        case briefFeedbackThanks = "Thanks for the feedback."
        case howItWorks = "How it works"
        case turnCapsLockOn = "Turn Caps Lock on"
        case startAwayInterval = "Start an away interval"
        case stepAway = "Step away"
        case collectCLIHistoryLocally = "Collect CLI history locally"
        case turnCapsLockOff = "Turn Caps Lock off"
        case generateReturnBrief = "Generate a return brief"
        case back = "Back"
        case checkAgain = "Check again"
        case openAdvancedSettings = "Open Advanced Settings"
        case startUsingCapsStack = "Start using CapsStack"
        case next = "Next"
        case currentStep = "Current step"
        case completed = "Completed"
        case notCompleted = "Not completed"
        case reviewSources = "Review sources"
        case chooseSummarizer = "Choose a summarizer"
        case reviewPrivacy = "Review privacy"
        case startWithCapsLock = "Start with Caps Lock"
        case selectDetectedAgents = "Select detected agents automatically"
        case generateBriefsPreferredCLI = "Generate briefs with your preferred CLI"
        case telemetryStartsOff = "Anonymous telemetry starts off"
        case onToStepAwayOffToReturn = "On to step away, off to return"

        // Settings
        case searchSettings = "Search settings…"
        case sources = "Sources"
        case sourcesDescription = "Choose which agents to collect while you are away. History from supported CLI, Desktop, and IDE clients is combined."
        case summarizer = "Summarizer"
        case general = "General"
        case notifications = "Notifications"
        case keyboardShortcuts = "Keyboard shortcuts"
        case dataManagement = "Data management"
        case advanced = "Advanced"
        case unavailableAgents = "Unavailable agents (%lld)"
        case noCollectionSourcesSelected = "No collection sources selected"
        case summarizerCLI = "Summarizer CLI"
        case recommended = "Recommended"
        case hideUnavailableCLIs = "Hide unavailable CLIs"
        case showUnavailableCLIs = "Show unavailable CLIs"
        case selectedCLINotDetected = "The selected CLI was not detected. Set its executable in Advanced settings."
        case noSummarizerAvailable = "No summarizer CLI is available. Install Codex, Claude Code, OpenCode, or Pi, or set an executable in Advanced settings."
        case switchCLIOnFailure = "Switch to another CLI if the summary fails"
        case model = "Model"
        case cliDefault = "CLI default"
        case currentSetting = "Current setting: %@"
        case modelAccessibility = "%@ model"
        case reasoningAccessibility = "%@ reasoning"
        case refreshModelList = "Refresh %@ model list"
        case canFetchModelList = "You can fetch the model list."
        case fetchingModelList = "Fetching model list…"
        case noModelsReturned = "No models were returned. The CLI default will be used."
        case fetchedModels = "Fetched %lld models"
        case modelListFetchFallback = "Could not fetch the model list. You can use the CLI default."
        case openCode2Incompatible = "The OpenCode 2 CLI is not compatible with the current OpenCode 1 adapter."
        case reasoning = "Reasoning"
        case reasoningHint = "Reasoning: %@"
        case executablePath = "Executable path (leave blank to detect automatically)"
        case test = "Test"
        case close = "Close"
        case details = "Details"
        case testConnection = "Test %@ connection"
        case cancelConnectionTest = "Cancel %@ connection test"
        case detected = "Detected"
        case notDetected = "Not detected"
        case enableCapsStack = "Enable CapsStack"
        case capsStackSection = "CapsStack"
        case minimumAwayTime = "Minimum away time: %lld seconds"
        case capsLock = "Caps Lock"
        case cli = "CLI"
        case desktop = "Desktop"
        case cliDesktopIDE = "CLI / Desktop / IDE"
        case cliDesktopIDEOfficialExport = "CLI / Desktop / IDE (via official export)"
        case detectedSources = "%@ detected"
        case collectionStatus = "%@ · %@"
        case codexModelHint = "e.g. gpt-5.5 (leave blank for Codex's default)"
        case claudeModelHint = "e.g. sonnet or claude-sonnet-4-5 (leave blank for the default)"
        case opencodeModelHint = "e.g. anthropic/claude-sonnet-4-5 (provider/model)"
        case piModelHint = "e.g. openai/gpt-5.5 or a model ID"
        case copilotModelHint = "e.g. gpt-5.4 (leave blank for Copilot's default)"
        case kiloModelHint = "e.g. anthropic/claude-sonnet-4-6 (leave blank for the default)"
        case gooseModelHint = "e.g. claude-sonnet-4-6 (leave blank for Goose's default)"
        case qwenModelHint = "e.g. qwen3-coder-plus (leave blank for the default)"
        case continueModelHint = "e.g. claude-sonnet-4-6 (leave blank for the default)"
        case collectionOnly = "Collection only (not available as a summarizer)"
        case codexReasoningHint = "minimal / low / medium / high / xhigh / none"
        case claudeReasoningHint = "low / medium / high / max / xhigh (depends on the CLI version)"
        case opencodeReasoningHint = "A variant name supported by the selected model"
        case piReasoningHint = "off / minimal / low / medium / high / xhigh / max"
        case copilotReasoningHint = "low / medium / high / xhigh / max"
        case kiloReasoningHint = "Uses the Ask agent for summaries (no reasoning override)"
        case gooseReasoningHint = "Uses Chat mode for summaries (no reasoning override)"
        case modelDefaultReasoningHint = "Uses the model's default (no reasoning override)"
        case disableNormalCapsLock = "Disable normal Caps Lock input"
        case enabled = "Enabled"
        case accessibilityPermissionRequired = "Accessibility permission required"
        case openSystemSettings = "Open System Settings"
        case background = "Background"
        case alwaysRunBackground = "Always run in the background"
        case launchAtLogin = "Launch at login"
        case reviewSetupChoices = "Review your source, summarizer, and anonymous telemetry choices."
        case openSetup = "Open setup…"
        case openSettings = "Open Settings"
        case notificationsDescription = "Receive the summary result in a macOS notification when you return."
        case macOSNotifications = "macOS notifications"
        case allowed = "Allowed"
        case requestPermission = "Request permission"
        case notificationsAllowedDescription = "Summary completions and failures can be delivered."
        case notificationsDeniedDescription = "Allow CapsStack notifications in System Settings."
        case checkingPermission = "Checking permission…"
        case shortcutsAvailable = "Shortcuts available while the app is active."
        case openAwayMemo = "Open away memo"
        case historyOnlyThisMac = "History and away memos are managed only on this Mac."
        case historyFolder = "History folder"
        case show = "Show"
        case copyHistoryPath = "Copy history path"
        case copyFolderLocation = "Copy the folder location to the clipboard."
        case deleteAllHistory = "Delete all history"
        case deleteHistoryDescription = "Delete summary history and retry data from failed runs."
        case deleteAwayMemo = "Delete away memo"
        case clearAwayMemoDescription = "Clear the memo saved for the next away interval."
        case awayMemoDeleted = "Away memo deleted"
        case pathCopied = "Path copied"
        case advancedDescription = "Configure each CLI's executable, model, and reasoning level. Supported CLIs can load their model list."

        // CLI and diagnostics
        case unknownCommand = "Unknown command: %@"
        case missingArgument = "Missing argument: %@"
        case invalidArgument = "Invalid argument: %@"
        case conflictingOptions = "Conflicting options: %@"
        case historyActions = "list|latest|show"
        case memoActions = "get|set|clear"
        case stdinAndText = "--stdin and <text>"
        case textOrStdin = "<text> or --stdin"
        case jsonAndMarkdown = "--json and --markdown"
        case cliStatus = "CapsStack status"
        case cliUsage = "Usage:"
        case cliAliases = "Aliases:"
        case historyPath = "History: %@"
        case historyFileStatus = "History file: %@ / %lld entries"
        case awayMemoStatus = "Away memo: %@"
        case historyFilePresent = "present"
        case historyFileMissing = "missing"
        case awayMemoNone = "none"
        case agentCLIs = "Agent CLIs:"
        case noAwayMemo = "No away memo."
        case awayMemoCleared = "Away memo cleared."
        case duration = "Duration: %@ / Sessions: %lld"
        case noSummary = "No summary"
        case errorPrefix = "error: %@"
        case capsStackSummary = "# CapsStack Summary — %@"
        case capsStackHistory = "# CapsStack History — %@"
        case error = "Error"
        case pendingSummary = "Pending summary"
        case noSessions = "No sessions"
        case executableNotFound = "Executable not found: %@"
        case couldNotStartProcess = "Could not start process: %@"
        case processTimedOut = "Process timed out."
        case processCancelled = "Process was cancelled."
        case historyReadFailure = "Could not read the CapsStack history file."
        case pendingArtifactNotFound = "Pending collection artifact not found: %@"
        case historyEntryNotFound = "History entry not found: %@"
        case historyUnreadable = "Could not read the CapsStack history file: %@"
        case noProgressSummary = "No progress could be summarized."
        case providerNotFound = "%@ was not found."
        case providerFailed = "%@ failed to run: %@"
        case providerTimedOut = "%@ summary timed out."
        case providerInvalidOutput = "%@ returned an unreadable summary."
        case exitCode = "Exit code %d"
        case noProviderAvailable = "No summarizer CLI is available."
        case modelListingUnsupported = "%@ does not support model listing."
        case modelExecutableNotFound = "%@ executable was not found."
        case modelListingTimedOut = "Timed out while fetching the %@ model list."
        case modelListFetchFailed = "Could not fetch the model list from %@."
        case modelListParseFailed = "Could not parse the %@ model list."
        case accessibilityPermissionMessage = "Accessibility permission is required. Allow CapsStack in System Settings > Privacy & Security > Accessibility."
        case capsLockMonitoringFailed = "Could not start monitoring Caps Lock. Check your Accessibility permission."
        case eventTapRegistrationFailed = "Could not register the keyboard event tap."
        case logDirectoryNotFound = "Log directory not found: %@"
        case logDirectoryReadFailed = "Could not read log directory: %@"
        case tooManyLogFiles = "There are too many log files to inspect; only the latest %lld were read."
        case largeLogLimited = "Large log was limited to the last %lld MB: %@"
        case invalidJSONLinesSkipped = "Skipped %lld invalid JSONL lines in %@."
        case oversizedLinesSkipped = "Skipped %lld oversized lines in %@."
        case logReadFailed = "Could not read log (%@): %@"
        case copilotDirectoryReadFailed = "Could not read the GitHub Copilot session directory: %@"
        case tooManySessions = "There are too many sessions to inspect; only the latest %lld were checked."
        case logStorageDirectoryNotFound = "Log storage directory not found: %@"
        case providerNotFoundNoPeriod = "%@ was not found"
        case listSessionsFailed = "Could not list %@ sessions"
        case parseSessionListFailed = "Could not parse the %@ session list"
        case collectionTimedOut = "%@ collection exceeded %lld seconds; remaining sessions will be retried next time."
        case exportSessionFailed = "Could not export the %@ session: %@"
        case storageNotParsedDirectly = "%@. The DB-backed CLI storage was not parsed directly."
        case storageScannedFallback = "%@; storage files were scanned as a fallback."
        case additionalCollectionWarnings = "Omitted %lld additional collection warnings."
        case openCodeDesktopRequiresCLI = "Desktop detected · OpenCode CLI is required for collection"
        case inputChunksOmitted = "The input limit omitted %lld intermediate summary chunks."
        case projectSummariesOmitted = "The combined input limit omitted part of the project summaries."

        // Several app and CLI surfaces intentionally reuse the same localized wording. Keep
        // aliases instead of duplicate raw-value cases so this enum remains compilable while
        // preserving every existing call site.
        public static let returnBriefSection = Self.returnBrief
        public static let historyFile = Self.historyFileStatus
        public static let awayMemoPresent = Self.historyFilePresent
        public static let sessions = Self.sessionsLabel
        public static let status = Self.statusLabel
        public static let summarizerCLIMetadata = Self.summarizerCLI
        public static let sourcesMetadata = Self.sources
        public static let awayMemoMetadata = Self.awayMemo
        public static let collectionNotesMetadata = Self.collectionNotes
        public static let byProjectMetadata = Self.byProject
        public static let bySessionMetadata = Self.bySession
        public static let openCodeCollectionFailure = Self.storageNotParsedDirectly
    }

    public static func resource(_ key: Key, locale: Locale = .current) -> LocalizedStringResource {
        LocalizedStringResource(
            String.LocalizationValue(key.rawValue),
            locale: locale,
            bundle: .module
        )
    }

    public static func resolve(_ key: Key, locale: Locale = .current) -> String {
        // Foundation's `String(localized:bundle:locale:)` does not reliably select a SwiftPM
        // resource bundle's language table when the key is dynamic. Resolve against the
        // language-specific child bundle explicitly so non-SwiftUI surfaces (errors, notices,
        // CLI output, and Markdown) follow the same display language as the views.
        let bundle = localizedBundle(for: locale)
        return bundle.localizedString(
            forKey: key.rawValue,
            value: key.rawValue,
            table: "Localizable"
        )
    }

    public static func format(_ key: Key, _ arguments: CVarArg..., locale: Locale = .current) -> String {
        let format = resolve(key, locale: locale)
        return String(format: format, locale: locale, arguments: arguments)
    }

    private static func localizedBundle(for locale: Locale) -> Bundle {
        let moduleBundle = Bundle.module
        let identifiers: [String] = [
            locale.identifier,
            locale.identifier.replacingOccurrences(of: "_", with: "-"),
            locale.language.languageCode?.identifier
        ].compactMap { $0 }
        for identifier in identifiers where !identifier.isEmpty {
            if let path = moduleBundle.path(forResource: identifier, ofType: "lproj"),
               let bundle = Bundle(path: path) {
                return bundle
            }
        }
        return moduleBundle
    }
}
