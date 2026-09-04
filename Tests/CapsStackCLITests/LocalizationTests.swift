import CapsStackLocalization
import Foundation
import XCTest
@testable import CapsStackCLI

final class LocalizationTests: XCTestCase {
    private let english = Locale(identifier: "en")
    private let japanese = Locale(identifier: "ja-JP")

    func testSharedTextUsesTheRequestedDisplayLanguage() {
        XCTAssertEqual(CapsStackText.resolve(.history, locale: english), "History")
        XCTAssertEqual(CapsStackText.resolve(.history, locale: japanese), "履歴")
        XCTAssertEqual(
            CapsStackText.format(.notificationSubtitle, "進捗", 2, locale: japanese),
            "進捗 / セッション2件"
        )
        XCTAssertEqual(
            CapsStackText.format(.projectSessionsAccessibility, "Project", 2, locale: japanese),
            "Project、2セッション"
        )
    }

    func testCLIFormattingPreservesEnglishAndProvidesJapanese() {
        let entry = CLIHistoryEntry(
            id: UUID(),
            interval: CLIAwayInterval(
                start: Date(timeIntervalSince1970: 1_700_000_000),
                end: Date(timeIntervalSince1970: 1_700_000_125)
            ),
            status: .completed,
            summary: CLISummaryDocument(
                overview: "概要",
                progress: ["進捗"],
                currentState: ["状態"],
                decisions: ["決定"],
                blockers: ["問題"],
                nextSteps: ["次の手順"],
                sessions: [
                    CLISessionSummary(sessionID: "s1", source: "Codex", summary: "セッション概要")
                ]
            ),
            provider: .codex,
            fallbackUsed: false,
            sessionCount: 1,
            sources: [.codex],
            collectionIssues: [],
            errorMessage: nil,
            pendingArtifactID: nil,
            quickMemo: "メモ"
        )

        let englishMarkdown = CLIFormatting.markdown(entry, locale: english)
        XCTAssertTrue(englishMarkdown.contains("# CapsStack Summary"))
        XCTAssertTrue(englishMarkdown.contains("## Progress"))
        XCTAssertTrue(englishMarkdown.contains("**Sources**: Codex"))

        let japaneseMarkdown = CLIFormatting.markdown(entry, locale: japanese)
        XCTAssertTrue(japaneseMarkdown.contains("# CapsStack 要約"))
        XCTAssertTrue(japaneseMarkdown.contains("## 進捗"))
        XCTAssertTrue(japaneseMarkdown.contains("**収集元**: Codex"))
        XCTAssertTrue(japaneseMarkdown.contains("**所要時間**: 02:05"))
    }
}
