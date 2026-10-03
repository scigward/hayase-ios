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

    /// util.ts `desc(media)` of a description: the tags are cut out, `<br>` included, which is why a
    /// paragraph break is only as long as the line feeds AniList puts after it, runs of line feeds
    /// become one, and the entities stay as they are, the interface does not decode them.
    static func stripHTML(_ html: String) -> String {
        var s = html
        s = s.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\n+"#, with: "\n", options: .regularExpression)
        return notes(s).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// util.ts `notes(string)`. The regular expressions of the interface are not global: the first
    /// source and the first note are cut out, and no more.
    static func notes(_ string: String) -> String {
        var result = string
        for pattern in [#"\n?\(?Source: [^)]+\)?\n?"#, #"\n?Notes?:[ |\n][^\n]+\n?"#] {
            if let range = result.range(of: pattern, options: .regularExpression) {
                result.removeSubrange(range)
            }
        }
        return result
    }

    /// util.ts `episodes(media, eps)`
    static func episodes(for media: AnimeItem, mappings: Int = 0) -> Int {
        if let episodes = media.episodes, episodes != 0 { return episodes }
        return max(media.airedSchedule.last?.episode ?? 0, media.notYetAiredSchedule.last?.episode ?? 0, mappings)
    }

    /// auth/util.ts `of(media, eps)`: "12 Episodes", "3 / 12 Episodes", or nothing for a single episode or
    /// an unknown count. Without `eps`, the progress stands in for the count the mappings know.
    static func episodesText(for media: AnimeItem, mappings: Int? = nil) -> String? {
        let progress = media.listEntry?.progress ?? 0
        let count = episodes(for: media, mappings: mappings ?? progress)
        guard count != 1, count != 0 else { return nil }
        return progress == 0 || progress == count ? "\(count) Episodes" : "\(progress) / \(count) Episodes"
    }

    /// util.ts `isMovie(media)`
    static func isMovie(_ media: AnimeItem) -> Bool {
        if media.format == "MOVIE" { return true }
        let names = [media.titleRomaji, media.titleEnglish, media.titleNative, media.titleUserPreferred].compactMap { $0 } + media.synonyms
        if names.contains(where: { $0.lowercased().contains("movie") }) { return true }
        return (media.duration ?? 0) > 80 && media.episodes == 1
    }

    /// util.ts `isSingleEpisode(media)`
    static func isSingleEpisode(_ media: AnimeItem) -> Bool {
        media.episodes == 1 || (isMovie(media) && (media.episodes ?? 0) == 0)
    }

    /// extensions.ts `makeEpisodeList`'s `alSchedule`: when each episode airs, from the two schedules
    /// (the first of an episode wins), and for a single episode that has none, the day it started.
    static func airingSchedule(for media: AnimeItem?) -> [Int: Date] {
        guard let media else { return [:] }
        var schedule: [Int: Date] = [:]
        for node in media.airedSchedule + media.notYetAiredSchedule {
            guard let airingAt = node.airingAt, schedule[node.episode] == nil else { continue }
            schedule[node.episode] = Date(timeIntervalSince1970: Double(airingAt))
        }
        if schedule[1] == nil, isSingleEpisode(media) {
            var components = DateComponents()
            // `new Date(year, …)` reads 0-99 as 1900-1999
            let year = media.startYear ?? 0
            components.year = (0...99).contains(year) ? 1900 + year : year
            components.month = media.startMonth ?? 1
            components.day = media.startDay ?? 1
            if let date = Calendar.current.date(from: components) { schedule[1] = date }
        }
        return schedule
    }

    /// util.ts `season(media)`: the season and the year, from the start date when the media has none.
    static func seasonText(for media: AnimeItem) -> String? {
        let season: String? = media.season?.lowercased() ?? media.startMonth.flatMap { month in
            guard month != 0 else { return nil }
            // getSeasonForMonth, which takes the month as AniList counts it
            return ["winter", "spring", "summer", "fall"][Int((Double(month) / 12 * 4).rounded(.down)) % 4]
        }
        let year = media.year ?? media.startYear
        let parts = [season, year.flatMap { $0 != 0 ? String($0) : nil }].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    /// util.ts `format(media)`
    static func format(_ format: String?) -> String {
        switch format {
        case "TV": return "TV Series"
        case "TV_SHORT": return "TV Short"
        case "MOVIE": return "Movie"
        case "SPECIAL": return "Special"
        case "OVA": return "OVA"
        case "ONA": return "ONA"
        case "MUSIC": return "Music"
        case "MANGA": return "Manga"
        case "NOVEL": return "Novel"
        case "ONE_SHOT": return "One Shot"
        default: return "N/A"
        }
    }

    /// util.ts `status(media)`
    static func status(_ status: String?) -> String {
        switch status {
        case "RELEASING": return "Releasing"
        case "NOT_YET_RELEASED": return "Not Yet Released"
        case "FINISHED": return "Finished"
        case "CANCELLED": return "Cancelled"
        case "HIATUS": return "Hiatus"
        default: return "N/A"
        }
    }

    /// util.ts `removeDiacritics`: for some reason diacritics started breaking AL search.
    static func removeDiacritics(_ string: String) -> String {
        var result = ""
        result.unicodeScalars.append(contentsOf: string.decomposedStringWithCanonicalMapping.unicodeScalars.filter {
            !(0x0300...0x036F).contains($0.value)
        })
        return result
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

    /// util.ts `banner()`: the banner image, else the thumbnail of the trailer, else the cover.
    static func banner(for item: AnimeItem) -> String? {
        if let banner = item.bannerURL, !banner.isEmpty { return banner }
        if let trailer = item.trailerYouTubeID, !trailer.isEmpty {
            return "https://i.ytimg.com/vi/\(trailer)/maxresdefault.jpg"
        }
        return item.coverURL
    }

    /// util.ts `cover()`: the cover, else `banner()`.
    static func cover(for item: AnimeItem) -> String? {
        item.coverURL ?? banner(for: item)
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
            // `Math.round` rounds a half up and `rounded()` rounds it away from zero: -1.5 is -1 in the interface
            let value = Int(safe: (secondsElapsed / range.seconds + 0.5).rounded(.down))
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
            "averageScore": jsonValue(media.averageScore.map { Int(safe: Double($0.rounded())) }),
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

    private static func airingEpisodes(_ connection: AniListMedia.AiringConnection?) -> [AnimeItem.AiringEpisode] {
        (connection?.n ?? []).compactMap { node in
            node.e.map { AnimeItem.AiringEpisode(airingAt: node.a, episode: $0) }
        }
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
            startMonth: media.startDate?.month,
            startDay: media.startDate?.day,
            season: media.season,
            format: media.format,
            duration: media.duration,
            trailerYouTubeID: trailerID,
            favourites: media.favourites,
            coverColor: media.coverImage?.color,
            coverMediumURL: media.coverImage?.medium?.replacingOccurrences(of: "/small/", with: "/medium/"),
            malId: media.idMal,
            isFavourite: media.isFavourite,
            tags: tags(from: media.tags),
            isAdult: media.isAdult,
            source: media.source,
            countryOfOrigin: media.countryOfOrigin,
            studioNames: (media.studios?.nodes ?? []).compactMap { $0.name })
        item.extensionMediaJSON = extensionMediaJSON(from: media)
        item.airedSchedule = airingEpisodes(media.aired)
        item.notYetAiredSchedule = airingEpisodes(media.notaired)
        if let mle = media.mediaListEntry {
            item.mediaListEntry = AnimeItem.MediaListEntry(
                listID: mle.id ?? 0,
                status: mle.status,
                progress: mle.progress ?? 0,
                score: Int(safe: Double(mle.score ?? 0)),
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
            startMonth: media.startDate?.month,
            startDay: media.startDate?.day,
            season: media.season,
            format: media.format,
            duration: media.duration,
            trailerYouTubeID: trailerID,
            favourites: media.favourites,
            coverColor: media.coverImage?.color,
            coverMediumURL: media.coverImage?.medium?.replacingOccurrences(of: "/small/", with: "/medium/"),
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
