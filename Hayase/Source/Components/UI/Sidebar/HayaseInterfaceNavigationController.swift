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

final class HayaseInterfaceNavigationController: UINavigationController {
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
        applyInterfaceNavigationChrome()
    }

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

    override func setViewControllers(_ viewControllers: [UIViewController], animated: Bool) {
        super.setViewControllers(viewControllers, animated: animated)
        applyInterfaceNavigationChrome()
    }

    override func pushViewController(_ viewController: UIViewController, animated: Bool) {
        super.pushViewController(viewController, animated: animated)
        applyInterfaceNavigationChrome()
    }

    override func popViewController(animated: Bool) -> UIViewController? {
        let viewController = super.popViewController(animated: animated)
        applyInterfaceNavigationChrome()
        return viewController
    }

    override func popToRootViewController(animated: Bool) -> [UIViewController]? {
        let viewControllers = super.popToRootViewController(animated: animated)
        applyInterfaceNavigationChrome()
        return viewControllers
    }

    override func setNavigationBarHidden(_ hidden: Bool, animated: Bool) {
        super.setNavigationBarHidden(true, animated: false)
        applyInterfaceNavigationChrome()
    }

    private func applyInterfaceNavigationChrome() {
        super.setNavigationBarHidden(true, animated: false)
        navigationBar.isHidden = true
        navigationBar.alpha = 0
        navigationBar.isUserInteractionEnabled = false
        navigationBar.prefersLargeTitles = false
        navigationBar.standardAppearance.configureWithTransparentBackground()
        navigationBar.scrollEdgeAppearance = navigationBar.standardAppearance
        additionalSafeAreaInsets.top = 0
    }
}
