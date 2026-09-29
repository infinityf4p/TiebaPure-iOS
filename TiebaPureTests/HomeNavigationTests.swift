import XCTest
import UIKit
@testable import TiebaPure

final class HomeNavigationTests: XCTestCase {
    @MainActor
    func testHomeReselectIsVetoedWithoutRoutingAnAction() {
        let tabBar = UITabBarController()
        let home = UIViewController()
        let forums = UIViewController()
        tabBar.viewControllers = [home, forums]
        tabBar.selectedViewController = home
        let nativeDelegate = RecordingTabDelegate()
        tabBar.delegate = nativeDelegate
        var singleCount = 0
        var doubleCount = 0
        var longPressCount = 0
        let observer = TabSelectionObserver.Coordinator(
            onHomeSingleTap: { singleCount += 1 },
            onHomeDoubleTap: { doubleCount += 1 },
            onHomeLongPress: { longPressCount += 1 }
        )
        observer.attach(to: tabBar)

        // A reselect of the already-selected Home tab is rejected locally (so
        // UIKit cannot also pop/scroll), but it must not itself route refresh
        // or scroll actions — those are delivered by the gesture recognizers.
        XCTAssertFalse(observer.tabBarController(tabBar, shouldSelect: home))
        XCTAssertEqual(singleCount, 0)
        XCTAssertEqual(doubleCount, 0)
        XCTAssertEqual(longPressCount, 0)
        XCTAssertEqual(nativeDelegate.selectionCount, 0)
        XCTAssertTrue(tabBar.selectedViewController === home)
    }

    @MainActor
    func testMultiTouchCallbacksAreDeliveredInOrder() {
        let observer = TabSelectionObserver.Coordinator(
            onHomeSingleTap: {},
            onHomeDoubleTap: {},
            onHomeLongPress: {}
        )
        var order: [String] = []
        observer.onHomeSingleTap = { order.append("single") }
        observer.onHomeDoubleTap = { order.append("double") }
        observer.onHomeLongPress = { order.append("long") }
        observer.onHomeSingleTap()
        observer.onHomeLongPress()
        observer.onHomeDoubleTap()
        XCTAssertEqual(order, ["single", "long", "double"])
    }

    @MainActor
    func testSwitchingTabsPreservesNativeSelectionAndVeto() {
        let tabBar = UITabBarController()
        let home = UIViewController()
        let forums = UIViewController()
        tabBar.viewControllers = [home, forums]
        tabBar.selectedViewController = forums
        let nativeDelegate = RecordingTabDelegate()
        tabBar.delegate = nativeDelegate
        var singleCount = 0
        let observer = TabSelectionObserver.Coordinator(
            onHomeSingleTap: { singleCount += 1 },
            onHomeDoubleTap: {},
            onHomeLongPress: {}
        )
        observer.attach(to: tabBar)

        XCTAssertTrue(observer.tabBarController(tabBar, shouldSelect: home))
        nativeDelegate.permitsSelection = false
        XCTAssertFalse(observer.tabBarController(tabBar, shouldSelect: home))
        XCTAssertEqual(nativeDelegate.selectionCount, 2)
        XCTAssertEqual(singleCount, 0, "Returning from another tab must not route a Home action")
        observer.tabBarController(tabBar, didSelect: home)
        XCTAssertTrue(nativeDelegate.lastSelectedController === home)
        observer.detach()
        XCTAssertTrue(tabBar.delegate === nativeDelegate)
    }

    func testBackFromForumThreadKeepsForumAsCurrentRoute() {
        let threadA = ReaderSplitThreadRoute(threadID: 101, forumID: 7)
        let threadB = ReaderSplitThreadRoute(threadID: 202, forumID: 7)
        let forum = Forum(
            id: 7,
            name: "test",
            displayName: "test forum",
            avatarURL: nil,
            memberCount: 0,
            threadCount: 0
        )

        var path: [HomeNavigationRoute] = [.thread(threadA)]
        path = HomeNavigationPathPolicy.pushing(.fromForum(forum), onto: path)
        path = HomeNavigationPathPolicy.pushing(.thread(threadB), onto: path)

        path = HomeNavigationPathPolicy.removingCurrent(.thread(threadB), from: path)

        XCTAssertEqual(path, [.thread(threadA), .fromForum(forum)])
    }

    func testStaleRouteRemovalDoesNotPopAnotherLayer() {
        let threadA = ReaderSplitThreadRoute(threadID: 101, forumID: 7)
        let threadB = ReaderSplitThreadRoute(threadID: 202, forumID: 7)
        let path: [HomeNavigationRoute] = [.thread(threadA), .thread(threadB)]

        XCTAssertEqual(
            HomeNavigationPathPolicy.removingCurrent(.thread(threadA), from: path),
            path
        )
    }

    func testUserOpenedFromThreadIsOwnedByTheSameTypedPath() {
        let thread = ReaderSplitThreadRoute(threadID: 101, forumID: 7)
        let user = UserSummary(
            id: 9,
            name: "user",
            displayName: "User",
            portrait: ""
        )
        var path: [HomeNavigationRoute] = [.thread(thread)]

        path = HomeNavigationPathPolicy.pushing(
            .user(user: user, sourceThreadID: thread.threadID),
            onto: path
        )

        XCTAssertEqual(
            HomeNavigationPathPolicy.removingCurrent(path.last!, from: path),
            [.thread(thread)]
        )
    }

    func testInheritedReaderHandlerDoesNotEscapeCompactLocalStack() {
        XCTAssertEqual(
            ForumThreadsOpenRoutingPolicy.destination(
                hasExplicitParentHandler: false,
                hasReaderSplitHandler: true,
                isReaderSplitListColumn: false
            ),
            .localStack
        )
        XCTAssertEqual(
            ForumThreadsOpenRoutingPolicy.destination(
                hasExplicitParentHandler: true,
                hasReaderSplitHandler: true,
                isReaderSplitListColumn: false
            ),
            .parentReader
        )
        XCTAssertEqual(
            ForumThreadsOpenRoutingPolicy.destination(
                hasExplicitParentHandler: false,
                hasReaderSplitHandler: true,
                isReaderSplitListColumn: true
            ),
            .parentReader
        )
    }
}

@MainActor
private final class RecordingTabDelegate: NSObject, UITabBarControllerDelegate {
    var permitsSelection = true
    var selectionCount = 0
    var lastSelectedController: UIViewController?

    func tabBarController(_ tabBarController: UITabBarController, shouldSelect viewController: UIViewController) -> Bool {
        selectionCount += 1
        return permitsSelection
    }

    func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
        lastSelectedController = viewController
    }
}
