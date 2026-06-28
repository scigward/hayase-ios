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

    static func fetchViewer(token: String, completion: @escaping (TrackerViewer?) -> Void) {
        let query = """
        {
          Viewer {
            id
            name
            bannerImage
            avatar { large }
            mediaListOptions { animeList { customLists } }
            options { titleLanguage displayAdultContent }
          }
        }
        """
        guard let url = URL(string: "https://graphql.anilist.co") else {
            completion(nil)
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["query": query]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        AniListRequestExecutor.shared.perform(request, context: "AniListViewer") { result in
            guard case .success(let data) = result,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let dataObj = json["data"] as? [String: Any],
                  let viewer = dataObj["Viewer"] as? [String: Any],
                  let id = viewer["id"] as? Int,
                  let name = viewer["name"] as? String else {
                completion(nil)
                return
            }
            let avatar = (viewer["avatar"] as? [String: Any])?["large"] as? String
            let options = viewer["options"] as? [String: Any]
            let animeList = (viewer["mediaListOptions"] as? [String: Any])?["animeList"] as? [String: Any]
            let customLists = animeList?["customLists"] as? [String] ?? []
            let tv = TrackerViewer(
                id: String(id),
                name: name,
                avatarURL: avatar,
                bannerURL: viewer["bannerImage"] as? String,
                titleLanguage: options?["titleLanguage"] as? String,
                displayAdultContent: options?["displayAdultContent"] as? Bool,
                customLists: customLists)
            completion(tv)
        }
    }

    static func completeLogin(token: String, expiresIn: TimeInterval? = nil) {
        let expiresAt = expiresIn.map { Date().addingTimeInterval($0) }
        TrackerAccountManager.shared.setToken(token, for: .anilist, expiresAt: expiresAt)
        fetchViewer(token: token) { viewer in
            DispatchQueue.main.async {
                TrackerAccountManager.shared.setViewer(viewer, for: .anilist)
            }
        }
    }
}

// MARK: - AniList Tracking

final class AniListTracking {
    static let shared = AniListTracking()
    private init() {}

    private let endpoint = "https://graphql.anilist.co"

    private func notifyTrackingDidChange() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: LocalTracking.didChange, object: self)
        }
    }

    // MARK: - Mutations

    private let saveEntryMutation = """
    mutation ($lists: [String], $id: Int!, $status: MediaListStatus, $progress: Int, $repeat: Int, $score: Int) {
        SaveMediaListEntry(mediaId: $id, status: $status, progress: $progress, repeat: $repeat, scoreRaw: $score, customLists: $lists) {
            id
            status
            progress
            score(format: POINT_10)
            repeat
            customLists(asArray: true)
            media { id }
        }
    }
    """

    private let deleteEntryMutation = """
    mutation ($id: Int!) {
        DeleteMediaListEntry(id: $id) {
            deleted
        }
    }
    """

    private let singleMediaQuery = """
    query ($id: Int!) {
        Media(id: $id, type: ANIME) {
            id
            status
            episodes
            format
            duration
            title { romaji english native userPreferred }
            synonyms
            mediaListEntry {
                id
                status
                progress
                score(format: POINT_10)
                repeat
                customLists(asArray: true)
            }
        }
    }
    """

    // MARK: - Private helpers

    private func jsonInt(_ value: Any?) -> Int {
        if let i = value as? Int { return i }
        if let n = value as? NSNumber { return n.intValue }
        return 0
    }

    private func authRequest(query: String, variables: [String: Any], completion: @escaping ([String: Any]?) -> Void) {
        guard let token = TrackerAccountManager.shared.token(for: .anilist),
              let url = URL(string: endpoint) else {
            NSLog("[AniListTracking] authRequest: no token or invalid endpoint")
            completion(nil); return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["query": query, "variables": variables]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        AniListRequestExecutor.shared.perform(request, context: "AniListTracking") { result in
            guard case .success(let data) = result else {
                if case .failure(let error) = result, case .cancelled = error { return }
                if case .failure(let error) = result {
                    NSLog("[AniListTracking] authRequest failed: %@", error.description)
                }
                completion(nil); return
            }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                NSLog("[AniListTracking] authRequest: failed to parse JSON")
                completion(nil); return
            }
            guard let dataObj = json["data"] as? [String: Any] else {
                NSLog("[AniListTracking] authRequest: no 'data' field in response")
                completion(nil); return
            }
            completion(dataObj)
        }
    }

    // MARK: - Fetch current list entry

    func fetchMediaWithEntry(anilistID: Int, completion: @escaping (AnimeItem.MediaListEntry?, String?, Int?, String?, Int?) -> Void) {
        authRequest(query: singleMediaQuery, variables: ["id": anilistID]) { [weak self] data in
            guard let self else { completion(nil, nil, nil, nil, nil); return }
            guard let media = data?["Media"] as? [String: Any] else {
                completion(LocalTracking.shared.entry(for: anilistID), nil, nil, nil, nil); return
            }
            let mediaStatus = media["status"] as? String
            let episodes = media["episodes"] as? Int
            let format = media["format"] as? String
            let duration = media["duration"] as? Int

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
            completion(entry ?? LocalTracking.shared.entry(for: anilistID), mediaStatus, episodes, format, duration)
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
        let localEntry = LocalTracking.shared.entry(
            mediaID: mediaID,
            status: status,
            progress: progress,
            score: score,
            repeatCount: repeatCount,
            lists: lists)
        guard TrackerAccountManager.shared.isLoggedIn(.anilist),
              TrackerAccountManager.shared.isSyncEnabled(for: .anilist) else {
            completion?(localEntry); return
        }

        var vars: [String: Any] = ["id": mediaID]
        if let s = status   { vars["status"] = s }
        if let p = progress { vars["progress"] = p }
        if let sc = score   { vars["score"] = sc * 10 }
        if let r = repeatCount { vars["repeat"] = r }

        var customLists = lists ?? []
        if !customLists.contains("Watched using Hayase") {
            customLists.append("Watched using Hayase")
        }
        vars["lists"] = customLists

        authRequest(query: saveEntryMutation, variables: vars) { [weak self] data in
            guard let self else { completion?(nil); return }
            guard let entry = data?["SaveMediaListEntry"] as? [String: Any],
                  let listID = entry["id"] as? Int else {
                completion?(nil); return
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
            let result = AnimeItem.MediaListEntry(
                listID: listID,
                status: entry["status"] as? String,
                progress: self.jsonInt(entry["progress"]),
                score: self.jsonInt(entry["score"]),
                repeatCount: self.jsonInt(entry["repeat"]),
                customLists: enabledLists)
            AniListClient.shared.updateMediaListEntry(mediaID: resultMediaID, entry: result)
            self.updateCachedUserLists(mediaID: resultMediaID,
                                       status: result.status,
                                       refreshAfterUpdate: result.status == "COMPLETED") { [weak self] in
                self?.notifyTrackingDidChange()
            }
            completion?(result)
        }
    }

    // MARK: - deleteEntry()

    func deleteEntry(listID: Int, mediaID: Int? = nil, completion: ((Bool) -> Void)? = nil) {
        guard TrackerAccountManager.shared.isLoggedIn(.anilist),
              TrackerAccountManager.shared.isSyncEnabled(for: .anilist) else {
            completion?(LocalTracking.shared.delete(mediaID: mediaID ?? listID)); return
        }

        authRequest(query: deleteEntryMutation, variables: ["id": listID]) { [weak self] data in
            let deleted = (data?["DeleteMediaListEntry"] as? [String: Any])?["deleted"] as? Bool ?? false
            if deleted {
                if let mediaID {
                    AniListClient.shared.updateMediaListEntry(mediaID: mediaID, entry: nil)
                    self?.updateCachedUserLists(mediaID: mediaID,
                                                status: nil,
                                                refreshAfterUpdate: true) { [weak self] in
                        self?.notifyTrackingDidChange()
                    }
                } else {
                    self?.notifyTrackingDidChange()
                }
            }
            completion?(deleted)
        }
    }

    // MARK: - watch()

    func watch(anilistID: Int, episodeProgress: Int) {
        LocalTracking.shared.watch(anilistID: anilistID, episodeProgress: episodeProgress)
        fetchMediaWithEntry(anilistID: anilistID) { [weak self] currentEntry, mediaStatus, totalEps, _, _ in
            guard let self else { return }

            guard mediaStatus != nil else {
                NSLog("[AniListTracking] watch: fetchMediaWithEntry returned nil — attempting direct entry update for ep %d", episodeProgress)
                self.entry(mediaID: anilistID, status: "CURRENT", progress: episodeProgress)
                return
            }

            let total = totalEps ?? max(1, episodeProgress)
            if total < episodeProgress { return }
            LocalTracking.shared.watch(anilistID: anilistID, episodeProgress: episodeProgress, totalEpisodes: total)

            let currentProgress = currentEntry?.progress ?? 0
            if currentProgress >= episodeProgress { return }

            let canBeCompleted = mediaStatus == "FINISHED" || totalEps != nil

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

    // MARK: - setInitialState()

    func setInitialState(anilistID: Int, episode: Int) {
        LocalTracking.shared.setInitialState(anilistID: anilistID, episode: episode)
        guard episode == 1 else { return }

        fetchMediaWithEntry(anilistID: anilistID) { [weak self] currentEntry, _, totalEps, _, _ in
            guard let self else { return }

            guard let currentEntry else {
                self.entry(mediaID: anilistID, status: "CURRENT", progress: 0)
                return
            }

            if totalEps == 1 && currentEntry.status == "COMPLETED" { return }

            let transitionStatuses = ["COMPLETED", "PLANNING", "PAUSED"]
            guard transitionStatuses.contains(currentEntry.status ?? "") else { return }

            let newStatus = currentEntry.status == "COMPLETED" ? "REPEATING" : "CURRENT"
            self.entry(mediaID: anilistID, status: newStatus, progress: 0,
                      lists: currentEntry.customLists)
        }
    }

    // MARK: - User lists

    private let userListsQuery = """
    query ($id: Int) {
        MediaListCollection(userId: $id, type: ANIME, forceSingleCompletedList: true, sort: UPDATED_TIME_DESC) {
            lists {
                status
                entries {
                    id
                    media {
                        id
                        status
                        episodes
                        mediaListEntry {
                            id
                            status
                            progress
                            score(format: POINT_10)
                            repeat
                        }
                        nextAiringEpisode {
                            episode
                        }
                        relations {
                            edges {
                                relationType(version: 2)
                                node {
                                    id
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    """

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
    private var userListFetchCompletions: [((UserListIDs?) -> Void)] = []

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

            let alreadyFetching = !self.userListFetchCompletions.isEmpty
            self.userListFetchCompletions.append(completion)
            if alreadyFetching { return }

            self.authRequest(query: self.userListsQuery, variables: ["id": viewerID]) { [weak self] data in
                guard let self else { return }
                let parsed = self.parseUserListIDs(from: data)
                self.userListCacheQueue.async {
                    let completions = self.userListFetchCompletions
                    self.userListFetchCompletions = []
                    if let parsed {
                        self.cachedUserListViewerID = viewerID
                        self.cachedUserListIDs = parsed
                        self.cachedUserListFetchedAt = Date()
                    }
                    DispatchQueue.main.async {
                        completions.forEach { $0(parsed) }
                    }
                }
            }
        }
    }

    private func parseUserListIDs(from data: [String: Any]?) -> UserListIDs? {
        guard let collection = data?["MediaListCollection"] as? [String: Any],
              let lists = collection["lists"] as? [[String: Any]] else {
            return nil
        }

        var continueIDs: [Int] = []
        var planningIDs: [Int] = []
        var sequelIDs: [Int] = []

        for list in lists {
            let status = list["status"] as? String
            let entries = list["entries"] as? [[String: Any]] ?? []

            if status == "CURRENT" || status == "REPEATING" {
                for entry in entries {
                    guard let media = entry["media"] as? [String: Any],
                          let mediaID = media["id"] as? Int else { continue }
                    let mediaStatus = media["status"] as? String
                    if mediaStatus == "FINISHED" {
                        continueIDs.append(mediaID)
                    } else {
                        let progress: Int
                        if let mle = media["mediaListEntry"] as? [String: Any] {
                            progress = (mle["progress"] as? Int) ?? 0
                        } else {
                            progress = 0
                        }
                        let nextEp: Int
                        if let nae = media["nextAiringEpisode"] as? [String: Any] {
                            nextEp = (nae["episode"] as? Int) ?? (progress + 2)
                        } else {
                            nextEp = progress + 2
                        }
                        if progress < nextEp - 1 {
                            continueIDs.append(mediaID)
                        }
                    }
                }
            } else if status == "PLANNING" {
                for entry in entries {
                    guard let media = entry["media"] as? [String: Any],
                          let mediaID = media["id"] as? Int else { continue }
                    planningIDs.append(mediaID)
                }
            } else if status == "COMPLETED" {
                for entry in entries {
                    guard let media = entry["media"] as? [String: Any],
                          let relations = media["relations"] as? [String: Any],
                          let edges = relations["edges"] as? [[String: Any]] else { continue }
                    for edge in edges {
                        if edge["relationType"] as? String == "SEQUEL",
                           let node = edge["node"] as? [String: Any],
                           let nodeID = node["id"] as? Int {
                            sequelIDs.append(nodeID)
                        }
                    }
                }
            }
        }

        return UserListIDs(
            continueIDs: continueIDs,
            planningIDs: planningIDs,
            sequelIDs: orderedUnique(sequelIDs))
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

    // MARK: - Fetch progress

    func fetchProgress(anilistID: Int, completion: @escaping (Int?) -> Void) {
        let localProgress = LocalTracking.shared.progress(for: anilistID)
        guard TrackerAccountManager.shared.isLoggedIn(.anilist) else {
            completion(localProgress); return
        }
        fetchMediaWithEntry(anilistID: anilistID) { entry, _, _, _, _ in
            completion(max(entry?.progress ?? 0, localProgress ?? 0))
        }
    }

    // MARK: - Toggle Favourite

    private let toggleFavouriteMutation = """
    mutation ($animeId: Int) {
        ToggleFavourite(animeId: $animeId) {
            anime { nodes { id } }
        }
    }
    """

    private let isFavouriteQuery = """
    query ($id: Int) {
        Media(id: $id) {
            isFavourite
        }
    }
    """

    func toggleFavourite(mediaID: Int, completion: ((Bool) -> Void)? = nil) {
        authRequest(query: toggleFavouriteMutation, variables: ["animeId": mediaID]) { [weak self] data in
            guard let result = data?["ToggleFavourite"] as? [String: Any] else {
                completion?(false)
                return
            }
            let nodes = ((result["anime"] as? [String: Any])?["nodes"] as? [[String: Any]]) ?? []
            let isFavourite = nodes.contains { ($0["id"] as? Int) == mediaID }
            AniListClient.shared.updateFavouriteState(mediaID: mediaID, isFavourite: isFavourite)
            self?.notifyTrackingDidChange()
            completion?(true)
        }
    }

    func checkIsFavourite(mediaID: Int, completion: @escaping (Bool) -> Void) {
        authRequest(query: isFavouriteQuery, variables: ["id": mediaID]) { data in
            let isFav = (data?["Media"] as? [String: Any])?["isFavourite"] as? Bool ?? false
            completion(isFav)
        }
    }
}
