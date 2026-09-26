//
//  HayasePlayerPresentation.swift
//  Hayase
//
//  Made by scigward.
//
//  Mirrors: src/lib/components/ui/player/player.svelte (onNavigate/onMount fullscreen branch)
//

import UIKit

extension UIViewController {
    func presentHayasePlayer(_ player: VideoPlayerViewController,
                             animated: Bool = true,
                             completion: (() -> Void)? = nil) {
        player.modalTransitionStyle = .crossDissolve
        // Player route ownership must not change depending on how quickly torrent metadata resolves.
        let usesPlayerRouteHost = Router.shared.currentRoute == .player
            || UIDevice.current.userInterfaceIdiom == .pad
            || player.isLoadingMetadata
        if usesPlayerRouteHost, let nav = hayaseShellNavigationController() {
            let pushPlayer = {
                nav.setNavigationBarHidden(true, animated: false)
                nav.navigationBar.isHidden = true
                if nav.topViewController !== player {
                    if nav.viewControllers.contains(where: { $0 === player }) {
                        nav.popToViewController(player, animated: false)
                    } else {
                        nav.pushViewController(player, animated: animated)
                    }
                }
                player.enterFullscreenForPlayerRouteIfNeeded()
                if let completion = completion {
                    DispatchQueue.main.asyncAfter(deadline: .now() + (animated ? 0.35 : 0), execute: completion)
                }
            }
            if presentingViewController != nil && navigationController?.tabBarController == nil {
                dismiss(animated: false, completion: pushPlayer)
            } else {
                pushPlayer()
            }
            return
        }

        player.modalPresentationStyle = .fullScreen
        present(player, animated: animated, completion: completion)
    }

    var hayaseSidebarController: HayaseSidebarController? {
        var current: UIViewController? = self
        while let controller = current {
            if let sidebar = controller as? HayaseSidebarController { return sidebar }
            current = controller.parent
        }
        return presentingViewController?.hayaseSidebarController
    }

    func hayaseShellNavigationController() -> UINavigationController? {
        if let nav = navigationController, nav.tabBarController != nil {
            return nav
        }
        if let tab = tabBarController,
           let nav = tab.selectedViewController as? UINavigationController {
            return nav
        }
        for child in children {
            if let tab = child as? UITabBarController,
               let nav = tab.selectedViewController as? UINavigationController {
                return nav
            }
            if let nav = child as? UINavigationController,
               nav.tabBarController != nil {
                return nav
            }
        }
        if let presenting = presentingViewController {
            return presenting.hayaseShellNavigationController()
        }
        if let parent = parent {
            return parent.hayaseShellNavigationController()
        }
        return nil
    }
}
