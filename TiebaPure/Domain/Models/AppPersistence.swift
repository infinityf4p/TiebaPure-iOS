import Foundation
import OSLog

enum PersistenceAvailability: Equatable, Sendable {
    case available
    case unavailable

    var canPersist: Bool {
        self == .available
    }
}

enum PersistenceFaultPoint: Equatable {
    case legacyMigration
    case repair
    case clearAll
}

struct PersistenceFaultInjector {
    static let none = PersistenceFaultInjector { _ in }

    private let handler: (PersistenceFaultPoint) throws -> Void

    init(_ handler: @escaping (PersistenceFaultPoint) throws -> Void) {
        self.handler = handler
    }

    func check(_ point: PersistenceFaultPoint) throws {
        try handler(point)
    }
}

struct PersistenceLoadResult<Value> {
    let value: Value
    let repairError: Error?
}

/// JSON-file persistence backend (iOS 16 compatible replacement for SwiftData).
enum AppJSONPersistence {
    static let sharedDirectory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("TiebaPure", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static func fileURL(for key: String) -> URL {
        sharedDirectory.appendingPathComponent("\(key).json")
    }

    static func load<T: Decodable>(_ type: T.Type, key: String) throws -> T? {
        let url = fileURL(for: key)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(T.self, from: data)
    }

    static func save<T: Encodable>(_ value: T, key: String) throws {
        let data = try JSONEncoder().encode(value)
        let url = fileURL(for: key)
        try data.write(to: url, options: [.atomic])
    }

    static func remove(key: String) {
        let url = fileURL(for: key)
        try? FileManager.default.removeItem(at: url)
    }
}

/// Compatibility shim. SwiftData was replaced by JSON file persistence for iOS 16.
/// Test helpers that still reference container APIs degrade to JSON availability checks.
enum AppModelContainer {
    struct Resolution {
        let availability: PersistenceAvailability
        /// Placeholder for former ModelContainer identity checks in tests.
        let containerToken: ObjectIdentifier?

        var isDurable: Bool {
            availability.canPersist
        }

        init(availability: PersistenceAvailability, containerToken: ObjectIdentifier? = nil) {
            self.availability = availability
            self.containerToken = containerToken
        }
    }

    /// Former SwiftData model list; retained empty so older tests compile against the symbol.
    static let models: [Any.Type] = []

    static let sharedAvailability: PersistenceAvailability = .available
    static let sharedResolution = Resolution(availability: .available)
    static let shared: Any? = nil

    static func persistenceAvailability() -> PersistenceAvailability {
        .available
    }

    static func persistenceAvailability(for _: Any?) -> PersistenceAvailability {
        .available
    }

    static func allowsLegacyCleanup(for _: Any? = nil) -> Bool {
        true
    }

    static func resolve(
        persistent: () throws -> Any,
        fallback: () throws -> Any
    ) throws -> Resolution {
        do {
            _ = try persistent()
            return Resolution(availability: .available)
        } catch {
            PersistenceDiagnostics.report(error, operation: "open persistent store")
            _ = try fallback()
            return Resolution(availability: .unavailable)
        }
    }
}

enum PersistenceDiagnostics {
    private static let logger = Logger(
        subsystem: "dev.infinityf4p.tiebapure",
        category: "Persistence"
    )

    static func report(_ error: Error, operation: String) {
        logger.error("\(operation, privacy: .public) failed: \(String(describing: error), privacy: .public)")
    }
}

enum LegacyStorageMigration {
    enum DecodeError: Error {
        case invalidTopLevelArray
    }

    static func persistThenRemoveLegacyValue(
        defaults: UserDefaults,
        key: String,
        destinationIsDurable: Bool,
        persist: () throws -> Void
    ) throws {
        try persist()
        guard destinationIsDurable else { return }
        defaults.removeObject(forKey: key)
    }
}

enum PersistedArrayDecoder {
    static func decode<T: Decodable>(_ type: T.Type, from data: Data) -> [T]? {
        if let values = try? JSONDecoder().decode([T].self, from: data) {
            return values
        }
        return nil
    }
}

/// JSON-backed ordered list store used by history / recent / search / reading position.
enum JSONRecordStore {
    static func loadArray<T: Codable>(key: String) throws -> [T] {
        try AppJSONPersistence.load([T].self, key: key) ?? []
    }

    static func saveArray<T: Codable>(_ values: [T], key: String) throws {
        try AppJSONPersistence.save(values, key: key)
    }

    static func clear(key: String) {
        AppJSONPersistence.remove(key: key)
    }
}

// MARK: - Codable record DTOs (replacing @Model classes)

struct ThreadReadingPositionRecordDTO: Codable, Equatable {
    var threadID: Int64
    var postIDBitPattern: Int64
    var floor: Int
    var updatedAt: Date
    var sortIndex: Int

    init(entry: ThreadReadingPosition, sortIndex: Int) {
        self.threadID = entry.threadID
        self.postIDBitPattern = Int64(bitPattern: entry.postID)
        self.floor = entry.floor
        self.updatedAt = entry.updatedAt
        self.sortIndex = sortIndex
    }

    var entry: ThreadReadingPosition {
        ThreadReadingPosition(
            threadID: threadID,
            postID: UInt64(bitPattern: postIDBitPattern),
            floor: floor,
            updatedAt: updatedAt
        )
    }
}

struct BrowsingHistoryRecordDTO: Codable, Equatable {
    var threadID: Int64
    var forumID: Int64?
    var title: String
    var authorDisplayName: String
    var forumDisplayName: String?
    var visitedAt: Date
    var sortIndex: Int

    init(entry: BrowsingHistoryEntry, sortIndex: Int) {
        self.threadID = entry.threadID
        self.forumID = entry.forumID
        self.title = entry.title
        self.authorDisplayName = entry.authorDisplayName
        self.forumDisplayName = entry.forumDisplayName
        self.visitedAt = entry.visitedAt
        self.sortIndex = sortIndex
    }

    var entry: BrowsingHistoryEntry {
        BrowsingHistoryEntry(
            threadID: threadID,
            forumID: forumID,
            title: title,
            authorDisplayName: authorDisplayName,
            forumDisplayName: forumDisplayName,
            visitedAt: visitedAt
        )
    }
}

struct RecentForumRecordDTO: Codable, Equatable {
    var name: String
    var displayName: String
    var avatarURL: URL?
    var updatedAt: Date
    var sortIndex: Int

    init(entry: RecentForum, sortIndex: Int) {
        self.name = entry.name
        self.displayName = entry.displayName
        self.avatarURL = entry.avatarURL
        self.updatedAt = entry.updatedAt
        self.sortIndex = sortIndex
    }

    var entry: RecentForum {
        RecentForum(
            name: name,
            displayName: displayName,
            avatarURL: avatarURL,
            updatedAt: updatedAt
        )
    }
}

struct SearchHistoryRecordDTO: Codable, Equatable {
    var keyword: String
    var sortIndex: Int
}

struct ContentDraftRecordDTO: Codable, Equatable {
    var accountID: String
    var targetKey: String
    var targetData: Data
    var title: String
    var body: String
    var imagesBlob: Data
    var imagesByteCount: Int?
    var updatedAt: Date
}

enum PersistedRecordStore {
    static let browsingHistoryKey = "browsingHistory"
    static let recentForumsKey = "recentForums"
    static let searchHistoryKey = "searchHistory"
    static let readingPositionsKey = "readingPositions"
    static let contentDraftsKey = "contentDrafts"
    static let threadFavoritesKey = "threadFavorites"

    static func loadBrowsingHistory() throws -> [BrowsingHistoryEntry] {
        let records: [BrowsingHistoryRecordDTO] = try JSONRecordStore.loadArray(key: browsingHistoryKey)
        return records.sorted { $0.sortIndex < $1.sortIndex }.map(\.entry)
    }

    static func saveBrowsingHistory(_ entries: [BrowsingHistoryEntry]) throws {
        let records = entries.enumerated().map {
            BrowsingHistoryRecordDTO(entry: $0.element, sortIndex: $0.offset)
        }
        try JSONRecordStore.saveArray(records, key: browsingHistoryKey)
    }

    static func loadRecentForums() throws -> [RecentForum] {
        let records: [RecentForumRecordDTO] = try JSONRecordStore.loadArray(key: recentForumsKey)
        return records.sorted { $0.sortIndex < $1.sortIndex }.map(\.entry)
    }

    static func saveRecentForums(_ entries: [RecentForum]) throws {
        let records = entries.enumerated().map {
            RecentForumRecordDTO(entry: $0.element, sortIndex: $0.offset)
        }
        try JSONRecordStore.saveArray(records, key: recentForumsKey)
    }

    static func loadSearchHistory() throws -> [String] {
        let records: [SearchHistoryRecordDTO] = try JSONRecordStore.loadArray(key: searchHistoryKey)
        return records.sorted { $0.sortIndex < $1.sortIndex }.map(\.keyword)
    }

    static func saveSearchHistory(_ keywords: [String]) throws {
        let records = keywords.enumerated().map {
            SearchHistoryRecordDTO(keyword: $0.element, sortIndex: $0.offset)
        }
        try JSONRecordStore.saveArray(records, key: searchHistoryKey)
    }

    static func loadReadingPositions() throws -> [ThreadReadingPosition] {
        let records: [ThreadReadingPositionRecordDTO] = try JSONRecordStore.loadArray(key: readingPositionsKey)
        return records.sorted { $0.sortIndex < $1.sortIndex }.map(\.entry)
    }

    static func saveReadingPositions(_ entries: [ThreadReadingPosition]) throws {
        let records = entries.enumerated().map {
            ThreadReadingPositionRecordDTO(entry: $0.element, sortIndex: $0.offset)
        }
        try JSONRecordStore.saveArray(records, key: readingPositionsKey)
    }

    static func upsertReadingPosition(_ position: ThreadReadingPosition, limit: Int) throws {
        let effectiveLimit = min(max(limit, 0), 500)
        var entries = try loadReadingPositions()
        entries.removeAll { $0.threadID == position.threadID }
        entries.insert(position, at: 0)
        if entries.count > effectiveLimit {
            entries = Array(entries.prefix(effectiveLimit))
        }
        try saveReadingPositions(entries)
    }

    static func deleteReadingPosition(threadID: Int64) throws {
        var entries = try loadReadingPositions()
        entries.removeAll { $0.threadID == threadID }
        try saveReadingPositions(entries)
    }

    static func clearThreadLibrary() throws {
        JSONRecordStore.clear(key: threadFavoritesKey)
        JSONRecordStore.clear(key: readingPositionsKey)
    }

    static func loadContentDrafts() throws -> [ContentDraftRecordDTO] {
        try JSONRecordStore.loadArray(key: contentDraftsKey)
    }

    static func saveContentDrafts(_ drafts: [ContentDraftRecordDTO]) throws {
        try JSONRecordStore.saveArray(drafts, key: contentDraftsKey)
    }
}
