import XCTest
import UIKit
@testable import TiebaPure

final class ThreadAuthorBadgeTests: XCTestCase {
    func testSubpostInlinePrefixKeepsThreadAuthorBadgeSeparateFromUsernameText() {
        let author = UserSummary(
            id: 8,
            name: "subpost_user",
            displayName: "楼中楼用户",
            portrait: ""
        )
        let parts = SubpostInlinePrefix.parts(author: author, isThreadAuthor: true)

        XCTAssertEqual(parts, [
            .user(author),
            .text(" "),
            .threadAuthorBadge,
            .text(": ")
        ])
        XCTAssertFalse(parts.compactMap(\.plainText).joined().contains("楼主"))
    }

    func testSubpostInlinePrefixOmitsThreadAuthorBadgeForOtherUsers() {
        let author = UserSummary(
            id: 9,
            name: "ordinary_user",
            displayName: "普通用户",
            portrait: ""
        )
        let parts = SubpostInlinePrefix.parts(author: author, isThreadAuthor: false)

        XCTAssertEqual(parts, [.user(author), .text(": ")])
    }

    func testSubpostInlineAuthorUsesTheSameSecondaryNativeLinkAsReplyTarget() throws {
        let author = UserSummary(
            id: 9,
            name: "ordinary_user",
            displayName: "回复作者",
            portrait: "tb.1.reply_author"
        )
        let text = InlineContentText(
            blocks: [.text("回复 "), .mention(userID: 42, text: "被回复用户")],
            style: .subpost,
            prefixParts: [.user(author), .text(": ")],
            onOpenUser: { _ in }
        ).attributedString()

        let authorRange = (text.string as NSString).range(of: "回复作者")
        let targetRange = (text.string as NSString).range(of: "被回复用户")
        let authorColor = try XCTUnwrap(
            text.attribute(.foregroundColor, at: authorRange.location, effectiveRange: nil) as? UIColor
        )
        let targetColor = try XCTUnwrap(
            text.attribute(.foregroundColor, at: targetRange.location, effectiveRange: nil) as? UIColor
        )
        let authorURL = try XCTUnwrap(
            text.attribute(.link, at: authorRange.location, effectiveRange: nil) as? URL
        )
        let targetURL = try XCTUnwrap(
            text.attribute(.link, at: targetRange.location, effectiveRange: nil) as? URL
        )

        XCTAssertEqual(authorColor, InlineUserNamePresentation.foregroundColor)
        XCTAssertEqual(targetColor, InlineUserNamePresentation.foregroundColor)
        let decodedAuthor = try XCTUnwrap(InlineUserProfileLink.user(from: authorURL))
        XCTAssertEqual(decodedAuthor.id, author.id)
        XCTAssertEqual(decodedAuthor.displayNameResolved, author.displayNameResolved)
        XCTAssertEqual(decodedAuthor.portrait, author.portrait)
        XCTAssertEqual(InlineUserProfileLink.user(from: targetURL)?.id, 42)
    }
}

final class TallImageLayoutTests: XCTestCase {
    func testTallImageHeightIsCappedByWidthAndAbsoluteLimit() {
        let image = ImageContent(thumbnailURL: nil, originalURL: nil, width: 100, height: 1_000, showOriginalButton: true)

        XCTAssertEqual(InlineImageLayoutPolicy.height(containerWidth: 320, image: image), 480)
        XCTAssertEqual(InlineImageLayoutPolicy.height(containerWidth: 1_000, image: image), 600)
        XCTAssertTrue(InlineImageLayoutPolicy.isTall(image))
    }
}
