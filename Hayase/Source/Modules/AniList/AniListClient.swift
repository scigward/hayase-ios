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
    private var followingManyCompletions: [String: [(Result<[Int: [AniListUserSummary]], AniListRequestError>) -> Void]] = [:]

    private let fullMediaQueue = DispatchQueue(label: "com.hayase.anilist.fullMedia")
    private var fullMediaCache: [String: AnimeItem] = [:]
    private var fullMediaCompletions: [String: [(Result<AnimeItem, AniListRequestError>) -> Void]] = [:]

    private let animePageQueue = DispatchQueue(label: "com.hayase.anilist.animePage")
    private var animePageCache: [String: AnimePagePayload] = [:]
    private var animePageCompletions: [String: [(Result<AnimePagePayload, AniListRequestError>) -> Void]] = [:]

    private let animePageFollowingQueue = DispatchQueue(label: "com.hayase.anilist.animePageFollowing")
    private var animePageFollowingCache: [String: [AniListFollowingEntry]] = [:]
    private var animePageFollowingCompletions: [String: [([AniListFollowingEntry]) -> Void]] = [:]

    private let queryCacheQueue = DispatchQueue(label: "com.hayase.anilist.queryCache")
    private var bannerCache: [String: [AnimeItem]] = [:]
    private var homeSectionItemCache: [String: [AnimeItem]] = [:]
    private var searchPageCache: [String: AniListSearchPage] = [:]

    private let relationGraphQueue = DispatchQueue(label: "com.hayase.anilist.relationGraph")
    private var relationGraphCache: [Int: AnimeRelationGraph] = [:]

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

    private func fullMediaCacheKey(for id: Int) -> String {
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

        let bannerKey = cacheKey(prefix: "banner", variables: variables)
        let cachedBanner = queryCacheQueue.sync(execute: { bannerCache[bannerKey] })
        if policy != .networkOnly, let cached = cachedBanner {
            query?.setSuccess(cached, isEmpty: cached.isEmpty)
            completion(.success(cached))
            if policy == .cacheFirst { return nil }
        }
        if policy != .networkOnly, cachedBanner == nil, let cached = cachedAnimeItems(for: bannerKey) {
            queryCacheQueue.async { self.bannerCache[bannerKey] = cached }
            query?.setSuccess(cached, isEmpty: cached.isEmpty)
            completion(.success(cached))
            if policy == .cacheFirst { return nil }
        }
        guard policy != .pausedUntilVisible else { return nil }

        query?.setFetching()
        let token = requestExecutor.execute(query: AniListQueries.search,
                                            variables: variables,
                                            authorized: true,
                                            dedupeKey: bannerKey) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let graphQLResult):
                do {
                    let response = try JSONDecoder().decode(AniListResponse.self, from: graphQLResult.data)
                    let items = (response.data?.Page?.media ?? []).compactMap { AniListUtil.animeItem(from: $0) }
                    self.queryCacheQueue.async { self.bannerCache[bannerKey] = items }
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
        query?.setRefetch { [weak self] in
            self?.fetchBannerItemsResult(policy: .networkOnly, query: query, completion: completion)
        }
        return token
    }

    // MARK: - Home sections (home/+page.svelte)

    func homeSectionDefinitions() -> [AniListHomeSectionDefinition] {
        let season = AniListUtil.currentSeason()
        let year = AniListUtil.currentYear()
        return [
            AniListHomeSectionDefinition(id: "home.popular-season",
                                         title: "Popular This Season",
                                         variables: ["sort": ["POPULARITY_DESC"], "season": season, "seasonYear": year, "perPage": 25],
                                         startsPaused: true),
            AniListHomeSectionDefinition(id: "home.trending",
                                         title: "Trending Now",
                                         variables: ["sort": ["TRENDING_DESC"], "perPage": 25],
                                         startsPaused: true),
            AniListHomeSectionDefinition(id: "home.all-time-popular",
                                         title: "All Time Popular",
                                         variables: ["sort": ["POPULARITY_DESC"], "perPage": 25],
                                         startsPaused: true),
            AniListHomeSectionDefinition(id: "home.romance",
                                         title: "Romance",
                                         variables: ["sort": ["TRENDING_DESC"], "genre": ["Romance"], "perPage": 25],
                                         startsPaused: true),
            AniListHomeSectionDefinition(id: "home.action",
                                         title: "Action",
                                         variables: ["sort": ["TRENDING_DESC"], "genre": ["Action"], "perPage": 25],
                                         startsPaused: true),
            AniListHomeSectionDefinition(id: "home.adventure",
                                         title: "Adventure",
                                         variables: ["sort": ["TRENDING_DESC"], "genre": ["Adventure"], "perPage": 25],
                                         startsPaused: true),
            AniListHomeSectionDefinition(id: "home.fantasy",
                                         title: "Fantasy",
                                         variables: ["sort": ["TRENDING_DESC"], "genre": ["Fantasy"], "perPage": 25],
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
        if policy != .networkOnly, cachedSection == nil, let cached = cachedAnimeItems(for: key) {
            let section = makeHomeSectionData(definition: definition,
                                              items: cached,
                                              state: cached.isEmpty ? .empty : .loaded)
            queryCacheQueue.async { self.homeSectionItemCache[key] = cached }
            query?.setSuccess(section, isEmpty: cached.isEmpty)
            completion(.success(section))
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
        query?.setRefetch { [weak self] in
            self?.fetchHomeSectionResult(definition: definition, policy: .networkOnly, query: query, completion: completion)
        }
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

    @discardableResult
    func fetchFollowingManyResult(animeIDs: [Int],
                                  completion: @escaping (Result<[Int: [AniListUserSummary]], AniListRequestError>) -> Void) -> AniListRequestToken? {
        guard TrackerAccountManager.shared.isLoggedIn(.anilist),
              let viewerStr = TrackerAccountManager.shared.viewer(for: .anilist)?.id,
              let viewerID = Int(viewerStr) else {
            DispatchQueue.main.async { completion(.success([:])) }
            return nil
        }
        let ids = Array(Set(animeIDs)).sorted()
        guard !ids.isEmpty else {
            DispatchQueue.main.async { completion(.success([:])) }
            return nil
        }
        let key = ids.map(String.init).joined(separator: ",")

        var cachedResult: [Int: [AniListUserSummary]]?
        var shouldStartRequest = false
        followingManyQueue.sync {
            if let cached = followingManyCache[key], cached.viewerID == viewerID {
                cachedResult = cached.usersByMediaID
                return
            }
            followingManyCompletions[key, default: []].append(completion)
            shouldStartRequest = followingManyCompletions[key]?.count == 1
        }
        if let cachedResult {
            DispatchQueue.main.async { completion(.success(cachedResult)) }
            return nil
        }
        guard shouldStartRequest else { return nil }

        return requestExecutor.execute(query: AniListQueries.followingMany,
                                       variables: ["ids": ids],
                                       authorized: true,
                                       dedupeKey: cacheKey(prefix: "followingMany", variables: ["ids": ids])) { [weak self] result in
            guard let self else { return }
            let parsed: Result<[Int: [AniListUserSummary]], AniListRequestError>
            switch result {
            case .success(let graphQLResult):
                parsed = self.parseFollowingMany(json: graphQLResult.json, viewerID: viewerID)
            case .failure(let error):
                parsed = .failure(error)
            }

            self.followingManyQueue.async {
                let completions = self.followingManyCompletions.removeValue(forKey: key) ?? []
                if case .success(let usersByMediaID) = parsed {
                    self.followingManyCache[key] = (viewerID: viewerID, usersByMediaID: usersByMediaID)
                }
                DispatchQueue.main.async {
                    completions.forEach { $0(parsed) }
                }
            }
        }
    }

    /// Fetches a single user's full profile by ID — bio, banner, stats,
    /// follow state — via the standalone `AniListQueries.user` query.
    /// Reuses `parseUserSummary`, which already expects exactly this shape
    /// (it was written for `userFields` nested in the following-list
    /// response, and a `User(id:)` response nests the same fields the
    /// same way).
    func fetchUserProfileResult(id: Int,
                                completion: @escaping (Result<AniListUserSummary, AniListRequestError>) -> Void) -> AniListRequestToken? {
        let variables: [String: Any] = ["id": id]
        return requestExecutor.execute(query: AniListQueries.user,
                                       variables: variables,
                                       authorized: true,
                                       dedupeKey: cacheKey(prefix: "user", variables: variables)) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let graphQLResult):
                guard let data = graphQLResult.json["data"] as? [String: Any],
                      let userObject = data["User"] as? [String: Any],
                      let summary = self.parseUserSummary(userObject) else {
                    DispatchQueue.main.async { completion(.failure(.emptyData)) }
                    return
                }
                DispatchQueue.main.async { completion(.success(summary)) }
            case .failure(let error):
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    private func parseFollowingMany(json: [String: Any], viewerID: Int) -> Result<[Int: [AniListUserSummary]], AniListRequestError> {
        if let errors = json["errors"] as? [[String: Any]], !errors.isEmpty {
            let messages = errors.compactMap { $0["message"] as? String }
            return .failure(.graphQLErrors(messages.isEmpty ? ["Unknown GraphQL error"] : messages))
        }
        guard let dataObject = json["data"] as? [String: Any],
              let page = dataObject["Page"] as? [String: Any],
              let mediaList = page["mediaList"] as? [Any] else {
            return .failure(.emptyData)
        }

        var usersByMediaID: [Int: [AniListUserSummary]] = [:]
        var seenPairs = Set<String>()
        for rawEntry in mediaList {
            guard let entry = rawEntry as? [String: Any] else { continue }
            guard let media = entry["media"] as? [String: Any],
                  let mediaID = media["id"] as? Int,
                  let user = entry["user"] as? [String: Any],
                  let summary = parseUserSummary(user),
                  summary.id != viewerID else { continue }
            let pairKey = "\(mediaID):\(summary.id)"
            guard seenPairs.insert(pairKey).inserted else { continue }
            usersByMediaID[mediaID, default: []].append(summary)
        }
        return .success(usersByMediaID)
    }

    private func parseUserSummary(_ user: [String: Any]) -> AniListUserSummary? {
        guard let userID = user["id"] as? Int,
              let name = user["name"] as? String else { return nil }
        let avatar = (user["avatar"] as? [String: Any])?["large"] as? String
        let options = user["options"] as? [String: Any]
        let statistics = (user["statistics"] as? [String: Any])?["anime"] as? [String: Any]
        return AniListUserSummary(
            id: userID,
            name: name,
            avatarURL: avatar,
            bannerURL: user["bannerImage"] as? String,
            about: user["about"] as? String,
            isFollowing: boolValue(user["isFollowing"]),
            isFollower: boolValue(user["isFollower"]),
            donatorBadge: user["donatorBadge"] as? String,
            profileColor: options?["profileColor"] as? String,
            createdAt: userTimeIntervalValue(user["createdAt"]),
            animeCount: userIntegerValue(statistics?["count"]),
            episodesWatched: userIntegerValue(statistics?["episodesWatched"]),
            minutesWatched: userIntegerValue(statistics?["minutesWatched"]))
    }

    private func userIntegerValue(_ value: Any?) -> Int {
        if let value = value as? Int { return value }
        if let value = value as? Double { return Int(value) }
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String { return Int(value) ?? 0 }
        return 0
    }

    private func userTimeIntervalValue(_ value: Any?) -> TimeInterval {
        if let value = value as? TimeInterval { return value }
        if let value = value as? Int { return TimeInterval(value) }
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? String, let parsed = TimeInterval(value) { return parsed }
        return 0
    }

    private func boolValue(_ value: Any?) -> Bool {
        if let value = value as? Bool { return value }
        if let value = value as? Int { return value != 0 }
        if let value = value as? String { return value == "true" || value == "1" }
        return false
    }

    private func cachedSearchPage(for key: String) -> AniListSearchPage? {
        guard let data = AniListOperationCache.shared.cachedData(for: key),
              let response = try? JSONDecoder().decode(AniListResponse.self, from: data),
              let pageData = response.data?.Page else {
            return nil
        }
        return AniListSearchPage(
            items: (pageData.media ?? []).compactMap { AniListUtil.animeItem(from: $0) },
            hasNextPage: pageData.pageInfo?.hasNextPage ?? false,
            isCacheResult: true)
    }

    private func cachedAnimeItems(for key: String) -> [AnimeItem]? {
        cachedSearchPage(for: key)?.items
    }

    @discardableResult
    private func fetchSectionItemsResult(variables: [String: Any],
                                         policy: AniListRequestPolicy,
                                         completion: @escaping (Result<[AnimeItem], AniListRequestError>) -> Void) -> AniListRequestToken? {
        let vars = applyNsfwFilter(to: variables)
        let key = cacheKey(prefix: "search", variables: vars)

        let cachedItems = queryCacheQueue.sync(execute: { homeSectionItemCache[key] })
        if policy != .networkOnly, let cached = cachedItems {
            completion(.success(cached))
            if policy == .cacheFirst { return nil }
        }
        if policy != .networkOnly, cachedItems == nil, let cached = cachedAnimeItems(for: key) {
            queryCacheQueue.async { self.homeSectionItemCache[key] = cached }
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
        if let t = title, !t.isEmpty { variables["search"] = AniListUtil.removeDiacritics(t) }
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
        let cachedSearch = queryCacheQueue.sync(execute: { searchPageCache[key] })
        if policy != .networkOnly, let cached = cachedSearch {
            query?.setSuccess(cached, isEmpty: cached.items.isEmpty)
            completion(.success(AniListSearchPage(items: cached.items,
                                                  hasNextPage: cached.hasNextPage,
                                                  isCacheResult: policy == .cacheAndNetwork)))
            if policy == .cacheFirst { return nil }
        }
        if policy != .networkOnly, cachedSearch == nil, let cached = cachedSearchPage(for: key) {
            queryCacheQueue.async { self.searchPageCache[key] = cached }
            query?.setSuccess(cached, isEmpty: cached.items.isEmpty)
            completion(.success(cached))
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
        // the pages after the first are appended by the page, only the first one is asked again
        if (page ?? 1) == 1 { query?.setRefetch { [weak self] in
            self?.searchAnimeItemsPage(title: title, genres: genres, tags: tags, formats: formats,
                                       statuses: statuses, statusNot: statusNot, sort: sort,
                                       seasonYear: seasonYear, season: season, isAdult: isAdult,
                                       onList: onList, ids: ids, perPage: perPage, page: page,
                                       policy: .networkOnly, query: query, completion: completion)
        } }
        return token
    }

    // MARK: - Fetch by IDs (single / trace.moe)

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

    func searchResolverAnimeIDsResult(titleGroups: [(key: String, titles: [String], year: String?)],
                                      completion: @escaping (Result<[String: Int], AniListRequestError>) -> Void) {
        let flattened = titleGroups.flatMap { group -> [(key: String, title: String, year: String?, isAdult: Bool)] in
            group.titles.flatMap { title in
                [
                    (key: group.key, title: title, year: group.year, isAdult: false),
                    (key: group.key, title: title, year: group.year, isAdult: true),
                ]
            }
        }
        searchResolverAnimeIDsResult(flattenedTitles: flattened, completion: completion)
    }

    func searchResolverAnimeIDsResult(flattenedTitles: [(key: String, title: String, year: String?, isAdult: Bool)],
                                      completion: @escaping (Result<[String: Int], AniListRequestError>) -> Void) {
        let flattened = flattenedTitles
        guard !flattened.isEmpty else {
            DispatchQueue.main.async { completion(.success([:])) }
            return
        }

        var resultIDs: [String: Int] = [:]
        var firstError: AniListRequestError?
        var chunks: [[(key: String, title: String, year: String?, isAdult: Bool)]] = []
        for index in stride(from: 0, to: flattened.count, by: 24) {
            let endIndex = min(index + 24, flattened.count)
            chunks.append(Array(flattened[index..<endIndex]))
        }

        func runChunk(at chunkIndex: Int) {
            guard chunkIndex < chunks.count else {
                DispatchQueue.main.async {
                    if let firstError {
                        completion(.failure(firstError))
                    } else {
                        self.filterResolverSearchIDs(resultIDs, completion: completion)
                    }
                }
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

            var variables: [String: Any] = [:]
            for (index, object) in chunk.enumerated() where !(object.isAdult && index != 0) {
                variables["v\(index)"] = object.title
            }

            requestExecutor.execute(query: query,
                                    variables: variables,
                                    authorized: true,
                                    dedupeKey: cacheKey(prefix: "resolverSearch", variables: variables)) { result in
                switch result {
                case .success(let graphQLResult):
                    guard let dataObject = graphQLResult.json["data"] as? [String: Any] else {
                        if firstError == nil { firstError = .emptyData }
                        runChunk(at: chunkIndex + 1)
                        return
                    }
                    for (index, titleObject) in chunk.enumerated() {
                        if resultIDs[titleObject.key] != nil { continue }
                        guard let page = dataObject["v\(index)"] as? [String: Any] else { continue }
                        let mediaList = self.objectArray(page["media"])
                        guard !mediaList.isEmpty,
                              let best = self.bestResolverSearchMedia(in: mediaList, title: titleObject.title),
                              let id = best["id"] as? Int else { continue }
                        resultIDs[titleObject.key] = id
                    }
                case .failure(let error):
                    if firstError == nil { firstError = error }
                }
                runChunk(at: chunkIndex + 1)
            }
        }

        runChunk(at: 0)
    }

    private func filterResolverSearchIDs(_ resultIDs: [String: Int],
                                         completion: @escaping (Result<[String: Int], AniListRequestError>) -> Void) {
        let ids = Array(Set(resultIDs.values)).sorted()
        guard !ids.isEmpty else {
            DispatchQueue.main.async { completion(.success([:])) }
            return
        }

        let variables: [String: Any] = ["ids": ids, "perPage": 50]
        requestExecutor.execute(query: AniListQueries.search,
                                variables: variables,
                                authorized: true,
                                dedupeKey: cacheKey(prefix: "resolverSearchMedia", variables: variables)) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let graphQLResult):
                guard let page = (graphQLResult.json["data"] as? [String: Any])?["Page"] as? [String: Any],
                      let mediaObjects = page["media"] as? [Any] else {
                    DispatchQueue.main.async { completion(.failure(.emptyData)) }
                    return
                }

                var validIDs = Set<Int>()
                for mediaObject in mediaObjects.compactMap({ $0 as? [String: Any] }) {
                    guard let item = self.parseFullAnimeItem(from: mediaObject) else { continue }
                    validIDs.insert(item.id)
                    self.storeFullMediaPayload(item)
                }

                let filtered = resultIDs.filter { validIDs.contains($0.value) }
                DispatchQueue.main.async { completion(.success(filtered)) }
            case .failure(let error):
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    func fetchResolverMediaByIdResult(_ id: Int,
                                      completion: @escaping (Result<AnimeItem, AniListRequestError>) -> Void) {
        let cacheKey = fullMediaCacheKey(for: id)
        var cached: AnimeItem?
        var shouldStartRequest = false
        fullMediaQueue.sync {
            cached = fullMediaCache[cacheKey]
            if cached == nil {
                fullMediaCompletions[cacheKey, default: []].append(completion)
                shouldStartRequest = fullMediaCompletions[cacheKey]?.count == 1
            }
        }

        if let cached = cached {
            DispatchQueue.main.async { completion(.success(cached)) }
            return
        }
        if shouldStartRequest {
            fetchResolverMediaByIdFromNetwork(id, cacheKey: cacheKey)
        }
    }

    private func fetchResolverMediaByIdFromNetwork(_ id: Int, cacheKey storageKey: String) {
        requestExecutor.execute(query: AniListQueries.resolverMediaById,
                                variables: ["id": id],
                                authorized: true,
                                dedupeKey: cacheKey(prefix: "resolverMedia", variables: ["id": id])) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let graphQLResult):
                guard let media = (graphQLResult.json["data"] as? [String: Any])?["Media"] as? [String: Any] else {
                    self.finishFullMediaFetch(id: id, cacheKey: storageKey, result: .failure(.emptyData))
                    return
                }
                guard let item = self.parseFullAnimeItem(from: media) else {
                    self.finishFullMediaFetch(id: id, cacheKey: storageKey, result: .failure(.invalidJSON))
                    return
                }
                self.finishFullMediaFetch(id: id, cacheKey: storageKey, result: .success(item))
            case .failure(let error):
                self.finishFullMediaFetch(id: id, cacheKey: storageKey, result: .failure(error))
            }
        }
    }

    private func finishFullMediaFetch(id: Int, cacheKey: String, result: Result<AnimeItem, AniListRequestError>) {
        fullMediaQueue.async { [weak self] in
            guard let self else { return }
            if case .success(let item) = result {
                self.fullMediaCache[cacheKey] = item
            }
            let callbacks = self.fullMediaCompletions.removeValue(forKey: cacheKey) ?? []
            DispatchQueue.main.async {
                callbacks.forEach { $0(result) }
            }
        }
    }

    private func storeFullMediaPayload(_ item: AnimeItem) {
        guard item.isRouteReadyMediaPayload else { return }
        let cacheKey = fullMediaCacheKey(for: item.id)
        fullMediaQueue.async { [weak self] in
            guard let self else { return }
            if let existing = self.fullMediaCache[cacheKey] {
                self.fullMediaCache[cacheKey] = existing.mergingRouteMedia(item)
            } else {
                self.fullMediaCache[cacheKey] = item
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
            self.fullMediaCache = self.fullMediaCache.reduce(into: [:]) { result, pair in
                guard pair.key.hasSuffix(":public") else { return }
                result[pair.key] = self.strippingViewerState(from: pair.value)
            }
            self.fullMediaCompletions.removeAll()
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
            self.bannerCache = self.bannerCache.reduce(into: [:]) { result, pair in
                guard pair.key.contains("|public|") else { return }
                result[pair.key] = pair.value.map { self.strippingViewerState(from: $0) }
            }
            self.homeSectionItemCache = self.homeSectionItemCache.reduce(into: [:]) { result, pair in
                guard pair.key.contains("|public|") else { return }
                result[pair.key] = pair.value.map { self.strippingViewerState(from: $0) }
            }
            self.searchPageCache = self.searchPageCache.reduce(into: [:]) { result, pair in
                guard pair.key.contains("|public|") else { return }
                result[pair.key] = AniListSearchPage(items: pair.value.items.map { self.strippingViewerState(from: $0) },
                                                     hasNextPage: pair.value.hasNextPage)
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
        let scope = aniListCacheScope
        fullMediaQueue.async { [weak self] in
            guard let self else { return }
            let suffix = ":\(scope)"
            for key in Array(self.fullMediaCache.keys) where key.hasSuffix(suffix) {
                guard var item = self.fullMediaCache[key], item.id == mediaID else { continue }
                update(&item)
                self.fullMediaCache[key] = item
            }
        }
        animePageQueue.async { [weak self] in
            guard let self else { return }
            self.animePageCache = self.animePageCache.reduce(into: [:]) { result, pair in
                guard pair.key.hasSuffix(":\(scope)") else { result[pair.key] = pair.value; return }
                result[pair.key] = self.updating(payload: pair.value, mediaID: mediaID, update: update)
            }
        }
        queryCacheQueue.async { [weak self] in
            guard let self else { return }
            let scopeNeedle = "|\(scope)|"
            self.bannerCache = self.bannerCache.reduce(into: [:]) { result, pair in
                result[pair.key] = pair.key.contains(scopeNeedle) ? self.updating(items: pair.value, mediaID: mediaID, update: update) : pair.value
            }
            self.homeSectionItemCache = self.homeSectionItemCache.reduce(into: [:]) { result, pair in
                result[pair.key] = pair.key.contains(scopeNeedle) ? self.updating(items: pair.value, mediaID: mediaID, update: update) : pair.value
            }
            self.searchPageCache = self.searchPageCache.reduce(into: [:]) { result, pair in
                guard pair.key.contains(scopeNeedle) else { result[pair.key] = pair.value; return }
                result[pair.key] = AniListSearchPage(items: self.updating(items: pair.value.items, mediaID: mediaID, update: update),
                                                     hasNextPage: pair.value.hasNextPage)
            }
        }
        DispatchQueue.main.async {
            Router.shared.updateCachedAnimeItem(mediaID: mediaID, update: update)
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
            followingEntries: payload.followingEntries,
            relationGraph: payload.relationGraph)
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
        let synonymDistances = stringArray(media["synonyms"])
            .filter { !$0.isEmpty }
            .map { Self.levenshtein($0.lowercased(), target) + 2 }
        return (titleDistances + synonymDistances).min() ?? Int.max
    }

    private func resolverStartDate(_ media: [String: Any]) -> Date? {
        guard let startDate = media["startDate"] as? [String: Any],
              let year = startDate["year"] as? Int else { return nil }
        var components = DateComponents()
        components.year = year
        components.month = (startDate["month"] as? Int ?? 1) + 1
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

    // MARK: - Anime page (anime/[id])

    /// `cacheAndNetwork` is `client.animePage`'s `requestPolicy`: what is known comes first, the answer
    /// of the network follows, so `completion` can run twice.
    func fetchAnimePageResult(id: Int,
                              policy: AniListRequestPolicy = .cacheFirst,
                              completion: @escaping (Result<AnimePagePayload, AniListRequestError>) -> Void) {
        let cacheKey = animePageCacheKey(for: id)
        var cached: AnimePagePayload?
        var shouldStartRequest = false

        animePageQueue.sync {
            cached = animePageCache[cacheKey]
            if cached == nil || policy == .cacheAndNetwork || policy == .networkOnly {
                if animePageCompletions[cacheKey] != nil {
                    animePageCompletions[cacheKey]?.append(completion)
                } else {
                    animePageCompletions[cacheKey] = [completion]
                    shouldStartRequest = true
                }
            }
        }

        if let cached = cached, policy != .networkOnly {
            deliverAnimePagePayload(.success(cached), completion: completion)
            if policy != .cacheAndNetwork { return }
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
            followingEntries: followingEntries.isEmpty ? pageFollowingEntries : followingEntries,
            relationGraph: mediaObject.flatMap { buildRelationGraph(from: $0) })
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
            genres: stringArray(object["genres"]),
            description: (object["description"] as? String).map { AniListUtil.stripHTML($0) },
            synonyms: stringArray(object["synonyms"]),
            year: intValue(object["seasonYear"]),
            startYear: intValue(startDate?["year"]),
            season: object["season"] as? String,
            format: object["format"] as? String,
            duration: intValue(object["duration"]),
            trailerYouTubeID: trailerID,
            favourites: intValue(object["favourites"]),
            coverColor: cover?["color"] as? String,
            coverMediumURL: (cover?["medium"] as? String)?.replacingOccurrences(of: "/small/", with: "/medium/"),
            malId: intValue(object["idMal"]),
            isFavourite: object["isFavourite"] as? Bool,
            tags: parseTags(from: objectArray(object["tags"])),
            isAdult: object["isAdult"] as? Bool,
            source: object["source"] as? String,
            countryOfOrigin: object["countryOfOrigin"] as? String,
            studioNames: studioNames(from: object["studios"]))

        if let entry = object["mediaListEntry"] as? [String: Any] {
            item.mediaListEntry = AnimeItem.MediaListEntry(
                listID: intValue(entry["id"]) ?? 0,
                status: entry["status"] as? String,
                progress: intValue(entry["progress"]) ?? 0,
                score: intValue(entry["score"]) ?? 0,
                repeatCount: intValue(entry["repeat"]) ?? 0,
                customLists: parseCustomLists(entry["customLists"]))
        }

        item.airedSchedule = parseAiringSchedule(from: object["aired"] as? [String: Any])
        item.notYetAiredSchedule = parseAiringSchedule(from: object["notaired"] as? [String: Any])

        return item
    }

    private func parseFullAnimeItem(from object: [String: Any]) -> AnimeItem? {
        guard var item = parseAnimeItem(from: object) else { return nil }
        item.relations = parseRelations(from: object)
        return item
    }

    private func parseAiringSchedule(from object: [String: Any]?) -> [AnimeItem.AiringEpisode] {
        objectArray(object?["n"]).compactMap { node in
            guard let episode = intValue(node["e"]) else { return nil }
            return AnimeItem.AiringEpisode(airingAt: intValue(node["a"]), episode: episode)
        }
    }

    private func parseTags(from rawTags: [[String: Any]]) -> [AnimeTag] {
        rawTags.compactMap { tag in
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

    private func stringArray(_ value: Any?) -> [String] {
        if let values = value as? [String] { return values }
        return (value as? [Any])?.compactMap { $0 as? String } ?? []
    }

    private func objectArray(_ value: Any?) -> [[String: Any]] {
        if let values = value as? [[String: Any]] { return values }
        return (value as? [Any])?.compactMap { $0 as? [String: Any] } ?? []
    }

    private func studioNames(from value: Any?) -> [String] {
        guard let studios = value as? [String: Any] else { return [] }
        return objectArray(studios["nodes"]).compactMap { $0["name"] as? String }
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
        guard let nodesValue = (mediaObject?["recommendations"] as? [String: Any])?["nodes"] else {
            return []
        }
        return objectArray(nodesValue).compactMap { node in
            guard let media = node["mediaRecommendation"] as? [String: Any] else { return nil }
            return parseFullAnimeItem(from: media)
        }
    }

    private func parseFollowingEntries(from page: [String: Any]?) -> [AniListFollowingEntry] {
        guard let viewerID = aniListViewerID else { return [] }
        let entries = page?["mediaList"] as? [[String: Any]] ?? []
        return entries.compactMap { entry in
            guard let progress = entry["progress"] as? Int,
                  let user = entry["user"] as? [String: Any],
                  let summary = parseUserSummary(user),
                  summary.id != viewerID else { return nil }
            return AniListFollowingEntry(user: summary,
                                         progress: progress)
        }
    }

    func expandRelationGraph(_ graph: AnimeRelationGraph,
                             reload: Bool = false,
                             completion: @escaping (Result<AnimeRelationGraph, AniListRequestError>) -> Void) {
        var graph = graph
        var expandedIDs = graph.expandedIDs

        func run(_ ids: Set<Int>) {
            let pending = ids.subtracting(expandedIDs)
            guard !pending.isEmpty else {
                self.storeRelationGraph(graph)
                DispatchQueue.main.async { completion(.success(graph)) }
                return
            }
            expandedIDs.formUnion(pending)
            graph.expandedIDs.formUnion(pending)

            let variables: [String: Any] = ["ids": Array(pending).sorted()]
            requestExecutor.execute(query: AniListQueries.recursiveRelations,
                                    variables: variables,
                                    authorized: true,
                                    dedupeKey: cacheKey(prefix: reload ? "relations-tree-refresh" : "relations-tree",
                                                        variables: variables)) { [weak self] result in
                guard let self else { return }
                switch result {
                case .success(let graphQLResult):
                    guard let dataObject = graphQLResult.json["data"] as? [String: Any],
                          let page = dataObject["Page"] as? [String: Any],
                          let mediaList = page["media"] as? [[String: Any]] else {
                        DispatchQueue.main.async { completion(.failure(.emptyData)) }
                        return
                    }

                    self.logGraphQLErrors(graphQLResult.graphQLErrors, context: "RelationsTree")
                    graph.boundaryIDs.removeAll()
                    for mediaObject in mediaList {
                        self.mergeRelationMedia(mediaObject, into: &graph, depth: 0, expandedIDs: graph.expandedIDs)
                    }
                    self.storeRelationGraph(graph)
                    run(graph.boundaryIDs.subtracting(graph.expandedIDs))

                case .failure(let error):
                    DispatchQueue.main.async { completion(.failure(error)) }
                }
            }
        }

        run(graph.boundaryIDs)
    }

    private func buildRelationGraph(from mediaObject: [String: Any]) -> AnimeRelationGraph {
        guard let mediaID = intValue(mediaObject["id"]) else {
            var graph = AnimeRelationGraph(nodes: [:], edges: [:])
            mergeRelationMedia(mediaObject, into: &graph, depth: 0, expandedIDs: [])
            storeRelationGraph(graph)
            return graph
        }

        var graph = cachedRelationGraph(for: mediaID) ?? AnimeRelationGraph(nodes: [:], edges: [:])
        mergeRelationMedia(mediaObject, into: &graph, depth: 0, expandedIDs: graph.expandedIDs)
        storeRelationGraph(graph)
        return graph
    }

    private func cachedRelationGraph(for mediaID: Int) -> AnimeRelationGraph? {
        relationGraphQueue.sync { relationGraphCache[mediaID] }
    }

    private func storeRelationGraph(_ graph: AnimeRelationGraph) {
        guard !graph.nodes.isEmpty else { return }
        relationGraphQueue.async { [weak self] in
            guard let self else { return }
            for id in graph.nodes.keys {
                self.relationGraphCache[id] = graph
            }
        }
    }

    private func mergeRelationMedia(_ mediaObject: [String: Any],
                                    into graph: inout AnimeRelationGraph,
                                    depth: Int,
                                    expandedIDs: Set<Int>) {
        if let type = mediaObject["type"] as? String, type != "ANIME" { return }
        guard let media = parseAnimeItem(from: mediaObject) else { return }

        // client.ts `processEdges`: only a media that is not in the graph yet can be the end of it
        let isNew = graph.nodes[media.id] == nil
        if let existing = graph.nodes[media.id] {
            graph.nodes[media.id] = existing.mergingRouteMedia(media)
        } else {
            graph.nodes[media.id] = media
        }

        if depth >= 2 {
            if isNew, !expandedIDs.contains(media.id) {
                graph.boundaryIDs.insert(media.id)
            }
            return
        }

        let edges = ((mediaObject["relations"] as? [String: Any])?["edges"] as? [[String: Any]]) ?? []
        for edge in edges {
            guard let relationType = edge["relationType"] as? String,
                  relationType != "CHARACTER",
                  let nodeObject = edge["node"] as? [String: Any] else { continue }
            if let nodeType = nodeObject["type"] as? String, nodeType != "ANIME" { continue }
            guard let node = parseAnimeItem(from: nodeObject) else { continue }

            let edgeID = relationEdgeKey(media.id, node.id)
            if let existing = graph.edges[edgeID] {
                if existing.relationType == "PARENT" {
                    graph.edges.removeValue(forKey: edgeID)
                } else {
                    continue
                }
            }

            let isPrequel = relationType == "PREQUEL"
            graph.edges[edgeID] = AnimeRelationGraphEdge(
                id: "e\(edgeID)",
                sourceID: isPrequel ? node.id : media.id,
                targetID: isPrequel ? media.id : node.id,
                relationType: isPrequel ? "SEQUEL" : relationType)

            mergeRelationMedia(nodeObject, into: &graph, depth: depth + 1, expandedIDs: expandedIDs)
        }
    }

    private func relationEdgeKey(_ lhs: Int, _ rhs: Int) -> String {
        lhs < rhs ? "\(lhs)-\(rhs)" : "\(rhs)-\(lhs)"
    }

    private func parseRelations(from mediaObject: [String: Any]?) -> [AnimeRelation] {
        let edges = objectArray((mediaObject?["relations"] as? [String: Any])?["edges"])
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

    func threadsResult(mediaID: Int,
                       page: Int = 1,
                       perPage: Int = 16,
                       completion: @escaping (Result<[AniListThread], AniListRequestError>) -> Void) -> AniListRequestToken? {
        let variables: [String: Any] = ["id": mediaID, "page": page, "perPage": perPage]
        return requestExecutor.execute(query: AniListQueries.threads,
                                       variables: variables,
                                       authorized: true,
                                       dedupeKey: cacheKey(prefix: "threads", variables: variables),
                                       cacheAndNetwork: true) { result in
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

    /// `month` is the first day of the quarter that holds the month on show, as the page asks for
    /// a whole quarter (and the seasons around it) at a time.
    func fetchAiringForMonthResult(_ month: Date,
                                   onList: Bool = false,
                                   completion: @escaping (Result<[AiringScheduleEntry], AniListRequestError>) -> Void) -> AniListRequestToken? {
        let seasonWindow = scheduleSeasonWindow(around: month)
        var variables: [String: Any] = [
            "seasonCurrent": seasonWindow.current.season,
            "seasonYearCurrent": seasonWindow.current.year,
            "seasonLast": seasonWindow.last.season,
            "seasonYearLast": seasonWindow.last.year,
            "seasonNext": seasonWindow.next.season,
            "seasonYearNext": seasonWindow.next.year,
        ]
        // `formatNot: onList ? null : 'TV_SHORT'`
        if !onList { variables["formatNot"] = "TV_SHORT" }
        if onList {
            if TrackerAccountManager.shared.isLoggedIn(.anilist) { variables["onList"] = true }
            else {
                let ids = TrackerAggregator.scheduleIDs()
                guard !ids.isEmpty else {
                    DispatchQueue.main.async { completion(.success([])) }
                    return nil
                }
                variables["ids"] = ids
            }
        }
        if let nsfw = AniListUtil.nsfwGenreFilter { variables["nsfw"] = nsfw }

        return requestExecutor.execute(query: AniListQueries.schedule,
                                       variables: variables,
                                       authorized: true,
                                       dedupeKey: cacheKey(prefix: "schedule", variables: variables),
                                       cacheAndNetwork: true) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let graphQLResult):
                guard let dataObject = graphQLResult.json["data"] as? [String: Any] else {
                    DispatchQueue.main.async { completion(.failure(.emptyData)) }
                    return
                }
                self.logGraphQLErrors(graphQLResult.graphQLErrors, context: "Schedule")
                let entries = self.parseScheduleEntries(from: dataObject)
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

    /// Every episode of every media the query returned: the page puts each on its day, the days
    /// of the neighbouring months that its grid shows included.
    private func parseScheduleEntries(from dataObject: [String: Any]) -> [AiringScheduleEntry] {
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
        var item = AnimeItem(
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
        if let entry = object["mediaListEntry"] as? [String: Any] {
            item.mediaListEntry = AnimeItem.MediaListEntry(listID: intValue(entry["id"]) ?? 0,
                status: entry["status"] as? String, progress: intValue(entry["progress"]) ?? 0,
                score: 0, repeatCount: 0, customLists: [])
        } else if !TrackerAccountManager.shared.isLoggedIn(.anilist) {
            item.mediaListEntry = TrackerAggregator.listEntry(for: id)
        }
        return item
    }

    // MARK: - Per-media airing schedule

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
        //   https://hayase.ani.zip/v2/images/tmdb?anilist_id=<id>
        // and then picks TMDB backdrops/logos by vote_average. The previous native
        // path used api.ani.zip/v1 mappings images (Fanart/Poster), which is why
        // the Swift banner could show a completely different red key visual.
        var comps = URLComponents(string: "https://hayase.ani.zip/v2/images/tmdb")
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
            var validImagesResponse = false
            if error == nil, let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), let data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                validImagesResponse = true
                let backdrops = (json["backdrops"] as? [[String: Any]] ?? []).sortedByVoteAverageDescending()
                let posters = (json["posters"] as? [[String: Any]] ?? []).sortedByVoteAverageDescending()
                let logos = (json["logos"] as? [[String: Any]] ?? []).sortedByVoteAverageDescending()

                fanartURL = backdrops.firstTMDBImage(language: nil, minimumAspectRatio: 1.2)
                         ?? posters.firstTMDBImage(language: nil, minimumAspectRatio: 1.2)
                clearlogoURL = logos.firstTMDBImage(language: "en", minimumAspectRatio: 1.2)
            }
            _fanartQueue.async(flags: .barrier) {
                let cbs = _fanartCallbacks.removeValue(forKey: anilistID) ?? []
                // A network failure is not proof that this anime has no logo.
                if validImagesResponse { _fanartFetched.insert(anilistID) }
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
