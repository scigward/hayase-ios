//
//  Types.swift
//  Hayase
//
//  AnimeThemes type definitions.
//  Mirrors: src/lib/modules/animethemes/types.d.ts
//

import Foundation

// MARK: - Response

struct AnimeThemesResponse: Codable {
    let anime: [AnimeThemesAnime]?
    let links: AnimeThemesLinks?
    let meta: AnimeThemesMeta?
}

struct AnimeThemesAnime: Codable {
    let id: Int?
    let name: String?
    let media_format: String?
    let season: String?
    let slug: String?
    let synopsis: String?
    let year: Int?
    let animethemes: [AnimeThemesTheme]?
}

struct AnimeThemesTheme: Codable {
    let id: Int?
    let sequence: Int?
    let slug: String?
    let type: String?
    let song: AnimeThemesSong?
    let animethemeentries: [AnimeThemesEntry]?
}

struct AnimeThemesEntry: Codable {
    let id: Int?
    let episodes: String?
    let notes: String?
    let nsfw: Bool?
    let spoiler: Bool?
    let version: Int?
    let videos: [AnimeThemesVideo]?
}

struct AnimeThemesVideo: Codable {
    let id: Int?
    let basename: String?
    let tags: String?
    let link: String?
    let audio: AnimeThemesAudio?
}

struct AnimeThemesAudio: Codable {
    let id: Int?
    let basename: String?
    let size: Int?
    let link: String?
}

struct AnimeThemesSong: Codable {
    let id: Int?
    let title: String?
    let artists: [AnimeThemesArtist]?
}

struct AnimeThemesArtist: Codable {
    let id: Int?
    let name: String?
    let slug: String?
}

struct AnimeThemesLinks: Codable {
    let first: String?
    let last: String?
    let prev: String?
    let next: String?
}

struct AnimeThemesMeta: Codable {
    let current_page: Int?
    let from: Int?
    let path: String?
    let per_page: Int?
    let to: Int?
}
