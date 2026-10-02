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

    func testUserPortraitUpgradesLegacyInsecureTiebaAvatarURL() {
        let user = UserSummary(
            id: 42,
            name: "raw",
            displayName: "Readable",
            portrait: "http://tb.himg.baidu.com/sys/portrait/item/tb.1.demo"
        )

        XCTAssertEqual(user.portraitURL?.absoluteString, "https://himg.bdimg.com/sys/portrait/item/tb.1.demo")
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

    func testForumRouteKeepsVerbatimNameAndAppendsDisplaySuffixOnlyWhenMissing() {
        func summary(forumName: String?) -> ThreadSummary {
            ThreadSummary(
                id: 7,
                title: "title",
                author: UserSummary(id: 1, name: "author", displayName: "Author", portrait: ""),
                forumName: forumName,
                replyCount: 0,
                viewCount: 0,
                blocks: []
            )
        }

        XCTAssertEqual(summary(forumName: "显卡").forumRoute?.name, "显卡")
        XCTAssertEqual(summary(forumName: "显卡").forumDisplayNameResolved, "显卡吧")
        XCTAssertEqual(summary(forumName: "网吧").forumRoute?.name, "网吧")
        XCTAssertEqual(summary(forumName: "网吧").forumDisplayNameResolved, "网吧")
        XCTAssertNil(summary(forumName: "   ").forumRoute)
        XCTAssertNil(summary(forumName: nil).forumDisplayNameResolved)
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

    func testMapsVideoAndNormalizedVoiceContent() throws {
        var video = Tieba_PbContent()
        video.type = 5
        video.link = "https://video.example/a.mp4"
        video.src = "https://video.example/cover.jpg"
        video.bsize = "1280,720"

        var voice = Tieba_PbContent()
        voice.type = 10
        voice.voiceMd5 = " ABCDEF0123456789ABCDEF0123456789\n"
        voice.duringTime = 3_456

        let blocks = PostMapper.blocks(from: [video, voice])

        XCTAssertEqual(blocks.count, 2)
        guard case let .video(value) = blocks[0] else {
            return XCTFail("expected video block")
        }
        XCTAssertEqual(value.videoURL?.absoluteString, "https://video.example/a.mp4")
        XCTAssertEqual(value.coverURL?.absoluteString, "https://video.example/cover.jpg")
        XCTAssertEqual(value.width, 1280)
        XCTAssertEqual(value.height, 720)
        guard case let .voice(mappedVoice) = blocks[1] else {
            return XCTFail("expected voice block")
        }
        XCTAssertEqual(mappedVoice.md5, "abcdef0123456789abcdef0123456789")
        XCTAssertEqual(mappedVoice.durationMilliseconds, 3_456)
        XCTAssertEqual(blocks[1].plainText, "[语音]")
    }

    func testVoiceMappingRejectsInvalidMD5AndDeduplicatesNormalizedMD5() throws {
        var first = Tieba_PbContent()
        first.type = 10
        first.voiceMd5 = "ABCDEF0123456789ABCDEF0123456789"
        first.duringTime = 1_000

        var duplicate = Tieba_PbContent()
        duplicate.type = 10
        duplicate.voiceMd5 = "abcdef0123456789abcdef0123456789"
        duplicate.duringTime = 2_000

        var invalid = Tieba_PbContent()
        invalid.type = 10
        invalid.voiceMd5 = "not-a-32-character-hexadecimal-md5"

        let blocks = PostMapper.blocks(from: [first, duplicate, invalid])

        XCTAssertEqual(blocks.count, 1)
        guard case let .voice(voice) = try XCTUnwrap(blocks.first) else {
            return XCTFail("expected voice block")
        }
        XCTAssertEqual(voice.md5, "abcdef0123456789abcdef0123456789")
        XCTAssertEqual(voice.durationMilliseconds, 1_000)
        XCTAssertFalse(TiebaContentFilter.shouldKeep(content: invalid))
    }

    func testVoiceOnlyFloorMapsToPlayableVoiceBlock() throws {
        var voice = Tieba_PbContent()
        voice.type = 10
        voice.voiceMd5 = "0123456789abcdef0123456789abcdef"
        voice.duringTime = 2_500

        var post = Tieba_Post()
        post.id = 7
        post.floor = 5
        post.content = [voice]
        post.subPostNumber = 2

        let mapped = PostMapper.post(from: post, usersByID: [:], threadID: 123)

        XCTAssertEqual(mapped.blocks, [.voice(try XCTUnwrap(VoiceContent(
            md5: "0123456789abcdef0123456789abcdef",
            durationMilliseconds: 2_500
        )))])
        XCTAssertEqual(mapped.subpostCount, 2)
        XCTAssertTrue(TiebaContentFilter.shouldKeep(post: post))

        var empty = Tieba_Post()
        empty.id = 8
        empty.floor = 6

        XCTAssertTrue(PostMapper.post(from: empty, usersByID: [:], threadID: 123).blocks.isEmpty)
    }

    func testInvalidVoiceOnlyFloorIsOmittedUnlessItOwnsSubposts() {
        var invalidVoice = Tieba_PbContent()
        invalidVoice.type = 10
        invalidVoice.voiceMd5 = "invalid"

        var post = Tieba_Post()
        post.content = [invalidVoice]

        XCTAssertFalse(TiebaContentFilter.shouldKeep(post: post))
        post.subPostNumber = 1
        XCTAssertTrue(TiebaContentFilter.shouldKeep(post: post))
        XCTAssertTrue(PostMapper.post(from: post, usersByID: [:], threadID: 123).blocks.isEmpty)
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
        thread.firstPostID = 123
        var agree = Tieba_Agree()
        agree.agreeNum = 31
        agree.hasAgree_p = 1
        thread.agree = agree
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
        XCTAssertEqual(summary.firstPostID, 123)
        XCTAssertTrue(summary.isLiked)
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

    func testThreadSummaryMergesVoiceInfoAndDeduplicatesContentVoice() throws {
        var contentVoice = Tieba_PbContent()
        contentVoice.type = 10
        contentVoice.voiceMd5 = "ABCDEF0123456789ABCDEF0123456789"
        contentVoice.duringTime = 1_250

        var duplicateVoice = Tieba_Voice()
        duplicateVoice.voiceMd5 = "abcdef0123456789abcdef0123456789"
        duplicateVoice.duringTime = 2_500

        var additionalVoice = Tieba_Voice()
        additionalVoice.voiceMd5 = "11111111111111111111111111111111"
        additionalVoice.duringTime = 3_750

        var invalidVoice = Tieba_Voice()
        invalidVoice.voiceMd5 = "not-valid"

        var thread = Tieba_ThreadInfo()
        thread.id = 7
        thread.isVoiceThread = 1
        thread.firstPostContent = [contentVoice]
        thread.voiceInfo = [duplicateVoice, invalidVoice, additionalVoice]

        let summary = ThreadMapper.fromThreadInfo(thread, usersByID: [:])
        let voices = summary.blocks.compactMap { block -> VoiceContent? in
            guard case let .voice(voice) = block else { return nil }
            return voice
        }

        XCTAssertEqual(voices, [
            try XCTUnwrap(VoiceContent(
                md5: "abcdef0123456789abcdef0123456789",
                durationMilliseconds: 1_250
            )),
            try XCTUnwrap(VoiceContent(
                md5: "11111111111111111111111111111111",
                durationMilliseconds: 3_750
            ))
        ])
        XCTAssertEqual(summary.textPreview, "[语音][语音]")
    }

    func testUserProfileThreadPrefersStructuredVoiceOverFallbackText() throws {
        var voice = Tieba_Voice()
        voice.voiceMd5 = "22222222222222222222222222222222"
        voice.duringTime = 4_500

        var item = Tiebapure_Profile_UserThreadItem()
        item.threadID = 77
        item.contentThread = "[语音]"
        item.voiceInfo = [voice]

        let summary = try XCTUnwrap(UserProfileMapper.thread(from: item))

        XCTAssertEqual(summary.blocks, [.voice(try XCTUnwrap(VoiceContent(
            md5: "22222222222222222222222222222222",
            durationMilliseconds: 4_500
        )))])
        XCTAssertEqual(summary.textPreview, "[语音]")
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
        subpost.agree.hasAgree_p = 1

        var subpostList = Tieba_SubPost()
        subpostList.subPostList = [subpost]

        var post = Tieba_Post()
        post.id = 7
        post.tid = 123
        post.subPostList = subpostList
        post.subPostNumber = 1
        post.agree.agreeNum = 5
        post.agree.hasAgree_p = 1
        var postLocation = Tieba_Lbs()
        postLocation.name = "北京"
        post.lbsInfo = postLocation

        let mapped = PostMapper.post(from: post, usersByID: [8: author], threadID: 123)

        XCTAssertEqual(mapped.likeCount, 5)
        XCTAssertTrue(mapped.isLiked)
        XCTAssertEqual(mapped.ipAddress, "北京")
        XCTAssertEqual(mapped.previewSubposts.first?.floor, 3)
        XCTAssertEqual(mapped.previewSubposts.first?.ipAddress, "陕西")
        XCTAssertEqual(mapped.previewSubposts.first?.author.displayNameResolved, "楼中楼用户")
        XCTAssertEqual(mapped.previewSubposts.first?.likeCount, 6)
        XCTAssertEqual(mapped.previewSubposts.first?.isLiked, true)
        XCTAssertEqual(mapped.previewSubposts.first?.author.portraitURL?.absoluteString, "https://himg.bdimg.com/sys/portrait/item/tb.1.reply")
        XCTAssertEqual(mapped.previewSubposts.first?.blocks.compactMap(\.plainText).joined(), "回复内容")
    }

    func testSubpostMappingKeepsImageContentForTheDetailSheet() {
        var imageContent = Tieba_PbContent()
        imageContent.type = 3
        imageContent.src = "https://tiebac.baidu.com/forum/w%3D580/sign=abc.jpg"
        imageContent.cdnSrc = "https://tiebac.baidu.com/forum/w%3D580/sign=abc.jpg"
        imageContent.bsize = "800,600"
        imageContent.width = 800
        imageContent.height = 600

        var subpost = Tieba_SubPostList()
        subpost.id = 99
        subpost.content = [imageContent]

        let mapped = PostMapper.subpost(subpost)

        XCTAssertEqual(mapped.blocks.count, 1)
        guard case let .image(image)? = mapped.blocks.first else {
            return XCTFail("Expected the subpost image block to survive mapping")
        }
        XCTAssertEqual(
            image.thumbnailURL?.absoluteString,
            "https://tiebac.baidu.com/forum/w%3D580/sign=abc.jpg"
        )
        XCTAssertEqual(image.width, 800)
        XCTAssertEqual(image.height, 600)
    }

    func testPreviewSubpostResolvesUIDLessStructuredReplyTargetFromUniqueUser() {
        var target = Tieba_User()
        target.id = 42
        target.name = "reply_target_raw"
        target.nameShow = "被回复用户"

        var replyPrefix = Tieba_PbContent()
        replyPrefix.type = 0
        replyPrefix.text = "回复 "
        var targetMention = Tieba_PbContent()
        targetMention.type = 4
        targetMention.text = "被回复用户"
        targetMention.uid = 0
        var replyBody = Tieba_PbContent()
        replyBody.type = 0
        replyBody.text = "：结构化回复"

        var subpost = Tieba_SubPostList()
        subpost.id = 99
        subpost.content = [replyPrefix, targetMention, replyBody]

        let mapped = PostMapper.subpost(subpost, usersByID: [target.id: target])

        XCTAssertEqual(mapped.blocks, [
            .text("回复 "),
            .mention(userID: target.id, text: "被回复用户"),
            .text("：结构化回复")
        ])
    }

    func testPreviewSubpostRecoversFlattenedReplyTargetOnlyFromUniqueUser() {
        var target = Tieba_User()
        target.id = 42
        target.name = "reply_target_raw"
        target.nameShow = "被回复用户"

        var flattened = Tieba_PbContent()
        flattened.type = 0
        flattened.text = "回复 @被回复用户：扁平回复"

        var subpost = Tieba_SubPostList()
        subpost.id = 99
        subpost.content = [flattened]

        let mapped = PostMapper.subpost(subpost, usersByID: [target.id: target])

        XCTAssertEqual(mapped.blocks, [
            .text("回复 "),
            .mention(userID: target.id, text: "@被回复用户"),
            .text("：扁平回复")
        ])
    }

    func testPreviewSubpostKeepsNameOnlyTargetWhenUIDIsAmbiguous() {
        var first = Tieba_User()
        first.id = 42
        first.nameShow = "同名用户"
        var second = Tieba_User()
        second.id = 43
        second.nameShow = "同名用户"

        var flattened = Tieba_PbContent()
        flattened.type = 0
        flattened.text = "回复 同名用户：不能猜错主页"

        var subpost = Tieba_SubPostList()
        subpost.id = 99
        subpost.content = [flattened]

        let mapped = PostMapper.subpost(
            subpost,
            usersByID: [first.id: first, second.id: second]
        )

        XCTAssertEqual(mapped.blocks, [
            .text("回复 "),
            .mention(userID: nil, text: "同名用户"),
            .text("：不能猜错主页")
        ])
    }

    func testPreviewSubpostRecoversNoSpaceReplyTargetAcrossAdjacentTypeZeroBlocksFromUniqueUser() {
        var target = Tieba_User()
        target.id = 42
        target.name = "reply_target_raw"
        target.nameShow = "被回复用户"

        var prefix = Tieba_PbContent()
        prefix.type = 0
        prefix.text = "回复"
        var name = Tieba_PbContent()
        name.type = 0
        name.text = "@被回复用户"
        var body = Tieba_PbContent()
        body.type = 0
        body.text = ":正文"

        var subpost = Tieba_SubPostList()
        subpost.id = 99
        subpost.content = [prefix, name, body]

        let mapped = PostMapper.subpost(subpost, usersByID: [target.id: target])

        XCTAssertEqual(mapped.blocks, [
            .text("回复"),
            .mention(userID: target.id, text: "@被回复用户"),
            .text(":正文")
        ])
    }

    func testPreviewSubpostKeepsNameOnlyTargetWhenNotInUserList() {
        var flattened = Tieba_PbContent()
        flattened.type = 0
        flattened.text = "回复 @被回复用户：正文"

        var subpost = Tieba_SubPostList()
        subpost.id = 99
        subpost.content = [flattened]

        let mapped = PostMapper.subpost(subpost, usersByID: [:])

        XCTAssertEqual(mapped.blocks, [
            .text("回复 "),
            .mention(userID: nil, text: "@被回复用户"),
            .text("：正文")
        ])
    }

    func testPreviewSubpostKeepsReplyShapedTextThatIsNotTheLeadingBlock() {
        var target = Tieba_User()
        target.id = 42
        target.nameShow = "被回复用户"

        var body = Tieba_PbContent()
        body.type = 0
        body.text = "正文"
        var emoticon = Tieba_PbContent()
        emoticon.type = 2
        emoticon.c = "哈哈"
        var trailing = Tieba_PbContent()
        trailing.type = 0
        trailing.text = "回复 被回复用户：这不是引用"

        var subpost = Tieba_SubPostList()
        subpost.id = 99
        subpost.content = [body, emoticon, trailing]

        let mapped = PostMapper.subpost(subpost, usersByID: [target.id: target])

        XCTAssertEqual(mapped.blocks, [
            .text("正文"),
            .emoticon(code: "哈哈"),
            .text("回复 被回复用户：这不是引用")
        ])
    }

    func testMainPostDoesNotInterpretReplyShapedTextAsUserTarget() {
        var content = Tieba_PbContent()
        content.type = 0
        content.text = "回复某位用户：这只是帖子正文"

        var post = Tieba_Post()
        post.id = 7
        post.content = [content]

        let mapped = PostMapper.post(from: post, usersByID: [:], threadID: 123)

        XCTAssertEqual(mapped.blocks, [.text("回复某位用户：这只是帖子正文")])
    }

    func testPostAndSubpostPreferAuthorIPOverLocationFallbacks() throws {
        var author = Tieba_User()
        author.id = 8
        author.name = "reply_raw"
        author.ipAddress = "湖南"

        var subpost = Tieba_SubPostList()
        subpost.id = 99
        subpost.authorID = author.id
        var subpostLocation = Tieba_Lbs()
        subpostLocation.name = "陕西"
        subpost.location = subpostLocation

        var subpostList = Tieba_SubPost()
        subpostList.subPostList = [subpost]

        var post = Tieba_Post()
        post.id = 7
        post.author = author
        var postLocation = Tieba_Lbs()
        postLocation.name = "北京"
        post.lbsInfo = postLocation
        post.subPostList = subpostList

        let mapped = PostMapper.post(from: post, usersByID: [author.id: author], threadID: 123)

        XCTAssertEqual(mapped.ipAddress, "湖南")
        XCTAssertEqual(try XCTUnwrap(mapped.previewSubposts.first).ipAddress, "湖南")
    }

    func testSubpostAuthorFallsBackToUserIDInsteadOfBlankName() {
        var subpost = Tieba_SubPostList()
        subpost.id = 99
        subpost.authorID = 8

        let mapped = PostMapper.subpost(subpost)

        XCTAssertEqual(mapped.author.displayNameResolved, "用户8")
    }
}
