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
            VStack(
                alignment: .leading,
                spacing: isMainPost ? TiebaPureTheme.Spacing.md : ThreadReplyLayout.headerContentSpacing
            ) {
                UserHeaderView(
                    author: post.author,
                    floor: post.floor,
                    isThreadAuthor: isThreadAuthor,
                    isMainPost: isMainPost,
                    showsFloorBadge: isMainPost == false,
                    trailingLikeCount: isMainPost ? nil : post.likeCount
                )

                VStack(alignment: .leading, spacing: TiebaPureTheme.Spacing.sm) {
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

                    ThreadPostMetadataView(
                        createdAt: post.createdAt,
                        ipAddress: ThreadPostMetadataText.firstLocation(post.ipAddress, post.author.ipAddress),
                        accessibilityIdentifier: isMainPost
                            ? "thread-main-metadata"
                            : "thread-reply-metadata"
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
                .padding(.leading, isMainPost ? 0 : ThreadReplyLayout.bodyLeadingInset)
            }
        }
    }

    private var isThreadAuthor: Bool {
        guard let threadAuthorID else { return false }
        return threadAuthorID != 0 && threadAuthorID == post.author.id
    }
}

private enum UserNameCenterAlignment: AlignmentID {
    static func defaultValue(in context: ViewDimensions) -> CGFloat {
        context[VerticalAlignment.center]
    }
}

private extension VerticalAlignment {
    static let userNameCenter = VerticalAlignment(UserNameCenterAlignment.self)
}

struct UserHeaderView: View {
    let author: UserSummary
    let floor: Int?
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
        .alignmentGuide(.userNameCenter) { dimensions in
            dimensions[VerticalAlignment.center]
        }
    }

    private var regularLayout: some View {
        HStack(alignment: .userNameCenter, spacing: TiebaPureTheme.Spacing.sm) {
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
                .alignmentGuide(.userNameCenter) { dimensions in
                    dimensions[VerticalAlignment.center]
                }
            }

            Spacer(minLength: TiebaPureTheme.Spacing.sm)

            if let trailingLikeCount {
                CompactLikeCountView(count: trailingLikeCount)
                    .alignmentGuide(.userNameCenter) { dimensions in
                        dimensions[VerticalAlignment.center]
                    }
            }
        }
    }

    private var compactLayout: some View {
        HStack(alignment: .userNameCenter, spacing: TiebaPureTheme.Spacing.sm) {
            avatar
            VStack(alignment: .leading, spacing: TiebaPureTheme.Spacing.xxs) {
                Text(author.displayNameResolved)
                    .font((isMainPost ? Font.body : Font.callout).weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                    .alignmentGuide(.userNameCenter) { dimensions in
                        dimensions[VerticalAlignment.center]
                    }
                UserBadgesView(
                    author: author,
                    isThreadAuthor: isThreadAuthor,
                    floor: floor,
                    showsFloorBadge: showsFloorBadge
                )
            }

            Spacer(minLength: TiebaPureTheme.Spacing.xs)

            if let trailingLikeCount {
                CompactLikeCountView(count: trailingLikeCount)
                    .alignmentGuide(.userNameCenter) { dimensions in
                        dimensions[VerticalAlignment.center]
                    }
            }
        }
    }
}

enum ThreadReplyLayout {
    static let bodyLeadingInset = TiebaPureTheme.AvatarSize.medium + TiebaPureTheme.Spacing.sm
    static let headerContentSpacing: CGFloat = TiebaPureTheme.Spacing.xxs
    static let sectionSeparatorHeight: CGFloat = TiebaPureTheme.Spacing.xs
    static let previewTopPadding: CGFloat = TiebaPureTheme.Spacing.sm
    static let previewBottomPadding: CGFloat = TiebaPureTheme.Spacing.xxs
}

enum ThreadPostMetadataText {
    static func text(
        createdAt: Date?,
        ipAddress: String?,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> String {
        var items: [String] = []
        if let createdAt {
            items.append(ReaderDateText.threadMetadataString(from: createdAt, now: now, calendar: calendar))
        }
        if let location = normalizedLocation(ipAddress) {
            items.append(location)
        }
        return items.joined(separator: "  ")
    }

    static func firstLocation(_ candidates: String?...) -> String? {
        candidates.lazy.compactMap(normalizedLocation).first
    }

    static func normalizedLocation(_ value: String?) -> String? {
        guard var value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              value.isEmpty == false else {
            return nil
        }
        for prefix in ["IP属地：", "IP属地:", "来自"] where value.hasPrefix(prefix) {
            value.removeFirst(prefix.count)
            value = value.trimmingCharacters(in: .whitespacesAndNewlines)
            break
        }
        return value.isEmpty ? nil : value
    }
}

struct ThreadPostMetadataView: View {
    let createdAt: Date?
    let ipAddress: String?
    let accessibilityIdentifier: String

    var body: some View {
        let displayText = ThreadPostMetadataText.text(createdAt: createdAt, ipAddress: ipAddress)
        if displayText.isEmpty == false {
            Text(displayText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(accessibilityIdentifier)
                .accessibilityLabel(displayText)
        }
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
