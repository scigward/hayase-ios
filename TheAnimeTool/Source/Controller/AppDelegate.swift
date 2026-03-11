//
//  AppDelegate.swift
//  FinalProject
//
//  Created by Charles Augustine.
//
//


import UIKit
import CoreData


@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
	func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Hayase is `color-scheme: only dark` — enforce dark mode throughout the app
        window?.overrideUserInterfaceStyle = .dark
		return true
	}

	// MARK: Properties
	var window: UIWindow?
}

