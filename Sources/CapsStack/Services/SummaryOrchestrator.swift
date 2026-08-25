import Foundation

/// Coordinates provider selection, input-size limiting, and fallback. A provider failure never
/// discards the original collection batch, so callers can persist it for retry.
struct SummaryOrchestrator {
    private let providers: [CLIKind: SummaryProvider]
    private let maxInputBytes: Int
    private let maxChunkCount: Int

    init(
        resolver: CLIResolving = CLIResolver(),
        runner: ProcessRunning = ProcessRunner(),
        timeout: TimeInterval = 120,
        maxInputBytes: Int = 180 * 1024,
        maxChunkCount: Int = 8,
        providers: [CLIKind: SummaryProvider]? = nil
    ) {
        self.maxInputBytes = max(16 * 1024, maxInputBytes)
        self.maxChunkCount = min(16, max(1, maxChunkCount))
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
            try Task.checkCancellation()
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
                    try Task.checkCancellation()
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

        let allChunks = split(batch: batch)
        let chunks = boundedChunks(allChunks)
        let omittedChunkCount = allChunks.count - chunks.count
        let requiresIntegration = chunks.count != 1 || chunks[0] != batch || omittedChunkCount > 0
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
        guard requiresIntegration else { return documents[0] }

        // The raw records have already been summarized per session/chunk. Feed those compact
        // summaries back to the same provider for a chronological final integration pass.
        let perDocumentLimit = max(32, (maxInputBytes / 2) / max(1, documents.count))
        let summaryArtifacts = documents.enumerated().map { index, document in
            let encodedDocument = encode(document)
            let boundedDocument = truncatedUTF8(encodedDocument, limit: perDocumentLimit)
            return CollectedSessionArtifact(
                id: "summary-chunk-\(index + 1)",
                provider: kind,
                workingDirectory: nil,
                events: [CollectedEvent(
                    timestamp: batch.interval.start.addingTimeInterval(TimeInterval(index)),
                    kind: "chunk-summary",
                    content: boundedDocument
                )],
                wasTruncated: boundedDocument.utf8.count < encodedDocument.utf8.count
            )
        }
        let omissionNotice = omittedChunkCount > 0
            ? "入力上限により、中間の要約チャンクを\(omittedChunkCount)個省略しました。"
            : nil
        var integrationIssues = boundedIssues(batch.issues)
        if let omissionNotice {
            integrationIssues.append(CollectionIssue(provider: kind, message: omissionNotice))
        }
        let integrationBatch = CollectionBatch(
            interval: batch.interval,
            sessions: summaryArtifacts,
            issues: integrationIssues,
            quickMemo: batch.quickMemo.map { truncatedUTF8($0, limit: maxInputBytes / 8) }
        )
        let integrated = try await provider.summarize(
            batch: integrationBatch,
            executableOverride: executableOverride,
            modelOverride: modelOverride,
            reasoningOverride: reasoningOverride
        )
        guard let omissionNotice else { return integrated }
        return SummaryDocument(
            overview: integrated.overview,
            progress: integrated.progress,
            currentState: integrated.currentState,
            decisions: integrated.decisions,
            blockers: integrated.blockers + [omissionNotice],
            nextSteps: integrated.nextSteps,
            sessions: integrated.sessions
        )
    }

    /// A pathological log archive must not turn one return into an unbounded number of paid CLI
    /// calls. Preserve both the earliest context and the most recent state, and make the omitted
    /// middle explicit in the integration prompt and returned document.
    private func boundedChunks(_ chunks: [CollectionBatch]) -> [CollectionBatch] {
        guard chunks.count > maxChunkCount else { return chunks }
        let leadingCount = (maxChunkCount + 1) / 2
        let trailingCount = maxChunkCount - leadingCount
        return Array(chunks.prefix(leadingCount)) + Array(chunks.suffix(trailingCount))
    }

    private func split(batch: CollectionBatch) -> [CollectionBatch] {
        guard encodedSize(of: batch) > maxInputBytes else { return [batch] }

        let atoms = batch.sessions.flatMap { split(session: $0, interval: batch.interval) }
        guard !atoms.isEmpty else { return [batch] }

        var chunks: [CollectionBatch] = []
        var current: [CollectedSessionArtifact] = []
        for atom in atoms {
            let candidate = CollectionBatch(interval: batch.interval, sessions: current + [atom], issues: [])
            if !current.isEmpty && encodedSize(of: candidate) > maxInputBytes {
                chunks.append(CollectionBatch(interval: batch.interval, sessions: current, issues: []))
                current = [atom]
            } else {
                current.append(atom)
            }
        }
        if !current.isEmpty {
            chunks.append(CollectionBatch(interval: batch.interval, sessions: current, issues: []))
        }
        return chunks.isEmpty ? [batch] : chunks
    }

    private func split(session: CollectedSessionArtifact, interval: AwayInterval) -> [CollectedSessionArtifact] {
        let complete = CollectionBatch(interval: interval, sessions: [session], issues: [])
        guard encodedSize(of: complete) > maxInputBytes else {
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
            let bounded = truncatedUTF8(event.content, limit: max(1, maxInputBytes / 2))
            if bounded.utf8.count != event.content.utf8.count { didTruncateContent = true }
            return CollectedEvent(
                timestamp: event.timestamp,
                kind: truncatedUTF8(event.kind, limit: 1_024),
                content: bounded
            )
        }
        return CollectedSessionArtifact(
            id: "\(truncatedUTF8(session.id, limit: 2_048))#\(index)",
            provider: session.provider,
            workingDirectory: session.workingDirectory.map { truncatedUTF8($0, limit: 4_096) },
            events: boundedEvents,
            wasTruncated: session.wasTruncated || didTruncateContent
        )
    }

    private func encodedSize(of batch: CollectionBatch) -> Int {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return (try? encoder.encode(batch).count) ?? Int.max
    }

    private func boundedIssues(_ issues: [CollectionIssue]) -> [CollectionIssue] {
        let maximumIssueCount = 16
        let messageByteBudget = max(256, maxInputBytes / 10)
        var usedBytes = 0
        var result: [CollectionIssue] = []
        for issue in issues.prefix(maximumIssueCount) {
            let remaining = messageByteBudget - usedBytes
            guard remaining > 0 else { break }
            let message = truncatedUTF8(issue.message, limit: min(1_024, remaining))
            guard !message.isEmpty else { break }
            usedBytes += message.utf8.count
            result.append(CollectionIssue(id: issue.id, provider: issue.provider, message: message))
        }
        if result.count < issues.count, let provider = issues.first?.provider {
            result.append(CollectionIssue(
                provider: provider,
                message: "ほか\(issues.count - result.count)件の収集警告を省略しました。"
            ))
        }
        return result
    }

    private func truncatedUTF8(_ value: String, limit: Int) -> String {
        let bytes = Data(value.utf8)
        let boundedLimit = max(0, limit)
        guard bytes.count > boundedLimit else { return value }

        var end = min(bytes.count, boundedLimit)
        while end > 0 {
            if let result = String(data: bytes.prefix(end), encoding: .utf8) {
                return result
            }
            end -= 1
        }
        return ""
    }

    private func encode(_ document: SummaryDocument) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(document) else { return document.overview }
        return String(decoding: data, as: UTF8.self)
    }
}
