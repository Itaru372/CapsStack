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

    func makeCollector(for kind: CLIKind) -> SessionCollector {
        let rootDirectory = resolver.logDirectory(for: kind)
        switch kind {
        case .opencode:
            return OpenCodeSessionCollector(
                rootDirectory: rootDirectory,
                executableURL: resolver.executableURL(for: kind, override: nil)
            )
        default:
            return JSONLSessionCollector(provider: kind, rootDirectory: rootDirectory)
        }
    }

    func makeCollectors(for kinds: Set<CLIKind>) -> [SessionCollector] {
        kinds.sorted { $0.rawValue < $1.rawValue }.map(makeCollector(for:))
    }

    /// Convenience entry point for callers that do not need to retain a multi-collector.
    func collect(interval: AwayInterval, sources: Set<CLIKind>) -> CollectionBatch {
        MultiSessionCollector(factory: self).collect(interval: interval, sources: sources)
    }
}

/// Collects all selected providers and preserves partial results when one provider has a
/// missing directory or malformed records.
final class MultiSessionCollector: @unchecked Sendable {
    private let factory: SessionCollectorFactory

    init(factory: SessionCollectorFactory = SessionCollectorFactory()) {
        self.factory = factory
    }

    func collect(interval: AwayInterval, sources: Set<CLIKind>) -> CollectionBatch {
        var sessions: [CollectedSessionArtifact] = []
        var issues: [CollectionIssue] = []

        for collector in factory.makeCollectors(for: sources) {
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
