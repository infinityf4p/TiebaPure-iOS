import XCTest
@testable import TiebaPure

final class ContentFilterTests: XCTestCase {
    func testFilterDropsLiveThreadButKeepsVideoThread() {
        var live = Tieba_ThreadInfo()
        live.id = 1
        live.alaInfo = Tieba_AlaLiveInfo()

        var video = Tieba_ThreadInfo()
        video.id = 2
        var videoInfo = Tieba_VideoInfo()
        videoInfo.videoURL = "https://video.example/a.mp4"
        video.videoInfo = videoInfo

        XCTAssertFalse(TiebaContentFilter.shouldKeep(thread: live))
        XCTAssertTrue(TiebaContentFilter.shouldKeep(thread: video))
    }

    func testFilterDropsVoiceContent() {
        var voice = Tieba_PbContent()
        voice.type = 10
        voice.voiceMd5 = "voice"

        XCTAssertFalse(TiebaContentFilter.shouldKeep(content: voice))
    }

    func testFilterDropsAdAndFoldedPosts() {
        var ad = Tieba_Post()
        ad.advertisement = Tieba_Advertisement()

        var folded = Tieba_Post()
        folded.isFold = 1

        XCTAssertFalse(TiebaContentFilter.shouldKeep(post: ad))
        XCTAssertFalse(TiebaContentFilter.shouldKeep(post: folded))
    }
}
