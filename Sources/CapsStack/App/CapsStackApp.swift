import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // CapsStack is intentionally a menu-bar-only utility. History and settings
        // still open as normal windows on demand. Background execution is kept alive
        // so Caps Lock monitoring continues even when no window is visible.
        NSApp.setActivationPolicy(.accessory)
        if let icon = BrandAssets.nsImage(named: "CapsStackAppIcon") {
            NSApp.applicationIconImage = icon
        }
        // Prevent App Nap / automatic termination while monitoring in background.
        // The per-controller ProcessInfo activity handles the actual keep-alive,
        // but disabling sudden termination here avoids the system killing the
        // menu-bar helper during idle periods.
        ProcessInfo.processInfo.disableSuddenTermination()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Keep running in background even when history/settings windows are closed.
        false
    }
}

@main
struct CapsStackApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var controller = AppController()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(controller: controller)
                .task { controller.start() }
        } label: {
            BrandMenuBarIcon(indicatorColor: controller.phase.menuBarIndicatorColor)
                .accessibilityLabel("CapsStack — \(controller.stateTitle)")
        }
        .menuBarExtraStyle(.window)

        Window("CapsStack 履歴", id: "history") {
            HistoryView(controller: controller)
                .task { controller.start() }
                .tint(BrandPalette.petrolSlate)
        }
        .defaultSize(width: 820, height: 560)

        Settings {
            SettingsView(controller: controller)
                .tint(BrandPalette.petrolSlate)
                .task {
                    controller.start()
                    await controller.refreshCLIStatuses()
                }
        }
    }
}
