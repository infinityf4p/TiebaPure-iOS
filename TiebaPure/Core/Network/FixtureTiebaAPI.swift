#if DEBUG
import Foundation

enum FixtureScenario: String {
    case success
    case refreshUpdate
    case slowPaginationRefresh
    case slowHomeRefresh
    case emptyThenSuccess
    case empty
    case error
    case expired
    case slow
    case paginationFailure
    case longContent
    case textClipping
    case largeLikeCount
    case subpostReference
    case imageGesture
    case privateProfile
    case profileManagement
    case forumPinned
    case forumIDOnly
    case forumCategories
    case forumCategoryRace
    case voicePlayback
    case signFailure
    case readingPosition
    case scrollPerformance
    case layoutPreview
    case missingMainThenRecovery
    case missingMain
    case submissionFailure
    case submissionVerification
    case submissionUnknown
}

struct FixtureTiebaAPI: TiebaAPIService {
    let scenario: FixtureScenario
    let delayNanoseconds: UInt64
    private let state: FixtureRequestState

    init(scenario: FixtureScenario = .success, delayMilliseconds: Int = 0) {
        self.scenario = scenario
        delayNanoseconds = UInt64(max(delayMilliseconds, 0)) * 1_000_000
        state = FixtureRequestState()
    }

    func validateLogin(cookies: BaiduCookies) async throws -> Account {
        try await prepare()
        return Self.account
    }

    func personalizedThreads(account: Account?, page: Int, loadType: Int) async throws -> [ThreadSummary] {
        try await prepare(page: page)
        guard scenario != .empty else { return [] }
        if scenario == .slowHomeRefresh, page == 1 {
            let requestNumber = await state.nextPersonalizedPageOneRequestNumber()
            guard requestNumber > 1 else { return Self.threads }
            if requestNumber == 2 {
                try await Task.sleep(nanoseconds: 20_000_000_000)
                return [Self.refreshedThread]
            }
            var duplicate = Self.refreshedThread
            duplicate.title = "重复的首页刷新请求"
            return [duplicate]
        }
        if scenario == .slowPaginationRefresh, page > 1 {
            try await Task.sleep(nanoseconds: 10_000_000_000)
        }
        if (scenario == .refreshUpdate || scenario == .slowPaginationRefresh), page == 1 {
            let requestNumber = await state.nextPersonalizedPageOneRequestNumber()
            return requestNumber == 1 ? Self.threads : [Self.refreshedThread]
        }
        return page == 1 ? personalizedFixtureThreads : []
    }

    func followedForums(account: Account) async throws -> [Forum] {
        try await prepare()
        guard scenario != .empty else { return [] }
        let candidates = [Self.forum, Self.forumTwo]
        var result: [Forum] = []
        for forum in candidates {
            if await state.forumFollowed(
                accountID: account.id,
                forumID: forum.id,
                defaultValue: true
            ) {
                result.append(forum)
            }
        }
        return result
    }

    func forumThreads(
        account: Account?,
        forumName: String,
        page: Int,
        category: ForumThreadCategory
    ) async throws -> [ThreadSummary] {
        if scenario == .forumCategoryRace, page == 1 {
            let delay: UInt64
            switch category {
            case .replyTime:
                delay = 900_000_000
            case .publishTime:
                delay = 450_000_000
            case .featured:
                delay = 60_000_000
            }
            // Deliberately finish even after cancellation so UI tests can
            // prove that generation/request-key validation rejects stale
            // category responses.
            await Task.detached {
                try? await Task.sleep(nanoseconds: delay)
            }.value
        } else {
            try await prepare(page: page)
        }
        guard scenario != .empty else { return [] }
        guard page == 1 else { return [] }

        var fixtureThreads = Self.threads.map { thread in
            var copy = thread
            copy.forumName = forumName
            return copy
        }
        if scenario == .imageGesture {
            fixtureThreads = threadsWithSyntheticMediaURLs(
                fixtureThreads,
                pathPrefix: "forum"
            )
        }

        if scenario == .emptyThenSuccess {
            let requestNumber = await state.nextForumPageOneRequestNumber()
            guard requestNumber > 1 else { return [] }
            if requestNumber > 2, fixtureThreads.isEmpty == false {
                fixtureThreads[0].title = "贴吧连续刷新第\(requestNumber - 2)轮"
            }
        }

        if scenario == .forumPinned {
            var pinned = Self.pinnedForumThread
            pinned.forumName = forumName
            fixtureThreads.insert(pinned, at: 0)
        }

        if (scenario == .forumCategories || scenario == .forumCategoryRace),
           fixtureThreads.isEmpty == false {
            switch category {
            case .replyTime:
                fixtureThreads[0].title = "回复时间分类测试帖"
            case .publishTime:
                fixtureThreads[0].title = "发帖时间分类测试帖"
            case .featured:
                fixtureThreads[0].title = "精华分类测试帖"
            }
            fixtureThreads[0].id = 8_000 + Int64(category.sortType + 2)
            fixtureThreads[0].isGood = category == .featured
            let now = Date()
            fixtureThreads[0].createdAt = now.addingTimeInterval(-12 * 60)
            fixtureThreads[0].lastReplyAt = now.addingTimeInterval(-10)
        }

        let submittedThreads = await state.submittedThreads(forumName: forumName)
        return submittedThreads + fixtureThreads
    }

    func searchThreads(
        keyword: String,
        page: Int,
        sortType: Int,
        filterType: Int,
        forumName: String?,
        pageSize: Int
    ) async throws -> SearchResultsPage {
        if scenario == .slow || keyword == "慢请求" {
            try await Task.sleep(nanoseconds: max(delayNanoseconds, 900_000_000))
        } else {
            try await prepare(page: page)
        }
        guard scenario != .empty else {
            return SearchResultsPage(results: [], currentPage: page, hasMore: false)
        }
        if keyword == "仅回复命中", filterType == 1 {
            return SearchResultsPage(results: [], currentPage: page, hasMore: false)
        }
        let result = SearchResult(
            threadID: 1001,
            postID: 2002,
            forumID: Self.forum.id,
            forumName: forumName ?? Self.forum.name,
            forumAvatarURL: nil,
            title: "\(keyword) 的确定性搜索结果",
            content: "命中第二楼回复，可验证 postID 路由。",
            author: Self.author,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            replyCount: 3,
            likeCount: 2,
            shareCount: 1,
            blocks: [],
            isReplyMatch: true
        )
        if scenario == .layoutPreview, page == 1 {
            let results = (0..<8).map { index in
                var item = result
                item.threadID = index == 0 ? 1001 : Int64(1_100 + index)
                item.postID = index == 0 ? 2_002 : UInt64(2_100 + index)
                item.title = "\(keyword) 搜索结果 \(index + 1)"
                item.content = index.isMultiple(of: 2)
                    ? "用于检查筛选栏随结果自然滚动。"
                    : "搜索框保持在页面顶部。"
                item.replyCount = index + 1
                item.likeCount = index * 3
                return item
            }
            return SearchResultsPage(results: results, currentPage: page, hasMore: false)
        }
        return SearchResultsPage(results: page == 1 ? [result] : [], currentPage: page, hasMore: false)
    }

    func resolveUser(named name: String) async throws -> UserSummary {
        try await prepare()
        guard TiebaUserName.normalized(name) == TiebaUserName.normalized(Self.replyTarget.displayNameResolved) else {
            throw UserNameResolutionError.noExactMatch(TiebaUserName.referenceText(name))
        }
        return Self.replyTarget
    }

    func threadPage(
        account: Account?,
        threadID: Int64,
        page: Int,
        forumID: Int64?,
        postID: UInt64?,
        seeLz: Bool,
        sortType: ThreadReplySort
    ) async throws -> ThreadPage {
        try await prepare(page: page)
        var thread = await state.submittedThread(threadID: threadID)
            ?? Self.threads.first(where: { $0.id == threadID })
            ?? Self.threads[0]
        if scenario == .profileManagement {
            thread.author = Self.accountUser
        }
        let submittedMainPost = await state.submittedMainPost(threadID: threadID)
        let usesLongContent = scenario == .longContent
        let usesLargeLikeCount = scenario == .largeLikeCount
        let usesVoicePlayback = scenario == .voicePlayback
        let threadPageOneRequestNumber: Int
        if [.refreshUpdate, .missingMainThenRecovery, .missingMain].contains(scenario),
           page == 1 {
            threadPageOneRequestNumber = await state.nextThreadPageOneRequestNumber()
        } else {
            threadPageOneRequestNumber = 1
        }
        let text: String
        if threadPageOneRequestNumber > 1 {
            text = "帖子下拉刷新已更新"
        } else if usesLongContent {
            text = String(repeating: "这是用于验证主贴正文完整换行且不显示省略号的合成内容。", count: 14)
        } else {
            text = "这是完全离线的合成帖子正文，内容不来自真实用户。"
        }
        let scrollVariant = ProcessInfo.processInfo.environment["TIEBAPURE_SCROLL_FIXTURE_VARIANT"]
            ?? "mixed"
        let imageFixtureHost = scenario == .imageGesture || scenario == .scrollPerformance
            ? "fixture-success.invalid"
            : "fixture.invalid"
        let longImage = ImageContent(
            thumbnailURL: URL(string: "https://\(imageFixtureHost)/long-image.png"),
            originalURL: URL(string: "https://\(imageFixtureHost)/long-image-original.png"),
            width: 400,
            height: 1_600,
            showOriginalButton: true
        )
        var mainBlocks: [ContentBlock] = usesVoicePlayback
            ? [.text("详情页语音播放夹具"), .voice(Self.playableVoice)]
            : [
                .text(text),
                .link(title: "百度贴吧 HTTPS 链接", url: URL(string: "https://tieba.baidu.com"))
            ]
        if scenario == .scrollPerformance {
            switch scrollVariant {
            case "text":
                mainBlocks = [.text(text)]
            case "emoticons":
                mainBlocks = [.text(text), .emoticon(code: "滑稽")]
            case "images":
                mainBlocks = [.text(text), .image(longImage)]
            default:
                mainBlocks.append(.emoticon(code: "滑稽"))
            }
        }
        if scenario != .textClipping,
           scenario != .readingPosition,
           scenario != .layoutPreview,
           usesVoicePlayback == false,
           scenario != .scrollPerformance || ["mixed", "production"].contains(scrollVariant) {
            mainBlocks.append(.image(longImage))
        }
        let fixtureMain = Post(
            id: 2001,
            threadID: threadID,
            floor: 1,
            author: scenario == .profileManagement ? Self.accountUser : Self.author,
            ipAddress: "北京",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            blocks: mainBlocks,
            subpostCount: 0,
            likeCount: usesLargeLikeCount ? 9_876 : 12,
            previewSubposts: []
        )
        let main = submittedMainPost ?? fixtureMain
        let replyAuthor = UserSummary(
            id: 2,
            name: "fixture_reply",
            displayName: "很长很长的合成回复用户名用于布局测试",
            portrait: "",
            level: 13,
            levelName: "血之磐涅"
        )
        let replyText: String
        if postID == 2002 {
            replyText = "已定位搜索命中回复"
        } else if usesLongContent {
            replyText = String(repeating: "这是用于验证评论内容完整换行的合成回复。", count: 10)
        } else {
            replyText = "确定性回复内容"
        }
        let replySubposts: [Subpost]
        switch scenario {
        case .longContent:
            replySubposts = Self.longSubpostFixtures
        case .largeLikeCount:
            replySubposts = Self.largeLikeCountSubpostFixtures
        case .subpostReference:
            replySubposts = Self.referenceSubpostFixtures
        default:
            replySubposts = Self.subpostFixtures
        }
        let reply = Post(
            id: 2002,
            threadID: threadID,
            floor: 2,
            author: replyAuthor,
            ipAddress: "上海",
            createdAt: Date(timeIntervalSince1970: 1_700_000_200),
            blocks: usesVoicePlayback
                ? [.text("失败与重试夹具"), .voice(Self.failingVoice)]
                : [.text(replyText), .mention(userID: 1, text: "@合成作者")],
            subpostCount: replySubposts.count,
            likeCount: usesLargeLikeCount ? 123_456 : 3,
            previewSubposts: replySubposts
        )
        let replies: [Post]
        switch scenario {
        case .textClipping:
            replies = Self.textClippingReplyFixtures(threadID: threadID, author: replyAuthor)
        case .readingPosition:
            replies = Self.readingPositionReplyFixtures(threadID: threadID, author: replyAuthor)
        case .scrollPerformance:
            replies = Self.scrollPerformanceReplyFixtures(threadID: threadID, author: replyAuthor)
        case .layoutPreview:
            replies = Self.layoutPreviewReplyFixtures(threadID: threadID, author: replyAuthor)
        default:
            replies = [reply]
        }
        let submittedPosts = await state.submittedPosts(threadID: threadID)
        let omitsMainPost = scenario == .missingMain
            || scenario == .missingMainThenRecovery && threadPageOneRequestNumber == 1
        let posts = page == 1
            ? (omitsMainPost ? replies + submittedPosts : [main] + replies + submittedPosts)
            : []
        var isCollected = false
        if let account {
            await seedCollectionIfNeeded(account: account)
            isCollected = await state.threadCollected(accountID: account.id, threadID: threadID)
        }
        return ThreadPage(
            thread: thread,
            forum: Self.forum,
            mainPost: omitsMainPost ? nil : main,
            posts: posts,
            currentPage: page,
            totalPage: 1,
            hasMore: false,
            isCollected: isCollected
        )
    }

    func subposts(
        account: Account?,
        threadID: Int64,
        postID: UInt64,
        forumID: Int64,
        page: Int,
        subpostID: UInt64
    ) async throws -> [Subpost] {
        try await prepare(page: page)
        guard page == 1 else { return [] }
        let fixtureSubposts: [Subpost]
        switch scenario {
        case .longContent:
            fixtureSubposts = Self.longSubpostFixtures
        case .largeLikeCount:
            fixtureSubposts = Self.largeLikeCountSubpostFixtures
        case .subpostReference:
            fixtureSubposts = Self.referenceSubpostFixtures
        default:
            fixtureSubposts = Self.subpostFixtures
        }
        let submittedSubposts = await state.submittedSubposts(parentPostID: postID)
        return fixtureSubposts + submittedSubposts
    }

    func userProfile(account: Account?, user: UserSummary) async throws -> UserProfile {
        try await prepare()
        let profileEdit: UserProfileEditRequest?
        if let account {
            profileEdit = await state.profileEdit(accountID: account.id)
        } else {
            profileEdit = nil
        }
        let isFollowed = await state.userFollowed(
            accountID: account?.id ?? "guest",
            userID: user.id,
            defaultValue: false
        )
        let isCurrentUser = account.map { account in
            (Int64(account.uid).map { $0 == user.id } ?? false)
                || (user.name.isEmpty == false && user.name == account.name)
        } ?? false
        let resolvedUser = UserSummary(
            id: user.id == 0 ? Self.author.id : user.id,
            name: user.name.isEmpty ? Self.author.name : user.name,
            displayName: profileEdit?.normalizedNickname
                ?? (user.displayName.isEmpty ? Self.author.displayName : user.displayName),
            portrait: user.portrait,
            level: user.level ?? 9,
            levelName: user.levelName ?? "九级",
            ipAddress: user.ipAddress ?? "北京"
        )
        let hidesForums = scenario == .privateProfile
        return UserProfile(
            user: resolvedUser,
            isCurrentUser: isCurrentUser,
            isFollowed: isFollowed,
            tiebaID: "100000001",
            tiebaAge: "12.5年",
            sex: profileEdit?.sex ?? .unspecified,
            location: "北京",
            intro: profileEdit?.introduction
                ?? "这是用于验证用户主页布局、隐私状态和深色模式的合成资料。",
            backgroundURL: URL(string: "https://fixture-success.invalid/profile-background.png"),
            agreeCount: 4_639,
            followingCount: 74,
            followerCount: 56,
            threadCount: Self.threads.count,
            followedForumCount: hidesForums ? 63 : 2,
            followedForums: hidesForums ? [] : [Self.forum, Self.forumTwo],
            followedForumsVisibility: hidesForums ? .privateContent : .visible
        )
    }

    func updateOwnProfile(account: Account, request: UserProfileEditRequest) async throws {
        guard request.normalizedNickname.isEmpty == false else {
            throw UserProfileMutationError.missingNickname
        }
        try await prepare()
        await state.setProfileEdit(request, accountID: account.id)
    }

    func deleteOwnThread(account: Account, target: OwnThreadDeletionTarget) async throws {
        _ = account
        try UserProfileRequestFactory.validateDeletionTarget(target)
        try await prepare()
        await state.deleteThread(target.threadID)
    }

    func setUserFollowed(account: Account, user: UserSummary, followed: Bool) async throws {
        try await prepare()
        await state.setUserFollowed(
            followed,
            accountID: account.id,
            userID: user.id
        )
    }

    func userRelationships(
        account: Account?,
        userID: Int64,
        kind: UserRelationshipKind,
        page: Int
    ) async throws -> UserRelationshipPage {
        try await prepare(page: page)
        guard scenario != .empty, page == 1 else {
            return UserRelationshipPage(users: [], currentPage: page, totalCount: 0, hasMore: false)
        }
        let secondary = UserSummary(
                id: 2,
                name: "fixture_followed_user",
                displayName: "另一个合成关注用户",
                portrait: "",
                level: 12,
                levelName: "十二级",
                ipAddress: "上海"
            )
        let follower = UserSummary(
            id: 4,
            name: "fixture_follower_user",
            displayName: "合成粉丝用户",
            portrait: "",
            level: 8,
            levelName: "八级",
            ipAddress: "广东"
        )
        var users: [UserSummary]
        switch kind {
        case .following:
            users = [Self.author, secondary]
            if let account, Int64(account.uid) == userID {
                await state.seedUserFollowed(true, accountID: account.id, userID: Self.author.id)
                await state.seedUserFollowed(true, accountID: account.id, userID: secondary.id)
                var retainedUsers: [UserSummary] = []
                for candidate in users {
                    let isFollowed = await state.userFollowed(
                        accountID: account.id,
                        userID: candidate.id,
                        defaultValue: true
                    )
                    if isFollowed {
                        retainedUsers.append(candidate)
                    }
                }
                users = retainedUsers
            }
        case .followers:
            users = [follower, secondary]
        }
        _ = userID
        return UserRelationshipPage(
            users: users,
            currentPage: page,
            totalCount: users.count,
            hasMore: false
        )
    }

    func forumMembership(account: Account, forum: Forum) async throws -> ForumMembership {
        try await prepare()
        let forumID = try resolvedFixtureForumID(for: forum)
        return ForumMembership(
            forumID: forumID,
            isFollowed: await state.forumFollowed(
                accountID: account.id,
                forumID: forumID,
                defaultValue: true
            )
        )
    }

    func setForumFollowed(
        account: Account,
        forum: Forum,
        followed: Bool
    ) async throws -> ForumMembership {
        try await prepare()
        let forumID = try resolvedFixtureForumID(for: forum)
        await state.setForumFollowed(
            followed,
            accountID: account.id,
            forumID: forumID
        )
        return ForumMembership(forumID: forumID, isFollowed: followed)
    }

    func signForum(account: Account, forum: Forum) async throws -> ForumSignResult {
        try await prepare()
        let forumID = try resolvedFixtureForumID(for: forum)
        if scenario == .signFailure, forumID != Self.forum.id {
            throw TiebaAPIError.response(code: 220034, message: "操作太频繁")
        }
        let wasAlreadySigned = await state.markForumSigned(
            accountID: account.id,
            forumID: forumID
        ) == false
        return ForumSignResult(
            forumID: forumID,
            forumName: forum.name,
            wasAlreadySigned: wasAlreadySigned,
            bonusPoints: wasAlreadySigned ? 0 : 8,
            continuousDays: wasAlreadySigned ? 3 : 4,
            rank: 12
        )
    }

    func accountThreadFavorites(account: Account, page: Int) async throws -> AccountThreadFavoritesPage {
        try await prepare(page: page)
        guard scenario != .empty, page == 1 else {
            return AccountThreadFavoritesPage(favorites: [], currentPage: page, hasMore: false)
        }
        await seedCollectionIfNeeded(account: account)
        var favorites: [AccountThreadFavorite] = []
        for thread in Self.threads
        where await state.threadCollected(accountID: account.id, threadID: thread.id) {
            let forum = thread.forumID == Self.forumTwo.id ? Self.forumTwo : Self.forum
            favorites.append(AccountThreadFavorite(
                threadID: thread.id,
                forumID: forum.id,
                forumName: forum.name,
                title: thread.title,
                authorDisplayName: thread.author.displayNameResolved,
                replyCount: 12,
                lastReplyAt: Date(timeIntervalSince1970: 1_700_000_500),
                markedPostID: thread.id == Self.threads[0].id ? 2002 : nil
            ))
        }
        return AccountThreadFavoritesPage(
            favorites: favorites,
            currentPage: page,
            hasMore: false
        )
    }

    /// UI tests decide what the account already collected the same way they
    /// seed the local stores: through launch arguments.
    private func seedCollectionIfNeeded(account: Account) async {
        let arguments = ProcessInfo.processInfo.arguments
        var collected: [Int64] = []
        if arguments.contains("UITEST_SEED_ACCOUNT_COLLECTION") {
            collected.append(Self.threads[0].id)
        }
        if arguments.contains("UITEST_SEED_ACCOUNT_COLLECTION_MANY") {
            collected.append(contentsOf: Self.threads.map(\.id))
        }
        guard collected.isEmpty == false else { return }
        await state.seedThreadCollected(accountID: account.id, threadIDs: collected)
    }

    func setAccountThreadFavorite(
        account: Account,
        threadID: Int64,
        postID: UInt64,
        favorited: Bool
    ) async throws {
        _ = postID
        try await prepare()
        await state.setThreadCollected(favorited, accountID: account.id, threadID: threadID)
    }

    func messages(account: Account, kind: MessageKind, page: Int) async throws -> MessagesPage {
        _ = account
        try await prepare(page: page)
        guard scenario != .empty, page == 1 else {
            return MessagesPage(items: [], currentPage: page, hasMore: false)
        }
        let items = kind == .reply ? Self.replyMessages : Self.atMessages
        return MessagesPage(items: items, currentPage: page, hasMore: false)
    }

    func setPostLiked(
        account: Account,
        threadID: Int64,
        postID: UInt64,
        objectType: TiebaLikeObjectType,
        liked: Bool
    ) async throws {
        _ = account
        _ = threadID
        _ = postID
        _ = objectType
        _ = liked
        try await prepare()
    }

    func submitContent(
        account: Account,
        request: ContentSubmissionRequest
    ) async throws -> ContentSubmissionReceipt {
        try ContentSubmissionPolicy.validateForNetwork(request)
        try await prepare()
        switch scenario {
        case .submissionFailure:
            throw ContentSubmissionError.business(code: 7, message: "操作频繁，请稍后再试。")
        case .submissionVerification:
            throw ContentSubmissionError.verificationRequired(message: "贴吧要求完成安全验证。")
        case .submissionUnknown:
            throw ContentSubmissionError.outcomeUnknown
        default:
            return await state.submit(account: account, request: request)
        }
    }

    func userThreads(account: Account?, userID: Int64, page: Int) async throws -> UserThreadsPage {
        try await prepare(page: page)
        if scenario == .privateProfile {
            return UserThreadsPage(
                threads: [],
                currentPage: page,
                hasMore: false,
                visibility: .privateContent
            )
        }
        var visibleThreads: [ThreadSummary] = if page == 1 {
            await state.removingDeletedThreads(from: Self.threads)
        } else {
            []
        }
        if scenario == .profileManagement {
            visibleThreads = visibleThreads.map { thread in
                var ownThread = thread
                ownThread.author = Self.accountUser
                return ownThread
            }
        }
        let deletionTargets: [Int64: OwnThreadDeletionTarget] = Dictionary(
            uniqueKeysWithValues: visibleThreads.compactMap { thread -> (Int64, OwnThreadDeletionTarget)? in
                guard let forumID = thread.forumID, forumID > 0 else { return nil }
                let forumName = forumID == Self.forumTwo.id ? Self.forumTwo.name : Self.forum.name
                return (
                    thread.id,
                    OwnThreadDeletionTarget(
                        forumID: forumID,
                        forumName: forumName,
                        threadID: thread.id,
                        firstPostID: 2_001
                    )
                )
            }
        )
        return UserThreadsPage(
            threads: visibleThreads,
            currentPage: page,
            hasMore: page == 1,
            visibility: .visible,
            deletionTargetsByThreadID: deletionTargets
        )
    }

    private func prepare(page: Int = 1) async throws {
        try Task.checkCancellation()
        if delayNanoseconds > 0 || scenario == .slow {
            try await Task.sleep(nanoseconds: max(delayNanoseconds, scenario == .slow ? 900_000_000 : 0))
        }
        try Task.checkCancellation()
        if scenario == .paginationFailure, page > 1, await state.shouldFail(page: page) {
            throw URLError(.timedOut)
        }
        if scenario == .expired { throw TiebaAPIError.sessionExpired(code: 110001, message: "登录已失效") }
        if scenario == .error { throw URLError(.notConnectedToInternet) }
    }

    private func resolvedFixtureForumID(for forum: Forum) throws -> Int64 {
        if forum.id > 0 { return forum.id }
        let candidateNames = Set([forum.name, forum.displayName].map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        })
        if let match = [Self.forum, Self.forumTwo].first(where: {
            candidateNames.contains($0.name.lowercased())
                || candidateNames.contains($0.displayName.lowercased())
        }) {
            return match.id
        }
        throw TiebaMutationError.invalidForumID
    }

    private var personalizedFixtureThreads: [ThreadSummary] {
        switch scenario {
        case .imageGesture:
            return threadsWithSyntheticMediaURLs(Self.threads, pathPrefix: "home")
        case .voicePlayback:
            var voiceThread = Self.threads[0]
            voiceThread.title = "语音播放确定性夹具"
            voiceThread.blocks = [
                .voice(Self.playableVoice),
                .text("首页摘要只显示语音占位文字。")
            ]
            return [voiceThread]
        case .forumIDOnly:
            var idOnly = Self.threads[0]
            idOnly.id = 1801
            idOnly.title = "仅有吧ID的首页帖子"
            idOnly.forumName = nil

            var sameForum = Self.threads[2]
            sameForum.id = 1802
            sameForum.title = "同吧ID且有吧名的首页帖子"

            return [idOnly, sameForum, Self.threads[1]]
        default:
            return Self.threads
        }
    }

    private func threadsWithSyntheticMediaURLs(
        _ threads: [ThreadSummary],
        pathPrefix: String
    ) -> [ThreadSummary] {
        threads.map { thread in
            var thread = thread
            thread.blocks = thread.blocks.enumerated().map { blockIndex, block in
                guard case let .image(value) = block else { return block }
                var image = value
                image.thumbnailURL = URL(string:
                    "https://fixture-success.invalid/\(pathPrefix)-\(thread.id)-\(blockIndex)-thumbnail.png"
                )
                image.originalURL = URL(string:
                    "https://fixture-success.invalid/\(pathPrefix)-\(thread.id)-\(blockIndex)-original.png"
                )
                return .image(image)
            }
            return thread
        }
    }

    static let account = Account(
        uid: "42",
        name: "fixture_user",
        displayName: "模拟登录用户",
        portrait: "",
        bduss: "fixture-bduss",
        stoken: "fixture-stoken",
        baiduID: "fixture-baiduid",
        tbs: "fixture-tbs"
    )

    static let accountUser = UserSummary(
        id: Int64(account.uid) ?? 42,
        name: account.name,
        displayName: account.displayName,
        portrait: account.portrait,
        level: 9,
        levelName: "九级"
    )

    static let forum = Forum(id: 101, name: "测试", displayName: "测试吧", avatarURL: nil, memberCount: 12345, threadCount: 678)
    static let forumTwo = Forum(id: 102, name: "无障碍", displayName: "无障碍吧", avatarURL: nil, memberCount: 44, threadCount: 88)
    static let author = UserSummary(id: 1, name: "fixture_author", displayName: "合成内容作者", portrait: "", level: 9, levelName: "九级")
    static let replyTarget = UserSummary(id: 3, name: "fixture_reply_target", displayName: "被回复用户", portrait: "", level: 6, levelName: "六级")
    static let playableVoice = VoiceContent(
        md5: String(repeating: "a", count: 32),
        durationMilliseconds: 800
    )!
    static let failingVoice = VoiceContent(
        md5: String(repeating: "b", count: 32),
        durationMilliseconds: 2_500
    )!

    static let refreshedThread = ThreadSummary(
        id: 1099,
        forumID: forum.id,
        title: "下拉刷新已更新",
        author: author,
        forumName: forum.name,
        replyCount: 1,
        viewCount: 2,
        blocks: [.text("第二次首页请求返回的确定性刷新内容")]
    )

    static let pinnedForumThread = ThreadSummary(
        id: 1999,
        forumID: forum.id,
        title: "默认折叠的置顶测试帖",
        author: author,
        forumName: forum.name,
        replyCount: 18,
        viewCount: 99,
        blocks: [.text("仅用于验证贴吧置顶内容默认折叠与展开。")],
        isTop: true
    )

    static let threads: [ThreadSummary] = {
        let fourImages = (0..<4).map { index in
            ContentBlock.image(ImageContent(
                thumbnailURL: nil,
                originalURL: nil,
                width: index == 0 ? 400 : 800,
                height: index == 0 ? 1_600 : 600,
                showOriginalButton: index == 0
            ))
        }
        return [
            ThreadSummary(
                id: 1001,
                forumID: forum.id,
                title: "确定性主帖：回复筛选与媒体布局",
                author: author,
                forumName: forum.name,
                replyCount: 3,
                viewCount: 120,
                likeCount: 12,
                firstPostID: 2_001,
                blocks: [.text("合成摘要，不含真实贴吧用户内容。")] + fourImages,
                isGood: true
            ),
            ThreadSummary(
                id: 1002,
                forumID: forumTwo.id,
                title: "超长昵称、深色模式和辅助功能字号",
                author: UserSummary(id: 2, name: "long", displayName: "这是一个特别长的合成用户名用于验证自动换行", portrait: "", level: 18, levelName: "十八级"),
                forumName: forumTwo.name,
                replyCount: 0,
                viewCount: 1,
                blocks: [.text("第二条确定性内容")]
            ),
            ThreadSummary(
                id: 1003,
                forumID: forum.id,
                title: "单张超宽图片布局",
                author: author,
                forumName: forum.name,
                replyCount: 1,
                viewCount: 8,
                blocks: [
                    .text("一张合成超宽图"),
                    .image(ImageContent(
                        thumbnailURL: nil,
                        originalURL: nil,
                        width: 2_400,
                        height: 600,
                        showOriginalButton: false
                    ))
                ]
            ),
            ThreadSummary(
                id: 1004,
                forumID: forumTwo.id,
                title: "三张媒体网格布局",
                author: author,
                forumName: forumTwo.name,
                replyCount: 2,
                viewCount: 16,
                blocks: [.text("三张合成媒体")] + (0..<3).map { index in
                    .image(ImageContent(
                        thumbnailURL: nil,
                        originalURL: nil,
                        width: index == 0 ? 600 : 800,
                        height: index == 0 ? 800 : 600,
                        showOriginalButton: false
                    ))
                }
            )
        ]
    }()

    static let replyMessages = [
        MessageItem(
            id: "reply-1001-2002",
            kind: .reply,
            author: UserSummary(id: 2, name: "fixture_reply", displayName: "合成回复用户", portrait: ""),
            content: "这是回复我的第一条合成消息，内容完全离线生成。",
            threadID: 1001,
            postID: 2002,
            threadTitle: threads[0].title,
            forumName: forum.name,
            isFloorReply: false,
            createdAt: Date(timeIntervalSince1970: 1_700_000_500)
        ),
        MessageItem(
            id: "reply-1002-3001",
            kind: .reply,
            author: author,
            content: "楼中楼里回复我的合成消息，跳转应落在父楼层。",
            threadID: 1002,
            postID: 2002,
            threadTitle: threads[1].title,
            forumName: forumTwo.name,
            isFloorReply: true,
            createdAt: Date(timeIntervalSince1970: 1_700_000_560)
        )
    ]

    static let atMessages = [
        MessageItem(
            id: "at-1001-2002",
            kind: .at,
            author: replyTarget,
            content: "@模拟登录用户 这是一条合成的提及消息。",
            threadID: 1001,
            postID: 2002,
            threadTitle: threads[0].title,
            forumName: forum.name,
            isFloorReply: false,
            createdAt: Date(timeIntervalSince1970: 1_700_000_600)
        )
    ]

    static let subpostFixtures = [
        Subpost(id: 3001, floor: 1, author: author, ipAddress: "广东", blocks: [.text("楼中楼合成回复一")], createdAt: Date(timeIntervalSince1970: 1_700_000_300), likeCount: 1),
        Subpost(id: 3002, floor: 2, author: author, ipAddress: "浙江", blocks: [.text("楼中楼合成回复二")], createdAt: Date(timeIntervalSince1970: 1_700_000_360), likeCount: 0)
    ]

    static let largeLikeCountSubpostFixtures: [Subpost] = (0..<4).map(makeLargeLikeCountSubpost)

    private static func makeLargeLikeCountSubpost(index: Int) -> Subpost {
        let author = UserSummary(
            id: Int64(4 + index),
            name: "fixture_large_like_author_\(index)",
            displayName: "用于验证左侧压缩的楼中楼超长用户名\(index + 1)",
            portrait: "",
            level: 13,
            levelName: "血之磐涅"
        )
        let createdAt = Date(timeIntervalSince1970: 1_700_000_300 + TimeInterval(index * 60))
        return Subpost(
            id: UInt64(3_061 + index),
            floor: index + 1,
            author: author,
            ipAddress: "广东",
            blocks: [.text("大点赞数仍应固定显示在右侧单行。")],
            createdAt: createdAt,
            likeCount: 98_765 + index
        )
    }

    static let referenceSubpostFixtures: [Subpost] = (0..<4).map { index -> Subpost in
        let createdAt = Date(timeIntervalSince1970: TimeInterval(1_700_000_300 + index * 60))
        let blocks: [ContentBlock] = index == 0
            ? degradedReplyTargetBlocks
            : [.text("楼中楼参考布局回复\(index + 1)，用于检查完整换行。")]
        return Subpost(
            id: UInt64(3_051 + index),
            floor: index + 1,
            author: author,
            ipAddress: index.isMultiple(of: 2) ? "广东" : "浙江",
            blocks: blocks,
            createdAt: createdAt,
            likeCount: index
        )
    }

    private static let degradedReplyTargetBlocks: [ContentBlock] = {
        var replyPrefix = Tieba_PbContent()
        replyPrefix.type = 0
        replyPrefix.text = "回复"

        var replyTarget = Tieba_PbContent()
        replyTarget.type = 0
        replyTarget.text = "被回复用户"

        var replyBody = Tieba_PbContent()
        replyBody.type = 0
        replyBody.text = "：楼中楼参考布局回复1，用于检查双用户名独立跳转。"

        return PostMapper.subpostBlocks(
            from: [replyPrefix, replyTarget, replyBody],
            usersByID: [:]
        )
    }()

    static let longSubpostFixtures = (0..<4).map { index in
        let createdAt = Date(timeIntervalSince1970: TimeInterval(1_700_000_300 + index * 60))
        let blocks: [ContentBlock] = [
            .text(String(
                repeating: "这是用于验证楼中楼内容完整换行的第\(index + 1)条合成回复。",
                count: 8
            ))
        ]
        return Subpost(
            id: UInt64(3101 + index),
            floor: index + 1,
            author: author,
            ipAddress: index.isMultiple(of: 2) ? "广东" : "浙江",
            blocks: blocks,
            createdAt: createdAt,
            likeCount: index
        )
    }

    static func textClippingReplyFixtures(threadID: Int64, author: UserSummary) -> [Post] {
        let blockCases: [[ContentBlock]] = [
            [.text("翻译这段回复的第一行不应被白色裁切，第二行也应完整显示。")],
            [.text("A\u{0301} E\u{0302} Ü 高字形首行与中文混排，顶部笔画必须完整。")],
            [.text("A\u{0301}\u{0307} 叠加附标必须完整显示，不能只保留字母主体。")],
            [.text("ภาษาไทย မြန်မာ ཨོཾ العربية 多文字体系首行顶部必须完整。")],
            [.emoticon(code: "滑稽"), .text(" 首行含贴吧表情附件，后续回复文字必须保持正确基线。")],
            [
                .text("回复 "),
                .mention(userID: replyTarget.id, text: replyTarget.displayNameResolved),
                .text("：首行包含可点击用户名时不能改变行高或裁切文字。")
            ],
            [.text(String(repeating: "多行回复用于触发离屏复用和宽度重算，首行顶部必须完整。", count: 4))]
        ]

        return blockCases.enumerated().map { index, blocks in
            Post(
                id: UInt64(2_101 + index),
                threadID: threadID,
                floor: index + 2,
                author: author,
                ipAddress: index.isMultiple(of: 2) ? "上海" : "广东",
                createdAt: Date(timeIntervalSince1970: TimeInterval(1_700_000_200 + index * 60)),
                blocks: blocks,
                subpostCount: 0,
                likeCount: index,
                previewSubposts: []
            )
        }
    }

    static func readingPositionReplyFixtures(
        threadID: Int64,
        author: UserSummary
    ) -> [Post] {
        (0..<32).map { index in
            Post(
                id: UInt64(4_000 + index),
                threadID: threadID,
                floor: index + 2,
                author: author,
                ipAddress: index.isMultiple(of: 2) ? "上海" : "广东",
                createdAt: Date(timeIntervalSince1970: TimeInterval(1_700_001_000 + index * 60)),
                blocks: [
                    .text(index.isMultiple(of: 3)
                        ? String(repeating: "用于验证阅读位置保存与恢复的合成长回复。", count: 4)
                        : "阅读位置回归回复第 \(index + 1) 条。")
                ],
                subpostCount: 0,
                likeCount: index,
                previewSubposts: []
            )
        }
    }

    static func layoutPreviewReplyFixtures(
        threadID: Int64,
        author: UserSummary
    ) -> [Post] {
        let previewSubposts = Array(subpostFixtures.prefix(3))
        return [
            Post(
                id: 2_002,
                threadID: threadID,
                floor: 2,
                author: author,
                ipAddress: "上海",
                createdAt: Date(timeIntervalSince1970: 1_700_000_200),
                blocks: [.text("这个楼层没有楼中楼回复。")],
                subpostCount: 0,
                likeCount: 3,
                previewSubposts: []
            ),
            Post(
                id: 2_003,
                threadID: threadID,
                floor: 3,
                author: author,
                ipAddress: "广东",
                createdAt: Date(timeIntervalSince1970: 1_700_000_260),
                blocks: [.text("这个楼层下面还有几条回复。")],
                subpostCount: previewSubposts.count,
                likeCount: 5,
                previewSubposts: previewSubposts
            )
        ]
    }

    static func scrollPerformanceReplyFixtures(
        threadID: Int64,
        author: UserSummary
    ) -> [Post] {
        let variant = ProcessInfo.processInfo.environment["TIEBAPURE_SCROLL_FIXTURE_VARIANT"]
            ?? "mixed"
        let includesEmoticons = variant == "mixed" || variant == "emoticons" || variant == "production"
        let includesImages = variant == "mixed" || variant == "images" || variant == "production"
        let includesSubposts = variant == "production"
        return (0..<40).map { index in
            var blocks: [ContentBlock] = includesEmoticons && index.isMultiple(of: 3)
                ? [
                    .emoticon(code: "滑稽"),
                    .text(" 混合内容滚动回复第 \(index + 1) 条，表情只应刷新当前使用它的行。")
                ]
                : [
                    .text(index.isMultiple(of: 2)
                        ? String(repeating: "混合内容滚动性能回归长回复。", count: 4)
                        : "混合内容滚动回复第 \(index + 1) 条。")
                ]
            if includesImages, index.isMultiple(of: 4) {
                let imageCount = index.isMultiple(of: 8) ? 3 : 1
                for imageIndex in 0..<imageCount {
                    let identity = "scroll-\(index)-\(imageIndex)"
                    blocks.append(.image(ImageContent(
                        thumbnailURL: URL(string: "https://fixture-success.invalid/\(identity)-thumbnail.png"),
                        originalURL: URL(string: "https://fixture-success.invalid/\(identity)-original.png"),
                        width: 640,
                        height: imageIndex == 0 ? 480 : 640,
                        showOriginalButton: false
                    )))
                }
            }
            let previewSubposts: [Subpost] = includesSubposts && index.isMultiple(of: 2)
                ? (0..<3).map { subpostIndex in
                    Subpost(
                        id: UInt64(50_000 + index * 10 + subpostIndex),
                        floor: subpostIndex + 1,
                        author: author,
                        ipAddress: subpostIndex.isMultiple(of: 2) ? "广东" : "浙江",
                        blocks: [
                            .text("楼中楼摘要第 \(subpostIndex + 1) 条 "),
                            .emoticon(code: "滑稽"),
                            .text("，用于验证真实复杂回复的滚动性能。")
                        ],
                        createdAt: Date(timeIntervalSince1970: TimeInterval(1_700_003_000 + index * 60)),
                        likeCount: subpostIndex
                    )
                }
                : []
            return Post(
                id: UInt64(5_000 + index),
                threadID: threadID,
                floor: index + 2,
                author: author,
                ipAddress: index.isMultiple(of: 2) ? "上海" : "广东",
                createdAt: Date(timeIntervalSince1970: TimeInterval(1_700_002_000 + index * 60)),
                blocks: blocks,
                subpostCount: previewSubposts.count,
                likeCount: index * 173,
                previewSubposts: previewSubposts
            )
        }
    }
}

private actor FixtureRequestState {
    private var failedPages = Set<Int>()
    private var personalizedPageOneRequestCount = 0
    private var forumPageOneRequestCount = 0
    private var threadPageOneRequestCount = 0
    private var userFollowStates: [String: Bool] = [:]
    private var forumFollowStates: [String: Bool] = [:]
    private var signedForums: Set<String> = []
    private var threadCollectStates: [String: Bool] = [:]
    private var submittedThreadValues: [Int64: ThreadSummary] = [:]
    private var submittedMainPostValues: [Int64: Post] = [:]
    private var submittedPostValues: [Int64: [Post]] = [:]
    private var submittedSubpostValues: [UInt64: [Subpost]] = [:]
    private var profileEditsByAccountID: [String: UserProfileEditRequest] = [:]
    private var deletedThreadIDs = Set<Int64>()
    private var nextThreadID: Int64 = 9_001
    private var nextPostID: UInt64 = 19_001

    func shouldFail(page: Int) -> Bool {
        failedPages.insert(page).inserted
    }

    func nextPersonalizedPageOneRequestNumber() -> Int {
        personalizedPageOneRequestCount += 1
        return personalizedPageOneRequestCount
    }

    func nextForumPageOneRequestNumber() -> Int {
        forumPageOneRequestCount += 1
        return forumPageOneRequestCount
    }

    func nextThreadPageOneRequestNumber() -> Int {
        threadPageOneRequestCount += 1
        return threadPageOneRequestCount
    }

    func setUserFollowed(_ followed: Bool, accountID: String, userID: Int64) {
        userFollowStates["\(accountID)|\(userID)"] = followed
    }

    func seedUserFollowed(_ followed: Bool, accountID: String, userID: Int64) {
        let key = "\(accountID)|\(userID)"
        if userFollowStates[key] == nil {
            userFollowStates[key] = followed
        }
    }

    func userFollowed(accountID: String, userID: Int64, defaultValue: Bool) -> Bool {
        userFollowStates["\(accountID)|\(userID)"] ?? defaultValue
    }

    func setThreadCollected(_ collected: Bool, accountID: String, threadID: Int64) {
        threadCollectStates["\(accountID)|\(threadID)"] = collected
    }

    func seedThreadCollected(accountID: String, threadIDs: [Int64]) {
        for threadID in threadIDs {
            let key = "\(accountID)|\(threadID)"
            if threadCollectStates[key] == nil {
                threadCollectStates[key] = true
            }
        }
    }

    func threadCollected(accountID: String, threadID: Int64) -> Bool {
        threadCollectStates["\(accountID)|\(threadID)"] ?? false
    }

    func setProfileEdit(_ request: UserProfileEditRequest, accountID: String) {
        profileEditsByAccountID[accountID] = request
    }

    func profileEdit(accountID: String) -> UserProfileEditRequest? {
        profileEditsByAccountID[accountID]
    }

    func deleteThread(_ threadID: Int64) {
        deletedThreadIDs.insert(threadID)
        submittedThreadValues[threadID] = nil
        submittedMainPostValues[threadID] = nil
        submittedPostValues[threadID] = nil
    }

    func removingDeletedThreads(from threads: [ThreadSummary]) -> [ThreadSummary] {
        threads.filter { deletedThreadIDs.contains($0.id) == false }
    }

    /// Returns true the first time a forum is signed for an account, so the
    /// fixture can exercise both the fresh check-in and the repeat.
    func markForumSigned(accountID: String, forumID: Int64) -> Bool {
        signedForums.insert("\(accountID)|\(forumID)").inserted
    }

    func setForumFollowed(_ followed: Bool, accountID: String, forumID: Int64) {
        forumFollowStates["\(accountID)|\(forumID)"] = followed
    }

    func forumFollowed(accountID: String, forumID: Int64, defaultValue: Bool) -> Bool {
        forumFollowStates["\(accountID)|\(forumID)"] ?? defaultValue
    }

    func submittedThreads(forumName: String) -> [ThreadSummary] {
        submittedThreadValues.values
            .filter { $0.forumName == forumName }
            .sorted { $0.id > $1.id }
    }

    func submittedThread(threadID: Int64) -> ThreadSummary? {
        submittedThreadValues[threadID]
    }

    func submittedMainPost(threadID: Int64) -> Post? {
        submittedMainPostValues[threadID]
    }

    func submittedPosts(threadID: Int64) -> [Post] {
        submittedPostValues[threadID] ?? []
    }

    func submittedSubposts(parentPostID: UInt64) -> [Subpost] {
        submittedSubpostValues[parentPostID] ?? []
    }

    func submit(
        account: Account,
        request: ContentSubmissionRequest
    ) -> ContentSubmissionReceipt {
        let author = UserSummary(
            id: Int64(account.uid) ?? 42,
            name: account.name,
            displayName: account.displayName,
            portrait: account.portrait
        )
        let blocks = TiebaEmoticon.blocks(from: request.body)
        switch request.target.kind {
        case .newThread:
            let threadID = nextThreadID
            nextThreadID += 1
            let postID = nextPostID
            nextPostID += 1
            let thread = ThreadSummary(
                id: threadID,
                forumID: request.target.forumID,
                title: request.title,
                author: author,
                forumName: request.target.forumName,
                replyCount: 0,
                viewCount: 1,
                blocks: blocks.isEmpty ? [.text(request.body)] : blocks
            )
            submittedThreadValues[threadID] = thread
            submittedMainPostValues[threadID] = Post(
                id: postID,
                threadID: threadID,
                floor: 1,
                author: author,
                ipAddress: "夹具",
                createdAt: Date(),
                blocks: blocks.isEmpty ? [.text(request.body)] : blocks,
                subpostCount: 0,
                likeCount: 0,
                previewSubposts: []
            )
            return ContentSubmissionReceipt(threadID: threadID, postID: nil)
        case .threadReply:
            let threadID = request.target.threadID ?? 0
            let postID = nextPostID
            nextPostID += 1
            let post = Post(
                id: postID,
                threadID: threadID,
                floor: 100 + (submittedPostValues[threadID]?.count ?? 0),
                author: author,
                ipAddress: "夹具",
                createdAt: Date(),
                blocks: blocks.isEmpty ? [.text(request.body)] : blocks,
                subpostCount: 0,
                likeCount: 0,
                previewSubposts: []
            )
            submittedPostValues[threadID, default: []].append(post)
            return ContentSubmissionReceipt(threadID: threadID, postID: postID)
        case .postReply, .subpostReply:
            let threadID = request.target.threadID ?? 0
            let postID = nextPostID
            nextPostID += 1
            let parentPostID = request.target.parentPostID ?? 0
            let visibleBlocks: [ContentBlock]
            if request.target.kind == .subpostReply,
               let replyUserDisplayName = request.target.replyUserDisplayName,
               replyUserDisplayName.isEmpty == false {
                visibleBlocks = [
                    .text("回复 "),
                    .mention(userID: request.target.replyUserID, text: replyUserDisplayName),
                    .text("：")
                ] + (blocks.isEmpty ? [.text(request.body)] : blocks)
            } else {
                visibleBlocks = blocks.isEmpty ? [.text(request.body)] : blocks
            }
            let subpost = Subpost(
                id: postID,
                floor: 100 + (submittedSubpostValues[parentPostID]?.count ?? 0),
                author: author,
                ipAddress: "夹具",
                blocks: visibleBlocks,
                createdAt: Date(),
                likeCount: 0
            )
            submittedSubpostValues[parentPostID, default: []].append(subpost)
            return ContentSubmissionReceipt(threadID: threadID, postID: postID)
        }
    }
}
#endif
