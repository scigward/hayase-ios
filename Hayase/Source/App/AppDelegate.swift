//
//  AppDelegate.swift
//  Hayase
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
        if let window { Navigate.observePointer(in: window) }   // `inputType`
        HardwareKeys.start()
        Gamepad.shared.start()
        AniListRefocus.shared.start()
        TrackerAggregator.start()
        AniListConnectionStatus.shared.start()
        AniListTracking.shared.start()
        _ = AniListOfflineQueue.shared   // the failed mutations of last time go out
        installSplash()

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

        // The mini-player session of the previous launch is restored (Hayase: server.active
        // auto-mounts the player on app reload) once the splash has given way to the app: see finishSplash().
        DispatchQueue.main.async {
            HayaseInterfaceScale.apply()
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
        let tabs = launchTabs
            ?? UIStoryboard(name: "Main", bundle: nil).instantiateInitialViewController() as? UITabBarController
        launchTabs = nil
        guard let window, let tabs else { return }
        SetupFlow.markFinished()
        setupTransition.perform(in: window) {
            window.rootViewController = HayaseSidebarController(tabBarController: tabs)
            window.makeKeyAndVisible()
            HayaseInterfaceScale.apply()
        }
        DispatchQueue.main.async { DeepLink.shellDidAppear() }
    }

    /// `routes/+page.svelte`: the app opens on the splash. The tab controller the storyboard made is kept
    /// for the shell that follows it.
    private func installSplash() {
        launchTabs = window?.rootViewController as? UITabBarController
        window?.rootViewController = SplashViewController()
        window?.makeKeyAndVisible()
    }

    /// The end of the splash, `goto(data.goto, { replaceState: true })`: Home, or the setup when it has not
    /// been done, in place of the splash and with the crossfade of a view transition.
    func finishSplash() {
        guard let window, window.rootViewController is SplashViewController else { return }
        // menubar.svelte: the "Debug Mode!" ribbon is part of the root layout, so the setup has it too
        DebugRibbonWindow.installIfNeeded(in: window.windowScene)
        let finished = SetupFlow.isFinished
        splashTransition.perform(in: window) { [self] in
            if finished { installSidebarShell() } else { installSetup() }
            HayaseInterfaceScale.apply()
        }
        if finished {
            // Hayase: server.active auto-mounts the player on app reload
            DispatchQueue.main.async {
                MiniPlayerManager.shared.restoreSessionIfNeeded()
                DeepLink.shellDidAppear()
            }
        }
    }

    private func installSidebarShell() {
        // Preserve the storyboard tab controller and its relationship-owned
        // navigation stacks. Rebuilding this graph caused destination roots
        // that had never appeared (Schedule, Client and Settings) to crash on
        // their first lifecycle transition.
        let tabs = launchTabs
            ?? UIStoryboard(name: "Main", bundle: nil).instantiateInitialViewController() as? UITabBarController
        launchTabs = nil
        guard let tabs else { return }
        window?.rootViewController = HayaseSidebarController(tabBarController: tabs)
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

    // MARK: - Links

    /// `hayase://` links, which the app registers (Info.plist `CFBundleURLTypes`)
    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        guard DeepLink.target(for: url) != nil else { return false }
        DeepLink.open(url)
        return true
    }

    /// Links of hayase.watch, where the app has them (associated domains)
    func application(_ application: UIApplication, continue userActivity: NSUserActivity,
                     restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        guard userActivity.activityType == NSUserActivityTypeBrowsingWeb,
              let url = userActivity.webpageURL, DeepLink.target(for: url) != nil else { return false }
        DeepLink.open(url)
        return true
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
        if window?.rootViewController is HayaseSidebarController { MiniPlayerManager.shared.restoreSessionIfNeeded() }
    }

    // MARK: Keys

    /// The end of the responder chain is the window of the page: a key of a hardware keyboard that no responder
    /// had a command for gets here. The arrows are what `navigate` listens for there, and Enter is the click of the
    /// focused element that the browser makes.
    override var keyCommands: [UIKeyCommand]? {
        [.keydown(KeyboardEvent.Key.arrowUp), .keydown(KeyboardEvent.Key.arrowDown),
         .keydown(KeyboardEvent.Key.arrowLeft), .keydown(KeyboardEvent.Key.arrowRight),
         .keydown(KeyboardEvent.Key.enter)]
    }

	// MARK: Properties
	var window: UIWindow?
    private let setupTransition = HayaseRouteTransition()
    private let splashTransition = HayaseRouteTransition()
    /// What the storyboard made of the tabs, for the shell to take after the splash.
    private var launchTabs: UITabBarController?
}


extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
