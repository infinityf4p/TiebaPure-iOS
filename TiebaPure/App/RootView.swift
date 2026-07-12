import SwiftUI
import UIKit

struct RootView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var account: Account?
    @State private var didLoadAccount = false

    var body: some View {
        Group {
            if didLoadAccount == false {
                ProgressView()
                    .controlSize(.large)
            } else {
                MainTabView(account: account)
            }
        }
        .task {
            account = try? await environment.accountStore.load()
            didLoadAccount = true
        }
        .onReceive(environment.accountStore.accountDidChange) { newAccount in
            account = newAccount
            didLoadAccount = true
        }
    }
}

private struct MainTabView: View {
    let account: Account?
    @State private var selectedTab: RootTab = .home
    @State private var homeRefreshToken = 0

    var body: some View {
        TabView(selection: tabSelection) {
            HomeView(account: account, refreshToken: homeRefreshToken)
                .tabItem {
                    Label("首页", systemImage: "house")
                }
                .tag(RootTab.home)

            ForumHubView(account: account)
                .tabItem {
                    Label("进吧", systemImage: "square.grid.2x2")
                }
                .tag(RootTab.forums)

            MeView(account: account)
                .tabItem {
                    Label("我的", systemImage: "person.circle")
                }
                .tag(RootTab.me)
        }
        .background(
            TabSelectionObserver {
                homeRefreshToken += 1
            }
        )
    }

    private var tabSelection: Binding<RootTab> {
        Binding(
            get: { selectedTab },
            set: { newValue in
                selectedTab = newValue
            }
        )
    }
}

enum RootTab: Hashable {
    case home
    case forums
    case me
}

private struct TabSelectionObserver: UIViewControllerRepresentable {
    let onReselectHome: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onReselectHome: onReselectHome)
    }

    func makeUIViewController(context: Context) -> Controller {
        Controller(coordinator: context.coordinator)
    }

    func updateUIViewController(_ controller: Controller, context: Context) {
        context.coordinator.onReselectHome = onReselectHome
        controller.coordinator = context.coordinator
        controller.isObservationActive = true
        controller.attachToTabBarController()
    }

    static func dismantleUIViewController(_ controller: Controller, coordinator: Coordinator) {
        controller.isObservationActive = false
        coordinator.detach()
    }

    final class Controller: UIViewController {
        var coordinator: Coordinator
        var isObservationActive = true

        init(coordinator: Coordinator) {
            self.coordinator = coordinator
            super.init(nibName: nil, bundle: nil)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            attachToTabBarController()
        }

        func attachToTabBarController() {
            guard isObservationActive else { return }
            var visited = Set<ObjectIdentifier>()
            guard let tabBarController = tabBarController ?? findTabBarController(
                from: view.window?.rootViewController,
                visited: &visited
            ) else {
                return
            }
            coordinator.attach(to: tabBarController)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.isObservationActive else { return }
                var currentVisited = Set<ObjectIdentifier>()
                guard let currentController = self.tabBarController ?? self.findTabBarController(
                    from: self.view.window?.rootViewController,
                    visited: &currentVisited
                ) else {
                    return
                }
                self.coordinator.attach(to: currentController)
            }
        }

        private func findTabBarController(
            from controller: UIViewController?,
            visited: inout Set<ObjectIdentifier>
        ) -> UITabBarController? {
            guard let controller else { return nil }

            let identifier = ObjectIdentifier(controller)
            guard visited.insert(identifier).inserted else { return nil }

            if let tabBarController = controller as? UITabBarController {
                return tabBarController
            }

            if let found = findTabBarController(from: controller.presentedViewController, visited: &visited) {
                return found
            }

            for child in controller.children {
                if let found = findTabBarController(from: child, visited: &visited) {
                    return found
                }
            }

            return nil
        }
    }

    final class Coordinator: NSObject, UITabBarControllerDelegate {
        var onReselectHome: () -> Void
        private weak var observedController: UITabBarController?
        private weak var previousDelegate: UITabBarControllerDelegate?

        init(onReselectHome: @escaping () -> Void) {
            self.onReselectHome = onReselectHome
        }

        func attach(to tabBarController: UITabBarController) {
            guard observedController !== tabBarController || tabBarController.delegate !== self else {
                return
            }
            detach()
            if tabBarController.delegate !== self {
                previousDelegate = tabBarController.delegate
            }
            observedController = tabBarController
            tabBarController.delegate = self
        }

        func detach() {
            if let observedController, observedController.delegate === self {
                observedController.delegate = previousDelegate
            }
            observedController = nil
            previousDelegate = nil
        }

        func tabBarController(
            _ tabBarController: UITabBarController,
            shouldSelect viewController: UIViewController
        ) -> Bool {
            let permitsSelection = previousDelegate?.tabBarController?(
                tabBarController,
                shouldSelect: viewController
            ) ?? true
            guard permitsSelection else { return false }

            if tabBarController.selectedViewController === viewController,
               tabBarController.viewControllers?.first === viewController {
                onReselectHome()
            }
            return true
        }

        func tabBarController(
            _ tabBarController: UITabBarController,
            didSelect viewController: UIViewController
        ) {
            previousDelegate?.tabBarController?(tabBarController, didSelect: viewController)
        }

        override func responds(to aSelector: Selector!) -> Bool {
            super.responds(to: aSelector) || previousDelegate?.responds(to: aSelector) == true
        }

        override func forwardingTarget(for aSelector: Selector!) -> Any? {
            if previousDelegate?.responds(to: aSelector) == true {
                return previousDelegate
            }
            return super.forwardingTarget(for: aSelector)
        }
    }
}

enum RootTabHitTester {
    static func tab(at point: CGPoint, itemFrames: [CGRect]) -> RootTab? {
        guard let index = itemFrames.firstIndex(where: { $0.contains(point) }) else { return nil }
        return RootTab(tabIndex: index)
    }
}

extension RootTab {
    init?(tabIndex: Int) {
        switch tabIndex {
        case 0:
            self = .home
        case 1:
            self = .forums
        case 2:
            self = .me
        default:
            return nil
        }
    }
}
