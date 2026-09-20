//
//  Route.swift
//  Hayase
//
//  Mirrors: src/routes/app/+layout.svelte, src/routes/app/client/+page.ts, src/routes/app/settings/+page.ts, src/routes/app/anime/[id]/thread/[threadId]/+layout.ts
//

import Foundation

// MARK: - Route

enum Route: Hashable {
    case home
    case search(SearchState?)
    case schedule
    case w2g(id: String?)
    case chat
    case client(ClientRoute)
    case settings(SettingsRoute)
    case profile
    case anime(id: Int)
    case animeThread(animeID: Int, threadID: Int)
    case player

    enum ClientRoute: String, Hashable {
        case root = ""
        case overview
        case files
        case peers
        case trackers
        case library
    }

    enum SettingsRoute: String, Hashable {
        case root = ""
        case player
        case client
        case interface
        case extensions
        case accounts
        case app
        case changelog
    }

    struct SearchState: Hashable {
        var title: String?
        var genres: [String]
        var tags: [String]
        var year: String?
        var season: String?
        var formats: [String]
        var statuses: [String]
        var sort: String?
        var onList: Bool?
        var ids: [Int]?

        init(title: String? = nil,
             genres: [String] = [],
             tags: [String] = [],
             year: String? = nil,
             season: String? = nil,
             formats: [String] = [],
             statuses: [String] = [],
             sort: String? = nil,
             onList: Bool? = nil,
             ids: [Int]? = nil) {
            self.title = title
            self.genres = genres
            self.tags = tags
            self.year = year
            self.season = season
            self.formats = formats
            self.statuses = statuses
            self.sort = sort
            self.onList = onList
            self.ids = ids
        }
    }

    var path: String {
        switch self {
        case .home:
            return "/app/home"
        case .search:
            return "/app/search"
        case .schedule:
            return "/app/schedule"
        case .w2g(let id):
            if let id, !id.isEmpty { return "/app/w2g/\(id)" }
            return "/app/w2g"
        case .chat:
            return "/app/chat"
        case .client(.root):
            return "/app/client"
        case .client(let route):
            return "/app/client/\(route.rawValue)"
        case .settings(.root):
            return "/app/settings"
        case .settings(let route):
            return "/app/settings/\(route.rawValue)"
        case .profile:
            return "/app/profile"
        case .anime(let id):
            return "/app/anime/\(id)"
        case .animeThread(let animeID, let threadID):
            return "/app/anime/\(animeID)/thread/\(threadID)"
        case .player:
            return "/app/player"
        }
    }

    var tabIndex: Int? {
        switch self {
        case .home:
            return 0
        case .search:
            return 1
        case .schedule:
            return 2
        case .w2g:
            return 3
        case .chat:
            return 4
        case .client:
            return 5
        case .settings, .profile:
            return 6
        case .anime, .animeThread, .player:
            return nil
        }
    }


    var resetsTabStack: Bool {
        switch self {
        case .home, .search, .schedule, .w2g, .chat, .client, .settings, .profile:
            return true
        case .anime, .animeThread, .player:
            return false
        }
    }

    init?(tabIndex: Int) {
        switch tabIndex {
        case 0:
            self = .home
        case 1:
            self = .search(nil)
        case 2:
            self = .schedule
        case 3:
            self = .w2g(id: nil)
        case 4:
            self = .chat
        case 5:
            self = .client(.root)
        case 6:
            self = .settings(.root)
        default:
            return nil
        }
    }

    init?(path rawPath: String) {
        var path = rawPath
        if path.hasPrefix("/#") { path.removeFirst(2) }
        if path.hasPrefix("#") { path.removeFirst() }
        if !path.hasPrefix("/") { path = "/" + path }

        let parts = path.split(separator: "/").map(String.init)
        guard parts.first == "app", parts.count >= 2 else { return nil }

        switch parts[1] {
        case "home":
            self = .home
        case "search":
            self = .search(nil)
        case "schedule":
            self = .schedule
        case "w2g":
            self = .w2g(id: parts.count > 2 ? parts[2] : nil)
        case "chat":
            self = .chat
        case "client":
            let route = parts.count > 2 ? ClientRoute(rawValue: parts[2]) : .root
            self = .client(route ?? .root)
        case "settings":
            let route = parts.count > 2 ? SettingsRoute(rawValue: parts[2]) : .root
            self = .settings(route ?? .root)
        case "profile":
            self = .settings(.accounts)  // +page.ts redirects 307 to /app/settings/accounts
        case "anime":
            guard parts.count > 2, let animeID = Int(parts[2]) else { return nil }
            if parts.count > 4, parts[3] == "thread", let threadID = Int(parts[4]) {
                self = .animeThread(animeID: animeID, threadID: threadID)
            } else {
                self = .anime(id: animeID)
            }
        case "player":
            self = .player
        default:
            return nil
        }
    }
}
