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
    let bannerURL: String?
    let titleLanguage: String?
    let displayAdultContent: Bool?
    let customLists: [String]

    init(id: String,
         name: String,
         avatarURL: String?,
         bannerURL: String? = nil,
         titleLanguage: String? = nil,
         displayAdultContent: Bool? = nil,
         customLists: [String] = []) {
        self.id = id
        self.name = name
        self.avatarURL = avatarURL
        self.bannerURL = bannerURL
        self.titleLanguage = titleLanguage
        self.displayAdultContent = displayAdultContent
        self.customLists = customLists
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case avatarURL
        case bannerURL
        case titleLanguage
        case displayAdultContent
        case customLists
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        avatarURL = try container.decodeIfPresent(String.self, forKey: .avatarURL)
        bannerURL = try container.decodeIfPresent(String.self, forKey: .bannerURL)
        titleLanguage = try container.decodeIfPresent(String.self, forKey: .titleLanguage)
        displayAdultContent = try container.decodeIfPresent(Bool.self, forKey: .displayAdultContent)
        customLists = try container.decodeIfPresent([String].self, forKey: .customLists) ?? []
    }
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
