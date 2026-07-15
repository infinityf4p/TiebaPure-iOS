import Foundation

struct BrowsingHistoryEntry: Codable, Equatable, Identifiable, Sendable {
    var threadID: Int64
    var forumID: Int64?
    var title: String
    var authorDisplayName: String
    var forumDisplayName: String?
    var visitedAt: Date

    var id: Int64 { threadID }
}

enum BrowsingHistoryPolicy {
    static let maximumStoredEntries = 500
    private static let maximumTitleLength = 200
    private static let maximumNameLength = 80

    static func entry(
        for thread: ThreadSummary,
        forum: Forum?,
        fallbackForumID: Int64?,
        visitedAt: Date
    ) -> BrowsingHistoryEntry? {
        guard thread.id > 0 else { return nil }

        let resolvedForumID = [thread.forumID, forum?.id, fallbackForumID]
            .compactMap { $0 }
            .first(where: { $0 > 0 })
        let resolvedTitle = normalizedText(
            thread.title.isEmpty ? thread.textPreview : thread.title,
            maximumLength: maximumTitleLength
        )
        let title = resolvedTitle.isEmpty ? "帖子 \(thread.id)" : resolvedTitle
        let author = normalizedText(
            thread.author.displayNameResolved,
            maximumLength: maximumNameLength
        )

        return BrowsingHistoryEntry(
            threadID: thread.id,
            forumID: resolvedForumID,
            title: title,
            authorDisplayName: author.isEmpty ? "未知用户" : author,
            forumDisplayName: resolvedForumDisplayName(thread: thread, forum: forum),
            visitedAt: visitedAt
        )
    }

    static func adding(
        _ entry: BrowsingHistoryEntry,
        to items: [BrowsingHistoryEntry],
        limit: Int
    ) -> [BrowsingHistoryEntry] {
        guard limit > 0 else { return [] }
        var updated = items.filter { $0.threadID != entry.threadID }
        updated.insert(entry, at: 0)
        return Array(updated.prefix(limit))
    }

    static func removing(
        threadIDs: Set<Int64>,
        from items: [BrowsingHistoryEntry]
    ) -> [BrowsingHistoryEntry] {
        items.filter { threadIDs.contains($0.threadID) == false }
    }

    static func sanitized(
        _ items: [BrowsingHistoryEntry],
        limit: Int
    ) -> [BrowsingHistoryEntry] {
        guard limit > 0 else { return [] }
        var seenThreadIDs = Set<Int64>()
        var result: [BrowsingHistoryEntry] = []

        for item in items where item.threadID > 0 {
            guard seenThreadIDs.insert(item.threadID).inserted else { continue }
            let cleanedTitle = normalizedText(item.title, maximumLength: maximumTitleLength)
            let cleanedAuthor = normalizedText(item.authorDisplayName, maximumLength: maximumNameLength)
            let cleanedForum = item.forumDisplayName.map {
                normalizedText($0, maximumLength: maximumNameLength)
            }
            result.append(BrowsingHistoryEntry(
                threadID: item.threadID,
                forumID: item.forumID.flatMap { $0 > 0 ? $0 : nil },
                title: cleanedTitle.isEmpty ? "帖子 \(item.threadID)" : cleanedTitle,
                authorDisplayName: cleanedAuthor.isEmpty ? "未知用户" : cleanedAuthor,
                forumDisplayName: cleanedForum?.isEmpty == false ? cleanedForum : nil,
                visitedAt: item.visitedAt
            ))
            if result.count == limit { break }
        }

        return result
    }

    private static func resolvedForumDisplayName(
        thread: ThreadSummary,
        forum: Forum?
    ) -> String? {
        if let displayName = thread.forumDisplayNameResolved {
            return normalizedText(displayName, maximumLength: maximumNameLength)
        }
        guard let forum else { return nil }
        let displayName = normalizedText(forum.displayName, maximumLength: maximumNameLength)
        if displayName.isEmpty == false { return displayName }
        let name = normalizedText(forum.name, maximumLength: maximumNameLength)
        guard name.isEmpty == false else { return nil }
        return name.hasSuffix("吧") ? name : "\(name)吧"
    }

    private static func normalizedText(_ value: String, maximumLength: Int) -> String {
        let collapsed = value
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { $0.isEmpty == false }
            .joined(separator: " ")
        return String(collapsed.prefix(maximumLength))
    }
}

@MainActor
final class BrowsingHistoryStore: ObservableObject {
    static let shared = BrowsingHistoryStore()

    private let defaults: UserDefaults
    private let key: String
    private let limit: Int
    private let now: () -> Date
    @Published private(set) var items: [BrowsingHistoryEntry]

    init(
        defaults: UserDefaults = .standard,
        key: String = "dev.infinityf4p.tiebapure.browsingHistory",
        limit: Int = BrowsingHistoryPolicy.maximumStoredEntries,
        now: @escaping () -> Date = Date.init
    ) {
        self.defaults = defaults
        self.key = key
        self.limit = max(limit, 0)
        self.now = now
        items = Self.loadItems(defaults: defaults, key: key, limit: max(limit, 0))
    }

    func reload() {
        items = Self.loadItems(defaults: defaults, key: key, limit: limit)
    }

    func record(
        thread: ThreadSummary,
        forum: Forum? = nil,
        fallbackForumID: Int64? = nil
    ) {
        guard let entry = BrowsingHistoryPolicy.entry(
            for: thread,
            forum: forum,
            fallbackForumID: fallbackForumID,
            visitedAt: now()
        ) else { return }
        persist(BrowsingHistoryPolicy.adding(entry, to: items, limit: limit))
    }

    func remove(threadIDs: Set<Int64>) {
        guard threadIDs.isEmpty == false else { return }
        persist(BrowsingHistoryPolicy.removing(threadIDs: threadIDs, from: items))
    }

    func clear() {
        defaults.removeObject(forKey: key)
        items = []
    }

    private func persist(_ updated: [BrowsingHistoryEntry]) {
        guard updated.isEmpty == false else {
            clear()
            return
        }
        guard let data = try? JSONEncoder().encode(updated) else { return }
        defaults.set(data, forKey: key)
        items = updated
    }

    private static func loadItems(
        defaults: UserDefaults,
        key: String,
        limit: Int
    ) -> [BrowsingHistoryEntry] {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([BrowsingHistoryEntry].self, from: data) else {
            return []
        }
        return BrowsingHistoryPolicy.sanitized(decoded, limit: limit)
    }
}
