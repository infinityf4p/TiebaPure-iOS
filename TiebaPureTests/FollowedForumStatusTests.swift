import XCTest
@testable import TiebaPure

final class FollowedForumStatusTests: XCTestCase {
    func testGuideEndpointTargetsTheWebGuideHost() {
        let url = TiebaEndpoint.followedForumGuide.url

        XCTAssertEqual(url.host, "tieba.baidu.com")
        XCTAssertEqual(url.path, "/c/f/forum/forumGuide")
        XCTAssertNil(url.query)
    }

    func testGuideFieldsCarryGuideParametersWithoutCredentials() throws {
        let fields = try TiebaSocialRequestFactory.followedForumGuideFields(
            tbs: "  tbs-value  ",
            page: 2
        )

        XCTAssertEqual(fields["tbs"], "tbs-value")
        XCTAssertEqual(fields["sort_type"], "3")
        XCTAssertEqual(fields["call_from"], "3")
        XCTAssertEqual(fields["page_no"], "2")
        XCTAssertEqual(fields["res_num"], "\(FollowedForumGuidePolicy.pageSize)")
        XCTAssertNil(fields["BDUSS"], "这个网页接口靠 Cookie 传凭据，表单里不应再出现 BDUSS")
        XCTAssertNil(fields["sign"])
    }

    func testGuideFieldsClampPageAndPageSize() throws {
        let fields = try TiebaSocialRequestFactory.followedForumGuideFields(
            tbs: "tbs",
            page: 0,
            pageSize: 0
        )

        XCTAssertEqual(fields["page_no"], "1")
        XCTAssertEqual(fields["res_num"], "1")
    }

    func testGuideFieldsRejectEmptyTBS() {
        XCTAssertThrowsError(
            try TiebaSocialRequestFactory.followedForumGuideFields(tbs: "   ", page: 1)
        ) { error in
            XCTAssertEqual(error as? TiebaMutationError, .missingTBS)
        }
    }

    func testGuideResponseDecodesLevelAndCheckInForEveryForum() throws {
        // The service answers FLAT: like_forum sits beside error_code, with no
        // data wrapper, and unrelated display keys ride along. Decoding a
        // nested data read nil on every success and reported the whole payload
        // as "empty data".
        let json = """
        {
          "error_code": 0,
          "error_msg": "",
          "ctime": "1",
          "block_pop_info": null,
          "forum_create_info": null,
          "like_forum": [
            { "forum_id": "4242", "forum_name": "合成吧", "level_id": "12", "is_sign": true },
            { "forum_id": 4343, "forum_name": "另一个吧", "level_id": 3, "is_sign": 0 }
          ],
          "like_forum_has_more": "0"
        }
        """

        let response = try JSONDecoder().decode(FollowedForumGuideResponseDTO.self, from: Data(json.utf8))

        XCTAssertEqual(response.errorCode, 0)
        XCTAssertEqual(response.forums.count, 2)
        XCTAssertEqual(response.forums[0].forumID, 4242)
        XCTAssertEqual(response.forums[0].level, 12, "字符串等级也要解出来")
        XCTAssertTrue(response.forums[0].isSignedToday, "布尔签到态也要解出来")
        XCTAssertEqual(response.forums[1].forumID, 4343)
        XCTAssertEqual(response.forums[1].level, 3)
        XCTAssertFalse(response.forums[1].isSignedToday, "数字签到态也要解出来")
        XCTAssertEqual(response.hasMore, false)
    }

    func testGuideResponseTreatsMissingForumListAsEmpty() throws {
        let json = """
        { "error_code": 0, "error_msg": "", "like_forum_has_more": 1 }
        """

        let response = try JSONDecoder().decode(FollowedForumGuideResponseDTO.self, from: Data(json.utf8))

        XCTAssertEqual(response.forums.isEmpty, true)
        XCTAssertEqual(response.hasMore, true)
    }

    func testGuideResponseSurfacesServiceErrorCode() throws {
        let json = """
        { "error_code": 1989, "error_msg": "参数错误" }
        """

        let response = try JSONDecoder().decode(FollowedForumGuideResponseDTO.self, from: Data(json.utf8))

        XCTAssertEqual(response.errorCode, 1989)
        XCTAssertEqual(response.errorMessage, "参数错误")
        XCTAssertEqual(response.forums.isEmpty, true)
    }

    func testTileLabelReadsLevelAndCheckInAsOneSentence() {
        XCTAssertEqual(
            ForumTileAccessibilityPolicy.label(
                title: "壁纸吧",
                level: 12,
                isSignedToday: true,
                isManaging: false
            ),
            "进入壁纸吧，等级12，今日已签到"
        )
        XCTAssertEqual(
            ForumTileAccessibilityPolicy.label(
                title: "壁纸吧",
                level: 0,
                isSignedToday: false,
                isManaging: false
            ),
            "进入壁纸吧",
            "没有等级和签到信息时不要念出占位文案"
        )
        XCTAssertEqual(
            ForumTileAccessibilityPolicy.label(
                title: "壁纸吧",
                level: 12,
                isSignedToday: true,
                isManaging: true
            ),
            "壁纸吧",
            "管理模式下的磁贴只念名字，避免和删除按钮冲突"
        )
    }
}
