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

        let firstForumThread = app.buttons["确定性主帖：回复筛选与媒体布局"]
        let secondForumThread = app.buttons["单张超宽图片布局"]
        let otherForumThread = app.buttons["超长昵称、深色模式和辅助功能字号"]
        XCTAssertTrue(firstForumThread.exists)
        XCTAssertTrue(secondForumThread.exists)
        XCTAssertTrue(otherForumThread.exists)

        let forumMenu = app.buttons["thread-forum-menu-1001"]
        XCTAssertTrue(forumMenu.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForHittable(forumMenu, expected: true, timeout: 5))
        forumMenu.tap()

        let blockForum = app.buttons["屏蔽测试吧"]
        XCTAssertTrue(blockForum.waitForExistence(timeout: 5))
        blockForum.tap()

        XCTAssertTrue(
            firstForumThread.waitForNonExistence(timeout: 5),
            "屏蔽贴吧后，当前贴吧的第一条帖子应立即消失"
        )
        XCTAssertTrue(
            secondForumThread.waitForNonExistence(timeout: 5),
            "屏蔽贴吧后，同一贴吧的其他帖子也应一起消失"
        )
        XCTAssertTrue(
            otherForumThread.waitForExistence(timeout: 5),
            "屏蔽一个贴吧不能误删其他贴吧的帖子"
        )
    }

    func testVoiceSummaryRequiresDetailAndPlaybackStatesRemainAccessible() {
        let app = launchApp(scenario: "voicePlayback")
        let successIdentifier = "voice-playback-\(String(repeating: "a", count: 32))"
        let failureIdentifier = "voice-playback-\(String(repeating: "b", count: 32))"

        let voiceThread = app.buttons["语音播放确定性夹具"]
        XCTAssertTrue(voiceThread.waitForExistence(timeout: 45))
        XCTAssertTrue(
            (voiceThread.value as? String)?.contains("[语音]") == true,
            "首页摘要应以可读文字表示语音"
        )
        XCTAssertFalse(
            app.descendants(matching: .any)[successIdentifier].exists,
            "首页摘要不应嵌入可播放控件"
        )

        openFirstThread(in: app)
        let success = app.descendants(matching: .any)[successIdentifier]
        XCTAssertTrue(success.waitForExistence(timeout: 8))
        XCTAssertGreaterThanOrEqual(success.frame.height, 44)
        XCTAssertGreaterThanOrEqual(success.frame.width, 44)
        XCTAssertEqual(success.label, "播放语音")
        XCTAssertTrue((success.value as? String)?.contains("时长") == true)

        success.tap()
        XCTAssertTrue(
            waitForAnyLabel(
                ["正在加载语音", "暂停语音", "重新播放语音"],
                on: success,
                timeout: 5
            )
        )

        let failure = app.descendants(matching: .any)[failureIdentifier]
        let detailScrollView = app.scrollViews["thread-detail-scroll-view"]
        for _ in 0..<8 where failure.exists == false || failure.isHittable == false {
            detailScrollView.swipeUp()
        }
        XCTAssertTrue(failure.exists && failure.isHittable)
        failure.tap()
        XCTAssertTrue(waitForAnyLabel(["正在加载语音", "重新加载语音"], on: failure, timeout: 3))
        XCTAssertTrue(waitForAnyLabel(["重新加载语音"], on: failure, timeout: 5))
        for _ in 0..<8 where success.exists == false {
            detailScrollView.swipeDown()
        }
        XCTAssertEqual(
            success.label,
            "播放语音",
            "切换语音后旧控件必须回到非活动状态"
        )

        for _ in 0..<8 where failure.exists == false || failure.isHittable == false {
            detailScrollView.swipeUp()
        }
        XCTAssertTrue(failure.exists && failure.isHittable)
        failure.tap()
        XCTAssertTrue(waitForAnyLabel(["正在加载语音", "重新加载语音"], on: failure, timeout: 3))
        XCTAssertTrue(waitForAnyLabel(["重新加载语音"], on: failure, timeout: 5))
    }

    func testVoicePlaybackControlFitsAtAccessibilityXXXL() {
        let app = launchApp(
            scenario: "voicePlayback",
            additionalArguments: [
                "-UIPreferredContentSizeCategoryName",
                "UICTContentSizeCategoryAccessibilityXXXL"
            ]
        )
        openFirstThread(in: app)

        let identifier = "voice-playback-\(String(repeating: "a", count: 32))"
        let control = app.descendants(matching: .any)[identifier]
        XCTAssertTrue(control.waitForExistence(timeout: 8))
        XCTAssertTrue(control.isHittable)
        XCTAssertGreaterThanOrEqual(control.frame.width, 44)
        XCTAssertGreaterThanOrEqual(control.frame.height, 44)
        XCTAssertTrue(
            app.frame.insetBy(dx: 8, dy: 0).contains(control.frame),
            "无障碍大字体下语音控件不能超出屏幕"
        )
        XCTAssertEqual(control.label, "播放语音")
    }

    func testHomeForumMenuBlocksThreadWhoseForumNameIsMissing() {
        let app = launchApp(scenario: "forumIDOnly")
        let idOnlyThread = app.buttons["仅有吧ID的首页帖子"]
        let sameForumThread = app.buttons["同吧ID且有吧名的首页帖子"]
        let unrelatedThread = app.buttons["超长昵称、深色模式和辅助功能字号"]
        XCTAssertTrue(idOnlyThread.waitForExistence(timeout: 45))
        XCTAssertTrue(sameForumThread.exists)
        XCTAssertTrue(unrelatedThread.exists)

        let menu = app.buttons["thread-forum-menu-1801"]
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        XCTAssertEqual(menu.label, "该吧的更多帖子操作")
        menu.tap()

        let blockForum = app.buttons["屏蔽该吧"]
        XCTAssertTrue(blockForum.waitForExistence(timeout: 5))
        blockForum.tap()

        XCTAssertTrue(idOnlyThread.waitForNonExistence(timeout: 5))
        XCTAssertTrue(
            sameForumThread.waitForNonExistence(timeout: 5),
            "ID-only 屏蔽规则必须同时过滤同 FID 且随后补全吧名的帖子"
        )
        XCTAssertTrue(unrelatedThread.waitForExistence(timeout: 5))
    }

    func testThreadAuthorOpensPublicUserProfile() {
        let app = launchApp()
        openFirstThread(in: app)

        let userButton = app.buttons["thread-main-user-button"]
        XCTAssertTrue(userButton.waitForExistence(timeout: 8))
        XCTAssertTrue(waitForHittable(userButton, expected: true, timeout: 5))
        userButton.tap()

        XCTAssertTrue(app.descendants(matching: .any)["user-profile-screen"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["合成内容作者"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.descendants(matching: .any)["user-profile-metadata"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.descendants(matching: .any)["user-profile-secondary-metadata"].exists)
        let avatar = app.descendants(matching: .any)["user-profile-avatar"]
        XCTAssertTrue(avatar.exists)
        XCTAssertEqual(avatar.frame.width, 56, accuracy: 1)
        XCTAssertEqual(avatar.frame.height, 56, accuracy: 1)
        let followButton = app.buttons["user-profile-follow-button"]
        XCTAssertTrue(followButton.exists)
        XCTAssertGreaterThanOrEqual(followButton.frame.width, 44)
        XCTAssertGreaterThanOrEqual(followButton.frame.height, 44)

        let agreeStat = app.descendants(matching: .any)["user-profile-agree-stat"]
        let followingStat = app.buttons["user-profile-following-stat"]
        let followersStat = app.buttons["user-profile-followers-stat"]
        XCTAssertTrue(agreeStat.exists)
        XCTAssertTrue(followingStat.exists)
        XCTAssertTrue(followersStat.exists)
        XCTAssertEqual(agreeStat.frame.midY, followingStat.frame.midY, accuracy: 1)
        XCTAssertEqual(followingStat.frame.midY, followersStat.frame.midY, accuracy: 1)
        XCTAssertTrue(app.buttons["user-profile-posts-tab"].exists)
        XCTAssertTrue(app.buttons["user-profile-thread-row-1001"].waitForExistence(timeout: 8))
        attachScreenshot(named: "fixture-public-user-profile-posts")

        let forumsTab = app.buttons["user-profile-forums-tab"]
        XCTAssertTrue(scrollToHittable(forumsTab, in: app.scrollViews["user-profile-screen"]))
        forumsTab.tap()
        XCTAssertTrue(app.buttons["user-profile-forum-row-0"].waitForExistence(timeout: 5))
        attachScreenshot(named: "fixture-public-user-profile")
    }

    func testPublicUserProfileHeaderFitsAtAccessibilityXXXL() {
        let app = launchApp(additionalArguments: [
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityXXXL"
        ])
        openFirstThread(in: app)

        let userButton = app.buttons["thread-main-user-button"]
        XCTAssertTrue(userButton.waitForExistence(timeout: 8))
        userButton.tap()

        XCTAssertTrue(app.descendants(matching: .any)["user-profile-screen"].waitForExistence(timeout: 8))
        let avatar = app.descendants(matching: .any)["user-profile-avatar"]
        let primaryMetadata = app.descendants(matching: .any)["user-profile-metadata"]
        let secondaryMetadata = app.descendants(matching: .any)["user-profile-secondary-metadata"]
        let followButton = app.buttons["user-profile-follow-button"]
        let agreeStat = app.descendants(matching: .any)["user-profile-agree-stat"]
        let followingStat = app.buttons["user-profile-following-stat"]
        let followersStat = app.buttons["user-profile-followers-stat"]

        for element in [
            avatar,
            primaryMetadata,
            secondaryMetadata,
            followButton,
            agreeStat,
            followingStat,
            followersStat
        ] {
            XCTAssertTrue(element.waitForExistence(timeout: 8))
            let horizontalBounds = app.frame.insetBy(dx: 8, dy: 0)
            XCTAssertGreaterThanOrEqual(
                element.frame.minX,
                horizontalBounds.minX,
                "\(element.identifier) 左侧不能超出屏幕：\(element.frame)"
            )
            XCTAssertLessThanOrEqual(
                element.frame.maxX,
                horizontalBounds.maxX,
                "\(element.identifier) 右侧不能超出屏幕：\(element.frame)"
            )
        }

        for element in [followButton, agreeStat, followingStat, followersStat] {
            XCTAssertGreaterThanOrEqual(element.frame.width, 44)
            XCTAssertGreaterThanOrEqual(element.frame.height, 44)
        }
        XCTAssertFalse(
            avatar.frame.intersects(followButton.frame),
            "头像和关注按钮不能重叠：\(avatar.frame)，\(followButton.frame)"
        )
        XCTAssertFalse(
            agreeStat.frame.intersects(followingStat.frame),
            "获赞和关注统计不能重叠：\(agreeStat.frame)，\(followingStat.frame)"
        )
        XCTAssertFalse(
            followingStat.frame.intersects(followersStat.frame),
            "关注和粉丝统计不能重叠：\(followingStat.frame)，\(followersStat.frame)"
        )
        attachScreenshot(named: "fixture-public-user-profile-axxxl")
    }

    func testLongNamePublicUserProfileFitsInDarkMode() {
        let app = launchApp(
            additionalArguments: ["-dev.infinityf4p.tiebapure.appearance", "dark"],
            resetAppearance: false
        )
        let userButton = app.buttons["feed-user-button-2"]
        XCTAssertTrue(userButton.waitForExistence(timeout: 8))
        userButton.tap()

        XCTAssertTrue(app.descendants(matching: .any)["user-profile-screen"].waitForExistence(timeout: 8))
        let name = app.descendants(matching: .any)["user-profile-name"]
        let followButton = app.buttons["user-profile-follow-button"]
        XCTAssertTrue(name.waitForExistence(timeout: 8))
        XCTAssertTrue(followButton.waitForExistence(timeout: 8))
        XCTAssertTrue(name.label.contains("特别长的合成用户名"))
        XCTAssertLessThanOrEqual(name.frame.maxX, followButton.frame.minX + 1)
        XCTAssertGreaterThanOrEqual(followButton.frame.width, 44)
        XCTAssertGreaterThanOrEqual(followButton.frame.height, 44)
        XCTAssertLessThanOrEqual(followButton.frame.maxX, app.frame.maxX - 8)
        attachScreenshot(named: "fixture-public-user-profile-dark-long-name")
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
        XCTAssertTrue(waitForHittable(profileButton, expected: true, timeout: 5))
        profileButton.tap()

        XCTAssertTrue(app.descendants(matching: .any)["user-profile-screen"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["模拟登录用户"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["user-profile-follow-button"].exists)
    }

    func testMessagesGuestPromptAndLoggedInFixtureJourney() {
        var app = launchApp()
        rootTab("我的", in: app).tap()

        XCTAssertTrue(app.staticTexts["未登录也可以浏览公开帖子"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["手机号验证码登录"].exists)
        XCTAssertFalse(app.buttons["me-messages-entry"].exists)

        app.terminate()
        app = launchApp(account: "loggedIn")
        rootTab("我的", in: app).tap()

        let messagesEntry = app.buttons["me-messages-entry"]
        XCTAssertTrue(messagesEntry.waitForExistence(timeout: 8))
        XCTAssertTrue(waitForHittable(messagesEntry, expected: true, timeout: 5))
        messagesEntry.tap()

        XCTAssertTrue(app.descendants(matching: .any)["messages-screen"].waitForExistence(timeout: 8))
        let replyRow = app.buttons["message-row-reply-1001-2002"]
        XCTAssertTrue(replyRow.waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["这是回复我的第一条合成消息，内容完全离线生成。"].exists)

        let atSegment = app.segmentedControls.buttons["@我的"]
        XCTAssertTrue(atSegment.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForHittable(atSegment, expected: true, timeout: 5))
        atSegment.tap()

        let atRow = app.buttons["message-row-at-1001-2002"]
        XCTAssertTrue(atRow.waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["@模拟登录用户 这是一条合成的提及消息。"].exists)
        XCTAssertTrue(waitForHittable(atRow, expected: true, timeout: 5))
        atRow.tap()

        XCTAssertTrue(app.buttons["更多"].waitForExistence(timeout: 8))
        XCTAssertTrue(waitForLabelContaining("已定位搜索命中回复", in: app, maxSwipes: 10))
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
        XCTAssertTrue(waitForHittable(entry, expected: true, timeout: 5))
        entry.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["followed-users-screen"]
                .waitForExistence(timeout: 8)
        )
        let followedUser = app.buttons["followed-user-row-1"]
        XCTAssertTrue(followedUser.waitForExistence(timeout: 8))
        XCTAssertTrue(waitForHittable(followedUser, expected: true, timeout: 5))
        XCTAssertTrue(app.staticTexts["另一个合成关注用户"].exists)

        followedUser.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["user-profile-screen"]
                .waitForExistence(timeout: 8)
        )
        XCTAssertTrue(app.staticTexts["合成内容作者"].waitForExistence(timeout: 8))

        let unfollowButton = app.buttons["user-profile-follow-button"]
        expectation(for: NSPredicate(format: "label == %@", "取消关注"), evaluatedWith: unfollowButton)
        waitForExpectations(timeout: 5)
        unfollowButton.tap()
        expectation(for: NSPredicate(format: "label == %@", "关注用户"), evaluatedWith: unfollowButton)
        waitForExpectations(timeout: 5)

        middleSwipeRight(in: app)
        XCTAssertTrue(
            app.descendants(matching: .any)["followed-users-screen"]
                .waitForExistence(timeout: 5),
            "关注用户主页右划只能返回关注用户列表"
        )
        XCTAssertTrue(
            followedUser.waitForNonExistence(timeout: 5),
            "在目标主页取消关注后，返回时应移除来源行但不能越级退出列表"
        )
        XCTAssertTrue(app.buttons["followed-user-row-2"].exists)
        middleSwipeRight(in: app)
        XCTAssertTrue(app.navigationBars["我的"].waitForExistence(timeout: 5))
    }

    func testOwnProfileFollowingCountTracksNestedUnfollow() {
        let app = launchApp(account: "loggedIn")
        rootTab("我的", in: app).tap()

        let profileButton = app.buttons["me-user-profile-button"]
        XCTAssertTrue(profileButton.waitForExistence(timeout: 8))
        profileButton.tap()

        let followingStat = app.buttons["user-profile-following-stat"]
        XCTAssertTrue(followingStat.waitForExistence(timeout: 8))
        XCTAssertEqual(followingStat.label, "关注74")
        followingStat.tap()

        let followedUser = app.buttons["followed-user-row-1"]
        XCTAssertTrue(followedUser.waitForExistence(timeout: 8))
        followedUser.tap()

        let unfollowButton = app.buttons["user-profile-follow-button"]
        expectation(for: NSPredicate(format: "label == %@", "取消关注"), evaluatedWith: unfollowButton)
        waitForExpectations(timeout: 5)
        unfollowButton.tap()
        expectation(for: NSPredicate(format: "label == %@", "关注用户"), evaluatedWith: unfollowButton)
        waitForExpectations(timeout: 5)

        middleSwipeRight(in: app)
        XCTAssertTrue(app.descendants(matching: .any)["followed-users-screen"].waitForExistence(timeout: 5))
        XCTAssertTrue(followedUser.waitForNonExistence(timeout: 5))

        middleSwipeRight(in: app)
        XCTAssertTrue(app.descendants(matching: .any)["user-profile-screen"].waitForExistence(timeout: 5))
        expectation(for: NSPredicate(format: "label == %@", "关注73"), evaluatedWith: followingStat)
        waitForExpectations(timeout: 5)
    }

    func testLoggedInUserCanUnfollowForumAndOpenFollowerList() {
        let app = launchApp(account: "loggedIn")
        rootTab("进吧", in: app).tap()

        let forumRow = app.buttons.matching(identifier: "forum-hub-forum-row").firstMatch
        XCTAssertTrue(forumRow.waitForExistence(timeout: 8))
        forumRow.tap()

        let followButton = app.buttons["forum-follow-button"]
        XCTAssertTrue(followButton.waitForExistence(timeout: 8))
        expectation(
            for: NSPredicate(format: "label == %@", "取消关注本吧"),
            evaluatedWith: followButton
        )
        waitForExpectations(timeout: 5)
        XCTAssertTrue(waitForHittable(followButton, expected: true, timeout: 5))
        followButton.tap()
        expectation(
            for: NSPredicate(format: "label == %@", "关注本吧"),
            evaluatedWith: followButton
        )
        waitForExpectations(timeout: 5)

        middleSwipeRight(in: app)
        rootTab("我的", in: app).tap()
        let forumListEntry = app.buttons["关注的吧"]
        XCTAssertTrue(forumListEntry.waitForExistence(timeout: 8))
        forumListEntry.tap()
        XCTAssertTrue(app.navigationBars["关注的吧"].waitForExistence(timeout: 8))
        XCTAssertFalse(
            app.buttons.matching(NSPredicate(format: "label == %@", "进入测试吧")).firstMatch.exists,
            "取消关注后，关注吧列表不能继续显示旧条目"
        )

        middleSwipeRight(in: app)
        rootTab("首页", in: app).tap()
        openFirstThread(in: app)
        let userButton = app.buttons["thread-main-user-button"]
        XCTAssertTrue(userButton.waitForExistence(timeout: 8))
        userButton.tap()

        let followersStat = app.buttons["user-profile-followers-stat"]
        XCTAssertTrue(followersStat.waitForExistence(timeout: 8))
        followersStat.tap()
        XCTAssertTrue(app.descendants(matching: .any)["followers-screen"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["follower-user-row-4"].waitForExistence(timeout: 8))

        middleSwipeRight(in: app)
        XCTAssertTrue(
            app.descendants(matching: .any)["user-profile-screen"].waitForExistence(timeout: 5),
            "粉丝列表右划只能返回当前用户主页"
        )
    }

    func testMeFollowRowsMatchBrowsingRowHeight() {
        let app = launchApp(account: "loggedIn")
        rootTab("我的", in: app).tap()

        let followedUsers = app.buttons["followed-users-entry"]
        let followedForums = app.buttons["关注的吧"]
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

    func testLoggedInUserCanAcknowledgeComposeRiskSaveDraftAndPublishThread() {
        let app = launchApp(
            account: "loggedIn",
            additionalArguments: ["UITEST_RESET_CONTENT_SUBMISSION"]
        )
        openFirstFollowedForum(in: app)

        let newThreadButton = app.buttons["forum-new-thread-button"]
        XCTAssertTrue(newThreadButton.waitForExistence(timeout: 8))
        XCTAssertTrue(waitForHittable(newThreadButton, expected: true, timeout: 5))

        newThreadButton.tap()
        let riskAlert = app.alerts["实验性发布功能"]
        XCTAssertTrue(riskAlert.waitForExistence(timeout: 8))
        XCTAssertTrue(riskAlert.staticTexts.element(matching: NSPredicate(
            format: "label CONTAINS %@",
            "应用不会自动重发"
        )).exists)
        riskAlert.buttons["取消"].tap()
        XCTAssertTrue(riskAlert.waitForNonExistence(timeout: 5))
        XCTAssertTrue(
            app.navigationBars["测试吧"].waitForExistence(timeout: 5),
            "取消风险提示后应回到吧页，且不能触发发布"
        )

        newThreadButton.tap()
        XCTAssertTrue(riskAlert.waitForExistence(timeout: 8))
        riskAlert.buttons["了解并继续"].tap()

        let title = "UI自动化草稿主题"
        let body = "这是一段确定性的夹具正文"
        let titleField = app.textFields["帖子标题"]
        let bodyEditor = app.textViews["正文内容"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 8))
        titleField.tap()
        titleField.typeText(title)
        let bodyWasInitiallyVisible = bodyEditor.waitForExistence(timeout: 8)
        if bodyWasInitiallyVisible == false {
            let composerScrollView = app.scrollViews.firstMatch
            if composerScrollView.exists {
                composerScrollView.swipeUp()
            }
        }
        XCTAssertTrue(
            bodyWasInitiallyVisible || bodyEditor.waitForExistence(timeout: 5),
            "新帖编辑器滚动后仍应显示正文输入区"
        )
        bodyEditor.tap()
        bodyEditor.typeText(body)

        let emoticonButton = app.buttons["表情"]
        XCTAssertTrue(waitForHittable(emoticonButton, expected: true, timeout: 10))
        emoticonButton.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 10))
        let insertEmoticon = app.buttons["content-composer-emoticon-image_emoticon1"]
        XCTAssertTrue(insertEmoticon.waitForExistence(timeout: 15))
        XCTAssertTrue(waitForHittable(insertEmoticon, expected: true, timeout: 10))
        insertEmoticon.tap()
        XCTAssertTrue(waitForValueContaining("#(呵呵)", on: bodyEditor, timeout: 5))

        let saveDraftButton = app.buttons["保存草稿"]
        XCTAssertTrue(waitForHittable(saveDraftButton, expected: true, timeout: 5))
        saveDraftButton.tap()
        XCTAssertTrue(app.staticTexts["草稿已保存"].waitForExistence(timeout: 8))

        let cancelComposer = app.navigationBars["发布新帖"].buttons["取消"]
        XCTAssertTrue(cancelComposer.waitForExistence(timeout: 5))
        cancelComposer.tap()
        XCTAssertTrue(app.navigationBars["测试吧"].waitForExistence(timeout: 5))

        newThreadButton.tap()
        XCTAssertFalse(
            riskAlert.waitForExistence(timeout: 1),
            "同一安装确认风险后不应重复提示"
        )
        XCTAssertTrue(titleField.waitForExistence(timeout: 8))
        XCTAssertTrue(bodyEditor.waitForExistence(timeout: 8))
        XCTAssertTrue(waitForValueContaining(title, on: titleField, timeout: 5))
        XCTAssertTrue(waitForValueContaining(body, on: bodyEditor, timeout: 5))
        XCTAssertTrue(waitForValueContaining("#(呵呵)", on: bodyEditor, timeout: 5))

        let sendButton = app.navigationBars["发布新帖"].buttons["发送"]
        XCTAssertTrue(waitForHittable(sendButton, expected: true, timeout: 5))
        sendButton.tap()
        XCTAssertTrue(
            app.navigationBars["发布新帖"].waitForNonExistence(timeout: 10),
            "夹具发送成功后应关闭编辑器"
        )
        XCTAssertTrue(
            app.navigationBars[title].waitForExistence(timeout: 10),
            "发布成功后应进入刚发布的新主题"
        )
        XCTAssertTrue(
            app.descendants(matching: .any).matching(
                NSPredicate(
                    format: "identifier == %@ AND (label CONTAINS %@ OR value CONTAINS %@)",
                    "thread-main-text",
                    body,
                    body
                )
            ).firstMatch.waitForExistence(timeout: 10),
            "刚发布主题的正文和作者必须来自本次提交，不能使用固定夹具内容"
        )
    }

    func testLoggedInUserCanReplyToFloorAndReturnsToUpdatedSubpostList() {
        let app = launchApp(
            scenario: "subpostReference",
            account: "loggedIn",
            additionalArguments: ["UITEST_RESET_CONTENT_SUBMISSION"]
        )
        openFirstThread(in: app)

        XCTAssertTrue(
            waitForElement(named: "thread-reply-button-2002", in: app, maxSwipes: 12)
        )
        app.buttons["thread-reply-button-2002"].tap()

        let riskAlert = app.alerts["实验性发布功能"]
        XCTAssertTrue(riskAlert.waitForExistence(timeout: 8))
        riskAlert.buttons["了解并继续"].tap()

        let body = "UI自动化楼层回复"
        let bodyEditor = app.textViews["正文内容"]
        XCTAssertTrue(bodyEditor.waitForExistence(timeout: 8))
        bodyEditor.tap()
        bodyEditor.typeText(body)

        let sendButton = app.buttons["发送"]
        XCTAssertTrue(waitForHittable(sendButton, expected: true, timeout: 5))
        sendButton.tap()

        XCTAssertTrue(
            bodyEditor.waitForNonExistence(timeout: 10),
            "发送成功后应关闭楼层回复编辑器"
        )
        XCTAssertTrue(
            app.navigationBars.matching(
                NSPredicate(format: "identifier BEGINSWITH %@", "2楼的回复")
            ).firstMatch.waitForExistence(timeout: 10),
            "发送成功后应回到当前帖子并打开对应楼中楼"
        )
        XCTAssertTrue(
            app.descendants(matching: .any).matching(
                NSPredicate(
                    format: "identifier == %@ AND (label CONTAINS %@ OR value CONTAINS %@)",
                    "thread-subpost-text",
                    body,
                    body
                )
            ).firstMatch.waitForExistence(timeout: 10),
            "新回复应在更新后的楼中楼中可见"
        )
    }

    func testReplySettingDefaultsOffEnablesRepliesAndPersistsAcrossRelaunch() {
        var app = launchApp(
            account: "loggedIn",
            additionalArguments: ["UITEST_RESET_CONTENT_SUBMISSION_RISK"]
        )
        rootTab("我的", in: app).tap()

        let settingsEntry = app.descendants(matching: .any)["app-settings-entry"]
        XCTAssertTrue(revealBySwipingUp(settingsEntry, in: app, maxSwipes: 8))
        settingsEntry.tap()
        XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout: 8))

        let repliesToggle = app.switches["settings-replies-enabled-toggle"]
        XCTAssertTrue(repliesToggle.waitForExistence(timeout: 5))
        XCTAssertEqual(repliesToggle.value as? String, "0", "回帖设置必须默认关闭")
        repliesToggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertTrue(waitForSwitch(repliesToggle, value: "1"))

        app.terminate()
        app = launchApp(
            account: "loggedIn",
            additionalArguments: ["UITEST_PRESERVE_CONTENT_SUBMISSION_SETTINGS"]
        )
        rootTab("我的", in: app).tap()
        let persistedSettingsEntry = app.descendants(matching: .any)["app-settings-entry"]
        XCTAssertTrue(revealBySwipingUp(persistedSettingsEntry, in: app, maxSwipes: 8))
        persistedSettingsEntry.tap()
        XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout: 8))

        let persistedToggle = app.switches["settings-replies-enabled-toggle"]
        XCTAssertTrue(persistedToggle.waitForExistence(timeout: 5))
        XCTAssertEqual(persistedToggle.value as? String, "1", "重启后应保留已开启的回帖设置")
    }

    func testDisabledPostingAndLikesHideWriteActionsButKeepEveryLikeCount() {
        var app = launchApp(scenario: "subpostReference", account: "loggedIn")
        rootTab("我的", in: app).tap()

        let settingsEntry = app.descendants(matching: .any)["app-settings-entry"]
        XCTAssertTrue(revealBySwipingUp(settingsEntry, in: app, maxSwipes: 8))
        settingsEntry.tap()
        XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout: 8))

        let newThreadsToggle = app.switches["settings-new-threads-enabled-toggle"]
        let likesToggle = app.switches["settings-likes-enabled-toggle"]
        XCTAssertTrue(newThreadsToggle.waitForExistence(timeout: 5))
        XCTAssertTrue(likesToggle.waitForExistence(timeout: 5))
        XCTAssertEqual(newThreadsToggle.value as? String, "1")
        XCTAssertEqual(likesToggle.value as? String, "1")
        newThreadsToggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        likesToggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertTrue(waitForSwitch(newThreadsToggle, value: "0"))
        XCTAssertTrue(waitForSwitch(likesToggle, value: "0"))

        app.terminate()
        app = launchApp(
            scenario: "subpostReference",
            account: "loggedIn",
            additionalArguments: ["UITEST_PRESERVE_CONTENT_SUBMISSION_SETTINGS"]
        )
        openFirstFollowedForum(in: app)
        XCTAssertFalse(
            app.buttons["forum-new-thread-button"].waitForExistence(timeout: 2),
            "关闭发帖后不应保留发布入口"
        )
        openFirstThread(in: app)

        assertLikeCountIsReadOnly(identifier: "thread-main-like-button", in: app)
        XCTAssertTrue(
            revealBySwipingUp(
                app.descendants(matching: .any)["thread-like-button-2002"],
                in: app,
                maxSwipes: 12
            )
        )
        assertLikeCountIsReadOnly(identifier: "thread-like-button-2002", in: app)

        XCTAssertTrue(waitForElement(named: "查看全部4条回复", in: app, maxSwipes: 8))
        app.buttons["查看全部4条回复"].tap()
        XCTAssertTrue(app.navigationBars["2楼的回复(4条)"].waitForExistence(timeout: 8))
        assertLikeCountIsReadOnly(identifier: "thread-subpost-parent-like-button", in: app)
        XCTAssertTrue(
            revealBySwipingUp(
                app.descendants(matching: .any)["thread-subpost-like-button-3051"],
                in: app,
                maxSwipes: 8
            )
        )
        assertLikeCountIsReadOnly(identifier: "thread-subpost-like-button-3051", in: app)
    }

    func testEnabledReplySettingShowsHittableThreadEntry() {
        let app = launchApp(
            account: "loggedIn",
            additionalArguments: ["UITEST_RESET_CONTENT_SUBMISSION"]
        )
        openFirstThread(in: app)

        let replyEntry = app.buttons["thread-compose-reply-button"]
        XCTAssertTrue(replyEntry.waitForExistence(timeout: 8))
        XCTAssertTrue(waitForHittable(replyEntry, expected: true, timeout: 5))
        replyEntry.tap()

        let riskAlert = app.alerts["实验性发布功能"]
        XCTAssertTrue(riskAlert.waitForExistence(timeout: 8))
        riskAlert.buttons["了解并继续"].tap()
        XCTAssertTrue(app.navigationBars["回复帖子"].waitForExistence(timeout: 8))
    }

    func testPlainTextTapOpensCorrectMainFloorAndSubpostComposer() {
        let app = launchApp(
            scenario: "subpostReference",
            account: "loggedIn",
            additionalArguments: ["UITEST_RESET_CONTENT_SUBMISSION"]
        )
        openFirstThread(in: app)

        let mainText = app.descendants(matching: .any)["thread-main-text"]
        XCTAssertTrue(mainText.waitForExistence(timeout: 8))
        mainText.coordinate(withNormalizedOffset: CGVector(dx: 0.12, dy: 0.18)).tap()

        let riskAlert = app.alerts["实验性发布功能"]
        XCTAssertTrue(riskAlert.waitForExistence(timeout: 8))
        riskAlert.buttons["了解并继续"].tap()
        assertReplyComposer(
            navigationTitle: "回复用户",
            prompt: "回复 合成内容作者",
            in: app
        )
        app.navigationBars["回复用户"].buttons["取消"].tap()

        let floorText = app.descendants(matching: .any).matching(identifier: "thread-reply-text")
            .matching(NSPredicate(
                format: "label CONTAINS %@ OR value CONTAINS %@",
                "确定性回复内容",
                "确定性回复内容"
            ))
            .firstMatch
        XCTAssertTrue(revealBySwipingUp(floorText, in: app, maxSwipes: 12))
        floorText.coordinate(withNormalizedOffset: CGVector(dx: 0.18, dy: 0.35)).tap()
        assertReplyComposer(
            navigationTitle: "回复用户",
            prompt: "回复 很长很长的合成回复用户名用于布局测试",
            in: app
        )
        app.navigationBars["回复用户"].buttons["取消"].tap()

        XCTAssertTrue(waitForElement(named: "查看全部4条回复", in: app, maxSwipes: 12))
        app.buttons["查看全部4条回复"].tap()
        XCTAssertTrue(app.navigationBars["2楼的回复(4条)"].waitForExistence(timeout: 8))

        let subpostText = app.descendants(matching: .any)
            .matching(identifier: "thread-subpost-text")
            .matching(NSPredicate(
                format: "label CONTAINS %@ OR value CONTAINS %@",
                "楼中楼参考布局回复2",
                "楼中楼参考布局回复2"
            ))
            .firstMatch
        XCTAssertTrue(revealBySwipingUp(subpostText, in: app, maxSwipes: 8))
        subpostText.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.5)).tap()
        assertReplyComposer(
            navigationTitle: "回复用户",
            prompt: "回复 合成内容作者",
            in: app
        )
        app.navigationBars["回复用户"].buttons["取消"].tap()
        XCTAssertTrue(app.navigationBars["2楼的回复(4条)"].waitForExistence(timeout: 5))
    }

    func testLiveAccountContentLifecycle() throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["TIEBAPURE_RUN_LIVE_ACCOUNT_UI"] == "1" else {
            throw XCTSkip("真实账号冒烟仅在显式启用时运行。")
        }

        let mode = environment["TIEBAPURE_LIVE_ACCOUNT_MODE"] ?? "read"
        let forumName = environment["TIEBAPURE_LIVE_FORUM"]
            ?? "洗个头脱了四五百根怎么了"
        let token = environment["TIEBAPURE_LIVE_TEST_TOKEN"]
            ?? String(UUID().uuidString.prefix(8))
        let title = environment["TIEBAPURE_LIVE_THREAD_TITLE"]
            ?? "TiebaPure 测试 \(token)"
        let threadBody = environment["TIEBAPURE_LIVE_THREAD_BODY"]
            ?? "TiebaPure 真实账号低频测试，请忽略。标记：\(token)"

        let app = XCUIApplication()
        app.launch()

        let meTab = rootTab("我的", in: app)
        XCTAssertTrue(meTab.waitForExistence(timeout: 20))
        meTab.tap()
        XCTAssertTrue(app.buttons["me-user-profile-button"].waitForExistence(timeout: 10))

        if mode == "cleanup" {
            openLiveTestThreadFromHistory(title: title, in: app)
            deleteCurrentLiveTestThread(in: app)
            return
        }

        if mode == "write" || mode == "resume" || mode == "resumeSubpost" {
            let settingsEntry = app.descendants(matching: .any)["app-settings-entry"]
            XCTAssertTrue(settingsEntry.waitForExistence(timeout: 10))
            settingsEntry.tap()

            let repliesToggle = app.switches["settings-replies-enabled-toggle"]
            XCTAssertTrue(repliesToggle.waitForExistence(timeout: 10))
            if (repliesToggle.value as? String) != "1" {
                repliesToggle.coordinate(
                    withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)
                ).tap()
            }
            let repliesEnabled = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "value == %@", "1"),
                object: repliesToggle
            )
            XCTAssertEqual(XCTWaiter.wait(for: [repliesEnabled], timeout: 5), .completed)

            let settingsBackButton = app.navigationBars["设置"].buttons.firstMatch
            XCTAssertTrue(settingsBackButton.waitForExistence(timeout: 5))
            settingsBackButton.tap()
        }

        let bodyEditor = app.textViews["正文内容"]
        let submissionError = app.descendants(matching: .any)[
            "content-composer-submission-error"
        ]
        var forumNavigationBar: XCUIElement?

        if mode == "resume" || mode == "resumeSubpost" {
            openLiveTestThreadFromHistory(title: title, in: app)
        } else {
            let followedForums = app.buttons["关注的吧"]
            XCTAssertTrue(followedForums.waitForExistence(timeout: 10))
            followedForums.tap()

            let targetForum = app.buttons.matching(
                NSPredicate(format: "label CONTAINS %@", forumName)
            ).firstMatch
            XCTAssertTrue(targetForum.waitForExistence(timeout: 20), "未找到真实账号测试吧：\(forumName)")
            targetForum.tap()

            let resolvedForumNavigationBar = app.navigationBars.matching(
                NSPredicate(format: "identifier CONTAINS %@", forumName)
            ).firstMatch
            XCTAssertTrue(resolvedForumNavigationBar.waitForExistence(timeout: 15))
            forumNavigationBar = resolvedForumNavigationBar
            let newThreadButton = app.buttons["forum-new-thread-button"]
            XCTAssertTrue(newThreadButton.waitForExistence(timeout: 10))

            guard mode == "write" else { return }

            newThreadButton.tap()
            let riskAlert = app.alerts["实验性发布功能"]
            if riskAlert.waitForExistence(timeout: 2) {
                riskAlert.buttons["了解并继续"].tap()
            }

            let titleField = app.textFields["帖子标题"]
            XCTAssertTrue(titleField.waitForExistence(timeout: 10))
            XCTAssertTrue(bodyEditor.waitForExistence(timeout: 10))
            titleField.tap()
            titleField.typeText(title)
            bodyEditor.tap()
            bodyEditor.typeText(threadBody)

            let sendThread = app.navigationBars["发布新帖"].buttons["发送"]
            XCTAssertTrue(waitForHittable(sendThread, expected: true, timeout: 5))
            sendThread.tap()
            let threadComposer = app.navigationBars["发布新帖"]
            let submissionDeadline = Date().addingTimeInterval(30)
            while threadComposer.exists, submissionError.exists == false, Date() < submissionDeadline {
                RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            }
            XCTAssertFalse(
                submissionError.exists,
                "真实发帖被服务端明确拒绝：\(submissionError.label)"
            )
            XCTAssertFalse(threadComposer.exists, "真实发帖请求未完成")
            XCTAssertTrue(app.descendants(matching: .any)["thread-main-text"].waitForExistence(timeout: 30))
        }

        if mode != "resumeSubpost" {
            let threadReply = environment["TIEBAPURE_LIVE_THREAD_REPLY"]
                ?? "普通回帖测试 \(token)"
            let threadReplyButton = app.buttons["thread-compose-reply-button"]
            XCTAssertTrue(threadReplyButton.waitForExistence(timeout: 10))
            threadReplyButton.tap()
            XCTAssertTrue(bodyEditor.waitForExistence(timeout: 10))
            bodyEditor.tap()
            bodyEditor.typeText(threadReply)
            let sendReply = app.navigationBars["回复帖子"].buttons["发送"]
            XCTAssertTrue(waitForHittable(sendReply, expected: true, timeout: 5))
            sendReply.tap()
            waitForLiveSubmissionToFinish(
                editor: bodyEditor,
                error: submissionError,
                timeout: 30
            )
            XCTAssertFalse(
                submissionError.exists,
                "真实普通回帖被服务端明确拒绝：\(submissionError.label)"
            )
            XCTAssertFalse(bodyEditor.exists, "普通回帖请求未完成")
        }

        let floorReplyButton = app.buttons.matching(
            NSPredicate(format: "label == %@", "回复第2楼")
        ).firstMatch
        let threadScrollView = app.scrollViews["thread-detail-scroll-view"]
        for _ in 0..<12 where floorReplyButton.exists == false || floorReplyButton.isHittable == false {
            threadScrollView.swipeUp()
        }
        XCTAssertTrue(floorReplyButton.exists && floorReplyButton.isHittable)
        floorReplyButton.tap()
        XCTAssertTrue(bodyEditor.waitForExistence(timeout: 10))
        bodyEditor.tap()
        let floorReply = environment["TIEBAPURE_LIVE_FLOOR_REPLY"]
            ?? "楼层回复测试 \(token)"
        bodyEditor.typeText(floorReply)
        let sendFloorReply = app.buttons["发送"]
        XCTAssertTrue(waitForHittable(sendFloorReply, expected: true, timeout: 5))
        sendFloorReply.tap()
        waitForLiveSubmissionToFinish(
            editor: bodyEditor,
            error: submissionError,
            timeout: 30
        )
        XCTAssertFalse(
            submissionError.exists,
            "真实楼层回复被服务端明确拒绝：\(submissionError.label)"
        )
        XCTAssertFalse(bodyEditor.exists, "楼层回复请求未完成")

        let subpostNavigationBar = app.navigationBars.matching(
            NSPredicate(format: "identifier CONTAINS %@", "楼的回复")
        ).firstMatch
        XCTAssertTrue(subpostNavigationBar.waitForExistence(timeout: 30))
        let subpostReplyButton = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "subpost-reply-button-")
        ).firstMatch
        XCTAssertTrue(subpostReplyButton.waitForExistence(timeout: 20))
        subpostReplyButton.tap()
        XCTAssertTrue(bodyEditor.waitForExistence(timeout: 10))
        bodyEditor.tap()
        let subpostReply = environment["TIEBAPURE_LIVE_SUBPOST_REPLY"]
            ?? "楼中楼回复测试 \(token)"
        bodyEditor.typeText(subpostReply)
        let sendSubpostReply = app.buttons["发送"]
        XCTAssertTrue(waitForHittable(sendSubpostReply, expected: true, timeout: 5))
        sendSubpostReply.tap()
        waitForLiveSubmissionToFinish(
            editor: bodyEditor,
            error: submissionError,
            timeout: 30
        )
        XCTAssertFalse(
            submissionError.exists,
            "真实楼中楼回复被服务端明确拒绝：\(submissionError.label)"
        )
        XCTAssertFalse(bodyEditor.exists, "楼中楼回复请求未完成")

        let closeSubposts = subpostNavigationBar.buttons["完成"]
        XCTAssertTrue(closeSubposts.waitForExistence(timeout: 10))
        closeSubposts.tap()
        XCTAssertTrue(app.descendants(matching: .any)["thread-main-text"].waitForExistence(timeout: 10))

        deleteCurrentLiveTestThread(in: app, forumNavigationBar: forumNavigationBar)
    }

    private func waitForLiveSubmissionToFinish(
        editor: XCUIElement,
        error: XCUIElement,
        timeout: TimeInterval
    ) {
        let deadline = Date().addingTimeInterval(timeout)
        while editor.exists, error.exists == false, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
    }

    private func openLiveTestThreadFromHistory(title: String, in app: XCUIApplication) {
        let historyEntry = app.buttons["browsing-history-entry"]
        XCTAssertTrue(
            waitForElement(named: "browsing-history-entry", in: app, maxSwipes: 4),
            "未找到浏览历史入口"
        )
        historyEntry.tap()
        XCTAssertTrue(app.navigationBars["浏览历史"].waitForExistence(timeout: 10))

        let targetThread = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", title)
        ).firstMatch
        XCTAssertTrue(
            targetThread.waitForExistence(timeout: 10),
            "浏览历史中没有待处理的测试帖：\(title)"
        )
        targetThread.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["thread-main-text"]
                .waitForExistence(timeout: 20)
        )
    }

    private func deleteCurrentLiveTestThread(
        in app: XCUIApplication,
        forumNavigationBar: XCUIElement? = nil
    ) {
        let more = app.buttons["更多"]
        XCTAssertTrue(more.waitForExistence(timeout: 10))
        more.tap()
        let delete = app.buttons["thread-delete-own-thread"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        delete.tap()
        let confirmDelete = app.buttons["删除帖子"]
        XCTAssertTrue(confirmDelete.waitForExistence(timeout: 5))
        confirmDelete.tap()
        if let forumNavigationBar {
            XCTAssertTrue(
                forumNavigationBar.waitForExistence(timeout: 30),
                "删除测试帖后应返回测试吧"
            )
        } else {
            XCTAssertTrue(
                app.navigationBars["浏览历史"].waitForExistence(timeout: 30),
                "从浏览历史删除测试帖后应返回浏览历史"
            )
        }
    }

    func testComposerBlocksEditingWhenDraftReadFailsUntilRetrySucceeds() {
        let app = launchApp(
            account: "loggedIn",
            additionalArguments: [
                "UITEST_RESET_CONTENT_SUBMISSION",
                "UITEST_FAIL_CONTENT_DRAFT_LOAD_ONCE"
            ]
        )
        openFirstFollowedForum(in: app)

        let newThreadButton = app.buttons["forum-new-thread-button"]
        XCTAssertTrue(newThreadButton.waitForExistence(timeout: 8))
        newThreadButton.tap()

        let draftLoadError = app.descendants(matching: .any)[
            "content-composer-draft-load-error"
        ]
        XCTAssertTrue(draftLoadError.waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["无法恢复草稿"].exists)
        XCTAssertTrue(app.staticTexts["本机草稿读取失败。为避免覆盖已有内容，编辑器已暂停打开。"].exists)
        XCTAssertFalse(
            app.textFields["帖子标题"].exists,
            "读取草稿失败时不能展示可能覆盖旧草稿的编辑器"
        )
        XCTAssertFalse(app.alerts["实验性发布功能"].exists)

        let retryButton = app.buttons["重试"]
        XCTAssertTrue(retryButton.waitForExistence(timeout: 5))
        retryButton.tap()

        let riskAlert = app.alerts["实验性发布功能"]
        XCTAssertTrue(riskAlert.waitForExistence(timeout: 8))
        riskAlert.buttons["了解并继续"].tap()
        XCTAssertTrue(app.textFields["帖子标题"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.textViews["正文内容"].waitForExistence(timeout: 8))

        app.navigationBars["发布新帖"].buttons["取消"].tap()
        XCTAssertTrue(app.navigationBars["测试吧"].waitForExistence(timeout: 5))
    }

    func testComposerPromptsForUnsavedChangesFromCancelAndSwipeDismissal() {
        let app = launchApp(
            account: "loggedIn",
            additionalArguments: ["UITEST_RESET_CONTENT_SUBMISSION"]
        )
        openFirstFollowedForum(in: app)

        let newThreadButton = app.buttons["forum-new-thread-button"]
        XCTAssertTrue(newThreadButton.waitForExistence(timeout: 8))
        newThreadButton.tap()
        let riskAlert = app.alerts["实验性发布功能"]
        XCTAssertTrue(riskAlert.waitForExistence(timeout: 8))
        riskAlert.buttons["了解并继续"].tap()

        let savedTitle = "未保存退出确认主题"
        let savedBody = "下滑退出前应询问是否保存"
        let titleField = app.textFields["帖子标题"]
        let bodyEditor = app.textViews["正文内容"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 8))
        titleField.tap()
        titleField.typeText(savedTitle)
        bodyEditor.tap()
        bodyEditor.typeText(savedBody)

        let cancelButton = app.navigationBars["发布新帖"].buttons["取消"]
        cancelButton.tap()
        XCTAssertTrue(app.buttons["继续编辑"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["保存草稿并关闭"].exists)
        XCTAssertTrue(app.buttons["放弃更改"].exists)
        app.buttons["继续编辑"].tap()
        XCTAssertTrue(app.navigationBars["发布新帖"].waitForExistence(timeout: 5))

        let dragStart = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08))
        let dragEnd = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.72))
        dragStart.press(forDuration: 0.1, thenDragTo: dragEnd)
        XCTAssertTrue(
            app.buttons["保存草稿并关闭"].waitForExistence(timeout: 5),
            "有未保存内容时，下滑关闭也必须弹出保存选择"
        )
        app.buttons["保存草稿并关闭"].tap()
        XCTAssertTrue(app.navigationBars["测试吧"].waitForExistence(timeout: 8))

        newThreadButton.tap()
        XCTAssertFalse(riskAlert.waitForExistence(timeout: 1))
        XCTAssertTrue(titleField.waitForExistence(timeout: 8))
        XCTAssertTrue(waitForValueContaining(savedTitle, on: titleField, timeout: 5))
        XCTAssertTrue(waitForValueContaining(savedBody, on: bodyEditor, timeout: 5))

        titleField.tap()
        titleField.typeText("临时修改")
        cancelButton.tap()
        XCTAssertTrue(app.buttons["放弃更改"].waitForExistence(timeout: 5))
        app.buttons["放弃更改"].tap()
        XCTAssertTrue(app.navigationBars["测试吧"].waitForExistence(timeout: 8))

        newThreadButton.tap()
        XCTAssertTrue(titleField.waitForExistence(timeout: 8))
        XCTAssertEqual(
            titleField.value as? String,
            savedTitle,
            "放弃本次修改后，之前明确保存的草稿必须保持不变"
        )
        cancelButton.tap()
        XCTAssertTrue(app.navigationBars["测试吧"].waitForExistence(timeout: 5))
    }

    func testLargeLikeCountsStayOnOneLineAtTheTrailingEdge() {
        let app = launchApp(scenario: "largeLikeCount", account: "loggedIn")
        openFirstThread(in: app)

        let mainLike = app.buttons["thread-main-like-button"]
        XCTAssertTrue(mainLike.waitForExistence(timeout: 8))
        assertTrailingLikeControl(
            mainLike,
            fullCount: 9_876,
            authorID: 1,
            isMainPost: true,
            in: app
        )

        XCTAssertTrue(waitForElement(named: "thread-like-button-2002", in: app, maxSwipes: 12))
        let replyLike = app.buttons["thread-like-button-2002"]
        assertTrailingLikeControl(
            replyLike,
            fullCount: 123_456,
            authorID: 2,
            isMainPost: false,
            in: app
        )

        XCTAssertTrue(waitForElement(named: "查看全部4条回复", in: app, maxSwipes: 8))
        app.buttons["查看全部4条回复"].tap()
        XCTAssertTrue(app.navigationBars["2楼的回复(4条)"].waitForExistence(timeout: 8))

        let subpostLike = app.buttons["thread-subpost-like-button-3061"]
        XCTAssertTrue(subpostLike.waitForExistence(timeout: 8))
        assertTrailingLikeControl(
            subpostLike,
            fullCount: 98_765,
            authorID: 4,
            isMainPost: false,
            in: app
        )
        attachScreenshot(named: "fixture-trailing-single-line-large-like-counts")
    }

    func testPullingHomeFeedRefreshesContentAndPreservesExistingRows() {
        let app = launchApp(scenario: "refreshUpdate")

        let firstRow = threadRows(in: app).firstMatch
        XCTAssertTrue(firstRow.waitForExistence(timeout: 45))
        let originalThread = app.buttons["确定性主帖：回复筛选与媒体布局"]
        XCTAssertTrue(originalThread.waitForExistence(timeout: 5))
        XCTAssertFalse(app.searchFields.firstMatch.exists)
        XCTAssertTrue(
            waitForHittable(app.buttons["home-search-button"], expected: true, timeout: 5)
        )

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

        let mainText = app.descendants(matching: .any)["thread-main-text"]
        XCTAssertTrue(mainText.waitForExistence(timeout: 8))
        XCTAssertFalse(
            mainText.label.contains("帖子下拉刷新已更新") ||
                (mainText.value as? String)?.contains("帖子下拉刷新已更新") == true
        )

        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.20))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.34))
        start.press(forDuration: 0.1, thenDragTo: end)

        let refreshed = NSPredicate(
            format: "label CONTAINS %@ OR value CONTAINS %@",
            "帖子下拉刷新已更新",
            "帖子下拉刷新已更新"
        )
        expectation(for: refreshed, evaluatedWith: mainText)
        waitForExpectations(timeout: 8)
    }

    func testHomeAndThreadRefreshKeepTopIndicatorsVisible() {
        let app = launchApp(
            scenario: "refreshUpdate",
            additionalArguments: ["UITEST_EXTENDED_REFRESH_ANIMATION"]
        )
        XCTAssertTrue(threadRows(in: app).firstMatch.waitForExistence(timeout: 45))
        let homeScrollView = app.scrollViews["home-feed-scroll-view"]
        XCTAssertTrue(homeScrollView.waitForExistence(timeout: 5))

        let homeStart = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.20))
        let homeEnd = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.34))
        homeStart.press(forDuration: 0.1, thenDragTo: homeEnd)
        let homeRefresh = app.descendants(matching: .any)["home-refresh-animation"]
        XCTAssertTrue(
            homeRefresh.waitForExistence(timeout: 2)
        )
        assertRefreshRevealMatchesGroupedBackground(
            in: app,
            scrollContainer: homeScrollView,
            refreshIndicator: homeRefresh,
            context: "首页刷新保持态"
        )
        attachScreenshot(named: "fixture-home-refresh-indicator")

        openFirstThread(in: app)
        let threadScrollView = app.scrollViews["thread-detail-scroll-view"]
        XCTAssertTrue(threadScrollView.waitForExistence(timeout: 5))
        let threadStart = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.20))
        let threadEnd = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.34))
        threadStart.press(forDuration: 0.1, thenDragTo: threadEnd)
        let threadRefresh = app.descendants(matching: .any)["thread-refresh-animation"]
        XCTAssertTrue(
            threadRefresh.waitForExistence(timeout: 2)
        )
        assertRefreshRevealMatchesGroupedBackground(
            in: app,
            scrollContainer: threadScrollView,
            refreshIndicator: threadRefresh,
            context: "帖子页刷新保持态"
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

    func testDiagonalRightSwipeAtHomeTopDoesNotTriggerRefresh() {
        let app = launchApp(
            scenario: "refreshUpdate",
            additionalArguments: ["UITEST_EXTENDED_REFRESH_ANIMATION"]
        )
        let originalThread = app.buttons["确定性主帖：回复筛选与媒体布局"]
        XCTAssertTrue(originalThread.waitForExistence(timeout: 45))

        let refreshAnimation = app.descendants(matching: .any)["home-refresh-animation"]
        let diagonalStart = app.coordinate(withNormalizedOffset: CGVector(dx: 0.18, dy: 0.20))
        let diagonalEnd = app.coordinate(withNormalizedOffset: CGVector(dx: 0.78, dy: 0.32))
        diagonalStart.press(forDuration: 0.1, thenDragTo: diagonalEnd)

        XCTAssertFalse(
            refreshAnimation.waitForExistence(timeout: 1.5),
            "以横向为主的右划即使带有下移分量，也不得触发刷新"
        )
        XCTAssertFalse(app.buttons["下拉刷新已更新"].exists)

        let verticalStart = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.20))
        let verticalEnd = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.34))
        verticalStart.press(forDuration: 0.1, thenDragTo: verticalEnd)
        XCTAssertTrue(
            app.buttons["下拉刷新已更新"].waitForExistence(timeout: 8),
            "取消横向手势后，下一次正常纵向下拉仍应可刷新"
        )
    }

    func testPullingEmptyForumStateLoadsContent() {
        let app = launchApp(
            scenario: "emptyThenSuccess",
            additionalArguments: ["UITEST_EXTENDED_REFRESH_ANIMATION"]
        )

        rootTab("进吧", in: app).tap()
        let forumField = app.textFields["输入吧名"]
        XCTAssertTrue(forumField.waitForExistence(timeout: 10))
        forumField.tap()
        forumField.typeText("测试")
        let enterForum = app.buttons["进入贴吧"]
        XCTAssertTrue(waitForHittable(enterForum, expected: true, timeout: 5))
        enterForum.tap()

        XCTAssertTrue(app.navigationBars["测试吧"].waitForExistence(timeout: 10))
        let emptyTitle = app.staticTexts["暂无帖子"]
        XCTAssertTrue(emptyTitle.waitForExistence(timeout: 10))
        let stateScrollView = app.scrollViews["forum-threads-scroll-view"]
        XCTAssertTrue(stateScrollView.exists)

        let shortPullDelta = min(96 / max(stateScrollView.frame.height, 1), 0.22)
        let start = stateScrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.20))
        let end = stateScrollView.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.20 + shortPullDelta)
        )
        start.press(forDuration: 0.2, thenDragTo: end)

        let firstRefreshAnimation = app.descendants(matching: .any)["forum-refresh-animation"]
        XCTAssertTrue(
            firstRefreshAnimation.waitForExistence(timeout: 2),
            "空态松手后应保留统一的顶部刷新符号"
        )
        XCTAssertTrue(threadRows(in: app).firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(
            firstRefreshAnimation.exists,
            "空态切换为帖子列表时不得提前销毁刷新符号和顶部占位"
        )
        XCTAssertTrue(
            firstRefreshAnimation.waitForNonExistence(timeout: 8)
        )

        let navigationBar = app.navigationBars["测试吧"]
        XCTAssertTrue(navigationBar.exists)
        let categoryPicker = app.otherElements["forum-category-picker"]
        XCTAssertTrue(categoryPicker.waitForExistence(timeout: 5))
        let forumScrollView = app.scrollViews["forum-threads-scroll-view"]
        XCTAssertTrue(forumScrollView.waitForExistence(timeout: 5))
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        for cycle in 1...4 {
            // On iOS 26 the ScrollView accessibility frame includes the
            // navigation-bar region even though its visible content starts
            // below it. Begin inside the first post rather than that region.
            let pullStart = forumScrollView.coordinate(
                withNormalizedOffset: CGVector(dx: 0.5, dy: 0.20)
            )
            let pullEnd = forumScrollView.coordinate(
                withNormalizedOffset: CGVector(dx: 0.5, dy: 0.20 + shortPullDelta)
            )
            pullStart.press(forDuration: 0.1, thenDragTo: pullEnd)

            let refreshAnimation = app.descendants(matching: .any)["forum-refresh-animation"]
            XCTAssertTrue(
                refreshAnimation.waitForExistence(timeout: 2),
                "第\(cycle)次刷新没有显示统一的顶部动画"
            )
            let refreshedTitle = app.buttons["贴吧连续刷新第\(cycle)轮"]
            XCTAssertTrue(
                refreshedTitle.waitForExistence(timeout: 8),
                "第\(cycle)次连续刷新没有完成"
            )
            XCTAssertTrue(
                refreshAnimation.waitForNonExistence(timeout: 8),
                "第\(cycle)次刷新动画没有在任务完成后收起"
            )
            let firstRow = threadRows(in: app).firstMatch
            guard let stableFrame = waitForStableFrame(of: firstRow) else {
                return XCTFail("第\(cycle)次刷新后首行布局没有稳定")
            }
            XCTAssertGreaterThanOrEqual(
                stableFrame.minY - categoryPicker.frame.maxY,
                -1,
                "第\(cycle)次刷新后首行不得与分类栏重叠"
            )
            XCTAssertLessThanOrEqual(
                stableFrame.minY - categoryPicker.frame.maxY,
                24,
                "第\(cycle)次刷新后顶部不得残留额外空白"
            )
        }
    }

    func testHomeTabReselectAfterScrollingRefreshesContent() {
        let app = launchApp(
            scenario: "refreshUpdate",
            additionalArguments: ["UITEST_RESELECT_REFRESH_HOLD"]
        )

        let firstRow = threadRows(in: app).firstMatch
        XCTAssertTrue(firstRow.waitForExistence(timeout: 45))
        guard waitForStableFrame(of: firstRow) != nil else {
            return XCTFail("首页首行初始布局没有稳定")
        }
        let homeTab = rootTab("首页", in: app)
        XCTAssertTrue(waitForHittable(homeTab, expected: true, timeout: 5))
        let appFrame = app.frame
        let homeTabFrame = homeTab.frame
        let homeTabCoordinate = app.coordinate(withNormalizedOffset: CGVector(
            dx: homeTabFrame.midX / appFrame.width,
            dy: homeTabFrame.midY / appFrame.height
        ))

        app.swipeUp()
        app.swipeUp()
        homeTabCoordinate.tap()

        let refreshAnimation = app.descendants(matching: .any)["home-refresh-animation"]
        XCTAssertTrue(
            refreshAnimation.waitForExistence(timeout: 2),
            "重复点击首页后应通过统一刷新状态机显示顶部动画"
        )
        XCTAssertTrue(app.buttons["下拉刷新已更新"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["确定性主帖：回复筛选与媒体布局"].exists)

        let refreshedFirstRow = threadRows(in: app).firstMatch
        RunLoop.current.run(until: Date().addingTimeInterval(0.35))
        let heldFrame = refreshedFirstRow.frame
        let refreshFrame = refreshAnimation.frame
        XCTAssertFalse(heldFrame.isEmpty, "首页刷新期间首行必须保持可见")
        XCTAssertGreaterThanOrEqual(
            heldFrame.minY,
            refreshFrame.maxY - 1,
            "刷新中的内容不能覆盖顶部加载符号"
        )

        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        XCTAssertTrue(refreshAnimation.exists, "扩展测试窗口内刷新符号不应提前消失")
        let laterHeldFrame = refreshedFirstRow.frame
        XCTAssertGreaterThanOrEqual(
            laterHeldFrame.minY,
            refreshFrame.maxY - 1,
            "刷新保持期间内容始终不能覆盖顶部加载符号"
        )

        XCTAssertTrue(
            refreshAnimation.waitForNonExistence(timeout: 12),
            "刷新完成后顶部加载动画应收起"
        )
        guard let restoredFrame = waitForStableFrame(of: refreshedFirstRow) else {
            return XCTFail("首页刷新完成后的首行布局没有稳定")
        }
        XCTAssertGreaterThanOrEqual(
            laterHeldFrame.minY - restoredFrame.minY,
            34,
            "刷新成功后，同一首行应随保留的顶部空间一起向上复位"
        )
        XCTAssertLessThanOrEqual(
            laterHeldFrame.minY - restoredFrame.minY,
            48,
            "刷新结束复位不应产生超过设计占位的额外跳动"
        )
    }

    func testHomeTabReselectInterruptsPaginationAndRefreshesImmediately() {
        let app = launchApp(
            scenario: "slowPaginationRefresh",
            additionalArguments: ["UITEST_EXTENDED_REFRESH_ANIMATION"]
        )
        let scrollView = app.scrollViews["home-feed-scroll-view"]
        XCTAssertTrue(scrollView.waitForExistence(timeout: 10))
        XCTAssertTrue(threadRows(in: app).firstMatch.waitForExistence(timeout: 45))

        let loadingMore = app.descendants(matching: .any)["正在加载更多帖子"]
        for _ in 0..<8 where loadingMore.exists == false {
            scrollView.swipeUp()
        }
        XCTAssertTrue(
            loadingMore.waitForExistence(timeout: 2),
            "测试必须先确认慢分页请求已开始"
        )

        let homeTab = rootTab("首页", in: app)
        let appFrame = app.frame
        let homeTabFrame = homeTab.frame
        app.coordinate(withNormalizedOffset: CGVector(
            dx: homeTabFrame.midX / appFrame.width,
            dy: homeTabFrame.midY / appFrame.height
        )).tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["home-refresh-animation"]
                .waitForExistence(timeout: 2),
            "分页中重复点击首页也必须立即进入统一刷新状态"
        )
        XCTAssertTrue(
            app.buttons["下拉刷新已更新"].waitForExistence(timeout: 5),
            "首页刷新应取消慢分页并提交新的第一页"
        )
    }

    func testForumHubAndMeKeepLoginOutOfHome() {
        let app = launchApp()

        rootTab("进吧", in: app).tap()
        XCTAssertTrue(app.navigationBars["进吧"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.textFields["输入吧名"].exists)

        rootTab("我的", in: app).tap()
        XCTAssertTrue(app.navigationBars["我的"].waitForExistence(timeout: 10))
        let loginButton = app.buttons["手机号验证码登录"]
        let followedForumsButton = app.buttons["关注的吧"]
        XCTAssertTrue(
            loginButton.waitForExistence(timeout: 5) || followedForumsButton.waitForExistence(timeout: 5)
        )
    }

    func testForumHubTitleStaysInsideNavigationBarWhileScrolling() {
        let app = launchApp(
            account: "loggedIn",
            additionalArguments: [
                "UITEST_EXTENDED_REFRESH_ANIMATION",
                "UITEST_SEED_SCROLLABLE_RECENT_FORUMS",
                "-UIPreferredContentSizeCategoryName",
                "UICTContentSizeCategoryAccessibilityXXXL"
            ]
        )

        rootTab("进吧", in: app).tap()
        let navigationBar = app.navigationBars["进吧"]
        let title = navigationBar.staticTexts["进吧"]
        let forumList = app.descendants(matching: .any)["forum-hub-list"]
        let forumField = app.textFields["输入吧名"]
        let firstForumRow = app.buttons.matching(identifier: "forum-hub-forum-row").firstMatch
        XCTAssertTrue(navigationBar.waitForExistence(timeout: 10))
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertTrue(forumList.waitForExistence(timeout: 5))
        XCTAssertTrue(forumField.waitForExistence(timeout: 5))
        XCTAssertTrue(
            firstForumRow.waitForExistence(timeout: 10),
            "关注贴吧加载完成后才验证下拉刷新"
        )

        let initialFrame = title.frame
        assertNavigationTitle(title, staysInside: navigationBar)

        let pullDelta = min(96 / max(forumList.frame.height, 1), 0.70)
        let refreshStart = forumList.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.20)
        )
        let refreshEnd = forumList.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.20 + pullDelta)
        )
        refreshStart.press(forDuration: 0.1, thenDragTo: refreshEnd)
        let refreshAnimation = app.descendants(matching: .any)[
            "forum-hub-refresh-animation"
        ]
        XCTAssertTrue(refreshAnimation.waitForExistence(timeout: 2))
        assertNavigationTitle(title, staysInside: navigationBar)
        assertRefreshRevealMatchesGroupedBackground(
            in: app,
            scrollContainer: forumList,
            refreshIndicator: refreshAnimation,
            context: "进吧刷新保持态"
        )
        XCTAssertTrue(refreshAnimation.waitForNonExistence(timeout: 8))
        assertNavigationTitle(title, staysInside: navigationBar)

        for _ in 0..<6 {
            forumList.swipeUp()
            assertNavigationTitle(title, staysInside: navigationBar)
        }
        XCTAssertFalse(forumField.isHittable, "测试必须先让进吧列表明确离开顶部")
        for _ in 0..<12 where forumField.isHittable == false {
            forumList.swipeDown()
            assertNavigationTitle(title, staysInside: navigationBar)
        }
        XCTAssertTrue(forumField.isHittable, "滚动验证结束后必须回到进吧页顶部")
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))

        XCTAssertEqual(title.frame.midX, initialFrame.midX, accuracy: 1)
        XCTAssertEqual(title.frame.midY, initialFrame.midY, accuracy: 1)
        attachScreenshot(named: "fixture-forum-hub-inline-title-after-scroll")
    }

    func testFollowedForumTitleAndFirstRowStayVisibleWhileRefreshing() {
        let app = launchApp(
            account: "loggedIn",
            additionalArguments: [
                "UITEST_EXTENDED_REFRESH_ANIMATION",
                "-UIPreferredContentSizeCategoryName",
                "UICTContentSizeCategoryAccessibilityXXXL"
            ]
        )

        rootTab("我的", in: app).tap()
        let entry = app.buttons["关注的吧"]
        XCTAssertTrue(entry.waitForExistence(timeout: 8))
        entry.tap()

        let navigationBar = app.navigationBars["关注的吧"]
        let title = navigationBar.staticTexts["关注的吧"]
        let searchField = app.textFields["followed-forum-search-field"]
        let list = app.scrollViews["followed-forum-list"]
        let firstRow = app.buttons.matching(identifier: "followed-forum-row").firstMatch
        XCTAssertTrue(navigationBar.waitForExistence(timeout: 8))
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        XCTAssertTrue(list.waitForExistence(timeout: 5))
        XCTAssertTrue(firstRow.waitForExistence(timeout: 8))
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))

        let initialTitleFrame = title.frame
        let initialSearchFrame = searchField.frame
        let initialListFrame = list.frame
        assertNavigationTitle(title, staysInside: navigationBar)
        assertVisible(firstRow, inside: list, context: "关注的吧首行刷新前")

        let appFrame = app.frame
        let firstRowFrame = firstRow.frame
        let startPoint = CGPoint(
            x: firstRowFrame.midX,
            y: firstRowFrame.minY + min(max(firstRowFrame.height * 0.35, 24), 60)
        )
        // Start inside visible row content. On iOS 26 the scroll view's
        // accessibility frame can extend behind fixed navigation/header chrome,
        // where a synthetic drag would not reach the list pan recognizer.
        let endPoint = CGPoint(
            x: startPoint.x,
            y: min(startPoint.y + 120, appFrame.maxY - 32)
        )
        let start = app.coordinate(withNormalizedOffset: CGVector(
            dx: startPoint.x / max(appFrame.width, 1),
            dy: startPoint.y / max(appFrame.height, 1)
        ))
        let end = app.coordinate(withNormalizedOffset: CGVector(
            dx: endPoint.x / max(appFrame.width, 1),
            dy: endPoint.y / max(appFrame.height, 1)
        ))
        start.press(forDuration: 0.1, thenDragTo: end)

        let refresh = app.descendants(matching: .any)["forum-list-refresh-animation"]
        XCTAssertTrue(refresh.waitForExistence(timeout: 2))
        assertNavigationTitle(title, staysInside: navigationBar)
        XCTAssertEqual(searchField.frame.minY, initialSearchFrame.minY, accuracy: 1)
        XCTAssertEqual(searchField.frame.height, initialSearchFrame.height, accuracy: 1)
        let heldRefreshDistance: CGFloat = 44
        XCTAssertEqual(
            list.frame.minY,
            initialListFrame.minY + heldRefreshDistance,
            accuracy: 2,
            "列表只应保留统一的 44pt 刷新空间，不得发生搜索抽屉重排"
        )
        assertVisible(firstRow, inside: list, context: "关注的吧首行刷新保持态")
        assertRefreshRevealMatchesGroupedBackground(
            in: app,
            scrollContainer: list,
            refreshIndicator: refresh,
            context: "关注的吧刷新保持态"
        )
        attachScreenshot(named: "fixture-followed-forums-refresh-stable-title")

        XCTAssertTrue(refresh.waitForNonExistence(timeout: 8))
        assertNavigationTitle(title, staysInside: navigationBar)
        XCTAssertEqual(title.frame.midX, initialTitleFrame.midX, accuracy: 1)
        XCTAssertEqual(title.frame.midY, initialTitleFrame.midY, accuracy: 1)
    }

    private func assertVisible(
        _ element: XCUIElement,
        inside container: XCUIElement,
        context: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(element.exists, "\(context)：元素不存在", file: file, line: line)
        let intersection = container.frame.intersection(element.frame)
        XCTAssertFalse(intersection.isNull, "\(context)：元素不在可视区域", file: file, line: line)
        XCTAssertGreaterThan(
            intersection.height,
            min(20, element.frame.height * 0.5),
            "\(context)：元素被顶部或底部明显裁切",
            file: file,
            line: line
        )
    }

    private func assertRefreshRevealMatchesGroupedBackground(
        in app: XCUIApplication,
        scrollContainer: XCUIElement,
        refreshIndicator: XCUIElement,
        context: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let capturedScreenshot = XCUIScreen.main.screenshot()
        let screenshot = capturedScreenshot.image
        let point = CGPoint(
            x: scrollContainer.frame.minX + 8,
            // Anchor the sample to the real refresh overlay. On iOS 26 a
            // scroll view's accessibility frame can extend behind navigation
            // chrome and is not a reliable visible-surface origin.
            y: refreshIndicator.frame.midY
        )
        guard let actual = screenshotRGB(screenshot, atScreenPoint: point, screenFrame: app.frame) else {
            XCTFail("\(context)：无法读取刷新暴露区像素", file: file, line: line)
            return
        }
        let expectedColor = UIColor.systemGroupedBackground.resolvedColor(
            with: UITraitCollection(userInterfaceStyle: UITraitCollection.current.userInterfaceStyle)
        )
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard expectedColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            XCTFail("\(context)：无法解析语义背景色", file: file, line: line)
            return
        }
        let expected = (
            red: Int((red * 255).rounded()),
            green: Int((green * 255).rounded()),
            blue: Int((blue * 255).rounded())
        )
        let difference = abs(actual.red - expected.red)
            + abs(actual.green - expected.green)
            + abs(actual.blue - expected.blue)
        if difference > 30 {
            let attachment = XCTAttachment(screenshot: capturedScreenshot)
            attachment.name = "\(context)-background-mismatch"
            attachment.lifetime = .keepAlways
            add(attachment)
            print(
                "\(context): scrollFrame=\(scrollContainer.frame), "
                    + "samplePoint=\(point), actual=\(actual), expected=\(expected)"
            )
        }
        XCTAssertLessThanOrEqual(
            difference,
            30,
            "\(context)：刷新暴露区与分组背景不连续，实际 \(actual)，预期 \(expected)",
            file: file,
            line: line
        )
    }

    private func screenshotRGB(
        _ image: UIImage,
        atScreenPoint point: CGPoint,
        screenFrame: CGRect
    ) -> (red: Int, green: Int, blue: Int)? {
        guard let cgImage = image.cgImage,
              screenFrame.width > 0,
              screenFrame.height > 0,
              let data = cgImage.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data) else {
            return nil
        }
        let x = min(max(Int(point.x / screenFrame.width * CGFloat(cgImage.width)), 0), cgImage.width - 1)
        let y = min(max(Int(point.y / screenFrame.height * CGFloat(cgImage.height)), 0), cgImage.height - 1)
        let bytesPerPixel = cgImage.bitsPerPixel / 8
        guard bytesPerPixel >= 3 else { return nil }
        let offset = y * cgImage.bytesPerRow + x * bytesPerPixel
        return (Int(bytes[offset]), Int(bytes[offset + 1]), Int(bytes[offset + 2]))
    }

    func testViewingThreadAddsBrowsingHistoryInMeAndReopensIt() {
        let app = launchApp()
        openFirstThread(in: app)
        XCTAssertTrue(app.buttons["更多"].waitForExistence(timeout: 8))

        let threadBackButton = app.navigationBars.buttons.firstMatch
        XCTAssertTrue(waitForHittable(threadBackButton, expected: true, timeout: 5))
        threadBackButton.tap()
        XCTAssertTrue(rootTab("我的", in: app).waitForExistence(timeout: 8))

        rootTab("我的", in: app).tap()
        let historyEntry = app.buttons["browsing-history-entry"]
        XCTAssertTrue(
            waitForElement(named: "browsing-history-entry", in: app, maxSwipes: 4),
            "小屏设备滚动后应能找到浏览历史入口"
        )
        historyEntry.tap()

        XCTAssertTrue(app.navigationBars["浏览历史"].waitForExistence(timeout: 8))
        let historyRow = app.buttons["browsing-history-row-1001"]
        XCTAssertTrue(historyRow.waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["确定性主帖：回复筛选与媒体布局"].exists)

        historyRow.tap()
        XCTAssertTrue(app.buttons["更多"].waitForExistence(timeout: 8))

        middleSwipeRight(in: app)
        XCTAssertTrue(
            app.navigationBars["浏览历史"].waitForExistence(timeout: 5),
            "历史帖子右划只能返回浏览历史"
        )
        middleSwipeRight(in: app)
        XCTAssertTrue(app.navigationBars["我的"].waitForExistence(timeout: 5))
    }

    func testBrowsingHistoryThreadRightSwipeKeepsEveryRouteAcrossRepeatedCycles() {
        let app = launchApp()
        openFirstThread(in: app)
        app.navigationBars.buttons.firstMatch.tap()
        rootTab("我的", in: app).tap()
        XCTAssertTrue(
            waitForElement(named: "browsing-history-entry", in: app, maxSwipes: 4),
            "小屏设备滚动后应能找到浏览历史入口"
        )
        app.buttons["browsing-history-entry"].tap()

        let historyBar = app.navigationBars["浏览历史"]
        let historyRow = app.buttons["browsing-history-row-1001"]
        XCTAssertTrue(historyBar.waitForExistence(timeout: 8))

        for cycle in 1...5 {
            XCTAssertTrue(historyRow.waitForExistence(timeout: 5), "第\(cycle)轮缺少历史帖子")
            historyRow.tap()
            XCTAssertTrue(app.buttons["更多"].waitForExistence(timeout: 8), "第\(cycle)轮未进入帖子")
            middleSwipeRight(in: app)
            XCTAssertTrue(
                historyBar.waitForExistence(timeout: 5),
                "第\(cycle)轮帖子右划必须且只能回到浏览历史"
            )
        }

        middleSwipeRight(in: app)
        XCTAssertTrue(app.navigationBars["我的"].waitForExistence(timeout: 5))
    }

    func testThreadFavoriteAppearsInMeAndReopensIt() {
        let app = launchApp(account: "loggedIn")
        openFirstThread(in: app)

        let favoriteButton = app.buttons["thread-favorite-button"]
        XCTAssertTrue(favoriteButton.waitForExistence(timeout: 8))
        XCTAssertTrue(waitForHittable(favoriteButton, expected: true, timeout: 5))
        favoriteButton.tap()
        let favoriteUpdated = NSPredicate(format: "label == %@", "取消收藏帖子")
        expectation(for: favoriteUpdated, evaluatedWith: favoriteButton)
        waitForExpectations(timeout: 5)

        let threadBackButton = app.navigationBars.buttons.firstMatch
        XCTAssertTrue(waitForHittable(threadBackButton, expected: true, timeout: 5))
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

        middleSwipeRight(in: app)
        XCTAssertTrue(
            app.navigationBars["帖子收藏"].waitForExistence(timeout: 5),
            "收藏帖子右划只能返回帖子收藏"
        )
        middleSwipeRight(in: app)
        XCTAssertTrue(app.navigationBars["我的"].waitForExistence(timeout: 5))
    }

    func testSavedReadingPositionAutoRestoresAndReturnsToTop() {
        let app = launchApp(
            scenario: "imageGesture",
            account: "loggedIn",
            additionalArguments: [
                "UITEST_SEED_LOCAL_THREAD_LIBRARY",
                "UITEST_SEED_ACCOUNT_COLLECTION"
            ]
        )
        rootTab("我的", in: app).tap()

        let favoritesEntry = app.buttons["thread-favorites-entry"]
        XCTAssertTrue(favoritesEntry.waitForExistence(timeout: 8))
        favoritesEntry.tap()
        XCTAssertTrue(app.buttons["thread-library-manage"].waitForExistence(timeout: 8))
        let favoriteRow = app.buttons["thread-favorite-row-1001"]
        XCTAssertTrue(favoriteRow.waitForExistence(timeout: 8))
        favoriteRow.tap()

        // The saved position restores automatically: the targeted reply is
        // scrolled into view without any manual step.
        let replyText = app.descendants(matching: .any)["thread-reply-text"].firstMatch
        XCTAssertTrue(replyText.waitForExistence(timeout: 8))
        let replyBecameVisible = NSPredicate(format: "hittable == true")
        expectation(for: replyBecameVisible, evaluatedWith: replyText)
        waitForExpectations(timeout: 5)
        // The fixture marks post-ID-targeted loads with this distinct reply
        // body, proving the first request itself carried the saved post ID.
        XCTAssertTrue(
            replyText.label.contains("已定位搜索命中回复") ||
                (replyText.value as? String)?.contains("已定位搜索命中回复") == true
        )
        let restoredReplyMinY = replyText.frame.minY
        RunLoop.current.run(until: Date().addingTimeInterval(1.8))
        XCTAssertEqual(
            replyText.frame.minY,
            restoredReplyMinY,
            accuracy: 4,
            "目标上方的成功图片完成布局后，恢复楼层不能再次漂移"
        )

        let banner = app.otherElements["restored-reading-banner"]
        XCTAssertTrue(banner.exists)
        let returnToTop = app.buttons["restored-reading-return-top"]
        XCTAssertTrue(returnToTop.exists)
        XCTAssertTrue(returnToTop.isHittable)
        returnToTop.tap()

        let mainText = app.descendants(matching: .any)["thread-main-text"].firstMatch
        XCTAssertTrue(mainText.waitForExistence(timeout: 8))
        let mainBecameVisible = NSPredicate(format: "hittable == true")
        expectation(for: mainBecameVisible, evaluatedWith: mainText)
        waitForExpectations(timeout: 5)
        XCTAssertFalse(banner.exists)
    }

    func testScrollingThreadRecordsAndRestoresReadingPosition() {
        let app = launchApp(scenario: "readingPosition")
        openFirstThread(in: app)

        let scrollView = app.scrollViews["thread-detail-scroll-view"]
        XCTAssertTrue(scrollView.waitForExistence(timeout: 8))
        for _ in 0..<5 {
            scrollView.swipeUp(velocity: .fast)
        }

        let backButton = app.navigationBars.buttons.firstMatch
        XCTAssertTrue(waitForHittable(backButton, expected: true, timeout: 5))
        backButton.tap()
        XCTAssertTrue(threadRows(in: app).firstMatch.waitForExistence(timeout: 8))

        openFirstThread(in: app)
        let restoredBanner = app.otherElements["restored-reading-banner"]
        XCTAssertTrue(
            restoredBanner.waitForExistence(timeout: 8),
            "实际滚动后再次进入同帖时应恢复最近阅读位置"
        )
        XCTAssertFalse(
            (restoredBanner.value as? String)?.isEmpty ?? true,
            "恢复提示必须携带已保存的具体楼层"
        )
    }

    func testThreadVerticalScrollFrameProbe() {
        runThreadVerticalScrollFrameProbe(variant: "mixed")
    }

    func testThreadVerticalScrollFrameProbeTextOnly() {
        runThreadVerticalScrollFrameProbe(variant: "text")
    }

    func testThreadVerticalScrollFrameProbeEmoticonsOnly() {
        runThreadVerticalScrollFrameProbe(variant: "emoticons")
    }

    func testThreadVerticalScrollFrameProbeImagesOnly() {
        runThreadVerticalScrollFrameProbe(variant: "images")
    }

    func testThreadVerticalScrollFrameProbeProductionMixed() {
        runThreadVerticalScrollFrameProbe(variant: "production")
    }

    private func runThreadVerticalScrollFrameProbe(variant: String) {
        let app = launchApp(
            scenario: "scrollPerformance",
            additionalArguments: ["UITEST_SCROLL_FRAME_PROBE"],
            additionalEnvironment: ["TIEBAPURE_SCROLL_FIXTURE_VARIANT": variant],
            disableAnimations: false
        )
        openFirstThread(in: app)

        let scrollView = app.scrollViews["thread-detail-scroll-view"]
        XCTAssertTrue(scrollView.waitForExistence(timeout: 8))
        for _ in 0..<8 {
            scrollView.swipeUp(velocity: .fast)
        }
        for _ in 0..<8 {
            scrollView.swipeDown(velocity: .fast)
        }
        Thread.sleep(forTimeInterval: 0.8)
    }

    func testBrowsingHistorySearchAndBatchDeleteManageVisibleRecords() {
        let app = launchApp(additionalArguments: ["UITEST_SEED_LOCAL_THREAD_MANAGEMENT"])
        rootTab("我的", in: app).tap()
        XCTAssertTrue(waitForElement(named: "browsing-history-entry", in: app, maxSwipes: 4))
        app.buttons["browsing-history-entry"].tap()

        XCTAssertTrue(app.descendants(matching: .any)["browsing-history-row-1001"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.descendants(matching: .any)["browsing-history-row-1004"].exists)
        let searchField = app.searchFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        searchField.tap()
        searchField.typeText("无障碍")
        XCTAssertTrue(app.descendants(matching: .any)["browsing-history-row-1002"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["browsing-history-row-1004"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["browsing-history-row-1001"].exists)

        app.terminate()
        let batchApp = launchApp(additionalArguments: ["UITEST_SEED_LOCAL_THREAD_MANAGEMENT"])
        rootTab("我的", in: batchApp).tap()
        XCTAssertTrue(waitForElement(named: "browsing-history-entry", in: batchApp, maxSwipes: 4))
        batchApp.buttons["browsing-history-entry"].tap()

        let editButton = batchApp.buttons["browsing-history-edit"]
        XCTAssertTrue(editButton.waitForExistence(timeout: 5))
        editButton.tap()
        batchApp.buttons["browsing-history-select-all"].tap()
        XCTAssertTrue(batchApp.staticTexts["已选 4 项"].waitForExistence(timeout: 5))
        batchApp.buttons["browsing-history-delete-selected"].tap()
        XCTAssertTrue(batchApp.buttons["删除"].waitForExistence(timeout: 5))
        batchApp.buttons["删除"].tap()
        XCTAssertTrue(batchApp.descendants(matching: .any)["browsing-history-empty"].waitForExistence(timeout: 5))
        XCTAssertFalse(batchApp.descendants(matching: .any)["browsing-history-row-1001"].exists)
    }

    func testThreadFavoritesFilterBatchDeleteKeepsHiddenFavorites() {
        let app = launchApp(
            account: "loggedIn",
            additionalArguments: [
                "UITEST_SEED_LOCAL_THREAD_MANAGEMENT",
                "UITEST_SEED_ACCOUNT_COLLECTION_MANY"
            ]
        )
        rootTab("我的", in: app).tap()
        let favoritesEntry = app.buttons["thread-favorites-entry"]
        XCTAssertTrue(favoritesEntry.waitForExistence(timeout: 8))
        favoritesEntry.tap()

        XCTAssertTrue(app.descendants(matching: .any)["thread-favorite-row-1001"].waitForExistence(timeout: 8))
        let filter = app.segmentedControls["thread-favorites-progress-filter"]
        XCTAssertTrue(filter.waitForExistence(timeout: 5))
        filter.buttons["无进度"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["thread-favorite-row-1002"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["thread-favorite-row-1004"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["thread-favorite-row-1001"].exists)

        app.buttons["thread-favorites-edit"].tap()
        app.buttons["thread-favorites-select-all"].tap()
        XCTAssertTrue(app.staticTexts["已选 2 项"].waitForExistence(timeout: 5))
        app.buttons["thread-favorites-delete-selected"].tap()
        XCTAssertTrue(app.buttons["删除"].waitForExistence(timeout: 5))
        app.buttons["删除"].tap()

        filter.buttons["全部"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["thread-favorite-row-1001"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["thread-favorite-row-1003"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["thread-favorite-row-1002"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["thread-favorite-row-1004"].exists)
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
        let app = launchApp(additionalArguments: ["UITEST_READING_REPLY_SORT_DESCENDING"])

        let searchField = openGlobalSearch(in: app)
        searchField.typeText("iPhone")
        searchField.typeText("\n")

        XCTAssertTrue(app.navigationBars["搜索"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.segmentedControls.buttons["全部"].waitForExistence(timeout: 10))
        let firstResult = threadRows(in: app).firstMatch
        XCTAssertTrue(firstResult.waitForExistence(timeout: 10))
        app.descendants(matching: .any).matching(identifier: "thread-open-area").firstMatch.tap()
        let ascendingSort = app.buttons["thread-reply-sort-0"]
        XCTAssertTrue(ascendingSort.waitForExistence(timeout: 8))
        XCTAssertEqual(
            ascendingSort.value as? String,
            "已选择",
            "搜索回复携带 postID 时必须覆盖倒序默认值，使用可确定定位的正序"
        )
        XCTAssertTrue(waitForLabelContaining("已定位搜索命中回复", in: app, maxSwipes: 10))
    }

    func testSearchBackButtonDismissesFocusedSearchInOneStepAndHistoryPersists() {
        let app = launchApp()
        let searchField = openGlobalSearch(in: app)
        searchField.typeText("history-test")
        searchField.typeText("\n")
        XCTAssertTrue(threadRows(in: app).firstMatch.waitForExistence(timeout: 8))

        let backButton = app.navigationBars["搜索"].buttons.firstMatch
        XCTAssertTrue(waitForHittable(backButton, expected: true, timeout: 5))
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

    func testSearchUsesSystemBackSwipeToPreviousPage() {
        let app = launchApp()
        _ = openGlobalSearch(in: app)
        let searchNavigationBar = app.navigationBars["搜索"]

        middleSwipeRight(in: app)

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
        XCTAssertTrue(waitForHittable(profileBackButton, expected: true, timeout: 5))
        profileBackButton.tap()
        XCTAssertTrue(app.buttons["更多"].waitForExistence(timeout: 5))

        middleSwipeRight(in: app)
        XCTAssertTrue(app.navigationBars["首页"].waitForExistence(timeout: 5))
        XCTAssertTrue(rootTab("首页", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(rootTab("进吧", in: app).exists)
        XCTAssertTrue(rootTab("我的", in: app).exists)
    }

    func testThreadDetailUsesSystemBackSwipeToPreviousPage() {
        let app = launchApp()
        openFirstThread(in: app)
        let detailMarker = app.buttons["更多"]
        XCTAssertTrue(detailMarker.exists)

        middleSwipeRight(in: app)

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

    func testThreadShortRightDragCancelsWithoutChangingRoute() {
        let app = launchApp()
        openFirstThread(in: app)

        let detailMarker = app.buttons["更多"]
        XCTAssertTrue(detailMarker.waitForExistence(timeout: 8))
        let startX: CGFloat
        let endX: CGFloat
        if #available(iOS 26.0, *) {
            startX = 0.45
            endX = 0.55
        } else {
            startX = 0.01
            endX = 0.08
        }
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: startX, dy: 0.38))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: endX, dy: 0.38))
        start.press(
            forDuration: 0.1,
            thenDragTo: end,
            withVelocity: 100,
            thenHoldForDuration: 0.1
        )

        XCTAssertTrue(
            detailMarker.waitForExistence(timeout: 3),
            "未达到完成阈值的右划必须回弹并留在帖子页"
        )
        XCTAssertFalse(app.navigationBars["首页"].exists)

        middleSwipeRight(in: app)
        XCTAssertTrue(app.navigationBars["首页"].waitForExistence(timeout: 5))
    }

    func testUserProfileMiddleRightSwipeReturnsOnlyOneLevelToThread() {
        let app = launchApp()
        openFirstThread(in: app)

        let userButton = app.buttons["thread-main-user-button"]
        XCTAssertTrue(userButton.waitForExistence(timeout: 8))
        userButton.tap()

        let profileScreen = app.descendants(matching: .any)["user-profile-screen"]
        XCTAssertTrue(profileScreen.waitForExistence(timeout: 8))
        middleSwipeRight(in: app)

        let profileDismissed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: profileScreen
        )
        XCTAssertEqual(XCTWaiter.wait(for: [profileDismissed], timeout: 5), .completed)
        attachScreenshot(named: "fixture-thread-after-profile-right-swipe")
        XCTAssertTrue(
            app.descendants(matching: .any)["thread-favorite-button"].waitForExistence(timeout: 5),
            "从用户主页右划后应回到帖子，而不是越过帖子直接回首页。当前层级：\n\(app.debugDescription)"
        )

        middleSwipeRight(in: app)
        XCTAssertTrue(app.navigationBars["首页"].waitForExistence(timeout: 5))
    }

    func testRepeatedUserProfileRightSwipesNeverSkipTheThread() {
        let app = launchApp()
        openFirstThread(in: app)

        for iteration in 0..<6 {
            let userButton = app.buttons["thread-main-user-button"]
            XCTAssertTrue(userButton.waitForExistence(timeout: 8))
            userButton.tap()

            let profileScreen = app.descendants(matching: .any)["user-profile-screen"]
            XCTAssertTrue(profileScreen.waitForExistence(timeout: 8))
            middleSwipeRight(in: app)

            let profileDismissed = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "exists == false"),
                object: profileScreen
            )
            XCTAssertEqual(
                XCTWaiter.wait(for: [profileDismissed], timeout: 5),
                .completed,
                "第\(iteration + 1)次返回时用户主页没有关闭"
            )
            XCTAssertTrue(
                app.descendants(matching: .any)["thread-favorite-button"].waitForExistence(timeout: 5),
                "第\(iteration + 1)次返回越过帖子直接回到了首页"
            )
            XCTAssertFalse(app.navigationBars["首页"].exists)
        }
    }

    func testUserProfileThreadRightSwipeReturnsOnlyToUserProfile() {
        let app = launchApp()
        openFirstThread(in: app)

        let originalThreadMarker = app.descendants(matching: .any)["thread-favorite-button"]
        let userButton = app.buttons["thread-main-user-button"]
        XCTAssertTrue(userButton.waitForExistence(timeout: 8))
        userButton.tap()

        let profileScreen = app.descendants(matching: .any)["user-profile-screen"]
        XCTAssertTrue(profileScreen.waitForExistence(timeout: 8))
        let profileThread = app.buttons["user-profile-thread-row-1002"]
        XCTAssertTrue(profileThread.waitForExistence(timeout: 8))
        XCTAssertTrue(scrollToHittable(profileThread, in: app.scrollViews["user-profile-screen"]))
        profileThread.tap()
        let profileCoveredByThread = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: profileScreen
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [profileCoveredByThread], timeout: 8),
            .completed,
            "点击用户主页帖子后应进入帖子详情"
        )

        middleSwipeRight(in: app, y: 0.2)
        XCTAssertTrue(
            profileScreen.waitForExistence(timeout: 5),
            "用户主页中的帖子右划只能返回用户主页，不能越过用户主页"
        )

        middleSwipeRight(in: app)
        XCTAssertTrue(originalThreadMarker.waitForExistence(timeout: 5))
    }

    func testUserProfileSourceThreadReturnsToExistingThreadWithoutDuplicatePush() {
        let app = launchApp()
        openFirstThread(in: app)

        let userButton = app.buttons["thread-main-user-button"]
        XCTAssertTrue(userButton.waitForExistence(timeout: 8))
        userButton.tap()

        let profileScreen = app.descendants(matching: .any)["user-profile-screen"]
        XCTAssertTrue(profileScreen.waitForExistence(timeout: 8))
        let sourceThread = app.buttons["user-profile-thread-row-1001"]
        XCTAssertTrue(sourceThread.waitForExistence(timeout: 8))
        XCTAssertTrue(scrollToHittable(sourceThread, in: app.scrollViews["user-profile-screen"]))
        sourceThread.tap()

        let profileDismissed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: profileScreen
        )
        XCTAssertEqual(XCTWaiter.wait(for: [profileDismissed], timeout: 8), .completed)
        middleSwipeRight(in: app, y: 0.2)
        XCTAssertTrue(
            app.navigationBars["首页"].waitForExistence(timeout: 5),
            "来源帖子不应被重复压入导航栈"
        )
    }

    func testSearchUserProfileRightSwipeReturnsOnlyToSearch() {
        let app = launchApp()
        let searchField = openGlobalSearch(in: app)
        searchField.typeText("iPhone")
        searchField.typeText("\n")

        let result = threadRows(in: app).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 10))
        let userButton = app.buttons
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "feed-user-button-"))
            .firstMatch
        XCTAssertTrue(userButton.waitForExistence(timeout: 8))
        XCTAssertTrue(scrollToHittable(userButton, in: app.scrollViews.firstMatch))
        userButton.tap()

        let profileScreen = app.descendants(matching: .any)["user-profile-screen"]
        XCTAssertTrue(profileScreen.waitForExistence(timeout: 8))
        middleSwipeRight(in: app)
        XCTAssertTrue(
            app.navigationBars["搜索"].waitForExistence(timeout: 5),
            "搜索结果用户主页右划只能返回搜索结果"
        )
        XCTAssertTrue(result.exists)

        middleSwipeRight(in: app)
        XCTAssertTrue(app.navigationBars["首页"].waitForExistence(timeout: 5))
    }

    func testForumUserProfileRightSwipeReturnsOnlyToForum() {
        let app = launchApp()
        rootTab("进吧", in: app).tap()

        let forumField = app.textFields["输入吧名"]
        XCTAssertTrue(forumField.waitForExistence(timeout: 10))
        forumField.tap()
        forumField.typeText("测试")
        app.buttons["进入贴吧"].tap()

        XCTAssertTrue(app.navigationBars["测试吧"].waitForExistence(timeout: 10))
        let userButton = app.buttons
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "feed-user-button-"))
            .firstMatch
        XCTAssertTrue(userButton.waitForExistence(timeout: 10))
        userButton.tap()

        let profileScreen = app.descendants(matching: .any)["user-profile-screen"]
        XCTAssertTrue(profileScreen.waitForExistence(timeout: 8))
        middleSwipeRight(in: app)
        XCTAssertTrue(
            app.navigationBars["测试吧"].waitForExistence(timeout: 5),
            "贴吧列表用户主页右划只能返回原贴吧"
        )

        middleSwipeRight(in: app)
        XCTAssertTrue(app.navigationBars["进吧"].waitForExistence(timeout: 5))
    }

    func testForumThreadUserProfileRightSwipeNeverSkipsThread() {
        let app = launchApp()
        rootTab("进吧", in: app).tap()

        let forumField = app.textFields["输入吧名"]
        XCTAssertTrue(forumField.waitForExistence(timeout: 10))
        forumField.tap()
        forumField.typeText("测试")
        app.buttons["进入贴吧"].tap()

        XCTAssertTrue(app.navigationBars["测试吧"].waitForExistence(timeout: 10))
        openFirstThread(in: app)

        for iteration in 0..<8 {
            let userButton = app.buttons["thread-main-user-button"]
            XCTAssertTrue(userButton.waitForExistence(timeout: 8))
            userButton.tap()

            let profileScreen = app.descendants(matching: .any)["user-profile-screen"]
            XCTAssertTrue(profileScreen.waitForExistence(timeout: 8))
            middleSwipeRight(in: app)

            let profileDismissed = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "exists == false"),
                object: profileScreen
            )
            XCTAssertEqual(
                XCTWaiter.wait(for: [profileDismissed], timeout: 5),
                .completed,
                "第\(iteration + 1)次从用户主页返回时，用户主页没有关闭"
            )
            XCTAssertTrue(
                app.buttons["thread-favorite-button"].waitForExistence(timeout: 5),
                "第\(iteration + 1)次从用户主页返回越过了帖子详情，直接落到贴吧列表"
            )
        }

        middleSwipeRight(in: app)
        let detailScrollView = app.scrollViews["thread-detail-scroll-view"]
        XCTAssertTrue(
            detailScrollView.waitForNonExistence(timeout: 5),
            "帖子详情右划后详情页应先消失"
        )
        XCTAssertTrue(
            app.navigationBars["测试吧"].waitForExistence(timeout: 5),
            "帖子详情右划后应保留当前贴吧导航层"
        )
        XCTAssertTrue(
            app.scrollViews["forum-threads-scroll-view"].waitForExistence(timeout: 5),
            "帖子详情右划后应显示当前贴吧的帖子列表"
        )
        XCTAssertFalse(app.textFields["输入吧名"].isHittable, "不得越级返回进吧根页")
        XCTAssertFalse(app.buttons["thread-favorite-button"].exists)
    }

    func testRightSwipeOnThreadImageDismissesWithoutOpeningPreview() {
        let app = launchApp(scenario: "imageGesture")
        openFirstThread(in: app)

        let inlineImage = visibleThreadInlineImage(in: app)
        XCTAssertNotNil(inlineImage)
        guard let inlineImage else { return }

        if #available(iOS 26.0, *) {
            inlineImage.swipeRight()
        } else {
            let imageFrame = inlineImage.frame
            let appFrame = app.frame
            let visibleY = min(max(imageFrame.midY, appFrame.minY + 140), appFrame.maxY - 120)
            let localY = min(max((visibleY - imageFrame.minY) / imageFrame.height, 0.1), 0.9)
            let start = inlineImage.coordinate(
                withNormalizedOffset: CGVector(dx: 0.4, dy: localY)
            )
            let end = app.coordinate(withNormalizedOffset: CGVector(
                dx: 0.9,
                dy: (visibleY - appFrame.minY) / appFrame.height
            ))
            start.press(forDuration: 0.05, thenDragTo: end)
        }

        let preview = app.descendants(matching: .any)["full-screen-image-pager"]
        XCTAssertFalse(preview.waitForExistence(timeout: 1), "图片区域右划不得打开全屏预览")
        if #available(iOS 26.0, *) {
            XCTAssertTrue(app.navigationBars["首页"].waitForExistence(timeout: 5))
        } else {
            XCTAssertTrue(app.buttons["更多"].waitForExistence(timeout: 3))
            middleSwipeRight(in: app)
            XCTAssertTrue(app.navigationBars["首页"].waitForExistence(timeout: 5))
        }
    }

    func testTappingThreadImageStillOpensPreview() {
        let app = launchApp(
            scenario: "imageGesture",
            account: "loggedIn",
            additionalArguments: ["UITEST_RESET_CONTENT_SUBMISSION"]
        )
        openFirstThread(in: app)

        for iteration in 0..<3 {
            let inlineImage = visibleThreadInlineImage(in: app)
            XCTAssertNotNil(inlineImage)
            guard let inlineImage else { return }
            inlineImage.tap()

            XCTAssertTrue(
                app.descendants(matching: .any)["full-screen-image-pager"].waitForExistence(timeout: 5),
                "第\(iteration + 1)次真正点按图片仍应打开全屏预览"
            )
            XCTAssertFalse(app.navigationBars["回复用户"].exists, "点击媒体不得触发回帖编辑器")
            dismissFullScreenImageBySingleTap(in: app)

            let sourceIsHittable = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "hittable == true"),
                object: inlineImage
            )
            XCTAssertEqual(
                XCTWaiter.wait(for: [sourceIsHittable], timeout: 5),
                .completed,
                "第\(iteration + 1)次关闭后应缩回同一张帖子图片"
            )
            XCTAssertTrue(app.buttons["thread-favorite-button"].exists)
        }
    }

    func testHomeImageStaysAlignedAfterPreviewDismissAndScrollReuse() {
        let app = launchApp(scenario: "imageGesture")
        let media = app.buttons["media-item-image-1001-1"]
        XCTAssertTrue(media.waitForExistence(timeout: 8))
        if media.isHittable == false {
            let feed = app.scrollViews.firstMatch
            XCTAssertTrue(feed.exists)
            feed.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.78))
                .press(
                    forDuration: 0.05,
                    thenDragTo: feed.coordinate(
                        withNormalizedOffset: CGVector(dx: 0.5, dy: 0.58)
                    )
                )
        }
        let mediaIsHittable = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "hittable == true"),
            object: media
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [mediaIsHittable], timeout: 5),
            .completed,
            "小屏或无障碍大字体下，短距离滚动后主页图片应完整可见"
        )

        let initialFrame = media.frame
        let initialImage = media.screenshot().image
        let initialAttachment = XCTAttachment(image: initialImage)
        initialAttachment.name = "home-image-before-preview"
        initialAttachment.lifetime = .deleteOnSuccess
        add(initialAttachment)
        print("HOME_IMAGE_REUSE initialFrame=\(initialFrame)")
        media.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["full-screen-image-pager"]
                .waitForExistence(timeout: 5)
        )
        dismissFullScreenImageBySingleTap(in: app)
        XCTAssertTrue(media.waitForExistence(timeout: 5))

        let feed = app.scrollViews["home-feed-scroll-view"]
        XCTAssertTrue(feed.exists)
        let upwardStart = feed.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.72))
        let upwardEnd = feed.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.28))
        var upwardDragCount = 0
        while media.isHittable, upwardDragCount < 3 {
            upwardStart.press(
                forDuration: 0.05,
                thenDragTo: upwardEnd,
                withVelocity: 300,
                thenHoldForDuration: 0.1
            )
            upwardDragCount += 1
        }
        XCTAssertFalse(media.isHittable, "滚动后应先让图片离屏，以覆盖 LazyVStack 复用路径")

        let downwardStart = feed.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.28))
        let downwardEnd = feed.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.72))
        for _ in 0..<upwardDragCount {
            downwardStart.press(
                forDuration: 0.05,
                thenDragTo: downwardEnd,
                withVelocity: 300,
                thenHoldForDuration: 0.1
            )
        }

        XCTAssertTrue(media.isHittable, "返回并滚动后应能再次看到同一张主页图片")
        let finalFrame = media.frame
        let finalImage = media.screenshot().image
        let finalAttachment = XCTAttachment(image: finalImage)
        finalAttachment.name = "home-image-after-scroll-reuse"
        finalAttachment.lifetime = .deleteOnSuccess
        add(finalAttachment)
        print("HOME_IMAGE_REUSE finalFrame=\(finalFrame)")
        XCTAssertGreaterThanOrEqual(
            finalFrame.minY,
            app.frame.minY,
            "像素比较前图片顶部必须完整回到可见区域"
        )
        XCTAssertLessThanOrEqual(
            finalFrame.maxY,
            app.tabBars.firstMatch.frame.minY,
            "像素比较前图片底部不得被标签栏遮挡"
        )
        XCTAssertEqual(media.frame.width, initialFrame.width, accuracy: 1)
        XCTAssertEqual(media.frame.height, initialFrame.height, accuracy: 1)
        assertScreenshotsVisuallyMatch(
            initialImage,
            finalImage,
            context: "主页图片预览返回并滚动复用后"
        )
        media.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["full-screen-image-pager"]
                .waitForExistence(timeout: 5),
            "滚动复用后的图片仍应从当前位置打开"
        )
    }

    func testHomeImageStaysAlignedAcrossRapidDismissAndScrollCycles() {
        let app = launchApp(scenario: "imageGesture")
        let media = app.buttons["media-item-image-1001-1"]
        XCTAssertTrue(media.waitForExistence(timeout: 8))
        XCTAssertTrue(waitForHittable(media, expected: true, timeout: 5))
        let baselineFrame = media.frame
        let baselineImage = media.screenshot().image
        let feed = app.scrollViews["home-feed-scroll-view"]
        XCTAssertTrue(feed.exists)

        let upwardStart = feed.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.66))
        let upwardEnd = feed.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.52))
        let downwardStart = feed.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.52))
        let downwardEnd = feed.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.66))

        for cycle in 1...8 {
            media.tap()
            let pager = app.descendants(matching: .any)["full-screen-image-pager"]
            XCTAssertTrue(pager.waitForExistence(timeout: 3), "第\(cycle)轮没有打开图片")
            let surface = app.images["full-screen-image-zoom-surface-0"]
            XCTAssertTrue(surface.waitForExistence(timeout: 2))
            surface.coordinate(
                withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)
            ).tap()

            // Deliberately submit the scroll immediately after the dismissal
            // gesture instead of waiting for a source-is-hittable expectation.
            upwardStart.press(forDuration: 0.01, thenDragTo: upwardEnd)
            downwardStart.press(forDuration: 0.01, thenDragTo: downwardEnd)

            // The physical drags deliberately overlap dismissal, but their
            // inertial scrolling is not guaranteed to cancel at the same
            // instant. Wait for the source cell itself to stop moving before
            // beginning the next open cycle; otherwise a tap can merely stop
            // UIScrollView deceleration and never reach the image button.
            XCTAssertNotNil(
                waitForStableFrame(of: media),
                "第\(cycle)轮滚动未在下一次点击前稳定"
            )
            XCTAssertTrue(media.isHittable, "第\(cycle)轮返回滚动后图片不可点击")
            XCTAssertEqual(media.frame.minX, baselineFrame.minX, accuracy: 1)
            XCTAssertEqual(media.frame.width, baselineFrame.width, accuracy: 1)
            XCTAssertEqual(media.frame.height, baselineFrame.height, accuracy: 1)
            assertScreenshotsVisuallyMatch(
                baselineImage,
                media.screenshot().image,
                context: "第\(cycle)轮图片返回后立即滚动"
            )
        }
    }

    func testHomeImageCanScrollInTheFirstPostDismissalFrameWithoutMovingTheThumbnailLayer() {
        let app = launchApp(
            scenario: "imageGesture",
            additionalArguments: [
                "UITEST_IMAGE_DISMISS_SCROLL_RACE",
                "UITEST_IMAGE_DISMISS_SCROLL_RACE_VISUAL_HOLD",
                "UITEST_FORCE_IMAGE_TRANSITIONS"
            ]
        )
        let media = app.buttons["media-item-image-1001-1"]
        XCTAssertTrue(media.waitForExistence(timeout: 8))
        let feed = app.scrollViews["home-feed-scroll-view"]
        XCTAssertTrue(feed.exists)
        // `hittable` is insufficient on an SE-sized viewport: UIKit can tap a
        // partially clipped thumbnail, while production correctly refuses to
        // fly a hero into geometry that is not wholly represented on screen.
        // Centre the fixture first so this test exercises the real hero path on
        // every simulator rather than accidentally validating the fade fallback.
        for _ in 0..<4 {
            let visibleFeedFrame = feed.frame.insetBy(dx: 2, dy: 4)
            let mediaFrame = media.frame
            let isFullyVisible = media.isHittable
                && visibleFeedFrame.contains(mediaFrame)
            if isFullyVisible { break }

            let movesContentUp = mediaFrame.midY > visibleFeedFrame.midY
            let startY: CGFloat = movesContentUp ? 0.78 : 0.24
            let endY: CGFloat = movesContentUp ? 0.38 : 0.68
            feed.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: startY))
                .press(
                    forDuration: 0.05,
                    thenDragTo: feed.coordinate(
                        withNormalizedOffset: CGVector(dx: 0.5, dy: endY)
                    )
                )
        }
        let sourceIsHittable = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "hittable == true"),
            object: media
        )
        XCTAssertEqual(XCTWaiter.wait(for: [sourceIsHittable], timeout: 5), .completed)
        XCTAssertTrue(
            feed.frame.insetBy(dx: 2, dy: 4).contains(media.frame),
            "图片必须完整进入列表可视区后再验证 hero 转场"
        )
        let probe = app.descendants(matching: .any)["image-dismiss-scroll-race-probe"]
        for cycle in 1...6 {
            XCTAssertTrue(media.isHittable, "第\(cycle)轮图片没有恢复到可点击位置")
            media.tap()

            let pager = app.descendants(matching: .any)["full-screen-image-pager"]
            XCTAssertTrue(pager.waitForExistence(timeout: 5))
            let surface = app.images["full-screen-image-zoom-surface-0"]
            XCTAssertTrue(surface.waitForExistence(timeout: 3))
            surface.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)).tap()

            XCTAssertTrue(probe.waitForExistence(timeout: 5))
            let expectedResult = "cycle=\(cycle);completed=1"
            let completed = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "value BEGINSWITH %@", expectedResult),
                object: probe
            )
            XCTAssertEqual(XCTWaiter.wait(for: [completed], timeout: 5), .completed)

            let result = probe.value as? String ?? ""
            print("IMAGE_DISMISS_SCROLL_RACE \(result)")
            let firstObservedScroll = diagnosticMetric(
                "firstScrollMs",
                from: result
            ) ?? -1
            XCTAssertGreaterThanOrEqual(firstObservedScroll, 0)
            let firstScrollAfterFinish = diagnosticMetric(
                "firstScrollAfterFinishMs",
                from: result
            ) ?? -1
            XCTAssertGreaterThanOrEqual(
                firstScrollAfterFinish,
                0,
                "转场代理销毁前不允许底层列表滚动"
            )
            XCTAssertLessThanOrEqual(
                firstScrollAfterFinish,
                34,
                "代理清理并恢复正式缩略图后，应在两个显示帧内允许列表滚动"
            )
            XCTAssertGreaterThanOrEqual(
                diagnosticMetric("scrollDeltaMilli", from: result) ?? 0,
                96_000
            )
            XCTAssertEqual(
                diagnosticMetric("sourceBitmap", from: result),
                1,
                "列表正式缩略图必须始终保留自己的 bitmap"
            )
            XCTAssertEqual(
                diagnosticMetric("maxHeroProxyCount", from: result),
                1,
                "自定义转场同时最多只能存在一个临时图片代理"
            )
            XCTAssertGreaterThanOrEqual(
                diagnosticMetric("heroProxySamples", from: result) ?? 0,
                3
            )
            XCTAssertEqual(
                diagnosticMetric("sourceVisibleWhileProxy", from: result),
                0,
                "正式缩略图与临时代理不得同时显示"
            )
            XCTAssertEqual(
                diagnosticMetric("scrollBeforeProxyCleanup", from: result),
                0,
                "临时代理存在时底层列表不得改变 contentOffset"
            )
            XCTAssertEqual(
                diagnosticMetric("proxyCountAtFirstScroll", from: result),
                0,
                "第一帧真实滚动前临时代理必须已完全销毁"
            )
            XCTAssertEqual(
                diagnosticMetric("sourceVisibleAtFirstScroll", from: result),
                1,
                "第一帧真实滚动必须由已恢复的正式缩略图负责显示"
            )
            XCTAssertEqual(diagnosticMetric("visibleImageStable", from: result), 1)
            XCTAssertEqual(
                diagnosticMetric("sourceRestored", from: result),
                1,
                "图片转场结束后必须完整恢复真实缩略图的位图、层级、透明度和变换"
            )
        }
    }

    func testHomeOpensAnotherImageOnFirstTapAfterDismissal() {
        let app = launchApp(scenario: "imageGesture")
        let firstImage = app.buttons["media-item-image-1001-1"]
        let secondImage = app.buttons["media-item-image-1001-2"]
        XCTAssertTrue(firstImage.waitForExistence(timeout: 8))
        XCTAssertTrue(secondImage.waitForExistence(timeout: 8))
        XCTAssertTrue(waitForHittable(firstImage, expected: true, timeout: 5))
        XCTAssertTrue(waitForHittable(secondImage, expected: true, timeout: 5))

        // Cache physical coordinates before a modal covers the feed. Calling
        // `element.tap()` during an over-full-screen dismissal makes XCUITest
        // resolve {-1, -1} and inject no touch; users tap window coordinates.
        let appFrame = app.frame
        let firstImageFrame = firstImage.frame
        let secondImageFrame = secondImage.frame
        XCTAssertTrue(appFrame.intersects(firstImageFrame))
        XCTAssertTrue(appFrame.intersects(secondImageFrame))
        // SwiftUI can expose every child Button with the media container's
        // union frame. The fixture shows three equal-width thumbnails; derive
        // the first tile centre only in that overlap case.
        let usesSharedAccessibilityFrame =
            abs(firstImageFrame.minX - secondImageFrame.minX) < 1
            && abs(firstImageFrame.width - secondImageFrame.width) < 1
        let firstImageMidX = usesSharedAccessibilityFrame
            ? firstImageFrame.minX + firstImageFrame.width / 6
            : firstImageFrame.midX
        let firstImageCoordinate = app.coordinate(
            withNormalizedOffset: CGVector(
                dx: (firstImageMidX - appFrame.minX) / appFrame.width,
                dy: (firstImageFrame.midY - appFrame.minY) / appFrame.height
            )
        )
        let secondImageCoordinate = app.coordinate(
                withNormalizedOffset: CGVector(
                    dx: (secondImageFrame.midX - appFrame.minX) / appFrame.width,
                    dy: (secondImageFrame.midY - appFrame.minY) / appFrame.height
                )
        )

        for cycle in 1...6 {
            firstImageCoordinate.tap()
            let pager = app.descendants(matching: .any)["full-screen-image-pager"]
            XCTAssertTrue(pager.waitForExistence(timeout: 3), "第\(cycle)轮第一张图未打开")
            XCTAssertTrue(
                app.staticTexts["image-page-indicator"].waitForExistence(timeout: 2)
                    && app.staticTexts["image-page-indicator"].label == "第1张，共4张",
                "第\(cycle)轮应打开第一张图"
            )
            dismissFullScreenImageBySingleTap(in: app, timeout: 2)
            XCTAssertTrue(
                pager.waitForNonExistence(timeout: 2),
                "第\(cycle)轮第一张图的 dismissal 未完成"
            )

            // UIKit intentionally suppresses new input while a modal
            // transition is active. Start at the semantic dismissal boundary,
            // then inject exactly one physical tap with no cooldown or retry.
            secondImageCoordinate.tap()
            XCTAssertTrue(
                pager.waitForExistence(timeout: 2),
                "第\(cycle)轮返回后首次点击第二张图被丢弃"
            )
            XCTAssertTrue(
                app.staticTexts["image-page-indicator"].waitForExistence(timeout: 2)
                    && app.staticTexts["image-page-indicator"].label == "第2张，共4张",
                "第\(cycle)轮应直接打开第二张图，而不是残留第一张会话"
            )
            dismissFullScreenImageBySingleTap(in: app, timeout: 2)
            XCTAssertTrue(
                pager.waitForNonExistence(timeout: 2),
                "第\(cycle)轮第二张图的 dismissal 未完成"
            )
        }
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

    func testAboutShowsProjectAndBundledDependencyLicenses() {
        let app = launchApp()

        rootTab("我的", in: app).tap()
        XCTAssertTrue(waitForElement(named: "关于 TiebaPure", in: app, maxSwipes: 4))
        app.buttons["关于 TiebaPure"].tap()
        XCTAssertTrue(waitForLabelContaining("infinityf4p", in: app, maxSwipes: 2))
        XCTAssertTrue(waitForLabelContaining("开源与许可", in: app, maxSwipes: 4))
        XCTAssertTrue(waitForLabelContaining("GPL-3.0-only", in: app, maxSwipes: 5))
        XCTAssertTrue(waitForLabelContaining("SwiftProtobuf", in: app, maxSwipes: 5))
        XCTAssertTrue(waitForLabelContaining("Apache-2.0", in: app, maxSwipes: 5))

        let gplRow = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "GPL-3.0-only")
        ).firstMatch
        XCTAssertTrue(gplRow.waitForExistence(timeout: 3))
        gplRow.tap()
        XCTAssertTrue(waitForLabelContaining("GNU GENERAL PUBLIC LICENSE", in: app, maxSwipes: 2))

        app.navigationBars["TiebaPure-iOS"].buttons.firstMatch.tap()
        let dependencyRow = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "Apache-2.0")
        ).firstMatch
        XCTAssertTrue(dependencyRow.waitForExistence(timeout: 3))
        dependencyRow.tap()
        XCTAssertTrue(waitForLabelContaining("Apache License", in: app, maxSwipes: 2))
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

    func testSubpostPreviewSeparatesRepliesWithoutExpandingOpenAllButton() {
        let app = launchApp(scenario: "subpostReference")
        openFirstThread(in: app)

        XCTAssertTrue(waitForElement(named: "查看全部4条回复", in: app, maxSwipes: 20))
        let previewRows = app.descendants(matching: .any)
            .matching(identifier: "thread-subpost-preview-text")
            .allElementsBoundByIndex
        XCTAssertGreaterThanOrEqual(previewRows.count, 3)

        for index in 1..<3 {
            let verticalGap = previewRows[index].frame.minY - previewRows[index - 1].frame.maxY
            XCTAssertEqual(verticalGap, 8, accuracy: 1)
        }

        XCTAssertEqual(app.buttons["查看全部4条回复"].frame.height, 36, accuracy: 1)
    }

    func testSubpostPreviewAuthorAndReplyTargetOpenIndependentProfiles() {
        let app = launchApp(scenario: "subpostReference")
        openFirstThread(in: app)

        XCTAssertTrue(waitForElement(named: "查看全部4条回复", in: app, maxSwipes: 20))
        let authorLink = app.links["合成内容作者"].firstMatch
        XCTAssertTrue(authorLink.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForHittable(authorLink, expected: true, timeout: 5))

        let replyTargetLink = app.links["被回复用户"]
        XCTAssertTrue(
            replyTargetLink.waitForExistence(timeout: 5),
            "被回复用户名应保留用户链接语义"
        )
        XCTAssertTrue(waitForHittable(replyTargetLink, expected: true, timeout: 5))
        attachScreenshot(named: "fixture-subpost-preview-two-native-links")

        authorLink.tap()
        XCTAssertTrue(app.descendants(matching: .any)["user-profile-screen"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["合成内容作者"].waitForExistence(timeout: 5))
        app.navigationBars["用户主页"].buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["更多"].waitForExistence(timeout: 5))

        let restoredReplyTargetLink = app.links["被回复用户"]
        XCTAssertTrue(restoredReplyTargetLink.waitForExistence(timeout: 5))
        restoredReplyTargetLink.tap()
        XCTAssertTrue(app.descendants(matching: .any)["user-profile-screen"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["被回复用户"].waitForExistence(timeout: 5))
    }

    func testSubpostPreviewLayoutRemainsStableAfterProfileRoundTrip() {
        let app = launchApp(scenario: "subpostReference")
        openFirstThread(in: app)

        XCTAssertTrue(waitForElement(named: "查看全部4条回复", in: app, maxSwipes: 20))
        let initialRows = app.descendants(matching: .any)
            .matching(identifier: "thread-subpost-preview-text")
            .allElementsBoundByIndex
        XCTAssertGreaterThanOrEqual(initialRows.count, 3)
        let initialFrames = initialRows.prefix(3).map(\.frame)
        attachScreenshot(named: "fixture-subpost-preview-before-profile")

        let authorLink = app.links["合成内容作者"].firstMatch
        XCTAssertTrue(authorLink.waitForExistence(timeout: 5))
        authorLink.tap()
        XCTAssertTrue(app.descendants(matching: .any)["user-profile-screen"].waitForExistence(timeout: 8))
        middleSwipeRight(in: app)
        XCTAssertTrue(app.buttons["更多"].waitForExistence(timeout: 8))

        let restoredRows = app.descendants(matching: .any)
            .matching(identifier: "thread-subpost-preview-text")
            .allElementsBoundByIndex
        XCTAssertGreaterThanOrEqual(restoredRows.count, 3)
        let restoredFrames = restoredRows.prefix(3).map(\.frame)
        attachScreenshot(named: "fixture-subpost-preview-after-profile")

        for index in 0..<3 {
            XCTAssertEqual(restoredFrames[index].height, initialFrames[index].height, accuracy: 1)
            if index > 0 {
                let initialGap = initialFrames[index].minY - initialFrames[index - 1].maxY
                let restoredGap = restoredFrames[index].minY - restoredFrames[index - 1].maxY
                XCTAssertEqual(restoredGap, initialGap, accuracy: 1)
                XCTAssertEqual(restoredGap, 8, accuracy: 1)
            }
        }
    }

    func testSubpostPreviewLayoutRemainsStableAfterNativeBackRoundTrip() {
        let app = launchApp(scenario: "subpostReference")
        openFirstThread(in: app)

        XCTAssertTrue(waitForElement(named: "查看全部4条回复", in: app, maxSwipes: 20))
        let initialRows = app.descendants(matching: .any)
            .matching(identifier: "thread-subpost-preview-text")
            .allElementsBoundByIndex
        XCTAssertGreaterThanOrEqual(initialRows.count, 3)
        let initialFrames = initialRows.prefix(3).map(\.frame)

        let authorLink = app.links["合成内容作者"].firstMatch
        XCTAssertTrue(authorLink.waitForExistence(timeout: 5))
        authorLink.tap()
        XCTAssertTrue(app.descendants(matching: .any)["user-profile-screen"].waitForExistence(timeout: 8))
        app.navigationBars["用户主页"].buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["更多"].waitForExistence(timeout: 8))

        let restoredRows = app.descendants(matching: .any)
            .matching(identifier: "thread-subpost-preview-text")
            .allElementsBoundByIndex
        XCTAssertGreaterThanOrEqual(restoredRows.count, 3)
        let restoredFrames = restoredRows.prefix(3).map(\.frame)

        for index in 0..<3 {
            XCTAssertEqual(restoredFrames[index].height, initialFrames[index].height, accuracy: 1)
            if index > 0 {
                let initialGap = initialFrames[index].minY - initialFrames[index - 1].maxY
                let restoredGap = restoredFrames[index].minY - restoredFrames[index - 1].maxY
                XCTAssertEqual(restoredGap, initialGap, accuracy: 1)
                XCTAssertEqual(restoredGap, 8, accuracy: 1)
            }
        }
    }

    func testExpandedSubpostUsesSecondaryInteractiveUserNames() {
        let app = launchApp(scenario: "subpostReference")
        openFirstThread(in: app)

        XCTAssertTrue(waitForElement(named: "查看全部4条回复", in: app, maxSwipes: 20))
        app.buttons["查看全部4条回复"].tap()
        XCTAssertTrue(app.navigationBars["2楼的回复(4条)"].waitForExistence(timeout: 8))

        let authorButton = app.buttons
            .matching(identifier: "thread-user-button-1")
            .firstMatch
        XCTAssertTrue(authorButton.waitForExistence(timeout: 5))
        XCTAssertEqual(authorButton.value as? String, "灰色用户名")

        let replyText = app.descendants(matching: .any)
            .matching(identifier: "thread-subpost-text")
            .firstMatch
        XCTAssertTrue(replyText.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForHittable(replyText, expected: true, timeout: 5))
        XCTAssertTrue(
            replyText.label.contains("被回复用户") ||
                (replyText.value as? String)?.contains("被回复用户") == true
        )
        attachScreenshot(named: "fixture-expanded-subpost-secondary-usernames")

        authorButton.tap()
        XCTAssertTrue(app.descendants(matching: .any)["user-profile-screen"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["合成内容作者"].waitForExistence(timeout: 5))
        app.navigationBars["用户主页"].buttons.element(boundBy: 0).tap()

        XCTAssertTrue(app.navigationBars["2楼的回复(4条)"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.links["被回复用户"].waitForExistence(timeout: 5))
        let replyTargetLinks = app.links
            .matching(identifier: "被回复用户")
            .allElementsBoundByIndex
        let restoredReplyTargetLink = replyTargetLinks.first(where: \.isHittable)
        XCTAssertNotNil(
            restoredReplyTargetLink,
            "完整楼中楼中应有一个位于当前 sheet、可点击的被回复用户名链接"
        )
        guard let restoredReplyTargetLink else { return }
        restoredReplyTargetLink.tap()
        XCTAssertTrue(app.descendants(matching: .any)["user-profile-screen"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["被回复用户"].waitForExistence(timeout: 5))
    }

    func testExpandedSubpostUsesLabelFreeSectionDivider() {
        let app = launchApp(scenario: "subpostReference")
        openFirstThread(in: app)

        XCTAssertTrue(waitForElement(named: "查看全部4条回复", in: app, maxSwipes: 20))
        app.buttons["查看全部4条回复"].tap()
        XCTAssertTrue(app.navigationBars["2楼的回复(4条)"].waitForExistence(timeout: 8))

        let parentMetadata = app.descendants(matching: .any)["thread-subpost-parent-metadata"]
        let firstReply = app.descendants(matching: .any)
            .matching(identifier: "thread-subpost-text")
            .firstMatch

        XCTAssertTrue(parentMetadata.waitForExistence(timeout: 5))
        XCTAssertTrue(firstReply.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["层主内容"].exists)
        XCTAssertFalse(app.staticTexts["楼中楼回复"].exists)

        XCTAssertLessThan(parentMetadata.frame.maxY, firstReply.frame.minY)
        XCTAssertGreaterThanOrEqual(
            firstReply.frame.minY - parentMetadata.frame.maxY,
            12
        )
        attachScreenshot(named: "fixture-expanded-subpost-label-free-divider")
    }

    func testSubpostUserProfileRightSwipeReturnsOnlyToSubpostSheet() {
        let app = launchApp(scenario: "subpostReference")
        openFirstThread(in: app)

        XCTAssertTrue(waitForElement(named: "查看全部4条回复", in: app, maxSwipes: 20))
        app.buttons["查看全部4条回复"].tap()
        let subpostNavigationBar = app.navigationBars["2楼的回复(4条)"]
        XCTAssertTrue(subpostNavigationBar.waitForExistence(timeout: 8))

        let authorButton = app.buttons
            .matching(identifier: "thread-user-button-1")
            .firstMatch
        XCTAssertTrue(authorButton.waitForExistence(timeout: 5))
        authorButton.tap()

        let profileScreen = app.descendants(matching: .any)["user-profile-screen"]
        XCTAssertTrue(profileScreen.waitForExistence(timeout: 8))
        middleSwipeRight(in: app)

        let profileDismissed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: profileScreen
        )
        XCTAssertEqual(XCTWaiter.wait(for: [profileDismissed], timeout: 5), .completed)
        XCTAssertTrue(
            subpostNavigationBar.waitForExistence(timeout: 5),
            "楼中楼用户主页右划只能返回楼中楼，不能同时关闭楼中楼"
        )

        subpostDismissSwipeRight(in: app)
        XCTAssertFalse(subpostNavigationBar.waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["更多"].waitForExistence(timeout: 5))
    }

    func testThreadDetailTextSupportsNativeCopySelection() {
        let app = launchApp(
            scenario: "longContent",
            account: "loggedIn",
            additionalArguments: ["UITEST_RESET_CONTENT_SUBMISSION"]
        )
        openFirstThread(in: app)

        let mainText = app.descendants(matching: .any)["thread-main-text"]
        XCTAssertTrue(mainText.waitForExistence(timeout: 8))
        XCTAssertTrue(waitForHittable(mainText, expected: true, timeout: 5))
        mainText.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.2))
            .press(forDuration: 1.2)

        let copyControl = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label IN %@", ["复制", "拷贝", "Copy"]))
            .firstMatch
        XCTAssertTrue(copyControl.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForHittable(copyControl, expected: true, timeout: 5))
        copyControl.tap()
        XCTAssertFalse(app.navigationBars["回复用户"].exists, "长按复制不得触发回帖编辑器")
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
        let sheetSurface = app.descendants(matching: .any)["subpost-sheet-surface"]
        XCTAssertTrue(sheetSurface.waitForExistence(timeout: 5))
        XCTAssertEqual(
            sheetSurface.frame.maxY,
            app.frame.maxY,
            accuracy: 1,
            "楼中楼可移动表面必须覆盖底部安全区，不能露出灰色底层页面"
        )
        attachScreenshot(named: "fixture-subpost-reference-layout")

        let downwardStart = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.32))
        let downwardEnd = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.72))
        downwardStart.press(forDuration: 0.05, thenDragTo: downwardEnd)
        XCTAssertTrue(navigationBar.exists, "楼中楼下滑只能滚动内容，不应退出")

        let restingFrame = navigationBar.frame
        let parentMetadata = app.descendants(matching: .any)["thread-subpost-parent-metadata"]
        XCTAssertTrue(parentMetadata.waitForExistence(timeout: 5))
        let partialSwipeStart = parentMetadata.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)
        )
        let partialSwipeEnd = partialSwipeStart.withOffset(CGVector(dx: 56, dy: 0))
        partialSwipeStart.press(
            forDuration: 0.05,
            thenDragTo: partialSwipeEnd,
            withVelocity: 80,
            thenHoldForDuration: 0.25
        )
        XCTAssertTrue(navigationBar.waitForExistence(timeout: 3))
        XCTAssertEqual(navigationBar.frame.minY, restingFrame.minY, accuracy: 2)
        XCTAssertEqual(navigationBar.frame.minX, restingFrame.minX, accuracy: 2)

        for cycle in 0..<4 {
            if cycle > 0 {
                XCTAssertTrue(
                    waitForElement(named: "查看全部4条回复", in: app, maxSwipes: 5)
                )
                app.buttons["查看全部4条回复"].tap()
                XCTAssertTrue(navigationBar.waitForExistence(timeout: 8))
            }

            XCTAssertEqual(
                app.navigationBars.matching(identifier: "2楼的回复(4条)").count,
                1,
                "任一时刻只能存在一层楼中楼"
            )
            let swipeStart = app.coordinate(
                withNormalizedOffset: CGVector(dx: 0.35, dy: 0.45)
            )
            let swipeEnd = app.coordinate(
                withNormalizedOffset: CGVector(dx: 0.88, dy: 0.45)
            )
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
            XCTAssertEqual(
                XCTWaiter.wait(for: [dismissed], timeout: 5),
                .completed,
                "第 \(cycle + 1) 轮楼中楼应只关闭一次"
            )
            XCTAssertTrue(app.buttons["更多"].waitForExistence(timeout: 3))
        }

        attachScreenshot(named: "fixture-subpost-returned-to-thread")
    }

    func testFullScreenImageOffersDownloadAndTapReturnsToSource() {
        let app = launchApp(additionalArguments: [
            "UITEST_IMAGE_VIEWER",
            "UITEST_ZOOM_DIAGNOSTICS",
            "UITEST_IMAGE_PROGRESS_DELAY"
        ])

        let originalButton = app.buttons["view-original-image"]
        let saveButton = app.buttons["save-current-image"]
        XCTAssertTrue(originalButton.waitForExistence(timeout: 8))
        XCTAssertTrue(saveButton.waitForExistence(timeout: 8))
        let metadataLoaded = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label CONTAINS %@", "3.5MB"),
            object: originalButton
        )
        XCTAssertEqual(XCTWaiter.wait(for: [metadataLoaded], timeout: 5), .completed)
        XCTAssertTrue(originalButton.label.contains("查看原图"))
        XCTAssertEqual(saveButton.label, "下载图片")
        XCTAssertFalse(app.buttons["关闭图片"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["full-screen-image-pager"].exists)

        let zoomSurface = app.images["full-screen-image-zoom-surface-0"]
        XCTAssertTrue(zoomSurface.waitForExistence(timeout: 5))
        XCTAssertEqual(zoomSurface.value as? String, "缩放 100%")
        let zoomDiagnostics = app.descendants(matching: .any)[
            "full-screen-image-zoom-diagnostics-0"
        ]
        XCTAssertTrue(zoomDiagnostics.waitForExistence(timeout: 3))

        let exercisesUserGestureZoom = app.frame.width < 700
        if exercisesUserGestureZoom {
            zoomSurface.pinch(withScale: 1.5, velocity: 1)
            let zoomed = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "value != %@", "缩放 100%"),
                object: zoomSurface
            )
            XCTAssertEqual(XCTWaiter.wait(for: [zoomed], timeout: 5), .completed)
            XCTAssertTrue(
                app.descendants(matching: .any)["full-screen-image-pager"].exists,
                "捏合缩放不应关闭图片页"
            )
            XCTAssertFalse(app.buttons["关闭图片"].exists)

            let enlargedPercentage = Int(
                (zoomSurface.value as? String ?? "").filter(\.isNumber)
            ) ?? 100
            XCTAssertGreaterThan(enlargedPercentage, 100)
        }
        let zoomDiagnosticValue = zoomDiagnostics.value as? String ?? ""
        XCTAssertTrue(
            zoomDiagnosticValue.contains("layer=UIImageView"),
            "全屏缩放必须直接作用在 UIKit 图片层"
        )
        if exercisesUserGestureZoom {
            let firstCallback = diagnosticMetric(
                "first",
                from: zoomDiagnosticValue
            )
            XCTAssertNotNil(firstCallback)
            XCTAssertGreaterThanOrEqual(firstCallback ?? -1, 0)
            XCTAssertGreaterThan(
                diagnosticMetric("callbacks", from: zoomDiagnosticValue) ?? 0,
                0,
                "真实捏合必须持续驱动原生图片层：\(zoomDiagnosticValue)"
            )
        }

        // XCUITest intentionally emits a synthetic pinch at roughly 6–8 Hz,
        // so its 130 ms gap measures event generation rather than app latency.
        // Drive the same production zoom path at display cadence and assert
        // that each image-layer update stays within a frame budget instead.
        let renderProbe = app.descendants(matching: .any)[
            "full-screen-image-render-probe-result-0"
        ]
        XCTAssertTrue(renderProbe.waitForExistence(timeout: 3))
        let renderProbeCompleted = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value CONTAINS %@", "completed=true"),
            object: renderProbe
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [renderProbeCompleted], timeout: 5),
            .completed,
            "缩放渲染探针未完成：result=\(renderProbe.value ?? "nil")"
        )
        let renderProbeValue = renderProbe.value as? String ?? ""
        print("ZOOM_RENDER_PROBE \(renderProbeValue)")
        let maximumFramesPerSecond = diagnosticMetric(
            "maxFPS",
            from: renderProbeValue
        ) ?? 60
        let minimumExpectedFrames = Int(
            (Double(maximumFramesPerSecond) * 0.8 * 0.7).rounded(.down)
        )
        XCTAssertGreaterThanOrEqual(
            diagnosticMetric("frames", from: renderProbeValue) ?? 0,
            minimumExpectedFrames,
            "缩放渲染探针应达到设备刷新率相关门槛：\(renderProbeValue)"
        )
        let twoFrameBudgetMilliseconds = Int(ceil(
            2_000 / Double(max(maximumFramesPerSecond, 1))
        ))
        XCTAssertLessThanOrEqual(
            diagnosticMetric("p95FrameGap", from: renderProbeValue) ?? .max,
            twoFrameBudgetMilliseconds,
            "至少 95% 的缩放帧应在两帧预算内：\(renderProbeValue)"
        )
        // maxFrameGap and maxWork are deliberately printed but not asserted on.
        // Each is a max over ~49 frames, so one shared-runner scheduling hiccup
        // decides it. The p95 above is the stable gate that still catches jank.

        if exercisesUserGestureZoom {
            // The real pinch above has already enlarged the image. A single
            // double tap must therefore reset it. XCUITest cannot reliably
            // synthesize either gesture into a page-hosted scroll view on
            // iPad, where the display-cadence render probe above covers the
            // same production zoom layer instead.
            zoomSurface.coordinate(
                withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)
            ).doubleTap()
            let reset = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "value == %@", "缩放 100%"),
                object: zoomSurface
            )
            XCTAssertEqual(
                XCTWaiter.wait(for: [reset], timeout: 5),
                .completed,
                "双击缩小未完成：surface=\(zoomSurface.value ?? "nil"), diagnostics=\(zoomDiagnostics.value ?? "nil")"
            )
            XCTAssertGreaterThanOrEqual(
                diagnosticMetric(
                    "doubleTaps",
                    from: zoomDiagnostics.value as? String ?? ""
                ) ?? 0,
                1,
                "双击必须由原生缩放控制器处理：\(zoomDiagnostics.value ?? "nil")"
            )
        }

        XCTAssertTrue(originalButton.label.contains("查看原图"))
        XCTAssertTrue(originalButton.label.contains("3.5MB"))
        originalButton.tap()
        let loadingState = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label CONTAINS %@", "原图下载进度"),
            object: originalButton
        )
        XCTAssertEqual(XCTWaiter.wait(for: [loadingState], timeout: 2), .completed)
        XCTAssertTrue(
            originalButton.label.contains("%"),
            "下载进度应直接包含在 VoiceOver 可读的按钮标签中"
        )
        attachScreenshot(named: "fixture-image-viewer-original-progress")
        let originalLoaded = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", "原图已加载"),
            object: originalButton
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [originalLoaded], timeout: 5),
            .completed,
            "点击查看原图后应切换到原图已加载状态"
        )

        saveButton.tap()
        XCTAssertTrue(app.alerts["图片已保存"].waitForExistence(timeout: 5))
        app.alerts["图片已保存"].buttons["好"].tap()

        app.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.3)).tap()

        XCTAssertTrue(app.staticTexts["图片来源页"].waitForExistence(timeout: 5))

        let sourceImage = app.descendants(matching: .any)["image-viewer-source-image"]
        XCTAssertTrue(sourceImage.waitForExistence(timeout: 3))
        let sourceIsHittable = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "hittable == true"),
            object: sourceImage
        )
        XCTAssertEqual(XCTWaiter.wait(for: [sourceIsHittable], timeout: 3), .completed)
        sourceImage.tap()
        let reopened = app.descendants(matching: .any)["full-screen-image-pager"]
            .waitForExistence(timeout: 5)
        XCTAssertTrue(reopened, "缩回来源位置后应能再次从同一图片放大")
        dismissFullScreenImageBySingleTap(in: app)
        let sourceIsHittableAgain = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "hittable == true"),
            object: sourceImage
        )
        XCTAssertEqual(XCTWaiter.wait(for: [sourceIsHittableAgain], timeout: 5), .completed)
    }

    func testFullScreenImageControlsFitAtAccessibilityXXXL() {
        assertFullScreenImageControlsFit(
            contentSizeCategory: "UICTContentSizeCategoryAccessibilityXXXL",
            screenshotName: "fixture-image-viewer-controls-axxxl"
        )
    }

    func testFullScreenImageControlsFitAtXXXL() {
        assertFullScreenImageControlsFit(
            contentSizeCategory: "UICTContentSizeCategoryXXXL",
            screenshotName: "fixture-image-viewer-controls-xxxl"
        )
    }

    private func assertFullScreenImageControlsFit(
        contentSizeCategory: String,
        screenshotName: String
    ) {
        let app = launchApp(additionalArguments: [
            "UITEST_IMAGE_VIEWER",
            "-UIPreferredContentSizeCategoryName",
            contentSizeCategory
        ])
        let originalButton = app.buttons["view-original-image"]
        let downloadButton = app.buttons["save-current-image"]
        XCTAssertTrue(originalButton.waitForExistence(timeout: 8))
        XCTAssertTrue(downloadButton.waitForExistence(timeout: 8))
        XCTAssertTrue(originalButton.isHittable)
        XCTAssertTrue(downloadButton.isHittable)

        let originalFrame = originalButton.frame
        let downloadFrame = downloadButton.frame
        XCTAssertGreaterThanOrEqual(originalFrame.width, 44)
        XCTAssertGreaterThanOrEqual(originalFrame.height, 44)
        XCTAssertGreaterThanOrEqual(downloadFrame.width, 44)
        XCTAssertGreaterThanOrEqual(downloadFrame.height, 44)
        XCTAssertTrue(app.frame.insetBy(dx: 8, dy: 0).contains(originalFrame))
        XCTAssertTrue(app.frame.insetBy(dx: 8, dy: 0).contains(downloadFrame))
        XCTAssertFalse(originalFrame.intersects(downloadFrame))

        originalButton.tap()
        let loaded = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", "原图已加载"),
            object: originalButton
        )
        XCTAssertEqual(XCTWaiter.wait(for: [loaded], timeout: 5), .completed)
        XCTAssertEqual(originalButton.frame.minX, originalFrame.minX, accuracy: 1)
        XCTAssertEqual(originalButton.frame.width, originalFrame.width, accuracy: 1)
        XCTAssertEqual(downloadButton.frame.minX, downloadFrame.minX, accuracy: 1)
        XCTAssertEqual(downloadButton.frame.width, downloadFrame.width, accuracy: 1)
        attachScreenshot(named: screenshotName)
    }

    func testFullScreenImageDoubleTapZoomUsesGestureRecognizer() {
        let app = launchApp(additionalArguments: ["UITEST_IMAGE_VIEWER"])
        let zoomSurface = app.images["full-screen-image-zoom-surface-0"]
        XCTAssertTrue(zoomSurface.waitForExistence(timeout: 8))
        XCTAssertEqual(zoomSurface.value as? String, "缩放 100%")

        zoomSurface.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)
        ).doubleTap()
        let zoomed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value != %@", "缩放 100%"),
            object: zoomSurface
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [zoomed], timeout: 5),
            .completed,
            "双击必须经过真实手势识别链放大图片"
        )

        zoomSurface.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)
        ).doubleTap()
        let reset = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "缩放 100%"),
            object: zoomSurface
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [reset], timeout: 5),
            .completed,
            "第二次双击必须经过真实手势识别链复位"
        )
    }

    func testFullScreenImageRightSwipeAndVerticalDragReturnToSource() {
        let app = launchApp(additionalArguments: ["UITEST_IMAGE_VIEWER"])
        let pager = app.descendants(matching: .any)["full-screen-image-pager"]
        let zoomSurface = app.images["full-screen-image-zoom-surface-0"]
        XCTAssertTrue(pager.waitForExistence(timeout: 8))
        XCTAssertTrue(zoomSurface.waitForExistence(timeout: 5))

        let shortStart = app.coordinate(withNormalizedOffset: CGVector(dx: 0.38, dy: 0.42))
        let shortEnd = app.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.50))
        shortStart.press(forDuration: 0.2, thenDragTo: shortEnd)
        XCTAssertTrue(pager.waitForExistence(timeout: 2), "未达到阈值的斜向拖动应回弹")

        // Keep the physical x/y travel equal across device sizes. This used to
        // fall into the axis-lock dead zone and leave the image stationary.
        let downStart = app.coordinate(withNormalizedOffset: CGVector(dx: 0.20, dy: 0.35))
        let downEnd = downStart.withOffset(CGVector(dx: 240, dy: 240))
        downStart.press(forDuration: 0.1, thenDragTo: downEnd)
        XCTAssertTrue(app.staticTexts["图片来源页"].waitForExistence(timeout: 5))

        let sourceImage = app.descendants(matching: .any)["image-viewer-source-image"]
        XCTAssertTrue(sourceImage.waitForExistence(timeout: 3))
        XCTAssertTrue(waitForHittable(sourceImage, expected: true, timeout: 5))
        sourceImage.tap()
        XCTAssertTrue(pager.waitForExistence(timeout: 5))

        // Start above the bottom controls on compact screens so the image pan,
        // rather than the original-image button, owns the gesture.
        let upStart = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.30))
        let upEnd = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.04))
        upStart.press(forDuration: 0.1, thenDragTo: upEnd)
        XCTAssertTrue(app.staticTexts["图片来源页"].waitForExistence(timeout: 5))

        XCTAssertTrue(waitForHittable(sourceImage, expected: true, timeout: 5))
        sourceImage.tap()
        XCTAssertTrue(pager.waitForExistence(timeout: 5))
        let rightStart = app.coordinate(withNormalizedOffset: CGVector(dx: 0.18, dy: 0.45))
        let rightEnd = app.coordinate(withNormalizedOffset: CGVector(dx: 0.82, dy: 0.45))
        rightStart.press(forDuration: 0.1, thenDragTo: rightEnd)
        XCTAssertTrue(app.staticTexts["图片来源页"].waitForExistence(timeout: 5))
        XCTAssertFalse(pager.exists)
    }

    func testFullScreenImagePagingDoesNotConflictWithDismissGesture() {
        var app = launchApp(additionalArguments: [
            "UITEST_IMAGE_VIEWER",
            "UITEST_IMAGE_VIEWER_MULTIPLE"
        ])
        let indicator = app.staticTexts["image-page-indicator"]
        let firstSurface = app.images["full-screen-image-zoom-surface-0"]
        XCTAssertTrue(indicator.waitForExistence(timeout: 8))
        XCTAssertEqual(indicator.label, "第1张，共2张")
        XCTAssertTrue(firstSurface.waitForExistence(timeout: 5))

        firstSurface.swipeLeft()
        let secondPage = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", "第2张，共2张"),
            object: indicator
        )
        XCTAssertEqual(XCTWaiter.wait(for: [secondPage], timeout: 5), .completed)
        XCTAssertTrue(app.images["full-screen-image-zoom-surface-1"].waitForExistence(timeout: 3))

        app.images["full-screen-image-zoom-surface-1"].swipeRight()
        let firstPage = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", "第1张，共2张"),
            object: indicator
        )
        XCTAssertEqual(XCTWaiter.wait(for: [firstPage], timeout: 5), .completed)

        let rightStart = app.coordinate(withNormalizedOffset: CGVector(dx: 0.18, dy: 0.45))
        let rightEnd = app.coordinate(withNormalizedOffset: CGVector(dx: 0.82, dy: 0.45))
        rightStart.press(forDuration: 0.1, thenDragTo: rightEnd)
        XCTAssertTrue(
            app.staticTexts["图片来源页"].waitForExistence(timeout: 5),
            "多图第一页右划应退出，而不是被分页手势吞掉"
        )

        app.terminate()
        app = launchApp(additionalArguments: [
            "UITEST_IMAGE_VIEWER",
            "UITEST_IMAGE_VIEWER_MULTIPLE"
        ])
        XCTAssertTrue(
            app.staticTexts["image-page-indicator"].waitForExistence(timeout: 8)
        )
        let verticalStart = app.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)
        )
        let verticalEnd = app.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.78)
        )
        verticalStart.press(forDuration: 0.1, thenDragTo: verticalEnd)
        XCTAssertTrue(
            app.staticTexts["图片来源页"].waitForExistence(timeout: 5),
            "多图模式也应允许上下拖动退出"
        )
    }

    func testRemoteImageReplacesBitmapWhenReusableViewChangesURL() {
        let app = launchApp(additionalArguments: ["UITEST_REMOTE_IMAGE_REUSE"])
        let surface = app.descendants(matching: .any)["remote-image-reuse-surface"]
        let state = app.staticTexts["remote-image-reuse-state"]
        XCTAssertTrue(surface.waitForExistence(timeout: 5))
        XCTAssertTrue(state.waitForExistence(timeout: 5))

        let loadedA = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", "已加载 A"),
            object: state
        )
        XCTAssertEqual(XCTWaiter.wait(for: [loadedA], timeout: 5), .completed)
        let imageA = surface.screenshot().image.pngData()

        app.buttons["remote-image-reuse-switch"].tap()
        let loadedB = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", "已加载 B"),
            object: state
        )
        XCTAssertEqual(XCTWaiter.wait(for: [loadedB], timeout: 5), .completed)
        let imageB = surface.screenshot().image.pngData()

        XCTAssertNotEqual(
            imageA,
            imageB,
            "同一个列表图片视图换成新 URL 后必须替换位图，不能继续显示旧图片"
        )
    }

    func testManualRemoteImageAuthorizationDoesNotLeakAcrossReusedURL() {
        let app = launchApp(additionalArguments: [
            "UITEST_REMOTE_IMAGE_REUSE",
            "UITEST_REMOTE_IMAGE_REUSE_MANUAL"
        ])
        let state = app.staticTexts["remote-image-reuse-state"]
        let load = app.buttons["remote-image-reuse-load"]
        XCTAssertTrue(state.waitForExistence(timeout: 5))
        XCTAssertEqual(state.label, "等待加载 A")

        load.tap()
        let loadedA = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", "已加载 A"),
            object: state
        )
        XCTAssertEqual(XCTWaiter.wait(for: [loadedA], timeout: 5), .completed)

        app.buttons["remote-image-reuse-switch"].tap()
        XCTAssertEqual(state.label, "等待加载 B")
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        XCTAssertEqual(
            state.label,
            "等待加载 B",
            "加载 A 的手动授权不得在同一复用视图换成 B 后继续生效"
        )

        load.tap()
        let loadedB = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", "已加载 B"),
            object: state
        )
        XCTAssertEqual(XCTWaiter.wait(for: [loadedB], timeout: 5), .completed)
    }

    func testDataSavingImageFailureAllowsExplicitOriginalFallback() {
        let app = launchApp(additionalArguments: [
            "UITEST_READER_MEDIA_POLICY",
            "UITEST_READING_MEDIA_DATA_SAVING"
        ])
        let image = app.descendants(matching: .any)["thread-inline-image"]
        XCTAssertTrue(image.waitForExistence(timeout: 5))
        let failedPreview = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", "图片预览加载失败，加载原图"),
            object: image
        )
        XCTAssertEqual(XCTWaiter.wait(for: [failedPreview], timeout: 5), .completed)

        image.tap()
        let loadedOriginal = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label BEGINSWITH %@", "查看"),
            object: image
        )
        XCTAssertEqual(XCTWaiter.wait(for: [loadedOriginal], timeout: 5), .completed)
        image.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["full-screen-image-pager"]
                .waitForExistence(timeout: 8)
        )
        XCTAssertFalse(app.buttons["关闭图片"].exists)
    }

    func testManualVideoCoverFailureStillAllowsPlayback() {
        let app = launchApp(additionalArguments: [
            "UITEST_READER_MEDIA_POLICY",
            "UITEST_READING_MEDIA_MANUAL"
        ])
        let video = app.buttons["加载视频封面"]
        XCTAssertTrue(video.waitForExistence(timeout: 5))
        video.tap()

        let failedCover = app.buttons["播放视频，封面加载失败"]
        XCTAssertTrue(failedCover.waitForExistence(timeout: 5))
        failedCover.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["full-screen-video-player"]
                .waitForExistence(timeout: 5)
        )
    }

    func testAutomaticVideoCoverFailureDoesNotBlockMediaDestinations() {
        let app = launchApp(additionalArguments: ["UITEST_READER_MEDIA_POLICY"])

        let video = app.buttons["播放视频，封面加载失败"]
        XCTAssertTrue(video.waitForExistence(timeout: 5))
        for cycle in 1...2 {
            video.tap()
            let player = app.descendants(matching: .any)["full-screen-video-player"]
            XCTAssertTrue(
                player.waitForExistence(timeout: 5),
                "无封面视频第\(cycle)次没有打开"
            )
            player.swipeDown(velocity: .slow)
            XCTAssertTrue(
                waitForHittable(video, expected: true, timeout: 5),
                "无封面视频第\(cycle)次退出后没有立即恢复交互"
            )
        }

        let gridVideo = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "测试视频，封面加载失败")
        ).firstMatch
        XCTAssertTrue(gridVideo.waitForExistence(timeout: 5))
        gridVideo.tap()
        XCTAssertTrue(
            app.staticTexts["reader-media-grid-action"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertEqual(
            app.staticTexts["reader-media-grid-action"].label,
            "已打开媒体网格目标"
        )
    }

    func testVideoPreviewReturnsToItsCoverAndCanReopenImmediately() {
        let app = launchApp(additionalArguments: [
            "UITEST_READER_MEDIA_POLICY",
            "UITEST_VIDEO_PREVIEW_HERO"
        ])
        let video = app.buttons["播放视频"]
        XCTAssertTrue(video.waitForExistence(timeout: 8))
        XCTAssertTrue(waitForHittable(video, expected: true, timeout: 5))
        guard let initialFrame = waitForStableFrame(of: video) else {
            return XCTFail("视频封面初始布局没有稳定")
        }

        for cycle in 1...2 {
            video.tap()
            let player = app.descendants(matching: .any)["full-screen-video-player"]
            XCTAssertTrue(
                player.waitForExistence(timeout: 5),
                "第\(cycle)次没有打开全屏视频"
            )
            let failure = app.descendants(matching: .any)["video-playback-failure"]
            XCTAssertTrue(
                failure.waitForExistence(timeout: 5),
                "DEBUG 视频夹具没有进入可重试的失败态"
            )
            XCTAssertFalse(
                app.descendants(matching: .any)["video-loading-indicator"].exists,
                "视频失败后加载指示器仍在显示"
            )
            player.swipeDown(velocity: .slow)
            XCTAssertTrue(
                waitForHittable(video, expected: true, timeout: 5),
                "第\(cycle)次关闭后视频封面没有恢复交互"
            )
            guard let restoredFrame = waitForStableFrame(of: video) else {
                return XCTFail("第\(cycle)次关闭后视频封面布局没有稳定")
            }
            XCTAssertEqual(restoredFrame.minX, initialFrame.minX, accuracy: 1)
            XCTAssertEqual(restoredFrame.minY, initialFrame.minY, accuracy: 1)
            XCTAssertEqual(restoredFrame.width, initialFrame.width, accuracy: 1)
            XCTAssertEqual(restoredFrame.height, initialFrame.height, accuracy: 1)
        }
    }

    func testFullScreenImageTransitionHandlesCroppedThumbnailAndOriginalRatio() {
        let arguments = [
            "UITEST_IMAGE_VIEWER",
            "UITEST_IMAGE_VIEWER_CROPPED_THUMBNAIL"
        ]
        let app = launchApp(additionalArguments: arguments)

        XCTAssertTrue(app.descendants(matching: .any)["full-screen-image-pager"]
            .waitForExistence(timeout: 8))
        dismissFullScreenImageBySingleTap(in: app)

        let sourceImage = app.descendants(matching: .any)["image-viewer-source-image"]
        XCTAssertTrue(sourceImage.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForHittable(sourceImage, expected: true, timeout: 5))
        sourceImage.tap()
        XCTAssertTrue(app.descendants(matching: .any)["full-screen-image-pager"]
            .waitForExistence(timeout: 5))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.3)).tap()
        XCTAssertTrue(sourceImage.waitForExistence(timeout: 5))
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

        let openArea = app.descendants(matching: .any)
            .matching(identifier: "thread-open-area")
            .firstMatch
        XCTAssertTrue(openArea.waitForExistence(timeout: 8))
        openArea.tap()
        XCTAssertTrue(app.buttons["更多"].waitForExistence(timeout: 8))
        XCTAssertTrue(waitForElement(named: "全部回复", in: app, maxSwipes: 30))
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
        XCTAssertTrue(waitForHittable(rootTab("首页", in: app), expected: true, timeout: 5))
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
        XCTAssertTrue(waitForHittable(rootTab("首页", in: app), expected: true, timeout: 5))
    }

    func testFollowedForumWholeRowNavigatesWithoutGestureConflict() {
        let app = launchApp(account: "loggedIn")
        rootTab("我的", in: app).tap()
        XCTAssertTrue(app.buttons["关注的吧"].waitForExistence(timeout: 8))
        app.buttons["关注的吧"].tap()
        XCTAssertTrue(app.navigationBars["关注的吧"].waitForExistence(timeout: 8))

        let row = app.buttons.matching(identifier: "followed-forum-row").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 8))
        row.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap()

        XCTAssertTrue(app.navigationBars["测试吧"].waitForExistence(timeout: 8))
        XCTAssertTrue(threadRows(in: app).firstMatch.waitForExistence(timeout: 8))

        middleSwipeRight(in: app)
        XCTAssertTrue(
            app.navigationBars["关注的吧"].waitForExistence(timeout: 5),
            "关注吧进入贴吧后右划只能返回关注吧列表"
        )
        middleSwipeRight(in: app)
        XCTAssertTrue(app.navigationBars["我的"].waitForExistence(timeout: 5))
    }

    func testAppearanceSettingWorksForGuestAndPersistsAcrossRelaunch() {
        let expectedSystemAppearance = UITraitCollection.current.userInterfaceStyle == .dark
            ? "深色"
            : "浅色"
        var app = launchApp()
        rootTab("我的", in: app).tap()

        let settingsEntry = app.descendants(matching: .any)["app-settings-entry"]
        XCTAssertTrue(settingsEntry.waitForExistence(timeout: 8))
        XCTAssertTrue(waitForHittable(settingsEntry, expected: true, timeout: 5))
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

    func testReadingSettingsPersistAndApplyToNewThreadAndManualMedia() {
        var app = launchApp(scenario: "imageGesture")
        rootTab("我的", in: app).tap()

        let settingsEntry = app.descendants(matching: .any)["app-settings-entry"]
        XCTAssertTrue(revealBySwipingUp(settingsEntry, in: app, maxSwipes: 8))
        settingsEntry.tap()
        XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout: 8))

        let readingEntry = app.buttons["settings-reading-entry"]
        XCTAssertTrue(revealBySwipingUp(readingEntry, in: app, maxSwipes: 4))
        readingEntry.tap()
        XCTAssertTrue(app.navigationBars["阅读设置"].waitForExistence(timeout: 8))

        let extraLarge = pickerOption(
            "特大",
            identifier: "reading-font-size-picker",
            in: app
        )
        let relaxed = pickerOption(
            "宽松",
            identifier: "reading-line-spacing-picker",
            in: app
        )
        XCTAssertTrue(revealBySwipingUp(extraLarge, in: app, maxSwipes: 2))
        extraLarge.tap()
        XCTAssertTrue(revealBySwipingUp(relaxed, in: app, maxSwipes: 2))
        relaxed.tap()
        XCTAssertTrue(app.descendants(matching: .any)["reading-typography-preview"].exists)

        let replySortPicker = app.segmentedControls["reading-reply-sort-picker"]
        XCTAssertTrue(revealBySwipingUp(replySortPicker, in: app, maxSwipes: 4))
        let descending = replySortPicker.buttons["倒序"]
        XCTAssertTrue(descending.waitForExistence(timeout: 2))
        descending.tap()

        let manual = pickerOption(
            "手动加载",
            identifier: "reading-media-loading-picker",
            exactLabel: false,
            in: app
        )
        XCTAssertTrue(revealBySwipingUp(manual, in: app, maxSwipes: 4))
        manual.tap()

        app.terminate()
        app = launchApp(
            scenario: "imageGesture",
            resetReadingPreferences: false
        )
        rootTab("我的", in: app).tap()
        let persistedSettingsEntry = app.descendants(matching: .any)["app-settings-entry"]
        XCTAssertTrue(revealBySwipingUp(persistedSettingsEntry, in: app, maxSwipes: 8))
        persistedSettingsEntry.tap()
        let persistedReadingEntry = app.buttons["settings-reading-entry"]
        XCTAssertTrue(revealBySwipingUp(persistedReadingEntry, in: app, maxSwipes: 4))
        persistedReadingEntry.tap()
        XCTAssertTrue(app.navigationBars["阅读设置"].waitForExistence(timeout: 8))
        let persistedExtraLarge = pickerOption(
            "特大",
            identifier: "reading-font-size-picker",
            in: app
        )
        XCTAssertTrue(revealBySwipingUp(persistedExtraLarge, in: app, maxSwipes: 2))
        XCTAssertTrue(persistedExtraLarge.isSelected)
        let persistedRelaxed = pickerOption(
            "宽松",
            identifier: "reading-line-spacing-picker",
            in: app
        )
        XCTAssertTrue(revealBySwipingUp(persistedRelaxed, in: app, maxSwipes: 2))
        XCTAssertTrue(persistedRelaxed.isSelected)
        let persistedReplySortPicker = app.segmentedControls["reading-reply-sort-picker"]
        XCTAssertTrue(revealBySwipingUp(persistedReplySortPicker, in: app, maxSwipes: 4))
        XCTAssertTrue(persistedReplySortPicker.buttons["倒序"].isSelected)
        let persistedManual = pickerOption(
            "手动加载",
            identifier: "reading-media-loading-picker",
            exactLabel: false,
            in: app
        )
        XCTAssertTrue(revealBySwipingUp(persistedManual, in: app, maxSwipes: 4))
        XCTAssertTrue(persistedManual.isSelected)

        rootTab("首页", in: app).tap()
        openFirstThread(in: app)
        let descendingSort = app.buttons["thread-reply-sort-1"]
        XCTAssertTrue(revealBySwipingUp(descendingSort, in: app, maxSwipes: 8))
        XCTAssertEqual(descendingSort.value as? String, "已选择")

        let inlineImage = visibleThreadInlineImage(in: app, searchingTowardTop: true)
        XCTAssertNotNil(inlineImage)
        XCTAssertEqual(inlineImage?.label, "加载图片")
        inlineImage?.tap()
        let loaded = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label BEGINSWITH %@", "查看"),
            object: inlineImage
        )
        XCTAssertEqual(XCTWaiter.wait(for: [loaded], timeout: 5), .completed)
        inlineImage?.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["full-screen-image-pager"]
                .waitForExistence(timeout: 8)
        )
        dismissFullScreenImageBySingleTap(in: app)

        // A saved reading position must still restore in deterministic floor
        // order even when the persisted default for new threads is descending.
        app.terminate()
        app = launchApp(
            scenario: "imageGesture",
            account: "loggedIn",
            additionalArguments: [
                "UITEST_SEED_LOCAL_THREAD_LIBRARY",
                "UITEST_SEED_ACCOUNT_COLLECTION"
            ],
            resetReadingPreferences: false
        )
        rootTab("我的", in: app).tap()
        let favoritesEntry = app.buttons["thread-favorites-entry"]
        XCTAssertTrue(revealBySwipingUp(favoritesEntry, in: app, maxSwipes: 8))
        favoritesEntry.tap()
        let favoriteRow = app.buttons["thread-favorite-row-1001"]
        XCTAssertTrue(favoriteRow.waitForExistence(timeout: 8))
        favoriteRow.tap()
        XCTAssertTrue(app.otherElements["restored-reading-banner"].waitForExistence(timeout: 5))
        let returnToTop = app.buttons["restored-reading-return-top"]
        XCTAssertTrue(returnToTop.waitForExistence(timeout: 5))
        returnToTop.tap()
        let ascendingSort = app.buttons["thread-reply-sort-0"]
        XCTAssertTrue(revealBySwipingUp(ascendingSort, in: app, maxSwipes: 8))
        XCTAssertEqual(ascendingSort.value as? String, "已选择")
    }

    func testFailedInlineImageRetryDoesNotOpenOrClosePreview() {
        let app = launchApp(scenario: "longContent")
        openFirstThread(in: app)

        let retry = buttonLabelContaining("图片加载失败", in: app, maxSwipes: 20)
        XCTAssertNotNil(retry)
        retry?.tap()

        XCTAssertFalse(app.descendants(matching: .any)["full-screen-image-pager"].exists)
        XCTAssertTrue(app.buttons["更多"].exists)
    }

    func testEmptyFilteredSearchKeepsControlsAvailable() {
        let app = launchApp()
        let searchField = openGlobalSearch(in: app)
        searchField.typeText("仅回复命中")
        searchField.typeText("\n")
        XCTAssertTrue(threadRows(in: app).firstMatch.waitForExistence(timeout: 8))

        let topicFilter = app.segmentedControls.buttons["主题"]
        XCTAssertTrue(waitForHittable(topicFilter, expected: true, timeout: 5))
        topicFilter.tap()
        XCTAssertTrue(app.staticTexts["没有结果"].waitForExistence(timeout: 8))

        let allFilter = app.segmentedControls.buttons["全部"]
        XCTAssertTrue(allFilter.exists)
        XCTAssertTrue(waitForHittable(allFilter, expected: true, timeout: 5))
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
        XCTAssertTrue(waitForHittable(link, expected: true, timeout: 5))
    }

    func testReplyFirstLineGlyphsRemainVisibleAfterScrollReuse() {
        let app = launchApp(scenario: "textClipping")
        openFirstThread(in: app)

        attachScreenshot(named: "text-clipping-top")
        let expectedReplies = [
            "翻译这段回复",
            "A\u{0301} E\u{0302} Ü",
            "A\u{0301}\u{0307}",
            "ภาษาไทย မြန်မာ",
            "首行含贴吧表情",
            "首行包含可点击用户名",
            "多行回复用于触发"
        ]
        let replyQuery = app.descendants(matching: .any).matching(identifier: "thread-reply-text")
        let visibleFrame = app.windows.firstMatch.frame

        for (index, fragment) in expectedReplies.enumerated() {
            let reply = replyQuery.matching(
                NSPredicate(
                    format: "label CONTAINS %@ OR value CONTAINS %@",
                    fragment,
                    fragment
                )
            ).firstMatch
            for _ in 0..<16 {
                if reply.exists, reply.frame.intersects(visibleFrame) { break }
                app.swipeUp()
            }
            XCTAssertTrue(reply.exists, "未找到回复夹具：\(fragment)")
            XCTAssertTrue(reply.frame.intersects(visibleFrame), "回复未滚动到可见区域：\(fragment)")
            XCTAssertGreaterThan(reply.frame.height, 0)
            attachScreenshot(named: "text-clipping-reply-\(index + 1)")
            assertRenderedTextContainsInk(
                reply,
                context: "回复夹具 \(fragment)"
            )
        }

        for _ in 0..<8 {
            app.swipeDown()
        }
        let reusedReply = replyQuery.matching(
            NSPredicate(
                format: "label CONTAINS %@ OR value CONTAINS %@",
                expectedReplies.last!,
                expectedReplies.last!
            )
        ).firstMatch
        for _ in 0..<20 {
            if reusedReply.exists, reusedReply.frame.intersects(visibleFrame) { break }
            app.swipeUp()
        }
        attachScreenshot(named: "text-clipping-after-reuse")
        XCTAssertTrue(reusedReply.exists)
        XCTAssertTrue(reusedReply.frame.intersects(visibleFrame))
        XCTAssertGreaterThan(reusedReply.frame.height, 0)
        assertRenderedTextContainsInk(
            reusedReply,
            context: "离屏复用后的末条回复"
        )
    }

    private func assertRenderedTextContainsInk(
        _ element: XCUIElement,
        context: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let image = element.screenshot().image
        guard let cgImage = image.cgImage,
              let providerData = cgImage.dataProvider?.data,
              let bytes = CFDataGetBytePtr(providerData) else {
            XCTFail("\(context)：无法读取文字截图像素", file: file, line: line)
            return
        }

        let width = cgImage.width
        let height = cgImage.height
        let bytesPerPixel = cgImage.bitsPerPixel / 8
        guard width > 2, height > 2, bytesPerPixel >= 3 else {
            XCTFail("\(context)：文字截图像素格式异常", file: file, line: line)
            return
        }

        func components(x: Int, y: Int) -> (Int, Int, Int) {
            let offset = y * cgImage.bytesPerRow + x * bytesPerPixel
            return (
                Int(bytes[offset]),
                Int(bytes[offset + 1]),
                Int(bytes[offset + 2])
            )
        }

        let firstBackground = components(x: 0, y: 0)
        let secondBackground = components(x: width - 1, y: 0)
        let background = (
            (firstBackground.0 + secondBackground.0) / 2,
            (firstBackground.1 + secondBackground.1) / 2,
            (firstBackground.2 + secondBackground.2) / 2
        )

        var firstInkRow: Int?
        rowSearch: for y in 0..<height {
            for x in 0..<width {
                let pixel = components(x: x, y: y)
                let distance = abs(pixel.0 - background.0)
                    + abs(pixel.1 - background.1)
                    + abs(pixel.2 - background.2)
                if distance >= 90 {
                    firstInkRow = y
                    break rowSearch
                }
            }
        }

        guard let firstInkRow else {
            XCTFail("\(context)：截图中没有检测到文字像素", file: file, line: line)
            return
        }
        XCTAssertLessThan(
            firstInkRow,
            height,
            "\(context)：实际文字没有出现在元素截图内",
            file: file,
            line: line
        )
    }

    private func assertScreenshotsVisuallyMatch(
        _ expected: UIImage,
        _ actual: UIImage,
        context: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let expectedImage = expected.cgImage,
              let rawActualImage = actual.cgImage else {
            XCTFail("\(context)：无法读取截图", file: file, line: line)
            return
        }
        let widthDelta = abs(expectedImage.width - rawActualImage.width)
        let heightDelta = abs(expectedImage.height - rawActualImage.height)
        guard widthDelta <= 2, heightDelta <= 2 else {
            XCTFail(
                "\(context)：截图尺寸明显变化（"
                    + "\(expectedImage.width)×\(expectedImage.height) → "
                    + "\(rawActualImage.width)×\(rawActualImage.height)）",
                file: file,
                line: line
            )
            return
        }
        let actualImage: CGImage
        if widthDelta == 0, heightDelta == 0 {
            actualImage = rawActualImage
        } else {
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            guard let rendererContext = CGContext(
                data: nil,
                width: expectedImage.width,
                height: expectedImage.height,
                bitsPerComponent: 8,
                bytesPerRow: expectedImage.width * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                XCTFail("\(context)：无法统一截图像素尺寸", file: file, line: line)
                return
            }
            rendererContext.interpolationQuality = .high
            rendererContext.draw(
                rawActualImage,
                in: CGRect(
                    x: 0,
                    y: 0,
                    width: expectedImage.width,
                    height: expectedImage.height
                )
            )
            guard let normalizedImage = rendererContext.makeImage() else {
                XCTFail("\(context)：无法生成同尺寸截图", file: file, line: line)
                return
            }
            actualImage = normalizedImage
        }
        guard
              let expectedData = expectedImage.dataProvider?.data,
              let actualData = actualImage.dataProvider?.data,
              let expectedBytes = CFDataGetBytePtr(expectedData),
              let actualBytes = CFDataGetBytePtr(actualData) else {
            XCTFail("\(context)：无法读取同尺寸截图", file: file, line: line)
            return
        }

        let expectedBytesPerPixel = expectedImage.bitsPerPixel / 8
        let actualBytesPerPixel = actualImage.bitsPerPixel / 8
        guard expectedBytesPerPixel >= 3, actualBytesPerPixel >= 3 else {
            XCTFail("\(context)：截图像素格式异常", file: file, line: line)
            return
        }

        var differenceTotal = 0
        var changedPixelCount = 0
        var sampledPixelCount = 0
        for y in stride(from: 0, to: expectedImage.height, by: 2) {
            for x in stride(from: 0, to: expectedImage.width, by: 2) {
                let expectedOffset = y * expectedImage.bytesPerRow + x * expectedBytesPerPixel
                let actualOffset = y * actualImage.bytesPerRow + x * actualBytesPerPixel
                let difference = (0..<3).reduce(0) { result, component in
                    result + abs(
                        Int(expectedBytes[expectedOffset + component])
                            - Int(actualBytes[actualOffset + component])
                    )
                }
                differenceTotal += difference
                changedPixelCount += difference >= 60 ? 1 : 0
                sampledPixelCount += 1
            }
        }

        let meanDifference = Double(differenceTotal) / Double(max(sampledPixelCount * 3, 1))
        let changedFraction = Double(changedPixelCount) / Double(max(sampledPixelCount, 1))
        XCTAssertLessThan(meanDifference, 8, "\(context)：平均像素偏差过大", file: file, line: line)
        XCTAssertLessThan(changedFraction, 0.08, "\(context)：图片内容出现明显错位", file: file, line: line)
    }

    func testReduceMotionKeepsRefreshIndicatorStatic() throws {
        guard UIAccessibility.isReduceMotionEnabled else {
            throw XCTSkip("仅在已启用 Reduce Motion 的设备矩阵中运行。")
        }
        let app = launchApp(
            additionalArguments: ["UITEST_EXTENDED_REFRESH_ANIMATION"]
        )
        let firstRow = threadRows(in: app).firstMatch
        XCTAssertTrue(firstRow.waitForExistence(timeout: 8))

        let start = firstRow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15))
        let end = firstRow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 1.35))
        start.press(forDuration: 0.1, thenDragTo: end)

        let indicator = app.descendants(matching: .any)["home-refresh-animation"]
        XCTAssertTrue(
            indicator.waitForExistence(timeout: 2),
            "Reduce Motion 下仍应显示与下拉阶段相同的灰色加载符号"
        )
        let initialFrame = indicator.frame
        let initialImage = indicator.screenshot().image
        RunLoop.current.run(until: Date().addingTimeInterval(0.35))
        XCTAssertEqual(indicator.frame, initialFrame, "Reduce Motion 下加载符号不得位移")
        assertScreenshotsVisuallyMatch(
            initialImage,
            indicator.screenshot().image,
            context: "Reduce Motion 下加载符号应保持静态"
        )
    }

    func testForumListMediaOpensPreviewAndWholeRowOpensThread() {
        let app = launchApp(scenario: "forumPinned")
        rootTab("进吧", in: app).tap()
        let forumField = app.textFields["输入吧名"]
        XCTAssertTrue(forumField.waitForExistence(timeout: 8))
        forumField.tap()
        forumField.typeText("测试\n")

        XCTAssertTrue(app.navigationBars["测试吧"].waitForExistence(timeout: 8))
        XCTAssertFalse(
            app.searchFields.firstMatch.exists,
            "吧页不应再显示顶部搜索栏"
        )
        XCTAssertTrue(app.buttons["搜索本吧"].exists)
        XCTAssertTrue(waitForHittable(app.buttons["搜索本吧"], expected: true, timeout: 5))
        XCTAssertTrue(app.buttons["forum-more-menu"].exists)
        XCTAssertTrue(waitForHittable(app.buttons["forum-more-menu"], expected: true, timeout: 5))

        let pinnedThread = app.buttons["默认折叠的置顶测试帖"]
        XCTAssertFalse(pinnedThread.exists, "置顶内容默认必须折叠")
        let pinnedToggle = app.buttons["forum-pinned-threads-toggle"]
        XCTAssertTrue(pinnedToggle.waitForExistence(timeout: 5))
        XCTAssertEqual(pinnedToggle.label, "展开1条置顶内容")
        pinnedToggle.tap()
        XCTAssertTrue(pinnedThread.waitForExistence(timeout: 5))
        XCTAssertEqual(pinnedToggle.label, "收起1条置顶内容")
        pinnedToggle.tap()
        XCTAssertTrue(pinnedThread.waitForNonExistence(timeout: 5))

        let row = threadRows(in: app).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 8))
        let media = app.buttons["media-item-image-1001-1"]
        XCTAssertTrue(media.waitForExistence(timeout: 5))
        XCTAssertTrue(
            media.label.hasPrefix("帖子图片"),
            "吧页媒体点开的是图片，VoiceOver 不能再说要进入帖子"
        )
        media.tap()
        let pager = app.descendants(matching: .any)["full-screen-image-pager"]
        XCTAssertTrue(pager.waitForExistence(timeout: 8), "吧页点击图片应打开全屏预览")
        dismissFullScreenImageBySingleTap(in: app)
        XCTAssertTrue(pager.waitForNonExistence(timeout: 5))

        row.tap()
        XCTAssertTrue(app.buttons["更多"].waitForExistence(timeout: 8))
    }

    func testForumManualMediaLoadsBeforeOpeningPreview() {
        let app = launchApp(
            scenario: "imageGesture",
            additionalArguments: ["UITEST_READING_MEDIA_MANUAL"]
        )
        rootTab("进吧", in: app).tap()
        let forumField = app.textFields["输入吧名"]
        XCTAssertTrue(forumField.waitForExistence(timeout: 8))
        forumField.tap()
        forumField.typeText("测试\n")
        XCTAssertTrue(app.navigationBars["测试吧"].waitForExistence(timeout: 8))

        let media = app.buttons["media-item-image-1001-1"]
        XCTAssertTrue(media.waitForExistence(timeout: 8))
        XCTAssertTrue(media.label.hasPrefix("加载帖子图片"))
        media.tap()
        XCTAssertTrue(app.navigationBars["测试吧"].exists)
        XCTAssertFalse(app.buttons["thread-favorite-button"].exists)

        let loaded = XCTNSPredicateExpectation(
            predicate: NSPredicate(
                format: "NOT (label BEGINSWITH %@) AND NOT (label BEGINSWITH %@)",
                "加载帖子图片",
                "正在加载帖子图片"
            ),
            object: media
        )
        XCTAssertEqual(XCTWaiter.wait(for: [loaded], timeout: 5), .completed)
        XCTAssertTrue(media.label.hasPrefix("帖子图片"))
        media.tap()
        let pager = app.descendants(matching: .any)["full-screen-image-pager"]
        XCTAssertTrue(pager.waitForExistence(timeout: 8), "加载完成后点击图片应打开全屏预览")
        dismissFullScreenImageBySingleTap(in: app)
        XCTAssertTrue(pager.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["测试吧"].exists)
    }

    func testForumLatestMenuSwitchesReplyPublishAndFeaturedCategories() {
        let app = launchApp(scenario: "forumCategories")
        rootTab("进吧", in: app).tap()
        let forumField = app.textFields["输入吧名"]
        XCTAssertTrue(forumField.waitForExistence(timeout: 8))
        forumField.tap()
        forumField.typeText("测试\n")

        XCTAssertTrue(app.navigationBars["测试吧"].waitForExistence(timeout: 8))
        let latestMenu = app.buttons["forum-category-latest-menu"]
        let featured = app.descendants(matching: .any)["forum-category-featured"]
        for control in [latestMenu, featured] {
            XCTAssertTrue(control.waitForExistence(timeout: 5))
            XCTAssertTrue(waitForHittable(control, expected: true, timeout: 5))
            XCTAssertGreaterThanOrEqual(control.frame.height, 44)
        }
        let categoryPicker = app.otherElements["forum-category-picker"]
        XCTAssertTrue(categoryPicker.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(categoryPicker.frame.height, 44)
        XCTAssertLessThanOrEqual(
            categoryPicker.frame.height,
            46,
            "默认字号下分类栏应保持紧凑，不再占据大块竖向空间"
        )

        XCTAssertTrue(
            app.buttons["回复时间分类测试帖"].waitForExistence(timeout: 8),
            "吧页首次进入应默认按回复时间加载最新页签"
        )
        XCTAssertTrue(
            app.staticTexts["刚刚回复"].waitForExistence(timeout: 5),
            "回复时间排序应明确展示最后回复时间"
        )

        let forumScrollView = app.scrollViews["forum-threads-scroll-view"]
        XCTAssertTrue(forumScrollView.waitForExistence(timeout: 5))
        forumScrollView.swipeUp()
        XCTAssertTrue(
            waitForHittable(latestMenu, expected: false, timeout: 5),
            "最新分类应随帖子列表上滑离开可视区域"
        )
        XCTAssertTrue(
            waitForHittable(featured, expected: false, timeout: 5),
            "精华分类应随帖子列表上滑离开可视区域"
        )
        forumScrollView.swipeDown()
        XCTAssertTrue(
            waitForHittable(latestMenu, expected: true, timeout: 5),
            "回到顶部后应重新显示最新分类"
        )
        XCTAssertTrue(
            waitForHittable(featured, expected: true, timeout: 5),
            "回到顶部后应重新显示精华分类"
        )

        latestMenu.tap()
        let publishTime = app.buttons["发帖时间排序"]
        XCTAssertTrue(publishTime.waitForExistence(timeout: 5))
        publishTime.tap()
        XCTAssertTrue(
            app.buttons["发帖时间分类测试帖"].waitForExistence(timeout: 8),
            "最新菜单选择发帖时间后应提交并展示对应响应"
        )
        XCTAssertTrue(
            app.staticTexts["12分钟前发布"].waitForExistence(timeout: 5),
            "发帖时间排序应展示创建时间而不是最后回复时间"
        )
        XCTAssertFalse(app.buttons["回复时间分类测试帖"].exists)

        featured.tap()
        XCTAssertTrue(
            app.buttons["精华分类测试帖"].waitForExistence(timeout: 8),
            "切换到精华后应提交并展示精华分类响应"
        )
        XCTAssertFalse(app.buttons["发帖时间分类测试帖"].exists)

        latestMenu.tap()
        let replyTime = app.buttons["回复时间排序"]
        XCTAssertTrue(replyTime.waitForExistence(timeout: 5))
        replyTime.tap()
        XCTAssertTrue(
            app.buttons["回复时间分类测试帖"].waitForExistence(timeout: 8),
            "从精华返回最新并选择回复时间后应恢复对应内容"
        )
        XCTAssertFalse(app.buttons["精华分类测试帖"].exists)
    }

    func testForumCategoryRaceKeepsOnlyLatestSelection() {
        let app = launchApp(scenario: "forumCategoryRace")
        rootTab("进吧", in: app).tap()
        let forumField = app.textFields["输入吧名"]
        XCTAssertTrue(forumField.waitForExistence(timeout: 8))
        forumField.tap()
        forumField.typeText("测试\n")

        XCTAssertTrue(app.navigationBars["测试吧"].waitForExistence(timeout: 8))
        let latestMenu = app.buttons["forum-category-latest-menu"]
        let featured = app.descendants(matching: .any)["forum-category-featured"]
        XCTAssertTrue(latestMenu.waitForExistence(timeout: 5))
        XCTAssertTrue(featured.waitForExistence(timeout: 5))

        // Initial 回复时间 is deliberately slow; 发帖时间 is slower than精华.
        // The final selection must win even when both cancelled responses arrive.
        latestMenu.tap()
        let publishTime = app.buttons["发帖时间排序"]
        XCTAssertTrue(publishTime.waitForExistence(timeout: 5))
        publishTime.tap()
        XCTAssertTrue(
            publishTime.waitForNonExistence(timeout: 3),
            "系统排序菜单应先完成收起，再点击底层精华分类"
        )
        XCTAssertTrue(waitForHittable(featured, expected: true, timeout: 5))
        featured.tap()
        XCTAssertTrue(
            app.buttons["精华分类测试帖"].waitForExistence(timeout: 5),
            "快速切换后应先提交最终选择的精华响应"
        )
        RunLoop.current.run(until: Date().addingTimeInterval(1.2))
        XCTAssertTrue(app.buttons["精华分类测试帖"].exists)
        XCTAssertFalse(app.buttons["发帖时间分类测试帖"].exists)
        XCTAssertFalse(app.buttons["回复时间分类测试帖"].exists)
    }

    func testForumToolbarSearchRefreshAndBlockBehaviors() {
        let app = launchApp(scenario: "emptyThenSuccess")
        rootTab("进吧", in: app).tap()
        let forumField = app.textFields["输入吧名"]
        XCTAssertTrue(forumField.waitForExistence(timeout: 8))
        forumField.tap()
        forumField.typeText("测试\n")
        XCTAssertTrue(app.navigationBars["测试吧"].waitForExistence(timeout: 8))

        for iteration in 0..<6 {
            let forumSearch = app.buttons["搜索本吧"]
            XCTAssertTrue(forumSearch.waitForExistence(timeout: 5))
            XCTAssertTrue(waitForHittable(forumSearch, expected: true, timeout: 5))
            forumSearch.tap()

            let searchNavigationBar = app.navigationBars["测试吧搜索"]
            XCTAssertTrue(searchNavigationBar.waitForExistence(timeout: 8))
            XCTAssertTrue(app.textFields["search-input"].exists)
            let backButton = searchNavigationBar.buttons["BackButton"]
            XCTAssertTrue(
                backButton.waitForExistence(timeout: 5),
                "第\(iteration + 1)次进入吧内搜索后应存在系统返回按钮"
            )
            backButton.tap()

            XCTAssertTrue(
                app.navigationBars["测试吧"].waitForExistence(timeout: 8),
                "第\(iteration + 1)次退出搜索后应只回到当前贴吧"
            )
            XCTAssertTrue(
                app.scrollViews["forum-threads-scroll-view"].waitForExistence(timeout: 5),
                "第\(iteration + 1)次退出搜索后应保留帖子列表"
            )
            XCTAssertFalse(app.textFields["输入吧名"].isHittable, "不得越级返回进吧根页")
        }

        let moreMenu = app.buttons["forum-more-menu"]
        moreMenu.tap()
        let refresh = app.buttons["刷新"]
        XCTAssertTrue(refresh.waitForExistence(timeout: 5))
        refresh.tap()
        XCTAssertTrue(threadRows(in: app).firstMatch.waitForExistence(timeout: 8))

        moreMenu.tap()
        let blockForum = app.buttons["屏蔽测试吧"]
        XCTAssertTrue(blockForum.waitForExistence(timeout: 5))
        blockForum.tap()
        XCTAssertTrue(app.navigationBars["进吧"].waitForExistence(timeout: 8))
        XCTAssertFalse(
            app.buttons["测试吧"].exists,
            "屏蔽当前贴吧并退出后，最近访问列表也不应继续展示该吧"
        )
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
        XCTAssertTrue(waitForHittable(backButton, expected: true, timeout: 5))
        backButton.tap()

        openArea = app.descendants(matching: .any).matching(identifier: "thread-open-area").firstMatch
        XCTAssertTrue(openArea.waitForExistence(timeout: 8))
        openArea.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.82)).tap()
        XCTAssertTrue(app.buttons["更多"].waitForExistence(timeout: 8))
    }

    func testIPadLandscapeReaderListUsesAvailableWidth() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else {
            throw XCTSkip("仅在 iPad 设备矩阵中运行。")
        }
        let app = launchApp()
        XCUIDevice.shared.orientation = .landscapeLeft
        addTeardownBlock {
            XCUIDevice.shared.orientation = .portrait
        }

        let landscape = XCTNSPredicateExpectation(
            predicate: NSPredicate { object, _ in
                guard let application = object as? XCUIApplication else { return false }
                return application.frame.width > application.frame.height
            },
            object: app
        )
        XCTAssertEqual(XCTWaiter.wait(for: [landscape], timeout: 8), .completed)

        let firstThreadRow = threadRows(in: app).firstMatch
        XCTAssertTrue(firstThreadRow.waitForExistence(timeout: 8))
        XCTAssertGreaterThanOrEqual(
            firstThreadRow.frame.width,
            app.frame.width * 0.35,
            "iPad 横屏帖子行应使用足够的横向空间展示标题"
        )
        XCTAssertLessThan(
            firstThreadRow.frame.maxX,
            app.frame.midX,
            "左侧帖子列表不能挤占右侧详情栏"
        )
    }

    func testIPadForumThreadOpensSharedDetailInsteadOfLeadingLocalStack() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else {
            throw XCTSkip("仅在 iPad 设备矩阵中运行。")
        }
        let app = launchApp()
        rootTab("进吧", in: app).tap()

        let forumField = app.textFields["输入吧名"]
        XCTAssertTrue(forumField.waitForExistence(timeout: 8))
        forumField.tap()
        forumField.typeText("测试\n")
        XCTAssertTrue(app.navigationBars["测试吧"].waitForExistence(timeout: 8))

        let placeholder = app.descendants(matching: .any)["split-detail-placeholder"]
        XCTAssertTrue(placeholder.waitForExistence(timeout: 5))
        let openArea = app.descendants(matching: .any)
            .matching(identifier: "thread-open-area")
            .firstMatch
        XCTAssertTrue(openArea.waitForExistence(timeout: 8))
        openArea.tap()

        let detailToolbarButton = app.buttons["thread-favorite-button"]
        XCTAssertTrue(detailToolbarButton.waitForExistence(timeout: 8))
        XCTAssertFalse(
            placeholder.isHittable,
            "帖子必须覆盖共享 detail 的占位页"
        )
        XCTAssertGreaterThan(
            detailToolbarButton.frame.midX,
            app.frame.midX,
            "帖子工具栏必须位于 iPad 右侧共享 detail，而不是压入左侧局部栈"
        )
        XCTAssertTrue(
            openArea.isHittable,
            "打开共享 detail 后左栏帖子列表必须继续可操作"
        )
        XCTAssertTrue(
            app.navigationBars["测试吧"].exists,
            "打开共享 detail 后左栏贴吧列表必须继续保留"
        )
    }

    private func launchApp(
        scenario: String = "success",
        account: String? = nil,
        additionalArguments: [String] = [],
        additionalEnvironment: [String: String] = [:],
        resetAppearance: Bool = true,
        resetReadingPreferences: Bool = true,
        disableAnimations: Bool = true
    ) -> XCUIApplication {
        let app = XCUIApplication()
        var launchArguments = [
            "UITEST_USE_FIXTURES",
            "UITEST_RESET_SEARCH_HISTORY",
            "UITEST_RESET_BROWSING_HISTORY",
            "UITEST_RESET_RECENT_FORUMS",
            "UITEST_RESET_LOCAL_THREAD_LIBRARY",
            "UITEST_RESET_BLOCKLIST",
            "UITEST_RESET_FORUM_THREAD_SORT"
        ]
        if disableAnimations {
            launchArguments.append("UITEST_DISABLE_ANIMATIONS")
        }
        if resetAppearance {
            launchArguments.append("UITEST_RESET_APPEARANCE")
        }
        if resetReadingPreferences {
            launchArguments.append("UITEST_RESET_READING_PREFERENCES")
        }
        app.launchArguments = launchArguments + additionalArguments
        app.launchEnvironment["TIEBAPURE_FIXTURE_SCENARIO"] = scenario
        for (key, value) in additionalEnvironment {
            app.launchEnvironment[key] = value
        }
        if let account {
            app.launchEnvironment["TIEBAPURE_FIXTURE_ACCOUNT"] = account
        }
        app.launch()
        return app
    }

    private func waitForSwitch(
        _ toggle: XCUIElement,
        value: String,
        timeout: TimeInterval = 5
    ) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", value),
            object: toggle
        )
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private func assertReplyComposer(
        navigationTitle: String,
        prompt: String,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(
            app.navigationBars[navigationTitle].waitForExistence(timeout: 8),
            "点击纯文本后应打开 \(navigationTitle) 编辑器",
            file: file,
            line: line
        )
        XCTAssertTrue(
            app.staticTexts[prompt].waitForExistence(timeout: 5),
            "编辑器回复目标不正确：\(prompt)",
            file: file,
            line: line
        )
        XCTAssertTrue(
            app.textViews["正文内容"].waitForExistence(timeout: 5),
            "回复编辑器必须显示正文输入区",
            file: file,
            line: line
        )
    }

    private func diagnosticMetric(_ name: String, from value: String) -> Int? {
        value.split(separator: ";").compactMap { component -> Int? in
            let parts = component.split(separator: "=", maxSplits: 1)
            guard parts.count == 2, parts[0] == Substring(name) else { return nil }
            return Int(parts[1])
        }.first
    }

    private func waitForStableFrame(
        of element: XCUIElement,
        timeout: TimeInterval = 10,
        consecutiveSamples: Int = 5,
        tolerance: CGFloat = 0.5
    ) -> CGRect? {
        // A frame read may take 0.5–0.75 seconds on a busy GitHub runner because
        // it requires an accessibility snapshot. Keep the requested timeout as
        // a lower bound, while scaling the sampling budget with the unchanged
        // consecutive-sample requirement.
        let effectiveTimeout = max(
            timeout,
            TimeInterval(max(consecutiveSamples, 1)) * 2
        )
        guard element.waitForExistence(timeout: effectiveTimeout) else {
            return nil
        }

        let deadline = Date().addingTimeInterval(effectiveTimeout)
        var previousFrame: CGRect?
        var stableSamples = 0

        while Date() < deadline {
            // Reading `exists` and `frame` separately forces two accessibility
            // snapshots per sample. A non-renderable frame is sufficient to
            // detect a temporarily missing/replaced element with one snapshot.
            let frame = element.frame
            guard frame.isNull == false,
                  frame.isInfinite == false,
                  frame.isEmpty == false else {
                previousFrame = nil
                stableSamples = 0
                RunLoop.current.run(until: Date().addingTimeInterval(0.05))
                continue
            }

            if let previousFrame,
               abs(frame.minX - previousFrame.minX) <= tolerance,
               abs(frame.minY - previousFrame.minY) <= tolerance,
               abs(frame.width - previousFrame.width) <= tolerance,
               abs(frame.height - previousFrame.height) <= tolerance {
                stableSamples += 1
            } else {
                stableSamples = 1
            }
            if stableSamples >= consecutiveSamples {
                return frame
            }
            previousFrame = frame
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        return nil
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

    private func waitForValueContaining(
        _ text: String,
        on element: XCUIElement,
        timeout: TimeInterval
    ) -> Bool {
        let predicate = NSPredicate(format: "value CONTAINS %@", text)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private func assertNavigationTitle(
        _ title: XCUIElement,
        staysInside navigationBar: XCUIElement,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let titleFrame = title.frame
        let navigationFrame = navigationBar.frame.insetBy(dx: -1, dy: -1)
        XCTAssertFalse(titleFrame.isEmpty, "导航标题必须保持可见", file: file, line: line)
        XCTAssertTrue(
            navigationFrame.contains(titleFrame),
            "导航标题必须完整位于导航栏内，不能在滚动或刷新后错位或被裁切",
            file: file,
            line: line
        )
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
        XCTAssertTrue(waitForHittable(badge, expected: true, timeout: 5))
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

    private func assertTrailingLikeControl(
        _ control: XCUIElement,
        fullCount: Int,
        authorID: Int64,
        isMainPost: Bool,
        in app: XCUIApplication
    ) {
        XCTAssertTrue(control.exists)
        let accessibilityValue = control.value as? String ?? ""
        let reportedDigits = accessibilityValue.unicodeScalars
            .filter { CharacterSet.decimalDigits.contains($0) }
            .map(String.init)
            .joined()
        XCTAssertEqual(reportedDigits, "\(fullCount)")
        XCTAssertGreaterThanOrEqual(control.frame.height, 44)
        XCTAssertLessThan(
            control.frame.height,
            80,
            "即使在 Accessibility XXXL 下，点赞图标和数字也只能占一行"
        )
        XCTAssertGreaterThan(control.frame.midX, app.frame.midX)

        let badge = app.descendants(matching: .any)["thread-user-level-badge-\(authorID)"]
        XCTAssertTrue(badge.waitForExistence(timeout: 5))
        XCTAssertLessThanOrEqual(
            badge.frame.maxX,
            control.frame.minX + 1,
            "左侧用户信息不得覆盖右侧点赞区"
        )
        XCTAssertEqual(
            badge.frame.midY,
            control.frame.midY,
            accuracy: 3,
            "点赞区应在作者行右侧居中且保持单行"
        )

        let nameIdentifier = isMainPost ? "thread-main-user-name" : "thread-user-name-\(authorID)"
        let name = app.descendants(matching: .any)[nameIdentifier]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        if name.frame.maxX.isFinite {
            XCTAssertLessThanOrEqual(name.frame.maxX, control.frame.minX + 1)
        }
    }

    private func appearanceOption(_ title: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons
            .matching(identifier: "appearance-picker")
            .matching(NSPredicate(format: "label == %@", title))
            .firstMatch
    }

    private func pickerOption(
        _ title: String,
        identifier: String,
        exactLabel: Bool = true,
        in app: XCUIApplication
    ) -> XCUIElement {
        if identifier != "reading-media-loading-picker" {
            return app.segmentedControls[identifier].buttons[title]
        }
        let labelPredicate = exactLabel
            ? NSPredicate(format: "label == %@", title)
            : NSPredicate(format: "label BEGINSWITH %@", title)
        return app.buttons
            .matching(identifier: identifier)
            .matching(labelPredicate)
            .firstMatch
    }

    private func revealBySwipingUp(
        _ element: XCUIElement,
        in app: XCUIApplication,
        maxSwipes: Int
    ) -> Bool {
        if element.waitForExistence(timeout: 2), element.isHittable {
            return true
        }
        for _ in 0..<maxSwipes {
            app.swipeUp()
            if element.exists, element.isHittable {
                return true
            }
        }
        return element.exists && element.isHittable
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

    private func waitForHittable(
        _ element: XCUIElement,
        expected: Bool,
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            let matches = expected
                ? (element.exists && element.isHittable)
                : (!element.exists || !element.isHittable)
            if matches {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline
        return expected
            ? (element.exists && element.isHittable)
            : (!element.exists || !element.isHittable)
    }

    private func dismissFullScreenImageBySingleTap(
        in app: XCUIApplication,
        timeout: TimeInterval = 5
    ) {
        let pager = app.descendants(matching: .any)["full-screen-image-pager"]
        XCTAssertTrue(pager.waitForExistence(timeout: timeout))
        XCTAssertFalse(app.buttons["关闭图片"].exists, "图片详情页不应显示独立关闭按钮")

        app.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.3)).tap()
        XCTAssertTrue(
            pager.waitForNonExistence(timeout: timeout),
            "轻点图片应返回来源页面"
        )
    }

    private func waitForAnyLabel(
        _ labels: [String],
        on element: XCUIElement,
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if element.exists, labels.contains(element.label) {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        } while Date() < deadline
        return element.exists && labels.contains(element.label)
    }

    private func openGlobalSearch(in app: XCUIApplication) -> XCUIElement {
        XCTAssertFalse(app.searchFields.firstMatch.exists)
        let searchButton = app.buttons["home-search-button"]
        XCTAssertTrue(searchButton.waitForExistence(timeout: 8))
        XCTAssertTrue(waitForHittable(searchButton, expected: true, timeout: 5))
        searchButton.tap()

        XCTAssertTrue(app.navigationBars["搜索"].waitForExistence(timeout: 8))
        let searchField = app.textFields["search-input"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 8))
        XCTAssertTrue(waitForHittable(searchField, expected: true, timeout: 5))
        searchField.tap()
        return searchField
    }

    private func openFirstFollowedForum(in app: XCUIApplication) {
        rootTab("进吧", in: app).tap()
        let forumRow = app.buttons.matching(identifier: "forum-hub-forum-row").firstMatch
        XCTAssertTrue(forumRow.waitForExistence(timeout: 8))
        XCTAssertTrue(waitForHittable(forumRow, expected: true, timeout: 5))
        forumRow.tap()
        XCTAssertTrue(app.navigationBars["测试吧"].waitForExistence(timeout: 8))
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

    private func assertLikeCountIsReadOnly(identifier: String, in app: XCUIApplication) {
        let count = app.descendants(matching: .any)[identifier]
        XCTAssertTrue(count.waitForExistence(timeout: 5), "关闭点赞后仍应显示 \(identifier) 的赞数")
        XCTAssertFalse(app.buttons[identifier].exists, "关闭点赞后 \(identifier) 不应仍是按钮")
        XCTAssertTrue(count.label.contains("点赞"), "只读计数仍应提供完整的点赞无障碍标签")
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

    private func middleSwipeRight(in app: XCUIApplication, y: CGFloat = 0.38) {
        // Let any in-flight navigation transition finish first. UIKit ignores
        // the pop gesture while a transition is running, and call sites decide
        // the next screen has arrived by querying a marker that appears as soon
        // as the incoming view renders — before the transition ends. On a
        // loaded runner the transition outlives that marker, so the swipe lands
        // mid-transition and is dropped with no diagnostic: the gesture is
        // synthesized, the app goes idle, and the route simply never changes.
        // Deliberately not a retry-until-popped loop: several tests assert this
        // gesture pops exactly one level, and a second swipe would break them.
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))

        if #available(iOS 26.0, *) {
            // XCTest's coordinate press/drag injection does not enter UIKit's
            // iOS 26 content-pop recognizer, even in an otherwise empty native
            // UINavigationController. The system swipe event does.
            app.swipeRight()
            return
        }

        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: y))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.88, dy: y))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    private func subpostDismissSwipeRight(in app: XCUIApplication, y: CGFloat = 0.38) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: y))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.88, dy: y))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    private func visibleThreadInlineImage(
        in app: XCUIApplication,
        searchingTowardTop: Bool = false
    ) -> XCUIElement? {
        let inlineImage = app.descendants(matching: .any)["thread-inline-image"]
        if inlineImage.waitForExistence(timeout: 2), inlineImage.isHittable {
            return inlineImage
        }
        let scrollView = app.scrollViews["thread-detail-scroll-view"]
        for _ in 0..<20 {
            if inlineImage.exists, inlineImage.isHittable {
                return inlineImage
            }
            if searchingTowardTop {
                scrollView.swipeDown()
            } else {
                scrollView.swipeUp()
            }
        }
        return inlineImage.exists && inlineImage.isHittable ? inlineImage : nil
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
