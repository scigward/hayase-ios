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
        let incoming = viewControllers[index]
        selectedIndex = index
        guard isViewLoaded else { return }

        guard let outgoing else {
            embed(incoming)
            return
        }

        outgoing.willMove(toParent: nil)
        addChild(incoming)
        prepareView(incoming.view)

        transition(from: outgoing,
                   to: incoming,
                   duration: 0,
                   options: [.transitionCrossDissolve, .allowAnimatedContent],
                   animations: nil) { [weak self, weak outgoing, weak incoming] _ in
            guard let self, let outgoing, let incoming else { return }
            outgoing.removeFromParent()
            incoming.didMove(toParent: self)
        }
    }

    private func embed(_ child: UIViewController) {
        addChild(child)
        prepareView(child.view)
        view.addSubview(child.view)
        child.didMove(toParent: self)
    }

    private func prepareView(_ childView: UIView) {
        childView.translatesAutoresizingMaskIntoConstraints = true
        childView.frame = view.bounds
        childView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
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
        guard let host = hayaseTabHost else { return nil }
        var root = self
        while let parent = root.parent, parent !== host {
            root = parent
        }
        guard root.parent === host else { return nil }
        return host.viewControllers.firstIndex { $0 === root }
    }
}
