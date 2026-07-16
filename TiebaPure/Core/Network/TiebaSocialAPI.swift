import Foundation

enum TiebaMutationError: Error, Equatable, CustomStringConvertible {
    case missingTBS
    case invalidThreadID
    case invalidPostID

    var description: String {
        switch self {
        case .missingTBS:
            return "未能刷新登录校验信息，请重新登录后再试。"
        case .invalidThreadID:
            return "帖子 ID 无效，无法完成操作。"
        case .invalidPostID:
            return "回复 ID 无效，无法完成操作。"
        }
    }
}

enum TiebaSocialRequestFactory {
    static func followedUsersFields(account: Account, page: Int) throws -> [String: String] {
        let requestedPage = try TiebaRequestValuePolicy.signedPage(page)
        return [
            "BDUSS": account.bduss,
            "_client_version": TiebaClientVersion.v12.rawValue,
            "pn": "\(requestedPage)",
            "uid": account.uid
        ]
    }

    static func likeFields(
        account: Account,
        tbs: String,
        threadID: Int64,
        postID: UInt64,
        objectType: TiebaLikeObjectType,
        liked: Bool,
        requestBuilder: TiebaRequestBuilder
    ) throws -> [String: String] {
        guard threadID > 0 else { throw TiebaMutationError.invalidThreadID }
        guard postID > 0 else { throw TiebaMutationError.invalidPostID }
        let resolvedTBS = tbs.trimmingCharacters(in: .whitespacesAndNewlines)
        guard resolvedTBS.isEmpty == false else { throw TiebaMutationError.missingTBS }

        var fields = requestBuilder.miniCommonFields()
        fields["BDUSS"] = account.bduss
        fields["agree_type"] = "2"
        fields["cuid_gid"] = ""
        fields["obj_type"] = "\(objectType.rawValue)"
        fields["op_type"] = liked ? "0" : "1"
        fields["post_id"] = "\(postID)"
        fields["stoken"] = account.stoken
        fields["tbs"] = resolvedTBS
        fields["thread_id"] = "\(threadID)"
        return fields
    }
}

enum TiebaMutationFallbackPolicy {
    static func isTBSFailure(code: Int, message: String) -> Bool {
        guard code != 0 else { return false }
        return message.range(of: "tbs", options: .caseInsensitive) != nil
    }
}

struct WebMutationTBSContext {
    var cookies: BaiduCookies
    var candidates: [String]
}

struct TiebaMutationResponseDTO: Decodable {
    var errorCode: Int
    var errorMessage: String

    enum CodingKeys: String, CodingKey {
        case errorCode = "error_code"
        case errorMessage = "error_msg"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        errorCode = container.flexibleInt(forKey: .errorCode)
        errorMessage = (try? container.decode(String.self, forKey: .errorMessage)) ?? ""
    }
}

struct FollowedUsersResponseDTO: Decodable {
    struct UserDTO: Decodable {
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
            id = container.flexibleInt64(forKey: .id)
            name = (try? container.decode(String.self, forKey: .name)) ?? ""
            displayName = (try? container.decode(String.self, forKey: .displayName)) ?? ""
            portrait = (try? container.decode(String.self, forKey: .portrait)) ?? ""
        }

        var userSummary: UserSummary {
            let portraitToken = portrait.split(separator: "?", maxSplits: 1).first.map(String.init) ?? portrait
            return UserSummary(
                id: id,
                name: name,
                displayName: displayName,
                portrait: portraitToken
            )
        }
    }

    var errorCode: Int
    var errorMessage: String
    var users: [UserDTO]
    var currentPage: Int
    var totalCount: Int
    var hasMore: Bool

    enum CodingKeys: String, CodingKey {
        case errorCode = "error_code"
        case errorMessage = "error_msg"
        case users = "follow_list"
        case currentPage = "pn"
        case totalCount = "total_follow_num"
        case hasMore = "has_more"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        errorCode = container.flexibleInt(forKey: .errorCode)
        errorMessage = (try? container.decode(String.self, forKey: .errorMessage)) ?? ""
        users = (try? container.decode([UserDTO].self, forKey: .users)) ?? []
        currentPage = container.flexibleInt(forKey: .currentPage)
        totalCount = container.flexibleInt(forKey: .totalCount)
        hasMore = container.flexibleInt(forKey: .hasMore) != 0
    }
}

extension TiebaAPI {
    func webMutationTBSContext(
        for account: Account,
        fallbackTBS: String
    ) async throws -> WebMutationTBSContext {
        let cookies = BaiduCookies(
            bduss: account.bduss,
            stoken: account.stoken,
            baiduID: account.baiduID
        )
        let webInfo = try await webMyInfo(cookies: cookies)
        try Task.checkCancellation()
        if webInfo.data?.isLogin == false {
            throw TiebaAPIError.sessionExpired(code: 4, message: "网页登录状态已失效")
        }

        let rawCandidates = [webInfo.data?.tbs, webInfo.data?.itbTbs, fallbackTBS]
        var candidates: [String] = []
        for candidate in rawCandidates {
            let value = candidate?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""
            if value.isEmpty == false, candidates.contains(value) == false {
                candidates.append(value)
            }
        }
        guard candidates.isEmpty == false else {
            throw TiebaMutationError.missingTBS
        }
        return WebMutationTBSContext(cookies: cookies, candidates: candidates)
    }

    func refreshedClientTBS(for account: Account) async throws -> String {
        var clientError: Error?

        do {
            let response = try await login(
                bduss: account.bduss,
                stoken: account.stoken,
                baiduID: account.baiduID ?? ""
            )
            try Task.checkCancellation()
            let code = Int(response.errorCode ?? "0") ?? 0
            if code == 0 {
                let tbs = response.anti?.tbs.trimmingCharacters(
                    in: CharacterSet.whitespacesAndNewlines
                ) ?? ""
                if tbs.isEmpty == false {
                    return tbs
                }
                clientError = TiebaMutationError.missingTBS
            } else {
                do {
                    try TiebaResponseValidator.validate(
                        code: code,
                        message: response.errorMessage ?? ""
                    )
                } catch {
                    clientError = error
                }
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            clientError = error
        }

        try Task.checkCancellation()

        do {
            let webInfo = try await webMyInfo(cookies: BaiduCookies(
                bduss: account.bduss,
                stoken: account.stoken,
                baiduID: account.baiduID
            ))
            try Task.checkCancellation()

            if webInfo.data?.isLogin == false {
                if let apiError = clientError as? TiebaAPIError,
                   case .sessionExpired = apiError {
                    throw apiError
                }
                throw TiebaAPIError.sessionExpired(code: 4, message: "网页登录状态已失效")
            }

            if let data = webInfo.data {
                for candidate in [data.tbs, data.itbTbs] {
                    let tbs = candidate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    if tbs.isEmpty == false {
                        return tbs
                    }
                }
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch let apiError as TiebaAPIError {
            if case .sessionExpired = apiError {
                throw apiError
            }
        } catch {
            // The web check is an independent fallback. A transient failure here
            // must not turn a still-usable stored client TBS into a forced logout.
        }

        let storedTBS = account.tbs.trimmingCharacters(in: .whitespacesAndNewlines)
        if storedTBS.isEmpty == false {
            return storedTBS
        }
        if let clientError {
            throw clientError
        }
        throw TiebaMutationError.missingTBS
    }

    func setPostLiked(
        account: Account,
        threadID: Int64,
        postID: UInt64,
        objectType: TiebaLikeObjectType,
        liked: Bool
    ) async throws {
        let tbs = try await refreshedClientTBS(for: account)
        var response = try await postLikeResponse(
            account: account,
            tbs: tbs,
            threadID: threadID,
            postID: postID,
            objectType: objectType,
            liked: liked
        )
        if TiebaMutationFallbackPolicy.isTBSFailure(
            code: response.errorCode,
            message: response.errorMessage
        ) {
            let context = try await webMutationTBSContext(for: account, fallbackTBS: tbs)
            for candidate in context.candidates where candidate != tbs {
                response = try await postLikeResponse(
                    account: account,
                    tbs: candidate,
                    threadID: threadID,
                    postID: postID,
                    objectType: objectType,
                    liked: liked
                )
                if TiebaMutationFallbackPolicy.isTBSFailure(
                    code: response.errorCode,
                    message: response.errorMessage
                ) == false {
                    break
                }
            }
        }
        try TiebaResponseValidator.validate(code: response.errorCode, message: response.errorMessage)
    }

    private func postLikeResponse(
        account: Account,
        tbs: String,
        threadID: Int64,
        postID: UInt64,
        objectType: TiebaLikeObjectType,
        liked: Bool
    ) async throws -> TiebaMutationResponseDTO {
        let fields = try TiebaSocialRequestFactory.likeFields(
            account: account,
            tbs: tbs,
            threadID: threadID,
            postID: postID,
            objectType: objectType,
            liked: liked,
            requestBuilder: requestBuilder
        )
        let cuid = requestBuilder.miniCUID
        return try await client.postForm(
            .agreePost,
            fields: fields,
            headers: [
                "Cookie": "ka=open",
                "Pragma": "no-cache",
                "User-Agent": "bdtb for Android \(TiebaClientVersion.mini.rawValue)",
                "client_user_token": account.uid,
                "cuid": cuid,
                "cuid_galaxy2": cuid
            ],
            signingSecret: "tiebaclient!!!",
            as: TiebaMutationResponseDTO.self
        )
    }

    func followedUsers(account: Account, page: Int) async throws -> FollowedUsersPage {
        let fields = try TiebaSocialRequestFactory.followedUsersFields(account: account, page: page)
        let response = try await client.postForm(
            .followedUsers,
            fields: fields,
            headers: [
                "Cookie": "ka=open",
                "Pragma": "no-cache",
                "User-Agent": "bdtb for Android \(TiebaClientVersion.v12.rawValue)"
            ],
            signingSecret: "tiebaclient!!!",
            as: FollowedUsersResponseDTO.self
        )
        try TiebaResponseValidator.validate(code: response.errorCode, message: response.errorMessage)
        return FollowedUsersPage(
            users: response.users.map(\.userSummary),
            currentPage: max(response.currentPage, page),
            totalCount: max(response.totalCount, 0),
            hasMore: response.hasMore
        )
    }
}

private extension KeyedDecodingContainer {
    func flexibleInt(forKey key: Key) -> Int {
        if let value = try? decode(Int.self, forKey: key) { return value }
        if let value = try? decode(Int64.self, forKey: key) { return Int(clamping: value) }
        if let value = try? decode(String.self, forKey: key) { return Int(value) ?? 0 }
        return 0
    }

    func flexibleInt64(forKey key: Key) -> Int64 {
        if let value = try? decode(Int64.self, forKey: key) { return value }
        if let value = try? decode(Int.self, forKey: key) { return Int64(value) }
        if let value = try? decode(String.self, forKey: key) { return Int64(value) ?? 0 }
        return 0
    }
}
