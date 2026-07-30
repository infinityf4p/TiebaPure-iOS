import Security
import SwiftUI
import XCTest
@testable import TiebaPure

final class TiebaPureSmokeTests: XCTestCase {
    func testInteractionCountUsesRequestedSingleLineKAndWFormat() {
        XCTAssertEqual(CompactInteractionCountText.string(for: -1), "0")
        XCTAssertEqual(CompactInteractionCountText.string(for: 0), "0")
        XCTAssertEqual(CompactInteractionCountText.string(for: 999), "999")
        XCTAssertEqual(CompactInteractionCountText.string(for: 1_000), "1.0k")
        XCTAssertEqual(CompactInteractionCountText.string(for: 1_234), "1.2k")
        XCTAssertEqual(CompactInteractionCountText.string(for: 9_876), "9.9k")
        XCTAssertEqual(CompactInteractionCountText.string(for: 10_000), "1.0w")
        XCTAssertEqual(CompactInteractionCountText.string(for: 12_345), "1.2w")
        XCTAssertEqual(CompactInteractionCountText.string(for: 123_456), "12.3w")

        for value in [999, 1_000, 9_999, 10_000, 99_999, 1_000_000] {
            XCTAssertFalse(CompactInteractionCountText.string(for: value).contains("\n"))
        }
    }

    func testThreadAuthorIdentityUsesCompactVisualSizes() {
        XCTAssertEqual(
            ThreadAuthorIdentityLayout.avatarSize(isMainPost: true),
            TiebaPureTheme.AvatarSize.medium
        )
        XCTAssertEqual(ThreadAuthorIdentityLayout.avatarSize(isMainPost: false), 36)
        XCTAssertLessThan(
            ThreadAuthorIdentityLayout.avatarSize(isMainPost: true),
            TiebaPureTheme.AvatarSize.large
        )
        XCTAssertLessThan(
            ThreadAuthorIdentityLayout.avatarSize(isMainPost: false),
            TiebaPureTheme.AvatarSize.medium
        )
        XCTAssertEqual(
            ThreadReplyLayout.bodyLeadingInset,
            ThreadAuthorIdentityLayout.replyAvatarSize + TiebaPureTheme.Spacing.sm
        )
    }

    func testUserLevelBadgeIsSingleLineAndNormalizesServerNewlines() {
        XCTAssertEqual(UserLevelBadgeLayout.maximumLineCount, 1)
        XCTAssertEqual(
            UserLevelBadgeLayout.text(level: 13, levelName: "  血之\n磐涅  "),
            "13 血之磐涅"
        )
        XCTAssertEqual(UserLevelBadgeLayout.text(level: 9, levelName: nil), "Lv.9")
        XCTAssertEqual(UserLevelBadgeLayout.text(level: 9, levelName: "  "), "Lv.9")
    }

    func testThreadDetailUsesUnlimitedWrappingWhileSummariesStillTruncate() {
        XCTAssertEqual(ThreadContentDisplayPolicy.detailLineLimit, 0)
        XCTAssertEqual(
            ThreadContentDisplayPolicy.maximumNumberOfLines(
                for: ThreadContentDisplayPolicy.detailLineLimit
            ),
            0
        )
        XCTAssertEqual(
            ThreadContentDisplayPolicy.lineBreakMode(
                for: ThreadContentDisplayPolicy.detailLineLimit
            ),
            .byWordWrapping
        )
        XCTAssertEqual(ThreadContentDisplayPolicy.summaryLineLimit, 2)
        XCTAssertEqual(
            ThreadContentDisplayPolicy.lineBreakMode(
                for: ThreadContentDisplayPolicy.summaryLineLimit
            ),
            .byTruncatingTail
        )
        XCTAssertEqual(ThreadContentDisplayPolicy.paragraphLineBreakMode, .byWordWrapping)
        XCTAssertTrue(
            ThreadContentInteractionPolicy.allowsTextSelection(
                for: ThreadContentDisplayPolicy.detailLineLimit
            )
        )
        XCTAssertFalse(
            ThreadContentInteractionPolicy.allowsTextSelection(
                for: ThreadContentDisplayPolicy.summaryLineLimit
            )
        )
    }

    func testThreadPaginationContinuesAfterServerLocatedPostPage() {
        XCTAssertEqual(
            TiebaPaginationPolicy.nextPage(requestedPage: 1, responseCurrentPage: 7),
            8
        )
        XCTAssertEqual(
            TiebaPaginationPolicy.nextPage(requestedPage: 3, responseCurrentPage: 0),
            4
        )
        XCTAssertNil(TiebaPaginationPolicy.nextPage(
            requestedPage: 1,
            responseCurrentPage: Int(Int32.max)
        ))
    }

    func testPreviewAccountHasStableIdentity() {
        XCTAssertEqual(Account.preview.id, "0")
    }

    func testHomeFeedRefreshPrependsIncomingThreadsAndKeepsOlderThreads() {
        let existing = [
            thread(id: 1, title: "old one"),
            thread(id: 2, title: "old two"),
            thread(id: 3, title: "old three")
        ]
        let incoming = [
            thread(id: 4, title: "new four"),
            thread(id: 2, title: "updated two"),
            thread(id: 5, title: "new five")
        ]

        let merged = HomeFeedMerge.refresh(existing: existing, incoming: incoming)

        XCTAssertEqual(merged.map(\.id), [4, 2, 5, 1, 3])
        XCTAssertEqual(merged[1].title, "updated two")
    }

    func testHomeFeedPaginationAppendsOnlyUnseenThreads() {
        let existing = [
            thread(id: 1, title: "one"),
            thread(id: 2, title: "two")
        ]
        let incoming = [
            thread(id: 2, title: "duplicate two"),
            thread(id: 3, title: "three")
        ]

        let merged = HomeFeedMerge.append(existing: existing, incoming: incoming)

        XCTAssertEqual(merged.map(\.id), [1, 2, 3])
        XCTAssertEqual(merged[1].title, "two")
    }

    func testKeywordHighlighterFindsCaseInsensitiveMatches() {
        let segments = KeywordHighlighter.segments(in: "iPhone 和 iphone 贴吧", keyword: "IPHONE")

        XCTAssertEqual(segments, [
            KeywordHighlightSegment(text: "iPhone", isHighlighted: true),
            KeywordHighlightSegment(text: " 和 ", isHighlighted: false),
            KeywordHighlightSegment(text: "iphone", isHighlighted: true),
            KeywordHighlightSegment(text: " 贴吧", isHighlighted: false)
        ])
    }

    func testSearchResultProjectsToHomeFeedThreadSummary() {
        let image = ImageContent(
            thumbnailURL: URL(string: "https://example.com/thumb.jpg"),
            originalURL: URL(string: "https://example.com/original.jpg"),
            width: 800,
            height: 600,
            showOriginalButton: true
        )
        let result = SearchResult(
            threadID: 12,
            postID: 34,
            forumID: 56,
            forumName: "显卡",
            forumAvatarURL: URL(string: "https://example.com/forum.png"),
            title: "主贴标题",
            content: "命中正文",
            author: UserSummary(id: 78, name: "raw", displayName: "作者", portrait: ""),
            createdAt: Date(timeIntervalSince1970: 1_710_000_000),
            replyCount: 90,
            likeCount: 12,
            shareCount: 3,
            blocks: [.image(image)],
            isReplyMatch: true
        )

        let summary = result.threadSummary

        XCTAssertEqual(summary.id, 12)
        XCTAssertEqual(summary.forumID, 56)
        XCTAssertEqual(summary.forumName, "显卡")
        XCTAssertEqual(summary.forumAvatarURL?.absoluteString, "https://example.com/forum.png")
        XCTAssertEqual(summary.title, "主贴标题")
        XCTAssertEqual(summary.author.displayName, "作者")
        XCTAssertEqual(summary.replyCount, 90)
        XCTAssertEqual(summary.likeCount, 12)
        XCTAssertEqual(summary.blocks, [.text("命中正文"), .image(image)])
    }

    func testForumSearchToolbarLaunchesForumScopedSearchWithoutKeyword() {
        let forum = Forum(
            id: 10,
            name: "显卡",
            displayName: "显卡吧",
            avatarURL: URL(string: "https://example.com/forum.png"),
            memberCount: 0,
            threadCount: 0
        )

        let emptyRoute = ForumSearchLaunchPolicy.route(
            for: .toolbarButton,
            currentText: "",
            forum: forum
        )
        let typedRoute = ForumSearchLaunchPolicy.route(
            for: .toolbarButton,
            currentText: "  黑苹果  ",
            forum: forum
        )

        XCTAssertEqual(emptyRoute?.keyword, "")
        XCTAssertEqual(typedRoute?.keyword, "黑苹果")
        XCTAssertEqual(emptyRoute?.scope, .forum(forum))
        XCTAssertNil(ForumSearchLaunchPolicy.route(for: .keyboardSubmit, currentText: "", forum: forum))
    }

    func testForumThreadTapPolicySeparatesForumIdentityFromThreadBody() {
        XCTAssertEqual(ForumThreadTapPolicy.destination(for: .forumIdentity), .forum)
        XCTAssertEqual(ForumThreadTapPolicy.destination(for: .userIdentity), .user)
        XCTAssertEqual(ForumThreadTapPolicy.destination(for: .threadBody), .thread)
        XCTAssertEqual(ForumThreadTapPolicy.destination(for: .media), .media)
        XCTAssertEqual(ForumThreadTapPolicy.destination(for: .stats), .none)
    }

    func testForumPinnedPresentationDefaultsCollapsedAndPreservesServerOrder() {
        var regularOne = thread(id: 1, title: "普通一")
        var pinnedOne = thread(id: 2, title: "置顶一")
        var regularTwo = thread(id: 3, title: "普通二")
        var pinnedTwo = thread(id: 4, title: "置顶二")
        regularOne.isTop = false
        pinnedOne.isTop = true
        regularTwo.isTop = false
        pinnedTwo.isTop = true
        let source = [regularOne, pinnedOne, regularTwo, pinnedTwo]

        let collapsed = ForumPinnedPresentationPolicy.presentation(
            threads: source,
            showsPinnedThreads: false
        )
        XCTAssertEqual(collapsed.pinnedThreads.map(\.id), [2, 4])
        XCTAssertEqual(collapsed.regularThreads.map(\.id), [1, 3])
        XCTAssertEqual(collapsed.visibleThreads.map(\.id), [1, 3])

        let expanded = ForumPinnedPresentationPolicy.presentation(
            threads: source,
            showsPinnedThreads: true
        )
        XCTAssertEqual(expanded.visibleThreads.map(\.id), [2, 4, 1, 3])
    }

    func testForumThreadCategoriesMapAPIParametersAndAccessibilityIdentifiers() {
        XCTAssertEqual(ForumThreadCategory.allCases, [.replyTime, .publishTime, .featured])
        XCTAssertEqual(ForumThreadCategory.latestSortOptions, [.replyTime, .publishTime])
        XCTAssertEqual(ForumThreadCategory.allCases.map(\.topLevelTitle), ["最新", "最新", "精华"])
        XCTAssertEqual(
            ForumThreadCategory.allCases.map(\.sortOptionTitle),
            ["回复时间排序", "发帖时间排序", "精华"]
        )
        XCTAssertEqual(
            ForumThreadCategory.allCases.map(\.belongsToLatestTab),
            [true, true, false]
        )
        XCTAssertEqual(ForumThreadCategory.allCases.map(\.sortType), [0, 1, -1])
        XCTAssertNil(ForumThreadCategory.replyTime.goodClassifyID)
        XCTAssertNil(ForumThreadCategory.publishTime.goodClassifyID)
        XCTAssertEqual(ForumThreadCategory.featured.goodClassifyID, 0)
        XCTAssertEqual(
            ForumThreadCategory.allCases.map(\.accessibilityIdentifier),
            ["forum-sort-reply-time", "forum-sort-publish-time", "forum-category-featured"]
        )
        XCTAssertEqual(
            ForumThreadCategory.allCases.map(\.accessibilityHint),
            ["按最近回复时间排序", "按发帖时间排序", "仅显示精华帖"]
        )
    }

    func testForumThreadCategoryMetadataMatchesItsServerSortTimestamp() {
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let lastReplyAt = Date(timeIntervalSince1970: 1_700_000_600)
        let thread = ThreadSummary(
            id: 1,
            title: "分类时间测试",
            author: UserSummary(id: 1, name: "author", displayName: "测试作者", portrait: ""),
            replyCount: 1,
            viewCount: 10,
            createdAt: createdAt,
            lastReplyAt: lastReplyAt,
            blocks: []
        )

        XCTAssertEqual(
            ForumThreadCategory.replyTime.metadata(for: thread),
            ForumThreadMetadataPresentation(
                date: lastReplyAt,
                actionSuffix: "回复",
                systemImage: "bubble.left.and.text.bubble.right"
            )
        )
        XCTAssertEqual(
            ForumThreadCategory.publishTime.metadata(for: thread),
            ForumThreadMetadataPresentation(
                date: createdAt,
                actionSuffix: "发布",
                systemImage: "clock"
            )
        )
        XCTAssertEqual(
            ForumThreadCategory.featured.metadata(for: thread),
            ForumThreadMetadataPresentation(
                date: lastReplyAt,
                actionSuffix: "回复",
                systemImage: "bubble.left.and.text.bubble.right"
            )
        )
    }

    func testForumThreadsRequestKeySeparatesAccountForumCategoryAndPage() {
        let base = ForumThreadsRequestKey(
            accountID: "account-a",
            forumID: 101,
            forumName: "测试",
            category: .replyTime,
            page: 1
        )

        XCTAssertEqual(
            base,
            ForumThreadsRequestKey(
                accountID: "account-a",
                forumID: 101,
                forumName: "测试",
                category: .replyTime,
                page: 1
            )
        )
        XCTAssertNotEqual(
            base,
            ForumThreadsRequestKey(
                accountID: "account-b",
                forumID: 101,
                forumName: "测试",
                category: .replyTime,
                page: 1
            )
        )
        XCTAssertNotEqual(
            base,
            ForumThreadsRequestKey(
                accountID: "account-a",
                forumID: 202,
                forumName: "测试",
                category: .replyTime,
                page: 1
            )
        )
        XCTAssertNotEqual(
            base,
            ForumThreadsRequestKey(
                accountID: "account-a",
                forumID: 101,
                forumName: "另一个吧",
                category: .replyTime,
                page: 1
            )
        )
        XCTAssertNotEqual(
            base,
            ForumThreadsRequestKey(
                accountID: "account-a",
                forumID: 101,
                forumName: "测试",
                category: .publishTime,
                page: 1
            )
        )
        XCTAssertNotEqual(
            base,
            ForumThreadsRequestKey(
                accountID: "account-a",
                forumID: 101,
                forumName: "测试",
                category: .replyTime,
                page: 2
            )
        )
    }

    func testForumFixturesCoverPinnedAndRepeatedRefreshStatesWithoutNetwork() async throws {
        let pinnedAPI = FixtureTiebaAPI(scenario: .forumPinned)
        let pinnedPage = try await pinnedAPI.forumThreads(
            account: nil,
            forumName: "测试",
            page: 1,
            category: .replyTime
        )
        XCTAssertEqual(pinnedPage.filter(\.isTop).map(\.title), ["默认折叠的置顶测试帖"])
        XCTAssertGreaterThan(pinnedPage.filter { $0.isTop == false }.count, 1)

        let refreshAPI = FixtureTiebaAPI(scenario: .emptyThenSuccess)
        let emptyPage = try await refreshAPI.forumThreads(
            account: nil,
            forumName: "测试",
            page: 1,
            category: .replyTime
        )
        XCTAssertTrue(emptyPage.isEmpty)

        let loadedPage = try await refreshAPI.forumThreads(
            account: nil,
            forumName: "测试",
            page: 1,
            category: .replyTime
        )
        XCTAssertFalse(loadedPage.isEmpty)

        for cycle in 1...4 {
            let refreshedPage = try await refreshAPI.forumThreads(
                account: nil,
                forumName: "测试",
                page: 1,
                category: .replyTime
            )
            XCTAssertEqual(refreshedPage.first?.title, "贴吧连续刷新第\(cycle)轮")
        }
    }

    func testForumHubTapPolicyOpensForumFromAnyRowArea() {
        for target in ForumHubRowTapTarget.allCases {
            XCTAssertEqual(
                ForumHubTapPolicy.destination(for: target),
                .forum,
                "\(target) should open the forum"
            )
        }
    }

    func testFollowedForumTapPolicyOpensForumFromAnyRowArea() {
        for target in ForumListRowTapTarget.allCases {
            XCTAssertEqual(
                ForumListTapPolicy.destination(for: target),
                .forum,
                "\(target) should open the followed forum"
            )
        }
    }

    func testForumHubRouteBuildsForumFromTrimmedInput() {
        let route = ForumHubRoutePolicy.route(forInput: "  显卡  ")

        XCTAssertEqual(route?.forum.name, "显卡")
        XCTAssertEqual(route?.forum.displayName, "显卡吧")
        XCTAssertNil(ForumHubRoutePolicy.route(forInput: "   "))
    }

    func testForumHubDetailBridgeMovesSelectionAcrossSizeClasses() {
        let forum = ForumHubRoutePolicy.route(
            for: Forum(
                id: 7,
                name: "测试",
                displayName: "测试吧",
                avatarURL: nil,
                memberCount: 0,
                threadCount: 0
            )
        )
        let route = ReaderSplitThreadRoute(
            threadID: 123,
            forumID: 7,
            initialPostID: 456
        )

        let compact = ForumHubSplitDetailBridgePolicy.state(
            changingTo: .compact,
            navigationPath: [.forum(forum)],
            splitDetail: route
        )
        XCTAssertNil(compact.splitDetail)
        XCTAssertEqual(compact.navigationPath, [.forum(forum), .thread(route)])

        let regular = ForumHubSplitDetailBridgePolicy.state(
            changingTo: .regular,
            navigationPath: compact.navigationPath,
            splitDetail: compact.splitDetail
        )
        XCTAssertEqual(regular.splitDetail, route)
        XCTAssertEqual(regular.navigationPath, [.forum(forum)])
    }

    func testForumHubDetailBridgePreservesExistingDestinationWithoutAWidthChange() {
        let split = ReaderSplitThreadRoute(threadID: 1, forumID: nil)
        let compact = ReaderSplitThreadRoute(threadID: 2, forumID: 3)
        let path: [ForumHubNavigationRoute] = [.thread(compact)]

        XCTAssertEqual(
            ForumHubSplitDetailBridgePolicy.state(
                changingTo: nil,
                navigationPath: path,
                splitDetail: split
            ),
            ForumHubSplitDetailBridgeState(
                navigationPath: path,
                splitDetail: split
            )
        )
    }

    func testNestedForumThreadUsesParentReaderRouteWheneverItIsInjected() {
        XCTAssertEqual(
            ForumThreadsOpenRoutingPolicy.destination(hasParentHandler: true),
            .parentReader
        )
        XCTAssertEqual(
            ForumThreadsOpenRoutingPolicy.destination(hasParentHandler: false),
            .localStack
        )
    }

    func testForumHubDetailBridgeKeepsExactlyOneRouteAcrossRepeatedWidthChanges() {
        let route = ReaderSplitThreadRoute(threadID: 777, forumID: 8)
        var state = ForumHubSplitDetailBridgeState(
            navigationPath: [.thread(route)],
            splitDetail: nil
        )

        for _ in 0..<5 {
            state = ForumHubSplitDetailBridgePolicy.state(
                changingTo: .regular,
                navigationPath: state.navigationPath,
                splitDetail: state.splitDetail
            )
            XCTAssertEqual(state.splitDetail, route)
            XCTAssertTrue(state.navigationPath.isEmpty)

            state = ForumHubSplitDetailBridgePolicy.state(
                changingTo: .compact,
                navigationPath: state.navigationPath,
                splitDetail: state.splitDetail
            )
            XCTAssertNil(state.splitDetail)
            XCTAssertEqual(state.navigationPath, [.thread(route)])
        }
    }

    func testForumHubDetailBridgePreservesSearchPrefixWhenMovingThread() {
        let forum = ForumHubRoutePolicy.route(
            for: Forum(
                id: 9,
                name: "测试",
                displayName: "测试吧",
                avatarURL: nil,
                memberCount: 0,
                threadCount: 0
            )
        )
        let search = ForumHubSearchRoute(forum: forum, keyword: "关键词")
        let thread = ReaderSplitThreadRoute(
            threadID: 901,
            forumID: 9,
            initialPostID: 902
        )
        let compactPath: [ForumHubNavigationRoute] = [
            .forum(forum),
            .search(search),
            .thread(thread)
        ]

        let regular = ForumHubSplitDetailBridgePolicy.state(
            changingTo: .regular,
            navigationPath: compactPath,
            splitDetail: nil
        )
        XCTAssertEqual(
            regular.navigationPath,
            [.forum(forum), .search(search)]
        )
        XCTAssertEqual(regular.splitDetail, thread)

        let compact = ForumHubSplitDetailBridgePolicy.state(
            changingTo: .compact,
            navigationPath: regular.navigationPath,
            splitDetail: regular.splitDetail
        )
        XCTAssertEqual(compact.navigationPath, compactPath)
        XCTAssertNil(compact.splitDetail)
    }

    func testForumHubDetailBridgeDoesNotDuplicateThreadBeneathChildRoute() {
        let forum = ForumHubRoutePolicy.route(
            for: Forum(
                id: 9,
                name: "测试",
                displayName: "测试吧",
                avatarURL: nil,
                memberCount: 0,
                threadCount: 0
            )
        )
        let thread = ReaderSplitThreadRoute(threadID: 901, forumID: 9)
        let user = UserSummary(
            id: 902,
            name: "tester",
            displayName: "测试用户",
            portrait: ""
        )
        let nestedPath: [ForumHubNavigationRoute] = [
            .forum(forum),
            .thread(thread),
            .user(user: user, sourceThreadID: thread.threadID)
        ]

        let regular = ForumHubSplitDetailBridgePolicy.state(
            changingTo: .regular,
            navigationPath: nestedPath,
            splitDetail: nil
        )
        XCTAssertEqual(regular.navigationPath, nestedPath)
        XCTAssertNil(regular.splitDetail)

        let compact = ForumHubSplitDetailBridgePolicy.state(
            changingTo: .compact,
            navigationPath: regular.navigationPath,
            splitDetail: thread
        )
        XCTAssertEqual(compact.navigationPath, nestedPath)
        XCTAssertNil(compact.splitDetail)
    }

    func testThreadDetailSearchStaysOnParentTypedPathBeforeMetadataLoads() {
        XCTAssertEqual(
            ThreadDetailSearchOpenRoutingPolicy.destination(
                hasParentHandler: true
            ),
            .parentPath
        )
        XCTAssertEqual(
            ThreadDetailSearchOpenRoutingPolicy.destination(
                hasParentHandler: false
            ),
            .localSearch
        )
    }

    func testForumHubSearchInfersForumFromTypedPathBeforeThreadLoads() {
        let forum = ForumHubRoutePolicy.route(
            for: Forum(
                id: 9,
                name: "测试",
                displayName: "测试吧",
                avatarURL: nil,
                memberCount: 0,
                threadCount: 0
            )
        )
        let thread = ReaderSplitThreadRoute(threadID: 901, forumID: 9)

        let route = ForumHubSearchRoutePolicy.route(
            scope: .global,
            keyword: "",
            navigationPath: [.forum(forum), .thread(thread)]
        )

        XCTAssertEqual(
            route,
            ForumHubSearchRoute(forum: forum, keyword: "")
        )
        XCTAssertNil(
            ForumHubSearchRoutePolicy.route(
                scope: .global,
                keyword: "",
                navigationPath: [.thread(thread)]
            )
        )
    }

    func testMyFollowedForumPresentationFiltersWithoutMutatingServiceItems() {
        let original = [
            Forum(
                id: 1,
                name: "隐藏",
                displayName: "隐藏吧",
                avatarURL: nil,
                memberCount: 1,
                threadCount: 1
            ),
            Forum(
                id: 2,
                name: "公开",
                displayName: "公开吧",
                avatarURL: nil,
                memberCount: 2,
                threadCount: 2
            )
        ]
        let blocklist = BlocklistSnapshot(entries: [
            BlocklistEntry(kind: .forum, value: "隐藏吧", userID: nil)
        ])

        let visible = ForumListPresentationPolicy.visibleForums(
            original,
            searchText: "",
            blocklist: blocklist
        )

        XCTAssertEqual(visible.map(\.id), [2])
        XCTAssertEqual(original.map(\.id), [1, 2])
        XCTAssertEqual(
            ForumListPresentationPolicy.emptyState(
                hasStoredForums: true,
                hasSearchText: false
            ),
            ForumListEmptyState(
                title: "没有可显示的关注贴吧",
                message: "已按你的屏蔽设置隐藏相关贴吧。"
            )
        )
    }

    func testBrowsingHistoryPresentationFiltersAvailableFieldsAndDeletesVisibleID() {
        let now = Date(timeIntervalSince1970: 100)
        let original = [
            BrowsingHistoryEntry(
                threadID: 1,
                title: "含有剧透",
                authorDisplayName: "甲",
                forumDisplayName: "公开吧",
                visitedAt: now
            ),
            BrowsingHistoryEntry(
                threadID: 2,
                title: "普通标题",
                authorDisplayName: "被屏蔽用户",
                forumDisplayName: "公开吧",
                visitedAt: now
            ),
            BrowsingHistoryEntry(
                threadID: 3,
                title: "普通标题",
                authorDisplayName: "乙",
                forumDisplayName: "隐藏吧",
                visitedAt: now
            ),
            BrowsingHistoryEntry(
                threadID: 4,
                title: "保留标题",
                authorDisplayName: "丙",
                forumDisplayName: "公开吧",
                visitedAt: now
            )
        ]
        let blocklist = localLibraryTestBlocklist

        let visible = BrowsingHistoryListPolicy.visibleEntries(
            original,
            blocklist: blocklist
        )

        XCTAssertEqual(visible.map(\.threadID), [4])
        XCTAssertEqual(original.map(\.threadID), [1, 2, 3, 4])
        XCTAssertEqual(
            BrowsingHistoryListPolicy.threadIDs(at: IndexSet(integer: 0), in: visible),
            [4]
        )
        XCTAssertTrue(
            BrowsingHistoryListPolicy.threadIDs(at: IndexSet(integer: 3), in: visible).isEmpty
        )
    }

    func testThreadFavoritesPresentationFiltersAvailableFieldsAndDeletesVisibleID() {
        let now = Date(timeIntervalSince1970: 100)
        let original = [
            ThreadFavoriteEntry(
                threadID: 1,
                title: "含有剧透",
                authorDisplayName: "甲",
                forumDisplayName: "公开吧",
                savedAt: now
            ),
            ThreadFavoriteEntry(
                threadID: 2,
                title: "普通标题",
                authorDisplayName: "被屏蔽用户",
                forumDisplayName: "公开吧",
                savedAt: now
            ),
            ThreadFavoriteEntry(
                threadID: 3,
                title: "普通标题",
                authorDisplayName: "乙",
                forumDisplayName: "隐藏吧",
                savedAt: now
            ),
            ThreadFavoriteEntry(
                threadID: 4,
                title: "保留标题",
                authorDisplayName: "丙",
                forumDisplayName: "公开吧",
                savedAt: now
            )
        ]
        let blocklist = localLibraryTestBlocklist

        let visible = ThreadFavoritesListPolicy.visibleFavorites(
            original,
            blocklist: blocklist
        )

        XCTAssertEqual(visible.map(\.threadID), [4])
        XCTAssertEqual(original.map(\.threadID), [1, 2, 3, 4])
        XCTAssertEqual(
            ThreadFavoritesListPolicy.threadIDs(at: IndexSet(integer: 0), in: visible),
            [4]
        )
        XCTAssertTrue(
            ThreadFavoritesListPolicy.threadIDs(at: IndexSet(integer: 3), in: visible).isEmpty
        )
    }

    private var localLibraryTestBlocklist: BlocklistSnapshot {
        BlocklistSnapshot(entries: [
            BlocklistEntry(kind: .keyword, value: "剧透", userID: nil),
            BlocklistEntry(kind: .user, value: "被屏蔽用户", userID: nil),
            BlocklistEntry(kind: .forum, value: "隐藏吧", userID: nil)
        ])
    }

    func testInteractionStatsLayoutPlacesCommentsAndLikesAtThirds() {
        XCTAssertEqual(InteractionStatsLayout.xPosition(for: .comments, in: 300), 100)
        XCTAssertEqual(InteractionStatsLayout.xPosition(for: .likes, in: 300), 200)
        XCTAssertEqual(InteractionStatsLayout.xPosition(for: .comments, in: 390), 130)
        XCTAssertEqual(InteractionStatsLayout.xPosition(for: .likes, in: 390), 260)
    }

    func testHomeMediaActionPolicyPlaysVideoFromFeed() {
        let video = VideoContent(
            videoURL: URL(string: "https://video.example/a.mp4"),
            coverURL: URL(string: "https://video.example/cover.jpg"),
            webURL: nil,
            width: 1280,
            height: 720,
            duration: 12
        )
        let item = ReaderMediaItem(
            id: "video",
            kind: .video,
            thumbnailURL: video.coverURL,
            video: video,
            aspectRatio: 16.0 / 9.0,
            accessibilityLabel: "Thread video"
        )

        XCTAssertEqual(HomeMediaActionPolicy.action(for: item), .playVideo(video))
    }

    func testHomeMediaActionPolicyPreviewsImageGroupFromFeed() {
        let first = ImageContent(
            thumbnailURL: URL(string: "https://image.example/thumb.jpg"),
            originalURL: URL(string: "https://image.example/original.jpg"),
            width: 800,
            height: 600,
            showOriginalButton: false
        )
        let second = ImageContent(
            thumbnailURL: URL(string: "https://image.example/two-thumb.jpg"),
            originalURL: URL(string: "https://image.example/two-original.jpg"),
            width: 900,
            height: 600,
            showOriginalButton: false
        )
        let firstItem = ReaderMediaItem(
            id: "image-1",
            kind: .image,
            thumbnailURL: first.thumbnailURL,
            image: first,
            aspectRatio: 4.0 / 3.0,
            accessibilityLabel: "Thread image"
        )
        let secondItem = ReaderMediaItem(
            id: "image-2",
            kind: .image,
            thumbnailURL: second.thumbnailURL,
            image: second,
            aspectRatio: 3.0 / 2.0,
            accessibilityLabel: "Thread image"
        )

        XCTAssertEqual(
            HomeMediaActionPolicy.action(for: secondItem, in: [firstItem, secondItem]),
            .previewImages([first, second], index: 1)
        )
    }

    func testTiebaLiteFeedMediaLayoutUsesStablePreviewRatios() {
        XCTAssertEqual(TiebaLiteMediaLayoutPolicy.visibleItemCount(totalCount: 1), 1)
        XCTAssertEqual(TiebaLiteMediaLayoutPolicy.visibleItemCount(totalCount: 5), 3)
        XCTAssertEqual(TiebaLiteMediaLayoutPolicy.containerAspectRatio(totalCount: 1), 2)
        XCTAssertEqual(TiebaLiteMediaLayoutPolicy.containerAspectRatio(totalCount: 2), 3)
        XCTAssertEqual(TiebaLiteMediaLayoutPolicy.thumbnailAspectRatio(totalCount: 1, visibleCount: 1), 2)
        XCTAssertEqual(TiebaLiteMediaLayoutPolicy.thumbnailAspectRatio(totalCount: 2, visibleCount: 2), 1.5)
        XCTAssertEqual(TiebaLiteMediaLayoutPolicy.thumbnailAspectRatio(totalCount: 3, visibleCount: 3), 1)
        XCTAssertTrue(TiebaLiteMediaLayoutPolicy.showsMoreBadge(totalCount: 4, visibleCount: 3))
    }

    func testTiebaLiteFeedMediaLayoutProducesBoundedContainerHeight() {
        XCTAssertEqual(
            TiebaLiteMediaLayoutPolicy.containerHeight(containerWidth: 320, totalCount: 1),
            160
        )
        XCTAssertEqual(
            TiebaLiteMediaLayoutPolicy.containerHeight(containerWidth: 320, totalCount: 2),
            320.0 / 3.0,
            accuracy: 0.001
        )
        XCTAssertEqual(
            TiebaLiteMediaLayoutPolicy.containerHeight(containerWidth: 320, totalCount: 9),
            320.0 / 3.0,
            accuracy: 0.001
        )
    }

    func testTiebaImageRequestsUseTiebaHeadersAndCache() throws {
        let url = try XCTUnwrap(URL(string: "https://tiebapic.baidu.com/forum/pic/item/demo.jpg"))

        let request = TiebaImageRequestPolicy.request(for: url)

        XCTAssertEqual(request.cachePolicy, .returnCacheDataElseLoad)
        XCTAssertEqual(request.timeoutInterval, 20)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Referer"), "https://tieba.baidu.com/")
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "tieba/12.52.1.0 skin/default")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "image/avif,image/webp,image/apng,image/*,*/*;q=0.8")
    }

    func testTiebaImageRetryPolicyOnlyRetriesTransientFailures() {
        XCTAssertTrue(TiebaImageRequestPolicy.shouldRetry(statusCode: 408, attempt: 0))
        XCTAssertTrue(TiebaImageRequestPolicy.shouldRetry(statusCode: 429, attempt: 1))
        XCTAssertTrue(TiebaImageRequestPolicy.shouldRetry(statusCode: 503, attempt: 0))
        XCTAssertFalse(TiebaImageRequestPolicy.shouldRetry(statusCode: 404, attempt: 0))
        XCTAssertFalse(TiebaImageRequestPolicy.shouldRetry(statusCode: 503, attempt: 2))
    }

    func testTiebaImageSourcePolicyKeepsThumbnailThenOriginalWithoutDuplicates() throws {
        let thumbnail = try XCTUnwrap(URL(string: "https://tiebapic.baidu.com/thumb.jpg"))
        let original = try XCTUnwrap(URL(string: "https://tiebapic.baidu.com/original.jpg"))

        XCTAssertEqual(
            TiebaImageSourcePolicy.urls(primary: thumbnail, fallback: original),
            [thumbnail, original]
        )
        XCTAssertEqual(
            TiebaImageSourcePolicy.urls(primary: thumbnail, fallback: thumbnail),
            [thumbnail]
        )

        let insecure = try XCTUnwrap(URL(string: "http://tiebapic.baidu.com/private.jpg"))
        let privateTarget = try XCTUnwrap(URL(string: "https://127.0.0.1/private.jpg"))
        XCTAssertEqual(
            TiebaImageSourcePolicy.urls(primary: insecure, fallback: original),
            [URL(string: "https://tiebapic.baidu.com/private.jpg")!, original]
        )
        XCTAssertTrue(
            TiebaImageSourcePolicy.urls(
                primary: URL(fileURLWithPath: "/tmp/private.png"),
                fallback: privateTarget
            ).isEmpty
        )
    }

    func testFullScreenImageSourcePolicySeparatesPreviewOriginalAndDownload() throws {
        let thumbnail = try XCTUnwrap(URL(string: "https://example.com/photo-thumbnail.jpg"))
        let original = try XCTUnwrap(URL(string: "https://example.com/photo-original.jpg"))

        let sources = FullScreenImageSourcePolicy.sources(
            thumbnail: thumbnail,
            original: original
        )
        XCTAssertEqual(sources.previewURL, thumbnail)
        XCTAssertEqual(sources.originalURL, original)
        XCTAssertEqual(sources.downloadURL, original)

        let thumbnailOnly = FullScreenImageSourcePolicy.sources(
            thumbnail: thumbnail,
            original: nil
        )
        XCTAssertEqual(thumbnailOnly.previewURL, thumbnail)
        XCTAssertNil(thumbnailOnly.originalURL)
        XCTAssertEqual(thumbnailOnly.downloadURL, thumbnail)
    }

    func testOriginalImageOnlyLoadsFromAnExplicitAvailableOrRetryState() {
        XCTAssertTrue(FullScreenOriginalImageLoadState.available.canRequest)
        XCTAssertTrue(FullScreenOriginalImageLoadState.failed.canRequest)
        XCTAssertFalse(FullScreenOriginalImageLoadState.unavailable.canRequest)
        XCTAssertFalse(FullScreenOriginalImageLoadState.loading.canRequest)
        XCTAssertFalse(FullScreenOriginalImageLoadState.loaded.canRequest)
    }

    func testOriginalImageLoadAlwaysWinsOverLatePreviewCompletion() {
        XCTAssertFalse(FullScreenImageLoadPrecedencePolicy.acceptsPreview(
            while: .loading
        ))
        XCTAssertFalse(FullScreenImageLoadPrecedencePolicy.acceptsPreview(
            while: .loaded
        ))
        XCTAssertTrue(FullScreenImageLoadPrecedencePolicy.acceptsPreview(
            while: .available
        ))
        XCTAssertTrue(FullScreenImageLoadPrecedencePolicy.acceptsPreview(
            while: .failed
        ))
    }

    func testOriginalImageFailureRestoresPreviewOnlyWhenNothingIsDisplayed() {
        XCTAssertTrue(FullScreenImageLoadPrecedencePolicy
            .resumesPreviewAfterOriginalFailure(hasResolvedImage: false))
        XCTAssertFalse(FullScreenImageLoadPrecedencePolicy
            .resumesPreviewAfterOriginalFailure(hasResolvedImage: true))
    }

    func testFullScreenImagePlaceholderReuseRequiresMatchingAspectRatio() {
        XCTAssertTrue(FullScreenImagePlaceholderPolicy.canReuseAsPreview(
            placeholderSize: CGSize(width: 120, height: 480),
            imageAspectRatio: 0.25
        ))
        XCTAssertFalse(FullScreenImagePlaceholderPolicy.canReuseAsPreview(
            placeholderSize: CGSize(width: 240, height: 240),
            imageAspectRatio: 0.25
        ))
        XCTAssertFalse(FullScreenImagePlaceholderPolicy.canReuseAsPreview(
            placeholderSize: nil,
            imageAspectRatio: 0.25
        ))
    }

    func testSyntheticFixtureImageFailureNeverUsesNetwork() throws {
        let fixture = try XCTUnwrap(URL(string: "https://fixture.invalid/long-image.png"))
        let lookalike = try XCTUnwrap(URL(string: "https://fixture.invalid.example/long-image.png"))
        let wrongScheme = try XCTUnwrap(URL(string: "http://fixture.invalid/long-image.png"))

        XCTAssertTrue(TiebaImageSourcePolicy.isSyntheticFailureURL(fixture))
        XCTAssertFalse(TiebaImageSourcePolicy.isSyntheticFailureURL(lookalike))
        XCTAssertFalse(TiebaImageSourcePolicy.isSyntheticFailureURL(wrongScheme))
    }

    func testSyntheticFixtureImageSuccessRequiresExactHTTPSHost() throws {
        let fixture = try XCTUnwrap(URL(string: "https://fixture-success.invalid/long-image.png"))
        let lookalike = try XCTUnwrap(URL(string: "https://fixture-success.invalid.example/long-image.png"))
        let wrongScheme = try XCTUnwrap(URL(string: "http://fixture-success.invalid/long-image.png"))

        XCTAssertTrue(TiebaImageSourcePolicy.isSyntheticSuccessURL(fixture))
        XCTAssertFalse(TiebaImageSourcePolicy.isSyntheticSuccessURL(lookalike))
        XCTAssertFalse(TiebaImageSourcePolicy.isSyntheticSuccessURL(wrongScheme))
    }

    func testTiebaLiteInlineImageLayoutKeepsWideImagesShallowInThreadDetail() {
        let wideImage = ImageContent(
            thumbnailURL: URL(string: "https://image.example/wide-thumb.jpg"),
            originalURL: URL(string: "https://image.example/wide-original.jpg"),
            width: 4_000,
            height: 500,
            showOriginalButton: false
        )

        XCTAssertEqual(TiebaLiteInlineImageLayoutPolicy.aspectRatio(for: wideImage), 8)
        XCTAssertEqual(
            TiebaLiteInlineImageLayoutPolicy.height(containerWidth: 320, image: wideImage),
            40
        )
        XCTAssertEqual(TiebaLiteMediaLayoutPolicy.thumbnailAspectRatio(totalCount: 1, visibleCount: 1), 2)
    }

    func testFullScreenImageSwipePolicySwitchesImagesWithoutDismiss() {
        XCTAssertEqual(
            FullScreenImageSwipePolicy.action(for: CGSize(width: -120, height: 8), currentIndex: 0, totalCount: 3),
            .next
        )
        XCTAssertEqual(
            FullScreenImageSwipePolicy.action(for: CGSize(width: 120, height: 8), currentIndex: 1, totalCount: 3),
            .previous
        )
        XCTAssertEqual(
            FullScreenImageSwipePolicy.action(for: CGSize(width: 120, height: 8), currentIndex: 0, totalCount: 3),
            .none
        )
    }

    func testFullScreenImageDismissGestureOnlyClaimsSupportedDirectionsAtRest() {
        XCTAssertEqual(
            FullScreenImageDismissGesturePolicy.axis(
                velocity: CGPoint(x: 900, y: 20),
                isFirstImage: true,
                isZoomed: false
            ),
            .horizontalRight
        )
        XCTAssertNil(FullScreenImageDismissGesturePolicy.axis(
            velocity: CGPoint(x: 900, y: 20),
            isFirstImage: false,
            isZoomed: false
        ))
        XCTAssertNil(FullScreenImageDismissGesturePolicy.axis(
            velocity: CGPoint(x: -900, y: 20),
            isFirstImage: true,
            isZoomed: false
        ))
        XCTAssertEqual(
            FullScreenImageDismissGesturePolicy.axis(
                velocity: CGPoint(x: 20, y: -900),
                isFirstImage: false,
                isZoomed: false
            ),
            .vertical
        )
        XCTAssertNil(FullScreenImageDismissGesturePolicy.axis(
            velocity: CGPoint(x: 20, y: 900),
            isFirstImage: true,
            isZoomed: true
        ))
        XCTAssertEqual(
            FullScreenImageDismissGesturePolicy.axis(
                velocity: CGPoint(x: 900, y: 800),
                isFirstImage: false,
                isZoomed: false
            ),
            .vertical,
            "斜向手势必须由退出手势接管，不能落入方向死区"
        )
        XCTAssertNil(FullScreenImageDismissGesturePolicy.axis(
            velocity: .zero,
            isFirstImage: true,
            isZoomed: false
        ))
    }

    func testFullScreenImageDismissMovementPreservesDiagonalTranslation() {
        XCTAssertEqual(
            FullScreenImageDismissGesturePolicy.adjustedTranslation(
                CGPoint(x: 48, y: 96),
                for: .vertical
            ),
            CGPoint(x: 48, y: 96)
        )
        XCTAssertEqual(
            FullScreenImageDismissGesturePolicy.adjustedTranslation(
                CGPoint(x: 96, y: 48),
                for: .horizontalRight
            ),
            CGPoint(x: 96, y: 48)
        )
        XCTAssertEqual(
            FullScreenImageDismissGesturePolicy.adjustedTranslation(
                CGPoint(x: -24, y: 48),
                for: .horizontalRight
            ),
            CGPoint(x: 0, y: 48),
            "首图右划退出不能在手指回拉时向左越界"
        )
    }

    func testFullScreenImageDismissThresholdRequiresDistanceOrIntentionalFlick() {
        let viewport = CGSize(width: 390, height: 844)
        XCTAssertFalse(FullScreenImageDismissGesturePolicy.shouldDismiss(
            translation: CGPoint(x: 60, y: 0),
            velocity: CGPoint(x: 400, y: 0),
            axis: .horizontalRight,
            viewportSize: viewport
        ))
        XCTAssertTrue(FullScreenImageDismissGesturePolicy.shouldDismiss(
            translation: CGPoint(x: 100, y: 0),
            velocity: CGPoint(x: 400, y: 0),
            axis: .horizontalRight,
            viewportSize: viewport
        ))
        XCTAssertFalse(FullScreenImageDismissGesturePolicy.shouldDismiss(
            translation: CGPoint(x: 0, y: 100),
            velocity: CGPoint(x: 0, y: 400),
            axis: .vertical,
            viewportSize: viewport
        ))
        XCTAssertTrue(FullScreenImageDismissGesturePolicy.shouldDismiss(
            translation: CGPoint(x: 0, y: -160),
            velocity: CGPoint(x: 0, y: -400),
            axis: .vertical,
            viewportSize: viewport
        ))
        XCTAssertTrue(FullScreenImageDismissGesturePolicy.shouldDismiss(
            translation: CGPoint(x: 0, y: 65),
            velocity: CGPoint(x: 0, y: 1_100),
            axis: .vertical,
            viewportSize: viewport
        ))
    }

    func testOriginalImageProgressAndFileSizeFormatting() {
        XCTAssertEqual(
            BoundedURLSessionProgress(receivedBytes: 1_835_008, expectedBytes: 3_670_016)
                .fractionCompleted ?? -1,
            0.5,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            BoundedURLSessionProgress(receivedBytes: 4, expectedBytes: 2)
                .fractionCompleted ?? -1,
            1
        )
        XCTAssertNil(BoundedURLSessionProgress(
            receivedBytes: 10,
            expectedBytes: nil
        ).fractionCompleted)
        XCTAssertEqual(
            FullScreenImageFileSizePolicy.displayString(byteCount: 3_670_016),
            "3.5MB"
        )
        XCTAssertEqual(
            FullScreenImageFileSizePolicy.displayString(byteCount: 1_048_576),
            "1MB"
        )
        XCTAssertEqual(
            FullScreenImageFileSizePolicy.displayString(byteCount: 1_536),
            "1.5KB"
        )
        XCTAssertNil(FullScreenImageFileSizePolicy.displayString(byteCount: 0))
    }

    func testImageMetadataContentRangeRequiresAValidTotalLength() throws {
        XCTAssertEqual(
            TiebaImageMetadataPolicy.totalByteCount(
                fromContentRange: "bytes 0-0/3670016"
            ),
            3_670_016
        )
        XCTAssertNil(TiebaImageMetadataPolicy.totalByteCount(
            fromContentRange: "bytes 0-0/*"
        ))
        XCTAssertNil(TiebaImageMetadataPolicy.totalByteCount(
            fromContentRange: "bytes 2-1/100"
        ))
        XCTAssertNil(TiebaImageMetadataPolicy.totalByteCount(
            fromContentRange: "not-a-range"
        ))

        let url = try XCTUnwrap(URL(string: "https://example.com/photo.jpg"))
        let validPartial = try XCTUnwrap(HTTPURLResponse(
            url: url,
            statusCode: 206,
            httpVersion: nil,
            headerFields: ["Content-Range": "bytes 0-0/3670016"]
        ))
        XCTAssertEqual(TiebaImageMetadataPolicy.contentLength(from: validPartial), 3_670_016)

        let unknownPartial = try XCTUnwrap(HTTPURLResponse(
            url: url,
            statusCode: 206,
            httpVersion: nil,
            headerFields: [
                "Content-Range": "bytes 0-0/*",
                "Content-Length": "1"
            ]
        ))
        XCTAssertNil(TiebaImageMetadataPolicy.contentLength(from: unknownPartial))
    }

    func testFullScreenImageZoomPolicyClampsAndTogglesAtStableScales() {
        XCTAssertEqual(FullScreenImageZoomPolicy.clampedScale(0.5), 1)
        XCTAssertEqual(FullScreenImageZoomPolicy.clampedScale(5), 4)
        XCTAssertEqual(FullScreenImageZoomPolicy.normalizedScale(1.005), 1)
        XCTAssertFalse(FullScreenImageZoomPolicy.isZoomed(1))
        XCTAssertTrue(FullScreenImageZoomPolicy.isZoomed(1.5))
        XCTAssertEqual(FullScreenImageZoomPolicy.doubleTapTarget(currentScale: 1), 2)
        XCTAssertEqual(FullScreenImageZoomPolicy.doubleTapTarget(currentScale: 2), 1)
    }

    func testImagePreviewKeepsSourceImageUntilSystemTransitionAndDecodeFinish() {
        XCTAssertFalse(ImagePreviewResolvedImageVisibilityPolicy.showsResolvedContent(
            hasPlaceholder: true,
            didFinishPresentation: false,
            loadState: .success
        ))
        XCTAssertFalse(ImagePreviewResolvedImageVisibilityPolicy.showsResolvedContent(
            hasPlaceholder: true,
            didFinishPresentation: true,
            loadState: .loading
        ))
        XCTAssertTrue(ImagePreviewResolvedImageVisibilityPolicy.showsResolvedContent(
            hasPlaceholder: true,
            didFinishPresentation: true,
            loadState: .success
        ))
        XCTAssertTrue(ImagePreviewResolvedImageVisibilityPolicy.showsResolvedContent(
            hasPlaceholder: false,
            didFinishPresentation: false,
            loadState: .loading
        ))
    }

    @MainActor
    func testImagePreviewSourceAnchorIsTheSingleVisibleBitmapView() {
        let identity = "fixture-image-a"
        let anchor = ImagePreviewSourceAnchor(sourceIdentity: identity)
        let sourceView = ImagePreviewSourceView()
        anchor.attach(sourceView, sourceIdentity: identity)
        let image = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image {
            $0.cgContext.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
        anchor.store(image: image, sourceIdentity: identity)

        XCTAssertTrue(anchor.image === image)
        XCTAssertTrue(sourceView.image === image)
        XCTAssertFalse(
            sourceView.subviews.contains {
                ($0 as? UIImageView)?.image != nil
            },
            "正式缩略图内部不得再叠加第二张可见图片"
        )

        anchor.clearImage(sourceIdentity: identity)
        XCTAssertNil(anchor.image)
        XCTAssertNil(sourceView.image)
    }

    @MainActor
    func testImagePreviewHeroLeaseKeepsCanonicalAndProxyMutuallyExclusive() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let controller = UIViewController()
        controller.view.frame = window.bounds
        window.rootViewController = controller
        window.makeKeyAndVisible()

        let sourceView = ImagePreviewSourceView()
        sourceView.frame = CGRect(x: 20, y: 140, width: 160, height: 100)
        let image = UIGraphicsImageRenderer(size: CGSize(width: 16, height: 10)).image {
            UIColor.systemPink.setFill()
            $0.fill(CGRect(x: 0, y: 0, width: 16, height: 10))
        }
        sourceView.image = image
        controller.view.addSubview(sourceView)
        let initialProxyCount = ImagePreviewHeroProxyView.activeCount

        let lease = ImagePreviewHeroSourceLease(
            sourceView: sourceView,
            image: image,
            sourceIdentity: nil,
            containerView: controller.view,
            imageFrame: sourceView.frame,
            cornerRadius: 12
        )

        XCTAssertNotNil(lease)
        XCTAssertTrue(sourceView.isHidden)
        XCTAssertFalse(lease?.proxyView.isHidden ?? true)
        XCTAssertTrue(lease?.proxyView.superview === controller.view)
        XCTAssertEqual(
            ImagePreviewHeroProxyView.activeCount,
            initialProxyCount + 1
        )

        lease?.finish()

        XCTAssertFalse(sourceView.isHidden)
        XCTAssertNil(lease?.proxyView.superview)
        XCTAssertEqual(ImagePreviewHeroProxyView.activeCount, initialProxyCount)

        // Cleanup is deliberately idempotent because presentation failure,
        // dismissal completion and view teardown may converge on it.
        lease?.finish()
        XCTAssertFalse(sourceView.isHidden)
        XCTAssertEqual(ImagePreviewHeroProxyView.activeCount, initialProxyCount)
    }

    @MainActor
    func testImagePreviewDismissalTapActivatesVisibleRegisteredSource() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let controller = UIViewController()
        controller.view.frame = window.bounds
        window.rootViewController = controller
        window.makeKeyAndVisible()

        let first = ImagePreviewSourceView()
        first.frame = CGRect(x: 20, y: 120, width: 120, height: 100)
        first.image = UIGraphicsImageRenderer(size: CGSize(width: 12, height: 10))
            .image { _ in }
        first.isHidden = true
        var firstActivationCount = 0
        first.onTransitionTap = { firstActivationCount += 1 }
        controller.view.addSubview(first)

        let second = ImagePreviewSourceView()
        second.frame = CGRect(x: 160, y: 120, width: 120, height: 100)
        second.image = UIGraphicsImageRenderer(size: CGSize(width: 12, height: 10))
            .image { _ in }
        var secondActivationCount = 0
        second.onTransitionTap = { secondActivationCount += 1 }
        controller.view.addSubview(second)

        ImagePreviewSourceRegistry.shared.register(first, identity: "dismiss-first")
        ImagePreviewSourceRegistry.shared.register(second, identity: "dismiss-second")
        defer {
            ImagePreviewSourceRegistry.shared.unregister(first, identity: "dismiss-first")
            ImagePreviewSourceRegistry.shared.unregister(second, identity: "dismiss-second")
        }

        XCTAssertFalse(
            ImagePreviewSourceRegistry.shared.activateSource(
                at: CGPoint(x: 80, y: 170),
                in: window
            ),
            "正在 hero suppression 的原图不得接收重复点按"
        )
        XCTAssertTrue(
            ImagePreviewSourceRegistry.shared.activateSource(
                at: CGPoint(x: 220, y: 170),
                in: window
            )
        )
        XCTAssertEqual(firstActivationCount, 0)
        XCTAssertEqual(secondActivationCount, 1)
    }

    @MainActor
    func testImagePreviewHeroSuppressesAReplacementSourceUntilCleanup() {
        let identity = "fixture-remounted-source"
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let controller = UIViewController()
        controller.view.frame = window.bounds
        window.rootViewController = controller
        window.makeKeyAndVisible()

        let image = UIGraphicsImageRenderer(size: CGSize(width: 16, height: 10)).image {
            UIColor.systemTeal.setFill()
            $0.fill(CGRect(x: 0, y: 0, width: 16, height: 10))
        }
        let source = ImagePreviewSourceView()
        source.frame = CGRect(x: 20, y: 140, width: 160, height: 100)
        source.image = image
        controller.view.addSubview(source)
        ImagePreviewSourceRegistry.shared.register(source, identity: identity)

        let lease = ImagePreviewHeroSourceLease(
            sourceView: source,
            image: image,
            sourceIdentity: identity,
            containerView: controller.view,
            imageFrame: source.frame,
            cornerRadius: 12
        )
        XCTAssertNotNil(lease)
        XCTAssertTrue(source.isHidden)

        let replacement = ImagePreviewSourceView()
        replacement.frame = source.frame
        replacement.image = image
        controller.view.addSubview(replacement)
        ImagePreviewSourceRegistry.shared.register(replacement, identity: identity)
        XCTAssertTrue(
            replacement.isHidden,
            "同 identity 的 SwiftUI 重挂载视图在 hero 存活期间也必须隐藏"
        )

        ImagePreviewSourceRegistry.shared.unregister(source, identity: identity)
        source.removeFromSuperview()
        lease?.finish()

        XCTAssertFalse(replacement.isHidden)
        XCTAssertNil(lease?.proxyView.superview)
        ImagePreviewSourceRegistry.shared.unregister(replacement, identity: identity)
    }

    @MainActor
    func testImagePreviewTransitionUsesTheActualVisibleSourceView() {
        let identity = "fixture-image-source"
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let sourceController = UIViewController()
        sourceController.view.frame = window.bounds
        window.rootViewController = sourceController
        window.makeKeyAndVisible()

        let sourceView = ImagePreviewSourceView()
        sourceView.frame = CGRect(x: 24, y: 180, width: 120, height: 90)
        sourceController.view.addSubview(sourceView)
        let anchor = ImagePreviewSourceAnchor(sourceIdentity: identity)
        anchor.attach(sourceView, sourceIdentity: identity)
        let image = UIGraphicsImageRenderer(size: CGSize(width: 12, height: 9)).image {
            $0.cgContext.setFillColor(UIColor.systemBlue.cgColor)
            $0.cgContext.fill(CGRect(x: 0, y: 0, width: 12, height: 9))
        }
        anchor.store(image: image, sourceIdentity: identity)
        let token = anchor.transitionToken

        let first = ImagePreviewSourceResolver.view(
            exactAnchor: anchor,
            token: token,
            sourceIdentity: identity
        ) as? UIImageView
        XCTAssertTrue(first === sourceView)
        XCTAssertTrue(first?.image === image)
        XCTAssertTrue(first?.superview === sourceController.view)

        sourceView.frame.origin.y = 96
        let moved = ImagePreviewSourceResolver.view(
            exactAnchor: anchor,
            token: token,
            sourceIdentity: identity
        ) as? UIImageView
        XCTAssertTrue(moved === sourceView)
        XCTAssertEqual(
            moved?.convert(moved?.bounds ?? .zero, to: sourceController.view),
            sourceView.frame,
            "图片转场必须始终解析到正在滚动的真实缩略图"
        )
        XCTAssertFalse(
            sourceView.subviews.contains {
                ($0 as? UIImageView)?.image != nil
            }
        )
    }

    @MainActor
    func testImagePreviewTransitionFallbackNeverCombinesReusedImageWithOldGeometry() {
        let oldIdentity = "fixture-image-old"
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let sourceController = UIViewController()
        sourceController.view.frame = window.bounds
        window.rootViewController = sourceController
        window.makeKeyAndVisible()

        let exactView = ImagePreviewSourceView()
        exactView.frame = CGRect(x: 20, y: 120, width: 120, height: 90)
        sourceController.view.addSubview(exactView)
        let anchor = ImagePreviewSourceAnchor(sourceIdentity: oldIdentity)
        anchor.attach(exactView, sourceIdentity: oldIdentity)
        let oldImage = UIGraphicsImageRenderer(size: CGSize(width: 12, height: 9)).image {
            UIColor.systemRed.setFill()
            $0.fill(CGRect(x: 0, y: 0, width: 12, height: 9))
        }
        anchor.store(image: oldImage, sourceIdentity: oldIdentity)
        let session = ImagePreviewSession(
            images: [],
            initialIndex: 0,
            sourceFrame: exactView.frame,
            sourceImage: oldImage,
            sourceAnchor: anchor,
            sourceIdentity: oldIdentity
        )

        let fallbackView = ImagePreviewSourceView()
        fallbackView.frame = CGRect(x: 220, y: 260, width: 120, height: 90)
        fallbackView.image = oldImage
        sourceController.view.addSubview(fallbackView)
        ImagePreviewSourceRegistry.shared.register(fallbackView, identity: oldIdentity)
        defer {
            ImagePreviewSourceRegistry.shared.unregister(fallbackView, identity: oldIdentity)
        }

        let reusedView = ImagePreviewSourceView()
        reusedView.frame = exactView.frame
        sourceController.view.addSubview(reusedView)
        anchor.attach(reusedView, sourceIdentity: "fixture-image-new")
        let reusedImage = UIGraphicsImageRenderer(size: CGSize(width: 9, height: 12)).image {
            UIColor.systemBlue.setFill()
            $0.fill(CGRect(x: 0, y: 0, width: 9, height: 12))
        }
        anchor.store(image: reusedImage, sourceIdentity: "fixture-image-new")

        let resolved = ImagePreviewSourceResolver.view(
            exactAnchor: anchor,
            token: session.sourceToken,
            sourceIdentity: session.sourceIdentity
        ) as? UIImageView

        XCTAssertTrue(resolved === fallbackView)
        XCTAssertEqual(
            resolved?.convert(resolved?.bounds ?? .zero, to: sourceController.view),
            fallbackView.frame
        )
        XCTAssertTrue(resolved?.image === oldImage)
        XCTAssertFalse(resolved?.image === reusedImage)
    }

    @MainActor
    func testImagePreviewTransitionRejectsAncestorClippedSource() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let controller = UIViewController()
        controller.view.frame = window.bounds
        window.rootViewController = controller
        window.makeKeyAndVisible()

        let scrollView = UIScrollView(frame: CGRect(x: 0, y: 100, width: 390, height: 100))
        scrollView.clipsToBounds = true
        controller.view.addSubview(scrollView)
        let source = ImagePreviewSourceView()
        source.frame = CGRect(x: 20, y: 80, width: 120, height: 50)
        scrollView.addSubview(source)

        XCTAssertNil(ImagePreviewTransitionGeometry.fullyVisibleFrame(of: source, in: window))

        source.frame.origin.y = 20
        XCTAssertNotNil(ImagePreviewTransitionGeometry.fullyVisibleFrame(of: source, in: window))

        source.isHidden = true
        XCTAssertNil(ImagePreviewTransitionGeometry.fullyVisibleFrame(of: source, in: window))
        source.isHidden = false
        source.alpha = 0
        XCTAssertNil(ImagePreviewTransitionGeometry.fullyVisibleFrame(of: source, in: window))
    }

    @MainActor
    func testImagePreviewSourceRejectsTokenAfterListCellIsReused() {
        let anchor = ImagePreviewSourceAnchor(sourceIdentity: "fixture-image-a")
        let oldToken = anchor.transitionToken
        let oldImage = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image {
            $0.cgContext.setFillColor(UIColor.red.cgColor)
            $0.cgContext.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
        anchor.store(image: oldImage, sourceIdentity: "fixture-image-a")

        let reusedSourceView = ImagePreviewSourceView()
        anchor.attach(reusedSourceView, sourceIdentity: "fixture-image-b")

        XCTAssertNil(anchor.image)
        XCTAssertNil(reusedSourceView.image)
        XCTAssertNotEqual(anchor.transitionToken, oldToken)
    }

    @MainActor
    func testImagePreviewPrefersExactTappedSourceOverLaterRegistryEntry() {
        let identity = "fixture-shared-image"
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let exactSource = ImagePreviewSourceView()
        exactSource.frame = CGRect(x: 20, y: 100, width: 120, height: 120)
        window.addSubview(exactSource)
        let image = UIGraphicsImageRenderer(size: CGSize(width: 12, height: 12)).image {
            UIColor.systemGreen.setFill()
            $0.fill(CGRect(x: 0, y: 0, width: 12, height: 12))
        }
        exactSource.image = image

        let laterRegistrySource = ImagePreviewSourceView()
        laterRegistrySource.frame = CGRect(x: 200, y: 300, width: 120, height: 120)
        laterRegistrySource.image = image
        window.addSubview(laterRegistrySource)
        ImagePreviewSourceRegistry.shared.register(laterRegistrySource, identity: identity)
        defer {
            ImagePreviewSourceRegistry.shared.unregister(laterRegistrySource, identity: identity)
        }

        let anchor = ImagePreviewSourceAnchor(sourceIdentity: identity)
        anchor.attach(exactSource, sourceIdentity: identity)
        anchor.store(image: image, sourceIdentity: identity)
        let resolved = ImagePreviewSourceResolver.view(
            exactAnchor: anchor,
            token: anchor.transitionToken,
            sourceIdentity: identity
        )

        XCTAssertTrue(
            resolved === exactSource,
            "同一内容暂时出现多个 Cell 时，转场必须回到真正被点击的 source"
        )
        XCTAssertEqual(
            ImagePreviewSourceResolver.frameInWindow(
                exactAnchor: anchor,
                token: anchor.transitionToken,
                sourceIdentity: identity
            ),
            CGRect(x: 20, y: 100, width: 120, height: 120),
            "结束转场必须重新读取当前 source 几何，不能复用打开时缓存的 CGRect"
        )
    }

    func testImagePreviewLifecycleKeepsDismissalBusyUntilUIKitCompletion() {
        let first = UUID()
        let second = UUID()
        var lifecycle = ImagePreviewLifecycle()

        XCTAssertTrue(lifecycle.beginPresentation(sessionID: first))
        XCTAssertEqual(lifecycle.phase, .presenting(first))
        XCTAssertTrue(lifecycle.finishPresentation(sessionID: first))
        XCTAssertEqual(lifecycle.phase, .presented(first))
        XCTAssertTrue(lifecycle.beginDismissal(sessionID: first))
        XCTAssertEqual(lifecycle.phase, .dismissing(first))

        XCTAssertFalse(
            lifecycle.beginPresentation(sessionID: second),
            "旧图片真正完成 dismissal 前，新图片必须排队而不是向 UIKit 重复 present"
        )
        XCTAssertEqual(lifecycle.phase, .dismissing(first))

        XCTAssertTrue(lifecycle.finish(sessionID: first))
        XCTAssertTrue(lifecycle.beginPresentation(sessionID: second))
        XCTAssertEqual(lifecycle.phase, .presenting(second))
    }

    func testImagePreviewLifecycleRollsBackCancelledTransitions() {
        let presentationID = UUID()
        var presentationLifecycle = ImagePreviewLifecycle()
        XCTAssertTrue(
            presentationLifecycle.beginPresentation(sessionID: presentationID)
        )
        XCTAssertTrue(
            presentationLifecycle.cancelPresentation(sessionID: presentationID)
        )
        XCTAssertEqual(presentationLifecycle.phase, .idle)

        let dismissalID = UUID()
        var dismissalLifecycle = ImagePreviewLifecycle()
        XCTAssertTrue(dismissalLifecycle.beginPresentation(sessionID: dismissalID))
        XCTAssertTrue(dismissalLifecycle.finishPresentation(sessionID: dismissalID))
        XCTAssertTrue(dismissalLifecycle.beginDismissal(sessionID: dismissalID))
        XCTAssertTrue(dismissalLifecycle.cancelDismissal(sessionID: dismissalID))
        XCTAssertEqual(dismissalLifecycle.phase, .presented(dismissalID))
    }

    func testImagePreviewLifecycleNeverTurnsDismissingBackIntoPresented() {
        let sessionID = UUID()
        var lifecycle = ImagePreviewLifecycle()

        XCTAssertTrue(lifecycle.beginPresentation(sessionID: sessionID))
        XCTAssertTrue(lifecycle.beginDismissal(sessionID: sessionID))
        XCTAssertFalse(lifecycle.finishPresentation(sessionID: sessionID))
        XCTAssertEqual(lifecycle.phase, .dismissing(sessionID))
    }

    func testImagePreviewOnlyAnimatesResolutionThatFinishesAfterPresentation() {
        XCTAssertFalse(
            ImagePreviewResolvedImageVisibilityPolicy.animatesResolvedReveal(
                presentationFinishedBeforeResolution: false
            ),
            "原图在 zoom 期间已完成时，结束帧必须原子替换，不能再闪一次"
        )
        XCTAssertTrue(
            ImagePreviewResolvedImageVisibilityPolicy.animatesResolvedReveal(
                presentationFinishedBeforeResolution: true
            ),
            "原图确实晚到时可以进行轻微渐变"
        )
    }

    func testImagePreviewTransitionUsesAspectFitDestinationAndExactVisibleSource() {
        let portrait = ImageContent(
            thumbnailURL: nil,
            originalURL: nil,
            width: 120,
            height: 480,
            showOriginalButton: true
        )
        let container = CGSize(width: 390, height: 844)
        let target = ImagePreviewTransitionGeometry.aspectFitFrame(
            image: portrait,
            in: container
        )

        XCTAssertEqual(target.width, 211, accuracy: 0.001)
        XCTAssertEqual(target.height, 844, accuracy: 0.001)
        XCTAssertEqual(target.minX, 89.5, accuracy: 0.001)
        XCTAssertEqual(target.minY, 0, accuracy: 0.001)

        let source = CGRect(x: 24, y: 236, width: 342, height: 228)
        XCTAssertEqual(
            ImagePreviewTransitionGeometry.sourceFrame(
                source,
                targetFrame: target,
                containerSize: container
            ),
            source
        )
    }

    func testImagePreviewCropMorphKeepsEverySampleUndistortedAndInsideEndpoints() {
        let source = CGRect(x: 24, y: 236, width: 342, height: 228)
        let target = CGRect(x: 89.5, y: 0, width: 211, height: 844)
        let imageSize = CGSize(width: 400, height: 1_600)
        var previousArea = source.width * source.height
        XCTAssertEqual(
            ImagePreviewTransitionGeometry.interpolatedFrame(
                from: source,
                to: target,
                progress: 0
            ),
            source
        )
        XCTAssertEqual(
            ImagePreviewTransitionGeometry.interpolatedFrame(
                from: source,
                to: target,
                progress: 1
            ),
            target
        )

        for index in 0...100 {
            let progress = CGFloat(index) / 100
            let frame = ImagePreviewTransitionGeometry.interpolatedFrame(
                from: source,
                to: target,
                progress: progress
            )
            let crop = ImagePreviewTransitionGeometry.aspectFillContentsRect(
                imageSize: imageSize,
                displaySize: frame.size
            )
            let croppedImageAspect = imageSize.width * crop.width
                / (imageSize.height * crop.height)

            XCTAssertEqual(
                croppedImageAspect,
                frame.width / frame.height,
                accuracy: 0.000_1,
                "每一帧都应通过裁剪匹配外框，而不是拉伸图片"
            )
            XCTAssertGreaterThanOrEqual(frame.width, min(source.width, target.width))
            XCTAssertLessThanOrEqual(frame.width, max(source.width, target.width))
            XCTAssertGreaterThanOrEqual(frame.height, min(source.height, target.height))
            XCTAssertLessThanOrEqual(frame.height, max(source.height, target.height))
            XCTAssertGreaterThanOrEqual(crop.minX, 0)
            XCTAssertGreaterThanOrEqual(crop.minY, 0)
            XCTAssertLessThanOrEqual(crop.maxX, 1)
            XCTAssertLessThanOrEqual(crop.maxY, 1)

            let area = frame.width * frame.height
            XCTAssertGreaterThanOrEqual(
                area + 0.001,
                previousArea,
                "400×1600 原图的打开路径不得先放大越界再缩回"
            )
            previousArea = area
        }

        XCTAssertEqual(
            ImagePreviewTransitionGeometry.aspectFillContentsRect(
                imageSize: imageSize,
                displaySize: target.size
            ),
            CGRect(x: 0, y: 0, width: 1, height: 1)
        )

        // This is the pixel geometry captured from the iPhone 17 regression
        // video. Linear CGRect interpolation grew from 1.850M to 1.901M px²,
        // then shrank to 1.721M px² even though each dimension was monotonic.
        let recordedSource = CGRect(x: 47, y: 742, width: 1_112, height: 1_664)
        let recordedTarget = CGRect(x: 275, y: 0, width: 656, height: 2_624)
        var recordedPreviousArea = recordedSource.width * recordedSource.height
        for index in 1...100 {
            let frame = ImagePreviewTransitionGeometry.interpolatedFrame(
                from: recordedSource,
                to: recordedTarget,
                progress: CGFloat(index) / 100
            )
            let area = frame.width * frame.height
            XCTAssertLessThanOrEqual(
                area,
                recordedPreviousArea + 0.001,
                "实机回归路径的可见面积必须持续缩向目标，不能先膨胀再回缩"
            )
            XCTAssertGreaterThanOrEqual(
                area + 0.001,
                recordedTarget.width * recordedTarget.height
            )
            recordedPreviousArea = area
        }
    }

    func testImagePreviewTransitionRejectsInvalidOrOffscreenSourceFrames() {
        let image = ImageContent(
            thumbnailURL: nil,
            originalURL: nil,
            width: 4_000,
            height: 1_000,
            showOriginalButton: false
        )
        let container = CGSize(width: 390, height: 844)
        let target = ImagePreviewTransitionGeometry.aspectFitFrame(
            image: image,
            in: container
        )

        XCTAssertNil(ImagePreviewTransitionGeometry.validSourceFrame(.zero))
        XCTAssertNil(ImagePreviewTransitionGeometry.validSourceFrame(
            CGRect(x: CGFloat.infinity, y: 0, width: 20, height: 20)
        ))
        XCTAssertEqual(
            ImagePreviewTransitionGeometry.sourceFrame(
                CGRect(x: 500, y: 900, width: 40, height: 40),
                targetFrame: target,
                containerSize: container
            ),
            target
        )
        XCTAssertEqual(target.width, 390, accuracy: 0.001)
        XCTAssertEqual(target.height, 97.5, accuracy: 0.001)
    }

    func testImagePreviewTransitionMatchesFullScreenViewerAndResolvedImageRatio() {
        let viewerViewport = CGRect(x: 0, y: 0, width: 390, height: 844)
        let target = ImagePreviewTransitionGeometry.aspectFitFrame(
            imageSize: CGSize(width: 120, height: 480),
            in: viewerViewport
        )

        XCTAssertEqual(target.width, 211, accuracy: 0.001)
        XCTAssertEqual(target.height, 844, accuracy: 0.001)
        XCTAssertEqual(target.minX, 89.5, accuracy: 0.001)
        XCTAssertEqual(target.minY, 0, accuracy: 0.001)

        let invalidImageSizeTarget = ImagePreviewTransitionGeometry.aspectFitFrame(
            imageSize: .zero,
            in: viewerViewport
        )
        XCTAssertEqual(invalidImageSizeTarget.width, 390, accuracy: 0.001)
        XCTAssertEqual(invalidImageSizeTarget.height, 390, accuracy: 0.001)
        XCTAssertEqual(invalidImageSizeTarget.minY, 227, accuracy: 0.001)

        XCTAssertTrue(ImagePreviewTransitionGeometry.framesMatch(
            target,
            target.offsetBy(dx: 0.4, dy: -0.4)
        ))
        XCTAssertFalse(ImagePreviewTransitionGeometry.framesMatch(
            target,
            target.offsetBy(dx: 1, dy: 0)
        ))
    }

    func testFullScreenImageDownloadPrefersOriginalAndPreservesGIFExtension() throws {
        let original = try XCTUnwrap(URL(string: "https://example.com/photo.gif"))
        let thumbnail = try XCTUnwrap(URL(string: "https://example.com/photo-small.jpg"))

        XCTAssertEqual(
            TiebaImageDownloadPolicy.preferredURL(original: original, thumbnail: thumbnail),
            original
        )
        let insecureOriginal = try XCTUnwrap(URL(string: "http://example.com/photo.gif"))
        XCTAssertEqual(
            TiebaImageDownloadPolicy.preferredURL(original: insecureOriginal, thumbnail: thumbnail),
            URL(string: "https://example.com/photo.gif")
        )
        XCTAssertEqual(
            TiebaImageDownloadPolicy.fileName(
                for: original,
                mimeType: "image/gif",
                typeIdentifier: nil
            ),
            "photo.gif"
        )
    }

    func testImageDownloadFileNameIsSanitizedAndBounded() throws {
        let stem = String(repeating: "a", count: 200)
        let url = try XCTUnwrap(URL(string: "https://example.com/\(stem)%20bad.jpg"))

        let fileName = TiebaImageDownloadPolicy.fileName(
            for: url,
            mimeType: "image/jpeg",
            typeIdentifier: nil
        )

        let resolvedStem = String(fileName.dropLast(".jpg".count))
        XCTAssertLessThanOrEqual(resolvedStem.count, TiebaImageDownloadPolicy.maximumFileNameStemLength)
        XCTAssertLessThanOrEqual(resolvedStem.utf8.count, TiebaImageDownloadPolicy.maximumFileNameStemBytes)
        XCTAssertFalse(resolvedStem.contains(" "))

        let unicodeURL = try XCTUnwrap(URL(string: "https://example.com/\(String(repeating: "图", count: 200)).png"))
        let unicodeFileName = TiebaImageDownloadPolicy.fileName(
            for: unicodeURL,
            mimeType: "image/png",
            typeIdentifier: nil
        )
        XCTAssertLessThanOrEqual(
            String(unicodeFileName.dropLast(".png".count)).utf8.count,
            TiebaImageDownloadPolicy.maximumFileNameStemBytes
        )
    }

    func testContentMediaPresentationRendersImagesSequentially() {
        XCTAssertEqual(ContentMediaPresentationPolicy.usesGrid(for: [.image(sampleImage()), .image(sampleImage())]), false)
        XCTAssertEqual(ContentMediaPresentationPolicy.usesGrid(for: [.image(sampleImage()), .video(sampleVideo())]), false)
    }

    func testForumThreadBadgePolicyOmitsVideoBadge() {
        let badges = ForumThreadBadgePolicy.items(isTop: false, isGood: false, hasVideo: true)

        XCTAssertFalse(badges.map(\.title).contains("Video"))
        XCTAssertTrue(badges.isEmpty)
    }

    func testHomeRefreshAnimationPolicySupportsUITestTimingAndAnimationOverrides() {
        XCTAssertEqual(
            HomeRefreshAnimationPolicy.minimumVisibleDurationNanoseconds(arguments: []),
            600_000_000
        )
        XCTAssertEqual(
            HomeRefreshAnimationPolicy.minimumVisibleDurationNanoseconds(
                arguments: ["UITEST_EXTENDED_REFRESH_ANIMATION"]
            ),
            5_000_000_000
        )
        XCTAssertTrue(
            HomeRefreshAnimationPolicy.disablesUITestAnimations(
                arguments: ["UITEST_DISABLE_ANIMATIONS"]
            )
        )
        XCTAssertFalse(HomeRefreshAnimationPolicy.disablesUITestAnimations(arguments: []))
    }

    func testHomeTabRefreshRevealsInlineAnimationAtTop() {
        XCTAssertTrue(HomeRefreshRevealPolicy.shouldScrollToTop(
            trigger: .tabTap,
            hasExistingContent: true
        ))
        XCTAssertFalse(HomeRefreshRevealPolicy.shouldScrollToTop(
            trigger: .pullToRefresh,
            hasExistingContent: true
        ))
        XCTAssertFalse(HomeRefreshRevealPolicy.shouldScrollToTop(
            trigger: .appOpen,
            hasExistingContent: true
        ))
        XCTAssertFalse(HomeRefreshRevealPolicy.shouldScrollToTop(
            trigger: .tabTap,
            hasExistingContent: false
        ))
    }

    func testShortPullRefreshRequiresTopAndVertical80PointPull() {
        XCTAssertEqual(
            ShortPullRefreshPolicy.distanceFromTop(contentOffsetY: -59, topInset: 59),
            0
        )
        XCTAssertEqual(
            ShortPullRefreshPolicy.distanceFromTop(contentOffsetY: 41, topInset: 59),
            100
        )
        XCTAssertEqual(ShortPullRefreshPolicy.distanceFromTop(markerOffset: -100), 100)
        XCTAssertTrue(ShortPullRefreshPolicy.isAtTop(distanceFromTop: 0))
        XCTAssertTrue(ShortPullRefreshPolicy.isAtTop(distanceFromTop: 2))
        XCTAssertFalse(ShortPullRefreshPolicy.isAtTop(distanceFromTop: 3))

        XCTAssertEqual(ShortPullRefreshPolicy.pullProgress(translation: CGSize(width: 0, height: -10)), 0)
        XCTAssertEqual(ShortPullRefreshPolicy.pullProgress(translation: CGSize(width: 0, height: 40)), 0.5)
        XCTAssertEqual(ShortPullRefreshPolicy.pullProgress(translation: CGSize(width: 0, height: 80)), 1)
        XCTAssertEqual(ShortPullRefreshPolicy.pullProgress(translation: CGSize(width: 0, height: 200)), 1)

        XCTAssertTrue(ShortPullRefreshPolicy.shouldBegin(
            distanceFromTop: 0,
            initialTranslation: CGSize(width: 0, height: 1)
        ))
        XCTAssertFalse(ShortPullRefreshPolicy.shouldBegin(
            distanceFromTop: 20,
            initialTranslation: CGSize(width: 0, height: 20)
        ))
        XCTAssertFalse(ShortPullRefreshPolicy.shouldBegin(
            distanceFromTop: 0,
            initialTranslation: CGSize(width: 0, height: -20)
        ))
        XCTAssertFalse(ShortPullRefreshPolicy.shouldBegin(
            distanceFromTop: 0,
            initialTranslation: CGSize(width: 20, height: 10)
        ))

        XCTAssertTrue(ShortPullRefreshPolicy.shouldTrigger(
            startedAtTop: true,
            isRefreshing: false,
            translation: CGSize(width: 4, height: 80)
        ))
        XCTAssertFalse(ShortPullRefreshPolicy.shouldTrigger(
            startedAtTop: true,
            isRefreshing: false,
            translation: CGSize(width: 4, height: 79)
        ))
        XCTAssertFalse(ShortPullRefreshPolicy.shouldTrigger(
            startedAtTop: false,
            isRefreshing: false,
            translation: CGSize(width: 4, height: 100)
        ))
        XCTAssertFalse(ShortPullRefreshPolicy.shouldTrigger(
            startedAtTop: true,
            isRefreshing: true,
            translation: CGSize(width: 4, height: 100)
        ))
        XCTAssertFalse(ShortPullRefreshPolicy.shouldTrigger(
            startedAtTop: true,
            isRefreshing: false,
            translation: CGSize(width: 100, height: 80)
        ))
        XCTAssertFalse(ShortPullRefreshPolicy.shouldTrigger(
            startedAtTop: false,
            isRefreshing: false,
            translation: CGSize(width: 0, height: 200)
        ), "从列表中部开始并越过顶部的长下滑也不得刷新")
    }

    func testShortPullRefreshClassifiesExistingPanDirection() {
        XCTAssertNil(ShortPullRefreshPolicy.verticalPullIntent(
            translation: CGSize(width: 1, height: 2)
        ))
        XCTAssertEqual(
            ShortPullRefreshPolicy.verticalPullIntent(
                translation: CGSize(width: 12, height: 80)
            ),
            true
        )
        XCTAssertEqual(
            ShortPullRefreshPolicy.verticalPullIntent(
                translation: CGSize(width: 100, height: 80)
            ),
            false,
            "顶部斜向右划必须让刷新状态机退出，不能和返回手势串扰"
        )
        XCTAssertEqual(
            ShortPullRefreshPolicy.verticalPullIntent(
                translation: CGSize(width: 0, height: -12)
            ),
            false
        )
    }

    func testShortPullRefreshGeometrySeparatesScrollAndOverscroll() {
        XCTAssertEqual(
            ShortPullRefreshPolicy.pullDistance(contentOffsetY: -59, topInset: 59),
            0
        )
        XCTAssertEqual(
            ShortPullRefreshPolicy.pullDistance(contentOffsetY: -91, topInset: 59),
            32
        )
        XCTAssertEqual(
            ShortPullRefreshPolicy.distanceFromTop(contentOffsetY: -91, topInset: 59),
            0
        )

        let pulled = ShortPullRefreshGeometry(contentOffsetY: -139, topInset: 59)
        XCTAssertEqual(pulled.distanceFromTop, 0)
        XCTAssertEqual(pulled.pullDistance, 80)

        let fingerDistance: CGFloat = 80
        let viewportLength: CGFloat = 800
        let compressedDistance = fingerDistance
            * ShortPullRefreshPolicy.rubberBandCoefficient
            * viewportLength
            / (viewportLength + fingerDistance * ShortPullRefreshPolicy.rubberBandCoefficient)
        XCTAssertEqual(
            ShortPullRefreshPolicy.fingerEquivalentPullDistance(
                overscrollDistance: compressedDistance,
                viewportLength: viewportLength
            ),
            fingerDistance,
            accuracy: 0.001,
            "UIKit 橡皮筋后的内容位移应还原为 80pt 手指位移"
        )
        let rubberBanded = ShortPullRefreshGeometry(
            contentOffsetY: -(59 + compressedDistance),
            topInset: 59,
            viewportLength: viewportLength
        )
        XCTAssertEqual(rubberBanded.pullDistance, compressedDistance, accuracy: 0.001)
        XCTAssertEqual(rubberBanded.fingerEquivalentPullDistance, fingerDistance, accuracy: 0.001)
        XCTAssertEqual(
            ShortPullRefreshPolicy.fingerEquivalentPullDistance(
                overscrollDistance: 0,
                viewportLength: 800
            ),
            0
        )
        XCTAssertEqual(
            ShortPullRefreshPolicy.fingerEquivalentPullDistance(
                overscrollDistance: 100,
                viewportLength: 80
            ),
            100 / ShortPullRefreshPolicy.rubberBandCoefficient,
            accuracy: 0.001,
            "极端几何下也必须返回有限且单调的等效位移"
        )

        let scrolled = ShortPullRefreshGeometry(contentOffsetY: 41, topInset: 59)
        XCTAssertEqual(scrolled.distanceFromTop, 100)
        XCTAssertEqual(scrolled.pullDistance, 0)
        XCTAssertEqual(scrolled.fingerEquivalentPullDistance, 0)
    }

    func testShortPullRefreshPhasePolicyLatchesTopAndPreventsDuplicates() {
        XCTAssertTrue(ShortPullRefreshPolicy.shouldBegin(
            distanceFromTop: 2,
            isRefreshing: false
        ))
        XCTAssertFalse(ShortPullRefreshPolicy.shouldBegin(
            distanceFromTop: 3,
            isRefreshing: false
        ))
        XCTAssertFalse(ShortPullRefreshPolicy.shouldBegin(
            distanceFromTop: 0,
            isRefreshing: true
        ))

        XCTAssertTrue(ShortPullRefreshPolicy.shouldTrigger(
            startedAtTop: true,
            isRefreshing: false,
            pullDistance: 80
        ))
        XCTAssertFalse(ShortPullRefreshPolicy.shouldTrigger(
            startedAtTop: true,
            isRefreshing: false,
            pullDistance: 79
        ))
        XCTAssertFalse(ShortPullRefreshPolicy.shouldTrigger(
            startedAtTop: false,
            isRefreshing: false,
            pullDistance: 200
        ), "列表中部起手后即使越过顶部也不能获得刷新资格")
        XCTAssertFalse(ShortPullRefreshPolicy.shouldTrigger(
            startedAtTop: true,
            isRefreshing: true,
            pullDistance: 100
        ), "已有刷新任务时不能重复触发")

        XCTAssertTrue(ShortPullRefreshPolicy.shouldTrigger(
            startedAtTop: true,
            isRefreshing: false,
            reachedThreshold: true
        ), "松手时最后一次有效手指位移仍满 80pt 才能刷新")
        XCTAssertFalse(ShortPullRefreshPolicy.shouldTrigger(
            startedAtTop: true,
            isRefreshing: false,
            reachedThreshold: false
        ))
        XCTAssertFalse(ShortPullRefreshPolicy.shouldTrigger(
            startedAtTop: false,
            isRefreshing: false,
            reachedThreshold: true
        ), "从列表中部起手不能借用后续越过阈值的状态")
    }

    func testShortPullRefreshDisarmsAfterReturningBelowThresholdBeforeRelease() {
        var isArmed = ShortPullRefreshPolicy.pullProgress(pullDistance: 80) >= 1
        XCTAssertTrue(isArmed)

        isArmed = ShortPullRefreshPolicy.pullProgress(pullDistance: 40) >= 1
        XCTAssertFalse(isArmed, "仍按住回推到 40pt 时，灰色圆环必须恢复为未满状态")
        XCTAssertFalse(
            ShortPullRefreshPolicy.shouldTrigger(
                startedAtTop: true,
                isRefreshing: false,
                reachedThreshold: isArmed
            ),
            "拉过 80pt 后回推到不足阈值再松手不得刷新"
        )
    }

    func testShortPullRefreshHoldsContentAtFortyFourPointsWhileRefreshing() {
        XCTAssertEqual(ShortPullRefreshPolicy.heldContentDistance, 44)
        XCTAssertEqual(
            ShortPullRefreshPolicy.heldContentOffset(pullDistance: 0, isRefreshing: false),
            0
        )
        XCTAssertEqual(
            ShortPullRefreshPolicy.heldContentOffset(pullDistance: -10, isRefreshing: true),
            44
        )
        XCTAssertEqual(
            ShortPullRefreshPolicy.heldContentOffset(pullDistance: 0, isRefreshing: true),
            44
        )
        XCTAssertEqual(
            ShortPullRefreshPolicy.heldContentOffset(pullDistance: 20, isRefreshing: true),
            24
        )
        XCTAssertEqual(
            ShortPullRefreshPolicy.heldContentOffset(pullDistance: 44, isRefreshing: true),
            0
        )
        XCTAssertEqual(
            ShortPullRefreshPolicy.heldContentOffset(pullDistance: 80, isRefreshing: true),
            0
        )
    }

    func testShortPullRefreshUsesSixHundredMillisecondMinimumVisibility() {
        XCTAssertEqual(
            ShortPullRefreshPolicy.minimumVisibleDurationNanoseconds,
            600_000_000
        )
        XCTAssertEqual(
            ShortPullRefreshPolicy.minimumVisibleDurationNanoseconds(
                arguments: ["UITEST_EXTENDED_REFRESH_ANIMATION"]
            ),
            5_000_000_000
        )
        XCTAssertEqual(
            ShortPullRefreshPolicy.minimumVisibleDurationNanoseconds(
                arguments: ["UITEST_RESELECT_REFRESH_HOLD"]
            ),
            10_000_000_000
        )
        XCTAssertEqual(
            ShortPullRefreshPolicy.remainingVisibleDurationNanoseconds(elapsed: 100_000_000),
            500_000_000
        )
        XCTAssertEqual(
            ShortPullRefreshPolicy.remainingVisibleDurationNanoseconds(elapsed: 700_000_000),
            0
        )
    }

    func testHomeOpenRefreshPolicyRefreshesWhenLoadedAppBecomesActive() {
        XCTAssertTrue(HomeOpenRefreshPolicy.shouldRefreshOnScenePhaseChange(
            from: .background,
            to: .active,
            didLoad: true
        ))
        XCTAssertFalse(HomeOpenRefreshPolicy.shouldRefreshOnScenePhaseChange(
            from: .inactive,
            to: .active,
            didLoad: true
        ))
        XCTAssertFalse(HomeOpenRefreshPolicy.shouldRefreshOnScenePhaseChange(
            from: .active,
            to: .active,
            didLoad: true
        ))
        XCTAssertFalse(HomeOpenRefreshPolicy.shouldRefreshOnScenePhaseChange(
            from: .background,
            to: .inactive,
            didLoad: true
        ))
        XCTAssertFalse(HomeOpenRefreshPolicy.shouldRefreshOnScenePhaseChange(
            from: .background,
            to: .active,
            didLoad: false
        ))
    }

    func testRootTabHitTesterMapsBottomTabRegions() {
        let centeredIPadFrames = [
            CGRect(x: 280, y: 0, width: 80, height: 49),
            CGRect(x: 360, y: 0, width: 80, height: 49),
            CGRect(x: 440, y: 0, width: 80, height: 49)
        ]
        XCTAssertEqual(RootTabHitTester.tab(at: CGPoint(x: 320, y: 20), itemFrames: centeredIPadFrames), .home)
        XCTAssertEqual(RootTabHitTester.tab(at: CGPoint(x: 400, y: 20), itemFrames: centeredIPadFrames), .forums)
        XCTAssertEqual(RootTabHitTester.tab(at: CGPoint(x: 480, y: 20), itemFrames: centeredIPadFrames), .me)
        XCTAssertNil(RootTabHitTester.tab(at: CGPoint(x: 20, y: 20), itemFrames: centeredIPadFrames))
        XCTAssertNil(RootTabHitTester.tab(at: CGPoint(x: 320, y: 20), itemFrames: []))
    }

    func testPaginationPrefetchStartsBeforeTheLastItem() {
        XCTAssertFalse(PaginationPrefetchPolicy.shouldLoadMore(currentIndex: 14, totalCount: 20))
        XCTAssertTrue(PaginationPrefetchPolicy.shouldLoadMore(currentIndex: 15, totalCount: 20))
        XCTAssertTrue(PaginationPrefetchPolicy.shouldLoadMore(currentIndex: 0, totalCount: 3))
        XCTAssertFalse(PaginationPrefetchPolicy.shouldLoadMore(currentIndex: 0, totalCount: 0))
    }

    func testLocallyFilteredPaginationReachesVisibleSecondPage() {
        var hiddenPageCount = 0
        var requestedPages: [Int] = []
        let visibleCounts = [0, 2]

        for (index, visibleCount) in visibleCounts.enumerated() {
            requestedPages.append(index + 1)
            let decision = LocallyFilteredPaginationPolicy.decision(
                visibleItemCount: visibleCount,
                serverHasMore: true,
                consecutiveHiddenPageCount: hiddenPageCount
            )
            hiddenPageCount = decision.consecutiveHiddenPageCount
            if decision.shouldAutomaticallyLoadNextPage == false {
                break
            }
        }

        XCTAssertEqual(requestedPages, [1, 2])
        XCTAssertEqual(hiddenPageCount, 0)
    }

    func testLocallyFilteredPaginationStopsAtAutomaticLimit() {
        var hiddenPageCount = 0
        var automaticRequests = 1
        var finalDecision: LocallyFilteredPaginationDecision?

        for _ in 0..<LocallyFilteredPaginationPolicy.automaticPageLimit {
            let decision = LocallyFilteredPaginationPolicy.decision(
                visibleItemCount: 0,
                serverHasMore: true,
                consecutiveHiddenPageCount: hiddenPageCount
            )
            hiddenPageCount = decision.consecutiveHiddenPageCount
            finalDecision = decision
            if decision.shouldAutomaticallyLoadNextPage {
                automaticRequests += 1
            }
        }

        XCTAssertEqual(automaticRequests, LocallyFilteredPaginationPolicy.automaticPageLimit)
        XCTAssertEqual(hiddenPageCount, LocallyFilteredPaginationPolicy.automaticPageLimit)
        XCTAssertEqual(finalDecision?.shouldAutomaticallyLoadNextPage, false)
        XCTAssertEqual(finalDecision?.shouldOfferManualContinuation, true)
    }

    func testRefreshAnimationMinimumDurationDoesNotLingerAfterSlowRequest() {
        XCTAssertEqual(
            HomeRefreshAnimationPolicy.remainingVisibleDurationNanoseconds(
                minimum: 250_000_000,
                elapsed: 100_000_000
            ),
            150_000_000
        )
        XCTAssertEqual(
            HomeRefreshAnimationPolicy.remainingVisibleDurationNanoseconds(
                minimum: 250_000_000,
                elapsed: 500_000_000
            ),
            0
        )
    }

    func testReaderErrorMessagesAreConciseAndLocalized() {
        XCTAssertEqual(ReaderErrorMessage.message(for: URLError(.timedOut)), "请求超时，请稍后重试。")
        XCTAssertEqual(ReaderErrorMessage.message(for: URLError(.notConnectedToInternet)), "网络不可用，请检查网络连接。")
        XCTAssertEqual(
            ReaderErrorMessage.message(for: AuthSessionError.untrustedCookie),
            "登录凭证未通过安全校验，请重新登录。"
        )
        XCTAssertEqual(
            ReaderErrorMessage.message(for: KeychainError.status(errSecInteractionNotAllowed)),
            "本机账号数据处理失败，请重新登录或稍后重试。"
        )
    }

    func testReaderDateTextUsesConciseRelativeTime() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        XCTAssertEqual(ReaderDateText.string(from: now.addingTimeInterval(-30), now: now), "刚刚")
        XCTAssertEqual(ReaderDateText.string(from: now.addingTimeInterval(-1_800), now: now), "30分钟前")
    }

    func testThreadReplyMetadataMatchesCompactFooterStyle() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 13, hour: 16)))
        let postDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 12, hour: 9, minute: 30)))

        XCTAssertEqual(
            ThreadPostMetadataText.text(
                createdAt: postDate,
                ipAddress: "IP属地：湖南",
                now: now,
                calendar: calendar
            ),
            "昨天 09:30  湖南"
        )
        let olderDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 10, hour: 9)))
        XCTAssertEqual(
            ThreadPostMetadataText.text(
                createdAt: olderDate,
                ipAddress: "来自 浙江 ",
                now: now,
                calendar: calendar
            ),
            "07-10  浙江"
        )
        XCTAssertEqual(ThreadPostMetadataText.firstLocation("  ", nil, "广东"), "广东")
    }

    func testSubpostOpenAllUsesCompactVisualAndHitHeights() {
        XCTAssertEqual(SubpostPreviewLayout.rowSpacing, 8)
        XCTAssertEqual(SubpostPreviewLayout.openAllTopSpacing, 4)
        XCTAssertGreaterThan(
            SubpostPreviewLayout.rowSpacing,
            SubpostPreviewLayout.openAllTopSpacing
        )
        XCTAssertEqual(SubpostPreviewLayout.openAllVisualMinHeight, 30)
        XCTAssertEqual(
            SubpostPreviewLayout.openAllVisualMinHeight / 44,
            2.0 / 3.0,
            accuracy: 0.02
        )
        XCTAssertEqual(
            SubpostPreviewLayout.openAllVisualMinHeight
                + SubpostPreviewLayout.openAllHitExpansion * 2,
            SubpostPreviewLayout.openAllHitHeight
        )
        XCTAssertEqual(SubpostPreviewLayout.openAllHitHeight, 36)
        XCTAssertLessThan(SubpostPreviewLayout.openAllHitHeight, 44)
    }

    func testSubpostSheetTitle() {
        XCTAssertEqual(SubpostSheetTitle.text(floor: 2, count: 10), "2楼的回复(10条)")
    }

    func testSubpostDetailUsesDistinctCompactSections() {
        XCTAssertEqual(SubpostDetailSectionLayout.separatorHeight, 12)
        XCTAssertEqual(SubpostDetailSectionLayout.headerVerticalPadding, 8)
        XCTAssertGreaterThan(
            SubpostDetailSectionLayout.separatorHeight,
            ThreadReplyLayout.sectionSeparatorHeight
        )
        XCTAssertEqual(
            SubpostDetailSectionLayout.accessibilityLabel(title: "层主内容", count: nil),
            "层主内容"
        )
        XCTAssertEqual(
            SubpostDetailSectionLayout.accessibilityLabel(title: "楼中楼回复", count: 4),
            "楼中楼回复，共4条"
        )
        XCTAssertEqual(
            SubpostDetailSectionLayout.accessibilityLabel(title: "楼中楼回复", count: -1),
            "楼中楼回复，共0条"
        )
    }

    func testSubpostRightSwipeDismissPolicyAcceptsOnlyIntentionalRightSwipes() {
        XCTAssertTrue(SubpostRightSwipeDismissPolicy.shouldBegin(
            translation: CGSize(width: 32, height: 8)
        ))
        XCTAssertFalse(SubpostRightSwipeDismissPolicy.shouldBegin(
            translation: CGSize(width: -32, height: 0)
        ))
        XCTAssertFalse(SubpostRightSwipeDismissPolicy.shouldBegin(
            translation: CGSize(width: 20, height: 40)
        ))
        XCTAssertEqual(
            SubpostRightSwipeDismissPolicy.verticalOffset(
                translationX: 120,
                containerHeight: 800
            ),
            120
        )
        XCTAssertEqual(
            SubpostRightSwipeDismissPolicy.verticalOffset(
                translationX: 800,
                containerHeight: 800
            ),
            576
        )
        XCTAssertEqual(
            SubpostRightSwipeDismissPolicy.predictedTranslation(
                translationX: 40,
                velocityX: 1_000
            ),
            220
        )
        XCTAssertTrue(SubpostRightSwipeDismissPolicy.shouldFinish(
            translationX: 120,
            predictedTranslationX: 120,
            containerWidth: 390
        ))
        XCTAssertTrue(SubpostRightSwipeDismissPolicy.shouldFinish(
            translationX: 40,
            predictedTranslationX: 260,
            containerWidth: 390
        ))
        XCTAssertFalse(SubpostRightSwipeDismissPolicy.shouldFinish(
            translationX: 40,
            predictedTranslationX: 100,
            containerWidth: 390
        ))
    }

    func testNavigationBackGesturePolicyUsesNativeContentPopOnlyOnIOS26() {
        XCTAssertEqual(
            NavigationBackGesturePolicy.mode(systemMajorVersion: 18),
            .edge
        )
        XCTAssertEqual(
            NavigationBackGesturePolicy.mode(systemMajorVersion: 25),
            .edge
        )
        XCTAssertEqual(
            NavigationBackGesturePolicy.mode(systemMajorVersion: 26),
            .content
        )
        XCTAssertEqual(
            NavigationBackGesturePolicy.mode(systemMajorVersion: 27),
            .content
        )
    }

    func testInlineContentTextUsesOneLiveLayoutStackWithoutClippingAfterReuse() {
        let textView = InlineContentTextView()
        if #available(iOS 17.0, *) {
            XCTAssertEqual(textView.sizingRule, .oversize)
        }
        textView.backgroundColor = .clear
        textView.isEditable = false
        textView.isScrollEnabled = false
        textView.textContainerInset = .zero
        textView.contentInset = .zero
        textView.contentInsetAdjustmentBehavior = .never
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainer.widthTracksTextView = false
        // Match the raster scale used by the live view. Rendering a 2x iPad
        // layout into a synthetic 3x bitmap tests a different fractional
        // baseline than the one that can appear on that device and can report
        // pixels outside a frame that is complete at its actual display scale.
        let renderScale = UIScreen.main.scale

        let traitCollections = [
            UITraitCollection(preferredContentSizeCategory: .large),
            UITraitCollection(preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge)
        ]

        for traits in traitCollections {
            traits.performAsCurrent {
                let cases: [(name: String, content: InlineContentText)] = [
                    (
                        "plain-cjk",
                        InlineContentText(
                            blocks: [.text("翻译这段回复的第一行不应被裁切，第二行也应完整显示。")],
                            style: .reply
                        )
                    ),
                    (
                        "combining-glyphs",
                        InlineContentText(
                            blocks: [.text("A\u{0301} E\u{0302} Ü 高字形首行与中文回复混排不应被裁切。")],
                            style: .reply
                        )
                    ),
                    (
                        "stacked-combining-glyphs",
                        InlineContentText(
                            blocks: [.text("A\u{0301}\u{0307} 叠加附标首行必须完整显示。")],
                            style: .reply
                        )
                    ),
                    (
                        "tall-scripts",
                        InlineContentText(
                            blocks: [.text("ภาษาไทย မြန်မာ ཨོཾ العربية 多文字体系首行不能裁切。")],
                            style: .reply
                        )
                    ),
                    (
                        "inline-emoticon",
                        InlineContentText(
                            blocks: [
                                .emoticon(code: "滑稽"),
                                .text("首行表情附件之后的回复文字不应被裁切。")
                            ],
                            style: .reply
                        )
                    ),
                    (
                        "interactive-mention",
                        InlineContentText(
                            blocks: [
                                .text("回复 "),
                                .mention(userID: 42, text: "被回复用户"),
                                .text("：带链接首行也必须完整。")
                            ],
                            style: .subpost,
                            prefixParts: [.text("合成作者 "), .threadAuthorBadge, .text(": ")],
                            onOpenUser: { _ in }
                        )
                    )
                ]
                var recordedHeights: [String: CGFloat] = [:]

                // Reuse one actual text view while content and width change,
                // then revisit every combination to catch stale TextKit state.
                for pass in 0..<2 {
                    let orderedCases = pass == 0 ? cases : Array(cases.reversed())
                    let widths = pass == 0 ? [238.0, 271.0, 319.0] : [319.0, 271.0, 238.0]
                    for width in widths {
                        for item in orderedCases {
                            let attributedText = item.content.attributedString()
                            let size = textView.fittingSize(
                                width: width,
                                attributedText: attributedText,
                                maximumNumberOfLines: 0,
                                lineBreakMode: .byWordWrapping
                            )
                            textView.frame = CGRect(origin: .zero, size: size)
                            textView.layoutIfNeeded()

                            let renderedBounds = textView.renderedTextBoundsInView
                            XCTAssertGreaterThanOrEqual(
                                renderedBounds.minY,
                                -0.5,
                                "\(item.name) @ \(width): first line starts outside the live view"
                            )
                            XCTAssertLessThanOrEqual(
                                renderedBounds.maxY,
                                size.height + 0.5,
                                "\(item.name) @ \(width): live glyphs exceed the measured frame"
                            )
                            XCTAssertEqual(textView.contentOffset.x, 0, accuracy: 0.01)
                            XCTAssertEqual(textView.contentOffset.y, 0, accuracy: 0.01)

                            let inkBounds = MainActor.assumeIsolated {
                                renderedAlphaBounds(of: textView, scale: renderScale)
                            }
                            XCTAssertNotNil(
                                inkBounds,
                                "\(item.name) @ \(width): rendered view contains no glyph pixels"
                            )
                            if let inkBounds {
                                XCTAssertGreaterThanOrEqual(
                                    inkBounds.minY,
                                    1,
                                    "\(item.name) @ \(width): real glyph ink touches the top clip boundary; size=\(size), used=\(renderedBounds), ink=\(inkBounds), inset=\(textView.textContainerInset)"
                                )
                                XCTAssertLessThanOrEqual(
                                    inkBounds.maxY,
                                    ceil(size.height * renderScale),
                                    "\(item.name) @ \(width): real glyph ink exceeds the fitted frame; size=\(size), used=\(renderedBounds), ink=\(inkBounds), inset=\(textView.textContainerInset)"
                                )
                            }

                            // Draw the same live TextKit layout into a padded,
                            // unbounded bitmap. Unlike a layer screenshot this
                            // exposes letterform pixels outside the view instead
                            // of clipping them first, so it distinguishes real
                            // clipping from a complete glyph that merely ends on
                            // the final device pixel.
                            let unboundedInkBounds = MainActor.assumeIsolated {
                                unboundedTextKitAlphaBounds(of: textView, scale: renderScale)
                            }
                            XCTAssertNotNil(
                                unboundedInkBounds,
                                "\(item.name) @ \(width): unbounded TextKit draw contains no glyph pixels"
                            )
                            if let inkBounds, let unboundedInkBounds {
                                // UITextView's letterform-aware oversize rule
                                // can translate its live canvas relative to a
                                // raw NSLayoutManager draw. Coordinates are
                                // therefore not directly comparable. Compare
                                // the complete vertical ink extent instead: a
                                // clipped live view necessarily loses pixels
                                // and becomes shorter than the unbounded draw.
                                XCTAssertGreaterThanOrEqual(
                                    inkBounds.height,
                                    unboundedInkBounds.height,
                                    "\(item.name) @ \(width): live view loses glyph pixels; size=\(size), live=\(inkBounds), unbounded=\(unboundedInkBounds), inset=\(textView.textContainerInset)"
                                )
                            }

                            let key = "\(traits.preferredContentSizeCategory.rawValue)-\(item.name)-\(width)"
                            if let recordedHeight = recordedHeights[key] {
                                XCTAssertEqual(
                                    size.height,
                                    recordedHeight,
                                    accuracy: 0.5,
                                    "\(item.name) @ \(width): reused view changed its fitting height"
                                )
                            } else {
                                recordedHeights[key] = size.height
                            }
                        }
                    }
                }
            }
        }
    }

    /// Returns the bounds of pixels actually drawn by the text view in a
    /// known transparent RGBA bitmap. TextKit's usedRect is typographic
    /// geometry and can report an in-bounds line even when a tall letterform's
    /// antialiased ink is shaved by the view boundary, so the clipping test
    /// must inspect rendered pixels as well.
    @MainActor
    private func renderedAlphaBounds(
        of view: UIView,
        scale: CGFloat
    ) -> CGRect? {
        let pixelWidth = max(Int(ceil(view.bounds.width * scale)), 1)
        let pixelHeight = max(Int(ceil(view.bounds.height * scale)), 1)
        let bytesPerPixel = 4
        let bytesPerRow = pixelWidth * bytesPerPixel
        var pixels = [UInt8](
            repeating: 0,
            count: pixelHeight * bytesPerRow
        )

        let didRender = pixels.withUnsafeMutableBytes { storage -> Bool in
            guard let baseAddress = storage.baseAddress,
                  let context = CGContext(
                    data: baseAddress,
                    width: pixelWidth,
                    height: pixelHeight,
                    bitsPerComponent: 8,
                    bytesPerRow: bytesPerRow,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  ) else { return false }
            context.scaleBy(x: scale, y: scale)
            view.layer.render(in: context)
            return true
        }
        guard didRender else { return nil }

        var minX = pixelWidth
        var minY = pixelHeight
        var maxX = -1
        var maxY = -1
        for y in 0..<pixelHeight {
            for x in 0..<pixelWidth {
                let alpha = pixels[y * bytesPerRow + x * bytesPerPixel + 3]
                guard alpha > 0 else { continue }
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        return CGRect(
            x: minX,
            y: minY,
            width: maxX - minX + 1,
            height: maxY - minY + 1
        )
    }

    /// Draws the text layout with transparent space around all four edges and
    /// returns pixel-space ink coordinates relative to the text view's origin.
    /// Negative coordinates or coordinates beyond the fitted frame are actual
    /// overflow that a normal view render would hide.
    @MainActor
    private func unboundedTextKitAlphaBounds(
        of textView: InlineContentTextView,
        scale: CGFloat
    ) -> CGRect? {
        let padding: CGFloat = 24
        let logicalWidth = textView.bounds.width + padding * 2
        let logicalHeight = textView.bounds.height + padding * 2
        let pixelWidth = max(Int(ceil(logicalWidth * scale)), 1)
        let pixelHeight = max(Int(ceil(logicalHeight * scale)), 1)
        let bytesPerPixel = 4
        let bytesPerRow = pixelWidth * bytesPerPixel
        var pixels = [UInt8](
            repeating: 0,
            count: pixelHeight * bytesPerRow
        )
        textView.layoutManager.ensureLayout(for: textView.textContainer)
        let glyphRange = textView.layoutManager.glyphRange(for: textView.textContainer)
        let didRender = pixels.withUnsafeMutableBytes { storage -> Bool in
            guard let baseAddress = storage.baseAddress,
                  let context = CGContext(
                    data: baseAddress,
                    width: pixelWidth,
                    height: pixelHeight,
                    bitsPerComponent: 8,
                    bytesPerRow: bytesPerRow,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  ) else { return false }

            // Recreate UIKit's top-left origin without imposing a view clip.
            context.translateBy(x: 0, y: CGFloat(pixelHeight))
            context.scaleBy(x: scale, y: -scale)
            context.translateBy(
                x: padding + textView.textContainerInset.left - textView.contentOffset.x,
                y: padding + textView.textContainerInset.top - textView.contentOffset.y
            )
            UIGraphicsPushContext(context)
            textView.layoutManager.drawBackground(
                forGlyphRange: glyphRange,
                at: .zero
            )
            textView.layoutManager.drawGlyphs(
                forGlyphRange: glyphRange,
                at: .zero
            )
            UIGraphicsPopContext()
            return true
        }
        guard didRender else { return nil }

        var minX = pixelWidth
        var minY = pixelHeight
        var maxX = -1
        var maxY = -1
        for y in 0..<pixelHeight {
            for x in 0..<pixelWidth {
                let alpha = pixels[y * bytesPerRow + x * bytesPerPixel + 3]
                guard alpha > 0 else { continue }
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        return CGRect(
            x: CGFloat(minX) - padding * scale,
            y: CGFloat(minY) - padding * scale,
            width: CGFloat(maxX - minX + 1),
            height: CGFloat(maxY - minY + 1)
        )
    }

    func testInlineUserProfileLinkPreservesReplyTargetIdentity() throws {
        let url = try XCTUnwrap(
            InlineUserProfileLink.url(userID: 42, displayText: " @被回复用户 ")
        )
        let user = try XCTUnwrap(InlineUserProfileLink.user(from: url))

        XCTAssertEqual(user.id, 42)
        XCTAssertEqual(user.name, "被回复用户")
        XCTAssertEqual(user.displayNameResolved, "被回复用户")

        let nameOnlyURL = try XCTUnwrap(
            InlineUserProfileLink.url(userID: 0, displayText: " @无 UID 用户 ")
        )
        let nameOnlyUser = try XCTUnwrap(InlineUserProfileLink.user(from: nameOnlyURL))
        XCTAssertEqual(nameOnlyUser.id, 0)
        XCTAssertEqual(nameOnlyUser.displayNameResolved, "无 UID 用户")

        XCTAssertNil(InlineUserProfileLink.url(userID: 0, displayText: "  "))
        XCTAssertNil(InlineUserProfileLink.user(from: URL(string: "https://tieba.baidu.com")!))
    }

    func testInlineReplyUserNamesStaySecondaryWhenUIDIsMissing() throws {
        let text = InlineContentText(
            blocks: [.mention(userID: nil, text: "被回复用户")],
            style: .subpost,
            prefixParts: [.text("回复用户: ")],
            onOpenUser: { _ in }
        ).attributedString()

        let prefixColor = try XCTUnwrap(
            text.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor
        )
        let targetLocation = (text.string as NSString).range(of: "被回复用户").location
        let targetColor = try XCTUnwrap(
            text.attribute(.foregroundColor, at: targetLocation, effectiveRange: nil) as? UIColor
        )

        XCTAssertTrue(prefixColor.isEqual(InlineUserNamePresentation.foregroundColor))
        XCTAssertTrue(targetColor.isEqual(InlineUserNamePresentation.foregroundColor))
        let targetURL = try XCTUnwrap(
            text.attribute(.link, at: targetLocation, effectiveRange: nil) as? URL
        )
        let linkedUser = try XCTUnwrap(InlineUserProfileLink.user(from: targetURL))
        XCTAssertEqual(linkedUser.id, 0)
        XCTAssertEqual(linkedUser.displayNameResolved, "被回复用户")
    }

    func testReferenceSubpostFixtureExercisesMissingUserTypeZeroPayload() throws {
        let first = try XCTUnwrap(FixtureTiebaAPI.referenceSubpostFixtures.first)

        XCTAssertEqual(first.blocks, [
            .text("回复"),
            .mention(userID: nil, text: "被回复用户"),
            .text("：楼中楼参考布局回复1，用于检查双用户名独立跳转。")
        ])
    }

    func testFixtureResolvesNameOnlyReplyTargetAndHonorsCancellation() async throws {
        let immediate = FixtureTiebaAPI()
        let resolved = try await immediate.resolveUser(named: " @被回复用户 ")
        XCTAssertEqual(resolved, FixtureTiebaAPI.replyTarget)

        let slow = FixtureTiebaAPI(delayMilliseconds: 500)
        let task = Task {
            try await slow.resolveUser(named: "被回复用户")
        }
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected cancelled name resolution not to publish a user")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
    }

    private func thread(id: Int64, title: String) -> ThreadSummary {
        ThreadSummary(
            id: id,
            forumID: 100,
            title: title,
            author: UserSummary(id: id, name: "user\(id)", displayName: "User \(id)", portrait: ""),
            forumName: "测试",
            replyCount: 0,
            viewCount: 0,
            likeCount: 0,
            blocks: [.text(title)]
        )
    }

    private func sampleImage() -> ImageContent {
        ImageContent(
            thumbnailURL: URL(string: "https://image.example/thumb.jpg"),
            originalURL: URL(string: "https://image.example/original.jpg"),
            width: 800,
            height: 600,
            showOriginalButton: false
        )
    }

    private func sampleVideo() -> VideoContent {
        VideoContent(
            videoURL: URL(string: "https://video.example/a.mp4"),
            coverURL: URL(string: "https://video.example/cover.jpg"),
            webURL: nil,
            width: 1280,
            height: 720,
            duration: 12
        )
    }
}
