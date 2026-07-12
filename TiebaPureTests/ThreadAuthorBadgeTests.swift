import XCTest
@testable import TiebaPure

final class ThreadAuthorBadgeTests: XCTestCase {
    func testSubpostInlinePrefixKeepsThreadAuthorBadgeSeparateFromUsernameText() {
        let parts = SubpostInlinePrefix.parts(authorName: "楼中楼用户", isThreadAuthor: true)

        XCTAssertEqual(parts, [
            .text("楼中楼用户"),
            .text(" "),
            .threadAuthorBadge,
            .text(": ")
        ])
        XCTAssertFalse(parts.compactMap(\.plainText).joined().contains("楼主"))
    }

    func testSubpostInlinePrefixOmitsThreadAuthorBadgeForOtherUsers() {
        let parts = SubpostInlinePrefix.parts(authorName: "普通用户", isThreadAuthor: false)

        XCTAssertEqual(parts, [.text("普通用户: ")])
    }
}

final class TallImageLayoutTests: XCTestCase {
    func testTallImageHeightIsCappedByWidthAndAbsoluteLimit() {
        let image = ImageContent(thumbnailURL: nil, originalURL: nil, width: 100, height: 1_000, showOriginalButton: true)

        XCTAssertEqual(TiebaLiteInlineImageLayoutPolicy.height(containerWidth: 320, image: image), 480)
        XCTAssertEqual(TiebaLiteInlineImageLayoutPolicy.height(containerWidth: 1_000, image: image), 600)
        XCTAssertTrue(TiebaLiteInlineImageLayoutPolicy.isTall(image))
    }
}
