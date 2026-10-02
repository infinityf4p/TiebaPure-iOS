import XCTest
@testable import TiebaPure

/// The topic page's JSON is hand-shaped here from the live service's real
/// response: strings and numbers mix for the same field (`discuss_num` arrives
/// as both), `abstract` is a plain string, and the paging cursor is the row's
/// feed id.
final class TopicThreadsTests: XCTestCase {
    private static let fixture = """
    {
      "no": 0,
      "error": "success",
      "data": {
        "has_more": true,
        "topic_info": {
          "topic_id": "28366254",
          "topic_name": "假期打分大会,奥特曼客串锐评",
          "topic_desc": "国庆奥特曼客串回打分大会，来给剧情打个分。",
          "discuss_num": "2294400",
          "browse_num": 284537,
          "topic_image": "https://example.com/topic.jpg"
        },
        "relate_thread": {
          "thread_list": [
            {
              "feed_id": 11068502310,
              "thread_info": {
                "tid": 11068502310,
                "title": "我发所有拍摄经手过赛罗戏份的导演，你来给他的赛罗打分",
                "forum_id": 7046,
                "forum_name": "奥特曼",
                "reply_num": 210,
                "agree_num": 1067,
                "first_post_id": 153987296729,
                "create_time": 1790825388,
                "last_time_int": 1790925058,
                "abstract": "摘要文本",
                "author": {
                  "id": 6682378323,
                  "name": "sky",
                  "name_show": "sky遥远彼之地",
                  "portrait": "tb.1.95276bfd"
                },
                "media": [
                  {
                    "type": "pic",
                    "width": "560",
                    "height": "746",
                    "small_pic": "https://example.com/small.jpg",
                    "big_pic": "https://example.com/big.jpg"
                  }
                ]
              }
            },
            {
              "feed_id": 11068684304,
              "thread_info": {
                "tid": 11068684304,
                "title": "第二个帖子"
              }
            }
          ]
        }
      }
    }
    """

    private func decoded() throws -> TopicDetailResponseDTO {
        try JSONDecoder().decode(TopicDetailResponseDTO.self, from: Data(Self.fixture.utf8))
    }

    private func data() throws -> TopicDetailResponseDTO.DataDTO {
        try XCTUnwrap(try decoded().data)
    }

    func testResponseDecodesSuccessCodeAndPagingFlag() throws {
        let response = try decoded()

        XCTAssertEqual(response.code, 0)
        XCTAssertEqual(response.message, "success")
        XCTAssertTrue(try data().hasMore)
    }

    func testTopicInfoDecodesCountsSentAsStringsAndNumbers() throws {
        let info = try XCTUnwrap(TopicMapper.info(from: try data().topicInfo))

        XCTAssertEqual(info.id, 28_366_254)
        XCTAssertEqual(info.name, "假期打分大会,奥特曼客串锐评")
        XCTAssertEqual(info.summary, "国庆奥特曼客串回打分大会，来给剧情打个分。")
        XCTAssertEqual(info.discussCount, 2_294_400, "讨论数是字符串也要解出来")
        XCTAssertEqual(info.browseCount, 284_537)
        XCTAssertEqual(info.imageURL?.absoluteString, "https://example.com/topic.jpg")
    }

    func testTopicCountsAreRoundedToWanPastTenThousand() throws {
        let info = try XCTUnwrap(TopicMapper.info(from: try data().topicInfo))

        XCTAssertEqual(info.discussCountText, "229.4万")
        XCTAssertEqual(info.browseCountText, "28.5万")
    }

    func testThreadsMapToRowsWithTextSummaryAndImage() throws {
        let threads = TopicMapper.threads(from: try data())

        XCTAssertEqual(threads.count, 2)
        let first = try XCTUnwrap(threads.first)
        XCTAssertEqual(first.id, 11_068_502_310)
        XCTAssertEqual(first.title, "我发所有拍摄经手过赛罗戏份的导演，你来给他的赛罗打分")
        XCTAssertEqual(first.forumID, 7046)
        XCTAssertEqual(first.forumName, "奥特曼")
        XCTAssertEqual(first.replyCount, 210)
        XCTAssertEqual(first.likeCount, 1067)
        XCTAssertEqual(first.author.displayName, "sky遥远彼之地")
        XCTAssertEqual(first.firstPostID, 153_987_296_729)
        XCTAssertNotNil(first.createdAt)
        XCTAssertEqual(first.textPreview, "摘要文本")
        XCTAssertEqual(first.mediaBlocks.count, 1)
    }

    func testThreadWithoutForumOrAuthorStillMaps() throws {
        let threads = TopicMapper.threads(from: try data())

        XCTAssertEqual(threads.count, 2)
        let second = try XCTUnwrap(threads.last)
        XCTAssertEqual(second.id, 11_068_684_304)
        XCTAssertNil(second.forumID, "服务端没给吧 id 时不要凭空造一个")
        XCTAssertEqual(second.author.displayNameResolved, "未知用户")
        XCTAssertTrue(second.mediaBlocks.isEmpty)
    }

    func testCursorIsTheLastFeedIDForTheNextPage() throws {
        XCTAssertEqual(TopicMapper.cursor(from: try data()), "11068684304")
    }

    func testEmptyThreadListStillProducesACursorlessPage() throws {
        let json = #"{"no":0,"error":"success","data":{"has_more":false}}"#
        let response = try JSONDecoder().decode(TopicDetailResponseDTO.self, from: Data(json.utf8))
        let data = try XCTUnwrap(response.data)

        XCTAssertTrue(TopicMapper.threads(from: data).isEmpty)
        XCTAssertNil(TopicMapper.cursor(from: data))
        XCTAssertNil(TopicMapper.info(from: data.topicInfo))
        XCTAssertFalse(data.hasMore)
    }
}
