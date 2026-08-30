import Foundation
import XCTest
@testable import CapsStack

final class CLIConfigurationTests: XCTestCase {
    func testFreshInstallWithCodexOnlySelectsCodexWithoutClaudeDependency() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        CLIInitialPreferences.applyIfNeeded(
            defaults: defaults,
            resolver: AvailabilityResolver(installed: [.codex], readableLogs: [.codex])
        )

        XCTAssertEqual(CollectorPreferences(defaults: defaults).enabledSources, [.codex])
        XCTAssertEqual(SummarizerPreferences(defaults: defaults).primary, .codex)
        XCTAssertTrue(defaults.bool(forKey: PreferenceKeys.cliDefaultsInitialized))
    }

    func testFreshInstallWithClaudeOnlySelectsClaudeWithoutCodexDependency() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        CLIInitialPreferences.applyIfNeeded(
            defaults: defaults,
            resolver: AvailabilityResolver(installed: [.claudeCode], readableLogs: [.claudeCode])
        )

        XCTAssertEqual(CollectorPreferences(defaults: defaults).enabledSources, [.claudeCode])
        XCTAssertEqual(SummarizerPreferences(defaults: defaults).primary, .claudeCode)
    }

    func testFreshInstallWithNoCLILeavesCollectorsDisabled() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        CLIInitialPreferences.applyIfNeeded(
            defaults: defaults,
            resolver: AvailabilityResolver(installed: [], readableLogs: [])
        )

        XCTAssertTrue(CollectorPreferences(defaults: defaults).enabledSources.isEmpty)
        XCTAssertEqual(SummarizerPreferences(defaults: defaults).primary, .codex)
    }

    func testInitialDetectionDoesNotOverwriteExplicitChoices() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(false, forKey: PreferenceKeys.collectCodex)
        defaults.set(true, forKey: PreferenceKeys.collectClaude)
        defaults.set(CLIKind.codex.rawValue, forKey: PreferenceKeys.primarySummarizer)

        CLIInitialPreferences.applyIfNeeded(
            defaults: defaults,
            resolver: AvailabilityResolver(installed: [.claudeCode], readableLogs: [.claudeCode])
        )

        XCTAssertEqual(CollectorPreferences(defaults: defaults).enabledSources, [.claudeCode])
        XCTAssertEqual(SummarizerPreferences(defaults: defaults).primary, .codex)
    }

    func testLegacyBootstrapDisablesUnavailableEnabledCollectorsOnce() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: PreferenceKeys.cliDefaultsInitialized)
        defaults.set(true, forKey: PreferenceKeys.collectCodex)
        defaults.set(true, forKey: PreferenceKeys.collectClaude)

        CLIInitialPreferences.applyIfNeeded(
            defaults: defaults,
            resolver: AvailabilityResolver(installed: [.codex], readableLogs: [.codex])
        )

        XCTAssertEqual(CollectorPreferences(defaults: defaults).enabledSources, [.codex])
        XCTAssertEqual(defaults.integer(forKey: PreferenceKeys.cliDefaultsInitialized), 3)
    }

    func testPreferredProviderSkipsAnUninstalledPrimaryForMemoOnlyRuns() {
        let codex = AvailabilitySummaryProvider(kind: .codex, available: false)
        let claude = AvailabilitySummaryProvider(kind: .claudeCode, available: true)
        let orchestrator = SummaryOrchestrator(providers: [
            .codex: codex,
            .claudeCode: claude
        ])

        XCTAssertEqual(
            orchestrator.preferredProvider(
                for: SummarizerPreferences(primary: .codex, automaticFallback: true)
            ),
            .claudeCode
        )
    }

    func testNoInstalledSummarizersProducesNeutralErrorWhenFallbackIsEnabled() async {
        let codex = AvailabilitySummaryProvider(kind: .codex, available: false)
        let claude = AvailabilitySummaryProvider(kind: .claudeCode, available: false)
        let orchestrator = SummaryOrchestrator(providers: [
            .codex: codex,
            .claudeCode: claude
        ])

        do {
            _ = try await orchestrator.summarize(
                batch: CollectionBatch(
                    interval: AwayInterval(start: .now.addingTimeInterval(-1), end: .now),
                    sessions: [CollectedSessionArtifact(
                        id: "session",
                        provider: .codex,
                        workingDirectory: nil,
                        events: [CollectedEvent(
                            timestamp: .now,
                            kind: "test",
                            content: "content"
                        )],
                        wasTruncated: false
                    )],
                    issues: []
                ),
                preferences: SummarizerPreferences(primary: .codex, automaticFallback: true)
            )
            XCTFail("expected no provider error")
        } catch let error as SummaryProviderError {
            XCTAssertEqual(error, .noProviderAvailable)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
        XCTAssertEqual(codex.callCount, 0)
        XCTAssertEqual(claude.callCount, 0)
    }

    func testUnavailablePrimaryUsesAvailableFallbackWithoutInvokingPrimary() async throws {
        let codex = AvailabilitySummaryProvider(kind: .codex, available: false)
        let claude = AvailabilitySummaryProvider(kind: .claudeCode, available: true)
        let orchestrator = SummaryOrchestrator(providers: [
            .codex: codex,
            .claudeCode: claude
        ])

        let outcome = try await orchestrator.summarize(
            batch: CollectionBatch(
                interval: AwayInterval(start: .now.addingTimeInterval(-1), end: .now),
                sessions: [CollectedSessionArtifact(
                    id: "session",
                    provider: .codex,
                    workingDirectory: nil,
                    events: [CollectedEvent(
                        timestamp: .now,
                        kind: "test",
                        content: "content"
                    )],
                    wasTruncated: false
                )],
                issues: []
            ),
            preferences: SummarizerPreferences(primary: .codex, automaticFallback: true)
        )

        XCTAssertEqual(outcome.provider, .claudeCode)
        XCTAssertTrue(outcome.fallbackUsed)
        XCTAssertEqual(codex.callCount, 0)
        XCTAssertEqual(claude.callCount, 1)
    }

    private func makeDefaults() throws -> (UserDefaults, String) {
        let suiteName = "CapsStackCLIConfigurationTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw NSError(domain: "CapsStackCLIConfigurationTests", code: 1)
        }
        return (defaults, suiteName)
    }
}

private struct AvailabilityResolver: CLIResolving {
    let installed: Set<CLIKind>
    let readableLogs: Set<CLIKind>

    func executableURL(for kind: CLIKind, override: String?) -> URL? {
        installed.contains(kind) ? URL(fileURLWithPath: "/usr/bin/true") : nil
    }

    func status(for kind: CLIKind, override: String?) -> CLIStatus {
        CLIStatus(
            kind: kind,
            executablePath: installed.contains(kind) ? "/usr/bin/true" : nil,
            version: installed.contains(kind) ? "test" : nil,
            logDirectory: "/tmp/\(kind.rawValue)",
            canReadLogs: readableLogs.contains(kind)
        )
    }

    func logDirectory(for kind: CLIKind) -> URL {
        URL(fileURLWithPath: "/tmp/\(kind.rawValue)", isDirectory: true)
    }
}

private final class AvailabilitySummaryProvider: SummaryProvider, @unchecked Sendable {
    let kind: CLIKind
    let available: Bool
    private(set) var callCount = 0

    init(kind: CLIKind, available: Bool) {
        self.kind = kind
        self.available = available
    }

    func isAvailable(executableOverride: String?) -> Bool {
        available
    }

    func summarize(
        batch: CollectionBatch,
        executableOverride: String?,
        modelOverride: String?,
        reasoningOverride: String?
    ) async throws -> SummaryDocument {
        callCount += 1
        if !available {
            throw SummaryProviderError.executableNotFound(kind)
        }
        return .empty
    }
}
