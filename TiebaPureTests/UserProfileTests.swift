import XCTest
@testable import TiebaPure

final class UserProfileTests: XCTestCase {
    private let builder = TiebaRequestBuilder(
        screenScale: 3,
        screenWidth: 1179,
        screenHeight: 2556,
        clientID: "profile-test-client"
    )

    override func tearDown() {
        SocialMockURLProtocol.handler = nil
        super.tearDown()
    }

    func testProfileRequestUsesCurrentUserShapeForOwnProfile() {
        let account = makeAccount()
        let user = UserSummary(id: 42, name: "raw", displayName: "本人", portrait: "portrait")

        let context = UserProfileRequestFactory.profileRequest(
            account: account,
            user: user,
            requestBuilder: builder
        )

        XCTAssertTrue(context.isCurrentUser)
        XCTAssertEqual(context.request.data.uid, 42)
        XCTAssertFalse(context.request.data.hasFriendUid)
        XCTAssertEqual(context.request.data.isGuest, 0)
        XCTAssertEqual(context.request.data.needPostCount, 1)
        XCTAssertEqual(context.request.data.hasPlist_p, 1)
        XCTAssertEqual(context.request.data.rn, 20)
        XCTAssertEqual(context.request.data.common.bduss, "bduss")
    }

    func testProfileRequestUsesGuestTargetForAnotherUser() {
        let account = makeAccount()
        let user = UserSummary(id: 99, name: "other", displayName: "其他用户", portrait: "other")

        let context = UserProfileRequestFactory.profileRequest(
            account: account,
            user: user,
            requestBuilder: builder
        )

        XCTAssertFalse(context.isCurrentUser)
        XCTAssertEqual(context.request.data.uid, 42)
        XCTAssertEqual(context.request.data.friendUid, 99)
        XCTAssertEqual(context.request.data.isGuest, 1)
    }

    func testAnonymousProfileRequestDoesNotInventCurrentUserID() {
        let user = UserSummary(id: 99, name: "other", displayName: "其他用户", portrait: "other")

        let context = UserProfileRequestFactory.profileRequest(
            account: nil,
            user: user,
            requestBuilder: builder
        )

        XCTAssertFalse(context.request.data.hasUid)
        XCTAssertEqual(context.request.data.friendUid, 99)
        XCTAssertEqual(context.request.data.isGuest, 1)
    }

    func testUserThreadsRequestIncludesPagingAndViewCardFields() throws {
        let request = try UserProfileRequestFactory.threadsRequest(
            account: makeAccount(),
            userID: 99,
            page: 3,
            requestBuilder: builder
        )

        XCTAssertEqual(request.data.uid, 99)
        XCTAssertEqual(request.data.pn, 3)
        XCTAssertEqual(request.data.rn, 20)
        XCTAssertEqual(request.data.isThread, 1)
        XCTAssertEqual(request.data.needContent, 1)
        XCTAssertEqual(request.data.qType, 1)
        XCTAssertEqual(request.data.isViewCard, 1)
        XCTAssertEqual(request.data.common.stoken, "stoken")
    }

    func testProfileMapperPreservesPublicForumsAndMetadata() {
        var forum = Tieba_LikeForumInfo()
        forum.forumID = 101
        forum.forumName = "测试吧"
        var privacy = Tieba_PrivSets()
        privacy.like = 1
        var proto = Tieba_User()
        proto.id = 99
        proto.name = "raw"
        proto.nameShow = "显示名称"
        proto.portrait = "portrait"
        proto.levelID = 8
        proto.tiebaUid = "tieba-99"
        proto.tbAge = "10.5年"
        proto.ipAddress = "广东"
        proto.displayIntro = "个人简介"
        proto.totalAgreeNum = 12_345
        proto.hasConcerned_p = 1
        proto.concernNum = 7
        proto.fansNum = 8
        proto.threadNum = 9
        proto.myLikeNum = 1
        proto.privSets = privacy
        proto.likeForum = [forum]

        let profile = UserProfileMapper.profile(
            from: proto,
            fallback: UserSummary(id: 99, name: "", displayName: "", portrait: ""),
            isCurrentUser: false
        )

        XCTAssertEqual(profile.user.displayNameResolved, "显示名称")
        XCTAssertEqual(profile.tiebaID, "tieba-99")
        XCTAssertEqual(profile.location, "广东")
        XCTAssertEqual(profile.agreeCount, 12_345)
        XCTAssertFalse(profile.isCurrentUser)
        XCTAssertTrue(profile.isFollowed)
        XCTAssertEqual(profile.followedForums.map(\.name), ["测试"])
        XCTAssertEqual(profile.followedForumsVisibility, .visible)
    }

    func testPrivacyPolicyDistinguishesPrivateFromPublicEmptyForums() {
        XCTAssertEqual(
            UserProfilePrivacyPolicy.followedForumsVisibility(
                isCurrentUser: false,
                privacyValue: 0,
                declaredCount: 3,
                returnedCount: 0
            ),
            .privateContent
        )
        XCTAssertEqual(
            UserProfilePrivacyPolicy.followedForumsVisibility(
                isCurrentUser: false,
                privacyValue: 0,
                declaredCount: 0,
                returnedCount: 0
            ),
            .visible
        )
        XCTAssertEqual(
            UserProfilePrivacyPolicy.followedForumsVisibility(
                isCurrentUser: true,
                privacyValue: 0,
                declaredCount: 3,
                returnedCount: 0
            ),
            .visible
        )
    }

    func testHiddenPostResponseMapsToPrivateState() {
        var data = Tiebapure_Profile_UserThreadsResponseData()
        data.hidePost = 1
        var response = Tiebapure_Profile_UserThreadsResponse()
        response.data = data

        let page = UserProfileMapper.threadsPage(from: response, page: 1)

        XCTAssertEqual(page.visibility, .privateContent)
        XCTAssertFalse(page.hasMore)
        XCTAssertTrue(page.threads.isEmpty)
    }

    func testProfileCountFormatterUsesCompactChineseUnits() {
        XCTAssertEqual(UserProfileCountText.string(4_639), "4639")
        XCTAssertEqual(UserProfileCountText.string(10_000), "1万")
        XCTAssertEqual(UserProfileCountText.string(12_345), "1.2万")
        XCTAssertEqual(UserProfileCountText.string(-1), "0")
    }

    func testFollowRequestUsesAuthenticatedSignedFormShape() throws {
        let account = makeAccount()
        let user = UserSummary(
            id: 99,
            name: "other",
            displayName: "其他用户",
            portrait: "portrait-token"
        )

        let fields = try UserProfileRequestFactory.followFields(
            account: account,
            user: user,
            timestamp: 1_700_000_000_000,
            requestBuilder: builder
        )

        XCTAssertEqual(fields["BDUSS"], "bduss")
        XCTAssertEqual(fields["stoken"], "stoken")
        XCTAssertEqual(fields["portrait"], "portrait-token")
        XCTAssertEqual(fields["tbs"], "tbs")
        XCTAssertEqual(fields["_client_version"], "11.10.8.6")
        XCTAssertEqual(fields["_client_id"], "profile-test-client")
        XCTAssertEqual(fields["_client_type"], "2")
        XCTAssertEqual(fields["baiduid"], "baiduid")
        XCTAssertEqual(fields["from"], "tieba")
        XCTAssertEqual(fields["from_type"], "2")
        XCTAssertEqual(fields["in_live"], "0")
        XCTAssertEqual(fields["timestamp"], "1700000000000")
        XCTAssertNil(fields["subapp_type"])
        XCTAssertEqual(TiebaEndpoint.login.url.host, "c.tieba.baidu.com")
        XCTAssertEqual(TiebaEndpoint.initNickname.url.host, "c.tieba.baidu.com")
        XCTAssertEqual(TiebaEndpoint.followedForums.url.host, "c.tieba.baidu.com")
        XCTAssertEqual(TiebaEndpoint.followUser.url.path, "/c/c/user/follow")
        XCTAssertEqual(TiebaEndpoint.unfollowUser.url.path, "/c/c/user/unfollow")
    }

    func testFollowRequestRejectsMissingPortrait() {
        let user = UserSummary(id: 99, name: "other", displayName: "其他用户", portrait: "")

        XCTAssertThrowsError(
            try UserProfileRequestFactory.followFields(
                account: makeAccount(),
                user: user,
                requestBuilder: builder
            )
        ) { error in
            XCTAssertEqual(error as? UserProfileAPIError, .missingPortrait)
        }
    }

    func testFollowRequestPrefersExplicitRefreshedTBS() throws {
        let fields = try UserProfileRequestFactory.followFields(
            account: makeAccount(),
            user: UserSummary(id: 99, name: "other", displayName: "其他用户", portrait: "portrait-token"),
            tbs: "fresh-tbs",
            requestBuilder: builder
        )

        XCTAssertEqual(fields["tbs"], "fresh-tbs")
    }

    func testLikeRequestUsesObjectSpecificPostIDs() throws {
        let account = makeAccount()
        let thread = try TiebaSocialRequestFactory.likeFields(
            account: account,
            tbs: "fresh-tbs",
            threadID: 1001,
            postID: 2001,
            objectType: .thread,
            liked: true,
            requestBuilder: builder
        )
        let post = try TiebaSocialRequestFactory.likeFields(
            account: account,
            tbs: "fresh-tbs",
            threadID: 1001,
            postID: 2002,
            objectType: .post,
            liked: false,
            requestBuilder: builder
        )
        let subpost = try TiebaSocialRequestFactory.likeFields(
            account: account,
            tbs: "fresh-tbs",
            threadID: 1001,
            postID: 3001,
            objectType: .subpost,
            liked: true,
            requestBuilder: builder
        )

        XCTAssertEqual(thread["post_id"], "2001")
        XCTAssertEqual(thread["obj_type"], "3")
        XCTAssertEqual(thread["op_type"], "0")
        XCTAssertEqual(thread["_client_version"], TiebaClientVersion.mini.rawValue)
        XCTAssertEqual(thread["from"], "1021636m")
        XCTAssertEqual(thread["subapp_type"], "mini")
        XCTAssertEqual(thread["BDUSS"], "bduss")
        XCTAssertEqual(thread["stoken"], "stoken")
        XCTAssertEqual(thread["cuid_galaxy2"], builder.miniCUID)
        XCTAssertEqual(post["post_id"], "2002")
        XCTAssertEqual(post["obj_type"], "1")
        XCTAssertEqual(post["op_type"], "1")
        XCTAssertEqual(subpost["post_id"], "3001")
        XCTAssertEqual(subpost["obj_type"], "2")
    }

    func testFollowedUsersResponseAcceptsStringNumbersAndStripsPortraitQuery() throws {
        let response = try JSONDecoder().decode(
            FollowedUsersResponseDTO.self,
            from: Data(
                #"{"error_code":"0","error_msg":"","pn":"2","total_follow_num":"21","has_more":"1","follow_list":[{"id":"99","name":"raw","name_show":"显示名称","portrait":"tb.1.avatar?t=1234567890"}]}"#.utf8
            )
        )

        XCTAssertEqual(response.currentPage, 2)
        XCTAssertEqual(response.totalCount, 21)
        XCTAssertTrue(response.hasMore)
        XCTAssertEqual(response.users.first?.userSummary.id, 99)
        XCTAssertEqual(response.users.first?.userSummary.displayNameResolved, "显示名称")
        XCTAssertEqual(response.users.first?.userSummary.portrait, "tb.1.avatar")
    }

    func testFollowMutationFetchesFreshTBSBeforeSubmitting() async throws {
        let api = makeSocialAPI { request in
            let path = try XCTUnwrap(request.url?.path)
            switch path {
            case "/c/s/login":
                XCTAssertEqual(request.url?.host, "c.tieba.baidu.com")
                let fields = try Self.formFields(request)
                XCTAssertEqual(fields["bdusstoken"], "bduss|")
                XCTAssertEqual(fields["_client_id"], "profile-test-client")
                XCTAssertEqual(fields["from"], "tieba")
                XCTAssertNotNil(fields["sign"])
                return Data(#"{"error_code":"0","anti":{"tbs":"fresh-tbs"}}"#.utf8)
            case "/c/c/user/follow":
                let fields = try Self.formFields(request)
                XCTAssertEqual(fields["tbs"], "fresh-tbs")
                XCTAssertNotEqual(fields["tbs"], "tbs")
                XCTAssertEqual(fields["baiduid"], "baiduid")
                XCTAssertTrue(request.value(forHTTPHeaderField: "Cookie")?.contains("BAIDUID=baiduid") == true)
                XCTAssertNotNil(fields["sign"])
                return Data(#"{"error_code":0,"error_msg":""}"#.utf8)
            default:
                XCTFail("Unexpected request path: \(path)")
                return Data()
            }
        }

        try await api.setUserFollowed(
            account: makeAccount(),
            user: UserSummary(id: 99, name: "other", displayName: "其他用户", portrait: "portrait-token"),
            followed: true
        )
    }

    func testFollowMutationFallsBackToOriginalWebEndpointWhenAppRejectsTBS() async throws {
        var requestedPaths: [String] = []
        let api = makeSocialAPI { request in
            let url = try XCTUnwrap(request.url)
            requestedPaths.append(url.path)
            switch url.path {
            case "/c/s/login":
                return Data(#"{"error_code":"0","anti":{"tbs":"client-tbs"}}"#.utf8)
            case "/c/c/user/follow":
                return Data(#"{"error_code":220034,"error_msg":"tbs校验失败"}"#.utf8)
            case "/mo/q/newmoindex":
                XCTAssertEqual(
                    request.value(forHTTPHeaderField: "Cookie"),
                    "BDUSS=bduss; STOKEN=stoken; BAIDUID=baiduid"
                )
                return Data(#"{"data":{"is_login":true,"tbs":"web-tbs"}}"#.utf8)
            case "/i":
                let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
                let query = Dictionary(
                    uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") }
                )
                XCTAssertEqual(request.httpMethod, "GET")
                XCTAssertEqual(query["portrait"], "portrait-token")
                XCTAssertEqual(query["tbs"], "web-tbs")
                XCTAssertEqual(query["action"], "follow")
                XCTAssertEqual(query["op"], "follow")
                XCTAssertEqual(
                    request.value(forHTTPHeaderField: "Cookie"),
                    "BDUSS=bduss; STOKEN=stoken; BAIDUID=baiduid"
                )
                return Data(#"{"error_code":0,"error_msg":""}"#.utf8)
            default:
                XCTFail("Unexpected request path: \(url.path)")
                return Data()
            }
        }

        try await api.setUserFollowed(
            account: makeAccount(),
            user: UserSummary(id: 99, name: "other", displayName: "其他用户", portrait: "portrait-token"),
            followed: true
        )

        XCTAssertEqual(
            requestedPaths,
            ["/c/s/login", "/c/c/user/follow", "/mo/q/newmoindex", "/i"]
        )
    }

    func testUnfollowWebFallbackRetriesAlternateTBS() async throws {
        var attemptedTBSValues: [String] = []
        let api = makeSocialAPI { request in
            let url = try XCTUnwrap(request.url)
            switch url.path {
            case "/c/s/login":
                return Data(#"{"error_code":"0","anti":{"tbs":"client-tbs"}}"#.utf8)
            case "/c/c/user/unfollow":
                return Data(#"{"error_code":220034,"error_msg":"tbs校验失败"}"#.utf8)
            case "/mo/q/newmoindex":
                return Data(#"{"data":{"is_login":true,"tbs":"web-tbs","itb_tbs":"web-itb-tbs"}}"#.utf8)
            case "/i":
                let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
                let query = Dictionary(
                    uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") }
                )
                XCTAssertEqual(query["action"], "follow")
                XCTAssertEqual(query["op"], "unfollow")
                let tbs = try XCTUnwrap(query["tbs"])
                attemptedTBSValues.append(tbs)
                if tbs == "web-tbs" {
                    return Data(#"{"error_code":220034,"error_msg":"tbs校验失败"}"#.utf8)
                }
                return Data(#"{"error_code":0,"error_msg":""}"#.utf8)
            default:
                XCTFail("Unexpected request path: \(url.path)")
                return Data()
            }
        }

        try await api.setUserFollowed(
            account: makeAccount(),
            user: UserSummary(id: 99, name: "other", displayName: "其他用户", portrait: "portrait-token"),
            followed: false
        )

        XCTAssertEqual(attemptedTBSValues, ["web-tbs", "web-itb-tbs"])
    }

    func testFollowFallbackOnlyHandlesExplicitTBSErrors() {
        XCTAssertTrue(UserFollowFallbackPolicy.shouldUseWebEndpoint(code: 220034, message: "tbs校验失败"))
        XCTAssertTrue(UserFollowFallbackPolicy.shouldUseWebEndpoint(code: 220034, message: "TBS invalid"))
        XCTAssertFalse(UserFollowFallbackPolicy.shouldUseWebEndpoint(code: 0, message: "tbs校验失败"))
        XCTAssertFalse(UserFollowFallbackPolicy.shouldUseWebEndpoint(code: 12, message: "参数错误"))
    }

    func testFollowMutationUsesWebTBSWhenClientLoginFalselyReportsExpired() async throws {
        let api = makeSocialAPI { request in
            let path = try XCTUnwrap(request.url?.path)
            switch path {
            case "/c/s/login":
                XCTAssertEqual(request.url?.host, "c.tieba.baidu.com")
                return Data(#"{"error_code":"110001","error_msg":"登录已失效"}"#.utf8)
            case "/mo/q/newmoindex":
                XCTAssertEqual(request.url?.host, "tieba.baidu.com")
                XCTAssertEqual(
                    request.value(forHTTPHeaderField: "Cookie"),
                    "BDUSS=bduss; STOKEN=stoken; BAIDUID=baiduid"
                )
                return Data(#"{"data":{"is_login":true,"tbs":"web-fresh-tbs"}}"#.utf8)
            case "/c/c/user/follow":
                let fields = try Self.formFields(request)
                XCTAssertEqual(fields["tbs"], "web-fresh-tbs")
                return Data(#"{"error_code":0,"error_msg":""}"#.utf8)
            default:
                XCTFail("Unexpected request path: \(path)")
                return Data()
            }
        }

        try await api.setUserFollowed(
            account: makeAccount(),
            user: UserSummary(id: 99, name: "other", displayName: "其他用户", portrait: "portrait-token"),
            followed: true
        )
    }

    func testFollowMutationReportsExpiredOnlyWhenWebCheckAlsoRejectsLogin() async {
        let api = makeSocialAPI { request in
            let path = try XCTUnwrap(request.url?.path)
            switch path {
            case "/c/s/login":
                return Data(#"{"error_code":"110001","error_msg":"客户端登录已失效"}"#.utf8)
            case "/mo/q/newmoindex":
                return Data(#"{"data":{"is_login":false}}"#.utf8)
            default:
                XCTFail("Expired account must not submit a follow mutation: \(path)")
                return Data()
            }
        }

        do {
            try await api.setUserFollowed(
                account: makeAccount(),
                user: UserSummary(id: 99, name: "other", displayName: "其他用户", portrait: "portrait-token"),
                followed: true
            )
            XCTFail("Expected session-expired error")
        } catch {
            XCTAssertEqual(
                error as? TiebaAPIError,
                .sessionExpired(code: 110001, message: "客户端登录已失效")
            )
        }
    }

    func testLikeMutationFetchesFreshTBSAndUsesReplyObjectType() async throws {
        let api = makeSocialAPI { request in
            let path = try XCTUnwrap(request.url?.path)
            switch path {
            case "/c/s/login":
                return Data(#"{"error_code":"0","anti":{"tbs":"fresh-like-tbs"}}"#.utf8)
            case "/c/c/agree/opAgree":
                let fields = try Self.formFields(request)
                XCTAssertEqual(fields["tbs"], "fresh-like-tbs")
                XCTAssertEqual(fields["thread_id"], "1001")
                XCTAssertEqual(fields["post_id"], "2002")
                XCTAssertEqual(fields["obj_type"], "1")
                XCTAssertEqual(fields["op_type"], "0")
                XCTAssertEqual(fields["_client_version"], TiebaClientVersion.mini.rawValue)
                XCTAssertEqual(fields["from"], "1021636m")
                XCTAssertEqual(fields["subapp_type"], "mini")
                XCTAssertEqual(fields["stoken"], "stoken")
                XCTAssertNotNil(fields["sign"])
                XCTAssertEqual(
                    request.value(forHTTPHeaderField: "User-Agent"),
                    "bdtb for Android \(TiebaClientVersion.mini.rawValue)"
                )
                XCTAssertEqual(request.value(forHTTPHeaderField: "cuid"), self.builder.miniCUID)
                return Data(#"{"error_code":"0","error_msg":""}"#.utf8)
            default:
                XCTFail("Unexpected request path: \(path)")
                return Data()
            }
        }

        try await api.setPostLiked(
            account: makeAccount(),
            threadID: 1001,
            postID: 2002,
            objectType: .post,
            liked: true
        )
    }

    func testLikeMutationRetriesWithWebTBSAfterExplicitValidationFailure() async throws {
        var attemptedTBSValues: [String] = []
        let api = makeSocialAPI { request in
            let path = try XCTUnwrap(request.url?.path)
            switch path {
            case "/c/s/login":
                return Data(#"{"error_code":"0","anti":{"tbs":"client-like-tbs"}}"#.utf8)
            case "/c/c/agree/opAgree":
                let fields = try Self.formFields(request)
                let tbs = try XCTUnwrap(fields["tbs"])
                attemptedTBSValues.append(tbs)
                if tbs == "client-like-tbs" {
                    return Data(#"{"error_code":220034,"error_msg":"tbs校验失败"}"#.utf8)
                }
                return Data(#"{"error_code":0,"error_msg":""}"#.utf8)
            case "/mo/q/newmoindex":
                return Data(#"{"data":{"is_login":true,"tbs":"web-like-tbs"}}"#.utf8)
            default:
                XCTFail("Unexpected request path: \(path)")
                return Data()
            }
        }

        try await api.setPostLiked(
            account: makeAccount(),
            threadID: 1001,
            postID: 2002,
            objectType: .post,
            liked: true
        )

        XCTAssertEqual(attemptedTBSValues, ["client-like-tbs", "web-like-tbs"])
    }

    func testFollowResponseAcceptsNumericAndStringErrorCodes() throws {
        let numeric = try JSONDecoder().decode(
            UserFollowResponseDTO.self,
            from: Data(#"{"error_code":0,"error_msg":""}"#.utf8)
        )
        let string = try JSONDecoder().decode(
            UserFollowResponseDTO.self,
            from: Data(#"{"error_code":"12","error_msg":"失败"}"#.utf8)
        )

        XCTAssertEqual(numeric.errorCode, 0)
        XCTAssertEqual(string.errorCode, 12)
        XCTAssertEqual(string.errorMessage, "失败")
    }

    private func makeAccount() -> Account {
        Account(
            uid: "42",
            name: "raw",
            displayName: "本人",
            portrait: "portrait",
            bduss: "bduss",
            stoken: "stoken",
            baiduID: "baiduid",
            tbs: "tbs"
        )
    }

    private func makeSocialAPI(handler: @escaping (URLRequest) throws -> Data) -> TiebaAPI {
        SocialMockURLProtocol.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SocialMockURLProtocol.self]
        return TiebaAPI(
            client: TiebaHTTPClient(session: URLSession(configuration: configuration)),
            requestBuilder: builder
        )
    }

    private static func formFields(_ request: URLRequest) throws -> [String: String] {
        let body: Data
        if let requestBody = request.httpBody {
            body = requestBody
        } else {
            let stream = try XCTUnwrap(request.httpBodyStream)
            stream.open()
            defer { stream.close() }
            var collected = Data()
            var buffer = [UInt8](repeating: 0, count: 4_096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count < 0 { throw try XCTUnwrap(stream.streamError) }
                if count == 0 { break }
                collected.append(contentsOf: buffer.prefix(count))
            }
            body = collected
        }
        let text = try XCTUnwrap(String(data: body, encoding: .utf8))
        var components = URLComponents()
        components.percentEncodedQuery = text
        return Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
    }
}

private final class SocialMockURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> Data)?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        do {
            let data = try XCTUnwrap(Self.handler)(request)
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
