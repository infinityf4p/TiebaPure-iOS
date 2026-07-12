import Foundation

struct ThreadSummary: Identifiable, Equatable, Sendable {
    var id: Int64
    var forumID: Int64?
    var title: String
    var author: UserSummary
    var forumName: String?
    var forumAvatarURL: URL?
    var replyCount: Int
    var viewCount: Int
    var likeCount: Int
    var createdAt: Date?
    var lastReplyAt: Date?
    var blocks: [ContentBlock]
    var isTop: Bool
    var isGood: Bool
    var hasVideo: Bool

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
        createdAt: Date? = nil,
        lastReplyAt: Date? = nil,
        blocks: [ContentBlock],
        isTop: Bool = false,
        isGood: Bool = false,
        hasVideo: Bool = false
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
        self.createdAt = createdAt
        self.lastReplyAt = lastReplyAt
        self.blocks = blocks
        self.isTop = isTop
        self.isGood = isGood
        self.hasVideo = hasVideo
    }

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

    private var normalizedForumName: String? {
        guard let forumName else { return nil }
        let trimmed = forumName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return nil }
        if trimmed.hasSuffix("吧") {
            return String(trimmed.dropLast())
        }
        return trimmed
    }
}

struct UserSummary: Identifiable, Equatable, Sendable {
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
