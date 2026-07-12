import Combine
import Foundation
import Security

protocol AccountStoreService: Sendable {
    func loadData() async throws -> Data?
    func saveData(_ data: Data) async throws
    func clearData() async throws
}

/// Read/delete-only access to the one-time plaintext migration source. Keeping
/// this separate from AccountStoreService makes a file-backed credential
/// fallback impossible to wire into production accidentally.
protocol LegacyAccountStoreService: Sendable {
    func loadData() async throws -> Data?
    func clearData() async throws
}

final class AccountStore: ObservableObject {
    private let service: AccountStoreService
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    let accountDidChange = PassthroughSubject<Account?, Never>()

    init(service: AccountStoreService) {
        self.service = service
    }

    func load() async throws -> Account? {
        guard let data = try await service.loadData() else { return nil }
        do {
            return try decoder.decode(Account.self, from: data)
        } catch {
            try? await service.clearData()
            throw error
        }
    }

    func save(_ account: Account) async throws {
        try Task.checkCancellation()
        let previousData = try await service.loadData()
        let data = try encoder.encode(account)
        do {
            try Task.checkCancellation()
            try await service.saveData(data)
            try Task.checkCancellation()
            try await MainActor.run {
                try Task.checkCancellation()
                accountDidChange.send(account)
            }
            try Task.checkCancellation()
        } catch is CancellationError {
            do {
                if let previousData {
                    try await service.saveData(previousData)
                } else {
                    try await service.clearData()
                }
            } catch {
                throw AccountStoreError.cancellationRollbackFailed
            }
            let previousAccount = previousData.flatMap { try? decoder.decode(Account.self, from: $0) }
            await MainActor.run {
                accountDidChange.send(previousAccount)
            }
            throw CancellationError()
        }
    }

    func clear() async throws {
        try await service.clearData()
        await MainActor.run {
            accountDidChange.send(nil)
        }
    }
}

actor MemoryAccountStoreService: AccountStoreService, LegacyAccountStoreService {
    private var data: Data?

    init(data: Data? = nil) {
        self.data = data
    }

    func loadData() async throws -> Data? {
        data
    }

    func saveData(_ data: Data) async throws {
        self.data = data
    }

    func clearData() async throws {
        data = nil
    }
}

/// Imports the previous plaintext account exactly once. Credentials are never
/// returned unless the Keychain write and plaintext deletion both succeed.
actor MigratingAccountStoreService: AccountStoreService {
    private let keychain: any AccountStoreService
    private let legacyFile: any LegacyAccountStoreService

    init(keychain: any AccountStoreService, legacyFile: any LegacyAccountStoreService) {
        self.keychain = keychain
        self.legacyFile = legacyFile
    }

    func loadData() async throws -> Data? {
        let keychainData: Data?
        do {
            keychainData = try await keychain.loadData()
        } catch {
            try? await legacyFile.clearData()
            throw AccountMigrationError.keychainWriteFailed
        }
        if let stored = keychainData {
            guard let decoded = Self.validAccount(from: stored),
                  let sanitized = try? JSONEncoder().encode(decoded) else {
                try? await keychain.clearData()
                try? await legacyFile.clearData()
                throw AccountMigrationError.invalidLegacyData
            }
            if sanitized != stored {
                do {
                    try await keychain.saveData(sanitized)
                } catch {
                    try? await keychain.clearData()
                    try? await legacyFile.clearData()
                    throw AccountMigrationError.keychainWriteFailed
                }
            }
            do {
                try await legacyFile.clearData()
            } catch {
                try? await keychain.clearData()
                throw AccountMigrationError.plaintextDeletionFailed
            }
            return sanitized
        }
        guard let legacy = try await legacyFile.loadData() else {
            return nil
        }
        guard let decoded = Self.validAccount(from: legacy),
              let sanitized = try? JSONEncoder().encode(decoded) else {
            try? await legacyFile.clearData()
            throw AccountMigrationError.invalidLegacyData
        }

        do {
            // Decode and re-encode instead of copying the legacy bytes. Codable
            // intentionally ignores unknown keys, so this strips the removed
            // full-cookie field and any other unrecognized plaintext material.
            try await keychain.saveData(sanitized)
            do {
                try await legacyFile.clearData()
            } catch {
                try? await keychain.clearData()
                throw AccountMigrationError.plaintextDeletionFailed
            }
            return sanitized
        } catch let error as AccountMigrationError {
            throw error
        } catch {
            // A failed migration must force a new login and must not continue
            // reading usable credentials from disk.
            try? await legacyFile.clearData()
            throw AccountMigrationError.keychainWriteFailed
        }
    }

    func saveData(_ data: Data) async throws {
        do {
            try await keychain.saveData(data)
        } catch {
            try? await legacyFile.clearData()
            throw AccountMigrationError.keychainWriteFailed
        }
        do {
            try await legacyFile.clearData()
        } catch {
            try? await keychain.clearData()
            throw AccountMigrationError.plaintextDeletionFailed
        }
    }

    func clearData() async throws {
        var firstError: Error?
        do { try await legacyFile.clearData() } catch { firstError = error }
        do { try await keychain.clearData() } catch { if firstError == nil { firstError = error } }
        if let firstError { throw firstError }
    }

    private static func validAccount(from data: Data) -> Account? {
        guard let account = try? JSONDecoder().decode(Account.self, from: data),
              account.uid.isEmpty == false,
              account.bduss.isEmpty == false,
              account.stoken.isEmpty == false else {
            return nil
        }
        return account
    }
}

enum AccountMigrationError: Error, Equatable {
    case keychainWriteFailed
    case plaintextDeletionFailed
    case invalidLegacyData
}

actor FileAccountStoreService: LegacyAccountStoreService {
    private let fileURL: URL

    init(fileURL: URL = FileAccountStoreService.defaultFileURL()) {
        self.fileURL = fileURL
    }

    func loadData() async throws -> Data? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }
        return try Data(contentsOf: fileURL)
    }

    func clearData() async throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return
        }
        try FileManager.default.removeItem(at: fileURL)
    }

    static func defaultFileURL() -> URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return baseURL
            .appendingPathComponent("TiebaPure", isDirectory: true)
            .appendingPathComponent("account.json")
    }
}

struct KeychainAccountStoreService: AccountStoreService {
    private let service: String
    private let account: String

    init(service: String = "dev.kevinchen.tiebapure.account", account: String = "single") {
        self.service = service
        self.account = account
    }

    func loadData() async throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError.status(status) }
        return result as? Data
    }

    func saveData(_ data: Data) async throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else { throw KeychainError.status(updateStatus) }

        var addQuery = query
        attributes.forEach { addQuery[$0.key] = $0.value }
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw KeychainError.status(addStatus) }
    }

    func clearData() async throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.status(status)
        }
    }
}

enum KeychainError: Error, Equatable {
    case status(OSStatus)
}

enum AccountStoreError: Error, Equatable {
    case cancellationRollbackFailed
}
