import XCTest
@testable import TiebaPure

final class ContentMappingTests: XCTestCase {
    func testContentBlocksAreEquatable() {
        let a = ContentBlock.text("hello")
        let b = ContentBlock.text("hello")

        XCTAssertEqual(a, b)
    }

    func testUserPortraitBuildsBaiduAvatarURL() {
        let user = UserSummary(
            id: 42,
            name: "raw",
            displayName: "Readable",
            portrait: "tb.1.demo"
        )

        XCTAssertEqual(user.portraitURL?.absoluteString, "https://himg.bdimg.com/sys/portrait/item/tb.1.demo")
    }

    func testUserPortraitRejectsLegacyInsecureTiebaAvatarURL() {
        let user = UserSummary(
            id: 42,
            name: "raw",
            displayName: "Readable",
            portrait: "http://tb.himg.baidu.com/sys/portrait/item/tb.1.demo"
        )

        XCTAssertNil(user.portraitURL)
    }

    func testThreadSummaryDerivesTextPreviewAndMediaBlocks() {
        let thread = ThreadSummary(
            id: 7,
            title: "title",
            author: UserSummary(id: 1, name: "author", displayName: "Author", portrait: ""),
            replyCount: 3,
            viewCount: 9,
            blocks: [
                .text("hello"),
                .image(ImageContent(
                    thumbnailURL: URL(string: "https://example.com/thumb.jpg"),
                    originalURL: nil,
                    width: 800,
                    height: 600,
                    showOriginalButton: false
                ))
            ]
        )

        XCTAssertEqual(thread.textPreview, "hello")
        XCTAssertEqual(thread.mediaBlocks.count, 1)
    }

    func testSplitsClassicTiebaEmoticonsOutOfText() {
        let blocks = TiebaEmoticon.blocks(from: "hello#(滑稽)world")

        XCTAssertEqual(blocks, [
            .text("hello"),
            .emoticon(code: "滑稽"),
            .text("world")
        ])
        XCTAssertEqual(blocks.compactMap(\.plainText).joined(), "hello[滑稽]world")
        XCTAssertEqual(TiebaEmoticon.imageName(for: "#(滑稽)"), "image_emoticon25")
    }

    func testMapsProtoEmoticonContent() {
        var emoticon = Tieba_PbContent()
        emoticon.type = 2
        emoticon.c = "哈哈"

        let blocks = PostMapper.blocks(from: [emoticon])

        XCTAssertEqual(blocks, [.emoticon(code: "哈哈")])
        XCTAssertEqual(TiebaEmoticon.imageName(for: "哈哈"), "image_emoticon2")
    }

    func testProtoEmoticonFallsBackToImageIDWhenNameIsUnknown() {
        var emoticon = Tieba_PbContent()
        emoticon.type = 2
        emoticon.text = "image_emoticon25"
        emoticon.c = "接口新别名"

        let blocks = PostMapper.blocks(from: [emoticon])

        XCTAssertEqual(blocks, [.emoticon(code: "image_emoticon25")])
    }

    func testSplitsAlternateTiebaEmoticonTokens() {
        let blocks = TiebaEmoticon.blocks(from: "a(#哈哈)b[大笑]c[黑头]d[高兴]e[未知]")

        XCTAssertEqual(blocks, [
            .text("a"),
            .emoticon(code: "哈哈"),
            .text("b"),
            .emoticon(code: "大笑"),
            .text("c"),
            .emoticon(code: "黑头"),
            .text("d"),
            .emoticon(code: "高兴"),
            .text("e"),
            .text("[未知]")
        ])
        XCTAssertEqual(TiebaEmoticon.imageName(for: "大笑"), "image_emoticon2")
        XCTAssertEqual(TiebaEmoticon.imageName(for: "黑头"), "image_emoticon10")
        XCTAssertEqual(TiebaEmoticon.imageName(for: "高兴"), "image_emoticon7")
    }

    func testMapsDirectEmoticonImageIDs() {
        XCTAssertEqual(TiebaEmoticon.imageName(for: "image_emoticon25"), "image_emoticon25")
        XCTAssertEqual(TiebaEmoticon.displayText(for: "image_emoticon25"), "[滑稽]")
    }

    func testMapsVideoContentAndIgnoresVoice() {
        var video = Tieba_PbContent()
        video.type = 5
        video.link = "https://video.example/a.mp4"
        video.src = "https://video.example/cover.jpg"
        video.bsize = "1280,720"

        var voice = Tieba_PbContent()
        voice.type = 10
        voice.voiceMd5 = "voice"

        let blocks = PostMapper.blocks(from: [video, voice])

        XCTAssertEqual(blocks.count, 1)
        guard case let .video(value) = blocks[0] else {
            return XCTFail("expected video block")
        }
        XCTAssertEqual(value.videoURL?.absoluteString, "https://video.example/a.mp4")
        XCTAssertEqual(value.coverURL?.absoluteString, "https://video.example/cover.jpg")
        XCTAssertEqual(value.width, 1280)
        XCTAssertEqual(value.height, 720)
    }

    func testMapsImageContentSizeAndOriginalURL() {
        var image = Tieba_PbContent()
        image.type = 3
        image.cdnSrc = "https://image.example/thumb.jpg"
        image.originSrc = "https://image.example/original.jpg"
        image.bsize = "800,600"
        image.showOriginalBtn = 1

        let blocks = PostMapper.blocks(from: [image])

        guard case let .image(value) = blocks.first else {
            return XCTFail("expected image block")
        }
        XCTAssertEqual(value.thumbnailURL?.absoluteString, "https://image.example/thumb.jpg")
        XCTAssertEqual(value.originalURL?.absoluteString, "https://image.example/original.jpg")
        XCTAssertEqual(value.width, 800)
        XCTAssertEqual(value.height, 600)
        XCTAssertTrue(value.showOriginalButton)
    }

    func testMapsThreadSummaryWithAuthorAndVideoInfo() {
        var author = Tieba_User()
        author.id = 42
        author.name = "raw"
        author.nameShow = "Readable"
        author.portrait = "tb.1.demo"
        author.levelID = 14
        author.levelName = "地狱少女"
        author.agreeNum = 999
        author.levelInfluence = "999"
        author.ipAddress = "河南"

        var videoInfo = Tieba_VideoInfo()
        videoInfo.videoURL = "https://video.example/a.mp4"
        videoInfo.thumbnailURL = "https://video.example/cover.jpg"
        videoInfo.videoWidth = 1280
        videoInfo.videoHeight = 720

        var thread = Tieba_ThreadInfo()
        thread.id = 7
        thread.title = "Title"
        thread.forumID = 9
        thread.forumName = "ios"
        var threadForum = Tieba_SimpleForum()
        threadForum.id = 9
        threadForum.name = "ios"
        threadForum.avatar = "https://example.com/forum.jpg"
        thread.forumInfo = threadForum
        thread.author = author
        thread.replyNum = 10
        thread.viewNum = 20
        thread.agreeNum = 31
        thread.isTop = 1
        thread.videoInfo = videoInfo

        let summary = ThreadMapper.fromThreadInfo(thread, usersByID: [:])

        XCTAssertEqual(summary.id, 7)
        XCTAssertEqual(summary.forumID, 9)
        XCTAssertEqual(summary.author.displayName, "Readable")
        XCTAssertEqual(summary.author.level, 14)
        XCTAssertEqual(summary.author.levelName, "地狱少女")
        XCTAssertEqual(summary.author.ipAddress, "河南")
        XCTAssertEqual(summary.forumAvatarURL?.absoluteString, "https://example.com/forum.jpg")
        XCTAssertEqual(summary.likeCount, 31)
        XCTAssertTrue(summary.isTop)
        XCTAssertTrue(summary.hasVideo)
    }

    func testThreadSummaryMapsPersonalizedMediaListURLs() {
        var media = Tieba_Media()
        media.bigPic = "https://tiebapic.baidu.com/forum/pic/item/thumb.jpg"
        media.srcPic = "//tiebapic.baidu.com/forum/pic/item/small.jpg"
        media.originPic = "https://tiebapic.baidu.com/forum/pic/item/original.jpg"
        media.width = 1_600
        media.height = 900
        media.showOriginalBtn = 1

        var emptyContentImage = Tieba_PbContent()
        emptyContentImage.type = 3
        emptyContentImage.bsize = "1600,900"

        var thread = Tieba_ThreadInfo()
        thread.id = 77
        thread.firstPostContent = [emptyContentImage]
        thread.media = [media]

        let summary = ThreadMapper.fromThreadInfo(thread, usersByID: [:])

        XCTAssertEqual(summary.mediaBlocks.count, 1)
        guard case let .image(image) = summary.mediaBlocks[0] else {
            return XCTFail("expected image")
        }
        XCTAssertEqual(image.thumbnailURL?.absoluteString, "https://tiebapic.baidu.com/forum/pic/item/thumb.jpg")
        XCTAssertEqual(image.originalURL?.absoluteString, "https://tiebapic.baidu.com/forum/pic/item/original.jpg")
        XCTAssertEqual(image.width, 1_600)
        XCTAssertEqual(image.height, 900)
        XCTAssertTrue(image.showOriginalButton)
    }

    func testThreadSummaryDoesNotDuplicateSameVideoFromContentAndVideoInfo() {
        var contentVideo = Tieba_PbContent()
        contentVideo.type = 5
        contentVideo.link = "https://video.example/a.mp4"
        contentVideo.src = "https://video.example/cover.jpg"
        contentVideo.bsize = "1280,720"

        var videoInfo = Tieba_VideoInfo()
        videoInfo.videoURL = "https://video.example/a.mp4"
        videoInfo.thumbnailURL = "https://video.example/cover.jpg"
        videoInfo.videoWidth = 1280
        videoInfo.videoHeight = 720

        var thread = Tieba_ThreadInfo()
        thread.id = 7
        thread.title = "Video thread"
        thread.firstPostContent = [contentVideo]
        thread.videoInfo = videoInfo

        let summary = ThreadMapper.fromThreadInfo(thread, usersByID: [:])
        let videos = summary.mediaBlocks.compactMap { block -> VideoContent? in
            if case let .video(video) = block {
                return video
            }
            return nil
        }

        XCTAssertEqual(videos.count, 1)
        XCTAssertEqual(videos.first?.videoURL?.absoluteString, "https://video.example/a.mp4")
        XCTAssertTrue(summary.hasVideo)
    }

    func testThreadSummaryMergesVideoInfoPlaybackURLIntoContentVideo() {
        var contentVideo = Tieba_PbContent()
        contentVideo.type = 5
        contentVideo.src = "https://video.example/content-cover.jpg"
        contentVideo.bsize = "1280,720"

        var videoInfo = Tieba_VideoInfo()
        videoInfo.videoURL = "https://video.example/direct.mp4"
        videoInfo.thumbnailURL = "https://video.example/info-cover.jpg"
        videoInfo.videoWidth = 1280
        videoInfo.videoHeight = 720

        var thread = Tieba_ThreadInfo()
        thread.id = 7
        thread.title = "Video thread"
        thread.firstPostContent = [contentVideo]
        thread.videoInfo = videoInfo

        let summary = ThreadMapper.fromThreadInfo(thread, usersByID: [:])
        let videos = summary.mediaBlocks.compactMap { block -> VideoContent? in
            if case let .video(video) = block {
                return video
            }
            return nil
        }

        XCTAssertEqual(videos.count, 1)
        XCTAssertEqual(videos.first?.videoURL?.absoluteString, "https://video.example/direct.mp4")
        XCTAssertEqual(videos.first?.coverURL?.absoluteString, "https://video.example/content-cover.jpg")
    }

    func testThreadPageKeepsFirstFloorPostAsMainPost() {
        var author = Tieba_User()
        author.id = 42
        author.name = "raw"
        author.nameShow = "楼主"

        var forum = Tieba_SimpleForum()
        forum.id = 9
        forum.name = "ios"

        var thread = Tieba_ThreadInfo()
        thread.id = 123
        thread.title = "主题"
        thread.author = author

        var mainContent = Tieba_PbContent()
        mainContent.type = 0
        mainContent.text = "主贴"

        var firstFloor = Tieba_Post()
        firstFloor.id = 11
        firstFloor.tid = 123
        firstFloor.floor = 1
        firstFloor.author = author
        firstFloor.content = [mainContent]

        var reply = Tieba_Post()
        reply.id = 12
        reply.tid = 123
        reply.floor = 2
        reply.author = author
        reply.content = [mainContent]

        var data = Tieba_PbPage_PbPageResponseData()
        data.forum = forum
        data.thread = thread
        data.firstFloorPost = firstFloor
        data.postList = [reply]
        data.page.currentPage = 1
        data.page.totalPage = 1

        var response = Tieba_PbPage_PbPageResponse()
        response.data = data

        let page = PostMapper.threadPage(from: response)

        XCTAssertEqual(page.mainPost?.id, 11)
        XCTAssertEqual(page.mainPost?.contentPreview, "主贴")
        XCTAssertEqual(page.posts.map(\.id), [12])
    }

    func testThreadPageUsesThreadAuthorIPWhenFirstFloorPostDoesNotIncludeIP() {
        var threadAuthor = Tieba_User()
        threadAuthor.id = 42
        threadAuthor.name = "raw"
        threadAuthor.nameShow = "楼主"
        threadAuthor.ipAddress = "河南"

        var firstFloorAuthor = Tieba_User()
        firstFloorAuthor.id = 42
        firstFloorAuthor.name = "raw"
        firstFloorAuthor.nameShow = "楼主"

        var forum = Tieba_SimpleForum()
        forum.id = 9
        forum.name = "ios"

        var thread = Tieba_ThreadInfo()
        thread.id = 123
        thread.title = "主题"
        thread.author = threadAuthor

        var content = Tieba_PbContent()
        content.type = 0
        content.text = "主贴"

        var firstFloor = Tieba_Post()
        firstFloor.id = 11
        firstFloor.tid = 123
        firstFloor.floor = 1
        firstFloor.author = firstFloorAuthor
        firstFloor.content = [content]

        var responseData = Tieba_PbPage_PbPageResponseData()
        responseData.forum = forum
        responseData.thread = thread
        responseData.firstFloorPost = firstFloor
        responseData.page.currentPage = 1
        responseData.page.totalPage = 1

        var response = Tieba_PbPage_PbPageResponse()
        response.data = responseData

        let page = PostMapper.threadPage(from: response)

        XCTAssertEqual(page.mainPost?.ipAddress, "河南")
    }

    func testMapsPreviewSubpostAuthorFromUserList() {
        var author = Tieba_User()
        author.id = 8
        author.name = "reply_raw"
        author.nameShow = "楼中楼用户"
        author.portrait = "tb.1.reply"

        var content = Tieba_PbContent()
        content.type = 0
        content.text = "回复内容"

        var subpost = Tieba_SubPostList()
        subpost.id = 99
        subpost.authorID = 8
        subpost.floor = 3
        var subpostLocation = Tieba_Lbs()
        subpostLocation.name = "陕西"
        subpost.location = subpostLocation
        subpost.content = [content]
        subpost.agree.agreeNum = 6

        var subpostList = Tieba_SubPost()
        subpostList.subPostList = [subpost]

        var post = Tieba_Post()
        post.id = 7
        post.tid = 123
        post.subPostList = subpostList
        post.subPostNumber = 1
        post.agree.agreeNum = 5
        var postLocation = Tieba_Lbs()
        postLocation.name = "北京"
        post.lbsInfo = postLocation

        let mapped = PostMapper.post(from: post, usersByID: [8: author], threadID: 123)

        XCTAssertEqual(mapped.likeCount, 5)
        XCTAssertEqual(mapped.ipAddress, "北京")
        XCTAssertEqual(mapped.previewSubposts.first?.floor, 3)
        XCTAssertEqual(mapped.previewSubposts.first?.ipAddress, "陕西")
        XCTAssertEqual(mapped.previewSubposts.first?.author.displayNameResolved, "楼中楼用户")
        XCTAssertEqual(mapped.previewSubposts.first?.likeCount, 6)
        XCTAssertEqual(mapped.previewSubposts.first?.author.portraitURL?.absoluteString, "https://himg.bdimg.com/sys/portrait/item/tb.1.reply")
        XCTAssertEqual(mapped.previewSubposts.first?.blocks.compactMap(\.plainText).joined(), "回复内容")
    }

    func testSubpostAuthorFallsBackToUserIDInsteadOfBlankName() {
        var subpost = Tieba_SubPostList()
        subpost.id = 99
        subpost.authorID = 8

        let mapped = PostMapper.subpost(subpost)

        XCTAssertEqual(mapped.author.displayNameResolved, "用户8")
    }
}
