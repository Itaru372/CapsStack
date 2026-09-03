import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // The approved design uses a regular macOS window plus the native menu bar,
        // while MenuBarExtra keeps away/return controls available system-wide.
        NSApp.setActivationPolicy(.regular)
        // Keep the Dock icon sourced from the bundle's AppIcon.icns. Replacing it with
        // the in-app PNG here makes macOS visibly switch icon sources after launch.
        // A freshly built bundle can otherwise open behind an older CapsStack instance (or
        // another app), making the user interact with a stale-looking window.
        NSApp.activate(ignoringOtherApps: true)
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
    @AppStorage(PreferenceKeys.setupCompleted) private var setupCompleted = false

    var body: some Scene {
        WindowGroup("CapsStack History", id: "history") {
            Group {
                if setupCompleted {
                    HistoryView(controller: controller)
                        .transition(.opacity)
                } else {
                    SetupView(controller: controller, isCompleted: $setupCompleted)
                        .transition(.opacity)
                }
            }
                .animation(.easeInOut(duration: 0.2), value: setupCompleted)
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

        Window("Away Memo", id: "quick-memo") {
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
        CommandMenu("History") {
            Button("Open History") {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "history")
            }
            .keyboardShortcut("o")

            Divider()

            Button("Reload") {
                controller.reloadHistory()
            }
            .keyboardShortcut("r", modifiers: [.command])
        }

        CommandMenu("Settings") {
            Button("Away Memo…") {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "quick-memo")
            }
            .keyboardShortcut("m", modifiers: [.command, .shift])

            Divider()

            Button("Settings…") {
                NSApp.activate(ignoringOtherApps: true)
                openSettings()
            }
        }
    }
}
