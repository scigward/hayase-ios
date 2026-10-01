//
//  UIScrollView+InstantTouches.swift
//  Hayase
//
//  A web page shows :active the moment a finger lands. A UIScrollView holds the touch back for
//  150ms to find out whether it is a scroll, so every button, chip and cell inside one reacts late.
//  Turning that delay off for every scroll view in the app gives all of them the immediate press
//  state; a UIButton must then still let a scroll that starts on it take over.
//

import UIKit
import ObjectiveC

extension UIScrollView {
    static func installInstantTouches() {
        swizzle(#selector(UIView.didMoveToWindow), #selector(hayase_didMoveToWindow))
        swizzle(#selector(UIScrollView.touchesShouldCancel(in:)), #selector(hayase_touchesShouldCancel(in:)))
    }

    private static func swizzle(_ original: Selector, _ replacement: Selector) {
        guard let originalMethod = class_getInstanceMethod(self, original),
              let replacementMethod = class_getInstanceMethod(self, replacement) else { return }
        if class_addMethod(self, original, method_getImplementation(replacementMethod), method_getTypeEncoding(replacementMethod)) {
            class_replaceMethod(self, replacement, method_getImplementation(originalMethod), method_getTypeEncoding(originalMethod))
        } else {
            method_exchangeImplementations(originalMethod, replacementMethod)
        }
    }

    @objc fileprivate func hayase_didMoveToWindow() {
        hayase_didMoveToWindow()
        if window != nil { delaysContentTouches = false }
    }

    @objc fileprivate func hayase_touchesShouldCancel(in view: UIView) -> Bool {
        view is UIButton || hayase_touchesShouldCancel(in: view)
    }
}
