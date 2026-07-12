import SwiftUI

struct SubpostPreviewView: View {
    let subposts: [Subpost]
    let totalCount: Int
    let threadAuthorID: Int64?
    let onOpenAll: (() -> Void)?

    init(
        subposts: [Subpost],
        totalCount: Int,
        threadAuthorID: Int64?,
        onOpenAll: (() -> Void)? = nil
    ) {
        self.subposts = Array(subposts.prefix(3))
        self.totalCount = totalCount
        self.threadAuthorID = threadAuthorID
        self.onOpenAll = onOpenAll
    }

    var body: some View {
        if subposts.isEmpty == false {
            VStack(alignment: .leading, spacing: TiebaPureTheme.Spacing.xs) {
                ForEach(subposts) { subpost in
                    SubpostInlineRow(subpost: subpost, threadAuthorID: threadAuthorID, lineLimit: 2)
                }

                if totalCount > subposts.count, let onOpenAll {
                    Button {
                        onOpenAll()
                    } label: {
                        HStack(spacing: 2) {
                            Text("查看全部 \(totalCount) 条回复")
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                        }
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 1)
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                    .minTouchTarget()
                    .accessibilityLabel("查看全部\(totalCount)条回复")
                }
            }
            .padding(.horizontal, TiebaPureTheme.Spacing.sm)
            .padding(.vertical, TiebaPureTheme.Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: TiebaPureTheme.Radius.media, style: .continuous)
                    .fill(TiebaPureTheme.ColorToken.readerTertiarySurface)
            )
        }
    }
}

struct SubpostInlineRow: View {
    let subpost: Subpost
    let threadAuthorID: Int64?
    var lineLimit: Int = 0

    var body: some View {
        InlineContentText(
            blocks: subpost.blocks,
            style: .subpost,
            lineLimit: lineLimit,
            prefixParts: SubpostInlinePrefix.parts(
                authorName: subpost.author.displayNameResolved,
                isThreadAuthor: isThreadAuthor
            )
        )
        .frame(maxWidth: .infinity, alignment: .leading)
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
