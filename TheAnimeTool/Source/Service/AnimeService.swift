//
//  AnimeService.swift
//  FinalProject
//
//  Created by Tieria C.Monk on 8/11/16.
//

import UIKit
import SwiftyJSON
import CoreData

public class AnimeService: NSObject {
    enum AnimeError: Error {
        case invalidServerJSONArray
        case errorSavingCoreData
        case emptyResult
    }

    static let LocalAnimeWillUpdateNotification = "LocalAnimeWillUpdateNotification"
    static let LocalAnimeDidUpdateNotification = "LocalAnimeDidUpdateNotification"
    static let LocalAnimeUpdateFailedNotification = "LocalAnimeUpdateFailedNotification"

    var insertIndexForTempEntries = 0

    private let graphQLEndpoint = "https://graphql.anilist.co"

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

    private func makeGraphQLRequest(query: String, variables: [String: Any]? = nil, completion: @escaping (Data?, Error?) -> Void) {
        guard let url = URL(string: graphQLEndpoint) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        var body: [String: Any] = ["query": query]
        if let variables = variables {
            body["variables"] = variables
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        URLSession.shared.dataTask(with: request) { data, _, error in
            completion(data, error)
        }.resume()
    }

    func UpdateTempWithAiringAnimes() {
        self.ClearTempAnimes()
        makeGraphQLRequest(query: airingAnimeQuery) { data, error in
            if let error = error {
                NotificationCenter.default.post(name: NSNotification.Name(AnimeService.LocalAnimeUpdateFailedNotification), object: error as NSError)
                print("Error getting anime data: \(error)")
                return
            }
            guard let data = data else { return }
            let animeJSON = JSON(data: data)
            do {
                try self.UpdateLocalAnimes(animeJSON["data"]["Page"]["media"], isTemp: true)
            } catch let error {
                NotificationCenter.default.post(name: NSNotification.Name(AnimeService.LocalAnimeUpdateFailedNotification), object: error as NSError)
            }
        }
    }

    func UpdateTempAnimesWithSearchString(_ searchStr: String) {
        self.ClearTempAnimes()
        makeGraphQLRequest(query: searchAnimeQuery, variables: ["search": searchStr]) { data, error in
            if let error = error {
                NotificationCenter.default.post(name: NSNotification.Name(AnimeService.LocalAnimeUpdateFailedNotification), object: error as NSError)
                print("Error getting anime data: \(error)")
                return
            }
            guard let data = data else { return }
            let animeJSON = JSON(data: data)
            do {
                try self.UpdateLocalAnimes(animeJSON["data"]["Page"]["media"], isTemp: true)
            } catch let error {
                NotificationCenter.default.post(name: NSNotification.Name(AnimeService.LocalAnimeUpdateFailedNotification), object: error as NSError)
            }
        }
    }

    private func UpdateLocalAnimes(_ animesJSON: JSON, isTemp: Bool) throws {
        guard let animesJSONArray = animesJSON.array, !animesJSONArray.isEmpty else {
            throw AnimeError.emptyResult
        }

        let context = CoreDataService.sharedCoreDataService.mainQueueContext
        let fetchRequest = NSFetchRequest<Animes>(entityName: Animes.entityName)
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: "animeAnilistId", ascending: true)]
        fetchRequest.predicate = NSPredicate(format: "animeStatus == %@", "RELEASING")
        let fetchedAnimes = (try? context.fetch(fetchRequest)) ?? []

        NotificationCenter.default.post(name: NSNotification.Name(AnimeService.LocalAnimeWillUpdateNotification), object: self)

        for animeJSON in animesJSONArray {
            print(animeJSON.description)

            var targetAnime: Animes
            let animeId = animeJSON["id"].intValue
            if let foundIndex = fetchedAnimes.firstIndex(where: { $0.animeAnilistId?.intValue == animeId }) {
                targetAnime = fetchedAnimes[foundIndex]
            } else {
                targetAnime = NSEntityDescription.insertNewObject(forEntityName: Animes.entityName, into: context) as! Animes
                guard let anilistId = animeJSON["id"].int else { continue }
                targetAnime.animeAnilistId = NSNumber(value: anilistId)
            }
            targetAnime.animeImgL = animeJSON["coverImage"]["large"].string
            targetAnime.animeImgM = animeJSON["coverImage"]["medium"].string
            targetAnime.animeImgS = animeJSON["coverImage"]["medium"].string
            targetAnime.animePopularity = animeJSON["popularity"].int.map { NSNumber(value: $0) }
            targetAnime.animeScore = animeJSON["averageScore"].float.map { NSNumber(value: $0) }
            targetAnime.animeStatus = animeJSON["status"].string
            targetAnime.animeTitleEnglish = animeJSON["title"]["english"].string ?? animeJSON["title"]["romaji"].string
            targetAnime.animeTitleJapanese = animeJSON["title"]["romaji"].string
            targetAnime.animeTotalEps = animeJSON["episodes"].int.map { NSNumber(value: $0) }
            targetAnime.animeNextEps = animeJSON["nextAiringEpisode"]["episode"].int.map { NSNumber(value: $0) }
            if let timeUntilAiring = animeJSON["nextAiringEpisode"]["timeUntilAiring"].int {
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
