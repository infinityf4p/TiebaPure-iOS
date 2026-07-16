import Foundation

enum PostMapper {
    static func blocks(from contents: [Tieba_PbContent]) -> [ContentBlock] {
        contents.flatMap(blocks)
    }

    static func blocks(from content: Tieba_PbContent) -> [ContentBlock] {
        guard TiebaContentFilter.shouldKeep(content: content) else { return [] }

        switch content.type {
        case 0, 9, 27:
            return TiebaEmoticon.blocks(from: content.text)
        case 1:
            return [.link(title: TiebaEmoticon.plainDisplayText(content.text), url: url(firstNonEmpty(content.link)))]
        case 2:
            let code = emoticonCode(from: content) ?? ""
            return code.isEmpty ? [] : [.emoticon(code: code)]
        case 3, 20:
            let size = parseSize(content.bsize, fallbackWidth: content.width, fallbackHeight: content.height)
            let thumbnailURL = url(firstNonEmpty(
                content.cdnSrc,
                content.cdnSrcActive,
                content.bigCdnSrc,
                content.bigSrc,
                content.dynamic,
                content.src,
                content.originSrc
            ))
            let originalURL = url(firstNonEmpty(
                content.originSrc,
                content.bigCdnSrc,
                content.bigSrc,
                content.cdnSrc,
                content.src
            ))
            guard thumbnailURL != nil || originalURL != nil else { return [] }
            return [.image(ImageContent(
                thumbnailURL: thumbnailURL,
                originalURL: originalURL,
                width: size.width,
                height: size.height,
                showOriginalButton: content.showOriginalBtn == 1
            ))]
        case 4:
            return [.mention(userID: content.uid == 0 ? nil : content.uid, text: content.text)]
        case 5:
            let size = parseSize(content.bsize, fallbackWidth: content.width, fallbackHeight: content.height)
            return [.video(VideoContent(
                videoURL: url(firstNonEmpty(content.link)),
                coverURL: url(firstNonEmpty(content.src, content.cdnSrc)),
                webURL: url(firstNonEmpty(content.text)),
                width: size.width,
                height: size.height,
                duration: Int(content.duringTime)
            ))]
        default:
            return TiebaEmoticon.blocks(from: content.text)
        }
    }

    static func videoBlock(from videoInfo: Tieba_VideoInfo) -> ContentBlock? {
        guard videoInfo.videoURL.isEmpty == false || videoInfo.thumbnailURL.isEmpty == false else {
            return nil
        }

        return .video(VideoContent(
            videoURL: url(firstNonEmpty(videoInfo.videoURL)),
            coverURL: url(firstNonEmpty(videoInfo.thumbnailURL)),
            webURL: nil,
            width: Int(videoInfo.videoWidth),
            height: Int(videoInfo.videoHeight),
            duration: Int(videoInfo.videoDuration)
        ))
    }

    static func imageBlock(from media: Tieba_Media) -> ContentBlock? {
        let thumbnailURL = url(firstNonEmpty(
            media.bigPic,
            media.dynamicPic,
            media.srcPic,
            media.originPic
        ))
        let originalURL = url(firstNonEmpty(
            media.originPic,
            media.bigPic,
            media.dynamicPic,
            media.srcPic
        ))
        guard thumbnailURL != nil || originalURL != nil else { return nil }

        return .image(ImageContent(
            thumbnailURL: thumbnailURL,
            originalURL: originalURL,
            width: Int(media.width),
            height: Int(media.height),
            showOriginalButton: media.showOriginalBtn == 1
        ))
    }

    static func post(from proto: Tieba_Post, usersByID: [Int64: Tieba_User], threadID: Int64) -> Post {
        let author = UserMapper.fromUser(
            proto.hasAuthor ? proto.author : Tieba_User(),
            fallbackID: proto.authorID,
            fallback: usersByID[proto.authorID]
        )

        return Post(
            id: proto.id,
            threadID: threadID == 0 ? proto.tid : threadID,
            floor: Int(proto.floor),
            author: author,
            ipAddress: firstNonEmpty(author.ipAddress, proto.lbsInfo.name),
            createdAt: proto.time == 0 ? nil : Date(timeIntervalSince1970: TimeInterval(proto.time)),
            blocks: blocks(from: proto.content),
            subpostCount: Int(proto.subPostNumber),
            likeCount: likeCount(from: proto),
            isLiked: proto.agree.hasAgree_p != 0,
            previewSubposts: proto.subPostList.subPostList.map { subpost($0, usersByID: usersByID) }
        )
    }

    static func subpost(_ proto: Tieba_SubPostList, usersByID: [Int64: Tieba_User] = [:]) -> Subpost {
        let author = UserMapper.fromUser(
            proto.hasAuthor ? proto.author : Tieba_User(),
            fallbackID: proto.authorID,
            fallback: usersByID[proto.authorID]
        )

        return Subpost(
            id: proto.id,
            floor: Int(proto.floor),
            author: author,
            ipAddress: firstNonEmpty(author.ipAddress, proto.location.name),
            blocks: blocks(from: proto.content),
            createdAt: proto.time == 0 ? nil : Date(timeIntervalSince1970: TimeInterval(proto.time)),
            likeCount: Int(proto.agree.agreeNum),
            isLiked: proto.agree.hasAgree_p != 0
        )
    }

    static func subpost(from proto: Tieba_SubPostList) -> Subpost {
        subpost(proto)
    }

    static func threadPage(from response: Tieba_PbPage_PbPageResponse) -> ThreadPage {
        let data = response.data
        var usersByID: [Int64: Tieba_User] = [:]
        for user in data.userList {
            usersByID[user.id] = user
        }

        let forum = ForumMapper.fromProto(data.forum)
        let thread = ThreadMapper.fromThreadInfo(data.thread, usersByID: usersByID)
        let posts = data.postList
            .filter(TiebaContentFilter.shouldKeep(post:))
            .map { post(from: $0, usersByID: usersByID, threadID: data.thread.id) }
            .map { enrichIPIfNeeded($0, thread: thread) }
        let mainPost = data.hasFirstFloorPost && data.firstFloorPost.id != 0
            ? enrichIPIfNeeded(post(from: data.firstFloorPost, usersByID: usersByID, threadID: data.thread.id), thread: thread)
            : posts.first { $0.floor == 1 }

        return ThreadPage(
            thread: thread,
            forum: forum,
            mainPost: mainPost,
            posts: posts,
            currentPage: Int(data.page.currentPage),
            totalPage: Int(data.page.totalPage),
            hasMore: data.page.currentPage < data.page.totalPage || data.page.hasMore_p != 0
        )
    }

    private static func parseSize(
        _ value: String,
        fallbackWidth: UInt32 = 0,
        fallbackHeight: UInt32 = 0
    ) -> (width: Int, height: Int) {
        let parts = value.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        let width = parts.first ?? Int(fallbackWidth)
        let height = parts.dropFirst().first ?? Int(fallbackHeight)
        return (width, height)
    }

    private static func firstNonEmpty(_ values: String?...) -> String? {
        values.compactMap { $0 }.first { $0.isEmpty == false }
    }

    private static func emoticonCode(from content: Tieba_PbContent) -> String? {
        let candidates = [content.c, content.text]
        if let renderable = candidates.first(where: { value in
            value.isEmpty == false && TiebaEmoticon.imageName(for: value) != nil
        }) {
            return renderable
        }
        return firstNonEmpty(content.c, content.text)
    }

    private static func enrichIPIfNeeded(_ post: Post, thread: ThreadSummary) -> Post {
        guard firstNonEmpty(post.ipAddress) == nil,
              post.author.id != 0,
              post.author.id == thread.author.id,
              let threadAuthorIP = firstNonEmpty(thread.author.ipAddress) else {
            return post
        }

        var enriched = post
        enriched.ipAddress = threadAuthorIP
        return enriched
    }

    private static func likeCount(from proto: Tieba_Post) -> Int {
        if proto.agree.agreeNum != 0 {
            return Int(proto.agree.agreeNum)
        }
        if proto.postZan.zanNum != 0 {
            return Int(proto.postZan.zanNum)
        }
        return Int(proto.zan.num)
    }

    private static func url(_ value: String?) -> URL? {
        TiebaURL.make(value)
    }
}
