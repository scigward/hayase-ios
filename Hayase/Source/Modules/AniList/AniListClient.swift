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
    private let requestExecutor = AniListRequestExecutor.shared
    private let followingManyQueue = DispatchQueue(label: "com.hayase.anilist.followingMany")
    private var followingManyCache: [String: (viewerID: Int, usersByMediaID: [Int: [AniListUserSummary]])] = [:]
    private var followingManyCompletions: [String: [([Int: [AniListUserSummary]]) -> Void]] = [:]

    private let fullMediaQueue = DispatchQueue(label: "com.hayase.anilist.fullMedia")
    private var fullMediaCache: [Int: AnimeItem] = [:]
    private var fullMediaCompletions: [Int: [(AnimeItem?) -> Void]] = [:]

    private let animePageQueue = DispatchQueue(label: "com.hayase.anilist.animePage")
    private var animePageCache: [String: AnimePagePayload] = [:]
    private var animePageCompletions: [String: [(Result<AnimePagePayload, AniListRequestError>) -> Void]] = [:]

    private let animePageFollowingQueue = DispatchQueue(label: "com.hayase.anilist.animePageFollowing")
    private var animePageFollowingCache: [String: [AniListFollowingEntry]] = [:]
    private var animePageFollowingCompletions: [String: [([AniListFollowingEntry]) -> Void]] = [:]

    private let queryCacheQueue = DispatchQueue(label: "com.hayase.anilist.queryCache")
    private var bannerCache: [AnimeItem]?
    private var homeSectionItemCache: [String: [AnimeItem]] = [:]
    private var searchPageCache: [String: AniListSearchPage] = [:]

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

    private func graphQLRequest(query: String,
                                variables: [String: Any]? = nil,
                                completion: @escaping (Result<[AniListMedia], AniListRequestError>) -> Void) {
        guard let url = URL(string: graphQLEndpoint) else {
            completion(.failure(.invalidEndpoint))
            return
        }
        var request = authorizedRequest(url: url)
        var body: [String: Any] = ["query": query]
        if let variables = variables { body["variables"] = variables }
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            completion(.failure(.encodingFailed(error)))
            return
        }

        performAniListRequest(request, context: "AniListLegacy") { result in
            switch result {
            case .success(let data):
                guard let response = try? JSONDecoder().decode(AniListResponse.self, from: data),
                      let mediaList = response.data?.Page?.media,
                      !mediaList.isEmpty else {
                    completion(.failure(.emptyData))
                    return
                }
                completion(.success(mediaList))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    private func postLocalAnimeUpdateFailure(_ error: Error) {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: NSNotification.Name(AniListClient.LocalAnimeUpdateFailedNotification),
                                            object: error as NSError)
        }
    }

    /// Adds an auth header whenever a valid AniList token exists.
    /// Interface stores the token before the viewer query resolves, so the
    /// native client must not wait for persisted viewer metadata to attach auth.
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

    @discardableResult
    private func performAniListRequest(_ request: URLRequest,
                                       context: String,
                                       completion: @escaping (Result<Data, AniListRequestError>) -> Void) -> AniListRequestToken {
        requestExecutor.perform(request, context: context, completion: completion)
    }

    private func dataOrLog(_ result: Result<Data, AniListRequestError>,
                           context: String) -> Data? {
        switch result {
        case .success(let data):
            return data
        case .failure(let error):
            if case .cancelled = error { return nil }
            NSLog("[AniListClient] %@ failed: %@", context, error.description)
            return nil
        }
    }

    @discardableResult
    private func performAniListDataTask(_ request: URLRequest,
                                        context: String,
                                        completion: @escaping (Data?, URLResponse?, Error?) -> Void) -> AniListRequestToken {
        performAniListRequest(request, context: context) { result in
            switch result {
            case .success(let data):
                completion(data, nil, nil)
            case .failure(let error):
                if case .cancelled = error {
                    completion(nil, nil, error)
                    return
                }
                NSLog("[AniListClient] %@ failed: %@", context, error.description)
                completion(nil, nil, error)
            }
        }
    }

    private var aniListViewerID: Int? {
        guard let rawID = TrackerAccountManager.shared.viewer(for: .anilist)?.id else { return nil }
        return Int(rawID)
    }

    private var hasValidAniListToken: Bool {
        TrackerAccountManager.shared.token(for: .anilist) != nil
    }

    private var aniListCacheScope: String {
        if let viewerID = aniListViewerID {
            return "viewer:\(viewerID)"
        }
        if hasValidAniListToken {
            // Interface attaches auth as soon as the token exists, before the viewer
            // query resolves. Keep those authenticated responses out of public cache.
            return "viewer:pending"
        }
        return "public"
    }

    private func animePageCacheKey(for id: Int) -> String {
        "\(id):\(aniListCacheScope)"
    }

    private func cacheKey(prefix: String, variables: [String: Any]) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: variables, options: [.sortedKeys])) ?? Data()
        let variablesString = String(data: data, encoding: .utf8) ?? "{}"
        return "\(prefix)|\(aniListCacheScope)|\(variablesString)"
    }

    private func applyNsfwFilter(to variables: [String: Any]) -> [String: Any] {
        var variables = variables
        if let nsfw = AniListUtil.nsfwGenreFilter { variables["nsfw"] = nsfw }
        return variables
    }

    private func parseCustomLists(_ rawLists: Any?) -> [String] {
        if let names = rawLists as? [String] { return names }
        let objects = rawLists as? [[String: Any]] ?? []
        return objects.compactMap { object in
            guard object["enabled"] as? Bool ?? false else { return nil }
            return object["name"] as? String
        }
    }

    // MARK: - CoreData (legacy, iOS-specific)

    func UpdateTempWithAiringAnimes() {
        ClearTempAnimes()
        var variables: [String: Any] = [:]
        if let nsfw = AniListUtil.nsfwGenreFilter { variables["nsfw"] = nsfw }
        graphQLRequest(query: AniListQueries.airingAnime, variables: variables.isEmpty ? nil : variables) { result in
            switch result {
            case .success(let mediaList):
                DispatchQueue.main.async {
                    do {
                        try self.UpdateLocalAnimes(mediaList, isTemp: true)
                    } catch let error {
                        self.postLocalAnimeUpdateFailure(error)
                    }
                }
            case .failure(let error):
                self.postLocalAnimeUpdateFailure(error)
            }
        }
    }

    func UpdateTempAnimesWithSearchString(_ searchStr: String) {
        ClearTempAnimes()
        var variables: [String: Any] = ["search": searchStr]
        if let nsfw = AniListUtil.nsfwGenreFilter { variables["nsfw"] = nsfw }
        graphQLRequest(query: AniListQueries.searchLegacy, variables: variables) { result in
            switch result {
            case .success(let mediaList):
                DispatchQueue.main.async {
                    do {
                        try self.UpdateLocalAnimes(mediaList, isTemp: true)
                    } catch let error {
                        self.postLocalAnimeUpdateFailure(error)
                    }
                }
            case .failure(let error):
                self.postLocalAnimeUpdateFailure(error)
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
        fetchBannerItemsResult(policy: .cacheAndNetwork) { result in
            switch result {
            case .success(let items): completion(items)
            case .failure: completion([])
            }
        }
    }

    @discardableResult
    func fetchBannerItemsResult(policy: AniListRequestPolicy = .cacheAndNetwork,
                                query: PageQuery<[AnimeItem]>? = nil,
                                completion: @escaping (Result<[AnimeItem], AniListRequestError>) -> Void) -> AniListRequestToken? {
        let season = AniListUtil.currentSeason()
        let year = AniListUtil.currentYear()
        let variables = applyNsfwFilter(to: [
            "sort": ["SCORE_DESC"],
            "perPage": 15,
            "season": season,
            "seasonYear": year,
            "statusNot": ["NOT_YET_RELEASED"]
        ])

        if policy != .networkOnly, let cached = queryCacheQueue.sync(execute: { bannerCache }) {
            query?.setSuccess(cached, isEmpty: cached.isEmpty)
            completion(.success(cached))
            if policy == .cacheFirst { return nil }
        }
        guard policy != .pausedUntilVisible else { return nil }

        query?.setFetching()
        let token = requestExecutor.execute(query: AniListQueries.search,
                                            variables: variables,
                                            authorized: true,
                                            dedupeKey: cacheKey(prefix: "search", variables: variables)) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let graphQLResult):
                do {
                    let response = try JSONDecoder().decode(AniListResponse.self, from: graphQLResult.data)
                    let items = (response.data?.Page?.media ?? []).compactMap { AniListUtil.animeItem(from: $0) }
                    self.queryCacheQueue.async { self.bannerCache = items }
                    query?.setSuccess(items, isEmpty: items.isEmpty)
                    DispatchQueue.main.async { completion(.success(items)) }
                } catch {
                    query?.setFailure(AniListRequestError.invalidJSON)
                    DispatchQueue.main.async { completion(.failure(.invalidJSON)) }
                }
            case .failure(let error):
                query?.setFailure(error)
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
        query?.attach(token)
        return token
    }

    // MARK: - Home sections (home/+page.svelte)

    func homeSectionDefinitions() -> [AniListHomeSectionDefinition] {
        let season = AniListUtil.currentSeason()
        let year = AniListUtil.currentYear()
        return [
            AniListHomeSectionDefinition(id: "home.popular-season",
                                         title: "Popular This Season",
                                         variables: ["sort": ["POPULARITY_DESC"], "season": season, "seasonYear": year],
                                         startsPaused: true),
            AniListHomeSectionDefinition(id: "home.trending",
                                         title: "Trending Now",
                                         variables: ["sort": ["TRENDING_DESC"]],
                                         startsPaused: true),
            AniListHomeSectionDefinition(id: "home.all-time-popular",
                                         title: "All Time Popular",
                                         variables: ["sort": ["POPULARITY_DESC"]],
                                         startsPaused: true),
            AniListHomeSectionDefinition(id: "home.romance",
                                         title: "Romance",
                                         variables: ["sort": ["TRENDING_DESC"], "genre": ["Romance"]],
                                         startsPaused: true),
            AniListHomeSectionDefinition(id: "home.action",
                                         title: "Action",
                                         variables: ["sort": ["TRENDING_DESC"], "genre": ["Action"]],
                                         startsPaused: true),
            AniListHomeSectionDefinition(id: "home.adventure",
                                         title: "Adventure",
                                         variables: ["sort": ["TRENDING_DESC"], "genre": ["Adventure"]],
                                         startsPaused: true),
            AniListHomeSectionDefinition(id: "home.fantasy",
                                         title: "Fantasy",
                                         variables: ["sort": ["TRENDING_DESC"], "genre": ["Fantasy"]],
                                         startsPaused: true),
        ]
    }

    @discardableResult
    func fetchHomeSectionResult(definition: AniListHomeSectionDefinition,
                                policy: AniListRequestPolicy = .cacheAndNetwork,
                                query: PageQuery<HomeSectionData>? = nil,
                                completion: @escaping (Result<HomeSectionData, AniListRequestError>) -> Void) -> AniListRequestToken? {
        if policy == .pausedUntilVisible {
            query?.preparePaused { [weak self, weak query] in
                self?.fetchHomeSectionResult(definition: definition,
                                             policy: .cacheAndNetwork,
                                             query: query,
                                             completion: completion)
            }
            return nil
        }

        let vars = applyNsfwFilter(to: definition.variables)
        let key = cacheKey(prefix: "search", variables: vars)
        let cachedItems = queryCacheQueue.sync { homeSectionItemCache[key] }
        let cachedSection = cachedItems.map {
            makeHomeSectionData(definition: definition,
                                items: $0,
                                state: $0.isEmpty ? .empty : .loaded)
        }

        if policy != .networkOnly, let cachedSection {
            query?.setSuccess(cachedSection, isEmpty: cachedSection.items.isEmpty)
            completion(.success(cachedSection))
            if policy == .cacheFirst { return nil }
        }

        query?.setFetching(previous: cachedSection)
        let token = requestExecutor.execute(query: AniListQueries.search,
                                            variables: vars,
                                            authorized: true,
                                            dedupeKey: key) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let graphQLResult):
                do {
                    let response = try JSONDecoder().decode(AniListResponse.self, from: graphQLResult.data)
                    guard let mediaList = response.data?.Page?.media else {
                        query?.setFailure(AniListRequestError.emptyData, previous: cachedSection)
                        DispatchQueue.main.async { completion(.failure(.emptyData)) }
                        return
                    }
                    let items = mediaList.compactMap { AniListUtil.animeItem(from: $0) }
                    let section = self.makeHomeSectionData(definition: definition,
                                                           items: items,
                                                           state: items.isEmpty ? .empty : .loaded)
                    self.queryCacheQueue.async { self.homeSectionItemCache[key] = items }
                    query?.setSuccess(section, isEmpty: items.isEmpty)
                    DispatchQueue.main.async { completion(.success(section)) }
                } catch {
                    query?.setFailure(AniListRequestError.invalidJSON, previous: cachedSection)
                    DispatchQueue.main.async { completion(.failure(.invalidJSON)) }
                }
            case .failure(let error):
                query?.setFailure(error, previous: cachedSection)
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
        query?.attach(token)
        return token
    }

    private func makeHomeSectionData(definition: AniListHomeSectionDefinition,
                                     items: [AnimeItem],
                                     state: HomeSectionContentState = .loaded) -> HomeSectionData {
        var section = HomeSectionData(title: definition.title, items: items)
        section.queryID = definition.id
        section.contentState = state
        section.filterGenre = (definition.variables["genre"] as? [String])?.first
        section.filterSort = (definition.variables["sort"] as? [String])?.first
        section.filterSeason = definition.variables["season"] as? String
        section.filterYear = (definition.variables["seasonYear"] as? Int).map(String.init)
        section.filterFormats = definition.variables["format"] as? [String] ?? []
        return section
    }

    // Home sections are intentionally fetched independently through PageQuery-backed
    // section descriptors. Interface's QueryCard rows are visibility-resumed stores,
    // so there must not be a grouped API here that can wake every Home section at once.

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

            performAniListDataTask(request, context: "AniList") { [weak self] data, _, error in
                guard let self = self else { return }
                if let error = error {
                    NSLog("[AniListClient] followingMany network error: %@", error.localizedDescription)
                }

                guard error == nil, data != nil else {
                    self.followingManyQueue.async {
                        let completions = self.followingManyCompletions.removeValue(forKey: key) ?? []
                        DispatchQueue.main.async { completions.forEach { $0([:]) } }
                    }
                    return
                }

                let usersByMediaID = self.parseFollowingMany(data: data, viewerID: viewerID)
                self.followingManyQueue.async {
                    let completions = self.followingManyCompletions.removeValue(forKey: key) ?? []
                    self.followingManyCache[key] = (viewerID: viewerID, usersByMediaID: usersByMediaID)
                    DispatchQueue.main.async {
                        completions.forEach { $0(usersByMediaID) }
                    }
                }
            }
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
        fetchSectionItemsResult(variables: variables, policy: .cacheAndNetwork) { result in
            switch result {
            case .success(let items): completion(items)
            case .failure: completion([])
            }
        }
    }

    @discardableResult
    private func fetchSectionItemsResult(variables: [String: Any],
                                         policy: AniListRequestPolicy,
                                         completion: @escaping (Result<[AnimeItem], AniListRequestError>) -> Void) -> AniListRequestToken? {
        let vars = applyNsfwFilter(to: variables)
        let key = cacheKey(prefix: "search", variables: vars)

        if policy != .networkOnly, let cached = queryCacheQueue.sync(execute: { homeSectionItemCache[key] }) {
            completion(.success(cached))
            if policy == .cacheFirst { return nil }
        }
        guard policy != .pausedUntilVisible else { return nil }

        return requestExecutor.execute(query: AniListQueries.search,
                                       variables: vars,
                                       authorized: true,
                                       dedupeKey: key) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let graphQLResult):
                do {
                    let response = try JSONDecoder().decode(AniListResponse.self, from: graphQLResult.data)
                    guard let mediaList = response.data?.Page?.media else {
                        DispatchQueue.main.async { completion(.failure(.emptyData)) }
                        return
                    }
                    let items = mediaList.compactMap { AniListUtil.animeItem(from: $0) }
                    self.queryCacheQueue.async { self.homeSectionItemCache[key] = items }
                    DispatchQueue.main.async { completion(.success(items)) }
                } catch {
                    DispatchQueue.main.async { completion(.failure(.invalidJSON)) }
                }
            case .failure(let error):
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    // MARK: - Fetch by IDs

    func fetchSectionByIDs(_ ids: [Int], completion: @escaping ([AnimeItem]) -> Void) {
        fetchSectionByIDsResult(ids) { result in
            switch result {
            case .success(let items): completion(items)
            case .failure(let error):
                NSLog("[AniListClient] fetchSectionByIDs failed: %@", error.description)
                completion([])
            }
        }
    }

    @discardableResult
    func fetchSectionByIDsResult(_ ids: [Int],
                                 completion: @escaping (Result<[AnimeItem], AniListRequestError>) -> Void) -> AniListRequestToken? {
        guard !ids.isEmpty else {
            DispatchQueue.main.async { completion(.success([])) }
            return nil
        }
        let variables = applyNsfwFilter(to: ["idIn": ids])
        return requestExecutor.execute(query: AniListQueries.idIn,
                                       variables: variables,
                                       authorized: true,
                                       dedupeKey: cacheKey(prefix: "search", variables: variables)) { result in
            switch result {
            case .success(let graphQLResult):
                do {
                    let response = try JSONDecoder().decode(AniListResponse.self, from: graphQLResult.data)
                    guard let mediaList = response.data?.Page?.media else {
                        DispatchQueue.main.async { completion(.failure(.emptyData)) }
                        return
                    }
                    var itemMap: [Int: AnimeItem] = [:]
                    for media in mediaList {
                        if let item = AniListUtil.animeItem(from: media) {
                            itemMap[item.id] = item
                        }
                    }
                    let ordered = ids.compactMap { itemMap[$0] }
                    DispatchQueue.main.async { completion(.success(ordered)) }
                } catch {
                    DispatchQueue.main.async { completion(.failure(.invalidJSON)) }
                }
            case .failure(let error):
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    func fetchSectionByIDsFiltered(_ ids: [Int],
                                   status: [String]? = nil,
                                   onList: Bool? = nil,
                                   sort: [String]? = nil,
                                   completion: @escaping ([AnimeItem]) -> Void) {
        fetchSectionByIDsFilteredResult(ids, status: status, onList: onList, sort: sort) { result in
            switch result {
            case .success(let items): completion(items)
            case .failure(let error):
                NSLog("[AniListClient] fetchSectionByIDsFiltered failed: %@", error.description)
                completion([])
            }
        }
    }

    @discardableResult
    func fetchSectionByIDsFilteredResult(_ ids: [Int],
                                         status: [String]? = nil,
                                         onList: Bool? = nil,
                                         sort: [String]? = nil,
                                         completion: @escaping (Result<[AnimeItem], AniListRequestError>) -> Void) -> AniListRequestToken? {
        guard !ids.isEmpty else {
            DispatchQueue.main.async { completion(.success([])) }
            return nil
        }
        var variables: [String: Any] = ["idIn": ids]
        if let status { variables["status"] = status }
        if let onList { variables["onList"] = onList }
        if let sort { variables["sort"] = sort }
        variables = applyNsfwFilter(to: variables)
        return requestExecutor.execute(query: AniListQueries.idInFiltered,
                                       variables: variables,
                                       authorized: true,
                                       dedupeKey: cacheKey(prefix: "search", variables: variables)) { result in
            switch result {
            case .success(let graphQLResult):
                do {
                    let response = try JSONDecoder().decode(AniListResponse.self, from: graphQLResult.data)
                    guard let mediaList = response.data?.Page?.media else {
                        DispatchQueue.main.async { completion(.failure(.emptyData)) }
                        return
                    }
                    let items = mediaList.compactMap { AniListUtil.animeItem(from: $0) }
                    DispatchQueue.main.async { completion(.success(items)) }
                } catch {
                    DispatchQueue.main.async { completion(.failure(.invalidJSON)) }
                }
            case .failure(let error):
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    // MARK: - Search (matches client.ts search())

    @discardableResult
    func searchAnimeItems(title: String?,
                          genres: [String],
                          tags: [String] = [],
                          formats: [String],
                          statuses: [String],
                          statusNot: [String] = [],
                          sort: String?,
                          seasonYear: Int? = nil,
                          season: String? = nil,
                          isAdult: Bool? = nil,
                          onList: Bool? = nil,
                          ids: [Int]? = nil,
                          perPage: Int? = nil,
                          page: Int,
                          completion: @escaping ([AnimeItem], Bool) -> Void) -> AniListRequestToken? {
        searchAnimeItemsPage(title: title,
                             genres: genres,
                             tags: tags,
                             formats: formats,
                             statuses: statuses,
                             statusNot: statusNot,
                             sort: sort,
                             seasonYear: seasonYear,
                             season: season,
                             isAdult: isAdult,
                             onList: onList,
                             ids: ids,
                             perPage: perPage,
                             page: page) { result in
            switch result {
            case .success(let page): completion(page.items, page.hasNextPage)
            case .failure: completion([], false)
            }
        }
    }

    @discardableResult
    func searchAnimeItemsPage(title: String?,
                              genres: [String],
                              tags: [String] = [],
                              formats: [String],
                              statuses: [String],
                              statusNot: [String] = [],
                              sort: String?,
                              seasonYear: Int? = nil,
                              season: String? = nil,
                              isAdult: Bool? = nil,
                              onList: Bool? = nil,
                              ids: [Int]? = nil,
                              perPage: Int? = nil,
                              page: Int? = nil,
                              policy: AniListRequestPolicy = .cacheAndNetwork,
                              query: PageQuery<AniListSearchPage>? = nil,
                              completion: @escaping (Result<AniListSearchPage, AniListRequestError>) -> Void) -> AniListRequestToken? {
        var variables: [String: Any] = [:]
        if let page { variables["page"] = page }
        if let sort { variables["sort"] = [sort] }
        if let perPage { variables["perPage"] = perPage }
        if let t = title, !t.isEmpty { variables["search"] = t }
        if !genres.isEmpty { variables["genre"] = genres }
        if !tags.isEmpty { variables["tag"] = tags }
        if !formats.isEmpty { variables["format"] = formats }
        if !statuses.isEmpty { variables["status"] = statuses }
        if !statusNot.isEmpty { variables["statusNot"] = statusNot }
        if let y = seasonYear { variables["seasonYear"] = y }
        if let s = season { variables["season"] = s }
        if let isAdult = isAdult { variables["isAdult"] = isAdult }
        if let onList = onList { variables["onList"] = onList }
        if let ids = ids, !ids.isEmpty { variables["ids"] = ids }
        variables = applyNsfwFilter(to: variables)

        let key = cacheKey(prefix: "search", variables: variables)
        if policy != .networkOnly, let cached = queryCacheQueue.sync(execute: { searchPageCache[key] }) {
            query?.setSuccess(cached, isEmpty: cached.items.isEmpty)
            completion(.success(AniListSearchPage(items: cached.items,
                                                  hasNextPage: cached.hasNextPage,
                                                  isCacheResult: policy == .cacheAndNetwork)))
            if policy == .cacheFirst { return nil }
        }
        guard policy != .pausedUntilVisible else { return nil }

        query?.setFetching()
        let token = requestExecutor.execute(query: AniListQueries.search,
                                            variables: variables,
                                            authorized: true,
                                            dedupeKey: key) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let graphQLResult):
                do {
                    let response = try JSONDecoder().decode(AniListResponse.self, from: graphQLResult.data)
                    guard let pageData = response.data?.Page else {
                        query?.setFailure(AniListRequestError.emptyData)
                        DispatchQueue.main.async { completion(.failure(.emptyData)) }
                        return
                    }
                    let searchPage = AniListSearchPage(
                        items: (pageData.media ?? []).compactMap { AniListUtil.animeItem(from: $0) },
                        hasNextPage: pageData.pageInfo?.hasNextPage ?? false)
                    self.queryCacheQueue.async { self.searchPageCache[key] = searchPage }
                    query?.setSuccess(searchPage, isEmpty: searchPage.items.isEmpty)
                    DispatchQueue.main.async { completion(.success(searchPage)) }
                } catch {
                    query?.setFailure(AniListRequestError.invalidJSON)
                    DispatchQueue.main.async { completion(.failure(.invalidJSON)) }
                }
            case .failure(let error):
                query?.setFailure(error)
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
        query?.attach(token)
        return token
    }

    // MARK: - Fetch by IDs (single / trace.moe)

    func fetchAnimeByIds(_ ids: [Int], completion: @escaping ([AnimeItem]) -> Void) {
        fetchAnimeByIdsResult(ids) { result in
            switch result {
            case .success(let items): completion(items)
            case .failure(let error):
                NSLog("[AniListClient] fetchAnimeByIds failed: %@", error.description)
                completion([])
            }
        }
    }

    @discardableResult
    func fetchAnimeByIdsResult(_ ids: [Int],
                               completion: @escaping (Result<[AnimeItem], AniListRequestError>) -> Void) -> AniListRequestToken? {
        guard !ids.isEmpty else {
            DispatchQueue.main.async { completion(.success([])) }
            return nil
        }
        let variables = applyNsfwFilter(to: ["ids": ids])
        return requestExecutor.execute(query: AniListQueries.byIds,
                                       variables: variables,
                                       authorized: true,
                                       dedupeKey: cacheKey(prefix: "search", variables: variables)) { result in
            switch result {
            case .success(let graphQLResult):
                do {
                    let response = try JSONDecoder().decode(AniListResponse.self, from: graphQLResult.data)
                    guard let pageData = response.data?.Page else {
                        DispatchQueue.main.async { completion(.failure(.emptyData)) }
                        return
                    }
                    let items = (pageData.media ?? []).compactMap { AniListUtil.animeItem(from: $0) }
                    DispatchQueue.main.async { completion(.success(items)) }
                } catch {
                    DispatchQueue.main.async { completion(.failure(.invalidJSON)) }
                }
            case .failure(let error):
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
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
        var chunks: [[(key: String, title: String, year: Int?, isAdult: Bool)]] = []
        var currentChunk: [(key: String, title: String, year: Int?, isAdult: Bool)] = []
        for object in flattened {
            // Keep the adult duplicate beside its non-adult title so the GraphQL
            // operation can reuse the same title variable, matching Interface's
            // searchCompound construction without adding needless variables.
            if currentChunk.count >= 24 && !object.isAdult {
                chunks.append(currentChunk)
                currentChunk = []
            }
            currentChunk.append(object)
        }
        if !currentChunk.isEmpty { chunks.append(currentChunk) }

        func runChunk(at chunkIndex: Int) {
            guard chunkIndex < chunks.count else {
                DispatchQueue.main.async { completion(resultIDs) }
                return
            }

            let chunk = chunks[chunkIndex]
            let variableDefs = chunk.enumerated().compactMap { index, object in
                object.isAdult && index != 0 ? nil : "$v\(index): String"
            }.joined(separator: ", ")
            let pages = chunk.enumerated().map { index, object in
                let yearPart = object.year.map { ", seasonYear: \($0)" } ?? ""
                let variableIndex = object.isAdult && index != 0 ? index - 1 : index
                return """
                v\(index): Page(perPage: 10) {
                  media(type: ANIME, search: $v\(variableIndex), status_in: [RELEASING, FINISHED], isAdult: \(object.isAdult)\(yearPart)) {
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
            for (index, object) in chunk.enumerated() where !(object.isAdult && index != 0) {
                variables["v\(index)"] = object.title
            }
            request.httpBody = try? JSONSerialization.data(withJSONObject: ["query": query, "variables": variables])

            performAniListDataTask(request, context: "AniList") { data, _, _ in
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
            }
        }

        runChunk(at: 0)
    }

    func fetchResolverMediaById(_ id: Int, completion: @escaping (AnimeItem?) -> Void) {
        var cached: AnimeItem?
        var shouldStartRequest = false
        fullMediaQueue.sync {
            cached = fullMediaCache[id]
            if cached == nil {
                if fullMediaCompletions[id] != nil {
                    fullMediaCompletions[id]?.append(completion)
                } else {
                    fullMediaCompletions[id] = [completion]
                    shouldStartRequest = true
                }
            }
        }

        if let cached {
            DispatchQueue.main.async { completion(cached) }
            return
        }
        if shouldStartRequest {
            fetchResolverMediaByIdFromNetwork(id)
        }
    }

    private func fetchResolverMediaByIdFromNetwork(_ id: Int) {
        guard let url = URL(string: graphQLEndpoint) else {
            finishFullMediaFetch(id: id, item: nil)
            return
        }

        var request = authorizedRequest(url: url)
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "query": AniListQueries.resolverMediaById,
            "variables": ["id": id]
        ])

        performAniListDataTask(request, context: "AniList") { [weak self] data, _, error in
            guard let self else { return }
            if let error {
                NSLog("[AniListClient] ResolverMedia network error: %@", error.localizedDescription)
            }

            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let media = (json["data"] as? [String: Any])?["Media"] as? [String: Any] else {
                self.finishFullMediaFetch(id: id, item: nil)
                return
            }

            self.logGraphQLErrors(json["errors"], context: "ResolverMedia")
            guard var item = self.parseAnimeItem(from: media) else {
                self.finishFullMediaFetch(id: id, item: nil)
                return
            }
            item.relations = self.parseRelations(from: media)
            self.finishFullMediaFetch(id: id, item: item)
        }
    }

    private func finishFullMediaFetch(id: Int, item: AnimeItem?) {
        fullMediaQueue.async { [weak self] in
            guard let self else { return }
            if let item {
                self.fullMediaCache[id] = item
            }
            let callbacks = self.fullMediaCompletions.removeValue(forKey: id) ?? []
            DispatchQueue.main.async {
                callbacks.forEach { $0(item) }
            }
        }
    }

    private func storeFullMediaPayload(_ item: AnimeItem) {
        guard item.isRouteReadyMediaPayload else { return }
        fullMediaQueue.async { [weak self] in
            guard let self else { return }
            if let existing = self.fullMediaCache[item.id] {
                self.fullMediaCache[item.id] = existing.mergingRouteMedia(item)
            } else {
                self.fullMediaCache[item.id] = item
            }
        }
    }

    func updateFavouriteState(mediaID: Int, isFavourite: Bool) {
        updateCachedMedia(mediaID: mediaID) { item in
            item.isFavourite = isFavourite
        }
    }

    func updateMediaListEntry(mediaID: Int, entry: AnimeItem.MediaListEntry?) {
        updateCachedMedia(mediaID: mediaID) { item in
            item.mediaListEntry = entry
        }
    }

    func clearViewerDependentCaches() {
        fullMediaQueue.async { [weak self] in
            guard let self else { return }
            self.fullMediaCache = self.fullMediaCache.mapValues { item in
                var item = item
                item.mediaListEntry = nil
                item.isFavourite = nil
                return item
            }
        }
        animePageQueue.async { [weak self] in
            self?.animePageCache.removeAll()
            self?.animePageCompletions.removeAll()
        }
        animePageFollowingQueue.async { [weak self] in
            self?.animePageFollowingCache.removeAll()
            self?.animePageFollowingCompletions.removeAll()
        }
        followingManyQueue.async { [weak self] in
            self?.followingManyCache.removeAll()
            self?.followingManyCompletions.removeAll()
        }
        queryCacheQueue.async { [weak self] in
            guard let self else { return }
            self.bannerCache = self.bannerCache?.map { self.strippingViewerState(from: $0) }
            self.homeSectionItemCache = self.homeSectionItemCache.mapValues { $0.map { self.strippingViewerState(from: $0) } }
            self.searchPageCache = self.searchPageCache.mapValues { page in
                AniListSearchPage(items: page.items.map { self.strippingViewerState(from: $0) },
                                  hasNextPage: page.hasNextPage)
            }
        }
    }

    private func strippingViewerState(from item: AnimeItem) -> AnimeItem {
        var item = item
        item.mediaListEntry = nil
        item.isFavourite = nil
        return item
    }

    private func updateCachedMedia(mediaID: Int, update: @escaping (inout AnimeItem) -> Void) {
        fullMediaQueue.async { [weak self] in
            guard let self, var item = self.fullMediaCache[mediaID] else { return }
            update(&item)
            self.fullMediaCache[mediaID] = item
        }
        animePageQueue.async { [weak self] in
            guard let self else { return }
            self.animePageCache = self.animePageCache.mapValues { payload in
                self.updating(payload: payload, mediaID: mediaID, update: update)
            }
        }
        queryCacheQueue.async { [weak self] in
            guard let self else { return }
            self.bannerCache = self.bannerCache.map { self.updating(items: $0, mediaID: mediaID, update: update) }
            self.homeSectionItemCache = self.homeSectionItemCache.mapValues { self.updating(items: $0, mediaID: mediaID, update: update) }
            self.searchPageCache = self.searchPageCache.mapValues { page in
                AniListSearchPage(items: self.updating(items: page.items, mediaID: mediaID, update: update),
                                  hasNextPage: page.hasNextPage)
            }
        }
    }

    private func updating(items: [AnimeItem], mediaID: Int, update: (inout AnimeItem) -> Void) -> [AnimeItem] {
        items.map { item in
            guard item.id == mediaID else { return item }
            var item = item
            update(&item)
            return item
        }
    }

    private func updating(payload: AnimePagePayload,
                          mediaID: Int,
                          update: (inout AnimeItem) -> Void) -> AnimePagePayload {
        var media = payload.media
        if var mediaValue = media, mediaValue.id == mediaID {
            update(&mediaValue)
            media = mediaValue
        }
        return AnimePagePayload(
            media: media,
            recommendations: updating(items: payload.recommendations, mediaID: mediaID, update: update),
            threads: payload.threads,
            threadTotal: payload.threadTotal,
            followingEntries: payload.followingEntries)
    }

    private func bestResolverSearchMedia(in mediaList: [[String: Any]], title: String) -> [String: Any]? {
        mediaList.min { lhs, rhs in
            let leftDistance = resolverTitleDistance(lhs, title: title)
            let rightDistance = resolverTitleDistance(rhs, title: title)
            if leftDistance == rightDistance {
                let leftDate = resolverStartDate(lhs)
                let rightDate = resolverStartDate(rhs)
                if leftDate != rightDate {
                    return (leftDate ?? Date()) < (rightDate ?? Date())
                }
            }
            return leftDistance < rightDistance
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
        fetchDetailForItemResult(id: id) { result in
            switch result {
            case .success(let relations): completion(relations)
            case .failure(let error):
                NSLog("[AniListClient] Detail fallback failed: %@", error.description)
                completion([])
            }
        }
    }

    @discardableResult
    func fetchDetailForItemResult(id: Int,
                                  completion: @escaping (Result<[AnimeRelation], AniListRequestError>) -> Void) -> AniListRequestToken? {
        let variables: [String: Any] = ["id": id]
        return requestExecutor.execute(query: AniListQueries.detail,
                                       variables: variables,
                                       authorized: true,
                                       dedupeKey: cacheKey(prefix: "detail", variables: variables)) { result in
            switch result {
            case .success(let graphQLResult):
                do {
                    let resp = try JSONDecoder().decode(AniListDetailResponse.self, from: graphQLResult.data)
                    guard let media = resp.data?.Media else {
                        DispatchQueue.main.async { completion(.failure(.emptyData)) }
                        return
                    }
                    let relations: [AnimeRelation] = (media.relations?.edges ?? []).compactMap { edge -> AnimeRelation? in
                        guard let type = edge.relationType,
                              type != "CHARACTER",
                              let node = edge.node,
                              (node.type ?? "ANIME") == "ANIME",
                              let nid = node.id else { return nil }
                        let relItem = AnimeItem(
                            id: nid,
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
                            year: node.seasonYear,
                            season: node.season,
                            format: node.format,
                            coverColor: node.coverImage?.color)
                        return AnimeRelation(relationType: type, media: relItem)
                    }
                    DispatchQueue.main.async { completion(.success(relations)) }
                } catch {
                    DispatchQueue.main.async { completion(.failure(.invalidJSON)) }
                }
            case .failure(let error):
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
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

        performAniListDataTask(request, context: "AniList") { data, _, _ in
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
        }
    }

    // MARK: - Anime page (anime/[id])

    func fetchAnimePage(id: Int, completion: @escaping (AnimePagePayload) -> Void) {
        fetchAnimePageResult(id: id) { result in
            switch result {
            case .success(let payload):
                completion(payload)
            case .failure(let error):
                NSLog("[AniListClient] AnimePage failed: %@", error.description)
                completion(self.emptyAnimePagePayload())
            }
        }
    }

    func fetchAnimePageResult(id: Int,
                              completion: @escaping (Result<AnimePagePayload, AniListRequestError>) -> Void) {
        let cacheKey = animePageCacheKey(for: id)
        var cached: AnimePagePayload?
        var shouldStartRequest = false

        animePageQueue.sync {
            cached = animePageCache[cacheKey]
            if cached == nil {
                if animePageCompletions[cacheKey] != nil {
                    animePageCompletions[cacheKey]?.append(completion)
                } else {
                    animePageCompletions[cacheKey] = [completion]
                    shouldStartRequest = true
                }
            }
        }

        if let cached {
            deliverAnimePagePayload(.success(cached), completion: completion)
            return
        }
        if shouldStartRequest {
            fetchAnimePageFromNetwork(id, cacheKey: cacheKey)
        }
    }

    private func fetchAnimePageFromNetwork(_ id: Int, cacheKey: String) {
        let variables: [String: Any] = ["id": id]
        requestExecutor.execute(query: AniListQueries.animePage,
                                variables: variables,
                                authorized: true,
                                dedupeKey: cacheKey) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let graphQLResult):
                guard let dataObject = graphQLResult.json["data"] as? [String: Any] else {
                    self.finishAnimePageFetch(id: id, cacheKey: cacheKey, result: .failure(.emptyData))
                    return
                }
                self.logGraphQLErrors(graphQLResult.graphQLErrors, context: "AnimePage")
                let payload = self.parseAnimePagePayload(from: dataObject, followingEntries: [])
                guard payload.media != nil else {
                    self.finishAnimePageFetch(id: id, cacheKey: cacheKey, result: .failure(.emptyData))
                    return
                }
                self.finishAnimePageFetch(id: id, cacheKey: cacheKey, result: .success(payload))
            case .failure(let error):
                self.finishAnimePageFetch(id: id, cacheKey: cacheKey, result: .failure(error))
            }
        }
    }

    private func finishAnimePageFetch(id: Int,
                                      cacheKey: String,
                                      result: Result<AnimePagePayload, AniListRequestError>) {
        animePageQueue.async { [weak self] in
            guard let self else { return }
            if case .success(let payload) = result, let media = payload.media {
                self.animePageCache[cacheKey] = payload
                self.storeFullMediaPayload(media)
            }
            let callbacks = self.animePageCompletions.removeValue(forKey: cacheKey) ?? []
            DispatchQueue.main.async {
                callbacks.forEach { $0(result) }
            }
        }
    }

    private func deliverAnimePagePayload(_ result: Result<AnimePagePayload, AniListRequestError>,
                                         completion: @escaping (Result<AnimePagePayload, AniListRequestError>) -> Void) {
        DispatchQueue.main.async { completion(result) }
    }

    private func emptyAnimePagePayload() -> AnimePagePayload {
        AnimePagePayload(media: nil, recommendations: [], threads: [], threadTotal: 0, followingEntries: [])
    }

    private func parseAnimePagePayload(from dataObject: [String: Any], followingEntries: [AniListFollowingEntry]) -> AnimePagePayload {
        let mediaObject = dataObject["Media"] as? [String: Any]
        var mediaItem = mediaObject.flatMap { parseAnimeItem(from: $0) }

        if var item = mediaItem {
            item.relations = parseRelations(from: mediaObject)
            mediaItem = item
        }

        let threadPage = dataObject["threads"] as? [String: Any]
        let threads = (threadPage?["threads"] as? [[String: Any]] ?? []).compactMap { AniListThread(dict: $0) }
        let total = intValue((threadPage?["pageInfo"] as? [String: Any])?["total"]) ?? threads.count
        let followingPage = dataObject["following"] as? [String: Any]
        let pageFollowingEntries = parseFollowingEntries(from: followingPage)

        return AnimePagePayload(
            media: mediaItem,
            recommendations: parseRecommendations(from: mediaObject),
            threads: threads,
            threadTotal: total,
            followingEntries: followingEntries.isEmpty ? pageFollowingEntries : followingEntries)
    }

    private func logGraphQLErrors(_ rawErrors: Any?, context: String) {
        let messages: [String]
        if let errors = rawErrors as? [[String: Any]] {
            messages = errors.compactMap { $0["message"] as? String }
        } else if let errorMessages = rawErrors as? [String] {
            messages = errorMessages
        } else {
            messages = []
        }
        guard !messages.isEmpty else { return }
        NSLog("[AniListClient] %@ GraphQL errors: %@", context, messages.joined(separator: ", "))
    }

    private func decodeAniListMedia(from object: [String: Any]) -> AniListMedia? {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object) else { return nil }
        return try? JSONDecoder().decode(AniListMedia.self, from: data)
    }

    private func parseAnimeItem(from object: [String: Any]) -> AnimeItem? {
        guard let id = intValue(object["id"]) else { return nil }

        let title = object["title"] as? [String: Any]
        let cover = object["coverImage"] as? [String: Any]
        let startDate = object["startDate"] as? [String: Any]
        let trailer = object["trailer"] as? [String: Any]
        let trailerID = (trailer?["site"] as? String)?.lowercased() == "youtube"
            ? trailer?["id"] as? String
            : nil

        var item = AnimeItem(
            id: id,
            titleEnglish: title?["english"] as? String,
            titleRomaji: title?["romaji"] as? String,
            titleNative: title?["native"] as? String,
            titleUserPreferred: title?["userPreferred"] as? String,
            coverURL: cover?["extraLarge"] as? String ?? cover?["large"] as? String ?? cover?["medium"] as? String,
            score: floatValue(object["averageScore"]),
            status: object["status"] as? String,
            episodes: intValue(object["episodes"]),
            bannerURL: object["bannerImage"] as? String,
            genres: object["genres"] as? [String] ?? [],
            description: (object["description"] as? String).map { AniListUtil.stripHTML($0) },
            synonyms: object["synonyms"] as? [String] ?? [],
            year: intValue(object["seasonYear"]),
            startYear: intValue(startDate?["year"]),
            season: object["season"] as? String,
            format: object["format"] as? String,
            duration: intValue(object["duration"]),
            trailerYouTubeID: trailerID,
            favourites: intValue(object["favourites"]),
            coverColor: cover?["color"] as? String,
            malId: intValue(object["idMal"]),
            isFavourite: object["isFavourite"] as? Bool,
            tags: parseTags(from: object["tags"] as? [[String: Any]]),
            isAdult: object["isAdult"] as? Bool)

        if let entry = object["mediaListEntry"] as? [String: Any],
           let status = entry["status"] as? String {
            item.mediaListEntry = AnimeItem.MediaListEntry(
                listID: intValue(entry["id"]) ?? 0,
                status: status,
                progress: intValue(entry["progress"]) ?? 0,
                score: intValue(entry["score"]) ?? 0,
                repeatCount: intValue(entry["repeat"]) ?? 0,
                customLists: parseCustomLists(entry["customLists"]))
        }

        return item
    }

    private func parseTags(from rawTags: [[String: Any]]?) -> [AnimeTag] {
        (rawTags ?? []).compactMap { tag in
            guard let id = intValue(tag["id"]),
                  let name = tag["name"] as? String,
                  !name.isEmpty else { return nil }
            return AnimeTag(
                id: id,
                name: name,
                isMediaSpoiler: tag["isMediaSpoiler"] as? Bool ?? false,
                isGeneralSpoiler: tag["isGeneralSpoiler"] as? Bool ?? false,
                rank: intValue(tag["rank"]) ?? 0,
                isAdult: tag["isAdult"] as? Bool ?? false)
        }
    }

    private func intValue(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String { return Int(value) }
        return nil
    }

    private func floatValue(_ value: Any?) -> Float? {
        if let value = value as? Float { return value }
        if let value = value as? Double { return Float(value) }
        if let value = value as? NSNumber { return value.floatValue }
        if let value = value as? String { return Float(value) }
        return nil
    }

    private func parseRecommendations(from mediaObject: [String: Any]?) -> [AnimeItem] {
        guard let nodes = (mediaObject?["recommendations"] as? [String: Any])?["nodes"] as? [[String: Any]] else {
            return []
        }
        return nodes.compactMap { node in
            guard let media = node["mediaRecommendation"] as? [String: Any] else { return nil }
            return parseAnimeItem(from: media)
        }
    }

    private func parseFollowingEntries(from page: [String: Any]?) -> [AniListFollowingEntry] {
        guard let viewerID = aniListViewerID else { return [] }
        let entries = page?["mediaList"] as? [[String: Any]] ?? []
        return entries.compactMap { entry in
            guard let progress = entry["progress"] as? Int,
                  let user = entry["user"] as? [String: Any],
                  let userID = user["id"] as? Int,
                  userID != viewerID,
                  let name = user["name"] as? String else { return nil }
            let avatar = (user["avatar"] as? [String: Any])?["large"] as? String
            return AniListFollowingEntry(user: AniListUserSummary(id: userID, name: name, avatarURL: avatar),
                                         progress: progress)
        }
    }

    private func parseRelations(from mediaObject: [String: Any]?) -> [AnimeRelation] {
        let edges = ((mediaObject?["relations"] as? [String: Any])?["edges"] as? [[String: Any]]) ?? []
        return edges.compactMap { edge in
            guard let type = edge["relationType"] as? String,
                  let node = edge["node"] as? [String: Any],
                  (node["type"] as? String ?? "ANIME") == "ANIME",
                  let item = parseAnimeItem(from: node) else { return nil }
            guard type != "CHARACTER" else { return nil }
            return AnimeRelation(relationType: type, media: item)
        }
    }

    // MARK: - Trailer + Genres

    func fetchTrailerAndGenres(id: Int, completion: @escaping (_ trailerYouTubeID: String?, _ genres: [String], _ malId: Int?) -> Void) {
        fetchTrailerAndGenresResult(id: id) { result in
            switch result {
            case .success(let payload):
                completion(payload.trailerYouTubeID, payload.genres, payload.malId)
            case .failure(let error):
                NSLog("[AniListClient] Trailer/genres failed: %@", error.description)
                completion(nil, [], nil)
            }
        }
    }

    @discardableResult
    func fetchTrailerAndGenresResult(id: Int,
                                     completion: @escaping (Result<AnimeTrailerGenresPayload, AniListRequestError>) -> Void) -> AniListRequestToken? {
        let variables: [String: Any] = ["id": id]
        return requestExecutor.execute(query: AniListQueries.trailerGenres,
                                       variables: variables,
                                       authorized: true,
                                       dedupeKey: cacheKey(prefix: "trailerGenres", variables: variables)) { result in
            switch result {
            case .success(let graphQLResult):
                guard let data = graphQLResult.json["data"] as? [String: Any],
                      let media = data["Media"] as? [String: Any] else {
                    DispatchQueue.main.async { completion(.failure(.emptyData)) }
                    return
                }
                let genres = media["genres"] as? [String] ?? []
                let malId = (media["idMal"] as? NSNumber)?.intValue
                var trailerID: String? = nil
                if let trailer = media["trailer"] as? [String: Any],
                   (trailer["site"] as? String)?.lowercased() == "youtube" {
                    trailerID = trailer["id"] as? String
                }
                let payload = AnimeTrailerGenresPayload(trailerYouTubeID: trailerID,
                                                        genres: genres,
                                                        malId: malId)
                DispatchQueue.main.async { completion(.success(payload)) }
            case .failure(let error):
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    // MARK: - Forum threads (matches client.ts threads())

    func threads(mediaID: Int,
                 page: Int = 1,
                 perPage: Int = 16,
                 completion: @escaping ([AniListThread]) -> Void) {
        threadsResult(mediaID: mediaID, page: page, perPage: perPage) { result in
            switch result {
            case .success(let threads): completion(threads)
            case .failure(let error):
                NSLog("[AniListClient] Threads failed: %@", error.description)
                completion([])
            }
        }
    }

    @discardableResult
    func threadsResult(mediaID: Int,
                       page: Int = 1,
                       perPage: Int = 16,
                       completion: @escaping (Result<[AniListThread], AniListRequestError>) -> Void) -> AniListRequestToken? {
        let variables: [String: Any] = ["id": mediaID, "page": page, "perPage": perPage]
        return requestExecutor.execute(query: AniListQueries.threads,
                                       variables: variables,
                                       authorized: true,
                                       dedupeKey: cacheKey(prefix: "threads", variables: variables)) { result in
            switch result {
            case .success(let graphQLResult):
                guard let data = graphQLResult.json["data"] as? [String: Any],
                      let threadPage = data["threads"] as? [String: Any],
                      let rawThreads = threadPage["threads"] as? [[String: Any]] else {
                    DispatchQueue.main.async { completion(.failure(.emptyData)) }
                    return
                }
                let parsed = rawThreads.compactMap { AniListThread(dict: $0) }
                DispatchQueue.main.async { completion(.success(parsed)) }
            case .failure(let error):
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    // MARK: - Airing schedule

    func fetchAiringForMonth(_ month: Date, completion: @escaping ([AiringScheduleEntry]) -> Void) {
        fetchAiringForMonthResult(month) { result in
            switch result {
            case .success(let entries): completion(entries)
            case .failure(let error):
                NSLog("[AniListClient] Schedule failed: %@", error.description)
                completion([])
            }
        }
    }

    @discardableResult
    func fetchAiringForMonthResult(_ month: Date,
                                   completion: @escaping (Result<[AiringScheduleEntry], AniListRequestError>) -> Void) -> AniListRequestToken? {
        let seasonWindow = scheduleSeasonWindow(around: Date())
        var variables: [String: Any] = [
            "seasonCurrent": seasonWindow.current.season,
            "seasonYearCurrent": seasonWindow.current.year,
            "seasonLast": seasonWindow.last.season,
            "seasonYearLast": seasonWindow.last.year,
            "seasonNext": seasonWindow.next.season,
            "seasonYearNext": seasonWindow.next.year,
            "formatNot": "TV_SHORT"
        ]
        if let nsfw = AniListUtil.nsfwGenreFilter { variables["nsfw"] = nsfw }

        return requestExecutor.execute(query: AniListQueries.schedule,
                                       variables: variables,
                                       authorized: true,
                                       dedupeKey: cacheKey(prefix: "schedule", variables: variables)) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let graphQLResult):
                guard let dataObject = graphQLResult.json["data"] as? [String: Any] else {
                    DispatchQueue.main.async { completion(.failure(.emptyData)) }
                    return
                }
                self.logGraphQLErrors(graphQLResult.graphQLErrors, context: "Schedule")
                let entries = self.parseScheduleEntries(from: dataObject, visibleMonth: month)
                DispatchQueue.main.async { completion(.success(entries)) }
            case .failure(let error):
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    private func scheduleSeasonWindow(around month: Date) -> (current: (season: String, year: Int), last: (season: String, year: Int), next: (season: String, year: Int)) {
        let calendar = Calendar(identifier: .gregorian)
        func seasonTuple(for date: Date) -> (season: String, year: Int) {
            let monthNumber = calendar.component(.month, from: date)
            let year = calendar.component(.year, from: date)
            switch monthNumber {
            case 1...3: return ("WINTER", year)
            case 4...6: return ("SPRING", year)
            case 7...9: return ("SUMMER", year)
            default: return ("FALL", year)
            }
        }

        let lastDate = calendar.date(byAdding: .month, value: -3, to: month) ?? month
        let nextDate = calendar.date(byAdding: .month, value: 3, to: month) ?? month
        return (seasonTuple(for: month), seasonTuple(for: lastDate), seasonTuple(for: nextDate))
    }

    private func parseScheduleEntries(from dataObject: [String: Any], visibleMonth: Date) -> [AiringScheduleEntry] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        let monthComponents = calendar.dateComponents([.year, .month], from: visibleMonth)
        guard let monthStart = calendar.date(from: monthComponents),
              let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) else { return [] }

        var seenMediaIDs = Set<Int>()
        var entries: [AiringScheduleEntry] = []
        for key in ["curr1", "curr2", "curr3", "residue", "next1", "next2"] {
            guard let page = dataObject[key] as? [String: Any],
                  let mediaObjects = page["media"] as? [[String: Any]] else { continue }
            for mediaObject in mediaObjects {
                guard let mediaID = intValue(mediaObject["id"]), seenMediaIDs.insert(mediaID).inserted else { continue }
                if ((mediaObject["mediaListEntry"] as? [String: Any])?["status"] as? String) == "DROPPED" { continue }
                guard let item = parseScheduleMediaItem(from: mediaObject) else { continue }

                var seenEpisodes = Set<Int>()
                for node in scheduleNodes(from: mediaObject) {
                    guard let episode = intValue(node["e"]),
                          let airingAt = intValue(node["a"]),
                          seenEpisodes.insert(episode).inserted else { continue }
                    let date = Date(timeIntervalSince1970: Double(airingAt))
                    guard date >= monthStart && date < monthEnd else { continue }
                    entries.append(AiringScheduleEntry(episode: episode, airingAt: date, media: item))
                }
            }
        }
        return entries.sorted { $0.airingAt < $1.airingAt }
    }

    private func scheduleNodes(from mediaObject: [String: Any]) -> [[String: Any]] {
        func nodes(for key: String) -> [[String: Any]] {
            let schedule = mediaObject[key] as? [String: Any]
            return schedule?["n"] as? [[String: Any]] ?? []
        }
        return nodes(for: "aired") + nodes(for: "notaired")
    }

    private func parseScheduleMediaItem(from object: [String: Any]) -> AnimeItem? {
        guard let id = intValue(object["id"]) else { return nil }
        let title = object["title"] as? [String: Any]
        let cover = object["coverImage"] as? [String: Any]
        return AnimeItem(
            id: id,
            titleEnglish: title?["english"] as? String,
            titleRomaji: title?["romaji"] as? String,
            titleNative: title?["native"] as? String,
            titleUserPreferred: title?["userPreferred"] as? String,
            coverURL: cover?["extraLarge"] as? String ?? cover?["large"] as? String,
            score: nil,
            status: nil,
            episodes: nil,
            bannerURL: nil,
            genres: [],
            description: nil,
            coverColor: cover?["color"] as? String)
    }

    // MARK: - Per-media airing schedule

    func fetchMediaAiringSchedule(anilistID: Int, completion: @escaping (MediaScheduleResult?) -> Void) {
        fetchMediaAiringScheduleResult(anilistID: anilistID) { result in
            switch result {
            case .success(let schedule): completion(schedule)
            case .failure(let error):
                NSLog("[AniListClient] Media schedule failed: %@", error.description)
                completion(nil)
            }
        }
    }

    @discardableResult
    func fetchMediaAiringScheduleResult(anilistID: Int,
                                        completion: @escaping (Result<MediaScheduleResult, AniListRequestError>) -> Void) -> AniListRequestToken? {
        let variables: [String: Any] = ["id": anilistID]
        return requestExecutor.execute(query: AniListQueries.mediaSchedule,
                                       variables: variables,
                                       authorized: true,
                                       dedupeKey: cacheKey(prefix: "mediaSchedule", variables: variables)) { result in
            switch result {
            case .success(let graphQLResult):
                do {
                    let resp = try JSONDecoder().decode(MediaScheduleResponse.self, from: graphQLResult.data)
                    guard let media = resp.data?.Media else {
                        DispatchQueue.main.async { completion(.failure(.emptyData)) }
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
                    let result = MediaScheduleResult(schedule: schedule,
                                                     startDate: sd,
                                                     episodeCount: media.episodes)
                    DispatchQueue.main.async { completion(.success(result)) }
                } catch {
                    DispatchQueue.main.async { completion(.failure(.invalidJSON)) }
                }
            case .failure(let error):
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
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
        // Web Hayase uses episodesCached(id), which calls:
        //   https://api.ani.zip/v2/images/tmdb?anilist_id=<id>
        // and then picks TMDB backdrops/logos by vote_average. The previous native
        // path used api.ani.zip/v1 mappings images (Fanart/Poster), which is why
        // the Swift banner could show a completely different red key visual.
        var comps = URLComponents(string: "https://api.ani.zip/v2/images/tmdb")
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
        URLSession.shared.dataTask(with: req) { data, response, error in
            if let error {
                NSLog("[AniZip] image fetch failed: %@", error.localizedDescription)
            }
            if let http = response as? HTTPURLResponse,
               http.statusCode < 200 || http.statusCode >= 300 {
                NSLog("[AniZip] image fetch HTTP %@", String(http.statusCode))
            }

            var fanartURL: String? = nil
            var clearlogoURL: String? = nil
            if let data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let backdrops = (json["backdrops"] as? [[String: Any]] ?? []).sortedByVoteAverageDescending()
                let posters = (json["posters"] as? [[String: Any]] ?? []).sortedByVoteAverageDescending()
                let logos = (json["logos"] as? [[String: Any]] ?? []).sortedByVoteAverageDescending()

                fanartURL = backdrops.firstTMDBImage(language: nil, minimumAspectRatio: 1.2)
                         ?? posters.firstTMDBImage(language: nil, minimumAspectRatio: 1.2)
                clearlogoURL = logos.firstTMDBImage(language: "en", minimumAspectRatio: 1.2)
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
private extension Array where Element == [String: Any] {
    func sortedByVoteAverageDescending() -> [[String: Any]] {
        sorted { lhs, rhs in
            (lhs["vote_average"] as? Double ?? 0) > (rhs["vote_average"] as? Double ?? 0)
        }
    }

    func firstTMDBImage(language: String?, minimumAspectRatio: Double) -> String? {
        first { image in
            let imageLanguage = image["iso_639_1"] as? String
            let aspectRatio = image["aspect_ratio"] as? Double ?? 0
            return imageLanguage == language && aspectRatio > minimumAspectRatio
        }?["file_path"] as? String
    }
}
