import Foundation

extension TiebaAPI {
    func searchThreads(
        keyword: String,
        page: Int,
        sortType: Int = 5,
        filterType: Int = 2,
        forumName: String? = nil,
        pageSize: Int = 30
    ) async throws -> SearchResultsPage {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            return SearchResultsPage(results: [], currentPage: 1, hasMore: false)
        }

        var queryItems: [URLQueryItem] = [
            .init(name: "word", value: trimmed),
            .init(name: "pn", value: "\(page)"),
            .init(name: "st", value: "\(sortType)"),
            .init(name: "tt", value: "\(filterType)")
        ]

        let referer: String
        if let forumName, forumName.isEmpty == false {
            let encodedForumName = forumName.tiebaRefererQueryEscaped
            queryItems.append(contentsOf: [
                .init(name: "rn", value: "\(pageSize)"),
                .init(name: "fname", value: forumName),
                .init(name: "ct", value: "2"),
                .init(name: "cv", value: "12.52.1.0")
            ])
            referer = "https://tieba.baidu.com/mo/q/hybrid-usergrow-search/searchGlobal?entryPage=frs&forumName=\(encodedForumName)"
        } else {
            let encodedKeyword = trimmed.tiebaRefererQueryEscaped
            queryItems.append(contentsOf: [
                .init(name: "ct", value: "1"),
                .init(name: "cv", value: "99.9.101")
            ])
            referer = "https://tieba.baidu.com/mo/q/hybrid/search?keyword=\(encodedKeyword)"
        }

        let response = try await client.getJSON(
            .searchThread,
            queryItems: queryItems,
            headers: [
                "User-Agent": "tieba/12.52.1.0 skin/default",
                "Referer": referer
            ],
            as: SearchThreadResponseDTO.self
        )

        if response.errorCode != 0 {
            throw TiebaAPIError.response(code: response.errorCode, message: response.errorMessage)
        }

        return SearchResultsPage(
            results: response.data.postList.map(\.searchResult),
            currentPage: response.data.currentPage,
            hasMore: response.data.hasMore == 1
        )
    }
}

private extension String {
    var tiebaRefererQueryEscaped: String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=?+#")
        return addingPercentEncoding(withAllowedCharacters: allowed) ?? self
    }
}

private struct SearchThreadResponseDTO: Decodable {
    var errorCode: Int
    var errorMessage: String
    var data: DataDTO

    enum CodingKeys: String, CodingKey {
        case errorCode = "no"
        case errorMessage = "error"
        case data
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        errorCode = Int(container.decodeStringIfPresent(forKey: .errorCode) ?? "") ?? 0
        errorMessage = container.decodeStringIfPresent(forKey: .errorMessage) ?? ""
        data = try container.decodeIfPresent(DataDTO.self, forKey: .data) ?? DataDTO()
    }

    struct DataDTO: Decodable {
        var hasMore: Int = 0
        var currentPage: Int = 1
        var postList: [ThreadInfoDTO] = []

        enum CodingKeys: String, CodingKey {
            case hasMore = "has_more"
            case currentPage = "current_page"
            case postList = "post_list"
        }

        init() {}

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            hasMore = Int(container.decodeStringIfPresent(forKey: .hasMore) ?? "") ?? 0
            currentPage = Int(container.decodeStringIfPresent(forKey: .currentPage) ?? "") ?? 1
            postList = try container.decodeIfPresent([ThreadInfoDTO].self, forKey: .postList) ?? []
        }
    }

    struct ThreadInfoDTO: Decodable {
        var threadID: Int64
        var postID: UInt64?
        var title: String
        var content: String
        var createdAt: Date?
        var replyCount: Int
        var likeCount: Int
        var shareCount: Int
        var forumID: Int64?
        var forumName: String
        var user: UserDTO
        var forumInfo: ForumDTO?
        var media: [MediaDTO]
        var mainPost: MainPostDTO?
        var postInfo: PostInfoDTO?

        enum CodingKeys: String, CodingKey {
            case tid
            case pid
            case title
            case content
            case time
            case replyCount = "post_num"
            case likeCount = "like_num"
            case shareCount = "share_num"
            case forumID = "forum_id"
            case forumName = "forum_name"
            case user
            case forumInfo = "forum_info"
            case media
            case mainPost = "main_post"
            case postInfo = "post_info"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            threadID = Int64(container.decodeStringIfPresent(forKey: .tid) ?? "") ?? 0
            postID = UInt64(container.decodeStringIfPresent(forKey: .pid) ?? "")
            title = container.decodeStringIfPresent(forKey: .title) ?? ""
            content = container.decodeStringIfPresent(forKey: .content) ?? ""
            createdAt = container.decodeDateIfPresent(forKey: .time)
            replyCount = Int(container.decodeStringIfPresent(forKey: .replyCount) ?? "") ?? 0
            likeCount = Int(container.decodeStringIfPresent(forKey: .likeCount) ?? "") ?? 0
            shareCount = Int(container.decodeStringIfPresent(forKey: .shareCount) ?? "") ?? 0
            forumID = Int64(container.decodeStringIfPresent(forKey: .forumID) ?? "")
            forumName = container.decodeStringIfPresent(forKey: .forumName) ?? ""
            user = try container.decodeIfPresent(UserDTO.self, forKey: .user) ?? UserDTO()
            forumInfo = try container.decodeIfPresent(ForumDTO.self, forKey: .forumInfo)
            media = try container.decodeIfPresent([MediaDTO].self, forKey: .media) ?? []
            mainPost = try container.decodeIfPresent(MainPostDTO.self, forKey: .mainPost)
            postInfo = try container.decodeIfPresent(PostInfoDTO.self, forKey: .postInfo)
        }

        var searchResult: SearchResult {
            let resolvedForumName = forumName.isEmpty ? forumInfo?.forumName ?? "" : forumName
            let resolvedTitle = title.isEmpty ? mainPost?.title ?? postInfo?.title ?? "" : title
            let resolvedContent = content.isEmpty ? postInfo?.content ?? mainPost?.content ?? "" : content
            return SearchResult(
                threadID: threadID,
                postID: postID == 0 ? nil : postID,
                forumID: forumID,
                forumName: resolvedForumName,
                forumAvatarURL: TiebaURL.make(forumInfo?.avatar),
                title: TiebaEmoticon.plainDisplayText(resolvedTitle),
                content: TiebaEmoticon.plainDisplayText(resolvedContent),
                author: user.summary,
                createdAt: createdAt,
                replyCount: replyCount,
                likeCount: likeCount,
                shareCount: shareCount,
                blocks: media.compactMap(\.contentBlock),
                isReplyMatch: postInfo != nil
            )
        }
    }

    struct UserDTO: Decodable {
        var id: Int64 = 0
        var name: String = ""
        var displayName: String = ""
        var portrait: String = ""

        enum CodingKeys: String, CodingKey {
            case userID = "user_id"
            case userName = "user_name"
            case showNickname = "show_nickname"
            case portrait
        }

        init() {}

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = Int64(container.decodeStringIfPresent(forKey: .userID) ?? "") ?? 0
            name = container.decodeStringIfPresent(forKey: .userName) ?? ""
            displayName = container.decodeStringIfPresent(forKey: .showNickname) ?? name
            portrait = container.decodeStringIfPresent(forKey: .portrait) ?? ""
        }

        var summary: UserSummary {
            UserSummary(id: id, name: name, displayName: displayName, portrait: portrait)
        }
    }

    struct ForumDTO: Decodable {
        var forumName: String
        var avatar: String

        enum CodingKeys: String, CodingKey {
            case forumName = "forum_name"
            case avatar
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            forumName = container.decodeStringIfPresent(forKey: .forumName) ?? ""
            avatar = container.decodeStringIfPresent(forKey: .avatar) ?? ""
        }
    }

    struct MainPostDTO: Decodable {
        var title: String
        var content: String

        enum CodingKeys: String, CodingKey {
            case title
            case content
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            title = container.decodeStringIfPresent(forKey: .title) ?? ""
            content = container.decodeStringIfPresent(forKey: .content) ?? ""
        }
    }

    struct PostInfoDTO: Decodable {
        var title: String
        var content: String

        enum CodingKeys: String, CodingKey {
            case title
            case content
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            title = container.decodeStringIfPresent(forKey: .title) ?? ""
            content = container.decodeStringIfPresent(forKey: .content) ?? ""
        }
    }

    struct MediaDTO: Decodable {
        var type: String
        var width: Int
        var height: Int
        var waterPic: URL?
        var smallPic: URL?
        var bigPic: URL?
        var src: URL?
        var videoURL: URL?
        var highVideoURL: URL?
        var videoCoverURL: URL?

        enum CodingKeys: String, CodingKey {
            case type
            case width
            case height
            case waterPic = "water_pic"
            case smallPic = "small_pic"
            case bigPic = "big_pic"
            case src
            case videoURL = "vsrc"
            case highVideoURL = "vhsrc"
            case videoCoverURL = "vpic"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            type = container.decodeStringIfPresent(forKey: .type) ?? ""
            width = Int(container.decodeStringIfPresent(forKey: .width) ?? "") ?? 1
            height = Int(container.decodeStringIfPresent(forKey: .height) ?? "") ?? 1
            waterPic = TiebaURL.make(container.decodeStringIfPresent(forKey: .waterPic))
            smallPic = TiebaURL.make(container.decodeStringIfPresent(forKey: .smallPic))
            bigPic = TiebaURL.make(container.decodeStringIfPresent(forKey: .bigPic))
            src = TiebaURL.make(container.decodeStringIfPresent(forKey: .src))
            videoURL = TiebaURL.make(container.decodeStringIfPresent(forKey: .videoURL))
            highVideoURL = TiebaURL.make(container.decodeStringIfPresent(forKey: .highVideoURL))
            videoCoverURL = TiebaURL.make(container.decodeStringIfPresent(forKey: .videoCoverURL))
        }

        var contentBlock: ContentBlock? {
            if type == "flash" {
                return .video(VideoContent(
                    videoURL: highVideoURL ?? videoURL,
                    coverURL: videoCoverURL ?? bigPic ?? smallPic,
                    webURL: nil,
                    width: width,
                    height: height,
                    duration: 0
                ))
            }

            guard type == "pic" else { return nil }
            return .image(ImageContent(
                thumbnailURL: bigPic ?? smallPic ?? waterPic ?? src,
                originalURL: src ?? bigPic ?? smallPic ?? waterPic,
                width: width,
                height: height,
                showOriginalButton: true
            ))
        }
    }
}

private extension KeyedDecodingContainer {
    func decodeStringIfPresent(forKey key: Key) -> String? {
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return value
        }
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return String(value)
        }
        if let value = try? decodeIfPresent(Int64.self, forKey: key) {
            return String(value)
        }
        if let value = try? decodeIfPresent(UInt64.self, forKey: key) {
            return String(value)
        }
        if let value = try? decodeIfPresent(Double.self, forKey: key) {
            return String(value)
        }
        return nil
    }

    func decodeDateIfPresent(forKey key: Key) -> Date? {
        guard let text = decodeStringIfPresent(forKey: key), let seconds = TimeInterval(text) else {
            return nil
        }
        return Date(timeIntervalSince1970: seconds)
    }
}
