import Foundation

struct SearchResultsPage: Equatable, Sendable {
    var results: [SearchResult]
    var currentPage: Int
    var hasMore: Bool
}

struct SearchResult: Identifiable, Equatable, Sendable {
    var threadID: Int64
    var postID: UInt64?
    var forumID: Int64?
    var forumName: String
    var forumAvatarURL: URL?
    var title: String
    var content: String
    var author: UserSummary
    var createdAt: Date?
    var replyCount: Int
    var likeCount: Int
    var shareCount: Int
    var blocks: [ContentBlock]
    var isReplyMatch: Bool

    var id: String {
        "\(threadID)-\(postID ?? 0)"
    }

    var threadSummary: ThreadSummary {
        var summaryBlocks: [ContentBlock] = []
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedContent.isEmpty == false {
            summaryBlocks.append(.text(trimmedContent))
        }
        summaryBlocks.append(contentsOf: blocks)

        return ThreadSummary(
            id: threadID,
            forumID: forumID,
            title: title,
            author: author,
            forumName: forumName,
            forumAvatarURL: forumAvatarURL,
            replyCount: replyCount,
            viewCount: 0,
            likeCount: likeCount,
            createdAt: createdAt,
            lastReplyAt: createdAt,
            blocks: summaryBlocks,
            hasVideo: blocks.contains { block in
                if case .video = block { return true }
                return false
            }
        )
    }
}
