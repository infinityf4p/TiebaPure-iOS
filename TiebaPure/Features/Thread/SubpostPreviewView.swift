import SwiftUI

struct SubpostPreviewView: View {
    let subposts: [Subpost]
    let totalCount: Int
    let threadAuthorID: Int64?
    let onOpenAll: (() -> Void)?
    let onOpenUser: ((UserSummary) -> Void)?

    init(
        subposts: [Subpost],
        totalCount: Int,
        threadAuthorID: Int64?,
        onOpenAll: (() -> Void)? = nil,
        onOpenUser: ((UserSummary) -> Void)? = nil
    ) {
        self.subposts = Array(subposts.prefix(3))
        self.totalCount = totalCount
        self.threadAuthorID = threadAuthorID
        self.onOpenAll = onOpenAll
        self.onOpenUser = onOpenUser
    }

    var body: some View {
        if subposts.isEmpty == false {
            VStack(alignment: .leading, spacing: TiebaPureTheme.Spacing.xxs) {
                ForEach(subposts) { subpost in
                    SubpostInlineRow(
                        subpost: subpost,
                        threadAuthorID: threadAuthorID,
                        lineLimit: ThreadContentDisplayPolicy.detailLineLimit,
                        onOpenUser: onOpenUser.map { open in { open(subpost.author) } }
                    )
                }

                if totalCount > subposts.count, let onOpenAll {
                    Button {
                        onOpenAll()
                    } label: {
                        HStack(spacing: 2) {
                            Text("查看全部\(totalCount)条回复")
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                        }
                        .font(.footnote)
                        .foregroundStyle(TiebaPureTheme.ColorToken.primaryAccent)
                        .frame(
                            maxWidth: .infinity,
                            minHeight: SubpostPreviewLayout.openAllVisualMinHeight,
                            alignment: .leading
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .contentShape(
                        .interaction,
                        Rectangle().inset(by: -SubpostPreviewLayout.openAllHitExpansion)
                    )
                    .accessibilityLabel("查看全部\(totalCount)条回复")
                }
            }
            .padding(.horizontal, TiebaPureTheme.Spacing.sm)
            .padding(.top, ThreadReplyLayout.previewTopPadding)
            .padding(.bottom, ThreadReplyLayout.previewBottomPadding)
            .background(
                RoundedRectangle(cornerRadius: TiebaPureTheme.Radius.media, style: .continuous)
                    .fill(TiebaPureTheme.ColorToken.readerTertiarySurface)
            )
        }
    }
}

enum SubpostPreviewLayout {
    static let openAllVisualMinHeight: CGFloat = 30
    static let openAllHitHeight: CGFloat = 36
    static let openAllHitExpansion = (openAllHitHeight - openAllVisualMinHeight) / 2
}

struct SubpostInlineRow: View {
    let subpost: Subpost
    let threadAuthorID: Int64?
    var lineLimit: Int = ThreadContentDisplayPolicy.detailLineLimit
    var onOpenUser: (() -> Void)?

    var body: some View {
        InlineContentText(
            blocks: subpost.blocks,
            style: .subpost,
            lineLimit: lineLimit,
            prefixParts: SubpostInlinePrefix.parts(
                authorName: subpost.author.displayNameResolved,
                isThreadAuthor: isThreadAuthor
            ),
            allowsTextSelection: ThreadContentInteractionPolicy.allowsTextSelection(
                for: lineLimit
            ),
            accessibilityIdentifier: "thread-subpost-preview-text"
        )
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .topLeading) {
            if let onOpenUser {
                Button(action: onOpenUser) {
                    Text(subpost.author.displayNameResolved)
                        .font(.subheadline)
                        .foregroundStyle(.clear)
                        .fixedSize()
                        .frame(minHeight: 44, alignment: .top)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("查看用户\(subpost.author.displayNameResolved)的主页")
                .accessibilityHint("打开用户主页")
                .accessibilityIdentifier("thread-subpost-preview-user-\(subpost.author.id)")
            }
        }
    }

    private var isThreadAuthor: Bool {
        guard let threadAuthorID else { return false }
        return threadAuthorID != 0 && subpost.author.id == threadAuthorID
    }
}

enum SubpostInlinePrefix {
    static func parts(authorName: String, isThreadAuthor: Bool) -> [InlineContentText.PrefixPart] {
        guard isThreadAuthor else {
            return [.text("\(authorName): ")]
        }
        return [
            .text(authorName),
            .text(" "),
            .threadAuthorBadge,
            .text(": ")
        ]
    }
}
