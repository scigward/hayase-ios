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
    private var forwardViewControllers: [UIViewController] = []
    private var isRestoringForwardController = false

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
        applyInterfaceNavigationChrome()
    }

    private func installHistorySwipeGestures() {
        interactivePopGestureRecognizer?.isEnabled = false

        let backGesture = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(handleBackSwipe(_:)))
        backGesture.edges = .left
        backGesture.delegate = self
        view.addGestureRecognizer(backGesture)

        let forwardGesture = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(handleForwardSwipe(_:)))
        forwardGesture.edges = .right
        forwardGesture.delegate = self
        view.addGestureRecognizer(forwardGesture)
    }

    @objc private func handleBackSwipe(_ gesture: UIScreenEdgePanGestureRecognizer) {
        guard gesture.state == .ended else { return }
        let translation = gesture.translation(in: view)
        let velocity = gesture.velocity(in: view)
        guard translation.x > 60 || velocity.x > 400 else { return }
        _ = popViewController(animated: true)
    }

    @objc private func handleForwardSwipe(_ gesture: UIScreenEdgePanGestureRecognizer) {
        guard gesture.state == .ended else { return }
        let translation = gesture.translation(in: view)
        let velocity = gesture.velocity(in: view)
        guard translation.x < -60 || velocity.x < -400 else { return }
        guard let viewController = forwardViewControllers.popLast() else { return }
        isRestoringForwardController = true
        pushViewController(viewController, animated: true)
        isRestoringForwardController = false
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let edgeGesture = gestureRecognizer as? UIScreenEdgePanGestureRecognizer else { return true }
        if edgeGesture.edges == .left {
            return viewControllers.count > 1
        }
        if edgeGesture.edges == .right {
            return !forwardViewControllers.isEmpty
        }
        return true
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
    }
}
