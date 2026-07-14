import Foundation

struct RecentForum: Codable, Equatable, Identifiable, Sendable {
    var name: String
    var displayName: String
    var avatarURL: URL?
    var updatedAt: Date

    var id: String { name.lowercased() }

    var forum: Forum {
        Forum(
            id: 0,
            name: name,
            displayName: displayName,
            avatarURL: avatarURL,
            memberCount: 0,
            threadCount: 0
        )
    }
}

@MainActor
final class RecentForumStore: ObservableObject {
    static let shared = RecentForumStore()

    private let key: String
    private let limit: Int
    private let defaults: UserDefaults
    private let now: () -> Date
    @Published private(set) var items: [RecentForum]

    init(
        defaults: UserDefaults = .standard,
        key: String = "dev.infinityf4p.tiebapure.recentForums",
        limit: Int = 30,
        now: @escaping () -> Date = Date.init
    ) {
        self.defaults = defaults
        self.key = key
        self.limit = limit
        self.now = now
        if let data = defaults.data(forKey: key) {
            items = (try? JSONDecoder().decode([RecentForum].self, from: data)) ?? []
        } else {
            items = []
        }
    }

    func reload() {
        guard let data = defaults.data(forKey: key) else {
            items = []
            return
        }
        items = (try? JSONDecoder().decode([RecentForum].self, from: data)) ?? []
    }

    func save(_ forum: Forum) {
        let recent = RecentForum(
            name: forum.name,
            displayName: forum.displayName,
            avatarURL: forum.avatarURL,
            updatedAt: now()
        )
        save(recent)
    }

    func save(name: String, displayName: String? = nil, avatarURL: URL? = nil) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return }

        save(RecentForum(
            name: trimmed,
            displayName: displayName ?? "\(trimmed)吧",
            avatarURL: avatarURL,
            updatedAt: now()
        ))
    }

    private func save(_ recent: RecentForum) {
        var updated = items.filter { $0.id != recent.id }
        updated.insert(recent, at: 0)
        if updated.count > limit {
            updated = Array(updated.prefix(limit))
        }
        if let data = try? JSONEncoder().encode(updated) {
            defaults.set(data, forKey: key)
            items = updated
        }
    }
}
