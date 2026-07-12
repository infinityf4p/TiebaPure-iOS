import SwiftUI

struct ImageViewer: View {
    let image: ImageContent
    let galleryImages: [ImageContent]
    let galleryIndex: Int

    @State private var previewSession: ImagePreviewSession?
    @State private var inlineLoadState: TiebaRemoteImageLoadState = .empty
    @State private var inlineRetryTrigger = 0

    init(
        image: ImageContent,
        galleryImages: [ImageContent]? = nil,
        galleryIndex: Int = 0
    ) {
        self.image = image
        self.galleryImages = galleryImages ?? [image]
        self.galleryIndex = galleryIndex
    }

    var body: some View {
        Group {
            if previewURL != nil {
                Button {
                    if inlineLoadState == .failure {
                        inlineRetryTrigger += 1
                    } else {
                        previewSession = ImagePreviewSession(
                            images: galleryImages,
                            initialIndex: galleryIndex
                        )
                    }
                } label: {
                    inlineImage
                }
                .buttonStyle(.plain)
                .minTouchTarget()
                .accessibilityLabel(inlineLoadState == .failure
                    ? "图片加载失败，重新加载"
                    : (isTallImage ? "查看长图原图" : "查看图片"))
                .accessibilityHint(inlineLoadState == .failure
                    ? "重新请求当前图片，不会打开全屏预览"
                    : "全屏显示完整图片")
            } else {
                imagePlaceholder
                    .accessibilityLabel("图片不可用")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fullScreenCover(item: $previewSession) { session in
            FullScreenImageView(session: session)
        }
    }

    private var previewURL: URL? {
        image.thumbnailURL ?? image.originalURL
    }

    private var inlineAspectRatio: CGFloat {
        TiebaLiteInlineImageLayoutPolicy.displayAspectRatio(for: image)
    }

    private var isTallImage: Bool {
        TiebaLiteInlineImageLayoutPolicy.isTall(image)
    }

    private var inlineImage: some View {
        Color.clear
        .aspectRatio(inlineAspectRatio, contentMode: .fit)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay {
            ZStack {
                RoundedRectangle(cornerRadius: TiebaPureTheme.Radius.media, style: .continuous)
                    .fill(TiebaPureTheme.ColorToken.readerTertiarySurface)

                TiebaRemoteImage(
                    primaryURL: image.thumbnailURL ?? image.originalURL,
                    fallbackURL: image.originalURL,
                    contentMode: .fill,
                    showsProgress: true,
                    retryTrigger: inlineRetryTrigger,
                    showsRetryButton: false,
                    onLoadStateChange: { inlineLoadState = $0 }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if isTallImage {
                    Text("查看原图")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(.black.opacity(0.62), in: Capsule())
                        .padding(TiebaPureTheme.Spacing.xs)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
        }
        .frame(maxHeight: TiebaLiteInlineImageLayoutPolicy.maximumInlineHeight)
        .clipShape(RoundedRectangle(cornerRadius: TiebaPureTheme.Radius.media, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: TiebaPureTheme.Radius.media, style: .continuous))
        .clipped()
    }

    private var imagePlaceholder: some View {
        Color.clear
        .aspectRatio(inlineAspectRatio, contentMode: .fit)
        .frame(maxHeight: TiebaLiteInlineImageLayoutPolicy.maximumInlineHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay {
            ZStack {
                RoundedRectangle(cornerRadius: TiebaPureTheme.Radius.media, style: .continuous)
                    .fill(TiebaPureTheme.ColorToken.readerTertiarySurface)

                Image(systemName: "photo")
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: TiebaPureTheme.Radius.media, style: .continuous))
        .clipped()
    }
}

enum TiebaLiteInlineImageLayoutPolicy {
    static let maximumInlineHeight: CGFloat = 600
    static let minimumDisplayAspectRatio: CGFloat = 2.0 / 3.0

    static func aspectRatio(for image: ImageContent) -> CGFloat {
        guard image.width > 0, image.height > 0 else { return 1 }
        return CGFloat(image.width) / CGFloat(image.height)
    }

    static func displayAspectRatio(for image: ImageContent) -> CGFloat {
        max(aspectRatio(for: image), minimumDisplayAspectRatio)
    }

    static func isTall(_ image: ImageContent) -> Bool {
        aspectRatio(for: image) < minimumDisplayAspectRatio || image.showOriginalButton
    }

    static func height(containerWidth: CGFloat, image: ImageContent) -> CGFloat {
        let aspectRatio = displayAspectRatio(for: image)
        guard aspectRatio > 0 else { return containerWidth }
        return min(containerWidth / aspectRatio, containerWidth * 1.5, maximumInlineHeight)
    }
}

struct ImagePreviewSession: Identifiable {
    let id = UUID()
    let images: [ImageContent]
    let initialIndex: Int

    init(images: [ImageContent], initialIndex: Int) {
        self.images = images
        self.initialIndex = ImagePreviewIndexPolicy.clampedIndex(
            initialIndex,
            totalCount: images.count
        )
    }
}

private struct FullScreenImageItem: Identifiable, Equatable {
    let id: String
    let primaryURL: URL?
    let fallbackURL: URL?

    init(image: ImageContent, index: Int) {
        id = "\(index)-\(image.originalURL?.absoluteString ?? image.thumbnailURL?.absoluteString ?? "missing")"
        primaryURL = image.originalURL ?? image.thumbnailURL
        fallbackURL = image.thumbnailURL
    }

    init(url: URL?, index: Int) {
        id = "\(index)-\(url?.absoluteString ?? "missing")"
        primaryURL = url
        fallbackURL = nil
    }
}

struct FullScreenImageView: View {
    private let items: [FullScreenImageItem]
    @State private var currentIndex: Int

    @Environment(\.dismiss) private var dismiss

    init(url: URL?) {
        let item = FullScreenImageItem(url: url, index: 0)
        items = [item]
        _currentIndex = State(initialValue: 0)
    }

    init(session: ImagePreviewSession) {
        self.init(images: session.images, initialIndex: session.initialIndex)
    }

    init(images: [ImageContent], initialIndex: Int) {
        let resolvedItems = images.enumerated().map { index, image in
            FullScreenImageItem(image: image, index: index)
        }
        items = resolvedItems.isEmpty ? [FullScreenImageItem(url: nil, index: 0)] : resolvedItems
        _currentIndex = State(initialValue: ImagePreviewIndexPolicy.clampedIndex(
            initialIndex,
            totalCount: resolvedItems.count
        ))
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black
                .ignoresSafeArea()

            TabView(selection: $currentIndex) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    GeometryReader { proxy in
                        TiebaRemoteImage(
                            primaryURL: item.primaryURL,
                            fallbackURL: item.fallbackURL,
                            contentMode: .fit,
                            showsProgress: true
                        )
                        .tint(.white)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                    }
                    .ignoresSafeArea()
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: TiebaPureTheme.IconSize.toolbar, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.black.opacity(0.45), in: Circle())
            }
            .accessibilityLabel("关闭图片")
            .padding(TiebaPureTheme.Spacing.md)

            if items.count > 1 {
                Text("\(currentIndex + 1) / \(items.count)")
                    .font(.footnote.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.45), in: Capsule())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, TiebaPureTheme.Spacing.lg)
                    .accessibilityLabel("第\(currentIndex + 1)张，共\(items.count)张")
            }
        }
    }
}

enum ImagePreviewIndexPolicy {
    static func clampedIndex(_ index: Int, totalCount: Int) -> Int {
        guard totalCount > 0 else { return 0 }
        return min(max(index, 0), totalCount - 1)
    }
}

enum FullScreenImageSwipeAction: Equatable {
    case previous
    case next
    case none
}

enum FullScreenImageSwipePolicy {
    static func action(for translation: CGSize, currentIndex: Int, totalCount: Int) -> FullScreenImageSwipeAction {
        let horizontal = translation.width
        let vertical = abs(translation.height)
        guard totalCount > 1, abs(horizontal) > 80, abs(horizontal) > vertical * 1.4 else {
            return .none
        }
        if horizontal < 0 {
            return currentIndex < totalCount - 1 ? .next : .none
        }
        return currentIndex > 0 ? .previous : .none
    }
}
