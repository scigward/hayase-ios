//
//  AnimeService.swift
//  FinalProject
//
//  Created by Tieria C.Monk on 8/11/16.
//

import UIKit
import CoreData

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
                let media: [AniListMedia]?
            }
        }
    }

    private struct AniListMedia: Codable {
        let id: Int?
        let title: Title?
        let coverImage: CoverImage?
        let averageScore: Float?
        let popularity: Int?
        let episodes: Int?
        let nextAiringEpisode: NextAiringEpisode?
        let status: String?

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
          averageScore
          popularity
          episodes
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
          averageScore
          popularity
          episodes
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
            targetAnime.animeImgS = media.coverImage?.medium
            targetAnime.animePopularity = media.popularity.map { NSNumber(value: $0) }
            targetAnime.animeScore = media.averageScore.map { NSNumber(value: $0) }
            targetAnime.animeStatus = media.status
            targetAnime.animeTitleEnglish = media.title?.english ?? media.title?.romaji
            targetAnime.animeTitleJapanese = media.title?.romaji
            targetAnime.animeTotalEps = media.episodes.map { NSNumber(value: $0) }
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

    static let sharedAnimeService = AnimeService()
}
