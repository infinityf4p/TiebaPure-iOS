import Foundation

struct RecentForum: Codable, Equatable, Identifiable, Sendable {
    var name: String
    var displayName: String
    var avatarURL: URL?
    var updatedAt: Date

    var id: String { name.lowercased() }

    init(
        name: String,
        displayName: String,
        avatarURL: URL? = nil,
        updatedAt: Date
    ) {
        self.name = name
        self.displayName = displayName
        self.avatarURL = avatarURL
        self.updatedAt = updatedAt
    }

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

enum RecentForumPolicy {
    static let maximumStoredEntries = 30
    private static let maximumNameLength = 80

    static func sanitized(_ items: [RecentForum], limit: Int) -> [RecentForum] {
        let effectiveLimit = min(max(limit, 0), maximumStoredEntries)
        guard effectiveLimit > 0 else { return [] }
        var seenIDs = Set<String>()
        var result: [RecentForum] = []

        let ordered = items.sorted {
            if $0.updatedAt != $1.updatedAt {
                return $0.updatedAt > $1.updatedAt
            }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        for item in ordered where item.updatedAt.timeIntervalSinceReferenceDate.isFinite {
            let name = normalized(item.name)
            guard name.isEmpty == false else { continue }
            let id = name.lowercased()
            guard seenIDs.insert(id).inserted else { continue }
            let displayName = normalized(item.displayName)
            result.append(RecentForum(
                name: name,
                displayName: displayName.isEmpty ? "\(name)吧" : displayName,
                avatarURL: sanitizedAvatarURL(item.avatarURL),
                updatedAt: item.updatedAt
            ))
            if result.count == effectiveLimit { break }
        }
        return result
    }

    private static func normalized(_ value: String) -> String {
        let collapsed = value
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { $0.isEmpty == false }
            .joined(separator: " ")
        return String(collapsed.prefix(maximumNameLength))
    }

    private static func sanitizedAvatarURL(_ url: URL?) -> URL? {
        guard let url, url.scheme?.lowercased() == "https" else {
            return nil
        }
        return TiebaURL.image(url.absoluteString)
    }
}

@MainActor
final class RecentForumStore: ObservableObject {
    static let shared = RecentForumStore()

    private let key: String
    private let limit: Int
    private let defaults: UserDefaults
    private let now: () -> Date
    private let persistentBackendIsAvailable: Bool
    private let faultInjector: PersistenceFaultInjector
    @Published private(set) var items: [RecentForum]
    @Published private(set) var persistenceAvailability: PersistenceAvailability

    init(
        defaults: UserDefaults = .standard,
        key: String = "dev.infinityf4p.tiebapure.recentForums",
        limit: Int = RecentForumPolicy.maximumStoredEntries,
        persistenceAvailability: PersistenceAvailability? = nil,
        faultInjector: PersistenceFaultInjector = .none,
        now: @escaping () -> Date = Date.init
    ) {
        self.defaults = defaults
        self.key = key
        self.limit = min(max(limit, 0), RecentForumPolicy.maximumStoredEntries)
        self.now = now
        self.faultInjector = faultInjector
        let initialAvailability = persistenceAvailability ?? .available
        persistentBackendIsAvailable = initialAvailability.canPersist
        self.persistenceAvailability = initialAvailability
        var legacyFallback: [RecentForum]?
        var migrationFailed = false
        do {
            try Self.migrateLegacyStorage(
                defaults: defaults,
                key: key,
                limit: self.limit,
                destinationIsDurable: initialAvailability.canPersist,
                legacyFallback: &legacyFallback,
                faultInjector: faultInjector
            )
        } catch {
            PersistenceDiagnostics.report(error, operation: "migrate recent forums")
            self.persistenceAvailability = .unavailable
            migrationFailed = true
        }
        do {
            let result = try Self.loadAndRepairItems(
                limit: self.limit,
                canRepair: persistentBackendIsAvailable,
                faultInjector: faultInjector
            )
            items = result.value
            if let error = result.repairError {
                PersistenceDiagnostics.report(error, operation: "repair recent forums")
                self.persistenceAvailability = .unavailable
            }
        } catch {
            PersistenceDiagnostics.report(error, operation: "load recent forums")
            items = migrationFailed ? (legacyFallback ?? []) : []
            self.persistenceAvailability = .unavailable
        }
        if migrationFailed, items.isEmpty, let legacyFallback {
            items = legacyFallback
        }
    }

    @discardableResult
    func reload() -> Bool {
        do {
            let result = try Self.loadAndRepairItems(
                limit: limit,
                canRepair: persistentBackendIsAvailable,
                faultInjector: faultInjector
            )
            items = result.value
            if let error = result.repairError {
                PersistenceDiagnostics.report(error, operation: "repair recent forums")
                persistenceAvailability = .unavailable
                return false
            }
            markPersistenceSucceeded()
            return true
        } catch {
            PersistenceDiagnostics.report(error, operation: "reload recent forums")
            persistenceAvailability = .unavailable
            return false
        }
    }

    @discardableResult
    func save(_ forum: Forum) -> Bool {
        save(RecentForum(
            name: forum.name,
            displayName: forum.displayName,
            avatarURL: forum.avatarURL,
            updatedAt: now()
        ))
    }

    @discardableResult
    func save(name: String, displayName: String? = nil, avatarURL: URL? = nil) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return false }
        return save(RecentForum(
            name: trimmed,
            displayName: displayName ?? "\(trimmed)吧",
            avatarURL: avatarURL,
            updatedAt: now()
        ))
    }

    @discardableResult
    func clear() -> Bool {
        guard persistentBackendIsAvailable else {
            persistenceAvailability = .unavailable
            return false
        }
        do {
            try PersistedRecordStore.saveRecentForums([])
            defaults.removeObject(forKey: key)
            items = []
            markPersistenceSucceeded()
            return true
        } catch {
            PersistenceDiagnostics.report(error, operation: "clear recent forums")
            persistenceAvailability = .unavailable
            return false
        }
    }

    private func save(_ recent: RecentForum) -> Bool {
        guard persistentBackendIsAvailable else {
            persistenceAvailability = .unavailable
            return false
        }
        return persist(
            RecentForumPolicy.sanitized([recent] + items, limit: limit),
            operation: "save recent forums"
        )
    }

    @discardableResult
    func remove(ids: Set<String>) -> Bool {
        guard ids.isEmpty == false else { return true }
        let normalizedIDs = Set(ids.map { $0.lowercased() })
        let updated = items.filter { normalizedIDs.contains($0.id) == false }
        guard updated.count != items.count else { return true }
        guard persistentBackendIsAvailable else {
            persistenceAvailability = .unavailable
            return false
        }
        guard updated.isEmpty == false else { return clear() }
        return persist(updated, operation: "remove recent forums")
    }

    private func persist(_ updated: [RecentForum], operation: String) -> Bool {
        do {
            try PersistedRecordStore.saveRecentForums(updated)
            items = updated
            markPersistenceSucceeded()
            return true
        } catch {
            PersistenceDiagnostics.report(error, operation: operation)
            persistenceAvailability = .unavailable
            return false
        }
    }

    private func markPersistenceSucceeded() {
        guard persistentBackendIsAvailable else { return }
        persistenceAvailability = .available
    }

    private static func loadAndRepairItems(
        limit: Int,
        canRepair: Bool,
        faultInjector: PersistenceFaultInjector = .none
    ) throws -> PersistenceLoadResult<[RecentForum]> {
        let raw = try PersistedRecordStore.loadRecentForums()
        let sanitized = RecentForumPolicy.sanitized(raw, limit: limit)
        if canRepair, raw != sanitized {
            do {
                try faultInjector.check(.repair)
                try PersistedRecordStore.saveRecentForums(sanitized)
            } catch {
                return PersistenceLoadResult(value: sanitized, repairError: error)
            }
        }
        return PersistenceLoadResult(value: sanitized, repairError: nil)
    }

    private static func migrateLegacyStorage(
        defaults: UserDefaults,
        key: String,
        limit: Int,
        destinationIsDurable: Bool,
        legacyFallback: inout [RecentForum]?,
        faultInjector: PersistenceFaultInjector
    ) throws {
        guard let data = defaults.data(forKey: key) else { return }
        let existing = try PersistedRecordStore.loadRecentForums()
        let source: [RecentForum]
        if existing.isEmpty {
            guard let decoded = PersistedArrayDecoder.decode(RecentForum.self, from: data) else {
                throw LegacyStorageMigration.DecodeError.invalidTopLevelArray
            }
            source = RecentForumPolicy.sanitized(decoded, limit: limit)
            legacyFallback = source
        } else {
            source = existing
        }
        let sanitized = RecentForumPolicy.sanitized(source, limit: limit)
        try LegacyStorageMigration.persistThenRemoveLegacyValue(
            defaults: defaults,
            key: key,
            destinationIsDurable: destinationIsDurable
        ) {
            try faultInjector.check(.legacyMigration)
            try PersistedRecordStore.saveRecentForums(sanitized)
        }
    }
}
