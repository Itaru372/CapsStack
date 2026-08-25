import Foundation
import XCTest
@testable import CapsStackCLI

final class ArgumentParserTests: XCTestCase {
    func testTopLevelCommandsAndAliases() throws {
        XCTAssertEqual(try CLIArgumentParser.parse([]), .help)
        XCTAssertEqual(try CLIArgumentParser.parse(["--help"]), .help)
        XCTAssertEqual(try CLIArgumentParser.parse(["version"]), .version)
        XCTAssertEqual(try CLIArgumentParser.parse(["--version"]), .version)
        XCTAssertEqual(try CLIArgumentParser.parse(["status", "--json"]), .status(json: true))
    }

    func testHistoryCommands() throws {
        let id = UUID()
        XCTAssertEqual(
            try CLIArgumentParser.parse(["history", "list", "--json", "--limit", "3"]),
            .historyList(limit: 3, json: true)
        )
        XCTAssertEqual(
            try CLIArgumentParser.parse(["history", "latest", "--markdown"]),
            .historyLatest(mode: .markdown)
        )
        XCTAssertEqual(
            try CLIArgumentParser.parse(["history", "show", id.uuidString, "--json"]),
            .historyShow(id: id, mode: .json)
        )
    }

    func testMemoSetJoinsTextAndSupportsStdin() throws {
        XCTAssertEqual(
            try CLIArgumentParser.parse(["memo", "set", "次は", "テスト", "--json"]),
            .memoSet(text: "次は テスト", stdin: false, json: true)
        )
        XCTAssertEqual(
            try CLIArgumentParser.parse(["memo", "set", "--stdin"]),
            .memoSet(text: nil, stdin: true, json: false)
        )
    }

    func testInvalidArgumentsAreRejected() {
        XCTAssertThrowsError(try CLIArgumentParser.parse(["history", "list", "--limit", "0"]))
        XCTAssertThrowsError(try CLIArgumentParser.parse(["history", "latest", "--json", "--markdown"]))
        XCTAssertThrowsError(try CLIArgumentParser.parse(["memo", "set", "text", "--stdin"]))
        XCTAssertThrowsError(try CLIArgumentParser.parse(["unknown"]))
    }
}
