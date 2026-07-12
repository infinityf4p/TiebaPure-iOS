import Combine
import XCTest
@testable import TiebaPure

final class StateRegressionTests: XCTestCase {
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
