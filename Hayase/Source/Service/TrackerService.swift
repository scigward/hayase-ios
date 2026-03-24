//
//  TrackerService.swift
//  Hayase
//
//  Tracker account management for AniList, Kitsu, MyAnimeList, and Local.
//  Mirrors Hayase's authAggregator architecture:
//    https://github.com/scigward/interface/tree/master/src/lib/modules/auth
//
//  Each tracker stores its auth state in UserDefaults with tracker-prefixed keys.
//  The viewer info (avatar, name, ID) is also persisted so the accounts page
//  can display it instantly without a network round-trip on launch.
//

import Foundation

// MARK: - TrackerViewer (user profile info)

/// Minimal viewer profile returned after authentication.
struct TrackerViewer: Codable {
    let id: String
    let name: String
    let avatarURL: String?
}

// MARK: - TrackerKind

enum TrackerKind: String, CaseIterable {
    case anilist = "anilist"
    case kitsu   = "kitsu"
    case mal     = "mal"
    case local   = "local"

    var displayName: String {
        switch self {
        case .anilist: return "AniList"
        case .kitsu:   return "Kitsu"
        case .mal:     return "MyAnimeList"
        case .local:   return "Local"
        }
    }

    /// UserDefaults key for whether sync is enabled.
    var syncKey: String { "tracker_sync_\(rawValue)" }

    /// UserDefaults key for the stored viewer JSON.
    var viewerKey: String { "tracker_viewer_\(rawValue)" }

    /// UserDefaults key for the auth token.
    var tokenKey: String { "tracker_token_\(rawValue)" }
}

// MARK: - TrackerAccountManager (singleton)

/// Centralized manager for all tracker accounts.
/// Mirrors Hayase's `authAggregator` — manages login state, viewer info, and
/// sync toggles for each tracker service.
final class TrackerAccountManager {

    static let shared = TrackerAccountManager()

    /// Posted when any tracker's login state changes (login/logout).
    static let didChange = Notification.Name("TrackerAccountManagerDidChange")

    private init() {}

    // MARK: - Sync toggles

    func isSyncEnabled(for tracker: TrackerKind) -> Bool {
        // Desktop defaults: { al: true, local: true, kitsu: true, mal: true }
        return UserDefaults.standard.object(forKey: tracker.syncKey) as? Bool ?? true
    }

    func setSyncEnabled(_ enabled: Bool, for tracker: TrackerKind) {
        UserDefaults.standard.set(enabled, forKey: tracker.syncKey)
        notify()
    }

    // MARK: - Viewer info

    func viewer(for tracker: TrackerKind) -> TrackerViewer? {
        guard let data = UserDefaults.standard.data(forKey: tracker.viewerKey) else { return nil }
        return try? JSONDecoder().decode(TrackerViewer.self, from: data)
    }

    func setViewer(_ viewer: TrackerViewer?, for tracker: TrackerKind) {
        if let viewer = viewer, let data = try? JSONEncoder().encode(viewer) {
            UserDefaults.standard.set(data, forKey: tracker.viewerKey)
        } else {
            UserDefaults.standard.removeObject(forKey: tracker.viewerKey)
        }
        notify()
    }

    // MARK: - Token

    func token(for tracker: TrackerKind) -> String? {
        UserDefaults.standard.string(forKey: tracker.tokenKey)
    }

    func setToken(_ token: String?, for tracker: TrackerKind) {
        if let token = token {
            UserDefaults.standard.set(token, forKey: tracker.tokenKey)
        } else {
            UserDefaults.standard.removeObject(forKey: tracker.tokenKey)
        }
    }

    // MARK: - Login state

    func isLoggedIn(_ tracker: TrackerKind) -> Bool {
        if tracker == .local { return true } // local is always "logged in"
        return viewer(for: tracker) != nil
    }

    // MARK: - Logout

    func logout(_ tracker: TrackerKind) {
        setViewer(nil, for: tracker)
        setToken(nil, for: tracker)
        notify()
    }

    // MARK: - Notify

    private func notify() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Self.didChange, object: nil)
        }
    }
}

// MARK: - AniList Auth

/// AniList OAuth2 implicit grant flow.
/// Mirrors Hayase's `$lib/modules/anilist/index.ts` client.auth().
///
/// Flow: open AniList authorize URL in Safari → redirect back with token fragment.
/// After getting the token, query the viewer endpoint for user info.
final class AniListAuth {

    /// Default AniList client ID matching Hayase.
    static let defaultClientID = "37117"

    static var clientID: String {
        get { UserDefaults.standard.string(forKey: "pref_anilistClientID") ?? defaultClientID }
        set { UserDefaults.standard.set(newValue, forKey: "pref_anilistClientID") }
    }

    /// The OAuth authorize URL for AniList implicit grant.
    static var authorizeURL: URL {
        URL(string: "https://anilist.co/api/v2/oauth/authorize?client_id=\(clientID)&response_type=token")!
    }

    /// After receiving the access token, fetch the viewer profile.
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

    /// Complete the login flow: store token and fetch viewer info.
    static func completeLogin(token: String) {
        TrackerAccountManager.shared.setToken(token, for: .anilist)
        fetchViewer(token: token) { viewer in
            DispatchQueue.main.async {
                TrackerAccountManager.shared.setViewer(viewer, for: .anilist)
            }
        }
    }
}

// MARK: - MyAnimeList Auth

/// MAL OAuth2 PKCE flow.
/// Mirrors Hayase's `$lib/modules/auth/mal/index.ts`.
final class MALAuth {

    static let defaultClientID = "6114d00ca681b67b7e37a611c4b054b4"

    static var clientID: String {
        get { UserDefaults.standard.string(forKey: "pref_malClientID") ?? defaultClientID }
        set { UserDefaults.standard.set(newValue, forKey: "pref_malClientID") }
    }

    /// Generate a random code verifier for PKCE.
    static func generateCodeVerifier() -> String {
        let chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~"
        return String((0..<128).map { _ in chars.randomElement()! })
    }

    /// The OAuth authorize URL for MAL PKCE flow.
    static func authorizeURL(codeChallenge: String) -> URL {
        var components = URLComponents(string: "https://myanimelist.net/v1/oauth2/authorize")!
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "plain"),
        ]
        return components.url!
    }

    /// Exchange authorization code for access token.
    static func exchangeCode(_ code: String, codeVerifier: String, completion: @escaping (String?) -> Void) {
        var request = URLRequest(url: URL(string: "https://myanimelist.net/v1/oauth2/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = "client_id=\(clientID)&grant_type=authorization_code&code=\(code)&code_verifier=\(codeVerifier)"
        request.httpBody = body.data(using: .utf8)

        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let token = json["access_token"] as? String else {
                completion(nil)
                return
            }
            completion(token)
        }.resume()
    }

    /// Fetch the viewer profile from MAL API.
    static func fetchViewer(token: String, completion: @escaping (TrackerViewer?) -> Void) {
        var request = URLRequest(url: URL(string: "https://api.myanimelist.net/v2/users/@me?fields=anime_statistics")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let id = json["id"] as? Int,
                  let name = json["name"] as? String else {
                completion(nil)
                return
            }
            let avatar = json["picture"] as? String
            completion(TrackerViewer(id: String(id), name: name, avatarURL: avatar))
        }.resume()
    }

    /// Complete the login with authorization code.
    static func completeLogin(code: String, codeVerifier: String) {
        exchangeCode(code, codeVerifier: codeVerifier) { token in
            guard let token = token else { return }
            TrackerAccountManager.shared.setToken(token, for: .mal)
            fetchViewer(token: token) { viewer in
                DispatchQueue.main.async {
                    TrackerAccountManager.shared.setViewer(viewer, for: .mal)
                }
            }
        }
    }
}

// MARK: - Kitsu Auth

/// Kitsu email/password authentication.
/// Mirrors Hayase's `$lib/modules/auth/kitsu/index.ts`.
final class KitsuAuth {

    /// Login with email and password, exchange for OAuth token.
    static func login(email: String, password: String, completion: @escaping (Bool) -> Void) {
        var request = URLRequest(url: URL(string: "https://kitsu.io/api/oauth/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = "grant_type=password&username=\(email.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")&password=\(password.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
        request.httpBody = body.data(using: .utf8)

        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let token = json["access_token"] as? String else {
                DispatchQueue.main.async { completion(false) }
                return
            }
            TrackerAccountManager.shared.setToken(token, for: .kitsu)
            fetchViewer(token: token) { viewer in
                DispatchQueue.main.async {
                    TrackerAccountManager.shared.setViewer(viewer, for: .kitsu)
                    completion(viewer != nil)
                }
            }
        }.resume()
    }

    /// Fetch the viewer profile from Kitsu API.
    static func fetchViewer(token: String, completion: @escaping (TrackerViewer?) -> Void) {
        var request = URLRequest(url: URL(string: "https://kitsu.io/api/edge/users?filter[self]=true&fields[users]=name,avatar")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.api+json", forHTTPHeaderField: "Accept")

        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let dataArray = json["data"] as? [[String: Any]],
                  let user = dataArray.first,
                  let id = user["id"] as? String,
                  let attributes = user["attributes"] as? [String: Any],
                  let name = attributes["name"] as? String else {
                completion(nil)
                return
            }
            let avatar = (attributes["avatar"] as? [String: Any])?["large"] as? String
            completion(TrackerViewer(id: id, name: name, avatarURL: avatar))
        }.resume()
    }
}

// MARK: - AniList Tracking

/// AniList GraphQL mutations and queries for tracking anime progress.
/// Mirrors Hayase desktop's auth/client.ts (watch, setInitialState, entry, delete).
final class AniListTracking {
    static let shared = AniListTracking()
    private init() {}

    private let endpoint = "https://graphql.anilist.co"

    // MARK: - Mutations

    /// SaveMediaListEntry mutation — matches desktop Entry mutation in queries.ts
    /// Includes customLists to preserve existing lists and add "Watched using Hayase"
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

    /// DeleteMediaListEntry mutation
    private let deleteEntryMutation = """
    mutation ($id: Int!) {
        DeleteMediaListEntry(id: $id) {
            deleted
        }
    }
    """

    /// Fetch a single media with its mediaListEntry (requires auth token)
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

    /// Safe Int extraction from JSON values that might be Int or Double (AniList
    /// returns Float types for some fields like score).
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
            // Log GraphQL errors (e.g. invalid token, rate limiting)
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

    // MARK: - Fetch current list entry for a media

    /// Fetches the current media with its mediaListEntry from AniList.
    /// Returns (mediaListEntry, mediaStatus, episodes, format, duration).
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
                // Parse customLists(asArray: true) → [{enabled: Bool, name: String}]
                // Filter to only enabled list names, matching desktop:
                //   mediaList.customLists.filter(({enabled}) => enabled).map(({name}) => name)
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

    // MARK: - entry() — universal entry update (matches auth/client.ts entry())

    /// Updates/creates a media list entry on AniList.
    /// Mirrors auth/client.ts `entry(variables)`.
    /// `lists` param preserves existing custom lists; "Watched using Hayase" is always appended.
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
        if let sc = score   { vars["score"] = sc * 10 } // POINT_10 (0-10) → scoreRaw (0-100)
        if let r = repeatCount { vars["repeat"] = r }

        // Desktop: variables.lists ??= []; if (!lists.includes('Watched using Hayase')) lists.push(...)
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

    /// Deletes a media list entry from AniList.
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

    // MARK: - watch() — auto-update progress (matches auth/client.ts watch())

    /// Called when the user watches an episode. Mirrors auth/client.ts `watch()`:
    /// 1. Fetches latest media data to check current progress
    /// 2. Won't downgrade progress (currentProgress >= newProgress → skip)
    /// 3. Auto-determines status: COMPLETED if last episode, CURRENT otherwise
    /// 4. Handles REPEATING status preservation
    ///
    /// Desktop's watch() always has a fallback `outdated` media object from the page cache.
    /// Our iOS equivalent: if fetchMediaWithEntry fails completely (network error), we still
    /// attempt to update progress with status CURRENT, since the mutation itself may succeed.
    func watch(anilistID: Int, episodeProgress: Int) {
        fetchMediaWithEntry(anilistID: anilistID) { [weak self] currentEntry, mediaStatus, totalEps, _, _ in
            guard let self else { return }

            // If the fresh fetch failed entirely (network error, expired token, etc.)
            // we still try to update. Desktop falls back to the cached `outdated` media
            // object — we don't have that, so we use safe defaults.
            guard mediaStatus != nil else {
                NSLog("[AniListTracking] watch: fetchMediaWithEntry returned nil — attempting direct entry update for ep %d", episodeProgress)
                self.entry(mediaID: anilistID, status: "CURRENT", progress: episodeProgress)
                return
            }

            // Desktop: const totalEps = episodes(media) ?? 1
            // Desktop episodes() falls back to airingSchedule and progress if media.episodes is nil.
            // Our singleMediaQuery only fetches media.episodes, so for airing shows without
            // an episode count, totalEps is nil. Use max(1, episodeProgress) as safe fallback
            // to avoid aborting for episodes > 1.
            let total = totalEps ?? max(1, episodeProgress)
            if total < episodeProgress { return } // episode number exceeds total episodes

            let currentProgress = currentEntry?.progress ?? 0
            if currentProgress >= episodeProgress { return } // don't downgrade

            // Desktop: canBeCompleted = media.status === 'FINISHED' || media.episodes != null
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

    // MARK: - setInitialState() — matches auth/client.ts setInitialState()

    /// Called when starting playback of episode 1. Handles status transitions:
    /// - No entry → create with CURRENT, progress 0
    /// - PLANNING/PAUSED → CURRENT, progress 0
    /// - COMPLETED → REPEATING, progress 0 (unless single-episode media)
    func setInitialState(anilistID: Int, episode: Int) {
        guard episode == 1 else { return }

        fetchMediaWithEntry(anilistID: anilistID) { [weak self] currentEntry, _, totalEps, _, _ in
            guard let self else { return }

            // No existing entry → create one with CURRENT status
            guard let currentEntry else {
                self.entry(mediaID: anilistID, status: "CURRENT", progress: 0)
                return
            }

            // Single-episode media (movie): don't set to REPEATING if already COMPLETED
            if totalEps == 1 && currentEntry.status == "COMPLETED" { return }

            // COMPLETED/PLANNING/PAUSED → transition
            let transitionStatuses = ["COMPLETED", "PLANNING", "PAUSED"]
            guard transitionStatuses.contains(currentEntry.status ?? "") else { return }

            let newStatus = currentEntry.status == "COMPLETED" ? "REPEATING" : "CURRENT"
            self.entry(mediaID: anilistID, status: newStatus, progress: 0,
                      lists: currentEntry.customLists)
        }
    }

    // MARK: - User lists (homepage sections — matches anilist/client.ts continueIDs/planningIDs/sequelIDs)

    /// Matches desktop's UserLists query in queries.ts.
    /// Fetches the user's MediaListCollection to derive personalized home sections.
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

    /// Result of fetching user lists — contains IDs for personalized home sections.
    struct UserListIDs {
        let continueIDs: [Int]   // CURRENT/REPEATING with unwatched episodes
        let planningIDs: [Int]   // PLANNING entries
        let sequelIDs: [Int]     // SEQUEL relations from COMPLETED entries, not on user's list
    }

    /// Fetches the authenticated user's anime lists and derives IDs for home sections.
    /// Mirrors desktop's anilist/client.ts: continueIDs, planningIDs, sequelIDs.
    func fetchUserLists(completion: @escaping (UserListIDs?) -> Void) {
        guard TrackerAccountManager.shared.isLoggedIn(.anilist) else {
            completion(nil); return
        }
        // Get the user's AniList viewer ID
        guard let viewerStr = TrackerAccountManager.shared.viewer(for: .anilist)?.id,
              let viewerID = Int(viewerStr) else {
            completion(nil); return
        }

        authRequest(query: userListsQuery, variables: ["id": viewerID]) { data in
            guard let collection = data?["MediaListCollection"] as? [String: Any],
                  let lists = collection["lists"] as? [[String: Any]] else {
                completion(nil); return
            }

            // Desktop continueIDs: CURRENT or REPEATING entries where user hasn't caught up
            var continueIDs: [Int] = []
            // Desktop planningIDs: PLANNING entries
            var planningIDs: [Int] = []
            // Desktop sequelIDs: unique SEQUEL node IDs from COMPLETED entries
            var sequelIDs: [Int] = []

            for list in lists {
                let status = list["status"] as? String
                let entries = list["entries"] as? [[String: Any]] ?? []

                if status == "CURRENT" || status == "REPEATING" {
                    // Matches desktop continueIDs logic:
                    //   if (entry.media.status === 'FINISHED') return true
                    //   progress < (nextAiringEpisode.episode ?? (progress + 2)) - 1
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
                    // Matches desktop sequelIDs: flatMap SEQUEL relation nodes, deduplicate
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

            // Deduplicate sequelIDs (matches desktop: [...new Set(...)])
            let uniqueSequelIDs = Array(Set(sequelIDs))

            completion(UserListIDs(
                continueIDs: continueIDs,
                planningIDs: planningIDs,
                sequelIDs: uniqueSequelIDs))
        }
    }

    // MARK: - Fetch mediaListEntry progress for a specific media

    /// Fetches just the mediaListEntry.progress for a given media ID.
    /// Used by AnimeDetailViewController to show watched episode state.
    func fetchProgress(anilistID: Int, completion: @escaping (Int?) -> Void) {
        guard TrackerAccountManager.shared.isLoggedIn(.anilist) else {
            completion(nil); return
        }
        fetchMediaWithEntry(anilistID: anilistID) { entry, _, _, _, _ in
            completion(entry?.progress)
        }
    }
}
