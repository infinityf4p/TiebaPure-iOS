import SwiftUI
import UIKit

/// Documents the system navigation gesture used by each supported OS family.
///
/// iOS 26 adds `UINavigationController.interactiveContentPopGestureRecognizer`,
/// which recognizes an interactive pop across the navigation controller's
/// content. Earlier systems only provide the leading-edge
/// `interactivePopGestureRecognizer`.
enum NavigationBackGesturePolicy {
    enum Mode: Equatable {
        case content
        case edge
    }

    static func mode(systemMajorVersion: Int) -> Mode {
        systemMajorVersion >= 26 ? .content : .edge
    }

    static var currentMode: Mode {
        mode(systemMajorVersion: ProcessInfo.processInfo.operatingSystemVersion.majorVersion)
    }
}

extension View {
    /// Keeps navigation system-owned while allowing a short, explicit critical
    /// section (such as a dispatched destructive write) to suspend both native
    /// pop recognizers. The original enabled state is restored afterwards.
    func fullScreenInteractiveNavigationPop(isEnabled: Bool = true) -> some View {
        background(
            NativeNavigationPopGestureControl(isEnabled: isEnabled)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        )
    }

    /// No longer captures page screenshots. Retained as a source-compatible
    /// no-op while callers are migrated away from the former snapshot driver.
    func interactiveNavigationPopRevealSource() -> some View {
        self
    }

    /// Native NavigationStack/UINavigationController pops update their route
    /// binding directly, so a second manual route mutation would risk popping
    /// two levels. The action is intentionally ignored.
    func interactiveNavigationPopStateSync(
        _ action: @escaping () -> Void
    ) -> some View {
        self
    }
}

private struct NativeNavigationPopGestureControl: UIViewControllerRepresentable {
    let isEnabled: Bool

    func makeUIViewController(context: Context) -> Controller {
        Controller()
    }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.setPopGesturesEnabled(isEnabled)
    }

    static func dismantleUIViewController(_ controller: Controller, coordinator: ()) {
        controller.restorePopGesturesIfNeeded()
    }

    @MainActor
    final class Controller: UIViewController {
        private var requestedEnabled = true
        private weak var controlledNavigationController: UINavigationController?
        private var previousEdgeGestureState: Bool?
        private var previousContentGestureState: Bool?

        func setPopGesturesEnabled(_ isEnabled: Bool) {
            requestedEnabled = isEnabled
            applyRequestedState()
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            applyRequestedState()
        }

        override func viewWillDisappear(_ animated: Bool) {
            restorePopGesturesIfNeeded()
            super.viewWillDisappear(animated)
        }

        func restorePopGesturesIfNeeded() {
            guard let navigationController = controlledNavigationController else { return }
            if let previousEdgeGestureState {
                navigationController.interactivePopGestureRecognizer?.isEnabled = previousEdgeGestureState
            }
            if let previousContentGestureState {
                Self.setContentPopGestureEnabled(
                    on: navigationController,
                    enabled: previousContentGestureState
                )
            }
            controlledNavigationController = nil
            previousEdgeGestureState = nil
            previousContentGestureState = nil
        }

        private func applyRequestedState() {
            guard requestedEnabled == false else {
                restorePopGesturesIfNeeded()
                return
            }
            guard let navigationController else { return }
            if controlledNavigationController !== navigationController {
                restorePopGesturesIfNeeded()
                controlledNavigationController = navigationController
                previousEdgeGestureState = navigationController
                    .interactivePopGestureRecognizer?.isEnabled
                previousContentGestureState = Self.contentPopGestureEnabled(
                    on: navigationController
                )
            }
            navigationController.interactivePopGestureRecognizer?.isEnabled = false
            Self.setContentPopGestureEnabled(on: navigationController, enabled: false)
        }

        /// iOS 26 adds `interactiveContentPopGestureRecognizer`. Access via KVC so
        /// this file still compiles against the iOS 18 SDK used by Xcode 16.
        private static func contentPopGestureEnabled(
            on navigationController: UINavigationController
        ) -> Bool? {
            guard navigationController.responds(
                to: Selector(("interactiveContentPopGestureRecognizer"))
            ) else {
                return nil
            }
            let gesture = navigationController.value(
                forKey: "interactiveContentPopGestureRecognizer"
            ) as? UIGestureRecognizer
            return gesture?.isEnabled
        }

        private static func setContentPopGestureEnabled(
            on navigationController: UINavigationController,
            enabled: Bool
        ) {
            guard navigationController.responds(
                to: Selector(("interactiveContentPopGestureRecognizer"))
            ) else {
                return
            }
            let gesture = navigationController.value(
                forKey: "interactiveContentPopGestureRecognizer"
            ) as? UIGestureRecognizer
            gesture?.isEnabled = enabled
        }
    }
}

/// Progress-driven pull-to-refresh indicator. While dragging, a ring fills
/// and rotates with the pull distance and pops to the accent color once the
/// release threshold is reached; while refreshing it becomes a spinner. Both
/// states sit on a floating material disc so the indicator reads as its own
/// layer instead of blending into content.
struct InlineRefreshActivityIndicator: View {
    var progress: CGFloat = 1
    var isRefreshing: Bool = true
    let accessibilityIdentifier: String

    private var clampedProgress: CGFloat { min(max(progress, 0), 1) }
    private var isReadyToRelease: Bool { clampedProgress >= 1 }

    var body: some View {
        ZStack {
            if isRefreshing {
                ProgressView()
                    .progressViewStyle(.circular)
                    .controlSize(.small)
                    .tint(Color(uiColor: .secondaryLabel))
                    .transition(.opacity)
            } else {
                Circle()
                    .trim(from: 0, to: 0.9 * clampedProgress)
                    .stroke(
                        isReadyToRelease
                            ? Color.accentColor
                            : Color(uiColor: .tertiaryLabel),
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                    )
                    .frame(width: 18, height: 18)
                    .rotationEffect(.degrees(-90 + Double(clampedProgress) * 240))
                    .opacity(0.35 + 0.65 * clampedProgress)
            }
        }
        .frame(width: 36, height: 36)
        .background(
            Circle()
                .fill(.ultraThinMaterial)
                .shadow(color: Color.black.opacity(0.1), radius: 6, y: 2)
        )
        .scaleEffect(isRefreshing ? 1 : 0.6 + 0.4 * clampedProgress)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isReadyToRelease)
        .accessibilityLabel(isRefreshing ? "正在刷新" : "下拉刷新")
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

/// One light tap the moment the pull crosses the release threshold, mirroring
/// the system refresh control's confirmation.
@MainActor
enum PullRefreshHaptics {
    private static let generator = UIImpactFeedbackGenerator(style: .light)

    static func triggerReady() {
        generator.impactOccurred(intensity: 0.8)
    }
}
