import Security
import SwiftUI
import XCTest
@testable import TiebaPure

final class TiebaPureSmokeTests: XCTestCase {
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
        XCTAssertEqual(ForumThreadTapPolicy.destination(for: .threadBody), .thread)
        XCTAssertEqual(ForumThreadTapPolicy.destination(for: .media), .media)
        XCTAssertEqual(ForumThreadTapPolicy.destination(for: .stats), .none)
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
            [original]
        )
        XCTAssertTrue(
            TiebaImageSourcePolicy.urls(
                primary: URL(fileURLWithPath: "/tmp/private.png"),
                fallback: privateTarget
            ).isEmpty
        )
    }

    func testSyntheticFixtureImageFailureNeverUsesNetwork() throws {
        let fixture = try XCTUnwrap(URL(string: "https://fixture.invalid/long-image.png"))
        let lookalike = try XCTUnwrap(URL(string: "https://fixture.invalid.example/long-image.png"))
        let wrongScheme = try XCTUnwrap(URL(string: "http://fixture.invalid/long-image.png"))

        XCTAssertTrue(TiebaImageSourcePolicy.isSyntheticFailureURL(fixture))
        XCTAssertFalse(TiebaImageSourcePolicy.isSyntheticFailureURL(lookalike))
        XCTAssertFalse(TiebaImageSourcePolicy.isSyntheticFailureURL(wrongScheme))
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
            thumbnail
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

    func testHomeTabRefreshShowsInlineAnimationOnlyWhenContentExists() {
        XCTAssertTrue(HomeRefreshAnimationPolicy.showsInlineAnimation(
            trigger: .tabTap,
            hasExistingContent: true
        ))
        XCTAssertFalse(HomeRefreshAnimationPolicy.showsInlineAnimation(
            trigger: .tabTap,
            hasExistingContent: false
        ))
        XCTAssertTrue(HomeRefreshAnimationPolicy.showsInlineAnimation(
            trigger: .pullToRefresh,
            hasExistingContent: true
        ))
        XCTAssertFalse(HomeRefreshAnimationPolicy.showsInlineAnimation(
            trigger: .pullToRefresh,
            hasExistingContent: false
        ))
        XCTAssertTrue(HomeRefreshAnimationPolicy.showsInlineAnimation(
            trigger: .appOpen,
            hasExistingContent: true
        ))
        XCTAssertFalse(HomeRefreshAnimationPolicy.showsInlineAnimation(
            trigger: .appOpen,
            hasExistingContent: false
        ))
        XCTAssertFalse(HomeRefreshAnimationPolicy.shouldAnimate(
            trigger: .pullToRefresh,
            hasExistingContent: true,
            reduceMotion: true
        ))
        XCTAssertEqual(
            HomeRefreshAnimationPolicy.minimumVisibleDurationNanoseconds(arguments: []),
            250_000_000
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

    func testShortPullRefreshRequiresTopAndVertical64PointPull() {
        XCTAssertTrue(ShortPullRefreshPolicy.isAtTop(offset: 0))
        XCTAssertTrue(ShortPullRefreshPolicy.isAtTop(offset: -2))
        XCTAssertFalse(ShortPullRefreshPolicy.isAtTop(offset: -3))

        XCTAssertTrue(ShortPullRefreshPolicy.shouldTrigger(
            startedAtTop: true,
            isRefreshing: false,
            translation: CGSize(width: 4, height: 64)
        ))
        XCTAssertFalse(ShortPullRefreshPolicy.shouldTrigger(
            startedAtTop: true,
            isRefreshing: false,
            translation: CGSize(width: 4, height: 63)
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
            translation: CGSize(width: 80, height: 70)
        ))
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

    func testSubpostSheetTitleAndMiddleRightSwipeDismissPolicy() {
        XCTAssertEqual(SubpostSheetTitle.text(floor: 2, count: 10), "2楼的回复(10条)")
        XCTAssertTrue(SubpostDismissSwipePolicy.shouldDismiss(
            startLocationX: 195,
            containerWidth: 390,
            translation: CGSize(width: 120, height: 10),
            predictedEndTranslation: CGSize(width: 150, height: 12)
        ))
        XCTAssertTrue(SubpostDismissSwipePolicy.shouldDismiss(
            startLocationX: 195,
            containerWidth: 390,
            translation: CGSize(width: 60, height: 8),
            predictedEndTranslation: CGSize(width: 180, height: 10)
        ))
        XCTAssertFalse(SubpostDismissSwipePolicy.shouldDismiss(
            startLocationX: 195,
            containerWidth: 390,
            translation: CGSize(width: -140, height: 0),
            predictedEndTranslation: CGSize(width: -180, height: 0)
        ))
        XCTAssertFalse(SubpostDismissSwipePolicy.shouldDismiss(
            startLocationX: 20,
            containerWidth: 390,
            translation: CGSize(width: 140, height: 0),
            predictedEndTranslation: CGSize(width: 180, height: 0)
        ))
        XCTAssertFalse(SubpostDismissSwipePolicy.shouldDismiss(
            startLocationX: 195,
            containerWidth: 390,
            translation: CGSize(width: 110, height: 120),
            predictedEndTranslation: CGSize(width: 180, height: 160)
        ))
    }

    func testThreadDetailMiddleRightSwipeDismissPolicyRejectsEdgeVerticalAndLeftDrags() {
        XCTAssertTrue(ThreadDetailDismissSwipePolicy.shouldDismiss(
            startLocationX: 195,
            containerWidth: 390,
            translation: CGSize(width: 120, height: 8),
            predictedEndTranslation: CGSize(width: 150, height: 10)
        ))
        XCTAssertTrue(ThreadDetailDismissSwipePolicy.shouldDismiss(
            startLocationX: 195,
            containerWidth: 390,
            translation: CGSize(width: 60, height: 4),
            predictedEndTranslation: CGSize(width: 180, height: 8)
        ))
        XCTAssertFalse(ThreadDetailDismissSwipePolicy.shouldDismiss(
            startLocationX: 20,
            containerWidth: 390,
            translation: CGSize(width: 140, height: 0),
            predictedEndTranslation: CGSize(width: 180, height: 0)
        ))
        XCTAssertFalse(ThreadDetailDismissSwipePolicy.shouldDismiss(
            startLocationX: 195,
            containerWidth: 390,
            translation: CGSize(width: -140, height: 0),
            predictedEndTranslation: CGSize(width: -180, height: 0)
        ))
        XCTAssertFalse(ThreadDetailDismissSwipePolicy.shouldDismiss(
            startLocationX: 195,
            containerWidth: 390,
            translation: CGSize(width: 100, height: 100),
            predictedEndTranslation: CGSize(width: 180, height: 160)
        ))
    }

    func testSearchMiddleRightSwipeDismissPolicyRejectsVerticalAndLeftDrags() {
        XCTAssertTrue(SearchDismissSwipePolicy.shouldDismiss(
            startLocationX: 195,
            containerWidth: 390,
            translation: CGSize(width: 120, height: 8),
            predictedEndTranslation: CGSize(width: 150, height: 10)
        ))
        XCTAssertTrue(SearchDismissSwipePolicy.shouldDismiss(
            startLocationX: 20,
            containerWidth: 390,
            translation: CGSize(width: 60, height: 4),
            predictedEndTranslation: CGSize(width: 180, height: 8)
        ))
        XCTAssertFalse(SearchDismissSwipePolicy.shouldDismiss(
            startLocationX: 350,
            containerWidth: 390,
            translation: CGSize(width: 140, height: 0),
            predictedEndTranslation: CGSize(width: 180, height: 0)
        ))
        XCTAssertFalse(SearchDismissSwipePolicy.shouldDismiss(
            startLocationX: 195,
            containerWidth: 390,
            translation: CGSize(width: -140, height: 0),
            predictedEndTranslation: CGSize(width: -180, height: 0)
        ))
        XCTAssertFalse(SearchDismissSwipePolicy.shouldDismiss(
            startLocationX: 195,
            containerWidth: 390,
            translation: CGSize(width: 100, height: 100),
            predictedEndTranslation: CGSize(width: 180, height: 160)
        ))
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
