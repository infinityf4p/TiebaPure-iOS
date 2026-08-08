import Combine
import Foundation

// Legacy UserDefaults blobs are decoded element by element during the one-time
// migration into SwiftData: a single corrupt entry must not drop the rest.
struct FailableDecodable<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: Decoder) {
        value = try? Value(from: decoder)
    }
}


enum LocalThreadListSearchPolicy {
    static func matches(query: String, fields: [String?]) -> Bool {
        let terms = query
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
        guard terms.isEmpty == false else { return true }

        let searchableText = fields.compactMap { $0 }.joined(separator: "\n")
        let options: String.CompareOptions = [
            .caseInsensitive,
            .diacriticInsensitive,
            .widthInsensitive
        ]
        return terms.allSatisfy { term in
            searchableText.range(of: term, options: options) != nil
        }
    }
}

enum LocalThreadListSelectionPolicy {
    static func retainedSelection(
        _ selection: Set<Int64>,
        visibleThreadIDs: [Int64]
    ) -> Set<Int64> {
        selection.intersection(Set(visibleThreadIDs))
    }

    static func selectionByTogglingAll(
        _ selection: Set<Int64>,
        visibleThreadIDs: [Int64]
    ) -> Set<Int64> {
        let visible = Set(visibleThreadIDs)
        guard visible.isEmpty == false else { return [] }
        let retained = selection.intersection(visible)
        return retained == visible ? [] : visible
    }
}


struct ThreadReadingPosition: Codable, Equatable, Identifiable, Sendable {
    var threadID: Int64
    var postID: UInt64
    var floor: Int
    var updatedAt: Date

    var id: Int64 { threadID }
}

enum LocalThreadLibraryPolicy {
    static let maximumReadingPositions = 500

    static func readingPosition(
        threadID: Int64,
        postID: UInt64,
        floor: Int,
        updatedAt: Date
    ) -> ThreadReadingPosition? {
        // Restore targets the post ID; floor is display-only and hot-sorted
        // responses legitimately omit it (floor == 0).
        guard threadID > 0, postID > 0, floor >= 0 else { return nil }
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
        let effectiveLimit = min(max(limit, 0), maximumReadingPositions)
        guard effectiveLimit > 0 else { return [] }
        var updated = positions.filter { $0.threadID != position.threadID }
        updated.insert(position, at: 0)
        return Array(updated.prefix(effectiveLimit))
    }

    static func sanitizedReadingPositions(
        _ positions: [ThreadReadingPosition],
        limit: Int
    ) -> [ThreadReadingPosition] {
        let effectiveLimit = min(max(limit, 0), maximumReadingPositions)
        guard effectiveLimit > 0 else { return [] }
        var seenThreadIDs = Set<Int64>()
        var result: [ThreadReadingPosition] = []

        let ordered = positions.sorted {
            if $0.updatedAt != $1.updatedAt {
                return $0.updatedAt > $1.updatedAt
            }
            return $0.threadID > $1.threadID
        }
        for position in ordered {
            guard position.threadID > 0,
                  position.postID > 0,
                  position.floor >= 0,
                  position.updatedAt.timeIntervalSinceReferenceDate.isFinite,
                  seenThreadIDs.insert(position.threadID).inserted else { continue }
            result.append(position)
            if result.count == effectiveLimit { break }
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
    private let readingPositionsKey: String
    private let limit: Int
    private let now: () -> Date
    private let persistentBackendIsAvailable: Bool
    private let faultInjector: PersistenceFaultInjector
    private var readingPositionMutationTail: Task<Bool, Never>?
    private var readingPositionMutationTailID: UUID?
    private var pendingReadingPositionMutationCount = 0
    @Published private(set) var readingPositions: [ThreadReadingPosition]
    @Published private(set) var persistenceAvailability: PersistenceAvailability

    init(
        defaults: UserDefaults = .standard,
        readingPositionsKey: String = "dev.infinityf4p.tiebapure.threadReadingPositions",
        limit: Int = LocalThreadLibraryPolicy.maximumReadingPositions,
        persistenceAvailability: PersistenceAvailability? = nil,
        faultInjector: PersistenceFaultInjector = .none,
        now: @escaping () -> Date = Date.init
    ) {
        self.defaults = defaults
        self.readingPositionsKey = readingPositionsKey
        self.limit = min(max(limit, 0), LocalThreadLibraryPolicy.maximumReadingPositions)
        self.now = now
        self.faultInjector = faultInjector
        let initialAvailability = persistenceAvailability ?? .available
        persistentBackendIsAvailable = initialAvailability.canPersist
        self.persistenceAvailability = initialAvailability

        var legacyFallback: [ThreadReadingPosition]?
        var migrationFailed = false
        do {
            try Self.migrateLegacyReadingPositions(
                defaults: defaults,
                key: readingPositionsKey,
                limit: self.limit,
                destinationIsDurable: initialAvailability.canPersist,
                legacyFallback: &legacyFallback,
                faultInjector: faultInjector
            )
        } catch {
            PersistenceDiagnostics.report(error, operation: "migrate reading positions")
            self.persistenceAvailability = .unavailable
            migrationFailed = true
        }

        do {
            let result = try Self.loadAndRepairReadingPositions(
                limit: self.limit,
                canRepair: persistentBackendIsAvailable,
                faultInjector: faultInjector
            )
            readingPositions = result.value
            if let error = result.repairError {
                PersistenceDiagnostics.report(error, operation: "repair reading positions")
                self.persistenceAvailability = .unavailable
            }
        } catch {
            PersistenceDiagnostics.report(error, operation: "load reading positions")
            readingPositions = migrationFailed ? (legacyFallback ?? []) : []
            self.persistenceAvailability = .unavailable
        }
        if migrationFailed, readingPositions.isEmpty, let legacyFallback {
            readingPositions = legacyFallback
        }
    }

    @discardableResult
    func reload() -> Bool {
        guard pendingReadingPositionMutationCount == 0 else { return false }
        do {
            let result = try Self.loadAndRepairReadingPositions(
                limit: limit,
                canRepair: persistentBackendIsAvailable,
                faultInjector: faultInjector
            )
            readingPositions = result.value
            if let error = result.repairError {
                PersistenceDiagnostics.report(error, operation: "repair reading positions")
                persistenceAvailability = .unavailable
                return false
            }
            markPersistenceSucceeded()
            return true
        } catch {
            PersistenceDiagnostics.report(error, operation: "reload reading positions")
            persistenceAvailability = .unavailable
            return false
        }
    }

    func position(for threadID: Int64) -> ThreadReadingPosition? {
        readingPositions.first { $0.threadID == threadID }
    }

    @discardableResult
    func recordReadingPositionInBackground(
        threadID: Int64,
        postID: UInt64,
        floor: Int
    ) async -> Bool {
        await enqueueReadingPosition(threadID: threadID, postID: postID, floor: floor).value
    }

    func enqueueReadingPosition(
        threadID: Int64,
        postID: UInt64,
        floor: Int
    ) -> Task<Bool, Never> {
        let position = ThreadReadingPosition(
            threadID: threadID,
            postID: postID,
            floor: floor,
            updatedAt: now()
        )
        return enqueueReadingPositionMutation {
            try PersistedRecordStore.upsertReadingPosition(position, limit: self.limit)
            return try PersistedRecordStore.loadReadingPositions()
        }
    }

    @discardableResult
    func clearReadingPositionInBackground(threadID: Int64) async -> Bool {
        await enqueueClearReadingPosition(threadID: threadID).value
    }

    func enqueueClearReadingPosition(threadID: Int64) -> Task<Bool, Never> {
        enqueueReadingPositionMutation {
            try PersistedRecordStore.deleteReadingPosition(threadID: threadID)
            return try PersistedRecordStore.loadReadingPositions()
        }
    }

    @discardableResult
    func clearReadingPositionsInBackground() async -> Bool {
        await enqueueClearReadingPositions().value
    }

    func enqueueClearReadingPositions() -> Task<Bool, Never> {
        enqueueReadingPositionMutation {
            try PersistedRecordStore.saveReadingPositions([])
            return []
        }
    }

    func waitForPendingReadingPositionMutations() async {
        while let tail = readingPositionMutationTail {
            _ = await tail.value
        }
    }

    @discardableResult
    func recordReadingPosition(threadID: Int64, postID: UInt64, floor: Int) -> Bool {
        guard pendingReadingPositionMutationCount == 0 else { return false }
        guard persistentBackendIsAvailable else {
            persistenceAvailability = .unavailable
            return false
        }
        let position = ThreadReadingPosition(
            threadID: threadID,
            postID: postID,
            floor: floor,
            updatedAt: now()
        )
        do {
            try PersistedRecordStore.upsertReadingPosition(position, limit: limit)
            readingPositions = try PersistedRecordStore.loadReadingPositions()
            markPersistenceSucceeded()
            return true
        } catch {
            PersistenceDiagnostics.report(error, operation: "save reading position")
            persistenceAvailability = .unavailable
            return false
        }
    }

    @discardableResult
    func clearReadingPosition(threadID: Int64) -> Bool {
        guard pendingReadingPositionMutationCount == 0 else { return false }
        guard persistentBackendIsAvailable else {
            persistenceAvailability = .unavailable
            return false
        }
        do {
            try PersistedRecordStore.deleteReadingPosition(threadID: threadID)
            readingPositions = try PersistedRecordStore.loadReadingPositions()
            markPersistenceSucceeded()
            return true
        } catch {
            PersistenceDiagnostics.report(error, operation: "clear reading position")
            persistenceAvailability = .unavailable
            return false
        }
    }

    @discardableResult
    func clearReadingPositions() -> Bool {
        guard pendingReadingPositionMutationCount == 0 else { return false }
        guard persistentBackendIsAvailable else {
            persistenceAvailability = .unavailable
            return false
        }
        do {
            try PersistedRecordStore.saveReadingPositions([])
            readingPositions = []
            markPersistenceSucceeded()
            return true
        } catch {
            PersistenceDiagnostics.report(error, operation: "clear reading positions")
            persistenceAvailability = .unavailable
            return false
        }
    }

    @discardableResult
    func clearAll() -> Bool {
        guard pendingReadingPositionMutationCount == 0 else { return false }
        guard persistentBackendIsAvailable else {
            persistenceAvailability = .unavailable
            return false
        }
        do {
            try PersistedRecordStore.clearThreadLibrary()
            defaults.removeObject(forKey: readingPositionsKey)
            readingPositions = []
            markPersistenceSucceeded()
            return true
        } catch {
            PersistenceDiagnostics.report(error, operation: "clear thread library")
            persistenceAvailability = .unavailable
            return false
        }
    }

    private func enqueueReadingPositionMutation(
        _ work: @escaping () throws -> [ThreadReadingPosition]
    ) -> Task<Bool, Never> {
        guard persistentBackendIsAvailable else {
            persistenceAvailability = .unavailable
            return completedReadingPositionMutation(false)
        }
        let previous = readingPositionMutationTail
        let mutationID = UUID()
        pendingReadingPositionMutationCount += 1
        readingPositionMutationTailID = mutationID
        let task = Task { @MainActor [weak self] in
            if let previous {
                _ = await previous.value
            }
            guard let self else { return false }
            defer {
                self.pendingReadingPositionMutationCount = max(self.pendingReadingPositionMutationCount - 1, 0)
                if self.readingPositionMutationTailID == mutationID {
                    self.readingPositionMutationTail = nil
                    self.readingPositionMutationTailID = nil
                }
            }
            do {
                let updated = try await Task.detached(priority: .utility) {
                    try work()
                }.value
                self.readingPositions = updated
                self.markPersistenceSucceeded()
                return true
            } catch {
                PersistenceDiagnostics.report(error, operation: "mutate reading position")
                self.persistenceAvailability = .unavailable
                return false
            }
        }
        readingPositionMutationTail = task
        return task
    }

    private func completedReadingPositionMutation(_ result: Bool) -> Task<Bool, Never> {
        Task { result }
    }

    private func markPersistenceSucceeded() {
        guard persistentBackendIsAvailable else { return }
        persistenceAvailability = .available
    }

    private static func loadAndRepairReadingPositions(
        limit: Int,
        canRepair: Bool,
        faultInjector: PersistenceFaultInjector = .none
    ) throws -> PersistenceLoadResult<[ThreadReadingPosition]> {
        let raw = try PersistedRecordStore.loadReadingPositions()
        let sanitized = LocalThreadLibraryPolicy.sanitizedReadingPositions(raw, limit: limit)
        if canRepair, raw != sanitized {
            do {
                try faultInjector.check(.repair)
                try PersistedRecordStore.saveReadingPositions(sanitized)
            } catch {
                return PersistenceLoadResult(value: sanitized, repairError: error)
            }
        }
        return PersistenceLoadResult(value: sanitized, repairError: nil)
    }

    private static func migrateLegacyReadingPositions(
        defaults: UserDefaults,
        key: String,
        limit: Int,
        destinationIsDurable: Bool,
        legacyFallback: inout [ThreadReadingPosition]?,
        faultInjector: PersistenceFaultInjector
    ) throws {
        guard let data = defaults.data(forKey: key) else { return }
        let existing = try PersistedRecordStore.loadReadingPositions()
        let source: [ThreadReadingPosition]
        if existing.isEmpty {
            guard let decoded = PersistedArrayDecoder.decode(ThreadReadingPosition.self, from: data) else {
                throw LegacyStorageMigration.DecodeError.invalidTopLevelArray
            }
            source = LocalThreadLibraryPolicy.sanitizedReadingPositions(decoded, limit: limit)
            legacyFallback = source
        } else {
            source = existing
        }
        let sanitized = LocalThreadLibraryPolicy.sanitizedReadingPositions(source, limit: limit)
        try LegacyStorageMigration.persistThenRemoveLegacyValue(
            defaults: defaults,
            key: key,
            destinationIsDurable: destinationIsDurable
        ) {
            try faultInjector.check(.legacyMigration)
            try PersistedRecordStore.saveReadingPositions(sanitized)
        }
    }
}
