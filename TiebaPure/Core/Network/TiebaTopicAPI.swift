import Foundation

/// The 话题 (topic) page behind one 话题榜 row.
///
/// The web endpoint answers JSON, so this is a plain `Decodable` DTO rather than
/// a protobuf message. Field names and paging behaviour were read off the live
/// service: it needs `is_new`/`is_share`, and `last_id` is the only parameter
/// that moves the feed (see `TopicThreadPage`).
struct TopicDetailResponseDTO: Decodable {
    struct AuthorDTO: Decodable {
        var id: Int64
        var name: String
        var displayName: String
        var portrait: String

        enum CodingKeys: String, CodingKey {
            case id
            case name
            case displayName = "name_show"
            case portrait
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = container.topicInt64(forKey: .id)
            name = container.topicString(forKey: .name)
            displayName = container.topicString(forKey: .displayName)
            portrait = container.topicString(forKey: .portrait)
        }
    }

    struct MediaDTO: Decodable {
        var type: String
        var thumbnail: String
        var original: String
        var width: Int
        var height: Int

        enum CodingKeys: String, CodingKey {
            case type
            case thumbnail = "small_pic"
            case original = "big_pic"
            case width
            case height
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            type = container.topicString(forKey: .type)
            thumbnail = container.topicString(forKey: .thumbnail)
            original = container.topicString(forKey: .original)
            // The service sends the dimensions as strings.
            width = container.topicInt(forKey: .width)
            height = container.topicInt(forKey: .height)
        }
    }

    struct ThreadInfoDTO: Decodable {
        var id: Int64
        var title: String
        var forumID: Int64
        var forumName: String
        var replyCount: Int
        var likeCount: Int
        var firstPostID: UInt64
        var createdAt: Int64
        var lastReplyAt: Int64
        var summary: String
        var author: AuthorDTO?
        var media: [MediaDTO]

        enum CodingKeys: String, CodingKey {
            case id = "tid"
            case title
            case forumID = "forum_id"
            case forumName = "forum_name"
            case replyCount = "reply_num"
            case likeCount = "agree_num"
            case firstPostID = "first_post_id"
            case createdAt = "create_time"
            case lastReplyAt = "last_time_int"
            case summary = "abstract"
            case author
            case media
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = container.topicInt64(forKey: .id)
            title = container.topicString(forKey: .title)
            forumID = container.topicInt64(forKey: .forumID)
            forumName = container.topicString(forKey: .forumName)
            replyCount = container.topicInt(forKey: .replyCount)
            likeCount = container.topicInt(forKey: .likeCount)
            firstPostID = UInt64(clamping: container.topicInt64(forKey: .firstPostID))
            createdAt = container.topicInt64(forKey: .createdAt)
            lastReplyAt = container.topicInt64(forKey: .lastReplyAt)
            summary = container.topicString(forKey: .summary)
            author = try? container.decodeIfPresent(AuthorDTO.self, forKey: .author)
            media = (try? container.decodeIfPresent([MediaDTO].self, forKey: .media)) ?? []
        }
    }

    struct ThreadItemDTO: Decodable {
        var feedID: String
        var threadInfo: ThreadInfoDTO?

        enum CodingKeys: String, CodingKey {
            case feedID = "feed_id"
            case threadInfo = "thread_info"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            // Next page's `last_id`. It matches the thread id, but the service
            // defines it as the feed id, so keep it verbatim.
            if let number = try? container.decode(Int64.self, forKey: .feedID) {
                feedID = "\(number)"
            } else {
                feedID = container.topicString(forKey: .feedID)
            }
            threadInfo = try? container.decodeIfPresent(ThreadInfoDTO.self, forKey: .threadInfo)
        }
    }

    struct RelateThreadDTO: Decodable {
        var threadList: [ThreadItemDTO]

        enum CodingKeys: String, CodingKey {
            case threadList = "thread_list"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            threadList = (try? container.decodeIfPresent([ThreadItemDTO].self, forKey: .threadList)) ?? []
        }
    }

    struct TopicInfoDTO: Decodable {
        var id: Int64
        var name: String
        var summary: String
        var discussCount: Int
        var browseCount: Int
        var image: String

        enum CodingKeys: String, CodingKey {
            case id = "topic_id"
            case name = "topic_name"
            case summary = "topic_desc"
            case discussCount = "discuss_num"
            case browseCount = "browse_num"
            case image = "topic_image"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = container.topicInt64(forKey: .id)
            name = container.topicString(forKey: .name)
            summary = container.topicString(forKey: .summary)
            discussCount = container.topicInt(forKey: .discussCount)
            browseCount = container.topicInt(forKey: .browseCount)
            image = container.topicString(forKey: .image)
        }
    }

    struct DataDTO: Decodable {
        var topicInfo: TopicInfoDTO?
        var relateThread: RelateThreadDTO?
        var hasMore: Bool

        enum CodingKeys: String, CodingKey {
            case topicInfo = "topic_info"
            case relateThread = "relate_thread"
            case hasMore = "has_more"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            topicInfo = try? container.decodeIfPresent(TopicInfoDTO.self, forKey: .topicInfo)
            relateThread = try? container.decodeIfPresent(RelateThreadDTO.self, forKey: .relateThread)
            hasMore = container.topicBool(forKey: .hasMore)
        }
    }

    var code: Int
    var message: String
    var data: DataDTO?

    enum CodingKeys: String, CodingKey {
        case code = "no"
        case message = "error"
        case data
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        code = container.topicInt(forKey: .code)
        message = container.topicString(forKey: .message)
        data = try? container.decodeIfPresent(DataDTO.self, forKey: .data)
    }
}

enum TopicMapper {
    static func info(from dto: TopicDetailResponseDTO.TopicInfoDTO?) -> TopicInfo? {
        guard let dto, dto.id > 0, dto.name.isEmpty == false else { return nil }
        let image = TiebaURL.make(dto.image)
        return TopicInfo(
            id: dto.id,
            name: dto.name,
            summary: dto.summary,
            discussCount: max(dto.discussCount, 0),
            browseCount: max(dto.browseCount, 0),
            imageURL: image
        )
    }

    static func threads(from data: TopicDetailResponseDTO.DataDTO) -> [ThreadSummary] {
        (data.relateThread?.threadList ?? []).compactMap { item in
            guard let info = item.threadInfo else { return nil }
            return thread(from: info)
        }
    }

    /// The cursor for the next page: the last row's feed id, as the service
    /// expects it back in `last_id`.
    static func cursor(from data: TopicDetailResponseDTO.DataDTO) -> String? {
        let ids = (data.relateThread?.threadList ?? [])
            .map(\.feedID)
            .filter { $0.isEmpty == false }
        return ids.last
    }

    private static func thread(from info: TopicDetailResponseDTO.ThreadInfoDTO) -> ThreadSummary? {
        guard info.id > 0 else { return nil }
        var blocks: [ContentBlock] = []
        let summary = info.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        if summary.isEmpty == false {
            blocks.append(.text(summary))
        }
        blocks.append(contentsOf: imageBlocks(from: info.media))

        let author = info.author
        return ThreadSummary(
            id: info.id,
            forumID: info.forumID > 0 ? info.forumID : nil,
            title: info.title,
            author: UserSummary(
                id: author?.id ?? 0,
                name: author?.name ?? "",
                displayName: author?.displayName ?? "",
                portrait: author?.portrait ?? ""
            ),
            forumName: info.forumName.isEmpty ? nil : info.forumName,
            forumAvatarURL: nil,
            replyCount: max(info.replyCount, 0),
            viewCount: 0,
            likeCount: max(info.likeCount, 0),
            firstPostID: info.firstPostID > 0 ? info.firstPostID : nil,
            isLiked: false,
            createdAt: info.createdAt > 0 ? Date(timeIntervalSince1970: TimeInterval(info.createdAt)) : nil,
            lastReplyAt: info.lastReplyAt > 0 ? Date(timeIntervalSince1970: TimeInterval(info.lastReplyAt)) : nil,
            blocks: blocks,
            isTop: false,
            isGood: false,
            hasVideo: false
        )
    }

    /// Only image rows render: a topic feed mixes videos in, and turning one of
    /// those into a row needs the video payload this endpoint does not carry.
    private static func imageBlocks(from media: [TopicDetailResponseDTO.MediaDTO]) -> [ContentBlock] {
        media.compactMap { item in
            guard item.type == "pic" else { return nil }
            let thumbnail = TiebaURL.make(item.thumbnail)
            let original = TiebaURL.make(item.original)
            guard thumbnail != nil || original != nil else { return nil }
            return .image(ImageContent(
                thumbnailURL: thumbnail,
                originalURL: original,
                width: max(item.width, 0),
                height: max(item.height, 0),
                showOriginalButton: false
            ))
        }
    }
}

extension TiebaAPI {
    /// One page of a 话题's thread feed. `cursor` is empty for the first page and
    /// otherwise the previous page's `nextCursor`.
    func topicThreads(
        account: Account?,
        topicID: Int64,
        topicName: String,
        cursor: String,
        page: Int,
        pageSize: Int = TopicPagePolicy.pageSize
    ) async throws -> TopicThreadPage {
        let resolvedPage = max(page, 1)
        let resolvedSize = max(pageSize, 1)
        let queryItems: [URLQueryItem] = [
            URLQueryItem(name: "topic_id", value: "\(topicID)"),
            URLQueryItem(name: "topic_name", value: topicName),
            URLQueryItem(name: "is_new", value: "1"),
            URLQueryItem(name: "is_share", value: "1"),
            URLQueryItem(name: "pn", value: "\(resolvedPage)"),
            URLQueryItem(name: "rn", value: "\(resolvedSize)"),
            URLQueryItem(name: "offset", value: "\((resolvedPage - 1) * resolvedSize)"),
            URLQueryItem(name: "last_id", value: cursor)
        ]
        let response = try await client.getJSON(
            .topicDetail,
            queryItems: queryItems,
            headers: [
                "Cookie": TiebaFeedCookie.value(for: account),
                "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 16_4 like Mac OS X)"
            ],
            as: TopicDetailResponseDTO.self
        )
        try TiebaResponseValidator.validate(code: response.code, message: response.message)
        guard let data = response.data else { throw TiebaAPIError.emptyResponse }

        let threads = TopicMapper.threads(from: data)
        let nextCursor = TopicMapper.cursor(from: data) ?? cursor
        await AppLog.shared.record(
            .info,
            "话题",
            "话题\(topicID) 第\(resolvedPage)页 原始\(data.relateThread?.threadList.count ?? 0)条 "
                + "保留\(threads.count)条 has_more=\(data.hasMore) "
                + "下一游标=\(nextCursor.isEmpty ? "(无)" : "有")"
        )
        return TopicThreadPage(
            info: TopicMapper.info(from: data.topicInfo),
            threads: threads,
            hasMore: data.hasMore,
            nextCursor: nextCursor
        )
    }
}

/// The topic payload mixes strings and numbers for the same field (`discuss_num`
/// arrives as both), so every scalar goes through a tolerant reader. Named apart
/// from the other files' private helpers: those are file-scoped, and this one has
/// to stay local to the JSON decoding in this file.
private extension KeyedDecodingContainer {
    func topicString(forKey key: Key) -> String {
        if let value = try? decodeIfPresent(String.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(Int64.self, forKey: key) { return String(value) }
        if let value = try? decodeIfPresent(Double.self, forKey: key) { return String(value) }
        return ""
    }

    func topicInt(forKey key: Key) -> Int {
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(Int64.self, forKey: key) { return Int(clamping: value) }
        if let value = try? decodeIfPresent(String.self, forKey: key) { return Int(value) ?? 0 }
        return 0
    }

    func topicInt64(forKey key: Key) -> Int64 {
        if let value = try? decodeIfPresent(Int64.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return Int64(value) }
        if let value = try? decodeIfPresent(String.self, forKey: key) { return Int64(value) ?? 0 }
        return 0
    }

    func topicBool(forKey key: Key) -> Bool {
        if let value = try? decodeIfPresent(Bool.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return value != 0 }
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return value == "1" || value.lowercased() == "true"
        }
        return false
    }
}
