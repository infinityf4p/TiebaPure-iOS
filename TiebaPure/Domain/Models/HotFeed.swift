import Foundation

/// The 热点 (hot-thread) tab as one response: the service's own sub-tabs, the
/// 话题榜 it carries on every request, and the hot threads themselves.
///
/// The tab list comes back on every request, so switching sub-tabs keeps the
/// same set of tabs without a second discovery call.
struct HotFeed: Equatable, Sendable {
    var tabs: [HotTab] = []
    /// 话题榜 (hot topics). The service sends the same list with every request,
    /// category listings included.
    var topics: [HotTopic] = []
    var threads: [ThreadSummary] = []
}

/// One 话题榜 entry, shown above the hot-thread list.
struct HotTopic: Identifiable, Equatable, Sendable {
    var id: Int64
    var name: String
    /// 讨论数 as the service counts it.
    var discussCount: Int

    var discussCountText: String { TiebaCountText.text(discussCount) }
}

/// The service counts 讨论数 and 浏览数 into the millions, and the full number
/// crowds out whatever sits next to it, so anything past ten thousand is
/// rounded to 万. One owner, because the hot list and the topic page show the
/// same numbers.
enum TiebaCountText {
    static func text(_ count: Int) -> String {
        guard count >= 10_000 else { return "\(count)" }
        return String(format: "%.1f万", Double(count) / 10_000)
    }
}

/// Builds the 全部 listing the service itself does not offer.
///
/// There is no whole-list code — an empty code, "all" and "0" all answer with
/// the same 4-thread default — so 全部 is the union of the category listings,
/// deduped by thread id, ordered by the service's own 热度 value, which every
/// category listing already arrives sorted by.
enum HotFeedMerge {
    static func threads(from feeds: [HotFeed]) -> [ThreadSummary] {
        var best: [Int64: ThreadSummary] = [:]
        for feed in feeds {
            for thread in feed.threads {
                if let existing = best[thread.id], existing.hotScore >= thread.hotScore { continue }
                best[thread.id] = thread
            }
        }
        return best.values.sorted { lhs, rhs in
            if lhs.hotScore != rhs.hotScore { return lhs.hotScore > rhs.hotScore }
            if lhs.replyCount != rhs.replyCount { return lhs.replyCount > rhs.replyCount }
            return lhs.id > rhs.id
        }
    }
}

/// One sub-tab of the hot-thread listing.
struct HotTab: Identifiable, Equatable, Sendable {
    /// The 全部 entry. The service reports only its category sub-tabs
    /// (视频/长更/游戏/数码) in `hot_thread_tab_info` — it has no whole-list code
    /// at all — so the chip is built here and its listing is the merge of the
    /// category listings (see `HotFeedMerge`).
    static let allCode = "all"
    static let allName = "全部"
    static let all = HotTab(code: allCode, name: allName)

    var code: String
    var name: String

    var id: String { code }
}