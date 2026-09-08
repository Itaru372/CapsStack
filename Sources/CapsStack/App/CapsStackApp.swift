import AppKit
import CapsStackLocalization
import Darwin
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var instanceLockDescriptor: Int32?
    private var instanceLockURL: URL?
    private var isPrimaryInstance = true

    override init() {
        super.init()
        isPrimaryInstance = acquireInstanceLock()
        if !isPrimaryInstance {
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard isPrimaryInstance else {
            activateExistingApplication()
            NSApp.terminate(nil)
            return
        }

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

    deinit {
        if let instanceLockDescriptor {
            Darwin.close(instanceLockDescriptor)
        }
        if let instanceLockURL {
            try? FileManager.default.removeItem(at: instanceLockURL)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Keep running in background even when history/settings windows are closed.
        false
    }

    private func activateExistingApplication() {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return }
        let currentProcessID = ProcessInfo.processInfo.processIdentifier
        NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier)
            .first(where: { $0.processIdentifier != currentProcessID })?
            .activate(options: [.activateAllWindows])
    }

    /// `NSRunningApplication` can race while two `open -n` launches are registering. An
    /// exclusive lock file closes that gap. A stale PID is removed on the next launch so a
    /// terminated process cannot block the app forever.
    private func acquireInstanceLock() -> Bool {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        let directory = appSupport.appendingPathComponent("CapsStack", isDirectory: true)
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            return true
        }

        let lockURL = directory.appendingPathComponent("instance.lock")
        let descriptor = Darwin.open(lockURL.path, O_CREAT | O_EXCL | O_WRONLY, S_IRUSR | S_IWUSR)
        if descriptor >= 0 {
            let processID = Data("\(ProcessInfo.processInfo.processIdentifier)\n".utf8)
            processID.withUnsafeBytes { bytes in
                _ = Darwin.write(descriptor, bytes.baseAddress, processID.count)
            }
            instanceLockDescriptor = descriptor
            instanceLockURL = lockURL
            return true
        }

        guard errno == EEXIST else { return true }
        if activeInstanceLock(at: lockURL) { return false }
        try? fileManager.removeItem(at: lockURL)

        let retryDescriptor = Darwin.open(lockURL.path, O_CREAT | O_EXCL | O_WRONLY, S_IRUSR | S_IWUSR)
        guard retryDescriptor >= 0 else { return false }
        let processID = Data("\(ProcessInfo.processInfo.processIdentifier)\n".utf8)
        processID.withUnsafeBytes { bytes in
            _ = Darwin.write(retryDescriptor, bytes.baseAddress, processID.count)
        }
        instanceLockDescriptor = retryDescriptor
        instanceLockURL = lockURL
        return true
    }

    private func activeInstanceLock(at lockURL: URL) -> Bool {
        guard let rawProcessID = try? String(contentsOf: lockURL, encoding: .utf8),
              let processID = Int32(rawProcessID.trimmingCharacters(in: .whitespacesAndNewlines)),
              processID > 0 else {
            // The creator writes the PID immediately after the exclusive create. Treat a fresh
            // empty file as active so a simultaneous launch cannot remove the lock in that gap.
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: lockURL.path),
                  let modified = attributes[.modificationDate] as? Date else {
                return true
            }
            return Date().timeIntervalSince(modified) < 5
        }
        if let application = NSRunningApplication(processIdentifier: processID) {
            return application.bundleIdentifier == Bundle.main.bundleIdentifier
        }
        return Darwin.kill(processID, 0) == 0 || errno == EPERM
    }
}

@main
struct CapsStackApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var controller = AppController()
    @AppStorage(PreferenceKeys.setupCompleted) private var setupCompleted = false

    var body: some Scene {
        WindowGroup(CapsStackText.resource(.historyWindow), id: "history") {
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
                .accessibilityLabel(CapsStackText.format(.capsStackStatus, controller.stateTitle))
        }
        .menuBarExtraStyle(.menu)
        .commands {
            CapsStackCommands(controller: controller)
        }

        Window(CapsStackText.resource(.awayMemoWindow), id: "quick-memo") {
            QuickMemoView()
        }
        .windowResizability(.contentSize)

        Window(CapsStackText.resource(.aboutCapsStack), id: "about") {
            AboutView()
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
        CommandGroup(replacing: .appInfo) {
            Button(CapsStackText.resource(.aboutCapsStack)) {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "about")
            }
        }

        CommandMenu(CapsStackText.resource(.history)) {
            Button(CapsStackText.resource(.openHistory)) {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "history")
            }
            .keyboardShortcut("o")

            Divider()

            Button(CapsStackText.resource(.reload)) {
                controller.reloadHistory()
            }
            .keyboardShortcut("r", modifiers: [.command])
        }

        CommandMenu(CapsStackText.resource(.settings)) {
            Button(CapsStackText.resource(.awayMemoEllipsis)) {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "quick-memo")
            }
            .keyboardShortcut("m", modifiers: [.command, .shift])

            Divider()

            Button(CapsStackText.resource(.settingsEllipsis)) {
                NSApp.activate(ignoringOtherApps: true)
                openSettings()
            }
        }
    }
}
