import SwiftProtobuf
import XCTest
@testable import TiebaPure

/// One assertion per test on purpose. The CI runner keeps the failing test's
/// NAME but drops the assertion body (the `.xcresult` is never uploaded), so a
/// per-field failure is only identifiable from the test that carries it.
private func assertField<T: Equatable>(
    _ actual: T,
    _ expected: T,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    if actual != expected {
        XCTFail("field mismatch", file: file, line: line)
    }
}

final class HotThreadListTests: XCTestCase {
    /// Hand-encoded wire bytes, deliberately not produced by SwiftProtobuf, so
    /// field-number or wire-type drift in the generated schema fails the decode
    /// instead of round-tripping silently. A minimal HotThreadListResponse:
    /// data(2) holding one thread_info(2) {id 9001, title, replyNum 7,
    /// forumId 555, forumName, authorId 77} and one hot_thread_tab_info(3)
    /// {tab_name 3 = 综合, tab_code 8 = hot_all}.
    private static let hotThreadWireHex =
        "1241"
        + "122c"
        + "08a946"
        + "1a12e7babfe6a0bce5bc8fe783ade782b9e5b896"
        + "2007"
        + "d801ab04"
        + "e20109e783ade782b9e590a7"
        + "c0034d"
        + "1a11"
        + "1a06e7bbbce59088"
        + "4207686f745f616c6c"

    private static func data(hex: String) -> Data? {
        var bytes: [UInt8] = []
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        return Data(bytes)
    }

    /// One protobuf field read off the wire, so a request assertion can look at
    /// real field numbers instead of the generated accessors.
    private struct WireField {
        var number: Int
        var wireType: UInt8
        var payload: Data
    }

    private static func wireFields(_ data: Data) throws -> [WireField] {
        let bytes = [UInt8](data)
        var index = 0
        var fields: [WireField] = []

        func readVarint() throws -> UInt64 {
            var result: UInt64 = 0
            var shift: UInt64 = 0
            while true {
                guard index < bytes.count else {
                    throw WireError.truncated
                }
                let byte = bytes[index]
                index += 1
                result |= UInt64(byte & 0x7F) << shift
                if byte & 0x80 == 0 { break }
                shift += 7
            }
            return result
        }

        while index < bytes.count {
            let tag = try readVarint()
            let number = Int(tag >> 3)
            let wireType = UInt8(tag & 0x07)
            switch wireType {
            case 0:
                _ = try readVarint()
                fields.append(WireField(number: number, wireType: wireType, payload: Data()))
            case 2:
                let length = Int(try readVarint())
                guard index + length <= bytes.count else { throw WireError.truncated }
                fields.append(WireField(
                    number: number,
                    wireType: wireType,
                    payload: Data(bytes[index..<(index + length)])
                ))
                index += length
            default:
                throw WireError.unsupportedWireType(wireType)
            }
        }
        return fields
    }

    private enum WireError: Error {
        case truncated
        case unsupportedWireType(UInt8)
    }

    private var requestBuilder: TiebaRequestBuilder {
        TiebaRequestBuilder(
            screenScale: 3,
            screenWidth: 1179,
            screenHeight: 2556,
            clientID: "hotwireclient"
        )
    }

    private func decodedWireThreadInfo() throws -> Tieba_ThreadInfo {
        let wireData = try XCTUnwrap(Self.data(hex: Self.hotThreadWireHex))
        let decoded = try Tieba_HotThreadList_HotThreadListResponse(serializedBytes: wireData)
        return try XCTUnwrap(decoded.data.threadInfo.first)
    }

    private func mappedWireThread() throws -> ThreadSummary {
        ThreadMapper.fromThreadInfo(try decodedWireThreadInfo(), usersByID: [:])
    }

    func testHotThreadListEndpointTargetsTheCommandProtobufPath() {
        let url = TiebaEndpoint.hotThreadList.url

        XCTAssertEqual(url.host, "tieba.baidu.com")
        XCTAssertEqual(url.path, "/c/f/forum/hotThreadList")
        XCTAssertEqual(url.query, "cmd=309661")
    }

    func testRequestCarriesTabIdentifierAndCodeOnTheirWireFields() throws {
        let request = TiebaHotRequestFactory.request(
            account: nil,
            tabCode: "hot_all",
            requestBuilder: requestBuilder
        )

        let outer = try Self.wireFields(try request.serializedData())
        XCTAssertEqual(outer.map(\.number), [1], "请求只带一个 data 字段")

        let dataFields = try Self.wireFields(outer[0].payload)
        XCTAssertEqual(
            dataFields.map(\.number).sorted(),
            [1, 2, 3],
            "data 里必须是 common(1)、tab_id(2)、tab_code(3)"
        )
        let tabID = try XCTUnwrap(dataFields.first { $0.number == 2 })
        XCTAssertEqual(String(decoding: tabID.payload, as: UTF8.self), "1")
        let tabCode = try XCTUnwrap(dataFields.first { $0.number == 3 })
        XCTAssertEqual(String(decoding: tabCode.payload, as: UTF8.self), "hot_all")
    }

    func testRequestWithoutTabCodeAsksForTheAllTab() throws {
        let request = TiebaHotRequestFactory.request(
            account: nil,
            tabCode: "",
            requestBuilder: requestBuilder
        )

        let outer = try Self.wireFields(try request.serializedData())
        let dataFields = try Self.wireFields(outer[0].payload)

        XCTAssertEqual(
            dataFields.map(\.number).sorted(),
            [1, 2, 3],
            "空 tab_code 会被改写成 all：服务端对空代码只回一条残缺列表"
        )
        let tabCode = try XCTUnwrap(dataFields.first { $0.number == 3 })
        XCTAssertEqual(
            String(decoding: tabCode.payload, as: UTF8.self),
            HotTab.allCode
        )
    }

    func testHandCraftedHotThreadWireBytesDecodeAndMapToDomain() throws {
        let wireData = try XCTUnwrap(Self.data(hex: Self.hotThreadWireHex))
        let decoded = try Tieba_HotThreadList_HotThreadListResponse(serializedBytes: wireData)

        XCTAssertEqual(decoded.error.errorCode, 0)
        XCTAssertEqual(decoded.data.threadInfo.count, 1)
        XCTAssertEqual(decoded.data.hotThreadTabInfo.count, 1)
        XCTAssertEqual(decoded.data.hotThreadTabInfo[0].tabName, "综合")
        XCTAssertEqual(decoded.data.hotThreadTabInfo[0].tabCode, "hot_all")

        let tabs = HotFeedMapper.makeFeed(from: decoded.data).tabs
        XCTAssertEqual(
            tabs,
            [HotTab.all, HotTab(code: "hot_all", name: "综合")],
            "全部恒排第一，服务端的分类标签紧随其后"
        )
    }

    // MARK: - Hand-crafted wire bytes, one assertion per test

    func testHotWireDecodesThreadIDFromField1() throws {
        assertField(try decodedWireThreadInfo().id, 9001)
    }

    func testHotWireDecodesThreadTitleFromField3() throws {
        assertField(try decodedWireThreadInfo().title, "线格式热点帖")
    }

    func testHotWireDecodesThreadReplyNumFromField4() throws {
        assertField(try decodedWireThreadInfo().replyNum, 7)
    }

    func testHotWireDecodesThreadForumIDFromField27() throws {
        assertField(try decodedWireThreadInfo().forumID, 555)
    }

    func testHotWireDecodesThreadForumNameFromField28() throws {
        assertField(try decodedWireThreadInfo().forumName, "热点吧")
    }

    func testHotWireDecodesThreadAuthorIDFromField56() throws {
        assertField(try decodedWireThreadInfo().authorID, 77)
    }

    func testHotThreadMapsIDFromWireBytes() throws {
        assertField(try mappedWireThread().id, 9001)
    }

    func testHotThreadMapsTitleFromWireBytes() throws {
        assertField(try mappedWireThread().title, "线格式热点帖")
    }

    func testHotThreadMapsReplyCountFromWireBytes() throws {
        assertField(try mappedWireThread().replyCount, 7)
    }

    func testHotThreadMapsForumIDFromWireBytes() throws {
        assertField(try mappedWireThread().forumID, 555)
    }

    func testHotThreadMapsForumNameFromWireBytes() throws {
        assertField(try mappedWireThread().forumName, "热点吧")
    }

    func testHotThreadMapsAuthorIDFromWireBytes() throws {
        assertField(try mappedWireThread().author.id, 77)
    }

    func testTabsWithoutCodeOrNameAreDropped() {
        var responseData = Tieba_HotThreadList_HotThreadListResponseData()

        var codeOnly = Tieba_HotThreadList_FrsTabInfo()
        codeOnly.tabCode = "hot_all"
        var nameOnly = Tieba_HotThreadList_FrsTabInfo()
        nameOnly.tabName = "综合"
        var usable = Tieba_HotThreadList_FrsTabInfo()
        usable.tabCode = "hot_pic"
        usable.tabName = "图片"
        responseData.hotThreadTabInfo = [codeOnly, nameOnly, usable]

        let feed = HotFeedMapper.makeFeed(from: responseData)

        XCTAssertEqual(
            feed.tabs,
            [HotTab.all, HotTab(code: "hot_pic", name: "图片")],
            "被丢弃的两个坏标签不出现，本地补的全部仍在最前"
        )
    }

    func testServerReportedAllTabIsNotDuplicated() {
        var responseData = Tieba_HotThreadList_HotThreadListResponseData()

        var serviceAll = Tieba_HotThreadList_FrsTabInfo()
        serviceAll.tabCode = HotTab.allCode
        serviceAll.tabName = "综合"
        var other = Tieba_HotThreadList_FrsTabInfo()
        other.tabCode = "hot_pic"
        other.tabName = "图片"
        responseData.hotThreadTabInfo = [serviceAll, other]

        let feed = HotFeedMapper.makeFeed(from: responseData)

        XCTAssertEqual(
            feed.tabs,
            [HotTab(code: HotTab.allCode, name: "综合"), HotTab(code: "hot_pic", name: "图片")],
            "服务端已给 all 时不能再补一个，否则 tab 识别 id 重复"
        )
    }

    func testRepeatedThreadsAreDedupedByID() {
        var responseData = Tieba_HotThreadList_HotThreadListResponseData()

        var first = Tieba_ThreadInfo()
        first.id = 9001
        first.title = "线格式热点帖"
        var duplicate = Tieba_ThreadInfo()
        duplicate.id = 9001
        duplicate.title = "线格式热点帖"
        var other = Tieba_ThreadInfo()
        other.id = 9002
        other.title = "另一条热点"
        responseData.threadInfo = [first, duplicate, other]

        let feed = HotFeedMapper.makeFeed(from: responseData)

        XCTAssertEqual(feed.threads.map(\.id), [9001, 9002])
    }

    func testTopicWireBytesDecodeIDNameAndDiscussCount() throws {
        // topic_id(1) 28366254, topic_name(2) 假期打分大会, discuss_num(4) 1641000
        let wire = try XCTUnwrap(Self.data(hex: "08aeabc30d1212e58187e69c9fe68993e58886e5a4a7e4bc9a20a89464"))

        let topic = try Tieba_HotThreadList_RecomTopicList(serializedBytes: wire)

        XCTAssertEqual(topic.topicID, 28_366_254)
        XCTAssertEqual(topic.topicName, "假期打分大会")
        XCTAssertEqual(topic.discussNum, 1_641_000)
    }

    func testTopicListMapsInServiceOrderAndSkipsIncompleteRows() {
        var responseData = Tieba_HotThreadList_HotThreadListResponseData()

        var usable = Tieba_HotThreadList_RecomTopicList()
        usable.topicID = 28_366_254
        usable.topicName = "假期打分大会"
        usable.discussNum = 1_641_000
        var withoutName = Tieba_HotThreadList_RecomTopicList()
        withoutName.topicID = 28_366_253
        var withoutID = Tieba_HotThreadList_RecomTopicList()
        withoutID.topicName = "没有 id 的话题"
        responseData.topicList = [usable, withoutName, withoutID]

        let feed = HotFeedMapper.makeFeed(from: responseData)

        XCTAssertEqual(
            feed.topics,
            [HotTopic(id: 28_366_254, name: "假期打分大会", discussCount: 1_641_000)],
            "无 id 或无名字的话题行直接丢掉，其余保持服务端顺序"
        )
    }

    func testTopicDiscussCountUsesWanPastTenThousand() {
        func text(_ count: Int) -> String {
            HotTopic(id: 1, name: "话题", discussCount: count).discussCountText
        }

        XCTAssertEqual(text(0), "0")
        XCTAssertEqual(text(9_999), "9999")
        XCTAssertEqual(text(10_000), "1.0万")
        XCTAssertEqual(text(1_641_000), "164.1万")
    }

    func testMergedAllListingUnionsCategoriesAndOrdersByHeat() {
        let merged = HotFeedMerge.threads(from: [
            hotFeed(threads: [hotThread(id: 1, hot: 100), hotThread(id: 2, hot: 300)]),
            hotFeed(threads: [hotThread(id: 3, hot: 200)])
        ])

        XCTAssertEqual(merged.map(\.id), [2, 3, 1])
    }

    func testMergedAllListingKeepsTheHottestCopyOfADuplicate() {
        let merged = HotFeedMerge.threads(from: [
            hotFeed(threads: [hotThread(id: 7, hot: 10)]),
            hotFeed(threads: [hotThread(id: 7, hot: 90)])
        ])

        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].hotScore, 90)
    }

    func testMergedAllListingBreaksEqualHeatByReplyCount() {
        let merged = HotFeedMerge.threads(from: [
            hotFeed(threads: [
                hotThread(id: 4, hot: 0, replies: 3),
                hotThread(id: 5, hot: 0, replies: 9)
            ])
        ])

        XCTAssertEqual(merged.map(\.id), [5, 4])
    }

    func testMergedAllListingOfNoFeedsIsEmpty() {
        XCTAssertTrue(HotFeedMerge.threads(from: []).isEmpty)
    }

    private func hotFeed(threads: [ThreadSummary]) -> HotFeed {
        HotFeed(threads: threads)
    }

    private func hotThread(id: Int64, hot: Int64, replies: Int = 0) -> ThreadSummary {
        ThreadSummary(
            id: id,
            title: "帖子\(id)",
            author: UserSummary(id: 1, name: "author", displayName: "作者", portrait: ""),
            replyCount: replies,
            viewCount: 0,
            blocks: [],
            hotValue: hot == 0 ? nil : hot
        )
    }

    func testSegmentsExposeStableTitlesAndHints() {
        XCTAssertEqual(HomeFeedSegment.allCases.map(\.title), ["推荐", "热点"])
        XCTAssertEqual(HomeFeedSegment.recommended.accessibilityHint, "显示个性化推荐的帖子")
        XCTAssertEqual(HomeFeedSegment.hot.accessibilityHint, "显示贴吧热点帖子")
        XCTAssertEqual(
            Set(HomeFeedSegment.allCases.map(\.id)).count,
            HomeFeedSegment.allCases.count
        )
    }
}
