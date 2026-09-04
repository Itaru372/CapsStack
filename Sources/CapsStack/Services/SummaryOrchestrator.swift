import CapsStackLocalization
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
            .pi: PiSummaryProvider(resolver: resolver, runner: runner, timeout: timeout),
            .githubCopilot: SafeHeadlessSummaryProvider(
                kind: .githubCopilot,
                strategy: .githubCopilot,
                resolver: resolver,
                runner: runner,
                timeout: timeout
            ),
            .goose: SafeHeadlessSummaryProvider(
                kind: .goose,
                strategy: .goose,
                resolver: resolver,
                runner: runner,
                timeout: timeout
            ),
            .qwenCode: SafeHeadlessSummaryProvider(
                kind: .qwenCode,
                strategy: .qwenCode,
                resolver: resolver,
                runner: runner,
                timeout: timeout
            )
        ]
    }

    func summarize(batch: CollectionBatch, preferences: SummarizerPreferences) async throws -> SummaryOutcome {
        guard !batch.sessions.isEmpty else {
            return SummaryOutcome(document: .empty, provider: preferences.primary, fallbackUsed: false)
        }

        let primaryOverride = preferences.executableOverride(for: preferences.primary)
        let primaryProvider = providers[preferences.primary]
        let primaryAvailable = primaryProvider?.isAvailable(executableOverride: primaryOverride) ?? false
        let primaryError: Error

        if primaryAvailable {
            do {
                let document = try await summarizeWithProvider(
                    kind: preferences.primary,
                    batch: batch,
                    executableOverride: primaryOverride,
                    modelOverride: preferences.modelOverride(for: preferences.primary),
                    reasoningOverride: preferences.reasoningOverride(for: preferences.primary)
                )
                return SummaryOutcome(document: document, provider: preferences.primary, fallbackUsed: false)
            } catch {
                primaryError = error
            }
        } else if primaryProvider == nil {
            primaryError = SummaryProviderError.noProviderAvailable
        } else {
            // Do not invoke a missing executable just to discover that it is missing. This is
            // important for a Claude-only or Codex-only machine where the other provider is only
            // present as an optional fallback.
            primaryError = SummaryProviderError.executableNotFound(preferences.primary)
        }

        try Task.checkCancellation()
        guard preferences.automaticFallback else {
            throw primaryError
        }

        var lastError: Error = primaryError
        var attemptedFallback = false
        for fallbackKind in CLIKind.summarizerCases where fallbackKind != preferences.primary {
            guard let fallbackProvider = providers[fallbackKind] else { continue }
            let executableOverride = preferences.executableOverride(for: fallbackKind)
            guard fallbackProvider.isAvailable(executableOverride: executableOverride) else {
                continue
            }
            attemptedFallback = true
            do {
                let document = try await summarizeWithProvider(
                    kind: fallbackKind,
                    batch: batch,
                    executableOverride: executableOverride,
                    modelOverride: preferences.modelOverride(for: fallbackKind),
                    reasoningOverride: preferences.reasoningOverride(for: fallbackKind)
                )
                return SummaryOutcome(document: document, provider: fallbackKind, fallbackUsed: true)
            } catch {
                try Task.checkCancellation()
                lastError = error
            }
        }
        // If every fallback is missing, preserve the primary error unless the primary itself
        // is unavailable. In that case there is no provider at all, so report the neutral
        // error instead of making Codex or Claude appear to depend on the other one.
        if !attemptedFallback, !primaryAvailable {
            throw SummaryProviderError.noProviderAvailable
        }
        throw lastError
    }

    /// Selects the first provider that can actually run for the current preferences. This is
    /// used for synthetic memo-only sessions so their source reflects the provider that will
    /// summarize them when a stale primary setting points at an uninstalled CLI.
    func preferredProvider(for preferences: SummarizerPreferences) -> CLIKind? {
        var candidates = [preferences.primary]
        if preferences.automaticFallback {
            candidates.append(contentsOf: CLIKind.summarizerCases.filter { $0 != preferences.primary })
        }
        return candidates.first { kind in
            guard let provider = providers[kind] else { return false }
            return provider.isAvailable(executableOverride: preferences.executableOverride(for: kind))
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
        // summaries back to the same provider for a chronological final integration pass. The
        // project grouping can expand one document into many payloads, so the budget is based on
        // the flattened payload count rather than the number of intermediate documents.
        let payloads = documents.enumerated().flatMap { documentIndex, document in
            let projectPayloads: [(id: String, content: String, sessions: [SessionSummary])]
            if document.projects.isEmpty {
                projectPayloads = [("legacy", encode(document), document.sessions)]
            } else {
                projectPayloads = document.projects.enumerated().map { projectIndex, project in
                    ("project-\(projectIndex + 1)", encode(project), project.sessions)
                }
            }

            return projectPayloads.map { payload in
                (
                    id: "summary-chunk-\(documentIndex + 1)-\(payload.id)",
                    content: payload.content,
                    sessions: payload.sessions
                )
            }
        }.enumerated().map { ordinal, payload in
            (
                id: payload.id,
                content: payload.content,
                sessions: payload.sessions,
                ordinal: ordinal
            )
        }
        let perPayloadLimit = max(1, (maxInputBytes / 2) / max(1, payloads.count))
        func makeSummaryArtifacts(contentLimit: Int) -> [CollectedSessionArtifact] {
            payloads.map { payload in
                let boundedContent = truncatedUTF8(payload.content, limit: contentLimit)
                return CollectedSessionArtifact(
                    id: payload.id,
                    provider: kind,
                    workingDirectory: originalWorkingDirectory(
                        for: payload.sessions,
                        in: batch
                    ),
                    events: [CollectedEvent(
                        timestamp: batch.interval.start.addingTimeInterval(TimeInterval(payload.ordinal)),
                        kind: "chunk-summary",
                        content: boundedContent
                    )],
                    wasTruncated: boundedContent.utf8.count < payload.content.utf8.count,
                    client: originalClient(for: payload.sessions, in: batch)
                )
            }
        }
        let omissionNotice = omittedChunkCount > 0
            ? CapsStackText.format(.inputChunksOmitted, omittedChunkCount)
            : nil
        var integrationIssues = boundedIssues(batch.issues)
        if let omissionNotice {
            integrationIssues.append(CollectionIssue(provider: kind, message: omissionNotice))
        }
        let makeIntegrationBatch: ([CollectedSessionArtifact], [CollectionIssue]) -> CollectionBatch = { artifacts, issues in
            CollectionBatch(
                interval: batch.interval,
                sessions: artifacts,
                issues: issues,
                quickMemo: batch.quickMemo.map { truncatedUTF8($0, limit: maxInputBytes / 8) }
            )
        }

        var contentLimit = perPayloadLimit
        var summaryArtifacts = makeSummaryArtifacts(contentLimit: contentLimit)
        var integrationBatch = makeIntegrationBatch(summaryArtifacts, integrationIssues)
        var omittedProjectCount = 0

        // Account for JSON metadata, issues, and the memo as well as event content. If the
        // flattened project payloads still exceed the hard cap, shrink their content first and
        // then omit the oldest tail explicitly rather than sending an oversized request.
        while encodedSize(of: integrationBatch) > maxInputBytes {
            if contentLimit > 1 {
                contentLimit = max(1, contentLimit / 2)
                summaryArtifacts = makeSummaryArtifacts(contentLimit: contentLimit)
            } else if !summaryArtifacts.isEmpty {
                summaryArtifacts.removeLast()
                omittedProjectCount += 1
            } else {
                break
            }
            integrationBatch = makeIntegrationBatch(summaryArtifacts, integrationIssues)
        }

        let integrationOmissionNotice = omittedProjectCount > 0
            ? CapsStackText.resolve(.projectSummariesOmitted)
            : nil
        if let integrationOmissionNotice {
            integrationIssues.append(CollectionIssue(provider: kind, message: integrationOmissionNotice))
            integrationBatch = makeIntegrationBatch(summaryArtifacts, integrationIssues)
            // The notice itself consumes a small amount of the cap. Keep the final batch bounded
            // even when adding it forces one more payload to be removed.
            while encodedSize(of: integrationBatch) > maxInputBytes, !summaryArtifacts.isEmpty {
                summaryArtifacts.removeLast()
                omittedProjectCount += 1
                integrationBatch = makeIntegrationBatch(summaryArtifacts, integrationIssues)
            }
        }
        let integrated = try await provider.summarize(
            batch: integrationBatch,
            executableOverride: executableOverride,
            modelOverride: modelOverride,
            reasoningOverride: reasoningOverride
        )
        let omissionNotices = [omissionNotice, integrationOmissionNotice].compactMap { $0 }
        guard !omissionNotices.isEmpty else { return integrated }
        return SummaryDocument(
            overview: integrated.overview,
            progress: integrated.progress,
            currentState: integrated.currentState,
            decisions: integrated.decisions,
            blockers: integrated.blockers + omissionNotices,
            nextSteps: integrated.nextSteps,
            sessions: integrated.sessions,
            projects: integrated.projects
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
                wasTruncated: session.wasTruncated,
                client: session.client
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
            wasTruncated: session.wasTruncated || didTruncateContent,
            client: session.client
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
                message: CapsStackText.format(.additionalCollectionWarnings, issues.count - result.count)
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

    private func encode(_ project: ProjectSummary) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(project) else { return project.summary }
        return String(decoding: data, as: UTF8.self)
    }

    private func originalWorkingDirectory(
        for summaries: [SessionSummary],
        in batch: CollectionBatch
    ) -> String? {
        for summary in summaries {
            if let match = batch.sessions.first(where: { artifact in
                summary.sessionID == artifact.id
                    || summary.sessionID.hasPrefix("\(artifact.id)#")
                    || artifact.id.hasPrefix("\(summary.sessionID)#")
            }), let directory = match.workingDirectory {
                return directory
            }
        }
        return nil
    }

    private func originalClient(
        for summaries: [SessionSummary],
        in batch: CollectionBatch
    ) -> AgentClientKind? {
        let clients = Set(summaries.map { summary in
            batch.sessions.first(where: { artifact in
                summary.sessionID == artifact.id
                    || summary.sessionID.hasPrefix("\(artifact.id)#")
                    || artifact.id.hasPrefix("\(summary.sessionID)#")
            })?.effectiveClient ?? .unknown
        })
        return clients.count == 1 ? clients.first : nil
    }
}
