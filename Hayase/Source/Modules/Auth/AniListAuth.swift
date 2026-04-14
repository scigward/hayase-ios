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
        URL(string: "https://anilist.co/api/v2/oauth/authorize?client_id=\(clientID)&response_type=token")!
    }

    static func fetchViewer(token: String, completion: @escaping (TrackerViewer?) -> Void) {
        let query = """
        { Viewer { id name avatar { large } } }
        """
        var request = URLRequest(url: URL(string: "https://graphql.anilist.co")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["query": query]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let dataObj = json["data"] as? [String: Any],
                  let viewer = dataObj["Viewer"] as? [String: Any],
                  let id = viewer["id"] as? Int,
                  let name = viewer["name"] as? String else {
                completion(nil)
                return
            }
            let avatar = (viewer["avatar"] as? [String: Any])?["large"] as? String
            let tv = TrackerViewer(id: String(id), name: name, avatarURL: avatar)
            completion(tv)
        }.resume()
    }

    static func completeLogin(token: String) {
        TrackerAccountManager.shared.setToken(token, for: .anilist)
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
            title { english romaji }
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

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                NSLog("[AniListTracking] authRequest network error: %@", error.localizedDescription)
                completion(nil); return
            }
            guard let data = data else {
                NSLog("[AniListTracking] authRequest: no data received")
                completion(nil); return
            }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                NSLog("[AniListTracking] authRequest: failed to parse JSON")
                completion(nil); return
            }
            if let errors = json["errors"] as? [[String: Any]] {
                let messages = errors.compactMap { $0["message"] as? String }
                NSLog("[AniListTracking] GraphQL errors: %@", messages.joined(separator: ", "))
            }
            guard let dataObj = json["data"] as? [String: Any] else {
                NSLog("[AniListTracking] authRequest: no 'data' field in response")
                completion(nil); return
            }
            completion(dataObj)
        }.resume()
    }

    // MARK: - Fetch current list entry

    func fetchMediaWithEntry(anilistID: Int, completion: @escaping (AnimeItem.MediaListEntry?, String?, Int?, String?, Int?) -> Void) {
        authRequest(query: singleMediaQuery, variables: ["id": anilistID]) { [weak self] data in
            guard let self else { completion(nil, nil, nil, nil, nil); return }
            guard let media = data?["Media"] as? [String: Any] else {
                completion(nil, nil, nil, nil, nil); return
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
            completion(entry, mediaStatus, episodes, format, duration)
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
        guard TrackerAccountManager.shared.isLoggedIn(.anilist),
              TrackerAccountManager.shared.isSyncEnabled(for: .anilist) else {
            completion?(nil); return
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
            let result = AnimeItem.MediaListEntry(
                listID: listID,
                status: entry["status"] as? String,
                progress: self.jsonInt(entry["progress"]),
                score: self.jsonInt(entry["score"]),
                repeatCount: self.jsonInt(entry["repeat"]),
                customLists: enabledLists)
            completion?(result)
        }
    }

    // MARK: - deleteEntry()

    func deleteEntry(listID: Int, completion: ((Bool) -> Void)? = nil) {
        guard TrackerAccountManager.shared.isLoggedIn(.anilist),
              TrackerAccountManager.shared.isSyncEnabled(for: .anilist) else {
            completion?(false); return
        }

        authRequest(query: deleteEntryMutation, variables: ["id": listID]) { data in
            let deleted = (data?["DeleteMediaListEntry"] as? [String: Any])?["deleted"] as? Bool ?? false
            completion?(deleted)
        }
    }

    // MARK: - watch()

    func watch(anilistID: Int, episodeProgress: Int) {
        fetchMediaWithEntry(anilistID: anilistID) { [weak self] currentEntry, mediaStatus, totalEps, _, _ in
            guard let self else { return }

            guard mediaStatus != nil else {
                NSLog("[AniListTracking] watch: fetchMediaWithEntry returned nil — attempting direct entry update for ep %d", episodeProgress)
                self.entry(mediaID: anilistID, status: "CURRENT", progress: episodeProgress)
                return
            }

            let total = totalEps ?? max(1, episodeProgress)
            if total < episodeProgress { return }

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

    func fetchUserLists(completion: @escaping (UserListIDs?) -> Void) {
        guard TrackerAccountManager.shared.isLoggedIn(.anilist) else {
            completion(nil); return
        }
        guard let viewerStr = TrackerAccountManager.shared.viewer(for: .anilist)?.id,
              let viewerID = Int(viewerStr) else {
            completion(nil); return
        }

        authRequest(query: userListsQuery, variables: ["id": viewerID]) { data in
            guard let collection = data?["MediaListCollection"] as? [String: Any],
                  let lists = collection["lists"] as? [[String: Any]] else {
                completion(nil); return
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

            let uniqueSequelIDs = Array(Set(sequelIDs))

            completion(UserListIDs(
                continueIDs: continueIDs,
                planningIDs: planningIDs,
                sequelIDs: uniqueSequelIDs))
        }
    }

    // MARK: - Fetch progress

    func fetchProgress(anilistID: Int, completion: @escaping (Int?) -> Void) {
        guard TrackerAccountManager.shared.isLoggedIn(.anilist) else {
            completion(nil); return
        }
        fetchMediaWithEntry(anilistID: anilistID) { entry, _, _, _, _ in
            completion(entry?.progress)
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
        authRequest(query: toggleFavouriteMutation, variables: ["animeId": mediaID]) { data in
            let success = data?["ToggleFavourite"] != nil
            completion?(success)
        }
    }

    func checkIsFavourite(mediaID: Int, completion: @escaping (Bool) -> Void) {
        authRequest(query: isFavouriteQuery, variables: ["id": mediaID]) { data in
            let isFav = (data?["Media"] as? [String: Any])?["isFavourite"] as? Bool ?? false
            completion(isFav)
        }
    }
}
