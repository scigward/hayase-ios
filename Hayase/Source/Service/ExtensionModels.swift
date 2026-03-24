// ExtensionModels.swift
// Ports types.d.ts from scigward/interface — used by ExtensionService and ExtensionWorker.

import Foundation

// MARK: - Core types (mirror types.d.ts)

/// Mirrors types.d.ts SearchOptions value entry
struct ExtensionOptionDef: Codable, Equatable {
    var type: String          // "string" | "number" | "boolean" | "select"
    var description: String
    var values: [String]?
    var `default`: AnyCodableValue
}

/// Minimal Codable Any for extension option values and defaults
enum AnyCodableValue: Codable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let b = try? c.decode(Bool.self)   { self = .bool(b); return }
        if let n = try? c.decode(Double.self) { self = .number(n); return }
        if let s = try? c.decode(String.self) { self = .string(s); return }
        self = .null
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let s): try c.encode(s)
        case .number(let n): try c.encode(n)
        case .bool(let b):   try c.encode(b)
        case .null:          try c.encodeNil()
        }
    }

    var stringValue: String {
        switch self {
        case .string(let s): return s
        case .number(let n): return n.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(n)) : String(n)
        case .bool(let b):   return b ? "true" : "false"
        case .null:          return ""
        }
    }

    var jsonCompatible: Any {
        switch self {
        case .string(let s): return s
        case .number(let n): return n
        case .bool(let b):   return b
        case .null:          return NSNull()
        }
    }
}

/// Mirrors types.d.ts ExtensionConfig
struct ExtensionConfig: Codable, Equatable {
    var name: String
    var version: String
    var description: String?
    var id: String
    /// "torrent" | "nzb" | "url"
    var type: String
    /// "high" | "medium" | "low"
    var accuracy: String
    var ratio: AnyCodableValue?
    /// URL to the icon image
    var icon: String
    /// "sub" | "dub" | "both"
    var media: String
    /// Base64-encoded origin URL for CORS enablement (mirrors ExtensionConfig.url)
    var url: String?
    var languages: [String]?         // optional — not all real manifests include this
    /// URL to the config JSON (may use gh: or npm: prefix)
    var update: String?
    /// URL to the extension JS code (may use gh: or npm: or file: prefix)
    var code: String
    var options: [String: ExtensionOptionDef]?
}

/// Per-extension user options and enabled state — mirrors ExtensionsOptions in storage.ts
struct ExtensionOptions: Codable {
    var options: [String: AnyCodableValue]
    var enabled: Bool
}

/// Mirrors TorrentResult in types.d.ts
struct TorrentResult {
    var title: String
    var link: String
    var hash: String
    var id: Int? = nil
    var seeders: Int = 0
    var leechers: Int = 0
    var downloads: Int = 0
    /// "high" | "medium" | "low"
    var accuracy: String = "low"
    /// size in bytes
    var size: Int64 = 0
    var date: Date? = nil
    /// "batch" | "best" | "alt"
    var type: String? = nil
    /// Which extension(s) returned this result
    var extensionIds: Set<String> = []
    // Swift synthesises a memberwise init since no init is declared in the body.
    // Required fields: title, link, hash. All others have defaults.
}

extension TorrentResult {
    /// Decode a result dictionary returned by an extension's single/batch/movie call.
    init?(from dict: [String: Any]) {
        guard let title = dict["title"] as? String else { return nil }
        let rawLink = (dict["link"] as? String) ?? ""

        // 'hash' is required for deduplication.
        // If the extension omits it or returns nil, try to extract the InfoHash
        // from a magnet URI (xt=urn:btih:HASH) in the link field.
        let rawHash: String
        if let h = dict["hash"] as? String, !h.isEmpty {
            rawHash = h.lowercased()
        } else {
            let lower = rawLink.lowercased()
            if let xtRange = lower.range(of: "xt=urn:btih:") {
                let afterXt = String(lower[xtRange.upperBound...])
                let hash = afterXt.components(separatedBy: CharacterSet(charactersIn: "&\n\r\t ")).first ?? ""
                guard !hash.isEmpty else { return nil }
                rawHash = hash
            } else {
                return nil
            }
        }

        self.title     = title
        self.link      = rawLink
        self.hash      = rawHash
        self.id        = dict["id"] as? Int
        self.seeders   = (dict["seeders"]   as? NSNumber)?.intValue ?? 0
        self.leechers  = (dict["leechers"]  as? NSNumber)?.intValue ?? 0
        self.downloads = (dict["downloads"] as? NSNumber)?.intValue ?? 0
        self.accuracy  = (dict["accuracy"]  as? String) ?? "low"
        self.size      = Int64((dict["size"] as? NSNumber)?.doubleValue ?? 0)
        self.type      = dict["type"] as? String
        if let dateStr = dict["date"] as? String {
            self.date = ISO8601DateFormatter().date(from: dateStr)
        }
    }
}

/// Mirrors TorrentQuery in types.d.ts
struct TorrentQuery {
    var mediaJSON: [String: Any]
    var anilistId: Int
    var titles: [String]
    var episode: Int
    var episodeCount: Int?
    var absoluteEpisodeNumber: Int?
    /// AniDB anime ID — fetched from api.ani.zip, required by animetosho and others
    var anidbAid: Int?
    /// AniDB episode ID — fetched from api.ani.zip, required by animetosho and others
    var anidbEid: Int?
    /// MyAnimeList ID — from api.ani.zip mappings
    var malId: Int?
    /// TheTVDB series ID — from api.ani.zip mappings
    var tvdbId: Int?
    /// TheTVDB episode ID — from api.ani.zip episode entry
    var tvdbEId: Int?
    /// TheMovieDB ID — from api.ani.zip mappings
    var tmdbId: Int?
    /// Kitsu ID — from api.ani.zip mappings
    var kitsuId: Int?
    /// IMDB ID — from api.ani.zip mappings
    var imdbId: String?
    /// "2160" | "1080" | "720" | "540" | "480" | ""
    var resolution: String
    var exclusions: [String]
    /// "sub" | "dub" — nil means no preference
    var subDub: String?

    /// Build from an AnimeItem + episode context (mirrors Extensions.createTitles)
    static func make(from item: AnimeItem, episode: Int, resolution: String) -> TorrentQuery {
        var titleDict: [String: Any] = [:]
        if let eng = item.titleEnglish { titleDict["english"] = eng }
        if let rom = item.titleRomaji  { titleDict["romaji"]  = rom }
        titleDict["userPreferred"] = item.titleEnglish ?? item.titleRomaji ?? ""

        var mediaJSON: [String: Any] = [
            "id":       item.id,
            "title":    titleDict,
            "synonyms": item.synonyms,
            "format":   item.format ?? "TV",
            "status":   item.status ?? "RELEASING"
        ]
        if let ep = item.episodes { mediaJSON["episodes"] = ep }

        // Build titles list — mirrors Extensions.createTitles exactly:
        //   const grouped = [...new Set(
        //     Object.values(media.title ?? {}).concat(media.synonyms)
        //       .filter(name => name != null && name.length > 3)
        //   )]
        let candidates = ([item.titleEnglish, item.titleRomaji].compactMap { $0 } + item.synonyms)
            .filter { $0.count > 3 }
        var seen = Set<String>()
        var titles: [String] = []

        // Extract just the digit from e.g. "Season 2" or "2nd Season" using NSRegularExpression
        func extractSeasonNum(_ t: String) -> (range: Range<String.Index>, num: String)? {
            let patterns = [
                (#"Season (\d+)"#, false),   // "Season 2" → "S2"
                (#"(\d+)(?:nd|rd|th|st) Season"#, true), // "2nd Season" → "S2"
            ]
            for (pattern, numFirst) in patterns {
                guard let re = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
                      let m = re.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)),
                      m.numberOfRanges > 1,
                      let fullRange = Range(m.range, in: t),
                      let numRange = Range(m.range(at: 1), in: t) else { continue }
                _ = numFirst // both patterns capture the digit in group 1
                return (fullRange, String(t[numRange]))
            }
            return nil
        }

        func appendTitle(_ t: String) {
            guard seen.insert(t).inserted else { return }
            titles.append(t)
            if let (range, num) = extractSeasonNum(t) {
                let alt = t.replacingCharacters(in: range, with: "S\(num)")
                if seen.insert(alt).inserted { titles.append(alt) }
            }
        }
        for t in candidates {
            appendTitle(t)
            if t.contains("-") { appendTitle(t.replacingOccurrences(of: "-", with: "")) }
        }

        return TorrentQuery(
            mediaJSON: mediaJSON,
            anilistId: item.id,
            titles: titles,
            episode: episode,
            episodeCount: item.episodes,
            absoluteEpisodeNumber: nil,
            anidbAid: nil,
            anidbEid: nil,
            malId: nil,
            tvdbId: nil,
            tvdbEId: nil,
            tmdbId: nil,
            kitsuId: nil,
            imdbId: nil,
            resolution: resolution,
            exclusions: [],
            subDub: nil
        )
    }

    /// Serialise for passing to the JS extension worker
    func toDict() -> [String: Any] {
        var d: [String: Any] = [
            "media":      mediaJSON,
            "anilistId":  anilistId,
            "titles":     titles,
            "episode":    episode,
            "resolution": resolution,
            "exclusions": exclusions
        ]
        if let c = episodeCount          { d["episodeCount"] = c }
        if let a = absoluteEpisodeNumber { d["absoluteEpisodeNumber"] = a }
        if let aid = anidbAid            { d["anidbAid"] = aid }
        if let eid = anidbEid            { d["anidbEid"] = eid }
        if let v = malId                 { d["malId"] = v }
        if let v = tvdbId                { d["tvdbId"] = v }
        if let v = tvdbEId               { d["tvdbEId"] = v }
        if let v = tmdbId                { d["tmdbId"] = v }
        if let v = kitsuId               { d["kitsuId"] = v }
        if let v = imdbId                { d["imdbId"] = v }
        if let t = subDub                { d["type"] = t }
        return d
    }
}
