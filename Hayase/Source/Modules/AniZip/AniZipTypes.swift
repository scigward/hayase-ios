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


// MARK: - TMDB Images

struct AniZipBackdrop: Codable {
    let filePath: String
    let width: Int?
    let height: Int?
    let aspectRatio: Double
    let iso6391: String?
    let voteAverage: Double
    let voteCount: Int?

    enum CodingKeys: String, CodingKey {
        case filePath = "file_path"
        case width
        case height
        case aspectRatio = "aspect_ratio"
        case iso6391 = "iso_639_1"
        case voteAverage = "vote_average"
        case voteCount = "vote_count"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        filePath = (try? c.decode(String.self, forKey: .filePath)) ?? ""
        width = Self.decodeInt(from: c, forKey: .width)
        height = Self.decodeInt(from: c, forKey: .height)
        aspectRatio = Self.decodeDouble(from: c, forKey: .aspectRatio) ?? 0
        iso6391 = try? c.decodeIfPresent(String.self, forKey: .iso6391)
        voteAverage = Self.decodeDouble(from: c, forKey: .voteAverage) ?? 0
        voteCount = Self.decodeInt(from: c, forKey: .voteCount)
    }

    private static func decodeInt<Key: CodingKey>(from c: KeyedDecodingContainer<Key>, forKey key: Key) -> Int? {
        if let n = try? c.decodeIfPresent(Int.self, forKey: key) { return n }
        if let d = try? c.decodeIfPresent(Double.self, forKey: key) { return Int(d) }
        if let s = try? c.decodeIfPresent(String.self, forKey: key) { return Int(s) ?? Int(Double(s) ?? 0) }
        return nil
    }

    private static func decodeDouble<Key: CodingKey>(from c: KeyedDecodingContainer<Key>, forKey key: Key) -> Double? {
        if let d = try? c.decodeIfPresent(Double.self, forKey: key) { return d }
        if let n = try? c.decodeIfPresent(Int.self, forKey: key) { return Double(n) }
        if let s = try? c.decodeIfPresent(String.self, forKey: key) { return Double(s) }
        return nil
    }
}

struct AniZipImagesResponse: Codable {
    let backdrops: [AniZipBackdrop]?
    let id: Int?
    let logos: [AniZipBackdrop]?
    let posters: [AniZipBackdrop]?
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

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        animeplanet_id = Self.decodeString(from: c, forKey: .animeplanet_id)
        kitsu_id       = Self.decodeInt(from: c, forKey: .kitsu_id)
        mal_id         = Self.decodeInt(from: c, forKey: .mal_id)
        type           = Self.decodeString(from: c, forKey: .type)
        anilist_id     = Self.decodeInt(from: c, forKey: .anilist_id)
        anisearch_id   = Self.decodeInt(from: c, forKey: .anisearch_id)
        anidb_id       = Self.decodeInt(from: c, forKey: .anidb_id)
        notifymoe_id   = Self.decodeString(from: c, forKey: .notifymoe_id)
        livechart_id   = Self.decodeInt(from: c, forKey: .livechart_id)
        thetvdb_id     = Self.decodeInt(from: c, forKey: .thetvdb_id)
        imdb_id        = Self.decodeString(from: c, forKey: .imdb_id)
        themoviedb_id  = Self.decodeString(from: c, forKey: .themoviedb_id)
    }

    private static func decodeInt<Key: CodingKey>(from c: KeyedDecodingContainer<Key>, forKey key: Key) -> Int? {
        if let n = try? c.decodeIfPresent(Int.self, forKey: key) { return n }
        if let d = try? c.decodeIfPresent(Double.self, forKey: key) { return Int(d) }
        if let s = try? c.decodeIfPresent(String.self, forKey: key) { return Int(s) ?? Int(Double(s) ?? 0) }
        return nil
    }

    private static func decodeString<Key: CodingKey>(from c: KeyedDecodingContainer<Key>, forKey key: Key) -> String? {
        if let s = try? c.decodeIfPresent(String.self, forKey: key), !s.isEmpty { return s }
        if let n = try? c.decodeIfPresent(Int.self, forKey: key) { return String(n) }
        if let d = try? c.decodeIfPresent(Double.self, forKey: key) { return String(d) }
        return nil
    }
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
        tvdbShowId            = Self.decodeInt(from: c, forKey: .tvdbShowId)
        tvdbId                = Self.decodeInt(from: c, forKey: .tvdbId)
        seasonNumber          = Self.decodeInt(from: c, forKey: .seasonNumber)
        episodeNumber         = Self.decodeInt(from: c, forKey: .episodeNumber)
        absoluteEpisodeNumber = Self.decodeInt(from: c, forKey: .absoluteEpisodeNumber)
        title                 = Self.decodeStringMap(from: c, forKey: .title)
        airDate               = try c.decodeIfPresent(String.self,         forKey: .airDate)
        airDateUtc            = try c.decodeIfPresent(String.self,         forKey: .airDateUtc)
        overview              = try c.decodeIfPresent(String.self,         forKey: .overview)
        image                 = try c.decodeIfPresent(String.self,         forKey: .image)
        anidbEid              = Self.decodeInt(from: c, forKey: .anidbEid)
        airdate               = try c.decodeIfPresent(String.self,         forKey: .airdate)
        summary               = try c.decodeIfPresent(String.self,         forKey: .summary)
        finaleType            = try c.decodeIfPresent(String.self,         forKey: .finaleType)

        // `runtime` and `length`: spec says number, but the API can return float/string values.
        runtime = Self.decodeInt(from: c, forKey: .runtime)
        length  = Self.decodeInt(from: c, forKey: .length)

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

    private static func decodeInt<Key: CodingKey>(from c: KeyedDecodingContainer<Key>, forKey key: Key) -> Int? {
        if let n = try? c.decodeIfPresent(Int.self, forKey: key) { return n }
        if let d = try? c.decodeIfPresent(Double.self, forKey: key) { return Int(d) }
        if let s = try? c.decodeIfPresent(String.self, forKey: key) { return Int(s) ?? Int(Double(s) ?? 0) }
        return nil
    }

    private static func decodeStringMap<Key: CodingKey>(from c: KeyedDecodingContainer<Key>, forKey key: Key) -> [String: String]? {
        guard let nested = try? c.nestedContainer(keyedBy: AniZipDynamicKey.self, forKey: key) else { return nil }
        var result: [String: String] = [:]
        for nestedKey in nested.allKeys {
            if let value = try? nested.decodeIfPresent(String.self, forKey: nestedKey) {
                result[nestedKey.stringValue] = value
            } else if let value = try? nested.decodeIfPresent(Int.self, forKey: nestedKey) {
                result[nestedKey.stringValue] = String(value)
            } else if let value = try? nested.decodeIfPresent(Double.self, forKey: nestedKey) {
                result[nestedKey.stringValue] = String(value)
            }
        }
        return result.isEmpty ? nil : result
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

    /// Memberwise initializer — needed because the custom Codable init(from:) suppresses
    /// Swift's auto-synthesized memberwise initializer.
    init(titles: [String: String]?, episodes: [String: AniZipEpisodeEntry]?,
         episodeCount: Int?, specialCount: Int?,
         images: [AniZipImage]?, mappings: AniZipMappings?) {
        self.titles       = titles
        self.episodes     = episodes
        self.episodeCount = episodeCount
        self.specialCount = specialCount
        self.images       = images
        self.mappings     = mappings
    }

    // Custom decoder: decodes episodes entry-by-entry, silently skipping any
    // entry that fails to decode (e.g. unexpected field types), so one malformed
    // episode never wipes out the entire episodes dict.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        titles       = Self.decodeStringMap(from: c, forKey: .titles)
        episodeCount = Self.decodeInt(from: c, forKey: .episodeCount)
        specialCount = Self.decodeInt(from: c, forKey: .specialCount)
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

    private static func decodeInt<Key: CodingKey>(from c: KeyedDecodingContainer<Key>, forKey key: Key) -> Int? {
        if let n = try? c.decodeIfPresent(Int.self, forKey: key) { return n }
        if let d = try? c.decodeIfPresent(Double.self, forKey: key) { return Int(d) }
        if let s = try? c.decodeIfPresent(String.self, forKey: key) { return Int(s) ?? Int(Double(s) ?? 0) }
        return nil
    }

    private static func decodeStringMap<Key: CodingKey>(from c: KeyedDecodingContainer<Key>, forKey key: Key) -> [String: String]? {
        guard let nested = try? c.nestedContainer(keyedBy: AniZipDynamicKey.self, forKey: key) else { return nil }
        var result: [String: String] = [:]
        for nestedKey in nested.allKeys {
            if let value = try? nested.decodeIfPresent(String.self, forKey: nestedKey) {
                result[nestedKey.stringValue] = value
            } else if let value = try? nested.decodeIfPresent(Int.self, forKey: nestedKey) {
                result[nestedKey.stringValue] = String(value)
            } else if let value = try? nested.decodeIfPresent(Double.self, forKey: nestedKey) {
                result[nestedKey.stringValue] = String(value)
            }
        }
        return result.isEmpty ? nil : result
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
