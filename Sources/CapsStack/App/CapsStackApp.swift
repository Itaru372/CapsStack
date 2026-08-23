import AppKit
import SwiftUI

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
        arrangeMainMenu()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        arrangeMainMenu()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Keep running in background even when history/settings windows are closed.
        false
    }

    /// SwiftUI installs command menus after the standard system menus and cannot express
    /// this app's exact Japanese menu ordering. Reorder the already-installed items without
    /// changing their target/action ownership.
    private func arrangeMainMenu() {
        // SwiftUI finishes installing scene commands asynchronously after launch ownership
        // settles. A bounded retry window covers that handoff without polling indefinitely.
        let attempts: [(delay: TimeInterval, allowsEditFallback: Bool)] = [
            (0.15, false),
            (0.45, false),
            (0.80, false),
            (1.20, false),
            (2.00, true),
            (4.00, true)
        ]
        for attempt in attempts {
            DispatchQueue.main.asyncAfter(deadline: .now() + attempt.delay) {
                _ = Self.arrangeInstalledMainMenu(allowsEditFallback: attempt.allowsEditFallback)
            }
        }
    }

    @discardableResult
    private static func arrangeInstalledMainMenu(allowsEditFallback: Bool) -> Bool {
        guard let mainMenu = NSApp.mainMenu else { return false }

        for title in ["File", "ファイル"] {
            if let index = mainMenu.items.firstIndex(where: { $0.title == title }) {
                mainMenu.removeItem(at: index)
            }
        }

        if allowsEditFallback,
           !mainMenu.items.contains(where: { $0.title == "編集" }) {
            let editItem = NSMenuItem(title: "編集", action: nil, keyEquivalent: "")
            editItem.submenu = makeStandardEditMenu()
            mainMenu.addItem(editItem)
        }

        let customTitles = ["履歴", "設定"]
        let customItems = mainMenu.items.filter { customTitles.contains($0.title) }
        for item in customItems {
            mainMenu.removeItem(item)
        }
        for (offset, item) in customItems.enumerated() {
            mainMenu.insertItem(item, at: 1 + offset)
        }

        for (offset, title) in ["履歴", "設定", "編集", "表示"].enumerated() {
            guard let currentIndex = mainMenu.items.firstIndex(where: { $0.title == title }),
                  currentIndex != offset + 1 else { continue }

            guard let item = mainMenu.item(at: currentIndex) else { continue }
            mainMenu.removeItem(at: currentIndex)
            mainMenu.insertItem(item, at: offset + 1)
        }

        moveFirstMenuItem(in: mainMenu, matching: ["ウィンドウ", "ウインドウ"], to: 5)
        moveFirstMenuItem(in: mainMenu, matching: ["ヘルプ"], to: 6)

        let titles = Array(mainMenu.items.map(\.title).dropFirst().prefix(6))
        return [
            ["履歴", "設定", "編集", "表示", "ウィンドウ", "ヘルプ"],
            ["履歴", "設定", "編集", "表示", "ウインドウ", "ヘルプ"]
        ].contains(titles)
    }

    private static func moveFirstMenuItem(
        in mainMenu: NSMenu,
        matching titles: [String],
        to index: Int
    ) {
        guard let currentIndex = mainMenu.items.firstIndex(where: { titles.contains($0.title) }),
              currentIndex != index,
              let item = mainMenu.item(at: currentIndex) else { return }

        mainMenu.removeItem(at: currentIndex)
        mainMenu.insertItem(item, at: index)

    }

    private static func makeStandardEditMenu() -> NSMenu {
        let menu = NSMenu(title: "編集")
        menu.addItem(NSMenuItem(title: "取り消す", action: NSSelectorFromString("undo:"), keyEquivalent: "z"))
        menu.addItem(NSMenuItem(title: "やり直す", action: NSSelectorFromString("redo:"), keyEquivalent: "Z"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "カット", action: NSSelectorFromString("cut:"), keyEquivalent: "x"))
        menu.addItem(NSMenuItem(title: "コピー", action: NSSelectorFromString("copy:"), keyEquivalent: "c"))
        menu.addItem(NSMenuItem(title: "ペースト", action: NSSelectorFromString("paste:"), keyEquivalent: "v"))
        menu.addItem(NSMenuItem(title: "すべてを選択", action: NSSelectorFromString("selectAll:"), keyEquivalent: "a"))
        return menu
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
        .commands {
            CapsStackCommands(controller: controller)
        }

        MenuBarExtra {
            MenuBarView(controller: controller)
                .task { controller.start() }
        } label: {
            BrandMenuBarIcon(indicatorColor: controller.phase.menuBarIndicatorColor)
                .accessibilityLabel("CapsStack — \(controller.stateTitle)")
        }
        .menuBarExtraStyle(.window)

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
            Button("設定...") {
                NSApp.activate(ignoringOtherApps: true)
                openSettings()
            }
        }
    }
}
