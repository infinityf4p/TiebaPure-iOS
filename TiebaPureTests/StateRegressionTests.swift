import Combine
import XCTest
@testable import TiebaPure

final class StateRegressionTests: XCTestCase {
    @MainActor
    func testAppAppearancePersistsOverridesAndSanitizesInvalidValues() throws {
        let suiteName = "AppAppearanceStoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let key = "appearance"

        let store = AppAppearanceStore(defaults: defaults, key: key)
        XCTAssertEqual(store.selection, .system)
        XCTAssertNil(store.selection.preferredColorScheme)
        XCTAssertNil(defaults.object(forKey: key))

        store.select(.dark)
        XCTAssertEqual(store.selection, .dark)
        XCTAssertEqual(store.selection.preferredColorScheme, .dark)
        XCTAssertEqual(defaults.string(forKey: key), AppAppearance.dark.rawValue)

        let reloaded = AppAppearanceStore(defaults: defaults, key: key)
        XCTAssertEqual(reloaded.selection, .dark)

        reloaded.select(.light)
        XCTAssertEqual(reloaded.selection, .light)
        XCTAssertEqual(reloaded.selection.preferredColorScheme, .light)
        XCTAssertEqual(defaults.string(forKey: key), AppAppearance.light.rawValue)

        reloaded.select(.system)
        XCTAssertEqual(reloaded.selection, .system)
        XCTAssertNil(reloaded.selection.preferredColorScheme)
        XCTAssertNil(defaults.object(forKey: key))

        defaults.set("invalid-appearance", forKey: key)
        let sanitized = AppAppearanceStore(defaults: defaults, key: key)
        XCTAssertEqual(sanitized.selection, .system)
        XCTAssertNil(defaults.object(forKey: key))
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testSearchRoutePreservesMatchedPostID() {
        let route = SearchThreadRoute(threadID: 10, forumID: 20, postID: 30)
        XCTAssertEqual(route.postID, 30)
    }

    func testSearchRequestKeyIncludesEveryResultCondition() {
        let base = SearchRequestKey(accountID: "A", keyword: "词", forumName: "吧", filterType: 2, sortType: 5, page: 1)
        XCTAssertNotEqual(base, SearchRequestKey(accountID: "B", keyword: "词", forumName: "吧", filterType: 2, sortType: 5, page: 1))
        XCTAssertNotEqual(base, SearchRequestKey(accountID: "A", keyword: "新词", forumName: "吧", filterType: 2, sortType: 5, page: 1))
        XCTAssertNotEqual(base, SearchRequestKey(accountID: "A", keyword: "词", forumName: "吧", filterType: 1, sortType: 5, page: 1))
        XCTAssertNotEqual(base, SearchRequestKey(accountID: "A", keyword: "词", forumName: "吧", filterType: 2, sortType: 0, page: 1))
        XCTAssertNotEqual(base, SearchRequestKey(accountID: "A", keyword: "词", forumName: "吧", filterType: 2, sortType: 5, page: 2))
    }

    @MainActor
    func testRecentForumStorePublishesDeduplicatesAndLimitsItems() throws {
        let suiteName = "RecentForumStoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        var tick: TimeInterval = 0
        let store = RecentForumStore(defaults: defaults, limit: 30) {
            tick += 1
            return Date(timeIntervalSince1970: tick)
        }
        var observations: [[RecentForum]] = []
        let cancellable = store.$items.dropFirst().sink { observations.append($0) }

        for index in 0..<35 {
            store.save(name: "forum\(index)")
        }
        store.save(name: "forum10", displayName: "更新后的十号吧")

        XCTAssertEqual(store.items.count, 30)
        XCTAssertEqual(store.items.first?.name, "forum10")
        XCTAssertEqual(store.items.first?.displayName, "更新后的十号吧")
        XCTAssertEqual(store.items.filter { $0.name == "forum10" }.count, 1)
        XCTAssertFalse(observations.isEmpty)
        withExtendedLifetime(cancellable) {}
        defaults.removePersistentDomain(forName: suiteName)
    }

    @MainActor
    func testSearchHistoryPersistsDeduplicatesLimitsAndDeletes() throws {
        let suiteName = "SearchHistoryStoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let store = SearchHistoryStore(
            defaults: defaults,
            key: "search-history",
            limit: 3
        )

        store.record("  第一条  ")
        store.record("Second")
        store.record("second")
        store.record("第三条")
        store.record("第四条")

        XCTAssertEqual(store.items, ["第四条", "第三条", "second"])

        let reloaded = SearchHistoryStore(
            defaults: defaults,
            key: "search-history",
            limit: 3
        )
        XCTAssertEqual(reloaded.items, store.items)

        reloaded.remove("SECOND")
        XCTAssertEqual(reloaded.items, ["第四条", "第三条"])
        reloaded.clear()
        XCTAssertTrue(reloaded.items.isEmpty)
        XCTAssertNil(defaults.object(forKey: "search-history"))
        defaults.removePersistentDomain(forName: suiteName)
    }

    @MainActor
    func testBrowsingHistoryPersistsDeduplicatesLimitsAndDeletes() throws {
        XCTAssertEqual(BrowsingHistoryPolicy.maximumStoredEntries, 500)
        let suiteName = "BrowsingHistoryStoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        var tick: TimeInterval = 0
        let store = BrowsingHistoryStore(
            defaults: defaults,
            key: "browsing-history",
            limit: 2
        ) {
            tick += 1
            return Date(timeIntervalSince1970: tick)
        }
        let author = UserSummary(
            id: 1,
            name: "author",
            displayName: "历史作者",
            portrait: ""
        )
        let forum = Forum(
            id: 101,
            name: "测试",
            displayName: "测试吧",
            avatarURL: nil,
            memberCount: 0,
            threadCount: 0
        )
        func thread(id: Int64, title: String, forumID: Int64? = nil) -> ThreadSummary {
            ThreadSummary(
                id: id,
                forumID: forumID,
                title: title,
                author: author,
                forumName: forum.name,
                replyCount: 0,
                viewCount: 0,
                blocks: []
            )
        }

        store.record(thread: thread(id: 1, title: "第一条"), forum: forum)
        store.record(thread: thread(id: 2, title: "第二条"), forum: forum)
        store.record(thread: thread(id: 1, title: "更新后的第一条"), forum: forum)
        store.record(
            thread: thread(id: 3, title: "第三条"),
            fallbackForumID: 303
        )
        store.record(thread: thread(id: 0, title: "无效帖子"), forum: forum)

        XCTAssertEqual(store.items.map(\.threadID), [3, 1])
        XCTAssertEqual(store.items.last?.title, "更新后的第一条")
        XCTAssertEqual(store.items.first?.forumID, 303)
        XCTAssertEqual(store.items.last?.forumDisplayName, "测试吧")
        XCTAssertEqual(store.items.first?.visitedAt, Date(timeIntervalSince1970: 4))

        let reloaded = BrowsingHistoryStore(
            defaults: defaults,
            key: "browsing-history",
            limit: 2
        )
        XCTAssertEqual(reloaded.items, store.items)

        reloaded.remove(threadIDs: [3])
        XCTAssertEqual(reloaded.items.map(\.threadID), [1])
        reloaded.clear()
        XCTAssertTrue(reloaded.items.isEmpty)
        XCTAssertNil(defaults.object(forKey: "browsing-history"))
        defaults.removePersistentDomain(forName: suiteName)
    }

    @MainActor
    func testLocalThreadLibraryPersistsFavoritesAndReadingPositions() throws {
        XCTAssertEqual(LocalThreadLibraryPolicy.maximumFavoriteEntries, 500)
        XCTAssertEqual(LocalThreadLibraryPolicy.maximumReadingPositions, 500)
        let suiteName = "LocalThreadLibraryStoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        var tick: TimeInterval = 0
        let store = LocalThreadLibraryStore(
            defaults: defaults,
            favoritesKey: "favorites",
            readingPositionsKey: "positions",
            favoriteLimit: 2,
            readingPositionLimit: 2
        ) {
            tick += 1
            return Date(timeIntervalSince1970: tick)
        }
        let author = UserSummary(
            id: 1,
            name: "author",
            displayName: "收藏作者",
            portrait: ""
        )
        let forum = Forum(
            id: 101,
            name: "测试",
            displayName: "测试吧",
            avatarURL: nil,
            memberCount: 0,
            threadCount: 0
        )
        func thread(id: Int64, title: String) -> ThreadSummary {
            ThreadSummary(
                id: id,
                forumID: forum.id,
                title: title,
                author: author,
                forumName: forum.name,
                replyCount: 0,
                viewCount: 0,
                blocks: []
            )
        }

        store.addFavorite(thread: thread(id: 1, title: "第一条"), forum: forum)
        store.addFavorite(thread: thread(id: 2, title: "第二条"), forum: forum)
        store.addFavorite(thread: thread(id: 1, title: "更新后的第一条"), forum: forum)
        store.addFavorite(thread: thread(id: 3, title: "第三条"), forum: forum)
        store.addFavorite(thread: thread(id: 0, title: "无效帖子"), forum: forum)

        XCTAssertEqual(store.favorites.map(\.threadID), [3, 1])
        XCTAssertEqual(store.favorites.last?.title, "更新后的第一条")
        XCTAssertTrue(store.isFavorite(threadID: 3))
        XCTAssertFalse(store.toggleFavorite(thread: thread(id: 3, title: "第三条"), forum: forum))
        XCTAssertEqual(store.favorites.map(\.threadID), [1])

        store.recordReadingPosition(threadID: 1, postID: 1001, floor: 1)
        store.recordReadingPosition(threadID: 1, postID: 1002, floor: 2)
        store.recordReadingPosition(threadID: 2, postID: 2003, floor: 3)
        store.recordReadingPosition(threadID: 1, postID: 1004, floor: 4)
        store.recordReadingPosition(threadID: 3, postID: 3005, floor: 5)

        XCTAssertEqual(store.readingPositions.map(\.threadID), [3, 1])
        XCTAssertEqual(store.position(for: 1)?.postID, 1004)
        XCTAssertEqual(store.position(for: 1)?.floor, 4)
        XCTAssertNil(store.position(for: 2))

        let reloaded = LocalThreadLibraryStore(
            defaults: defaults,
            favoritesKey: "favorites",
            readingPositionsKey: "positions",
            favoriteLimit: 2,
            readingPositionLimit: 2
        )
        XCTAssertEqual(reloaded.favorites, store.favorites)
        XCTAssertEqual(reloaded.readingPositions, store.readingPositions)

        reloaded.clearReadingPosition(threadID: 1)
        XCTAssertNil(reloaded.position(for: 1))
        reloaded.clearReadingPositions()
        XCTAssertTrue(reloaded.readingPositions.isEmpty)
        XCTAssertFalse(reloaded.favorites.isEmpty)
        XCTAssertNil(defaults.object(forKey: "positions"))

        reloaded.recordReadingPosition(threadID: 1, postID: 1006, floor: 6)
        reloaded.clearAll()
        XCTAssertTrue(reloaded.favorites.isEmpty)
        XCTAssertTrue(reloaded.readingPositions.isEmpty)
        XCTAssertNil(defaults.object(forKey: "favorites"))
        XCTAssertNil(defaults.object(forKey: "positions"))
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testThreadReadingViewportPolicyRecordsOnlyReplyAtCaptureLine() {
        let entries = [
            ThreadPostViewportEntry(postID: 2001, floor: 1, minY: -240, maxY: 80),
            ThreadPostViewportEntry(postID: 2002, floor: 2, minY: 80, maxY: 240),
            ThreadPostViewportEntry(postID: 2003, floor: 3, minY: 240, maxY: 400)
        ]

        XCTAssertNil(ThreadReadingViewportPolicy.position(
            entries: entries,
            scrollDistanceFromTop: 20
        ))
        XCTAssertEqual(
            ThreadReadingViewportPolicy.position(
                entries: entries,
                scrollDistanceFromTop: 240
            )?.postID,
            2002
        )
        XCTAssertNil(ThreadReadingViewportPolicy.position(
            entries: [ThreadPostViewportEntry(postID: 2001, floor: 1, minY: 0, maxY: 200)],
            scrollDistanceFromTop: 100
        ))
    }

    func testFixtureSearchCarriesPostIDAndCancellationPropagates() async throws {
        let api = FixtureTiebaAPI(scenario: .success)
        let page = try await api.searchThreads(
            keyword: "确定性",
            page: 1,
            sortType: 5,
            filterType: 2,
            forumName: nil,
            pageSize: 30
        )
        XCTAssertEqual(page.results.first?.postID, 2002)

        let slow = FixtureTiebaAPI(scenario: .slow)
        let task = Task {
            try await slow.searchThreads(
                keyword: "慢请求",
                page: 1,
                sortType: 5,
                filterType: 2,
                forumName: nil,
                pageSize: 30
            )
        }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
        }
    }
}
