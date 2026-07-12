import SwiftProtobuf
import XCTest
@testable import TiebaPure

final class MultipartFormDataTests: XCTestCase {
    func testMultipartContainsDataFileAndStoken() throws {
        let body = MultipartFormData(boundary: "--------7da3d81520810*")
        body.addField(name: "_client_version", value: "12.52.1.0")
        body.addField(name: "stoken", value: "stoken")
        body.addFile(name: "data", filename: "file", data: Data([0x08, 0x01]))

        let data = body.finalize()
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertTrue(text.contains("name=\"_client_version\""))
        XCTAssertTrue(text.contains("name=\"stoken\""))
        XCTAssertTrue(text.contains("name=\"data\"; filename=\"file\""))
        XCTAssertTrue(text.hasSuffix("--------7da3d81520810*--\r\n"))
    }

    func testRequestBuilderAddsSTokenAndSerializedProtobuf() throws {
        let builder = TiebaRequestBuilder(
            screenScale: 3,
            screenWidth: 1179,
            screenHeight: 2556,
            clientID: "client"
        )
        let account = Account(
            uid: "42",
            name: "raw",
            displayName: "Raw",
            portrait: "",
            bduss: "bduss",
            stoken: "stoken",
            baiduID: nil,
            tbs: "tbs"
        )

        var request = Tieba_CommonRequest()
        request.clientType = 2

        let multipart = try builder.multipart(protobuf: request, account: account, includeSToken: true)
        let text = try XCTUnwrap(String(data: multipart.body, encoding: .utf8))

        XCTAssertEqual(multipart.contentType, "multipart/form-data; boundary=\(TiebaRequestBuilder.boundary)")
        XCTAssertTrue(text.contains("name=\"stoken\""))
        XCTAssertTrue(text.contains("name=\"data\"; filename=\"file\""))
    }

    func testCommonRequestCopiesAccountAndDeviceFields() {
        let builder = TiebaRequestBuilder(
            screenScale: 3,
            screenWidth: 1179,
            screenHeight: 2556,
            clientID: "client"
        )
        let account = Account(
            uid: "42",
            name: "raw",
            displayName: "Raw",
            portrait: "",
            bduss: "bduss",
            stoken: "stoken",
            baiduID: nil,
            tbs: "tbs"
        )

        let common = builder.common(account: account)

        XCTAssertEqual(common.bduss, "bduss")
        XCTAssertEqual(common.stoken, "stoken")
        XCTAssertEqual(common.clientID, "client")
        XCTAssertEqual(common.clientVersion, "12.52.1.0")
        XCTAssertEqual(common.userAgent, "tieba/12.52.1.0")
        XCTAssertEqual(common.scrW, 1179)
        XCTAssertEqual(common.scrH, 2556)
        XCTAssertEqual(common.scrDip, 3)
    }
}
