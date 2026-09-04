import Foundation
import CapsStackLocalization
import XCTest
@testable import CapsStackCLI

final class HistoryAndFormattingTests: XCTestCase {
    func testHistoryLoadsExistingSchemaNewestFirst() throws {
        let fixture = try Fixture(entries: [makeEntry(offset: 0), makeEntry(offset: 120)])
        defer { fixture.remove() }

        let entries = try fixture.repository.load()
        XCTAssertEqual(entries.map(\.id), [fixture.entries[1].id, fixture.entries[0].id])
        XCTAssertEqual(entries.last?.quickMemo, "次はテスト")
    }

    func testHistoryDecodesLegacyEntryWithoutQuickMemo() throws {
        let entry = makeEntry(offset: 0)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(entry)) as? [String: Any])
        object.removeValue(forKey: "quickMemo")
        let fixture = try Fixture(rawData: try JSONSerialization.data(withJSONObject: [object]))
        defer { fixture.remove() }

        XCTAssertNil(try fixture.repository.latest().quickMemo)
    }

    func testJSONIsStableAndMachineReadable() throws {
        let entry = makeEntry(offset: 0)
        let first = try CLIFormatting.json(entry)
        let second = try CLIFormatting.json(entry)
        XCTAssertEqual(first, second)
        XCTAssertNoThrow(try JSONSerialization.jsonObject(with: Data(first.utf8)))
        XCTAssertLessThan(try XCTUnwrap(first.range(of: "\"fallbackUsed\"")?.lowerBound),
                          try XCTUnwrap(first.range(of: "\"id\"")?.lowerBound))
    }

    func testMarkdownMatchesAppSectionMeaning() {
        let markdown = CLIFormatting.markdown(makeEntry(offset: 0), locale: Locale(identifier: "en"))
        XCTAssertTrue(markdown.contains("# CapsStack Summary"))
        XCTAssertTrue(markdown.contains("## Progress"))
        XCTAssertTrue(markdown.contains("## Current state"))
        XCTAssertTrue(markdown.contains("## Decisions"))
        XCTAssertTrue(markdown.contains("## Blockers"))
        XCTAssertTrue(markdown.contains("## Next steps"))
        XCTAssertTrue(markdown.contains("**Sources**: Codex"))
        XCTAssertTrue(markdown.contains("**Summarizer CLI**: Codex CLI"))
        XCTAssertTrue(markdown.contains("**Codex — s1**"))
        XCTAssertTrue(markdown.contains("Away memo"))
    }

    func testApplicationListLimitAndMissingEntryFailure() throws {
        let fixture = try Fixture(entries: [makeEntry(offset: 0), makeEntry(offset: 120)])
        defer { fixture.remove() }
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "CapsStackCLI.History.\(UUID())"))
        let app = CapsStackCLIApplication(
            history: fixture.repository,
            memo: CLIMemoStore(defaults: defaults, domainName: nil),
            environment: [:],
            version: "test",
            locale: Locale(identifier: "en")
        )

        let list = app.run(arguments: ["history", "list", "--limit", "1", "--json"])
        XCTAssertEqual(list.exitCode, 0)
        XCTAssertTrue(list.stderr.isEmpty)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(list.stdout.utf8)) as? [[String: Any]])
        XCTAssertEqual(json.count, 1)

        let missing = app.run(arguments: ["history", "show", UUID().uuidString, "--json"])
        XCTAssertEqual(missing.exitCode, 1)
        XCTAssertTrue(missing.stdout.isEmpty)
        XCTAssertTrue(missing.stderr.hasPrefix("error:"))
    }
}

private struct Fixture {
    let directory: URL
    let entries: [CLIHistoryEntry]
    let repository: CLIHistoryRepository

    init(entries: [CLIHistoryEntry]) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try self.init(rawData: encoder.encode(entries), entries: entries)
    }

    init(rawData: Data, entries: [CLIHistoryEntry] = []) throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("CapsStackCLI.\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("history.json")
        try rawData.write(to: url)
        self.entries = entries
        repository = CLIHistoryRepository(historyURL: url)
    }

    func remove() { try? FileManager.default.removeItem(at: directory) }
}

private func makeEntry(offset: TimeInterval) -> CLIHistoryEntry {
    let start = Date(timeIntervalSince1970: 1_700_000_000 + offset)
    return CLIHistoryEntry(
        id: UUID(),
        interval: CLIAwayInterval(start: start, end: start.addingTimeInterval(65)),
        status: .completed,
        summary: CLISummaryDocument(
            overview: "CLIを実装しました。",
            progress: ["履歴を読み取り"],
            currentState: ["テスト中"],
            decisions: ["Foundationのみを使用"],
            blockers: ["なし"],
            nextSteps: ["回帰テスト"],
            sessions: [CLISessionSummary(sessionID: "s1", source: "Codex", summary: "実装")]
        ),
        provider: .codex,
        fallbackUsed: false,
        sessionCount: 1,
        sources: [.codex],
        collectionIssues: [],
        errorMessage: nil,
        pendingArtifactID: nil,
        quickMemo: "次はテスト"
    )
}
