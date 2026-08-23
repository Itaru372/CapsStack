import AppKit
import SwiftUI

struct MenuBarView: View {
    @ObservedObject var controller: AppController
    @Environment(\.openWindow) private var openWindow
    @AppStorage(PreferenceKeys.quickMemo) private var quickMemoText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                BrandAppIcon()
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 7) {
                        Circle()
                            .fill(controller.phase.brandColor)
                            .frame(width: 8, height: 8)
                            .accessibilityHidden(true)
                        Text(controller.stateTitle)
                            .font(.headline)
                            .foregroundStyle(.primary)
                    }
                    Text(controller.stateDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
            }

            if !controller.isCapsStackEnabled {
                Label("CapsStackは一時停止中です。設定で有効にしてください。", systemImage: "pause.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            } else if controller.phase == .away, let start = controller.awayStartedAt {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Label(
                        DurationFormatter.string(from: context.date.timeIntervalSince(start)),
                        systemImage: "clock"
                    )
                    .font(.system(.body, design: .rounded).monospacedDigit())
                    .foregroundStyle(BrandPalette.BriefTheme.signal)
                }

                Label("検出セッション \(controller.activeSessionCount)件", systemImage: "terminal")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            if controller.phase != .away && controller.phase != .summarizing && controller.isCapsStackEnabled {
                VStack(alignment: .leading, spacing: 4) {
                    Text("退席前メモ（任意）")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $quickMemoText)
                        .frame(minHeight: 36, maxHeight: 72)
                        .font(.caption)
                        .scrollContentBackground(.hidden)
                        .background(BrandPalette.bone, in: RoundedRectangle(cornerRadius: 6))
                }

                Divider()
            }

                Button {
                if controller.phase == .away {
                    controller.endAwayManually()
                } else if controller.phase != .summarizing {
                    controller.beginAwayManually()
                }
            } label: {
                Label(
                    controller.phase == .away ? "今すぐ復帰" : "退席を開始",
                    systemImage: controller.phase == .away ? "person.crop.circle.badge.checkmark" : "figure.walk.departure"
                )
                .frame(maxWidth: .infinity)
            }
            .disabled(!controller.isCapsStackEnabled || controller.phase == .summarizing || controller.phase == .disabled)
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(BrandPalette.BriefTheme.signal)
            .foregroundStyle(.black)

            Button {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "history")
            } label: {
                Label("履歴を開く", systemImage: "clock.arrow.circlepath")
            }

            SettingsLink {
                Label("設定…", systemImage: "gearshape")
            }

            Divider()

            Button("CapsStackを終了") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding(16)
        .frame(width: 316)
        .background(BrandPalette.BriefTheme.panel)
        .preferredColorScheme(.dark)
    }
}
