import SwiftUI
import UIKit

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
                inlineImage
                .minTouchTarget()
                .onTapGesture {
                    activateInlineImage()
                }
                .accessibilityElement(children: .ignore)
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("thread-inline-image")
                .accessibilityLabel(inlineLoadState == .failure
                    ? "图片加载失败，重新加载"
                    : (isTallImage ? "查看长图原图" : "查看图片"))
                .accessibilityHint(inlineLoadState == .failure
                    ? "重新请求当前图片，不会打开全屏预览"
                    : "全屏显示完整图片")
                .accessibilityAction {
                    activateInlineImage()
                }
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

    private func activateInlineImage() {
        if inlineLoadState == .failure {
            inlineRetryTrigger += 1
        } else {
            previewSession = ImagePreviewSession(
                images: galleryImages,
                initialIndex: galleryIndex
            )
        }
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

private struct FullScreenZoomImageContent: View {
    let primaryURL: URL?
    let fallbackURL: URL?

    var body: some View {
        TiebaRemoteImage(
            primaryURL: primaryURL,
            fallbackURL: fallbackURL,
            contentMode: .fit,
            showsProgress: true
        )
        .tint(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }
}

private struct FullScreenZoomableRemoteImage: UIViewControllerRepresentable {
    let primaryURL: URL?
    let fallbackURL: URL?
    let imageIndex: Int
    let onSingleTap: () -> Void

    func makeUIViewController(context: Context) -> FullScreenZoomImageController {
        FullScreenZoomImageController(
            primaryURL: primaryURL,
            fallbackURL: fallbackURL,
            imageIndex: imageIndex,
            onSingleTap: onSingleTap
        )
    }

    func updateUIViewController(
        _ uiViewController: FullScreenZoomImageController,
        context: Context
    ) {
        uiViewController.onSingleTap = onSingleTap
        uiViewController.updateAccessibility(imageIndex: imageIndex)
    }

    static func dismantleUIViewController(
        _ uiViewController: FullScreenZoomImageController,
        coordinator: ()
    ) {
        uiViewController.onSingleTap = nil
    }
}

private final class FullScreenZoomImageController: UIViewController,
    UIScrollViewDelegate,
    UIGestureRecognizerDelegate {
    private let scrollView = UIScrollView()
    private let accessibilityProxy = UIView()
    private let imageHost: UIHostingController<FullScreenZoomImageContent>
    private var imageIndex: Int
    private var lastViewportSize: CGSize = .zero

    var onSingleTap: (() -> Void)?

    init(
        primaryURL: URL?,
        fallbackURL: URL?,
        imageIndex: Int,
        onSingleTap: @escaping () -> Void
    ) {
        imageHost = UIHostingController(
            rootView: FullScreenZoomImageContent(
                primaryURL: primaryURL,
                fallbackURL: fallbackURL
            )
        )
        self.imageIndex = imageIndex
        self.onSingleTap = onSingleTap
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let rootView = UIView()
        rootView.backgroundColor = .black
        view = rootView

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.backgroundColor = .black
        scrollView.delegate = self
        scrollView.minimumZoomScale = FullScreenImageZoomPolicy.minimumScale
        scrollView.maximumZoomScale = FullScreenImageZoomPolicy.maximumScale
        scrollView.bounces = true
        scrollView.bouncesZoom = true
        scrollView.alwaysBounceHorizontal = false
        scrollView.alwaysBounceVertical = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.decelerationRate = .fast
        scrollView.panGestureRecognizer.isEnabled = false
        rootView.addSubview(scrollView)

        addChild(imageHost)
        imageHost.view.translatesAutoresizingMaskIntoConstraints = false
        imageHost.view.backgroundColor = .clear
        scrollView.addSubview(imageHost.view)
        imageHost.didMove(toParent: self)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: rootView.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),
            imageHost.view.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            imageHost.view.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            imageHost.view.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            imageHost.view.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            imageHost.view.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            imageHost.view.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor)
        ])

        accessibilityProxy.translatesAutoresizingMaskIntoConstraints = false
        accessibilityProxy.backgroundColor = .clear
        accessibilityProxy.isUserInteractionEnabled = false
        accessibilityProxy.isAccessibilityElement = true
        rootView.addSubview(accessibilityProxy)
        NSLayoutConstraint.activate([
            accessibilityProxy.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            accessibilityProxy.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            accessibilityProxy.topAnchor.constraint(equalTo: rootView.topAnchor),
            accessibilityProxy.bottomAnchor.constraint(equalTo: rootView.bottomAnchor)
        ])

        let singleTap = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap))
        singleTap.cancelsTouchesInView = false
        singleTap.delegate = self

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        doubleTap.cancelsTouchesInView = false
        doubleTap.delegate = self
        singleTap.require(toFail: doubleTap)

        scrollView.addGestureRecognizer(singleTap)
        scrollView.addGestureRecognizer(doubleTap)
        configureAccessibility()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let viewportSize = scrollView.bounds.size
        if lastViewportSize != .zero,
           viewportSize != .zero,
           viewportSize != lastViewportSize,
           FullScreenImageZoomPolicy.isZoomed(scrollView.zoomScale) {
            scrollView.setZoomScale(FullScreenImageZoomPolicy.minimumScale, animated: false)
        }
        lastViewportSize = viewportSize
        centerZoomedContent()
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        imageHost.view
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        updateZoomState()
    }

    func scrollViewDidEndZooming(
        _ scrollView: UIScrollView,
        with view: UIView?,
        atScale scale: CGFloat
    ) {
        let normalizedScale = FullScreenImageZoomPolicy.normalizedScale(scale)
        if normalizedScale != scale {
            scrollView.setZoomScale(normalizedScale, animated: false)
        }
        updateZoomState()
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldReceive touch: UITouch
    ) -> Bool {
        var candidate = touch.view
        while let view = candidate {
            if view is UIControl {
                return false
            }
            candidate = view.superview
        }
        return true
    }

    func updateAccessibility(imageIndex: Int) {
        self.imageIndex = imageIndex
        configureAccessibility()
    }

    @objc private func handleSingleTap() {
        onSingleTap?()
    }

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        let targetScale = FullScreenImageZoomPolicy.doubleTapTarget(
            currentScale: scrollView.zoomScale
        )
        if targetScale == FullScreenImageZoomPolicy.minimumScale {
            scrollView.setZoomScale(targetScale, animated: true)
            return
        }

        let location = gesture.location(in: imageHost.view)
        zoom(to: targetScale, centeredAt: location, animated: true)
    }

    private func zoom(to scale: CGFloat, centeredAt location: CGPoint, animated: Bool) {
        let targetScale = FullScreenImageZoomPolicy.clampedScale(scale)
        let viewportSize = scrollView.bounds.size
        guard viewportSize.width > 0, viewportSize.height > 0 else {
            scrollView.setZoomScale(targetScale, animated: animated)
            return
        }
        let zoomSize = CGSize(
            width: viewportSize.width / targetScale,
            height: viewportSize.height / targetScale
        )
        let zoomRect = CGRect(
            x: location.x - zoomSize.width / 2,
            y: location.y - zoomSize.height / 2,
            width: zoomSize.width,
            height: zoomSize.height
        )
        scrollView.zoom(to: zoomRect, animated: animated)
    }

    private func updateZoomState() {
        scrollView.panGestureRecognizer.isEnabled = FullScreenImageZoomPolicy.isZoomed(
            scrollView.zoomScale
        )
        centerZoomedContent()
        updateAccessibilityValue()
    }

    private func centerZoomedContent() {
        let horizontalInset = max(
            (scrollView.bounds.width - scrollView.contentSize.width) / 2,
            0
        )
        let verticalInset = max(
            (scrollView.bounds.height - scrollView.contentSize.height) / 2,
            0
        )
        scrollView.contentInset = UIEdgeInsets(
            top: verticalInset,
            left: horizontalInset,
            bottom: verticalInset,
            right: horizontalInset
        )
    }

    private func configureAccessibility() {
        accessibilityProxy.accessibilityIdentifier = "full-screen-image-zoom-surface-\(imageIndex)"
        accessibilityProxy.accessibilityLabel = "全屏图片"
        accessibilityProxy.accessibilityTraits = [.image]
        accessibilityProxy.accessibilityCustomActions = [
            UIAccessibilityCustomAction(name: "放大图片") { [weak self] _ in
                guard let self else { return false }
                let scale = min(
                    self.scrollView.zoomScale * 2,
                    FullScreenImageZoomPolicy.maximumScale
                )
                let center = CGPoint(
                    x: self.imageHost.view.bounds.midX,
                    y: self.imageHost.view.bounds.midY
                )
                self.zoom(to: scale, centeredAt: center, animated: true)
                return true
            },
            UIAccessibilityCustomAction(name: "缩小图片") { [weak self] _ in
                guard let self else { return false }
                self.scrollView.setZoomScale(
                    FullScreenImageZoomPolicy.minimumScale,
                    animated: true
                )
                return true
            }
        ]
        updateAccessibilityValue()
    }

    private func updateAccessibilityValue() {
        let percentage = Int((scrollView.zoomScale * 100).rounded())
        accessibilityProxy.accessibilityValue = "缩放 \(percentage)%"
        accessibilityProxy.accessibilityHint = FullScreenImageZoomPolicy.isZoomed(scrollView.zoomScale)
            ? "单指拖动查看图片，双指捏合或双击缩小"
            : "双指捏合或双击放大，轻点返回来源页面"
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
                    FullScreenZoomableRemoteImage(
                        primaryURL: item.primaryURL,
                        fallbackURL: item.fallbackURL,
                        imageIndex: index,
                        onSingleTap: { dismiss() }
                    )
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
        .accessibilityHint("双指捏合或双击缩放，轻点图片返回来源页面")
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
                    url: URL(string: "https://fixture-success.invalid/viewer.png"),
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

enum FullScreenImageZoomPolicy {
    static let minimumScale: CGFloat = 1
    static let maximumScale: CGFloat = 4
    static let doubleTapScale: CGFloat = 2
    private static let minimumZoomDelta: CGFloat = 0.01

    static func clampedScale(_ scale: CGFloat) -> CGFloat {
        min(max(scale, minimumScale), maximumScale)
    }

    static func normalizedScale(_ scale: CGFloat) -> CGFloat {
        let clamped = clampedScale(scale)
        return clamped <= minimumScale + minimumZoomDelta ? minimumScale : clamped
    }

    static func isZoomed(_ scale: CGFloat) -> Bool {
        normalizedScale(scale) > minimumScale
    }

    static func doubleTapTarget(currentScale: CGFloat) -> CGFloat {
        isZoomed(currentScale) ? minimumScale : doubleTapScale
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
