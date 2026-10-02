import Foundation

struct ThreadSummary: Identifiable, Equatable, Codable, Sendable {
    var id: Int64
    var forumID: Int64?
    var title: String
    var author: UserSummary
    var forumName: String?
    var forumAvatarURL: URL?
    var replyCount: Int
    var viewCount: Int
    var likeCount: Int
    var firstPostID: UInt64?
    var isLiked: Bool
    var createdAt: Date?
    var lastReplyAt: Date?
    var blocks: [ContentBlock]
    var isTop: Bool
    var isGood: Bool
    var hasVideo: Bool
    /// 热度 as the hot-thread endpoint reports it; nil for every other listing.
    /// Optional on purpose: saved threads written before this field existed must
    /// keep decoding.
    var hotValue: Int64?

    init(
        id: Int64,
        forumID: Int64? = nil,
        title: String,
        author: UserSummary,
        forumName: String? = nil,
        forumAvatarURL: URL? = nil,
        replyCount: Int,
        viewCount: Int,
        likeCount: Int = 0,
        firstPostID: UInt64? = nil,
        isLiked: Bool = false,
        createdAt: Date? = nil,
        lastReplyAt: Date? = nil,
        blocks: [ContentBlock],
        isTop: Bool = false,
        isGood: Bool = false,
        hasVideo: Bool = false,
        hotValue: Int64? = nil
    ) {
        self.id = id
        self.forumID = forumID
        self.title = title
        self.author = author
        self.forumName = forumName
        self.forumAvatarURL = forumAvatarURL
        self.replyCount = replyCount
        self.viewCount = viewCount
        self.likeCount = likeCount
        self.firstPostID = firstPostID
        self.isLiked = isLiked
        self.createdAt = createdAt
        self.lastReplyAt = lastReplyAt
        self.blocks = blocks
        self.isTop = isTop
        self.isGood = isGood
        self.hasVideo = hasVideo
        self.hotValue = hotValue
    }

    /// Ordering key for the merged 全部 listing; 0 means the endpoint did not
    /// report a 热度 value.
    var hotScore: Int64 { hotValue ?? 0 }

    var textPreview: String {
        blocks.compactMap(\.plainText).joined()
    }

    var mediaBlocks: [ContentBlock] {
        blocks.filter { block in
            if case .image = block { return true }
            if case .video = block { return true }
            return false
        }
    }

    var forumDisplayNameResolved: String? {
        guard let trimmed = normalizedForumName else { return nil }
        guard trimmed.isEmpty == false else { return nil }
        return trimmed.hasSuffix("吧") ? trimmed : "\(trimmed)吧"
    }

    var forumRoute: Forum? {
        guard let name = normalizedForumName, let displayName = forumDisplayNameResolved else {
            return nil
        }
        return Forum(
            id: forumID ?? 0,
            name: name,
            displayName: displayName,
            avatarURL: forumAvatarURL,
            memberCount: 0,
            threadCount: 0
        )
    }

    // The API's forum_name carries no "吧" suffix, so the routing name must
    // stay verbatim: forums genuinely named 网吧/酒吧 would otherwise be
    // routed to a different forum. Suffix handling belongs to display only.
    private var normalizedForumName: String? {
        guard let forumName else { return nil }
        let trimmed = forumName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct UserSummary: Identifiable, Equatable, Hashable, Codable, Sendable {
    var id: Int64
    var name: String
    var displayName: String
    var portrait: String
    var level: Int?
    var levelName: String?
    var ipAddress: String?

    init(
        id: Int64,
        name: String,
        displayName: String,
        portrait: String,
        level: Int? = nil,
        levelName: String? = nil,
        ipAddress: String? = nil
    ) {
        self.id = id
        self.name = name
        self.displayName = displayName
        self.portrait = portrait
        self.level = level
        self.levelName = levelName
        self.ipAddress = ipAddress
    }

    var displayNameResolved: String {
        let resolved = displayName.isEmpty ? name : displayName
        if resolved.isEmpty == false {
            return resolved
        }
        return id == 0 ? "未知用户" : "用户\(id)"
    }

    var portraitURL: URL? {
        TiebaURL.avatar(portrait)
    }
}

enum TiebaUserName {
    static func referenceText(_ value: String) -> String {
        var result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        while result.hasPrefix("@") {
            result.removeFirst()
            result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return result
    }

    static func normalized(_ value: String) -> String {
        referenceText(value)
            .precomposedStringWithCanonicalMapping
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: Locale(identifier: "zh_CN")
            )
    }
}
