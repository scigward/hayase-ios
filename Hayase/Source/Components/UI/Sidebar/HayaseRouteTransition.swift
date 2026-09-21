//
//  HayaseRouteTransition.swift
//  Hayase
//
//  Made by scigward.
//
//  Mirrors: src/routes/+layout.svelte (onNavigate view transition) and src/app.css (:root::view-transition-old/new)
//

import UIKit

// MARK: - HayaseRouteTransition

/// Cross-dissolves old and new root snapshots like the web View Transition.
final class HayaseRouteTransition {
    // app.css uses an invalid animation-name shorthand, so WebKit retains
    // the View Transitions default: a 250ms CSS `ease` crossfade.
    private static let duration: TimeInterval = 0.25
    private static let controlPoint1 = CGPoint(x: 0.25, y: 0.1)
    private static let controlPoint2 = CGPoint(x: 0.25, y: 1)

    private var animator: UIViewPropertyAnimator?

    func perform(in view: UIView, changes: () -> Void) {
        finish()
        guard !UIAccessibility.isReduceMotionEnabled,
              let oldSnapshot = view.snapshotView(afterScreenUpdates: false) else {
            changes()
            return
        }
        oldSnapshot.frame = view.bounds
        oldSnapshot.isUserInteractionEnabled = false  // ::view-transition pointer-events: none
        view.addSubview(oldSnapshot)
        changes()
        view.layoutIfNeeded()

        // The default browser transition fades both pseudo-elements. Hide the
        // old image while capturing the destination, so it cannot be baked
        // into the new image when UIKit produces its snapshot.
        oldSnapshot.isHidden = true
        let newSnapshot = view.snapshotView(afterScreenUpdates: true)
        oldSnapshot.isHidden = false
        newSnapshot?.frame = view.bounds
        newSnapshot?.alpha = 0
        newSnapshot?.isUserInteractionEnabled = false
        if let newSnapshot { view.addSubview(newSnapshot) }

        let animator = UIViewPropertyAnimator(duration: Self.duration,
                                              controlPoint1: Self.controlPoint1,
                                              controlPoint2: Self.controlPoint2) {
            oldSnapshot.alpha = 0
            newSnapshot?.alpha = 1
        }
        animator.addCompletion { [weak self, weak animator] _ in
            oldSnapshot.removeFromSuperview()
            newSnapshot?.removeFromSuperview()
            if self?.animator === animator {
                self?.animator = nil
            }
        }
        self.animator = animator
        animator.startAnimation()
    }

    private func finish() {
        guard let animator, animator.state == .active else { return }
        animator.stopAnimation(false)
        animator.finishAnimation(at: .end)
    }
}
