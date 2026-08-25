import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // The approved design uses a regular macOS window plus the native menu bar,
        // while MenuBarExtra keeps away/return controls available system-wide.
        NSApp.setActivationPolicy(.regular)
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
        WindowGroup("CapsStack 履歴", id: "history") {
            HistoryView(controller: controller)
                .task { controller.start() }
        }
        .defaultSize(width: 1120, height: 740)

        MenuBarExtra {
            MenuBarView(controller: controller)
                .task { controller.start() }
        } label: {
            BrandMenuBarIcon(indicatorColor: controller.phase.menuBarIndicatorColor)
                .accessibilityLabel("CapsStack — \(controller.stateTitle)")
        }
        .menuBarExtraStyle(.menu)
        .commands {
            CapsStackCommands(controller: controller)
        }

        Window("退席前メモ", id: "quick-memo") {
            QuickMemoView()
        }
        .windowResizability(.contentSize)

        Settings {
            SettingsView(controller: controller)
                .task {
                    controller.start()
                    await controller.refreshCLIStatuses()
                }
        }
    }
}

private struct CapsStackCommands: Commands {
    let controller: AppController
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandMenu("履歴") {
            Button("履歴を開く") {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "history")
            }
            .keyboardShortcut("o")

            Divider()

            Button("再読み込み") {
                controller.reloadHistory()
            }
            .keyboardShortcut("r", modifiers: [.command])
        }

        CommandMenu("設定") {
            Button("退席前メモ...") {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "quick-memo")
            }
            .keyboardShortcut("m", modifiers: [.command, .shift])

            Divider()

            Button("設定...") {
                NSApp.activate(ignoringOtherApps: true)
                openSettings()
            }
        }
    }
}
