//
//  AniListAuth.swift
//  Hayase
//
//  AniList OAuth2 authentication and tracking provider.
//  Mirrors: src/lib/modules/anilist/ (auth portions of client.ts)
//

import Foundation

// MARK: - AniList Auth

final class AniListAuth {

    static let defaultClientID = "37117"
    static let hayaseCustomListName = "Watched using Hayase"

    static var clientID: String {
        get { UserDefaults.standard.string(forKey: "pref_anilistClientID") ?? defaultClientID }
        set { UserDefaults.standard.set(newValue, forKey: "pref_anilistClientID") }
    }

    static var authorizeURL: URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "anilist.co"
        components.path = "/api/v2/oauth/authorize"
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "token")
        ]
        return components.url ?? URL(string: "https://anilist.co/api/v2/oauth/authorize")!
    }

    static func fetchViewer(token: String, reportLoginFailure: Bool = false, completion: @escaping (TrackerViewer?) -> Void) {
        guard let url = URL(string: "https://graphql.anilist.co") else {
            completion(nil)
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["query": AniListQueries.viewer]
        request.httpBody = JSONSerialization.safeData(body)

        AniListRequestExecutor.shared.perform(request, context: "AniListViewer") { result in
            guard case .success(let data) = result,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let dataObj = json["data"] as? [String: Any],
                  let viewer = dataObj["Viewer"] as? [String: Any] else {
                if reportLoginFailure {
                    let message: String
                    switch result {
                    case .failure(.cancelled): completion(nil); return
                    case .failure(let error): message = error.description
                    case .success: message = "The server returned an invalid response."
                    }
                    DispatchQueue.main.async { AppErrorToast.show(message, title: "Login failed!") }
                }
                completion(nil)
                return
            }
            guard let tv = trackerViewer(from: viewer) else {
                if reportLoginFailure {
                    DispatchQueue.main.async { AppErrorToast.show("The server returned an invalid response.", title: "Login failed!") }
                }
                completion(nil)
                return
            }
            completion(tv)
        }
    }

    private static func trackerViewer(from viewer: [String: Any]) -> TrackerViewer? {
        guard let id = viewer["id"] as? Int,
              let name = viewer["name"] as? String else { return nil }
        let avatar = (viewer["avatar"] as? [String: Any])?["large"] as? String
        let options = viewer["options"] as? [String: Any]
        let animeList = (viewer["mediaListOptions"] as? [String: Any])?["animeList"] as? [String: Any]
        let customLists = (animeList?["customLists"] as? [Any] ?? []).compactMap { $0 as? String }
        return TrackerViewer(
            id: String(id),
            name: name,
            avatarURL: avatar,
            bannerURL: viewer["bannerImage"] as? String,
            titleLanguage: options?["titleLanguage"] as? String,
            displayAdultContent: options?["displayAdultContent"] as? Bool,
            customLists: customLists)
    }

    private static func ensureHayaseCustomList(token: String, viewer: TrackerViewer, completion: @escaping (TrackerViewer) -> Void) {
        guard !viewer.customLists.contains(hayaseCustomListName),
              let url = URL(string: "https://graphql.anilist.co") else {
            completion(viewer)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var lists = viewer.customLists
        lists.append(hayaseCustomListName)
        let variables: [String: Any] = ["lists": lists]
        request.httpBody = JSONSerialization.safeData(["query": AniListQueries.updateUser, "variables": variables])

        AniListRequestExecutor.shared.perform(request, context: "AniListUpdateUser") { result in
            guard case .success(let data) = result,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let dataObj = json["data"] as? [String: Any],
                  let updated = dataObj["UpdateUser"] as? [String: Any],
                  let updatedViewer = trackerViewer(from: updated) else {
                NSLog("[AniListAuth] Failed to ensure AniList custom list; continuing with fetched viewer")
                completion(viewer)
                return
            }
            completion(updatedViewer)
        }
    }

    static func completeLogin(token: String, expiresIn: TimeInterval? = nil) {
        let expiresAt = expiresIn.map { Date().addingTimeInterval($0) }
        TrackerAccountManager.shared.setToken(token, for: .anilist, expiresAt: expiresAt)
        fetchViewer(token: token, reportLoginFailure: true) { viewer in
            guard let viewer else {
                DispatchQueue.main.async {
                    TrackerAccountManager.shared.clearAniListSessionForAuthFailure()
                }
                return
            }
            ensureHayaseCustomList(token: token, viewer: viewer) { ensuredViewer in
                DispatchQueue.main.async {
                    TrackerAccountManager.shared.setViewer(ensuredViewer, for: .anilist)
                }
            }
        }
    }
}

// MARK: - AniList Tracking

final class AniListTracking {
    static let shared = AniListTracking()
    private init() {
        // `userlists` is a query the app always has open: `refocusExchange` asks it again too
        NotificationCenter.default.addObserver(forName: AniListRefocus.didRefocus, object: nil, queue: .main) { [weak self] _ in
            guard TrackerAccountManager.shared.isLoggedIn(.anilist) else { return }
            self?.fetchUserLists(forceRefresh: true) { _ in self?.notifyTrackingDidChange() }
        }
        // ...and the one that is opened for whoever signs in
        NotificationCenter.default.addObserver(forName: TrackerAccountManager.didChange, object: nil, queue: .main) { [weak self] _ in
            self?.loadViewerListsIfNeeded()
        }
    }

    /// `userlists = derived(viewerID, …)`: the viewer's lists load once there is a viewer, wherever the
    /// app starts, and are what every card, button and the schedule read an entry from.
    func start() {
        loadViewerListsIfNeeded()
    }

    private func loadViewerListsIfNeeded() {
        guard TrackerAccountManager.shared.isLoggedIn(.anilist), !AniListViewerState.shared.areListsLoaded else { return }
        fetchUserLists { _ in }
    }

    private let endpoint = "https://graphql.anilist.co"

    private func notifyTrackingDidChange() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: LocalTracking.didChange, object: self)
        }
    }

    // MARK: - Mutations

    // MARK: - Private helpers

    private func jsonInt(_ value: Any?) -> Int {
        if let i = value as? Int { return i }
        if let n = value as? NSNumber { return n.intValue }
        return 0
    }

    private func authRequestResult(query: String,
                                   variables: [String: Any],
                                   optimistic: Bool = false,
                                   completion: @escaping (Result<[String: Any], AniListRequestError>) -> Void) {
        guard TrackerAccountManager.shared.token(for: .anilist) != nil else {
            completion(.failure(.unauthenticated))
            return
        }
        guard let url = URL(string: endpoint) else {
            completion(.failure(.invalidEndpoint))
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = TrackerAccountManager.shared.token(for: .anilist) {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        guard let data = JSONSerialization.safeData(["query": query, "variables": variables]) else {
            completion(.failure(.encodingFailed(CocoaError(.coderInvalidValue))))
            return
        }
        request.httpBody = data

        AniListRequestExecutor.shared.perform(request, context: "AniListTracking", optimistic: optimistic) { result in
            switch result {
            case .success(let data):
                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    completion(.failure(.invalidJSON))
                    return
                }
                guard let dataObj = json["data"] as? [String: Any] else {
                    completion(.failure(.emptyData))
                    return
                }
                completion(.success(dataObj))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    /// A query: the token goes along when there is one, a media does not need one to be read.
    private func queryResult(query: String,
                             variables: [String: Any],
                             completion: @escaping (Result<[String: Any], AniListRequestError>) -> Void) {
        AniListRequestExecutor.shared.execute(query: query, variables: variables, authorized: true) { result in
            switch result {
            case .success(let graphQLResult):
                guard let dataObj = graphQLResult.json["data"] as? [String: Any] else {
                    completion(.failure(.emptyData))
                    return
                }
                completion(.success(dataObj))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    // MARK: - Fetch current list entry

    func fetchMediaWithEntryResult(anilistID: Int,
                                   completion: @escaping (Result<(entry: AnimeItem.MediaListEntry?, mediaStatus: String?, episodes: Int?, format: String?, duration: Int?, scheduleEpisodes: Int), AniListRequestError>) -> Void) {
        queryResult(query: AniListQueries.trackingSingleMedia, variables: ["id": anilistID]) { [weak self] result in
            guard let self else {
                completion(.failure(.cancelled))
                return
            }
            switch result {
            case .success(let data):
                guard let media = data["Media"] as? [String: Any] else {
                    completion(.failure(.emptyData))
                    return
                }
                let mediaStatus = media["status"] as? String
                let episodes = media["episodes"] as? Int
                let format = media["format"] as? String
                let duration = media["duration"] as? Int
                // util.ts `episodes()`: the last episode of either schedule when there is no count
                func lastEpisode(_ key: String) -> Int {
                    let nodes = (media[key] as? [String: Any])?["n"] as? [[String: Any]]
                    return (nodes?.last?["e"] as? Int) ?? 0
                }
                let scheduleEpisodes = max(lastEpisode("aired"), lastEpisode("notaired"))

                var entry: AnimeItem.MediaListEntry?
                if let mle = media["mediaListEntry"] as? [String: Any],
                   let listID = mle["id"] as? Int {
                    var enabledLists: [String] = []
                    if let customListsArray = mle["customLists"] as? [[String: Any]] {
                        for cl in customListsArray {
                            if let enabled = cl["enabled"] as? Bool, enabled,
                               let name = cl["name"] as? String {
                                enabledLists.append(name)
                            }
                        }
                    }
                    entry = AnimeItem.MediaListEntry(
                        listID: listID,
                        status: mle["status"] as? String,
                        progress: self.jsonInt(mle["progress"]),
                        score: self.jsonInt(mle["score"]),
                        repeatCount: self.jsonInt(mle["repeat"]),
                        customLists: enabledLists)
                }
                // `mediaListEntry`: AniList's entry first, then kitsu, mal, simkl and the local one
                completion(.success((entry ?? TrackerAggregator.externalEntry(for: anilistID),
                                     mediaStatus, episodes, format, duration, scheduleEpisodes)))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    // MARK: - entry()

    func entry(mediaID: Int,
               status: String? = nil,
               progress: Int? = nil,
               score: Int? = nil,
               repeatCount: Int? = nil,
               lists: [String]? = nil,
               completion: ((AnimeItem.MediaListEntry?) -> Void)? = nil) {
        entryResult(mediaID: mediaID,
                    status: status,
                    progress: progress,
                    score: score,
                    repeatCount: repeatCount,
                    lists: lists) { result in
            switch result {
            case .success(let entry):
                completion?(entry)
            case .failure(let error):
                NSLog("[AniListTracking] SaveMediaListEntry failed: %@", error.description)
                completion?(nil)
            }
        }
    }

    func entryResult(mediaID: Int,
                     status: String? = nil,
                     progress: Int? = nil,
                     score: Int? = nil,
                     repeatCount: Int? = nil,
                     lists: [String]? = nil,
                     completion: @escaping (Result<AnimeItem.MediaListEntry, AniListRequestError>) -> Void) {
        let syncLocal = TrackerAccountManager.shared.isSyncEnabled(for: .local)
        let localEntry = syncLocal ? LocalTracking.shared.entry(
            mediaID: mediaID,
            status: status,
            progress: progress,
            score: score,
            repeatCount: repeatCount,
            lists: lists) : nil
        // auth/client.ts `entry`: kitsu, mal and simkl get the change whatever AniList does
        TrackerAggregator.entry(TrackerEntryVariables(id: mediaID, status: status, progress: progress,
                                                      score: score.map { $0 * 10 }, repeatCount: repeatCount,
                                                      lists: lists))
        guard TrackerAccountManager.shared.isLoggedIn(.anilist),
              TrackerAccountManager.shared.isSyncEnabled(for: .anilist) else {
            if let localEntry {
                completion(.success(localEntry))
            } else if Self.syncsToAnotherTracker {
                completion(.success(AnimeItem.MediaListEntry(listID: mediaID, status: status, progress: progress ?? 0,
                                                             score: score ?? 0, repeatCount: repeatCount ?? 0,
                                                             customLists: lists ?? [])))
            } else {
                completion(.failure(.unauthenticated))
            }
            return
        }

        var vars: [String: Any] = ["id": mediaID]
        if let s = status   { vars["status"] = s }
        if let p = progress { vars["progress"] = p }
        if let sc = score   { vars["score"] = sc * 10 }
        if let r = repeatCount { vars["repeat"] = r }

        var customLists = lists ?? []
        if !customLists.contains(AniListAuth.hayaseCustomListName) {
            customLists.append(AniListAuth.hayaseCustomListName)
        }
        vars["lists"] = customLists

        authRequestResult(query: AniListQueries.saveEntry, variables: vars, optimistic: true) { [weak self] result in
            guard let self else {
                completion(.failure(.cancelled))
                return
            }
            switch result {
            case .success(let data):
                guard let entry = data["SaveMediaListEntry"] as? [String: Any],
                      let listID = entry["id"] as? Int else {
                    completion(.failure(.emptyData))
                    return
                }
                var enabledLists: [String] = []
                if let cls = entry["customLists"] as? [[String: Any]] {
                    for cl in cls {
                        if let enabled = cl["enabled"] as? Bool, enabled,
                           let name = cl["name"] as? String {
                            enabledLists.append(name)
                        }
                    }
                }
                let resultMediaID = ((entry["media"] as? [String: Any])?["id"] as? Int) ?? mediaID
                let resultEntry = AnimeItem.MediaListEntry(
                    listID: listID,
                    status: entry["status"] as? String,
                    progress: self.jsonInt(entry["progress"]),
                    score: self.jsonInt(entry["score"]),
                    repeatCount: self.jsonInt(entry["repeat"]),
                    customLists: enabledLists)
                AniListMutationUpdaters.applyMediaListEntry(mediaID: resultMediaID, entry: resultEntry)
                self.updateCachedUserLists(mediaID: resultMediaID,
                                           status: resultEntry.status,
                                           refreshAfterUpdate: resultEntry.status == "COMPLETED") { [weak self] in
                    self?.notifyTrackingDidChange()
                }
                completion(.success(resultEntry))
            case .failure(let error):
                if AniListOfflineQueue.isOfflineError(error) {
                    // urql-client.ts `optimistic.SaveMediaListEntry`, kept until the device is online
                    AniListOfflineQueue.shared.enqueue(query: AniListQueries.saveEntry, variables: vars)
                    let optimisticEntry = AnimeItem.MediaListEntry(
                        listID: -Int.random(in: 1...999_999_999),
                        status: status,
                        progress: progress ?? 0,
                        score: score ?? 0,
                        repeatCount: repeatCount ?? 0,
                        customLists: customLists)
                    AniListMutationUpdaters.applyMediaListEntry(mediaID: mediaID, entry: optimisticEntry)
                    self.updateCachedUserLists(mediaID: mediaID,
                                               status: optimisticEntry.status,
                                               refreshAfterUpdate: false) { [weak self] in
                        self?.notifyTrackingDidChange()
                    }
                    completion(.success(optimisticEntry))
                } else if let localEntry {
                    NSLog("[AniListTracking] SaveMediaListEntry remote failed after local update: %@", error.description)
                    completion(.success(localEntry))
                } else {
                    completion(.failure(error))
                }
            }
        }
    }

    /// Kitsu, MAL or Simkl is signed in and on.
    private static var syncsToAnotherTracker: Bool {
        let manager = TrackerAccountManager.shared
        return [TrackerKind.kitsu, .mal, .simkl].contains { manager.isSyncEnabled(for: $0) && manager.viewer(for: $0) != nil }
    }

    // MARK: - deleteEntry()

    func deleteEntry(listID: Int, mediaID: Int? = nil, completion: ((Bool) -> Void)? = nil) {
        deleteEntryResult(listID: listID, mediaID: mediaID) { result in
            switch result {
            case .success(let deleted):
                completion?(deleted)
            case .failure(let error):
                NSLog("[AniListTracking] DeleteMediaListEntry failed: %@", error.description)
                completion?(false)
            }
        }
    }

    func deleteEntryResult(listID: Int,
                           mediaID: Int? = nil,
                           completion: @escaping (Result<Bool, AniListRequestError>) -> Void) {
        if let mediaID { TrackerAggregator.delete(mediaID: mediaID, malID: nil) }
        guard TrackerAccountManager.shared.isLoggedIn(.anilist),
              TrackerAccountManager.shared.isSyncEnabled(for: .anilist) else {
            guard TrackerAccountManager.shared.isSyncEnabled(for: .local) else {
                completion(Self.syncsToAnotherTracker ? .success(true) : .failure(.unauthenticated))
                return
            }
            completion(.success(LocalTracking.shared.delete(mediaID: mediaID ?? listID)))
            return
        }
        var localDeleteAttempted = false
        if TrackerAccountManager.shared.isSyncEnabled(for: .local),
           let mediaID {
            localDeleteAttempted = true
            _ = LocalTracking.shared.delete(mediaID: mediaID)
        }
        // client.ts `deleteEntry`: `!id || (id <= 0 && navigator.onLine)`, an entry that is not on AniList yet
        if listID <= 0, AniListConnectionStatus.shared.isOnline {
            completion(.success(localDeleteAttempted))
            return
        }

        authRequestResult(query: AniListQueries.deleteEntry, variables: ["id": listID], optimistic: true) { [weak self] result in
            switch result {
            case .success(let data):
                guard let payload = data["DeleteMediaListEntry"] as? [String: Any],
                      let deleted = payload["deleted"] as? Bool else {
                    completion(.failure(.emptyData))
                    return
                }
                if deleted {
                    if let mediaID {
                        AniListMutationUpdaters.applyMediaListEntry(mediaID: mediaID, entry: nil)
                        self?.updateCachedUserLists(mediaID: mediaID,
                                                    status: nil,
                                                    refreshAfterUpdate: true) { [weak self] in
                            self?.notifyTrackingDidChange()
                        }
                    } else {
                        self?.notifyTrackingDidChange()
                    }
                }
                completion(.success(deleted))
            case .failure(let error):
                if AniListOfflineQueue.isOfflineError(error) {
                    // `optimistic.DeleteMediaListEntry`
                    AniListOfflineQueue.shared.enqueue(query: AniListQueries.deleteEntry, variables: ["id": listID])
                    if let mediaID {
                        AniListMutationUpdaters.applyMediaListEntry(mediaID: mediaID, entry: nil)
                        self?.updateCachedUserLists(mediaID: mediaID, status: nil, refreshAfterUpdate: false) { [weak self] in
                            self?.notifyTrackingDidChange()
                        }
                    }
                    completion(.success(true))
                } else if localDeleteAttempted {
                    NSLog("[AniListTracking] DeleteMediaListEntry remote failed after local update: %@", error.description)
                    completion(.success(true))
                } else {
                    completion(.failure(error))
                }
            }
        }
    }

    // MARK: - watch()

    /// The few facts about a media that `watch` and `setInitialState` decide on.
    private struct TrackedMedia {
        let status: String?
        let episodes: Int?
        let scheduleEpisodes: Int
    }

    /// auth/client.ts `client.single(…)`, `?? outdated`: the media as AniList has it, and the one
    /// already known when AniList cannot be asked.
    private func trackedMedia(from payload: (entry: AnimeItem.MediaListEntry?, mediaStatus: String?, episodes: Int?, format: String?, duration: Int?, scheduleEpisodes: Int)?,
                              anilistID: Int,
                              episodesHint: Int?) -> TrackedMedia? {
        if let payload, payload.mediaStatus != nil {
            return TrackedMedia(status: payload.mediaStatus, episodes: payload.episodes, scheduleEpisodes: payload.scheduleEpisodes)
        }
        if let known = Router.shared.cachedAnimeItem(for: anilistID) {
            let scheduled = max(known.airedSchedule.last?.episode ?? 0, known.notYetAiredSchedule.last?.episode ?? 0)
            return TrackedMedia(status: known.status, episodes: known.episodes, scheduleEpisodes: scheduled)
        }
        if let episodesHint, episodesHint > 0 {
            return TrackedMedia(status: nil, episodes: episodesHint, scheduleEpisodes: 0)
        }
        return nil
    }

    /// `get(this.mediaListEntry(id))`: the viewer's lists, then the other trackers'.
    private func listedEntry(for mediaID: Int, fetched: AnimeItem.MediaListEntry?) -> AnimeItem.MediaListEntry? {
        fetched
            ?? AniListViewerState.shared.entry(for: mediaID, fallback: nil)
            ?? TrackerAggregator.externalEntry(for: mediaID)
    }

    func watch(anilistID: Int, episodeProgress: Int, episodesHint: Int? = nil) {
        // auth/client.ts `watch`: `!isFinite(progress) || progress < 0`
        guard episodeProgress >= 0 else { return }
        fetchMediaWithEntryResult(anilistID: anilistID) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                let payload = try? result.get()
                // without a media there is nothing to say whether this was the last episode
                guard let media = self.trackedMedia(from: payload, anilistID: anilistID, episodesHint: episodesHint) else { return }
                let currentEntry = self.listedEntry(for: anilistID, fetched: payload?.entry)

                // `episodes(media) || 1`: episodes or movie which is single episode
                let counted = (media.episodes ?? 0) != 0 ? (media.episodes ?? 0) : media.scheduleEpisodes
                let total = counted == 0 ? 1 : counted
                // woah, bad data from resolver?!
                if total < episodeProgress { return }

                let currentProgress = currentEntry?.progress ?? 0
                if currentProgress >= episodeProgress { return }

                // an airing show without an expected end has no episode count: do not complete it
                let canBeCompleted = media.status == "FINISHED" || media.episodes != nil

                let status: String
                if total == episodeProgress && canBeCompleted {
                    status = "COMPLETED"
                } else if currentEntry?.status == "REPEATING" {
                    status = "REPEATING"
                } else {
                    status = "CURRENT"
                }

                self.entry(mediaID: anilistID, status: status, progress: episodeProgress,
                          lists: currentEntry?.customLists ?? [])
            }
        }
    }

    // MARK: - setInitialState()

    /// `get(this.mediaListEntry(id))` for a viewer whose lists may not be in yet: AniList is asked about
    /// the one media when they are not. A nil entry that is not `known` is not "not on a list" but "cannot tell".
    private func entryForInitialState(anilistID: Int,
                                      completion: @escaping (_ entry: AnimeItem.MediaListEntry?, _ known: Bool) -> Void) {
        guard TrackerAccountManager.shared.isLoggedIn(.anilist), !AniListViewerState.shared.areListsLoaded else {
            completion(listedEntry(for: anilistID, fetched: nil), true)
            return
        }
        fetchMediaWithEntryResult(anilistID: anilistID) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success(let payload): completion(self.listedEntry(for: anilistID, fetched: payload.entry), true)
                case .failure: completion(nil, false)
                }
            }
        }
    }

    func setInitialState(anilistID: Int, episode: Int) {
        guard episode == 1 else { return }

        // `client.single(media.id, 'cache-first')`, for `episodes(media)` below
        AniListClient.shared.fetchResolverMediaByIdResult(anilistID) { [weak self] mediaResult in
            DispatchQueue.main.async {
                guard let self else { return }
                let media = (try? mediaResult.get()) ?? Router.shared.cachedAnimeItem(for: anilistID)
                self.entryForInitialState(anilistID: anilistID) { [weak self] currentEntry, known in
                    guard let self, known else { return }
                    guard let currentEntry else {
                        self.entry(mediaID: anilistID, status: "CURRENT", progress: 0)
                        return
                    }
                    let counted = media.map { AniListUtil.episodes(for: $0) } ?? 0

                    // for single episode media don't set to REPEATING, as restarting the app over and over
                    // again will keep setting it to REPEATING, then COMPLETED
                    if counted == 1 && currentEntry.status == "COMPLETED" { return }

                    let transitionStatuses = ["COMPLETED", "PLANNING", "PAUSED"]
                    guard transitionStatuses.contains(currentEntry.status ?? "") else { return }

                    let newStatus = currentEntry.status == "COMPLETED" ? "REPEATING" : "CURRENT"
                    self.entry(mediaID: anilistID, status: newStatus, progress: 0,
                              lists: currentEntry.customLists)
                }
            }
        }
    }

    // MARK: - User lists

    struct UserListIDs {
        let continueIDs: [Int]
        let planningIDs: [Int]
        let sequelIDs: [Int]
    }

    private let userListCacheTTL: TimeInterval = 120
    private let userListCacheQueue = DispatchQueue(label: "com.hayase.anilist.userListCache")
    private var cachedUserListViewerID: Int?
    private var cachedUserListIDs: UserListIDs?
    private var cachedUserListFetchedAt: Date?
    /// Who is waiting for the answer of which account: an answer for the account that was signed in
    /// before is not one for the account that is signed in now.
    private var userListFetchCompletions: [(viewerID: Int, completion: (UserListIDs?) -> Void)] = []

    func cachedUserLists() -> UserListIDs? {
        guard TrackerAccountManager.shared.isLoggedIn(.anilist),
              let viewerStr = TrackerAccountManager.shared.viewer(for: .anilist)?.id,
              let viewerID = Int(viewerStr) else {
            return nil
        }
        return userListCacheQueue.sync {
            cachedUserListViewerID == viewerID ? cachedUserListIDs : nil
        }
    }

    func fetchUserLists(forceRefresh: Bool = false, completion: @escaping (UserListIDs?) -> Void) {
        guard TrackerAccountManager.shared.isLoggedIn(.anilist) else {
            completion(nil); return
        }
        guard let viewerStr = TrackerAccountManager.shared.viewer(for: .anilist)?.id,
              let viewerID = Int(viewerStr) else {
            completion(nil); return
        }

        userListCacheQueue.async { [weak self] in
            guard let self else { return }
            if !forceRefresh,
               self.cachedUserListViewerID == viewerID,
               let cached = self.cachedUserListIDs,
               let fetchedAt = self.cachedUserListFetchedAt,
               Date().timeIntervalSince(fetchedAt) < self.userListCacheTTL {
                DispatchQueue.main.async { completion(cached) }
                return
            }

            let alreadyFetching = self.userListFetchCompletions.contains { $0.viewerID == viewerID }
            self.userListFetchCompletions.append((viewerID, completion))
            if alreadyFetching { return }

            self.authRequestResult(query: AniListQueries.userLists, variables: ["id": viewerID]) { [weak self] result in
                guard let self else { return }
                let parsedLists: (ids: UserListIDs, entries: [Int: AnimeItem.MediaListEntry])?
                switch result {
                case .success(let data):
                    parsedLists = self.parseUserLists(from: data)
                case .failure(let error):
                    NSLog("[AniListTracking] User lists failed: %@", error.description)
                    parsedLists = nil
                }
                let parsed = parsedLists?.ids
                self.userListCacheQueue.async {
                    let completions = self.userListFetchCompletions.filter { $0.viewerID == viewerID }
                    self.userListFetchCompletions.removeAll { $0.viewerID == viewerID }
                    if let parsedLists {
                        self.cachedUserListViewerID = viewerID
                        self.cachedUserListIDs = parsedLists.ids
                        self.cachedUserListFetchedAt = Date()
                        // `medialists`: in before anything that reads an entry is told the lists are here;
                        // the lists of an account that has been replaced since are of no use to the new one
                        if TrackerAccountManager.shared.viewer(for: .anilist)?.id == viewerStr {
                            AniListViewerState.shared.replaceEntries(parsedLists.entries, viewerID: viewerID,
                                                                     keepingChanges: AniListOfflineQueue.shared.hasPending)
                        }
                    }
                    DispatchQueue.main.async {
                        completions.forEach { $0.completion(parsed) }
                    }
                }
            }
        }
    }

    private func jsonOptionalInt(_ value: Any?) -> Int? {
        if let i = value as? Int { return i }
        if let n = value as? NSNumber { return n.intValue }
        return nil
    }

    /// client.ts `medialists`, `continueIDs`, `planningIDs` and `sequelIDs`, all of them derived from
    /// the one `UserLists` answer. The entries speak for themselves: AniList answers `null` for the
    /// `mediaListEntry` of a media inside a list, so nothing is read from there.
    private func parseUserLists(from data: [String: Any]?) -> (ids: UserListIDs, entries: [Int: AnimeItem.MediaListEntry])? {
        guard let collection = data?["MediaListCollection"] as? [String: Any],
              let lists = collection["lists"] as? [[String: Any]] else {
            return nil
        }

        func entries(of list: [String: Any]) -> [[String: Any]] {
            list["entries"] as? [[String: Any]] ?? []
        }

        // `medialists`: `if (entry?.mediaId) map.set(entry.mediaId, entry)`, over every list
        var byMedia: [Int: AnimeItem.MediaListEntry] = [:]
        for list in lists {
            for entry in entries(of: list) {
                guard let mediaID = jsonOptionalInt(entry["mediaId"]), mediaID != 0 else { continue }
                var enabledLists: [String] = []
                for customList in entry["customLists"] as? [[String: Any]] ?? [] {
                    if customList["enabled"] as? Bool == true, let name = customList["name"] as? String {
                        enabledLists.append(name)
                    }
                }
                byMedia[mediaID] = AnimeItem.MediaListEntry(
                    listID: jsonOptionalInt(entry["id"]) ?? 0,
                    status: entry["status"] as? String,
                    progress: jsonOptionalInt(entry["progress"]) ?? 0,
                    score: jsonOptionalInt(entry["score"]) ?? 0,
                    repeatCount: jsonOptionalInt(entry["repeat"]) ?? 0,
                    customLists: enabledLists)
            }
        }

        var continueIDs: [Int] = []
        var planningIDs: [Int] = []
        var sequelIDs: [Int] = []

        // `continueIDs`: the entries of the lists that are CURRENT or REPEATING
        for list in lists where ["CURRENT", "REPEATING"].contains(list["status"] as? String ?? "") {
            for entry in entries(of: list) {
                guard let mediaID = jsonOptionalInt(entry["mediaId"]), mediaID != 0 else { continue }
                let media = entry["media"] as? [String: Any]
                if media?["status"] as? String == "FINISHED" {
                    continueIDs.append(mediaID)
                    continue
                }
                let progress = jsonOptionalInt(entry["progress"]) ?? 0
                // +2 is for series that don't have the next airing episode scheduled, but are still some-how
                // airing; -1 is because the latest aired episode counts, not the next one
                let nextEpisode = jsonOptionalInt((media?["nextAiringEpisode"] as? [String: Any])?["episode"]) ?? (progress + 2)
                if progress < nextEpisode - 1 { continueIDs.append(mediaID) }
            }
        }

        // `planningIDs`: the PLANNING list's media
        if let planning = lists.first(where: { $0["status"] as? String == "PLANNING" }) {
            for entry in entries(of: planning) {
                if let mediaID = jsonOptionalInt(entry["mediaId"]), mediaID != 0 { planningIDs.append(mediaID) }
            }
        }

        // `sequelIDs`: the sequels of what is COMPLETED
        if let completed = lists.first(where: { $0["status"] as? String == "COMPLETED" }) {
            for entry in entries(of: completed) {
                let edges = ((entry["media"] as? [String: Any])?["relations"] as? [String: Any])?["edges"] as? [[String: Any]] ?? []
                for edge in edges where edge["relationType"] as? String == "SEQUEL" {
                    if let nodeID = jsonOptionalInt((edge["node"] as? [String: Any])?["id"]) { sequelIDs.append(nodeID) }
                }
            }
        }

        return (UserListIDs(continueIDs: continueIDs,
                            planningIDs: planningIDs,
                            sequelIDs: orderedUnique(sequelIDs)),
                byMedia)
    }

    private func orderedUnique(_ ids: [Int]) -> [Int] {
        var seen = Set<Int>()
        var result: [Int] = []
        for id in ids where seen.insert(id).inserted {
            result.append(id)
        }
        return result
    }

    private func updateCachedUserLists(mediaID: Int,
                                       status: String?,
                                       refreshAfterUpdate: Bool = false,
                                       completion: (() -> Void)? = nil) {
        userListCacheQueue.async { [weak self] in
            guard let self, var cached = self.cachedUserListIDs else {
                DispatchQueue.main.async { completion?() }
                return
            }
            cached = UserListIDs(
                continueIDs: cached.continueIDs.filter { $0 != mediaID },
                planningIDs: cached.planningIDs.filter { $0 != mediaID },
                sequelIDs: cached.sequelIDs.filter { $0 != mediaID })
            if status == "PLANNING" {
                cached = UserListIDs(
                    continueIDs: cached.continueIDs,
                    planningIDs: [mediaID] + cached.planningIDs,
                    sequelIDs: cached.sequelIDs)
            } else if status == "CURRENT" || status == "REPEATING" {
                cached = UserListIDs(
                    continueIDs: [mediaID] + cached.continueIDs,
                    planningIDs: cached.planningIDs,
                    sequelIDs: cached.sequelIDs)
            }
            self.cachedUserListIDs = cached
            self.cachedUserListFetchedAt = Date()
            DispatchQueue.main.async { [weak self] in
                guard refreshAfterUpdate else {
                    completion?()
                    return
                }
                self?.fetchUserLists(forceRefresh: true) { _ in
                    completion?()
                }
            }
        }
    }

    func clearViewerCache() {
        userListCacheQueue.async { [weak self] in
            self?.cachedUserListViewerID = nil
            self?.cachedUserListIDs = nil
            self?.cachedUserListFetchedAt = nil
            self?.userListFetchCompletions.removeAll()
        }
    }

    // MARK: - Toggle Favourite

    func toggleFavourite(mediaID: Int, completion: ((Bool) -> Void)? = nil) {
        toggleFavouriteResult(mediaID: mediaID) { result in
            switch result {
            case .success:
                completion?(true)
            case .failure(let error):
                NSLog("[AniListTracking] ToggleFavourite failed: %@", error.description)
                completion?(false)
            }
        }
    }

    func toggleFavouriteResult(mediaID: Int,
                               completion: @escaping (Result<Bool, AniListRequestError>) -> Void) {
        // `toggleFav`: AniList, Kitsu and the local list, each when it is signed in; no sync switch asks
        let localFavourite = LocalTracking.shared.toggleFavourite(mediaID: mediaID)
        let kitsuSignedIn = KitsuSync.shared.isSignedIn
        guard TrackerAccountManager.shared.isLoggedIn(.anilist) else {
            guard kitsuSignedIn else {
                AniListMutationUpdaters.applyFavourite(mediaID: mediaID, isFavourite: localFavourite)
                notifyTrackingDidChange()
                completion(.success(localFavourite))
                return
            }
            Task {
                await KitsuSync.shared.toggleFavourite(mediaID: mediaID)
                let isFavourite = KitsuSync.shared.isFavourite(mediaID: mediaID)
                AniListMutationUpdaters.applyFavourite(mediaID: mediaID, isFavourite: isFavourite)
                self.notifyTrackingDidChange()
                completion(.success(isFavourite))
            }
            return
        }
        if kitsuSignedIn { Task { await KitsuSync.shared.toggleFavourite(mediaID: mediaID) } }

        authRequestResult(query: AniListQueries.toggleFavourite, variables: ["id": mediaID], optimistic: true) { [weak self] result in
            switch result {
            case .success(let data):
                guard let payload = data["ToggleFavourite"] as? [String: Any] else {
                    completion(.failure(.emptyData))
                    return
                }
                let nodes = ((payload["anime"] as? [String: Any])?["nodes"] as? [[String: Any]]) ?? []
                let isFavourite = nodes.contains { ($0["id"] as? Int) == mediaID }
                AniListMutationUpdaters.applyFavourite(mediaID: mediaID, isFavourite: isFavourite)
                self?.notifyTrackingDidChange()
                completion(.success(isFavourite))
            case .failure(let error):
                if AniListOfflineQueue.isOfflineError(error) {
                    // `optimistic.ToggleFavourite`
                    AniListOfflineQueue.shared.enqueue(query: AniListQueries.toggleFavourite, variables: ["id": mediaID])
                }
                NSLog("[AniListTracking] ToggleFavourite remote failed after local update: %@", error.description)
                AniListMutationUpdaters.applyFavourite(mediaID: mediaID, isFavourite: localFavourite)
                self?.notifyTrackingDidChange()
                completion(.success(localFavourite))
            }
        }
    }

    // MARK: - Bookmark

    /// bookmark.svelte: a media that is on the list comes off it, any other goes on as PLANNING.
    /// What the lists say of the media decides, as it does for the icon that was pressed.
    func toggleBookmark(media: AnimeItem, completion: ((Bool) -> Void)? = nil) {
        let mediaID = media.id
        if let current = media.listEntry {
            deleteEntry(listID: current.listID, mediaID: mediaID) { deleted in
                DispatchQueue.main.async { completion?(deleted) }
            }
        } else {
            entry(mediaID: mediaID, status: "PLANNING") { entry in
                DispatchQueue.main.async { completion?(entry != nil) }
            }
        }
    }
}
