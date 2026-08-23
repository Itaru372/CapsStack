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
        let historyStore = HistoryStore(directoryURL: historyDirectory)
        try makeSampleEntry(in: historyStore)

        let controller = AppController(
            defaults: defaults,
            historyStore: historyStore,
            notifications: SilentNotificationService()
        )
        controller.reloadHistory()

        let menuBar = try render(
            MenuBarView(controller: controller)
                .frame(width: 316, height: 340, alignment: .top)
                .background(BrandPalette.BriefTheme.panel),
            size: CGSize(width: 316, height: 340)
        )
        let settings = try render(
            SettingsView(controller: controller)
                .frame(width: 980, height: 680)
                .background(BrandPalette.BriefTheme.canvas),
            size: CGSize(width: 980, height: 680)
        )
        let history = try render(
            HistoryView(controller: controller)
                .frame(width: 1120, height: 740)
                .background(BrandPalette.BriefTheme.canvas),
            size: CGSize(width: 1120, height: 740)
        )

        XCTAssertEqual(menuBar.size, CGSize(width: 316, height: 340))
        XCTAssertEqual(settings.size, CGSize(width: 980, height: 680))
        XCTAssertEqual(history.size, CGSize(width: 1120, height: 740))

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

    private func makeSampleEntry(in store: HistoryStore) throws {
        let start = Calendar.current.date(byAdding: .day, value: -1, to: .now) ?? .now
        let end = start.addingTimeInterval(8_322)
        let summary = SummaryDocument(
            overview: "退席中の4セッションを整理しました。",
            progress: ["ユーザー認証フローにパスキー認証を追加", "チーム招待APIの権限チェックを実装"],
            currentState: ["CIは安定しています"],
            decisions: ["招待リンクの有効期限は7日間とする"],
            blockers: ["リカバリーフローのレビュー待ち"],
            nextSteps: ["招待メールの文面をレビュー", "リカバリーフローを実装する"],
            sessions: []
        )
        let session = CollectedSessionArtifact(
            id: "qa-session",
            provider: .codex,
            workingDirectory: nil,
            events: [CollectedEvent(timestamp: start, kind: "message", content: "sample")],
            wasTruncated: false
        )
        _ = try store.saveCompleted(
            batch: CollectionBatch(
                interval: AwayInterval(start: start, end: end),
                sessions: [session],
                issues: [],
                quickMemo: "GUIエージェントの補足メモ"
            ),
            outcome: SummaryOutcome(document: summary, provider: .codex, fallbackUsed: false)
        )
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
