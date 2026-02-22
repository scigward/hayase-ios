//
//  AnimeService.swift
//  FinalProject
//
//  Created by Tieria C.Monk on 8/11/16.
//

import UIKit
import CoreData

// MARK: - Home section models

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
}

struct HomeSectionData {
    let title: String
    var items: [AnimeItem]
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
    query ($status: MediaStatus, $sort: [MediaSort], $genre: String) {
      Page(page: 1, perPage: 20) {
        media(type: ANIME, status: $status, sort: $sort, genre: $genre) {
          id
          title { english romaji }
          coverImage { large medium }
          bannerImage
          averageScore
          genres
          episodes
          status
          description(asHtml: false)
        }
      }
    }
    """

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
                    description: desc)
            }
            completion(items)
        }.resume()
    }

    // MARK: - AniList anime search (used by SearchViewController)

    private let anilistSearchQuery = """
    query ($search: String, $genre: String, $format: MediaFormat, $status: MediaStatus, $sort: [MediaSort], $page: Int) {
      Page(page: $page, perPage: 20) {
        pageInfo { hasNextPage }
        media(type: ANIME, search: $search, genre: $genre, format: $format, status: $status, sort: $sort) {
          id
          title { english romaji }
          coverImage { large medium }
          bannerImage
          averageScore
          genres
          episodes
          status
          description(asHtml: false)
        }
      }
    }
    """

    /// Search AniList with optional title, genre, format, status and sort.
    /// Calls completion on the main queue with ([AnimeItem], hasNextPage).
    func searchAnimeItems(title: String?,
                          genre: String?,
                          format: String?,
                          status: String?,
                          sort: String,
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
                    description: desc)
            }
            DispatchQueue.main.async { completion(items, hasNext) }
        }.resume()
    }

    func fetchHomeSections(completion: @escaping ([HomeSectionData]) -> Void) {
        let configs: [(title: String, variables: [String: Any])] = [
            ("Currently Airing", ["sort": ["POPULARITY_DESC"], "status": "RELEASING"]),
            ("Trending Now",     ["sort": ["TRENDING_DESC"]]),
            ("All Time Popular", ["sort": ["POPULARITY_DESC"]]),
            ("Action",           ["sort": ["TRENDING_DESC"], "genre": "Action"]),
            ("Romance",          ["sort": ["TRENDING_DESC"], "genre": "Romance"]),
        ]

        let group = DispatchGroup()
        let syncQueue = DispatchQueue(label: "com.theAnimetool.homeSections")
        var results: [(index: Int, section: HomeSectionData)] = []

        for (index, config) in configs.enumerated() {
            group.enter()
            fetchSectionItems(variables: config.variables) { items in
                let sectionData = HomeSectionData(title: config.title, items: items)
                syncQueue.sync { results.append((index: index, section: sectionData)) }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            let sorted = results.sorted { $0.index < $1.index }.map { $0.section }
            completion(sorted)
        }
    }

    static let sharedAnimeService = AnimeService()
}
