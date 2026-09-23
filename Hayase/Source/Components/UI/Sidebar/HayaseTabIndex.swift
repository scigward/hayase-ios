//
//  HayaseTabIndex.swift
//  Hayase
//
//  Made by scigward.
//

import UIKit
import ObjectiveC

private var hayaseLogicalRouteIndexKey: UInt8 = 0

extension UIViewController {
    /// Stable route identity, independent of UIKit's visible tab slot.
    var hayaseLogicalRouteIndex: Int? {
        get { (objc_getAssociatedObject(self, &hayaseLogicalRouteIndexKey) as? NSNumber)?.intValue }
        set {
            objc_setAssociatedObject(self, &hayaseLogicalRouteIndexKey,
                                     newValue.map { NSNumber(value: $0) }, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }

    var hayaseTabIndex: Int? {
        if let index = hayaseLogicalRouteIndex ?? navigationController?.hayaseLogicalRouteIndex {
            return index
        }
        guard let tab = tabBarController else { return nil }
        if let navigationController,
           let index = tab.viewControllers?.firstIndex(where: { $0 === navigationController }) {
            return index
        }
        return tab.selectedIndex
    }
}
