import Foundation

@MainActor
final class AppEnvironment: ObservableObject {
    let accountStore: AccountStore
    let api: any TiebaAPIService
    let logoutCoordinator: LogoutCoordinator

    init(accountStore: AccountStore, api: any TiebaAPIService, logoutCoordinator: LogoutCoordinator) {
        self.accountStore = accountStore
        self.api = api
        self.logoutCoordinator = logoutCoordinator
    }

    static func live() -> AppEnvironment {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("UITEST_USE_FIXTURES") {
            return fixture()
        }
#endif
        let accountStore = AccountStore(
            service: MigratingAccountStoreService(
                keychain: KeychainAccountStoreService(),
                legacyFile: FileAccountStoreService()
            )
        )
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        return AppEnvironment(
            accountStore: accountStore,
            api: TiebaAPI(client: TiebaHTTPClient(session: SecureRemoteURLSession.make(
                configuration: configuration,
                redirectScope: .baiduHTTPS
            ))),
            logoutCoordinator: LogoutCoordinator(accountStore: accountStore)
        )
    }

#if DEBUG
    private static func fixture() -> AppEnvironment {
        let environment = ProcessInfo.processInfo.environment
        let scenario = FixtureScenario(rawValue: environment["TIEBAPURE_FIXTURE_SCENARIO"] ?? "success") ?? .success
        let delay = Int(environment["TIEBAPURE_FIXTURE_DELAY_MS"] ?? "0") ?? 0
        let accountData: Data?
        if environment["TIEBAPURE_FIXTURE_ACCOUNT"] == "loggedIn" {
            accountData = try? JSONEncoder().encode(FixtureTiebaAPI.account)
        } else {
            accountData = nil
        }
        let service = MemoryAccountStoreService(data: accountData)
        let store = AccountStore(service: service)
        return AppEnvironment(
            accountStore: store,
            api: FixtureTiebaAPI(scenario: scenario, delayMilliseconds: delay),
            logoutCoordinator: LogoutCoordinator(accountStore: store, artifactCleaner: FixtureSessionArtifactCleaner())
        )
    }
#endif
}

#if DEBUG
@MainActor
private struct FixtureSessionArtifactCleaner: SessionArtifactCleaning {
    func clear() async throws {}
}
#endif
