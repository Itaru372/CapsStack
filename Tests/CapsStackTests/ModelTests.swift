import XCTest
@testable import CapsStack

final class ModelTests: XCTestCase {
    func testBrandAssetsArePackaged() {
        XCTAssertNotNil(BrandAssets.nsImage(named: "CapsStackAppIcon"))
        XCTAssertNotNil(BrandAssets.nsImage(named: "CapsStackMenuBar"))
    }

    func testCollectorAndSummarizerPreferencesAreIndependent() throws {
        let suiteName = "CapsStackTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(false, forKey: PreferenceKeys.collectCodex)
        defaults.set(true, forKey: PreferenceKeys.collectClaude)
        defaults.set(CLIKind.codex.rawValue, forKey: PreferenceKeys.primarySummarizer)
        defaults.set("gpt-test", forKey: PreferenceKeys.codexModel)
        defaults.set("high", forKey: PreferenceKeys.codexReasoning)

        let collectors = CollectorPreferences(defaults: defaults)
        let summarizer = SummarizerPreferences(defaults: defaults)

        XCTAssertEqual(collectors.enabledSources, [.claudeCode])
        XCTAssertEqual(summarizer.primary, .codex)
        XCTAssertEqual(summarizer.modelOverride(for: .codex), "gpt-test")
        XCTAssertEqual(summarizer.reasoningOverride(for: .codex), "high")
        XCTAssertNil(summarizer.modelOverride(for: .pi))
    }

    func testSummaryDocumentRoundTripsAsJSON() throws {
        let document = SummaryDocument(
            overview: "認証フローを整理しました。",
            progress: ["API接続を完了"],
            currentState: ["テスト中"],
            decisions: ["Keychainを使用"],
            blockers: [],
            nextSteps: ["回帰テスト"],
            sessions: [
                SessionSummary(sessionID: "session-1", source: "Codex CLI", summary: "実装を進行")
            ]
        )

        let data = try JSONEncoder().encode(document)
        XCTAssertEqual(try JSONDecoder().decode(SummaryDocument.self, from: data), document)
    }

    func testDurationFormatterUsesClockStyle() {
        XCTAssertEqual(DurationFormatter.string(from: 65), "01:05")
        XCTAssertEqual(DurationFormatter.string(from: 3_661), "1:01:01")
        XCTAssertEqual(DurationFormatter.string(from: -4), "00:00")
    }
}
