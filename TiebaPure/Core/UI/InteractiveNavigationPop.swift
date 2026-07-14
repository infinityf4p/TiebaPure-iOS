import SwiftUI
import UIKit

/// Installs one full-screen, interactive pop gesture on a NavigationStack.
/// The transition is driven by UINavigationController so the real previous
/// page, including its navigation state, is revealed while the finger moves.
struct InteractiveNavigationPopInstaller: UIViewControllerRepresentable {
    var isEnabled = true

    func makeCoordinator() -> Coordinator {
        Coordinator(isEnabled: isEnabled)
    }

    func makeUIViewController(context: Context) -> AttachmentController {
        let controller = AttachmentController()
        controller.onAttach = { [weak coordinator = context.coordinator] controller in
            coordinator?.attach(from: controller)
        }
        return controller
    }

    func updateUIViewController(_ controller: AttachmentController, context: Context) {
        context.coordinator.isEnabled = isEnabled
        controller.onAttach = { [weak coordinator = context.coordinator] controller in
            coordinator?.attach(from: controller)
        }
        context.coordinator.attach(from: controller)
    }

    static func dismantleUIViewController(
        _ controller: AttachmentController,
        coordinator: Coordinator
    ) {
        controller.onAttach = nil
        coordinator.detach()
    }

    final class AttachmentController: UIViewController {
        var onAttach: ((AttachmentController) -> Void)?

        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            onAttach?(self)
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            onAttach?(self)
        }
    }

    @MainActor
    final class Coordinator: NSObject, UINavigationControllerDelegate, UIGestureRecognizerDelegate {
        var isEnabled: Bool

        private weak var navigationController: UINavigationController?
        private weak var ownerViewController: UIViewController?
        private weak var previousDelegate: UINavigationControllerDelegate?
        private var interactionController: UIPercentDrivenInteractiveTransition?
        private var animator: InteractiveSlidePopAnimator?
        private var isDrivingTransition = false
        private var pendingDetach = false
        private lazy var panGesture: UIPanGestureRecognizer = {
            let gesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
            gesture.delegate = self
            gesture.maximumNumberOfTouches = 1
            gesture.cancelsTouchesInView = true
            gesture.delaysTouchesBegan = false
            return gesture
        }()

        init(isEnabled: Bool) {
            self.isEnabled = isEnabled
            super.init()
        }

        func attach(from controller: AttachmentController) {
            guard let context = navigationContext(from: controller) else {
                DispatchQueue.main.async { [weak self, weak controller] in
                    guard let self, let controller else { return }
                    self.attach(from: controller)
                }
                return
            }

            let navigationController = context.navigationController
            ownerViewController = context.ownerViewController
            guard self.navigationController !== navigationController else { return }
            detach()
            self.navigationController = navigationController
            navigationController.view.addGestureRecognizer(panGesture)
        }

        func detach() {
            if isDrivingTransition {
                pendingDetach = true
                return
            }
            panGesture.view?.removeGestureRecognizer(panGesture)
            navigationController = nil
            ownerViewController = nil
            pendingDetach = false
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard gestureRecognizer === panGesture,
                  isEnabled,
                  isDrivingTransition == false,
                  interactionController == nil,
                  let navigationController,
                  navigationController.viewControllers.count > 1,
                  ownerViewController == nil || navigationController.topViewController === ownerViewController,
                  navigationController.presentedViewController == nil,
                  navigationController.transitionCoordinator == nil else {
                return false
            }

            let velocity = panGesture.velocity(in: navigationController.view)
            let location = panGesture.location(in: navigationController.view)
            return InteractiveNavigationPopPolicy.shouldBegin(
                startLocationX: location.x,
                containerWidth: navigationController.view.bounds.width,
                velocity: CGSize(width: velocity.x, height: velocity.y)
            )
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            // The directional gate above prevents vertical scroll gestures from
            // becoming a pop. Allowing simultaneity keeps ScrollView responsive
            // when the user's intent is vertical.
            gestureRecognizer === panGesture || otherGestureRecognizer === panGesture
        }

        @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard let navigationController else { return }
            let translation = gesture.translation(in: navigationController.view)
            let velocity = gesture.velocity(in: navigationController.view)
            let progress = InteractiveNavigationPopPolicy.progress(
                translationX: translation.x,
                containerWidth: navigationController.view.bounds.width
            )

            switch gesture.state {
            case .began:
                beginInteractivePop(on: navigationController)
            case .changed:
                interactionController?.update(progress)
            case .ended:
                if InteractiveNavigationPopPolicy.shouldFinish(
                    progress: progress,
                    velocityX: velocity.x
                ) {
                    interactionController?.finish()
                } else {
                    interactionController?.cancel()
                }
            case .cancelled, .failed:
                interactionController?.cancel()
            default:
                break
            }
        }

        private func beginInteractivePop(on navigationController: UINavigationController) {
            guard isDrivingTransition == false else { return }
            previousDelegate = navigationController.delegate
            navigationController.delegate = self

            let interactionController = UIPercentDrivenInteractiveTransition()
            interactionController.completionCurve = .easeOut
            interactionController.completionSpeed = 0.92
            self.interactionController = interactionController
            animator = InteractiveSlidePopAnimator(reduceMotion: UIAccessibility.isReduceMotionEnabled)
            isDrivingTransition = true

            if navigationController.popViewController(animated: true) == nil {
                interactionController.cancel()
                restoreNavigationDelegate()
            }
        }

        func navigationController(
            _ navigationController: UINavigationController,
            animationControllerFor operation: UINavigationController.Operation,
            from fromVC: UIViewController,
            to toVC: UIViewController
        ) -> UIViewControllerAnimatedTransitioning? {
            if isDrivingTransition, operation == .pop, let animator {
                return animator
            }
            return previousDelegate?.navigationController?(
                navigationController,
                animationControllerFor: operation,
                from: fromVC,
                to: toVC
            )
        }

        func navigationController(
            _ navigationController: UINavigationController,
            interactionControllerFor animationController: UIViewControllerAnimatedTransitioning
        ) -> UIViewControllerInteractiveTransitioning? {
            if isDrivingTransition,
               let animator,
               animationController === animator {
                return interactionController
            }
            return previousDelegate?.navigationController?(
                navigationController,
                interactionControllerFor: animationController
            )
        }

        func navigationController(
            _ navigationController: UINavigationController,
            willShow viewController: UIViewController,
            animated: Bool
        ) {
            previousDelegate?.navigationController?(
                navigationController,
                willShow: viewController,
                animated: animated
            )
        }

        func navigationController(
            _ navigationController: UINavigationController,
            didShow viewController: UIViewController,
            animated: Bool
        ) {
            previousDelegate?.navigationController?(
                navigationController,
                didShow: viewController,
                animated: animated
            )
            restoreNavigationDelegate()
        }

        private func restoreNavigationDelegate() {
            if let navigationController, navigationController.delegate === self {
                navigationController.delegate = previousDelegate
            }
            previousDelegate = nil
            interactionController = nil
            animator = nil
            isDrivingTransition = false

            if pendingDetach {
                detach()
            }
        }

        private func navigationContext(
            from controller: UIViewController
        ) -> (navigationController: UINavigationController, ownerViewController: UIViewController?)? {
            var parent: UIViewController? = controller
            while let current = parent {
                if let navigationController = current.navigationController {
                    let owner = navigationController.viewControllers.first(where: { $0 === current })
                        ?? navigationController.topViewController
                    return (navigationController, owner)
                }
                parent = current.parent
            }

            var responder: UIResponder? = controller.view
            while let current = responder?.next {
                if let viewController = current as? UIViewController,
                   let navigationController = viewController.navigationController {
                    let owner = navigationController.viewControllers.first(where: { $0 === viewController })
                        ?? navigationController.topViewController
                    return (navigationController, owner)
                }
                responder = current
            }

            guard let rootViewController = controller.view.window?.rootViewController,
                  let navigationController = visibleNavigationController(from: rootViewController) else {
                return nil
            }
            return (navigationController, navigationController.topViewController)
        }

        private func visibleNavigationController(
            from viewController: UIViewController
        ) -> UINavigationController? {
            if let presented = viewController.presentedViewController,
               presented.isBeingDismissed == false,
               let found = visibleNavigationController(from: presented) {
                return found
            }
            if let tabBarController = viewController as? UITabBarController,
               let selected = tabBarController.selectedViewController {
                return visibleNavigationController(from: selected)
            }
            if let navigationController = viewController as? UINavigationController {
                if let visible = navigationController.visibleViewController,
                   let nested = visibleNavigationController(from: visible),
                   nested !== navigationController {
                    return nested
                }
                return navigationController
            }
            for child in viewController.children.reversed()
            where child.viewIfLoaded?.window != nil {
                if let found = visibleNavigationController(from: child) {
                    return found
                }
            }
            return nil
        }
    }
}

private final class InteractiveSlidePopAnimator: NSObject, UIViewControllerAnimatedTransitioning {
    private let reduceMotion: Bool

    init(reduceMotion: Bool) {
        self.reduceMotion = reduceMotion
    }

    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
        reduceMotion ? 0.18 : 0.28
    }

    func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
        guard let fromView = transitionContext.view(forKey: .from),
              let toView = transitionContext.view(forKey: .to),
              let toViewController = transitionContext.viewController(forKey: .to) else {
            transitionContext.completeTransition(false)
            return
        }

        let containerView = transitionContext.containerView
        let width = max(containerView.bounds.width, 1)
        toView.frame = transitionContext.finalFrame(for: toViewController)
        toView.transform = reduceMotion
            ? .identity
            : CGAffineTransform(translationX: -width * 0.24, y: 0)
        containerView.insertSubview(toView, belowSubview: fromView)

        let dimmingView = UIView(frame: toView.bounds)
        dimmingView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        dimmingView.backgroundColor = UIColor.black.withAlphaComponent(reduceMotion ? 0 : 0.08)
        toView.addSubview(dimmingView)

        fromView.layer.shadowColor = UIColor.black.cgColor
        fromView.layer.shadowOpacity = reduceMotion ? 0 : 0.16
        fromView.layer.shadowRadius = 12
        fromView.layer.shadowOffset = CGSize(width: -3, height: 0)

        UIView.animate(
            withDuration: transitionDuration(using: transitionContext),
            delay: 0,
            options: [.curveEaseOut, .allowUserInteraction]
        ) {
            fromView.transform = CGAffineTransform(translationX: width, y: 0)
            toView.transform = .identity
            dimmingView.alpha = 0
        } completion: { _ in
            let completed = transitionContext.transitionWasCancelled == false
            fromView.transform = .identity
            toView.transform = .identity
            fromView.layer.shadowOpacity = 0
            dimmingView.removeFromSuperview()
            transitionContext.completeTransition(completed)
        }
    }
}

enum InteractiveNavigationPopPolicy {
    static let maximumStartFraction: CGFloat = 0.9
    static let horizontalDominance: CGFloat = 1.2
    static let completionProgress: CGFloat = 0.28
    static let completionVelocity: CGFloat = 650
    static let minimumFlickProgress: CGFloat = 0.06

    static func shouldBegin(
        startLocationX: CGFloat,
        containerWidth: CGFloat,
        velocity: CGSize
    ) -> Bool {
        guard containerWidth > 0 else { return false }
        let startFraction = startLocationX / containerWidth
        return startFraction >= 0
            && startFraction <= maximumStartFraction
            && velocity.width > 0
            && velocity.width > abs(velocity.height) * horizontalDominance
    }

    static func progress(translationX: CGFloat, containerWidth: CGFloat) -> CGFloat {
        guard containerWidth > 0 else { return 0 }
        return min(max(translationX / containerWidth, 0), 1)
    }

    static func shouldFinish(progress: CGFloat, velocityX: CGFloat) -> Bool {
        progress >= completionProgress
            || (progress >= minimumFlickProgress && velocityX >= completionVelocity)
    }
}

extension View {
    func fullScreenInteractiveNavigationPop(isEnabled: Bool = true) -> some View {
        background {
            InteractiveNavigationPopInstaller(isEnabled: isEnabled)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
    }
}

/// Matches the original compact, grey radial activity indicator used by the
/// project before the labelled capsule refresh treatment was introduced.
struct InlineRefreshActivityIndicator: View {
    let accessibilityIdentifier: String

    var body: some View {
        ProgressView()
            .progressViewStyle(.circular)
            .controlSize(.small)
            .tint(Color(uiColor: .secondaryLabel))
            .frame(width: 44, height: 36)
            .accessibilityLabel("正在刷新")
            .accessibilityIdentifier(accessibilityIdentifier)
    }
}
