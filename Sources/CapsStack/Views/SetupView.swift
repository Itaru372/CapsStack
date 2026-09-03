import SwiftUI

struct SetupView: View {
    @ObservedObject var controller: AppController
    @Binding var isCompleted: Bool

    @Environment(\.openSettings) private var openSettings
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
    @AppStorage(PreferenceKeys.primarySummarizer) private var primarySummarizer = ""
    @State private var currentStep: SetupStep = .collectors

    var body: some View {
        HStack(spacing: 0) {
            introduction

            VStack(alignment: .leading, spacing: 24) {
                setupHeader

                currentStepContent
                    .id(currentStep)
                    .transition(.opacity.combined(with: .move(edge: .trailing)))

                Spacer(minLength: 20)
                footer
            }
            .padding(36)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .animation(.easeInOut(duration: 0.2), value: currentStep)
        }
        .background(BrandPalette.BriefTheme.canvas.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .tint(BrandPalette.BriefTheme.signal)
        .task {
            await controller.refreshCLIStatuses()
            normalizeSelections()
        }
        .onChange(of: controller.cliStatuses) { _, _ in
            normalizeSelections()
        }
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 24) {
            BrandAppIcon(size: 58)

            VStack(alignment: .leading, spacing: 10) {
                Text("戻った瞬間、\n次の一手がわかる。")
                    .font(.system(size: 32, weight: .bold, design: .serif))
                    .fixedSize(horizontal: false, vertical: true)

                Text("Caps Lockを退席スイッチにして、ローカルの作業履歴から復帰ブリーフを作ります。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 16) {
                ForEach(SetupStep.allCases) { step in
                    setupPoint(for: step)
                }
            }

            Spacer(minLength: 24)

            Label("セッション本文とメモは、このMac上の処理にだけ使われます。", systemImage: "lock.shield")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(36)
        .frame(width: 340, alignment: .leading)
        .background(BrandPalette.BriefTheme.panel.ignoresSafeArea(edges: .vertical))
    }

    private var setupHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("セットアップ")
                .font(.system(size: 28, weight: .bold, design: .serif))
            Text("ステップ \(currentStep.rawValue + 1) / \(SetupStep.allCases.count) ・ \(currentStep.title)")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var currentStepContent: some View {
        switch currentStep {
        case .collectors:
            collectorsSection
        case .summarizer:
            summarizerSection
        case .telemetry:
            telemetrySection
        case .usage:
            usageSection
        }
    }

    private var collectorsSection: some View {
        SetupSection(number: 1, title: "作業履歴の収集元") {
            if detectedCollectors.isEmpty {
                unavailableMessage("対応エージェントや読み取り可能な履歴はまだ見つかりません。退席前メモだけでも利用できます。")
            } else {
                VStack(spacing: 8) {
                    ForEach(detectedCollectors) { kind in
                        Toggle(isOn: collectorBinding(for: kind)) {
                            HStack(spacing: 12) {
                                AgentArtwork(kind: kind, size: 28)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(kind.collectionDisplayName)
                                        .font(.headline)
                                    Text(collectorStatus(for: kind))
                                        .font(.caption)
                                        .foregroundStyle(collectorStatusColor(for: kind))
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                            }
                        }
                        .toggleStyle(.switch)
                        .disabled(cannotEnableCollector(kind))
                        .accessibilityLabel("\(kind.collectionDisplayName)の収集")
                        .accessibilityValue(isCollectorEnabled(kind) ? "オン" : "オフ")
                        .padding(.horizontal, 14)
                        .frame(height: 64)
                        .frame(maxWidth: .infinity)
                        .background(BrandPalette.BriefTheme.card, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(BrandPalette.BriefTheme.border, in: RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
        }
    }

    private var summarizerSection: some View {
        SetupSection(number: 2, title: "復帰ブリーフの要約担当") {
            if availableSummarizers.isEmpty {
                unavailableMessage("要約に使えるCLIが見つかりません。インストール後に再確認するか、実行ファイルを設定してください。")
            } else {
                VStack(spacing: 8) {
                    ForEach(availableSummarizers) { kind in
                        Button {
                            primarySummarizer = kind.rawValue
                        } label: {
                            HStack(spacing: 9) {
                                Image(systemName: kind.systemImage)
                                Text(kind.displayName)
                                    .lineLimit(1)
                                Spacer(minLength: 4)
                                Image(systemName: primarySummarizer == kind.rawValue ? "checkmark.circle.fill" : "circle")
                            }
                            .foregroundStyle(primarySummarizer == kind.rawValue ? BrandPalette.BriefTheme.signal : .primary)
                            .padding(.horizontal, 14)
                            .frame(maxWidth: .infinity, minHeight: 52, maxHeight: 52, alignment: .leading)
                            .background(BrandPalette.BriefTheme.card, in: RoundedRectangle(cornerRadius: 10))
                            .overlay(
                                primarySummarizer == kind.rawValue
                                    ? BrandPalette.BriefTheme.signal.opacity(0.45)
                                    : BrandPalette.BriefTheme.border,
                                in: RoundedRectangle(cornerRadius: 10)
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(primarySummarizer == kind.rawValue ? .isSelected : [])
                    }
                }
            }
        }
    }

    private var telemetrySection: some View {
        SetupSection(number: 3, title: "匿名テレメトリ") {
            VStack(alignment: .leading, spacing: 10) {
                Toggle(
                    "匿名の利用状況を共有する",
                    isOn: Binding(
                        get: { controller.isTelemetryEnabled },
                        set: { controller.setTelemetryEnabled($0) }
                    )
                )
                .toggleStyle(.switch)
                .disabled(!controller.isTelemetryConfigured)

                Text(telemetryDetail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(BrandPalette.BriefTheme.card, in: RoundedRectangle(cornerRadius: 10))
            .overlay(BrandPalette.BriefTheme.border, in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private var usageSection: some View {
        SetupSection(number: 4, title: "使い方") {
            VStack(alignment: .leading, spacing: 10) {
                usageStep(symbol: "capslock.fill", title: "Caps LockをON", detail: "退席区間を開始")
                usageStep(symbol: "cup.and.saucer.fill", title: "作業から離れる", detail: "CLI履歴をローカル収集")
                usageStep(symbol: "text.page.fill", title: "Caps LockをOFF", detail: "復帰ブリーフを生成")
            }
            .frame(maxWidth: .infinity)
            .padding(16)
            .background(BrandPalette.BriefTheme.card, in: RoundedRectangle(cornerRadius: 10))
            .overlay(BrandPalette.BriefTheme.border, in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if currentStep != .collectors {
                Button("戻る") {
                    move(to: currentStep.previous ?? .collectors)
                }
            }

            if currentStep == .collectors || currentStep == .summarizer {
                Button("再確認") {
                    Task { await controller.refreshCLIStatuses() }
                }
            }

            if currentStep == .summarizer && !canCompleteSetup {
                Button("詳細設定を開く") {
                    openSettings()
                }
            }

            Spacer()

            Button(currentStep == .usage ? "CapsStackを始める" : "次へ") {
                if let next = currentStep.next {
                    move(to: next)
                } else {
                    isCompleted = true
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(currentStep == .summarizer && !canCompleteSetup)
            .keyboardShortcut(.defaultAction)
        }
    }

    private var detectedCollectors: [CLIKind] {
        CLIKind.collectorCases.filter { kind in
            controller.cliStatuses[kind].map {
                $0.isInstalled || $0.canReadLogs || $0.isDesktopAppInstalled
            } == true
        }
    }

    private var availableSummarizers: [CLIKind] {
        CLIKind.summarizerCases.filter { controller.cliStatuses[$0]?.isInstalled == true }
    }

    private var canCompleteSetup: Bool {
        availableSummarizers.contains { $0.rawValue == primarySummarizer }
    }

    private var telemetryDetail: String {
        if !controller.isTelemetryConfigured {
            return "このビルドには送信先が設定されていないため、匿名イベントは送信されません。"
        }
        return "復帰ブリーフの成功率や失敗種別などの集計イベントだけを送信します。履歴、メモ、セッション本文、パス、認証情報は送信しません。"
    }

    private func normalizeSelections() {
        if !availableSummarizers.contains(where: { $0.rawValue == primarySummarizer }),
           let first = availableSummarizers.first {
            primarySummarizer = first.rawValue
        }
    }

    private func isCollectorEnabled(_ kind: CLIKind) -> Bool {
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

    private func collectorBinding(for kind: CLIKind) -> Binding<Bool> {
        switch kind {
        case .codex: $collectCodex
        case .claudeCode: $collectClaude
        case .opencode: $collectOpenCode
        case .pi: $collectPi
        case .githubCopilot: $collectGitHubCopilot
        case .kiloCode: $collectKilo
        case .goose: $collectGoose
        case .qwenCode: $collectQwen
        case .continueCLI: $collectContinue
        case .geminiCLI: $collectGemini
        }
    }

    private func collectorStatus(for kind: CLIKind) -> String {
        guard let status = controller.cliStatuses[kind] else { return "確認中…" }
        return status.collectionStatusDescription
    }

    private func cannotEnableCollector(_ kind: CLIKind) -> Bool {
        guard !isCollectorEnabled(kind), let status = controller.cliStatuses[kind] else { return false }
        return !status.canCollect
    }

    private func collectorStatusColor(for kind: CLIKind) -> Color {
        guard let status = controller.cliStatuses[kind], !status.canCollect else { return .secondary }
        return .orange
    }

    private func move(to step: SetupStep) {
        withAnimation(.easeInOut(duration: 0.2)) {
            currentStep = step
        }
    }

    private func setupPoint(for step: SetupStep) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(step.rawValue <= currentStep.rawValue ? BrandPalette.BriefTheme.signal : Color.clear)
                    .overlay(Circle().stroke(BrandPalette.BriefTheme.border))
                if step.rawValue < currentStep.rawValue {
                    Image(systemName: "checkmark")
                        .font(.caption.bold())
                        .foregroundStyle(Color.black)
                } else {
                    Text("\(step.rawValue + 1)")
                        .font(.caption.bold().monospacedDigit())
                        .foregroundStyle(step == currentStep ? Color.black : Color.secondary)
                }
            }
            .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(step.title)
                    .font(.callout.weight(step == currentStep ? .bold : .semibold))
                    .foregroundStyle(step == currentStep ? .primary : .secondary)
                Text(step.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(step == currentStep ? "現在のステップ" : step.rawValue < currentStep.rawValue ? "完了" : "未完了")
    }

    private func usageStep(symbol: String, title: String, detail: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 15))
                .foregroundStyle(BrandPalette.BriefTheme.signal)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func unavailableMessage(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle")
            .font(.callout)
            .foregroundStyle(Color.orange)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(BrandPalette.BriefTheme.card, in: RoundedRectangle(cornerRadius: 10))
    }
}

private enum SetupStep: Int, CaseIterable, Identifiable {
    case collectors
    case summarizer
    case telemetry
    case usage

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .collectors: "収集元を確認"
        case .summarizer: "要約担当を選択"
        case .telemetry: "プライバシーを確認"
        case .usage: "Caps Lockで開始"
        }
    }

    var detail: String {
        switch self {
        case .collectors: "検出したエージェントを自動で選択"
        case .summarizer: "普段使うCLIでブリーフを生成"
        case .telemetry: "匿名テレメトリは初期状態でOFF"
        case .usage: "ONで退席、OFFで復帰"
        }
    }

    var previous: SetupStep? { SetupStep(rawValue: rawValue - 1) }
    var next: SetupStep? { SetupStep(rawValue: rawValue + 1) }
}

private struct SetupSection<Content: View>: View {
    let number: Int
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text("\(number)")
                    .font(.caption.bold().monospacedDigit())
                    .foregroundStyle(Color.black)
                    .frame(width: 24, height: 24)
                    .background(BrandPalette.BriefTheme.signal, in: Circle())
                    .accessibilityHidden(true)
                Text(title)
                    .font(.title3.bold())
            }
            content()
        }
        .accessibilityElement(children: .contain)
    }
}
