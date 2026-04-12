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
    /// AniDB episode identifier — may be returned as a string or a number by the API.
    let episode: String
    let anidbEid: Int?
    let length: Int?
    let airdate: String?
    /// Returned as a string by the API, but some entries send a number (e.g. 7.83).
    /// The original raw-JSON code handled both via `(NSNumber)?.doubleValue ?? String → Double`.
    let rating: String?
    let summary: String?
    let finaleType: String?

    // Custom decoder: handles `episode` and `rating` as either String or number,
    // matching the original [String:Any] raw-JSON parsing that accepted both types.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tvdbShowId            = try c.decodeIfPresent(Int.self,            forKey: .tvdbShowId)
        tvdbId                = try c.decodeIfPresent(Int.self,            forKey: .tvdbId)
        seasonNumber          = try c.decodeIfPresent(Int.self,            forKey: .seasonNumber)
        episodeNumber         = try c.decodeIfPresent(Int.self,            forKey: .episodeNumber)
        absoluteEpisodeNumber = try c.decodeIfPresent(Int.self,            forKey: .absoluteEpisodeNumber)
        title                 = try c.decodeIfPresent([String: String].self, forKey: .title)
        airDate               = try c.decodeIfPresent(String.self,         forKey: .airDate)
        airDateUtc            = try c.decodeIfPresent(String.self,         forKey: .airDateUtc)
        overview              = try c.decodeIfPresent(String.self,         forKey: .overview)
        image                 = try c.decodeIfPresent(String.self,         forKey: .image)
        anidbEid              = try c.decodeIfPresent(Int.self,            forKey: .anidbEid)
        airdate               = try c.decodeIfPresent(String.self,         forKey: .airdate)
        summary               = try c.decodeIfPresent(String.self,         forKey: .summary)
        finaleType            = try c.decodeIfPresent(String.self,         forKey: .finaleType)

        // `runtime` and `length`: spec says number but may come as float (e.g. 23.5).
        // Mirrors original `(info["runtime"] as? NSNumber)?.intValue` which handles both.
        if let n = try? c.decodeIfPresent(Int.self, forKey: .runtime) {
            runtime = n
        } else if let d = try? c.decodeIfPresent(Double.self, forKey: .runtime) {
            runtime = Int(d)
        } else {
            runtime = nil
        }
        if let n = try? c.decodeIfPresent(Int.self, forKey: .length) {
            length = n
        } else if let d = try? c.decodeIfPresent(Double.self, forKey: .length) {
            length = Int(d)
        } else {
            length = nil
        }

        // `episode` field: string in the spec but sometimes returned as a number.
        if let s = try? c.decodeIfPresent(String.self, forKey: .episode) {
            episode = s ?? ""
        } else if let n = try? c.decodeIfPresent(Int.self, forKey: .episode) {
            episode = "\(n)"
        } else if let n = try? c.decodeIfPresent(Double.self, forKey: .episode) {
            episode = "\(Int(n))"
        } else {
            episode = ""
        }

        // `rating` field: string in the spec but sometimes returned as a number (e.g. 7.83).
        if let s = try? c.decodeIfPresent(String.self, forKey: .rating) {
            rating = s
        } else if let n = try? c.decodeIfPresent(Double.self, forKey: .rating) {
            rating = String(n)
        } else if let n = try? c.decodeIfPresent(Int.self, forKey: .rating) {
            rating = String(n)
        } else {
            rating = nil
        }
    }
}

// MARK: - Episodes Response

struct AniZipEpisodesResponse: Codable {
    let titles: [String: String]?
    let episodes: [String: AniZipEpisodeEntry]?
    let episodeCount: Int?
    let specialCount: Int?
    let images: [AniZipImage]?
    let mappings: AniZipMappings?

    // Custom decoder: decodes episodes entry-by-entry, silently skipping any
    // entry that fails to decode (e.g. unexpected field types), so one malformed
    // episode never wipes out the entire episodes dict.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        titles       = try c.decodeIfPresent([String: String].self, forKey: .titles)
        episodeCount = try c.decodeIfPresent(Int.self,              forKey: .episodeCount)
        specialCount = try c.decodeIfPresent(Int.self,              forKey: .specialCount)
        images       = try c.decodeIfPresent([AniZipImage].self,    forKey: .images)
        mappings     = try c.decodeIfPresent(AniZipMappings.self,   forKey: .mappings)

        // Decode episodes entry-by-entry so a single bad entry doesn't nuke the whole dict.
        if c.contains(.episodes) {
            var parsed: [String: AniZipEpisodeEntry] = [:]
            if let epsContainer = try? c.nestedContainer(keyedBy: AniZipDynamicKey.self, forKey: .episodes) {
                for key in epsContainer.allKeys {
                    if let entry = try? epsContainer.decode(AniZipEpisodeEntry.self, forKey: key) {
                        parsed[key.stringValue] = entry
                    }
                }
            }
            episodes = parsed.isEmpty ? nil : parsed
        } else {
            episodes = nil
        }
    }
}

// MARK: - Mappings Response

typealias AniZipMappingsResponse = AniZipMappings

// MARK: - Dynamic coding key for episodes dict

private struct AniZipDynamicKey: CodingKey {
    var stringValue: String
    var intValue: Int?
    init(stringValue: String) { self.stringValue = stringValue; self.intValue = nil }
    init?(intValue: Int) { self.intValue = intValue; self.stringValue = "\(intValue)" }
}
