import Combine
import Foundation

enum BlocklistEntryKind: String, Codable, CaseIterable, Sendable {
    case keyword
    case user
    case forum
}

struct BlocklistEntry: Codable, Equatable, Identifiable, Sendable {
    var kind: BlocklistEntryKind
    // Keyword text, user display name, or forum name depending on kind.
    var value: String
    // User entries added from a profile carry the account id; manual entries
    // stay name-only and match by display name.
    var userID: Int64?
    // Forum entries created from a feed can still be precise when that
    // endpoint omits forum_name. Optional keeps old persisted JSON compatible.
    var forumID: Int64? = nil

    static func forumIDOnlyDisplayValue(_ forumID: Int64) -> String {
        "贴吧 ID \(forumID)"
    }

    var forumNameForMatching: String? {
        guard kind == .forum else { return nil }
        let normalized = TiebaForumName.normalized(value)
        guard normalized.isEmpty == false else { return nil }
        if let forumID,
           normalized == TiebaForumName.normalized(Self.forumIDOnlyDisplayValue(forumID)) {
            return nil
        }
        return normalized
    }

    // Doubles as the dedupe key: one entry per case-folded keyword or forum
    // name, per user id, or per normalized name for name-only user entries.
    var id: String {
        switch kind {
        case .keyword:
            return "keyword:\(value.lowercased())"
        case .forum:
            if let forumID, forumID > 0 {
                return "forum:id:\(forumID)"
            }
            return "forum:name:\(TiebaForumName.normalized(value))"
        case .user:
            if let userID {
                return "user:id:\(userID)"
            }
            return "user:name:\(TiebaUserName.normalized(value))"
        }
    }
}

enum BlocklistPolicy {
    static let maximumEntriesPerKind = 200
    static let maximumKeywordCharacters = 200
    static let maximumUserNameCharacters = 100
    static let maximumForumNameCharacters = 100

    static func normalized(_ entry: BlocklistEntry) -> BlocklistEntry? {
        var normalized = entry
        switch entry.kind {
        case .forum:
            normalized.userID = nil
            if let forumID = entry.forumID, forumID > 0 {
                normalized.forumID = forumID
            } else {
                normalized.forumID = nil
            }
            let name = entry.forumNameForMatching
            if let name, name.isEmpty == false {
                normalized.value = name
            } else if let forumID = normalized.forumID {
                // BlocklistSettingsView displays `value` directly, so retain a
                // readable label even for a rule whose only identity is FID.
                normalized.value = BlocklistEntry.forumIDOnlyDisplayValue(forumID)
            } else {
                normalized.value = ""
            }
        case .keyword, .user:
            normalized.value = entry.value.trimmingCharacters(in: .whitespacesAndNewlines)
            normalized.forumID = nil
        }
        let characterLimit: Int
        switch normalized.kind {
        case .keyword:
            characterLimit = maximumKeywordCharacters
        case .user:
            characterLimit = maximumUserNameCharacters
        case .forum:
            characterLimit = maximumForumNameCharacters
        }
        normalized.value = String(normalized.value.prefix(characterLimit))
        if normalized.kind != .user { normalized.userID = nil }
        if let userID = normalized.userID, userID <= 0 {
            normalized.userID = nil
        }
        guard normalized.value.isEmpty == false else { return nil }
        return normalized
    }

    static func sanitized(
        _ entries: [BlocklistEntry],
        limitPerKind: Int = maximumEntriesPerKind
    ) -> [BlocklistEntry] {
        guard limitPerKind > 0 else { return [] }
        var seenIDs = Set<String>()
        var countsByKind: [BlocklistEntryKind: Int] = [:]
        var result: [BlocklistEntry] = []
        for entry in entries {
            guard let entry = normalized(entry),
                  seenIDs.insert(entry.id).inserted,
                  countsByKind[entry.kind, default: 0] < limitPerKind else { continue }
            countsByKind[entry.kind, default: 0] += 1
            result.append(entry)
        }
        return result
    }
}

enum BlocklistPersistence {
    static let defaultKey = "dev.infinityf4p.tiebapure.blocklist"

    static func loadEntries(
        defaults: UserDefaults = .standard,
        key: String = defaultKey,
        limitPerKind: Int = BlocklistPolicy.maximumEntriesPerKind
    ) -> [BlocklistEntry] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return BlocklistPolicy.sanitized(
            PersistedArrayDecoder.decode(BlocklistEntry.self, from: data) ?? [],
            limitPerKind: limitPerKind
        )
    }
}

extension BlocklistSnapshot {
    init(entries: [BlocklistEntry]) {
        var keywords = Set<String>()
        var userIDs = Set<Int64>()
        var userNames = Set<String>()
        var forumIDs = Set<Int64>()
        var forumNames = Set<String>()
        for entry in entries {
            switch entry.kind {
            case .keyword:
                let keyword = entry.value.lowercased()
                if keyword.isEmpty == false { keywords.insert(keyword) }
            case .user:
                if let userID = entry.userID, userID > 0 {
                    userIDs.insert(userID)
                }
                // Keep the normalized name as a fallback even for precise
                // UID-backed entries. Some legacy endpoints omit the UID, and
                // otherwise the same blocked account could reappear there.
                let name = TiebaUserName.normalized(entry.value)
                if name.isEmpty == false { userNames.insert(name) }
            case .forum:
                if let forumID = entry.forumID, forumID > 0 {
                    forumIDs.insert(forumID)
                }
                if let name = entry.forumNameForMatching, name.isEmpty == false {
                    forumNames.insert(name)
                }
            }
        }
        self.init(
            keywords: keywords,
            userIDs: userIDs,
            userNames: userNames,
            forumIDs: forumIDs,
            forumNames: forumNames
        )
    }
}

@MainActor
final class BlocklistStore: ObservableObject {
    static let shared = BlocklistStore()

    private let defaults: UserDefaults
    private let key: String
    private let limitPerKind: Int
    private let publishSnapshot: (BlocklistSnapshot) -> Void

    @Published private(set) var entries: [BlocklistEntry]

    init(
        defaults: UserDefaults = .standard,
        key: String = BlocklistPersistence.defaultKey,
        limitPerKind: Int = BlocklistPolicy.maximumEntriesPerKind,
        publishSnapshot: @escaping (BlocklistSnapshot) -> Void = TiebaContentFilter.updateBlocklist
    ) {
        self.defaults = defaults
        self.key = key
        self.limitPerKind = max(limitPerKind, 0)
        self.publishSnapshot = publishSnapshot
        entries = BlocklistPersistence.loadEntries(
            defaults: defaults,
            key: key,
            limitPerKind: max(limitPerKind, 0)
        )
        publishSnapshot(BlocklistSnapshot(entries: entries))
    }

    func reload() {
        entries = BlocklistPersistence.loadEntries(
            defaults: defaults,
            key: key,
            limitPerKind: limitPerKind
        )
        publishSnapshot(BlocklistSnapshot(entries: entries))
    }

    func entries(of kind: BlocklistEntryKind) -> [BlocklistEntry] {
        entries.filter { $0.kind == kind }
    }

    func addKeyword(_ keyword: String) {
        add(BlocklistEntry(kind: .keyword, value: keyword, userID: nil))
    }

    func addForum(named name: String) {
        addForum(id: nil, named: name)
    }

    func addForum(id: Int64?, named name: String?) {
        add(
            BlocklistEntry(
                kind: .forum,
                value: name ?? "",
                userID: nil,
                forumID: id
            )
        )
    }

    func addUser(id: Int64?, displayName: String) {
        add(BlocklistEntry(kind: .user, value: displayName, userID: id))
    }

    func isUserBlocked(id: Int64, displayName: String) -> Bool {
        matchingUserEntryIDs(id: id, displayName: displayName).isEmpty == false
    }

    @discardableResult
    func toggleUser(id: Int64, displayName: String) -> Bool {
        let matches = matchingUserEntryIDs(id: id, displayName: displayName)
        guard matches.isEmpty else {
            remove(ids: matches)
            return false
        }
        add(BlocklistEntry(kind: .user, value: displayName, userID: id > 0 ? id : nil))
        return isUserBlocked(id: id, displayName: displayName)
    }

    func remove(_ entry: BlocklistEntry) {
        remove(ids: [entry.id])
    }

    func remove(ids: Set<String>) {
        guard ids.isEmpty == false else { return }
        let updated = entries.filter { ids.contains($0.id) == false }
        guard updated.count != entries.count else { return }
        persist(updated)
    }

    func clear(kind: BlocklistEntryKind) {
        let updated = entries.filter { $0.kind != kind }
        guard updated.count != entries.count else { return }
        persist(updated)
    }

    private func add(_ entry: BlocklistEntry) {
        guard let entry = BlocklistPolicy.normalized(entry) else { return }
        var updated = entries.filter { existing in
            if existing.id == entry.id { return false }
            guard entry.kind == .forum,
                  existing.kind == .forum else { return true }
            if let forumID = entry.forumID,
               let existingForumID = existing.forumID,
               forumID > 0,
               forumID == existingForumID {
                return false
            }
            guard let forumName = entry.forumNameForMatching,
                  let existingForumName = existing.forumNameForMatching else {
                return true
            }
            return forumName != existingForumName
        }
        updated.insert(entry, at: 0)
        persist(BlocklistPolicy.sanitized(updated, limitPerKind: limitPerKind))
    }

    private func matchingUserEntryIDs(id: Int64, displayName: String) -> Set<String> {
        let normalizedName = TiebaUserName.normalized(displayName)
        return Set(entries.compactMap { entry -> String? in
            guard entry.kind == .user else { return nil }
            if let userID = entry.userID {
                if id > 0 && userID == id {
                    return entry.id
                }
            }
            guard normalizedName.isEmpty == false else { return nil }
            return TiebaUserName.normalized(entry.value) == normalizedName ? entry.id : nil
        })
    }

    private func persist(_ updated: [BlocklistEntry]) {
        if updated.isEmpty {
            defaults.removeObject(forKey: key)
            entries = []
        } else {
            guard let data = try? JSONEncoder().encode(updated) else { return }
            defaults.set(data, forKey: key)
            entries = updated
        }
        publishSnapshot(BlocklistSnapshot(entries: entries))
    }
}
