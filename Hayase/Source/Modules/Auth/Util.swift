//
//  Util.swift
//  Hayase
//
//  Auth utility types and helpers.
//  Mirrors: src/lib/modules/auth/util.ts
//

import Foundation

// MARK: - TrackerViewer

struct TrackerViewer: Codable {
    let id: String
    let name: String
    let avatarURL: String?
}

// MARK: - TrackerKind

enum TrackerKind: String, CaseIterable {
    case anilist = "anilist"
    case kitsu   = "kitsu"
    case mal     = "mal"
    case local   = "local"

    var displayName: String {
        switch self {
        case .anilist: return "AniList"
        case .kitsu:   return "Kitsu"
        case .mal:     return "MyAnimeList"
        case .local:   return "Local"
        }
    }

    var syncKey: String { "tracker_sync_\(rawValue)" }

    var viewerKey: String { "tracker_viewer_\(rawValue)" }

    var tokenKey: String { "tracker_token_\(rawValue)" }
}
