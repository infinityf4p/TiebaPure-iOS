import Foundation

enum ThreadMapper {
    static func fromThreadInfo(_ proto: Tieba_ThreadInfo, usersByID: [Int64: Tieba_User]) -> ThreadSummary {
        let author = UserMapper.fromUser(
            proto.hasAuthor ? proto.author : Tieba_User(),
            fallbackID: proto.authorID,
            fallback: usersByID[proto.authorID]
        )
        var blocks = PostMapper.blocks(from: proto.firstPostContent)
        for mediaBlock in proto.media.compactMap(PostMapper.imageBlock(from:)) {
            guard hasMatchingImage(mediaBlock, in: blocks) == false else { continue }
            blocks.append(mediaBlock)
        }
        if proto.hasVideoInfo, let videoBlock = PostMapper.videoBlock(from: proto.videoInfo) {
            if let existingVideoIndex = firstVideoIndex(in: blocks) {
                blocks[existingVideoIndex] = mergedVideoBlock(
                    contentBlock: blocks[existingVideoIndex],
                    videoInfoBlock: videoBlock
                )
            } else {
                blocks.append(videoBlock)
            }
        }
        let forumID = proto.forumID != 0 ? proto.forumID : (proto.forumInfo.id == 0 ? nil : proto.forumInfo.id)
        let forumName = firstNonEmpty(proto.forumName, proto.hasForumInfo ? proto.forumInfo.name : nil)

        return ThreadSummary(
            id: proto.id == 0 ? proto.threadID : proto.id,
            forumID: forumID,
            title: proto.title,
            author: author,
            forumName: forumName,
            forumAvatarURL: proto.hasForumInfo ? TiebaURL.make(proto.forumInfo.avatar) : nil,
            replyCount: Int(proto.replyNum),
            viewCount: Int(proto.viewNum),
            likeCount: likeCount(from: proto),
            createdAt: proto.createTime == 0 ? nil : Date(timeIntervalSince1970: TimeInterval(proto.createTime)),
            lastReplyAt: proto.lastTimeInt == 0 ? nil : Date(timeIntervalSince1970: TimeInterval(proto.lastTimeInt)),
            blocks: blocks,
            isTop: proto.isTop != 0,
            isGood: proto.isGood != 0,
            hasVideo: proto.hasVideoInfo || containsVideo(in: blocks)
        )
    }

    private static func containsVideo(in blocks: [ContentBlock]) -> Bool {
        firstVideoIndex(in: blocks) != nil
    }

    private static func hasMatchingImage(_ candidate: ContentBlock, in blocks: [ContentBlock]) -> Bool {
        guard case let .image(candidateImage) = candidate else { return false }
        return blocks.contains { block in
            guard case let .image(image) = block else { return false }
            let existingURLs = [image.thumbnailURL, image.originalURL].compactMap { $0 }
            return [candidateImage.thumbnailURL, candidateImage.originalURL]
                .compactMap { $0 }
                .contains { existingURLs.contains($0) }
        }
    }

    private static func firstVideoIndex(in blocks: [ContentBlock]) -> Int? {
        blocks.firstIndex { block in
            if case .video = block { return true }
            return false
        }
    }

    private static func mergedVideoBlock(contentBlock: ContentBlock, videoInfoBlock: ContentBlock) -> ContentBlock {
        guard case let .video(contentVideo) = contentBlock,
              case let .video(infoVideo) = videoInfoBlock else {
            return contentBlock
        }

        return .video(VideoContent(
            videoURL: infoVideo.videoURL ?? contentVideo.videoURL,
            coverURL: contentVideo.coverURL ?? infoVideo.coverURL,
            webURL: contentVideo.webURL ?? infoVideo.webURL,
            width: firstPositive(contentVideo.width, infoVideo.width),
            height: firstPositive(contentVideo.height, infoVideo.height),
            duration: firstPositive(contentVideo.duration, infoVideo.duration)
        ))
    }

    private static func firstPositive(_ values: Int...) -> Int {
        values.first { $0 > 0 } ?? 0
    }

    private static func likeCount(from proto: Tieba_ThreadInfo) -> Int {
        if proto.agree.agreeNum != 0 {
            return Int(proto.agree.agreeNum)
        }
        return Int(proto.agreeNum)
    }

    private static func firstNonEmpty(_ values: String?...) -> String? {
        values.compactMap { $0 }.first { $0.isEmpty == false }
    }
}

enum UserMapper {
    static func fromUser(_ proto: Tieba_User, fallbackID: Int64? = nil, fallback: Tieba_User? = nil) -> UserSummary {
        let fallbackUserID = fallback?.id ?? 0
        let id = proto.id != 0 ? proto.id : (fallbackUserID != 0 ? fallbackUserID : fallbackID ?? 0)
        let name = firstNonEmpty(proto.name, fallback?.name, id == 0 ? "未知用户" : "用户\(id)")
        let displayName = firstNonEmpty(proto.nameShow, fallback?.nameShow, name)
        let portrait = firstNonEmpty(proto.portrait, proto.portraith, fallback?.portrait, fallback?.portraith, "")
        let level = firstNonZero(proto.levelID, fallback?.levelID).map(Int.init)
        let levelName = firstNonEmpty(proto.levelName, fallback?.levelName)

        return UserSummary(
            id: id,
            name: name,
            displayName: displayName,
            portrait: portrait,
            level: level,
            levelName: levelName.isEmpty ? nil : levelName,
            ipAddress: firstNonEmpty(proto.ipAddress, proto.ip, fallback?.ipAddress, fallback?.ip)
        )
    }

    private static func firstNonEmpty(_ values: String?...) -> String {
        values.compactMap { $0 }.first { $0.isEmpty == false } ?? ""
    }

    private static func firstNonZero<T: FixedWidthInteger>(_ values: T?...) -> T? {
        values.compactMap { $0 }.first { $0 != 0 }
    }
}
