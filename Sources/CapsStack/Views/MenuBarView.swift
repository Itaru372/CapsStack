import AppKit
import SwiftUI

struct MenuBarView: View {
    @ObservedObject var controller: AppController
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @AppStorage(PreferenceKeys.quickMemo) private var quickMemoText = ""

    private var statusActionTitle: String {
        controller.phase == .away ? "今すぐ復帰" : "退席を開始"
    }

    private var notice: String? {
        if !controller.isCapsStackEnabled {
            return "設定でCapsStackを有効にすると再開します"
        }
        if controller.phase == .failed {
            return controller.lastError ?? "履歴から再要約できます"
        }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            statusBarHeader

            if let notice {
                Text(notice)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 6)
            }

            MenuBarDivider()

            MenuBarRow(title: statusActionTitle) {
                if controller.phase == .away {
                    controller.endAwayManually()
                } else if controller.phase != .summarizing {
                    controller.beginAwayManually()
                }
            }
            .disabled(
                !controller.isCapsStackEnabled
                    || controller.phase == .summarizing
                    || controller.phase == .disabled
            )

            quickMemoField

            MenuBarDivider()

            MenuBarRow(title: "履歴を開く", shortcut: "⌘O") {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "history")
            }

            MenuBarRow(title: "設定...", shortcut: "⌘,") {
                openSettings()
            }

            MenuBarDivider()

            MenuBarRow(title: "CapsStackを終了", shortcut: "⌘Q") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(.vertical, 5)
        .frame(width: 300)
        .background(BrandPalette.BriefTheme.panel)
        .preferredColorScheme(.dark)
    }

    private var statusBarHeader: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(controller.phase.brandColor)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)

            Text(controller.stateTitle)
                .foregroundStyle(.primary)

            Spacer(minLength: 12)

            if controller.phase == .away, let start = controller.awayStartedAt {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(DurationFormatter.string(from: context.date.timeIntervalSince(start)))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        }
        .font(.system(size: 13))
        .padding(.horizontal, 14)
        .frame(height: 26)
        .accessibilityElement(children: .combine)
    }

    private var quickMemoField: some View {
        TextField("退席前メモ...", text: $quickMemoText)
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .padding(.horizontal, 14)
            .frame(height: 24)
            .disabled(
                !controller.isCapsStackEnabled || controller.phase == .summarizing
            )
    }
}

private struct MenuBarDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.12))
            .frame(height: 1)
            .padding(.vertical, 3)
    }
}

private struct MenuBarRow: View {
    let title: String
    var shortcut: String?
    let action: () -> Void

    @State private var isHovered = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let isHighlighted = isHovered && isEnabled

        Button(action: action) {
            HStack(spacing: 0) {
                Text(title)

                Spacer(minLength: 16)

                if let shortcut {
                    Text(shortcut)
                        .monospacedDigit()
                        .foregroundStyle(
                            isHighlighted ? Color.white.opacity(0.8) : Color.secondary
                        )
                }
            }
            .font(.system(size: 13))
            .foregroundStyle(isHighlighted ? Color.white : Color.primary)
            .padding(.horizontal, 14)
            .frame(height: 24)
            .contentShape(Rectangle())
            .background {
                if isHighlighted {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.accentColor.opacity(0.9))
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .opacity(isEnabled ? 1 : 0.45)
    }
}
