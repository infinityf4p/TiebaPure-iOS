import Foundation

struct UserProfileRequestContext {
    var request: Tiebapure_Profile_UserProfileRequest
    var isCurrentUser: Bool
}

enum UserProfileRequestFactory {
    static func profileRequest(
        account: Account?,
        user: UserSummary,
        requestBuilder: TiebaRequestBuilder
    ) -> UserProfileRequestContext {
        let currentUserID = account.flatMap { Int64($0.uid) }
        let isCurrentUser = currentUserID != nil && currentUserID == user.id

        var data = Tiebapure_Profile_UserProfileRequestData()
        if let currentUserID {
            data.uid = currentUserID
        }
        if isCurrentUser == false {
            if user.id != 0 {
                data.friendUid = user.id
            } else {
                data.friendUidPortrait = user.portrait
            }
        }
        data.needPostCount = 1
        data.isGuest = isCurrentUser ? 0 : 1
        data.pn = 1
        data.rn = 20
        data.hasPlist_p = 1
        data.common = requestBuilder.common(account: account)
        data.scrW = UInt32(clamping: requestBuilder.screenWidth)
        data.scrH = UInt32(clamping: requestBuilder.screenHeight)
        data.qType = 0
        data.scrDip = requestBuilder.screenScale
        data.isFromUsercenter = 1
        data.page = 1

        var request = Tiebapure_Profile_UserProfileRequest()
        request.data = data
        return UserProfileRequestContext(request: request, isCurrentUser: isCurrentUser)
    }

    static func threadsRequest(
        account: Account?,
        userID: Int64,
        page: Int,
        requestBuilder: TiebaRequestBuilder
    ) throws -> Tiebapure_Profile_UserThreadsRequest {
        let requestedPage = try TiebaRequestValuePolicy.unsignedPage(page)
        var data = Tiebapure_Profile_UserThreadsRequestData()
        data.uid = userID
        data.rn = 20
        data.isThread = 1
        data.needContent = 1
        data.pn = requestedPage
        data.common = requestBuilder.common(account: account)
        data.scrW = Int32(clamping: requestBuilder.screenWidth)
        data.scrH = Int32(clamping: requestBuilder.screenHeight)
        data.scrDip = requestBuilder.screenScale
        data.qType = 1
        data.isViewCard = 1

        var request = Tiebapure_Profile_UserThreadsRequest()
        request.data = data
        return request
    }

    static func followFields(
        account: Account,
        user: UserSummary,
        tbs: String? = nil,
        timestamp: Int64 = Int64(Date().timeIntervalSince1970 * 1_000),
        requestBuilder: TiebaRequestBuilder
    ) throws -> [String: String] {
        let portrait = user.portrait.trimmingCharacters(in: .whitespacesAndNewlines)
        guard portrait.isEmpty == false else {
            throw UserProfileAPIError.missingPortrait
        }
        let resolvedTBS = (tbs ?? account.tbs).trimmingCharacters(in: .whitespacesAndNewlines)
        guard resolvedTBS.isEmpty == false else {
            throw UserProfileAPIError.missingTBS
        }

        var fields = requestBuilder.officialCommonFields(
            bduss: account.bduss,
            baiduID: account.baiduID,
            clientVersion: "11.10.8.6",
            timestamp: timestamp
        )
        fields["stoken"] = account.stoken
        fields["portrait"] = portrait
        fields["tbs"] = resolvedTBS
        fields["authsid"] = "null"
        fields["from_type"] = "2"
        fields["in_live"] = "0"
        fields["timestamp"] = "\(timestamp)"
        return fields
    }

    static func webFollowQueryItems(
        user: UserSummary,
        tbs: String,
        followed: Bool
    ) throws -> [URLQueryItem] {
        let portrait = user.portrait.trimmingCharacters(in: .whitespacesAndNewlines)
        guard portrait.isEmpty == false else {
            throw UserProfileAPIError.missingPortrait
        }
        let resolvedTBS = tbs.trimmingCharacters(in: .whitespacesAndNewlines)
        guard resolvedTBS.isEmpty == false else {
            throw UserProfileAPIError.missingTBS
        }
        return [
            .init(name: "portrait", value: portrait),
            .init(name: "cuid", value: ""),
            .init(name: "auth", value: ""),
            .init(name: "uid", value: ""),
            .init(name: "ssid", value: ""),
            .init(name: "from", value: ""),
            .init(name: "pu", value: ""),
            .init(name: "bd_page_type", value: "2"),
            .init(name: "originid", value: ""),
            .init(name: "mo_device", value: "1"),
            .init(name: "tbs", value: resolvedTBS),
            .init(name: "action", value: "follow"),
            .init(name: "op", value: followed ? "follow" : "unfollow")
        ]
    }
}

enum UserFollowFallbackPolicy {
    static func shouldUseWebEndpoint(code: Int, message: String) -> Bool {
        TiebaMutationFallbackPolicy.isTBSFailure(code: code, message: message)
    }
}

enum UserProfileAPIError: Error, Equatable, CustomStringConvertible {
    case missingProfile
    case missingUserIdentifier
    case missingPortrait
    case missingTBS

    var description: String {
        switch self {
        case .missingProfile:
            return "贴吧没有返回可用的用户资料。"
        case .missingUserIdentifier:
            return "缺少用户 ID，无法加载用户帖子。"
        case .missingPortrait:
            return "缺少用户标识，无法修改关注状态。"
        case .missingTBS:
            return "登录状态不完整，请重新登录后再试。"
        }
    }
}

struct UserFollowResponseDTO: Decodable {
    var errorCode: Int
    var errorMessage: String

    enum CodingKeys: String, CodingKey {
        case errorCode = "error_code"
        case errorMessage = "error_msg"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let value = try? container.decode(Int.self, forKey: .errorCode) {
            errorCode = value
        } else if let value = try? container.decode(String.self, forKey: .errorCode) {
            errorCode = Int(value) ?? 0
        } else {
            errorCode = 0
        }
        errorMessage = (try? container.decode(String.self, forKey: .errorMessage)) ?? ""
    }
}

extension TiebaAPI {
    func userProfile(account: Account?, user: UserSummary) async throws -> UserProfile {
        let context = UserProfileRequestFactory.profileRequest(
            account: account,
            user: user,
            requestBuilder: requestBuilder
        )
        let multipart = try requestBuilder.multipart(
            protobuf: context.request,
            account: account,
            includeSToken: false
        )
        let response = try await client.postProtobuf(
            .userProfile,
            body: multipart.body,
            contentType: multipart.contentType,
            headers: ["X-BD-DATA-TYPE": "protobuf"],
            as: Tiebapure_Profile_UserProfileResponse.self
        )
        try TiebaResponseValidator.validate(
            code: Int(response.error.errorCode),
            message: response.error.userMsg.isEmpty ? response.error.errorMsg : response.error.userMsg
        )
        guard response.hasData, response.data.hasUser else {
            throw UserProfileAPIError.missingProfile
        }
        return UserProfileMapper.profile(
            from: response.data.user,
            fallback: user,
            isCurrentUser: context.isCurrentUser
        )
    }

    func userThreads(account: Account?, userID: Int64, page: Int) async throws -> UserThreadsPage {
        guard userID > 0 else { throw UserProfileAPIError.missingUserIdentifier }
        let request = try UserProfileRequestFactory.threadsRequest(
            account: account,
            userID: userID,
            page: page,
            requestBuilder: requestBuilder
        )
        let multipart = try requestBuilder.multipart(
            protobuf: request,
            account: account,
            includeSToken: true
        )
        let response = try await client.postProtobuf(
            .userThreads,
            body: multipart.body,
            contentType: multipart.contentType,
            headers: ["X-BD-DATA-TYPE": "protobuf"],
            as: Tiebapure_Profile_UserThreadsResponse.self
        )
        try TiebaResponseValidator.validate(
            code: Int(response.error.errorCode),
            message: response.error.userMsg.isEmpty ? response.error.errorMsg : response.error.userMsg
        )
        return UserProfileMapper.threadsPage(from: response, page: page)
    }

    func setUserFollowed(account: Account, user: UserSummary, followed: Bool) async throws {
        let tbs = try await refreshedClientTBS(for: account)
        let timestamp = Int64(Date().timeIntervalSince1970 * 1_000)
        let fields = try UserProfileRequestFactory.followFields(
            account: account,
            user: user,
            tbs: tbs,
            timestamp: timestamp,
            requestBuilder: requestBuilder
        )
        let endpoint: TiebaEndpoint = followed ? .followUser : .unfollowUser
        let response = try await client.postForm(
            endpoint,
            fields: fields,
            headers: requestBuilder.officialHeaders(
                baiduID: account.baiduID,
                clientVersion: "11.10.8.6",
                timestamp: timestamp
            ),
            signingSecret: "tiebaclient!!!",
            as: UserFollowResponseDTO.self
        )
        if UserFollowFallbackPolicy.shouldUseWebEndpoint(
            code: response.errorCode,
            message: response.errorMessage
        ) {
            try await setUserFollowedViaWeb(
                account: account,
                user: user,
                followed: followed,
                fallbackTBS: tbs
            )
            return
        }
        try TiebaResponseValidator.validate(code: response.errorCode, message: response.errorMessage)
    }

    private func setUserFollowedViaWeb(
        account: Account,
        user: UserSummary,
        followed: Bool,
        fallbackTBS: String
    ) async throws {
        let context = try await webMutationTBSContext(for: account, fallbackTBS: fallbackTBS)
        var lastResponse: UserFollowResponseDTO?
        for candidate in context.candidates {
            let queryItems = try UserProfileRequestFactory.webFollowQueryItems(
                user: user,
                tbs: candidate,
                followed: followed
            )
            let response = try await client.getJSON(
                .webUserFollow,
                queryItems: queryItems,
                headers: [
                    "Cookie": context.cookies.minimalCookieHeader,
                    "Pragma": "no-cache",
                    "Referer": "https://tieba.baidu.com/",
                    "User-Agent": "Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 Mobile Safari/537.36 tieba/11.10.8.6 skin/default"
                ],
                as: UserFollowResponseDTO.self
            )
            lastResponse = response
            if UserFollowFallbackPolicy.shouldUseWebEndpoint(
                code: response.errorCode,
                message: response.errorMessage
            ) {
                continue
            }
            try TiebaResponseValidator.validate(code: response.errorCode, message: response.errorMessage)
            return
        }
        if let lastResponse {
            try TiebaResponseValidator.validate(
                code: lastResponse.errorCode,
                message: lastResponse.errorMessage
            )
        }
        throw UserProfileAPIError.missingTBS
    }
}
