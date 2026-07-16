import XCTest
import UIKit

final class TiebaPureUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testLaunchShowsHomeWithoutLoginAndRootTabs() {
        let app = launchApp()

        XCTAssertTrue(
            app.navigationBars["首页"].waitForExistence(timeout: 20)
                || rootTab("首页", in: app).exists
        )
        XCTAssertTrue(rootTab("首页", in: app).exists)
        XCTAssertTrue(rootTab("进吧", in: app).exists)
        XCTAssertTrue(rootTab("我的", in: app).exists)
        XCTAssertTrue(threadRows(in: app).firstMatch.waitForExistence(timeout: 45))
    }

    func testThreadAuthorOpensPublicUserProfile() {
        let app = launchApp()
        openFirstThread(in: app)

        let userButton = app.buttons["thread-main-user-button"]
        XCTAssertTrue(userButton.waitForExistence(timeout: 8))
        XCTAssertTrue(userButton.isHittable)
        userButton.tap()

        XCTAssertTrue(app.descendants(matching: .any)["user-profile-screen"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["合成内容作者"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["user-profile-metadata"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["user-profile-follow-button"].exists)
        XCTAssertTrue(app.buttons["user-profile-posts-tab"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["user-profile-thread-row"].waitForExistence(timeout: 8))
        attachScreenshot(named: "fixture-public-user-profile-posts")

        let forumsTab = app.buttons["user-profile-forums-tab"]
        XCTAssertTrue(scrollToHittable(forumsTab, in: app.scrollViews["user-profile-screen"]))
        forumsTab.tap()
        XCTAssertTrue(app.buttons["user-profile-forum-row-0"].waitForExistence(timeout: 5))
        attachScreenshot(named: "fixture-public-user-profile")
    }

    func testPrivateUserProfileShowsExplicitPrivacyStates() {
        let app = launchApp(scenario: "privateProfile")
        openFirstThread(in: app)

        let userButton = app.buttons["thread-main-user-button"]
        XCTAssertTrue(userButton.waitForExistence(timeout: 8))
        userButton.tap()

        XCTAssertTrue(app.descendants(matching: .any)["user-profile-private-posts"].waitForExistence(timeout: 8))
        attachScreenshot(named: "fixture-private-user-profile-posts")
        let forumsTab = app.buttons["user-profile-forums-tab"]
        XCTAssertTrue(scrollToHittable(forumsTab, in: app.scrollViews["user-profile-screen"]))
        forumsTab.tap()
        XCTAssertTrue(app.descendants(matching: .any)["user-profile-private-forums"].waitForExistence(timeout: 5))
        attachScreenshot(named: "fixture-private-user-profile")
    }

    func testLoggedInAccountHeaderOpensOwnUserProfile() {
        let app = launchApp(account: "loggedIn")
        rootTab("我的", in: app).tap()

        let profileButton = app.buttons["me-user-profile-button"]
        XCTAssertTrue(profileButton.waitForExistence(timeout: 8))
        XCTAssertTrue(profileButton.isHittable)
        profileButton.tap()

        XCTAssertTrue(app.descendants(matching: .any)["user-profile-screen"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["模拟登录用户"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["user-profile-follow-button"].exists)
    }

    func testLoggedInUserCanToggleProfileFollowState() {
        let app = launchApp(account: "loggedIn")
        openFirstThread(in: app)

        let userButton = app.buttons["thread-main-user-button"]
        XCTAssertTrue(userButton.waitForExistence(timeout: 8))
        userButton.tap()

        let followButton = app.buttons["user-profile-follow-button"]
        XCTAssertTrue(followButton.waitForExistence(timeout: 8))
        XCTAssertEqual(followButton.label, "关注用户")
        followButton.tap()

        let unfollowButton = app.buttons["user-profile-follow-button"]
        let followed = NSPredicate(format: "label == %@", "取消关注")
        expectation(for: followed, evaluatedWith: unfollowButton)
        waitForExpectations(timeout: 5)
        unfollowButton.tap()

        let unfollowed = NSPredicate(format: "label == %@", "关注用户")
        expectation(for: unfollowed, evaluatedWith: followButton)
        waitForExpectations(timeout: 5)
    }

    func testLoggedInUserCanOpenFollowedUsersFromMe() {
        let app = launchApp(account: "loggedIn")
        rootTab("我的", in: app).tap()

        let entry = app.buttons["followed-users-entry"]
        XCTAssertTrue(entry.waitForExistence(timeout: 8))
        XCTAssertTrue(entry.isHittable)
        entry.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["followed-users-screen"]
                .waitForExistence(timeout: 8)
        )
        let followedUser = app.buttons["followed-user-row-1"]
        XCTAssertTrue(followedUser.waitForExistence(timeout: 8))
        XCTAssertTrue(followedUser.isHittable)
        XCTAssertTrue(app.staticTexts["另一个合成关注用户"].exists)

        followedUser.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["user-profile-screen"]
                .waitForExistence(timeout: 8)
        )
        XCTAssertTrue(app.staticTexts["合成内容作者"].waitForExistence(timeout: 8))
    }

    func testMeFollowRowsMatchBrowsingRowHeight() {
        let app = launchApp(account: "loggedIn")
        rootTab("我的", in: app).tap()

        let followedUsers = app.buttons["followed-users-entry"]
        let followedForums = app.buttons["我的关注吧"]
        let favorites = app.buttons["thread-favorites-entry"]
        let history = app.buttons["browsing-history-entry"]
        XCTAssertTrue(followedUsers.waitForExistence(timeout: 8))
        XCTAssertTrue(followedForums.exists)
        XCTAssertTrue(favorites.exists)
        XCTAssertTrue(history.exists)

        let baselineHeight = favorites.frame.height
        XCTAssertGreaterThanOrEqual(baselineHeight, 44)
        XCTAssertEqual(history.frame.height, baselineHeight, accuracy: 1)
        XCTAssertEqual(followedUsers.frame.height, baselineHeight, accuracy: 1)
        XCTAssertEqual(followedForums.frame.height, baselineHeight, accuracy: 1)
    }

    func testLoggedInUserCanLikeThreadReplyAndSubpost() {
        let app = launchApp(scenario: "subpostReference", account: "loggedIn")
        openFirstThread(in: app)

        let mainLikeButton = app.buttons["thread-main-like-button"]
        XCTAssertTrue(mainLikeButton.waitForExistence(timeout: 8))
        XCTAssertEqual(mainLikeButton.label, "点赞")
        XCTAssertTrue(mainLikeButton.value as? String == "当前12个赞")
        mainLikeButton.tap()
        XCTAssertTrue(waitForLikeState(mainLikeButton, label: "取消点赞", count: 13))

        XCTAssertTrue(waitForElement(named: "thread-like-button-2002", in: app, maxSwipes: 12))
        let replyLikeButton = app.buttons["thread-like-button-2002"]
        XCTAssertEqual(replyLikeButton.label, "点赞")
        replyLikeButton.tap()
        XCTAssertTrue(waitForLikeState(replyLikeButton, label: "取消点赞", count: 4))

        XCTAssertTrue(waitForElement(named: "查看全部4条回复", in: app, maxSwipes: 8))
        app.buttons["查看全部4条回复"].tap()
        XCTAssertTrue(app.navigationBars["2楼的回复(4条)"].waitForExistence(timeout: 8))

        let parentLikeButton = app.buttons["thread-subpost-parent-like-button"]
        XCTAssertTrue(parentLikeButton.waitForExistence(timeout: 8))
        XCTAssertTrue(waitForLikeState(parentLikeButton, label: "取消点赞", count: 4))

        XCTAssertTrue(waitForElement(named: "thread-subpost-like-button-3051", in: app, maxSwipes: 8))
        let subpostLikeButton = app.buttons["thread-subpost-like-button-3051"]
        XCTAssertEqual(subpostLikeButton.label, "点赞")
        subpostLikeButton.tap()
        XCTAssertTrue(waitForLikeState(subpostLikeButton, label: "取消点赞", count: 1))
    }

    func testPullingHomeFeedRefreshesContentAndPreservesExistingRows() {
        let app = launchApp(scenario: "refreshUpdate")

        let firstRow = threadRows(in: app).firstMatch
        XCTAssertTrue(firstRow.waitForExistence(timeout: 45))
        let originalThread = app.buttons["确定性主帖：回复筛选与媒体布局"]
        XCTAssertTrue(originalThread.waitForExistence(timeout: 5))
        XCTAssertFalse(app.searchFields.firstMatch.exists)
        XCTAssertTrue(app.buttons["home-search-button"].isHittable)

        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.20))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.34))
        start.press(forDuration: 0.1, thenDragTo: end)

        XCTAssertTrue(app.buttons["下拉刷新已更新"].waitForExistence(timeout: 5))
        XCTAssertTrue(originalThread.exists, "刷新后应保留之前加载的帖子")
        let refreshedRow = threadRows(in: app).firstMatch
        let navigationBar = app.navigationBars["首页"]
        XCTAssertLessThanOrEqual(refreshedRow.frame.minY - navigationBar.frame.maxY, 24)
    }

    func testShortPullRefreshesThreadDetailAtSameDistanceAsHome() {
        let app = launchApp(scenario: "refreshUpdate")
        openFirstThread(in: app)

        let mainText = app.textViews["thread-main-text"]
        XCTAssertTrue(mainText.waitForExistence(timeout: 8))
        XCTAssertFalse((mainText.value as? String)?.contains("帖子下拉刷新已更新") == true)

        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.20))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.34))
        start.press(forDuration: 0.1, thenDragTo: end)

        let refreshed = NSPredicate(format: "value CONTAINS %@", "帖子下拉刷新已更新")
        expectation(for: refreshed, evaluatedWith: mainText)
        waitForExpectations(timeout: 8)
    }

    func testHomeAndThreadRefreshKeepTopIndicatorsVisible() {
        let app = launchApp(
            scenario: "refreshUpdate",
            additionalArguments: ["UITEST_EXTENDED_REFRESH_ANIMATION"]
        )
        XCTAssertTrue(threadRows(in: app).firstMatch.waitForExistence(timeout: 45))

        let homeStart = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.20))
        let homeEnd = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.34))
        homeStart.press(forDuration: 0.1, thenDragTo: homeEnd)
        XCTAssertTrue(
            app.descendants(matching: .any)["home-refresh-animation"].waitForExistence(timeout: 2)
        )
        attachScreenshot(named: "fixture-home-refresh-indicator")

        openFirstThread(in: app)
        let threadStart = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.20))
        let threadEnd = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.34))
        threadStart.press(forDuration: 0.1, thenDragTo: threadEnd)
        XCTAssertTrue(
            app.descendants(matching: .any)["thread-refresh-animation"].waitForExistence(timeout: 2)
        )
        attachScreenshot(named: "fixture-thread-refresh-indicator")
    }

    func testPullingDownAwayFromHomeTopDoesNotRefresh() {
        let app = launchApp(
            scenario: "refreshUpdate",
            additionalArguments: ["UITEST_EXTENDED_REFRESH_ANIMATION"]
        )

        let homeScrollView = app.scrollViews["home-feed-scroll-view"]
        let firstThread = app.buttons["确定性主帖：回复筛选与媒体布局"]
        XCTAssertTrue(homeScrollView.waitForExistence(timeout: 10))
        XCTAssertTrue(firstThread.waitForExistence(timeout: 45))
        for _ in 0..<6 where firstThread.isHittable {
            homeScrollView.swipeUp()
        }
        XCTAssertFalse(firstThread.isHittable, "测试必须先让首页明确离开顶部")

        let refreshAnimation = app.descendants(matching: .any)["home-refresh-animation"]
        XCTAssertFalse(refreshAnimation.exists)

        let start = homeScrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.48))
        let end = homeScrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.66))
        start.press(forDuration: 0.1, thenDragTo: end)

        XCTAssertFalse(
            refreshAnimation.waitForExistence(timeout: 1.5),
            "首页不在顶部时向下滑动不得触发刷新"
        )
    }

    func testPullingEmptyForumStateLoadsContent() {
        let app = launchApp(scenario: "emptyThenSuccess")

        rootTab("进吧", in: app).tap()
        let forumField = app.textFields["输入吧名"]
        XCTAssertTrue(forumField.waitForExistence(timeout: 10))
        forumField.tap()
        forumField.typeText("测试")
        let enterForum = app.buttons["进入贴吧"]
        XCTAssertTrue(enterForum.isHittable)
        enterForum.tap()

        XCTAssertTrue(app.navigationBars["测试吧"].waitForExistence(timeout: 10))
        let emptyTitle = app.staticTexts["暂无帖子"]
        XCTAssertTrue(emptyTitle.waitForExistence(timeout: 10))
        let stateScrollView = app.scrollViews["reader-state-scroll-view"]
        XCTAssertTrue(stateScrollView.exists)

        let start = stateScrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
        let end = stateScrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
        start.press(forDuration: 0.2, thenDragTo: end)

        XCTAssertTrue(threadRows(in: app).firstMatch.waitForExistence(timeout: 10))
    }

    func testHomeTabReselectAfterScrollingRefreshesContent() {
        let app = launchApp(scenario: "refreshUpdate")

        let firstRow = threadRows(in: app).firstMatch
        XCTAssertTrue(firstRow.waitForExistence(timeout: 45))
        let homeTab = rootTab("首页", in: app)
        XCTAssertTrue(homeTab.isHittable)
        let appFrame = app.frame
        let homeTabFrame = homeTab.frame
        let homeTabCoordinate = app.coordinate(withNormalizedOffset: CGVector(
            dx: homeTabFrame.midX / appFrame.width,
            dy: homeTabFrame.midY / appFrame.height
        ))

        app.swipeUp()
        app.swipeUp()
        homeTabCoordinate.tap()

        XCTAssertTrue(app.buttons["下拉刷新已更新"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["确定性主帖：回复筛选与媒体布局"].exists)
    }

    func testForumHubAndMeKeepLoginOutOfHome() {
        let app = launchApp()

        rootTab("进吧", in: app).tap()
        XCTAssertTrue(app.navigationBars["进吧"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.textFields["输入吧名"].exists)

        rootTab("我的", in: app).tap()
        XCTAssertTrue(app.navigationBars["我的"].waitForExistence(timeout: 10))
        let loginButton = app.buttons["手机号验证码登录"]
        let followedForumsButton = app.buttons["我的关注吧"]
        XCTAssertTrue(
            loginButton.waitForExistence(timeout: 5) || followedForumsButton.waitForExistence(timeout: 5)
        )
    }

    func testViewingThreadAddsBrowsingHistoryInMeAndReopensIt() {
        let app = launchApp()
        openFirstThread(in: app)
        XCTAssertTrue(app.buttons["更多"].waitForExistence(timeout: 8))

        let threadBackButton = app.navigationBars.buttons.firstMatch
        XCTAssertTrue(threadBackButton.isHittable)
        threadBackButton.tap()
        XCTAssertTrue(rootTab("我的", in: app).waitForExistence(timeout: 8))

        rootTab("我的", in: app).tap()
        let historyEntry = app.buttons["browsing-history-entry"]
        XCTAssertTrue(historyEntry.waitForExistence(timeout: 8))
        historyEntry.tap()

        XCTAssertTrue(app.navigationBars["浏览历史"].waitForExistence(timeout: 8))
        let historyRow = app.buttons["browsing-history-row-1001"]
        XCTAssertTrue(historyRow.waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["确定性主帖：回复筛选与媒体布局"].exists)

        historyRow.tap()
        XCTAssertTrue(app.buttons["更多"].waitForExistence(timeout: 8))
    }

    func testThreadFavoriteAppearsInMeAndReopensIt() {
        let app = launchApp()
        openFirstThread(in: app)

        let favoriteButton = app.buttons["thread-favorite-button"]
        XCTAssertTrue(favoriteButton.waitForExistence(timeout: 8))
        XCTAssertTrue(favoriteButton.isHittable)
        favoriteButton.tap()
        let favoriteUpdated = NSPredicate(format: "label == %@", "取消收藏帖子")
        expectation(for: favoriteUpdated, evaluatedWith: favoriteButton)
        waitForExpectations(timeout: 5)

        let threadBackButton = app.navigationBars.buttons.firstMatch
        XCTAssertTrue(threadBackButton.isHittable)
        threadBackButton.tap()
        rootTab("我的", in: app).tap()

        let favoritesEntry = app.buttons["thread-favorites-entry"]
        XCTAssertTrue(favoritesEntry.waitForExistence(timeout: 8))
        favoritesEntry.tap()
        XCTAssertTrue(app.navigationBars["帖子收藏"].waitForExistence(timeout: 8))

        let favoriteRow = app.buttons["thread-favorite-row-1001"]
        XCTAssertTrue(favoriteRow.waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["确定性主帖：回复筛选与媒体布局"].exists)
        favoriteRow.tap()
        XCTAssertTrue(app.buttons["thread-favorite-button"].waitForExistence(timeout: 8))
    }

    func testSavedReadingPositionOffersContinueAndTargetsReply() {
        let app = launchApp(additionalArguments: ["UITEST_SEED_LOCAL_THREAD_LIBRARY"])
        rootTab("我的", in: app).tap()

        let favoritesEntry = app.buttons["thread-favorites-entry"]
        XCTAssertTrue(favoritesEntry.waitForExistence(timeout: 8))
        favoritesEntry.tap()
        XCTAssertTrue(app.buttons["thread-library-manage"].waitForExistence(timeout: 8))
        let favoriteRow = app.buttons["thread-favorite-row-1001"]
        XCTAssertTrue(favoriteRow.waitForExistence(timeout: 8))
        favoriteRow.tap()

        let continueReading = app.buttons["continue-reading-button"]
        XCTAssertTrue(continueReading.waitForExistence(timeout: 8))
        XCTAssertEqual(continueReading.value as? String, "2楼")
        let replyText = app.textViews["thread-reply-text"].firstMatch
        XCTAssertTrue(replyText.waitForExistence(timeout: 8))
        continueReading.tap()

        let replyBecameVisible = NSPredicate(format: "hittable == true")
        expectation(for: replyBecameVisible, evaluatedWith: replyText)
        waitForExpectations(timeout: 5)
        XCTAssertTrue((replyText.value as? String)?.contains("确定性回复内容") == true)
        XCTAssertFalse(continueReading.exists)
    }

    func testVerifiedLoginSkipPasswordStaysInAppAndPublishesAccount() {
        let app = launchApp(additionalArguments: ["UITEST_LOGIN_REDIRECT_FIXTURE"])

        rootTab("我的", in: app).tap()
        let loginButton = app.buttons["手机号验证码登录"]
        XCTAssertTrue(loginButton.waitForExistence(timeout: 8))
        loginButton.tap()

        let skipPassword = app.links["跳过设置密码"]
        XCTAssertTrue(skipPassword.waitForExistence(timeout: 8))
        XCTAssertFalse(app.alerts["登录失败"].exists)
        skipPassword.tap()

        XCTAssertTrue(app.staticTexts["模拟登录用户"].waitForExistence(timeout: 8))
        let loginNavigationBar = app.navigationBars["手机号验证码登录"]
        let dismissed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: loginNavigationBar
        )
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 5), .completed)
        XCTAssertFalse(app.alerts["登录失败"].exists)
        XCTAssertTrue(app.state == .runningForeground)
    }

    func testSearchResultRoutesToMatchedReply() {
        let app = launchApp()

        let searchField = openGlobalSearch(in: app)
        searchField.typeText("iPhone")
        searchField.typeText("\n")

        XCTAssertTrue(app.navigationBars["搜索"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.segmentedControls.buttons["全部"].waitForExistence(timeout: 10))
        let firstResult = threadRows(in: app).firstMatch
        XCTAssertTrue(firstResult.waitForExistence(timeout: 10))
        app.descendants(matching: .any).matching(identifier: "thread-open-area").firstMatch.tap()
        XCTAssertTrue(waitForLabelContaining("已定位搜索命中回复", in: app, maxSwipes: 10))
    }

    func testSearchBackButtonDismissesFocusedSearchInOneStepAndHistoryPersists() {
        let app = launchApp()
        let searchField = openGlobalSearch(in: app)
        searchField.typeText("history-test")
        searchField.typeText("\n")
        XCTAssertTrue(threadRows(in: app).firstMatch.waitForExistence(timeout: 8))

        let backButton = app.buttons["search-back-button"]
        XCTAssertTrue(backButton.isHittable)
        backButton.tap()

        XCTAssertTrue(app.navigationBars["首页"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.navigationBars["搜索"].exists)

        let reopenedField = openGlobalSearch(in: app)
        XCTAssertTrue(reopenedField.exists)
        let historyItem = app.buttons["search-history-item-0"]
        XCTAssertTrue(historyItem.waitForExistence(timeout: 5))
        XCTAssertTrue(historyItem.label.contains("history-test"))
        XCTAssertTrue(app.buttons["search-history-clear-all"].exists)
    }

    func testSearchSupportsMiddleRightSwipeToPreviousPage() {
        let app = launchApp()
        _ = openGlobalSearch(in: app)
        let searchNavigationBar = app.navigationBars["搜索"]

        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.38))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.88, dy: 0.38))
        start.press(forDuration: 0.05, thenDragTo: end)

        let dismissed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: searchNavigationBar
        )
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 5), .completed)
        XCTAssertTrue(app.navigationBars["首页"].exists)
        XCTAssertTrue(rootTab("首页", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(rootTab("进吧", in: app).exists)
        XCTAssertTrue(rootTab("我的", in: app).exists)
    }

    func testRootTabsRestoreAfterReturningFromFollowedUserProfileAndThread() {
        let app = launchApp(account: "loggedIn")
        openFirstThread(in: app)

        let userButton = app.buttons["thread-main-user-button"]
        XCTAssertTrue(userButton.waitForExistence(timeout: 8))
        userButton.tap()
        XCTAssertTrue(app.descendants(matching: .any)["user-profile-screen"].waitForExistence(timeout: 8))

        let followButton = app.buttons["user-profile-follow-button"]
        XCTAssertTrue(followButton.waitForExistence(timeout: 5))
        followButton.tap()
        let followed = NSPredicate(format: "label == %@", "取消关注")
        expectation(for: followed, evaluatedWith: followButton)
        waitForExpectations(timeout: 5)

        let profileNavigationBar = app.navigationBars["用户主页"]
        XCTAssertTrue(profileNavigationBar.waitForExistence(timeout: 5))
        let profileBackButton = profileNavigationBar.buttons.element(boundBy: 0)
        XCTAssertTrue(profileBackButton.isHittable)
        profileBackButton.tap()
        XCTAssertTrue(app.buttons["更多"].waitForExistence(timeout: 5))

        middleSwipeRight(in: app)
        XCTAssertTrue(app.navigationBars["首页"].waitForExistence(timeout: 5))
        XCTAssertTrue(rootTab("首页", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(rootTab("进吧", in: app).exists)
        XCTAssertTrue(rootTab("我的", in: app).exists)
    }

    func testThreadDetailSupportsMiddleRightSwipeToPreviousPage() {
        let app = launchApp()
        openFirstThread(in: app)
        let detailMarker = app.buttons["更多"]
        XCTAssertTrue(detailMarker.exists)

        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.38))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.88, dy: 0.38))
        start.press(forDuration: 0.05, thenDragTo: end)

        let dismissed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: detailMarker
        )
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 5), .completed)
        XCTAssertTrue(app.navigationBars["首页"].exists)
        XCTAssertTrue(rootTab("首页", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(rootTab("进吧", in: app).exists)
        XCTAssertTrue(rootTab("我的", in: app).exists)
    }

    func testRightSwipeOnThreadImageDismissesWithoutOpeningPreview() {
        let app = launchApp(scenario: "imageGesture")
        openFirstThread(in: app)

        let inlineImage = visibleThreadInlineImage(in: app)
        XCTAssertNotNil(inlineImage)
        guard let inlineImage else { return }

        let imageFrame = inlineImage.frame
        let appFrame = app.frame
        let visibleY = min(max(imageFrame.midY, appFrame.minY + 140), appFrame.maxY - 120)
        let localY = min(max((visibleY - imageFrame.minY) / imageFrame.height, 0.1), 0.9)
        let start = inlineImage.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: localY))
        let end = app.coordinate(withNormalizedOffset: CGVector(
            dx: 0.9,
            dy: (visibleY - appFrame.minY) / appFrame.height
        ))
        start.press(forDuration: 0.05, thenDragTo: end)

        let preview = app.descendants(matching: .any)["full-screen-image-pager"]
        XCTAssertFalse(preview.waitForExistence(timeout: 1), "图片区域右划不得打开全屏预览")
        XCTAssertTrue(app.navigationBars["首页"].waitForExistence(timeout: 5))
    }

    func testTappingThreadImageStillOpensPreview() {
        let app = launchApp(scenario: "imageGesture")
        openFirstThread(in: app)

        let inlineImage = visibleThreadInlineImage(in: app)
        XCTAssertNotNil(inlineImage)
        guard let inlineImage else { return }
        inlineImage.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["full-screen-image-pager"].waitForExistence(timeout: 5),
            "真正点按图片仍应打开全屏预览"
        )
    }

    func testThreadDetailShowsReplyControls() {
        let app = launchApp()

        openFirstThread(in: app)

        XCTAssertTrue(waitForElement(named: "全部回复", in: app, maxSwipes: 30))
        XCTAssertTrue(app.descendants(matching: .any)["只看楼主"].exists)
        XCTAssertTrue(app.buttons["按热门排列回复"].exists)
        XCTAssertTrue(app.buttons["按正序排列回复"].exists)
        XCTAssertTrue(app.buttons["按倒序排列回复"].exists)

        XCTAssertTrue(app.buttons["更多"].exists)
        app.buttons["更多"].tap()
        XCTAssertTrue(app.buttons["复制链接"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["刷新"].exists)
        app.buttons["复制链接"].tap()
        XCTAssertTrue(app.alerts["已复制链接"].waitForExistence(timeout: 5))
        app.alerts["已复制链接"].buttons["好"].tap()

        XCTAssertTrue(app.buttons["搜索本吧"].exists)
        app.buttons["搜索本吧"].tap()
        XCTAssertTrue(app.textFields["search-input"].waitForExistence(timeout: 10))
    }

    func testThreadLevelBadgeStaysOnOneLine() {
        let app = launchApp()
        openFirstThread(in: app)

        let referenceHeight = visibleLevelBadge(authorID: 1, in: app).frame.height
        assertAuthorIdentityIsSingleRow(authorID: 1, isMainPost: true, includesThreadAuthorBadge: true, in: app)
        let badge = visibleLevelBadge(authorID: 2, in: app)
        XCTAssertEqual(badge.label, "贴吧等级13 血之磐涅")
        XCTAssertEqual(
            badge.frame.height,
            referenceHeight,
            accuracy: 1,
            "长等级徽章应与同字号短徽章保持相同的单行高度"
        )
        assertAuthorIdentityIsSingleRow(authorID: 2, isMainPost: false, in: app)
        attachScreenshot(named: "fixture-single-line-user-level-badge")
    }

    func testThreadLevelBadgeStaysOnOneLineAtAccessibilityXXXL() {
        let app = launchApp(additionalArguments: [
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityXXXL"
        ])
        openFirstThread(in: app)

        let referenceHeight = visibleLevelBadge(authorID: 1, in: app).frame.height
        assertAuthorIdentityIsSingleRow(authorID: 1, isMainPost: true, includesThreadAuthorBadge: true, in: app)
        let badge = visibleLevelBadge(authorID: 2, in: app)
        XCTAssertEqual(badge.label, "贴吧等级13 血之磐涅")
        XCTAssertEqual(
            badge.frame.height,
            referenceHeight,
            accuracy: 1,
            "无障碍大字体下长等级徽章仍应保持单行高度"
        )
        assertAuthorIdentityIsSingleRow(authorID: 2, isMainPost: false, in: app)
        attachScreenshot(named: "fixture-single-line-user-level-badge-axxxl")
    }

    func testAboutShowsTiebaLiteAttributionAndGPL() {
        let app = launchApp()

        rootTab("我的", in: app).tap()
        XCTAssertTrue(waitForElement(named: "关于 TiebaPure", in: app, maxSwipes: 4))
        app.buttons["关于 TiebaPure"].tap()
        XCTAssertTrue(waitForLabelContaining("infinityf4p", in: app, maxSwipes: 2))
        XCTAssertTrue(waitForLabelContaining("开源与来源", in: app, maxSwipes: 4))
        XCTAssertTrue(waitForLabelContaining("GPL-3.0-only", in: app, maxSwipes: 5))
        XCTAssertTrue(waitForLabelContaining("查看 TiebaLite 来源项目", in: app, maxSwipes: 5))
    }

    func testFixtureEmptyStateIsDeterministic() {
        let app = launchApp(scenario: "empty")
        XCTAssertTrue(app.staticTexts["暂无推荐"].waitForExistence(timeout: 8))
    }

    func testFixtureErrorStateOffersAccessibleRetry() {
        let app = launchApp(scenario: "error")
        XCTAssertTrue(waitForLabelContaining("网络不可用", in: app, maxSwipes: 1))
        XCTAssertTrue(app.buttons["重试"].exists)
    }

    func testPaginationFailureKeepsContentAndRetriesSamePage() {
        let app = launchApp(scenario: "paginationFailure")
        XCTAssertTrue(threadRows(in: app).firstMatch.waitForExistence(timeout: 8))
        let retry = app.buttons["重试"]
        if waitForElement(named: "重试", in: app, maxSwipes: 8) == false {
            XCTAssertTrue(waitForElement(named: "加载更多", in: app, maxSwipes: 8))
            app.buttons["加载更多"].tap()
            XCTAssertTrue(waitForElement(named: "重试", in: app, maxSwipes: 8))
        }
        retry.tap()
        XCTAssertFalse(retry.waitForExistence(timeout: 2))
        XCTAssertTrue(threadRows(in: app).firstMatch.exists)
    }

    func testTallInlineImageOffersOriginalEntry() {
        let app = launchApp(scenario: "longContent")
        openFirstThread(in: app)
        XCTAssertTrue(waitForLabelContaining("查看原图", in: app, maxSwipes: 20))
    }

    func testThreadDetailMainReplyAndSubpostsWrapWithoutTruncation() {
        let app = launchApp(scenario: "longContent")
        openFirstThread(in: app)

        let mainText = elementWithIdentifier(
            "thread-main-text",
            in: app,
            maxSwipes: 0
        )
        XCTAssertNotNil(mainText)
        XCTAssertGreaterThan(mainText?.frame.height ?? 0, 120)

        let replyText = elementWithIdentifier(
            "thread-reply-text",
            in: app,
            maxSwipes: 20
        )
        XCTAssertNotNil(replyText)
        XCTAssertGreaterThan(replyText?.frame.height ?? 0, 100)

        let previewText = elementWithIdentifier(
            "thread-subpost-preview-text",
            in: app,
            maxSwipes: 8
        )
        XCTAssertNotNil(previewText)
        XCTAssertGreaterThan(previewText?.frame.height ?? 0, 80)

        XCTAssertTrue(waitForElement(named: "查看全部4条回复", in: app, maxSwipes: 6))
        app.buttons["查看全部4条回复"].tap()
        XCTAssertTrue(app.navigationBars["2楼的回复(4条)"].waitForExistence(timeout: 8))

        let parentText = elementWithIdentifier(
            "thread-subpost-parent-text",
            in: app,
            maxSwipes: 0
        )
        XCTAssertNotNil(parentText)
        XCTAssertGreaterThan(parentText?.frame.height ?? 0, 100)

        let subpostText = elementWithIdentifier(
            "thread-subpost-text",
            in: app,
            maxSwipes: 8
        )
        XCTAssertNotNil(subpostText)
        XCTAssertGreaterThan(subpostText?.frame.height ?? 0, 80)
        XCTAssertTrue(app.descendants(matching: .any)["thread-subpost-metadata"].exists)
    }

    func testThreadDetailTextSupportsNativeCopySelection() {
        let app = launchApp(scenario: "longContent")
        openFirstThread(in: app)

        let mainText = app.textViews["thread-main-text"]
        XCTAssertTrue(mainText.waitForExistence(timeout: 8))
        XCTAssertTrue(mainText.isHittable)
        mainText.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.2))
            .press(forDuration: 1.2)

        let copyControl = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label IN %@", ["复制", "拷贝", "Copy"]))
            .firstMatch
        XCTAssertTrue(copyControl.waitForExistence(timeout: 5))
        XCTAssertTrue(copyControl.isHittable)
        copyControl.tap()
        XCTAssertTrue(app.buttons["更多"].exists)
    }

    func testSubpostRightSwipeDismissesTheWholeSheet() {
        let app = launchApp(scenario: "subpostReference")
        openFirstThread(in: app)

        XCTAssertTrue(waitForElement(named: "查看全部4条回复", in: app, maxSwipes: 20))
        let openAllButton = app.buttons["查看全部4条回复"]
        XCTAssertEqual(openAllButton.frame.height, 36, accuracy: 1)
        openAllButton.tap()
        let navigationBar = app.navigationBars["2楼的回复(4条)"]
        XCTAssertTrue(navigationBar.waitForExistence(timeout: 8))
        attachScreenshot(named: "fixture-subpost-reference-layout")

        let downwardStart = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.32))
        let downwardEnd = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.72))
        downwardStart.press(forDuration: 0.05, thenDragTo: downwardEnd)
        XCTAssertTrue(navigationBar.exists, "楼中楼下滑只能滚动内容，不应退出")

        let swipeStart = app.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.45))
        let swipeEnd = app.coordinate(withNormalizedOffset: CGVector(dx: 0.88, dy: 0.45))
        swipeStart.press(
            forDuration: 0.05,
            thenDragTo: swipeEnd,
            withVelocity: 300,
            thenHoldForDuration: 0.4
        )

        let dismissed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: navigationBar
        )
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 5), .completed)
        XCTAssertTrue(app.buttons["更多"].waitForExistence(timeout: 3))
        attachScreenshot(named: "fixture-subpost-returned-to-thread")
    }

    func testFullScreenImageOffersDownloadAndTapReturnsToSource() {
        let app = launchApp(additionalArguments: ["UITEST_IMAGE_VIEWER"])

        let saveButton = app.buttons["save-current-image"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["关闭图片"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["full-screen-image-pager"].exists)

        let zoomSurface = app.images["full-screen-image-zoom-surface-0"]
        XCTAssertTrue(zoomSurface.waitForExistence(timeout: 5))
        XCTAssertEqual(zoomSurface.value as? String, "缩放 100%")

        app.pinch(withScale: 2, velocity: 2)
        let zoomed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value != %@", "缩放 100%"),
            object: zoomSurface
        )
        XCTAssertEqual(XCTWaiter.wait(for: [zoomed], timeout: 5), .completed)
        XCTAssertTrue(app.buttons["关闭图片"].exists, "捏合缩放不应关闭图片页")

        let enlargedPercentage = Int(
            (zoomSurface.value as? String ?? "").filter(\.isNumber)
        ) ?? 100
        XCTAssertGreaterThan(enlargedPercentage, 100)

        app.doubleTap()
        let reset = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "缩放 100%"),
            object: zoomSurface
        )
        XCTAssertEqual(XCTWaiter.wait(for: [reset], timeout: 5), .completed)

        saveButton.tap()
        XCTAssertTrue(app.alerts["图片已保存"].waitForExistence(timeout: 5))
        app.alerts["图片已保存"].buttons["好"].tap()

        app.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.3)).tap()

        XCTAssertTrue(app.staticTexts["图片来源页"].waitForExistence(timeout: 5))
    }

    func testSyntheticScreenshotMatrix() {
        let app = launchApp()
        XCTAssertTrue(threadRows(in: app).firstMatch.waitForExistence(timeout: 8))
        attachScreenshot(named: "fixture-home")

        let searchField = openGlobalSearch(in: app)
        searchField.typeText("合成测试")
        searchField.typeText("\n")
        XCTAssertTrue(threadRows(in: app).firstMatch.waitForExistence(timeout: 8))
        attachScreenshot(named: "fixture-search-controls")

        app.descendants(matching: .any).matching(identifier: "thread-open-area").firstMatch.tap()
        XCTAssertTrue(waitForElement(named: "全部回复", in: app, maxSwipes: 10))
        app.swipeUp()
        attachScreenshot(named: "fixture-thread-controls")
    }

    func testLandscapeHomeAndSearchLayout() {
        let app = launchApp()
        XCUIDevice.shared.orientation = .landscapeLeft
        addTeardownBlock {
            XCUIDevice.shared.orientation = .portrait
        }

        XCTAssertTrue(threadRows(in: app).firstMatch.waitForExistence(timeout: 8))
        XCTAssertTrue(rootTab("首页", in: app).isHittable)
        attachScreenshot(named: "fixture-landscape-home")

        let searchField = openGlobalSearch(in: app)
        searchField.typeText("横屏")
        searchField.typeText("\n")
        XCTAssertTrue(threadRows(in: app).firstMatch.waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["排序：最新"].exists || waitForLabelContaining("最新", in: app, maxSwipes: 1))
        attachScreenshot(named: "fixture-landscape-search")
    }

    func testFixtureMediaCountMatrixIsAccessible() {
        let app = launchApp()
        XCTAssertTrue(threadRows(in: app).firstMatch.waitForExistence(timeout: 8))
        XCTAssertTrue(waitForLabelContaining("共4项媒体", in: app, maxSwipes: 2))
        XCTAssertTrue(waitForLabelContaining("共1项媒体", in: app, maxSwipes: 6))
        XCTAssertTrue(waitForLabelContaining("共3项媒体", in: app, maxSwipes: 6))
        attachScreenshot(named: "fixture-media-count-matrix")
    }

    func testForegroundBackgroundKeepsFixtureContent() {
        let app = launchApp()
        XCTAssertTrue(threadRows(in: app).firstMatch.waitForExistence(timeout: 8))

        XCUIDevice.shared.press(.home)
        app.activate()

        XCTAssertTrue(threadRows(in: app).firstMatch.waitForExistence(timeout: 8))
        XCTAssertTrue(rootTab("首页", in: app).isHittable)
    }

    func testFollowedForumWholeRowNavigatesWithoutGestureConflict() {
        let app = launchApp(account: "loggedIn")
        rootTab("我的", in: app).tap()
        XCTAssertTrue(app.buttons["我的关注吧"].waitForExistence(timeout: 8))
        app.buttons["我的关注吧"].tap()
        XCTAssertTrue(app.navigationBars["我的关注吧"].waitForExistence(timeout: 8))

        let row = app.buttons.matching(identifier: "followed-forum-row").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 8))
        row.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap()

        XCTAssertTrue(app.navigationBars["测试吧"].waitForExistence(timeout: 8))
        XCTAssertTrue(threadRows(in: app).firstMatch.waitForExistence(timeout: 8))
    }

    func testAppearanceSettingWorksForGuestAndPersistsAcrossRelaunch() {
        let expectedSystemAppearance = UITraitCollection.current.userInterfaceStyle == .dark
            ? "深色"
            : "浅色"
        var app = launchApp()
        rootTab("我的", in: app).tap()

        let settingsEntry = app.descendants(matching: .any)["app-settings-entry"]
        XCTAssertTrue(settingsEntry.waitForExistence(timeout: 8))
        XCTAssertTrue(settingsEntry.isHittable)
        settingsEntry.tap()
        XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout: 8))
        XCTAssertTrue(waitForAppearance(expectedSystemAppearance, in: app))

        let darkOption = appearanceOption("深色", in: app)
        XCTAssertTrue(darkOption.waitForExistence(timeout: 5))
        darkOption.tap()
        XCTAssertTrue(waitForAppearance("深色", in: app))
        attachScreenshot(named: "fixture-settings-dark")

        app.terminate()
        app = launchApp(resetAppearance: false)
        rootTab("我的", in: app).tap()
        XCTAssertTrue(app.descendants(matching: .any)["app-settings-entry"].waitForExistence(timeout: 8))
        app.descendants(matching: .any)["app-settings-entry"].tap()
        XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout: 8))
        XCTAssertTrue(waitForAppearance("深色", in: app))

        let lightOption = appearanceOption("浅色", in: app)
        XCTAssertTrue(lightOption.waitForExistence(timeout: 5))
        lightOption.tap()
        XCTAssertTrue(waitForAppearance("浅色", in: app))

        let systemOption = appearanceOption("跟随系统", in: app)
        XCTAssertTrue(systemOption.waitForExistence(timeout: 5))
        systemOption.tap()
        XCTAssertTrue(waitForAppearance(expectedSystemAppearance, in: app))
    }

    func testFailedInlineImageRetryDoesNotOpenOrClosePreview() {
        let app = launchApp(scenario: "longContent")
        openFirstThread(in: app)

        let retry = buttonLabelContaining("图片加载失败", in: app, maxSwipes: 20)
        XCTAssertNotNil(retry)
        retry?.tap()

        XCTAssertFalse(app.buttons["关闭图片"].exists)
        XCTAssertTrue(app.buttons["更多"].exists)
    }

    func testEmptyFilteredSearchKeepsControlsAvailable() {
        let app = launchApp()
        let searchField = openGlobalSearch(in: app)
        searchField.typeText("仅回复命中")
        searchField.typeText("\n")
        XCTAssertTrue(threadRows(in: app).firstMatch.waitForExistence(timeout: 8))

        let topicFilter = app.segmentedControls.buttons["主题"]
        XCTAssertTrue(topicFilter.isHittable)
        topicFilter.tap()
        XCTAssertTrue(app.staticTexts["没有结果"].waitForExistence(timeout: 8))

        let allFilter = app.segmentedControls.buttons["全部"]
        XCTAssertTrue(allFilter.exists)
        XCTAssertTrue(allFilter.isHittable)
        allFilter.tap()
        XCTAssertTrue(threadRows(in: app).firstMatch.waitForExistence(timeout: 8))
    }

    func testPostHTTPSLinkExposesNativeLinkTrait() {
        let app = launchApp()
        openFirstThread(in: app)

        let link = app.links["百度贴吧 HTTPS 链接"]
        if link.waitForExistence(timeout: 5) == false || link.isHittable == false {
            for _ in 0..<20 {
                if link.exists, link.isHittable { break }
                app.swipeUp()
            }
        }
        XCTAssertTrue(link.exists)
        XCTAssertTrue(link.isHittable)
    }

    func testReduceMotionSuppressesCustomRefreshAnimation() throws {
        guard UIAccessibility.isReduceMotionEnabled else {
            throw XCTSkip("仅在已启用 Reduce Motion 的设备矩阵中运行。")
        }
        let app = launchApp()
        let firstRow = threadRows(in: app).firstMatch
        XCTAssertTrue(firstRow.waitForExistence(timeout: 8))

        let start = firstRow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15))
        let end = firstRow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 1.35))
        start.press(forDuration: 0.1, thenDragTo: end)

        XCTAssertFalse(app.descendants(matching: .any)["home-refresh-animation"].waitForExistence(timeout: 2))
    }

    func testForumListMediaIsDecorativeAndWholeRowOpensThread() {
        let app = launchApp()
        rootTab("进吧", in: app).tap()
        let forumField = app.textFields["输入吧名"]
        XCTAssertTrue(forumField.waitForExistence(timeout: 8))
        forumField.tap()
        forumField.typeText("测试\n")

        XCTAssertTrue(app.navigationBars["测试吧"].waitForExistence(timeout: 8))
        let row = threadRows(in: app).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 8))
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "帖子图片")).count, 0)

        row.tap()
        XCTAssertTrue(app.buttons["更多"].waitForExistence(timeout: 8))
    }

    func testSwitchingToHomeDoesNotTriggerReselectRefresh() {
        let app = launchApp()
        XCTAssertTrue(threadRows(in: app).firstMatch.waitForExistence(timeout: 8))
        rootTab("进吧", in: app).tap()
        XCTAssertTrue(app.navigationBars["进吧"].waitForExistence(timeout: 8))

        rootTab("首页", in: app).tap()
        XCTAssertTrue(threadRows(in: app).firstMatch.waitForExistence(timeout: 8))
        XCTAssertFalse(app.descendants(matching: .any)["home-refresh-animation"].exists)
    }

    func testIPadTabBarBlankSpaceDoesNotSelectOrRefreshHome() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else {
            throw XCTSkip("仅在 iPad 设备矩阵中运行。")
        }
        let app = launchApp()
        rootTab("进吧", in: app).tap()
        XCTAssertTrue(app.navigationBars["进吧"].waitForExistence(timeout: 8))

        let tabElements = ["首页", "进吧", "我的"].map { rootTab($0, in: app) }
        XCTAssertTrue(tabElements.allSatisfy(\.exists))
        let leadingX = tabElements.map(\.frame.minX).min() ?? 0
        XCTAssertGreaterThan(leadingX, 24)
        let tabY = tabElements.map(\.frame.midY).reduce(0, +) / CGFloat(tabElements.count)
        let appFrame = app.frame
        app.coordinate(withNormalizedOffset: CGVector(
            dx: max(2, leadingX - 20) / appFrame.width,
            dy: tabY / appFrame.height
        )).tap()

        XCTAssertTrue(app.navigationBars["进吧"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["home-refresh-animation"].exists)
    }

    func testIPadHomeThreadTitleAndSummaryBothOpenDetail() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else {
            throw XCTSkip("仅在 iPad 设备矩阵中运行。")
        }
        let app = launchApp()
        var openArea = app.descendants(matching: .any).matching(identifier: "thread-open-area").firstMatch
        XCTAssertTrue(openArea.waitForExistence(timeout: 8))

        openArea.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.2)).tap()
        XCTAssertTrue(app.buttons["更多"].waitForExistence(timeout: 8))

        let backButton = app.navigationBars.buttons.firstMatch
        XCTAssertTrue(backButton.isHittable)
        backButton.tap()

        openArea = app.descendants(matching: .any).matching(identifier: "thread-open-area").firstMatch
        XCTAssertTrue(openArea.waitForExistence(timeout: 8))
        openArea.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.82)).tap()
        XCTAssertTrue(app.buttons["更多"].waitForExistence(timeout: 8))
    }

    private func launchApp(
        scenario: String = "success",
        account: String? = nil,
        additionalArguments: [String] = [],
        resetAppearance: Bool = true
    ) -> XCUIApplication {
        let app = XCUIApplication()
        var launchArguments = [
            "UITEST_USE_FIXTURES",
            "UITEST_DISABLE_ANIMATIONS",
            "UITEST_RESET_SEARCH_HISTORY",
            "UITEST_RESET_BROWSING_HISTORY",
            "UITEST_RESET_LOCAL_THREAD_LIBRARY"
        ]
        if resetAppearance {
            launchArguments.append("UITEST_RESET_APPEARANCE")
        }
        app.launchArguments = launchArguments + additionalArguments
        app.launchEnvironment["TIEBAPURE_FIXTURE_SCENARIO"] = scenario
        if let account {
            app.launchEnvironment["TIEBAPURE_FIXTURE_ACCOUNT"] = account
        }
        app.launch()
        return app
    }

    private func waitForAppearance(_ appearance: String, in app: XCUIApplication) -> Bool {
        let effectiveMode = app.descendants(matching: .any)["appearance-effective-mode"]
        let predicate = NSPredicate(format: "label CONTAINS %@", appearance)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: effectiveMode)
        return XCTWaiter.wait(for: [expectation], timeout: 5) == .completed
    }

    private func waitForLikeState(
        _ button: XCUIElement,
        label: String,
        count: Int
    ) -> Bool {
        let predicate = NSPredicate(
            format: "label == %@ AND value == %@",
            label,
            "当前\(count)个赞"
        )
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: button)
        return XCTWaiter.wait(for: [expectation], timeout: 5) == .completed
    }

    private func visibleLevelBadge(authorID: Int64, in app: XCUIApplication) -> XCUIElement {
        let badge = app.descendants(matching: .any)["thread-user-level-badge-\(authorID)"]
        if badge.waitForExistence(timeout: 5) == false || badge.isHittable == false {
            for _ in 0..<12 {
                if badge.exists, badge.isHittable { break }
                app.swipeUp()
            }
        }
        XCTAssertTrue(badge.exists)
        XCTAssertTrue(badge.isHittable)
        return badge
    }

    private func assertAuthorIdentityIsSingleRow(
        authorID: Int64,
        isMainPost: Bool,
        includesThreadAuthorBadge: Bool = false,
        in app: XCUIApplication
    ) {
        let nameIdentifier = isMainPost ? "thread-main-user-name" : "thread-user-name-\(authorID)"
        let name = app.descendants(matching: .any)[nameIdentifier]
        let badge = app.descendants(matching: .any)["thread-user-level-badge-\(authorID)"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertTrue(badge.waitForExistence(timeout: 5))
        XCTAssertEqual(
            name.frame.midY,
            badge.frame.midY,
            accuracy: 2,
            "用户名和贴吧等级徽章必须保持在同一行"
        )
        if includesThreadAuthorBadge {
            let threadAuthorBadge = app.descendants(matching: .any)["thread-author-badge-\(authorID)"]
            XCTAssertTrue(threadAuthorBadge.waitForExistence(timeout: 5))
            XCTAssertEqual(
                name.frame.midY,
                threadAuthorBadge.frame.midY,
                accuracy: 2,
                "用户名和楼主徽章必须保持在同一行"
            )
        }
    }

    private func appearanceOption(_ title: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons
            .matching(identifier: "appearance-picker")
            .matching(NSPredicate(format: "label == %@", title))
            .firstMatch
    }

    private func threadRows(in app: XCUIApplication) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: "thread-row")
    }

    private func scrollToHittable(
        _ element: XCUIElement,
        in scrollView: XCUIElement,
        maxSwipes: Int = 8
    ) -> Bool {
        guard element.waitForExistence(timeout: 2), scrollView.exists else { return false }
        for _ in 0..<maxSwipes where element.isHittable == false {
            scrollView.swipeUp()
        }
        return element.isHittable
    }

    private func openGlobalSearch(in app: XCUIApplication) -> XCUIElement {
        XCTAssertFalse(app.searchFields.firstMatch.exists)
        let searchButton = app.buttons["home-search-button"]
        XCTAssertTrue(searchButton.waitForExistence(timeout: 8))
        XCTAssertTrue(searchButton.isHittable)
        searchButton.tap()

        XCTAssertTrue(app.navigationBars["搜索"].waitForExistence(timeout: 8))
        let searchField = app.textFields["search-input"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 8))
        XCTAssertTrue(searchField.isHittable)
        searchField.tap()
        return searchField
    }

    private func rootTab(_ label: String, in app: XCUIApplication) -> XCUIElement {
        let symbolIdentifier: String?
        switch label {
        case "首页": symbolIdentifier = "house"
        case "进吧": symbolIdentifier = "square.grid.2x2"
        case "我的": symbolIdentifier = "person.circle"
        default: symbolIdentifier = nil
        }
        if let symbolIdentifier {
            let symbolButton = app.buttons.matching(identifier: symbolIdentifier).firstMatch
            if symbolButton.exists { return symbolButton }
        }
        let labeledButton = app.buttons.matching(
            NSPredicate(format: "label == %@ OR identifier == %@", label, label)
        ).firstMatch
        if labeledButton.exists { return labeledButton }
        return app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@ OR identifier == %@", label, label))
            .firstMatch
    }

    private func openFirstThread(in app: XCUIApplication) {
        let firstOpenArea = app.descendants(matching: .any).matching(identifier: "thread-open-area").firstMatch
        XCTAssertTrue(firstOpenArea.waitForExistence(timeout: 45))
        firstOpenArea.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)).tap()
        if app.buttons["更多"].waitForExistence(timeout: 5) == false, firstOpenArea.exists {
            firstOpenArea.tap()
        }
        let didOpenDetail = app.buttons["更多"].waitForExistence(timeout: 8)
        XCTAssertTrue(didOpenDetail)
    }

    private func middleSwipeRight(in app: XCUIApplication) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.38))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.88, dy: 0.38))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    private func visibleThreadInlineImage(in app: XCUIApplication) -> XCUIElement? {
        let inlineImage = app.descendants(matching: .any)["thread-inline-image"]
        guard inlineImage.waitForExistence(timeout: 8) else { return nil }
        for _ in 0..<8 where inlineImage.isHittable == false {
            app.swipeUp()
        }
        return inlineImage.isHittable ? inlineImage : nil
    }

    private func waitForElement(named name: String, in app: XCUIApplication, maxSwipes: Int) -> Bool {
        let element = app.buttons[name]
        if element.waitForExistence(timeout: 5), element.isHittable {
            return true
        }

        for _ in 0..<maxSwipes {
            if element.exists && element.isHittable {
                return true
            }
            app.swipeUp()
        }
        return element.exists && element.isHittable
    }

    private func waitForStaticText(named name: String, in app: XCUIApplication, maxSwipes: Int) -> Bool {
        let element = app.staticTexts[name]
        if element.waitForExistence(timeout: 3) { return true }
        for _ in 0..<maxSwipes {
            if element.exists { return true }
            app.swipeUp()
        }
        return element.exists
    }

    private func waitForLabelContaining(_ text: String, in app: XCUIApplication, maxSwipes: Int) -> Bool {
        let element = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", text))
            .firstMatch
        if element.waitForExistence(timeout: 3) { return true }
        for _ in 0..<maxSwipes {
            if element.exists { return true }
            app.swipeUp()
        }
        return element.exists
    }

    private func buttonLabelContaining(
        _ text: String,
        in app: XCUIApplication,
        maxSwipes: Int
    ) -> XCUIElement? {
        let element = app.buttons
            .matching(NSPredicate(format: "label CONTAINS %@", text))
            .firstMatch
        if element.waitForExistence(timeout: 8), element.isHittable { return element }
        for _ in 0..<maxSwipes {
            if element.exists, element.isHittable { return element }
            app.swipeUp()
        }
        return element.exists && element.isHittable ? element : nil
    }

    private func elementWithIdentifier(
        _ identifier: String,
        in app: XCUIApplication,
        maxSwipes: Int
    ) -> XCUIElement? {
        let element = app.descendants(matching: .any)
            .matching(identifier: identifier)
            .firstMatch
        if element.waitForExistence(timeout: 5) { return element }
        for _ in 0..<maxSwipes {
            app.swipeUp()
            if element.waitForExistence(timeout: 1) { return element }
        }
        return element.exists ? element : nil
    }

    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
