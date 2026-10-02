import Foundation

/// The header of one 话题 (topic): what a 话题榜 row shows, plus the counts the
/// topic page adds above its thread feed.
struct TopicInfo: Equatable, Sendable {
    var id: Int64
    var name: String
    var summary: String
    var discussCount: Int
    var browseCount: Int
    var imageURL: URL?

    var discussCountText: String { TiebaCountText.text(discussCount) }

    var browseCountText: String { TiebaCountText.text(browseCount) }
}

/// One page of a 话题's thread feed.
///
/// The service pages by cursor, not by number: `pn` and `offset` alone answer
/// error 300000 ("param invalid"), and only `last_id` — the previous page's last
/// feed id — moves the feed forward, so `nextCursor` carries it.
struct TopicThreadPage: Equatable, Sendable {
    /// Only the first page carries the header.
    var info: TopicInfo?
    var threads: [ThreadSummary]
    var hasMore: Bool
    var nextCursor: String

    static let empty = TopicThreadPage(info: nil, threads: [], hasMore: false, nextCursor: "")
}

enum TopicPagePolicy {
    static let pageSize = 20
}
