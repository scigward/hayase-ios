//
//  HayaseTabHostController.swift
//  Hayase
//
//  Made by scigward.
//
//  Mirrors: src/routes/app/+layout.svelte (the single <slot /> next to the sidebar)
//

import UIKit

// MARK: - HayaseTabHostController

/// Keeps UIKit's real tab-controller containment and lifecycle while the app
/// draws the visible navigation in HayaseSidebarController.
///
/// The first web-navigation implementation replaced UITabBarController with a
/// plain UIViewController and manually moved UINavigationController children.
/// That bypassed the UIKit tab relationship used by the storyboard roots and
/// made first selection of Schedule, Client and Settings terminate the app.
/// Keeping a real tab host also restores each page's `tabBarController` chain.
final class HayaseTabHostController: UITabBarController {

    init(viewControllers: [UIViewController]) {
        super.init(nibName: nil, bundle: nil)
        setViewControllers(viewControllers, animated: false)
        selectedIndex = 0
        tabBar.isHidden = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        tabBar.isHidden = true
    }

    func select(_ index: Int) {
        guard let viewControllers,
              viewControllers.indices.contains(index),
              index != selectedIndex else { return }
        selectedIndex = index
        tabBar.isHidden = true
    }
}

// MARK: - Host lookup

extension UIViewController {
    var hayaseTabHost: HayaseTabHostController? {
        if let host = tabBarController as? HayaseTabHostController {
            return host
        }
        var candidate = parent
        while let current = candidate {
            if let host = current as? HayaseTabHostController { return host }
            candidate = current.parent
        }
        return nil
    }

    /// Index of the tab this controller currently lives in, if any.
    var hayaseTabIndex: Int? {
        guard let host = hayaseTabHost else { return nil }
        if let navigationController,
           let index = host.viewControllers?.firstIndex(where: { $0 === navigationController }) {
            return index
        }
        var root = self
        while let parent = root.parent, parent !== host {
            root = parent
        }
        guard root.parent === host else { return nil }
        return host.viewControllers?.firstIndex { $0 === root }
    }
}
