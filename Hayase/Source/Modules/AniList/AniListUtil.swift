//
//  Util.swift
//  Hayase
//
//  AniList utility functions.
//  Mirrors: src/lib/modules/anilist/util.ts
//

import Foundation

// MARK: - Season / Year helpers (matches util.ts: currentSeason, currentYear)

enum AniListUtil {

    /// Returns the current AniList season string.
    /// WINTER = Jan–Mar, SPRING = Apr–Jun, SUMMER = Jul–Sep, FALL = Oct–Dec.
    static func currentSeason() -> String {
        let month = Calendar.current.component(.month, from: Date())
        switch month {
        case 1, 2, 3:   return "WINTER"
        case 4, 5, 6:   return "SPRING"
        case 7, 8, 9:   return "SUMMER"
        default:         return "FALL"
        }
    }

    static func currentYear() -> Int {
        Calendar.current.component(.year, from: Date())
    }

    /// Strip HTML tags and decode common HTML entities from AniList description text.
    /// Matches web interface's desc() + notes() pipeline.
    static func stripHTML(_ html: String) -> String {
        var s = html
        s = s.replacingOccurrences(of: #"<br\s*/?>"#, with: "\n", options: .regularExpression)
        s = s.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: "&amp;", with: "&")
        s = s.replacingOccurrences(of: "&lt;", with: "<")
        s = s.replacingOccurrences(of: "&gt;", with: ">")
        s = s.replacingOccurrences(of: "&#039;", with: "'")
        s = s.replacingOccurrences(of: "&apos;", with: "'")
        s = s.replacingOccurrences(of: "&quot;", with: "\"")
        s = s.replacingOccurrences(of: "&nbsp;", with: " ")
        s = s.replacingOccurrences(of: #"\n+"#, with: "\n", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\n?\(?Source: [^)]+\)?\n?"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\n?Notes?:[ |\n][^\n]+\n?"#, with: "", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    enum TitlePreference: String {
        case anilist = "ANILIST"
        case english = "ENGLISH"
        case native = "NATIVE"
        case romaji = "ROMAJI"
    }

    static var titlePreference: TitlePreference {
        let raw = Settings.titleType
        return TitlePreference(rawValue: raw) ?? .anilist
    }

    private static func cleanTitle(_ value: String?) -> String? {
        guard let title = value?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else {
            return nil
        }
        return title
    }

    /// Matches interface `title(media)`: AniList/default uses `userPreferred` only.
    static func title(for item: AnimeItem) -> String {
        let defaultTitle = cleanTitle(item.titleUserPreferred) ?? "TBA"
        switch titlePreference {
        case .anilist:
            return defaultTitle
        case .english:
            return cleanTitle(item.titleEnglish) ?? defaultTitle
        case .native:
            return cleanTitle(item.titleNative) ?? defaultTitle
        case .romaji:
            return cleanTitle(item.titleRomaji) ?? defaultTitle
        }
    }

    /// Matches anime/[id]/+layout.svelte's muted alternate title line.
    static func alternateTitle(for item: AnimeItem) -> String? {
        let primary = title(for: item).lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let romaji = cleanTitle(item.titleRomaji)
        let native = cleanTitle(item.titleNative)
        let alternate = romaji?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) == primary
            ? (native ?? romaji)
            : (romaji ?? native)
        guard let alternate = alternate, !alternate.isEmpty else { return nil }
        return alternate
    }


    static func animeItem(from anime: Animes) -> AnimeItem {
        let english = cleanTitle(anime.animeTitleEnglish)
        let romaji = cleanTitle(anime.animeTitleJapanese)
        return AnimeItem(
            id: anime.animeAnilistId?.intValue ?? 0,
            titleEnglish: english,
            titleRomaji: romaji,
            titleUserPreferred: english ?? romaji,
            coverURL: anime.animeImgL ?? anime.animeImgM ?? anime.animeImgS,
            score: anime.animeScore?.floatValue,
            status: anime.animeStatus,
            episodes: anime.animeTotalEps?.intValue,
            bannerURL: anime.animeImgS ?? anime.animeImgL ?? anime.animeImgM,
            genres: [],
            description: anime.animeDescription)
    }

    static func title(for anime: Animes) -> String {
        title(for: animeItem(from: anime))
    }

    static func alternateTitle(for anime: Animes) -> String? {
        alternateTitle(for: animeItem(from: anime))
    }

    /// Mirrors utils.ts `since(...)` instead of Apple's rounded formatter.
    static func since(_ date: Date, relativeTo now: Date = Date()) -> String {
        let secondsElapsed = date.timeIntervalSince(now)
        let ranges: [(unit: String, seconds: TimeInterval)] = [
            ("year", 3600 * 24 * 365),
            ("month", 3600 * 24 * 30),
            ("week", 3600 * 24 * 7),
            ("day", 3600 * 24),
            ("hour", 3600),
            ("minute", 60),
            ("second", 1),
        ]

        for range in ranges where range.seconds < abs(secondsElapsed) {
            let value = Int((secondsElapsed / range.seconds).rounded())
            return relativeTime(value: value, unit: range.unit)
        }
        return "now"
    }

    private static func relativeTime(value: Int, unit: String) -> String {
        let absValue = abs(value)
        let label = absValue == 1 ? unit : "\(unit)s"
        if value > 0 { return "in \(absValue) \(label)" }
        if value < 0 { return "\(absValue) \(label) ago" }
        return "now"
    }

    static func tags(from mediaTags: [AniListMedia.MediaTag]?) -> [AnimeTag] {
        (mediaTags ?? []).compactMap { tag in
            guard let id = tag.id, let name = tag.name, !name.isEmpty else { return nil }
            return AnimeTag(
                id: id,
                name: name,
                isMediaSpoiler: tag.isMediaSpoiler ?? false,
                isGeneralSpoiler: tag.isGeneralSpoiler ?? false,
                rank: tag.rank ?? 0,
                isAdult: tag.isAdult ?? false)
        }
    }

    /// NSFW genre filter — returns `["Hentai"]` when user hasn't enabled "Show Hentai".
    /// Matches settings.ts: `nsfw = showHentai ? null : ['Hentai']`.
    static var nsfwGenreFilter: [String]? {
        let show = Settings.showHentai
        return show ? nil : ["Hentai"]
    }

    static func mediaListCustomLists(from rawLists: [AniListMedia.MediaListEntry.CustomList]?) -> [String] {
        (rawLists ?? []).compactMap { customList in
            customList.enabled == true ? customList.name : nil
        }
    }

    private static func jsonValue(_ value: Any?) -> Any {
        value ?? NSNull()
    }

    /// Exact media object shape used by the interface extension pipeline.
    /// Mirrors the FullMedia fragment in interface/src/lib/modules/anilist/queries.ts.
    static func extensionMediaJSON(from media: AniListMedia) -> [String: Any] {
        [
            "id": jsonValue(media.id),
            "idMal": jsonValue(media.idMal),
            "title": titleJSON(media.title, includeAllFields: true),
            "description": jsonValue(media.description),
            "season": jsonValue(media.season),
            "seasonYear": jsonValue(media.seasonYear),
            "format": jsonValue(media.format),
            "status": jsonValue(media.status),
            "episodes": jsonValue(media.episodes),
            "duration": jsonValue(media.duration),
            "averageScore": jsonValue(media.averageScore.map { Int($0.rounded()) }),
            "genres": jsonValue(media.genres),
            "isFavourite": jsonValue(media.isFavourite),
            "coverImage": coverImageJSON(media.coverImage, fields: [.extraLarge, .medium, .color]),
            "source": jsonValue(media.source),
            "countryOfOrigin": jsonValue(media.countryOfOrigin),
            "isAdult": jsonValue(media.isAdult),
            "bannerImage": jsonValue(media.bannerImage),
            "synonyms": jsonValue(media.synonyms),
            "nextAiringEpisode": nextAiringEpisodeJSON(media.nextAiringEpisode),
            "startDate": fuzzyDateJSON(media.startDate),
            "trailer": trailerJSON(media.trailer),
            "mediaListEntry": mediaListEntryJSON(media.mediaListEntry),
            "studios": studiosJSON(media.studios),
            "notaired": airingConnectionJSON(media.notaired),
            "aired": airingConnectionJSON(media.aired),
            "relations": relationConnectionJSON(media.relations, includeNestedNodeDetails: true)
        ]
    }

    private enum CoverImageField {
        case extraLarge
        case medium
        case color
    }

    private static func titleJSON(_ title: AniListMedia.Title?, includeAllFields: Bool) -> Any {
        guard let title else { return NSNull() }
        if includeAllFields {
            return [
                "romaji": jsonValue(title.romaji),
                "english": jsonValue(title.english),
                "native": jsonValue(title.native),
                "userPreferred": jsonValue(title.userPreferred)
            ]
        }
        return ["userPreferred": jsonValue(title.userPreferred)]
    }

    private static func coverImageJSON(_ cover: AniListMedia.CoverImage?, fields: [CoverImageField]) -> Any {
        guard let cover else { return NSNull() }
        var result: [String: Any] = [:]
        for field in fields {
            switch field {
            case .extraLarge:
                result["extraLarge"] = jsonValue(cover.extraLarge)
            case .medium:
                result["medium"] = jsonValue(cover.medium)
            case .color:
                result["color"] = jsonValue(cover.color)
            }
        }
        return result
    }

    private static func fuzzyDateJSON(_ date: AniListMedia.StartDate?) -> Any {
        guard let date else { return NSNull() }
        return [
            "year": jsonValue(date.year),
            "month": jsonValue(date.month),
            "day": jsonValue(date.day)
        ]
    }

    private static func trailerJSON(_ trailer: AniListMedia.Trailer?) -> Any {
        guard let trailer else { return NSNull() }
        return [
            "id": jsonValue(trailer.id),
            "site": jsonValue(trailer.site)
        ]
    }

    private static func nextAiringEpisodeJSON(_ airing: AniListMedia.NextAiringEpisode?) -> Any {
        guard let airing else { return NSNull() }
        return [
            "id": jsonValue(airing.id),
            "timeUntilAiring": jsonValue(airing.timeUntilAiring),
            "episode": jsonValue(airing.episode)
        ]
    }

    private static func mediaListEntryJSON(_ entry: AniListMedia.MediaListEntry?) -> Any {
        guard let entry else { return NSNull() }
        return [
            "id": jsonValue(entry.id),
            "status": jsonValue(entry.status),
            "progress": jsonValue(entry.progress),
            "repeat": jsonValue(entry.repeatCount),
            "score": jsonValue(entry.score),
            "customLists": jsonValue(mediaListCustomLists(from: entry.customLists))
        ]
    }

    private static func studiosJSON(_ studios: AniListMedia.StudioConnection?) -> Any {
        guard let studios else { return NSNull() }
        return [
            "nodes": jsonValue(studios.nodes?.map { studio in
                [
                    "id": jsonValue(studio.id),
                    "name": jsonValue(studio.name)
                ]
            })
        ]
    }

    private static func airingConnectionJSON(_ connection: AniListMedia.AiringConnection?) -> Any {
        guard let connection else { return NSNull() }
        return [
            "n": jsonValue(connection.n?.map { node in
                [
                    "a": jsonValue(node.a),
                    "e": jsonValue(node.e)
                ]
            })
        ]
    }

    private static func relationConnectionJSON(_ connection: AniListMedia.RelationConnection?,
                                               includeNestedNodeDetails: Bool) -> Any {
        guard let connection else { return NSNull() }
        return [
            "edges": jsonValue(connection.edges?.map { edge in
                [
                    "relationType": jsonValue(edge.relationType),
                    "node": relationNodeJSON(edge.node, includeNestedRelations: includeNestedNodeDetails)
                ]
            })
        ]
    }

    private static func relationNodeJSON(_ node: AniListMedia.RelationNode?, includeNestedRelations: Bool) -> Any {
        guard let node else { return NSNull() }
        var result: [String: Any] = [
            "id": jsonValue(node.id),
            "status": jsonValue(node.status),
            "format": jsonValue(node.format),
            "episodes": jsonValue(node.episodes),
            "title": titleJSON(node.title, includeAllFields: false),
            "coverImage": coverImageJSON(node.coverImage, fields: [.extraLarge]),
            "type": jsonValue(node.type)
        ]

        if includeNestedRelations {
            result["synonyms"] = jsonValue(node.synonyms)
            result["season"] = jsonValue(node.season)
            result["seasonYear"] = jsonValue(node.seasonYear)
            result["relations"] = relationConnectionJSON(node.relations, includeNestedNodeDetails: false)
            result["startDate"] = fuzzyDateJSON(node.startDate)
            result["endDate"] = fuzzyDateJSON(node.endDate)
        }

        return result
    }

    /// Convert an AniListMedia Codable object to an AnimeItem value type.
    static func animeItem(from media: AniListMedia) -> AnimeItem? {
        guard let id = media.id else { return nil }
        let desc = media.description.map { stripHTML($0) }
        let trailerID = (media.trailer?.site?.lowercased() == "youtube") ? media.trailer?.id : nil
        var item = AnimeItem(
            id: id,
            titleEnglish: media.title?.english,
            titleRomaji: media.title?.romaji,
            titleNative: media.title?.native,
            titleUserPreferred: media.title?.userPreferred,
            coverURL: media.coverImage?.extraLarge ?? media.coverImage?.large ?? media.coverImage?.medium,
            score: media.averageScore,
            status: media.status,
            episodes: media.episodes,
            bannerURL: media.bannerImage,
            genres: media.genres ?? [],
            description: desc,
            synonyms: media.synonyms ?? [],
            year: media.seasonYear,
            startYear: media.startDate?.year,
            season: media.season,
            format: media.format,
            duration: media.duration,
            trailerYouTubeID: trailerID,
            favourites: media.favourites,
            coverColor: media.coverImage?.color,
            malId: media.idMal,
            isFavourite: media.isFavourite,
            tags: tags(from: media.tags),
            isAdult: media.isAdult,
            source: media.source,
            countryOfOrigin: media.countryOfOrigin,
            studioNames: (media.studios?.nodes ?? []).compactMap { $0.name })
        item.extensionMediaJSON = extensionMediaJSON(from: media)
        if let mle = media.mediaListEntry {
            item.mediaListEntry = AnimeItem.MediaListEntry(
                listID: mle.id ?? 0,
                status: mle.status,
                progress: mle.progress ?? 0,
                score: Int(mle.score ?? 0),
                repeatCount: mle.repeatCount ?? 0,
                customLists: mediaListCustomLists(from: mle.customLists))
        }
        item.relations = (media.relations?.edges ?? []).compactMap { edge in
            guard let type = edge.relationType,
                  type != "CHARACTER",
                  let node = edge.node,
                  node.type == nil || node.type == "ANIME",
                  let nodeID = node.id else { return nil }
            let relation = AnimeItem(
                id: nodeID,
                titleEnglish: node.title?.english,
                titleRomaji: node.title?.romaji,
                titleNative: node.title?.native,
                titleUserPreferred: node.title?.userPreferred,
                coverURL: node.coverImage?.extraLarge ?? node.coverImage?.large ?? node.coverImage?.medium,
                score: node.averageScore,
                status: node.status,
                episodes: node.episodes,
                bannerURL: nil,
                genres: [],
                description: nil,
                synonyms: [],
                year: node.seasonYear,
                startYear: nil,
                season: node.season,
                format: node.format,
                coverColor: node.coverImage?.color)
            return AnimeRelation(relationType: type, media: relation)
        }
        return item
    }

    static func animeItem(from media: AniListResolverMediaResponse.ResolverMedia) -> AnimeItem? {
        guard let id = media.id else { return nil }
        let desc = media.description.map { stripHTML($0) }
        let trailerID = (media.trailer?.site?.lowercased() == "youtube") ? media.trailer?.id : nil
        var item = AnimeItem(
            id: id,
            titleEnglish: media.title?.english,
            titleRomaji: media.title?.romaji,
            titleNative: media.title?.native,
            titleUserPreferred: media.title?.userPreferred,
            coverURL: media.coverImage?.extraLarge ?? media.coverImage?.large ?? media.coverImage?.medium,
            score: media.averageScore,
            status: media.status,
            episodes: media.episodes,
            bannerURL: media.bannerImage,
            genres: media.genres ?? [],
            description: desc,
            synonyms: media.synonyms ?? [],
            year: media.seasonYear,
            startYear: media.startDate?.year,
            season: media.season,
            format: media.format,
            duration: media.duration,
            trailerYouTubeID: trailerID,
            favourites: media.favourites,
            coverColor: media.coverImage?.color,
            malId: media.idMal,
            isFavourite: media.isFavourite,
            tags: tags(from: media.tags),
            isAdult: media.isAdult,
            source: media.source,
            countryOfOrigin: media.countryOfOrigin,
            studioNames: (media.studios?.nodes ?? []).compactMap { $0.name })

        item.relations = (media.relations?.edges ?? []).compactMap { edge in
            guard let type = edge.relationType,
                  type != "CHARACTER",
                  let node = edge.node,
                  node.type == nil || node.type == "ANIME",
                  let nodeID = node.id else { return nil }
            let relation = AnimeItem(
                id: nodeID,
                titleEnglish: node.title?.english,
                titleRomaji: node.title?.romaji,
                titleNative: node.title?.native,
                titleUserPreferred: node.title?.userPreferred,
                coverURL: node.coverImage?.extraLarge ?? node.coverImage?.large ?? node.coverImage?.medium,
                score: node.averageScore,
                status: node.status,
                episodes: node.episodes,
                bannerURL: nil,
                genres: [],
                description: nil,
                synonyms: [],
                year: node.seasonYear,
                startYear: nil,
                season: node.season,
                format: node.format,
                coverColor: node.coverImage?.color)
            return AnimeRelation(relationType: type, media: relation)
        }

        return item
    }
}
