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
        TiebaImageSourcePolicy.urls(
            primary: image.thumbnailURL,
            fallback: image.originalURL
        ).first
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
        primaryURL = TiebaImageDownloadPolicy.preferredURL(
            original: image.originalURL,
            thumbnail: image.thumbnailURL
        )
        fallbackURL = TiebaURL.image(image.thumbnailURL?.absoluteString)
    }

    init(url: URL?, index: Int) {
        id = "\(index)-\(url?.absoluteString ?? "missing")"
        primaryURL = TiebaURL.image(url?.absoluteString)
        fallbackURL = nil
    }
}

struct FullScreenImageView: View {
    private let items: [FullScreenImageItem]
    private let saveAction: (URL) async throws -> Void
    @State private var currentIndex: Int
    @State private var isDownloading = false
    @State private var downloadTask: Task<Void, Never>?
    @State private var downloadNotice: ImageDownloadNotice?

    @Environment(\.dismiss) private var dismiss

    init(
        url: URL?,
        saveAction: @escaping (URL) async throws -> Void = FullScreenImageView.liveSave
    ) {
        let item = FullScreenImageItem(url: url, index: 0)
        items = [item]
        self.saveAction = saveAction
        _currentIndex = State(initialValue: 0)
    }

    init(session: ImagePreviewSession) {
        self.init(images: session.images, initialIndex: session.initialIndex)
    }

    init(
        images: [ImageContent],
        initialIndex: Int,
        saveAction: @escaping (URL) async throws -> Void = FullScreenImageView.liveSave
    ) {
        let resolvedItems = images.enumerated().map { index, image in
            FullScreenImageItem(image: image, index: index)
        }
        items = resolvedItems.isEmpty ? [FullScreenImageItem(url: nil, index: 0)] : resolvedItems
        self.saveAction = saveAction
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
                    .contentShape(Rectangle())
                    .onTapGesture {
                        dismiss()
                    }
                    .ignoresSafeArea()
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()
            .accessibilityIdentifier("full-screen-image-pager")

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

            VStack(spacing: 0) {
                Spacer(minLength: 0)
                bottomBar
            }
        }
        .accessibilityHint("轻点图片返回来源页面")
        .alert(item: $downloadNotice) { notice in
            Alert(
                title: Text(notice.title),
                message: Text(notice.message),
                dismissButton: .default(Text("好"))
            )
        }
        .onDisappear {
            downloadTask?.cancel()
            downloadTask = nil
        }
    }

    private var bottomBar: some View {
        HStack(spacing: TiebaPureTheme.Spacing.md) {
            if items.count > 1 {
                Text("\(currentIndex + 1) / \(items.count)")
                    .font(.footnote.monospacedDigit().weight(.semibold))
                    .accessibilityLabel("第\(currentIndex + 1)张，共\(items.count)张")
            }

            Spacer(minLength: 0)

            Button {
                saveCurrentImage()
            } label: {
                if isDownloading {
                    ProgressView()
                        .tint(.white)
                        .frame(width: 44, height: 44)
                } else {
                    Label("保存原图", systemImage: "arrow.down.to.line")
                        .font(.body.weight(.semibold))
                        .frame(minWidth: 44, minHeight: 44)
                }
            }
            .buttonStyle(.plain)
            .disabled(isDownloading || currentDownloadURL == nil)
            .accessibilityIdentifier("save-current-image")
            .accessibilityLabel(isDownloading ? "正在保存图片" : "保存原图")
            .accessibilityHint("下载当前原图并保存到系统照片")
        }
        .foregroundStyle(.white)
        .padding(.horizontal, TiebaPureTheme.Spacing.md)
        .padding(.top, TiebaPureTheme.Spacing.lg)
        .padding(.bottom, TiebaPureTheme.Spacing.sm)
        .background(
            LinearGradient(
                colors: [.clear, .black.opacity(0.72)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private var currentDownloadURL: URL? {
        guard items.indices.contains(currentIndex) else { return nil }
        return items[currentIndex].primaryURL
    }

    private func saveCurrentImage() {
        guard isDownloading == false, let url = currentDownloadURL else { return }
        downloadTask?.cancel()
        isDownloading = true
        downloadTask = Task { @MainActor in
            defer {
                isDownloading = false
                downloadTask = nil
            }
            do {
                try await saveAction(url)
                try Task.checkCancellation()
                downloadNotice = ImageDownloadNotice(
                    title: "图片已保存",
                    message: "原图已保存到系统照片。"
                )
            } catch is CancellationError {
                return
            } catch TiebaImageDownloadError.photoLibraryAccessDenied {
                downloadNotice = ImageDownloadNotice(
                    title: "无法保存图片",
                    message: "请在系统设置中允许 TiebaPure 添加照片后重试。"
                )
            } catch {
                downloadNotice = ImageDownloadNotice(
                    title: "图片保存失败",
                    message: "请检查网络或照片权限后重试。"
                )
            }
        }
    }

    private static func liveSave(url: URL) async throws {
        let payload = try await TiebaImageDownloadClient().download(from: url)
        try Task.checkCancellation()
        try await TiebaPhotoLibrarySaver.save(payload)
    }
}

private struct ImageDownloadNotice: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

#if DEBUG
struct ImageViewerUITestHost: View {
    @State private var isPresented = true

    var body: some View {
        Text("图片来源页")
            .accessibilityIdentifier("image-viewer-source")
            .fullScreenCover(isPresented: $isPresented) {
                FullScreenImageView(
                    url: URL(string: "https://fixture.invalid/viewer.png"),
                    saveAction: { _ in }
                )
            }
    }
}
#endif

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
