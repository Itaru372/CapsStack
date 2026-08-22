import Foundation

enum HistoryStoreError: LocalizedError, Equatable {
    case invalidHistoryData
    case pendingArtifactNotFound(UUID)

    var errorDescription: String? {
        switch self {
        case .invalidHistoryData:
            return "CapsStackの履歴ファイルを読み取れません。"
        case .pendingArtifactNotFound(let id):
            return "保留中の収集資料が見つかりません: \(id.uuidString)"
        }
    }
}

/// Persists summaries and retryable raw collection artifacts under Application Support.
///
/// Layout:
///   Application Support/CapsStack/history.json
///   Application Support/CapsStack/Pending/<artifact-id>.json
final class HistoryStore: @unchecked Sendable {
    let directoryURL: URL
    let historyURL: URL
    let pendingDirectoryURL: URL

    private let fileManager: FileManager
    private let lock = NSLock()
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        directoryURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        let base = directoryURL ?? Self.defaultDirectory(fileManager: fileManager)
        self.directoryURL = base
        self.historyURL = base.appendingPathComponent("history.json")
        self.pendingDirectoryURL = base.appendingPathComponent("Pending", isDirectory: true)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    /// Loads entries newest-first. Missing history is the normal first-launch state.
    func load() throws -> [HistoryEntry] {
        lock.lock()
        defer { lock.unlock() }
        return try loadUnlocked()
    }

    func loadEntries() throws -> [HistoryEntry] {
        try load()
    }

    /// A convenience snapshot for UI code. Errors are surfaced by `load()` for callers that need
    /// diagnostics; this property keeps a corrupted file from crashing a menu-bar UI.
    var entries: [HistoryEntry] {
        (try? load()) ?? []
    }

    /// Inserts or replaces an entry by its UUID.
    @discardableResult
    func save(_ entry: HistoryEntry) throws -> HistoryEntry {
        lock.lock()
        defer { lock.unlock() }
        var entries = try loadUnlocked()
        if let index = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[index] = entry
        } else {
            entries.append(entry)
        }
        try writeHistory(entries)
        return entry
    }

    @discardableResult
    func replace(_ entry: HistoryEntry) throws -> HistoryEntry {
        try save(entry)
    }

    @discardableResult
    func replace(id: UUID, with entry: HistoryEntry) throws -> HistoryEntry {
        lock.lock()
        defer { lock.unlock() }
        var entries = try loadUnlocked()
        guard let index = entries.firstIndex(where: { $0.id == id }) else {
            throw HistoryStoreError.invalidHistoryData
        }
        entries[index] = entry
        try writeHistory(entries)
        return entry
    }

    func delete(_ id: UUID) throws {
        lock.lock()
        defer { lock.unlock() }
        var entries = try loadUnlocked()
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        let entry = entries.remove(at: index)
        try writeHistory(entries)
        if let pendingID = entry.pendingArtifactID {
            try removePendingUnlocked(pendingID)
        }
    }

    func delete(entryID: UUID) throws {
        try delete(entryID)
    }

    /// Saves raw input before a summary attempt. If the process crashes, the Pending artifact is
    /// enough to retry without rereading source logs.
    @discardableResult
    func savePending(batch: CollectionBatch, errorMessage: String? = nil) throws -> HistoryEntry {
        lock.lock()
        defer { lock.unlock() }
        let artifactID = UUID()
        try ensureDirectories()
        try writePendingUnlocked(batch, id: artifactID)

        let entry = HistoryEntry(
            interval: batch.interval,
            status: .pending,
            sessionCount: batch.sessions.count,
            sources: sources(for: batch),
            collectionIssues: batch.issues,
            errorMessage: errorMessage,
            pendingArtifactID: artifactID
        )
        var entries = try loadUnlocked()
        entries.append(entry)
        try writeHistory(entries)
        return entry
    }

    func savePending(batch: CollectionBatch, error: String?) throws -> HistoryEntry {
        try savePending(batch: batch, errorMessage: error)
    }

    @discardableResult
    func savePendingArtifact(_ batch: CollectionBatch) throws -> UUID {
        lock.lock()
        defer { lock.unlock() }
        let id = UUID()
        try ensureDirectories()
        try writePendingUnlocked(batch, id: id)
        return id
    }

    func loadPending(_ id: UUID) throws -> CollectionBatch? {
        lock.lock()
        defer { lock.unlock() }
        let url = pendingURL(for: id)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        do {
            return try decoder.decode(CollectionBatch.self, from: Data(contentsOf: url))
        } catch {
            throw HistoryStoreError.invalidHistoryData
        }
    }

    func loadPendingArtifact(_ id: UUID) throws -> CollectionBatch? {
        try loadPending(id)
    }

    func loadPendingArtifact(id: UUID) throws -> CollectionBatch? {
        try loadPending(id)
    }

    func deletePending(_ id: UUID) throws {
        lock.lock()
        defer { lock.unlock() }
        try removePendingUnlocked(id)
    }

    func deletePendingArtifact(_ id: UUID) throws {
        try deletePending(id)
    }

    /// Persists the successful summary and removes its raw pending artifact only after the history
    /// write succeeds. If the history write fails, the Pending file remains available for retry.
    @discardableResult
    func saveCompleted(
        batch: CollectionBatch,
        outcome: SummaryOutcome,
        replacingPendingID: UUID? = nil
    ) throws -> HistoryEntry {
        lock.lock()
        defer { lock.unlock() }
        var entries = try loadUnlocked()
        let existing = replacingPendingID.flatMap { pendingID in
            entries.first(where: { $0.pendingArtifactID == pendingID })
        }
        let entry = HistoryEntry(
            id: existing?.id ?? UUID(),
            interval: batch.interval,
            status: batch.sessions.isEmpty ? .empty : .completed,
            summary: outcome.document,
            provider: outcome.provider,
            fallbackUsed: outcome.fallbackUsed,
            sessionCount: batch.sessions.count,
            sources: sources(for: batch),
            collectionIssues: batch.issues,
            errorMessage: nil,
            pendingArtifactID: nil
        )
        if let existingIndex = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[existingIndex] = entry
        } else {
            entries.append(entry)
        }
        try writeHistory(entries)
        if let pendingID = replacingPendingID {
            try removePendingUnlocked(pendingID)
        }
        return entry
    }

    @discardableResult
    func completePending(
        pendingArtifactID: UUID,
        batch: CollectionBatch,
        outcome: SummaryOutcome
    ) throws -> HistoryEntry {
        try saveCompleted(batch: batch, outcome: outcome, replacingPendingID: pendingArtifactID)
    }

    func saveCompleted(
        batch: CollectionBatch,
        outcome: SummaryOutcome,
        pendingArtifactID: UUID?
    ) throws -> HistoryEntry {
        try saveCompleted(batch: batch, outcome: outcome, replacingPendingID: pendingArtifactID)
    }

    private func loadUnlocked() throws -> [HistoryEntry] {
        guard fileManager.fileExists(atPath: historyURL.path) else { return [] }
        do {
            let data = try Data(contentsOf: historyURL)
            return try decoder.decode([HistoryEntry].self, from: data)
                .sorted { $0.interval.end > $1.interval.end }
        } catch {
            throw HistoryStoreError.invalidHistoryData
        }
    }

    private func ensureDirectories() throws {
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: pendingDirectoryURL, withIntermediateDirectories: true)
    }

    private func writeHistory(_ entries: [HistoryEntry]) throws {
        try ensureDirectories()
        let data = try encoder.encode(entries.sorted { $0.interval.end > $1.interval.end })
        try data.write(to: historyURL, options: .atomic)
    }

    private func writePendingUnlocked(_ batch: CollectionBatch, id: UUID) throws {
        let data = try encoder.encode(batch)
        try data.write(to: pendingURL(for: id), options: .atomic)
    }

    private func removePendingUnlocked(_ id: UUID) throws {
        let url = pendingURL(for: id)
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }

    private func pendingURL(for id: UUID) -> URL {
        pendingDirectoryURL.appendingPathComponent("\(id.uuidString).json")
    }

    private func sources(for batch: CollectionBatch) -> [CLIKind] {
        Array(Set(batch.sessions.map(\.provider))).sorted { $0.rawValue < $1.rawValue }
    }

    private static func defaultDirectory(fileManager: FileManager) -> URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return appSupport.appendingPathComponent("CapsStack", isDirectory: true)
    }
}
