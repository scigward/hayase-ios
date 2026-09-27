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

        // Force TorrentService initialization so libtorrent restores previous
        // torrents via fastResume before we attempt session restore.
        _ = TorrentService.sharedTorrentService

        // Restore mini-player session from previous launch (Hayase:
        // server.active auto-mounts the player on app reload).
        // Dispatched async to let the root view controller finish loading
        // from the storyboard before the mini-player window is created.
        DispatchQueue.main.async {
            HayaseInterfaceScale.apply()
            MiniPlayerManager.shared.restoreSessionIfNeeded()
        }

		return true
	}

    private func installSidebarShellIfNeeded() {
        guard let tabBarController = window?.rootViewController as? UITabBarController else { return }
        // Preserve the storyboard tab controller and its relationship-owned
        // navigation stacks. Rebuilding this graph caused destination roots
        // that had never appeared (Schedule, Client and Settings) to crash on
        // their first lifecycle transition.
        window?.rootViewController = HayaseSidebarController(tabBarController: tabBarController)
        window?.makeKeyAndVisible()
    }

    // MARK: - URL Scheme Handling

    /// Handle incoming URLs from the `hayase://` URL scheme, including the
    /// invite handoff emitted by hayase.watch/w2g/<code>.
    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        if url.scheme?.lowercased() == "hayase", url.host?.lowercased() == "w2g" {
            guard let code = Self.w2gInviteCode(from: url) else { return false }
            // The website opens this scheme while the app may still be launching.
            // Let the storyboard shell install and observe the router first.
            DispatchQueue.main.async { [weak self] in
                self?.installSidebarShellIfNeeded()
                guard let shell = self?.window?.rootViewController as? HayaseSidebarController else { return }
                shell.loadViewIfNeeded()
                Router.shared.navigate(.w2g(id: code))
            }
            return true
        }

        // AniList implicit grant: hayase://#access_token=xxx&token_type=Bearer&expires_in=xxx
        if let fragment = url.fragment {
            let params = fragment.components(separatedBy: "&")
                .reduce(into: [String: String]()) { dict, pair in
                    let parts = pair.components(separatedBy: "=")
                    if parts.count == 2 { dict[parts[0]] = parts[1] }
                }
            if let token = params["access_token"] {
                let expiresIn = params["expires_in"].flatMap(TimeInterval.init)
                AniListAuth.completeLogin(token: token, expiresIn: expiresIn)
                return true
            }
        }

        // MAL PKCE flow: hayase://callback?code=xxx
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let code = components.queryItems?.first(where: { $0.name == "code" })?.value,
           let verifier = UserDefaults.standard.string(forKey: "mal_code_verifier") {
            MALAuth.completeLogin(code: code, codeVerifier: verifier)
            return true
        }

        return false
    }

    private static func w2gInviteCode(from url: URL) -> String? {
        guard url.user == nil, url.password == nil, url.port == nil,
              url.query == nil, url.fragment == nil else { return nil }
        let components = url.path.split(separator: "/", omittingEmptySubsequences: true)
        guard components.count == 1, components[0].utf8.count == 8,
              components[0].utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }) else {
            return nil
        }
        return components[0].lowercased()
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
        // confirmed foregroundActive. The initial async dispatch from
        // didFinishLaunchingWithOptions may fire before the window scene
        // is fully active, causing makePassthroughWindow to fail silently.
        guard !hasEnteredForeground else { return }
        hasEnteredForeground = true
        MiniPlayerManager.shared.restoreSessionIfNeeded()
    }

	// MARK: Properties
	var window: UIWindow?
}


extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
