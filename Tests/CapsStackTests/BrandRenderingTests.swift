import AppKit
import SwiftUI
import XCTest
@testable import CapsStack

@MainActor
final class BrandRenderingTests: XCTestCase {
    func testBrandedSurfacesRender() throws {
        let suiteName = "CapsStackBrandRenderingTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.set(false, forKey: PreferenceKeys.capsStackEnabled)
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

        let quickMemo = try render(
            QuickMemoView()
                .defaultAppStorage(defaults)
                .frame(width: 468, height: 330),
            size: CGSize(width: 468, height: 330)
        )
        let settings = try render(
            SettingsView(controller: controller)
                .frame(width: 980, height: 680)
                .background(BrandPalette.BriefTheme.canvas),
            size: CGSize(width: 980, height: 680)
        )
        let setup = try render(
            SetupView(controller: controller, isCompleted: .constant(false))
                .frame(width: 1120, height: 740),
            size: CGSize(width: 1120, height: 740)
        )
        let history = try render(
            HistoryView(controller: controller)
                .frame(width: 1120, height: 740)
                .background(BrandPalette.BriefTheme.canvas),
            size: CGSize(width: 1120, height: 740)
        )

        XCTAssertEqual(quickMemo.size, CGSize(width: 468, height: 330))
        XCTAssertEqual(settings.size, CGSize(width: 980, height: 680))
        XCTAssertEqual(setup.size, CGSize(width: 1120, height: 740))
        XCTAssertEqual(history.size, CGSize(width: 1120, height: 740))

        if let outputPath = ProcessInfo.processInfo.environment["CAPSSTACK_QA_OUTPUT"] {
            let outputDirectory = URL(fileURLWithPath: outputPath, isDirectory: true)
            try FileManager.default.createDirectory(
                at: outputDirectory,
                withIntermediateDirectories: true
            )
            try writePNG(quickMemo, to: outputDirectory.appendingPathComponent("quick-memo.png"))
            try writePNG(settings, to: outputDirectory.appendingPathComponent("settings.png"))
            try writePNG(setup, to: outputDirectory.appendingPathComponent("setup.png"))
            try writePNG(history, to: outputDirectory.appendingPathComponent("history.png"))
        }
    }

    func testAllPagesInBothAppearances() async throws {
        let suite = "CapsStackVisualQA.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.set(false, forKey: PreferenceKeys.capsStackEnabled)
        defer { defaults.removePersistentDomain(forName: suite) }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = HistoryStore(directoryURL: directory)
        try makeSampleEntry(in: store)
        let controller = AppController(defaults: defaults, resolver: VisualQAResolver(),
                                       historyStore: store, notifications: SilentNotificationService())
        controller.reloadHistory()
        await controller.refreshCLIStatuses()
        let output = ProcessInfo.processInfo.environment["CAPSSTACK_QA_OUTPUT"].map {
            URL(fileURLWithPath: $0, isDirectory: true)
        }
        if let output { try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true) }
        for scheme in [ColorScheme.light, .dark] {
            let suffix = scheme == .light ? "light" : "dark"
            var pages: [(String, AnyView, CGSize)] = []
            for section in SettingsSection.allCases {
                pages.append(("settings-\(section.rawValue)", AnyView(SettingsView(controller: controller, initialSection: section)), CGSize(width: 980, height: 680)))
            }
            for step in SetupStep.allCases {
                pages.append(("setup-\(step.rawValue + 1)", AnyView(SetupView(controller: controller, isCompleted: .constant(false), initialStep: step)), CGSize(width: 1120, height: 740)))
            }
            pages.append(("history", AnyView(HistoryView(controller: controller)), CGSize(width: 1120, height: 740)))
            pages.append(("memo", AnyView(QuickMemoView()), CGSize(width: 468, height: 330)))
            pages.append(("about", AnyView(AboutView()), CGSize(width: 420, height: 410)))
            for (name, page, size) in pages {
                let snapshot = try render(page.defaultAppStorage(defaults).environment(\.colorScheme, scheme)
                    .frame(width: size.width, height: size.height), size: size)
                XCTAssertEqual(snapshot.size, size, name)
                if let output { try writePNG(snapshot, to: output.appendingPathComponent("\(name)-\(suffix).png")) }
            }
        }
    }

    func testCompactHistoryRecoveryStatesRender() throws {
        let suite = "CapsStackRecoveryQA.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.set(false, forKey: PreferenceKeys.capsStackEnabled)
        defer { defaults.removePersistentDomain(forName: suite) }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = HistoryStore(directoryURL: directory)
        let controller = AppController(defaults: defaults, resolver: VisualQAResolver(), historyStore: store,
                                       notifications: SilentNotificationService())
        let output = ProcessInfo.processInfo.environment["CAPSSTACK_QA_OUTPUT"].map { URL(fileURLWithPath: $0) }
        for name in ["no-history", "empty", "pending"] {
            if name != "no-history" {
                let entry = HistoryEntry(interval: AwayInterval(start: .now.addingTimeInterval(-600), end: .now),
                                         status: name == "empty" ? .empty : .pending,
                                         sessionCount: name == "empty" ? 0 : 2, sources: [.codex],
                                         errorMessage: name == "pending" ? String(repeating: "CLI diagnostic line\n", count: 100) : nil,
                                         pendingArtifactID: name == "pending" ? UUID() : nil)
                try store.save(entry)
            }
            controller.reloadHistory()
            let size = CGSize(width: 940, height: 600)
            let snapshot = try render(HistoryView(controller: controller).defaultAppStorage(defaults)
                .environment(\.colorScheme, .light).frame(width: size.width, height: size.height), size: size)
            XCTAssertEqual(snapshot.size, size)
            if let output { try writePNG(snapshot, to: output.appendingPathComponent("history-\(name)-compact.png")) }
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
            overview: "退席中のセッションを整理しました。",
            progress: ["ユーザー認証フローにパスキー認証を追加", "チーム招待APIの権限チェックを実装"],
            currentState: ["CIは安定しています"],
            decisions: ["招待リンクの有効期限は7日間とする"],
            blockers: ["リカバリーフローのレビュー待ち"],
            nextSteps: ["招待メールの文面をレビュー", "リカバリーフローを実装する"],
            sessions: [],
            projects: [ProjectSummary(
                projectID: "project-1",
                name: "CapsStack",
                summary: "認証と招待フローの実装が進みました。",
                sessions: [SessionSummary(
                    sessionID: "codex:qa-session",
                    source: "Codex CLI",
                    summary: "パスキー認証と権限チェックを実装しました。"
                )]
            )]
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

private final class SilentNotificationService: NotificationServicing, @unchecked Sendable {
    func requestAuthorization() async -> Bool { false }

    func notify(
        outcome: SummaryOutcome,
        interval: AwayInterval,
        sessionCount: Int
    ) async {}

    func notifyFailure(message: String, interval: AwayInterval?) async {}
}

private struct VisualQAResolver: CLIResolving {
    func executableURL(for kind: CLIKind, override: String?) -> URL? { nil }
    func logDirectory(for kind: CLIKind) -> URL { URL(fileURLWithPath: "/tmp/capsstack-visual-fixture") }
    func status(for kind: CLIKind, override: String?) -> CLIStatus {
        let installed = [.codex, .claudeCode, .opencode].contains(kind)
        return CLIStatus(kind: kind, executablePath: installed ? "/fixture/\(kind.rawValue)" : nil,
                         version: installed ? "CLI" : nil, logDirectory: logDirectory(for: kind).path,
                         canReadLogs: installed)
    }
}
