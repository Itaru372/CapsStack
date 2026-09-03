import SwiftUI

struct SettingsView: View {
    @ObservedObject var controller: AppController
    @StateObject private var launchAtLogin = LaunchAtLoginService()
    @State private var selectedSection: SettingsSection = .collectors
    @State private var searchText = ""
    @State private var showsClearHistoryConfirmation = false

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                TextField("Search settings…", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.callout)
                    .padding(.horizontal, 10)
                    .frame(height: 34)
                    .background(BrandPalette.BriefTheme.card, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(BrandPalette.BriefTheme.border, in: RoundedRectangle(cornerRadius: 8))
                    .padding(.horizontal, 14)
                    .padding(.top, 18)
                    .padding(.bottom, 12)

                ForEach(filteredSections) { section in
                    Button {
                        selectedSection = section
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: section.systemImage)
                                .font(.system(size: 13))
                            Text(section.title)
                                .font(.callout.weight(selectedSection == section ? .semibold : .regular))
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(selectedSection == section ? BrandPalette.BriefTheme.signal : .primary)
                        .padding(.vertical, 9)
                        .padding(.horizontal, 12)
                        .background(
                            selectedSection == section
                                ? BrandPalette.BriefTheme.signal.opacity(0.12)
                                : Color.clear,
                            in: RoundedRectangle(cornerRadius: 7)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 10)
                }

                Spacer(minLength: 0)
            }
            .frame(width: 236)
            .background(BrandPalette.BriefTheme.panel.ignoresSafeArea(edges: .vertical))

            Rectangle()
                .fill(BrandPalette.BriefTheme.border)
                .frame(width: 1)

            detail
                .padding(26)
                .frame(maxWidth: 780, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(BrandPalette.BriefTheme.canvas.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .tint(BrandPalette.BriefTheme.signal)
        .confirmationDialog(
            "Delete all history and retry data?",
            isPresented: $showsClearHistoryConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete All", role: .destructive) {
                controller.clearAllHistory()
            }
            Button("Cancel", role: .cancel) {}
        }
        .onChange(of: searchText) { _, newValue in
            let sections = filteredSections
            if !sections.contains(selectedSection) {
                selectedSection = sections.first ?? selectedSection
            }
        }
        .onAppear {
            launchAtLogin.refresh()
            controller.start()
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch selectedSection {
        case .collectors:
            SettingsScrollView {
                CollectorSettingsView(controller: controller, searchText: searchText)
            }
        case .summarizers:
            SummarizerSettingsView(controller: controller)
        case .general:
            GeneralSettingsView(controller: controller, launchAtLogin: launchAtLogin)
        case .notifications:
            SettingsScrollView {
                NotificationSettingsView(controller: controller)
            }
        case .hotkeys:
            SettingsScrollView {
                HotkeySettingsView()
            }
        case .data:
            SettingsScrollView {
                DataManagementSettingsView(
                    controller: controller,
                    showsClearConfirmation: $showsClearHistoryConfirmation
                )
            }
        case .advanced:
            SettingsScrollView {
                AdvancedSummarizerSettingsView(controller: controller)
            }
        }
    }

    private var filteredSections: [SettingsSection] {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return SettingsSection.allCases
        }
        return SettingsSection.allCases.filter { section in
            section.searchKeywords.localizedCaseInsensitiveContains(searchText)
                || section.title.localizedCaseInsensitiveContains(searchText)
        }
    }
}

/// Custom settings pages need scrolling, while `Form` pages already own their native scroll
/// view. Keeping only one vertical scroll container per page avoids a transparent nested
/// `NSScrollView` intercepting clicks on controls such as toggles and text fields.
private struct SettingsScrollView<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView {
            content()
        }
    }
}

private enum SettingsSection: String, CaseIterable, Identifiable, Hashable {
    case collectors
    case summarizers
    case general
    case notifications
    case hotkeys
    case data
    case advanced

    var id: String { rawValue }

    var title: String {
        switch self {
        case .collectors: "Sources"
        case .summarizers: "Summarizer"
        case .general: "General"
        case .notifications: "Notifications"
        case .hotkeys: "Keyboard shortcuts"
        case .data: "Data management"
        case .advanced: "Advanced"
        }
    }

    var systemImage: String {
        switch self {
        case .collectors: "tray.and.arrow.down"
        case .summarizers: "text.quote"
        case .general: "gearshape"
        case .notifications: "bell"
        case .hotkeys: "command.square"
        case .data: "externaldrive"
        case .advanced: "slider.horizontal.3"
        }
    }

    var searchKeywords: String {
        switch self {
        case .collectors: "Codex Claude OpenCode Pi GitHub Copilot Kilo Goose Qwen Continue Gemini sources logs connection"
        case .summarizers: "summary CLI model fallback signal reasoning"
        case .general: "Caps Lock launch background accessibility away"
        case .notifications: "permission notifications alert sound"
        case .hotkeys: "shortcuts command history settings quit"
        case .data: "history delete backup folder memo privacy"
        case .advanced: "executable path reasoning effort variant thinking"
        }
    }
}

private struct SettingsHeader: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.title2.bold())
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 18)
    }
}

private struct CollectorSettingsView: View {
    @ObservedObject var controller: AppController
    let searchText: String
    @AppStorage(PreferenceKeys.collectCodex) private var collectCodex = false
    @AppStorage(PreferenceKeys.collectClaude) private var collectClaude = false
    @AppStorage(PreferenceKeys.collectOpenCode) private var collectOpenCode = false
    @AppStorage(PreferenceKeys.collectPi) private var collectPi = false
    @AppStorage(PreferenceKeys.collectGitHubCopilot) private var collectGitHubCopilot = false
    @AppStorage(PreferenceKeys.collectKilo) private var collectKilo = false
    @AppStorage(PreferenceKeys.collectGoose) private var collectGoose = false
    @AppStorage(PreferenceKeys.collectQwen) private var collectQwen = false
    @AppStorage(PreferenceKeys.collectContinue) private var collectContinue = false
    @AppStorage(PreferenceKeys.collectGemini) private var collectGemini = false
    @State private var showsUnavailableCollectors = false

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsHeader(
                title: "Sources",
                message: "Choose which agents to collect while you are away. History from supported CLI, Desktop, and IDE clients is combined."
            )

            VStack(spacing: 10) {
                ForEach(primaryCollectorKinds) { kind in
                    collectorRow(kind: kind, isOn: binding(for: kind))
                }

                if !unavailableCollectorKinds.isEmpty {
                    DisclosureGroup("Unavailable agents (\(unavailableCollectorKinds.count))", isExpanded: $showsUnavailableCollectors) {
                        VStack(spacing: 10) {
                            ForEach(unavailableCollectorKinds) { kind in
                                collectorRow(kind: kind, isOn: binding(for: kind))
                            }
                        }
                        .padding(.top, 10)
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                }
            }

            if !CLIKind.collectorCases.contains(where: isEnabled) {
                Label("No collection sources selected", systemImage: "exclamationmark.triangle")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(Color.orange)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(BrandPalette.BriefTheme.card, in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private var primaryCollectorKinds: [CLIKind] {
        CLIKind.collectorCases.filter { kind in
            isEnabled(kind) || controller.cliStatuses[kind].map {
                $0.isInstalled || $0.canReadLogs || $0.isDesktopAppInstalled
            } == true
        }
    }

    private var unavailableCollectorKinds: [CLIKind] {
        CLIKind.collectorCases.filter { !primaryCollectorKinds.contains($0) }
    }

    private func isEnabled(_ kind: CLIKind) -> Bool {
        switch kind {
        case .codex: collectCodex
        case .claudeCode: collectClaude
        case .opencode: collectOpenCode
        case .pi: collectPi
        case .githubCopilot: collectGitHubCopilot
        case .kiloCode: collectKilo
        case .goose: collectGoose
        case .qwenCode: collectQwen
        case .continueCLI: collectContinue
        case .geminiCLI: collectGemini
        }
    }

    private func binding(for kind: CLIKind) -> Binding<Bool> {
        Binding(
            get: { isEnabled(kind) },
            set: { enabled in
                switch kind {
                case .codex: collectCodex = enabled
                case .claudeCode: collectClaude = enabled
                case .opencode: collectOpenCode = enabled
                case .pi: collectPi = enabled
                case .githubCopilot: collectGitHubCopilot = enabled
                case .kiloCode: collectKilo = enabled
                case .goose: collectGoose = enabled
                case .qwenCode: collectQwen = enabled
                case .continueCLI: collectContinue = enabled
                case .geminiCLI: collectGemini = enabled
                }
            }
        )
    }

    private func matches(_ kind: CLIKind) -> Bool {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || kind.collectionDisplayName.localizedCaseInsensitiveContains(searchText)
            || kind.collectionClientDescription.localizedCaseInsensitiveContains(searchText)
    }

    @ViewBuilder
    private func collectorRow(kind: CLIKind, isOn: Binding<Bool>) -> some View {
        if matches(kind) {
            Toggle(isOn: isOn) {
                HStack(spacing: 14) {
                    AgentArtwork(kind: kind)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(kind.collectionDisplayName)
                            .font(.headline)
                        statusText(for: kind)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(collectorStatusColor(for: kind))
                    }

                    Spacer(minLength: 12)
                }
            }
            .toggleStyle(.switch)
            .disabled(cannotEnable(kind, isOn: isOn))
            .accessibilityLabel("Collect from \(kind.collectionDisplayName)")
            .accessibilityValue(isOn.wrappedValue ? "On" : "Off")
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(BrandPalette.BriefTheme.card, in: RoundedRectangle(cornerRadius: 11))
            .overlay(BrandPalette.BriefTheme.border, in: RoundedRectangle(cornerRadius: 11))
            .contentShape(Rectangle())
        }
    }

    @ViewBuilder
    private func statusText(for kind: CLIKind) -> some View {
        if let status = controller.cliStatuses[kind] {
            Text(status.collectionStatusDescription)
        } else {
            Text("Checking…")
        }
    }

    private func cannotEnable(_ kind: CLIKind, isOn: Binding<Bool>) -> Bool {
        guard !isOn.wrappedValue, let status = controller.cliStatuses[kind] else { return false }
        return !status.canCollect
    }

    private func collectorStatusColor(for kind: CLIKind) -> Color {
        guard let status = controller.cliStatuses[kind], !status.canCollect else { return .secondary }
        return .orange
    }
}

private struct SummarizerSettingsView: View {
    @ObservedObject var controller: AppController
    @AppStorage(PreferenceKeys.primarySummarizer) private var primaryRaw = ""
    @AppStorage(PreferenceKeys.automaticFallback) private var automaticFallback = true
    @AppStorage(PreferenceKeys.codexModel) private var codexModel = ""
    @AppStorage(PreferenceKeys.claudeModel) private var claudeModel = ""
    @AppStorage(PreferenceKeys.opencodeModel) private var opencodeModel = ""
    @AppStorage(PreferenceKeys.piModel) private var piModel = ""
    @AppStorage(PreferenceKeys.copilotModel) private var copilotModel = ""
    @AppStorage(PreferenceKeys.kiloModel) private var kiloModel = ""
    @AppStorage(PreferenceKeys.gooseModel) private var gooseModel = ""
    @AppStorage(PreferenceKeys.qwenModel) private var qwenModel = ""
    @AppStorage(PreferenceKeys.codexReasoning) private var codexReasoning = ""
    @AppStorage(PreferenceKeys.claudeReasoning) private var claudeReasoning = ""
    @AppStorage(PreferenceKeys.opencodeReasoning) private var opencodeReasoning = ""
    @AppStorage(PreferenceKeys.piReasoning) private var piReasoning = ""
    @AppStorage(PreferenceKeys.copilotReasoning) private var copilotReasoning = ""
    @State private var showsUnavailableSummarizers = false

    var body: some View {
        Form {
            Section("Return brief") {
                Picker("Summarizer CLI", selection: $primaryRaw) {
                    ForEach(displayedSummarizerKinds) { kind in
                        HStack {
                            Label(kind.displayName, systemImage: kind.systemImage)
                            if kind == .codex {
                                Text("Recommended")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(BrandPalette.BriefTheme.signal)
                            }
                        }
                        .tag(kind.rawValue)
                    }
                }
                .pickerStyle(.radioGroup)

                if !unavailableSummarizerKinds.isEmpty {
                    Button(showsUnavailableSummarizers ? "Hide unavailable CLIs" : "Show unavailable CLIs") {
                        showsUnavailableSummarizers.toggle()
                    }
                    .buttonStyle(.link)
                }

                if let selectedKind, controller.cliStatuses[selectedKind]?.isInstalled == false {
                    Label("The selected CLI was not detected. Set its executable in Advanced settings.", systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(Color.orange)
                }

                if displayedSummarizerKinds.isEmpty {
                    Label("No summarizer CLI is available. Install Codex, Claude Code, OpenCode, or Pi, or set an executable in Advanced settings.", systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(Color.orange)
                }

                if let selectedKind {
                    ModelSelectionControl(
                        kind: selectedKind,
                        model: modelBinding(for: selectedKind),
                        controller: controller
                    )
                    if selectedKind.supportsReasoningOverride {
                        ReasoningSelectionControl(
                            kind: selectedKind,
                            reasoning: reasoningBinding(for: selectedKind)
                        )
                    }
                }

                Toggle("Switch to another CLI if the summary fails", isOn: $automaticFallback)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .onAppear {
            normalizePrimaryIfNeeded()
        }
        .onChange(of: controller.cliStatuses) { _, _ in
            normalizePrimaryIfNeeded()
        }
        .task(id: selectedKind) {
            guard let selectedKind else { return }
            await controller.refreshCLIModels(for: selectedKind)
        }
    }

    private var selectedKind: CLIKind? {
        let kind = CLIKind(rawValue: primaryRaw)
        return kind?.supportsSummarization == true ? kind : nil
    }

    private var availableSummarizerKinds: [CLIKind] {
        CLIKind.summarizerCases.filter { controller.cliStatuses[$0]?.isInstalled == true }
    }

    private var unavailableSummarizerKinds: [CLIKind] {
        CLIKind.summarizerCases.filter { !availableSummarizerKinds.contains($0) }
    }

    private var displayedSummarizerKinds: [CLIKind] {
        guard !showsUnavailableSummarizers else { return CLIKind.summarizerCases }
        let selected = selectedKind.map { [$0] } ?? []
        return CLIKind.summarizerCases.filter { availableSummarizerKinds.contains($0) || selected.contains($0) }
    }

    private func normalizePrimaryIfNeeded() {
        guard let available = availableSummarizerKinds.first else {
            return
        }

        let selected = CLIKind(rawValue: primaryRaw)
        if let selected,
           selected.supportsSummarization,
           controller.cliStatuses[selected]?.isInstalled == true {
            return
        }
        primaryRaw = available.rawValue
    }

    private func modelBinding(for kind: CLIKind) -> Binding<String> {
        Binding(
            get: {
                switch kind {
                case .codex: codexModel
                case .claudeCode: claudeModel
                case .opencode: opencodeModel
                case .pi: piModel
                case .githubCopilot: copilotModel
                case .kiloCode: kiloModel
                case .goose: gooseModel
                case .qwenCode: qwenModel
                case .continueCLI, .geminiCLI: ""
                }
            },
            set: { value in
                switch kind {
                case .codex: codexModel = value
                case .claudeCode: claudeModel = value
                case .opencode: opencodeModel = value
                case .pi: piModel = value
                case .githubCopilot: copilotModel = value
                case .kiloCode: kiloModel = value
                case .goose: gooseModel = value
                case .qwenCode: qwenModel = value
                case .continueCLI, .geminiCLI: break
                }
            }
        )
    }

    private func reasoningBinding(for kind: CLIKind) -> Binding<String> {
        Binding(
            get: {
                switch kind {
                case .codex: codexReasoning
                case .claudeCode: claudeReasoning
                case .opencode: opencodeReasoning
                case .pi: piReasoning
                case .githubCopilot: copilotReasoning
                case .kiloCode, .goose, .qwenCode, .continueCLI, .geminiCLI: ""
                }
            },
            set: { value in
                switch kind {
                case .codex: codexReasoning = value
                case .claudeCode: claudeReasoning = value
                case .opencode: opencodeReasoning = value
                case .pi: piReasoning = value
                case .githubCopilot: copilotReasoning = value
                case .kiloCode, .goose, .qwenCode, .continueCLI, .geminiCLI: break
                }
            }
        )
    }
}

private struct ModelSelectionControl: View {
    let kind: CLIKind
    @Binding var model: String
    @ObservedObject var controller: AppController

    var body: some View {
        if kind.supportsModelListing {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Picker("Model", selection: $model) {
                        Text("CLI default")
                            .tag("")

                        if let currentModel, !controller.models(for: kind).contains(where: { $0.id == currentModel }) {
                            Text("Current setting: \(currentModel)")
                                .tag(model)
                        }

                        ForEach(controller.models(for: kind)) { availableModel in
                            if availableModel.displayName == availableModel.id {
                                Text(availableModel.id)
                                    .tag(availableModel.id)
                            } else {
                                Text("\(availableModel.displayName) (\(availableModel.id))")
                                    .tag(availableModel.id)
                            }
                        }
                    }
                    .accessibilityLabel("\(kind.displayName) model")

                    Button {
                        Task { await controller.refreshCLIModels(for: kind) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .disabled(controller.modelFetchState(for: kind) == .loading)
                    .accessibilityLabel("Refresh \(kind.displayName) model list")
                }

                catalogStatus
            }
            .task(id: kind) {
                await controller.refreshCLIModels(for: kind)
            }
        } else {
            TextField(kind.modelHint, text: $model)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("\(kind.displayName) model")
        }
    }

    private var currentModel: String? {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    @ViewBuilder
    private var catalogStatus: some View {
        switch controller.modelFetchState(for: kind) {
        case .idle:
            Text("You can fetch the model list.")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .loading:
            Label("Fetching model list…", systemImage: "arrow.triangle.2.circlepath")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .loaded:
            if controller.models(for: kind).isEmpty {
                Text("No models were returned. The CLI default will be used.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Fetched \(controller.models(for: kind).count) models")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .failed:
            Label(
                controller.cliModelErrors[kind] ?? "Could not fetch the model list. You can use the CLI default.",
                systemImage: "exclamationmark.triangle"
            )
            .font(.caption)
            .foregroundStyle(Color.orange)
        }
    }
}

private struct ReasoningSelectionControl: View {
    let kind: CLIKind
    @Binding var reasoning: String

    var body: some View {
        if reasoningOptions.isEmpty {
            TextField("Reasoning: \(kind.reasoningHint)", text: $reasoning)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("\(kind.displayName) reasoning")
        } else {
            Picker("Reasoning", selection: $reasoning) {
                Text("CLI default")
                    .tag("")

                if let currentReasoning, !reasoningOptions.contains(currentReasoning) {
                    Text("Current setting: \(currentReasoning)")
                        .tag(currentReasoning)
                }

                ForEach(reasoningOptions, id: \.self) { option in
                    Text(option)
                        .tag(option)
                }
            }
            .accessibilityLabel("\(kind.displayName) reasoning")
        }
    }

    private var currentReasoning: String? {
        let trimmed = reasoning.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var reasoningOptions: [String] {
        switch kind {
        case .codex:
            ["none", "minimal", "low", "medium", "high", "xhigh"]
        case .claudeCode:
            ["low", "medium", "high", "xhigh", "max"]
        case .pi:
            ["off", "minimal", "low", "medium", "high", "xhigh", "max"]
        case .githubCopilot:
            ["low", "medium", "high", "xhigh", "max"]
        case .opencode, .kiloCode, .goose, .qwenCode, .continueCLI, .geminiCLI:
            []
        }
    }
}

private struct GeneralSettingsView: View {
    @ObservedObject var controller: AppController
    @ObservedObject var launchAtLogin: LaunchAtLoginService
    @Environment(\.openWindow) private var openWindow
    @AppStorage(PreferenceKeys.capsStackEnabled) private var capsStackEnabled = true
    @AppStorage(PreferenceKeys.keepRunningInBackground) private var keepRunningInBackground = true
    @AppStorage(PreferenceKeys.suppressOriginalCapsLock) private var suppressOriginalCapsLock = false
    @AppStorage(PreferenceKeys.minimumAwayDuration) private var minimumAwaySeconds = 0
    @AppStorage(PreferenceKeys.setupCompleted) private var setupCompleted = false

    var body: some View {
        Form {
            Section("CapsStack") {
                Toggle("Enable CapsStack", isOn: Binding(
                    get: { capsStackEnabled },
                    set: { newValue in
                        capsStackEnabled = newValue
                        controller.setCapsStackEnabled(newValue)
                    }
                ))
                Stepper("Minimum away time: \(minimumAwaySeconds) seconds", value: $minimumAwaySeconds, in: 0...3600, step: 5)
            }

            Section("Caps Lock") {
                Toggle("Disable normal Caps Lock input", isOn: $suppressOriginalCapsLock)

                if suppressOriginalCapsLock {
                    if controller.isSuppressingOriginalCapsLock {
                        Label("Enabled", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(BrandPalette.BriefTheme.signal)
                    } else {
                        Label("Accessibility permission required", systemImage: "lock.shield")
                            .foregroundStyle(Color.orange)
                        Button("Open System Settings") {
                            controller.openAccessibilitySettings()
                        }
                    }
                }
            }

            Section("Background") {
                Toggle("Always run in the background", isOn: Binding(
                    get: { keepRunningInBackground },
                    set: { newValue in
                        keepRunningInBackground = newValue
                        controller.setKeepRunningInBackground(newValue)
                    }
                ))
                Toggle("Launch at login", isOn: Binding(
                    get: { launchAtLogin.isEnabled },
                    set: { launchAtLogin.setEnabled($0) }
                ))

                if let error = launchAtLogin.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(Color.orange)
                }
            }

            Section("Setup") {
                Button("Open setup…") {
                    setupCompleted = false
                    openWindow(id: "history")
                }
                Text("Review your source, summarizer, and anonymous telemetry choices.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .onChange(of: suppressOriginalCapsLock) { _, newValue in
            controller.setSuppressOriginalCapsLock(newValue)
        }
    }
}

private struct NotificationSettingsView: View {
    @ObservedObject var controller: AppController

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsHeader(title: "Notifications", message: "Receive the summary result in a macOS notification when you return.")

            HStack(spacing: 16) {
                Image(systemName: "bell.fill")
                    .frame(width: 34, height: 34)
                    .background(BrandPalette.BriefTheme.signal.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 4) {
                    Text("macOS notifications").font(.headline)
                    Text(authorizationMessage)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if controller.isNotificationAuthorized == true {
                    Label("Allowed", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(BrandPalette.BriefTheme.signal)
                } else if controller.isNotificationAuthorized == false {
                    Button("Open System Settings") {
                        controller.openNotificationSettings()
                    }
                } else {
                    Button("Request permission") {
                        Task { await controller.requestNotificationAuthorization() }
                    }
                }
            }
            .padding(16)
            .background(BrandPalette.BriefTheme.card, in: RoundedRectangle(cornerRadius: 11))
            .overlay(BrandPalette.BriefTheme.border, in: RoundedRectangle(cornerRadius: 11))
        }
    }

    private var authorizationMessage: String {
        switch controller.isNotificationAuthorized {
        case true: "Summary completions and failures can be delivered."
        case false: "Allow CapsStack notifications in System Settings."
        case nil: "Checking permission…"
        }
    }
}

private struct HotkeySettingsView: View {
    private let shortcuts: [(name: String, shortcut: String)] = [
        ("Open History", "⌘O"),
        ("Open away memo", "⇧⌘M"),
        ("Open Settings", "⌘,"),
        ("Quit CapsStack", "⌘Q")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsHeader(title: "Keyboard shortcuts", message: "Shortcuts available while the app is active.")

            VStack(spacing: 0) {
                ForEach(Array(shortcuts.enumerated()), id: \.offset) { index, shortcut in
                    HStack {
                        Text(shortcut.name)
                        Spacer()
                        Text(shortcut.shortcut)
                            .font(.body.monospacedDigit().weight(.medium))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 13)

                    if index < shortcuts.count - 1 {
                        Divider()
                    }
                }
            }
            .background(BrandPalette.BriefTheme.card, in: RoundedRectangle(cornerRadius: 11))
            .overlay(BrandPalette.BriefTheme.border, in: RoundedRectangle(cornerRadius: 11))
        }
    }
}

private struct DataManagementSettingsView: View {
    @ObservedObject var controller: AppController
    @Binding var showsClearConfirmation: Bool
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsHeader(
                title: "Data management",
                message: "History and away memos are managed only on this Mac."
            )

            dataRow(
                title: "History folder",
                subtitle: controller.historyDirectoryURL.path,
                buttonTitle: "Show",
                action: controller.revealHistoryFolder
            )

            dataRow(
                title: "Copy history path",
                subtitle: "Copy the folder location to the clipboard.",
                buttonTitle: "Copy",
                action: copyPath
            )

            dataRow(
                title: "Delete all history",
                subtitle: "Delete summary history and retry data from failed runs.",
                buttonTitle: "Delete",
                destructive: true,
                action: { showsClearConfirmation = true }
            )

            dataRow(
                title: "Delete away memo",
                subtitle: "Clear the memo saved for the next away interval.",
                buttonTitle: "Delete",
                destructive: true,
                action: {
                    controller.clearQuickMemo()
                    message = "Away memo deleted"
                }
            )

            if let message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func copyPath() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(controller.historyDirectoryURL.path, forType: .string)
        message = "Path copied"
    }

    private func dataRow(
        title: String,
        subtitle: String,
        buttonTitle: String,
        destructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.headline)
                Text(subtitle)
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }

            Spacer()

            Button(buttonTitle, action: action)
                .buttonStyle(.borderedProminent)
                .tint(destructive ? .red : BrandPalette.BriefTheme.signal)
        }
        .padding(16)
        .background(BrandPalette.BriefTheme.card, in: RoundedRectangle(cornerRadius: 11))
        .overlay(BrandPalette.BriefTheme.border, in: RoundedRectangle(cornerRadius: 11))
    }
}

private struct AdvancedSummarizerSettingsView: View {
    @ObservedObject var controller: AppController
    @AppStorage(PreferenceKeys.codexExecutablePath) private var codexPath = ""
    @AppStorage(PreferenceKeys.claudeExecutablePath) private var claudePath = ""
    @AppStorage(PreferenceKeys.opencodeExecutablePath) private var opencodePath = ""
    @AppStorage(PreferenceKeys.piExecutablePath) private var piPath = ""
    @AppStorage(PreferenceKeys.copilotExecutablePath) private var copilotPath = ""
    @AppStorage(PreferenceKeys.kiloExecutablePath) private var kiloPath = ""
    @AppStorage(PreferenceKeys.gooseExecutablePath) private var goosePath = ""
    @AppStorage(PreferenceKeys.qwenExecutablePath) private var qwenPath = ""
    @AppStorage(PreferenceKeys.codexModel) private var codexModel = ""
    @AppStorage(PreferenceKeys.claudeModel) private var claudeModel = ""
    @AppStorage(PreferenceKeys.opencodeModel) private var opencodeModel = ""
    @AppStorage(PreferenceKeys.piModel) private var piModel = ""
    @AppStorage(PreferenceKeys.copilotModel) private var copilotModel = ""
    @AppStorage(PreferenceKeys.kiloModel) private var kiloModel = ""
    @AppStorage(PreferenceKeys.gooseModel) private var gooseModel = ""
    @AppStorage(PreferenceKeys.qwenModel) private var qwenModel = ""
    @AppStorage(PreferenceKeys.codexReasoning) private var codexReasoning = ""
    @AppStorage(PreferenceKeys.claudeReasoning) private var claudeReasoning = ""
    @AppStorage(PreferenceKeys.opencodeReasoning) private var opencodeReasoning = ""
    @AppStorage(PreferenceKeys.piReasoning) private var piReasoning = ""
    @AppStorage(PreferenceKeys.copilotReasoning) private var copilotReasoning = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsHeader(title: "Advanced", message: "Configure each CLI's executable, model, and reasoning level. Supported CLIs can load their model list.")

            ExecutableRow(
                kind: .codex,
                path: $codexPath,
                model: $codexModel,
                reasoning: $codexReasoning,
                controller: controller
            )
            ExecutableRow(
                kind: .claudeCode,
                path: $claudePath,
                model: $claudeModel,
                reasoning: $claudeReasoning,
                controller: controller
            )
            ExecutableRow(
                kind: .opencode,
                path: $opencodePath,
                model: $opencodeModel,
                reasoning: $opencodeReasoning,
                controller: controller
            )
            ExecutableRow(
                kind: .pi,
                path: $piPath,
                model: $piModel,
                reasoning: $piReasoning,
                controller: controller
            )
            ExecutableRow(
                kind: .githubCopilot,
                path: $copilotPath,
                model: $copilotModel,
                reasoning: $copilotReasoning,
                controller: controller
            )
            ExecutableRow(
                kind: .kiloCode,
                path: $kiloPath,
                model: $kiloModel,
                reasoning: .constant(""),
                controller: controller
            )
            ExecutableRow(
                kind: .goose,
                path: $goosePath,
                model: $gooseModel,
                reasoning: .constant(""),
                controller: controller
            )
            ExecutableRow(
                kind: .qwenCode,
                path: $qwenPath,
                model: $qwenModel,
                reasoning: .constant(""),
                controller: controller
            )
        }
    }
}

private struct ExecutableRow: View {
    let kind: CLIKind
    @Binding var path: String
    @Binding var model: String
    @Binding var reasoning: String
    @ObservedObject var controller: AppController
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                AgentArtwork(kind: kind, size: 32)

                VStack(alignment: .leading, spacing: 3) {
                    Text(kind.displayName).font(.headline)
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if let testMessage = controller.providerTestMessages[kind] {
                        Text(testMessage)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(testMessageColor(testMessage))
                            .lineLimit(1)
                    }
                }

                Spacer()

                Button {
                    if controller.testingProvider == kind {
                        controller.cancelProviderTest()
                    } else {
                        controller.startProviderTest(kind)
                    }
                } label: {
                    if controller.testingProvider == kind {
                        Label("Cancel", systemImage: "xmark")
                    } else {
                        Text("Test")
                    }
                }
                .disabled(controller.testingProvider != nil && controller.testingProvider != kind)
                .accessibilityLabel(
                    controller.testingProvider == kind
                        ? "Cancel \(kind.displayName) connection test"
                        : "Test \(kind.displayName) connection"
                )

                Button(isExpanded ? "Close" : "Details") {
                    withAnimation(.easeOut(duration: 0.18)) { isExpanded.toggle() }
                }
                .buttonStyle(.borderless)
            }

            if isExpanded {
                Divider()
                TextField("Executable path (leave blank to detect automatically)", text: $path)
                    .textFieldStyle(.roundedBorder)
                ModelSelectionControl(
                    kind: kind,
                    model: $model,
                    controller: controller
                )
                if kind.supportsReasoningOverride {
                    ReasoningSelectionControl(kind: kind, reasoning: $reasoning)
                }

                if let testMessage = controller.providerTestMessages[kind] {
                    Text(testMessage)
                        .font(.caption)
                        .foregroundStyle(testMessageColor(testMessage))
                }
            }
        }
        .padding(16)
        .background(BrandPalette.BriefTheme.card, in: RoundedRectangle(cornerRadius: 11))
        .overlay(BrandPalette.BriefTheme.border, in: RoundedRectangle(cornerRadius: 11))
        .onChange(of: path) { _, _ in
            Task {
                await controller.refreshCLIStatuses()
                await controller.refreshCLIModels(for: kind)
            }
        }
    }

    private var statusText: String {
        guard let status = controller.cliStatuses[kind] else { return "Checking…" }
        if status.isInstalled {
            return status.version ?? status.executablePath ?? "Detected"
        }
        return "Not detected"
    }

    private func testMessageColor(_ message: String) -> Color {
        switch message {
        case "Success": BrandPalette.BriefTheme.signal
        case "Checking…", "Cancelled": .secondary
        default: .red
        }
    }
}
