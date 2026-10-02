import SwiftUI

struct PostRowView: View {
    @Environment(\.readingPreferences) private var readingPreferences

    let post: Post
    let threadTitle: String?
    let threadAuthorID: Int64?
    let isMainPost: Bool
    let onOpenSubposts: ((Post) -> Void)?
    let onOpenUser: ((UserSummary) -> Void)?
    let onOpenTiebaRoute: ((ExternalRoute) -> Void)?
    let isLikeUpdating: Bool
    let onToggleLike: (() -> Void)?
    let onReply: (() -> Void)?

    init(
        post: Post,
        threadTitle: String? = nil,
        threadAuthorID: Int64? = nil,
        isMainPost: Bool = false,
        onOpenSubposts: ((Post) -> Void)? = nil,
        onOpenUser: ((UserSummary) -> Void)? = nil,
        onOpenTiebaRoute: ((ExternalRoute) -> Void)? = nil,
        isLikeUpdating: Bool = false,
        onToggleLike: (() -> Void)? = nil,
        onReply: (() -> Void)? = nil
    ) {
        self.post = post
        self.threadTitle = threadTitle
        self.threadAuthorID = threadAuthorID
        self.isMainPost = isMainPost
        self.onOpenSubposts = onOpenSubposts
        self.onOpenUser = onOpenUser
        self.onOpenTiebaRoute = onOpenTiebaRoute
        self.isLikeUpdating = isLikeUpdating
        self.onToggleLike = onToggleLike
        self.onReply = onReply
    }

    var body: some View {
        let metadataPlacement = ThreadPostMetadataPlacement.resolve(
            isMainPost: isMainPost,
            hasPreviewSubposts: post.previewSubposts.isEmpty == false
        )
        ReaderCard(
            showsDivider: isMainPost == false,
            contentBottomPadding: metadataPlacement.cardBottomPadding
        ) {
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
                    trailingLikeCount: post.likeCount,
                    isLiked: post.isLiked,
                    isLikeUpdating: isLikeUpdating,
                    onToggleLike: onToggleLike,
                    likeAccessibilityIdentifier: isMainPost
                        ? "thread-main-like-button"
                        : "thread-like-button-\(post.id)",
                    onOpenUser: onOpenUser.map { open in { open(post.author) } }
                )

                VStack(alignment: .leading, spacing: ThreadReplyLayout.bodyStackSpacing) {
                    if isMainPost, let threadTitle, threadTitle.isEmpty == false {
                        InlineContentText(
                            blocks: [.text(threadTitle)],
                            style: .title,
                            lineLimit: ThreadContentDisplayPolicy.detailLineLimit,
                            readerFontSize: readingPreferences.fontSize,
                            readerFontFamily: readingPreferences.fontFamily,
                            readerLineSpacing: readingPreferences.lineSpacing,
                            allowsLinkInteraction: false,
                            allowsTextSelection: true,
                            accessibilityIdentifier: "thread-main-title"
                        )
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.bottom, TiebaPureTheme.Spacing.sm)
                    }

                    ContentBlocksView(
                        blocks: post.blocks,
                        textStyle: isMainPost ? .body : .reply,
                        lineLimit: ThreadContentDisplayPolicy.detailLineLimit,
                        readerFontSize: readingPreferences.fontSize,
                        readerFontFamily: readingPreferences.fontFamily,
                        readerLineSpacing: readingPreferences.lineSpacing,
                        inlineAccessibilityIdentifier: isMainPost
                            ? "thread-main-text"
                            : "thread-reply-text",
                        onOpenTiebaRoute: onOpenTiebaRoute,
                        onPlainTextTap: onReply
                    )

                    ThreadPostMetadataView(
                        createdAt: post.createdAt,
                        ipAddress: ThreadPostMetadataText.firstLocation(post.ipAddress, post.author.ipAddress),
                        accessibilityIdentifier: isMainPost
                            ? "thread-main-metadata"
                            : "thread-reply-metadata",
                        replyAccessibilityLabel: "回复第\(post.floor)楼",
                        replyAccessibilityIdentifier: "thread-reply-button-\(post.id)",
                        onReply: onReply,
                        placement: metadataPlacement
                    )

                    if post.previewSubposts.isEmpty == false {
                        SubpostPreviewView(
                            subposts: post.previewSubposts,
                            totalCount: post.subpostCount,
                            threadAuthorID: threadAuthorID,
                            onOpenAll: onOpenSubposts.map { open in { open(post) } },
                            onOpenUser: onOpenUser,
                            onOpenTiebaRoute: onOpenTiebaRoute
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

extension PostRowView: Equatable {
    static func == (lhs: PostRowView, rhs: PostRowView) -> Bool {
        lhs.post == rhs.post
            && lhs.threadTitle == rhs.threadTitle
            && lhs.threadAuthorID == rhs.threadAuthorID
            && lhs.isMainPost == rhs.isMainPost
            && lhs.isLikeUpdating == rhs.isLikeUpdating
            && (lhs.onOpenSubposts != nil) == (rhs.onOpenSubposts != nil)
            && (lhs.onOpenUser != nil) == (rhs.onOpenUser != nil)
            && (lhs.onOpenTiebaRoute != nil) == (rhs.onOpenTiebaRoute != nil)
            && (lhs.onToggleLike != nil) == (rhs.onToggleLike != nil)
            && (lhs.onReply != nil) == (rhs.onReply != nil)
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
    var nameTone: UserHeaderNameTone = .primary
    var showsFloorBadge = true
    var trailingLikeCount: Int?
    var isLiked = false
    var isLikeUpdating = false
    var onToggleLike: (() -> Void)?
    var likeAccessibilityIdentifier: String?
    var onOpenUser: (() -> Void)?

    var body: some View {
        HStack(alignment: .userNameCenter, spacing: TiebaPureTheme.Spacing.xs) {
            userIdentity
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(0)

            trailingLikeControl
                .alignmentGuide(.userNameCenter) { dimensions in
                    dimensions[VerticalAlignment.center]
                }
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var avatar: some View {
        AvatarView(
            url: author.portraitURL,
            title: author.displayNameResolved,
            size: ThreadAuthorIdentityLayout.avatarSize(isMainPost: isMainPost)
        )
        .alignmentGuide(.userNameCenter) { dimensions in
            dimensions[VerticalAlignment.center]
        }
    }

    @ViewBuilder
    private var trailingLikeControl: some View {
        if let trailingLikeCount {
            if let onToggleLike {
                Button(action: onToggleLike) {
                    HStack(spacing: TiebaPureTheme.Spacing.xxs) {
                        if isLikeUpdating {
                            ProgressView()
                                .controlSize(.small)
                                .accessibilityHidden(true)
                        } else {
                            Image(systemName: isLiked ? "hand.thumbsup.fill" : "hand.thumbsup")
                                .font(.system(size: TiebaPureTheme.IconSize.inline, weight: .medium))
                                .accessibilityHidden(true)
                        }
                        Text(CompactInteractionCountText.string(for: trailingLikeCount))
                            .font(.subheadline)
                            .monospacedDigit()
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    .foregroundStyle(isLiked ? Color.accentColor : Color.secondary)
                    .frame(minWidth: 44, minHeight: 44, alignment: .trailing)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isLikeUpdating)
                .accessibilityLabel(isLiked ? "取消点赞" : "点赞")
                .accessibilityValue("当前\(trailingLikeCount)个赞")
                .accessibilityHint(isLikeUpdating ? "正在提交" : "双击切换点赞状态")
                .accessibilityIdentifier(likeAccessibilityIdentifier ?? "thread-like-button")
            } else {
                CompactLikeCountView(count: trailingLikeCount)
                    .frame(minWidth: 44, minHeight: 44, alignment: .trailing)
                    .accessibilityIdentifier(likeAccessibilityIdentifier ?? "thread-like-count")
            }
        }
    }

    @ViewBuilder
    private var userIdentity: some View {
        let content = HStack(alignment: .userNameCenter, spacing: TiebaPureTheme.Spacing.sm) {
            avatar
            HStack(alignment: .center, spacing: TiebaPureTheme.Spacing.xs) {
                Text(author.displayNameResolved)
                    .font((isMainPost ? Font.callout : Font.subheadline).weight(.semibold))
                    .foregroundStyle(nameTone.foregroundColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .minimumScaleFactor(0.85)
                    .layoutPriority(0)
                    .accessibilityIdentifier(
                        isMainPost ? "thread-main-user-name" : "thread-user-name-\(author.id)"
                    )

                UserBadgesView(
                    author: author,
                    isThreadAuthor: isThreadAuthor,
                    floor: floor,
                    showsFloorBadge: showsFloorBadge
                )
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .alignmentGuide(.userNameCenter) { dimensions in
                dimensions[VerticalAlignment.center]
            }
        }

        if let onOpenUser {
            Button(action: onOpenUser) {
                content
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
            .accessibilityLabel("查看用户\(author.displayNameResolved)的主页")
            .accessibilityValue(nameTone.accessibilityValue)
            .accessibilityHint("打开用户主页")
            .accessibilityIdentifier(isMainPost ? "thread-main-user-button" : "thread-user-button-\(author.id)")
        } else {
            content
        }
    }
}

enum UserHeaderNameTone: String {
    case primary
    case secondary

    var foregroundColor: Color {
        switch self {
        case .primary:
            return .primary
        case .secondary:
            return .secondary
        }
    }

    var accessibilityValue: String {
        switch self {
        case .primary:
            return "普通用户名"
        case .secondary:
            return "灰色用户名"
        }
    }
}

enum ThreadAuthorIdentityLayout {
    static let replyAvatarSize: CGFloat = 36

    static func avatarSize(isMainPost: Bool) -> CGFloat {
        isMainPost ? TiebaPureTheme.AvatarSize.medium : replyAvatarSize
    }
}

enum ThreadReplyLayout {
    static let bodyLeadingInset = ThreadAuthorIdentityLayout.replyAvatarSize + TiebaPureTheme.Spacing.sm
    static let headerContentSpacing: CGFloat = TiebaPureTheme.Spacing.xxs
    static let bodyStackSpacing: CGFloat = 0
    static let metadataHitHeight: CGFloat = 44
    static let sectionSeparatorHeight: CGFloat = TiebaPureTheme.Spacing.xs
    static let previewTopPadding: CGFloat = TiebaPureTheme.Spacing.sm
    static let previewBottomPadding: CGFloat = TiebaPureTheme.Spacing.xxs
}

enum ThreadPostMetadataPlacement: Equatable {
    case mainPost
    case standaloneReply
    case beforeSubpostPreview

    static func resolve(isMainPost: Bool, hasPreviewSubposts: Bool) -> ThreadPostMetadataPlacement {
        if isMainPost { return .mainPost }
        return hasPreviewSubposts ? .beforeSubpostPreview : .standaloneReply
    }

    var visualHeight: CGFloat {
        self == .mainPost ? 28 : 20
    }

    var topSpacing: CGFloat {
        switch self {
        case .mainPost:
            return TiebaPureTheme.Spacing.xxs
        case .standaloneReply, .beforeSubpostPreview:
            return 6
        }
    }

    var bottomSpacing: CGFloat {
        self == .beforeSubpostPreview ? 6 : 0
    }

    var totalVerticalSpace: CGFloat {
        topSpacing + visualHeight + bottomSpacing
    }

    var hitExpansion: CGFloat {
        max((ThreadReplyLayout.metadataHitHeight - visualHeight) / 2, 0)
    }

    var cardBottomPadding: CGFloat {
        self == .standaloneReply ? topSpacing : TiebaPureTheme.Spacing.sm
    }

    var totalSpaceToFollowingContent: CGFloat {
        totalVerticalSpace + (self == .standaloneReply ? cardBottomPadding : 0)
    }
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
    var replyAccessibilityLabel: String? = nil
    var replyAccessibilityIdentifier: String? = nil
    var onReply: (() -> Void)? = nil
    var placement: ThreadPostMetadataPlacement = .standaloneReply

    var body: some View {
        let displayText = ThreadPostMetadataText.text(createdAt: createdAt, ipAddress: ipAddress)
        if displayText.isEmpty == false || onReply != nil {
            HStack(alignment: .center, spacing: TiebaPureTheme.Spacing.sm) {
                if displayText.isEmpty == false {
                    Text(displayText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .layoutPriority(1)
                        .accessibilityIdentifier(accessibilityIdentifier)
                        .accessibilityLabel(displayText)
                }

                Spacer(minLength: TiebaPureTheme.Spacing.xs)

                if let onReply {
                    Button(action: onReply) {
                        Label("回复", systemImage: "bubble.left")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .frame(
                                minWidth: 56,
                                minHeight: placement.visualHeight,
                                alignment: .trailing
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .contentShape(
                        .interaction,
                        Rectangle().inset(by: -placement.hitExpansion)
                    )
                    .accessibilityLabel(replyAccessibilityLabel ?? "回复")
                    .accessibilityHint("打开回复编辑器")
                    .accessibilityIdentifier(replyAccessibilityIdentifier ?? "thread-reply-button")
                }
            }
            .frame(
                maxWidth: .infinity,
                minHeight: placement.visualHeight,
                alignment: .leading
            )
            .padding(.top, placement.topSpacing)
            .padding(.bottom, placement.bottomSpacing)
        }
    }
}

struct UserBadgesView: View {
    let author: UserSummary
    let isThreadAuthor: Bool
    var floor: Int?
    var showsFloorBadge = false

    var body: some View {
        HStack(spacing: TiebaPureTheme.Spacing.xxs) {
            badges
        }
        .dynamicTypeSize(.xSmall ... .xxxLarge)
    }

    @ViewBuilder
    private var badges: some View {
        if let level = author.level, level > 0 {
            let levelText = UserLevelBadgeLayout.text(
                level: level,
                levelName: author.levelName
            )
            Text(levelText)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(UserLevelBadgeLayout.maximumLineCount)
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(1)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.orange.opacity(0.18))
                )
                .accessibilityIdentifier("thread-user-level-badge-\(author.id)")
                .accessibilityLabel("贴吧等级\(levelText)")
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
            ThreadAuthorBadge(accessibilityIdentifier: "thread-author-badge-\(author.id)")
        }
    }
}

enum UserLevelBadgeLayout {
    static let maximumLineCount = 1

    static func text(level: Int, levelName: String?) -> String {
        let normalizedName = levelName?
            .components(separatedBy: .newlines)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return normalizedName.isEmpty ? "Lv.\(level)" : "\(level) \(normalizedName)"
    }
}

struct ThreadAuthorBadge: View {
    var accessibilityIdentifier: String? = nil

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
            .accessibilityIdentifier(accessibilityIdentifier ?? "thread-author-badge")
    }
}
