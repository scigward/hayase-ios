//
//  AppDelegate.swift
//  FinalProject
//
//  Created by Charles Augustine.
//
//


import UIKit
import AVFoundation
import CoreData


@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
	func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Hayase is `color-scheme: only dark` — enforce dark mode throughout the app
        window?.overrideUserInterfaceStyle = .dark
        UIScrollView.installInstantTouches()
        AniListRefocus.shared.start()
        TrackerAggregator.start()
        AniListConnectionStatus.shared.start()
        AniListTracking.shared.start()
        _ = AniListOfflineQueue.shared   // the failed mutations of last time go out
        installSidebarShellIfNeeded()

        // Configure audio session for playback. This is required for:
        // 1. PiP — the system refuses to enter PiP without a playback session
        // 2. AirPlay video — the content source must be backed by an active
        //    audio session so the system routes both audio and video
        // 3. Background audio — keeps the torrent stream server alive while
        //    the player is in PiP or the screen is locked
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("⚠️ AVAudioSession setup failed: \(error)")
        }

        // Observe external-display availability from launch without claiming
        // the display. A dedicated window is created only for active video.
        _ = ExternalDisplayManager.shared

        // Restore mini-player session from previous launch (Hayase:
        // server.active auto-mounts the player on app reload).
        // Dispatched async to let the root view controller finish loading
        // from the storyboard before the mini-player window is created.
        DispatchQueue.main.async {
            HayaseInterfaceScale.apply()
            // Nothing is playing before the setup has been done
            if SetupFlow.isFinished { MiniPlayerManager.shared.restoreSessionIfNeeded() }
        }

		return true
	}

    /// `routes/+page.ts`: the app is the setup until `setup-finished` has reached the version.
    private func installSetup() {
        window?.rootViewController = SetupViewController()
        window?.makeKeyAndVisible()
    }

    /// Next on the last step of the setup, which is `goto('/#/app/home', { replaceState: true })`: the
    /// app takes the place of the setup, with the crossfade of a view transition.
    func finishSetup() {
        guard let window,
              let tabs = UIStoryboard(name: "Main", bundle: nil).instantiateInitialViewController() as? UITabBarController else { return }
        SetupFlow.markFinished()
        setupTransition.perform(in: window) {
            window.rootViewController = HayaseSidebarController(tabBarController: tabs)
            window.makeKeyAndVisible()
            HayaseInterfaceScale.apply()
        }
    }

    private func installSidebarShellIfNeeded() {
        guard SetupFlow.isFinished else {
            installSetup()
            return
        }
        guard let tabBarController = window?.rootViewController as? UITabBarController else { return }
        // Preserve the storyboard tab controller and its relationship-owned
        // navigation stacks. Rebuilding this graph caused destination roots
        // that had never appeared (Schedule, Client and Settings) to crash on
        // their first lifecycle transition.
        window?.rootViewController = HayaseSidebarController(tabBarController: tabBarController)
        window?.makeKeyAndVisible()
    }

    /// Native equivalent of the interface restart after clearing its stores.
    func rebuildInterfaceAfterSettingsReset() {
        // The reset clears `setup-finished` with the rest, so the interface starts over with the setup.
        guard SetupFlow.isFinished else {
            installSetup()
            HayaseInterfaceScale.apply()
            return
        }
        guard let tabs = UIStoryboard(name: "Main", bundle: nil).instantiateInitialViewController() as? UITabBarController else { return }
        window?.rootViewController = HayaseSidebarController(tabBarController: tabs)
        window?.makeKeyAndVisible()
        HayaseInterfaceScale.apply()
    }

    /// `native.restart()`, which logging out of a tracker ends with: the interface starts over on the page it was on.
    func restartInterface() {
        let route = Router.shared.currentRoute
        MiniPlayerManager.shared.close()
        rebuildInterfaceAfterSettingsReset()
        DispatchQueue.main.async { Router.shared.replace(route) }
    }

    // MARK: - Background / Termination

    func applicationDidEnterBackground(_ application: UIApplication) {
        // Re-save the mini-player session state so the current playback
        // position is up to date when the app is killed in the background.
        MiniPlayerManager.shared.resaveSessionStateIfActive()
    }

    /// Whether applicationDidBecomeActive has already fired once.
    /// Used to guard the fallback restore attempt so it only runs on cold start.
    private var hasEnteredForeground = false

    func applicationDidBecomeActive(_ application: UIApplication) {
        // Fallback: retry the mini-player restore once the scene is
        // foregroundActive. The initial async dispatch may run before the
        // shell's root view is ready to host the mini-player.
        guard !hasEnteredForeground else { return }
        hasEnteredForeground = true
        if SetupFlow.isFinished { MiniPlayerManager.shared.restoreSessionIfNeeded() }
    }

	// MARK: Properties
	var window: UIWindow?
    private let setupTransition = HayaseRouteTransition()
}


extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
