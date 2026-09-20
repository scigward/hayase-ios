//
//  HayasePlayerPresentation.swift
//  Hayase
//
//  Made by scigward.
//
//  Mirrors: player.svelte route behavior. iPhone enters fullscreen; iPad stays
//  inside the app shell until the user explicitly toggles fullscreen.
//

import UIKit

extension UIViewController {
    var hayaseShouldEmbedPlayerInShell: Bool {
        let traits = view.window?.traitCollection ?? traitCollection
        let bounds = view.window?.bounds ?? view.bounds
        let isPhoneLandscape = traits.userInterfaceIdiom == .phone
            && bounds.width > bounds.height
            && bounds.width >= 568
        return bounds.width >= 768 || traits.horizontalSizeClass == .regular || isPhoneLandscape
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
            if presentingViewController != nil && navigationController?.hayaseTabHost == nil {
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
        if let nav = navigationController, nav.hayaseTabHost != nil {
            return nav
        }
        if let host = hayaseTabHost,
           let nav = host.selectedViewController as? UINavigationController {
            return nav
        }
        for child in children {
            if let host = child as? HayaseTabHostController,
               let nav = host.selectedViewController as? UINavigationController {
                return nav
            }
            if let nav = child as? UINavigationController,
               nav.hayaseTabHost != nil {
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
