import Foundation

/// Coordinates provider selection, input-size limiting, and fallback. A provider failure never
/// discards the original collection batch, so callers can persist it for retry.
struct SummaryOrchestrator {
    private let providers: [CLIKind: SummaryProvider]
    private let maxInputBytes: Int

    init(
        resolver: CLIResolving = CLIResolver(),
        runner: ProcessRunning = ProcessRunner(),
        timeout: TimeInterval = 120,
        maxInputBytes: Int = 180 * 1024,
        providers: [CLIKind: SummaryProvider]? = nil
    ) {
        self.maxInputBytes = max(16 * 1024, maxInputBytes)
        self.providers = providers ?? [
            .codex: CodexSummaryProvider(resolver: resolver, runner: runner, timeout: timeout),
            .claudeCode: ClaudeCodeSummaryProvider(resolver: resolver, runner: runner, timeout: timeout),
            .opencode: OpenCodeSummaryProvider(resolver: resolver, runner: runner, timeout: timeout),
            .pi: PiSummaryProvider(resolver: resolver, runner: runner, timeout: timeout)
        ]
    }

    func summarize(batch: CollectionBatch, preferences: SummarizerPreferences) async throws -> SummaryOutcome {
        guard !batch.sessions.isEmpty else {
            return SummaryOutcome(document: .empty, provider: preferences.primary, fallbackUsed: false)
        }

        do {
            let document = try await summarizeWithProvider(
                kind: preferences.primary,
                batch: batch,
                executableOverride: preferences.executableOverride(for: preferences.primary),
                modelOverride: preferences.modelOverride(for: preferences.primary),
                reasoningOverride: preferences.reasoningOverride(for: preferences.primary)
            )
            return SummaryOutcome(document: document, provider: preferences.primary, fallbackUsed: false)
        } catch let primaryError {
            guard preferences.automaticFallback else {
                throw primaryError
            }

            var lastError: Error = primaryError
            for fallbackKind in CLIKind.allCases where fallbackKind != preferences.primary {
                guard providers[fallbackKind] != nil else { continue }
                do {
                    let document = try await summarizeWithProvider(
                        kind: fallbackKind,
                        batch: batch,
                        executableOverride: preferences.executableOverride(for: fallbackKind),
                        modelOverride: preferences.modelOverride(for: fallbackKind),
                        reasoningOverride: preferences.reasoningOverride(for: fallbackKind)
                    )
                    return SummaryOutcome(document: document, provider: fallbackKind, fallbackUsed: true)
                } catch {
                    lastError = error
                }
            }
            throw lastError
        }
    }

    /// Convenience API useful for a settings test or a controller that already has raw values.
    func summarize(
        batch: CollectionBatch,
        primary: CLIKind,
        automaticFallback: Bool,
        executableOverrides: [CLIKind: String] = [:],
        modelOverrides: [CLIKind: String] = [:],
        reasoningOverrides: [CLIKind: String] = [:]
    ) async throws -> SummaryOutcome {
        try await summarize(
            batch: batch,
            preferences: SummarizerPreferences(
                primary: primary,
                automaticFallback: automaticFallback,
                executableOverrides: executableOverrides,
                modelOverrides: modelOverrides,
                reasoningOverrides: reasoningOverrides
            )
        )
    }

    private func summarizeWithProvider(
        kind: CLIKind,
        batch: CollectionBatch,
        executableOverride: String?,
        modelOverride: String?,
        reasoningOverride: String?
    ) async throws -> SummaryDocument {
        guard let provider = providers[kind] else {
            throw SummaryProviderError.noProviderAvailable
        }

        let chunks = split(batch: batch)
        var documents: [SummaryDocument] = []
        documents.reserveCapacity(chunks.count)
        for chunk in chunks {
            documents.append(try await provider.summarize(
                batch: chunk,
                executableOverride: executableOverride,
                modelOverride: modelOverride,
                reasoningOverride: reasoningOverride
            ))
        }
        guard documents.count > 1 else { return documents[0] }

        // The raw records have already been summarized per session/chunk. Feed those compact
        // summaries back to the same provider for a chronological final integration pass.
        let summaryArtifacts = documents.enumerated().map { index, document in
            CollectedSessionArtifact(
                id: "summary-chunk-\(index + 1)",
                provider: kind,
                workingDirectory: nil,
                events: [CollectedEvent(
                    timestamp: batch.interval.start.addingTimeInterval(TimeInterval(index)),
                    kind: "chunk-summary",
                    content: encode(document)
                )],
                wasTruncated: false
            )
        }
        let integrationBatch = CollectionBatch(
            interval: batch.interval,
            sessions: summaryArtifacts,
            issues: batch.issues
        )
        return try await provider.summarize(
            batch: integrationBatch,
            executableOverride: executableOverride,
            modelOverride: modelOverride,
            reasoningOverride: reasoningOverride
        )
    }

    private func split(batch: CollectionBatch) -> [CollectionBatch] {
        guard encodedSize(of: batch) > maxInputBytes else { return [batch] }

        let atoms = batch.sessions.flatMap { split(session: $0, interval: batch.interval) }
        guard !atoms.isEmpty else { return [batch] }

        var chunks: [CollectionBatch] = []
        var current: [CollectedSessionArtifact] = []
        for atom in atoms {
            let candidate = CollectionBatch(interval: batch.interval, sessions: current + [atom], issues: batch.issues)
            if !current.isEmpty && encodedSize(of: candidate) > maxInputBytes {
                chunks.append(CollectionBatch(interval: batch.interval, sessions: current, issues: batch.issues))
                current = [atom]
            } else {
                current.append(atom)
            }
        }
        if !current.isEmpty {
            chunks.append(CollectionBatch(interval: batch.interval, sessions: current, issues: batch.issues))
        }
        return chunks.isEmpty ? [batch] : chunks
    }

    private func split(session: CollectedSessionArtifact, interval: AwayInterval) -> [CollectedSessionArtifact] {
        let complete = CollectionBatch(interval: interval, sessions: [session], issues: [])
        guard encodedSize(of: complete) > maxInputBytes, session.events.count > 1 else {
            return [session]
        }

        var result: [CollectedSessionArtifact] = []
        var currentEvents: [CollectedEvent] = []
        for event in session.events {
            let candidateEvents = currentEvents + [event]
            let candidate = CollectedSessionArtifact(
                id: session.id,
                provider: session.provider,
                workingDirectory: session.workingDirectory,
                events: candidateEvents,
                wasTruncated: session.wasTruncated
            )
            if !currentEvents.isEmpty,
               encodedSize(of: CollectionBatch(interval: interval, sessions: [candidate], issues: [])) > maxInputBytes {
                result.append(makeChunk(from: session, events: currentEvents, index: result.count + 1))
                currentEvents = [event]
            } else {
                currentEvents = candidateEvents
            }
        }
        if !currentEvents.isEmpty {
            result.append(makeChunk(from: session, events: currentEvents, index: result.count + 1))
        }
        return result
    }

    private func makeChunk(
        from session: CollectedSessionArtifact,
        events: [CollectedEvent],
        index: Int
    ) -> CollectedSessionArtifact {
        var didTruncateContent = false
        let boundedEvents = events.map { event in
            let bounded = String(event.content.prefix(max(1, maxInputBytes / 2)))
            if bounded.count != event.content.count { didTruncateContent = true }
            return CollectedEvent(timestamp: event.timestamp, kind: event.kind, content: bounded)
        }
        return CollectedSessionArtifact(
            id: "\(session.id)#\(index)",
            provider: session.provider,
            workingDirectory: session.workingDirectory,
            events: boundedEvents,
            wasTruncated: session.wasTruncated || didTruncateContent
        )
    }

    private func encodedSize(of batch: CollectionBatch) -> Int {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return (try? encoder.encode(batch).count) ?? Int.max
    }

    private func encode(_ document: SummaryDocument) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(document) else { return document.overview }
        return String(decoding: data, as: UTF8.self)
    }
}
