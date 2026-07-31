import SwiftProtobuf
import XCTest
@testable import TiebaPure

final class FixtureDecodingTests: XCTestCase {
    private struct WireField: Equatable {
        var number: Int
        var wireType: UInt8
    }

    /// Hand-encoded wire bytes, deliberately not produced by SwiftProtobuf,
    /// so field-number or wire-type drift in the generated schemas fails the
    /// decode instead of round-tripping silently. The message is a minimal
    /// PbPageResponse: data(2) holding page(3){current_page 1, total_page 2,
    /// has_more 1}, one post_list(6) entry {id 9001, floor 1, author_id 77}
    /// whose content(5) carries a type-0 text block, a type-3 image block and
    /// a type-5 video block, thread(8){id 654321, title, replyNum 2,
    /// authorId 77} and one user_list(13) entry {id 77, name, nameShow}.
    private static let threadPageWireHex =
        "12f6021a0618012802300132ac0208a94618012a100800120ce6a5bce4b8bbe6"
        + "ada3e696872a780803222f68747470733a2f2f696d6773612e62616964752e63"
        + "6f6d2f666f72756d2f7069632f6974656d2f776972652e6a70672a073732302c"
        + "393630ca013668747470733a2f2f696d6773612e62616964752e636f6d2f666f"
        + "72756d2f7069632f6974656d2f776972655f6f726967696e2e6a70679802012a"
        + "95010805122068747470733a2f2f74696562612e62616964752e636f6d2f702f"
        + "3635343332311a2c68747470733a2f2f74622d766964656f2e62647374617469"
        + "632e636f6d2f766964656f2f776972652e6d7034223568747470733a2f2f696d"
        + "6773612e62616964752e636f6d2f666f72756d2f7069632f6974656d2f776972"
        + "655f636f7665722e6a70672a08313238302c373230685f98014d421d08f1f727"
        + "1a12e7babfe6a0bce5bc8fe6b58be8af95e5b8962002c0034d6a1e104d1a0977"
        + "6972655f75736572220fe7babfe6a0bce5bc8fe794a8e688b7"

    func testHandCraftedThreadPageWireBytesDecodeAndMapToDomain() throws {
        let wireData = try XCTUnwrap(Self.data(hex: Self.threadPageWireHex))
        let decoded = try Tieba_PbPage_PbPageResponse(serializedBytes: wireData)

        XCTAssertEqual(decoded.data.page.currentPage, 1)
        XCTAssertEqual(decoded.data.page.totalPage, 2)
        XCTAssertEqual(decoded.data.thread.id, 654321)
        XCTAssertEqual(decoded.data.thread.title, "线格式测试帖")
        XCTAssertEqual(decoded.data.postList.count, 1)
        XCTAssertEqual(decoded.data.postList.first?.content.count, 3)
        XCTAssertEqual(decoded.data.userList.first?.id, 77)
        XCTAssertEqual(decoded.data.userList.first?.nameShow, "线格式用户")

        let page = PostMapper.threadPage(from: decoded)

        XCTAssertEqual(page.thread.id, 654321)
        XCTAssertEqual(page.thread.title, "线格式测试帖")
        XCTAssertEqual(page.thread.replyCount, 2)
        XCTAssertEqual(page.thread.author.id, 77)
        XCTAssertEqual(page.thread.author.name, "wire_user")
        XCTAssertEqual(page.thread.author.displayName, "线格式用户")
        XCTAssertEqual(page.currentPage, 1)
        XCTAssertEqual(page.totalPage, 2)
        XCTAssertTrue(page.hasMore)

        let mainPost = try XCTUnwrap(page.mainPost)
        XCTAssertEqual(mainPost.id, 9001)
        XCTAssertEqual(mainPost.threadID, 654321)
        XCTAssertEqual(mainPost.floor, 1)
        XCTAssertEqual(mainPost.author.id, 77)
        XCTAssertEqual(mainPost.author.name, "wire_user")
        XCTAssertEqual(mainPost.blocks, [
            .text("楼主正文"),
            .image(ImageContent(
                thumbnailURL: URL(string: "https://imgsa.baidu.com/forum/pic/item/wire.jpg"),
                originalURL: URL(string: "https://imgsa.baidu.com/forum/pic/item/wire_origin.jpg"),
                width: 720,
                height: 960,
                showOriginalButton: true
            )),
            .video(VideoContent(
                videoURL: URL(string: "https://tb-video.bdstatic.com/video/wire.mp4"),
                coverURL: URL(string: "https://imgsa.baidu.com/forum/pic/item/wire_cover.jpg"),
                webURL: URL(string: "https://tieba.baidu.com/p/654321"),
                width: 1280,
                height: 720,
                duration: 95
            ))
        ])
    }

    func testHandCraftedPersonalizedWireBytesDecodeThreadAndAuthor() throws {
        let author = Self.message([
            .varint(2, 88),
            .string(3, "personalized_user"),
            .string(4, "推荐流用户")
        ])
        let thread = Self.message([
            .varint(1, 765_432),
            .string(3, "推荐流线格式主题"),
            .varint(4, 9),
            .varint(5, 120),
            .message(18, author),
            .varint(27, 66),
            .string(28, "推荐测试"),
            .varint(56, 88),
            .message(142, Self.message([.varint(1, 0), .string(2, "推荐流正文")]))
        ])
        let response = Self.message([
            .message(2, Self.message([.message(2, thread)]))
        ])

        let decoded = try Tieba_PersonalizedResponse(serializedBytes: response)
        let proto = try XCTUnwrap(decoded.data.threadList.first)
        let mapped = ThreadMapper.fromThreadInfo(proto, usersByID: [:])

        XCTAssertEqual(decoded.data.threadList.count, 1)
        XCTAssertEqual(mapped.id, 765_432)
        XCTAssertEqual(mapped.title, "推荐流线格式主题")
        XCTAssertEqual(mapped.author.id, 88)
        XCTAssertEqual(mapped.author.displayName, "推荐流用户")
        XCTAssertEqual(mapped.forumID, 66)
        XCTAssertEqual(mapped.forumName, "推荐测试")
        XCTAssertEqual(mapped.blocks, [.text("推荐流正文")])
    }

    func testRequestSchemasPreserveFieldNumbersWireTypesAndPresence() throws {
        var common = Tieba_CommonRequest()
        common.bduss = "BDUSS"
        common.stoken = "STOKEN"
        common.qType = 0
        common.isTeenager = 0
        XCTAssertEqual(
            try Self.fields(in: common.serializedData()),
            [
                WireField(number: 10, wireType: 2),
                WireField(number: 30, wireType: 2),
                WireField(number: 40, wireType: 0),
                WireField(number: 41, wireType: 0)
            ]
        )

        var frs = Tieba_FrsPage_FrsPageRequestData()
        frs.kw = "测试"
        frs.isGood = 1
        frs.cid = 0
        frs.pn = 2
        frs.common = Tieba_CommonRequest()
        frs.sortType = -1
        frs.loadType = 2
        frs.appPos = Tieba_AppPosInfo()
        frs.adParam = Tieba_FrsPage_AdParam()
        XCTAssertEqual(
            try Self.fields(in: frs.serializedData()),
            [
                WireField(number: 1, wireType: 2),
                WireField(number: 4, wireType: 0),
                WireField(number: 5, wireType: 0),
                WireField(number: 15, wireType: 0),
                WireField(number: 39, wireType: 2),
                WireField(number: 47, wireType: 0),
                WireField(number: 49, wireType: 0),
                WireField(number: 50, wireType: 2),
                WireField(number: 51, wireType: 2)
            ]
        )

        var page = Tieba_PbPage_PbPageRequestData()
        page.kz = 123
        page.lz = 1
        page.r = 2
        page.pid = 456
        page.withFloor = 1
        page.floorRn = 4
        page.rn = 15
        page.pn = 3
        page.common = Tieba_CommonRequest()
        page.forumID = 789
        page.floorSortType = 1
        page.sourceType = 2
        XCTAssertEqual(
            try Self.fields(in: page.serializedData()),
            [
                WireField(number: 4, wireType: 0),
                WireField(number: 5, wireType: 0),
                WireField(number: 6, wireType: 0),
                WireField(number: 7, wireType: 0),
                WireField(number: 8, wireType: 0),
                WireField(number: 9, wireType: 0),
                WireField(number: 13, wireType: 0),
                WireField(number: 18, wireType: 0),
                WireField(number: 25, wireType: 2),
                WireField(number: 56, wireType: 0),
                WireField(number: 74, wireType: 0),
                WireField(number: 75, wireType: 0)
            ]
        )

        var floor = Tieba_PbFloor_PbFloorRequestData()
        floor.kz = 123
        floor.pid = 456
        floor.spid = 789
        floor.pn = 2
        floor.common = Tieba_CommonRequest()
        floor.isCommReverse = 0
        floor.forumID = 42
        floor.oriUgcType = 0
        XCTAssertEqual(
            try Self.fields(in: floor.serializedData()),
            [
                WireField(number: 1, wireType: 0),
                WireField(number: 2, wireType: 0),
                WireField(number: 3, wireType: 0),
                WireField(number: 4, wireType: 0),
                WireField(number: 9, wireType: 2),
                WireField(number: 10, wireType: 0),
                WireField(number: 11, wireType: 0),
                WireField(number: 15, wireType: 0)
            ]
        )

        var personalized = Tieba_PersonalizedRequestData()
        personalized.common = Tieba_CommonRequest()
        personalized.loadType = 2
        personalized.pn = 3
        personalized.scrDip = 3
        personalized.needForumlist = 1
        personalized.appPos = Tieba_AppPosInfo()
        XCTAssertEqual(
            try Self.fields(in: personalized.serializedData()),
            [
                WireField(number: 1, wireType: 2),
                WireField(number: 4, wireType: 0),
                WireField(number: 6, wireType: 0),
                WireField(number: 10, wireType: 1),
                WireField(number: 22, wireType: 0),
                WireField(number: 36, wireType: 2)
            ]
        )

        var profile = Tiebapure_Profile_UserProfileRequestData()
        profile.uid = 0
        profile.friendUid = 77
        profile.pn = 2
        profile.common = Tieba_CommonRequest()
        XCTAssertTrue(profile.hasUid)
        XCTAssertTrue(profile.hasFriendUid)
        XCTAssertEqual(
            try Self.fields(in: profile.serializedData()),
            [
                WireField(number: 1, wireType: 0),
                WireField(number: 3, wireType: 0),
                WireField(number: 6, wireType: 0),
                WireField(number: 9, wireType: 2)
            ]
        )

        var userThreads = Tiebapure_Profile_UserThreadsRequestData()
        userThreads.uid = 77
        userThreads.isThread = 0
        userThreads.pn = 2
        userThreads.common = Tieba_CommonRequest()
        userThreads.isViewCard = 0
        XCTAssertTrue(userThreads.hasIsThread)
        XCTAssertTrue(userThreads.hasIsViewCard)
        XCTAssertEqual(
            try Self.fields(in: userThreads.serializedData()),
            [
                WireField(number: 1, wireType: 0),
                WireField(number: 4, wireType: 0),
                WireField(number: 26, wireType: 0),
                WireField(number: 27, wireType: 2),
                WireField(number: 33, wireType: 0)
            ]
        )
    }

    func testHandCraftedForumWireBytesDecodeUsersAndThreads() throws {
        let author = Self.message([
            .varint(2, 77),
            .string(3, "wire_user"),
            .string(4, "线格式用户"),
            .string(125, "协议测试")
        ])
        let thread = Self.message([
            .varint(1, 654_321),
            .string(3, "线格式吧页主题"),
            .varint(4, 12),
            .varint(5, 345),
            .varint(27, 88),
            .string(28, "测试"),
            .varint(56, 77),
            .message(142, Self.message([.varint(1, 0), .string(2, "主题正文")]))
        ])
        let response = Self.message([
            .message(2, Self.message([
                .message(7, thread),
                .message(17, author)
            ]))
        ])

        let decoded = try Tieba_FrsPage_FrsPageResponse(serializedBytes: response)
        XCTAssertEqual(decoded.data.threadList.count, 1)
        XCTAssertEqual(decoded.data.userList.count, 1)

        let users = Dictionary(uniqueKeysWithValues: decoded.data.userList.map { ($0.id, $0) })
        let mapped = ThreadMapper.fromThreadInfo(try XCTUnwrap(decoded.data.threadList.first), usersByID: users)
        XCTAssertEqual(mapped.id, 654_321)
        XCTAssertEqual(mapped.title, "线格式吧页主题")
        XCTAssertEqual(mapped.author.displayName, "线格式用户")
        XCTAssertEqual(mapped.author.levelName, "协议测试")
        XCTAssertEqual(mapped.forumID, 88)
        XCTAssertEqual(mapped.forumName, "测试")
        XCTAssertEqual(mapped.blocks, [.text("主题正文")])
    }

    func testHandCraftedFloorWireBytesDecodeReplyMetadata() throws {
        let author = Self.message([
            .varint(2, 77),
            .string(3, "reply_user"),
            .string(4, "回复用户"),
            .string(127, "广东")
        ])
        let content = Self.message([.varint(1, 0), .string(2, "楼中楼正文")])
        let agree = Self.message([.varint(1, 23), .varint(2, 1)])
        let location = Self.message([.string(3, "深圳")])
        let subpost = Self.message([
            .varint(1, 9_001),
            .message(2, content),
            .varint(3, 1_720_000_000),
            .varint(4, 77),
            .varint(6, 3),
            .message(7, author),
            .message(9, agree),
            .message(10, location)
        ])
        let response = Self.message([
            .message(2, Self.message([.message(4, subpost)]))
        ])

        let decoded = try Tieba_PbFloor_PbFloorResponse(serializedBytes: response)
        let proto = try XCTUnwrap(decoded.data.subpostList.first)
        XCTAssertEqual(proto.location.name, "深圳")
        XCTAssertEqual(proto.author.ipAddress, "广东")
        let mapped = PostMapper.subpost(proto)
        XCTAssertEqual(mapped.id, 9_001)
        XCTAssertEqual(mapped.floor, 3)
        XCTAssertEqual(mapped.author.displayName, "回复用户")
        XCTAssertEqual(mapped.ipAddress, "广东")
        XCTAssertEqual(mapped.likeCount, 23)
        XCTAssertTrue(mapped.isLiked)
        XCTAssertEqual(mapped.blocks, [.text("楼中楼正文")])
    }

    func testHandCraftedProfileWireBytesPreserveHighNumberedUserFields() throws {
        let forum = Self.message([.string(1, "测试"), .varint(2, 88)])
        let privacy = Self.message([.varint(2, 1)])
        let user = Self.message([
            .varint(2, 77),
            .string(3, "wire_user"),
            .string(4, "线格式用户"),
            .varint(30, 56),
            .varint(31, 34),
            .varint(33, 1),
            .varint(35, 1),
            .string(38, "8.5"),
            .message(45, privacy),
            .message(47, forum),
            .varint(87, 12),
            .varint(118, 4_321),
            .string(120, "tieba-wire-id"),
            .string(125, "协议测试"),
            .string(127, "广东"),
            .string(138, "简介")
        ])
        let response = Self.message([
            .message(2, Self.message([.message(1, user)]))
        ])

        let decoded = try Tiebapure_Profile_UserProfileResponse(serializedBytes: response)
        let profile = UserProfileMapper.profile(
            from: decoded.data.user,
            fallback: UserSummary(id: 77, name: "wire_user", displayName: "线格式用户", portrait: ""),
            isCurrentUser: false
        )
        XCTAssertTrue(profile.isFollowed)
        XCTAssertEqual(profile.tiebaID, "tieba-wire-id")
        XCTAssertEqual(profile.tiebaAge, "8.5")
        XCTAssertEqual(profile.location, "广东")
        XCTAssertEqual(profile.intro, "简介")
        XCTAssertEqual(profile.agreeCount, 4_321)
        XCTAssertEqual(profile.followingCount, 34)
        XCTAssertEqual(profile.followerCount, 56)
        XCTAssertEqual(profile.threadCount, 12)
        XCTAssertEqual(profile.followedForums.map(\.name), ["测试"])
        XCTAssertEqual(decoded.data.user.privSets.like, 1)
        XCTAssertEqual(profile.followedForumsVisibility, .visible)
    }

    func testHandCraftedUserThreadsWireBytesDecodeContentAndPrivacy() throws {
        let post = Self.message([
            .varint(1, 66),
            .varint(2, 765_432),
            .varint(5, 1_720_000_000),
            .string(6, "推荐测试"),
            .string(7, "用户主题线格式"),
            .string(9, "用户主题正文"),
            .string(10, "user_threads"),
            .string(11, "广东"),
            .varint(17, 15),
            .varint(18, 88),
            .string(19, "portrait-token"),
            .string(35, "用户主题作者"),
            .varint(37, 23),
            .varint(38, 456)
        ])
        let visibleResponse = Self.message([
            .message(2, Self.message([.message(1, post)]))
        ])

        let decoded = try Tiebapure_Profile_UserThreadsResponse(serializedBytes: visibleResponse)
        let page = UserProfileMapper.threadsPage(from: decoded, page: 1)
        let thread = try XCTUnwrap(page.threads.first)

        XCTAssertEqual(page.visibility, .visible)
        XCTAssertTrue(page.hasMore)
        XCTAssertEqual(thread.id, 765_432)
        XCTAssertEqual(thread.forumID, 66)
        XCTAssertEqual(thread.forumName, "推荐测试")
        XCTAssertEqual(thread.author.id, 88)
        XCTAssertEqual(thread.author.displayName, "用户主题作者")
        XCTAssertEqual(thread.author.ipAddress, "广东")
        XCTAssertEqual(thread.replyCount, 15)
        XCTAssertEqual(thread.likeCount, 23)
        XCTAssertEqual(thread.viewCount, 456)
        XCTAssertEqual(thread.blocks, [.text("用户主题正文")])

        let privateResponse = Self.message([
            .message(2, Self.message([.varint(2, 1)]))
        ])
        let privateDecoded = try Tiebapure_Profile_UserThreadsResponse(serializedBytes: privateResponse)
        let privatePage = UserProfileMapper.threadsPage(from: privateDecoded, page: 1)
        XCTAssertEqual(privatePage.visibility, .privateContent)
        XCTAssertFalse(privatePage.hasMore)
        XCTAssertTrue(privatePage.threads.isEmpty)
    }

    private static func data(hex: String) -> Data? {
        guard hex.count.isMultiple(of: 2) else { return nil }
        var bytes = [UInt8]()
        bytes.reserveCapacity(hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        return Data(bytes)
    }

    private enum RawField {
        case varint(Int, UInt64)
        case string(Int, String)
        case message(Int, Data)
    }

    private static func message(_ fields: [RawField]) -> Data {
        var data = Data()
        for field in fields {
            switch field {
            case let .varint(number, value):
                appendVarint(UInt64(number << 3), to: &data)
                appendVarint(value, to: &data)
            case let .string(number, value):
                appendLengthDelimited(number: number, bytes: Data(value.utf8), to: &data)
            case let .message(number, value):
                appendLengthDelimited(number: number, bytes: value, to: &data)
            }
        }
        return data
    }

    private static func appendLengthDelimited(number: Int, bytes: Data, to data: inout Data) {
        appendVarint(UInt64((number << 3) | 2), to: &data)
        appendVarint(UInt64(bytes.count), to: &data)
        data.append(bytes)
    }

    private static func appendVarint(_ value: UInt64, to data: inout Data) {
        var remaining = value
        while remaining >= 0x80 {
            data.append(UInt8(remaining & 0x7f) | 0x80)
            remaining >>= 7
        }
        data.append(UInt8(remaining))
    }

    private static func fields(in data: Data) throws -> [WireField] {
        var index = data.startIndex
        var fields = [WireField]()
        while index < data.endIndex {
            let key = try readVarint(from: data, index: &index)
            let wireType = UInt8(key & 0x07)
            fields.append(WireField(number: Int(key >> 3), wireType: wireType))
            switch wireType {
            case 0:
                _ = try readVarint(from: data, index: &index)
            case 1:
                try advance(&index, by: 8, in: data)
            case 2:
                let count = try readVarint(from: data, index: &index)
                guard count <= UInt64(Int.max) else { throw WireFixtureError.invalidLength }
                try advance(&index, by: Int(count), in: data)
            case 5:
                try advance(&index, by: 4, in: data)
            default:
                throw WireFixtureError.unsupportedWireType(wireType)
            }
        }
        return fields
    }

    private static func readVarint(from data: Data, index: inout Data.Index) throws -> UInt64 {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        while index < data.endIndex, shift < 64 {
            let byte = data[index]
            index = data.index(after: index)
            result |= UInt64(byte & 0x7f) << shift
            if byte & 0x80 == 0 { return result }
            shift += 7
        }
        throw WireFixtureError.truncated
    }

    private static func advance(_ index: inout Data.Index, by count: Int, in data: Data) throws {
        guard let next = data.index(index, offsetBy: count, limitedBy: data.endIndex) else {
            throw WireFixtureError.truncated
        }
        index = next
    }

    private enum WireFixtureError: Error {
        case truncated
        case invalidLength
        case unsupportedWireType(UInt8)
    }
}
