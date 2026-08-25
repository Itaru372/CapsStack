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

            ScrollView {
                detail
                    .padding(26)
                    .frame(maxWidth: 780, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
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

    @AppStorage(PreferenceKeys.keepRunningInBackground) private var keepRunningInBackground = true

    @ViewBuilder
    private var detail: some View {
        switch selectedSection {
        case .collectors:
            CollectorSettingsView(controller: controller, searchText: searchText)
        case .summarizers:
            SummarizerSettingsView(controller: controller)
        case .general:
            GeneralSettingsView(controller: controller, launchAtLogin: launchAtLogin)
        case .notifications:
            NotificationSettingsView(controller: controller)
        case .hotkeys:
            HotkeySettingsView()
        case .data:
            DataManagementSettingsView(
                controller: controller,
                showsClearConfirmation: $showsClearHistoryConfirmation
            )
        case .advanced:
            AdvancedSummarizerSettingsView(controller: controller)
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
        case .collectors: "Codex Claude OpenCode Pi 収集 ログ 接続"
        case .summarizers: "要約 CLI モデル fallback フォールバック signal"
        case .general: "Caps Lock 起動 常駐 アクセシビリティ 退席"
        case .notifications: "許可 通知 alert サウンド"
        case .hotkeys: "ショートカット command 履歴 設定 終了"
        case .data: "履歴 削除 バックアップ フォルダ メモ"
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
    @AppStorage(PreferenceKeys.collectCodex) private var collectCodex = true
    @AppStorage(PreferenceKeys.collectClaude) private var collectClaude = true
    @AppStorage(PreferenceKeys.collectOpenCode) private var collectOpenCode = false
    @AppStorage(PreferenceKeys.collectPi) private var collectPi = false

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsHeader(
                title: "収集元",
                message: "退席中にアクティビティを収集するツールを選択します。"
            )

            VStack(spacing: 10) {
                collectorRow(kind: .codex, isOn: $collectCodex)
                collectorRow(kind: .claudeCode, isOn: $collectClaude)
                collectorRow(kind: .opencode, isOn: $collectOpenCode)
                collectorRow(kind: .pi, isOn: $collectPi)
            }

            if ![collectCodex, collectClaude, collectOpenCode, collectPi].contains(true) {
                Label("収集元が選択されていません", systemImage: "exclamationmark.triangle")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(Color.orange)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(BrandPalette.BriefTheme.card, in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private func matches(_ kind: CLIKind) -> Bool {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || kind.displayName.localizedCaseInsensitiveContains(searchText)
    }

    @ViewBuilder
    private func collectorRow(kind: CLIKind, isOn: Binding<Bool>) -> some View {
        if matches(kind) {
            HStack(spacing: 14) {
                Image(systemName: kind.systemImage)
                    .font(.system(size: 16))
                    .frame(width: 34, height: 34)
                    .background(BrandPalette.BriefTheme.signal.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 4) {
                    Text(kind.displayName)
                        .font(.headline)
                    statusText(for: kind)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                Toggle("", isOn: isOn)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
            .padding(16)
            .background(BrandPalette.BriefTheme.card, in: RoundedRectangle(cornerRadius: 11))
            .overlay(BrandPalette.BriefTheme.border, in: RoundedRectangle(cornerRadius: 11))
        }
    }

    @ViewBuilder
    private func statusText(for kind: CLIKind) -> some View {
        if let status = controller.cliStatuses[kind] {
            Text(status.canReadLogs ? "\(status.logDirectory) ・ 接続中" : "\(status.logDirectory) ・ 読み取れません")
        } else {
            Text("確認中...")
        }
    }
}

private struct SummarizerSettingsView: View {
    @ObservedObject var controller: AppController
    @AppStorage(PreferenceKeys.primarySummarizer) private var primaryRaw = CLIKind.codex.rawValue
    @AppStorage(PreferenceKeys.automaticFallback) private var automaticFallback = true

    var body: some View {
        Form {
            Section("復帰ブリーフの生成") {
                Picker("担当CLI", selection: $primaryRaw) {
                    ForEach(CLIKind.allCases) { kind in
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

                Toggle("失敗時に別のCLIへ切り替える", isOn: $automaticFallback)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }
}

private struct GeneralSettingsView: View {
    @ObservedObject var controller: AppController
    @ObservedObject var launchAtLogin: LaunchAtLoginService
    @AppStorage(PreferenceKeys.capsStackEnabled) private var capsStackEnabled = true
    @AppStorage(PreferenceKeys.keepRunningInBackground) private var keepRunningInBackground = true
    @AppStorage(PreferenceKeys.suppressOriginalCapsLock) private var suppressOriginalCapsLock = false
    @AppStorage(PreferenceKeys.minimumAwayDuration) private var minimumAwaySeconds = 0

    var body: some View {
        Form {
            Section("CapsStack") {
                Toggle("CapsStack機能を有効にする", isOn: $capsStackEnabled)
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
            SettingsHeader(title: "データ管理", message: "履歴と退席前メモはこのMac上でのみ管理されます。")

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
    @AppStorage(PreferenceKeys.codexModel) private var codexModel = ""
    @AppStorage(PreferenceKeys.claudeModel) private var claudeModel = ""
    @AppStorage(PreferenceKeys.opencodeModel) private var opencodeModel = ""
    @AppStorage(PreferenceKeys.piModel) private var piModel = ""
    @AppStorage(PreferenceKeys.codexReasoning) private var codexReasoning = ""
    @AppStorage(PreferenceKeys.claudeReasoning) private var claudeReasoning = ""
    @AppStorage(PreferenceKeys.opencodeReasoning) private var opencodeReasoning = ""
    @AppStorage(PreferenceKeys.piReasoning) private var piReasoning = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                SettingsHeader(title: "詳細設定", message: "各CLIの実行ファイル、モデル、推論強度を指定できます。")

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
            }
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
                Image(systemName: kind.systemImage)
                    .frame(width: 32, height: 32)
                    .background(BrandPalette.BriefTheme.signal.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 3) {
                    Text(kind.displayName).font(.headline)
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Button("テスト") {
                    Task { await controller.testProvider(kind) }
                }
                .disabled(controller.testingProvider == kind)

                Button(isExpanded ? "閉じる" : "詳細") {
                    withAnimation(.easeOut(duration: 0.18)) { isExpanded.toggle() }
                }
                .buttonStyle(.borderless)
            }

            if isExpanded {
                Divider()
                TextField("実行ファイル（空欄なら自動検出）", text: $path)
                    .textFieldStyle(.roundedBorder)
                TextField(kind.modelHint, text: $model)
                    .textFieldStyle(.roundedBorder)
                TextField("Reasoning: \(kind.reasoningHint)", text: $reasoning)
                    .textFieldStyle(.roundedBorder)

                if let testMessage = controller.providerTestMessages[kind] {
                    Text(testMessage)
                        .font(.caption)
                        .foregroundStyle(testMessage.hasPrefix("成功") ? BrandPalette.BriefTheme.signal : Color.red)
                }
            }
        }
        .padding(16)
        .background(BrandPalette.BriefTheme.card, in: RoundedRectangle(cornerRadius: 11))
        .overlay(BrandPalette.BriefTheme.border, in: RoundedRectangle(cornerRadius: 11))
        .onChange(of: path) { _, _ in
            Task { await controller.refreshCLIStatuses() }
        }
    }

    private var statusText: String {
        guard let status = controller.cliStatuses[kind] else { return "確認中..." }
        if status.isInstalled {
            return status.version ?? status.executablePath ?? "検出済み"
        }
        return "未検出"
    }
}
