//
//  HayaseRouteTransition.swift
//  Hayase
//
//  Mirrors: src/routes/+layout.svelte (onNavigate view transition)
//

import UIKit

/// Performs one container transition without retaining route snapshots.
final class HayaseRouteTransition {
    // The earlier tab host used this duration and UIKit's cross-dissolve.
    private static let duration: TimeInterval = 0.16

    func perform(in view: UIView, changes: @escaping () -> Void) {
        guard !UIAccessibility.isReduceMotionEnabled, view.window != nil else {
            changes()
            return
        }
        UIView.transition(with: view,
                          duration: Self.duration,
                          options: [.transitionCrossDissolve, .allowAnimatedContent],
                          animations: changes)
    }
}
