import Foundation

struct BrowsingHistoryEntry: Codable, Equatable, Identifiable, Sendable {
    var threadID: Int64
    var forumID: Int64?
    var title: String
    var authorDisplayName: String
    var forumDisplayName: String?
    var visitedAt: Date

    var id: Int64 { threadID }

    init(
        threadID: Int64,
        forumID: Int64? = nil,
        title: String,
        authorDisplayName: String,
        forumDisplayName: String? = nil,
        visitedAt: Date
    ) {
        self.threadID = threadID
        self.forumID = forumID
        self.title = title
        self.authorDisplayName = authorDisplayName
        self.forumDisplayName = forumDisplayName
        self.visitedAt = visitedAt
    }
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
        let effectiveLimit = min(max(limit, 0), maximumStoredEntries)
        guard effectiveLimit > 0 else { return [] }
        var updated = items.filter { $0.threadID != entry.threadID }
        updated.insert(entry, at: 0)
        return Array(updated.prefix(effectiveLimit))
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
        let effectiveLimit = min(max(limit, 0), maximumStoredEntries)
        guard effectiveLimit > 0 else { return [] }
        var seenThreadIDs = Set<Int64>()
        var result: [BrowsingHistoryEntry] = []

        let ordered = items.sorted {
            if $0.visitedAt != $1.visitedAt {
                return $0.visitedAt > $1.visitedAt
            }
            return $0.threadID > $1.threadID
        }
        for item in ordered where
            item.threadID > 0 &&
            item.visitedAt.timeIntervalSinceReferenceDate.isFinite
        {
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
            if result.count == effectiveLimit { break }
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
    private let persistentBackendIsAvailable: Bool
    private let faultInjector: PersistenceFaultInjector
    private var mutationTail: Task<Bool, Never>?
    private var mutationTailID: UUID?
    private var pendingMutationCount = 0
    @Published private(set) var items: [BrowsingHistoryEntry]
    @Published private(set) var persistenceAvailability: PersistenceAvailability

    init(
        defaults: UserDefaults = .standard,
        key: String = "dev.infinityf4p.tiebapure.browsingHistory",
        limit: Int = BrowsingHistoryPolicy.maximumStoredEntries,
        persistenceAvailability: PersistenceAvailability? = nil,
        faultInjector: PersistenceFaultInjector = .none,
        now: @escaping () -> Date = Date.init
    ) {
        self.defaults = defaults
        self.key = key
        self.limit = min(max(limit, 0), BrowsingHistoryPolicy.maximumStoredEntries)
        self.now = now
        self.faultInjector = faultInjector
        let initialAvailability = persistenceAvailability ?? .available
        persistentBackendIsAvailable = initialAvailability.canPersist
        self.persistenceAvailability = initialAvailability
        var legacyFallback: [BrowsingHistoryEntry]?
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
            PersistenceDiagnostics.report(error, operation: "migrate browsing history")
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
                PersistenceDiagnostics.report(error, operation: "repair browsing history")
                self.persistenceAvailability = .unavailable
            }
        } catch {
            PersistenceDiagnostics.report(error, operation: "load browsing history")
            items = migrationFailed ? (legacyFallback ?? []) : []
            self.persistenceAvailability = .unavailable
        }
        if migrationFailed, items.isEmpty, let legacyFallback {
            items = legacyFallback
        }
    }

    @discardableResult
    func reload() -> Bool {
        guard pendingMutationCount == 0 else { return false }
        do {
            let result = try Self.loadAndRepairItems(
                limit: limit,
                canRepair: persistentBackendIsAvailable,
                faultInjector: faultInjector
            )
            items = result.value
            if let error = result.repairError {
                PersistenceDiagnostics.report(error, operation: "repair browsing history")
                persistenceAvailability = .unavailable
                return false
            }
            markPersistenceSucceeded()
            return true
        } catch {
            PersistenceDiagnostics.report(error, operation: "reload browsing history")
            persistenceAvailability = .unavailable
            return false
        }
    }

    @discardableResult
    func record(
        thread: ThreadSummary,
        forum: Forum? = nil,
        fallbackForumID: Int64? = nil
    ) -> Bool {
        guard pendingMutationCount == 0,
              let entry = BrowsingHistoryPolicy.entry(
            for: thread,
            forum: forum,
            fallbackForumID: fallbackForumID,
            visitedAt: now()
        ) else { return false }
        return persist(BrowsingHistoryPolicy.adding(entry, to: items, limit: limit))
    }

    @discardableResult
    func recordInBackground(
        thread: ThreadSummary,
        forum: Forum? = nil,
        fallbackForumID: Int64? = nil
    ) async -> Bool {
        await enqueueRecord(
            thread: thread,
            forum: forum,
            fallbackForumID: fallbackForumID
        ).value
    }

    func enqueueRecord(
        thread: ThreadSummary,
        forum: Forum? = nil,
        fallbackForumID: Int64? = nil
    ) -> Task<Bool, Never> {
        guard let entry = BrowsingHistoryPolicy.entry(
            for: thread,
            forum: forum,
            fallbackForumID: fallbackForumID,
            visitedAt: now()
        ) else {
            return completedMutation(false)
        }
        return enqueueMutation {
            let current = try PersistedRecordStore.loadBrowsingHistory()
            let updated = BrowsingHistoryPolicy.adding(entry, to: current, limit: self.limit)
            try PersistedRecordStore.saveBrowsingHistory(updated)
            return updated
        }
    }

    @discardableResult
    func remove(threadIDs: Set<Int64>) -> Bool {
        guard pendingMutationCount == 0 else { return false }
        guard threadIDs.isEmpty == false else { return true }
        return persist(BrowsingHistoryPolicy.removing(threadIDs: threadIDs, from: items))
    }

    @discardableResult
    func removeInBackground(threadIDs: Set<Int64>) async -> Bool {
        guard threadIDs.isEmpty == false else { return true }
        return await enqueueMutation {
            let current = try PersistedRecordStore.loadBrowsingHistory()
            let updated = BrowsingHistoryPolicy.removing(threadIDs: threadIDs, from: current)
            try PersistedRecordStore.saveBrowsingHistory(updated)
            return updated
        }.value
    }

    @discardableResult
    func clear() -> Bool {
        guard pendingMutationCount == 0 else { return false }
        guard persistentBackendIsAvailable else {
            persistenceAvailability = .unavailable
            return false
        }
        do {
            try PersistedRecordStore.saveBrowsingHistory([])
            defaults.removeObject(forKey: key)
            items = []
            markPersistenceSucceeded()
            return true
        } catch {
            PersistenceDiagnostics.report(error, operation: "clear browsing history")
            persistenceAvailability = .unavailable
            return false
        }
    }

    @discardableResult
    func clearInBackground() async -> Bool {
        await enqueueMutation {
            try PersistedRecordStore.saveBrowsingHistory([])
            return []
        }.value
    }

    func waitForPendingMutations() async {
        while let tail = mutationTail {
            _ = await tail.value
        }
    }

    @discardableResult
    private func persist(_ updated: [BrowsingHistoryEntry]) -> Bool {
        guard persistentBackendIsAvailable else {
            persistenceAvailability = .unavailable
            return false
        }
        do {
            try PersistedRecordStore.saveBrowsingHistory(updated)
            items = updated
            markPersistenceSucceeded()
            return true
        } catch {
            PersistenceDiagnostics.report(error, operation: "save browsing history")
            persistenceAvailability = .unavailable
            return false
        }
    }

    private func enqueueMutation(
        _ work: @escaping () throws -> [BrowsingHistoryEntry]
    ) -> Task<Bool, Never> {
        guard persistentBackendIsAvailable else {
            persistenceAvailability = .unavailable
            return completedMutation(false)
        }
        let previousMutation = mutationTail
        let mutationID = UUID()
        pendingMutationCount += 1
        mutationTailID = mutationID
        let task = Task { @MainActor [weak self] in
            if let previousMutation {
                _ = await previousMutation.value
            }
            guard let self else { return false }
            defer {
                self.pendingMutationCount = max(self.pendingMutationCount - 1, 0)
                if self.mutationTailID == mutationID {
                    self.mutationTail = nil
                    self.mutationTailID = nil
                }
            }
            do {
                let updated = try await Task.detached(priority: .utility) {
                    try work()
                }.value
                self.items = updated
                self.markPersistenceSucceeded()
                return true
            } catch {
                PersistenceDiagnostics.report(error, operation: "mutate browsing history")
                self.persistenceAvailability = .unavailable
                return false
            }
        }
        mutationTail = task
        return task
    }

    private func completedMutation(_ result: Bool) -> Task<Bool, Never> {
        Task { result }
    }

    private func markPersistenceSucceeded() {
        guard persistentBackendIsAvailable else { return }
        persistenceAvailability = .available
    }

    private static func loadAndRepairItems(
        limit: Int,
        canRepair: Bool,
        faultInjector: PersistenceFaultInjector = .none
    ) throws -> PersistenceLoadResult<[BrowsingHistoryEntry]> {
        let raw = try PersistedRecordStore.loadBrowsingHistory()
        let sanitized = BrowsingHistoryPolicy.sanitized(raw, limit: limit)
        if canRepair, raw != sanitized {
            do {
                try faultInjector.check(.repair)
                try PersistedRecordStore.saveBrowsingHistory(sanitized)
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
        legacyFallback: inout [BrowsingHistoryEntry]?,
        faultInjector: PersistenceFaultInjector
    ) throws {
        guard let data = defaults.data(forKey: key) else { return }
        let existing = try PersistedRecordStore.loadBrowsingHistory()
        let source: [BrowsingHistoryEntry]
        if existing.isEmpty {
            guard let decoded = PersistedArrayDecoder.decode(BrowsingHistoryEntry.self, from: data) else {
                throw LegacyStorageMigration.DecodeError.invalidTopLevelArray
            }
            source = BrowsingHistoryPolicy.sanitized(decoded, limit: limit)
            legacyFallback = source
        } else {
            source = existing
        }
        let sanitized = BrowsingHistoryPolicy.sanitized(source, limit: limit)
        try LegacyStorageMigration.persistThenRemoveLegacyValue(
            defaults: defaults,
            key: key,
            destinationIsDurable: destinationIsDurable
        ) {
            try faultInjector.check(.legacyMigration)
            try PersistedRecordStore.saveBrowsingHistory(sanitized)
        }
    }
}
