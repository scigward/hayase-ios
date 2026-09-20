//
//  HayaseInterfaceNavigationController.swift
//  Hayase
//
//  Made by scigward.
//
//  Mirrors: src/routes/app/+layout.svelte
//

import UIKit

// MARK: - HayaseInterfaceNavigationController

final class HayaseInterfaceNavigationController: UINavigationController, UINavigationControllerDelegate, UIGestureRecognizerDelegate {
    private enum HistorySwipeDirection {
        case back
        case forward
    }

    private var forwardViewControllers: [UIViewController] = []
    private var isRestoringForwardController = false
    private var activeHistorySwipeDirection: HistorySwipeDirection?

    convenience init(wrapping navigationController: UINavigationController) {
        let viewControllers = navigationController.viewControllers
        navigationController.setViewControllers([], animated: false)
        self.init()
        tabBarItem = navigationController.tabBarItem
        title = navigationController.title
        restorationIdentifier = navigationController.restorationIdentifier
        setViewControllers(viewControllers, animated: false)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        delegate = self
        installHistorySwipeGestures()
        applyInterfaceNavigationChrome()
    }

    override var prefersStatusBarHidden: Bool { true }
    override var childForStatusBarHidden: UIViewController? { nil }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        applyInterfaceNavigationChrome()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        applyInterfaceNavigationChrome()
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        applyInterfaceNavigationChrome()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        applyInterfaceNavigationChrome()
    }

    override func setViewControllers(_ viewControllers: [UIViewController], animated: Bool) {
        super.setViewControllers(viewControllers, animated: animated)
        forwardViewControllers.removeAll()
        applyInterfaceNavigationChrome()
    }

    override func pushViewController(_ viewController: UIViewController, animated: Bool) {
        if !isRestoringForwardController {
            forwardViewControllers.removeAll()
        }
        super.pushViewController(viewController, animated: animated)
        applyInterfaceNavigationChrome()
    }

    override func popViewController(animated: Bool) -> UIViewController? {
        guard viewControllers.count > 1 else {
            applyInterfaceNavigationChrome()
            return nil
        }
        let viewController = super.popViewController(animated: animated)
        if let viewController {
            forwardViewControllers.append(viewController)
        }
        applyInterfaceNavigationChrome()
        return viewController
    }

    override func popToRootViewController(animated: Bool) -> [UIViewController]? {
        let viewControllers = super.popToRootViewController(animated: animated)
        forwardViewControllers.removeAll()
        applyInterfaceNavigationChrome()
        return viewControllers
    }

    override func setNavigationBarHidden(_ hidden: Bool, animated: Bool) {
        super.setNavigationBarHidden(true, animated: false)
        applyInterfaceNavigationChrome()
    }

    func navigationController(_ navigationController: UINavigationController,
                              willShow viewController: UIViewController,
                              animated: Bool) {
        applyInterfaceNavigationChrome()
    }

    func navigationController(_ navigationController: UINavigationController,
                              didShow viewController: UIViewController,
                              animated: Bool) {
        // An interactive pop can be cancelled after popViewController() was asked for.
        // Keep only controllers that are genuinely no longer on the stack.
        forwardViewControllers.removeAll { candidate in
            navigationController.viewControllers.contains { $0 === candidate }
        }
        applyInterfaceNavigationChrome()
    }

    private func installHistorySwipeGestures() {
        interactivePopGestureRecognizer?.isEnabled = true

        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handleHistoryPan(_:)))
        panGesture.maximumNumberOfTouches = 1
        panGesture.cancelsTouchesInView = false
        panGesture.delegate = self
        view.addGestureRecognizer(panGesture)
    }

    @objc private func handleHistoryPan(_ gesture: UIPanGestureRecognizer) {
        guard gesture.state == .ended else {
            if gesture.state == .cancelled || gesture.state == .failed {
                activeHistorySwipeDirection = nil
            }
            return
        }

        let translation = gesture.translation(in: view)
        let velocity = gesture.velocity(in: view)
        defer { activeHistorySwipeDirection = nil }

        switch activeHistorySwipeDirection {
        case .back:
            break  // UINavigationController owns the interactive leading-edge pop.
        case .forward:
            guard translation.x < -60 || velocity.x < -400,
                  let viewController = forwardViewControllers.popLast() else { return }
            isRestoringForwardController = true
            pushViewController(viewController, animated: true)
            isRestoringForwardController = false
        case .none:
            break
        }
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let panGesture = gestureRecognizer as? UIPanGestureRecognizer else { return true }
        guard !isCurrentStackRouteOwned else { return false }

        let start = panGesture.location(in: view)
        let velocity = panGesture.velocity(in: view)
        let edgeWidth: CGFloat = 32
        let isNearForwardEdge = start.x >= view.bounds.width - edgeWidth
        guard isNearForwardEdge else { return false }
        if abs(velocity.y) > abs(velocity.x) * 1.6 { return false }

        if isNearForwardEdge, !forwardViewControllers.isEmpty {
            activeHistorySwipeDirection = .forward
            return true
        }

        activeHistorySwipeDirection = nil
        return false
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        gestureRecognizer is UIPanGestureRecognizer
    }

    private var isCurrentStackRouteOwned: Bool {
        switch Router.shared.currentRoute {
        case .anime, .animeThread, .player:
            return true
        default:
            return false
        }
    }

    private func applyInterfaceNavigationChrome() {
        super.setNavigationBarHidden(true, animated: false)
        isToolbarHidden = true
        navigationBar.isHidden = true
        navigationBar.alpha = 0
        navigationBar.isUserInteractionEnabled = false
        toolbar.isHidden = true
        toolbar.alpha = 0
        navigationBar.prefersLargeTitles = false
        navigationBar.standardAppearance.configureWithTransparentBackground()
        navigationBar.scrollEdgeAppearance = navigationBar.standardAppearance
        additionalSafeAreaInsets.top = 0
        interactivePopGestureRecognizer?.isEnabled = !isCurrentStackRouteOwned && viewControllers.count > 1
    }
}
