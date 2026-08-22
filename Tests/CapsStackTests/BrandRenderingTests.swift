import AppKit
import SwiftUI
import XCTest
@testable import CapsStack

@MainActor
final class BrandRenderingTests: XCTestCase {
    func testBrandedSurfacesRender() throws {
        let suiteName = "CapsStackBrandRenderingTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let historyDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(suiteName, isDirectory: true)
        let controller = AppController(
            defaults: defaults,
            historyStore: HistoryStore(directoryURL: historyDirectory),
            notifications: SilentNotificationService()
        )

        let menuBar = try render(
            MenuBarView(controller: controller)
                .frame(width: 316, height: 300, alignment: .top)
                .background(Color(nsColor: .windowBackgroundColor)),
            size: CGSize(width: 316, height: 300)
        )
        let settings = try render(
            SettingsView(controller: controller)
                .frame(width: 640, height: 560)
                .background(Color(nsColor: .windowBackgroundColor)),
            size: CGSize(width: 640, height: 560)
        )
        let history = try render(
            HistoryView(controller: controller)
                .frame(width: 820, height: 560)
                .background(Color(nsColor: .windowBackgroundColor)),
            size: CGSize(width: 820, height: 560)
        )

        XCTAssertEqual(menuBar.size, CGSize(width: 316, height: 300))
        XCTAssertEqual(settings.size, CGSize(width: 640, height: 560))
        XCTAssertEqual(history.size, CGSize(width: 820, height: 560))

        if let outputPath = ProcessInfo.processInfo.environment["CAPSSTACK_QA_OUTPUT"] {
            let outputDirectory = URL(fileURLWithPath: outputPath, isDirectory: true)
            try FileManager.default.createDirectory(
                at: outputDirectory,
                withIntermediateDirectories: true
            )
            try writePNG(menuBar, to: outputDirectory.appendingPathComponent("menu-bar.png"))
            try writePNG(settings, to: outputDirectory.appendingPathComponent("settings.png"))
            try writePNG(history, to: outputDirectory.appendingPathComponent("history.png"))
        }
    }

    private func render<Content: View>(
        _ content: Content,
        size: CGSize
    ) throws -> NSImage {
        _ = NSApplication.shared
        let hostingView = NSHostingView(rootView: content)
        hostingView.frame = CGRect(origin: .zero, size: size)

        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        hostingView.layoutSubtreeIfNeeded()
        window.displayIfNeeded()

        let representation = try XCTUnwrap(
            hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds)
        )
        hostingView.cacheDisplay(in: hostingView.bounds, to: representation)

        let image = NSImage(size: size)
        image.addRepresentation(representation)
        return image
    }

    private func writePNG(_ image: NSImage, to url: URL) throws {
        let tiffData = try XCTUnwrap(image.tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiffData))
        let pngData = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try pngData.write(to: url, options: .atomic)
    }
}

private final class SilentNotificationService: NotificationServicing {
    func requestAuthorization() async -> Bool { false }

    func notify(
        outcome: SummaryOutcome,
        interval: AwayInterval,
        sessionCount: Int
    ) async {}

    func notifyFailure(message: String, interval: AwayInterval?) async {}
}
