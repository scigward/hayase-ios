//
//  RootLayout.swift
//  Hayase
//
//  Mirrors: src/routes/+layout.svelte: what happens when the page changes (`onNavigate`: the view transition, which
//  iOS leaves to the swipe of the system when it is the one going back or forward), the progress bar that shows while
//  a route loads, and the scroll positions and the snapshots of the pages that were left.
//

import UIKit

extension HayaseSidebarController {
    func installProgressBarIfNeeded() {
        guard progressWindow == nil, let scene = view.window?.windowScene else { return }
        progressWindow = HayaseProgressBarWindow(windowScene: scene)
    }

    func installRouteHistoryGestures() {
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handleRouteHistoryPan(_:)))
        panGesture.maximumNumberOfTouches = 1
        panGesture.cancelsTouchesInView = false
        panGesture.delegate = self
        view.addGestureRecognizer(panGesture)
    }

    @objc func handleRouteHistoryPan(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: view)
        switch gesture.state {
        case .began:
            beginHistorySwipe()
        case .changed:
            guard let swipe = historySwipe else { return }
            let dragged = swipe.direction == .back ? translation.x : -translation.x
            guard view.bounds.width > 0 else { return }
            swipe.update(progress: max(dragged, 0) / view.bounds.width)
        case .ended:
            finishHistorySwipe(translation: translation, velocity: gesture.velocity(in: view))
        case .cancelled, .failed:
            historySwipe?.finish(completing: false) { [weak self] in
                self?.endHistorySwipe()
            }
            activeHistorySwipeDirection = nil
        default:
            break
        }
    }

    func beginHistorySwipe() {
        guard historySwipe == nil,
              let direction = activeHistorySwipeDirection,
              let route = direction == .back ? router.previousRoute : router.nextRoute,
              let destination = routeSnapshots[route],
              destination.bounds.size == view.bounds.size,
              let current = view.snapshotView(afterScreenUpdates: false) else { return }
        historySwipe = HayaseHistorySwipe(direction: direction, current: current, destination: destination, host: view)
    }

    func finishHistorySwipe(translation: CGPoint, velocity: CGPoint) {
        let direction = activeHistorySwipeDirection
        activeHistorySwipeDirection = nil
        let commits: Bool
        switch direction {
        case .back:
            commits = translation.x > 60 || velocity.x > 400
        case .forward:
            commits = translation.x < -60 || velocity.x < -400
        case .none:
            commits = false
        }
        guard let swipe = historySwipe else {
            if commits {
                if direction == .back { router.back() } else { router.forward() }
            }
            return
        }
        swipe.finish(completing: commits) { [weak self] in
            guard let self else { return }
            if commits {
                self.completeHistorySwipe(swipe)
            } else {
                self.endHistorySwipe()
            }
        }
    }

    func completeHistorySwipe(_ swipe: HayaseHistorySwipe) {
        if let route = lastAppliedRoute {
            storeSnapshot(swipe.current, for: route)
        }
        let moved = swipe.direction == .back ? router.back() : router.forward()
        if !moved {
            endHistorySwipe()
        }
    }

    func endHistorySwipe() {
        guard let swipe = historySwipe else { return }
        historySwipe = nil
        view.layoutIfNeeded()
        DispatchQueue.main.async {
            swipe.remove()
        }
    }

    func captureSnapshotBeforeRouteChange(to route: Route) {
        guard historySwipe == nil, !isMobileMenuOpen,
              let previousRoute = lastAppliedRoute, previousRoute != route,
              let snapshot = view.snapshotView(afterScreenUpdates: false) else { return }
        storeSnapshot(snapshot, for: previousRoute)
    }

    func storeSnapshot(_ snapshot: UIView, for route: Route) {
        snapshot.frame = view.bounds
        routeSnapshots[route] = snapshot
        routeSnapshotOrder.removeAll { $0 == route }
        routeSnapshotOrder.append(route)
        while routeSnapshotOrder.count > Self.routeSnapshotLimit {
            routeSnapshots.removeValue(forKey: routeSnapshotOrder.removeFirst())
        }
    }

    func beginNavigationProgress() {
        guard !isNavigationLoading else { return }
        isNavigationLoading = true
        progressWindow?.bar.navigationWillBegin()
    }

    func finishNavigationProgress() {
        isNavigationLoading = false
        progressWindow?.bar.navigationDidFinish()
        endHistorySwipe()
    }

    func usesViewTransition(for route: Route, kind: Router.NavigationKind, animated: Bool) -> Bool {
        // iOS runs its own back/forward animation, and entering the mobile player skips it.
        // SvelteKit still runs onNavigate for goto(..., { replaceState: true }).
        guard animated, (kind == .push || kind == .replace) else { return false }
        // supports.ts includes BOTH iPhone and iPad in isMobile.
        if route == .player, UIDevice.current.userInterfaceIdiom == .phone || UIDevice.current.userInterfaceIdiom == .pad { return false }
        guard let player = visiblePlayerForRouteExit() else { return true }
        // Root +layout.svelte skips startViewTransition whenever fullscreenElement is set.
        // Phones force the player fullscreen; iPad can enter the same state manually.
        return UIDevice.current.userInterfaceIdiom != .phone && !player.isFullscreenForRouteNavigation
    }

    func saveScrollPositionBeforeRouteChange(to route: Route) {
        guard let previousRoute = lastAppliedRoute, previousRoute != route,
              let offset = RouteScrollRestoration.capture(from: topVisibleHostedController()) else { return }
        routeScrollPositions[previousRoute] = offset
    }

    func restoreScrollPositionIfNeeded(for route: Route, kind: Router.NavigationKind, noScroll: Bool) {
        switch kind {
        case .back, .forward:
            RouteScrollRestoration.restore(routeScrollPositions[route], in: topVisibleHostedController())
        case .push, .replace, .sync:
            guard !noScroll else { return }
            RouteScrollRestoration.scrollToTop(in: topVisibleHostedController())
        }
    }
}
