import Foundation

enum TiebaHotRequestFactory {
    /// One listing per sub-tab: the tab id stays fixed and the code is the only
    /// variable part. The tab list itself comes back on every response, so the
    /// first request needs no discovery round.
    ///
    /// An empty code folds into `HotTab.allCode`, so no caller can send a
    /// code-less request: it and "all" answer with the same 4-thread default,
    /// which the API layer turns into the merged 全部 listing.
    static func request(
        account: Account?,
        tabCode: String,
        requestBuilder: TiebaRequestBuilder
    ) -> Tieba_HotThreadList_HotThreadListRequest {
        var requestData = Tieba_HotThreadList_HotThreadListRequestData()
        requestData.common = requestBuilder.common(account: account)
        requestData.tabID = "1"
        requestData.tabCode = tabCode.isEmpty ? HotTab.allCode : tabCode

        var request = Tieba_HotThreadList_HotThreadListRequest()
        request.data = requestData
        return request
    }
}

enum HotFeedMapper {
    static func makeFeed(
        from data: Tieba_HotThreadList_HotThreadListResponseData
    ) -> HotFeed {
        let reported = data.hotThreadTabInfo.compactMap { tab -> HotTab? in
            // A tab without a code cannot be requested, and a tab without a
            // name has nothing to show on the tab bar.
            guard tab.tabCode.isEmpty == false, tab.tabName.isEmpty == false else { return nil }
            return HotTab(code: tab.tabCode, name: tab.tabName)
        }
        var tabs = reported
        // The service lists only its category sub-tabs, so without this chip
        // the bar would have no way back to the whole list after a category is
        // picked. A category already called "all" would then duplicate it.
        if tabs.contains(where: { $0.code == HotTab.allCode }) == false {
            tabs.insert(HotTab.all, at: 0)
        }
        return HotFeed(
            tabs: tabs,
            topics: topics(in: data),
            threads: dedupedByID(
                data.threadInfo
                    .filter(TiebaContentFilter.shouldMap(thread:))
                    .map { ThreadMapper.fromThreadInfo($0, usersByID: [:]) }
            )
        )
    }

    /// 话题榜 rows. A topic without an id or a name has nothing to render and
    /// nothing to identify it by.
    private static func topics(
        in data: Tieba_HotThreadList_HotThreadListResponseData
    ) -> [HotTopic] {
        data.topicList.compactMap { topic -> HotTopic? in
            guard topic.topicID > 0, topic.topicName.isEmpty == false else { return nil }
            return HotTopic(
                id: Int64(clamping: topic.topicID),
                name: topic.topicName,
                discussCount: Int(clamping: topic.discussNum)
            )
        }
    }

    /// The same thread can appear twice in one listing (a pinned row repeated at
    /// the top of a sub-tab), and duplicate row identities break list diffing.
    private static func dedupedByID(_ threads: [ThreadSummary]) -> [ThreadSummary] {
        var seen = Set<Int64>()
        return threads.filter { seen.insert($0.id).inserted }
    }
}

extension TiebaAPI {
    /// 热点 (hot threads) for one sub-tab of the home hot-thread tab.
    ///
    /// The service has no whole-list code, so `HotTab.allCode` is assembled from
    /// the category listings instead of being one request; every other code is
    /// exactly one. Threads are filtered and mapped exactly like the
    /// personalized feed so both tabs share one row presentation.
    func hotThreads(account: Account?, tabCode: String) async throws -> HotFeed {
        guard tabCode.isEmpty || tabCode == HotTab.allCode else {
            return try await hotThreadsListing(account: account, tabCode: tabCode)
        }
        return try await allHotThreads(account: account)
    }

    /// 全部: the service's default listing (its rows, the tab list and the
    /// 话题榜) plus every category listing merged into one 热度-ordered list.
    private func allHotThreads(account: Account?) async throws -> HotFeed {
        let base = try await hotThreadsListing(account: account, tabCode: HotTab.allCode)
        let categoryCodes = base.tabs.map(\.code).filter { $0 != HotTab.allCode }
        guard categoryCodes.isEmpty == false else { return base }

        // The categories are independent reads, so they run at once: the 全部
        // listing is the first thing the tab shows.
        let feeds = await withTaskGroup(of: HotFeed?.self) { group in
            for code in categoryCodes {
                group.addTask {
                    do {
                        return try await hotThreadsListing(account: account, tabCode: code)
                    } catch is CancellationError {
                        // The user switched tabs; a cancelled read is not a
                        // category failure and must not be logged as one.
                        return nil
                    } catch {
                        if Task.isCancelled || (error as? URLError)?.code == .cancelled {
                            return nil
                        }
                        // One category failing still leaves a usable 全部 listing,
                        // but it must not disappear without a trace.
                        await AppLog.shared.recordError(
                            "首页热点",
                            "全部合并：\(code) 拉取失败，本次只用其余分类",
                            error: error
                        )
                        return nil
                    }
                }
            }
            var collected: [HotFeed] = []
            for await feed in group {
                if let feed { collected.append(feed) }
            }
            return collected
        }
        // A superseded load (another tab was tapped) must not report itself as a
        // successful, smaller 全部 merge.
        try Task.checkCancellation()

        let merged = HotFeedMerge.threads(from: [base] + feeds)
        await AppLog.shared.record(
            .info,
            "首页热点",
            "全部合并 \(categoryCodes.count) 个分类：默认 \(base.threads.count) 条 + 分类 "
                + "\(feeds.reduce(0) { $0 + $1.threads.count }) 条 → 去重后 \(merged.count) 条 "
                + "话题\(base.topics.count)条"
        )
        return HotFeed(tabs: base.tabs, topics: base.topics, threads: merged)
    }

    /// One listing from one request, with the diagnostic line that separates
    /// "the service sent four threads" from "we filtered them".
    private func hotThreadsListing(account: Account?, tabCode: String) async throws -> HotFeed {
        let request = TiebaHotRequestFactory.request(
            account: account,
            tabCode: tabCode,
            requestBuilder: requestBuilder
        )
        let multipart = try requestBuilder.multipart(
            protobuf: request,
            account: account,
            includeSToken: false
        )
        do {
            let response = try await client.postProtobuf(
                .hotThreadList,
                body: multipart.body,
                contentType: multipart.contentType,
                headers: [
                    "X-BD-DATA-TYPE": "protobuf",
                    "Cookie": TiebaFeedCookie.value(for: account)
                ],
                as: Tieba_HotThreadList_HotThreadListResponse.self
            )

            try validateTiebaError(response.error)
            guard response.hasData else { throw TiebaAPIError.emptyResponse }
            let feed = HotFeedMapper.makeFeed(from: response.data)
            // The service's own tab list (with codes) is what decides whether a
            // missing 全部 is a server change or a local one.
            let serverTabs = response.data.hotThreadTabInfo
                .map { "\($0.tabName)(\($0.tabCode))" }
                .joined(separator: "/")
            await AppLog.shared.record(
                .info,
                "首页热点",
                "tabCode=\(tabCode.isEmpty ? HotTab.allCode : tabCode) 已登录=\(account != nil) "
                    + "服务端子标签=\(serverTabs.isEmpty ? "(无)" : serverTabs) "
                    + "展示=\(feed.tabs.map(\.name).joined(separator: "/")) "
                    + "原始\(response.data.threadInfo.count)条 保留\(feed.threads.count)条 "
                    + "来源吧=\(Self.forumNames(feed.threads))"
            )
            return feed
        } catch {
            // Switching tabs cancels the in-flight read; that is not a failure
            // and should not fill the log with errors.
            if error is CancellationError || (error as? URLError)?.code == .cancelled || Task.isCancelled {
                throw error
            }
            await AppLog.shared.recordError(
                "首页热点",
                "tabCode=\(tabCode.isEmpty ? HotTab.allCode : tabCode) 失败",
                error: error
            )
            throw error
        }
    }

    /// A hot listing has no per-forum grouping, so the forum names are the only
    /// way to tell "the service sent the global hot list" from "the service sent
    /// the tab we expected" once a user compares it with the official app.
    private static func forumNames(_ threads: [ThreadSummary]) -> String {
        let names = threads
            .prefix(8)
            .compactMap { $0.forumName?.isEmpty == false ? $0.forumName : nil }
        guard names.isEmpty == false else { return "(帖子未带吧名)" }
        return names.joined(separator: "、")
    }
}