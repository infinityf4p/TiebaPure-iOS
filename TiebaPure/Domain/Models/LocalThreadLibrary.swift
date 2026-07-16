import Foundation

struct ThreadFavoriteEntry: Codable, Equatable, Identifiable, Sendable {
    var threadID: Int64
    var forumID: Int64?
    var title: String
    var authorDisplayName: String
    var forumDisplayName: String?
    var savedAt: Date

    var id: Int64 { threadID }
}

struct ThreadReadingPosition: Codable, Equatable, Identifiable, Sendable {
    var threadID: Int64
    var postID: UInt64
    var floor: Int
    var updatedAt: Date

    var id: Int64 { threadID }
}

enum LocalThreadLibraryPolicy {
    static let maximumFavoriteEntries = 500
    static let maximumReadingPositions = 500

    static func favorite(
        for thread: ThreadSummary,
        forum: Forum?,
        fallbackForumID: Int64?,
        savedAt: Date
    ) -> ThreadFavoriteEntry? {
        guard let reference = BrowsingHistoryPolicy.entry(
            for: thread,
            forum: forum,
            fallbackForumID: fallbackForumID,
            visitedAt: savedAt
        ) else { return nil }

        return ThreadFavoriteEntry(
            threadID: reference.threadID,
            forumID: reference.forumID,
            title: reference.title,
            authorDisplayName: reference.authorDisplayName,
            forumDisplayName: reference.forumDisplayName,
            savedAt: savedAt
        )
    }

    static func addingFavorite(
        _ favorite: ThreadFavoriteEntry,
        to favorites: [ThreadFavoriteEntry],
        limit: Int
    ) -> [ThreadFavoriteEntry] {
        guard limit > 0 else { return [] }
        var updated = favorites.filter { $0.threadID != favorite.threadID }
        updated.insert(favorite, at: 0)
        return Array(updated.prefix(limit))
    }

    static func removingFavorites(
        threadIDs: Set<Int64>,
        from favorites: [ThreadFavoriteEntry]
    ) -> [ThreadFavoriteEntry] {
        favorites.filter { threadIDs.contains($0.threadID) == false }
    }

    static func sanitizedFavorites(
        _ favorites: [ThreadFavoriteEntry],
        limit: Int
    ) -> [ThreadFavoriteEntry] {
        guard limit > 0 else { return [] }
        var seenThreadIDs = Set<Int64>()
        var result: [ThreadFavoriteEntry] = []

        for favorite in favorites.sorted(by: { $0.savedAt > $1.savedAt }) where favorite.threadID > 0 {
            guard seenThreadIDs.insert(favorite.threadID).inserted else { continue }
            let title = normalized(favorite.title, maximumLength: 200)
            let author = normalized(favorite.authorDisplayName, maximumLength: 80)
            let forum = favorite.forumDisplayName.map { normalized($0, maximumLength: 80) }
            result.append(ThreadFavoriteEntry(
                threadID: favorite.threadID,
                forumID: favorite.forumID.flatMap { $0 > 0 ? $0 : nil },
                title: title.isEmpty ? "帖子 \(favorite.threadID)" : title,
                authorDisplayName: author.isEmpty ? "未知用户" : author,
                forumDisplayName: forum?.isEmpty == false ? forum : nil,
                savedAt: favorite.savedAt
            ))
            if result.count == limit { break }
        }

        return result
    }

    static func readingPosition(
        threadID: Int64,
        postID: UInt64,
        floor: Int,
        updatedAt: Date
    ) -> ThreadReadingPosition? {
        guard threadID > 0, postID > 0, floor > 1 else { return nil }
        return ThreadReadingPosition(
            threadID: threadID,
            postID: postID,
            floor: floor,
            updatedAt: updatedAt
        )
    }

    static func addingReadingPosition(
        _ position: ThreadReadingPosition,
        to positions: [ThreadReadingPosition],
        limit: Int
    ) -> [ThreadReadingPosition] {
        guard limit > 0 else { return [] }
        var updated = positions.filter { $0.threadID != position.threadID }
        updated.insert(position, at: 0)
        return Array(updated.prefix(limit))
    }

    static func sanitizedReadingPositions(
        _ positions: [ThreadReadingPosition],
        limit: Int
    ) -> [ThreadReadingPosition] {
        guard limit > 0 else { return [] }
        var seenThreadIDs = Set<Int64>()
        var result: [ThreadReadingPosition] = []

        for position in positions.sorted(by: { $0.updatedAt > $1.updatedAt }) {
            guard position.threadID > 0,
                  position.postID > 0,
                  position.floor > 1,
                  seenThreadIDs.insert(position.threadID).inserted else { continue }
            result.append(position)
            if result.count == limit { break }
        }

        return result
    }

    private static func normalized(_ value: String, maximumLength: Int) -> String {
        let collapsed = value
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { $0.isEmpty == false }
            .joined(separator: " ")
        return String(collapsed.prefix(maximumLength))
    }
}

@MainActor
final class LocalThreadLibraryStore: ObservableObject {
    static let shared = LocalThreadLibraryStore()

    private let defaults: UserDefaults
    private let favoritesKey: String
    private let readingPositionsKey: String
    private let favoriteLimit: Int
    private let readingPositionLimit: Int
    private let now: () -> Date

    @Published private(set) var favorites: [ThreadFavoriteEntry]
    @Published private(set) var readingPositions: [ThreadReadingPosition]

    init(
        defaults: UserDefaults = .standard,
        favoritesKey: String = "dev.infinityf4p.tiebapure.threadFavorites",
        readingPositionsKey: String = "dev.infinityf4p.tiebapure.threadReadingPositions",
        favoriteLimit: Int = LocalThreadLibraryPolicy.maximumFavoriteEntries,
        readingPositionLimit: Int = LocalThreadLibraryPolicy.maximumReadingPositions,
        now: @escaping () -> Date = Date.init
    ) {
        self.defaults = defaults
        self.favoritesKey = favoritesKey
        self.readingPositionsKey = readingPositionsKey
        self.favoriteLimit = max(favoriteLimit, 0)
        self.readingPositionLimit = max(readingPositionLimit, 0)
        self.now = now
        favorites = Self.loadFavorites(
            defaults: defaults,
            key: favoritesKey,
            limit: max(favoriteLimit, 0)
        )
        readingPositions = Self.loadReadingPositions(
            defaults: defaults,
            key: readingPositionsKey,
            limit: max(readingPositionLimit, 0)
        )
    }

    func reload() {
        favorites = Self.loadFavorites(defaults: defaults, key: favoritesKey, limit: favoriteLimit)
        readingPositions = Self.loadReadingPositions(
            defaults: defaults,
            key: readingPositionsKey,
            limit: readingPositionLimit
        )
    }

    func isFavorite(threadID: Int64) -> Bool {
        favorites.contains { $0.threadID == threadID }
    }

    @discardableResult
    func toggleFavorite(
        thread: ThreadSummary,
        forum: Forum? = nil,
        fallbackForumID: Int64? = nil
    ) -> Bool {
        if isFavorite(threadID: thread.id) {
            removeFavorites(threadIDs: [thread.id])
            return false
        }
        addFavorite(thread: thread, forum: forum, fallbackForumID: fallbackForumID)
        return isFavorite(threadID: thread.id)
    }

    func addFavorite(
        thread: ThreadSummary,
        forum: Forum? = nil,
        fallbackForumID: Int64? = nil
    ) {
        guard let favorite = LocalThreadLibraryPolicy.favorite(
            for: thread,
            forum: forum,
            fallbackForumID: fallbackForumID,
            savedAt: now()
        ) else { return }
        persistFavorites(LocalThreadLibraryPolicy.addingFavorite(
            favorite,
            to: favorites,
            limit: favoriteLimit
        ))
    }

    func refreshFavoriteMetadata(
        thread: ThreadSummary,
        forum: Forum? = nil,
        fallbackForumID: Int64? = nil
    ) {
        guard let index = favorites.firstIndex(where: { $0.threadID == thread.id }),
              let refreshed = LocalThreadLibraryPolicy.favorite(
                for: thread,
                forum: forum,
                fallbackForumID: fallbackForumID,
                savedAt: favorites[index].savedAt
              ),
              refreshed != favorites[index] else { return }
        var updated = favorites
        updated[index] = refreshed
        persistFavorites(updated)
    }

    func removeFavorites(threadIDs: Set<Int64>) {
        guard threadIDs.isEmpty == false else { return }
        persistFavorites(LocalThreadLibraryPolicy.removingFavorites(
            threadIDs: threadIDs,
            from: favorites
        ))
    }

    func clearFavorites() {
        defaults.removeObject(forKey: favoritesKey)
        favorites = []
    }

    func position(for threadID: Int64) -> ThreadReadingPosition? {
        readingPositions.first { $0.threadID == threadID }
    }

    func recordReadingPosition(threadID: Int64, postID: UInt64, floor: Int) {
        guard let position = LocalThreadLibraryPolicy.readingPosition(
            threadID: threadID,
            postID: postID,
            floor: floor,
            updatedAt: now()
        ) else { return }
        if let current = self.position(for: threadID),
           current.postID == postID,
           current.floor == floor {
            return
        }
        persistReadingPositions(LocalThreadLibraryPolicy.addingReadingPosition(
            position,
            to: readingPositions,
            limit: readingPositionLimit
        ))
    }

    func clearReadingPosition(threadID: Int64) {
        guard readingPositions.contains(where: { $0.threadID == threadID }) else { return }
        persistReadingPositions(readingPositions.filter { $0.threadID != threadID })
    }

    func clearReadingPositions() {
        defaults.removeObject(forKey: readingPositionsKey)
        readingPositions = []
    }

    func clearAll() {
        clearFavorites()
        clearReadingPositions()
    }

    private func persistFavorites(_ updated: [ThreadFavoriteEntry]) {
        guard updated.isEmpty == false else {
            clearFavorites()
            return
        }
        guard let data = try? JSONEncoder().encode(updated) else { return }
        defaults.set(data, forKey: favoritesKey)
        favorites = updated
    }

    private func persistReadingPositions(_ updated: [ThreadReadingPosition]) {
        guard updated.isEmpty == false else {
            defaults.removeObject(forKey: readingPositionsKey)
            readingPositions = []
            return
        }
        guard let data = try? JSONEncoder().encode(updated) else { return }
        defaults.set(data, forKey: readingPositionsKey)
        readingPositions = updated
    }

    private static func loadFavorites(
        defaults: UserDefaults,
        key: String,
        limit: Int
    ) -> [ThreadFavoriteEntry] {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([ThreadFavoriteEntry].self, from: data) else {
            return []
        }
        return LocalThreadLibraryPolicy.sanitizedFavorites(decoded, limit: limit)
    }

    private static func loadReadingPositions(
        defaults: UserDefaults,
        key: String,
        limit: Int
    ) -> [ThreadReadingPosition] {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([ThreadReadingPosition].self, from: data) else {
            return []
        }
        return LocalThreadLibraryPolicy.sanitizedReadingPositions(decoded, limit: limit)
    }
}
