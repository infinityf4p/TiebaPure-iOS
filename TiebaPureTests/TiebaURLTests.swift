import XCTest
@testable import TiebaPure

final class TiebaURLTests: XCTestCase {
    func testTiebaURLUpgradesHTTPImageURLToHTTPS() {
        let url = TiebaURL.make("http://tiebapic.baidu.com/forum/pic/item/a.jpg?tbpicau=test")

        XCTAssertEqual(url?.absoluteString, "https://tiebapic.baidu.com/forum/pic/item/a.jpg?tbpicau=test")
    }

    func testTiebaURLHandlesProtocolRelativeURL() {
        let url = TiebaURL.make("//tb.himg.baidu.com/sys/portrait/item/user")

        XCTAssertEqual(url?.absoluteString, "https://tb.himg.baidu.com/sys/portrait/item/user")
    }

    func testTiebaURLRejectsDangerousSchemesUserInfoAndLocalTargets() {
        XCTAssertNil(TiebaURL.webpage("javascript:alert(1)"))
        XCTAssertNil(TiebaURL.image("file:///tmp/private"))
        XCTAssertNil(TiebaURL.video("data:video/mp4;base64,AAAA"))
        XCTAssertNil(TiebaURL.webpage("https://user:pass@example.com/path"))
        XCTAssertNil(TiebaURL.webpage("https://localhost/path"))
        XCTAssertNil(TiebaURL.webpage("https://127.0.0.1/path"))
        XCTAssertNil(TiebaURL.webpage("https://10.0.0.8/path"))
        XCTAssertNil(TiebaURL.webpage("https://172.20.0.1/path"))
        XCTAssertNil(TiebaURL.webpage("https://192.168.1.1/path"))
        XCTAssertNil(TiebaURL.webpage("https://[::1]/path"))
        XCTAssertNil(TiebaURL.webpage("https://2130706433/path"))
        XCTAssertNil(TiebaURL.webpage("https://0x7f000001/path"))
        XCTAssertNil(TiebaURL.webpage("https://0177.0.0.1/path"))
        XCTAssertNil(TiebaURL.webpage("https://127.1/path"))
        XCTAssertNil(TiebaURL.webpage("https://localhost./path"))
        XCTAssertNil(TiebaURL.webpage("https://printer.local/path"))
        XCTAssertNil(TiebaURL.webpage("https://[0:0:0:0:0:0:0:1]/path"))
        XCTAssertNil(TiebaURL.webpage("https://[::ffff:127.0.0.1]/path"))
        XCTAssertNil(TiebaURL.webpage("https://[fc00::1]/path"))
        XCTAssertNil(TiebaURL.webpage("https://[fe80::1]/path"))
        XCTAssertNil(TiebaURL.webpage("http://user:pass@example.com/path"))
        XCTAssertNil(TiebaURL.webpage("http://localhost/path"))
        XCTAssertNil(TiebaURL.webpage("http://127.0.0.1/path"))
        XCTAssertNil(TiebaURL.webpage("http://192.168.1.1/path"))
    }

    func testTiebaURLAcceptsOnlyPublicHTTPSAndUpgradesHTTP() {
        XCTAssertEqual(TiebaURL.webpage("https://tieba.baidu.com/p/1")?.scheme, "https")
        XCTAssertEqual(TiebaURL.image("http://tiebapic.baidu.com/a.jpg")?.absoluteString, "https://tiebapic.baidu.com/a.jpg")
    }

    func testVideoPresentationRevalidatesInitialURLs() throws {
        let secureVideo = try XCTUnwrap(URL(string: "https://video.example/demo.mp4"))
        let insecureVideo = try XCTUnwrap(URL(string: "http://video.example/demo.mp4"))
        let privateWebpage = try XCTUnwrap(URL(string: "https://127.0.0.1/watch"))

        XCTAssertEqual(TiebaVideoSourcePolicy.videoURL(secureVideo), secureVideo)
        XCTAssertEqual(TiebaVideoSourcePolicy.videoURL(insecureVideo), secureVideo)
        XCTAssertNil(TiebaVideoSourcePolicy.videoURL(URL(fileURLWithPath: "/tmp/private.mp4")))
        XCTAssertNil(TiebaVideoSourcePolicy.webpageURL(privateWebpage))
    }

    func testRedirectPolicyRevalidatesEveryDestination() {
        XCTAssertTrue(SecureRemoteRedirectScope.publicHTTPS.allows(URL(string: "https://tiebapic.baidu.com/a.jpg")))
        XCTAssertFalse(SecureRemoteRedirectScope.publicHTTPS.allows(URL(string: "http://tiebapic.baidu.com/a.jpg")))
        XCTAssertFalse(SecureRemoteRedirectScope.publicHTTPS.allows(URL(string: "https://2130706433/private")))
        XCTAssertFalse(SecureRemoteRedirectScope.publicHTTPS.allows(URL(string: "https://[::ffff:127.0.0.1]/private")))
    }

    func testAPIRedirectPolicyNeverForwardsSensitiveRequestsOutsideBaidu() {
        XCTAssertTrue(SecureRemoteRedirectScope.baiduHTTPS.allows(URL(string: "https://c.tieba.baidu.com/c/f/frs/page")))
        XCTAssertFalse(SecureRemoteRedirectScope.baiduHTTPS.allows(URL(string: "https://attacker.example/collect")))
        XCTAssertFalse(SecureRemoteRedirectScope.baiduHTTPS.allows(URL(string: "https://baidu.com.attacker.example/collect")))
    }

    func testEmoticonRedirectPolicyAllowsOnlyExactCDNAndValidArtworkPath() {
        XCTAssertTrue(SecureRemoteRedirectScope.bdStaticHTTPS.allows(URL(
            string: "https://tb2.bdstatic.com/tb/editor/images/client/image_emoticon125.png"
        )))
        XCTAssertFalse(SecureRemoteRedirectScope.bdStaticHTTPS.allows(URL(
            string: "https://tb1.bdstatic.com/tb/editor/images/client/image_emoticon125.png"
        )))
        XCTAssertFalse(SecureRemoteRedirectScope.bdStaticHTTPS.allows(URL(
            string: "https://bdstatic.com/tb/editor/images/client/image_emoticon125.png"
        )))
        XCTAssertFalse(SecureRemoteRedirectScope.bdStaticHTTPS.allows(URL(
            string: "https://tb2.bdstatic.com/tb/editor/images/client/not-an-emoticon.png"
        )))
        XCTAssertFalse(SecureRemoteRedirectScope.bdStaticHTTPS.allows(URL(
            string: "https://tb2.bdstatic.com/tb/editor/images/client/image_emoticon1000.png"
        )))
        XCTAssertFalse(SecureRemoteRedirectScope.bdStaticHTTPS.allows(URL(
            string: "https://tb2.bdstatic.com/tb/editor/images/client/nested/image_emoticon1.png"
        )))
        XCTAssertFalse(SecureRemoteRedirectScope.bdStaticHTTPS.allows(URL(
            string: "http://tb2.bdstatic.com/tb/editor/images/client/image_emoticon1.png"
        )))
    }

    func testExternalRouteParsesCustomSchemeAndWebLinks() throws {
        XCTAssertEqual(
            ExternalRoute.parse(try XCTUnwrap(URL(string: "tiebapure://thread/8888888888"))),
            .thread(id: 8_888_888_888, postID: nil)
        )
        XCTAssertEqual(
            ExternalRoute.parse(try XCTUnwrap(URL(string: "tiebapure://thread/123?pid=456"))),
            .thread(id: 123, postID: 456)
        )
        XCTAssertEqual(
            ExternalRoute.parse(try XCTUnwrap(URL(string: "tiebapure://forum/%E5%AD%99%E7%AC%91%E5%B7%9D"))),
            .forum(name: "孙笑川")
        )
        XCTAssertEqual(
            ExternalRoute.parse(try XCTUnwrap(URL(string: "tiebapure://forum?kw=steam"))),
            .forum(name: "steam")
        )
        XCTAssertEqual(
            ExternalRoute.parse(try XCTUnwrap(URL(
                string: "tiebapure://open?url=https%3A%2F%2Ftieba.baidu.com%2Fp%2F9999%3Fpid%3D77"
            ))),
            .thread(id: 9_999, postID: 77)
        )
        XCTAssertEqual(
            ExternalRoute.parse(try XCTUnwrap(URL(string: "https://tieba.baidu.com/p/424242"))),
            .thread(id: 424_242, postID: nil)
        )
        XCTAssertEqual(
            ExternalRoute.parse(try XCTUnwrap(URL(string: "https://tieba.baidu.com/f?kw=%E6%B5%8B%E8%AF%95"))),
            .forum(name: "测试")
        )
        XCTAssertEqual(
            ExternalRoute.parse(try XCTUnwrap(URL(string: "https://tieba.baidu.com/f?kw=%E6%B5%8B%E8%AF%95%E5%90%A7"))),
            .forum(name: "测试")
        )
        XCTAssertEqual(
            ExternalRoute.parse(try XCTUnwrap(URL(string: "https://c.tieba.baidu.com/p/31337"))),
            .thread(id: 31_337, postID: nil)
        )
        XCTAssertEqual(
            ExternalRoute.parse(try XCTUnwrap(URL(
                string: "https://tieba.baidu.com/p/123?pid=9223372036854775807"
            ))),
            .thread(id: 123, postID: UInt64(Int64.max))
        )
        XCTAssertEqual(
            ExternalRoute.parse(try XCTUnwrap(URL(
                string: "https://tieba.baidu.com/p/123?pid=9223372036854775808"
            ))),
            .thread(id: 123, postID: nil)
        )
        XCTAssertEqual(
            ExternalRoute.parse(try XCTUnwrap(URL(
                string: "tiebapure://thread/123?post_id=18446744073709551615"
            ))),
            .thread(id: 123, postID: nil)
        )

        XCTAssertNil(ExternalRoute.parse(try XCTUnwrap(URL(string: "tiebapure://thread/abc"))))
        XCTAssertNil(ExternalRoute.parse(try XCTUnwrap(URL(string: "tiebapure://thread/0"))))
        XCTAssertNil(ExternalRoute.parse(try XCTUnwrap(URL(string: "tiebapure://forum/%20"))))
        XCTAssertNil(ExternalRoute.parse(try XCTUnwrap(URL(
            string: "tiebapure://forum/\(String(repeating: "a", count: 101))"
        ))))
        XCTAssertNil(ExternalRoute.parse(try XCTUnwrap(URL(string: "tiebapure://user:pass@thread/123"))))
        XCTAssertNil(ExternalRoute.parse(try XCTUnwrap(URL(string: "https://attacker.example/p/1"))))
        XCTAssertNil(ExternalRoute.parse(try XCTUnwrap(URL(string: "http://tieba.baidu.com/p/1"))))
        XCTAssertNil(ExternalRoute.parse(try XCTUnwrap(URL(string: "https://user:pass@tieba.baidu.com/p/1"))))
        XCTAssertNil(ExternalRoute.parse(try XCTUnwrap(URL(
            string: "tiebapure://open?url=https%3A%2F%2Fattacker.example%2Fp%2F1"
        ))))
        XCTAssertNil(ExternalRoute.parse(try XCTUnwrap(URL(
            string: "tiebapure://open?url=http%3A%2F%2Ftieba.baidu.com%2Fp%2F1"
        ))))
        XCTAssertNil(ExternalRoute.parse(try XCTUnwrap(URL(
            string: "tiebapure://open?url=https%3A%2F%2Fuser%3Apass%40tieba.baidu.com%2Fp%2F1"
        ))))
        XCTAssertNil(ExternalRoute.parse(try XCTUnwrap(URL(string: "https://faketieba.baidu.com.evil.example/p/1"))))
    }
}
