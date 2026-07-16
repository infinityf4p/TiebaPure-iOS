import Foundation

enum UserProfileMapper {
    static func profile(
        from proto: Tieba_User,
        fallback: UserSummary,
        isCurrentUser: Bool
    ) -> UserProfile {
        let user = UserMapper.fromUser(proto, fallbackID: fallback.id)
        let resolvedUser = UserSummary(
            id: user.id,
            name: firstNonEmpty(user.name, fallback.name),
            displayName: firstNonEmpty(user.displayName, fallback.displayName, user.name),
            portrait: firstNonEmpty(user.portrait, fallback.portrait),
            level: user.level ?? fallback.level,
            levelName: firstNonEmptyOptional(user.levelName, fallback.levelName),
            ipAddress: firstNonEmptyOptional(user.ipAddress, fallback.ipAddress)
        )
        let forums = proto.likeForum.compactMap { item -> Forum? in
            let name = normalizedForumName(item.forumName)
            guard name.isEmpty == false else { return nil }
            let id = Int64(exactly: item.forumID) ?? 0
            return Forum(
                id: id,
                name: name,
                displayName: name.hasSuffix("吧") ? name : "\(name)吧",
                avatarURL: nil,
                memberCount: 0,
                threadCount: 0
            )
        }
        let uniqueForums = deduplicatedForums(forums)
        let declaredForumCount = max(Int(proto.myLikeNum), uniqueForums.count)
        let privacyValue = proto.hasPrivSets ? Int(proto.privSets.like) : 0

        return UserProfile(
            user: resolvedUser,
            isCurrentUser: isCurrentUser,
            isFollowed: proto.hasConcerned_p != 0,
            tiebaID: firstNonEmpty(proto.tiebaUid, proto.id == 0 ? "" : "\(proto.id)"),
            tiebaAge: proto.tbAge,
            sex: sex(from: proto.sex != 0 ? proto.sex : proto.gender),
            location: firstNonEmptyOptional(proto.ipAddress, proto.ip, fallback.ipAddress),
            intro: firstNonEmpty(proto.displayIntro, proto.intro),
            backgroundURL: TiebaURL.make(proto.bgPic),
            agreeCount: max(Int(proto.totalAgreeNum), Int(proto.agreeNum)),
            followingCount: max(Int(proto.concernNum), 0),
            followerCount: max(Int(proto.fansNum), 0),
            threadCount: max(Int(proto.threadNum), 0),
            followedForumCount: max(declaredForumCount, 0),
            followedForums: uniqueForums,
            followedForumsVisibility: UserProfilePrivacyPolicy.followedForumsVisibility(
                isCurrentUser: isCurrentUser,
                privacyValue: privacyValue,
                declaredCount: declaredForumCount,
                returnedCount: uniqueForums.count
            )
        )
    }

    static func threadsPage(
        from response: Tiebapure_Profile_UserThreadsResponse,
        page: Int
    ) -> UserThreadsPage {
        let threads = response.data.postList.compactMap(thread(from:))
        return UserThreadsPage(
            threads: threads,
            currentPage: page,
            hasMore: response.data.hidePost == 0 && threads.isEmpty == false,
            visibility: response.data.hidePost == 0 ? .visible : .privateContent
        )
    }

    static func thread(from item: Tiebapure_Profile_UserThreadItem) -> ThreadSummary? {
        guard let threadID = Int64(exactly: item.threadID), threadID > 0 else { return nil }

        var blocks = PostMapper.blocks(from: item.firstPostContent)
        if blocks.isEmpty {
            blocks = PostMapper.blocks(from: item.richAbstract)
        }
        if blocks.isEmpty {
            let abstractText = item.abstractThread
                .map(\.text)
                .joined()
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let fallbackText = firstNonEmpty(abstractText, item.contentThread)
            if fallbackText.isEmpty == false {
                blocks = [.text(fallbackText)]
            }
        }
        for media in item.media {
            guard let block = PostMapper.imageBlock(from: media), contains(block, in: blocks) == false else {
                continue
            }
            blocks.append(block)
        }

        let richTitle = PostMapper.blocks(from: item.richTitle)
            .compactMap(\.plainText)
            .joined()
        let authorName = firstNonEmpty(item.nameShow, item.userName, item.userID == 0 ? "" : "用户\(item.userID)")
        let forumID = Int64(exactly: item.forumID)

        return ThreadSummary(
            id: threadID,
            forumID: (forumID ?? 0) == 0 ? nil : forumID,
            title: firstNonEmpty(item.title, richTitle),
            author: UserSummary(
                id: item.userID,
                name: firstNonEmpty(item.userName, authorName),
                displayName: authorName,
                portrait: item.userPortrait,
                ipAddress: item.ip
            ),
            forumName: normalizedForumName(item.forumName),
            replyCount: Int(item.replyNum),
            viewCount: max(Int(item.viewNum), 0),
            likeCount: max(Int(item.agreeNum), 0),
            createdAt: item.createTime == 0 ? nil : Date(timeIntervalSince1970: TimeInterval(item.createTime)),
            lastReplyAt: nil,
            blocks: blocks,
            hasVideo: false
        )
    }

    private static func sex(from value: Int32) -> UserProfileSex {
        switch value {
        case 1:
            return .male
        case 2:
            return .female
        default:
            return .unspecified
        }
    }

    private static func normalizedForumName(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasSuffix("吧") ? String(trimmed.dropLast()) : trimmed
    }

    private static func deduplicatedForums(_ forums: [Forum]) -> [Forum] {
        var seen = Set<String>()
        return forums.filter { forum in
            let key = forum.id != 0 ? "id:\(forum.id)" : "name:\(forum.name.lowercased())"
            return seen.insert(key).inserted
        }
    }

    private static func contains(_ candidate: ContentBlock, in blocks: [ContentBlock]) -> Bool {
        guard case let .image(candidateImage) = candidate else { return false }
        let candidateURLs = [candidateImage.thumbnailURL, candidateImage.originalURL].compactMap { $0 }
        return blocks.contains { block in
            guard case let .image(image) = block else { return false }
            let existingURLs = [image.thumbnailURL, image.originalURL].compactMap { $0 }
            return candidateURLs.contains { existingURLs.contains($0) }
        }
    }

    private static func firstNonEmpty(_ values: String?...) -> String {
        values.compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { $0.isEmpty == false } ?? ""
    }

    private static func firstNonEmptyOptional(_ values: String?...) -> String? {
        let value = values.compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { $0.isEmpty == false } ?? ""
        return value.isEmpty ? nil : value
    }
}
