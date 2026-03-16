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

		return true
	}

	// MARK: Properties
	var window: UIWindow?
}

