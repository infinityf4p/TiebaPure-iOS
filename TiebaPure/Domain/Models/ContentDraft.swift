import Foundation

struct ContentDraft: Equatable, Sendable {
    var accountID: String
    var target: ContentSubmissionTarget
    var title: String
    var body: String
    var images: [ContentSubmissionImage]
    var updatedAt: Date
}

enum ContentDraftLoadOutcome: Equatable, Sendable {
    case loaded(ContentDraft?)
    case damaged(ContentDraftDamage)
    case unavailable
}

enum ContentDraftDamage: Equatable, Sendable {
    case targetMetadata
    case attachmentContainer
}

enum ContentDraftPolicy {
    static let maximumDraftsPerAccount = 100
    static let maximumDraftsGlobally = 200
    static let maximumAttachmentBytesPerDraft = 96 * 1_024 * 1_024
    static let maximumAttachmentBytesPerAccount = 256 * 1_024 * 1_024
    static let maximumAttachmentBytesGlobally = 512 * 1_024 * 1_024
}

private enum ContentDraftStoreError: Error {
    case persistenceUnavailable
    case invalidAccountID
    case damagedTarget
    case damagedAttachmentContainer
    case attachmentBudgetExceeded
}

enum ContentDraftImageBlobDecodeOutcome: Equatable, Sendable {
    case decoded([ContentSubmissionImage])
    case damagedContainer
    case cancelled
}

struct ContentDraftPruneCandidate: Sendable {
    let sourceIndex: Int
    let persistentID: String?
    let accountID: String
    let targetKey: String
    let updatedAt: Date
    let imagesByteCount: Int?
}

enum ContentDraftPruner {
    static func deletionIndices(for candidates: [ContentDraftPruneCandidate]) -> Set<Int> {
        let ordered = candidates.sorted { lhs, rhs in
            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }
            if lhs.accountID != rhs.accountID {
                return lhs.accountID < rhs.accountID
            }
            if lhs.targetKey != rhs.targetKey {
                return lhs.targetKey < rhs.targetKey
            }
            if let lhsID = lhs.persistentID, let rhsID = rhs.persistentID, lhsID != rhsID {
                return lhsID < rhsID
            }
            if lhs.persistentID != nil, rhs.persistentID == nil {
                return true
            }
            if lhs.persistentID == nil, rhs.persistentID != nil {
                return false
            }
            return lhs.sourceIndex < rhs.sourceIndex
        }

        var deletionIndices = Set<Int>()
        var retainedDraftsByAccount: [String: Int] = [:]
        var retainedBytesByAccount: [String: Int] = [:]
        var retainedGlobalDrafts = 0
        var retainedGlobalBytes = 0

        for candidate in ordered {
            let accountDrafts = retainedDraftsByAccount[candidate.accountID, default: 0]
            let accountBytes = retainedBytesByAccount[candidate.accountID, default: 0]
            let byteCount = candidate.imagesByteCount.flatMap { $0 >= 0 ? $0 : nil }

            let exceedsCount = accountDrafts >= ContentDraftPolicy.maximumDraftsPerAccount
                || retainedGlobalDrafts >= ContentDraftPolicy.maximumDraftsGlobally
            let exceedsByteBudget: Bool
            if let byteCount {
                exceedsByteBudget = byteCount > ContentDraftPolicy.maximumAttachmentBytesPerDraft
                    || fits(
                        additionalBytes: byteCount,
                        usedBytes: accountBytes,
                        limit: ContentDraftPolicy.maximumAttachmentBytesPerAccount
                    ) == false
                    || fits(
                        additionalBytes: byteCount,
                        usedBytes: retainedGlobalBytes,
                        limit: ContentDraftPolicy.maximumAttachmentBytesGlobally
                    ) == false
            } else {
                // Legacy rows remain count-limited but are not guessed into a
                // byte budget. Background repair resolves them before the next
                // exact byte-based prune.
                exceedsByteBudget = false
            }

            if exceedsCount || exceedsByteBudget {
                deletionIndices.insert(candidate.sourceIndex)
                continue
            }

            retainedDraftsByAccount[candidate.accountID] = accountDrafts + 1
            retainedGlobalDrafts += 1
            if let byteCount {
                retainedBytesByAccount[candidate.accountID] = accountBytes + byteCount
                retainedGlobalBytes += byteCount
            }
        }
        return deletionIndices
    }

    private static func fits(additionalBytes: Int, usedBytes: Int, limit: Int) -> Bool {
        additionalBytes <= limit && usedBytes <= limit - additionalBytes
    }
}

/// Encodes each attachment in an independently checksummed frame. Any damaged
/// frame blocks the draft so editing never silently discards an attachment.
enum ContentDraftImageBlobCodec {
    private static let magic = Data([0x54, 0x50, 0x44, 0x49]) // TPDI
    private static let version: UInt8 = 2
    private static let legacyJSONVersion: UInt8 = 1
    private static let headerSize = 8
    private static let frameHeaderSize = 8
    private static let maximumFrameBytes = 16 * 1_024 * 1_024
    private static let maximumUUIDBytes = 64
    private static let maximumMIMETypeBytes = 128

    static func encode(_ images: [ContentSubmissionImage]) throws -> Data {
        var blob = Data()
        blob.append(magic)
        blob.append(version)
        blob.append(contentsOf: [0, 0, 0])

        for image in images {
            try Task.checkCancellation()
            let payload = try encodeFrame(image)
            guard payload.count <= maximumFrameBytes,
                  payload.count <= Int(UInt32.max) else {
                throw ContentDraftStoreError.attachmentBudgetExceeded
            }
            append(UInt32(payload.count), to: &blob)
            append(checksum(payload), to: &blob)
            blob.append(payload)
        }
        return blob
    }

    static func decode(_ blob: Data) -> [ContentSubmissionImage] {
        guard case let .decoded(images) = decodeWithIntegrity(blob) else {
            return []
        }
        return images
    }

    static func decodeWithIntegrity(_ blob: Data) -> ContentDraftImageBlobDecodeOutcome {
        guard blob.count >= headerSize,
              blob.prefix(magic.count) == magic else {
            return .damagedContainer
        }

        let storedVersion = blob[magic.count]
        guard storedVersion == version || storedVersion == legacyJSONVersion else {
            return .damagedContainer
        }
        var images: [ContentSubmissionImage] = []
        var offset = headerSize
        while offset < blob.count {
            guard Task.isCancelled == false else { return .cancelled }
            guard images.count < ContentSubmissionPolicy.maximumImages else {
                return .damagedContainer
            }
            guard offset + frameHeaderSize <= blob.count else {
                return .damagedContainer
            }
            guard let lengthValue = readUInt32(blob, at: offset),
                  let expectedChecksum = readUInt32(blob, at: offset + 4) else {
                return .damagedContainer
            }
            offset += frameHeaderSize
            let length = Int(lengthValue)
            guard length <= maximumFrameBytes,
                  offset <= blob.count,
                  length <= blob.count - offset else {
                return .damagedContainer
            }

            let payload = Data(blob[offset..<(offset + length)])
            offset += length
            guard checksum(payload) == expectedChecksum,
                  let image = decodeFrame(payload, version: storedVersion),
                  image.data.isEmpty == false,
                  image.data.count <= ContentSubmissionPolicy.maximumImageBytes,
                  image.pixelWidth > 0,
                  image.pixelHeight > 0,
                  ContentSubmissionPolicy.allowedImageMIMETypes.contains(image.mimeType.lowercased()) else {
                return .damagedContainer
            }
            images.append(image)
        }
        return .decoded(images)
    }

    private static func encodeFrame(_ image: ContentSubmissionImage) throws -> Data {
        let uuid = Data(image.id.uuidString.utf8)
        let mimeType = Data(image.mimeType.lowercased().utf8)
        guard uuid.isEmpty == false,
              uuid.count <= maximumUUIDBytes,
              mimeType.isEmpty == false,
              mimeType.count <= maximumMIMETypeBytes,
              image.data.isEmpty == false,
              image.data.count <= ContentSubmissionPolicy.maximumImageBytes,
              image.pixelWidth > 0,
              image.pixelHeight > 0,
              image.pixelWidth <= Int(UInt32.max),
              image.pixelHeight <= Int(UInt32.max) else {
            throw ContentDraftStoreError.attachmentBudgetExceeded
        }

        var payload = Data()
        payload.reserveCapacity(1 + uuid.count + 4 + 4 + 2 + mimeType.count + image.data.count)
        payload.append(UInt8(uuid.count))
        payload.append(uuid)
        append(UInt32(image.pixelWidth), to: &payload)
        append(UInt32(image.pixelHeight), to: &payload)
        append(UInt16(mimeType.count), to: &payload)
        payload.append(mimeType)
        payload.append(image.data)
        return payload
    }

    private static func decodeFrame(
        _ payload: Data,
        version: UInt8
    ) -> ContentSubmissionImage? {
        if version == legacyJSONVersion {
            return try? JSONDecoder().decode(ContentSubmissionImage.self, from: payload)
        }

        var offset = 0
        guard let uuidLength = readUInt8(payload, at: &offset),
              uuidLength > 0,
              uuidLength <= maximumUUIDBytes,
              let uuidData = read(payload, count: uuidLength, at: &offset),
              let uuidString = String(data: uuidData, encoding: .utf8),
              let id = UUID(uuidString: uuidString),
              let width = readUInt32(payload, at: offset) else {
            return nil
        }
        offset += 4
        guard let height = readUInt32(payload, at: offset) else { return nil }
        offset += 4
        guard let mimeLength = readUInt16(payload, at: offset) else { return nil }
        offset += 2
        guard mimeLength > 0,
              mimeLength <= maximumMIMETypeBytes,
              let mimeData = read(payload, count: mimeLength, at: &offset),
              let mimeType = String(data: mimeData, encoding: .utf8),
              offset < payload.count else {
            return nil
        }
        let imageData = Data(payload[offset...])
        return ContentSubmissionImage(
            id: id,
            data: imageData,
            pixelWidth: Int(width),
            pixelHeight: Int(height),
            mimeType: mimeType
        )
    }

    private static func append(_ value: UInt32, to data: inout Data) {
        data.append(UInt8((value >> 24) & 0xff))
        data.append(UInt8((value >> 16) & 0xff))
        data.append(UInt8((value >> 8) & 0xff))
        data.append(UInt8(value & 0xff))
    }

    private static func append(_ value: UInt16, to data: inout Data) {
        data.append(UInt8((value >> 8) & 0xff))
        data.append(UInt8(value & 0xff))
    }

    private static func readUInt8(_ data: Data, at offset: inout Int) -> Int? {
        guard offset < data.count else { return nil }
        defer { offset += 1 }
        return Int(data[offset])
    }

    private static func read(_ data: Data, count: Int, at offset: inout Int) -> Data? {
        guard count >= 0, offset >= 0, count <= data.count - offset else { return nil }
        defer { offset += count }
        return Data(data[offset..<(offset + count)])
    }

    private static func readUInt32(_ data: Data, at offset: Int) -> UInt32? {
        guard offset >= 0, offset + 4 <= data.count else { return nil }
        return (UInt32(data[offset]) << 24)
            | (UInt32(data[offset + 1]) << 16)
            | (UInt32(data[offset + 2]) << 8)
            | UInt32(data[offset + 3])
    }

    private static func readUInt16(_ data: Data, at offset: Int) -> Int? {
        guard offset >= 0, offset + 2 <= data.count else { return nil }
        return Int(UInt16(data[offset]) << 8 | UInt16(data[offset + 1]))
    }

    private static func checksum(_ data: Data) -> UInt32 {
        data.reduce(2_166_136_261) { value, byte in
            (value ^ UInt32(byte)) &* 16_777_619
        }
    }
}

private struct ContentDraftByteCountUpdate: Sendable {
    let persistentID: String
    let byteCount: Int
}

private struct ContentDraftBackgroundLoadResult: Sendable {
    let outcome: ContentDraftLoadOutcome
    let byteCountUpdate: ContentDraftByteCountUpdate?
}

/// External attachment data is faulted only inside this model actor. The main
/// context receives scalar byte-count updates and can enforce capacity without
/// touching every attachment blob.

@MainActor
final class ContentDraftStore {
    private let persistentBackendIsAvailable: Bool
    private let faultInjector: PersistenceFaultInjector
    private(set) var persistenceAvailability: PersistenceAvailability

    init(
        persistenceAvailability: PersistenceAvailability? = nil,
        faultInjector: PersistenceFaultInjector = .none
    ) {
        self.faultInjector = faultInjector
        let initial = persistenceAvailability ?? .available
        self.persistentBackendIsAvailable = initial.canPersist
        self.persistenceAvailability = initial
        scheduleMaintenance()
    }

    /// Legacy SwiftData initializer kept for older call sites/tests.
    convenience init(
        modelContainer _: Any?,
        persistenceAvailability: PersistenceAvailability? = nil,
        faultInjector: PersistenceFaultInjector = .none
    ) {
        self.init(
            persistenceAvailability: persistenceAvailability,
            faultInjector: faultInjector
        )
    }

    func load(
        accountID: String,
        target: ContentSubmissionTarget,
        into draft: inout ContentDraft?
    ) -> Bool {
        draft = nil
        guard requirePersistence(operation: "load content draft") else { return false }
        do {
            let normalizedAccountID = try normalizedAccountID(accountID)
            let matches = try matchingRecords(
                accountID: normalizedAccountID,
                targetKey: target.draftKey
            )
            guard let record = preferredRecord(in: matches) else {
                markPersistenceSucceeded()
                return true
            }
            guard let storedTarget = try? JSONDecoder().decode(
                ContentSubmissionTarget.self,
                from: record.targetData
            ), storedTarget.draftKey == target.draftKey else {
                throw ContentDraftStoreError.damagedTarget
            }
            let imagesBlob = record.imagesBlob
            let images: [ContentSubmissionImage]
            switch ContentDraftImageBlobCodec.decodeWithIntegrity(imagesBlob) {
            case let .decoded(decodedImages):
                images = decodedImages
            case .damagedContainer:
                throw ContentDraftStoreError.damagedAttachmentContainer
            case .cancelled:
                return false
            }
            draft = ContentDraft(
                accountID: normalizedAccountID,
                target: storedTarget,
                title: record.title,
                body: record.body,
                images: images,
                updatedAt: record.updatedAt
            )
            // backfill byte count
            var all = try PersistedRecordStore.loadContentDrafts()
            if let idx = all.firstIndex(where: {
                $0.accountID == record.accountID &&
                $0.targetKey == record.targetKey &&
                $0.updatedAt == record.updatedAt
            }), all[idx].imagesByteCount != imagesBlob.count {
                all[idx].imagesByteCount = imagesBlob.count
                try PersistedRecordStore.saveContentDrafts(all)
            }
            markPersistenceSucceeded()
            return true
        } catch ContentDraftStoreError.damagedTarget {
            PersistenceDiagnostics.report(
                ContentDraftStoreError.damagedTarget,
                operation: "load content draft"
            )
            markPersistenceSucceeded()
            return false
        } catch ContentDraftStoreError.damagedAttachmentContainer {
            PersistenceDiagnostics.report(
                ContentDraftStoreError.damagedAttachmentContainer,
                operation: "load content draft"
            )
            markPersistenceSucceeded()
            return false
        } catch {
            PersistenceDiagnostics.report(error, operation: "load content draft")
            persistenceAvailability = .unavailable
            return false
        }
    }

    func draft(accountID: String, target: ContentSubmissionTarget) -> ContentDraft? {
        var loaded: ContentDraft?
        guard load(accountID: accountID, target: target, into: &loaded) else { return nil }
        return loaded
    }

    func loadAsync(
        accountID: String,
        target: ContentSubmissionTarget
    ) async -> ContentDraftLoadOutcome {
        guard requirePersistence(operation: "load content draft") else { return .unavailable }
        do {
            let normalizedAccountID = try normalizedAccountID(accountID)
            let targetKey = target.draftKey
            let snapshot = try await Task.detached(priority: .utility) {
                try PersistedRecordStore.loadContentDrafts()
            }.value
            guard Task.isCancelled == false else { return .unavailable }
            let matches = snapshot.filter {
                $0.accountID == normalizedAccountID && $0.targetKey == targetKey
            }
            guard let record = preferredRecord(in: matches) else {
                markPersistenceSucceeded()
                return .loaded(nil)
            }
            guard let storedTarget = try? JSONDecoder().decode(
                ContentSubmissionTarget.self,
                from: record.targetData
            ), storedTarget.draftKey == target.draftKey else {
                markPersistenceSucceeded()
                return .damaged(.targetMetadata)
            }
            switch ContentDraftImageBlobCodec.decodeWithIntegrity(record.imagesBlob) {
            case let .decoded(images):
                markPersistenceSucceeded()
                return .loaded(ContentDraft(
                    accountID: normalizedAccountID,
                    target: storedTarget,
                    title: record.title,
                    body: record.body,
                    images: images,
                    updatedAt: record.updatedAt
                ))
            case .damagedContainer:
                markPersistenceSucceeded()
                return .damaged(.attachmentContainer)
            case .cancelled:
                return .unavailable
            }
        } catch {
            PersistenceDiagnostics.report(error, operation: "load content draft")
            persistenceAvailability = .unavailable
            return .unavailable
        }
    }

    @discardableResult
    func save(_ draft: ContentDraft) -> Bool {
        do {
            try persist(draft)
            return true
        } catch {
            return fail(error, operation: "save content draft")
        }
    }

    func saveAsync(_ draft: ContentDraft) async throws {
        guard persistentBackendIsAvailable else {
            persistenceAvailability = .unavailable
            throw ContentDraftStoreError.persistenceUnavailable
        }
        let account = try normalizedAccountID(draft.accountID)
        let imagesBlob = try ContentDraftImageBlobCodec.encode(draft.images)
        if imagesBlob.count > ContentDraftPolicy.maximumAttachmentBytesPerDraft {
            throw ContentDraftStoreError.attachmentBudgetExceeded
        }
        let targetData = try JSONEncoder().encode(draft.target)
        let record = ContentDraftRecordDTO(
            accountID: account,
            targetKey: draft.target.draftKey,
            targetData: targetData,
            title: draft.title,
            body: draft.body,
            imagesBlob: imagesBlob,
            imagesByteCount: imagesBlob.count,
            updatedAt: draft.updatedAt
        )
        try await Task.detached(priority: .utility) {
            var drafts = try PersistedRecordStore.loadContentDrafts()
            drafts.removeAll {
                $0.accountID == record.accountID && $0.targetKey == record.targetKey
            }
            drafts.append(record)
            try PersistedRecordStore.saveContentDrafts(drafts)
        }.value
        markPersistenceSucceeded()
    }

    func save(
        accountID: String,
        target: ContentSubmissionTarget,
        title: String,
        body: String,
        images: [ContentSubmissionImage]
    ) -> Bool {
        save(ContentDraft(
            accountID: accountID,
            target: target,
            title: title,
            body: body,
            images: images,
            updatedAt: Date()
        ))
    }

    func saveAsync(
        accountID: String,
        target: ContentSubmissionTarget,
        title: String,
        body: String,
        images: [ContentSubmissionImage]
    ) async throws {
        try await saveAsync(ContentDraft(
            accountID: accountID,
            target: target,
            title: title,
            body: body,
            images: images,
            updatedAt: Date()
        ))
    }

    @discardableResult
    func delete(accountID: String, target: ContentSubmissionTarget) -> Bool {
        guard requirePersistence(operation: "delete content draft") else { return false }
        do {
            let normalizedAccountID = try normalizedAccountID(accountID)
            var drafts = try PersistedRecordStore.loadContentDrafts()
            drafts.removeAll {
                $0.accountID == normalizedAccountID && $0.targetKey == target.draftKey
            }
            try PersistedRecordStore.saveContentDrafts(drafts)
            markPersistenceSucceeded()
            return true
        } catch {
            return fail(error, operation: "delete content draft")
        }
    }

    @discardableResult
    func clear(accountID: String) -> Bool {
        guard requirePersistence(operation: "clear content drafts") else { return false }
        do {
            let normalizedAccountID = try normalizedAccountID(accountID)
            var drafts = try PersistedRecordStore.loadContentDrafts()
            drafts.removeAll { $0.accountID == normalizedAccountID }
            try PersistedRecordStore.saveContentDrafts(drafts)
            markPersistenceSucceeded()
            return true
        } catch {
            return fail(error, operation: "clear content drafts")
        }
    }

    func repairLegacyMetadataAndPruneAsync() async -> Bool {
        guard persistentBackendIsAvailable else { return false }
        do {
            var drafts = try await Task.detached(priority: .utility) {
                try PersistedRecordStore.loadContentDrafts()
            }.value
            var changed = false
            for index in drafts.indices where drafts[index].imagesByteCount == nil {
                drafts[index].imagesByteCount = drafts[index].imagesBlob.count
                changed = true
            }
            let candidates = drafts.enumerated().map { index, record in
                ContentDraftPruneCandidate(
                    sourceIndex: index,
                    persistentID: "\(record.accountID)|\(record.targetKey)|\(record.updatedAt.timeIntervalSince1970)",
                    accountID: record.accountID,
                    targetKey: record.targetKey,
                    updatedAt: record.updatedAt,
                    imagesByteCount: record.imagesByteCount ?? record.imagesBlob.count
                )
            }
            let deletion = ContentDraftPruner.deletionIndices(for: candidates)
            if deletion.isEmpty == false {
                drafts = drafts.enumerated().compactMap { index, record in
                    deletion.contains(index) ? nil : record
                }
                changed = true
            }
            if changed {
                try await Task.detached(priority: .utility) {
                    try PersistedRecordStore.saveContentDrafts(drafts)
                }.value
            }
            markPersistenceSucceeded()
            return true
        } catch {
            PersistenceDiagnostics.report(error, operation: "repair content drafts")
            persistenceAvailability = .unavailable
            return false
        }
    }

    private func persist(_ draft: ContentDraft) throws {
        guard persistentBackendIsAvailable else {
            persistenceAvailability = .unavailable
            throw ContentDraftStoreError.persistenceUnavailable
        }
        let account = try normalizedAccountID(draft.accountID)
        let imagesBlob = try ContentDraftImageBlobCodec.encode(draft.images)
        if imagesBlob.count > ContentDraftPolicy.maximumAttachmentBytesPerDraft {
            throw ContentDraftStoreError.attachmentBudgetExceeded
        }
        let targetData = try JSONEncoder().encode(draft.target)
        var drafts = try PersistedRecordStore.loadContentDrafts()
        drafts.removeAll {
            $0.accountID == account && $0.targetKey == draft.target.draftKey
        }
        drafts.append(ContentDraftRecordDTO(
            accountID: account,
            targetKey: draft.target.draftKey,
            targetData: targetData,
            title: draft.title,
            body: draft.body,
            imagesBlob: imagesBlob,
            imagesByteCount: imagesBlob.count,
            updatedAt: draft.updatedAt
        ))
        try PersistedRecordStore.saveContentDrafts(drafts)
        markPersistenceSucceeded()
    }

    private func matchingRecords(
        accountID: String,
        targetKey: String
    ) throws -> [ContentDraftRecordDTO] {
        try PersistedRecordStore.loadContentDrafts().filter {
            $0.accountID == accountID && $0.targetKey == targetKey
        }
    }

    private func preferredRecord(
        in records: [ContentDraftRecordDTO]
    ) -> ContentDraftRecordDTO? {
        records.sorted { $0.updatedAt > $1.updatedAt }.first
    }

    private func normalizedAccountID(_ accountID: String) throws -> String {
        let trimmed = accountID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            throw ContentDraftStoreError.invalidAccountID
        }
        return trimmed
    }

    private func scheduleMaintenance() {
        Task { @MainActor [weak self] in
            _ = await self?.repairLegacyMetadataAndPruneAsync()
        }
    }

    private func requirePersistence(operation: String) -> Bool {
        guard persistentBackendIsAvailable else {
            return fail(ContentDraftStoreError.persistenceUnavailable, operation: operation)
        }
        return true
    }

    private func fail(_ error: Error, operation: String) -> Bool {
        PersistenceDiagnostics.report(error, operation: operation)
        persistenceAvailability = .unavailable
        return false
    }

    private func markPersistenceSucceeded() {
        guard persistentBackendIsAvailable else { return }
        persistenceAvailability = .available
    }
}
