//
//  HayaseTabIndex.swift
//  Hayase
//
//  Made by scigward.
//

import UIKit

extension UIViewController {
    /// Index of the storyboard tab this controller currently belongs to.
    ///
    /// UIKit can place overflow tabs inside its More navigation controller on
    /// compact devices, so prefer the owning navigation controller's original
    /// index and fall back to the currently selected tab.
    var hayaseTabIndex: Int? {
        guard let tab = tabBarController else { return nil }
        if let navigationController,
           let index = tab.viewControllers?.firstIndex(where: { $0 === navigationController }) {
            return index
        }
        return tab.selectedIndex
    }
}
