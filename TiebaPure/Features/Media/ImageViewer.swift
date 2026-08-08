import SwiftUI
import UIKit
import Combine

struct ImageViewer: View {
    @Environment(\.readingPreferences) private var readingPreferences
    @Environment(\.displayScale) private var displayScale

    let image: ImageContent
    let galleryImages: [ImageContent]
    let galleryIndex: Int

    @State private var inlineLoadState: TiebaRemoteImageLoadState = .empty
    @State private var inlineRetryTrigger = 0
    @State private var manualLoadAuthorization: String?
    @State private var explicitFallbackAuthorization: String?
    @StateObject private var previewSource: ImagePreviewSourceAnchor
    private let previewSourceIdentity: String

    init(
        image: ImageContent,
        galleryImages: [ImageContent]? = nil,
        galleryIndex: Int = 0
    ) {
        self.image = image
        self.galleryImages = galleryImages ?? [image]
        self.galleryIndex = galleryIndex
        let identity = Self.sourceIdentity(for: image)
        previewSourceIdentity = identity
        _previewSource = StateObject(
            wrappedValue: ImagePreviewSourceAnchor(sourceIdentity: identity)
        )
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
                .accessibilityLabel(inlineAccessibilityLabel)
                .accessibilityHint(inlineAccessibilityHint)
                .accessibilityAction {
                    activateInlineImage()
                }
            } else {
                imagePlaceholder
                    .accessibilityLabel("图片不可用")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var previewURL: URL? {
        TiebaImageSourcePolicy.urls(
            primary: image.thumbnailURL,
            fallback: image.originalURL
        ).first
    }

    private var inlineAspectRatio: CGFloat {
        InlineImageLayoutPolicy.displayAspectRatio(for: image)
    }

    private var isTallImage: Bool {
        InlineImageLayoutPolicy.isTall(image)
    }

    private func activateInlineImage() {
        if inlineLoadState == .failure {
            if shouldOfferExplicitFallback {
                explicitFallbackAuthorization = previewSourceIdentity
            }
            inlineRetryTrigger += 1
        } else if inlineLoadState == .empty,
                  mediaRequestPolicy.loadsAutomatically == false {
            manualLoadAuthorization = previewSourceIdentity
            return
        } else if inlineLoadState == .loading,
                  ReaderMediaActivationPolicy.blocksWhileLoading(
                    requestPolicy: mediaRequestPolicy
                  ) {
            return
        } else {
            ImagePreviewCoordinator.shared.present(
                ImagePreviewSession(
                    images: galleryImages,
                    initialIndex: galleryIndex,
                    sourceFrame: ImagePreviewSourceRegistry.shared
                        .frameInWindow(for: previewSourceIdentity)
                        ?? previewSource.frameInWindow,
                    sourceImage: previewSource.image,
                    sourceAnchor: previewSource,
                    sourceIdentity: previewSourceIdentity,
                    prefetchesAdjacentPages: readingPreferences.mediaLoading != .manual
                )
            )
        }
    }

    private var inlineImage: some View {
        Color.clear
        .aspectRatio(inlineAspectRatio, contentMode: .fit)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay {
            GeometryReader { proxy in
                ZStack {
                RoundedRectangle(cornerRadius: TiebaPureTheme.Radius.media, style: .continuous)
                    .fill(TiebaPureTheme.ColorToken.readerTertiarySurface)

                TiebaRemoteImage(
                    primaryURL: imageRequestSources.primaryURL,
                    fallbackURL: imageRequestSources.fallbackURL,
                    targetPixelSize: TiebaImageDecodePolicy.previewTargetPixelSize(
                        for: proxy.size,
                        displayScale: displayScale
                    ),
                    contentMode: .fill,
                    showsProgress: true,
                    retryTrigger: inlineRetryTrigger,
                    showsRetryButton: false,
                    showsResolvedImage: false,
                    loadsAutomatically: isManualLoadAuthorized,
                    onLoadStateChange: {
                        inlineLoadState = $0
                        if $0 != .success {
                            previewSource.clearImage(
                                sourceIdentity: previewSourceIdentity
                            )
                        }
                    },
                    onImageResolved: {
                        previewSource.store(
                            image: $0,
                            sourceIdentity: previewSourceIdentity
                        )
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if mediaRequestPolicy.loadsAutomatically == false,
                   inlineLoadState == .empty {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 30, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                        .background(.regularMaterial, in: Circle())
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }

                // This is the sole visible thumbnail and the canonical source
                // registered with the app-owned transition scene. Keeping one
                // bitmap owner prevents a transition copy from drifting inside
                // the cell when the feed resumes scrolling after dismissal.
                ImagePreviewSourceAnchorReader(
                    anchor: previewSource,
                    sourceIdentity: previewSourceIdentity,
                    onTransitionTap: activateInlineImage
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)

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
        }
        .frame(maxHeight: InlineImageLayoutPolicy.maximumInlineHeight)
        .clipShape(RoundedRectangle(cornerRadius: TiebaPureTheme.Radius.media, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: TiebaPureTheme.Radius.media, style: .continuous))
        .clipped()
    }

    private var imagePlaceholder: some View {
        Color.clear
        .aspectRatio(inlineAspectRatio, contentMode: .fit)
        .frame(maxHeight: InlineImageLayoutPolicy.maximumInlineHeight)
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

    private static func sourceIdentity(for image: ImageContent) -> String {
        [
            image.thumbnailURL?.absoluteString ?? "",
            image.originalURL?.absoluteString ?? "",
            String(image.width),
            String(image.height)
        ].joined(separator: "|")
    }

    private var mediaRequestPolicy: ReaderMediaRequestPolicy {
        ReaderMediaRequestPolicy.resolve(readingPreferences.mediaLoading)
    }

    private var isManualLoadAuthorized: Bool {
        mediaRequestPolicy.allowsLoading(
            sourceIdentity: previewSourceIdentity,
            manualAuthorization: manualLoadAuthorization
        )
    }

    private var allowsExplicitFallback: Bool {
        mediaRequestPolicy.allowsFallback(
            sourceIdentity: previewSourceIdentity,
            explicitAuthorization: explicitFallbackAuthorization
        )
    }

    private var imageRequestSources: ReaderImageRequestSources {
        ReaderImageRequestSourcePolicy.resolve(
            previewURL: image.thumbnailURL,
            originalURL: image.originalURL,
            requestPolicy: mediaRequestPolicy,
            sourceIdentity: previewSourceIdentity,
            explicitOriginalAuthorization: explicitFallbackAuthorization
        )
    }

    private var shouldOfferExplicitFallback: Bool {
        guard readingPreferences.mediaLoading == .dataSaving,
              allowsExplicitFallback == false,
              let originalURL = image.originalURL else {
            return false
        }
        return originalURL != image.thumbnailURL
    }

    private var inlineAccessibilityLabel: String {
        switch inlineLoadState {
        case .empty where mediaRequestPolicy.loadsAutomatically == false:
            return "加载图片"
        case .loading:
            return "正在加载图片"
        case .failure:
            return shouldOfferExplicitFallback
                ? "图片预览加载失败，加载原图"
                : "图片加载失败，重新加载"
        case .empty, .success:
            return isTallImage ? "查看长图原图" : "查看图片"
        }
    }

    private var inlineAccessibilityHint: String {
        switch inlineLoadState {
        case .empty where mediaRequestPolicy.loadsAutomatically == false:
            return "加载当前图片预览"
        case .loading:
            return "请等待图片加载完成"
        case .failure:
            return shouldOfferExplicitFallback
                ? "明确请求当前图片原图"
                : "重新请求当前图片，不会打开全屏预览"
        case .empty, .success:
            return "全屏显示完整图片"
        }
    }
}

enum InlineImageLayoutPolicy {
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
    let sourceFrame: CGRect?
    let sourceImage: UIImage?
    let sourceAnchor: ImagePreviewSourceAnchor?
    let sourceToken: ImagePreviewSourceToken?
    /// Stable content identity of the originating thumbnail. The transition
    /// resolves the live source view through this, never through a cached
    /// view reference, so cell recycling cannot redirect it to another post.
    let sourceIdentity: String?
    let prefetchesAdjacentPages: Bool

    @MainActor
    init(
        images: [ImageContent],
        initialIndex: Int,
        sourceFrame: CGRect? = nil,
        sourceImage: UIImage? = nil,
        sourceAnchor: ImagePreviewSourceAnchor? = nil,
        sourceIdentity: String? = nil,
        prefetchesAdjacentPages: Bool = true
    ) {
        self.images = images
        self.initialIndex = ImagePreviewIndexPolicy.clampedIndex(
            initialIndex,
            totalCount: images.count
        )
        self.sourceFrame = ImagePreviewTransitionGeometry.validSourceFrame(sourceFrame)
        self.sourceImage = sourceImage
        self.sourceAnchor = sourceAnchor
        sourceToken = sourceAnchor?.transitionToken
        self.sourceIdentity = sourceIdentity ?? sourceAnchor?.sourceIdentity
        self.prefetchesAdjacentPages = prefetchesAdjacentPages
    }
}

/// Identity-keyed registry of the thumbnails that are currently on screen.
///
/// A lazy feed destroys, recreates and recycles its cells while a preview is
/// open, so a transition may not hold a reference to any particular cell view:
/// by dismissal time that view can be gone, moved, or reused by another post.
/// Cells register themselves under a stable content identity and the
/// transition resolves the *current* owner of that identity on demand. When
/// nobody owns it, the transition degrades to a cross dissolve instead of
/// flying into a stale rectangle.
@MainActor
final class ImagePreviewSourceRegistry {
    static let shared = ImagePreviewSourceRegistry()

    private struct Entry {
        weak var view: ImagePreviewSourceView?
    }

    private struct SuppressedEntry {
        weak var view: ImagePreviewSourceView?
        let wasHidden: Bool
    }

    private var entries: [String: [Entry]] = [:]
    private var suppressionCounts: [String: Int] = [:]
    private var suppressedEntries: [String: [ObjectIdentifier: SuppressedEntry]] = [:]
    private init() {}

    func register(_ view: ImagePreviewSourceView, identity: String) {
        guard identity.isEmpty == false else { return }
        var live = (entries[identity] ?? []).filter { $0.view != nil && $0.view !== view }
        live.append(Entry(view: view))
        entries[identity] = live
        if isSuppressed(identity) {
            suppress(view, identity: identity)
        }
    }

    func unregister(_ view: ImagePreviewSourceView, identity: String) {
        guard identity.isEmpty == false else { return }
        restore(view, identity: identity)
        let live = (entries[identity] ?? []).filter { $0.view != nil && $0.view !== view }
        if live.isEmpty {
            entries[identity] = nil
        } else {
            entries[identity] = live
        }
    }

    /// Keeps every live owner of one content identity hidden while the app-owned
    /// hero proxy is visible. Lazy stacks may dismantle and recreate a cell in
    /// the middle of a transition; newly registered owners are suppressed too,
    /// so a remount cannot reintroduce a second thumbnail below the proxy.
    func beginSuppression(identity: String, including view: ImagePreviewSourceView) {
        guard identity.isEmpty == false else { return }
        suppressionCounts[identity, default: 0] += 1
        let live = (entries[identity] ?? []).compactMap(\.view)
        for candidate in live where candidate !== view {
            suppress(candidate, identity: identity)
        }
        suppress(view, identity: identity)
    }

    func endSuppression(identity: String) {
        guard identity.isEmpty == false,
              let count = suppressionCounts[identity] else {
            return
        }
        if count > 1 {
            suppressionCounts[identity] = count - 1
            return
        }
        suppressionCounts[identity] = nil
        let suppressed = suppressedEntries.removeValue(forKey: identity) ?? [:]
        UIView.performWithoutAnimation {
            for entry in suppressed.values {
                entry.view?.isHidden = entry.wasHidden
            }
        }
    }

    private func isSuppressed(_ identity: String) -> Bool {
        (suppressionCounts[identity] ?? 0) > 0
    }

    private func suppress(_ view: ImagePreviewSourceView, identity: String) {
        let identifier = ObjectIdentifier(view)
        if suppressedEntries[identity]?[identifier] == nil {
            suppressedEntries[identity, default: [:]][identifier] = SuppressedEntry(
                view: view,
                wasHidden: view.isHidden
            )
        }
        UIView.performWithoutAnimation {
            view.isHidden = true
        }
    }

    private func restore(_ view: ImagePreviewSourceView, identity: String) {
        let identifier = ObjectIdentifier(view)
        guard let entry = suppressedEntries[identity]?.removeValue(forKey: identifier) else {
            return
        }
        UIView.performWithoutAnimation {
            view.isHidden = entry.wasHidden
        }
        if suppressedEntries[identity]?.isEmpty == true {
            suppressedEntries[identity] = nil
        }
    }

    /// The thumbnail that currently represents `identity` and is genuinely
    /// visible. Resolved fresh on every call — never cached across the
    /// preview's lifetime.
    func liveView(for identity: String?) -> ImagePreviewSourceView? {
        guard let identity, identity.isEmpty == false else { return nil }
        let live = (entries[identity] ?? []).filter { $0.view != nil }
        entries[identity] = live.isEmpty ? nil : live
        // Later registrations win: that is the most recently attached cell.
        for entry in live.reversed() {
            guard let view = entry.view,
                  let window = view.window,
                  view.image != nil,
                  view.isHidden == false,
                  view.alpha > 0.01,
                  view.bounds.width >= 2,
                  view.bounds.height >= 2 else {
                continue
            }
            guard ImagePreviewTransitionGeometry.fullyVisibleFrame(
                of: view,
                in: window
            ) != nil else {
                continue
            }
            return view
        }
        return nil
    }

    func frameInWindow(for identity: String?) -> CGRect? {
        guard let view = liveView(for: identity), let window = view.window else { return nil }
        return ImagePreviewTransitionGeometry.validSourceFrame(
            view.convert(view.bounds, to: window)
        )
    }

    /// Replays the first thumbnail tap delivered immediately after the
    /// previous full-screen viewer has completed dismissal. UIKit freezes
    /// input during its modal transition; at completion the source hierarchy
    /// is restored, but SwiftUI can still miss that first button action.
    ///
    /// Resolving through live registered source views keeps this independent
    /// of SwiftUI's recycled button hierarchy and prevents a cached cell from
    /// opening the wrong image.
    @discardableResult
    func activateSource(at point: CGPoint, in window: UIWindow) -> Bool {
        var candidates: [(view: ImagePreviewSourceView, frame: CGRect)] = []
        var cleanedEntries: [String: [Entry]] = [:]

        for (identity, registeredEntries) in entries {
            let live = registeredEntries.filter { $0.view != nil }
            if live.isEmpty == false {
                cleanedEntries[identity] = live
            }

            for entry in live.reversed() {
                guard let view = entry.view,
                      view.window === window,
                      view.image != nil,
                      view.isHidden == false,
                      view.alpha > 0.01,
                      let frame = ImagePreviewTransitionGeometry.fullyVisibleFrame(
                          of: view,
                          in: window
                      ),
                      frame.contains(point),
                      view.canActivateDuringTransition else {
                    continue
                }
                candidates.append((view, frame))
            }
        }
        entries = cleanedEntries

        // Media cells do not normally overlap, but picking the smallest hit
        // frame makes the result deterministic if a compact thumbnail sits
        // inside a larger tappable image container.
        guard let target = candidates.min(by: {
            ($0.frame.width * $0.frame.height) < ($1.frame.width * $1.frame.height)
        }) else {
            return false
        }
        return target.view.activateDuringTransition()
    }
}

@MainActor
final class ImagePreviewSourceAnchor: ObservableObject {
    weak var view: ImagePreviewSourceView?
    private(set) var sourceIdentity: String
    private(set) var sourceGeneration = UUID()
    private(set) var image: UIImage?

    init(sourceIdentity: String = "") {
        self.sourceIdentity = sourceIdentity
    }

    var frameInWindow: CGRect? {
        guard let view, let window = view.window, view.bounds.isEmpty == false else { return nil }
        return ImagePreviewTransitionGeometry.fullyVisibleFrame(
            of: view,
            in: window
        )
    }

    var transitionToken: ImagePreviewSourceToken {
        ImagePreviewSourceToken(
            sourceIdentity: sourceIdentity,
            generation: sourceGeneration
        )
    }

    func store(image: UIImage, sourceIdentity: String) {
        bind(to: sourceIdentity)
        if self.image !== image {
            self.image = image
        }
        if view?.image !== image {
            view?.image = image
        }
    }

    func clearImage(sourceIdentity: String) {
        guard self.sourceIdentity == sourceIdentity else { return }
        image = nil
        view?.image = nil
    }

    func prepareForReuse(sourceIdentity: String) {
        bind(to: sourceIdentity)
    }

#if DEBUG
    func visibleImageObservation(
        token: ImagePreviewSourceToken?
    ) -> (view: UIView, imageIdentifier: ObjectIdentifier)? {
        guard token == transitionToken,
              let view,
              let image = view.image,
              view.window != nil,
              view.bounds.width >= 2,
              view.bounds.height >= 2 else {
            return nil
        }
        return (view, ObjectIdentifier(image))
    }
#endif

    func attach(_ view: ImagePreviewSourceView, sourceIdentity: String) {
        bind(to: sourceIdentity)
        if self.view !== view {
            self.view?.image = nil
            self.view = view
        }
        if view.image !== image {
            view.image = image
        }
    }

    func detach(_ view: ImagePreviewSourceView, sourceIdentity: String) {
        guard self.sourceIdentity == sourceIdentity, self.view === view else {
            return
        }
        self.view = nil
    }

    func transitionSourceView(token: ImagePreviewSourceToken?) -> UIView? {
        guard token == transitionToken,
              let view,
              let window = view.window,
              view.image != nil,
              view.isHidden == false,
              view.alpha > 0.01,
              view.bounds.width >= 2,
              view.bounds.height >= 2 else {
            return nil
        }
        guard ImagePreviewTransitionGeometry.fullyVisibleFrame(
            of: view,
            in: window
        ) != nil else {
            return nil
        }
        return view
    }

    func transitionSourceFrame(token: ImagePreviewSourceToken?) -> CGRect? {
        guard transitionSourceView(token: token) != nil else { return nil }
        return frameInWindow
    }

    private func bind(to identity: String) {
        guard sourceIdentity != identity else { return }
        view?.image = nil
        view = nil
        image = nil
        sourceIdentity = identity
        sourceGeneration = UUID()
    }
}

struct ImagePreviewSourceToken: Equatable {
    let sourceIdentity: String
    let generation: UUID
}

@MainActor
enum ImagePreviewSourceResolver {
    static func view(
        exactAnchor: ImagePreviewSourceAnchor?,
        token: ImagePreviewSourceToken?,
        sourceIdentity: String?
    ) -> UIView? {
        if let exactSource = exactAnchor?.transitionSourceView(token: token) {
            return exactSource
        }
        return ImagePreviewSourceRegistry.shared.liveView(for: sourceIdentity)
    }

    static func frameInWindow(
        exactAnchor: ImagePreviewSourceAnchor?,
        token: ImagePreviewSourceToken?,
        sourceIdentity: String?
    ) -> CGRect? {
        if let exactFrame = exactAnchor?.transitionSourceFrame(token: token) {
            return exactFrame
        }
        guard let sourceView = ImagePreviewSourceRegistry.shared.liveView(for: sourceIdentity),
              let window = sourceView.window else {
            return nil
        }
        return ImagePreviewTransitionGeometry.validSourceFrame(
            sourceView.convert(sourceView.bounds, to: window)
        )
    }
}

struct ImagePreviewSourceAnchorReader: UIViewRepresentable {
    let anchor: ImagePreviewSourceAnchor
    let sourceIdentity: String
    var onTransitionTap: (() -> Void)? = nil

    func makeUIView(context: Context) -> ImagePreviewSourceView {
        let view = ImagePreviewSourceView()
        view.onTransitionTap = onTransitionTap
        anchor.attach(view, sourceIdentity: sourceIdentity)
        ImagePreviewSourceRegistry.shared.register(view, identity: sourceIdentity)
        context.coordinator.registeredIdentity = sourceIdentity
        return view
    }

    func updateUIView(_ uiView: ImagePreviewSourceView, context: Context) {
        context.coordinator.update(
            uiView,
            anchor: anchor,
            sourceIdentity: sourceIdentity,
            onTransitionTap: onTransitionTap
        )
    }

    static func dismantleUIView(_ uiView: ImagePreviewSourceView, coordinator: Coordinator) {
        uiView.onTransitionTap = nil
        guard let identity = coordinator.registeredIdentity else { return }
        coordinator.anchor?.detach(uiView, sourceIdentity: identity)
        ImagePreviewSourceRegistry.shared.unregister(uiView, identity: identity)
        coordinator.registeredIdentity = nil
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(anchor: anchor)
    }

    @MainActor
    final class Coordinator {
        weak var anchor: ImagePreviewSourceAnchor?
        var registeredIdentity: String?

        init(anchor: ImagePreviewSourceAnchor) {
            self.anchor = anchor
        }

        func update(
            _ uiView: ImagePreviewSourceView,
            anchor: ImagePreviewSourceAnchor,
            sourceIdentity: String,
            onTransitionTap: (() -> Void)?
        ) {
            // A recycled cell keeps its UIView but can be handed a different post's
            // image, so the registry entry has to follow the new identity.
            let previousIdentity = registeredIdentity
            let anchorChanged = self.anchor !== anchor
            let identityChanged = previousIdentity != sourceIdentity

            if anchorChanged {
                if let previousIdentity {
                    self.anchor?.detach(
                        uiView,
                        sourceIdentity: previousIdentity
                    )
                }
                self.anchor = anchor
            }

            if identityChanged {
                if let previousIdentity {
                    ImagePreviewSourceRegistry.shared.unregister(
                        uiView,
                        identity: previousIdentity
                    )
                }
                registeredIdentity = sourceIdentity
            }
            uiView.onTransitionTap = onTransitionTap
            if anchorChanged || identityChanged || anchor.view !== uiView {
                anchor.attach(uiView, sourceIdentity: sourceIdentity)
            }
            if identityChanged {
                ImagePreviewSourceRegistry.shared.register(uiView, identity: sourceIdentity)
            }
        }
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiView: ImagePreviewSourceView,
        context: Context
    ) -> CGSize? {
        guard let width = proposal.width,
              let height = proposal.height,
              width.isFinite,
              height.isFinite,
              width > 0,
              height > 0 else {
            return nil
        }
        return CGSize(width: width, height: height)
    }
}

@MainActor
final class ImagePreviewSourceView: UIImageView {
    var onTransitionTap: (() -> Void)?

    var canActivateDuringTransition: Bool {
        onTransitionTap != nil
    }

    @discardableResult
    func activateDuringTransition() -> Bool {
        guard let onTransitionTap else { return false }
        onTransitionTap()
        return true
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: UIView.noIntrinsicMetric)
    }

    init() {
        super.init(frame: .zero)
        backgroundColor = .clear
        contentMode = .scaleAspectFill
        clipsToBounds = true
        isUserInteractionEnabled = false
        accessibilityElementsHidden = true
        layer.cornerCurve = .continuous
        layer.cornerRadius = TiebaPureTheme.Radius.media
        layer.allowsEdgeAntialiasing = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

#if DEBUG
/// Verifies the custom hero transition's ownership contract, then drives the
/// real feed in the first runloop after transition cleanup. XCUITest waits for
/// application quiescence and cannot independently prove that the temporary
/// bitmap was removed before the source page became scrollable.
@MainActor
final class ImageDismissScrollRaceProbe: NSObject {
    static let shared = ImageDismissScrollRaceProbe()

    private static let argument = "UITEST_IMAGE_DISMISS_SCROLL_RACE"
    private static let visualHoldArgument = "UITEST_IMAGE_DISMISS_SCROLL_RACE_VISUAL_HOLD"
    private weak var sourceView: ImagePreviewSourceView?
    private weak var visibleImageView: UIView?
    private weak var sourceAnchor: ImagePreviewSourceAnchor?
    private weak var scrollView: UIScrollView?
    private weak var window: UIWindow?
    private weak var openingSourceSuperview: UIView?
    private var sourceToken: ImagePreviewSourceToken?
    private var visibleImageIdentifier: ObjectIdentifier?
    private var sessionID: UUID?
    private var openingFrameInSuperview = CGRect.zero
    private var openingVisibleFrameInSource = CGRect.zero
    private var openingBoundsOrigin = CGPoint.zero
    private var openingSourceAlpha: CGFloat = 1
    private var openingSourceHidden = false
    private var openingSourceTransform = CGAffineTransform.identity
    private var openingSourceLayerTransform = CATransform3DIdentity
    private var openingSourceLayerOpacity: Float = 1
    private var displayLink: CADisplayLink?
    private var dismissalStart: CFTimeInterval?
    private var dismissalFinish: CFTimeInterval?
    private var scrollStart: CFTimeInterval?
    private var firstScroll: CFTimeInterval?
    private var cycle = 0
    private var sampleCountBeforeFinish = 0
    private var maxModelError: CGFloat = 0
    private var maxPostFinishPresentationError: CGFloat = 0
    private var maxVisibleModelError: CGFloat = 0
    private var maxVisiblePresentationError: CGFloat = 0
    private var visiblePresentationSamples = 0
    private var maxSourceContentsRectError: CGFloat = 0
    private var sourcePresentationSamples = 0
    private var maxBitmapSourceCount = 0
    private var bitmapSourceSamples = 0
    private var visibleImageStayedBound = true
    private var sourceHadBitmap = false
    private var maxHeroProxyCount = 0
    private var heroProxySamples = 0
    private var sourceVisibleWhileProxy = false
    private var scrollBeforeProxyCleanup = false
    private var proxyCountAtFirstScroll = -1
    private var sourceVisibleAtFirstScroll = false
    private var resultLabel: UILabel?

    private var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains(Self.argument)
    }

    func prepare(session: ImagePreviewSession) {
        guard isEnabled else { return }
        stopSampling()
        guard let sourceView = ImagePreviewSourceResolver.view(
            exactAnchor: session.sourceAnchor,
            token: session.sourceToken,
            sourceIdentity: session.sourceIdentity
        ) as? ImagePreviewSourceView,
        let visibleObservation = session.sourceAnchor?.visibleImageObservation(
            token: session.sourceToken
        ),
        let window = sourceView.window,
        visibleObservation.view.window === window,
        let scrollView = Self.ancestorScrollView(of: sourceView) else {
            publish("completed=1;error=missing-visible-source")
            return
        }

        cycle += 1
        self.sourceView = sourceView
        visibleImageView = visibleObservation.view
        sourceAnchor = session.sourceAnchor
        self.scrollView = scrollView
        self.window = window
        openingSourceSuperview = sourceView.superview
        sourceToken = session.sourceToken
        visibleImageIdentifier = visibleObservation.imageIdentifier
        sessionID = session.id
        openingFrameInSuperview = sourceView.frame
        openingVisibleFrameInSource = visibleObservation.view.convert(
            visibleObservation.view.bounds,
            to: sourceView
        )
        openingBoundsOrigin = scrollView.bounds.origin
        openingSourceAlpha = sourceView.alpha
        openingSourceHidden = sourceView.isHidden
        openingSourceTransform = sourceView.transform
        openingSourceLayerTransform = sourceView.layer.transform
        openingSourceLayerOpacity = sourceView.layer.opacity
        dismissalStart = nil
        dismissalFinish = nil
        scrollStart = nil
        firstScroll = nil
        sampleCountBeforeFinish = 0
        maxModelError = 0
        maxPostFinishPresentationError = 0
        maxVisibleModelError = 0
        maxVisiblePresentationError = 0
        visiblePresentationSamples = 0
        maxSourceContentsRectError = 0
        sourcePresentationSamples = 0
        maxBitmapSourceCount = 0
        bitmapSourceSamples = 0
        visibleImageStayedBound = true
        sourceHadBitmap = sourceView.image != nil
        maxHeroProxyCount = 0
        heroProxySamples = 0
        sourceVisibleWhileProxy = false
        scrollBeforeProxyCleanup = false
        proxyCountAtFirstScroll = -1
        sourceVisibleAtFirstScroll = false
        installResultLabel(in: window)
        publish("cycle=\(cycle);completed=0;prepared=1")
    }

    func dismissalDidBegin(sessionID: UUID) {
        guard isEnabled, self.sessionID == sessionID, displayLink == nil else { return }
        let start = CACurrentMediaTime()
        dismissalStart = start
        let displayLink = CADisplayLink(target: self, selector: #selector(sampleFrame(_:)))
        let maximumFramesPerSecond = Float(UIScreen.main.maximumFramesPerSecond)
        displayLink.preferredFrameRateRange = CAFrameRateRange(
            minimum: min(60, maximumFramesPerSecond),
            maximum: maximumFramesPerSecond,
            preferred: maximumFramesPerSecond
        )
        self.displayLink = displayLink
        displayLink.add(to: .main, forMode: .common)
    }

    func dismissalDidFinish(sessionID: UUID) {
        guard isEnabled, self.sessionID == sessionID else { return }
        let finish = CACurrentMediaTime()
        dismissalFinish = finish
        // `dismissalDidFinish` is published only after the custom animator has
        // removed its proxy and restored the stable source in a committed
        // transaction. This is the first safe point at which the feed may
        // actually change contentOffset.
        beginScroll(at: finish)
    }

    @objc private func sampleFrame(_ displayLink: CADisplayLink) {
        guard let dismissalStart,
              let sourceView,
              let visibleImageView,
              let scrollView else {
            complete(error: "lost-source")
            return
        }

        let now = CACurrentMediaTime()
        let elapsed = now - dismissalStart
        let heroProxyCount = ImagePreviewHeroProxyView.activeCount
        maxHeroProxyCount = max(maxHeroProxyCount, heroProxyCount)
        if heroProxyCount > 0 {
            heroProxySamples += 1
            sourceVisibleWhileProxy = sourceVisibleWhileProxy
                || sourceView.isHidden == false
            scrollBeforeProxyCleanup = scrollBeforeProxyCleanup
                || abs(scrollView.bounds.origin.y - openingBoundsOrigin.y) >= 0.5
        }
        if scrollStart != nil,
           firstScroll == nil,
           abs(scrollView.bounds.origin.y - openingBoundsOrigin.y) >= 1 {
            // This timestamp is recorded only after reading an actually changed
            // UIScrollView offset, rather than copying the planned start time.
            firstScroll = now
            proxyCountAtFirstScroll = heroProxyCount
            sourceVisibleAtFirstScroll = sourceView.isHidden == false
        }
        if let scrollStart {
            let maximumY = max(
                -scrollView.adjustedContentInset.top,
                scrollView.contentSize.height
                    - scrollView.bounds.height
                    + scrollView.adjustedContentInset.bottom
            )
            let targetY = min(openingBoundsOrigin.y + 120, maximumY)
            let progress = min(max((now - scrollStart) / 0.12, 0), 1)
            let interpolatedY = openingBoundsOrigin.y
                + (targetY - openingBoundsOrigin.y) * CGFloat(progress)
            let nextY = min(targetY, max(openingBoundsOrigin.y + 2, interpolatedY))
            if abs(nextY - scrollView.bounds.origin.y) > 0.1 {
                scrollView.setContentOffset(
                    CGPoint(x: openingBoundsOrigin.x, y: nextY),
                    animated: false
                )
            }
        }

        // Measure the source relative to its immediate card/container. Window-space
        // presentation coordinates intentionally lag while the entire scroll view
        // commits a new contentOffset; that is not a thumbnail alignment defect.
        let modelFrame = sourceView.frame
        maxModelError = max(
            maxModelError,
            Self.maximumFrameDelta(modelFrame, openingFrameInSuperview)
        )

        let visibleModelFrame = visibleImageView.convert(
            visibleImageView.bounds,
            to: sourceView
        )
        maxVisibleModelError = max(
            maxVisibleModelError,
            Self.maximumFrameDelta(visibleModelFrame, openingVisibleFrameInSource)
        )
        if let observation = sourceAnchor?.visibleImageObservation(token: sourceToken) {
            visibleImageStayedBound = visibleImageStayedBound
                && observation.view === visibleImageView
                && observation.imageIdentifier == visibleImageIdentifier
        } else {
            visibleImageStayedBound = false
        }

        if dismissalFinish == nil {
            sampleCountBeforeFinish += 1
        } else if
            let presentation = sourceView.layer.presentation(),
            let superPresentation = sourceView.superview?.layer.presentation()
        {
            let presentationFrame = presentation.convert(
                presentation.bounds,
                to: superPresentation
            )
            maxPostFinishPresentationError = max(
                maxPostFinishPresentationError,
                Self.maximumFrameDelta(presentationFrame, openingFrameInSuperview)
            )
        }

        if dismissalFinish != nil {
            if let visiblePresentation = visibleImageView.layer.presentation(),
               let sourcePresentation = sourceView.layer.presentation() {
                let visibleFrameInSource = visiblePresentation.convert(
                    visiblePresentation.bounds,
                    to: sourcePresentation
                )
                visiblePresentationSamples += 1
                maxVisiblePresentationError = max(
                    maxVisiblePresentationError,
                    Self.maximumFrameDelta(
                        visibleFrameInSource,
                        openingVisibleFrameInSource
                    )
                )
            }
        }

        if let sourcePresentation = sourceView.layer.presentation() {
            sourcePresentationSamples += 1
            maxSourceContentsRectError = max(
                maxSourceContentsRectError,
                Self.maximumFrameDelta(
                    sourcePresentation.contentsRect,
                    sourceView.layer.contentsRect
                )
            )
        }
        bitmapSourceSamples += 1
        maxBitmapSourceCount = max(
            maxBitmapSourceCount,
            Self.countBitmapImageViews(in: sourceView)
        )

        if let dismissalFinish, now - dismissalFinish >= 0.18 {
            complete(error: nil)
        // Leave enough time for a loaded simulator to run the custom animator
        // and collect post-cleanup samples without reporting a false timeout.
        } else if elapsed >= 2.0 {
            complete(error: "timeout")
        }
    }

    private func complete(error: String?) {
        let firstScrollMilliseconds: Int
        if let dismissalStart, let firstScroll {
            firstScrollMilliseconds = Int(((firstScroll - dismissalStart) * 1_000).rounded())
        } else {
            firstScrollMilliseconds = -1
        }
        let firstScrollAfterFinishMilliseconds: Int
        if let dismissalFinish, let firstScroll {
            firstScrollAfterFinishMilliseconds = Int(
                ((firstScroll - dismissalFinish) * 1_000).rounded()
            )
        } else {
            firstScrollAfterFinishMilliseconds = -1
        }
        let scrollDelta = Int((abs(
            (scrollView?.bounds.origin.y ?? openingBoundsOrigin.y) - openingBoundsOrigin.y
        ) * 1_000).rounded())
        let sourceRestored: Bool
        if let sourceView,
           let image = sourceView.image,
           let visibleImageIdentifier {
            sourceRestored = sourceView.superview === openingSourceSuperview
                && ObjectIdentifier(image) == visibleImageIdentifier
                && sourceView.isHidden == openingSourceHidden
                && abs(sourceView.alpha - openingSourceAlpha) <= 0.001
                && sourceView.transform == openingSourceTransform
                && CATransform3DEqualToTransform(
                    sourceView.layer.transform,
                    openingSourceLayerTransform
                )
                && abs(sourceView.layer.opacity - openingSourceLayerOpacity) <= 0.001
        } else {
            sourceRestored = false
        }
        var components = [
            "cycle=\(cycle)",
            "completed=1",
            "firstScrollMs=\(firstScrollMilliseconds)",
            "firstScrollAfterFinishMs=\(firstScrollAfterFinishMilliseconds)",
            "scrollDeltaMilli=\(scrollDelta)",
            "samplesBeforeFinish=\(sampleCountBeforeFinish)",
            "maxModelErrorMilli=\(Int((maxModelError * 1_000).rounded()))",
            "maxPostPresentationErrorMilli=\(Int((maxPostFinishPresentationError * 1_000).rounded()))",
            "maxVisibleModelErrorMilli=\(Int((maxVisibleModelError * 1_000).rounded()))",
            "maxVisiblePresentationErrorMilli=\(Int((maxVisiblePresentationError * 1_000).rounded()))",
            "visiblePresentationSamples=\(visiblePresentationSamples)",
            "maxSourceContentsRectErrorMilli=\(Int((maxSourceContentsRectError * 1_000).rounded()))",
            "sourcePresentationSamples=\(sourcePresentationSamples)",
            "maxBitmapSourceCount=\(maxBitmapSourceCount)",
            "bitmapSourceSamples=\(bitmapSourceSamples)",
            "singleVisibleSource=\(sourceHadBitmap && maxBitmapSourceCount == 1 ? 1 : 0)",
            "visibleImageStable=\(visibleImageStayedBound ? 1 : 0)",
            "sourceRestored=\(sourceRestored ? 1 : 0)",
            "sourceBitmap=\(sourceHadBitmap ? 1 : 0)",
            "maxHeroProxyCount=\(maxHeroProxyCount)",
            "heroProxySamples=\(heroProxySamples)",
            "sourceVisibleWhileProxy=\(sourceVisibleWhileProxy ? 1 : 0)",
            "scrollBeforeProxyCleanup=\(scrollBeforeProxyCleanup ? 1 : 0)",
            "proxyCountAtFirstScroll=\(proxyCountAtFirstScroll)",
            "sourceVisibleAtFirstScroll=\(sourceVisibleAtFirstScroll ? 1 : 0)"
        ]
        if let error { components.append("error=\(error)") }
        let result = components.joined(separator: ";")
        stopSampling()
        let origin = openingBoundsOrigin
        if ProcessInfo.processInfo.arguments.contains(Self.visualHoldArgument) {
            // Keep the real, already-scrolled feed visible briefly after hero
            // cleanup. This DEBUG-only hold lets a 60 fps recording prove that
            // the returned thumbnail remains attached to its cell.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { [weak self, weak scrollView] in
                scrollView?.setContentOffset(origin, animated: false)
                self?.publish(result)
            }
        } else {
            publish(result)
            DispatchQueue.main.async { [weak scrollView] in
                scrollView?.setContentOffset(origin, animated: false)
            }
        }
    }

    private func beginScroll(at time: CFTimeInterval) {
        guard let scrollView else { return }
        let maximumY = max(
            -scrollView.adjustedContentInset.top,
            scrollView.contentSize.height
                - scrollView.bounds.height
                + scrollView.adjustedContentInset.bottom
        )
        let firstY = min(openingBoundsOrigin.y + 2, maximumY)
        guard firstY > openingBoundsOrigin.y else { return }
        scrollStart = time
        scrollView.setContentOffset(
            CGPoint(x: openingBoundsOrigin.x, y: firstY),
            animated: false
        )
        if abs(scrollView.bounds.origin.y - openingBoundsOrigin.y) >= 1 {
            // Verify UIKit committed the real scroll offset synchronously
            // after transition cleanup. CADisplayLink can be delayed by a busy
            // simulator and is not the input timestamp.
            firstScroll = CACurrentMediaTime()
            proxyCountAtFirstScroll = ImagePreviewHeroProxyView.activeCount
            sourceVisibleAtFirstScroll = sourceView?.isHidden == false
        }
    }

    private func stopSampling() {
        displayLink?.invalidate()
        displayLink = nil
    }

    private func installResultLabel(in window: UIWindow) {
        if resultLabel?.window !== window {
            resultLabel?.removeFromSuperview()
            let label = UILabel(frame: CGRect(x: 0, y: 0, width: 2, height: 2))
            label.isUserInteractionEnabled = false
            label.isAccessibilityElement = true
            label.accessibilityIdentifier = "image-dismiss-scroll-race-probe"
            label.textColor = .clear
            label.backgroundColor = .clear
            window.addSubview(label)
            resultLabel = label
        }
    }

    private func publish(_ value: String) {
        resultLabel?.accessibilityValue = value
        resultLabel?.accessibilityLabel = value
    }

    private static func ancestorScrollView(of view: UIView) -> UIScrollView? {
        var current = view.superview
        while let candidate = current {
            if let scrollView = candidate as? UIScrollView,
               scrollView.isScrollEnabled,
               scrollView.contentSize.height > scrollView.bounds.height {
                return scrollView
            }
            current = candidate.superview
        }
        return nil
    }

    private static func maximumFrameDelta(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        max(
            abs(lhs.minX - rhs.minX),
            abs(lhs.minY - rhs.minY),
            abs(lhs.width - rhs.width),
            abs(lhs.height - rhs.height)
        )
    }

    private static func countBitmapImageViews(in root: UIView) -> Int {
        let ownCount: Int
        if let imageView = root as? UIImageView, imageView.image != nil {
            ownCount = 1
        } else {
            ownCount = 0
        }
        return root.subviews.reduce(ownCount) {
            $0 + countBitmapImageViews(in: $1)
        }
    }
}
#endif

enum ImagePreviewTransitionGeometry {
    static func validSourceFrame(_ frame: CGRect?) -> CGRect? {
        guard let frame,
              frame.isNull == false,
              frame.isInfinite == false,
              frame.minX.isFinite,
              frame.minY.isFinite,
              frame.width.isFinite,
              frame.height.isFinite,
              frame.width >= 2,
              frame.height >= 2 else {
            return nil
        }
        return frame.standardized
    }

    /// Native zoom removes the source from its original hierarchy. Partially
    /// clipped cells therefore cannot be represented by frame alone without a
    /// matching contentsRect. Reject them and let UIKit use its safe fallback.
    static func fullyVisibleFrame(
        of view: UIView,
        in window: UIWindow,
        tolerance: CGFloat = 0.75
    ) -> CGRect? {
        guard view.isHidden == false,
              view.alpha > 0.01,
              view.window === window,
              let sourceFrame = validSourceFrame(view.convert(view.bounds, to: window)),
              sourceFrame.intersects(window.bounds) else {
            return nil
        }

        var visibleRect = window.bounds
        var ancestor = view.superview
        while let current = ancestor, current !== window {
            guard current.isHidden == false, current.alpha > 0.01 else { return nil }
            if current.clipsToBounds || current.layer.masksToBounds || current is UIScrollView {
                let clipFrame = current.convert(current.bounds, to: window)
                visibleRect = visibleRect.intersection(clipFrame)
                guard visibleRect.isNull == false, visibleRect.isEmpty == false else {
                    return nil
                }
            }
            ancestor = current.superview
        }

        let intersection = sourceFrame.intersection(visibleRect)
        guard intersection.isNull == false,
              abs(intersection.minX - sourceFrame.minX) <= tolerance,
              abs(intersection.minY - sourceFrame.minY) <= tolerance,
              abs(intersection.maxX - sourceFrame.maxX) <= tolerance,
              abs(intersection.maxY - sourceFrame.maxY) <= tolerance else {
            return nil
        }
        return sourceFrame
    }

    static func aspectFitFrame(image: ImageContent, in containerSize: CGSize) -> CGRect {
        aspectFitFrame(
            aspectRatio: CGFloat(image.aspectRatio),
            in: CGRect(origin: .zero, size: containerSize)
        )
    }

    static func aspectFitFrame(imageSize: CGSize, in containerFrame: CGRect) -> CGRect {
        let aspectRatio: CGFloat
        if imageSize.width.isFinite,
           imageSize.height.isFinite,
           imageSize.width > 0,
           imageSize.height > 0 {
            aspectRatio = imageSize.width / imageSize.height
        } else {
            aspectRatio = 1
        }
        return aspectFitFrame(aspectRatio: aspectRatio, in: containerFrame)
    }

    static func aspectFitFrame(aspectRatio rawAspectRatio: CGFloat, in containerFrame: CGRect) -> CGRect {
        guard containerFrame.width > 0, containerFrame.height > 0 else { return .zero }
        let aspectRatio = rawAspectRatio.isFinite && rawAspectRatio > 0 ? rawAspectRatio : 1

        var width = containerFrame.width
        var height = width / aspectRatio
        if height > containerFrame.height {
            height = containerFrame.height
            width = height * aspectRatio
        }

        return CGRect(
            x: containerFrame.minX + (containerFrame.width - width) / 2,
            y: containerFrame.minY + (containerFrame.height - height) / 2,
            width: width,
            height: height
        )
    }

    static func sourceFrame(
        _ sourceFrame: CGRect?,
        targetFrame: CGRect,
        containerSize: CGSize
    ) -> CGRect {
        guard let sourceFrame = validSourceFrame(sourceFrame) else { return targetFrame }
        let containerBounds = CGRect(origin: .zero, size: containerSize)
        guard sourceFrame.intersects(containerBounds) else { return targetFrame }
        return sourceFrame
    }

    /// The normalized center crop that lets one bitmap fill `displaySize`
    /// without distortion. The hero transition changes this crop continuously
    /// while its outer frame follows a single monotonic path; it never enlarges
    /// past the destination and then shrinks back.
    static func aspectFillContentsRect(
        imageSize: CGSize,
        displaySize: CGSize
    ) -> CGRect {
        guard imageSize.width.isFinite,
              imageSize.height.isFinite,
              displaySize.width.isFinite,
              displaySize.height.isFinite,
              imageSize.width > 0,
              imageSize.height > 0,
              displaySize.width > 0,
              displaySize.height > 0 else {
            return CGRect(x: 0, y: 0, width: 1, height: 1)
        }

        let imageAspect = imageSize.width / imageSize.height
        let displayAspect = displaySize.width / displaySize.height
        if abs(imageAspect - displayAspect) < 0.000_1 {
            return CGRect(x: 0, y: 0, width: 1, height: 1)
        }
        if displayAspect < imageAspect {
            let width = displayAspect / imageAspect
            return CGRect(x: (1 - width) / 2, y: 0, width: width, height: 1)
        }

        let height = imageAspect / displayAspect
        return CGRect(x: 0, y: (1 - height) / 2, width: 1, height: height)
    }

    static func interpolatedFrame(
        from start: CGRect,
        to end: CGRect,
        progress rawProgress: CGFloat
    ) -> CGRect {
        let progress = min(max(rawProgress, 0), 1)
        // Return the authored endpoints bit-for-bit. Besides avoiding harmless
        // logarithmic rounding such as 844.0000000000002, this guarantees the
        // final proxy frame is identical to the real viewer/source frame at
        // the atomic handoff.
        if progress <= 0 { return start }
        if progress >= 1 { return end }
        let center = CGPoint(
            x: start.midX + (end.midX - start.midX) * progress,
            y: start.midY + (end.midY - start.midY) * progress
        )
        let width = geometricallyInterpolatedLength(
            from: start.width,
            to: end.width,
            progress: progress
        )
        let height = geometricallyInterpolatedLength(
            from: start.height,
            to: end.height,
            progress: progress
        )
        return CGRect(
            x: center.x - width / 2,
            y: center.y - height / 2,
            width: width,
            height: height
        )
    }

    static func easeInOut(_ rawProgress: CGFloat) -> CGFloat {
        let progress = min(max(rawProgress, 0), 1)
        return (1 - cos(.pi * progress)) / 2
    }

    private static func geometricallyInterpolatedLength(
        from start: CGFloat,
        to end: CGFloat,
        progress: CGFloat
    ) -> CGFloat {
        guard start.isFinite, end.isFinite, start > 0, end > 0 else {
            return start + (end - start) * progress
        }
        let value = exp(log(start) + (log(end) - log(start)) * progress)
        // Transcendental rounding can otherwise produce values a fraction of
        // a point outside the authored range (for example
        // 844.0000000000002). Clamp the production geometry so every sampled
        // frame genuinely satisfies the no-overshoot invariant.
        return min(max(value, min(start, end)), max(start, end))
    }

    static func framesMatch(
        _ lhs: CGRect,
        _ rhs: CGRect,
        tolerance: CGFloat = 0.5
    ) -> Bool {
        abs(lhs.minX - rhs.minX) <= tolerance
            && abs(lhs.minY - rhs.minY) <= tolerance
            && abs(lhs.width - rhs.width) <= tolerance
            && abs(lhs.height - rhs.height) <= tolerance
    }
}

@MainActor
final class ImagePreviewTransitionContentState {
    private struct ResolvedContent {
        let image: UIImage
        let frameInWindow: CGRect?
    }

    private let initialIndex: Int
    private var initialContent: ResolvedContent?

    init(initialIndex: Int, initialImage: UIImage?) {
        self.initialIndex = initialIndex
        if let initialImage {
            initialContent = ResolvedContent(
                image: initialImage,
                frameInWindow: nil
            )
        }
    }

    func update(image: UIImage, frameInWindow: CGRect?, at index: Int) {
        guard ImagePreviewTransitionContentRetentionPolicy.retains(
            index: index,
            initialIndex: initialIndex
        ) else { return }
        initialContent = ResolvedContent(
            image: image,
            frameInWindow: ImagePreviewTransitionGeometry.validSourceFrame(
                frameInWindow
            )
        )
    }

    func image(at index: Int) -> UIImage? {
        guard index == initialIndex else { return nil }
        return initialContent?.image
    }

    func frame(
        at index: Int,
        convertedTo containerView: UIView
    ) -> CGRect? {
        guard index == initialIndex,
              let frameInWindow = initialContent?.frameInWindow,
              let window = containerView.window else {
            return nil
        }
        return ImagePreviewTransitionGeometry.validSourceFrame(
            containerView.convert(frameInWindow, from: window)
        )
    }
}

enum ImagePreviewTransitionContentRetentionPolicy {
    /// Only the source page can run the thumbnail hero on dismissal. Other
    /// pages fall back to the normal full-screen dismissal, so retaining their
    /// decoded bitmaps here only grows memory with every swipe.
    static func retains(index: Int, initialIndex: Int) -> Bool {
        index == initialIndex
    }
}

/// The one app-owned bitmap used while the full-screen viewer is moving
/// between its aspect-fit frame and the list thumbnail's aspect-fill crop.
///
/// The canonical thumbnail and the full-screen hierarchy are hidden while
/// this view is visible. Unlike UIKit's native zoom portal, this view is
/// removed synchronously before `completeTransition`, so the feed cannot
/// resume scrolling while a stale transition surface is still on screen.
@MainActor
final class ImagePreviewHeroProxyView: UIView {
    static private(set) var activeCount = 0
    static private(set) weak var activeView: ImagePreviewHeroProxyView?

    let imageView = UIImageView()
    private var isActive = false

    init(image: UIImage) {
        super.init(frame: .zero)
        clipsToBounds = false
        isUserInteractionEnabled = false
        accessibilityElementsHidden = true

        imageView.image = image
        // The outer frame and the normalized center crop are animated together
        // by the hero animator. `scaleToFill` is intentional here:
        // `contentsRect` already has the exact aspect ratio of the frame, so
        // the bitmap remains undistorted while its crop opens to the full image.
        imageView.contentMode = .scaleToFill
        imageView.backgroundColor = .clear
        imageView.clipsToBounds = true
        imageView.isUserInteractionEnabled = false
        imageView.accessibilityElementsHidden = true
        imageView.layer.cornerCurve = .continuous
        imageView.layer.allowsEdgeAntialiasing = true
        addSubview(imageView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func activate(
        in containerView: UIView,
        imageFrame: CGRect,
        cornerRadius: CGFloat
    ) {
        guard isActive == false else { return }
        frame = containerView.bounds
        autoresizingMask = [.flexibleWidth, .flexibleHeight]
        imageView.frame = imageFrame
        imageView.layer.contentsRect = ImagePreviewTransitionGeometry
            .aspectFillContentsRect(
                imageSize: imageView.image?.size ?? imageFrame.size,
                displaySize: imageFrame.size
            )
        imageView.layer.cornerRadius = cornerRadius
        containerView.addSubview(self)
        isActive = true
        Self.activeCount += 1
        Self.activeView = self
    }

    func render(
        frame: CGRect,
        imageSize: CGSize,
        cornerRadius: CGFloat
    ) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageView.frame = frame
        imageView.layer.contentsRect = ImagePreviewTransitionGeometry
            .aspectFillContentsRect(
                imageSize: imageSize,
                displaySize: frame.size
            )
        imageView.layer.cornerRadius = cornerRadius
        CATransaction.commit()
    }

    func deactivate() {
        guard isActive else { return }
        layer.removeAllAnimations()
        imageView.layer.removeAllAnimations()
        removeFromSuperview()
        isActive = false
        Self.activeCount = max(0, Self.activeCount - 1)
        if Self.activeView === self {
            Self.activeView = nil
        }
    }
}

/// Owns the visibility swap between the stable list thumbnail and the
/// transition proxy. `finish()` is idempotent and restores the exact hidden
/// state captured at creation.
@MainActor
final class ImagePreviewHeroSourceLease {
    private(set) weak var sourceView: ImagePreviewSourceView?
    let proxyView: ImagePreviewHeroProxyView
    private let sourceWasHidden: Bool
    private let suppressedIdentity: String?
    private var isFinished = false

    init?(
        sourceView: ImagePreviewSourceView,
        image: UIImage,
        sourceIdentity: String?,
        containerView: UIView,
        imageFrame: CGRect,
        cornerRadius: CGFloat
    ) {
        guard sourceView.window != nil,
              sourceView.isHidden == false,
              sourceView.alpha > 0.01 else {
            return nil
        }
        self.sourceView = sourceView
        sourceWasHidden = sourceView.isHidden
        proxyView = ImagePreviewHeroProxyView(image: image)
        let validIdentity = sourceIdentity.flatMap { $0.isEmpty ? nil : $0 }
        suppressedIdentity = validIdentity
        proxyView.isHidden = true
        proxyView.activate(
            in: containerView,
            imageFrame: imageFrame,
            cornerRadius: cornerRadius
        )

        UIView.performWithoutAnimation {
            if let validIdentity {
                ImagePreviewSourceRegistry.shared.beginSuppression(
                    identity: validIdentity,
                    including: sourceView
                )
            } else {
                sourceView.isHidden = true
            }
            proxyView.isHidden = false
        }
    }

    func finish() {
        guard isFinished == false else { return }
        isFinished = true
        UIView.performWithoutAnimation {
            proxyView.deactivate()
            if let suppressedIdentity {
                ImagePreviewSourceRegistry.shared.endSuppression(
                    identity: suppressedIdentity
                )
            } else {
                sourceView?.isHidden = sourceWasHidden
            }
        }
    }
}

/// Observes the first touch after UIKit has completed the modal dismissal.
/// The transition-container gate continues to freeze the source hierarchy
/// while the hero is active. UIKit intentionally does not deliver new input
/// into that modal transition; once completion fires, this non-cancelling
/// recognizer provides a one-touch fallback for a temporarily stale SwiftUI
/// button without delaying or cancelling normal scrolling.
@MainActor
final class MediaPreviewDismissalInteractionGate: UIGestureRecognizer,
    UIGestureRecognizerDelegate {
    private let onTapAtWindowPoint: (CGPoint, UIWindow) -> Void
    private var initialWindowPoint: CGPoint?
    private var maximumTravel: CGFloat = 0
    private var didObserveFirstTouch = false
    private var pendingTapPoint: CGPoint?
    private var didCompleteTransition = false
    private var transitionCompletion: (() -> Void)?
    private static let maximumTapTravel: CGFloat = 12

    init(onTapAtWindowPoint: @escaping (CGPoint, UIWindow) -> Void) {
        self.onTapAtWindowPoint = onTapAtWindowPoint
        super.init(target: nil, action: nil)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
        delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func installed(in window: UIWindow) -> MediaPreviewDismissalInteractionGate {
        window.addGestureRecognizer(self)
        return self
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard didObserveFirstTouch == false,
              let touch = touches.first,
              let window = view as? UIWindow else {
            return
        }
        didObserveFirstTouch = true
        initialWindowPoint = touch.location(in: window)
        maximumTravel = 0
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first,
              let window = view as? UIWindow,
              let initialWindowPoint else {
            return
        }
        let point = touch.location(in: window)
        maximumTravel = max(
            maximumTravel,
            hypot(
                point.x - initialWindowPoint.x,
                point.y - initialWindowPoint.y
            )
        )
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if maximumTravel <= Self.maximumTapTravel {
            pendingTapPoint = initialWindowPoint
        }
        initialWindowPoint = nil
        state = pendingTapPoint == nil ? .failed : .recognized
        finishIfPossible()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        initialWindowPoint = nil
        state = .failed
        finishIfPossible()
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }

    /// If a touch is already in flight, keep the old lifecycle until it ends so
    /// its intent can be queued before the coordinator becomes idle. Otherwise
    /// finish immediately but leave this non-cancelling observer armed for the
    /// first post-dismissal touch; SwiftUI occasionally needs that replay even
    /// though UIKit has already completed the modal transition.
    func transitionDidComplete(completion: @escaping () -> Void) {
        guard didCompleteTransition == false else { return }
        didCompleteTransition = true
        transitionCompletion = completion
        if didObserveFirstTouch == false {
            transitionCompletion = nil
            completion()
            return
        }
        finishIfPossible()
    }

    func cancel() {
        transitionCompletion = nil
        pendingTapPoint = nil
        initialWindowPoint = nil
        removeFromWindow()
    }

    private func finishIfPossible() {
        guard didCompleteTransition, initialWindowPoint == nil else {
            return
        }
        if let pendingTapPoint, let window = view as? UIWindow {
            self.pendingTapPoint = nil
            onTapAtWindowPoint(pendingTapPoint, window)
        }
        removeFromWindow()
        if let transitionCompletion {
            self.transitionCompletion = nil
            transitionCompletion()
        }
    }

    private func removeFromWindow() {
        view?.removeGestureRecognizer(self)
    }
}

enum ImagePreviewLifecyclePhase: Equatable {
    case idle
    case presenting(UUID)
    case presented(UUID)
    case dismissing(UUID)

    var sessionID: UUID? {
        switch self {
        case .idle:
            return nil
        case let .presenting(id), let .presented(id), let .dismissing(id):
            return id
        }
    }

    var isBusy: Bool {
        sessionID != nil
    }
}

enum ImagePreviewTransitionMotionPolicy {
    static var animationsEnabled: Bool {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("UITEST_FORCE_IMAGE_TRANSITIONS") {
            return true
        }
#endif
        return UIAccessibility.isReduceMotionEnabled == false
    }
}

struct ImagePreviewLifecycle {
    private(set) var phase: ImagePreviewLifecyclePhase = .idle

    mutating func beginPresentation(sessionID: UUID) -> Bool {
        guard phase == .idle else { return false }
        phase = .presenting(sessionID)
        return true
    }

    mutating func finishPresentation(sessionID: UUID) -> Bool {
        guard phase == .presenting(sessionID) else { return false }
        phase = .presented(sessionID)
        return true
    }

    mutating func cancelPresentation(sessionID: UUID) -> Bool {
        guard phase == .presenting(sessionID) else { return false }
        phase = .idle
        return true
    }

    mutating func beginDismissal(sessionID: UUID) -> Bool {
        switch phase {
        case let .presenting(id):
            guard id == sessionID else { return false }
            phase = .dismissing(sessionID)
            return true
        case let .presented(id):
            guard id == sessionID else { return false }
            phase = .dismissing(sessionID)
            return true
        case let .dismissing(id):
            return id == sessionID
        case .idle:
            return false
        }
    }

    mutating func finish(sessionID: UUID) -> Bool {
        guard phase.sessionID == sessionID else { return false }
        phase = .idle
        return true
    }

    mutating func cancelDismissal(sessionID: UUID) -> Bool {
        guard phase == .dismissing(sessionID) else { return false }
        phase = .presented(sessionID)
        return true
    }
}

@MainActor
final class ImagePreviewPresentationState {
    private(set) var didFinishPresentation = false
    let presentationDidFinish = PassthroughSubject<Void, Never>()
    let currentIndexDidChange = PassthroughSubject<Int, Never>()
    private(set) var currentIndex: Int
    private var zoomedIndices: Set<Int> = []

    init(initialIndex: Int) {
        currentIndex = initialIndex
    }

    func setCurrentIndex(_ index: Int) {
        guard currentIndex != index else { return }
        currentIndex = index
        currentIndexDidChange.send(index)
    }

    func markPresentationFinished() {
        guard didFinishPresentation == false else { return }
        didFinishPresentation = true
        presentationDidFinish.send()
    }

    func setZoomed(_ zoomed: Bool, at index: Int) {
        if zoomed {
            zoomedIndices.insert(index)
        } else {
            zoomedIndices.remove(index)
        }
    }

    var allowsInteractiveDismissal: Bool {
        zoomedIndices.contains(currentIndex) == false
    }
}

@MainActor
private final class ImagePreviewDismissRelay {
    weak var controller: ImagePreviewHostingController?

    func dismiss() {
        guard let controller,
              controller.presentingViewController != nil,
              controller.isBeingDismissed == false else {
            return
        }
        controller.beginDismissalIfNeeded()
        controller.dismiss(animated: ImagePreviewTransitionMotionPolicy.animationsEnabled) {
            controller.finishDismissalIfNeeded()
        }
    }
}

@MainActor
private final class ImagePreviewHostingController: UIHostingController<FullScreenImageView>,
    UIAdaptivePresentationControllerDelegate,
    UIViewControllerTransitioningDelegate,
    MediaPreviewHeroTransitionParticipant {
    let session: ImagePreviewSession
    let transitionState: ImagePreviewPresentationState
    let transitionContent: ImagePreviewTransitionContentState
    private let onDismissalBegan: (UUID) -> Void
    private let onDismissalFinished: (UUID) -> Void
    private let onPresentationCancelled: (UUID) -> Void
    private let onDismissalCancelled: (UUID) -> Void
    private var didCancelPresentation = false
    private var didBeginDismissal = false
    private var didFinishDismissal = false
    private var dismissalInteractionGate: MediaPreviewDismissalInteractionGate?

    init(
        session: ImagePreviewSession,
        transitionState: ImagePreviewPresentationState,
        transitionContent: ImagePreviewTransitionContentState,
        rootView: FullScreenImageView,
        onDismissalBegan: @escaping (UUID) -> Void,
        onDismissalFinished: @escaping (UUID) -> Void,
        onPresentationCancelled: @escaping (UUID) -> Void,
        onDismissalCancelled: @escaping (UUID) -> Void
    ) {
        self.session = session
        self.transitionState = transitionState
        self.transitionContent = transitionContent
        self.onDismissalBegan = onDismissalBegan
        self.onDismissalFinished = onDismissalFinished
        self.onPresentationCancelled = onPresentationCancelled
        self.onDismissalCancelled = onDismissalCancelled
        super.init(rootView: rootView)
        view.backgroundColor = .black
    }

    @available(*, unavailable)
    required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        presentationController?.delegate = self
    }

    func presentationControllerWillDismiss(_ presentationController: UIPresentationController) {
        beginDismissalIfNeeded()
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        finishDismissalIfNeeded()
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        .lightContent
    }

    override var preferredStatusBarUpdateAnimation: UIStatusBarAnimation {
        .fade
    }

    func animationController(
        forPresented presented: UIViewController,
        presenting: UIViewController,
        source: UIViewController
    ) -> UIViewControllerAnimatedTransitioning? {
        MediaPreviewHeroAnimator(operation: .presentation, participant: self)
    }

    func animationController(
        forDismissed dismissed: UIViewController
    ) -> UIViewControllerAnimatedTransitioning? {
        MediaPreviewHeroAnimator(operation: .dismissal, participant: self)
    }

    var mediaPreviewHeroSourceIdentity: String? {
        session.sourceIdentity
    }

    func mediaPreviewStableSourceView(
        in sourceViewController: UIViewController
    ) -> ImagePreviewSourceView? {
        stableTransitionSourceView(in: sourceViewController)
    }

    func mediaPreviewHeroDismissalContent(
        sourceView: ImagePreviewSourceView,
        dismissedView: UIView,
        containerView: UIView
    ) -> MediaPreviewHeroDismissalContent? {
        let currentIndex = transitionState.currentIndex
        guard currentIndex == session.initialIndex,
              transitionState.allowsInteractiveDismissal,
              let image = transitionContent.image(at: currentIndex)
                ?? sourceView.image else {
            return nil
        }
        let frame = transitionContent.frame(
            at: currentIndex,
            convertedTo: containerView
        ) ?? ImagePreviewTransitionGeometry.aspectFitFrame(
            imageSize: image.size,
            in: dismissedView.frame
        )
        return MediaPreviewHeroDismissalContent(image: image, frame: frame)
    }

    func mediaPreviewHeroTransitionDidCancel(
        _ operation: MediaPreviewHeroOperation
    ) {
        switch operation {
        case .presentation:
            heroPresentationDidCancel()
        case .dismissal:
            heroDismissalDidCancel()
        }
    }

    @discardableResult
    func stableTransitionSourceView(
        in sourceViewController: UIViewController
    ) -> ImagePreviewSourceView? {
        guard transitionState.currentIndex == session.initialIndex,
              let sourceView = ImagePreviewSourceResolver.view(
                  exactAnchor: session.sourceAnchor,
                  token: session.sourceToken,
                  sourceIdentity: session.sourceIdentity
              ) as? ImagePreviewSourceView,
              let sourceWindow = sourceView.window else {
            return nil
        }
        sourceViewController.loadViewIfNeeded()
        let container = sourceViewController.view!
        guard container.window === sourceWindow,
              sourceView.isDescendant(of: container),
              ImagePreviewTransitionGeometry.fullyVisibleFrame(
                  of: sourceView,
                  in: sourceWindow
              ) != nil else {
            return nil
        }
        return sourceView
    }

    func finishPresentationIfNeeded() {
        transitionState.markPresentationFinished()
    }

    func beginDismissalIfNeeded() {
        guard didBeginDismissal == false else { return }
        didBeginDismissal = true
        onDismissalBegan(session.id)
        if let window = view.window {
            dismissalInteractionGate = MediaPreviewDismissalInteractionGate(
                onTapAtWindowPoint: { point, window in
                    ImagePreviewSourceRegistry.shared.activateSource(
                        at: point,
                        in: window
                    )
                }
            )
            .installed(in: window)
        }
    }

    func finishDismissalIfNeeded() {
        guard didFinishDismissal == false else { return }
        didFinishDismissal = true
        let finish = onDismissalFinished
        let sessionID = session.id
        guard let dismissalInteractionGate else {
            finish(sessionID)
            return
        }
        self.dismissalInteractionGate = nil
        dismissalInteractionGate.transitionDidComplete {
            finish(sessionID)
        }
    }

    func heroPresentationDidCancel() {
        guard didCancelPresentation == false else { return }
        didCancelPresentation = true
        onPresentationCancelled(session.id)
    }

    func heroDismissalDidCancel() {
        didBeginDismissal = false
        didFinishDismissal = false
        dismissalInteractionGate?.cancel()
        dismissalInteractionGate = nil
        onDismissalCancelled(session.id)
    }
}

@MainActor
final class ImagePreviewCoordinator {
    static let shared = ImagePreviewCoordinator()

    private let arbiter = MediaPreviewPresentationArbiter.shared
    private var activeController: ImagePreviewHostingController?

    private init() {}

    @discardableResult
    func present(
        _ session: ImagePreviewSession,
        saveAction: @escaping (URL) async throws -> Void = FullScreenImageView.liveSave
    ) -> Bool {
        let initialImage = session.images.indices.contains(session.initialIndex)
            ? session.images[session.initialIndex]
            : nil
        let request = MediaPreviewPresentationRequest(
            id: session.id,
            kind: .image,
            sourceKey: session.sourceIdentity
                ?? initialImage?.originalURL?.absoluteString
                ?? initialImage?.thumbnailURL?.absoluteString
        )
        return arbiter.submit(request) { [weak self] in
            self?.startPresentation(
                session,
                request: request,
                saveAction: saveAction
            ) ?? false
        }
    }

    private func startPresentation(
        _ session: ImagePreviewSession,
        request: MediaPreviewPresentationRequest,
        saveAction: @escaping (URL) async throws -> Void
    ) -> Bool {
        guard let presenter = Self.topPresenter() else { return false }
#if DEBUG
        ImageDismissScrollRaceProbe.shared.prepare(session: session)
#endif

        let transitionState = ImagePreviewPresentationState(initialIndex: session.initialIndex)
        let transitionContent = ImagePreviewTransitionContentState(
            initialIndex: session.initialIndex,
            initialImage: session.sourceImage
        )
        let dismissRelay = ImagePreviewDismissRelay()
        let viewer = FullScreenImageView(
            session: session,
            transitionState: transitionState,
            saveAction: saveAction,
            onRequestDismiss: {
                dismissRelay.dismiss()
            },
            onCurrentIndexChange: { index in
                transitionState.setCurrentIndex(index)
            },
            onCurrentImageResolved: { index, image, frameInWindow in
                transitionContent.update(
                    image: image,
                    frameInWindow: frameInWindow,
                    at: index
                )
            },
            onZoomStateChange: { index, isZoomed in
                transitionState.setZoomed(isZoomed, at: index)
            }
        )
        let controller = ImagePreviewHostingController(
            session: session,
            transitionState: transitionState,
            transitionContent: transitionContent,
            rootView: viewer,
            onDismissalBegan: { [weak self] sessionID in
                self?.beginDismissal(sessionID: sessionID, request: request)
            },
            onDismissalFinished: { [weak self] sessionID in
                self?.finishDismissal(sessionID: sessionID, request: request)
            },
            onPresentationCancelled: { [weak self] sessionID in
                self?.cancelPresentation(sessionID: sessionID, request: request)
            },
            onDismissalCancelled: { [weak self] sessionID in
                self?.cancelDismissal(sessionID: sessionID, request: request)
            }
        )
        dismissRelay.controller = controller
        controller.modalPresentationStyle = .overFullScreen
        controller.modalPresentationCapturesStatusBarAppearance = true
        controller.isModalInPresentation = true
        controller.transitioningDelegate = controller
        controller.loadViewIfNeeded()
        controller.view.layoutIfNeeded()
        activeController = controller

        presenter.present(
            controller,
            animated: ImagePreviewTransitionMotionPolicy.animationsEnabled
        ) { [weak self, weak controller] in
            guard let self,
                  self.arbiter.presentationDidFinish(request) else {
                return
            }
            controller?.finishPresentationIfNeeded()
        }
        MediaPreviewPresentationAttachmentVerifier.verify(
            controller: controller,
            presenter: presenter
        ) { [weak controller] in
            controller?.heroPresentationDidCancel()
        }
        return true
    }

    private func beginDismissal(
        sessionID: UUID,
        request: MediaPreviewPresentationRequest
    ) {
        guard sessionID == request.id,
              arbiter.dismissalWillBegin(request) else {
            return
        }
#if DEBUG
        ImageDismissScrollRaceProbe.shared.dismissalDidBegin(sessionID: sessionID)
#endif
    }

    private func finishDismissal(
        sessionID: UUID,
        request: MediaPreviewPresentationRequest
    ) {
        guard sessionID == request.id else { return }
        if activeController?.session.id == sessionID {
            activeController = nil
        }
#if DEBUG
        ImageDismissScrollRaceProbe.shared.dismissalDidFinish(sessionID: sessionID)
#endif
        _ = arbiter.dismissalDidFinish(request)
    }

    private func cancelPresentation(
        sessionID: UUID,
        request: MediaPreviewPresentationRequest
    ) {
        guard sessionID == request.id,
              arbiter.presentationDidCancel(request) else {
            return
        }
        if activeController?.session.id == sessionID {
            activeController = nil
        }
    }

    private func cancelDismissal(
        sessionID: UUID,
        request: MediaPreviewPresentationRequest
    ) {
        guard sessionID == request.id else { return }
        _ = arbiter.dismissalDidCancel(request)
    }

    static func topPresenter() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
        let scene = scenes.first(where: { $0.activationState == .foregroundActive })
            ?? scenes.first(where: { $0.windows.contains(where: \.isKeyWindow) })
        let window = scene?.windows.first(where: \.isKeyWindow)
            ?? scene?.windows.first(where: { $0.isHidden == false && $0.alpha > 0 })
        guard let root = window?.rootViewController else { return nil }
        return topViewController(from: root)
    }

    static func topViewController(from controller: UIViewController) -> UIViewController {
        if let presented = controller.presentedViewController,
           presented.isBeingDismissed == false {
            return topViewController(from: presented)
        }
        if let navigationController = controller as? UINavigationController,
           let visible = navigationController.visibleViewController {
            return topViewController(from: visible)
        }
        if let tabBarController = controller as? UITabBarController,
           let selected = tabBarController.selectedViewController {
            return topViewController(from: selected)
        }
        if let visibleChild = controller.children.reversed().first(where: {
            $0.viewIfLoaded?.window != nil
        }) {
            return topViewController(from: visibleChild)
        }
        return controller
    }
}

enum FullScreenOriginalImageLoadState: Equatable {
    case unavailable
    case available
    case loading
    case loaded
    case failed

    var canRequest: Bool {
        self == .available || self == .failed
    }
}

enum FullScreenImageLoadPrecedencePolicy {
    static func acceptsPreview(
        while originalState: FullScreenOriginalImageLoadState
    ) -> Bool {
        originalState != .loading && originalState != .loaded
    }

    static func resumesPreviewAfterOriginalFailure(
        hasResolvedImage: Bool
    ) -> Bool {
        hasResolvedImage == false
    }
}

enum FullScreenImageSourcePolicy {
    struct Sources: Equatable {
        let previewURL: URL?
        let originalURL: URL?
        let downloadURL: URL?
    }

    static func sources(thumbnail: URL?, original: URL?) -> Sources {
        let safeThumbnail = allowedImageURL(thumbnail)
        let safeOriginal = allowedImageURL(original)
        return Sources(
            previewURL: safeThumbnail ?? safeOriginal,
            originalURL: safeOriginal,
            downloadURL: safeOriginal ?? safeThumbnail
        )
    }

    /// Automatic full-screen image-body loading stays on the preview tier. A
    /// distinct original image body is reserved for the explicit original and
    /// download actions; the visible page may still issue a body-free HEAD
    /// request so the control can display its file size.
    static func automaticPreviewURLs(
        primary: URL?,
        fallback: URL?,
        original: URL?
    ) -> [URL] {
        let candidates = TiebaImageSourcePolicy.urls(
            primary: primary,
            fallback: fallback
        ).filter { allowedImageURL($0) != nil }
        guard let safeOriginal = allowedImageURL(original) else {
            return candidates
        }
        let previewCandidates = candidates.filter { $0 != safeOriginal }
        // Some legacy payloads expose only one URL. It can still be decoded at
        // preview size; there is no distinct lower-resolution network source.
        return previewCandidates.isEmpty ? Array(candidates.prefix(1)) : previewCandidates
    }

    private static func allowedImageURL(_ candidate: URL?) -> URL? {
        guard let safeURL = TiebaURL.image(candidate?.absoluteString) else { return nil }
        if TiebaRemoteMediaPolicy.allows(safeURL) {
            return safeURL
        }
#if DEBUG
        if TiebaImageSourcePolicy.isSyntheticSuccessURL(safeURL)
            || TiebaImageSourcePolicy.isSyntheticFailureURL(safeURL) {
            return safeURL
        }
#endif
        return nil
    }
}

private struct FullScreenImageItem: Identifiable {
    let id: String
    let primaryURL: URL?
    let fallbackURL: URL?
    let originalURL: URL?
    let downloadURL: URL?
    let imageAspectRatio: CGFloat
    let placeholderImage: UIImage?

    init(image: ImageContent, index: Int, placeholderImage: UIImage? = nil) {
        id = "\(index)-\(image.originalURL?.absoluteString ?? image.thumbnailURL?.absoluteString ?? "missing")"
        let sources = FullScreenImageSourcePolicy.sources(
            thumbnail: image.thumbnailURL,
            original: image.originalURL
        )
        primaryURL = sources.previewURL
        fallbackURL = nil
        originalURL = sources.originalURL
        downloadURL = sources.downloadURL
        imageAspectRatio = CGFloat(image.aspectRatio)
        self.placeholderImage = placeholderImage
    }

    init(url: URL?, index: Int) {
        id = "\(index)-\(url?.absoluteString ?? "missing")"
        let sources = FullScreenImageSourcePolicy.sources(thumbnail: url, original: url)
        primaryURL = sources.previewURL
        fallbackURL = nil
        originalURL = sources.originalURL
        downloadURL = sources.downloadURL
        imageAspectRatio = 1
        placeholderImage = nil
    }
}

enum ImagePreviewResolvedImageVisibilityPolicy {
    static func showsResolvedContent(
        hasPlaceholder: Bool,
        didFinishPresentation: Bool,
        loadState: TiebaRemoteImageLoadState
    ) -> Bool {
        guard hasPlaceholder else { return true }
        guard didFinishPresentation else { return false }
        return loadState == .success || loadState == .failure
    }

    static func animatesResolvedReveal(
        presentationFinishedBeforeResolution: Bool
    ) -> Bool {
        presentationFinishedBeforeResolution
    }
}

enum FullScreenImageLoadSchedulingPolicy {
    /// A page may start its preview-image load only after the hero
    /// presentation has finished, and only while it is the visible page or an
    /// immediate neighbor. Loading every page at presentation time flooded
    /// the 0.32s transition window with downloads and full-size decodes.
    static func allowsLoading(
        pageIndex: Int,
        currentIndex: Int,
        didFinishPresentation: Bool,
        prefetchesAdjacentPages: Bool = true
    ) -> Bool {
        guard didFinishPresentation else { return false }
        if prefetchesAdjacentPages {
            return abs(pageIndex - currentIndex) <= 1
        }
        return pageIndex == currentIndex
    }
}

enum FullScreenImageMetadataSchedulingPolicy {
    /// Original-file metadata is needed for the visible "查看原图" control,
    /// but adjacent pages must not touch their original URLs speculatively.
    static func allowsLoading(
        pageIndex: Int,
        currentIndex: Int,
        didFinishPresentation: Bool
    ) -> Bool {
        didFinishPresentation && pageIndex == currentIndex
    }
}

enum FullScreenImagePageResidencyPolicy {
    /// UIKit may keep every page controller owned by the page-style TabView.
    /// Bound decoded-image residency independently of that implementation
    /// detail so long galleries retain only the visible page and its neighbors.
    static func retainsPage(pageIndex: Int, currentIndex: Int) -> Bool {
        abs(pageIndex - currentIndex) <= 1
    }
}

enum FullScreenImageDecodePolicy {
    static let maximumPreviewDecodedPixelSize = 3_072
    static let maximumPreviewDisplayScale: CGFloat = 3

    /// Match the screen's native pixel density without decoding beyond the
    /// size a phone or tablet can use for its initial full-screen presentation.
    /// The explicit original-image action remains on the separate 4096 tier.
    static var initialTargetPixelSize: Int {
        previewTargetPixelSize(
            for: UIScreen.main.bounds.size,
            displayScale: UIScreen.main.scale
        )
    }

    static func previewTargetPixelSize(
        for pointSize: CGSize,
        displayScale: CGFloat
    ) -> Int {
        let longestPointEdge = max(pointSize.width, pointSize.height)
        guard longestPointEdge.isFinite,
              longestPointEdge > 0,
              displayScale.isFinite,
              displayScale > 0 else {
            return 1_024
        }
        let previewScale = min(displayScale, maximumPreviewDisplayScale)
        return min(
            Int(ceil(longestPointEdge * previewScale)),
            maximumPreviewDecodedPixelSize
        )
    }
}

enum FullScreenImagePlaceholderPolicy {
    static func canReuseAsPreview(
        placeholderSize: CGSize?,
        imageAspectRatio: CGFloat
    ) -> Bool {
        guard let placeholderSize,
              placeholderSize.width > 0,
              placeholderSize.height > 0,
              imageAspectRatio > 0 else {
            return false
        }
        let placeholderAspectRatio = placeholderSize.width / placeholderSize.height
        return abs(placeholderAspectRatio - imageAspectRatio) <= 0.01
    }
}

private struct FullScreenZoomableRemoteImage: UIViewControllerRepresentable {
    let primaryURL: URL?
    let fallbackURL: URL?
    let originalURL: URL?
    let imageAspectRatio: CGFloat
    let placeholderImage: UIImage?
    let transitionState: ImagePreviewPresentationState
    let imageIndex: Int
    let coordinatesWithParentPager: Bool
    let prefetchesAdjacentPages: Bool
    let originalLoadRequest: Int
    let onImageResolved: (UIImage, CGRect?) -> Void
    let onOriginalLoadStateChange: (FullScreenOriginalImageLoadState) -> Void
    let onOriginalLoadProgressChange: (BoundedURLSessionProgress?) -> Void
    let onOriginalFileSizeChange: (Int64?) -> Void
    let onZoomStateChange: (Bool) -> Void
    let onSingleTap: () -> Void
    let onInteractiveDismiss: () -> Void

    func makeUIViewController(context: Context) -> FullScreenZoomImageController {
        FullScreenZoomImageController(
            primaryURL: primaryURL,
            fallbackURL: fallbackURL,
            originalURL: originalURL,
            imageAspectRatio: imageAspectRatio,
            placeholderImage: placeholderImage,
            transitionState: transitionState,
            imageIndex: imageIndex,
            coordinatesWithParentPager: coordinatesWithParentPager,
            prefetchesAdjacentPages: prefetchesAdjacentPages,
            onImageResolved: onImageResolved,
            onOriginalLoadStateChange: onOriginalLoadStateChange,
            onOriginalLoadProgressChange: onOriginalLoadProgressChange,
            onOriginalFileSizeChange: onOriginalFileSizeChange,
            onZoomStateChange: onZoomStateChange,
            onSingleTap: onSingleTap,
            onInteractiveDismiss: onInteractiveDismiss
        )
    }

    func updateUIViewController(
        _ uiViewController: FullScreenZoomImageController,
        context: Context
    ) {
        uiViewController.onImageResolved = onImageResolved
        uiViewController.onOriginalLoadStateChange = onOriginalLoadStateChange
        uiViewController.onOriginalLoadProgressChange = onOriginalLoadProgressChange
        uiViewController.onOriginalFileSizeChange = onOriginalFileSizeChange
        uiViewController.onZoomStateChange = onZoomStateChange
        uiViewController.onSingleTap = onSingleTap
        uiViewController.onInteractiveDismiss = onInteractiveDismiss
        uiViewController.updateAccessibility(imageIndex: imageIndex)
        uiViewController.reportResolvedImageLayoutIfPossible()
        uiViewController.requestOriginalImage(ifNewRequest: originalLoadRequest)
    }

    static func dismantleUIViewController(
        _ uiViewController: FullScreenZoomImageController,
        coordinator: ()
    ) {
        uiViewController.prepareForRemoval()
        uiViewController.onImageResolved = nil
        uiViewController.onOriginalLoadStateChange = nil
        uiViewController.onOriginalLoadProgressChange = nil
        uiViewController.onOriginalFileSizeChange = nil
        uiViewController.onZoomStateChange = nil
        uiViewController.onSingleTap = nil
        uiViewController.onInteractiveDismiss = nil
    }
}

@MainActor
private final class FullScreenZoomImageController: UIViewController,
    UIScrollViewDelegate,
    UIGestureRecognizerDelegate {
    private let scrollView = UIScrollView()
    private let zoomContentView = UIView()
    private let placeholderImageView = UIImageView()
    private let resolvedImageView = UIImageView()
    private let activityIndicator = UIActivityIndicatorView(style: .large)
    private let retryButton = UIButton(type: .system)
    private let zoomDiagnosticsProxy = UIView()
    private let renderProbeDiagnosticsProxy = UIView()
    private let primaryURL: URL?
    private let fallbackURL: URL?
    private let originalURL: URL?
    private let imageAspectRatio: CGFloat
    private let placeholderImage: UIImage?
    private let transitionState: ImagePreviewPresentationState
    private let coordinatesWithParentPager: Bool
    private let prefetchesAdjacentPages: Bool
    private var imageIndex: Int
    private var lastViewportSize: CGSize = .zero
    private var resolvedImage: UIImage?
    private var transitionImage: UIImage?
    private var loadTask: Task<Void, Never>?
    private var highResolutionLoadTask: Task<Void, Never>?
    private var metadataTask: Task<Void, Never>?
    private var lastOriginalLoadRequest = 0
    private var originalLoadState: FullScreenOriginalImageLoadState
    private var originalFileSize: Int64?
    private var latestOriginalProgress: BoundedURLSessionProgress?
    private var didFinishMetadataRequest = false
    private var presentationCancellable: AnyCancellable?
    private var currentIndexCancellable: AnyCancellable?
    private var didRevealResolvedImage = false
    private var lastReportedZoomed = false
    private var lastAccessibilityPercentage = 100
    private var zoomGestureStartTime: CFTimeInterval?
    private var firstZoomCallbackMilliseconds: Double?
    private var previousZoomCallbackTime: CFTimeInterval?
    private var maximumZoomCallbackGapMilliseconds: Double = 0
    private var zoomCallbackCount = 0
    private var doubleTapCount = 0
    private var renderProbeDisplayLink: CADisplayLink?
    private var renderProbeStartTimestamp: CFTimeInterval?
    private var renderProbePreviousTimestamp: CFTimeInterval?
    private var renderProbeMaximumFrameGapMilliseconds: Double = 0
    private var renderProbeFrameGapsMilliseconds: [Double] = []
    private var renderProbeMaximumWorkMilliseconds: Double = 0
    private var renderProbeFrameCount = 0
    private var isRunningRenderProbe = false
    private var didScheduleAutomaticRenderProbe = false
    private lazy var dismissPanGestureRecognizer = UIPanGestureRecognizer(
        target: self,
        action: #selector(handleDismissPan(_:))
    )
    private var activeDismissAxis: FullScreenImageDismissAxis?
    private var isCompletingDismissGesture = false

    var onImageResolved: ((UIImage, CGRect?) -> Void)?
    var onOriginalLoadStateChange: ((FullScreenOriginalImageLoadState) -> Void)?
    var onOriginalLoadProgressChange: ((BoundedURLSessionProgress?) -> Void)?
    var onOriginalFileSizeChange: ((Int64?) -> Void)?
    var onZoomStateChange: ((Bool) -> Void)?
    var onSingleTap: (() -> Void)?
    var onInteractiveDismiss: (() -> Void)?

    init(
        primaryURL: URL?,
        fallbackURL: URL?,
        originalURL: URL?,
        imageAspectRatio: CGFloat,
        placeholderImage: UIImage?,
        transitionState: ImagePreviewPresentationState,
        imageIndex: Int,
        coordinatesWithParentPager: Bool,
        prefetchesAdjacentPages: Bool,
        onImageResolved: @escaping (UIImage, CGRect?) -> Void,
        onOriginalLoadStateChange: @escaping (FullScreenOriginalImageLoadState) -> Void,
        onOriginalLoadProgressChange: @escaping (BoundedURLSessionProgress?) -> Void,
        onOriginalFileSizeChange: @escaping (Int64?) -> Void,
        onZoomStateChange: @escaping (Bool) -> Void,
        onSingleTap: @escaping () -> Void,
        onInteractiveDismiss: @escaping () -> Void
    ) {
        self.primaryURL = primaryURL
        self.fallbackURL = fallbackURL
        self.originalURL = originalURL
        self.imageAspectRatio = imageAspectRatio
        self.placeholderImage = placeholderImage
        self.transitionState = transitionState
        self.imageIndex = imageIndex
        self.coordinatesWithParentPager = coordinatesWithParentPager
        self.prefetchesAdjacentPages = prefetchesAdjacentPages
        if FullScreenImagePlaceholderPolicy.canReuseAsPreview(
            placeholderSize: placeholderImage?.size,
            imageAspectRatio: imageAspectRatio
        ) {
            resolvedImage = placeholderImage
            transitionImage = placeholderImage
        }
        originalLoadState = originalURL == nil ? .unavailable : .available
        self.onImageResolved = onImageResolved
        self.onOriginalLoadStateChange = onOriginalLoadStateChange
        self.onOriginalLoadProgressChange = onOriginalLoadProgressChange
        self.onOriginalFileSizeChange = onOriginalFileSizeChange
        self.onZoomStateChange = onZoomStateChange
        self.onSingleTap = onSingleTap
        self.onInteractiveDismiss = onInteractiveDismiss
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
        scrollView.delaysContentTouches = false
        // Expose the actual interactive surface to accessibility and UI tests.
        // A separate non-interactive overlay reported the right frame but sent
        // synthesized taps to a different hit-test target, which is why double
        // tap could be advertised yet never reach the zoom controller.
        scrollView.isAccessibilityElement = true
        // Keep one-finger panning disabled at rest so taps and the parent page
        // gesture are deterministic. The independent pinch recognizer enables
        // panning as soon as an actual zoom begins.
        scrollView.panGestureRecognizer.isEnabled = false
        scrollView.pinchGestureRecognizer?.delaysTouchesBegan = false
        scrollView.pinchGestureRecognizer?.delaysTouchesEnded = false
        let doubleTapRecognizer = UITapGestureRecognizer(
            target: self,
            action: #selector(handleDoubleTap(_:))
        )
        doubleTapRecognizer.numberOfTapsRequired = 2
        doubleTapRecognizer.cancelsTouchesInView = false
        let singleTapRecognizer = UITapGestureRecognizer(
            target: self,
            action: #selector(handleSingleTap(_:))
        )
        singleTapRecognizer.numberOfTapsRequired = 1
        singleTapRecognizer.cancelsTouchesInView = false
        singleTapRecognizer.require(toFail: doubleTapRecognizer)
        // Own taps at the controller root. UIScrollView may temporarily
        // disable its pan recognizer at 100%; attaching taps to the scroll view
        // made their delivery depend on that internal recognizer state.
        rootView.addGestureRecognizer(doubleTapRecognizer)
        rootView.addGestureRecognizer(singleTapRecognizer)
        dismissPanGestureRecognizer.maximumNumberOfTouches = 1
        dismissPanGestureRecognizer.cancelsTouchesInView = false
        dismissPanGestureRecognizer.delegate = self
        rootView.addGestureRecognizer(dismissPanGestureRecognizer)
        rootView.addSubview(scrollView)

        zoomContentView.backgroundColor = .black
        zoomContentView.clipsToBounds = false
        scrollView.addSubview(zoomContentView)

        placeholderImageView.image = placeholderImage
        // Match the resolved image view exactly (aspect-fit, full bounds).
        // A .scaleAspectFill placeholder in an aspect-fit frame renders the
        // image at a different scale than the resolved .scaleAspectFit view,
        // so revealing the resolved image popped/flickered at the end of the
        // open animation. Identical geometry makes the reveal a pure
        // low-res -> high-res swap with no scale change.
        placeholderImageView.contentMode = .scaleAspectFit
        placeholderImageView.clipsToBounds = true
        placeholderImageView.backgroundColor = .clear
        placeholderImageView.isHidden = placeholderImage == nil
        zoomContentView.addSubview(placeholderImageView)

        resolvedImageView.contentMode = .scaleAspectFit
        resolvedImageView.clipsToBounds = true
        resolvedImageView.backgroundColor = .clear
        resolvedImageView.alpha = placeholderImage == nil ? 1 : 0
        zoomContentView.addSubview(resolvedImageView)

        activityIndicator.color = .white
        activityIndicator.hidesWhenStopped = true
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        rootView.addSubview(activityIndicator)

        var retryConfiguration = UIButton.Configuration.gray()
        retryConfiguration.title = "图片加载失败，点按重试"
        retryConfiguration.image = UIImage(systemName: "arrow.clockwise")
        retryConfiguration.imagePadding = 8
        retryButton.configuration = retryConfiguration
        retryButton.tintColor = .white
        retryButton.translatesAutoresizingMaskIntoConstraints = false
        retryButton.isHidden = true
        retryButton.addTarget(self, action: #selector(retryLoading), for: .touchUpInside)
        rootView.addSubview(retryButton)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: rootView.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),
            activityIndicator.centerXAnchor.constraint(equalTo: rootView.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: rootView.centerYAnchor),
            retryButton.centerXAnchor.constraint(equalTo: rootView.centerXAnchor),
            retryButton.centerYAnchor.constraint(equalTo: rootView.centerYAnchor),
            retryButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44)
        ])

        if ProcessInfo.processInfo.arguments.contains("UITEST_ZOOM_DIAGNOSTICS") {
            zoomDiagnosticsProxy.frame = CGRect(x: 0, y: 0, width: 1, height: 1)
            zoomDiagnosticsProxy.backgroundColor = .clear
            zoomDiagnosticsProxy.isUserInteractionEnabled = false
            zoomDiagnosticsProxy.isAccessibilityElement = true
            zoomDiagnosticsProxy.accessibilityTraits = [.staticText]
            rootView.addSubview(zoomDiagnosticsProxy)
            updateZoomDiagnosticsValue()

            renderProbeDiagnosticsProxy.frame = CGRect(x: 0, y: 1, width: 1, height: 1)
            renderProbeDiagnosticsProxy.backgroundColor = .clear
            renderProbeDiagnosticsProxy.alpha = 0.02
            renderProbeDiagnosticsProxy.isUserInteractionEnabled = false
            renderProbeDiagnosticsProxy.isAccessibilityElement = true
            renderProbeDiagnosticsProxy.accessibilityTraits = [.staticText]
            renderProbeDiagnosticsProxy.accessibilityIdentifier = "full-screen-image-render-probe-result-\(imageIndex)"
            renderProbeDiagnosticsProxy.accessibilityLabel = "图片缩放渲染结果"
            renderProbeDiagnosticsProxy.accessibilityValue = "等待测试"
            rootView.addSubview(renderProbeDiagnosticsProxy)
        }

        configureAccessibility()

        presentationCancellable = transitionState.presentationDidFinish
            .sink { [weak self] in
                // If the full-resolution image completed during the hero,
                // replace the placeholder atomically in the presentation
                // completion transaction. A second 0.1s animation here was
                // the visible flash at the end of the transition.
                self?.commitStashedResolvedImage()
                self?.updateResolvedImageVisibility(animated: false)
                self?.updatePageResidency()
            }
        currentIndexCancellable = transitionState.currentIndexDidChange
            .sink { [weak self] _ in
                self?.updatePageResidency()
            }
        updatePageResidency()
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
        if viewportSize != .zero,
           FullScreenImageZoomPolicy.isZoomed(scrollView.zoomScale) == false {
            zoomContentView.bounds = CGRect(origin: .zero, size: viewportSize)
            zoomContentView.center = CGPoint(
                x: scrollView.bounds.midX,
                y: scrollView.bounds.midY
            )
            scrollView.contentSize = viewportSize
        }
        resolvedImageView.frame = zoomContentView.bounds
        // Same frame as the resolved view; .scaleAspectFit letterboxes the
        // placeholder to the identical rect the resolved image occupies.
        placeholderImageView.frame = zoomContentView.bounds
        centerZoomedContent()
        reportResolvedImageLayoutIfPossible()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard zoomDiagnosticsProxy.superview != nil,
              didScheduleAutomaticRenderProbe == false else { return }
        didScheduleAutomaticRenderProbe = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self, self.viewIfLoaded?.window != nil else { return }
            self.startRenderProbe()
        }
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        zoomContentView
    }

    func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) {
        // Enabling the pan recognizer only after the first zoom callback drops
        // the first part of a real two-finger gesture. Prepare it before UIKit
        // begins applying the scale, while it remains disabled at 100% so the
        // surrounding page view can still handle horizontal paging.
        if coordinatesWithParentPager {
            scrollView.panGestureRecognizer.isEnabled = true
        }
        if zoomDiagnosticsProxy.superview != nil {
            zoomGestureStartTime = CACurrentMediaTime()
            firstZoomCallbackMilliseconds = nil
            previousZoomCallbackTime = nil
            maximumZoomCallbackGapMilliseconds = 0
            zoomCallbackCount = 0
            updateZoomDiagnosticsValue()
        }
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        if isRunningRenderProbe == false {
            recordZoomCallback()
        }
        updateZoomState(updatesAccessibility: UIAccessibility.isVoiceOverRunning)
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
        updateZoomState(updatesAccessibility: true)
        if coordinatesWithParentPager,
           FullScreenImageZoomPolicy.isZoomed(normalizedScale) == false {
            DispatchQueue.main.async { [weak self] in
                guard let self,
                      FullScreenImageZoomPolicy.isZoomed(self.scrollView.zoomScale) == false else {
                    return
                }
                self.scrollView.panGestureRecognizer.isEnabled = false
            }
        }
    }

    func updateAccessibility(imageIndex: Int) {
        self.imageIndex = imageIndex
        configureAccessibility()
        if zoomDiagnosticsProxy.superview != nil {
            updateZoomDiagnosticsValue()
            renderProbeDiagnosticsProxy.accessibilityIdentifier = "full-screen-image-render-probe-result-\(imageIndex)"
        }
    }

    func reportResolvedImageLayoutIfPossible() {
        guard let transitionImage = transitionImage ?? resolvedImage ?? placeholderImage else {
            return
        }
        onImageResolved?(
            transitionImage,
            resolvedImageFrameInWindow(for: transitionImage)
        )
    }

    func requestOriginalImage(ifNewRequest request: Int) {
        guard request > lastOriginalLoadRequest else { return }
        lastOriginalLoadRequest = request
        guard originalLoadState.canRequest else { return }
        Task { @MainActor [weak self] in
            self?.startOriginalImageLoading()
        }
    }

    func prepareForRemoval() {
        renderProbeDisplayLink?.invalidate()
        renderProbeDisplayLink = nil
        loadTask?.cancel()
        loadTask = nil
        highResolutionLoadTask?.cancel()
        highResolutionLoadTask = nil
        metadataTask?.cancel()
        metadataTask = nil
        latestOriginalProgress = nil
        presentationCancellable?.cancel()
        presentationCancellable = nil
        currentIndexCancellable?.cancel()
        currentIndexCancellable = nil
    }

    private func startRenderProbe() {
        guard isRunningRenderProbe == false else { return }
        renderProbeDisplayLink?.invalidate()
        isRunningRenderProbe = true
        renderProbeStartTimestamp = nil
        renderProbePreviousTimestamp = nil
        renderProbeMaximumFrameGapMilliseconds = 0
        renderProbeFrameGapsMilliseconds.removeAll(keepingCapacity: true)
        renderProbeMaximumWorkMilliseconds = 0
        renderProbeFrameCount = 0
        renderProbeDiagnosticsProxy.accessibilityValue = "测试中"

        scrollView.panGestureRecognizer.isEnabled = true
        scrollView.setZoomScale(FullScreenImageZoomPolicy.minimumScale, animated: false)
        let displayLink = CADisplayLink(target: self, selector: #selector(stepRenderProbe(_:)))
        let maximumFramesPerSecond = Float(UIScreen.main.maximumFramesPerSecond)
        displayLink.preferredFrameRateRange = CAFrameRateRange(
            minimum: min(60, maximumFramesPerSecond),
            maximum: maximumFramesPerSecond,
            preferred: maximumFramesPerSecond
        )
        renderProbeDisplayLink = displayLink
        displayLink.add(to: .main, forMode: .common)
    }

    @objc private func stepRenderProbe(_ displayLink: CADisplayLink) {
        if renderProbeStartTimestamp == nil {
            renderProbeStartTimestamp = displayLink.timestamp
        }
        if let renderProbePreviousTimestamp {
            let frameGap = (displayLink.timestamp - renderProbePreviousTimestamp) * 1_000
            renderProbeFrameGapsMilliseconds.append(frameGap)
            renderProbeMaximumFrameGapMilliseconds = max(
                renderProbeMaximumFrameGapMilliseconds,
                frameGap
            )
        }
        renderProbePreviousTimestamp = displayLink.timestamp

        let elapsed = displayLink.timestamp - (renderProbeStartTimestamp ?? displayLink.timestamp)
        let duration: CFTimeInterval = 0.8
        let normalizedProgress = min(max(elapsed / duration, 0), 1)
        let scale = 1 + 0.5 * sin(Double.pi * normalizedProgress)
        let workStart = CACurrentMediaTime()
        scrollView.setZoomScale(CGFloat(scale), animated: false)
        view.layoutIfNeeded()
        renderProbeMaximumWorkMilliseconds = max(
            renderProbeMaximumWorkMilliseconds,
            (CACurrentMediaTime() - workStart) * 1_000
        )
        renderProbeFrameCount += 1

        guard normalizedProgress >= 1 else { return }
        displayLink.invalidate()
        renderProbeDisplayLink = nil
        scrollView.setZoomScale(FullScreenImageZoomPolicy.minimumScale, animated: false)
        if coordinatesWithParentPager {
            scrollView.panGestureRecognizer.isEnabled = false
        }
        isRunningRenderProbe = false
        updateZoomState(updatesAccessibility: true)
        let sortedFrameGaps = renderProbeFrameGapsMilliseconds.sorted()
        let percentile95Index = max(
            0,
            Int((Double(max(sortedFrameGaps.count - 1, 0)) * 0.95).rounded(.down))
        )
        let percentile95FrameGap = sortedFrameGaps.indices.contains(percentile95Index)
            ? sortedFrameGaps[percentile95Index]
            : 0
        renderProbeDiagnosticsProxy.accessibilityValue = [
            "completed=true",
            "maxFPS=\(UIScreen.main.maximumFramesPerSecond)",
            "frames=\(renderProbeFrameCount)",
            "maxFrameGap=\(Int(renderProbeMaximumFrameGapMilliseconds.rounded()))",
            "p95FrameGap=\(Int(percentile95FrameGap.rounded()))",
            "maxWork=\(Int(renderProbeMaximumWorkMilliseconds.rounded()))"
        ].joined(separator: ";")
    }

    @objc private func retryLoading() {
        startLoading(force: true)
    }

    private func startLoadingIfEligible() {
        guard FullScreenImageLoadSchedulingPolicy.allowsLoading(
            pageIndex: imageIndex,
            currentIndex: transitionState.currentIndex,
            didFinishPresentation: transitionState.didFinishPresentation,
            prefetchesAdjacentPages: prefetchesAdjacentPages
        ) else {
            return
        }
        startOriginalMetadataLoadingIfEligible()
        startLoading()
    }

    private func updatePageResidency() {
        guard FullScreenImagePageResidencyPolicy.retainsPage(
            pageIndex: imageIndex,
            currentIndex: transitionState.currentIndex
        ) else {
            evictInactivePageContent()
            return
        }
        startLoadingIfEligible()
    }

    private func evictInactivePageContent() {
        loadTask?.cancel()
        loadTask = nil
        highResolutionLoadTask?.cancel()
        highResolutionLoadTask = nil
        metadataTask?.cancel()
        metadataTask = nil
        didFinishMetadataRequest = false
        activityIndicator.stopAnimating()
        retryButton.isHidden = true

        if originalLoadState == .loading {
            setOriginalLoadState(originalURL == nil ? .unavailable : .available)
        }
        setOriginalLoadProgress(nil)
        originalFileSize = nil
        onOriginalFileSizeChange?(nil)

        resolvedImage = nil
        transitionImage = nil
        resolvedImageView.image = nil
        didRevealResolvedImage = false
        resolvedImageView.alpha = 0
        placeholderImageView.alpha = placeholderImage == nil ? 0 : 1
    }

    private func startOriginalMetadataLoadingIfEligible() {
        guard FullScreenImageMetadataSchedulingPolicy.allowsLoading(
            pageIndex: imageIndex,
            currentIndex: transitionState.currentIndex,
            didFinishPresentation: transitionState.didFinishPresentation
        ),
              didFinishMetadataRequest == false,
              metadataTask == nil,
              let originalURL else {
            return
        }
        didFinishMetadataRequest = true
        metadataTask = Task { @MainActor [weak self] in
            do {
                let fileSize = try await TiebaImageMetadataClient.shared.contentLength(
                    from: originalURL
                )
                guard let self, Task.isCancelled == false else { return }
                self.metadataTask = nil
                self.originalFileSize = fileSize
                self.onOriginalFileSizeChange?(fileSize)
                if let latestOriginalProgress,
                   latestOriginalProgress.expectedBytes == nil,
                   let expectedBytes = fileSize.flatMap({ Int(exactly: $0) }) {
                    self.setOriginalLoadProgress(BoundedURLSessionProgress(
                        receivedBytes: latestOriginalProgress.receivedBytes,
                        expectedBytes: expectedBytes
                    ))
                }
            } catch {
                guard let self else { return }
                self.metadataTask = nil
                // A transient HEAD failure must not suppress the size
                // forever. The next time this page becomes eligible, retry.
                self.didFinishMetadataRequest = false
            }
        }
    }

    private func startLoading(force: Bool = false) {
        if force == false, resolvedImage != nil || loadTask != nil { return }
        loadTask?.cancel()
        retryButton.isHidden = true
        if placeholderImage == nil {
            activityIndicator.startAnimating()
        }
        let urls = FullScreenImageSourcePolicy.automaticPreviewURLs(
            primary: primaryURL,
            fallback: fallbackURL,
            original: originalURL
        )
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let image = try await TiebaImagePipeline.shared.image(
                    from: urls,
                    targetPixelSize: FullScreenImageDecodePolicy.initialTargetPixelSize
                )
                try Task.checkCancellation()
                self.loadTask = nil
                self.activityIndicator.stopAnimating()
                guard FullScreenImageLoadPrecedencePolicy.acceptsPreview(
                    while: self.originalLoadState
                ) else {
                    return
                }
                let loadedAfterPresentation = self.transitionState.didFinishPresentation
                self.resolvedImage = image
                self.transitionImage = image
                // Committing a full-screen bitmap to the layer tree mid-hero
                // contends with the transition's commits. Loads normally start
                // only after the presentation finishes; if one still resolves
                // earlier (forced retry, cache-hit races), stash the bitmap
                // and let the presentation sink commit it in the completion
                // transaction.
                if loadedAfterPresentation {
                    self.resolvedImageView.image = image
                }
                self.updateResolvedImageVisibility(animated:
                    ImagePreviewResolvedImageVisibilityPolicy.animatesResolvedReveal(
                        presentationFinishedBeforeResolution: loadedAfterPresentation
                    )
                )
                self.reportResolvedImageLayoutIfPossible()
            } catch is CancellationError {
                return
            } catch {
                guard Task.isCancelled == false else { return }
                self.loadTask = nil
                self.activityIndicator.stopAnimating()
                self.retryButton.isHidden = self.placeholderImage != nil
            }
        }
    }

    private func commitStashedResolvedImage() {
        guard let resolvedImage, resolvedImageView.image !== resolvedImage else { return }
        resolvedImageView.image = resolvedImage
    }

    private func startOriginalImageLoading() {
        guard originalLoadState.canRequest, let originalURL else {
            setOriginalLoadState(.unavailable)
            return
        }
        // An explicit original-image request owns the visible image tier. Stop
        // the lower-resolution request and also reject any completion already
        // queued on the main actor so it cannot overwrite the original later.
        loadTask?.cancel()
        loadTask = nil
        activityIndicator.stopAnimating()
        retryButton.isHidden = true
        highResolutionLoadTask?.cancel()
        setOriginalLoadState(.loading)
        setOriginalLoadProgress(BoundedURLSessionProgress(
            receivedBytes: 0,
            expectedBytes: originalFileSize.flatMap({ Int(exactly: $0) })
        ))
        highResolutionLoadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let image = try await TiebaImagePipeline.shared.image(
                    from: [originalURL],
                    targetPixelSize: TiebaImageDecodePolicy.maximumDecodedPixelSize,
                    onProgress: { [weak self] progress in
                        await self?.receiveOriginalLoadProgress(progress)
                    }
                )
                try Task.checkCancellation()
                self.highResolutionLoadTask = nil
                self.resolvedImage = image
                // Keep the screen-sized preview as the dismissal texture. A
                // 4096-pixel bitmap adds avoidable GPU pressure to the hero.
                if self.transitionImage == nil {
                    self.transitionImage = image
                    self.reportResolvedImageLayoutIfPossible()
                }
                self.revealOriginalImage(image)
                let completedByteCount = self.originalFileSize.flatMap({ Int(exactly: $0) })
                    ?? self.latestOriginalProgress?.expectedBytes
                    ?? self.latestOriginalProgress?.receivedBytes
                    ?? 1
                self.setOriginalLoadProgress(BoundedURLSessionProgress(
                    receivedBytes: completedByteCount,
                    expectedBytes: completedByteCount
                ))
                self.setOriginalLoadState(.loaded)
            } catch is CancellationError {
                return
            } catch {
                guard Task.isCancelled == false else { return }
                self.highResolutionLoadTask = nil
                self.setOriginalLoadProgress(nil)
                self.setOriginalLoadState(.failed)
                if FullScreenImageLoadPrecedencePolicy
                    .resumesPreviewAfterOriginalFailure(
                        hasResolvedImage: self.resolvedImage != nil
                    ) {
                    self.startLoading(force: true)
                }
            }
        }
    }

    private func receiveOriginalLoadProgress(_ progress: BoundedURLSessionProgress) {
        guard originalLoadState == .loading else { return }
        let expectedBytes = progress.expectedBytes
            ?? originalFileSize.flatMap({ Int(exactly: $0) })
        setOriginalLoadProgress(BoundedURLSessionProgress(
            receivedBytes: progress.receivedBytes,
            expectedBytes: expectedBytes
        ))
    }

    private func setOriginalLoadProgress(_ progress: BoundedURLSessionProgress?) {
        guard latestOriginalProgress != progress else { return }
        latestOriginalProgress = progress
        onOriginalLoadProgressChange?(progress)
    }

    private func revealOriginalImage(_ image: UIImage) {
        let changes = { [weak self] in
            guard let self else { return }
            self.resolvedImageView.image = image
            self.resolvedImageView.alpha = 1
            self.placeholderImageView.alpha = 0
            self.didRevealResolvedImage = true
        }
        guard viewIfLoaded?.window != nil,
              resolvedImageView.image != nil,
              UIAccessibility.isReduceMotionEnabled == false else {
            changes()
            return
        }
        UIView.transition(
            with: zoomContentView,
            duration: 0.18,
            options: [.transitionCrossDissolve, .beginFromCurrentState, .allowUserInteraction],
            animations: changes
        )
    }

    private func setOriginalLoadState(_ state: FullScreenOriginalImageLoadState) {
        guard state != originalLoadState else { return }
        originalLoadState = state
        onOriginalLoadStateChange?(state)
    }

    private func updateResolvedImageVisibility(animated: Bool) {
        let shouldReveal = resolvedImage != nil
            && (placeholderImage == nil || transitionState.didFinishPresentation)
        guard shouldReveal != didRevealResolvedImage else { return }
        didRevealResolvedImage = shouldReveal

        let changes = { [weak self] in
            guard let self else { return }
            self.resolvedImageView.alpha = shouldReveal ? 1 : 0
            self.placeholderImageView.alpha = shouldReveal ? 0 : 1
        }
        if animated,
           viewIfLoaded?.window != nil,
           UIAccessibility.isReduceMotionEnabled == false {
            UIView.animate(
                withDuration: 0.1,
                delay: 0,
                options: [.curveEaseOut, .beginFromCurrentState, .allowUserInteraction],
                animations: changes
            )
        } else {
            changes()
        }
    }

    @objc private func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended else { return }
        performDoubleTapZoom(centeredAt: recognizer.location(in: zoomContentView))
    }

    @objc private func handleSingleTap(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended,
              isCompletingDismissGesture == false else { return }
        onSingleTap?()
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === dismissPanGestureRecognizer,
              transitionState.didFinishPresentation,
              imageIndex == transitionState.currentIndex,
              isCompletingDismissGesture == false else {
            return false
        }
        let pan = dismissPanGestureRecognizer
        activeDismissAxis = FullScreenImageDismissGesturePolicy.axis(
            velocity: pan.velocity(in: view),
            isFirstImage: imageIndex == 0,
            isZoomed: FullScreenImageZoomPolicy.isZoomed(scrollView.zoomScale)
        )
        return activeDismissAxis != nil
    }

    @objc private func handleDismissPan(_ recognizer: UIPanGestureRecognizer) {
        guard let axis = activeDismissAxis else { return }
        let translation = FullScreenImageDismissGesturePolicy.adjustedTranslation(
            recognizer.translation(in: view),
            for: axis
        )
        switch recognizer.state {
        case .changed:
            scrollView.transform = CGAffineTransform(
                translationX: translation.x,
                y: translation.y
            )
            reportResolvedImageLayoutIfPossible()
        case .ended:
            let shouldDismiss = FullScreenImageDismissGesturePolicy.shouldDismiss(
                translation: translation,
                velocity: recognizer.velocity(in: view),
                axis: axis,
                viewportSize: view.bounds.size
            )
            if shouldDismiss {
                isCompletingDismissGesture = true
                reportResolvedImageLayoutIfPossible()
                onInteractiveDismiss?()
            } else {
                restoreImageAfterCancelledDismissal()
            }
            activeDismissAxis = nil
        case .cancelled, .failed:
            restoreImageAfterCancelledDismissal()
            activeDismissAxis = nil
        default:
            break
        }
    }

    private func restoreImageAfterCancelledDismissal() {
        isCompletingDismissGesture = true
        guard UIAccessibility.isReduceMotionEnabled == false else {
            scrollView.transform = .identity
            isCompletingDismissGesture = false
            reportResolvedImageLayoutIfPossible()
            return
        }
        UIView.animate(
            withDuration: 0.28,
            delay: 0,
            usingSpringWithDamping: 0.84,
            initialSpringVelocity: 0,
            options: [.beginFromCurrentState, .allowUserInteraction]
        ) { [weak self] in
            self?.scrollView.transform = .identity
        } completion: { [weak self] _ in
            guard let self else { return }
            self.isCompletingDismissGesture = false
            self.reportResolvedImageLayoutIfPossible()
        }
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        guard gestureRecognizer === dismissPanGestureRecognizer,
              coordinatesWithParentPager,
              let otherPan = otherGestureRecognizer as? UIPanGestureRecognizer,
              otherPan !== scrollView.panGestureRecognizer,
              let ancestorView = otherPan.view else {
            return false
        }
        return view.isDescendant(of: ancestorView)
    }

    private func performDoubleTapZoom(centeredAt requestedLocation: CGPoint? = nil) {
        doubleTapCount += 1
        updateZoomDiagnosticsValue()
        let targetScale = FullScreenImageZoomPolicy.doubleTapTarget(
            currentScale: scrollView.zoomScale
        )
        if targetScale == FullScreenImageZoomPolicy.minimumScale {
            scrollView.setZoomScale(targetScale, animated: true)
            scheduleAccessibilityRefreshAfterZoomAnimation()
            return
        }

        scrollView.panGestureRecognizer.isEnabled = true
        let fallbackLocation = CGPoint(
            x: zoomContentView.bounds.midX,
            y: zoomContentView.bounds.midY
        )
        let location = requestedLocation.flatMap { location in
            zoomContentView.bounds.contains(location) ? location : nil
        } ?? fallbackLocation
        zoom(to: targetScale, centeredAt: location, animated: true)
        scheduleAccessibilityRefreshAfterZoomAnimation()
    }

    private func scheduleAccessibilityRefreshAfterZoomAnimation() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.updateZoomState(updatesAccessibility: true)
        }
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

    private func updateZoomState(updatesAccessibility: Bool) {
        let isZoomed = FullScreenImageZoomPolicy.isZoomed(scrollView.zoomScale)
        if isZoomed != lastReportedZoomed {
            lastReportedZoomed = isZoomed
            onZoomStateChange?(isZoomed)
        }
        centerZoomedContent()
        if updatesAccessibility {
            updateAccessibilityValue()
        }
    }

    private func centerZoomedContent() {
        // UIScrollView already updates contentSize for its zoom view. Moving one
        // layer is substantially cheaper than changing contentInset on every
        // pinch frame (which re-runs scroll-view layout and caused visible lag).
        let contentSize = scrollView.contentSize
        zoomContentView.center = CGPoint(
            x: max(contentSize.width, scrollView.bounds.width) / 2,
            y: max(contentSize.height, scrollView.bounds.height) / 2
        )
    }

    private func resolvedImageFrameInWindow(for image: UIImage) -> CGRect? {
        guard resolvedImageView.window != nil,
              resolvedImageView.bounds.width > 0,
              resolvedImageView.bounds.height > 0 else {
            return nil
        }
        let frame = ImagePreviewTransitionGeometry.aspectFitFrame(
            imageSize: image.size,
            in: resolvedImageView.bounds
        )
        return ImagePreviewTransitionGeometry.validSourceFrame(
            resolvedImageView.convert(frame, to: resolvedImageView.window)
        )
    }

    private func configureAccessibility() {
        scrollView.accessibilityIdentifier = "full-screen-image-zoom-surface-\(imageIndex)"
        scrollView.accessibilityLabel = "全屏图片"
        scrollView.accessibilityTraits = [.image]
        scrollView.accessibilityCustomActions = [
            UIAccessibilityCustomAction(name: "放大图片") { [weak self] _ in
                guard let self else { return false }
                let scale = min(
                    self.scrollView.zoomScale * 2,
                    FullScreenImageZoomPolicy.maximumScale
                )
                self.scrollView.panGestureRecognizer.isEnabled = true
                let center = CGPoint(
                    x: self.zoomContentView.bounds.midX,
                    y: self.zoomContentView.bounds.midY
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
        guard percentage != lastAccessibilityPercentage
                || scrollView.accessibilityValue == nil else {
            return
        }
        lastAccessibilityPercentage = percentage
        scrollView.accessibilityValue = "缩放 \(percentage)%"
        scrollView.accessibilityHint = FullScreenImageZoomPolicy.isZoomed(scrollView.zoomScale)
            ? "单指拖动查看图片，双指捏合或双击缩小"
            : "双指捏合或双击放大，轻点、首图右划或上下拖动返回来源页面"
    }

    private func recordZoomCallback() {
        guard zoomDiagnosticsProxy.superview != nil else { return }
        let now = CACurrentMediaTime()
        if firstZoomCallbackMilliseconds == nil, let zoomGestureStartTime {
            firstZoomCallbackMilliseconds = max(0, (now - zoomGestureStartTime) * 1_000)
        }
        if let previousZoomCallbackTime {
            maximumZoomCallbackGapMilliseconds = max(
                maximumZoomCallbackGapMilliseconds,
                (now - previousZoomCallbackTime) * 1_000
            )
        }
        previousZoomCallbackTime = now
        zoomCallbackCount += 1
        updateZoomDiagnosticsValue()
    }

    private func updateZoomDiagnosticsValue() {
        zoomDiagnosticsProxy.accessibilityIdentifier = "full-screen-image-zoom-diagnostics-\(imageIndex)"
        zoomDiagnosticsProxy.accessibilityLabel = "图片缩放诊断"
        let first = Int((firstZoomCallbackMilliseconds ?? -1).rounded())
        let maximumGap = Int(maximumZoomCallbackGapMilliseconds.rounded())
        zoomDiagnosticsProxy.accessibilityValue = [
            "layer=UIImageView",
            "first=\(first)",
            "maxGap=\(maximumGap)",
            "callbacks=\(zoomCallbackCount)",
            "doubleTaps=\(doubleTapCount)"
        ].joined(separator: ";")
    }
}

struct FullScreenImageView: View {
    private let items: [FullScreenImageItem]
    private let saveAction: (URL) async throws -> Void
    private let onRequestDismiss: (() -> Void)?
    private let onCurrentIndexChange: ((Int) -> Void)?
    private let onCurrentImageResolved: ((Int, UIImage, CGRect?) -> Void)?
    private let onZoomStateChange: ((Int, Bool) -> Void)?
    private let transitionState: ImagePreviewPresentationState
    private let prefetchesAdjacentPages: Bool
    @State private var currentIndex: Int
    @State private var originalLoadStates: [String: FullScreenOriginalImageLoadState]
    @State private var originalLoadRequests: [String: Int]
    @State private var originalLoadProgresses: [String: BoundedURLSessionProgress] = [:]
    @State private var originalFileSizes: [String: Int64] = [:]
    @State private var isDownloading = false
    @State private var downloadTask: Task<Void, Never>?
    @State private var downloadNotice: ImageDownloadNotice?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        url: URL?,
        saveAction: @escaping (URL) async throws -> Void = FullScreenImageView.liveSave,
        onRequestDismiss: (() -> Void)? = nil,
        onCurrentIndexChange: ((Int) -> Void)? = nil,
        onCurrentImageResolved: ((Int, UIImage, CGRect?) -> Void)? = nil
    ) {
        let item = FullScreenImageItem(url: url, index: 0)
        let transitionState = ImagePreviewPresentationState(initialIndex: 0)
        transitionState.markPresentationFinished()
        items = [item]
        self.saveAction = saveAction
        self.onRequestDismiss = onRequestDismiss
        self.onCurrentIndexChange = onCurrentIndexChange
        self.onCurrentImageResolved = onCurrentImageResolved
        onZoomStateChange = nil
        self.transitionState = transitionState
        prefetchesAdjacentPages = true
        _currentIndex = State(initialValue: 0)
        _originalLoadStates = State(initialValue: Self.initialOriginalLoadStates(for: [item]))
        _originalLoadRequests = State(initialValue: [:])
    }

    init(
        session: ImagePreviewSession,
        transitionState: ImagePreviewPresentationState,
        saveAction: @escaping (URL) async throws -> Void = FullScreenImageView.liveSave,
        onRequestDismiss: (() -> Void)? = nil,
        onCurrentIndexChange: ((Int) -> Void)? = nil,
        onCurrentImageResolved: ((Int, UIImage, CGRect?) -> Void)? = nil,
        onZoomStateChange: ((Int, Bool) -> Void)? = nil
    ) {
        let resolvedItems = session.images.enumerated().map { index, image in
            FullScreenImageItem(
                image: image,
                index: index,
                placeholderImage: index == session.initialIndex ? session.sourceImage : nil
            )
        }
        let finalItems = resolvedItems.isEmpty
            ? [FullScreenImageItem(url: nil, index: 0)]
            : resolvedItems
        items = finalItems
        self.saveAction = saveAction
        self.onRequestDismiss = onRequestDismiss
        self.onCurrentIndexChange = onCurrentIndexChange
        self.onCurrentImageResolved = onCurrentImageResolved
        self.onZoomStateChange = onZoomStateChange
        self.transitionState = transitionState
        prefetchesAdjacentPages = session.prefetchesAdjacentPages
        _currentIndex = State(initialValue: ImagePreviewIndexPolicy.clampedIndex(
            session.initialIndex,
            totalCount: resolvedItems.count
        ))
        _originalLoadStates = State(initialValue: Self.initialOriginalLoadStates(for: finalItems))
        _originalLoadRequests = State(initialValue: [:])
    }

    init(
        images: [ImageContent],
        initialIndex: Int,
        saveAction: @escaping (URL) async throws -> Void = FullScreenImageView.liveSave,
        onRequestDismiss: (() -> Void)? = nil,
        onCurrentIndexChange: ((Int) -> Void)? = nil,
        onCurrentImageResolved: ((Int, UIImage, CGRect?) -> Void)? = nil
    ) {
        let resolvedItems = images.enumerated().map { index, image in
            FullScreenImageItem(image: image, index: index)
        }
        let initialIndex = ImagePreviewIndexPolicy.clampedIndex(
            initialIndex,
            totalCount: resolvedItems.count
        )
        let transitionState = ImagePreviewPresentationState(initialIndex: initialIndex)
        transitionState.markPresentationFinished()
        let finalItems = resolvedItems.isEmpty
            ? [FullScreenImageItem(url: nil, index: 0)]
            : resolvedItems
        items = finalItems
        self.saveAction = saveAction
        self.onRequestDismiss = onRequestDismiss
        self.onCurrentIndexChange = onCurrentIndexChange
        self.onCurrentImageResolved = onCurrentImageResolved
        onZoomStateChange = nil
        self.transitionState = transitionState
        prefetchesAdjacentPages = true
        _currentIndex = State(initialValue: initialIndex)
        _originalLoadStates = State(initialValue: Self.initialOriginalLoadStates(for: finalItems))
        _originalLoadRequests = State(initialValue: [:])
    }

    private static func initialOriginalLoadStates(
        for items: [FullScreenImageItem]
    ) -> [String: FullScreenOriginalImageLoadState] {
        Dictionary(uniqueKeysWithValues: items.map { item in
            (item.id, item.originalURL == nil ? .unavailable : .available)
        })
    }

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            Group {
                if items.count == 1, let item = items.first {
                    zoomableImage(item, index: 0)
                        .ignoresSafeArea()
                } else {
                    TabView(selection: $currentIndex) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            zoomableImage(item, index: index)
                                .ignoresSafeArea()
                                .tag(index)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .ignoresSafeArea()
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("图片浏览器")
            .accessibilityIdentifier("full-screen-image-pager")

            VStack(spacing: 0) {
                Spacer(minLength: 0)
                bottomBar
            }
        }
        .accessibilityHint("双指捏合或双击缩放，单指可斜向拖动图片，轻点图片返回来源页面")
        .accessibilityAction(.escape) {
            close()
        }
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
        .onAppear {
            transitionState.setCurrentIndex(currentIndex)
            onCurrentIndexChange?(currentIndex)
        }
        .onChangeCompat(of: currentIndex) { _, index in
            transitionState.setCurrentIndex(index)
            onCurrentIndexChange?(index)
        }
    }

    private func close() {
        if let onRequestDismiss {
            onRequestDismiss()
        } else {
            dismiss()
        }
    }

    private func zoomableImage(
        _ item: FullScreenImageItem,
        index: Int
    ) -> some View {
        FullScreenZoomableRemoteImage(
            primaryURL: item.primaryURL,
            fallbackURL: item.fallbackURL,
            originalURL: item.originalURL,
            imageAspectRatio: item.imageAspectRatio,
            placeholderImage: item.placeholderImage,
            transitionState: transitionState,
            imageIndex: index,
            coordinatesWithParentPager: items.count > 1,
            prefetchesAdjacentPages: prefetchesAdjacentPages,
            originalLoadRequest: originalLoadRequests[item.id, default: 0],
            onImageResolved: { image, frameInWindow in
                onCurrentImageResolved?(index, image, frameInWindow)
            },
            onOriginalLoadStateChange: { state in
                guard originalLoadStates[item.id] != state else { return }
                originalLoadStates[item.id] = state
            },
            onOriginalLoadProgressChange: { progress in
                if let progress {
                    originalLoadProgresses[item.id] = progress
                } else {
                    originalLoadProgresses.removeValue(forKey: item.id)
                }
            },
            onOriginalFileSizeChange: { fileSize in
                if let fileSize {
                    originalFileSizes[item.id] = fileSize
                } else {
                    originalFileSizes.removeValue(forKey: item.id)
                }
            },
            onZoomStateChange: { isZoomed in
                onZoomStateChange?(index, isZoomed)
            },
            onSingleTap: {
                close()
            },
            onInteractiveDismiss: {
                close()
            }
        )
        .contentShape(Rectangle())
    }

    private var bottomBar: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                stackedBottomBar
            } else {
                ViewThatFits(in: .horizontal) {
                    compactBottomBar
                    stackedBottomBar
                }
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, TiebaPureTheme.Spacing.md)
        .padding(.top, TiebaPureTheme.Spacing.md)
        .padding(.bottom, TiebaPureTheme.Spacing.xs)
        .background(
            LinearGradient(
                colors: [.clear, .black.opacity(0.72)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private var compactBottomBar: some View {
        HStack(spacing: TiebaPureTheme.Spacing.sm) {
            if items.count > 1 {
                pageIndicator
            }

            Spacer(minLength: 0)

            viewOriginalButton
            downloadButton
        }
    }

    private var stackedBottomBar: some View {
        VStack(spacing: TiebaPureTheme.Spacing.sm) {
            if items.count > 1 {
                HStack {
                    pageIndicator
                    Spacer(minLength: 0)
                }
            }
            viewOriginalButton
                .frame(maxWidth: .infinity)
            downloadButton
                .frame(maxWidth: .infinity)
        }
    }

    private var pageIndicator: some View {
        Text("\(currentIndex + 1) / \(items.count)")
            .font(.footnote.monospacedDigit().weight(.semibold))
            .accessibilityIdentifier("image-page-indicator")
            .accessibilityLabel("第\(currentIndex + 1)张，共\(items.count)张")
    }

    private var viewOriginalButton: some View {
        Button {
            requestCurrentOriginalImage()
        } label: {
            stableOriginalButtonLabel
                .font((dynamicTypeSize.isAccessibilitySize
                    ? Font.body
                    : Font.footnote).weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .frame(
                    maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : nil,
                    minHeight: dynamicTypeSize.isAccessibilitySize ? 52 : 34
                )
                .background {
                    originalButtonBackground
                }
        }
        .buttonStyle(.plain)
        .frame(minWidth: 44, minHeight: 44)
        .contentShape(Rectangle())
        .disabled(currentOriginalLoadState.canRequest == false)
        .accessibilityIdentifier("view-original-image")
        .accessibilityLabel(originalImageAccessibilityLabel)
        .accessibilityHint(currentOriginalLoadState.canRequest
            ? "加载当前图片的高清原图"
            : "")
    }

    @ViewBuilder
    private var stableOriginalButtonLabel: some View {
        if dynamicTypeSize.isAccessibilitySize {
            originalButtonLabel
        } else {
            ZStack {
                HStack(spacing: TiebaPureTheme.Spacing.xs) {
                    Image(systemName: "checkmark.circle.fill")
                    Text("查看原图 30.0MB")
                }
                .hidden()
                .accessibilityHidden(true)
                originalButtonLabel
            }
        }
    }

    @ViewBuilder
    private var originalButtonLabel: some View {
        if currentOriginalLoadState == .loading {
            Text(originalImageButtonTitle)
                .fontDesign(.monospaced)
                .lineLimit(1)
        } else if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: TiebaPureTheme.Spacing.xs) {
                originalButtonStatusIcon
                Text(originalImageButtonTitle)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
        } else {
            HStack(spacing: TiebaPureTheme.Spacing.xs) {
                originalButtonStatusIcon
                Text(originalImageButtonTitle)
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private var originalButtonStatusIcon: some View {
        switch currentOriginalLoadState {
        case .loading:
            ProgressView()
                .tint(.white)
                .controlSize(.small)
        case .loaded:
            Image(systemName: "checkmark.circle.fill")
        case .failed:
            Image(systemName: "arrow.clockwise")
        case .unavailable:
            Image(systemName: "photo.badge.exclamationmark")
        case .available:
            Image(systemName: "arrow.up.left.and.arrow.down.right")
        }
    }

    private var originalImageButtonTitle: String {
        switch currentOriginalLoadState {
        case .available:
            if let currentOriginalSizeText {
                "查看原图 \(currentOriginalSizeText)"
            } else {
                "查看原图"
            }
        case .loading:
            if let fraction = currentOriginalProgress?.fractionCompleted {
                "\(Int((fraction * 100).rounded()))%"
            } else {
                "0%"
            }
        case .loaded: "原图已加载"
        case .failed: "重试原图"
        case .unavailable: "无原图"
        }
    }

    private var originalButtonBackground: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Color.black.opacity(currentOriginalLoadState.canRequest ? 0.55 : 0.78)
                if currentOriginalLoadState == .loading {
                    Color.white.opacity(0.24)
                        .frame(width: proxy.size.width * currentOriginalProgressFraction)
                        .animation(
                            reduceMotion ? nil : .linear(duration: 0.12),
                            value: currentOriginalProgressFraction
                        )
                }
            }
            .clipShape(RoundedRectangle(
                cornerRadius: TiebaPureTheme.Radius.media,
                style: .continuous
            ))
            .accessibilityHidden(true)
        }
    }

    private var downloadButton: some View {
        Button {
            saveCurrentImage()
        } label: {
            ZStack {
                if dynamicTypeSize.isAccessibilitySize == false {
                    HStack(spacing: TiebaPureTheme.Spacing.xs) {
                        Image(systemName: "arrow.down.to.line")
                        Text("下载中")
                    }
                    .hidden()
                    .accessibilityHidden(true)
                }
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(spacing: TiebaPureTheme.Spacing.xs) {
                        downloadButtonStatusIcon
                        Text(isDownloading ? "下载中" : "下载")
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                    }
                } else {
                    HStack(spacing: TiebaPureTheme.Spacing.xs) {
                        downloadButtonStatusIcon
                        Text(isDownloading ? "下载中" : "下载")
                            .lineLimit(1)
                    }
                }
            }
            .font((dynamicTypeSize.isAccessibilitySize
                ? Font.body
                : Font.footnote).weight(.semibold))
            .padding(.horizontal, 8)
            .frame(
                maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : nil,
                minHeight: dynamicTypeSize.isAccessibilitySize ? 52 : 34
            )
            .background(.black.opacity(0.45), in: RoundedRectangle(
                cornerRadius: TiebaPureTheme.Radius.media,
                style: .continuous
            ))
        }
        .buttonStyle(.plain)
        .frame(minWidth: 44, minHeight: 44)
        .contentShape(Rectangle())
        .disabled(isDownloading || currentDownloadURL == nil)
        .accessibilityIdentifier("save-current-image")
        .accessibilityLabel(isDownloading ? "正在下载图片" : "下载图片")
        .accessibilityHint("下载当前图片并保存到系统照片")
    }

    @ViewBuilder
    private var downloadButtonStatusIcon: some View {
        if isDownloading {
            ProgressView()
                .tint(.white)
                .controlSize(.small)
        } else {
            Image(systemName: "arrow.down.to.line")
        }
    }

    private var currentOriginalLoadState: FullScreenOriginalImageLoadState {
        guard let item = currentItem else { return .unavailable }
        return originalLoadStates[item.id]
            ?? (item.originalURL == nil ? .unavailable : .available)
    }

    private var currentOriginalProgress: BoundedURLSessionProgress? {
        guard let item = currentItem else { return nil }
        return originalLoadProgresses[item.id]
    }

    private var currentOriginalSizeText: String? {
        guard let item = currentItem,
              let byteCount = originalFileSizes[item.id] else {
            return nil
        }
        return FullScreenImageFileSizePolicy.displayString(byteCount: byteCount)
    }

    private var currentOriginalProgressFraction: CGFloat {
        CGFloat(min(max(currentOriginalProgress?.fractionCompleted ?? 0, 0), 1))
    }

    private var originalImageAccessibilityLabel: String {
        switch currentOriginalLoadState {
        case .available:
            if let currentOriginalSizeText {
                "查看原图，大小 \(currentOriginalSizeText)"
            } else {
                "查看原图"
            }
        case .loading:
            if let fraction = currentOriginalProgress?.fractionCompleted {
                "原图下载进度，\(Int((fraction * 100).rounded()))%"
            } else {
                "原图下载进度，0%"
            }
        case .loaded: "原图已加载"
        case .failed: "原图加载失败，点按重试"
        case .unavailable: "没有可用原图"
        }
    }

    private var currentItem: FullScreenImageItem? {
        guard items.indices.contains(currentIndex) else { return nil }
        return items[currentIndex]
    }

    private func requestCurrentOriginalImage() {
        guard let item = currentItem, currentOriginalLoadState.canRequest else { return }
        originalLoadRequests[item.id, default: 0] += 1
    }

    private var currentDownloadURL: URL? {
        currentItem?.downloadURL
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
                    message: "图片已保存到系统照片。"
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

    static func liveSave(url: URL) async throws {
        let payload = try await TiebaImageDownloadClient.shared.download(from: url)
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
    private static let sourceIdentity = "image-viewer-ui-test-source"
    @StateObject private var previewSource = ImagePreviewSourceAnchor(
        sourceIdentity: Self.sourceIdentity
    )
    @State private var didPresent = false

    private let fixtureImage = ImageContent(
        thumbnailURL: URL(string: "https://fixture-success.invalid/viewer-thumbnail.png"),
        originalURL: URL(string: "https://fixture-success.invalid/viewer-original.png"),
        width: 120,
        height: 480,
        showOriginalButton: true
    )
    private let secondFixtureImage = ImageContent(
        thumbnailURL: URL(string: "https://fixture-success.invalid/viewer-second-thumbnail.png"),
        originalURL: URL(string: "https://fixture-success.invalid/viewer-second-original.png"),
        width: 480,
        height: 240,
        showOriginalButton: true
    )

    private static let croppedThumbnailFixture: UIImage = {
        let size = CGSize(width: 240, height: 240)
        return UIGraphicsImageRenderer(size: size).image { context in
            let bounds = CGRect(origin: .zero, size: size)
            context.cgContext.setFillColor(UIColor.systemOrange.cgColor)
            context.cgContext.fill(bounds)
            context.cgContext.setFillColor(UIColor.systemPink.cgColor)
            context.cgContext.fill(CGRect(
                x: size.width * 0.58,
                y: 0,
                width: size.width * 0.42,
                height: size.height
            ))
            context.cgContext.setFillColor(UIColor.white.cgColor)
            context.cgContext.fillEllipse(in: CGRect(x: 20, y: 20, width: 64, height: 64))
            context.cgContext.setFillColor(UIColor.black.cgColor)
            context.cgContext.fill(CGRect(x: 24, y: 172, width: 192, height: 32))
        }
    }()

    private static let regularThumbnailFixture: UIImage = {
        let size = CGSize(width: 120, height: 480)
        return UIGraphicsImageRenderer(size: size).image { context in
            let bounds = CGRect(origin: .zero, size: size)
            context.cgContext.setFillColor(UIColor.systemBlue.cgColor)
            context.cgContext.fill(bounds)
            context.cgContext.setFillColor(UIColor.systemTeal.cgColor)
            context.cgContext.fill(CGRect(
                x: 0,
                y: size.height * 0.58,
                width: size.width,
                height: size.height * 0.42
            ))
            context.cgContext.setFillColor(UIColor.white.cgColor)
            context.cgContext.fillEllipse(in: CGRect(x: 24, y: 36, width: 72, height: 72))
        }
    }()

    private var usesCroppedThumbnailFixture: Bool {
        ProcessInfo.processInfo.arguments.contains("UITEST_IMAGE_VIEWER_CROPPED_THUMBNAIL")
    }

    private var fixtureImages: [ImageContent] {
        if ProcessInfo.processInfo.arguments.contains("UITEST_IMAGE_VIEWER_MULTIPLE") {
            return [fixtureImage, secondFixtureImage]
        }
        return [fixtureImage]
    }

    var body: some View {
        VStack(spacing: TiebaPureTheme.Spacing.md) {
            Text("图片来源页")
                .accessibilityIdentifier("image-viewer-source")

            Button(action: presentPreview) {
                sourceThumbnail
                .frame(width: 96, height: 180)
                .contentShape(Rectangle())
                .clipShape(RoundedRectangle(
                    cornerRadius: TiebaPureTheme.Radius.media,
                    style: .continuous
                ))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("image-viewer-source-image")
            .accessibilityLabel("查看测试图片")
        }
        .task {
            guard didPresent == false else { return }
            for _ in 0..<50 {
                if previewSource.frameInWindow != nil, previewSource.image != nil {
                    didPresent = true
                    presentPreview()
                    return
                }
                do {
                    try await Task.sleep(nanoseconds: 20_000_000)
                } catch {
                    return
                }
            }
        }
    }

    @ViewBuilder
    private var sourceThumbnail: some View {
        let image = usesCroppedThumbnailFixture
            ? Self.croppedThumbnailFixture
            : Self.regularThumbnailFixture
        ImagePreviewSourceAnchorReader(
            anchor: previewSource,
            sourceIdentity: Self.sourceIdentity
        )
            .onAppear {
                previewSource.store(
                    image: image,
                    sourceIdentity: Self.sourceIdentity
                )
            }
    }

    private func presentPreview() {
        guard let sourceFrame = previewSource.frameInWindow else { return }
        ImagePreviewCoordinator.shared.present(
            ImagePreviewSession(
                images: fixtureImages,
                initialIndex: 0,
                sourceFrame: sourceFrame,
                sourceImage: previewSource.image,
                sourceAnchor: previewSource
            ),
            saveAction: { _ in }
        )
    }
}

struct ReaderMediaPolicyUITestHost: View {
    @State private var mediaGridAction = "等待媒体网格操作"

    private let image = ImageContent(
        thumbnailURL: URL(string: "https://fixture.invalid/media-policy-thumbnail.png"),
        originalURL: URL(string: "https://fixture-success.invalid/media-policy-original.png"),
        width: 640,
        height: 400,
        showOriginalButton: true
    )
    private var video: VideoContent {
        let successfulCover = ProcessInfo.processInfo.arguments.contains(
            "UITEST_VIDEO_PREVIEW_HERO"
        )
        return VideoContent(
            videoURL: URL(string: "https://fixture-success.invalid/media-policy-video.mp4"),
            coverURL: URL(string: successfulCover
                ? "https://fixture-success.invalid/media-policy-video-cover.png"
                : "https://fixture.invalid/media-policy-video-cover.png"),
            webURL: nil,
            width: 640,
            height: 360,
            duration: 12
        )
    }

    private var mediaGridVideoItem: ReaderMediaItem {
        ReaderMediaItem(
            id: "policy-video",
            kind: .video,
            thumbnailURL: video.coverURL,
            video: video,
            aspectRatio: CGFloat(video.aspectRatio),
            accessibilityLabel: "测试视频"
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TiebaPureTheme.Spacing.lg) {
                ImageViewer(image: image)
                VideoPlayerView(video: video)
                MediaGridView(items: [mediaGridVideoItem]) { _, _, _, _ in
                    mediaGridAction = "已打开媒体网格目标"
                }
                Text(mediaGridAction)
                    .accessibilityIdentifier("reader-media-grid-action")
            }
            .padding()
        }
        .accessibilityIdentifier("reader-media-policy-host")
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

enum FullScreenImageDismissAxis: Equatable {
    case horizontalRight
    case vertical
}

enum FullScreenImageDismissGesturePolicy {
    private static let horizontalPagingDominance: CGFloat = 1.15

    static func axis(
        velocity: CGPoint,
        isFirstImage: Bool,
        isZoomed: Bool
    ) -> FullScreenImageDismissAxis? {
        guard isZoomed == false else { return nil }
        let horizontalSpeed = abs(velocity.x)
        let verticalSpeed = abs(velocity.y)
        if horizontalSpeed > verticalSpeed * horizontalPagingDominance {
            return isFirstImage && velocity.x > 0 ? .horizontalRight : nil
        }
        return verticalSpeed > 0 ? .vertical : nil
    }

    static func adjustedTranslation(
        _ translation: CGPoint,
        for axis: FullScreenImageDismissAxis
    ) -> CGPoint {
        switch axis {
        case .horizontalRight:
            return CGPoint(x: max(translation.x, 0), y: translation.y)
        case .vertical:
            return translation
        }
    }

    static func shouldDismiss(
        translation: CGPoint,
        velocity: CGPoint,
        axis: FullScreenImageDismissAxis,
        viewportSize: CGSize
    ) -> Bool {
        switch axis {
        case .horizontalRight:
            let distanceThreshold = min(max(viewportSize.width * 0.24, 88), 160)
            return translation.x >= distanceThreshold
                || (translation.x >= 44 && velocity.x >= 900)
        case .vertical:
            let distanceThreshold = min(max(viewportSize.height * 0.18, 120), 180)
            return abs(translation.y) >= distanceThreshold
                || (abs(translation.y) >= 60 && abs(velocity.y) >= 1_000)
        }
    }
}

enum FullScreenImageFileSizePolicy {
    static func displayString(byteCount: Int64) -> String? {
        guard byteCount > 0 else { return nil }
        let kibibyte = 1_024.0
        let mebibyte = kibibyte * kibibyte
        let value = Double(byteCount)
        if value >= mebibyte {
            return compactDecimal(value / mebibyte) + "MB"
        }
        if value >= kibibyte {
            return compactDecimal(value / kibibyte) + "KB"
        }
        return "\(byteCount)B"
    }

    private static func compactDecimal(_ value: Double) -> String {
        let formatted = String(format: "%.1f", value)
        return formatted.hasSuffix(".0") ? String(formatted.dropLast(2)) : formatted
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
