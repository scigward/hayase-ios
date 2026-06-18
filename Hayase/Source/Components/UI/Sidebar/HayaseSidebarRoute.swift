//
//  HayaseSidebarRoute.swift
//  Hayase
//
//  Made by scigward.
//
//  Mirrors: src/lib/components/ui/sidebar/sidebarlist.svelte
//

import UIKit

// MARK: - HayaseSidebarRoute

enum HayaseSidebarRoute: Hashable {
    case home
    case search
    case schedule
    case w2g
    case chat
    case client
    case donate
    case settings
    case profile

    var tabIndex: Int? {
        switch self {
        case .home: return 0
        case .search: return 1
        case .schedule: return 2
        case .w2g: return 3
        case .chat: return 4
        case .client: return 5
        case .settings: return 6
        case .profile: return 6
        case .donate: return nil
        }
    }

    var href: String {
        switch self {
        case .home: return "/#/app/home"
        case .search: return "/#/app/search"
        case .schedule: return "/#/app/schedule"
        case .w2g: return "/#/app/w2g"
        case .chat: return "/#/app/chat"
        case .client: return "/#/app/client"
        case .donate: return "https://github.com/sponsors/ThaUnknown/"
        case .settings: return "/#/app/settings"
        case .profile: return "/#/app/profile"
        }
    }

    var iconName: String {
        switch self {
        case .home: return "house"
        case .search: return "search"
        case .schedule: return "calendar-days"
        case .w2g: return "users"
        case .chat: return "messages-square"
        case .client: return "download"
        case .donate: return "heart"
        case .settings: return "bolt"
        case .profile: return "log-in"
        }
    }

    var accessibilityTitle: String {
        switch self {
        case .home: return "Home"
        case .search: return "Search"
        case .schedule: return "Schedule"
        case .w2g: return "Watch Together"
        case .chat: return "Chat"
        case .client: return "Client"
        case .donate: return "Donate"
        case .settings: return "Settings"
        case .profile: return "Profile"
        }
    }

    var isNativeRoute: Bool {
        tabIndex != nil
    }
}
