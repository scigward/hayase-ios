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

/// Cross-dissolves the whole screen while `changes` swaps the content.
final class HayaseRouteTransition {
    private static let duration: TimeInterval = 0.2  // fade-out 0.2 ease-in-out
    private static let controlPoint1 = CGPoint(x: 0.42, y: 0)  // ease-in-out
    private static let controlPoint2 = CGPoint(x: 0.58, y: 1)

    private var animator: UIViewPropertyAnimator?

    func perform(in view: UIView, changes: () -> Void) {
        finish()
        guard !UIAccessibility.isReduceMotionEnabled,
              let snapshot = view.snapshotView(afterScreenUpdates: false) else {
            changes()
            return
        }
        snapshot.frame = view.bounds
        snapshot.isUserInteractionEnabled = false  // ::view-transition pointer-events: none
        view.addSubview(snapshot)
        changes()
        view.layoutIfNeeded()

        let animator = UIViewPropertyAnimator(duration: Self.duration,
                                              controlPoint1: Self.controlPoint1,
                                              controlPoint2: Self.controlPoint2) {
            snapshot.alpha = 0
        }
        animator.addCompletion { [weak self, weak animator] _ in
            snapshot.removeFromSuperview()
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
