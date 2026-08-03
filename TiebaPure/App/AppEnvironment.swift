import Foundation

@MainActor
final class AppEnvironment: ObservableObject {
    let accountStore: AccountStore
    let api: any TiebaAPIService
    let logoutCoordinator: LogoutCoordinator
    let socialRelationshipState: SocialRelationshipState
    let socialMutationCoordinator: SocialMutationCoordinator
    let ownThreadMutationState: OwnThreadMutationState
    let contentDraftStore: ContentDraftStore
    let contentSubmissionSettingsStore: ContentSubmissionSettingsStore
    let contentSubmissionCoordinator: ContentSubmissionCoordinator

    init(
        accountStore: AccountStore,
        api: any TiebaAPIService,
        logoutCoordinator: LogoutCoordinator,
        socialRelationshipState: SocialRelationshipState? = nil,
        socialMutationCoordinator: SocialMutationCoordinator? = nil,
        ownThreadMutationState: OwnThreadMutationState? = nil,
        contentDraftStore: ContentDraftStore? = nil,
        contentSubmissionSettingsStore: ContentSubmissionSettingsStore? = nil,
        contentSubmissionCoordinator: ContentSubmissionCoordinator? = nil
    ) {
        self.accountStore = accountStore
        self.api = api
        self.logoutCoordinator = logoutCoordinator
        let resolvedSubmissionSettings = contentSubmissionSettingsStore
            ?? ContentSubmissionSettingsStore()
        self.contentSubmissionSettingsStore = resolvedSubmissionSettings
        let resolvedSocialState = socialRelationshipState ?? SocialRelationshipState()
        self.socialRelationshipState = resolvedSocialState
        self.socialMutationCoordinator = socialMutationCoordinator
            ?? SocialMutationCoordinator(
                api: api,
                state: resolvedSocialState,
                allowsLikes: { resolvedSubmissionSettings.likesEnabled }
            )
        self.ownThreadMutationState = ownThreadMutationState ?? OwnThreadMutationState()
        self.contentDraftStore = contentDraftStore ?? ContentDraftStore()
        self.contentSubmissionCoordinator = contentSubmissionCoordinator
            ?? ContentSubmissionCoordinator(
                api: api,
                allowsSubmission: { resolvedSubmissionSettings.allowsSubmission(kind: $0) }
            )
    }

    static func live() -> AppEnvironment {
#if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("UITEST_RESET_SEARCH_HISTORY") {
            requireUIFixturePersistence(
                SearchHistoryStore.shared.clear(),
                operation: "清空搜索历史"
            )
        }
        if arguments.contains("UITEST_RESET_BROWSING_HISTORY") {
            requireUIFixturePersistence(
                BrowsingHistoryStore.shared.clear(),
                operation: "清空浏览历史"
            )
        }
        if arguments.contains("UITEST_RESET_RECENT_FORUMS") {
            requireUIFixturePersistence(
                RecentForumStore.shared.clear(),
                operation: "清空最近浏览贴吧"
            )
        }
        if arguments.contains("UITEST_SEED_SCROLLABLE_RECENT_FORUMS") {
            for index in 1...6 {
                requireUIFixturePersistence(
                    RecentForumStore.shared.save(Forum(
                        id: Int64(10_000 + index),
                        name: "合成最近贴吧\(index)",
                        displayName: "合成最近贴吧\(index)吧",
                        avatarURL: nil,
                        memberCount: index * 100,
                        threadCount: index * 10
                    )),
                    operation: "写入可滚动最近贴吧夹具"
                )
            }
        }
        if arguments.contains("UITEST_RESET_LOCAL_THREAD_LIBRARY") {
            requireUIFixturePersistence(
                LocalThreadLibraryStore.shared.clearAll(),
                operation: "清空本机帖子记录"
            )
        }
        if arguments.contains("UITEST_RESET_BLOCKLIST") {
            BlocklistEntryKind.allCases.forEach {
                BlocklistStore.shared.clear(kind: $0)
            }
        }
        if arguments.contains("UITEST_RESET_FORUM_THREAD_SORT") {
            ForumThreadSortPreferenceStore().reset()
        }
        if arguments.contains("UITEST_RESET_CONTENT_SUBMISSION")
            || arguments.contains("UITEST_RESET_CONTENT_SUBMISSION_RISK") {
            ContentSubmissionRiskPolicy.reset()
        }
        if arguments.contains("UITEST_SEED_LOCAL_THREAD_LIBRARY") {
            requireUIFixturePersistence(
                LocalThreadLibraryStore.shared.addFavorite(
                    thread: FixtureTiebaAPI.threads[0],
                    forum: FixtureTiebaAPI.forum
                ),
                operation: "写入帖子收藏夹具"
            )
            requireUIFixturePersistence(
                LocalThreadLibraryStore.shared.recordReadingPosition(
                    threadID: FixtureTiebaAPI.threads[0].id,
                    postID: 2002,
                    floor: 2
                ),
                operation: "写入阅读位置夹具"
            )
        }
        if arguments.contains("UITEST_SEED_LOCAL_THREAD_MANAGEMENT") {
            for thread in FixtureTiebaAPI.threads {
                let forum = thread.forumID == FixtureTiebaAPI.forumTwo.id
                    ? FixtureTiebaAPI.forumTwo
                    : FixtureTiebaAPI.forum
                requireUIFixturePersistence(
                    BrowsingHistoryStore.shared.record(thread: thread, forum: forum),
                    operation: "写入多条浏览历史夹具"
                )
                requireUIFixturePersistence(
                    LocalThreadLibraryStore.shared.addFavorite(thread: thread, forum: forum),
                    operation: "写入多条帖子收藏夹具"
                )
            }
            for (threadID, postID, floor) in [
                (FixtureTiebaAPI.threads[0].id, UInt64(2_002), 2),
                (FixtureTiebaAPI.threads[2].id, UInt64(3_002), 3)
            ] {
                requireUIFixturePersistence(
                    LocalThreadLibraryStore.shared.recordReadingPosition(
                        threadID: threadID,
                        postID: postID,
                        floor: floor
                    ),
                    operation: "写入多条阅读位置夹具"
                )
            }
        }
        if arguments.contains("UITEST_USE_FIXTURES") {
            return fixture()
        }
#endif
        let keychainService = KeychainAccountStoreService()
        FreshInstallCredentialCleanup(
            defaults: .standard,
            storedCredentialCreationDate: keychainService.storedItemCreationDate,
            sandboxCreationDate: Self.sandboxCreationDate,
            clearStoredCredentials: keychainService.deleteStoredItem
        ).runIfNeeded()
        let accountStore = AccountStore(
            service: MigratingAccountStoreService(
                keychain: keychainService,
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
        let api = TiebaAPI(client: TiebaHTTPClient(session: SecureRemoteURLSession.make(
            configuration: configuration,
            redirectScope: .baiduHTTPS
        )))
        let contentSubmissionSettingsStore = ContentSubmissionSettingsStore()
        let contentSubmissionCoordinator = ContentSubmissionCoordinator(
            api: api,
            allowsSubmission: { contentSubmissionSettingsStore.allowsSubmission(kind: $0) }
        )
        let socialRelationshipState = SocialRelationshipState()
        let socialMutationCoordinator = SocialMutationCoordinator(
            api: api,
            state: socialRelationshipState,
            allowsLikes: { contentSubmissionSettingsStore.likesEnabled }
        )
        return AppEnvironment(
            accountStore: accountStore,
            api: api,
            logoutCoordinator: LogoutCoordinator(
                accountStore: accountStore,
                beginWriteInvalidation: {
                    socialMutationCoordinator.establishInvalidationBarrier()
                    contentSubmissionCoordinator.establishInvalidationBarrier()
                    let socialDrain = Task { @MainActor in
                        await socialMutationCoordinator.drainInvalidatedOperations()
                    }
                    let contentDrain = Task { @MainActor in
                        await contentSubmissionCoordinator.drainInvalidatedOperations()
                    }
                    await socialDrain.value
                    await contentDrain.value
                },
                endWriteInvalidation: {
                    contentSubmissionCoordinator.endInvalidation()
                    socialMutationCoordinator.endInvalidation()
                }
            ),
            socialRelationshipState: socialRelationshipState,
            socialMutationCoordinator: socialMutationCoordinator,
            contentSubmissionSettingsStore: contentSubmissionSettingsStore,
            contentSubmissionCoordinator: contentSubmissionCoordinator
        )
    }

    /// When this install's sandbox came into existence. The Library directory
    /// is created at install time and never by user action, unlike Documents.
    private static func sandboxCreationDate() -> Date? {
        guard let url = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first else {
            return nil
        }
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return attributes?[.creationDate] as? Date
    }

#if DEBUG
    private static func requireUIFixturePersistence(
        _ succeeded: @autoclosure () -> Bool,
        operation: String
    ) {
        guard succeeded() else {
            preconditionFailure("UI 测试夹具持久化失败：\(operation)")
        }
    }

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
        let api = FixtureTiebaAPI(scenario: scenario, delayMilliseconds: delay)
        let settingsSuite = "dev.infinityf4p.tiebapure.uitest.content-submission"
        let settingsDefaults = UserDefaults(suiteName: settingsSuite) ?? .standard
        if ProcessInfo.processInfo.arguments.contains(
            "UITEST_PRESERVE_CONTENT_SUBMISSION_SETTINGS"
        ) == false {
            settingsDefaults.removePersistentDomain(forName: settingsSuite)
        }
        let contentSubmissionSettingsStore = ContentSubmissionSettingsStore(
            defaults: settingsDefaults,
            key: "replies-enabled"
        )
        if ProcessInfo.processInfo.arguments.contains("UITEST_RESET_CONTENT_SUBMISSION") {
            contentSubmissionSettingsStore.setRepliesEnabled(true)
        }
        let contentSubmissionCoordinator = ContentSubmissionCoordinator(
            api: api,
            allowsSubmission: { contentSubmissionSettingsStore.allowsSubmission(kind: $0) }
        )
        let socialRelationshipState = SocialRelationshipState()
        let socialMutationCoordinator = SocialMutationCoordinator(
            api: api,
            state: socialRelationshipState,
            allowsLikes: { contentSubmissionSettingsStore.likesEnabled }
        )
        let draftStore = ContentDraftStore()
        if ProcessInfo.processInfo.arguments.contains("UITEST_RESET_CONTENT_SUBMISSION") {
            _ = draftStore.clear(accountID: FixtureTiebaAPI.account.id)
        }
        return AppEnvironment(
            accountStore: store,
            api: api,
            logoutCoordinator: LogoutCoordinator(
                accountStore: store,
                artifactCleaner: FixtureSessionArtifactCleaner(),
                beginWriteInvalidation: {
                    socialMutationCoordinator.establishInvalidationBarrier()
                    contentSubmissionCoordinator.establishInvalidationBarrier()
                    let socialDrain = Task { @MainActor in
                        await socialMutationCoordinator.drainInvalidatedOperations()
                    }
                    let contentDrain = Task { @MainActor in
                        await contentSubmissionCoordinator.drainInvalidatedOperations()
                    }
                    await socialDrain.value
                    await contentDrain.value
                },
                endWriteInvalidation: {
                    contentSubmissionCoordinator.endInvalidation()
                    socialMutationCoordinator.endInvalidation()
                }
            ),
            socialRelationshipState: socialRelationshipState,
            socialMutationCoordinator: socialMutationCoordinator,
            contentDraftStore: draftStore,
            contentSubmissionSettingsStore: contentSubmissionSettingsStore,
            contentSubmissionCoordinator: contentSubmissionCoordinator
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
