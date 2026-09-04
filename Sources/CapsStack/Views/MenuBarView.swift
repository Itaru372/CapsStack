import AppKit
import CapsStackLocalization
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
        CapsStackText.resolve(controller.phase == .away ? .returnNow : .stepAway)
    }

    private var quickMemoTitle: String {
        QuickMemoPreferences(text: quickMemoText).trimmedText == nil
            ? CapsStackText.resolve(.awayMemoEllipsis)
            : CapsStackText.resolve(.editAwayMemoEllipsis)
    }

    private var notice: String? {
        if !controller.isCapsStackEnabled {
            return CapsStackText.resolve(.enableCapsStack)
        }
        if controller.phase == .failed {
            return CapsStackText.resolve(.reviewHistoryDetails)
        }
        return nil
    }

    var body: some View {
        Label {
            Text(controller.stateTitle)
        } icon: {
            Image(systemName: controller.phase.menuSystemImage)
        }
        .accessibilityLabel(CapsStackText.format(.capsStackStatus, controller.stateTitle))

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

        Button(CapsStackText.resource(.openHistory)) {
            activateAndOpenWindow(id: "history")
        }
        .keyboardShortcut("o", modifiers: [.command])

        Button(CapsStackText.resource(.settingsEllipsis)) {
            NSApp.activate(ignoringOtherApps: true)
            openSettings()
        }
        .keyboardShortcut(",", modifiers: [.command])

        Divider()

        Button(CapsStackText.resource(.quitCapsStack)) {
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
