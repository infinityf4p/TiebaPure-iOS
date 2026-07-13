import XCTest
@testable import TiebaPure

final class SearchAPITests: XCTestCase {
    override func tearDown() {
        SearchMockURLProtocol.handler = nil
        super.tearDown()
    }

    func testGlobalSearchMapsReplyResultAndMedia() async throws {
        let api = makeAPI { request in
            let components = try XCTUnwrap(URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false))
            let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })

            XCTAssertEqual(components.path, "/mo/q/search/thread")
            XCTAssertEqual(query["word"], "iPhone 视频")
            XCTAssertEqual(query["pn"], "1")
            XCTAssertEqual(query["st"], "5")
            XCTAssertEqual(query["tt"], "2")
            XCTAssertEqual(query["ct"], "1")
            XCTAssertEqual(query["cv"], "99.9.101")
            XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "tieba/12.52.1.0 skin/default")
            XCTAssertEqual(
                request.value(forHTTPHeaderField: "Referer"),
                "https://tieba.baidu.com/mo/q/hybrid/search?keyword=iPhone%20%E8%A7%86%E9%A2%91"
            )

            return Self.searchResponseJSON
        }

        let page = try await api.searchThreads(keyword: "iPhone 视频", page: 1)

        XCTAssertTrue(page.hasMore)
        XCTAssertEqual(page.currentPage, 1)
        XCTAssertEqual(page.results.count, 1)

        let result = try XCTUnwrap(page.results.first)
        XCTAssertEqual(result.threadID, 123)
        XCTAssertEqual(result.postID, 456)
        XCTAssertEqual(result.forumID, 789)
        XCTAssertEqual(result.forumName, "iPhone")
        XCTAssertEqual(result.title, "主题标题")
        XCTAssertEqual(result.content, "命中回复")
        XCTAssertEqual(result.author.displayName, "作者")
        XCTAssertTrue(result.isReplyMatch)
        XCTAssertEqual(result.blocks.count, 2)

        guard case let .image(image) = result.blocks[0] else {
            return XCTFail("expected image block")
        }
        XCTAssertEqual(image.thumbnailURL?.absoluteString, "https://tiebapic.baidu.com/forum/pic/item/a.jpg")
        XCTAssertEqual(image.originalURL?.absoluteString, "https://tiebapic.baidu.com/forum/pic/item/a_original.jpg")

        guard case let .video(video) = result.blocks[1] else {
            return XCTFail("expected video block")
        }
        XCTAssertEqual(video.videoURL?.absoluteString, "https://video.example/a.mp4")
        XCTAssertEqual(video.coverURL?.absoluteString, "https://tiebapic.baidu.com/forum/pic/item/v.jpg")
        XCTAssertEqual(video.width, 1280)
        XCTAssertEqual(video.height, 720)
    }

    func testForumSearchUsesOriginalForumParameters() async throws {
        let api = makeAPI { request in
            let components = try XCTUnwrap(URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false))
            let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })

            XCTAssertEqual(query["word"], "显卡")
            XCTAssertEqual(query["pn"], "3")
            XCTAssertEqual(query["st"], "2")
            XCTAssertEqual(query["tt"], "1")
            XCTAssertEqual(query["rn"], "30")
            XCTAssertEqual(query["fname"], "显卡")
            XCTAssertEqual(query["ct"], "2")
            XCTAssertEqual(query["cv"], "12.52.1.0")
            XCTAssertEqual(
                request.value(forHTTPHeaderField: "Referer"),
                "https://tieba.baidu.com/mo/q/hybrid-usergrow-search/searchGlobal?entryPage=frs&forumName=%E6%98%BE%E5%8D%A1"
            )

            return #"{"no":0,"error":"success","data":{"has_more":0,"current_page":3,"post_list":[]}}"#.data(using: .utf8)!
        }

        let page = try await api.searchThreads(
            keyword: "显卡",
            page: 3,
            sortType: 2,
            filterType: 1,
            forumName: "显卡"
        )

        XCTAssertFalse(page.hasMore)
        XCTAssertEqual(page.currentPage, 3)
        XCTAssertTrue(page.results.isEmpty)
    }

    func testLoggedInForumThreadsFallsBackToFormWhenProtobufIsInvalid() async throws {
        final class RequestCounter {
            var count = 0
        }
        let counter = RequestCounter()
        let api = makeAPI { request in
            counter.count += 1
            let url = try XCTUnwrap(request.url)

            if counter.count == 1 {
                XCTAssertEqual(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "cmd" }?.value, "301001")
                XCTAssertEqual(request.value(forHTTPHeaderField: "forum_name"), "显卡")
                return Data([0x0A])
            }

            XCTAssertEqual(url.host, "c.tieba.baidu.com")
            XCTAssertEqual(url.path, "/c/f/frs/page")
            return Self.forumPageResponseJSON
        }

        let threads = try await api.forumThreads(account: .preview, forumName: "显卡", page: 1)

        XCTAssertEqual(counter.count, 2)
        XCTAssertEqual(threads.count, 1)
        XCTAssertEqual(threads.first?.title, "显卡主题")
        XCTAssertEqual(threads.first?.blocks, [.text("正文"), .emoticon(code: "滑稽")])
    }

    func testForumFormMapsExpiredSessionBusinessCode() async throws {
        let api = makeAPI { _ in
            #"{"error_code":"110001","error_msg":"登录失效","thread_list":[],"user_list":[]}"#.data(using: .utf8)!
        }

        do {
            _ = try await api.forumThreads(account: nil, forumName: "显卡", page: 1)
            XCTFail("Expected expired session business error")
        } catch {
            XCTAssertEqual(
                error as? TiebaAPIError,
                .sessionExpired(code: 110001, message: "登录失效")
            )
        }
    }

    func testSearchMapsExpiredSessionBusinessCode() async throws {
        let api = makeAPI { _ in
            #"{"no":110001,"error":"登录失效","data":{}}"#.data(using: .utf8)!
        }

        do {
            _ = try await api.searchThreads(keyword: "测试", page: 1)
            XCTFail("Expected expired session business error")
        } catch {
            XCTAssertEqual(
                error as? TiebaAPIError,
                .sessionExpired(code: 110001, message: "登录失效")
            )
        }
    }

    private func makeAPI(handler: @escaping (URLRequest) throws -> Data) -> TiebaAPI {
        SearchMockURLProtocol.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SearchMockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        return TiebaAPI(client: TiebaHTTPClient(session: session))
    }

    private static let searchResponseJSON = """
    {
      "no": 0,
      "error": "success",
      "data": {
        "has_more": 1,
        "current_page": 1,
        "post_list": [
          {
            "tid": "123",
            "pid": "456",
            "title": "主题标题",
            "content": "",
            "time": "1710000000",
            "post_num": "12",
            "like_num": "3",
            "share_num": "1",
            "forum_id": "789",
            "forum_name": "iPhone",
            "user": {
              "user_id": "42",
              "user_name": "raw",
              "show_nickname": "作者",
              "portrait": "tb.1.demo"
            },
            "post_info": {
              "title": "回复标题",
              "content": "命中回复"
            },
            "media": [
              {
                "type": "pic",
                "width": "800",
                "height": "600",
                "big_pic": "https://tiebapic.baidu.com/forum/pic/item/a.jpg",
                "src": "//tiebapic.baidu.com/forum/pic/item/a_original.jpg"
              },
              {
                "type": "flash",
                "width": "1280",
                "height": "720",
                "vsrc": "https://video.example/a.mp4",
                "vpic": "https://tiebapic.baidu.com/forum/pic/item/v.jpg"
              }
            ]
          }
        ]
      }
    }
    """.data(using: .utf8)!

    private static let forumPageResponseJSON = """
    {
      "error_code": "0",
      "error_msg": "",
      "thread_list": [
        {
          "id": "321",
          "title": "显卡主题",
          "reply_num": "4",
          "view_num": "20",
          "agree_num": "7",
          "author_id": "42",
          "abstract": "正文#(滑稽)"
        }
      ],
      "user_list": [
        {
          "id": "42",
          "name": "raw",
          "name_show": "作者",
          "portrait": "tb.1.demo"
        }
      ]
    }
    """.data(using: .utf8)!
}

private final class SearchMockURLProtocol: URLProtocol {
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
