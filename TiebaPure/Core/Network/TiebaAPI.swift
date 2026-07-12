import Foundation

struct TiebaAPI {
    var client: TiebaHTTPClient
    var requestBuilder = TiebaRequestBuilder.live()

    func validateLogin(cookies: BaiduCookies) async throws -> Account {
        let loginResponse: LoginResponseDTO?
        do {
            loginResponse = try await login(bduss: cookies.bduss, stoken: cookies.stoken)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            loginResponse = nil
        }
        try Task.checkCancellation()

        let nickname: InitNicknameResponseDTO?
        do {
            nickname = try await initNickname(bduss: cookies.bduss, stoken: cookies.stoken)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            nickname = nil
        }
        try Task.checkCancellation()

        if let account = account(from: loginResponse, nickname: nickname, cookies: cookies) {
            return account
        }

        let webInfo = try await webMyInfo(cookies: cookies)
        guard let account = account(from: webInfo, fallbackTBS: loginResponse?.anti?.tbs, cookies: cookies) else {
            throw LoginValidationError.missingAccountInfo
        }
        return account
    }

    func login(bduss: String, stoken: String) async throws -> LoginResponseDTO {
        try await client.postForm(
            .login,
            fields: [
                "bdusstoken": "\(bduss)|",
                "stoken": stoken,
                "channel_id": "",
                "channel_uid": "",
                "_client_version": "11.10.8.6",
                "authsid": "null"
            ],
            headers: [
                "Cookie": "ka=open",
                "User-Agent": "bdtb for Android 11.10.8.6"
            ],
            as: LoginResponseDTO.self
        )
    }

    func initNickname(bduss: String, stoken: String) async throws -> InitNicknameResponseDTO {
        try await client.postForm(
            .initNickname,
            fields: [
                "BDUSS": bduss,
                "stoken": stoken,
                "_client_version": "11.10.8.6"
            ],
            headers: [
                "Cookie": "ka=open",
                "User-Agent": "bdtb for Android 11.10.8.6"
            ],
            as: InitNicknameResponseDTO.self
        )
    }

    func webMyInfo(cookies: BaiduCookies) async throws -> WebMyInfoResponseDTO {
        try await client.getJSON(
            .webMyInfo,
            queryItems: [.init(name: "need_user", value: "1")],
            headers: [
                "Cookie": cookies.minimalCookieHeader,
                "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Mobile/15E148 Safari/604.1"
            ],
            as: WebMyInfoResponseDTO.self
        )
    }

    private func account(
        from login: LoginResponseDTO?,
        nickname: InitNicknameResponseDTO?,
        cookies: BaiduCookies
    ) -> Account? {
        guard let user = login?.user,
              let tbs = login?.anti?.tbs,
              user.id.isEmpty == false,
              tbs.isEmpty == false else {
            return nil
        }

        let displayName = firstNonEmpty(nickname?.userInfo?.nameShow, user.name)
        return Account(
            uid: user.id,
            name: firstNonEmpty(user.name, displayName, user.id),
            displayName: firstNonEmpty(displayName, user.name, user.id),
            portrait: user.portrait,
            bduss: cookies.bduss,
            stoken: cookies.stoken,
            baiduID: cookies.baiduID,
            tbs: tbs
        )
    }

    private func account(
        from webInfo: WebMyInfoResponseDTO,
        fallbackTBS: String?,
        cookies: BaiduCookies
    ) -> Account? {
        guard let data = webInfo.data,
              data.isLogin != false,
              let uid = firstNonEmpty(data.uid, data.id).nonEmpty,
              let tbs = firstNonEmpty(data.tbs, data.itbTbs, fallbackTBS).nonEmpty else {
            return nil
        }

        let name = firstNonEmpty(data.name, data.nameShow, uid)
        let displayName = firstNonEmpty(data.nameShow, data.name, uid)
        return Account(
            uid: uid,
            name: name,
            displayName: displayName,
            portrait: firstNonEmpty(data.portrait, data.portraitURL),
            bduss: cookies.bduss,
            stoken: cookies.stoken,
            baiduID: cookies.baiduID,
            tbs: tbs
        )
    }

    private func firstNonEmpty(_ values: String?...) -> String {
        values.compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { $0.isEmpty == false } ?? ""
    }
}

struct LoginResponseDTO: Decodable {
    struct User: Decodable {
        var id: String
        var name: String
        var portrait: String
    }

    struct Anti: Decodable {
        var tbs: String
    }

    var user: User?
    var anti: Anti?
    var errorCode: String?
    var errorMessage: String?

    enum CodingKeys: String, CodingKey {
        case user
        case anti
        case errorCode = "error_code"
        case errorMessage = "error_msg"
    }
}

struct InitNicknameResponseDTO: Decodable {
    struct UserInfo: Decodable {
        var nameShow: String
        var tiebaUid: String?
        var userName: String?
        var userNickname: String?

        enum CodingKeys: String, CodingKey {
            case nameShow = "name_show"
            case tiebaUid = "tieba_uid"
            case userName = "user_name"
            case userNickname = "user_nickname"
        }
    }

    var userInfo: UserInfo?

    enum CodingKeys: String, CodingKey {
        case userInfo = "user_info"
    }
}

struct WebMyInfoResponseDTO: Decodable {
    struct DataDTO: Decodable {
        var id: String?
        var uid: String?
        var name: String?
        var nameShow: String?
        var portrait: String?
        var portraitURL: String?
        var tbs: String?
        var itbTbs: String?
        var isLogin: Bool?

        enum CodingKeys: String, CodingKey {
            case id
            case uid
            case name
            case nameShow = "name_show"
            case portrait
            case portraitURL = "portrait_url"
            case tbs
            case itbTbs = "itb_tbs"
            case isLogin = "is_login"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = container.decodeStringIfPresent(forKey: .id)
            uid = container.decodeStringIfPresent(forKey: .uid)
            name = container.decodeStringIfPresent(forKey: .name)
            nameShow = container.decodeStringIfPresent(forKey: .nameShow)
            portrait = container.decodeStringIfPresent(forKey: .portrait)
            portraitURL = container.decodeStringIfPresent(forKey: .portraitURL)
            tbs = container.decodeStringIfPresent(forKey: .tbs)
            itbTbs = container.decodeStringIfPresent(forKey: .itbTbs)
            isLogin = try? container.decodeIfPresent(Bool.self, forKey: .isLogin)
            if isLogin == nil, let text = container.decodeStringIfPresent(forKey: .isLogin) {
                isLogin = text != "0" && text.lowercased() != "false"
            }
        }
    }

    var no: Int?
    var error: String?
    var data: DataDTO?
}

enum LoginValidationError: Error, Equatable, CustomStringConvertible {
    case missingAccountInfo

    var description: String {
        switch self {
        case .missingAccountInfo:
            return "登录 Cookie 已获取，但贴吧没有返回可用的账号资料，请重新登录。"
        }
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}

extension TiebaAPI {
    func personalizedThreads(account: Account?, page: Int, loadType: Int) async throws -> [ThreadSummary] {
        var requestData = Tieba_PersonalizedRequestData()
        requestData.appPos = Tieba_AppPosInfo()
        requestData.common = requestBuilder.common(account: account)
        requestData.loadType = UInt32(loadType)
        requestData.pn = UInt32(page)
        requestData.needTags = 0
        requestData.pageThreadCount = 11
        requestData.preAdThreadCount = 0
        requestData.sugCount = 0
        requestData.tagCode = 0
        requestData.qType = 1
        requestData.needForumlist = 0
        requestData.newNetType = 1
        requestData.newInstall = 0
        requestData.requestTimes = 0
        requestData.invokeSource = ""
        requestData.scrDip = requestBuilder.screenScale
        requestData.scrH = Int32(requestBuilder.screenHeight)
        requestData.scrW = Int32(requestBuilder.screenWidth)

        var request = Tieba_PersonalizedRequest()
        request.data = requestData

        let multipart = try requestBuilder.multipart(protobuf: request, account: account, includeSToken: false)
        let response = try await client.postProtobuf(
            .personalized,
            body: multipart.body,
            contentType: multipart.contentType,
            headers: [
                "X-BD-DATA-TYPE": "protobuf",
                "Cookie": "ka=open"
            ],
            as: Tieba_PersonalizedResponse.self
        )

        try validateTiebaError(response.error)

        return response.data.threadList
            .filter(TiebaContentFilter.shouldKeep(thread:))
            .map { ThreadMapper.fromThreadInfo($0, usersByID: [:]) }
    }

    func followedForums(account: Account) async throws -> [Forum] {
        let response = try await client.postForm(
            .followedForums,
            fields: [
                "BDUSS": account.bduss,
                "stoken": account.stoken,
                "user_id": account.uid,
                "_client_version": "11.10.8.6"
            ],
            headers: ["User-Agent": "bdtb for Android 11.10.8.6"],
            as: FollowedForumsDTO.self
        )

        try validateResponseCode(response.errorCode, message: response.errorMessage)

        return response.forums.map(ForumMapper.fromFollowedForum)
    }

    func forumThreads(account: Account?, forumName: String, page: Int, sortType: Int = 0) async throws -> [ThreadSummary] {
        guard let account else {
            return try await forumThreadsForm(forumName: forumName, page: page, sortType: sortType)
        }

        do {
            return try await forumThreadsProtobuf(account: account, forumName: forumName, page: page, sortType: sortType)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            guard Self.shouldFallbackFromForumProtobuf(error) else { throw error }
            return try await forumThreadsForm(forumName: forumName, page: page, sortType: sortType)
        }
    }

    private func forumThreadsProtobuf(account: Account, forumName: String, page: Int, sortType: Int) async throws -> [ThreadSummary] {
        var requestData = Tieba_FrsPage_FrsPageRequestData()
        requestData.adParam = Tieba_FrsPage_AdParam()
        requestData.appPos = Tieba_AppPosInfo()
        requestData.common = requestBuilder.common(account: account)
        requestData.kw = forumName
        requestData.loadType = page == 1 ? 1 : 2
        requestData.pn = Int32(page)
        requestData.qType = 2
        requestData.rn = 90
        requestData.rnNeed = 30
        requestData.scrDip = requestBuilder.screenScale
        requestData.scrH = Int32(requestBuilder.screenHeight)
        requestData.scrW = Int32(requestBuilder.screenWidth)
        requestData.sortType = Int32(sortType)
        requestData.stType = "recom_flist"
        requestData.withGroup = 1

        var request = Tieba_FrsPage_FrsPageRequest()
        request.data = requestData

        let multipart = try requestBuilder.multipart(protobuf: request, account: account, includeSToken: true)
        let response = try await client.postProtobuf(
            .frsPage,
            body: multipart.body,
            contentType: multipart.contentType,
            headers: ["forum_name": forumName],
            as: Tieba_FrsPage_FrsPageResponse.self
        )
        try validateTiebaError(response.error)

        var usersByID: [Int64: Tieba_User] = [:]
        for user in response.data.userList {
            usersByID[user.id] = user
        }

        return response.data.threadList
            .filter(TiebaContentFilter.shouldKeep(thread:))
            .map { ThreadMapper.fromThreadInfo($0, usersByID: usersByID) }
    }

    private func forumThreadsForm(forumName: String, page: Int, sortType: Int) async throws -> [ThreadSummary] {
        let cuid = requestBuilder.miniCUID
        var fields = requestBuilder.miniCommonFields()
        fields.merge([
            "kw": forumName,
            "pn": "\(page)",
            "sort_type": "\(sortType)",
            "q_type": "2",
            "st_type": "tb_forumlist",
            "with_group": "0",
            "rn": "20",
            "scr_dip": "\(requestBuilder.screenScale)",
            "scr_h": "\(requestBuilder.screenHeight)",
            "scr_w": "\(requestBuilder.screenWidth)"
        ]) { current, _ in current }

        let response = try await client.postForm(
            .forumPageForm,
            fields: fields,
            headers: [
                "User-Agent": "bdtb for Android \(TiebaClientVersion.mini.rawValue)",
                "Cookie": "ka=open",
                "Pragma": "no-cache",
                "cuid": cuid,
                "cuid_galaxy2": cuid
            ],
            signingSecret: "tiebaclient!!!",
            as: MiniForumPageDTO.self
        )

        if response.errorCode != 0 {
            throw TiebaAPIError.response(code: response.errorCode, message: response.errorMessage)
        }

        return response.threadList
            .filter(\.shouldKeep)
            .map { $0.threadSummary(usersByID: response.usersByID, forumName: forumName) }
    }
}

extension TiebaAPI {
    func threadPage(
        account: Account?,
        threadID: Int64,
        page: Int,
        forumID: Int64? = nil,
        postID: UInt64? = nil,
        seeLz: Bool = false,
        sortType: ThreadReplySort = .ascending
    ) async throws -> ThreadPage {
        var requestData = Tieba_PbPage_PbPageRequestData()
        requestData.common = requestBuilder.common(account: account)
        requestData.kz = threadID
        requestData.pn = Int32(page)
        requestData.r = Int32(sortType.rawValue)
        if let postID {
            requestData.pid = Int64(postID)
        }
        requestData.lz = seeLz ? 1 : 0
        requestData.forumID = forumID ?? 0
        requestData.mark = 0
        requestData.floorRn = 4
        requestData.floorSortType = 1
        requestData.qType = 2
        requestData.rn = 15
        requestData.scrDip = requestBuilder.screenScale
        requestData.scrH = Int32(requestBuilder.screenHeight)
        requestData.scrW = Int32(requestBuilder.screenWidth)
        requestData.sourceType = 2
        requestData.withFloor = 1

        var request = Tieba_PbPage_PbPageRequest()
        request.data = requestData

        let multipart = try requestBuilder.multipart(protobuf: request, account: account, includeSToken: true)
        let response = try await client.postProtobuf(
            .pbPage,
            body: multipart.body,
            contentType: multipart.contentType,
            as: Tieba_PbPage_PbPageResponse.self
        )
        try validateTiebaError(response.error)
        return PostMapper.threadPage(from: response)
    }

    func subposts(
        account: Account?,
        threadID: Int64,
        postID: UInt64,
        forumID: Int64,
        page: Int,
        subpostID: UInt64 = 0
    ) async throws -> [Subpost] {
        var requestData = Tieba_PbFloor_PbFloorRequestData()
        requestData.common = requestBuilder.common(account: account)
        requestData.forumID = forumID
        requestData.kz = threadID
        requestData.pid = Int64(postID)
        requestData.pn = Int32(page)
        requestData.spid = Int64(subpostID)
        requestData.scrDip = requestBuilder.screenScale
        requestData.scrH = Int32(requestBuilder.screenHeight)
        requestData.scrW = Int32(requestBuilder.screenWidth)
        requestData.isCommReverse = 0
        requestData.oriUgcType = 0

        var request = Tieba_PbFloor_PbFloorRequest()
        request.data = requestData

        let multipart = try requestBuilder.multipart(protobuf: request, account: account, includeSToken: false)
        let response = try await client.postProtobuf(
            .pbFloor,
            body: multipart.body,
            contentType: multipart.contentType,
            as: Tieba_PbFloor_PbFloorResponse.self
        )
        try validateTiebaError(response.error)
        return response.data.subpostList.map(PostMapper.subpost(from:))
    }

    static func shouldFallbackFromForumProtobuf(_ error: Error) -> Bool {
        if error is CancellationError || error is URLError || error is TiebaHTTPError || error is TiebaAPIError {
            return false
        }
        return error is DecodingError
            || String(reflecting: type(of: error)).contains("BinaryDecodingError")
    }

    private func validateTiebaError(_ error: Tieba_Error) throws {
        try validateResponseCode(
            Int(error.errorCode),
            message: error.userMsg.isEmpty ? error.errorMsg : error.userMsg
        )
    }

    private func validateResponseCode(_ code: Int, message: String) throws {
        try TiebaResponseValidator.validate(code: code, message: message)
    }
}

struct FollowedForumsDTO: Decodable {
    struct ForumDTO: Decodable {
        var id: Int64
        var name: String
        var avatar: String?

        enum CodingKeys: String, CodingKey {
            case forumID = "forum_id"
            case forumName = "forum_name"
            case avatar
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let idText = container.decodeStringIfPresent(forKey: .forumID) ?? "0"
            id = Int64(idText) ?? 0
            name = container.decodeStringIfPresent(forKey: .forumName) ?? ""
            avatar = try container.decodeIfPresent(String.self, forKey: .avatar)
        }
    }

    var forums: [ForumDTO]
    var errorCode: Int
    var errorMessage: String

    enum CodingKeys: String, CodingKey {
        case forumInfo = "forum_info"
        case errorCode = "error_code"
        case errorMessage = "error_msg"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        forums = try container.decodeIfPresent([ForumDTO].self, forKey: .forumInfo) ?? []
        errorCode = Int(container.decodeStringIfPresent(forKey: .errorCode) ?? "") ?? 0
        errorMessage = container.decodeStringIfPresent(forKey: .errorMessage) ?? ""
    }
}

private struct MiniForumPageDTO: Decodable {
    var errorCode: Int
    var errorMessage: String
    var threadList: [ThreadDTO]
    var userList: [UserDTO]

    var usersByID: [Int64: UserDTO] {
        var result: [Int64: UserDTO] = [:]
        for user in userList {
            result[user.id] = user
        }
        return result
    }

    enum CodingKeys: String, CodingKey {
        case errorCode = "error_code"
        case errorMessage = "error_msg"
        case threadList = "thread_list"
        case userList = "user_list"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        errorCode = Int(container.decodeStringIfPresent(forKey: .errorCode) ?? "") ?? 0
        errorMessage = container.decodeStringIfPresent(forKey: .errorMessage) ?? ""
        threadList = try container.decodeIfPresent([ThreadDTO].self, forKey: .threadList) ?? []
        userList = try container.decodeIfPresent([UserDTO].self, forKey: .userList) ?? []
    }

    struct UserDTO: Decodable {
        var id: Int64
        var name: String
        var displayName: String
        var portrait: String

        enum CodingKeys: String, CodingKey {
            case id
            case name
            case nameShow = "name_show"
            case nick
            case portrait
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = Int64(container.decodeStringIfPresent(forKey: .id) ?? "") ?? 0
            name = container.decodeStringIfPresent(forKey: .name) ?? ""
            displayName = container.decodeStringIfPresent(forKey: .nameShow)
                ?? container.decodeStringIfPresent(forKey: .nick)
                ?? name
            portrait = container.decodeStringIfPresent(forKey: .portrait) ?? ""
        }
    }

    struct ThreadDTO: Decodable {
        var id: Int64
        var title: String
        var replyCount: Int
        var viewCount: Int
        var likeCount: Int
        var lastReplyAt: Date?
        var createdAt: Date?
        var authorID: Int64
        var isTop: Bool
        var isGood: Bool
        var abstractText: String
        var media: [MediaDTO]
        var videoInfo: VideoDTO?
        var isVoiceThread: Bool
        var hasAdvertisement: Bool
        var hasLiveInfo: Bool
        var isDeleted: Bool

        enum CodingKeys: String, CodingKey {
            case id
            case tid
            case title
            case replyCount = "reply_num"
            case viewCount = "view_num"
            case likeCount = "agree_num"
            case likeCountCamel = "agreeNum"
            case lastTimeInt = "last_time_int"
            case createTime = "create_time"
            case authorID = "author_id"
            case isTop = "is_top"
            case isGood = "is_good"
            case abstractBlocks = "abstract"
            case media
            case videoInfo = "video_info"
            case isVoiceThread = "is_voice_thread"
            case isDeleted = "is_deleted"
            case adInfo = "ad_info"
            case adThread = "is_ad"
            case alaInfo = "ala_info"
            case twzhiboInfo = "twzhibo_info"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = Int64(container.decodeStringIfPresent(forKey: .id)
                ?? container.decodeStringIfPresent(forKey: .tid)
                ?? "") ?? 0
            title = container.decodeStringIfPresent(forKey: .title) ?? ""
            replyCount = Int(container.decodeStringIfPresent(forKey: .replyCount) ?? "") ?? 0
            viewCount = Int(container.decodeStringIfPresent(forKey: .viewCount) ?? "") ?? 0
            likeCount = Int(
                container.decodeStringIfPresent(forKey: .likeCount)
                    ?? container.decodeStringIfPresent(forKey: .likeCountCamel)
                    ?? ""
            ) ?? 0
            authorID = Int64(container.decodeStringIfPresent(forKey: .authorID) ?? "") ?? 0
            isTop = container.decodeStringIfPresent(forKey: .isTop) == "1"
            isGood = container.decodeStringIfPresent(forKey: .isGood) == "1"
            lastReplyAt = container.decodeDateIfPresent(forKey: .lastTimeInt)
            createdAt = container.decodeDateIfPresent(forKey: .createTime)
            media = try container.decodeIfPresent([MediaDTO].self, forKey: .media) ?? []
            videoInfo = try container.decodeIfPresent(VideoDTO.self, forKey: .videoInfo)
            isVoiceThread = container.decodeStringIfPresent(forKey: .isVoiceThread) == "1"
            isDeleted = container.decodeStringIfPresent(forKey: .isDeleted) == "1"
            hasAdvertisement = container.decodeStringIfPresent(forKey: .adThread) == "1"
                || container.contains(.adInfo)
            hasLiveInfo = container.contains(.alaInfo) || container.contains(.twzhiboInfo)

            if let text = container.decodeStringIfPresent(forKey: .abstractBlocks) {
                abstractText = text
            } else {
                let blocks = try container.decodeIfPresent([AbstractDTO].self, forKey: .abstractBlocks) ?? []
                abstractText = blocks.map(\.text).joined()
            }
        }

        var shouldKeep: Bool {
            id != 0
                && title.isEmpty == false
                && isVoiceThread == false
                && hasAdvertisement == false
                && hasLiveInfo == false
                && isDeleted == false
        }

        func threadSummary(usersByID: [Int64: UserDTO], forumName: String) -> ThreadSummary {
            let user = usersByID[authorID]
            var blocks: [ContentBlock] = []
            if abstractText.isEmpty == false {
                blocks.append(contentsOf: TiebaEmoticon.blocks(from: abstractText))
            }
            blocks.append(contentsOf: media.compactMap(\.imageBlock))
            if let videoBlock = videoInfo?.videoBlock {
                blocks.append(videoBlock)
            }

            return ThreadSummary(
                id: id,
                forumID: nil,
                title: title,
                author: UserSummary(
                    id: authorID,
                    name: user?.name ?? "",
                    displayName: user?.displayName ?? "",
                    portrait: user?.portrait ?? ""
                ),
                forumName: forumName,
                replyCount: replyCount,
                viewCount: viewCount,
                likeCount: likeCount,
                createdAt: createdAt,
                lastReplyAt: lastReplyAt,
                blocks: blocks,
                isTop: isTop,
                isGood: isGood,
                hasVideo: videoInfo != nil
            )
        }
    }

    struct AbstractDTO: Decodable {
        var text: String

        enum CodingKeys: String, CodingKey {
            case text
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            text = container.decodeStringIfPresent(forKey: .text) ?? ""
        }
    }

    struct MediaDTO: Decodable {
        var thumbnailURL: URL?
        var originalURL: URL?
        var showOriginalButton: Bool

        enum CodingKeys: String, CodingKey {
            case bigPic = "big_pic"
            case dynamicPic = "dynamic_pic"
            case srcPic = "src_pic"
            case originPic = "origin_pic"
            case showOriginalButton = "show_original_btn"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            thumbnailURL = TiebaURL.make(container.decodeStringIfPresent(forKey: .srcPic)
                ?? container.decodeStringIfPresent(forKey: .bigPic)
                ?? container.decodeStringIfPresent(forKey: .dynamicPic))
            originalURL = TiebaURL.make(container.decodeStringIfPresent(forKey: .originPic)
                ?? container.decodeStringIfPresent(forKey: .bigPic)
                ?? container.decodeStringIfPresent(forKey: .srcPic))
            showOriginalButton = container.decodeStringIfPresent(forKey: .showOriginalButton) == "1"
        }

        var imageBlock: ContentBlock? {
            guard thumbnailURL != nil || originalURL != nil else { return nil }
            return .image(ImageContent(
                thumbnailURL: thumbnailURL,
                originalURL: originalURL,
                width: 1,
                height: 1,
                showOriginalButton: showOriginalButton
            ))
        }
    }

    struct VideoDTO: Decodable {
        var videoURL: URL?
        var coverURL: URL?

        enum CodingKeys: String, CodingKey {
            case videoURL = "video_url"
            case originVideoURL = "origin_video_url"
            case thumbnailURL = "thumbnail_url"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            videoURL = TiebaURL.make(container.decodeStringIfPresent(forKey: .originVideoURL)
                ?? container.decodeStringIfPresent(forKey: .videoURL))
            coverURL = TiebaURL.make(container.decodeStringIfPresent(forKey: .thumbnailURL))
        }

        var videoBlock: ContentBlock? {
            guard videoURL != nil || coverURL != nil else { return nil }
            return .video(VideoContent(
                videoURL: videoURL,
                coverURL: coverURL,
                webURL: nil,
                width: 16,
                height: 9,
                duration: 0
            ))
        }
    }
}

enum TiebaAPIError: Error, Equatable, CustomStringConvertible {
    case response(code: Int, message: String)
    case sessionExpired(code: Int, message: String)

    static let sessionExpiredCodes: Set<Int> = [4, 110001, 110002, 110003, 110004]

    var description: String {
        switch self {
        case let .response(code, message):
            return message.isEmpty ? "Tieba API error \(code)" : message
        case let .sessionExpired(code, message):
            return message.isEmpty ? "登录已失效（\(code)）" : message
        }
    }
}

enum TiebaResponseValidator {
    static func validate(code: Int, message: String) throws {
        guard code != 0 else { return }
        if TiebaAPIError.sessionExpiredCodes.contains(code) {
            throw TiebaAPIError.sessionExpired(code: code, message: message)
        }
        throw TiebaAPIError.response(code: code, message: message)
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
