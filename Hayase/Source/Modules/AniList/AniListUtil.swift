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

    /// Matches interface `title(media)`: default AniList title is `userPreferred`.
    static func title(for item: AnimeItem) -> String {
        item.titleUserPreferred
            ?? item.titleRomaji
            ?? item.titleEnglish
            ?? item.titleNative
            ?? "TBA"
    }

    /// Matches anime/[id]/+layout.svelte's muted alternate title line.
    static func alternateTitle(for item: AnimeItem) -> String? {
        let primary = title(for: item)
        let normalizedPrimary = primary.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedRomaji = item.titleRomaji?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let alternate = normalizedRomaji == normalizedPrimary
            ? (item.titleNative ?? item.titleRomaji)
            : (item.titleRomaji ?? item.titleNative)
        guard let alternate, !alternate.isEmpty, alternate != primary else { return nil }
        return alternate
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
        let show = UserDefaults.standard.object(forKey: "pref_showHentai") as? Bool ?? false
        return show ? nil : ["Hentai"]
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
            tags: tags(from: media.tags),
            isAdult: media.isAdult)
        if let mle = media.mediaListEntry, let s = mle.status {
            item.mediaListEntry = AnimeItem.MediaListEntry(
                listID: mle.id ?? 0,
                status: s,
                progress: mle.progress ?? 0,
                score: Int(mle.score ?? 0),
                repeatCount: mle.repeatCount ?? 0,
                customLists: [])
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
            malId: media.idMal)

        item.relations = (media.relations?.edges ?? []).compactMap { edge in
            guard let type = edge.relationType,
                  let node = edge.node,
                  let nodeID = node.id else { return nil }
            let relation = AnimeItem(
                id: nodeID,
                titleEnglish: node.title?.english,
                titleRomaji: node.title?.romaji,
                coverURL: node.coverImage?.large ?? node.coverImage?.medium,
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
