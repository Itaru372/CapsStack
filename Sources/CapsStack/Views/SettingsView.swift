import SwiftUI

struct SettingsView: View {
    @ObservedObject var controller: AppController
    @StateObject private var launchAtLogin = LaunchAtLoginService()

    var body: some View {
        TabView {
            GeneralSettingsView(controller: controller, launchAtLogin: launchAtLogin)
                .tabItem { Label("一般", systemImage: "gearshape") }

            CollectorSettingsView(controller: controller)
                .tabItem { Label("収集", systemImage: "tray.and.arrow.down") }

            SummarizerSettingsView(controller: controller)
                .tabItem { Label("要約", systemImage: "text.quote") }
        }
        .frame(width: 640, height: 560)
        .scenePadding()
        .tint(BrandPalette.petrolSlate)
    }
}

private struct GeneralSettingsView: View {
    @ObservedObject var controller: AppController
    @ObservedObject var launchAtLogin: LaunchAtLoginService
    @AppStorage(PreferenceKeys.capsStackEnabled) private var capsStackEnabled = true
    @AppStorage(PreferenceKeys.keepRunningInBackground) private var keepRunningInBackground = true
    @AppStorage(PreferenceKeys.suppressOriginalCapsLock) private var suppressOriginalCapsLock = false

    var body: some View {
        Form {
            Section("CapsStack") {
                Toggle("CapsStack機能を有効にする", isOn: $capsStackEnabled)

                Text(capsStackEnabled
                     ? "オンの間だけCaps Lockの退席検知と要約が動作します。オフにするとバックグラウンド常駐は維持したまま、監視と収集だけを一時停止します。"
                     : "現在CapsStackは一時停止中です。オンに戻すとCaps Lock監視が再開します。")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                if !capsStackEnabled {
                    Label("CapsStackは一時停止中です", systemImage: "pause.circle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Caps Lock") {
                Toggle("本来のCaps Lock入力を無効化", isOn: $suppressOriginalCapsLock)

                Text("オンにすると、Caps Lockを押しても大文字固定になりません。Caps LockはCapsStackの退席トリガー専用になり、通常の文字入力に影響しなくなります。")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                if suppressOriginalCapsLock {
                    if controller.isSuppressingOriginalCapsLock {
                        Label("有効 — 大文字変換は無効化されています", systemImage: "checkmark.circle.fill")
                            .font(.callout)
                            .foregroundStyle(Color.secondary)
                    } else {
                        Label("有効化を試みましたが、権限が必要です", systemImage: "exclamationmark.triangle")
                            .font(.callout)
                            .foregroundStyle(BrandPalette.agedBrass)
                    }
                } else {
                    Label("無効 — 通常の大文字変換が有効です", systemImage: "a.circle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                if let error = controller.capsLockSuppressionError {
                    Label(error, systemImage: "exclamationmark.circle")
                        .font(.callout)
                        .foregroundStyle(BrandPalette.agedBrass)
                    Button("アクセシビリティ設定を開く") {
                        controller.openAccessibilitySettings()
                    }
                    .buttonStyle(.link)
                } else if suppressOriginalCapsLock && !controller.isSuppressingOriginalCapsLock {
                    Text("システム設定 > プライバシーとセキュリティ > アクセシビリティ で CapsStack を許可すると有効になります。許可後に一度オフ→オンしてください。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Button("アクセシビリティ設定を開く") {
                        controller.openAccessibilitySettings()
                    }
                    .buttonStyle(.link)
                }

                Text("この機能は入力監視の権限が必要です。無効のままなら従来どおりCaps Lockの大文字変換が動作しますが、CapsStackの退席検知は引き続き利用できます。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("バックグラウンド実行") {
                Toggle(
                    "バックグラウンドで常に実行",
                    isOn: Binding(
                        get: { keepRunningInBackground },
                        set: { newValue in
                            keepRunningInBackground = newValue
                            // keepRunningInBackground ONならログイン時起動もONにして常駐を保証する
                            launchAtLogin.setEnabled(newValue)
                        }
                    )
                )

                Text("オンにすると、アプリを閉じてもメニューバーに常駐し、スリープ復帰後も自動で監視を再開します。ログイン時に自動起動する設定も連動して有効になります。")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Toggle(
                    "Macへのログイン時にCapsStackを起動",
                    isOn: Binding(
                        get: { launchAtLogin.isEnabled },
                        set: { launchAtLogin.setEnabled($0) }
                    )
                )

                Text("有効にすると、MacへログインしたときにCapsStackが自動で起動してメニューバーに常駐します。")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                if let errorMessage = launchAtLogin.errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(BrandPalette.agedBrass)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            launchAtLogin.refresh()
            // 初回起動や「常に実行」ON時にログイン項目を自動で有効化
            if keepRunningInBackground, !launchAtLogin.isEnabled {
                launchAtLogin.setEnabled(true)
            }
        }
        .onChange(of: keepRunningInBackground) { _, newValue in
            if newValue, !launchAtLogin.isEnabled {
                launchAtLogin.setEnabled(true)
            }
        }
        .onChange(of: suppressOriginalCapsLock) { _, newValue in
            controller.setSuppressOriginalCapsLock(newValue)
        }
    }
}

private struct CollectorSettingsView: View {
    @ObservedObject var controller: AppController
    @AppStorage(PreferenceKeys.collectCodex) private var collectCodex = true
    @AppStorage(PreferenceKeys.collectClaude) private var collectClaude = true
    @AppStorage(PreferenceKeys.collectOpenCode) private var collectOpenCode = false
    @AppStorage(PreferenceKeys.collectPi) private var collectPi = false

    var body: some View {
        Form {
            Section {
                Text("退席中の記録を読むCLIを複数選択できます。要約担当の設定とは独立しています。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("収集元") {
                Toggle(isOn: $collectCodex) {
                    collectorLabel(for: .codex)
                }
                Toggle(isOn: $collectClaude) {
                    collectorLabel(for: .claudeCode)
                }
                Toggle(isOn: $collectOpenCode) {
                    collectorLabel(for: .opencode)
                }
                Toggle(isOn: $collectPi) {
                    collectorLabel(for: .pi)
                }
            }

            if !collectCodex && !collectClaude && !collectOpenCode && !collectPi {
                Label("収集元が選択されていません", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(BrandPalette.agedBrass)
            }
        }
        .formStyle(.grouped)
    }

    private func collectorLabel(for kind: CLIKind) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(kind.displayName, systemImage: kind.systemImage)
            CLIStatusCaption(status: controller.cliStatuses[kind], collectorOnly: true)
        }
    }
}

private struct SummarizerSettingsView: View {
    @ObservedObject var controller: AppController
    @AppStorage(PreferenceKeys.primarySummarizer) private var primaryRaw = CLIKind.codex.rawValue
    @AppStorage(PreferenceKeys.automaticFallback) private var automaticFallback = true
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
        Form {
            Section {
                Text("収集元に選んでいないCLIも要約担当にできます。元のセッションは再開しません。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("主な要約担当") {
                Picker("要約CLI", selection: $primaryRaw) {
                    ForEach(CLIKind.allCases) { kind in
                        Label(kind.displayName, systemImage: kind.systemImage)
                            .tag(kind.rawValue)
                    }
                }
                .pickerStyle(.radioGroup)

                Toggle("失敗時に別のCLIへ切り替える", isOn: $automaticFallback)
            }

            Section("実行ファイル・モデル・Reasoning") {
                executableRow(
                    kind: .codex,
                    path: $codexPath,
                    model: $codexModel,
                    reasoning: $codexReasoning
                )
                executableRow(
                    kind: .claudeCode,
                    path: $claudePath,
                    model: $claudeModel,
                    reasoning: $claudeReasoning
                )
                executableRow(
                    kind: .opencode,
                    path: $opencodePath,
                    model: $opencodeModel,
                    reasoning: $opencodeReasoning
                )
                executableRow(
                    kind: .pi,
                    path: $piPath,
                    model: $piModel,
                    reasoning: $piReasoning
                )
            }
        }
        .formStyle(.grouped)
        .onChange(of: codexPath) { _, _ in Task { await controller.refreshCLIStatuses() } }
        .onChange(of: claudePath) { _, _ in Task { await controller.refreshCLIStatuses() } }
        .onChange(of: opencodePath) { _, _ in Task { await controller.refreshCLIStatuses() } }
        .onChange(of: piPath) { _, _ in Task { await controller.refreshCLIStatuses() } }
    }

    private func executableRow(
        kind: CLIKind,
        path: Binding<String>,
        model: Binding<String>,
        reasoning: Binding<String>
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(kind.displayName)
                    .frame(width: 130, alignment: .leading)
                TextField("自動検出（必要なら絶対パスを指定）", text: path)
                    .textFieldStyle(.roundedBorder)
                Button("テスト") {
                    Task { await controller.testProvider(kind) }
                }
                .disabled(controller.testingProvider == kind)
            }
            TextField("モデル: (kind.modelHint)", text: model)
                .textFieldStyle(.roundedBorder)
            TextField("Reasoning: \(kind.reasoningHint)", text: reasoning)
                .textFieldStyle(.roundedBorder)
            HStack(spacing: 8) {
                CLIStatusCaption(status: controller.cliStatuses[kind], collectorOnly: false)
                if let message = controller.providerTestMessages[kind] {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(message.hasPrefix("成功") ? BrandPalette.petrolSlate : Color.red)
                }
            }
        }
    }
}

private struct CLIStatusCaption: View {
    let status: CLIStatus?
    let collectorOnly: Bool

    var body: some View {
        Group {
            if let status {
                if collectorOnly {
                    Label(
                        status.canReadLogs ? "ログを読み取り可能" : "ログ保存先を読み取れません",
                        systemImage: status.canReadLogs ? "checkmark.circle.fill" : "exclamationmark.circle"
                    )
                    .foregroundStyle(status.canReadLogs ? Color.secondary : BrandPalette.agedBrass)
                } else if status.isInstalled {
                    Label(status.version ?? status.executablePath ?? "検出済み", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Label("未検出", systemImage: "xmark.circle")
                        .foregroundStyle(BrandPalette.agedBrass)
                }
            } else {
                Label("確認中…", systemImage: "ellipsis.circle")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption)
    }
}
