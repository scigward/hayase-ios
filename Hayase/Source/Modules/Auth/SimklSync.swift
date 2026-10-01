//
//  SimklSync.swift
//  Hayase
//
//  Mirrors: interface lib/modules/auth/simkl.ts (`SimklSync`).
//

import Foundation

final class SimklSync: ListTracker {
    static let shared = SimklSync()

    private enum Endpoint {
        static let oauth = "https://api.simkl.com/oauth/token"
        static let user = "https://api.simkl.com/users/settings"
        static let remove = "https://api.simkl.com/sync/remove-from-list"
        static let add = "https://api.simkl.com/sync/add-to-list"
        static let allItems = "https://api.simkl.com/sync/all-items/anime/"
    }

    private static let simklToALStatus: [String: String] = [
        "watching": "CURRENT", "plan_to_watch": "PLANNING", "completed": "COMPLETED", "dropped": "DROPPED", "hold": "PAUSED",
    ]
    private static let alToSimklStatus: [String: String] = [
        "CURRENT": "watching", "PLANNING": "plan_to_watch", "COMPLETED": "completed", "DROPPED": "dropped",
        "PAUSED": "hold", "REPEATING": "watching",
    ]

    private init() {
        super.init(kind: .simkl)
    }

    func start() {
        guard TrackerAuthStore.load(.simkl) != nil else { return }
        Task { await loadUser() }
    }

    func signedOut() {
        TrackerAuthStore.save(nil, for: .simkl)
        clear()
    }

    // MARK: - Requests

    private struct Answer {
        var json: [String: Any]?
        var failed: Bool
    }

    private func send(_ request: URLRequest) async -> Answer {
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw NSError(domain: "Simkl", code: http.statusCode, userInfo: [
                    NSLocalizedDescriptionKey: "HTTP \(http.statusCode): \(String(data: data, encoding: .utf8) ?? "")",
                ])
            }
            if request.httpMethod == "DELETE" { return Answer(json: nil, failed: false) }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                // `res.json()` of a `null` or a list is not an error, `'error' in res` is just not there
                return Answer(json: nil, failed: false)
            }
            return Answer(json: json, failed: false)
        } catch {
            TrackerToast.error("Simkl Error", error.localizedDescription)
            return Answer(json: nil, failed: true)
        }
    }

    /// `_request`
    private func request(_ target: String, method: String, body: [String: Any]? = nil) async -> Answer {
        guard let url = URL(string: target) else { return Answer(json: nil, failed: true) }
        var auth = TrackerAuthStore.load(.simkl)
        if let current = auth, current.isStale {
            auth = await refresh(current)
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(SimklAuth.clientID, forHTTPHeaderField: "simkl-api-key")
        if let auth { request.setValue("Bearer \(auth.accessToken)", forHTTPHeaderField: "Authorization") }
        if let body { request.httpBody = try? JSONSerialization.data(withJSONObject: body) }
        return await send(request)
    }

    /// `_oauthRequest`
    private func oauthRequest(_ body: [String: Any]) async -> Answer {
        guard let url = URL(string: Endpoint.oauth) else { return Answer(json: nil, failed: true) }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return await send(request)
    }

    private func refresh(_ auth: TrackerOAuth) async -> TrackerOAuth {
        guard let refreshToken = auth.refreshToken else { return auth }
        var body: [String: Any] = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": SimklAuth.clientID,
        ]
        if !SimklAuth.clientSecret.isEmpty { body["client_secret"] = SimklAuth.clientSecret }
        let answer = await oauthRequest(body)
        if let json = answer.json,
           let renewed = TrackerOAuth(json: json, createdAt: Date().timeIntervalSince1970.rounded(.down)) {
            TrackerAuthStore.save(renewed, for: .simkl)
            return renewed
        }
        return auth
    }

    // MARK: - Login

    /// The second half of `login`: the code the authorization sent back for a token.
    func login(code: String) async -> Bool {
        let answer = await oauthRequest([
            "code": code,
            "client_id": SimklAuth.clientID,
            "client_secret": SimklAuth.clientSecret,
            "redirect_uri": SimklAuth.redirectURI,
            "grant_type": "authorization_code",
        ])
        guard let json = answer.json,
              let auth = TrackerOAuth(json: json, createdAt: Date().timeIntervalSince1970.rounded(.down)) else { return false }
        TrackerAuthStore.save(auth, for: .simkl)
        await loadUser()
        return isSignedIn
    }

    // MARK: - The user and the list

    private func loadUser() async {
        let answer = await request(Endpoint.user, method: "GET")
        guard !answer.failed, let json = answer.json,
              let id = (json["account"] as? [String: Any])?["id"] as? NSNumber else { return }
        let user = json["user"] as? [String: Any]
        let viewer = TrackerViewer(id: id.stringValue, name: user?["name"] as? String ?? "",
                                   avatarURL: user?["avatar"] as? String)
        await MainActor.run { TrackerAccountManager.shared.setViewer(viewer, for: .simkl) }
        await loadUserList()
    }

    private func loadUserList() async {
        let answer = await request(Endpoint.allItems, method: "GET")
        guard !answer.failed, let items = answer.json?["anime"] as? [[String: Any]] else { return }

        var entries: [(Int, AnimeItem.MediaListEntry)] = []
        for item in items {
            guard let show = item["show"] as? [String: Any],
                  let ids = show["ids"] as? [String: Any],
                  let anilist = ids["anilist"],
                  let mediaID = (anilist as? NSNumber)?.intValue ?? Int(anilist as? String ?? ""),
                  mediaID != 0 else { continue }
            let status = item["status"] as? String
            entries.append((mediaID, AnimeItem.MediaListEntry(
                listID: mediaID,
                status: status.flatMap { Self.simklToALStatus[$0] },
                progress: (item["watched_episodes_count"] as? NSNumber)?.intValue ?? 0,
                score: (item["user_rating"] as? NSNumber)?.intValue ?? 0,
                repeatCount: 0,
                customLists: [])))
        }
        replaceAll(entries)
    }

    // MARK: - Entries

    func deleteEntry(mediaID: Int) async {
        guard entry(for: mediaID) != nil else { return }
        let answer = await request(Endpoint.remove, method: "POST", body: ["shows": [["ids": ["anilist": mediaID]]]])
        if answer.failed { return }
        remove(mediaID)
    }

    func entry(_ variables: TrackerEntryVariables) async {
        let mediaID = variables.id
        var show: [String: Any] = ["ids": ["anilist": mediaID]]
        if let status = variables.status, let mapped = Self.alToSimklStatus[status] { show["to"] = mapped }
        if let progress = variables.progress, progress != 0 { show["watched_episodes"] = progress }
        if let score = variables.score, score != 0 { show["rating"] = score }

        let answer = await request(Endpoint.add, method: "POST", body: ["shows": [show]])
        // `!res || 'error' in res`
        guard !answer.failed, answer.json != nil else { return }

        let existing = entry(for: mediaID)
        set(AnimeItem.MediaListEntry(
            listID: mediaID,
            status: variables.status ?? existing?.status,
            progress: variables.progress ?? existing?.progress ?? 0,
            score: variables.score ?? existing?.score ?? 0,
            repeatCount: variables.repeatCount ?? existing?.repeatCount ?? 0,
            customLists: []), for: mediaID)
    }
}
