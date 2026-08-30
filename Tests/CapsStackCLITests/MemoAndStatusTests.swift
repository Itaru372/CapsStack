import Foundation
import XCTest
@testable import CapsStackCLI

final class MemoAndStatusTests: XCTestCase {
    func testMemoStoreUsesInjectedDefaultsAndTrimsValues() throws {
        let suite = "CapsStackCLI.Memo.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = CLIMemoStore(defaults: defaults, domainName: nil)

        store.set("  GUIの確認中\n")
        XCTAssertEqual(store.get(), "GUIの確認中")
        store.set(" \n\t ")
        XCTAssertNil(store.get())
    }

    func testProductionStyleMemoStoreUsesCapsStackPersistentDomain() throws {
        let defaultsSuite = "CapsStackCLI.DomainHost.\(UUID())"
        let domain = "CapsStackCLI.AppDomain.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsSuite))
        defer {
            defaults.removePersistentDomain(forName: defaultsSuite)
            defaults.removePersistentDomain(forName: domain)
        }
        let store = CLIMemoStore(defaults: defaults, domainName: domain)
        store.set("domain memo")
        XCTAssertEqual(defaults.persistentDomain(forName: domain)?[CLIMemoStore.key] as? String, "domain memo")
        XCTAssertEqual(store.get(), "domain memo")
        store.clear()
        XCTAssertNil(defaults.persistentDomain(forName: domain)?[CLIMemoStore.key])
    }

    func testMemoApplicationReadsStdinAndJSONNeverUsesStderr() throws {
        let suite = "CapsStackCLI.Stdin.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = CLIMemoStore(defaults: defaults, domainName: nil)
        let app = CapsStackCLIApplication(
            history: CLIHistoryRepository(historyURL: URL(fileURLWithPath: "/nonexistent/history.json")),
            memo: store,
            environment: [:],
            version: "test",
            readStandardInput: { "  stdin memo\n" }
        )

        let result = app.run(arguments: ["memo", "set", "--stdin", "--json"])
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.isEmpty)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(result.stdout.utf8)) as? [String: Any])
        XCTAssertEqual(object["memo"] as? String, "stdin memo")
        XCTAssertEqual(object["hasMemo"] as? Bool, true)
    }

    func testStatusFindsAllSupportedExecutableNamesOnPATH() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("CapsStackCLI.PATH.\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        for name in ["codex", "claude", "opencode", "opencode2", "pi", "copilot", "kilo", "goose", "qwen", "cn", "gemini"] {
            let url = directory.appendingPathComponent(name)
            XCTAssertTrue(FileManager.default.createFile(atPath: url.path, contents: Data()))
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        }
        let suite = "CapsStackCLI.Status.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let repository = CLIHistoryRepository(historyURL: directory.appendingPathComponent("missing-history.json"))

        let report = try CLIStatusService.report(
            history: repository,
            memo: CLIMemoStore(defaults: defaults, domainName: nil),
            path: directory.path
        )
        XCTAssertFalse(report.historyExists)
        XCTAssertEqual(report.historyCount, 0)
        XCTAssertEqual(
            report.agents.map(\.executable),
            ["codex", "claude", "opencode", "opencode2", "pi", "copilot", "kilo", "goose", "qwen", "cn", "gemini"]
        )
        XCTAssertTrue(report.agents.allSatisfy(\.isAvailable))
    }
}
