import UIKit
import XCTest
@testable import TiebaPure

final class EmoticonResourceTests: XCTestCase {
    func testClassicEmoticonResourceIsBundledAndReadable() throws {
        let url = try XCTUnwrap(TiebaEmoticon.imageURL(for: "滑稽"))
        let image = UIImage(contentsOfFile: url.path)

        XCTAssertNotNil(image)
    }

    func testAllBundledEmoticonsResolveByNameAndResource() throws {
        let expectedNamesByImageName = [
            "image_emoticon1": "呵呵",
            "image_emoticon2": "哈哈",
            "image_emoticon3": "吐舌",
            "image_emoticon4": "啊",
            "image_emoticon5": "酷",
            "image_emoticon6": "怒",
            "image_emoticon7": "开心",
            "image_emoticon8": "汗",
            "image_emoticon9": "泪",
            "image_emoticon10": "黑线",
            "image_emoticon11": "鄙视",
            "image_emoticon12": "不高兴",
            "image_emoticon13": "真棒",
            "image_emoticon14": "钱",
            "image_emoticon15": "疑问",
            "image_emoticon16": "阴险",
            "image_emoticon17": "吐",
            "image_emoticon18": "咦",
            "image_emoticon19": "委屈",
            "image_emoticon20": "花心",
            "image_emoticon21": "呼~",
            "image_emoticon22": "笑眼",
            "image_emoticon23": "冷",
            "image_emoticon24": "太开心",
            "image_emoticon25": "滑稽",
            "image_emoticon26": "勉强",
            "image_emoticon27": "狂汗",
            "image_emoticon28": "乖",
            "image_emoticon29": "睡觉",
            "image_emoticon30": "惊哭",
            "image_emoticon31": "生气",
            "image_emoticon32": "惊讶",
            "image_emoticon33": "喷",
            "image_emoticon34": "爱心",
            "image_emoticon35": "心碎",
            "image_emoticon36": "玫瑰",
            "image_emoticon37": "礼物",
            "image_emoticon38": "彩虹",
            "image_emoticon39": "星星月亮",
            "image_emoticon40": "太阳",
            "image_emoticon41": "钱币",
            "image_emoticon42": "灯泡",
            "image_emoticon43": "茶杯",
            "image_emoticon44": "蛋糕",
            "image_emoticon45": "音乐",
            "image_emoticon46": "haha",
            "image_emoticon47": "胜利",
            "image_emoticon48": "大拇指",
            "image_emoticon49": "弱",
            "image_emoticon50": "OK",
            "image_emoticon89": "噗"
        ]

        XCTAssertEqual(expectedNamesByImageName.count, 51)
        for (imageName, name) in expectedNamesByImageName {
            XCTAssertEqual(TiebaEmoticon.imageName(for: name), imageName, name)
            let url = try XCTUnwrap(TiebaEmoticon.imageURL(for: name), name)
            XCTAssertNotNil(UIImage(contentsOfFile: url.path), name)
        }
    }

    func testBracketedLegacyAliasXiaoGuaiRendersInline() {
        let blocks = TiebaEmoticon.blocks(from: "摸摸[小乖]继续")

        XCTAssertEqual(blocks, [
            .text("摸摸"),
            .emoticon(code: "小乖"),
            .text("继续")
        ])
        XCTAssertEqual(TiebaEmoticon.imageName(for: "小乖"), "image_emoticon28")
        XCTAssertEqual(TiebaEmoticon.imageName(for: "[小乖]"), "image_emoticon28")
    }

    func testExtendedEmoticonsResolveByImageIDAndKnownOriginalNames() throws {
        let expectedNamesByImageName = [
            "image_emoticon77": "沙发",
            "image_emoticon78": "手纸",
            "image_emoticon79": "香蕉",
            "image_emoticon80": "便便",
            "image_emoticon81": "药丸",
            "image_emoticon82": "红领巾",
            "image_emoticon83": "蜡烛",
            "image_emoticon84": "三道杠"
        ]

        XCTAssertEqual(TiebaEmoticon.imageName(for: "image_emoticon61"), "image_emoticon61")
        XCTAssertEqual(TiebaEmoticon.imageName(for: "image_emoticon125"), "image_emoticon125")
        XCTAssertNotNil(try XCTUnwrap(TiebaEmoticon.imageURL(for: "image_emoticon61")).path)
        XCTAssertNotNil(try XCTUnwrap(TiebaEmoticon.imageURL(for: "image_emoticon125")).path)

        for (imageName, name) in expectedNamesByImageName {
            XCTAssertEqual(TiebaEmoticon.imageName(for: name), imageName, name)
            let url = try XCTUnwrap(TiebaEmoticon.imageURL(for: name), name)
            XCTAssertNotNil(UIImage(contentsOfFile: url.path), name)
        }
    }
}
