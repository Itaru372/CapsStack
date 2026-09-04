import CapsStackLocalization
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
                TextField(CapsStackText.resolve(.searchSettings), text: $searchText)
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
        .frame(minWidth: 900, idealWidth: 980, minHeight: 600, idealHeight: 680)
        .background(BrandPalette.BriefTheme.canvas.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .tint(BrandPalette.BriefTheme.signal)
        .confirmationDialog(
            CapsStackText.resource(.deleteAllHistoryConfirmation),
            isPresented: $showsClearHistoryConfirmation,
            titleVisibility: .visible
        ) {
            Button(CapsStackText.resource(.deleteAll), role: .destructive) {
                controller.clearAllHistory()
            }
            Button(CapsStackText.resource(.cancel), role: .cancel) {}
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
                .padding(.bottom, 20)
        }
        .scrollIndicators(.visible)
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
        case .collectors: CapsStackText.resolve(.sources)
        case .summarizers: CapsStackText.resolve(.summarizer)
        case .general: CapsStackText.resolve(.general)
        case .notifications: CapsStackText.resolve(.notifications)
        case .hotkeys: CapsStackText.resolve(.keyboardShortcuts)
        case .data: CapsStackText.resolve(.dataManagement)
        case .advanced: CapsStackText.resolve(.advanced)
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
        case .collectors: "Codex Claude OpenCode Pi GitHub Copilot Kilo Goose Qwen Continue Gemini sources logs connection 収集元 ログ 接続"
        case .summarizers: "summary CLI model fallback signal reasoning 要約 モデル フォールバック 推論"
        case .general: "Caps Lock launch background accessibility away 起動 常駐 アクセシビリティ 退席"
        case .notifications: "permission notifications alert sound 許可 通知 サウンド"
        case .hotkeys: "shortcuts command history settings quit ショートカット 履歴 設定 終了"
        case .data: "history delete backup folder memo privacy 履歴 削除 フォルダ メモ プライバシー"
        case .advanced: "executable path reasoning effort variant thinking 実行ファイル パス 推論強度"
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
                title: CapsStackText.resolve(.sources),
                message: CapsStackText.resolve(.sourcesDescription)
            )

            VStack(spacing: 10) {
                ForEach(primaryCollectorKinds) { kind in
                    collectorRow(kind: kind, isOn: binding(for: kind))
                }

                if !unavailableCollectorKinds.isEmpty {
                    DisclosureGroup(
                        CapsStackText.format(.unavailableAgents, unavailableCollectorKinds.count),
                        isExpanded: $showsUnavailableCollectors
                    ) {
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
                Label(CapsStackText.resource(.noCollectionSourcesSelected), systemImage: "exclamationmark.triangle")
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
            .accessibilityLabel(CapsStackText.format(.collectFrom, kind.collectionDisplayName))
            .accessibilityValue(CapsStackText.resolve(isOn.wrappedValue ? .on : .off))
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
            Text(CapsStackText.resource(.checking))
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
            Section(CapsStackText.resource(.returnBriefSection)) {
                Picker(CapsStackText.resource(.summarizerCLI), selection: $primaryRaw) {
                    ForEach(displayedSummarizerKinds) { kind in
                        HStack {
                            Label(kind.displayName, systemImage: kind.systemImage)
                            if kind == .codex {
                                Text(CapsStackText.resource(.recommended))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(BrandPalette.BriefTheme.signal)
                            }
                        }
                        .tag(kind.rawValue)
                    }
                }
                .pickerStyle(.radioGroup)

                if !unavailableSummarizerKinds.isEmpty {
                    Button(CapsStackText.resource(
                        showsUnavailableSummarizers ? .hideUnavailableCLIs : .showUnavailableCLIs
                    )) {
                        showsUnavailableSummarizers.toggle()
                    }
                    .buttonStyle(.link)
                }

                if let selectedKind, controller.cliStatuses[selectedKind]?.isInstalled == false {
                    Label(CapsStackText.resource(.selectedCLINotDetected), systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(Color.orange)
                }

                if displayedSummarizerKinds.isEmpty {
                    Label(CapsStackText.resource(.noSummarizerAvailable), systemImage: "exclamationmark.triangle")
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

                Toggle(CapsStackText.resource(.switchCLIOnFailure), isOn: $automaticFallback)
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
                    Picker(CapsStackText.resource(.model), selection: $model) {
                        Text(CapsStackText.resource(.cliDefault))
                            .tag("")

                        if let currentModel, !controller.models(for: kind).contains(where: { $0.id == currentModel }) {
                            Text(CapsStackText.format(.currentSetting, currentModel))
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
                    .accessibilityLabel(CapsStackText.format(.modelAccessibility, kind.displayName))

                    Button {
                        Task { await controller.refreshCLIModels(for: kind) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .disabled(controller.modelFetchState(for: kind) == .loading)
                    .accessibilityLabel(CapsStackText.format(.refreshModelList, kind.displayName))
                }

                catalogStatus
            }
            .task(id: kind) {
                await controller.refreshCLIModels(for: kind)
            }
        } else {
            TextField(kind.modelHint, text: $model)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel(CapsStackText.format(.modelAccessibility, kind.displayName))
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
            Text(CapsStackText.resource(.canFetchModelList))
                .font(.caption)
                .foregroundStyle(.secondary)
        case .loading:
            Label(CapsStackText.resource(.fetchingModelList), systemImage: "arrow.triangle.2.circlepath")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .loaded:
            if controller.models(for: kind).isEmpty {
                Text(CapsStackText.resource(.noModelsReturned))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text(CapsStackText.format(.fetchedModels, controller.models(for: kind).count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .failed:
            Label(
                controller.cliModelErrors[kind] ?? CapsStackText.resolve(.modelListFetchFallback),
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
            TextField(CapsStackText.format(.reasoningHint, kind.reasoningHint), text: $reasoning)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel(CapsStackText.format(.reasoningAccessibility, kind.displayName))
        } else {
            Picker(CapsStackText.resource(.reasoning), selection: $reasoning) {
                Text(CapsStackText.resource(.cliDefault))
                    .tag("")

                if let currentReasoning, !reasoningOptions.contains(currentReasoning) {
                    Text(CapsStackText.format(.currentSetting, currentReasoning))
                        .tag(currentReasoning)
                }

                ForEach(reasoningOptions, id: \.self) { option in
                    Text(option)
                        .tag(option)
                }
            }
            .accessibilityLabel(CapsStackText.format(.reasoningAccessibility, kind.displayName))
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
            Section(CapsStackText.resource(.capsStackSection)) {
                Toggle(CapsStackText.resource(.enableCapsStack), isOn: Binding(
                    get: { capsStackEnabled },
                    set: { newValue in
                        capsStackEnabled = newValue
                        controller.setCapsStackEnabled(newValue)
                    }
                ))
                Stepper(CapsStackText.format(.minimumAwayTime, minimumAwaySeconds), value: $minimumAwaySeconds, in: 0...3600, step: 5)
            }

            Section(CapsStackText.resource(.capsLock)) {
                Toggle(CapsStackText.resource(.disableNormalCapsLock), isOn: $suppressOriginalCapsLock)

                if suppressOriginalCapsLock {
                    if controller.isSuppressingOriginalCapsLock {
                        Label(CapsStackText.resource(.enabled), systemImage: "checkmark.circle.fill")
                            .foregroundStyle(BrandPalette.BriefTheme.signal)
                    } else {
                        Label(CapsStackText.resource(.accessibilityPermissionRequired), systemImage: "lock.shield")
                            .foregroundStyle(Color.orange)
                        Button(CapsStackText.resource(.openSystemSettings)) {
                            controller.openAccessibilitySettings()
                        }
                    }
                }
            }

            Section(CapsStackText.resource(.background)) {
                Toggle(CapsStackText.resource(.alwaysRunBackground), isOn: Binding(
                    get: { keepRunningInBackground },
                    set: { newValue in
                        keepRunningInBackground = newValue
                        controller.setKeepRunningInBackground(newValue)
                    }
                ))
                Toggle(CapsStackText.resource(.launchAtLogin), isOn: Binding(
                    get: { launchAtLogin.isEnabled },
                    set: { launchAtLogin.setEnabled($0) }
                ))

                if let error = launchAtLogin.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(Color.orange)
                }
            }

            Section(CapsStackText.resource(.setup)) {
                Button(CapsStackText.resource(.openSetup)) {
                    setupCompleted = false
                    openWindow(id: "history")
                }
                Text(CapsStackText.resource(.reviewSetupChoices))
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
            SettingsHeader(title: CapsStackText.resolve(.notifications), message: CapsStackText.resolve(.notificationsDescription))

            HStack(spacing: 16) {
                Image(systemName: "bell.fill")
                    .frame(width: 34, height: 34)
                    .background(BrandPalette.BriefTheme.signal.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 4) {
                    Text(CapsStackText.resource(.macOSNotifications)).font(.headline)
                    Text(authorizationMessage)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if controller.isNotificationAuthorized == true {
                    Label(CapsStackText.resource(.allowed), systemImage: "checkmark.circle.fill")
                        .foregroundStyle(BrandPalette.BriefTheme.signal)
                } else if controller.isNotificationAuthorized == false {
                    Button(CapsStackText.resource(.openSystemSettings)) {
                        controller.openNotificationSettings()
                    }
                } else {
                    Button(CapsStackText.resource(.requestPermission)) {
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
        case true: CapsStackText.resolve(.notificationsAllowedDescription)
        case false: CapsStackText.resolve(.notificationsDeniedDescription)
        case nil: CapsStackText.resolve(.checkingPermission)
        }
    }
}

private struct HotkeySettingsView: View {
    private let shortcuts: [(name: String, shortcut: String)] = [
        (CapsStackText.resolve(.openHistory), "⌘O"),
        (CapsStackText.resolve(.openAwayMemo), "⇧⌘M"),
        (CapsStackText.resolve(.openSettings), "⌘,"),
        (CapsStackText.resolve(.quitCapsStack), "⌘Q")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsHeader(title: CapsStackText.resolve(.keyboardShortcuts), message: CapsStackText.resolve(.shortcutsAvailable))

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
                title: CapsStackText.resolve(.dataManagement),
                message: CapsStackText.resolve(.historyOnlyThisMac)
            )

            dataRow(
                title: CapsStackText.resolve(.historyFolder),
                subtitle: controller.historyDirectoryURL.path,
                buttonTitle: CapsStackText.resolve(.show),
                action: controller.revealHistoryFolder
            )

            dataRow(
                title: CapsStackText.resolve(.copyHistoryPath),
                subtitle: CapsStackText.resolve(.copyFolderLocation),
                buttonTitle: CapsStackText.resolve(.copy),
                action: copyPath
            )

            dataRow(
                title: CapsStackText.resolve(.deleteAllHistory),
                subtitle: CapsStackText.resolve(.deleteHistoryDescription),
                buttonTitle: CapsStackText.resolve(.delete),
                destructive: true,
                action: { showsClearConfirmation = true }
            )

            dataRow(
                title: CapsStackText.resolve(.deleteAwayMemo),
                subtitle: CapsStackText.resolve(.clearAwayMemoDescription),
                buttonTitle: CapsStackText.resolve(.delete),
                destructive: true,
                action: {
                    controller.clearQuickMemo()
                    message = CapsStackText.resolve(.awayMemoDeleted)
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
        message = CapsStackText.resolve(.pathCopied)
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
            SettingsHeader(title: CapsStackText.resolve(.advanced), message: CapsStackText.resolve(.advancedDescription))

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
                        Label(CapsStackText.resource(.cancel), systemImage: "xmark")
                    } else {
                        Text(CapsStackText.resource(.test))
                    }
                }
                .disabled(controller.testingProvider != nil && controller.testingProvider != kind)
                .accessibilityLabel(
                    controller.testingProvider == kind
                        ? CapsStackText.format(.cancelConnectionTest, kind.displayName)
                        : CapsStackText.format(.testConnection, kind.displayName)
                )

                Button(CapsStackText.resource(isExpanded ? .close : .details)) {
                    withAnimation(.easeOut(duration: 0.18)) { isExpanded.toggle() }
                }
                .buttonStyle(.borderless)
            }

            if isExpanded {
                Divider()
                TextField(CapsStackText.resolve(.executablePath), text: $path)
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
        guard let status = controller.cliStatuses[kind] else { return CapsStackText.resolve(.checking) }
        if status.isInstalled {
            return status.version ?? status.executablePath ?? CapsStackText.resolve(.detected)
        }
        return CapsStackText.resolve(.notDetected)
    }

    private func testMessageColor(_ message: String) -> Color {
        if message == CapsStackText.resolve(.success) {
            return BrandPalette.BriefTheme.signal
        }
        if message == CapsStackText.resolve(.checking) || message == CapsStackText.resolve(.cancelled) {
            return .secondary
        }
        return .red
    }
}
