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
        // Apply Nunito Variable font globally (mirrors Hayase's `font-family: 'Nunito Variable'`)
        AppDelegate.applyNunitoFont()
		return true
	}

    // MARK: - Nunito Font (matches Hayase `font-family: 'Nunito Variable'`)
    // Hayase src/app.css: `font-family: 'Nunito Variable'` on html,body
    // We swizzle UIFont class methods so every label, button, nav bar etc uses Nunito.
    private static func applyNunitoFont() {
        // Map UIFont.Weight → Nunito PostScript name (from the variable font's named instances)
        swizzleFontMethods()

        // UIAppearance: navigation bar title + bar button items
        let navAppearance = UINavigationBarAppearance()
        navAppearance.configureWithOpaqueBackground()
        navAppearance.backgroundColor = .black
        navAppearance.titleTextAttributes = [
            .font: UIFont(name: "Nunito-SemiBold", size: 17) ?? .systemFont(ofSize: 17, weight: .semibold)
        ]
        navAppearance.largeTitleTextAttributes = [
            .font: UIFont(name: "Nunito-Bold", size: 34) ?? .systemFont(ofSize: 34, weight: .bold)
        ]
        UINavigationBar.appearance().standardAppearance = navAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navAppearance
        UINavigationBar.appearance().compactAppearance = navAppearance

        // Tab bar labels
        let tabAppearance = UITabBarItemAppearance()
        let tabFont = UIFont(name: "Nunito-Regular", size: 10) ?? .systemFont(ofSize: 10)
        let tabFontSelected = UIFont(name: "Nunito-SemiBold", size: 10) ?? .systemFont(ofSize: 10, weight: .semibold)
        tabAppearance.normal.titleTextAttributes = [.font: tabFont]
        tabAppearance.selected.titleTextAttributes = [.font: tabFontSelected]
        let tabBarAppearance = UITabBarAppearance()
        tabBarAppearance.configureWithOpaqueBackground()
        tabBarAppearance.stackedLayoutAppearance = tabAppearance
        tabBarAppearance.inlineLayoutAppearance = tabAppearance
        tabBarAppearance.compactInlineLayoutAppearance = tabAppearance
        UITabBar.appearance().standardAppearance = tabBarAppearance
        if #available(iOS 15.0, *) {
            UITabBar.appearance().scrollEdgeAppearance = tabBarAppearance
        }
    }

    private static var _swizzled = false
    private static func swizzleFontMethods() {
        guard !_swizzled else { return }
        _swizzled = true

        // Swizzle UIFont.systemFont(ofSize:) → Nunito-Regular
        let cls: AnyClass = UIFont.self
        if let orig = class_getClassMethod(cls, #selector(UIFont.systemFont(ofSize:))),
           let rep  = class_getClassMethod(cls, #selector(UIFont.nnt_systemFont(ofSize:))) {
            method_exchangeImplementations(orig, rep)
        }
        // Swizzle UIFont.boldSystemFont(ofSize:) → Nunito-Bold
        if let orig = class_getClassMethod(cls, #selector(UIFont.boldSystemFont(ofSize:))),
           let rep  = class_getClassMethod(cls, #selector(UIFont.nnt_boldSystemFont(ofSize:))) {
            method_exchangeImplementations(orig, rep)
        }
        // Swizzle UIFont.systemFont(ofSize:weight:) → Nunito weight mapping
        if let orig = class_getClassMethod(cls, #selector(UIFont.systemFont(ofSize:weight:))),
           let rep  = class_getClassMethod(cls, #selector(UIFont.nnt_systemFont(ofSize:weight:))) {
            method_exchangeImplementations(orig, rep)
        }
        // Swizzle UIFont.italicSystemFont(ofSize:) → Nunito-Italic (falls back to Regular if unavailable)
        if let orig = class_getClassMethod(cls, #selector(UIFont.italicSystemFont(ofSize:))),
           let rep  = class_getClassMethod(cls, #selector(UIFont.nnt_italicSystemFont(ofSize:))) {
            method_exchangeImplementations(orig, rep)
        }
    }

	// MARK: Properties
	var window: UIWindow?
}

// MARK: - UIFont Nunito swizzle replacements
extension UIFont {
    // Regular
    @objc class func nnt_systemFont(ofSize size: CGFloat) -> UIFont {
        UIFont(name: "Nunito-Regular", size: size) ?? UIFont.nnt_systemFont(ofSize: size)
    }
    // Bold
    @objc class func nnt_boldSystemFont(ofSize size: CGFloat) -> UIFont {
        UIFont(name: "Nunito-Bold", size: size) ?? UIFont.nnt_boldSystemFont(ofSize: size)
    }
    // Italic (Nunito variable font has an italic axis; fallback to Regular)
    @objc class func nnt_italicSystemFont(ofSize size: CGFloat) -> UIFont {
        UIFont(name: "Nunito-Regular", size: size) ?? UIFont.nnt_italicSystemFont(ofSize: size)
    }
    // Weight-mapped
    @objc class func nnt_systemFont(ofSize size: CGFloat, weight: UIFont.Weight) -> UIFont {
        let name: String
        switch weight {
        case .ultraLight, .thin, .light:
            name = "Nunito-Light"
        case .regular:
            name = "Nunito-Regular"
        case .medium:
            name = "Nunito-Medium"
        case .semibold:
            name = "Nunito-SemiBold"
        case .bold:
            name = "Nunito-Bold"
        case .heavy, .black:
            name = "Nunito-Black"
        default:
            name = "Nunito-Regular"
        }
        return UIFont(name: name, size: size) ?? UIFont.nnt_systemFont(ofSize: size, weight: weight)
    }
}

