import XCTest
@testable import TiebaPure

final class TiebaURLTests: XCTestCase {
    func testTiebaURLRejectsHTTPImageURL() {
        let url = TiebaURL.make("http://tiebapic.baidu.com/forum/pic/item/a.jpg?tbpicau=test")

        XCTAssertNil(url)
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
    }

    func testTiebaURLAcceptsOnlyPublicHTTPS() {
        XCTAssertEqual(TiebaURL.webpage("https://tieba.baidu.com/p/1")?.scheme, "https")
        XCTAssertNil(TiebaURL.image("http://tiebapic.baidu.com/a.jpg"))
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
}
