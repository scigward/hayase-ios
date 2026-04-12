//
//  Types.swift
//  Hayase
//
//  AniZip type definitions.
//  Mirrors: src/lib/modules/anizip/types.d.ts
//

import Foundation

// MARK: - Image

struct AniZipImage: Codable {
    let coverType: String?
    let url: String?
}

// MARK: - Mappings

struct AniZipMappings: Codable {
    let animeplanet_id: String?
    let kitsu_id: Int?
    let mal_id: Int?
    let type: String?
    let anilist_id: Int?
    let anisearch_id: Int?
    let anidb_id: Int?
    let notifymoe_id: String?
    let livechart_id: Int?
    let thetvdb_id: Int?
    let imdb_id: String?
    let themoviedb_id: String?
}

// MARK: - Episode

struct AniZipEpisodeEntry: Codable {
    let tvdbShowId: Int?
    let tvdbId: Int?
    let seasonNumber: Int?
    let episodeNumber: Int?
    let absoluteEpisodeNumber: Int?
    let title: [String: String]?
    let airDate: String?
    let airDateUtc: String?
    let runtime: Int?
    let overview: String?
    let image: String?
    let episode: String
    let anidbEid: Int?
    let length: Int?
    let airdate: String?
    let rating: String?
    let summary: String?
    let finaleType: String?
}

// MARK: - Episodes Response

struct AniZipEpisodesResponse: Codable {
    let titles: [String: String]?
    let episodes: [String: AniZipEpisodeEntry]?
    let episodeCount: Int?
    let specialCount: Int?
    let images: [AniZipImage]?
    let mappings: AniZipMappings?
}

// MARK: - Mappings Response

typealias AniZipMappingsResponse = AniZipMappings
