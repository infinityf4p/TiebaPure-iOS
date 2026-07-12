import Foundation
import WebKit

@MainActor
protocol SessionArtifactCleaning {
    func clear() async throws
}

struct LiveSessionArtifactCleaner: SessionArtifactCleaning {
    func clear() async throws {
        try Task.checkCancellation()
        clearFoundationCookies()
        URLCache.shared.removeAllCachedResponses()
        await TiebaImagePipeline.shared.clearCaches()
        try await clearLegacyBaiduWebKitData()
        try Task.checkCancellation()
    }

    private func clearFoundationCookies() {
        HTTPCookieStorage.shared.cookies?
            .filter { Self.isBaiduDomain($0.domain) }
            .forEach(HTTPCookieStorage.shared.deleteCookie)
    }

    private func clearLegacyBaiduWebKitData() async throws {
        let store = WKWebsiteDataStore.default()
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        let records = await withCheckedContinuation { continuation in
            store.fetchDataRecords(ofTypes: types) { continuation.resume(returning: $0) }
        }
        let baiduRecords = records.filter { Self.isBaiduDomain($0.displayName) }
        guard baiduRecords.isEmpty == false else { return }
        await withCheckedContinuation { continuation in
            store.removeData(ofTypes: types, for: baiduRecords) {
                continuation.resume()
            }
        }
    }

    private static func isBaiduDomain(_ value: String) -> Bool {
        let domain = value.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return domain == "baidu.com" || domain.hasSuffix(".baidu.com")
    }
}

@MainActor
final class LogoutCoordinator {
    private let accountStore: AccountStore
    private let artifactCleaner: any SessionArtifactCleaning

    init(accountStore: AccountStore, artifactCleaner: any SessionArtifactCleaning) {
        self.accountStore = accountStore
        self.artifactCleaner = artifactCleaner
    }

    convenience init(accountStore: AccountStore) {
        self.init(accountStore: accountStore, artifactCleaner: LiveSessionArtifactCleaner())
    }

    /// AccountStore publishes the signed-out state only after every other
    /// persisted session artifact has been cleared successfully.
    func logOut() async throws {
        try await artifactCleaner.clear()
        try await accountStore.clear()
    }
}
