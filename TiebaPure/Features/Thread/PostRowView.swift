import SwiftUI

struct PostRowView: View {
    let post: Post
    let threadTitle: String?
    let threadAuthorID: Int64?
    let isMainPost: Bool
    let onOpenSubposts: ((Post) -> Void)?

    init(
        post: Post,
        threadTitle: String? = nil,
        threadAuthorID: Int64? = nil,
        isMainPost: Bool = false,
        onOpenSubposts: ((Post) -> Void)? = nil
    ) {
        self.post = post
        self.threadTitle = threadTitle
        self.threadAuthorID = threadAuthorID
        self.isMainPost = isMainPost
        self.onOpenSubposts = onOpenSubposts
    }

    var body: some View {
        ReaderCard(showsDivider: isMainPost == false) {
            VStack(alignment: .leading, spacing: isMainPost ? TiebaPureTheme.Spacing.md : TiebaPureTheme.Spacing.sm) {
                UserHeaderView(
                    author: post.author,
                    floor: post.floor,
                    ipAddress: post.ipAddress,
                    createdAt: post.createdAt,
                    isThreadAuthor: isThreadAuthor,
                    isMainPost: isMainPost,
                    showsFloorBadge: isMainPost == false,
                    trailingLikeCount: isMainPost ? nil : post.likeCount
                )

                if isMainPost, let threadTitle, threadTitle.isEmpty == false {
                    Text(threadTitle)
                        .font(.title2.weight(.semibold))
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }

                ContentBlocksView(
                    blocks: post.blocks,
                    textStyle: isMainPost ? .body : .reply,
                    lineLimit: ThreadContentDisplayPolicy.detailLineLimit,
                    inlineAccessibilityIdentifier: isMainPost
                        ? "thread-main-text"
                        : "thread-reply-text"
                )

                if post.previewSubposts.isEmpty == false {
                    SubpostPreviewView(
                        subposts: post.previewSubposts,
                        totalCount: post.subpostCount,
                        threadAuthorID: threadAuthorID,
                        onOpenAll: onOpenSubposts.map { open in { open(post) } }
                    )
                }
            }
        }
    }

    private var isThreadAuthor: Bool {
        guard let threadAuthorID else { return false }
        return threadAuthorID != 0 && threadAuthorID == post.author.id
    }
}

struct UserHeaderView: View {
    let author: UserSummary
    let floor: Int?
    var ipAddress: String? = nil
    let createdAt: Date?
    let isThreadAuthor: Bool
    var isMainPost: Bool = false
    var showsFloorBadge = true
    var trailingLikeCount: Int?

    var body: some View {
        ViewThatFits(in: .horizontal) {
            regularLayout
            compactLayout
        }
    }

    private var avatar: some View {
            AvatarView(
                url: author.portraitURL,
                title: author.displayNameResolved,
                size: isMainPost ? TiebaPureTheme.AvatarSize.large : TiebaPureTheme.AvatarSize.medium
            )
    }

    private var regularLayout: some View {
        HStack(alignment: .top, spacing: TiebaPureTheme.Spacing.sm) {
            avatar
            VStack(alignment: .leading, spacing: TiebaPureTheme.Spacing.xxs) {
                HStack(alignment: .center, spacing: TiebaPureTheme.Spacing.xs) {
                    Text(author.displayNameResolved)
                        .font((isMainPost ? Font.body : Font.callout).weight(.semibold))
                        .lineLimit(2)

                    UserBadgesView(
                        author: author,
                        isThreadAuthor: isThreadAuthor,
                        floor: floor,
                        showsFloorBadge: showsFloorBadge
                    )
                }

                Text(metadataText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: TiebaPureTheme.Spacing.sm)

            if let trailingLikeCount {
                CompactLikeCountView(count: trailingLikeCount)
            }
        }
    }

    private var compactLayout: some View {
        HStack(alignment: .top, spacing: TiebaPureTheme.Spacing.sm) {
            avatar
            VStack(alignment: .leading, spacing: TiebaPureTheme.Spacing.xxs) {
                Text(author.displayNameResolved)
                    .font((isMainPost ? Font.body : Font.callout).weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                UserBadgesView(
                    author: author,
                    isThreadAuthor: isThreadAuthor,
                    floor: floor,
                    showsFloorBadge: showsFloorBadge
                )
                Text(metadataText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let trailingLikeCount {
                    CompactLikeCountView(count: trailingLikeCount)
                }
            }
        }
    }

    private var metadataText: String {
        var items: [String] = []
        if let createdAt {
            items.append(ReaderDateText.string(from: createdAt))
        }
        if let ipAddress = ipAddress ?? author.ipAddress, ipAddress.isEmpty == false {
            items.append(ipAddress)
        }
        return items.joined(separator: "  ")
    }
}

struct UserBadgesView: View {
    let author: UserSummary
    let isThreadAuthor: Bool
    var floor: Int?
    var showsFloorBadge = false

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: TiebaPureTheme.Spacing.xxs) {
                badges
            }
            VStack(alignment: .leading, spacing: TiebaPureTheme.Spacing.xxs) {
                badges
            }
        }
    }

    @ViewBuilder
    private var badges: some View {
        if let level = author.level, level > 0 {
            Text(author.levelName?.isEmpty == false ? "\(level) \(author.levelName ?? "")" : "Lv.\(level)")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.orange.opacity(0.18))
                )
        }

        if showsFloorBadge, let floor, floor > 0 {
            Text("\(floor)楼")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(TiebaPureTheme.ColorToken.readerTertiarySurface)
                )
        }

        if isThreadAuthor {
            ThreadAuthorBadge()
        }
    }
}

struct ThreadAuthorBadge: View {
    var body: some View {
        Text("楼主")
            .font(.caption2.weight(.bold))
            .foregroundStyle(.primary)
            .lineLimit(1)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(TiebaPureTheme.ColorToken.primaryAccent.opacity(0.16))
            )
            .fixedSize()
            .accessibilityLabel("楼主")
    }
}
