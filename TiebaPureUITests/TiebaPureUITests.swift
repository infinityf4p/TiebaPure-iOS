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

    func testPullingHomeFeedShowsRefreshAnimation() throws {
        guard UIAccessibility.isReduceMotionEnabled == false else {
            throw XCTSkip("Reduce Motion 开启时由动画抑制用例覆盖。")
        }
        let app = launchApp()

        let firstRow = threadRows(in: app).firstMatch
        XCTAssertTrue(firstRow.waitForExistence(timeout: 45))

        let start = firstRow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15))
        let end = firstRow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 1.35))
        start.press(forDuration: 0.1, thenDragTo: end)

        XCTAssertTrue(
            app.descendants(matching: .any)["home-refresh-animation"].waitForExistence(timeout: 3)
        )
    }

    func testHomeTabReselectAfterScrollingShowsRefreshAnimation() throws {
        guard UIAccessibility.isReduceMotionEnabled == false else {
            throw XCTSkip("Reduce Motion 开启时由动画抑制用例覆盖。")
        }
        let app = launchApp()

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

        XCTAssertTrue(
            app.descendants(matching: .any)["home-refresh-animation"].waitForExistence(timeout: 3)
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
        let followedForumsButton = app.buttons["我的关注吧"]
        XCTAssertTrue(
            loginButton.waitForExistence(timeout: 5) || followedForumsButton.waitForExistence(timeout: 5)
        )
    }

    func testSearchResultRoutesToMatchedReply() {
        let app = launchApp()

        let searchField = app.searchFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 20))
        searchField.tap()
        searchField.typeText("iPhone")
        searchField.typeText("\n")

        XCTAssertTrue(app.navigationBars["搜索"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.segmentedControls.buttons["全部"].waitForExistence(timeout: 10))
        let firstResult = threadRows(in: app).firstMatch
        XCTAssertTrue(firstResult.waitForExistence(timeout: 10))
        app.descendants(matching: .any).matching(identifier: "thread-open-area").firstMatch.tap()
        XCTAssertTrue(waitForLabelContaining("已定位搜索命中回复", in: app, maxSwipes: 10))
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
        XCTAssertTrue(app.staticTexts["输入关键词"].waitForExistence(timeout: 10))
    }

    func testAboutShowsTiebaLiteAttributionAndGPL() {
        let app = launchApp()

        rootTab("我的", in: app).tap()
        XCTAssertTrue(waitForElement(named: "关于 TiebaPure", in: app, maxSwipes: 4))
        app.buttons["关于 TiebaPure"].tap()
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

    func testSyntheticScreenshotMatrix() {
        let app = launchApp()
        XCTAssertTrue(threadRows(in: app).firstMatch.waitForExistence(timeout: 8))
        attachScreenshot(named: "fixture-home")

        let searchField = app.searchFields.firstMatch
        searchField.tap()
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

        let searchField = app.searchFields.firstMatch
        searchField.tap()
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
        let searchField = app.searchFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 8))
        searchField.tap()
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

    private func launchApp(scenario: String = "success", account: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_USE_FIXTURES", "UITEST_DISABLE_ANIMATIONS", "UITEST_EXTENDED_REFRESH_ANIMATION"]
        app.launchEnvironment["TIEBAPURE_FIXTURE_SCENARIO"] = scenario
        if let account {
            app.launchEnvironment["TIEBAPURE_FIXTURE_ACCOUNT"] = account
        }
        app.launch()
        return app
    }

    private func threadRows(in app: XCUIApplication) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: "thread-row")
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

    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
