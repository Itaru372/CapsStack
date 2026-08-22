import AppKit
import SwiftUI

struct MenuBarView: View {
    @ObservedObject var controller: AppController
    @Environment(\.openWindow) private var openWindow

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
                            .foregroundStyle(BrandPalette.inkAubergine)
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
                    .foregroundStyle(BrandPalette.inkAubergine)
                }

                Label("検出セッション \(controller.activeSessionCount)件", systemImage: "terminal")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            Button {
                if controller.phase == .away {
                    controller.endAwayManually()
                } else if controller.phase != .summarizing {
                    controller.beginAwayManually()
                }
            } label: {
                Label(
                    controller.isCapsStackEnabled
                        ? (controller.phase == .away ? "今すぐ復帰扱い" : "退席を開始")
                        : "一時停止中のため無効",
                    systemImage: controller.phase == .away ? "person.crop.circle.badge.checkmark" : "figure.walk.departure"
                )
                .frame(maxWidth: .infinity)
            }
            .disabled(!controller.isCapsStackEnabled || controller.phase == .summarizing || controller.phase == .disabled)
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(primaryActionColor)

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
    }

    private var primaryActionColor: Color {
        controller.phase == .away ? BrandPalette.petrolSlate : BrandPalette.agedBrass
    }
}
