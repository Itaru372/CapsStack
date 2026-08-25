import Foundation

enum CLIHistoryError: LocalizedError, Equatable {
    case unreadable(URL)
    case entryNotFound(UUID)
    case noEntries

    var errorDescription: String? {
        switch self {
        case .unreadable(let url):
            "CapsStackの履歴ファイルを読み取れません: \(url.path)"
        case .entryNotFound(let id):
            "履歴が見つかりません: \(id.uuidString)"
        case .noEntries:
            "履歴はまだありません。"
        }
    }
}

struct CLIHistoryRepository {
    let historyURL: URL
    private let fileManager: FileManager
    private let decoder: JSONDecoder

    init(historyURL: URL = Self.defaultHistoryURL(), fileManager: FileManager = .default) {
        self.historyURL = historyURL
        self.fileManager = fileManager
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    var exists: Bool {
        fileManager.fileExists(atPath: historyURL.path)
    }

    func load() throws -> [CLIHistoryEntry] {
        guard exists else { return [] }
        do {
            let data = try Data(contentsOf: historyURL)
            return try decoder.decode([CLIHistoryEntry].self, from: data)
                .sorted { $0.interval.end > $1.interval.end }
        } catch {
            throw CLIHistoryError.unreadable(historyURL)
        }
    }

    func latest() throws -> CLIHistoryEntry {
        guard let entry = try load().first else { throw CLIHistoryError.noEntries }
        return entry
    }

    func entry(id: UUID) throws -> CLIHistoryEntry {
        guard let entry = try load().first(where: { $0.id == id }) else {
            throw CLIHistoryError.entryNotFound(id)
        }
        return entry
    }

    static func defaultHistoryURL(fileManager: FileManager = .default) -> URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return appSupport
            .appendingPathComponent("CapsStack", isDirectory: true)
            .appendingPathComponent("history.json")
    }
}
