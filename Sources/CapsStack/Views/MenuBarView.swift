import AppKit
import SwiftUI

/// The contents deliberately use only native menu controls. Keeping this view free of
/// custom backgrounds, hover handling, and fixed sizing lets `MenuBarExtraStyle.menu`
/// render a standard, lightweight macOS menu.
struct MenuBarView: View {
    @ObservedObject var controller: AppController
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @AppStorage(PreferenceKeys.quickMemo) private var quickMemoText = ""

    private var statusActionTitle: String {
        controller.phase == .away ? "今すぐ復帰" : "退席を開始"
    }

    private var quickMemoTitle: String {
        QuickMemoPreferences(text: quickMemoText).trimmedText == nil
            ? "退席前メモ..."
            : "退席前メモを編集..."
    }

    private var notice: String? {
        if !controller.isCapsStackEnabled {
            return "設定でCapsStackを有効にしてください"
        }
        if controller.phase == .failed {
            return "履歴から詳細を確認できます"
        }
        return nil
    }

    var body: some View {
        Label {
            Text(controller.stateTitle)
        } icon: {
            Image(systemName: controller.phase.menuSystemImage)
        }
        .accessibilityLabel("CapsStackの状態: \(controller.stateTitle)")

        if let notice {
            Text(notice)
                .foregroundStyle(.secondary)
        }

        Divider()

        Button(statusActionTitle) {
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

        Button(quickMemoTitle) {
            activateAndOpenWindow(id: "quick-memo")
        }
        .disabled(!controller.isCapsStackEnabled || controller.phase == .summarizing)

        Divider()

        Button("履歴を開く") {
            activateAndOpenWindow(id: "history")
        }
        .keyboardShortcut("o", modifiers: [.command])

        Button("設定...") {
            NSApp.activate(ignoringOtherApps: true)
            openSettings()
        }
        .keyboardShortcut(",", modifiers: [.command])

        Divider()

        Button("CapsStackを終了") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: [.command])
    }

    private func activateAndOpenWindow(id: String) {
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: id)
    }
}

private extension AppPhase {
    var menuSystemImage: String {
        switch self {
        case .idle: "circle"
        case .away: "circle.fill"
        case .summarizing: "ellipsis.circle"
        case .failed: "exclamationmark.triangle"
        case .disabled: "pause.circle"
        }
    }
}
