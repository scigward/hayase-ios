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

/// Shows one root navigation controller at a time. The app draws its own
/// sidebar, so this replaces the hidden UITabBarController, which moves every
/// tab past the fifth under its "More" navigation controller at compact widths.
final class HayaseTabHostController: UIViewController {
    let viewControllers: [UIViewController]
    private(set) var selectedIndex = 0

    var selectedViewController: UIViewController? {
        viewControllers.indices.contains(selectedIndex) ? viewControllers[selectedIndex] : nil
    }

    init(viewControllers: [UIViewController]) {
        self.viewControllers = viewControllers
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        if let selected = selectedViewController {
            embed(selected)
        }
    }

    func select(_ index: Int) {
        guard viewControllers.indices.contains(index), index != selectedIndex else { return }
        let outgoing = selectedViewController
        selectedIndex = index
        guard isViewLoaded else { return }
        if let outgoing {
            unembed(outgoing)
        }
        if let incoming = selectedViewController {
            embed(incoming)
        }
    }

    private func embed(_ child: UIViewController) {
        addChild(child)
        child.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(child.view)
        NSLayoutConstraint.activate([
            child.view.topAnchor.constraint(equalTo: view.topAnchor),
            child.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            child.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            child.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        child.didMove(toParent: self)
    }

    private func unembed(_ child: UIViewController) {
        child.willMove(toParent: nil)
        child.view.removeFromSuperview()
        child.removeFromParent()
    }
}

// MARK: - Host lookup

extension UIViewController {
    var hayaseTabHost: HayaseTabHostController? {
        var candidate = parent
        while let current = candidate {
            if let host = current as? HayaseTabHostController { return host }
            candidate = current.parent
        }
        return nil
    }

    /// Index of the tab this controller currently lives in, if any.
    var hayaseTabIndex: Int? {
        hayaseTabHost?.selectedIndex
    }
}
