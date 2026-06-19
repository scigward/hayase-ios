//
//  Client.swift
//  Hayase
//
//  AniList API client.
//  Mirrors: src/lib/modules/anilist/client.ts
//

import UIKit
import CoreData

// MARK: - AniListClient

public final class AniListClient: NSObject {

    static let shared = AniListClient()

    private let graphQLEndpoint = "https://graphql.anilist.co"
    private let followingManyQueue = DispatchQueue(label: "com.hayase.anilist.followingMany")
    private var followingManyCache: [String: (viewerID: Int, usersByMediaID: [Int: [AniListUserSummary]])] = [:]
    private var followingManyCompletions: [String: [([Int: [AniListUserSummary]]) -> Void]] = [:]

    // MARK: - Notifications (iOS-specific, for CoreData sync)

    static let LocalAnimeWillUpdateNotification = "LocalAnimeWillUpdateNotification"
    static let LocalAnimeDidUpdateNotification  = "LocalAnimeDidUpdateNotification"
    static let LocalAnimeUpdateFailedNotification = "LocalAnimeUpdateFailedNotification"

    var insertIndexForTempEntries = 0

    enum AniListError: Error {
        case errorSavingCoreData
        case emptyResult
    }

    // MARK: - Private networking

    private func graphQLRequest(query: String, variables: [String: Any]? = nil, completion: @escaping ([AniListMedia]) -> Void) {
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
                    NotificationCenter.default.post(name: NSNotification.Name(AniListClient.LocalAnimeUpdateFailedNotification), object: error as NSError)
                }
                print("Error getting anime data: \(error)")
                return
            }
            guard let data = data,
                  let response = try? JSONDecoder().decode(AniListResponse.self, from: data),
                  let mediaList = response.data?.Page?.media, !mediaList.isEmpty else {
                let err = NSError(domain: "AniListClient", code: 4, userInfo: nil)
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: NSNotification.Name(AniListClient.LocalAnimeUpdateFailedNotification), object: err)
                }
                return
            }
            completion(mediaList)
        }.resume()
    }

    /// Adds an auth header if the user is logged in.
    private func authorizedRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = TrackerAccountManager.shared.token(for: .anilist) {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    // MARK: - CoreData (legacy, iOS-specific)

    func UpdateTempWithAiringAnimes() {
        ClearTempAnimes()
        var variables: [String: Any] = [:]
        if let nsfw = AniListUtil.nsfwGenreFilter { variables["nsfw"] = nsfw }
        graphQLRequest(query: AniListQueries.airingAnime, variables: variables.isEmpty ? nil : variables) { mediaList in
            DispatchQueue.main.async {
                do {
                    try self.UpdateLocalAnimes(mediaList, isTemp: true)
                } catch let error {
                    NotificationCenter.default.post(name: NSNotification.Name(AniListClient.LocalAnimeUpdateFailedNotification), object: error as NSError)
                }
            }
        }
    }

    func UpdateTempAnimesWithSearchString(_ searchStr: String) {
        ClearTempAnimes()
        var variables: [String: Any] = ["search": searchStr]
        if let nsfw = AniListUtil.nsfwGenreFilter { variables["nsfw"] = nsfw }
        graphQLRequest(query: AniListQueries.searchLegacy, variables: variables) { mediaList in
            DispatchQueue.main.async {
                do {
                    try self.UpdateLocalAnimes(mediaList, isTemp: true)
                } catch let error {
                    NotificationCenter.default.post(name: NSNotification.Name(AniListClient.LocalAnimeUpdateFailedNotification), object: error as NSError)
                }
            }
        }
    }

    private func UpdateLocalAnimes(_ mediaList: [AniListMedia], isTemp: Bool) throws {
        let context = CoreDataService.sharedCoreDataService.mainQueueContext
        let fetchRequest = NSFetchRequest<Animes>(entityName: Animes.entityName)
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: "animeAnilistId", ascending: true)]
        fetchRequest.predicate = NSPredicate(format: "animeStatus == %@", "RELEASING")
        let fetchedAnimes = (try? context.fetch(fetchRequest)) ?? []

        NotificationCenter.default.post(name: NSNotification.Name(AniListClient.LocalAnimeWillUpdateNotification), object: self)

        for media in mediaList {
            guard let anilistId = media.id else { continue }
            var targetAnime: Animes
            if let foundIndex = fetchedAnimes.firstIndex(where: { $0.animeAnilistId?.intValue == anilistId }) {
                targetAnime = fetchedAnimes[foundIndex]
            } else {
                guard let newAnime = NSEntityDescription.insertNewObject(forEntityName: Animes.entityName, into: context) as? Animes else { continue }
                targetAnime = newAnime
                targetAnime.animeAnilistId = NSNumber(value: anilistId)
            }
            targetAnime.animeImgL = media.coverImage?.large
            targetAnime.animeImgM = media.coverImage?.medium
            targetAnime.animeImgS = media.bannerImage
            targetAnime.animePopularity = media.popularity.map { NSNumber(value: $0) }
            targetAnime.animeScore = media.averageScore.map { NSNumber(value: $0) }
            targetAnime.animeStatus = media.status
            targetAnime.animeTitleEnglish = media.title?.english ?? media.title?.romaji
            targetAnime.animeTitleJapanese = media.title?.romaji
            targetAnime.animeTotalEps = media.episodes.map { NSNumber(value: $0) }
            targetAnime.animeDescription = AniListUtil.stripHTML(media.description ?? "")
            targetAnime.animeNextEps = media.nextAiringEpisode?.episode.map { NSNumber(value: $0) }
            if let timeUntilAiring = media.nextAiringEpisode?.timeUntilAiring {
                targetAnime.animeNextEpsTime = Date(timeIntervalSinceNow: Double(timeUntilAiring))
            }
            targetAnime.animeFlagTemp = NSNumber(value: isTemp)
            targetAnime.animeOrder = NSNumber(value: insertIndexForTempEntries)
            insertIndexForTempEntries += 1
        }

        do {
            try context.save()
        } catch {
            print("Error saving new anime information")
            throw AniListError.errorSavingCoreData
        }

        NotificationCenter.default.post(name: NSNotification.Name(AniListClient.LocalAnimeDidUpdateNotification), object: self)
    }

    func ClearTempAnimes() {
        let context = CoreDataService.sharedCoreDataService.mainQueueContext
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: Animes.entityName)
        request.predicate = NSPredicate(format: "animeFlagTemp == YES")
        context.deleteAllData(request)
        insertIndexForTempEntries = 0
    }

    // MARK: - Banner (banner.svelte)

    func fetchBannerItems(completion: @escaping ([AnimeItem]) -> Void) {
        guard let url = URL(string: graphQLEndpoint) else { completion([]); return }
        let season = AniListUtil.currentSeason()
        let year = AniListUtil.currentYear()
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        var variables: [String: Any] = [
            "sort": ["SCORE_DESC"],
            "season": season,
            "seasonYear": year,
            "statusNot": ["NOT_YET_RELEASED"]
        ]
        if let nsfw = AniListUtil.nsfwGenreFilter { variables["nsfw"] = nsfw }
        let body: [String: Any] = ["query": AniListQueries.banner, "variables": variables]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data = data,
                  let response = try? JSONDecoder().decode(AniListResponse.self, from: data),
                  let mediaList = response.data?.Page?.media else {
                DispatchQueue.main.async { completion([]) }
                return
            }
            let items = mediaList.compactMap { AniListUtil.animeItem(from: $0) }
            DispatchQueue.main.async { completion(items) }
        }.resume()
    }

    // MARK: - Home sections (home/+page.svelte)

    func fetchHomeSections(completion: @escaping ([HomeSectionData]) -> Void) {
        let season = AniListUtil.currentSeason()
        let year = AniListUtil.currentYear()
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
        let syncQueue = DispatchQueue(label: "com.hayase.homeSections")
        var results = [HomeSectionData?](repeating: nil, count: configs.count)

        for (index, config) in configs.enumerated() {
            group.enter()
            fetchSectionItems(variables: config.variables) { items in
                var sectionData = HomeSectionData(title: config.title, items: items)
                sectionData.filterGenre = config.variables["genre"] as? String
                sectionData.filterSort = (config.variables["sort"] as? [String])?.first
                syncQueue.sync { results[index] = sectionData }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            completion(results.compactMap { $0 })
        }
    }

    func fetchFollowingMany(animeIDs: [Int], completion: @escaping ([Int: [AniListUserSummary]]) -> Void) {
        guard TrackerAccountManager.shared.isLoggedIn(.anilist),
              let viewerStr = TrackerAccountManager.shared.viewer(for: .anilist)?.id,
              let viewerID = Int(viewerStr) else {
            completion([:]); return
        }
        let ids = Array(Set(animeIDs)).sorted()
        guard !ids.isEmpty, let url = URL(string: graphQLEndpoint) else {
            completion([:]); return
        }
        let key = ids.map(String.init).joined(separator: ",")

        followingManyQueue.async { [weak self] in
            guard let self = self else { return }
            if let cached = self.followingManyCache[key], cached.viewerID == viewerID {
                DispatchQueue.main.async { completion(cached.usersByMediaID) }
                return
            }

            let alreadyFetching = self.followingManyCompletions[key] != nil
            self.followingManyCompletions[key, default: []].append(completion)
            if alreadyFetching { return }

            var request = self.authorizedRequest(url: url)
            request.httpBody = try? JSONSerialization.data(withJSONObject: [
                "query": AniListQueries.followingMany,
                "variables": ["ids": ids]
            ])

            URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
                guard let self = self else { return }
                if let error = error {
                    NSLog("[AniListClient] followingMany network error: %@", error.localizedDescription)
                }

                let usersByMediaID = self.parseFollowingMany(data: data, viewerID: viewerID)
                self.followingManyQueue.async {
                    let completions = self.followingManyCompletions.removeValue(forKey: key) ?? []
                    self.followingManyCache[key] = (viewerID: viewerID, usersByMediaID: usersByMediaID)
                    DispatchQueue.main.async {
                        completions.forEach { $0(usersByMediaID) }
                    }
                }
            }.resume()
        }
    }

    private func parseFollowingMany(data: Data?, viewerID: Int) -> [Int: [AniListUserSummary]] {
        guard let data = data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        if let errors = json["errors"] as? [[String: Any]] {
            let messages = errors.compactMap { $0["message"] as? String }
            NSLog("[AniListClient] followingMany GraphQL errors: %@", messages.joined(separator: ", "))
        }
        guard let dataObject = json["data"] as? [String: Any],
              let page = dataObject["Page"] as? [String: Any],
              let mediaList = page["mediaList"] as? [Any] else {
            return [:]
        }

        var usersByMediaID: [Int: [AniListUserSummary]] = [:]
        var seenPairs = Set<String>()
        for rawEntry in mediaList {
            guard let entry = rawEntry as? [String: Any] else { continue }
            guard let media = entry["media"] as? [String: Any],
                  let mediaID = media["id"] as? Int,
                  let user = entry["user"] as? [String: Any],
                  let userID = user["id"] as? Int,
                  userID != viewerID,
                  let name = user["name"] as? String else { continue }
            let pairKey = "\(mediaID):\(userID)"
            guard seenPairs.insert(pairKey).inserted else { continue }
            let avatar = (user["avatar"] as? [String: Any])?["large"] as? String
            usersByMediaID[mediaID, default: []].append(AniListUserSummary(id: userID,
                                                                           name: name,
                                                                           avatarURL: avatar))
        }
        return usersByMediaID
    }

    private func fetchSectionItems(variables: [String: Any], completion: @escaping ([AnimeItem]) -> Void) {
        guard let url = URL(string: graphQLEndpoint) else { completion([]); return }
        var request = authorizedRequest(url: url)
        var vars = variables
        if let nsfw = AniListUtil.nsfwGenreFilter { vars["nsfw"] = nsfw }
        var body: [String: Any] = ["query": AniListQueries.homeSection]
        body["variables"] = vars
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data = data,
                  let response = try? JSONDecoder().decode(AniListResponse.self, from: data),
                  let mediaList = response.data?.Page?.media else {
                completion([])
                return
            }
            let items = mediaList.compactMap { AniListUtil.animeItem(from: $0) }
            completion(items)
        }.resume()
    }

    // MARK: - Fetch by IDs

    func fetchSectionByIDs(_ ids: [Int], completion: @escaping ([AnimeItem]) -> Void) {
        guard !ids.isEmpty, let url = URL(string: graphQLEndpoint) else { completion([]); return }
        var request = authorizedRequest(url: url)
        let body: [String: Any] = ["query": AniListQueries.idIn, "variables": ["idIn": ids]]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data = data,
                  let response = try? JSONDecoder().decode(AniListResponse.self, from: data),
                  let mediaList = response.data?.Page?.media else {
                DispatchQueue.main.async { completion([]) }
                return
            }
            var itemMap: [Int: AnimeItem] = [:]
            for media in mediaList {
                if let item = AniListUtil.animeItem(from: media) {
                    itemMap[item.id] = item
                }
            }
            let ordered = ids.compactMap { itemMap[$0] }
            DispatchQueue.main.async { completion(ordered) }
        }.resume()
    }

    func fetchSectionByIDsFiltered(_ ids: [Int],
                                   status: [String]? = nil,
                                   onList: Bool? = nil,
                                   completion: @escaping ([AnimeItem]) -> Void) {
        guard !ids.isEmpty, let url = URL(string: graphQLEndpoint) else { completion([]); return }
        var request = authorizedRequest(url: url)
        var variables: [String: Any] = ["idIn": ids]
        if let status = status { variables["status"] = status }
        if let onList = onList { variables["onList"] = onList }
        let body: [String: Any] = ["query": AniListQueries.idInFiltered, "variables": variables]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data = data,
                  let response = try? JSONDecoder().decode(AniListResponse.self, from: data),
                  let mediaList = response.data?.Page?.media else {
                DispatchQueue.main.async { completion([]) }
                return
            }
            let items = mediaList.compactMap { AniListUtil.animeItem(from: $0) }
            DispatchQueue.main.async { completion(items) }
        }.resume()
    }

    // MARK: - Search (matches client.ts search())

    func searchAnimeItems(title: String?,
                          genres: [String],
                          formats: [String],
                          statuses: [String],
                          sort: String,
                          seasonYear: Int? = nil,
                          season: String? = nil,
                          page: Int,
                          completion: @escaping ([AnimeItem], Bool) -> Void) {
        guard let url = URL(string: graphQLEndpoint) else { completion([], false); return }
        var request = authorizedRequest(url: url)
        var variables: [String: Any] = ["sort": [sort], "page": page]
        if let t = title, !t.isEmpty { variables["search"] = t }
        if !genres.isEmpty   { variables["genre_in"] = genres }
        if !formats.isEmpty  { variables["format_in"] = formats }
        if !statuses.isEmpty { variables["status_in"] = statuses }
        if let y = seasonYear { variables["seasonYear"] = y }
        if let s = season { variables["season"] = s }
        if let nsfw = AniListUtil.nsfwGenreFilter { variables["nsfw"] = nsfw }
        let body: [String: Any] = ["query": AniListQueries.search, "variables": variables]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data = data,
                  let response = try? JSONDecoder().decode(AniListResponse.self, from: data),
                  let pageData = response.data?.Page else {
                DispatchQueue.main.async { completion([], false) }
                return
            }
            let hasNext = pageData.pageInfo?.hasNextPage ?? false
            let items = (pageData.media ?? []).compactMap { AniListUtil.animeItem(from: $0) }
            DispatchQueue.main.async { completion(items, hasNext) }
        }.resume()
    }

    // MARK: - Fetch by IDs (single / trace.moe)

    func fetchAnimeByIds(_ ids: [Int], completion: @escaping ([AnimeItem]) -> Void) {
        guard !ids.isEmpty, let url = URL(string: graphQLEndpoint) else { completion([]); return }
        var request = authorizedRequest(url: url)
        let body: [String: Any] = ["query": AniListQueries.byIds, "variables": ["ids": ids]]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data = data,
                  let response = try? JSONDecoder().decode(AniListResponse.self, from: data),
                  let pageData = response.data?.Page else {
                DispatchQueue.main.async { completion([]) }
                return
            }
            let items = (pageData.media ?? []).compactMap { AniListUtil.animeItem(from: $0) }
            DispatchQueue.main.async { completion(items) }
        }.resume()
    }

    // MARK: - Resolver search/fetch (player resolver.ts parity)

    func searchResolverAnimeIDs(titleGroups: [(key: String, titles: [String], year: Int?)],
                                completion: @escaping ([String: Int]) -> Void) {
        let flattened = titleGroups.flatMap { group -> [(key: String, title: String, year: Int?, isAdult: Bool)] in
            let titles = group.titles
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            guard !titles.isEmpty else { return [] }
            var objects = titles.map { (key: group.key, title: $0, year: group.year, isAdult: false) }
            if let last = objects.last {
                objects.append((key: last.key, title: last.title, year: last.year, isAdult: true))
            }
            return objects
        }
        guard !flattened.isEmpty, let url = URL(string: graphQLEndpoint) else {
            completion([:])
            return
        }

        var resultIDs: [String: Int] = [:]
        let chunks = stride(from: 0, to: flattened.count, by: 24).map {
            Array(flattened[$0..<min($0 + 24, flattened.count)])
        }

        func runChunk(at chunkIndex: Int) {
            guard chunkIndex < chunks.count else {
                DispatchQueue.main.async { completion(resultIDs) }
                return
            }

            let chunk = chunks[chunkIndex]
            let variableDefs = chunk.enumerated().map { "$v\($0.offset): String" }.joined(separator: ", ")
            let pages = chunk.enumerated().map { index, object in
                let yearPart = object.year.map { ", seasonYear: \($0)" } ?? ""
                return """
                v\(index): Page(perPage: 10) {
                  media(type: ANIME, search: $v\(index), status_in: [RELEASING, FINISHED], isAdult: \(object.isAdult)\(yearPart)) {
                    id
                    title { romaji english native }
                    startDate { year month day }
                    synonyms
                  }
                }
                """
            }.joined(separator: "\n")
            let query = """
            query(\(variableDefs)) {
              \(pages)
            }
            """

            var request = authorizedRequest(url: url)
            var variables: [String: Any] = [:]
            for (index, object) in chunk.enumerated() {
                variables["v\(index)"] = object.title
            }
            request.httpBody = try? JSONSerialization.data(withJSONObject: ["query": query, "variables": variables])

            URLSession.shared.dataTask(with: request) { data, _, _ in
                defer { runChunk(at: chunkIndex + 1) }
                guard let data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let dataObject = json["data"] as? [String: Any] else { return }

                for (index, titleObject) in chunk.enumerated() {
                    if resultIDs[titleObject.key] != nil { continue }
                    guard let page = dataObject["v\(index)"] as? [String: Any],
                          let mediaList = page["media"] as? [[String: Any]],
                          !mediaList.isEmpty,
                          let best = self.bestResolverSearchMedia(in: mediaList, title: titleObject.title),
                          let id = best["id"] as? Int else { continue }
                    resultIDs[titleObject.key] = id
                }
            }.resume()
        }

        runChunk(at: 0)
    }

    func fetchResolverMediaById(_ id: Int, completion: @escaping (AnimeItem?) -> Void) {
        guard let url = URL(string: graphQLEndpoint) else { completion(nil); return }
        var request = authorizedRequest(url: url)
        let body: [String: Any] = ["query": AniListQueries.resolverMediaById, "variables": ["id": id]]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data = data,
                  let response = try? JSONDecoder().decode(AniListResolverMediaResponse.self, from: data),
                  let media = response.data?.Media,
                  let item = AniListUtil.animeItem(from: media) else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            DispatchQueue.main.async { completion(item) }
        }.resume()
    }

    private func bestResolverSearchMedia(in mediaList: [[String: Any]], title: String) -> [String: Any]? {
        mediaList.min { lhs, rhs in
            let leftDistance = resolverTitleDistance(lhs, title: title)
            let rightDistance = resolverTitleDistance(rhs, title: title)
            if leftDistance == rightDistance {
                let leftDate = resolverStartDate(lhs)
                let rightDate = resolverStartDate(rhs)
                if leftDate != nil || rightDate != nil {
                    return (leftDate ?? Date()) <= (rightDate ?? Date())
                }
            }
            return leftDistance <= rightDistance
        }
    }

    private func resolverTitleDistance(_ media: [String: Any], title: String) -> Int {
        let target = title.lowercased()
        let titleObject = media["title"] as? [String: Any] ?? [:]
        let titleDistances = titleObject.values.compactMap { $0 as? String }
            .filter { !$0.isEmpty }
            .map { Self.levenshtein($0.lowercased(), target) }
        let synonymDistances = (media["synonyms"] as? [String] ?? [])
            .filter { !$0.isEmpty }
            .map { Self.levenshtein($0.lowercased(), target) + 2 }
        return (titleDistances + synonymDistances).min() ?? Int.max
    }

    private func resolverStartDate(_ media: [String: Any]) -> Date? {
        guard let startDate = media["startDate"] as? [String: Any],
              let year = startDate["year"] as? Int else { return nil }
        var components = DateComponents()
        components.year = year
        components.month = startDate["month"] as? Int ?? 1
        components.day = startDate["day"] as? Int ?? 1
        return Calendar(identifier: .gregorian).date(from: components)
    }

    private static func levenshtein(_ lhs: String, _ rhs: String) -> Int {
        let a = Array(lhs)
        let b = Array(rhs)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }

        var previous = Array(0...b.count)
        var current = Array(repeating: 0, count: b.count + 1)

        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
            }
            swap(&previous, &current)
        }

        return previous[b.count]
    }

    // MARK: - Detail (relations)

    func fetchDetailForItem(id: Int, completion: @escaping ([AnimeRelation]) -> Void) {
        guard let url = URL(string: graphQLEndpoint) else { completion([]); return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let body: [String: Any] = ["query": AniListQueries.detail, "variables": ["id": id]]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data = data,
                  let resp = try? JSONDecoder().decode(AniListDetailResponse.self, from: data),
                  let media = resp.data?.Media else {
                DispatchQueue.main.async { completion([]) }
                return
            }

            let relations: [AnimeRelation] = (media.relations?.edges ?? []).compactMap { edge -> AnimeRelation? in
                guard let type = edge.relationType, let node = edge.node, let nid = node.id else { return nil }
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
                    description: nil,
                    year: node.seasonYear,
                    season: node.season,
                    format: node.format,
                    coverColor: node.coverImage?.color)
                return AnimeRelation(relationType: type, media: relItem)
            }

            DispatchQueue.main.async { completion(relations) }
        }.resume()
    }

    // MARK: - Staff + Stats

    func fetchStaffAndStats(id: Int,
                            completion: @escaping ([AnimeStaffMember], [AnimeScorePoint], [AnimeStatusCount]) -> Void) {
        guard let url = URL(string: graphQLEndpoint) else { completion([], [], []); return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let body: [String: Any] = ["query": AniListQueries.staffStats, "variables": ["id": id]]
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

    // MARK: - Trailer + Genres

    func fetchTrailerAndGenres(id: Int, completion: @escaping (_ trailerYouTubeID: String?, _ genres: [String], _ malId: Int?) -> Void) {
        guard let url = URL(string: graphQLEndpoint) else { completion(nil, [], nil); return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["query": AniListQueries.trailerGenres, "variables": ["id": id]])
        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let media = ((json["data"] as? [String: Any])?["Media"]) as? [String: Any] else {
                DispatchQueue.main.async { completion(nil, [], nil) }
                return
            }
            let genres = media["genres"] as? [String] ?? []
            let malId = (media["idMal"] as? NSNumber)?.intValue
            var trailerID: String? = nil
            if let trailer = media["trailer"] as? [String: Any],
               (trailer["site"] as? String)?.lowercased() == "youtube" {
                trailerID = trailer["id"] as? String
            }
            DispatchQueue.main.async { completion(trailerID, genres, malId) }
        }.resume()
    }

    // MARK: - Forum threads (matches client.ts threads())

    func threads(mediaID: Int, completion: @escaping ([AniListThread]) -> Void) {
        guard let url = URL(string: graphQLEndpoint) else { completion([]); return }
        let body: [String: Any] = ["query": AniListQueries.threads, "variables": ["id": mediaID]]
        guard let data = try? JSONSerialization.data(withJSONObject: body) else {
            completion([]); return
        }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = data

        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let page = ((json["data"] as? [String: Any])?["Page"] as? [String: Any]),
                  let rawThreads = page["threads"] as? [[String: Any]] else {
                DispatchQueue.main.async { completion([]) }
                return
            }
            let parsed = rawThreads.compactMap { AniListThread(dict: $0) }
            DispatchQueue.main.async { completion(parsed) }
        }.resume()
    }

    // MARK: - Airing schedule

    func fetchAiringForMonth(_ month: Date, completion: @escaping ([AiringScheduleEntry]) -> Void) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC") ?? TimeZone(secondsFromGMT: 0)!
        let comps = cal.dateComponents([.year, .month], from: month)
        guard let monthStart = cal.date(from: comps),
              let monthEnd = cal.date(byAdding: DateComponents(month: 1), to: monthStart) else {
            completion([]); return
        }
        let from = Int(monthStart.timeIntervalSince1970)
        let to = Int(monthEnd.timeIntervalSince1970) - 1
        collectAiringPages(from: from, to: to, page: 1, accumulated: [], completion: completion)
    }

    private func collectAiringPages(from: Int, to: Int, page: Int,
                                    accumulated: [AiringScheduleEntry],
                                    completion: @escaping ([AiringScheduleEntry]) -> Void) {
        guard let url = URL(string: graphQLEndpoint) else { completion(accumulated); return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let body: [String: Any] = [
            "query": AniListQueries.airingMonth,
            "variables": ["from": from, "to": to, "page": page]
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
            guard let self = self,
                  let data = data,
                  let resp = try? JSONDecoder().decode(AiringSchedulePagedResponse.self, from: data),
                  let pageData = resp.data?.Page else {
                DispatchQueue.main.async { completion(accumulated) }
                return
            }
            let entries: [AiringScheduleEntry] = (pageData.airingSchedules ?? []).compactMap { sched in
                guard let epNum = sched.episode,
                      let atUnix = sched.airingAt,
                      let media = sched.media,
                      let id = media.id else { return nil }
                let item = AnimeItem(
                    id: id,
                    titleEnglish: media.title?.english,
                    titleRomaji: media.title?.romaji,
                    coverURL: media.coverImage?.large,
                    score: media.averageScore,
                    status: media.status,
                    episodes: media.episodes,
                    bannerURL: nil,
                    genres: [],
                    description: nil,
                    coverColor: media.coverImage?.color)
                return AiringScheduleEntry(
                    episode: epNum,
                    airingAt: Date(timeIntervalSince1970: Double(atUnix)),
                    media: item)
            }
            let all = accumulated + entries
            if pageData.pageInfo?.hasNextPage == true {
                self.collectAiringPages(from: from, to: to, page: page + 1, accumulated: all, completion: completion)
            } else {
                DispatchQueue.main.async { completion(all) }
            }
        }.resume()
    }

    // MARK: - Per-media airing schedule

    func fetchMediaAiringSchedule(anilistID: Int, completion: @escaping (MediaScheduleResult?) -> Void) {
        guard let url = URL(string: graphQLEndpoint) else { completion(nil); return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let body: [String: Any] = ["query": AniListQueries.mediaSchedule, "variables": ["id": anilistID]]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data = data,
                  let resp = try? JSONDecoder().decode(MediaScheduleResponse.self, from: data),
                  let media = resp.data?.Media else {
                completion(nil)
                return
            }

            var schedule: [Int: Date] = [:]
            let allNodes = (media.aired?.n ?? []) + (media.notaired?.n ?? [])
            for node in allNodes {
                guard let ep = node.e, let at = node.a else { continue }
                if schedule[ep] == nil {
                    schedule[ep] = Date(timeIntervalSince1970: Double(at))
                }
            }

            let sd = media.startDate.map { ($0.year, $0.month, $0.day) }
            completion(MediaScheduleResult(schedule: schedule, startDate: sd, episodeCount: media.episodes))
        }.resume()
    }

    // MARK: - ani.zip image cache (Fanart + Clearlogo)

    private static var _fanartURLs:      [Int: String] = [:]
    private static var _clearlogoURLs:   [Int: String] = [:]
    private static var _fanartFetched:   Set<Int>      = []
    private static var _fanartCallbacks: [Int: [(String?) -> Void]] = [:]
    private static let _fanartQueue = DispatchQueue(label: "com.hayase.fanartcache", attributes: .concurrent)

    static func fetchFanartURL(anilistID: Int, completion: @escaping (String?) -> Void) {
        _fanartQueue.async(flags: .barrier) {
            if _fanartFetched.contains(anilistID) {
                let url = _fanartURLs[anilistID]
                DispatchQueue.main.async { completion(url) }
                return
            }
            if _fanartCallbacks[anilistID] != nil {
                _fanartCallbacks[anilistID]?.append(completion)
                return
            }
            _fanartCallbacks[anilistID] = [completion]
            _fetchAniZipImages(anilistID: anilistID)
        }
    }

    static func fetchClearlogoURL(anilistID: Int, completion: @escaping (String?) -> Void) {
        _fanartQueue.async(flags: .barrier) {
            if _fanartFetched.contains(anilistID) {
                let url = _clearlogoURLs[anilistID]
                DispatchQueue.main.async { completion(url) }
                return
            }
            if _fanartCallbacks[anilistID] != nil {
                _fanartCallbacks[anilistID]?.append({ _ in
                    _fanartQueue.async {
                        let url = _clearlogoURLs[anilistID]
                        DispatchQueue.main.async { completion(url) }
                    }
                })
                return
            }
            _fanartCallbacks[anilistID] = [{ _ in
                _fanartQueue.async {
                    let url = _clearlogoURLs[anilistID]
                    DispatchQueue.main.async { completion(url) }
                }
            }]
            _fetchAniZipImages(anilistID: anilistID)
        }
    }

    private static func _fetchAniZipImages(anilistID: Int) {
        var comps = URLComponents(string: "https://api.ani.zip/mappings")
        comps?.queryItems = [URLQueryItem(name: "anilist_id", value: String(anilistID))]
        guard let url = comps?.url else {
            _fanartQueue.async(flags: .barrier) {
                let cbs = _fanartCallbacks.removeValue(forKey: anilistID) ?? []
                _fanartFetched.insert(anilistID)
                cbs.forEach { cb in DispatchQueue.main.async { cb(nil) } }
            }
            return
        }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: req) { data, _, _ in
            var fanartURL: String? = nil
            var clearlogoURL: String? = nil
            if let data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let images = json["images"] as? [[String: Any]] {
                fanartURL = images.first(where: { ($0["coverType"] as? String) == "Fanart" })?["url"] as? String
                           ?? images.first(where: { ($0["coverType"] as? String) == "Poster" })?["url"] as? String
                clearlogoURL = images.first(where: { ($0["coverType"] as? String) == "Clearlogo" })?["url"] as? String
            }
            _fanartQueue.async(flags: .barrier) {
                let cbs = _fanartCallbacks.removeValue(forKey: anilistID) ?? []
                _fanartFetched.insert(anilistID)
                if let fanartURL { _fanartURLs[anilistID] = fanartURL }
                if let clearlogoURL { _clearlogoURLs[anilistID] = clearlogoURL }
                cbs.forEach { cb in DispatchQueue.main.async { cb(fanartURL) } }
            }
        }.resume()
    }
}
