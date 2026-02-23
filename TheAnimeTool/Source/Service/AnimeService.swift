//
//  AnimeService.swift
//  FinalProject
//
//  Created by Tieria C.Monk on 8/11/16.
//

import UIKit
import CoreData

// MARK: - Home section models

struct AnimeRelation {
    let relationType: String   // "SEQUEL", "PREQUEL", "SIDE_STORY", "ALTERNATIVE", etc.
    let media: AnimeItem
}

struct AnimeCharacter {
    let name: String
    let imageURL: String?
    let role: String           // "MAIN", "SUPPORTING", "BACKGROUND"
}

struct AnimeItem {
    let id: Int
    let titleEnglish: String?
    let titleRomaji: String?
    let coverURL: String?
    let score: Float?
    let status: String?
    let episodes: Int?
    let bannerURL: String?
    let genres: [String]
    let description: String?
    var year: Int? = nil             // media.seasonYear from AniList
    var startYear: Int? = nil        // media.startDate.year — fallback when seasonYear is null (matches small.svelte)
    var format: String? = nil        // media.format from AniList (TV, MOVIE, OVA, etc.)
    var trailerYouTubeID: String? = nil  // non-nil when AniList trailer site == "youtube"
    var favourites: Int? = nil           // AniList favourites count
    var relations: [AnimeRelation] = []
    var characters: [AnimeCharacter] = []
}

struct HomeSectionData {
    let title: String
    var items: [AnimeItem]
    var filterGenre: String? = nil   // genre filter for "View More" (e.g. "Action", "Romance")
    var filterSort: String? = nil    // sort filter for "View More" (e.g. "TRENDING_DESC")
}

// MARK: - Staff + Stats models (anime/[id]/staff.svelte, anime/[id]/stats.svelte)

struct AnimeStaffMember {
    let name: String
    let imageURL: String?
    let role: String      // e.g. "Director", "Character Design", "Music"
}

struct AnimeScorePoint {
    let score: Int        // 10, 20, 30 … 100
    let amount: Int       // number of users who gave this score
}

struct AnimeStatusCount {
    let status: String    // "CURRENT", "COMPLETED", "PLANNING", "DROPPED", "PAUSED"
    let amount: Int
}

public class AnimeService: NSObject {
    enum AnimeError: Error {
        case errorSavingCoreData
        case emptyResult
    }

    static let LocalAnimeWillUpdateNotification = "LocalAnimeWillUpdateNotification"
    static let LocalAnimeDidUpdateNotification = "LocalAnimeDidUpdateNotification"
    static let LocalAnimeUpdateFailedNotification = "LocalAnimeUpdateFailedNotification"

    var insertIndexForTempEntries = 0

    private let graphQLEndpoint = "https://graphql.anilist.co"

    // MARK: - Codable models for AniList v2 GraphQL response

    private struct AniListResponse: Codable {
        let data: AniListData?
        struct AniListData: Codable {
            let Page: AniListPage?
            struct AniListPage: Codable {
                let pageInfo: PageInfo?
                let media: [AniListMedia]?
                struct PageInfo: Codable {
                    let hasNextPage: Bool?
                }
            }
        }
    }

    private struct AniListMedia: Codable {
        let id: Int?
        let title: Title?
        let coverImage: CoverImage?
        let bannerImage: String?
        let averageScore: Float?
        let popularity: Int?
        let episodes: Int?
        let description: String?
        let nextAiringEpisode: NextAiringEpisode?
        let status: String?
        let genres: [String]?
        let favourites: Int?
        let trailer: Trailer?
        let seasonYear: Int?
        let format: String?
        struct StartDate: Codable { let year: Int? }
        let startDate: StartDate?

        struct Title: Codable {
            let english: String?
            let romaji: String?
        }
        struct CoverImage: Codable {
            let large: String?
            let medium: String?
        }
        struct NextAiringEpisode: Codable {
            let episode: Int?
            let timeUntilAiring: Int?
        }
        struct Trailer: Codable {
            let id: String?
            let site: String?
        }
    }

    // MARK: - GraphQL queries

    private let airingAnimeQuery = """
    query {
      Page(page: 1, perPage: 50) {
        media(status: RELEASING, type: ANIME, sort: POPULARITY_DESC) {
          id
          title { english romaji }
          coverImage { large medium }
          bannerImage
          averageScore
          popularity
          episodes
          description(asHtml: false)
          nextAiringEpisode { episode timeUntilAiring }
          status
        }
      }
    }
    """

    private let searchAnimeQuery = """
    query ($search: String) {
      Page(page: 1, perPage: 50) {
        media(search: $search, type: ANIME, sort: POPULARITY_DESC) {
          id
          title { english romaji }
          coverImage { large medium }
          bannerImage
          averageScore
          popularity
          episodes
          description(asHtml: false)
          nextAiringEpisode { episode timeUntilAiring }
          status
        }
      }
    }
    """

    // MARK: - Networking

    private func makeGraphQLRequest(query: String, variables: [String: Any]? = nil, completion: @escaping ([AniListMedia]) -> Void) {
        guard let url = URL(string: graphQLEndpoint) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        var body: [String: Any] = ["query": query]
        if let variables = variables { body["variables"] = variables }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { data, _, error in
            if let error = error {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: NSNotification.Name(AnimeService.LocalAnimeUpdateFailedNotification), object: error as NSError)
                }
                print("Error getting anime data: \(error)")
                return
            }
            guard let data = data,
                  let response = try? JSONDecoder().decode(AniListResponse.self, from: data),
                  let mediaList = response.data?.Page?.media, !mediaList.isEmpty else {
                let err = NSError(domain: "AnimeService", code: 4, userInfo: nil)
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: NSNotification.Name(AnimeService.LocalAnimeUpdateFailedNotification), object: err)
                }
                return
            }
            completion(mediaList)
        }.resume()
    }

    // MARK: - Public API

    func UpdateTempWithAiringAnimes() {
        self.ClearTempAnimes()
        makeGraphQLRequest(query: airingAnimeQuery) { mediaList in
            DispatchQueue.main.async {
                do {
                    try self.UpdateLocalAnimes(mediaList, isTemp: true)
                } catch let error {
                    NotificationCenter.default.post(name: NSNotification.Name(AnimeService.LocalAnimeUpdateFailedNotification), object: error as NSError)
                }
            }
        }
    }

    func UpdateTempAnimesWithSearchString(_ searchStr: String) {
        self.ClearTempAnimes()
        makeGraphQLRequest(query: searchAnimeQuery, variables: ["search": searchStr]) { mediaList in
            DispatchQueue.main.async {
                do {
                    try self.UpdateLocalAnimes(mediaList, isTemp: true)
                } catch let error {
                    NotificationCenter.default.post(name: NSNotification.Name(AnimeService.LocalAnimeUpdateFailedNotification), object: error as NSError)
                }
            }
        }
    }

    // MARK: - Core Data

    private func UpdateLocalAnimes(_ mediaList: [AniListMedia], isTemp: Bool) throws {
        let context = CoreDataService.sharedCoreDataService.mainQueueContext
        let fetchRequest = NSFetchRequest<Animes>(entityName: Animes.entityName)
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: "animeAnilistId", ascending: true)]
        fetchRequest.predicate = NSPredicate(format: "animeStatus == %@", "RELEASING")
        let fetchedAnimes = (try? context.fetch(fetchRequest)) ?? []

        NotificationCenter.default.post(name: NSNotification.Name(AnimeService.LocalAnimeWillUpdateNotification), object: self)

        for media in mediaList {
            guard let anilistId = media.id else { continue }
            print("Processing anime id: \(anilistId)")

            var targetAnime: Animes
            if let foundIndex = fetchedAnimes.firstIndex(where: { $0.animeAnilistId?.intValue == anilistId }) {
                targetAnime = fetchedAnimes[foundIndex]
            } else {
                targetAnime = NSEntityDescription.insertNewObject(forEntityName: Animes.entityName, into: context) as! Animes
                targetAnime.animeAnilistId = NSNumber(value: anilistId)
            }
            targetAnime.animeImgL = media.coverImage?.large
            targetAnime.animeImgM = media.coverImage?.medium
            // animeImgS repurposed to store bannerImage (was a duplicate of animeImgM).
            // AnimeDetailViewController uses this as the hero banner; falls back to animeImgL.
            targetAnime.animeImgS = media.bannerImage
            targetAnime.animePopularity = media.popularity.map { NSNumber(value: $0) }
            targetAnime.animeScore = media.averageScore.map { NSNumber(value: $0) }
            targetAnime.animeStatus = media.status
            targetAnime.animeTitleEnglish = media.title?.english ?? media.title?.romaji
            targetAnime.animeTitleJapanese = media.title?.romaji
            targetAnime.animeTotalEps = media.episodes.map { NSNumber(value: $0) }
            // Store HTML-stripped synopsis from AniList.
            targetAnime.animeDescription = AnimeService.stripHTML(media.description ?? "")
            targetAnime.animeNextEps = media.nextAiringEpisode?.episode.map { NSNumber(value: $0) }
            if let timeUntilAiring = media.nextAiringEpisode?.timeUntilAiring {
                targetAnime.animeNextEpsTime = Date(timeIntervalSinceNow: Double(timeUntilAiring))
            }
            targetAnime.animeFlagTemp = NSNumber(value: isTemp)
            targetAnime.animeOrder = NSNumber(value: self.insertIndexForTempEntries)
            self.insertIndexForTempEntries += 1
        }

        do {
            try context.save()
        } catch {
            print("Error saving new anime information")
            throw AnimeError.errorSavingCoreData
        }

        NotificationCenter.default.post(name: NSNotification.Name(AnimeService.LocalAnimeDidUpdateNotification), object: self)
    }

    func ClearTempAnimes() {
        let context = CoreDataService.sharedCoreDataService.mainQueueContext
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: Animes.entityName)
        request.predicate = NSPredicate(format: "animeFlagTemp == YES")
        context.deleteAllData(request)
        self.insertIndexForTempEntries = 0
    }

    // MARK: - Helpers

    /// Strip HTML tags and decode common HTML entities from AniList description text.
    /// AniList returns description(asHtml: false) but may still include <br> and HTML entities.
    static func stripHTML(_ html: String) -> String {
        var s = html
        // <br> / <br/> / <br /> → newline
        s = s.replacingOccurrences(of: #"<br\s*/?>"#, with: "\n", options: .regularExpression)
        // Remove all remaining HTML tags
        s = s.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        // Decode common HTML entities
        s = s.replacingOccurrences(of: "&amp;", with: "&")
        s = s.replacingOccurrences(of: "&lt;", with: "<")
        s = s.replacingOccurrences(of: "&gt;", with: ">")
        s = s.replacingOccurrences(of: "&#039;", with: "'")
        s = s.replacingOccurrences(of: "&apos;", with: "'")
        s = s.replacingOccurrences(of: "&quot;", with: "\"")
        s = s.replacingOccurrences(of: "&nbsp;", with: " ")
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Home sections (in-memory, no CoreData)

    private let homeSectionQuery = """
    query ($status: MediaStatus, $sort: [MediaSort], $genre: String, $season: MediaSeason, $seasonYear: Int) {
      Page(page: 1, perPage: 20) {
        media(type: ANIME, status: $status, sort: $sort, genre: $genre, season: $season, seasonYear: $seasonYear) {
          id
          title { english romaji }
          coverImage { large medium }
          bannerImage
          averageScore
          genres
          episodes
          status
          seasonYear
          format
          startDate { year }
          favourites
          trailer { id site }
          description(asHtml: false)
        }
      }
    }
    """

    /// Returns the current AniList season string.
    /// AniList season definitions: WINTER = Jan–Mar, SPRING = Apr–Jun, SUMMER = Jul–Sep, FALL = Oct–Dec.
    private static func currentAniListSeason() -> String {
        let month = Calendar.current.component(.month, from: Date())
        switch month {
        case 1, 2, 3:   return "WINTER"
        case 4, 5, 6:   return "SPRING"
        case 7, 8, 9:   return "SUMMER"
        default:         return "FALL"
        }
    }

    private static func currentYear() -> Int {
        Calendar.current.component(.year, from: Date())
    }

    private func fetchSectionItems(variables: [String: Any],
                                   completion: @escaping ([AnimeItem]) -> Void) {
        guard let url = URL(string: graphQLEndpoint) else { completion([]); return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        var body: [String: Any] = ["query": homeSectionQuery]
        body["variables"] = variables
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data = data,
                  let response = try? JSONDecoder().decode(AniListResponse.self, from: data),
                  let mediaList = response.data?.Page?.media else {
                completion([])
                return
            }
            let items: [AnimeItem] = mediaList.compactMap { media in
                guard let id = media.id else { return nil }
                let desc = media.description.map { AnimeService.stripHTML($0) }
                let trailerID = (media.trailer?.site?.lowercased() == "youtube") ? media.trailer?.id : nil
                return AnimeItem(
                    id: id,
                    titleEnglish: media.title?.english,
                    titleRomaji: media.title?.romaji,
                    coverURL: media.coverImage?.large ?? media.coverImage?.medium,
                    score: media.averageScore,
                    status: media.status,
                    episodes: media.episodes,
                    bannerURL: media.bannerImage,
                    genres: media.genres ?? [],
                    description: desc,
                    year: media.seasonYear,
                    startYear: media.startDate?.year,
                    format: media.format,
                    trailerYouTubeID: trailerID,
                    favourites: media.favourites)
            }
            completion(items)
        }.resume()
    }

    // MARK: - Fetch by IDs (for "Continue Watching" home section — matches Hayase continueIDs)

    private let idInQuery = """
    query ($idIn: [Int]) {
      Page(page: 1, perPage: 50) {
        media(type: ANIME, id_in: $idIn) {
          id
          title { english romaji }
          coverImage { large medium }
          bannerImage
          averageScore
          genres
          episodes
          status
          seasonYear
          format
          startDate { year }
          favourites
          trailer { id site }
          description(asHtml: false)
        }
      }
    }
    """

    /// Fetches anime items by AniList IDs. Used for the "Continue Watching" home section.
    /// Calls completion on the main queue.
    func fetchSectionByIDs(_ ids: [Int], completion: @escaping ([AnimeItem]) -> Void) {
        guard !ids.isEmpty, let url = URL(string: graphQLEndpoint) else { completion([]); return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let body: [String: Any] = ["query": idInQuery, "variables": ["idIn": ids]]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data = data,
                  let response = try? JSONDecoder().decode(AniListResponse.self, from: data),
                  let mediaList = response.data?.Page?.media else {
                DispatchQueue.main.async { completion([]) }
                return
            }
            // Preserve the caller's ordering (most-recently-watched first)
            var itemMap: [Int: AnimeItem] = [:]
            for media in mediaList {
                guard let id = media.id else { continue }
                let desc = media.description.map { AnimeService.stripHTML($0) }
                let trailerID = (media.trailer?.site?.lowercased() == "youtube") ? media.trailer?.id : nil
                itemMap[id] = AnimeItem(
                    id: id,
                    titleEnglish: media.title?.english,
                    titleRomaji: media.title?.romaji,
                    coverURL: media.coverImage?.large ?? media.coverImage?.medium,
                    score: media.averageScore,
                    status: media.status,
                    episodes: media.episodes,
                    bannerURL: media.bannerImage,
                    genres: media.genres ?? [],
                    description: desc,
                    year: media.seasonYear,
                    startYear: media.startDate?.year,
                    format: media.format,
                    trailerYouTubeID: trailerID,
                    favourites: media.favourites)
            }
            let ordered = ids.compactMap { itemMap[$0] }
            DispatchQueue.main.async { completion(ordered) }
        }.resume()
    }

    // MARK: - AniList anime search (used by SearchViewController)

    private let anilistSearchQuery = """
    query ($search: String, $genre: String, $format: MediaFormat, $status: MediaStatus, $sort: [MediaSort], $page: Int, $seasonYear: Int, $season: MediaSeason) {
      Page(page: $page, perPage: 20) {
        pageInfo { hasNextPage }
        media(type: ANIME, search: $search, genre: $genre, format: $format, status: $status, sort: $sort, seasonYear: $seasonYear, season: $season) {
          id
          title { english romaji }
          coverImage { large medium }
          bannerImage
          averageScore
          genres
          episodes
          status
          seasonYear
          format
          startDate { year }
          favourites
          trailer { id site }
          description(asHtml: false)
        }
      }
    }
    """

    /// Search AniList with optional title, genre, format, status, sort, seasonYear and season.
    /// Calls completion on the main queue with ([AnimeItem], hasNextPage).
    func searchAnimeItems(title: String?,
                          genre: String?,
                          format: String?,
                          status: String?,
                          sort: String,
                          seasonYear: Int? = nil,
                          season: String? = nil,
                          page: Int,
                          completion: @escaping ([AnimeItem], Bool) -> Void) {
        guard let url = URL(string: graphQLEndpoint) else { completion([], false); return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        var variables: [String: Any] = ["sort": [sort], "page": page]
        if let t = title, !t.isEmpty { variables["search"] = t }
        if let g = genre { variables["genre"] = g }
        if let f = format { variables["format"] = f }
        if let s = status { variables["status"] = s }
        if let y = seasonYear { variables["seasonYear"] = y }
        if let s = season { variables["season"] = s }

        let body: [String: Any] = ["query": anilistSearchQuery, "variables": variables]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data = data,
                  let response = try? JSONDecoder().decode(AniListResponse.self, from: data),
                  let pageData = response.data?.Page else {
                DispatchQueue.main.async { completion([], false) }
                return
            }
            let hasNext = pageData.pageInfo?.hasNextPage ?? false
            let items: [AnimeItem] = (pageData.media ?? []).compactMap { media in
                guard let id = media.id else { return nil }
                let desc = media.description.map { AnimeService.stripHTML($0) }
                let trailerID = (media.trailer?.site?.lowercased() == "youtube") ? media.trailer?.id : nil
                return AnimeItem(
                    id: id,
                    titleEnglish: media.title?.english,
                    titleRomaji: media.title?.romaji,
                    coverURL: media.coverImage?.large ?? media.coverImage?.medium,
                    score: media.averageScore,
                    status: media.status,
                    episodes: media.episodes,
                    bannerURL: media.bannerImage,
                    genres: media.genres ?? [],
                    description: desc,
                    year: media.seasonYear,
                    startYear: media.startDate?.year,
                    format: media.format,
                    trailerYouTubeID: trailerID,
                    favourites: media.favourites)
            }
            DispatchQueue.main.async { completion(items, hasNext) }
        }.resume()
    }

    func fetchHomeSections(completion: @escaping ([HomeSectionData]) -> Void) {
        // Matches Hayase home/+page.svelte exactly — no "Airing Today" (that's only in schedule)
        let season = AnimeService.currentAniListSeason()
        let year   = AnimeService.currentYear()
        let configs: [(title: String, variables: [String: Any])] = [
            ("Popular This Season", ["sort": ["POPULARITY_DESC"], "season": season, "seasonYear": year]),
            ("Trending Now",        ["sort": ["TRENDING_DESC"]]),
            ("All Time Popular",    ["sort": ["POPULARITY_DESC"]]),
            ("Romance",             ["sort": ["TRENDING_DESC"], "genre": "Romance"]),
            ("Action",              ["sort": ["TRENDING_DESC"], "genre": "Action"]),
            ("Adventure",           ["sort": ["TRENDING_DESC"], "genre": "Adventure"]),
            ("Fantasy",             ["sort": ["TRENDING_DESC"], "genre": "Fantasy"]),
        ]

        let group = DispatchGroup()
        let syncQueue = DispatchQueue(label: "com.theAnimetool.homeSections")
        var results = [HomeSectionData?](repeating: nil, count: configs.count)

        for (index, config) in configs.enumerated() {
            group.enter()
            fetchSectionItems(variables: config.variables) { items in
                var sectionData = HomeSectionData(title: config.title, items: items)
                sectionData.filterGenre = config.variables["genre"] as? String
                sectionData.filterSort  = (config.variables["sort"] as? [String])?.first
                syncQueue.sync { results[index] = sectionData }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            completion(results.compactMap { $0 })
        }
    }

    // MARK: - Detail fetch (relations + characters)

    private let detailQuery = """
    query ($id: Int) {
      Media(id: $id, type: ANIME) {
        relations {
          edges {
            relationType
            node {
              id
              title { english romaji }
              coverImage { large }
              averageScore
              episodes
              status
            }
          }
        }
        characters(sort: [ROLE, RELEVANCE], page: 1, perPage: 12) {
          edges {
            role
            node {
              name { full }
              image { medium }
            }
          }
        }
      }
    }
    """

    private struct AniListDetailResponse: Codable {
        let data: DetailData?
        struct DetailData: Codable {
            let Media: DetailMedia?
        }
        struct DetailMedia: Codable {
            let relations: RelationConnection?
            let characters: CharacterConnection?
        }
        struct RelationConnection: Codable {
            let edges: [RelationEdge]?
        }
        struct RelationEdge: Codable {
            let relationType: String?
            let node: RelationNode?
        }
        struct RelationNode: Codable {
            let id: Int?
            let title: RelTitle?
            let coverImage: RelCover?
            let averageScore: Float?
            let episodes: Int?
            let status: String?
            struct RelTitle: Codable { let english: String?; let romaji: String? }
            struct RelCover: Codable { let large: String? }
        }
        struct CharacterConnection: Codable {
            let edges: [CharacterEdge]?
        }
        struct CharacterEdge: Codable {
            let role: String?
            let node: CharacterNode?
        }
        struct CharacterNode: Codable {
            let name: CharName?
            let image: CharImage?
            struct CharName: Codable { let full: String? }
            struct CharImage: Codable { let medium: String? }
        }
    }

    /// Fetch relations and characters for an anime by its AniList ID.
    /// Calls completion on the main queue.
    func fetchDetailForItem(id: Int, completion: @escaping ([AnimeRelation], [AnimeCharacter]) -> Void) {
        guard let url = URL(string: graphQLEndpoint) else { completion([], []); return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let body: [String: Any] = ["query": detailQuery, "variables": ["id": id]]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data = data,
                  let resp = try? JSONDecoder().decode(AniListDetailResponse.self, from: data),
                  let media = resp.data?.Media else {
                DispatchQueue.main.async { completion([], []) }
                return
            }

            let relations: [AnimeRelation] = (media.relations?.edges ?? []).compactMap { edge -> AnimeRelation? in
                guard let type = edge.relationType, let node = edge.node, let nid = node.id else { return nil }
                // Skip unwanted relation types
                let skip = ["ADAPTATION", "CHARACTER", "OTHER"]
                if skip.contains(type) { return nil }
                let relItem = AnimeItem(
                    id: nid,
                    titleEnglish: node.title?.english,
                    titleRomaji: node.title?.romaji,
                    coverURL: node.coverImage?.large,
                    score: node.averageScore,
                    status: node.status,
                    episodes: node.episodes,
                    bannerURL: nil,
                    genres: [],
                    description: nil)
                return AnimeRelation(relationType: type, media: relItem)
            }

            let characters: [AnimeCharacter] = (media.characters?.edges ?? []).compactMap { edge in
                guard let node = edge.node, let fullName = node.name?.full else { return nil }
                return AnimeCharacter(
                    name: fullName,
                    imageURL: node.image?.medium,
                    role: edge.role ?? "SUPPORTING")
            }

            DispatchQueue.main.async { completion(relations, characters) }
        }.resume()
    }

    // MARK: - Airing schedule (used by ScheduleViewController)

    private struct AiringScheduleResponse: Codable {
        let data: AiringData?
        struct AiringData: Codable {
            let Page: AiringPage?
        }
        struct AiringPage: Codable {
            let airingSchedules: [AiringSchedule]?
        }
        struct AiringSchedule: Codable {
            let episode: Int?
            let airingAt: Int?
            let media: AiringMedia?
        }
        struct AiringMedia: Codable {
            let id: Int?
            let title: AiringTitle?
            let coverImage: AiringCover?
            let averageScore: Float?
            let episodes: Int?
            let status: String?
            struct AiringTitle: Codable { let english: String?; let romaji: String? }
            struct AiringCover: Codable { let large: String? }
        }
    }

    private let airingScheduleQuery = """
    query ($from: Int, $to: Int) {
      Page(page: 1, perPage: 50) {
        airingSchedules(airingAt_greater: $from, airingAt_lesser: $to, sort: TIME) {
          episode
          airingAt
          media {
            id
            title { english romaji }
            coverImage { large }
            averageScore
            episodes
            status
          }
        }
      }
    }
    """

    /// Fetch anime airing on the given weekday (0 = Sunday … 6 = Saturday).
    /// Calls completion on the main queue with a deduplicated list of AnimeItems.
    func fetchAiringForWeekday(_ weekday: Int, completion: @escaping ([AnimeItem]) -> Void) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        var comps = cal.dateComponents([.weekOfYear, .yearForWeekOfYear], from: Date())
        comps.weekday = weekday + 1  // Calendar.weekday is 1-indexed (1 = Sunday)
        guard let targetDay = cal.date(from: comps) else { completion([]); return }
        let start = Int(cal.startOfDay(for: targetDay).timeIntervalSince1970)
        let end = start + 86399

        guard let url = URL(string: graphQLEndpoint) else { completion([]); return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let body: [String: Any] = [
            "query": airingScheduleQuery,
            "variables": ["from": start, "to": end]
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data = data,
                  let resp = try? JSONDecoder().decode(AiringScheduleResponse.self, from: data),
                  let schedules = resp.data?.Page?.airingSchedules else {
                DispatchQueue.main.async { completion([]) }
                return
            }
            // Deduplicate by media id
            var seen = Set<Int>()
            let items: [AnimeItem] = schedules.compactMap { sched -> AnimeItem? in
                guard let media = sched.media, let id = media.id,
                      seen.insert(id).inserted else { return nil }
                return AnimeItem(
                    id: id,
                    titleEnglish: media.title?.english,
                    titleRomaji: media.title?.romaji,
                    coverURL: media.coverImage?.large,
                    score: media.averageScore,
                    status: media.status,
                    episodes: media.episodes,
                    bannerURL: nil,
                    genres: [],
                    description: nil)
            }
            DispatchQueue.main.async { completion(items) }
        }.resume()
    }

    static let sharedAnimeService = AnimeService()

    // MARK: - Staff + Stats fetch (anime/[id]/staff.svelte + anime/[id]/stats.svelte)

    private let staffStatsQuery = """
    query ($id: Int) {
      Media(id: $id, type: ANIME) {
        staff(sort: [RELEVANCE], page: 1, perPage: 12) {
          edges {
            role
            node {
              name { full }
              image { medium }
            }
          }
        }
        stats {
          scoreDistribution { score amount }
          statusDistribution { status amount }
        }
      }
    }
    """

    private struct StaffStatsResponse: Codable {
        let data: SSData?
        struct SSData: Codable { let Media: SSMedia? }
        struct SSMedia: Codable {
            let staff: StaffConn?
            let stats: MediaStats?
        }
        struct StaffConn: Codable { let edges: [StaffEdge]? }
        struct StaffEdge: Codable {
            let role: String?
            let node: StaffNode?
        }
        struct StaffNode: Codable {
            let name: StaffName?
            let image: StaffImage?
            struct StaffName: Codable { let full: String? }
            struct StaffImage: Codable { let medium: String? }
        }
        struct MediaStats: Codable {
            let scoreDistribution: [ScoreDist]?
            let statusDistribution: [StatusDist]?
            struct ScoreDist: Codable { let score: Int?; let amount: Int? }
            struct StatusDist: Codable { let status: String?; let amount: Int? }
        }
    }

    /// Fetch staff members and score/status distribution for an AniList anime.
    /// Calls completion on the main queue.
    func fetchStaffAndStats(id: Int,
                            completion: @escaping ([AnimeStaffMember], [AnimeScorePoint], [AnimeStatusCount]) -> Void) {
        guard let url = URL(string: graphQLEndpoint) else { completion([], [], []); return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let body: [String: Any] = ["query": staffStatsQuery, "variables": ["id": id]]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data = data,
                  let resp = try? JSONDecoder().decode(StaffStatsResponse.self, from: data),
                  let media = resp.data?.Media else {
                DispatchQueue.main.async { completion([], [], []) }
                return
            }
            let staff: [AnimeStaffMember] = (media.staff?.edges ?? []).compactMap { edge in
                guard let node = edge.node, let name = node.name?.full else { return nil }
                return AnimeStaffMember(name: name, imageURL: node.image?.medium, role: edge.role ?? "")
            }
            let scores: [AnimeScorePoint] = (media.stats?.scoreDistribution ?? []).compactMap { d in
                guard let s = d.score, let a = d.amount else { return nil }
                return AnimeScorePoint(score: s, amount: a)
            }.sorted { $0.score < $1.score }
            let statuses: [AnimeStatusCount] = (media.stats?.statusDistribution ?? []).compactMap { d in
                guard let s = d.status, let a = d.amount else { return nil }
                return AnimeStatusCount(status: s, amount: a)
            }
            DispatchQueue.main.async { completion(staff, scores, statuses) }
        }.resume()
    }
}
