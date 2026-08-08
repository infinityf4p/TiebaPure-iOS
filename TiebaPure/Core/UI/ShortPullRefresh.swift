import SwiftUI
import UIKit

/// Pure geometry and threshold decisions shared by the reusable refresh
/// modifier and the legacy feature call sites that are still being migrated.
enum ShortPullRefreshPolicy {
    static let triggerDistance: CGFloat = 80
    static let heldContentDistance: CGFloat = 44
    static let topTolerance: CGFloat = 2
    static let verticalDominance: CGFloat = 1.2
    static let rubberBandCoefficient: CGFloat = 0.55
    static var minimumVisibleDurationNanoseconds: UInt64 {
        minimumVisibleDurationNanoseconds(arguments: ProcessInfo.processInfo.arguments)
    }

    static func minimumVisibleDurationNanoseconds(arguments: [String]) -> UInt64 {
        #if DEBUG
        if arguments.contains("UITEST_RESELECT_REFRESH_HOLD") {
            return 10_000_000_000
        }
        if arguments.contains("UITEST_EXTENDED_REFRESH_ANIMATION") {
            return 5_000_000_000
        }
        #endif

        return 600_000_000
    }

    static func signedDistanceFromTop(contentOffsetY: CGFloat, topInset: CGFloat) -> CGFloat {
        contentOffsetY + topInset
    }

    static func distanceFromTop(contentOffsetY: CGFloat, topInset: CGFloat) -> CGFloat {
        max(signedDistanceFromTop(contentOffsetY: contentOffsetY, topInset: topInset), 0)
    }

    static func pullDistance(contentOffsetY: CGFloat, topInset: CGFloat) -> CGFloat {
        max(-signedDistanceFromTop(contentOffsetY: contentOffsetY, topInset: topInset), 0)
    }

    /// Converts the scroll view's rubber-banded content displacement back to
    /// an approximate finger travel distance. UIKit compresses overscroll, so
    /// comparing raw `contentOffset` against 80 would require the user to drag
    /// far more than 80 points on screen.
    static func fingerEquivalentPullDistance(
        overscrollDistance: CGFloat,
        viewportLength: CGFloat
    ) -> CGFloat {
        let overscroll = max(overscrollDistance, 0)
        guard overscroll > 0 else { return 0 }
        guard viewportLength > overscroll else {
            return overscroll / rubberBandCoefficient
        }
        return overscroll * viewportLength
            / (rubberBandCoefficient * (viewportLength - overscroll))
    }

    static func distanceFromTop(markerOffset: CGFloat) -> CGFloat {
        max(-markerOffset, 0)
    }

    static func isAtTop(distanceFromTop: CGFloat) -> Bool {
        distanceFromTop <= topTolerance
    }

    static func shouldBegin(
        distanceFromTop: CGFloat,
        initialTranslation: CGSize
    ) -> Bool {
        guard isAtTop(distanceFromTop: distanceFromTop) else { return false }
        guard initialTranslation.height > 0 else { return false }
        return initialTranslation.height >= abs(initialTranslation.width) * verticalDominance
    }

    /// Classifies the existing scroll view pan without adding a competing
    /// gesture recognizer. `nil` means the finger has not moved far enough to
    /// determine intent yet.
    static func verticalPullIntent(translation: CGSize) -> Bool? {
        let horizontalDistance = abs(translation.width)
        let verticalDistance = abs(translation.height)
        guard max(horizontalDistance, verticalDistance) >= 4 else { return nil }
        guard translation.height > 0 else { return false }
        return translation.height >= horizontalDistance * verticalDominance
    }

    static func shouldBegin(distanceFromTop: CGFloat, isRefreshing: Bool) -> Bool {
        isRefreshing == false && isAtTop(distanceFromTop: distanceFromTop)
    }

    static func shouldTrigger(
        startedAtTop: Bool,
        isRefreshing: Bool,
        translation: CGSize
    ) -> Bool {
        guard startedAtTop, isRefreshing == false else { return false }
        guard translation.height >= triggerDistance else { return false }
        return translation.height >= abs(translation.width) * verticalDominance
    }

    static func shouldTrigger(
        startedAtTop: Bool,
        isRefreshing: Bool,
        pullDistance: CGFloat
    ) -> Bool {
        startedAtTop && isRefreshing == false && pullDistance >= triggerDistance
    }

    static func shouldTrigger(
        startedAtTop: Bool,
        isRefreshing: Bool,
        reachedThreshold: Bool
    ) -> Bool {
        startedAtTop && isRefreshing == false && reachedThreshold
    }

    /// 0...1 fraction of the release threshold covered by the current drag.
    static func pullProgress(translation: CGSize) -> CGFloat {
        guard translation.height > 0 else { return 0 }
        return pullProgress(pullDistance: translation.height)
    }

    static func pullProgress(pullDistance: CGFloat) -> CGFloat {
        min(max(pullDistance / triggerDistance, 0), 1)
    }

    static func heldContentOffset(
        pullDistance: CGFloat,
        isRefreshing: Bool
    ) -> CGFloat {
        guard isRefreshing else { return 0 }
        return max(heldContentDistance - min(max(pullDistance, 0), heldContentDistance), 0)
    }

    static func remainingVisibleDurationNanoseconds(elapsed: UInt64) -> UInt64 {
        minimumVisibleDurationNanoseconds > elapsed
            ? minimumVisibleDurationNanoseconds - elapsed
            : 0
    }
}

enum ShortPullRefreshSource: Sendable {
    case pullGesture
    case programmatic
}

enum ShortPullRefreshSurface: Equatable, Sendable {
    case grouped
    case plain

    var color: Color {
        Color(uiColor: uiColor)
    }

    var uiColor: UIColor {
        switch self {
        case .grouped:
            .systemGroupedBackground
        case .plain:
            .systemBackground
        }
    }
}

/// Small equatable projection keeps `onScrollGeometryChange` updates limited to
/// the values that actually affect pull-to-refresh.
struct ShortPullRefreshGeometry: Equatable {
    static let awayFromTopDistance = ShortPullRefreshPolicy.topTolerance + 1

    var distanceFromTop: CGFloat
    var pullDistance: CGFloat
    var fingerEquivalentPullDistance: CGFloat

    static let zero = ShortPullRefreshGeometry(
        distanceFromTop: 0,
        pullDistance: 0,
        fingerEquivalentPullDistance: 0
    )

    init(
        distanceFromTop: CGFloat,
        pullDistance: CGFloat,
        fingerEquivalentPullDistance: CGFloat? = nil
    ) {
        self.distanceFromTop = distanceFromTop
        self.pullDistance = pullDistance
        self.fingerEquivalentPullDistance = fingerEquivalentPullDistance ?? pullDistance
    }

    init(
        contentOffsetY: CGFloat,
        topInset: CGFloat,
        viewportLength: CGFloat? = nil
    ) {
        let signedDistance = ShortPullRefreshPolicy.signedDistanceFromTop(
            contentOffsetY: contentOffsetY,
            topInset: topInset
        )
        if signedDistance > ShortPullRefreshPolicy.topTolerance {
            distanceFromTop = Self.awayFromTopDistance
            pullDistance = 0
            fingerEquivalentPullDistance = 0
            return
        }

        distanceFromTop = max(signedDistance, 0)
        pullDistance = max(-signedDistance, 0)
        if let viewportLength {
            fingerEquivalentPullDistance = ShortPullRefreshPolicy.fingerEquivalentPullDistance(
                overscrollDistance: pullDistance,
                viewportLength: viewportLength
            )
        } else {
            fingerEquivalentPullDistance = pullDistance
        }
    }

    init(scrollView: UIScrollView) {
        self.init(
            contentOffsetY: scrollView.contentOffset.y,
            topInset: scrollView.adjustedContentInset.top,
            viewportLength: scrollView.bounds.height
        )
    }

    @available(iOS 18.0, *)
    init(_ geometry: ScrollGeometry) {
        self.init(
            contentOffsetY: geometry.contentOffset.y,
            topInset: geometry.contentInsets.top,
            viewportLength: geometry.containerSize.height
        )
    }
}

extension View {
    /// Adds a short-distance refresh interaction without installing another
    /// gesture recognizer or changing the scroll view's content inset.
    ///
    /// Apply this modifier directly to a vertical `ScrollView` or `List`.
    func shortPullRefresh(
        isEnabled: Bool = true,
        surface: ShortPullRefreshSurface = .grouped,
        accessibilityIdentifier: String = "short-pull-refresh-indicator",
        action: @escaping () async -> Void
    ) -> some View {
        modifier(
            ShortPullRefreshModifier(
                isEnabled: isEnabled,
                surface: surface,
                accessibilityIdentifier: accessibilityIdentifier,
                programmaticRefreshToken: 0,
                action: { _ in await action() }
            )
        )
    }

    /// Adds the same interaction with an optional programmatic trigger. A
    /// changed token starts a refresh through the exact state machine used by
    /// a released pull, so content displacement and the indicator stay
    /// visually identical.
    func shortPullRefresh(
        isEnabled: Bool = true,
        surface: ShortPullRefreshSurface = .grouped,
        accessibilityIdentifier: String = "short-pull-refresh-indicator",
        programmaticRefreshToken: Int,
        action: @escaping (ShortPullRefreshSource) async -> Void
    ) -> some View {
        modifier(
            ShortPullRefreshModifier(
                isEnabled: isEnabled,
                surface: surface,
                accessibilityIdentifier: accessibilityIdentifier,
                programmaticRefreshToken: programmaticRefreshToken,
                action: action
            )
        )
    }

    @ViewBuilder
    func scrollFrameProbeForUITests() -> some View {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("UITEST_SCROLL_FRAME_PROBE") {
            modifier(ScrollFrameProbeModifier())
        } else {
            self
        }
        #else
        self
        #endif
    }

}

#if DEBUG
private struct ScrollFrameProbeSample: Codable, Sendable {
    var frameIntervals: [TimeInterval]
    var expectedFrameIntervals: [TimeInterval]
    var intervalRatios: [Double]
    var activeFrameCount: Int
    var maximumFramesPerSecond: Int
}

private actor ScrollFrameProbeWriter {
    private var latestRevision = 0

    func write(
        samples: [ScrollFrameProbeSample],
        revision: Int,
        to outputURL: URL
    ) {
        guard revision > latestRevision else { return }
        latestRevision = revision
        guard let data = try? JSONEncoder().encode(samples) else { return }
        try? data.write(to: outputURL, options: .atomic)
    }
}

@MainActor
private final class ScrollFrameProbe: NSObject {
    static let shared = ScrollFrameProbe()

    private var displayLink: CADisplayLink?
    private var previousTimestamp: CFTimeInterval?
    private var previousExpectedInterval: CFTimeInterval?
    private var intervals: [TimeInterval] = []
    private var expectedIntervals: [TimeInterval] = []
    private var intervalRatios: [Double] = []
    private var activeFrameCount: Int?
    private var samples: [ScrollFrameProbeSample] = []
    private let writer = ScrollFrameProbeWriter()
    private var writeRevision = 0
    private var delayedFinishTask: Task<Void, Never>?

    private var outputURL: URL {
        let variant = ProcessInfo.processInfo.environment["TIEBAPURE_SCROLL_FIXTURE_VARIANT"]
            ?? "mixed"
        return FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TiebaPureScrollFrameProbe-\(variant).json")
    }

    override private init() {
        super.init()
        try? FileManager.default.removeItem(at: outputURL)
    }

    func begin() {
        delayedFinishTask?.cancel()
        delayedFinishTask = nil
        finish(writeEmptySample: displayLink != nil)
        intervals = []
        expectedIntervals = []
        intervalRatios = []
        intervals.reserveCapacity(240)
        expectedIntervals.reserveCapacity(240)
        intervalRatios.reserveCapacity(240)
        activeFrameCount = nil
        previousTimestamp = nil
        previousExpectedInterval = nil
        let link = CADisplayLink(target: self, selector: #selector(handleFrame(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func finish() {
        delayedFinishTask?.cancel()
        delayedFinishTask = nil
        finish(writeEmptySample: true)
    }

    func finishAfterIdle() {
        delayedFinishTask?.cancel()
        activeFrameCount = intervals.count
        delayedFinishTask = Task { @MainActor in
            do {
                try await CompatibleTaskSleep.milliseconds(650)
            } catch {
                return
            }
            finish()
        }
    }

    private func finish(writeEmptySample: Bool) {
        displayLink?.invalidate()
        displayLink = nil
        previousTimestamp = nil
        previousExpectedInterval = nil
        guard writeEmptySample, intervals.isEmpty == false else { return }

        samples.append(
            ScrollFrameProbeSample(
                frameIntervals: intervals,
                expectedFrameIntervals: expectedIntervals,
                intervalRatios: intervalRatios,
                activeFrameCount: min(activeFrameCount ?? intervals.count, intervals.count),
                maximumFramesPerSecond: UIScreen.main.maximumFramesPerSecond
            )
        )
        intervals = []
        expectedIntervals = []
        intervalRatios = []
        activeFrameCount = nil
        writeRevision += 1
        let revision = writeRevision
        let snapshot = samples
        let outputURL = outputURL
        Task {
            await writer.write(
                samples: snapshot,
                revision: revision,
                to: outputURL
            )
        }
    }

    @objc private func handleFrame(_ displayLink: CADisplayLink) {
        let fallbackInterval = 1.0 / Double(max(UIScreen.main.maximumFramesPerSecond, 1))
        let targetInterval = displayLink.targetTimestamp - displayLink.timestamp
        let currentExpectedInterval = targetInterval.isFinite && targetInterval > 0
            ? targetInterval
            : fallbackInterval
        if let previousTimestamp, let previousExpectedInterval {
            let interval = displayLink.timestamp - previousTimestamp
            // ProMotion may legitimately move between 120/80/60 Hz. The
            // slower of the adjacent target periods is the budget for this
            // transition; a fixed 1/120s denominator reports those changes as
            // false dropped frames on iOS 26 simulators.
            let expectedInterval = max(previousExpectedInterval, currentExpectedInterval)
            intervals.append(interval)
            expectedIntervals.append(expectedInterval)
            intervalRatios.append(interval / expectedInterval)
        }
        previousTimestamp = displayLink.timestamp
        previousExpectedInterval = currentExpectedInterval
    }
}

private struct ScrollFrameProbeModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollPhaseChange { oldPhase, newPhase in
                let wasDirect = oldPhase == .tracking || oldPhase == .interacting
                let isDirect = newPhase == .tracking || newPhase == .interacting
                if isDirect, wasDirect == false {
                    ScrollFrameProbe.shared.begin()
                }
                if newPhase == .idle, oldPhase != .idle {
                    ScrollFrameProbe.shared.finishAfterIdle()
                }
            }
        } else {
            content
        }
    }
}
#endif

private struct ShortPullRefreshModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let isEnabled: Bool
    let surface: ShortPullRefreshSurface
    let accessibilityIdentifier: String
    let programmaticRefreshToken: Int
    let action: (ShortPullRefreshSource) async -> Void

    @State private var geometry = ShortPullRefreshGeometry.zero
    @State private var isDirectlyInteracting = false
    @State private var gestureStartedAtTop = false
    @State private var pullProgress: CGFloat = 0
    @State private var didReachThreshold = false
    @State private var isRefreshing = false
    @State private var activeRefreshSource: ShortPullRefreshSource?
    @State private var refreshTask: Task<Void, Never>?
    @State private var verticalPanIntent: Bool?

    func body(content: Content) -> some View {
        content
            .background {
                ShortPullScrollViewPanObserver(
                    surfaceColor: surface.uiColor,
                    onStateChange: handlePanChange,
                    onGeometryChange: { updateGeometry($0) },
                    onDirectInteractionChange: handleDirectInteractionChange
                )
                    .accessibilityHidden(true)
            }
            .offset(y: heldContentOffset)
            .animation(
                reduceMotion ? nil : .easeInOut(duration: 0.22),
                value: isRefreshing
            )
            .background {
                surface.color
                    .accessibilityHidden(true)
            }
            .overlay(alignment: .top) {
                refreshOverlay
                    .allowsHitTesting(false)
            }
            .onDisappear {
                cancelRefresh()
            }
            .onChange(of: isEnabled) { enabled in
                if enabled == false {
                    resetGesture()
                }
            }
            .onChangeCompat(of: programmaticRefreshToken) { oldValue, newValue in
                guard oldValue != newValue else { return }
                startRefresh(source: .programmatic)
            }
    }

    private var heldContentOffset: CGFloat {
        let compensatingPullDistance: CGFloat
        switch activeRefreshSource {
        case .pullGesture:
            compensatingPullDistance = geometry.pullDistance
        case .programmatic, nil:
            // Programmatic refresh has no finger-driven rubber-band movement
            // to compensate. Scroll-to-top can briefly publish a synthetic
            // negative offset, which must not shrink the requested 44pt hold.
            compensatingPullDistance = 0
        }
        return ShortPullRefreshPolicy.heldContentOffset(
            pullDistance: compensatingPullDistance,
            isRefreshing: isRefreshing
        )
    }

    @ViewBuilder
    private var refreshOverlay: some View {
        if isRefreshing {
            ShortPullRadialIndicator(progress: 1, isRefreshing: true)
                .frame(width: 36, height: 36)
                .background(.ultraThinMaterial, in: Circle())
                .padding(.top, 8)
                .accessibilityLabel("正在刷新")
                .accessibilityIdentifier(accessibilityIdentifier)
        } else if gestureStartedAtTop, pullProgress > 0 {
            ShortPullRadialIndicator(progress: pullProgress, isRefreshing: false)
                .frame(width: 36, height: 36)
                .background(.ultraThinMaterial, in: Circle())
                .padding(.top, 8)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    pullProgress >= 1 ? "松开即可刷新" : "下拉刷新"
                )
                .accessibilityValue("\(Int((pullProgress * 100).rounded()))%")
                .accessibilityIdentifier(accessibilityIdentifier)
        }
    }

    private func updateGeometry(_ newGeometry: ShortPullRefreshGeometry) {
        geometry = newGeometry
        guard isEnabled,
              verticalPanIntent != false,
              isDirectlyInteracting,
              gestureStartedAtTop,
              isRefreshing == false else {
            return
        }

        // Starting away from the top is latched as ineligible. Conversely, a
        // top-started upward scroll is invalidated rather than becoming
        // eligible again when it later crosses the top.
        if ShortPullRefreshPolicy.isAtTop(
            distanceFromTop: newGeometry.distanceFromTop
        ) == false {
            gestureStartedAtTop = false
            pullProgress = 0
            return
        }

        // Once UIKit resolves this as a vertical pull, the recognizer callback
        // owns progress updates. Geometry still tracks rubber-band displacement
        // for the held refresh offset, but must not cause a second state write.
        guard verticalPanIntent != true else { return }
        updateArmedState(
            pullDistance: newGeometry.fingerEquivalentPullDistance
        )
    }

    private func handleDirectInteractionChange(
        isDirect: Bool,
        geometry newGeometry: ShortPullRefreshGeometry
    ) {
        geometry = newGeometry
        let wasDirect = isDirectlyInteracting

        if isDirect, wasDirect == false {
            beginGesture(with: newGeometry)
        }

        if wasDirect, isDirect == false {
            finishGesture()
        }

        isDirectlyInteracting = isDirect
    }

    private func beginGesture(with geometry: ShortPullRefreshGeometry) {
        isDirectlyInteracting = true
        gestureStartedAtTop = isEnabled
            && verticalPanIntent != false
            && ShortPullRefreshPolicy.shouldBegin(
            distanceFromTop: geometry.distanceFromTop,
            isRefreshing: isRefreshing
        )
        pullProgress = gestureStartedAtTop
            ? ShortPullRefreshPolicy.pullProgress(
                pullDistance: geometry.fingerEquivalentPullDistance
            )
            : 0
        didReachThreshold = pullProgress >= 1
    }

    private func finishGesture() {
        let shouldRefresh = ShortPullRefreshPolicy.shouldTrigger(
            startedAtTop: gestureStartedAtTop && verticalPanIntent != false,
            isRefreshing: isRefreshing,
            reachedThreshold: didReachThreshold
        )
        resetGesture()
        verticalPanIntent = nil

        if isEnabled, shouldRefresh {
            startRefresh(source: .pullGesture)
        }
    }

    private func resetGesture() {
        isDirectlyInteracting = false
        gestureStartedAtTop = false
        pullProgress = 0
        didReachThreshold = false
    }

    private func handlePanChange(
        state: UIGestureRecognizer.State,
        translation: CGSize
    ) {
        switch state {
        case .began:
            verticalPanIntent = nil
        case .changed, .ended:
            if verticalPanIntent == nil {
                verticalPanIntent = ShortPullRefreshPolicy.verticalPullIntent(
                    translation: translation
                )
                if verticalPanIntent == false {
                    gestureStartedAtTop = false
                    pullProgress = 0
                    didReachThreshold = false
                }
            }
            guard verticalPanIntent == true else {
                return
            }
            guard isDirectlyInteracting,
                  gestureStartedAtTop,
                  isRefreshing == false else {
                return
            }
            updateArmedState(pullDistance: max(translation.height, 0))
        case .cancelled, .failed:
            verticalPanIntent = false
            resetGesture()
        default:
            break
        }
    }

    private func updateArmedState(pullDistance: CGFloat) {
        let currentProgress = ShortPullRefreshPolicy.pullProgress(
            pullDistance: pullDistance
        )
        let isNowArmed = currentProgress >= 1
        if isNowArmed, didReachThreshold == false {
            PullRefreshHaptics.triggerReady()
        }
        didReachThreshold = isNowArmed
        pullProgress = currentProgress
    }

    private func startRefresh(source: ShortPullRefreshSource) {
        let sourceCanStart = isEnabled || source == .programmatic
        guard sourceCanStart, refreshTask == nil, isRefreshing == false else { return }
        activeRefreshSource = source
        isRefreshing = true

        refreshTask = Task { @MainActor in
            let start = DispatchTime.now().uptimeNanoseconds
            await action(source)
            guard Task.isCancelled == false else { return }

            let elapsed = DispatchTime.now().uptimeNanoseconds - start
            let remaining = ShortPullRefreshPolicy.remainingVisibleDurationNanoseconds(
                elapsed: elapsed
            )
            if remaining > 0 {
                try? await Task.sleep(nanoseconds: remaining)
            }
            guard Task.isCancelled == false else { return }

            isRefreshing = false
            activeRefreshSource = nil
            refreshTask = nil
        }
    }

    private func cancelRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
        isRefreshing = false
        activeRefreshSource = nil
        resetGesture()
        verticalPanIntent = nil
    }
}

/// Observes the `UIScrollView`'s own pan recognizer. It adds only a target to
/// the existing recognizer, so native iOS navigation gestures keep their
/// normal arbitration and no second gesture competes for the same touch.
private struct ShortPullScrollViewPanObserver: UIViewRepresentable {
    let surfaceColor: UIColor
    let onStateChange: (UIGestureRecognizer.State, CGSize) -> Void
    let onGeometryChange: (ShortPullRefreshGeometry) -> Void
    let onDirectInteractionChange: (Bool, ShortPullRefreshGeometry) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            surfaceColor: surfaceColor,
            onStateChange: onStateChange,
            onGeometryChange: onGeometryChange,
            onDirectInteractionChange: onDirectInteractionChange
        )
    }

    func makeUIView(context: Context) -> AttachmentView {
        let view = AttachmentView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        view.onHierarchyChange = { [weak coordinator = context.coordinator] attachmentView in
            coordinator?.scheduleAttachment(from: attachmentView)
        }
        context.coordinator.scheduleAttachment(from: view)
        return view
    }

    func updateUIView(_ uiView: AttachmentView, context: Context) {
        context.coordinator.update(
            surfaceColor: surfaceColor,
            onStateChange: onStateChange,
            onGeometryChange: onGeometryChange,
            onDirectInteractionChange: onDirectInteractionChange,
            from: uiView
        )
    }

    static func dismantleUIView(_ uiView: AttachmentView, coordinator: Coordinator) {
        uiView.onHierarchyChange = nil
        coordinator.detach()
    }

    final class AttachmentView: UIView {
        var onHierarchyChange: ((AttachmentView) -> Void)?
        private(set) var hierarchyGeneration: UInt = 0

        override func didMoveToSuperview() {
            super.didMoveToSuperview()
            hierarchyGeneration &+= 1
            onHierarchyChange?(self)
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            hierarchyGeneration &+= 1
            onHierarchyChange?(self)
        }
    }

    final class ScrollLifecycleSentinel: UIView {
        var onWindowChange: ((ScrollLifecycleSentinel) -> Void)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            onWindowChange?(self)
        }
    }

    final class Coordinator: NSObject {
        var surfaceColor: UIColor {
            didSet {
                guard oldValue.isEqual(surfaceColor) == false else { return }
                if attachedScrollView?.backgroundColor?.isEqual(surfaceColor) != true {
                    attachedScrollView?.backgroundColor = surfaceColor
                }
            }
        }
        var onStateChange: (UIGestureRecognizer.State, CGSize) -> Void
        var onGeometryChange: (ShortPullRefreshGeometry) -> Void
        var onDirectInteractionChange: (Bool, ShortPullRefreshGeometry) -> Void
        private weak var attachedScrollView: UIScrollView?
        private var originalBackgroundColor: UIColor?
        private weak var panGestureRecognizer: UIPanGestureRecognizer?
        private var pendingAttachment: DispatchWorkItem?
        private var attachmentRequestID: UInt = 0
        private var attachedHierarchyGeneration: UInt?
        private var lifecycleSentinel: ScrollLifecycleSentinel?
        private var offsetObservation: NSKeyValueObservation?
        private var insetObservation: NSKeyValueObservation?
        private var boundsObservation: NSKeyValueObservation?
        private var isDirectlyInteracting = false
        private weak var currentAttachmentView: AttachmentView?

        init(
            surfaceColor: UIColor,
            onStateChange: @escaping (UIGestureRecognizer.State, CGSize) -> Void,
            onGeometryChange: @escaping (ShortPullRefreshGeometry) -> Void,
            onDirectInteractionChange: @escaping (Bool, ShortPullRefreshGeometry) -> Void
        ) {
            self.surfaceColor = surfaceColor
            self.onStateChange = onStateChange
            self.onGeometryChange = onGeometryChange
            self.onDirectInteractionChange = onDirectInteractionChange
        }

        func update(
            surfaceColor: UIColor,
            onStateChange: @escaping (UIGestureRecognizer.State, CGSize) -> Void,
            onGeometryChange: @escaping (ShortPullRefreshGeometry) -> Void,
            onDirectInteractionChange: @escaping (Bool, ShortPullRefreshGeometry) -> Void,
            from view: AttachmentView
        ) {
            self.surfaceColor = surfaceColor
            self.onStateChange = onStateChange
            self.onGeometryChange = onGeometryChange
            self.onDirectInteractionChange = onDirectInteractionChange
            guard hasUsableAttachment(for: view) == false else { return }
            scheduleAttachment(from: view)
        }

        func scheduleAttachment(from view: AttachmentView) {
            currentAttachmentView = view
            attachmentRequestID &+= 1
            let requestID = attachmentRequestID
            let hierarchyGeneration = view.hierarchyGeneration
            pendingAttachment?.cancel()
            let workItem = DispatchWorkItem { [weak self, weak view] in
                guard let self, let view else { return }
                guard self.attachmentRequestID == requestID,
                      view.hierarchyGeneration == hierarchyGeneration else { return }
                self.pendingAttachment = nil
                self.attach(
                    to: Self.enclosingScrollView(startingAt: view),
                    hierarchyGeneration: hierarchyGeneration
                )
            }
            pendingAttachment = workItem
            DispatchQueue.main.async(execute: workItem)
        }

        func detach() {
            attachmentRequestID &+= 1
            pendingAttachment?.cancel()
            pendingAttachment = nil
            panGestureRecognizer?.removeTarget(self, action: #selector(handlePan(_:)))
            panGestureRecognizer = nil
            clearGeometryObservation()
            restoreScrollBackground()
            currentAttachmentView = nil
            isDirectlyInteracting = false
        }

        private func clearGeometryObservation() {
            offsetObservation?.invalidate()
            insetObservation?.invalidate()
            boundsObservation?.invalidate()
            offsetObservation = nil
            insetObservation = nil
            boundsObservation = nil
        }

        private func installGeometryObservation(on scrollView: UIScrollView) {
            clearGeometryObservation()
            let publish: (UIScrollView) -> Void = { [weak self] scrollView in
                self?.onGeometryChange(ShortPullRefreshGeometry(scrollView: scrollView))
            }
            offsetObservation = scrollView.observe(\.contentOffset, options: [.initial, .new]) { scrollView, _ in
                publish(scrollView)
            }
            insetObservation = scrollView.observe(\.contentInset, options: [.new]) { scrollView, _ in
                publish(scrollView)
            }
            boundsObservation = scrollView.observe(\.bounds, options: [.new]) { scrollView, _ in
                publish(scrollView)
            }
        }

        private func publishDirectInteraction(_ isDirect: Bool, scrollView: UIScrollView) {
            guard isDirectlyInteracting != isDirect else { return }
            isDirectlyInteracting = isDirect
            onDirectInteractionChange(isDirect, ShortPullRefreshGeometry(scrollView: scrollView))
        }

        private func hasUsableAttachment(for view: AttachmentView) -> Bool {
            guard let scrollView = attachedScrollView,
                  let recognizer = panGestureRecognizer,
                  recognizer === scrollView.panGestureRecognizer,
                  lifecycleSentinel?.superview === scrollView,
                  attachedHierarchyGeneration == view.hierarchyGeneration,
                  let window = view.window,
                  scrollView.window === window else {
                return false
            }
            return true
        }

        private func attach(
            to scrollView: UIScrollView?,
            hierarchyGeneration: UInt
        ) {
            guard let scrollView else {
                detach()
                return
            }
            let recognizer = scrollView.panGestureRecognizer
            if attachedScrollView === scrollView,
               panGestureRecognizer === recognizer {
                attachedHierarchyGeneration = hierarchyGeneration
                installLifecycleSentinelIfNeeded(on: scrollView)
                if scrollView.backgroundColor?.isEqual(surfaceColor) != true {
                    scrollView.backgroundColor = surfaceColor
                }
                return
            }
            panGestureRecognizer?.removeTarget(self, action: #selector(handlePan(_:)))
            clearGeometryObservation()
            restoreScrollBackground()
            attachedScrollView = scrollView
            attachedHierarchyGeneration = hierarchyGeneration
            originalBackgroundColor = scrollView.backgroundColor
            // UIKit renders rubber-band overscroll using the scroll view's
            // own background, not the SwiftUI background behind it. Keeping
            // both surfaces identical prevents a white/gray seam while the
            // refresh hold settles after release.
            scrollView.backgroundColor = surfaceColor
            panGestureRecognizer = recognizer
            recognizer.addTarget(self, action: #selector(handlePan(_:)))
            installGeometryObservation(on: scrollView)
            installLifecycleSentinelIfNeeded(on: scrollView)
        }

        private func restoreScrollBackground() {
            lifecycleSentinel?.onWindowChange = nil
            lifecycleSentinel?.removeFromSuperview()
            lifecycleSentinel = nil
            attachedScrollView?.backgroundColor = originalBackgroundColor
            attachedScrollView = nil
            attachedHierarchyGeneration = nil
            originalBackgroundColor = nil
        }

        private func installLifecycleSentinelIfNeeded(on scrollView: UIScrollView) {
            if lifecycleSentinel?.superview === scrollView { return }

            lifecycleSentinel?.onWindowChange = nil
            lifecycleSentinel?.removeFromSuperview()
            let sentinel = ScrollLifecycleSentinel(frame: .zero)
            sentinel.isUserInteractionEnabled = false
            sentinel.isAccessibilityElement = false
            sentinel.backgroundColor = .clear
            sentinel.onWindowChange = { [weak self, weak sentinel] changedSentinel in
                guard changedSentinel === sentinel,
                      changedSentinel.window == nil,
                      let self,
                      let attachmentView = self.currentAttachmentView else { return }
                self.scheduleAttachment(from: attachmentView)
            }
            lifecycleSentinel = sentinel
            scrollView.addSubview(sentinel)
        }

        @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
            if let scrollView = attachedScrollView {
                switch recognizer.state {
                case .began, .changed:
                    publishDirectInteraction(true, scrollView: scrollView)
                case .ended, .cancelled, .failed:
                    publishDirectInteraction(false, scrollView: scrollView)
                default:
                    break
                }
            }
            let point = recognizer.translation(in: recognizer.view)
            onStateChange(
                recognizer.state,
                CGSize(width: point.x, height: point.y)
            )
        }

        private static func enclosingScrollView(startingAt view: UIView) -> UIScrollView? {
            var current: UIView? = view.superview
            while let candidate = current {
                if let scrollView = candidate as? UIScrollView {
                    return scrollView
                }
                current = candidate.superview
            }

            // A SwiftUI background can be hosted as a sibling of the
            // platform scroll view rather than as its descendant. Starting
            // from the nearest common ancestor, choose the scroll view whose
            // visible frame most closely overlaps this attachment.
            guard let window = view.window else { return nil }
            let attachmentFrame = view.convert(view.bounds, to: window)
            guard attachmentFrame.isEmpty == false else { return nil }

            current = view.superview
            while let ancestor = current {
                let candidates = descendantScrollViews(of: ancestor)
                    .filter { $0.window === window && $0.isHidden == false }
                if let bestMatch = candidates.max(by: {
                    overlapScore(
                        scrollView: $0,
                        attachmentFrame: attachmentFrame,
                        window: window
                    ) < overlapScore(
                        scrollView: $1,
                        attachmentFrame: attachmentFrame,
                        window: window
                    )
                }), overlapScore(
                    scrollView: bestMatch,
                    attachmentFrame: attachmentFrame,
                    window: window
                ) > 0.5 {
                    return bestMatch
                }
                current = ancestor.superview
            }
            return nil
        }

        private static func descendantScrollViews(of root: UIView) -> [UIScrollView] {
            var result: [UIScrollView] = []
            var pending = root.subviews
            while let candidate = pending.popLast() {
                if let scrollView = candidate as? UIScrollView {
                    result.append(scrollView)
                }
                pending.append(contentsOf: candidate.subviews)
            }
            return result
        }

        private static func overlapScore(
            scrollView: UIScrollView,
            attachmentFrame: CGRect,
            window: UIWindow
        ) -> CGFloat {
            let scrollFrame = scrollView.convert(scrollView.bounds, to: window)
            let intersection = attachmentFrame.intersection(scrollFrame)
            guard intersection.isNull == false, intersection.isEmpty == false else {
                return 0
            }
            let attachmentArea = max(attachmentFrame.width * attachmentFrame.height, 1)
            let overlapRatio = intersection.width * intersection.height / attachmentArea
            let widthSimilarity = min(scrollFrame.width, attachmentFrame.width)
                / max(scrollFrame.width, attachmentFrame.width, 1)
            let heightSimilarity = min(scrollFrame.height, attachmentFrame.height)
                / max(scrollFrame.height, attachmentFrame.height, 1)
            return overlapRatio * widthSimilarity * heightSimilarity
        }
    }
}

/// Twelve short gray spokes fill clockwise as the pull approaches 80 points.
/// Refreshing reuses the exact same shape with a rotating gray phase.
private struct ShortPullRadialIndicator: View {
    let progress: CGFloat
    let isRefreshing: Bool

    private let spokeCount = 12
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var pausesRotation: Bool {
        reduceMotion || ProcessInfo.processInfo.arguments.contains("UITEST_DISABLE_ANIMATIONS")
    }

    var body: some View {
        TimelineView(.animation(paused: pausesRotation || isRefreshing == false)) {
            timeline in
            ZStack {
                ForEach(0..<spokeCount, id: \.self) { index in
                    Capsule()
                        .fill(Color(uiColor: .secondaryLabel))
                        .frame(width: 2.2, height: 6)
                        .offset(y: -8)
                        .rotationEffect(.degrees(Double(index) * 360 / Double(spokeCount)))
                        .opacity(spokeOpacity(at: index, date: timeline.date))
                }
            }
        }
    }

    private func spokeOpacity(at index: Int, date: Date) -> Double {
        if isRefreshing {
            guard pausesRotation == false else { return index == 0 ? 0.95 : 0.28 }
            let phase = date.timeIntervalSinceReferenceDate * Double(spokeCount)
            let distance = (Double(index) - phase)
                .truncatingRemainder(dividingBy: Double(spokeCount))
            let wrappedDistance = distance < 0 ? distance + Double(spokeCount) : distance
            return max(0.18, 0.95 - wrappedDistance * 0.065)
        }
        let filledSpokes = Int(ceil(progress * CGFloat(spokeCount)))
        return index < filledSpokes ? 0.9 : 0.16
    }
}
