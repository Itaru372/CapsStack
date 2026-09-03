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
                TextField("設定を検索...", text: $searchText)
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
            "すべての履歴と再試行データを削除しますか？",
            isPresented: $showsClearHistoryConfirmation,
            titleVisibility: .visible
        ) {
            Button("すべて削除", role: .destructive) {
                controller.clearAllHistory()
            }
            Button("キャンセル", role: .cancel) {}
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
        case .collectors: "収集元"
        case .summarizers: "要約担当"
        case .general: "一般"
        case .notifications: "通知"
        case .hotkeys: "ホットキー"
        case .data: "データ管理"
        case .advanced: "詳細設定"
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
        case .collectors: "Codex Claude OpenCode Pi GitHub Copilot Kilo Goose Qwen Continue Gemini 収集 ログ 接続"
        case .summarizers: "要約 CLI モデル fallback フォールバック signal"
        case .general: "Caps Lock 起動 常駐 アクセシビリティ 退席"
        case .notifications: "許可 通知 alert サウンド"
        case .hotkeys: "ショートカット command 履歴 設定 終了"
        case .data: "履歴 削除 バックアップ フォルダ メモ プライバシー"
        case .advanced: "実行ファイル パス reasoning effort variant thinking"
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
                title: "収集元",
                message: "退席中に収集するエージェントを選択します。対応するCLI・Desktop・IDEの履歴をまとめて扱います。"
            )

            VStack(spacing: 10) {
                ForEach(primaryCollectorKinds) { kind in
                    collectorRow(kind: kind, isOn: binding(for: kind))
                }

                if !unavailableCollectorKinds.isEmpty {
                    DisclosureGroup("未検出のエージェント（\(unavailableCollectorKinds.count)）", isExpanded: $showsUnavailableCollectors) {
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
                Label("収集元が選択されていません", systemImage: "exclamationmark.triangle")
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
            .accessibilityLabel("\(kind.collectionDisplayName)の収集")
            .accessibilityValue(isOn.wrappedValue ? "オン" : "オフ")
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
            Text("確認中...")
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
    @State private var showsUnavailableSummarizers = false

    var body: some View {
        Form {
            Section("復帰ブリーフの生成") {
                Picker("担当CLI", selection: $primaryRaw) {
                    ForEach(displayedSummarizerKinds) { kind in
                        HStack {
                            Label(kind.displayName, systemImage: kind.systemImage)
                            if kind == .codex {
                                Text("推奨")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(BrandPalette.BriefTheme.signal)
                            }
                        }
                        .tag(kind.rawValue)
                    }
                }
                .pickerStyle(.radioGroup)

                if !unavailableSummarizerKinds.isEmpty {
                    Button(showsUnavailableSummarizers ? "未検出のCLIを隠す" : "未検出のCLIも表示") {
                        showsUnavailableSummarizers.toggle()
                    }
                    .buttonStyle(.link)
                }

                if let selectedKind, controller.cliStatuses[selectedKind]?.isInstalled == false {
                    Label("選択中のCLIは未検出です。実行ファイルを詳細設定で指定できます。", systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(Color.orange)
                }

                if displayedSummarizerKinds.isEmpty {
                    Label("利用可能な要約CLIがありません。Codex、Claude Code、OpenCode、Piのいずれかをインストールするか、詳細設定で実行ファイルを指定してください。", systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(Color.orange)
                }

                if let selectedKind {
                    ModelSelectionControl(
                        kind: selectedKind,
                        model: modelBinding(for: selectedKind),
                        controller: controller
                    )
                }

                Toggle("失敗時に別のCLIへ切り替える", isOn: $automaticFallback)
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
}

private struct ModelSelectionControl: View {
    let kind: CLIKind
    @Binding var model: String
    @ObservedObject var controller: AppController

    var body: some View {
        if kind.supportsModelListing {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Picker("モデル", selection: $model) {
                        Text("CLIの既定値")
                            .tag("")

                        if let currentModel, !controller.models(for: kind).contains(where: { $0.id == currentModel }) {
                            Text("現在の設定: \(currentModel)")
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
                    .accessibilityLabel("\(kind.displayName)のモデル")

                    Button {
                        Task { await controller.refreshCLIModels(for: kind) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .disabled(controller.modelFetchState(for: kind) == .loading)
                    .accessibilityLabel("\(kind.displayName)のモデル一覧を再取得")
                }

                catalogStatus
            }
            .task(id: kind) {
                await controller.refreshCLIModels(for: kind)
            }
        } else {
            TextField(kind.modelHint, text: $model)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("\(kind.displayName)のモデル")
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
            Text("モデル一覧を取得できます。")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .loading:
            Label("モデル一覧を取得中...", systemImage: "arrow.triangle.2.circlepath")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .loaded:
            if controller.models(for: kind).isEmpty {
                Text("利用可能なモデルが返されませんでした。CLIの既定値を使用します。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("\(controller.models(for: kind).count)個のモデルを取得済み")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .failed:
            Label(
                controller.cliModelErrors[kind] ?? "モデル一覧を取得できませんでした。CLIの既定値を使用できます。",
                systemImage: "exclamationmark.triangle"
            )
            .font(.caption)
            .foregroundStyle(Color.orange)
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
                Toggle("CapsStack機能を有効にする", isOn: Binding(
                    get: { capsStackEnabled },
                    set: { newValue in
                        capsStackEnabled = newValue
                        controller.setCapsStackEnabled(newValue)
                    }
                ))
                Stepper("最短退席時間: \(minimumAwaySeconds)秒", value: $minimumAwaySeconds, in: 0...3600, step: 5)
            }

            Section("Caps Lock") {
                Toggle("本来のCaps Lock入力を無効化", isOn: $suppressOriginalCapsLock)

                if suppressOriginalCapsLock {
                    if controller.isSuppressingOriginalCapsLock {
                        Label("有効", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(BrandPalette.BriefTheme.signal)
                    } else {
                        Label("アクセシビリティ権限が必要です", systemImage: "lock.shield")
                            .foregroundStyle(Color.orange)
                        Button("システム設定を開く") {
                            controller.openAccessibilitySettings()
                        }
                    }
                }
            }

            Section("常駐") {
                Toggle("バックグラウンドで常に実行", isOn: Binding(
                    get: { keepRunningInBackground },
                    set: { newValue in
                        keepRunningInBackground = newValue
                        controller.setKeepRunningInBackground(newValue)
                    }
                ))
                Toggle("ログイン時に起動", isOn: Binding(
                    get: { launchAtLogin.isEnabled },
                    set: { launchAtLogin.setEnabled($0) }
                ))

                if let error = launchAtLogin.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(Color.orange)
                }
            }

            Section("セットアップ") {
                Button("セットアップを開く…") {
                    setupCompleted = false
                    openWindow(id: "history")
                }
                Text("収集元、要約担当、匿名テレメトリの選択を見直せます。")
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
            SettingsHeader(title: "通知", message: "復帰時の要約結果をmacOS通知で受け取ります。")

            HStack(spacing: 16) {
                Image(systemName: "bell.fill")
                    .frame(width: 34, height: 34)
                    .background(BrandPalette.BriefTheme.signal.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 4) {
                    Text("macOS通知").font(.headline)
                    Text(authorizationMessage)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if controller.isNotificationAuthorized == true {
                    Label("許可済み", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(BrandPalette.BriefTheme.signal)
                } else if controller.isNotificationAuthorized == false {
                    Button("システム設定を開く") {
                        controller.openNotificationSettings()
                    }
                } else {
                    Button("許可を要求") {
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
        case true: "要約完了と失敗を通知できます。"
        case false: "システム設定でCapsStackの通知を許可してください。"
        case nil: "許可状態を確認しています..."
        }
    }
}

private struct HotkeySettingsView: View {
    private let shortcuts: [(name: String, shortcut: String)] = [
        ("履歴を開く", "⌘O"),
        ("退席前メモを開く", "⇧⌘M"),
        ("設定を開く", "⌘,"),
        ("CapsStackを終了", "⌘Q")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsHeader(title: "ホットキー", message: "アプリがアクティブなときに使えるショートカットです。")

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
                title: "データ管理",
                message: "履歴と退席前メモはこのMac上でのみ管理されます。"
            )

            dataRow(
                title: "履歴フォルダ",
                subtitle: controller.historyDirectoryURL.path,
                buttonTitle: "表示",
                action: controller.revealHistoryFolder
            )

            dataRow(
                title: "履歴をコピー",
                subtitle: "フォルダの場所をクリップボードに保存します。",
                buttonTitle: "コピー",
                action: copyPath
            )

            dataRow(
                title: "すべての履歴を削除",
                subtitle: "要約履歴と失敗時の再試行データを削除します。",
                buttonTitle: "削除",
                destructive: true,
                action: { showsClearConfirmation = true }
            )

            dataRow(
                title: "退席前メモを削除",
                subtitle: "保存中の次回メモを空にします。",
                buttonTitle: "削除",
                destructive: true,
                action: {
                    controller.clearQuickMemo()
                    message = "退席前メモを削除しました"
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
        message = "パスをコピーしました"
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
            SettingsHeader(title: "詳細設定", message: "各CLIの実行ファイル、モデル、推論強度を指定できます。対応CLIはモデル一覧から選択できます。")

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
                        Label("キャンセル", systemImage: "xmark")
                    } else {
                        Text("テスト")
                    }
                }
                .disabled(controller.testingProvider != nil && controller.testingProvider != kind)
                .accessibilityLabel(
                    controller.testingProvider == kind
                        ? "\(kind.displayName)の接続テストをキャンセル"
                        : "\(kind.displayName)の接続テスト"
                )

                Button(isExpanded ? "閉じる" : "詳細") {
                    withAnimation(.easeOut(duration: 0.18)) { isExpanded.toggle() }
                }
                .buttonStyle(.borderless)
            }

            if isExpanded {
                Divider()
                TextField("実行ファイル（空欄なら自動検出）", text: $path)
                    .textFieldStyle(.roundedBorder)
                ModelSelectionControl(
                    kind: kind,
                    model: $model,
                    controller: controller
                )
                if kind.supportsReasoningOverride {
                    TextField("Reasoning: \(kind.reasoningHint)", text: $reasoning)
                        .textFieldStyle(.roundedBorder)
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
        guard let status = controller.cliStatuses[kind] else { return "確認中..." }
        if status.isInstalled {
            return status.version ?? status.executablePath ?? "検出済み"
        }
        return "未検出"
    }

    private func testMessageColor(_ message: String) -> Color {
        switch message {
        case "成功": BrandPalette.BriefTheme.signal
        case "確認中...", "キャンセルしました": .secondary
        default: .red
        }
    }
}
