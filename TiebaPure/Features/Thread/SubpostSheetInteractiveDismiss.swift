import SwiftUI
import UIKit

/// Installs a horizontal pan on the complete system sheet surface. The finger
/// moves horizontally, while the entire presented sheet follows vertically.
/// Moving the presentation surface (instead of its SwiftUI content) keeps the
/// real thread visible underneath and avoids exposing an opaque host layer.
struct SubpostSheetInteractiveDismissInstaller: UIViewControllerRepresentable {
    var isEnabled = true
    let onDismiss: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(isEnabled: isEnabled, onDismiss: onDismiss)
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
        context.coordinator.onDismiss = onDismiss
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
        coordinator.isEnabled = false
        coordinator.detach()
    }

    final class AttachmentController: UIViewController {
        var onAttach: ((AttachmentController) -> Void)?

        override func loadView() {
            let view = UIView(frame: .zero)
            view.backgroundColor = .clear
            view.isUserInteractionEnabled = false
            self.view = view
        }

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
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var isEnabled: Bool
        var onDismiss: () -> Void

        private weak var presentedViewController: UIViewController?
        private weak var sheetSurfaceView: UIView?
        private var initialCenter = CGPoint.zero
        private var initialOriginY: CGFloat = 0
        private var didCaptureInitialGeometry = false
        private var isFinishing = false
        private var retryScheduled = false

        private lazy var panGesture: UIPanGestureRecognizer = {
            let gesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
            gesture.delegate = self
            gesture.maximumNumberOfTouches = 1
            gesture.cancelsTouchesInView = false
            gesture.delaysTouchesBegan = false
            return gesture
        }()

        init(isEnabled: Bool, onDismiss: @escaping () -> Void) {
            self.isEnabled = isEnabled
            self.onDismiss = onDismiss
            super.init()
        }

        func attach(from controller: AttachmentController) {
            guard isEnabled else { return }
            guard let context = presentationContext(containing: controller) else {
                scheduleRetry(from: controller)
                return
            }

            retryScheduled = false
            guard sheetSurfaceView !== context.surfaceView else { return }
            detach()
            presentedViewController = context.viewController
            sheetSurfaceView = context.surfaceView
            initialCenter = context.surfaceView.center
            initialOriginY = context.surfaceView.frame.minY
            didCaptureInitialGeometry = true
            context.surfaceView.addGestureRecognizer(panGesture)
        }

        func detach() {
            guard isFinishing == false else { return }
            panGesture.view?.removeGestureRecognizer(panGesture)
            if didCaptureInitialGeometry {
                sheetSurfaceView?.center = initialCenter
            }
            presentedViewController = nil
            sheetSurfaceView = nil
            didCaptureInitialGeometry = false
            retryScheduled = false
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard gestureRecognizer === panGesture,
                  isEnabled,
                  isFinishing == false,
                  let sheetSurfaceView else {
                return false
            }

            let velocity = panGesture.velocity(in: sheetSurfaceView)
            guard SubpostRightSwipeDismissPolicy.shouldBegin(
                translation: CGSize(width: velocity.x, height: velocity.y)
            ) else {
                return false
            }

            initialCenter = sheetSurfaceView.center
            initialOriginY = sheetSurfaceView.frame.minY
            didCaptureInitialGeometry = true
            return true
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            gestureRecognizer === panGesture
        }

        @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard let sheetSurfaceView,
                  let presentedViewController,
                  isFinishing == false else {
                return
            }

            let translation = gesture.translation(in: sheetSurfaceView)
            let containerHeight = presentedViewController.presentationController?
                .containerView?.bounds.height ?? sheetSurfaceView.window?.bounds.height ?? sheetSurfaceView.bounds.height

            switch gesture.state {
            case .began, .changed:
                let offset = SubpostRightSwipeDismissPolicy.verticalOffset(
                    translationX: translation.x,
                    containerHeight: containerHeight
                )
                sheetSurfaceView.center = CGPoint(
                    x: initialCenter.x,
                    y: initialCenter.y + offset
                )

            case .ended:
                let velocity = gesture.velocity(in: sheetSurfaceView)
                let predictedTranslation = SubpostRightSwipeDismissPolicy.predictedTranslation(
                    translationX: translation.x,
                    velocityX: velocity.x
                )
                let shouldDismiss = SubpostRightSwipeDismissPolicy.shouldFinish(
                    translationX: translation.x,
                    predictedTranslationX: predictedTranslation,
                    containerWidth: sheetSurfaceView.bounds.width
                )
                if shouldDismiss {
                    finishDismissal(
                        viewController: presentedViewController,
                        surfaceView: sheetSurfaceView,
                        containerHeight: containerHeight
                    )
                } else {
                    restore(surfaceView: sheetSurfaceView)
                }

            case .cancelled, .failed:
                restore(surfaceView: sheetSurfaceView)

            default:
                break
            }
        }

        private func finishDismissal(
            viewController: UIViewController,
            surfaceView: UIView,
            containerHeight: CGFloat
        ) {
            isFinishing = true
            let targetOffset = max(containerHeight - initialOriginY + 32, surfaceView.bounds.height)
            let duration = UIAccessibility.isReduceMotionEnabled ? 0.12 : 0.24

            UIView.animate(
                withDuration: duration,
                delay: 0,
                options: [.beginFromCurrentState, .curveEaseIn, .allowUserInteraction]
            ) {
                surfaceView.center = CGPoint(
                    x: self.initialCenter.x,
                    y: self.initialCenter.y + targetOffset
                )
            } completion: { [weak self, weak viewController] _ in
                guard let self else { return }
                viewController?.dismiss(animated: false) { [weak self] in
                    guard let self else { return }
                    self.onDismiss()
                    self.presentedViewController = nil
                    self.sheetSurfaceView = nil
                    self.didCaptureInitialGeometry = false
                    self.isFinishing = false
                }
            }
        }

        private func restore(surfaceView: UIView) {
            let duration = UIAccessibility.isReduceMotionEnabled ? 0.10 : 0.22
            UIView.animate(
                withDuration: duration,
                delay: 0,
                usingSpringWithDamping: 0.88,
                initialSpringVelocity: 0,
                options: [.beginFromCurrentState, .allowUserInteraction]
            ) {
                surfaceView.center = self.initialCenter
            }
        }

        private func scheduleRetry(from controller: AttachmentController) {
            guard retryScheduled == false else { return }
            retryScheduled = true
            DispatchQueue.main.async { [weak self, weak controller] in
                guard let self, let controller else { return }
                self.retryScheduled = false
                self.attach(from: controller)
            }
        }

        private func presentationContext(
            containing controller: UIViewController
        ) -> (viewController: UIViewController, surfaceView: UIView)? {
            var ancestor: UIViewController? = controller
            while let current = ancestor {
                if current.presentingViewController != nil,
                   let surfaceView = current.presentationController?.presentedView {
                    return (current, surfaceView)
                }
                ancestor = current.parent
            }

            var candidate = controller.view.window?.rootViewController
            while let presented = candidate?.presentedViewController {
                if controller.view.isDescendant(of: presented.view),
                   let surfaceView = presented.presentationController?.presentedView {
                    return (presented, surfaceView)
                }
                candidate = presented
            }
            return nil
        }
    }
}

enum SubpostRightSwipeDismissPolicy {
    static let minimumTrackingDistance: CGFloat = 8
    static let horizontalDominance: CGFloat = 1.2
    static let completionProgress: CGFloat = 0.28
    static let completionDistance: CGFloat = 110
    static let predictedCompletionDistance: CGFloat = 220
    static let predictionDuration: CGFloat = 0.18
    static let maximumInteractiveOffsetFraction: CGFloat = 0.72

    static func shouldBegin(translation: CGSize) -> Bool {
        translation.width > 0
            && translation.width > abs(translation.height) * horizontalDominance
    }

    static func verticalOffset(translationX: CGFloat, containerHeight: CGFloat) -> CGFloat {
        guard containerHeight > 0 else { return 0 }
        return min(max(translationX, 0), containerHeight * maximumInteractiveOffsetFraction)
    }

    static func predictedTranslation(translationX: CGFloat, velocityX: CGFloat) -> CGFloat {
        max(translationX + velocityX * predictionDuration, 0)
    }

    static func shouldFinish(
        translationX: CGFloat,
        predictedTranslationX: CGFloat,
        containerWidth: CGFloat
    ) -> Bool {
        guard containerWidth > 0 else { return false }
        return translationX >= completionDistance
            || translationX / containerWidth >= completionProgress
            || predictedTranslationX >= predictedCompletionDistance
    }
}
