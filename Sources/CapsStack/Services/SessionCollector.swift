import Foundation

protocol SessionCollector: AnyObject {
    var provider: CLIKind { get }
    func collect(interval: AwayInterval) -> CollectionResult
}

/// Creates one collector per supported CLI. Log layout decisions stay in the backend so the UI
/// only needs to select source kinds.
struct SessionCollectorFactory {
    let resolver: CLIResolving

    init(resolver: CLIResolving = CLIResolver()) {
        self.resolver = resolver
    }

    func makeCollector(for kind: CLIKind, executableOverride: String? = nil) -> SessionCollector {
        let rootDirectory = resolver.logDirectory(for: kind)
        switch kind {
        case .opencode:
            return OpenCodeSessionCollector(
                rootDirectory: rootDirectory,
                executableURL: resolver.executableURL(for: kind, override: executableOverride)
            )
        case .kiloCode:
            return OpenCodeSessionCollector(
                provider: kind,
                rootDirectory: rootDirectory,
                executableURL: resolver.executableURL(for: kind, override: executableOverride),
                // Kilo defaults to the current project. The collector runs from the data
                // directory, so request every local project explicitly.
                listArguments: ["session", "list", "--all", "--format", "json"],
                exportArguments: { ["export", $0] },
                allowsFileFallback: false
            )
        case .goose:
            return OpenCodeSessionCollector(
                provider: kind,
                rootDirectory: rootDirectory,
                executableURL: resolver.executableURL(for: kind, override: executableOverride),
                listArguments: ["session", "list", "--format", "json"],
                exportArguments: {
                    ["session", "export", "--session-id", $0, "--format", "json"]
                },
                allowsFileFallback: false
            )
        case .githubCopilot:
            return GitHubCopilotSessionCollector(rootDirectory: rootDirectory)
        case .qwenCode:
            // Qwen's runtime root also contains settings, credentials, and other JSON state.
            // Only its documented current/legacy transcript directories are session inputs.
            return JSONLSessionCollector(
                provider: kind,
                rootDirectory: rootDirectory,
                allowedTopLevelDirectories: ["projects", "tmp"]
            )
        default:
            return JSONLSessionCollector(provider: kind, rootDirectory: rootDirectory)
        }
    }

    func makeCollectors(
        for kinds: Set<CLIKind>,
        executableOverrides: [CLIKind: String] = [:]
    ) -> [SessionCollector] {
        kinds.sorted { $0.rawValue < $1.rawValue }.map {
            makeCollector(for: $0, executableOverride: executableOverrides[$0])
        }
    }

    /// Convenience entry point for callers that do not need to retain a multi-collector.
    func collect(
        interval: AwayInterval,
        sources: Set<CLIKind>,
        executableOverrides: [CLIKind: String] = [:]
    ) -> CollectionBatch {
        MultiSessionCollector(factory: self).collect(
            interval: interval,
            sources: sources,
            executableOverrides: executableOverrides
        )
    }
}

/// Collects all selected providers and preserves partial results when one provider has a
/// missing directory or malformed records.
final class MultiSessionCollector: @unchecked Sendable {
    private let factory: SessionCollectorFactory

    init(factory: SessionCollectorFactory = SessionCollectorFactory()) {
        self.factory = factory
    }

    func collect(
        interval: AwayInterval,
        sources: Set<CLIKind>,
        executableOverrides: [CLIKind: String] = [:]
    ) -> CollectionBatch {
        var sessions: [CollectedSessionArtifact] = []
        var issues: [CollectionIssue] = []

        for collector in factory.makeCollectors(for: sources, executableOverrides: executableOverrides) {
            let result = collector.collect(interval: interval)
            sessions.append(contentsOf: result.sessions)
            issues.append(contentsOf: result.issues)
        }

        sessions.sort {
            ($0.firstEventAt ?? interval.start, $0.id) < ($1.firstEventAt ?? interval.start, $1.id)
        }
        return CollectionBatch(interval: interval, sessions: sessions, issues: issues)
    }
}
