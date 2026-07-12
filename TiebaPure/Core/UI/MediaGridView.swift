import SwiftUI

struct ReaderMediaItem: Identifiable, Equatable, Sendable {
    enum Kind: Sendable {
        case image
        case video
    }

    var id: String
    var kind: Kind
    var thumbnailURL: URL?
    var image: ImageContent?
    var video: VideoContent?
    var aspectRatio: CGFloat
    var accessibilityLabel: String

    init(
        id: String,
        kind: Kind,
        thumbnailURL: URL?,
        image: ImageContent? = nil,
        video: VideoContent? = nil,
        aspectRatio: CGFloat = 1,
        accessibilityLabel: String
    ) {
        self.id = id
        self.kind = kind
        self.thumbnailURL = thumbnailURL
        self.image = image
        self.video = video
        self.aspectRatio = max(0.5, min(aspectRatio, 2.0))
        self.accessibilityLabel = accessibilityLabel
    }
}

struct MediaGridView: View {
    let items: [ReaderMediaItem]
    let maxItemHeight: CGFloat?
    let totalItemCount: Int
    let usesTiebaLiteLayout: Bool
    let isInteractive: Bool
    let onTap: (ReaderMediaItem) -> Void

    init(
        items: [ReaderMediaItem],
        maxItemHeight: CGFloat? = nil,
        totalItemCount: Int? = nil,
        usesTiebaLiteLayout: Bool = false,
        isInteractive: Bool = true,
        onTap: @escaping (ReaderMediaItem) -> Void = { _ in }
    ) {
        self.items = items
        self.maxItemHeight = maxItemHeight
        self.totalItemCount = max(totalItemCount ?? items.count, items.count)
        self.usesTiebaLiteLayout = usesTiebaLiteLayout
        self.isInteractive = isInteractive
        self.onTap = onTap
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if usesTiebaLiteLayout {
                Color.clear
                    .frame(maxWidth: .infinity)
                    .aspectRatio(
                        TiebaLiteMediaLayoutPolicy.containerAspectRatio(totalCount: totalItemCount),
                        contentMode: .fit
                    )
                    .overlay {
                        HStack(spacing: TiebaPureTheme.Spacing.xs) {
                            ForEach(items) { item in
                                mediaButton(item)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            }
                        }
                    }
            } else {
                standardGrid
            }

            if TiebaLiteMediaLayoutPolicy.showsMoreBadge(
                totalCount: totalItemCount,
                visibleCount: items.count
            ) {
                Label("\(totalItemCount)", systemImage: "photo.on.rectangle")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(.black.opacity(0.55), in: Capsule())
                    .padding(TiebaPureTheme.Spacing.xs)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var standardGrid: some View {
        let columns = Array(
            repeating: GridItem(.flexible(), spacing: TiebaPureTheme.Spacing.xs),
            count: columnCount
        )
        return LazyVGrid(columns: columns, alignment: .leading, spacing: TiebaPureTheme.Spacing.xs) {
            ForEach(items) { item in
                mediaButton(item)
            }
        }
    }

    private func mediaButton(_ item: ReaderMediaItem) -> some View {
        Group {
            if isInteractive {
                MediaItemButton(
                    item: item,
                    maxHeight: usesTiebaLiteLayout ? nil : maxItemHeight,
                    aspectRatioOverride: usesTiebaLiteLayout ? nil : thumbnailAspectRatio,
                    fillsAvailableSpace: usesTiebaLiteLayout,
                    totalItemCount: totalItemCount,
                    onTap: onTap
                )
            } else {
                MediaThumbnailView(
                    item: item,
                    maxHeight: usesTiebaLiteLayout ? nil : maxItemHeight,
                    aspectRatioOverride: usesTiebaLiteLayout ? nil : thumbnailAspectRatio,
                    fillsAvailableSpace: usesTiebaLiteLayout,
                    retryTrigger: 0,
                    onLoadStateChange: { _ in }
                )
                .accessibilityHidden(true)
            }
        }
    }

    private var columnCount: Int {
        if usesTiebaLiteLayout {
            return max(1, items.count)
        }
        switch items.count {
        case 0, 1:
            return 1
        case 2, 4:
            return 2
        default:
            return 3
        }
    }

    private var thumbnailAspectRatio: CGFloat? {
        guard usesTiebaLiteLayout else { return nil }
        return TiebaLiteMediaLayoutPolicy.thumbnailAspectRatio(
            totalCount: totalItemCount,
            visibleCount: items.count
        )
    }
}

private struct MediaItemButton: View {
    let item: ReaderMediaItem
    let maxHeight: CGFloat?
    let aspectRatioOverride: CGFloat?
    let fillsAvailableSpace: Bool
    let totalItemCount: Int
    let onTap: (ReaderMediaItem) -> Void

    @State private var loadState: TiebaRemoteImageLoadState = .empty
    @State private var retryTrigger = 0

    var body: some View {
        Button {
            if loadState == .failure {
                retryTrigger += 1
            } else {
                onTap(item)
            }
        } label: {
            MediaThumbnailView(
                item: item,
                maxHeight: maxHeight,
                aspectRatioOverride: aspectRatioOverride,
                fillsAvailableSpace: fillsAvailableSpace,
                retryTrigger: retryTrigger,
                onLoadStateChange: { loadState = $0 }
            )
        }
        .buttonStyle(.plain)
        .minTouchTarget()
        .accessibilityLabel(loadState == .failure
            ? "\(item.accessibilityLabel)加载失败，重新加载，共\(totalItemCount)项媒体"
            : "\(item.accessibilityLabel)，共\(totalItemCount)项媒体")
        .accessibilityHint(loadState == .failure ? "重新请求当前媒体缩略图" : "打开媒体")
    }
}

private struct MediaThumbnailView: View {
    let item: ReaderMediaItem
    let maxHeight: CGFloat?
    let aspectRatioOverride: CGFloat?
    let fillsAvailableSpace: Bool
    let retryTrigger: Int
    let onLoadStateChange: (TiebaRemoteImageLoadState) -> Void

    var body: some View {
        Group {
            if fillsAvailableSpace {
                GeometryReader { proxy in
                    thumbnailContent
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                }
            } else {
                thumbnailContent
                    .aspectRatio(aspectRatioOverride ?? item.aspectRatio, contentMode: .fit)
                    .frame(maxHeight: maxHeight)
            }
        }
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: TiebaPureTheme.Radius.media, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: TiebaPureTheme.Radius.media, style: .continuous))
    }

    private var thumbnailContent: some View {
        ZStack {
            Rectangle()
                .fill(TiebaPureTheme.ColorToken.readerTertiarySurface)

            if let thumbnailURL = item.thumbnailURL {
                TiebaRemoteImage(
                    primaryURL: thumbnailURL,
                    fallbackURL: item.image?.originalURL,
                    contentMode: .fill,
                    retryTrigger: retryTrigger,
                    showsRetryButton: false,
                    onLoadStateChange: onLoadStateChange
                )
            } else {
                placeholder
            }

            if item.kind == .video {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: TiebaPureTheme.IconSize.play))
                    .foregroundStyle(.white)
                    .shadow(radius: 3)
                .accessibilityHidden(true)
            }
        }
    }

    private var placeholder: some View {
        Image(systemName: item.kind == .video ? "play.rectangle.fill" : "photo")
            .font(.system(size: 28))
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
    }
}

enum TiebaLiteMediaLayoutPolicy {
    static func visibleItemCount(totalCount: Int) -> Int {
        min(max(totalCount, 0), 3)
    }

    static func containerAspectRatio(totalCount: Int) -> CGFloat {
        totalCount <= 1 ? 2 : 3
    }

    static func containerHeight(containerWidth: CGFloat, totalCount: Int) -> CGFloat {
        containerWidth / containerAspectRatio(totalCount: totalCount)
    }

    static func thumbnailAspectRatio(totalCount: Int, visibleCount: Int) -> CGFloat {
        let visibleCount = max(visibleCount, 1)
        return containerAspectRatio(totalCount: totalCount) / CGFloat(visibleCount)
    }

    static func showsMoreBadge(totalCount: Int, visibleCount: Int) -> Bool {
        totalCount > visibleCount
    }
}
