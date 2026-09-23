//
//  HayaseRouteTransition.swift
//  Hayase
//
//  Mirrors: src/routes/+layout.svelte (onNavigate view transition)
//

import UIKit

final class HayaseRouteTransition {
    private var overlay: UIView?
    private var animator: UIViewPropertyAnimator?

    func finish() {
        animator?.stopAnimation(true)
        animator = nil
        overlay?.removeFromSuperview()
        overlay = nil
    }

    func perform(in view: UIView, changes: @escaping () -> Void) {
        finish()
        view.layoutIfNeeded()
        let snapshot = !UIAccessibility.isReduceMotionEnabled && view.window != nil
            ? view.snapshotView(afterScreenUpdates: false) : nil
        // Commit geometry before animating opacity. A UIKit transition block also
        // animates destination constraints, unlike a browser view transition.
        UIView.performWithoutAnimation {
            changes()
            view.layoutIfNeeded()
        }
        guard let snapshot else { return }
        snapshot.frame = view.bounds
        snapshot.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        snapshot.isUserInteractionEnabled = false
        view.addSubview(snapshot)
        overlay = snapshot
        // The source's animation-name shorthand is invalid; the browser uses
        // the View Transitions default: 250 ms and CSS ease.
        let timing = UICubicTimingParameters(controlPoint1: CGPoint(x: 0.25, y: 0.1),
                                             controlPoint2: CGPoint(x: 0.25, y: 1))
        let animation = UIViewPropertyAnimator(duration: 0.25, timingParameters: timing)
        animation.addAnimations { snapshot.alpha = 0 }
        animation.addCompletion { [weak self, weak snapshot] _ in
            snapshot?.removeFromSuperview()
            if self?.overlay === snapshot {
                self?.overlay = nil
                self?.animator = nil
            }
        }
        animator = animation
        animation.startAnimation()
    }
}
