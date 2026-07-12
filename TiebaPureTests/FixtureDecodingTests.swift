import SwiftProtobuf
import XCTest
@testable import TiebaPure

final class FixtureDecodingTests: XCTestCase {
    func testPbContentRoundTripKeepsVideoFields() throws {
        var content = Tieba_PbContent()
        content.type = 5
        content.text = "https://tieba.baidu.com/p/123"
        content.link = "https://video.example/video.mp4"
        content.src = "https://video.example/cover.jpg"
        content.bsize = "1920,1080"

        let data = try content.serializedData()
        let decoded = try Tieba_PbContent(serializedBytes: data)

        XCTAssertEqual(decoded.type, 5)
        XCTAssertEqual(decoded.link, "https://video.example/video.mp4")
        XCTAssertEqual(decoded.src, "https://video.example/cover.jpg")
    }
}
