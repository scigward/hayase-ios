//
//  KitsuSync.swift
//  Hayase
//
//  Mirrors: interface lib/modules/auth/kitsu.ts (`KitsuSync`).
//

import Foundation

final class KitsuSync: ListTracker {
    static let shared = KitsuSync()

    private enum Endpoint {
        static let oauth = "https://kitsu.app/api/oauth/token"
        static let user = "https://kitsu.app/api/edge/users"
        static let library = "https://kitsu.app/api/edge/library-entries"
        static let favourites = "https://kitsu.app/api/edge/favorites"
    }

    private static let kitsuToALStatus: [String: String] = [
        "current": "CURRENT", "planned": "PLANNING", "completed": "COMPLETED", "dropped": "DROPPED", "on_hold": "PAUSED",
    ]
    private static let alToKitsuStatus: [String: String] = [
        "CURRENT": "current", "PLANNING": "planned", "COMPLETED": "completed", "DROPPED": "dropped",
        "PAUSED": "on_hold", "REPEATING": "current",
    ]

    private let stateLock = NSLock()
    /// `favorites`: kitsu anime id to kitsu favourite id
    private var favourites: [String: String] = [:]
    private var kitsuToAL: [String: String] = [:]
    private var alToKitsu: [String: String] = [:]

    private init() {
        super.init(kind: .kitsu)
    }

    /// `this.auth.subscribe(auth => { if (auth) this._user() })`
    func start() {
        guard TrackerAuthStore.load(.kitsu) != nil else { return }
        Task { await loadUser() }
    }

    func signedOut() {
        TrackerAuthStore.save(nil, for: .kitsu)
        stateLock.lock()
        favourites = [:]
        kitsuToAL = [:]
        alToKitsu = [:]
        stateLock.unlock()
        clear()
    }

    // MARK: - Requests

    /// What `_request` hands back: the JSON of the answer and whether it said it was an error.
    private struct Answer {
        var json: [String: Any]?
        var isError: Bool
    }

    private func request(_ url: URL, method: String, body: [String: Any]? = nil) async -> Answer {
        var auth = TrackerAuthStore.load(.kitsu)
        if let current = auth, current.isStale {
            auth = await refresh(current)
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/vnd.api+json", forHTTPHeaderField: "Content-Type")
        request.setValue(auth.map { "Bearer \($0.accessToken)" } ?? "", forHTTPHeaderField: "Authorization")
        if let body { request.httpBody = try? JSONSerialization.data(withJSONObject: body) }
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            if method == "DELETE" { return Answer(json: nil, isError: false) }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw URLError(.cannotParseResponse)
            }
            if json["error"] != nil {
                TrackerToast.error("Kitsu Error", json["error_description"] as? String ?? "")
                return Answer(json: json, isError: true)
            }
            if let errors = json["errors"] as? [[String: Any]] {
                for error in errors { TrackerToast.error("Kitsu Error", error["detail"] as? String ?? "") }
                return Answer(json: json, isError: true)
            }
            return Answer(json: json, isError: false)
        } catch {
            TrackerToast.error("Kitsu Error", error.localizedDescription)
            return Answer(json: nil, isError: true)
        }
    }

    private func get(_ target: String, _ parameters: [(String, String)] = []) async -> Answer {
        guard var components = URLComponents(string: target) else { return Answer(json: nil, isError: true) }
        components.queryItems = parameters.map { URLQueryItem(name: $0.0, value: $0.1) }
        guard let url = components.url else { return Answer(json: nil, isError: true) }
        return await request(url, method: "GET")
    }

    private func refresh(_ auth: TrackerOAuth) async -> TrackerOAuth {
        guard let refreshToken = auth.refreshToken, let url = URL(string: Endpoint.oauth) else { return auth }
        let answer = await request(url, method: "POST", body: ["grant_type": "refresh_token", "refresh_token": refreshToken])
        if let json = answer.json, let renewed = TrackerOAuth(json: json) {
            TrackerAuthStore.save(renewed, for: .kitsu)
            return renewed
        }
        return auth
    }

    // MARK: - Login

    func login(username: String, password: String) async -> Bool {
        guard let url = URL(string: Endpoint.oauth) else { return false }
        let answer = await request(url, method: "POST", body: ["grant_type": "password", "username": username, "password": password])
        guard let json = answer.json, let auth = TrackerOAuth(json: json) else { return false }
        TrackerAuthStore.save(auth, for: .kitsu)
        await loadUser()
        return isSignedIn
    }

    // MARK: - The user and the list

    private func loadUser() async {
        let answer = await get(Endpoint.user, [
            ("filter[self]", "true"),
            ("include", "favorites.item,libraryEntries.anime,libraryEntries.anime.mappings"),
            ("fields[users]", "name,about,avatar,coverImage,createdAt"),
            ("fields[anime]", "status,episodeCount,mappings"),
            ("fields[mappings]", "externalSite,externalId"),
            ("fields[libraryEntries]", "anime,progress,status,reconsumeCount,reconsuming,rating"),
        ])
        guard !answer.isError, let json = answer.json,
              let user = (json["data"] as? [[String: Any]])?.first else { return }

        entriesToMediaList(json)

        let attributes = user["attributes"] as? [String: Any]
        let viewer = TrackerViewer(
            id: user["id"] as? String ?? "",
            name: attributes?["name"] as? String ?? "",
            avatarURL: (attributes?["avatar"] as? [String: Any])?["original"] as? String,
            bannerURL: (attributes?["coverImage"] as? [String: Any])?["original"] as? String)
        await MainActor.run { TrackerAccountManager.shared.setViewer(viewer, for: .kitsu) }
    }

    private func kitsuEntryToAL(_ entry: [String: Any], mediaID: Int) -> AnimeItem.MediaListEntry {
        let attributes = entry["attributes"] as? [String: Any]
        let status = attributes?["status"] as? String
        let rating = attributes?["rating"]
        let score = (rating as? NSNumber)?.doubleValue ?? Double((rating as? String) ?? "") ?? 0
        return AnimeItem.MediaListEntry(
            listID: Int(entry["id"] as? String ?? "") ?? 0,
            status: (attributes?["reconsuming"] as? Bool == true) ? "REPEATING" : status.flatMap { Self.kitsuToALStatus[$0] },
            progress: (attributes?["progress"] as? NSNumber)?.intValue ?? 0,
            score: Int(score),
            repeatCount: (attributes?["reconsumeCount"] as? NSNumber)?.intValue ?? 0,
            customLists: [])
    }

    private func entriesToMediaList(_ json: [String: Any]) {
        let data = json["data"] as? [[String: Any]] ?? []
        var anime: [String: [String: Any]] = [:]
        var mappings: [String: [String: Any]] = [:]
        var favourites: [String: [String: Any]] = [:]
        var entries: [[String: Any]] = []

        if data.first?["type"] as? String == "libraryEntries" { entries.append(contentsOf: data) }

        for included in json["included"] as? [[String: Any]] ?? [] {
            let type = included["type"] as? String
            let id = included["id"] as? String ?? ""
            if type == "anime" {
                anime[id] = included
            } else if type == "mappings" {
                guard (included["attributes"] as? [String: Any])?["externalSite"] as? String == "anilist/anime" else { continue }
                mappings[id] = included
            } else if type == "favorites" {
                favourites[id] = included
            } else {
                entries.append(included)
            }
        }

        func first(_ relationship: Any?) -> [String: Any]? {
            let data = (relationship as? [String: Any])?["data"]
            if let array = data as? [[String: Any]] { return array.first }
            return data as? [String: Any]
        }

        var resolved: [(Int, AnimeItem.MediaListEntry)] = []
        for entry in entries {
            let relationships = entry["relationships"] as? [String: Any]
            guard let animeReference = first(relationships?["anime"]),
                  let animeID = animeReference["id"] as? String else { continue }
            let animeRelationships = anime[animeID]?["relationships"] as? [String: Any]
            let mappingData = (animeRelationships?["mappings"] as? [String: Any])?["data"]
            let references: [[String: Any]] = (mappingData as? [[String: Any]]) ?? (mappingData as? [String: Any]).map { [$0] } ?? []
            let externalID = references
                .compactMap { mappings[$0["id"] as? String ?? ""] }
                .first
                .flatMap { ($0["attributes"] as? [String: Any])?["externalId"] as? String }
            guard let anilistID = externalID, let mediaID = Int(anilistID) else { continue }
            stateLock.lock()
            kitsuToAL[animeID] = anilistID
            alToKitsu[anilistID] = animeID
            stateLock.unlock()
            resolved.append((mediaID, kitsuEntryToAL(entry, mediaID: mediaID)))
        }
        setAll(resolved)

        for (favouriteID, favourite) in favourites {
            guard let item = first((favourite["relationships"] as? [String: Any])?["item"]),
                  let animeID = item["id"] as? String else { continue }
            stateLock.lock()
            self.favourites[animeID] = favouriteID
            stateLock.unlock()
            if let kitsuID = Int(animeID) { Task { _ = await lookupAnilistID(kitsuID: kitsuID) } }
        }
    }

    // MARK: - Ids

    private func lookupKitsuID(anilistID: Int) async -> String? {
        stateLock.lock()
        let known = alToKitsu[String(anilistID)]
        stateLock.unlock()
        if let known { return known }
        guard let id = await TrackerMappings.kitsuID(anilistID: anilistID) else { return nil }
        stateLock.lock()
        alToKitsu[String(anilistID)] = String(id)
        stateLock.unlock()
        return String(id)
    }

    private func lookupAnilistID(kitsuID: Int) async -> String? {
        stateLock.lock()
        let known = kitsuToAL[String(kitsuID)]
        stateLock.unlock()
        if let known { return known }
        guard let id = await TrackerMappings.anilistID(kitsuID: kitsuID) else { return nil }
        stateLock.lock()
        kitsuToAL[String(kitsuID)] = String(id)
        stateLock.unlock()
        return String(id)
    }

    // MARK: - Favourites

    func isFavourite(mediaID: Int) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard let kitsuID = alToKitsu[String(mediaID)] else { return false }
        return favourites[kitsuID] != nil
    }

    private func makeFavourite(kitsuAnimeID: String) async {
        guard let url = URL(string: Endpoint.favourites) else { return }
        let viewerID = TrackerAccountManager.shared.viewer(for: .kitsu)?.id ?? ""
        let answer = await request(url, method: "POST", body: [
            "data": [
                "relationships": [
                    "user": ["data": ["type": "users", "id": viewerID]],
                    "item": ["data": ["type": "anime", "id": kitsuAnimeID]],
                ],
                "type": "favorites",
            ],
        ])
        guard let id = (answer.json?["data"] as? [String: Any])?["id"] as? String else { return }
        stateLock.lock()
        favourites[kitsuAnimeID] = id
        stateLock.unlock()
    }

    func toggleFavourite(mediaID: Int) async {
        guard let kitsuID = await lookupKitsuID(anilistID: mediaID) else {
            TrackerToast.error("Kitsu Sync", "Could not find Kitsu ID for this media.")
            return
        }
        stateLock.lock()
        let known = favourites[kitsuID]
        stateLock.unlock()
        guard let favouriteID = known else {
            await makeFavourite(kitsuAnimeID: kitsuID)
            return
        }
        guard let url = URL(string: "\(Endpoint.favourites)/\(favouriteID)") else { return }
        let answer = await request(url, method: "DELETE")
        if answer.isError { return }
        stateLock.lock()
        favourites[kitsuID] = nil
        stateLock.unlock()
    }

    // MARK: - Entries

    private func addEntry(kitsuAnimeID: String, attributes: [String: Any], mediaID: Int) async {
        guard let url = URL(string: Endpoint.library) else { return }
        let viewerID = TrackerAccountManager.shared.viewer(for: .kitsu)?.id ?? ""
        let answer = await request(url, method: "POST", body: [
            "data": [
                "attributes": attributes,
                "relationships": [
                    "anime": ["data": ["id": kitsuAnimeID, "type": "anime"]],
                    "user": ["data": ["type": "users", "id": viewerID]],
                ],
                "type": "library-entries",
            ],
        ])
        guard let data = answer.json?["data"] as? [String: Any] else { return }
        set(kitsuEntryToAL(data, mediaID: mediaID), for: mediaID)
    }

    private func updateEntry(id: Int, attributes: [String: Any], mediaID: Int) async {
        guard let url = URL(string: "\(Endpoint.library)/\(id)") else { return }
        let answer = await request(url, method: "PATCH", body: [
            "data": ["id": id, "attributes": attributes, "type": "library-entries"],
        ])
        guard let data = answer.json?["data"] as? [String: Any] else { return }
        set(kitsuEntryToAL(data, mediaID: mediaID), for: mediaID)
    }

    func entry(_ variables: TrackerEntryVariables) async {
        let mediaID = variables.id
        var attributes: [String: Any] = ["reconsuming": variables.status == "REPEATING"]
        if let status = variables.status, let mapped = Self.alToKitsuStatus[status] { attributes["status"] = mapped }
        if let progress = variables.progress, progress != 0 { attributes["progress"] = progress }
        // kitsu's rating is 2-20... aka 2 = 10, 20 = 100, insane, normalize this
        if let score = variables.score, score != 0, score >= 10 {
            let rating = Double(score) / 5
            attributes["ratingTwenty"] = rating == rating.rounded() ? String(Int(rating)) : String(rating)
        }
        if let repeatCount = variables.repeatCount, repeatCount != 0 { attributes["reconsumeCount"] = repeatCount }

        if let existing = entry(for: mediaID) {
            await updateEntry(id: existing.listID, attributes: attributes, mediaID: mediaID)
            return
        }
        guard let kitsuAnimeID = await lookupKitsuID(anilistID: mediaID) else {
            TrackerToast.error("Kitsu Sync", "Could not find Kitsu ID for this media.")
            return
        }
        await addEntry(kitsuAnimeID: kitsuAnimeID, attributes: attributes, mediaID: mediaID)
    }

    func deleteEntry(mediaID: Int) async {
        guard let id = entry(for: mediaID)?.listID, id != 0,
              let url = URL(string: "\(Endpoint.library)/\(id)") else { return }
        let answer = await request(url, method: "DELETE")
        if answer.isError { return }
        remove(mediaID)
    }
}
