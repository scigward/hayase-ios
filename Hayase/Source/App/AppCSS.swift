//
//  AppCSS.swift
//  Hayase
//
//  Mirrors: src/app.css, the rule that everything that can be pressed gets smaller while it is:
//
//      a[href], button, fieldset, input, optgroup, option, select, textarea, details, [tabindex], [contenteditable] {
//        &:active:not([disabled], [type='range'], .no-scale, [tabindex="-1"]) {
//          transition: all 0.1s ease-in-out;
//          transform: scale(0.98);
//        }
//      }
//
//  The element goes to 98% in a tenth of a second, `ease-in-out`, and is back at once when it is let go (its own
//  transition is `transition-colors`, which has no transform in it). Here one recognizer on the window watches the
//  touches and scales the element that is pressed: a control that is enabled (a `button`, `input` or `select`),
//  an editable text view (`textarea`), or a view that takes the D-pad's click (`[tabindex]`). A view that does
//  not take part says so with `NoActiveScale` (`.no-scale`, `type=range`), or is one that scales itself.
//

import UIKit
import UIKit.UIGestureRecognizerSubclass
import ObjectiveC

/// `.no-scale`, `type=range`, or an element that already scales itself while it is pressed
protocol NoActiveScale {}

private var noActiveScaleKey: UInt8 = 0

extension UIView {
    /// `.no-scale` on one view
    var noActiveScale: Bool {
        get { (objc_getAssociatedObject(self, &noActiveScaleKey) as? NSNumber)?.boolValue ?? false }
        set { objc_setAssociatedObject(self, &noActiveScaleKey, NSNumber(value: newValue), .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }
}

enum ActiveScale {
    static let scale: CGFloat = 0.98
    static let duration: TimeInterval = 0.1

    static func install(in window: UIWindow) {
        window.addGestureRecognizer(Observer())
    }

    /// The element that a touch presses: the nearest view above it that is one, unless it opted out
    static func element(at touch: UITouch) -> UIView? {
        var view = touch.view
        while let current = view {
            if current is NoActiveScale || current.noActiveScale { return nil }
            if isElement(current) { return current }
            view = current.superview
        }
        return nil
    }

    private static func isElement(_ view: UIView) -> Bool {
        // `[disabled]`
        if let control = view as? UIControl {
            // a bare UIControl is the click catcher of a dialog or popover: not an element
            return control.isEnabled && type(of: control) != UIControl.self
        }
        if let text = view as? UITextView { return text.isEditable }
        return view.onDPadClick != nil
    }

    private final class Observer: UIGestureRecognizer, UIGestureRecognizerDelegate {
        private weak var pressed: UIView?
        private var restingTransform = CGAffineTransform.identity
        private var animator: UIViewPropertyAnimator?

        init() {
            super.init(target: nil, action: nil)
            cancelsTouchesInView = false
            delaysTouchesBegan = false
            delaysTouchesEnded = false
            delegate = self
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
            guard pressed == nil, let touch = touches.first, let target = ActiveScale.element(at: touch) else { return }
            pressed = target
            restingTransform = target.transform
            let pressedTransform = restingTransform.scaledBy(x: ActiveScale.scale, y: ActiveScale.scale)
            // transition: all 0.1s ease-in-out
            let animator = UIViewPropertyAnimator(duration: ActiveScale.duration,
                                                  controlPoint1: CGPoint(x: 0.42, y: 0),
                                                  controlPoint2: CGPoint(x: 0.58, y: 1)) {
                target.transform = pressedTransform
            }
            self.animator = animator
            animator.startAnimation()
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
            release()
        }

        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
            release()
        }

        override func reset() {
            release()
        }

        /// Out of `:active` the element is back at once
        private func release() {
            animator?.stopAnimation(true)
            animator = nil
            if let view = pressed {
                UIView.performWithoutAnimation { view.transform = restingTransform }
            }
            pressed = nil
        }
    }
}
