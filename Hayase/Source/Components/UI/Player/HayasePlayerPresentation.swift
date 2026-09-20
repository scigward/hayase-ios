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
    var hayaseShouldEmbedPlayerInShell: Bool {
        // player.svelte: SUPPORTS.isMobile && !SUPPORTS.isIPad forces fullscreen.
        UIDevice.current.userInterfaceIdiom == .pad
    }

    func presentHayasePlayer(_ player: VideoPlayerViewController,
                             animated: Bool = true,
                             completion: (() -> Void)? = nil) {
        player.modalTransitionStyle = .crossDissolve
        if hayaseShouldEmbedPlayerInShell, let nav = hayaseShellNavigationController() {
            let pushPlayer = {
                nav.setNavigationBarHidden(true, animated: false)
                nav.navigationBar.isHidden = true
                nav.pushViewController(player, animated: animated)
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
