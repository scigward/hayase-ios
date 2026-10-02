//
//  MALSync.swift
//  Hayase
//
//  Mirrors: interface lib/modules/auth/mal.ts (`MALSync`).
//

import Foundation

final class MALSync: ListTracker {
    static let shared = MALSync()

    private enum Endpoint {
        static let base = "https://api.myanimelist.net/v2"
        static let oauth = "https://myanimelist.net/v1/oauth2/token"
        static let user = "https://api.myanimelist.net/v2/users/@me"
        static let animeList = "https://api.myanimelist.net/v2/users/@me/animelist"
        static let anime = "https://api.myanimelist.net/v2/anime"
    }

    private static let malToALStatus: [String: String] = [
        "watching": "CURRENT", "plan_to_watch": "PLANNING", "completed": "COMPLETED", "dropped": "DROPPED", "on_hold": "PAUSED",
    ]
    private static let alToMALStatus: [String: String] = [
        "CURRENT": "watching", "PLANNING": "plan_to_watch", "COMPLETED": "completed", "DROPPED": "dropped",
        "PAUSED": "on_hold", "REPEATING": "watching",
    ]

    private let stateLock = NSLock()
    /// `malToAL = persisted('malToAL', {})`
    private let malToALKey = "malToAL"
    private var alToMAL: [Int: Int] = [:]

    private var malToAL: [Int: Int] {
        get {
            let stored = UserDefaults.standard.dictionary(forKey: malToALKey) as? [String: Int] ?? [:]
            return Dictionary(stored.compactMap { key, value in Int(key).map { ($0, value) } }, uniquingKeysWith: { first, _ in first })
        }
        set {
            UserDefaults.standard.set(Dictionary(newValue.map { (String($0.key), $0.value) }, uniquingKeysWith: { first, _ in first }), forKey: malToALKey)
        }
    }

    private init() {
        super.init(kind: .mal)
    }

    func start() {
        guard TrackerAuthStore.load(.mal) != nil else { return }
        Task { await loadUser() }
    }

    func signedOut() {
        TrackerAuthStore.save(nil, for: .mal)
        UserDefaults.standard.removeObject(forKey: malToALKey)
        stateLock.lock()
        alToMAL = [:]
        stateLock.unlock()
        clear()
    }

    // MARK: - Requests

    private struct Answer {
        var json: [String: Any]?
        var failed: Bool
    }

    /// `_request`: a status outside 200-299 is an error whose message is the status and the body.
    private func request(_ url: URL, method: String, form: [(String, String)]? = nil) async -> Answer {
        var auth = TrackerAuthStore.load(.mal)
        let refreshing = form?.contains { $0.0 == "refresh_token" } ?? false
        if let current = auth, current.isStale, !refreshing {
            auth = await refresh(current)
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        if let auth { request.setValue("Bearer \(auth.accessToken)", forHTTPHeaderField: "Authorization") }
        if let form {
            var components = URLComponents()
            components.queryItems = form.map { URLQueryItem(name: $0.0, value: $0.1) }
            request.httpBody = components.percentEncodedQuery?.data(using: .utf8)
        }
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw NSError(domain: "MAL", code: http.statusCode, userInfo: [
                    NSLocalizedDescriptionKey: "HTTP \(http.statusCode): \(String(data: data, encoding: .utf8) ?? "")",
                ])
            }
            if method == "DELETE" { return Answer(json: nil, failed: false) }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw URLError(.cannotParseResponse)
            }
            return Answer(json: json, failed: false)
        } catch {
            TrackerToast.error("MAL Error", error.localizedDescription)
            return Answer(json: nil, failed: true)
        }
    }

    private func get(_ target: String, _ parameters: [(String, String)] = []) async -> Answer {
        guard var components = URLComponents(string: target) else { return Answer(json: nil, failed: true) }
        components.queryItems = parameters.map { URLQueryItem(name: $0.0, value: $0.1) }
        guard let url = components.url else { return Answer(json: nil, failed: true) }
        return await request(url, method: "GET")
    }

    private func refresh(_ auth: TrackerOAuth) async -> TrackerOAuth {
        guard let refreshToken = auth.refreshToken, let url = URL(string: Endpoint.oauth) else { return auth }
        let answer = await request(url, method: "POST", form: [
            ("client_id", MALAuth.clientID), ("grant_type", "refresh_token"), ("refresh_token", refreshToken),
        ])
        if let json = answer.json,
           let renewed = TrackerOAuth(json: json, createdAt: Date().timeIntervalSince1970.rounded(.down)) {
            TrackerAuthStore.save(renewed, for: .mal)
            return renewed
        }
        return auth
    }

    // MARK: - Login

    /// The second half of `login`: the code the authorization sent back for a token.
    func login(code: String, challenge: String) async {
        guard let url = URL(string: Endpoint.oauth) else { return }
        let answer = await request(url, method: "POST", form: [
            ("client_id", MALAuth.clientID), ("grant_type", "authorization_code"), ("code", code),
            ("code_verifier", challenge), ("redirect_uri", MALAuth.redirectURI),
        ])
        guard let json = answer.json,
              let auth = TrackerOAuth(json: json, createdAt: Date().timeIntervalSince1970.rounded(.down)) else { return }
        TrackerAuthStore.save(auth, for: .mal)
        await loadUser()
    }

    // MARK: - The user and the list

    private func loadUser() async {
        let answer = await get(Endpoint.user, [("fields", "anime_statistics")])
        guard !answer.failed, let json = answer.json, let id = (json["id"] as? NSNumber)?.intValue else { return }
        let viewer = TrackerViewer(id: String(id), name: json["name"] as? String ?? "", avatarURL: json["picture"] as? String)
        await MainActor.run { TrackerAccountManager.shared.setViewer(viewer, for: .mal) }
        await loadUserList()
    }

    private func malEntryToAL(_ item: [String: Any], id: Int) -> AnimeItem.MediaListEntry {
        let status = item["status"] as? String
        return AnimeItem.MediaListEntry(
            listID: id,
            status: (item["is_rewatching"] as? Bool == true) ? "REPEATING" : status.flatMap { Self.malToALStatus[$0] },
            progress: (item["num_episodes_watched"] as? NSNumber)?.intValue ?? 0,
            score: (item["score"] as? NSNumber)?.intValue ?? 0,
            repeatCount: (item["num_times_rewatched"] as? NSNumber)?.intValue ?? 0,
            customLists: [])
    }

    private func loadUserList() async {
        var data: [[String: Any]] = []
        var hasNextPage = true
        var page = 0
        while hasNextPage {
            let answer = await get(Endpoint.animeList, [
                ("sort", "list_updated_at"), ("fields", "node.my_list_status"), ("nsfw", "true"),
                ("limit", "1000"), ("offset", String(page * 1000)),
            ])
            guard !answer.failed, let items = answer.json?["data"] as? [[String: Any]] else { break }
            hasNextPage = items.count == 1000
            page += 1
            data.append(contentsOf: items)
        }

        let ids = data.compactMap { ($0["node"] as? [String: Any])?["id"] as? Int }
        var cached = malToAL
        let unknown = ids.filter { cached[$0] == nil }
        let resolved: [Int: Int] = await withCheckedContinuation { continuation in
            AniListClient.shared.malIdsCompound(unknown) { continuation.resume(returning: $0) }
        }

        var entries: [(Int, AnimeItem.MediaListEntry)] = []
        for item in data {
            guard let node = item["node"] as? [String: Any], let malID = node["id"] as? Int else { continue }
            var found = cached[malID] ?? resolved[malID]
            if found == nil { found = await lookupAnilistID(malID: malID) }
            guard let anilistID = found else { continue }
            cached[malID] = anilistID
            stateLock.lock()
            alToMAL[anilistID] = malID
            stateLock.unlock()
            entries.append((anilistID, malEntryToAL(node["my_list_status"] as? [String: Any] ?? [:], id: malID)))
        }
        malToAL = cached
        replaceAll(entries)
    }

    // MARK: - Ids

    private func lookupMALID(anilistID: Int) async -> Int? {
        stateLock.lock()
        let known = alToMAL[anilistID]
        stateLock.unlock()
        if let known { return known }
        guard let id = await TrackerMappings.malID(anilistID: anilistID) else { return nil }
        stateLock.lock()
        alToMAL[anilistID] = id
        stateLock.unlock()
        var map = malToAL
        map[id] = anilistID
        malToAL = map
        return id
    }

    private func lookupAnilistID(malID: Int) async -> Int? {
        if let known = malToAL[malID] { return known }
        guard let id = await TrackerMappings.anilistID(malID: malID) else { return nil }
        var map = malToAL
        map[malID] = id
        malToAL = map
        stateLock.lock()
        alToMAL[id] = malID
        stateLock.unlock()
        return id
    }

    // MARK: - Entries

    func deleteEntry(mediaID: Int, malID knownMALID: Int?) async {
        var found = knownMALID
        if found == nil { found = await lookupMALID(anilistID: mediaID) }
        guard let malID = found, let url = URL(string: "\(Endpoint.anime)/\(malID)/my_list_status") else { return }
        let answer = await request(url, method: "DELETE")
        if answer.failed { return }
        remove(mediaID)
    }

    func entry(_ variables: TrackerEntryVariables) async {
        let mediaID = variables.id
        let media: AnimeItem? = await withCheckedContinuation { continuation in
            AniListClient.shared.fetchResolverMediaByIdResult(mediaID) { result in
                continuation.resume(returning: try? result.get())
            }
        }
        var found = media?.malId
        if found == nil { found = await lookupMALID(anilistID: mediaID) }
        guard let malID = found else {
            TrackerToast.error("MAL Sync", "Could not find MAL ID for this media.")
            return
        }

        let status = variables.status.flatMap { Self.alToMALStatus[$0] }
        var body: [(String, String)] = []
        if let status { body.append(("status", status)) }
        body.append(("is_rewatching", variables.status == "REPEATING" ? "true" : "false"))
        if let progress = variables.progress, progress != 0 { body.append(("num_watched_episodes", String(progress))) }
        if let score = variables.score, score != 0 {
            let value = Double(score) / 10
            body.append(("score", value == value.rounded() ? String(Int(value)) : String(value)))
        }
        if let repeatCount = variables.repeatCount, repeatCount != 0 { body.append(("num_times_rewatched", String(repeatCount))) }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        let today = formatter.string(from: Date())
        let notRepeating = (variables.repeatCount ?? 0) == 0
        if status == "watching", notRepeating, variables.progress == 1 { body.append(("start_date", today)) }
        if status == "completed", notRepeating { body.append(("finish_date", today)) }

        guard let url = URL(string: "\(Endpoint.anime)/\(malID)/my_list_status") else { return }
        let answer = await request(url, method: "PATCH", form: body)
        guard !answer.failed, let json = answer.json else { return }
        set(malEntryToAL(json, id: mediaID), for: mediaID)
    }
}
