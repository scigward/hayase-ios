//
//  TrackerSync.swift
//  Hayase
//
//  What kitsu.ts, mal.ts and simkl.ts share, and the aggregation of auth/client.ts: the list a
//  tracker keeps of its own, the OAuth object each one stores, the AniZip id lookups, and which
//  tracker answers when more than one is signed in.
//

import Foundation

// MARK: - OAuth

/// `OAuth` (kitsu-types.d.ts), `MALOAuth` and `SimklOAuth`: what the token endpoint answered.
struct TrackerOAuth: Codable {
    var accessToken: String
    var refreshToken: String?
    /// Seconds until the access token expires; Simkl does not always say.
    var expiresIn: Double?
    /// Seconds since 1970 at which it was issued.
    var createdAt: Double

    /// `expiresAt < Date.now() - 1000 * 60 * 5`: the interface only asks for a new token once the
    /// old one has been out of date for five minutes.
    var isStale: Bool {
        guard let expiresIn else { return false }
        return (createdAt + expiresIn) * 1000 < Date().timeIntervalSince1970 * 1000 - 1000 * 60 * 5
    }

    init(accessToken: String, refreshToken: String?, expiresIn: Double?, createdAt: Double) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresIn = expiresIn
        self.createdAt = createdAt
    }

    /// The JSON of a token endpoint; `createdAt` is the one in the answer, or now.
    init?(json: [String: Any], createdAt: Double? = nil) {
        guard let token = json["access_token"] as? String else { return nil }
        accessToken = token
        refreshToken = json["refresh_token"] as? String
        expiresIn = (json["expires_in"] as? NSNumber)?.doubleValue
        self.createdAt = createdAt ?? (json["created_at"] as? NSNumber)?.doubleValue ?? Date().timeIntervalSince1970.rounded(.down)
    }
}

enum TrackerAuthStore {
    private static func key(_ kind: TrackerKind) -> String { "tracker_oauth_\(kind.rawValue)" }

    static func load(_ kind: TrackerKind) -> TrackerOAuth? {
        if let json = Keychain.string(forKey: key(kind)), let data = json.data(using: .utf8),
           let auth = try? JSONDecoder().decode(TrackerOAuth.self, from: data) {
            return auth
        }
        // a login from before the whole answer of the token endpoint was kept: only the access token
        guard let token = TrackerAccountManager.shared.token(for: kind) else { return nil }
        return TrackerOAuth(accessToken: token, refreshToken: nil, expiresIn: nil,
                            createdAt: Date().timeIntervalSince1970.rounded(.down))
    }

    /// `auth.set(…)`. The access token also goes where the rest of the app looks for it.
    static func save(_ auth: TrackerOAuth?, for kind: TrackerKind) {
        if let auth, let data = try? JSONEncoder().encode(auth) {
            Keychain.set(String(data: data, encoding: .utf8), forKey: key(kind))
            TrackerAccountManager.shared.setToken(auth.accessToken, for: kind)
        } else {
            Keychain.set(nil, forKey: key(kind))
            TrackerAccountManager.shared.setToken(nil, for: kind)
        }
    }
}

// MARK: - Errors

enum TrackerToast {
    /// `toast.error(title, { description, duration: 15_000 })`
    static func error(_ title: String, _ description: String) {
        DispatchQueue.main.async { AppErrorToast.show(description, title: title) }
    }
}

// MARK: - Mappings (anizip/index.ts)

enum TrackerMappings {
    private static func fetch(_ query: String) async -> [String: Any]? {
        guard let url = URL(string: "https://hayase.ani.zip/v1/mappings?\(query)"),
              let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func number(_ json: [String: Any]?, _ key: String) -> Int? {
        if let value = json?[key] as? NSNumber { return value.intValue }
        if let value = json?[key] as? String { return Int(value) }
        return nil
    }

    static func kitsuID(anilistID: Int) async -> Int? {
        number(await fetch("anilist_id=\(anilistID)"), "kitsu_id")
    }

    static func malID(anilistID: Int) async -> Int? {
        number(await fetch("anilist_id=\(anilistID)"), "mal_id")
    }

    static func simklID(anilistID: Int) async -> Int? {
        number(await fetch("anilist_id=\(anilistID)"), "simkl_id")
    }

    static func anilistID(kitsuID: Int) async -> Int? {
        number(await fetch("kitsu_id=\(kitsuID)"), "anilist_id")
    }

    static func anilistID(malID: Int) async -> Int? {
        number(await fetch("mal_id=\(malID)"), "anilist_id")
    }
}

// MARK: - A tracker's own list

/// `userlist = writable(new Map<number, FullMediaList>())` with `continueIDs` and `planningIDs`:
/// a map keeps the order its keys went in.
class ListTracker {
    let kind: TrackerKind
    private let lock = NSLock()
    private var map: [Int: AnimeItem.MediaListEntry] = [:]
    private var order: [Int] = []

    init(kind: TrackerKind) {
        self.kind = kind
    }

    /// `kitsu()`, `mal()`, `simkl()`: there is a viewer.
    var isSignedIn: Bool {
        TrackerAccountManager.shared.viewer(for: kind) != nil
    }

    func entry(for mediaID: Int) -> AnimeItem.MediaListEntry? {
        lock.lock()
        defer { lock.unlock() }
        return map[mediaID]
    }

    /// The AniList ids on the list, in the order they were added.
    var mediaIDs: [Int] {
        lock.lock()
        defer { lock.unlock() }
        return order
    }

    func set(_ entry: AnimeItem.MediaListEntry, for mediaID: Int) {
        lock.lock()
        if map[mediaID] == nil { order.append(mediaID) }
        map[mediaID] = entry
        lock.unlock()
        notifyChanged()
    }

    /// `map.set` for a batch, without a notification for each.
    func setAll(_ entries: [(Int, AnimeItem.MediaListEntry)]) {
        lock.lock()
        for (mediaID, entry) in entries {
            if map[mediaID] == nil { order.append(mediaID) }
            map[mediaID] = entry
        }
        lock.unlock()
        notifyChanged()
    }

    /// `userlist.set(new Map(…))`
    func replaceAll(_ entries: [(Int, AnimeItem.MediaListEntry)]) {
        lock.lock()
        map = [:]
        order = []
        for (mediaID, entry) in entries {
            if map[mediaID] == nil { order.append(mediaID) }
            map[mediaID] = entry
        }
        lock.unlock()
        notifyChanged()
    }

    func remove(_ mediaID: Int) {
        lock.lock()
        map[mediaID] = nil
        order.removeAll { $0 == mediaID }
        lock.unlock()
        notifyChanged()
    }

    func clear() {
        lock.lock()
        map = [:]
        order = []
        lock.unlock()
        notifyChanged()
    }

    /// `entry.status === 'REPEATING' || entry.status === 'CURRENT'`
    var continueIDs: [Int] {
        lock.lock()
        defer { lock.unlock() }
        return order.filter { map[$0]?.status == "REPEATING" || map[$0]?.status == "CURRENT" }
    }

    /// `entry.status === 'PLANNING'`
    var planningIDs: [Int] {
        lock.lock()
        defer { lock.unlock() }
        return order.filter { map[$0]?.status == "PLANNING" }
    }

    func notifyChanged() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: LocalTracking.didChange, object: self)
        }
    }
}

// MARK: - The values an entry is saved with

/// `VariablesOf<typeof Entry>`: the score is the raw 0-100 `scoreRaw`.
struct TrackerEntryVariables {
    var id: Int
    var status: String?
    var progress: Int?
    var score: Int?
    var repeatCount: Int?
    var lists: [String]?
}

// MARK: - auth/client.ts

/// `authAggregator`: which tracker answers for what, in the order the interface asks them.
enum TrackerAggregator {
    static var kitsu: KitsuSync { KitsuSync.shared }
    static var mal: MALSync { MALSync.shared }
    static var simkl: SimklSync { SimklSync.shared }

    static func start() {
        KitsuSync.shared.start()
        MALSync.shared.start()
        SimklSync.shared.start()
    }

    /// `mediaListEntry` without AniList's own: `$kitsuList.get(id) ?? $malList.get(id) ??
    /// $simklList.get(id) ?? local.get(id)?.mediaListEntry`
    static func externalEntry(for mediaID: Int) -> AnimeItem.MediaListEntry? {
        kitsu.entry(for: mediaID)
            ?? mal.entry(for: mediaID)
            ?? simkl.entry(for: mediaID)
            ?? LocalTracking.shared.entry(for: mediaID)
    }

    /// `medialists`: the list of the first tracker that is signed in, the local one last.
    static func listEntry(for mediaID: Int) -> AnimeItem.MediaListEntry? {
        if kitsu.isSignedIn { return kitsu.entry(for: mediaID) }
        if mal.isSignedIn { return mal.entry(for: mediaID) }
        if simkl.isSignedIn { return simkl.entry(for: mediaID) }
        return LocalTracking.shared.entry(for: mediaID)
    }

    /// `schedule()`: the ids of the first signed in tracker's list.
    static func scheduleIDs() -> [Int] {
        if kitsu.isSignedIn { return kitsu.mediaIDs }
        if mal.isSignedIn { return mal.mediaIDs }
        if simkl.isSignedIn { return simkl.mediaIDs }
        return LocalTracking.shared.scheduleMediaIDs()
    }

    /// `continueIDs`, `planningIDs` and `sequelIDs` when AniList is not the tracker that answers.
    static func listIDs() -> AniListTracking.UserListIDs {
        if kitsu.isSignedIn { return .init(continueIDs: kitsu.continueIDs, planningIDs: kitsu.planningIDs, sequelIDs: []) }
        if mal.isSignedIn { return .init(continueIDs: mal.continueIDs, planningIDs: mal.planningIDs, sequelIDs: []) }
        if simkl.isSignedIn { return .init(continueIDs: simkl.continueIDs, planningIDs: simkl.planningIDs, sequelIDs: []) }
        return .init(continueIDs: LocalTracking.shared.continueIDs(), planningIDs: LocalTracking.shared.planningIDs(), sequelIDs: [])
    }

    /// `isFavourite`, for a media AniList did not answer for.
    static func isFavourite(mediaID: Int) -> Bool {
        if kitsu.isSignedIn { return kitsu.isFavourite(mediaID: mediaID) }
        return LocalTracking.shared.isFavourite(mediaID: mediaID)
    }

    /// `entry()`: every tracker that is on and signed in gets the change, whatever the others say.
    static func entry(_ variables: TrackerEntryVariables) {
        let manager = TrackerAccountManager.shared
        if manager.isSyncEnabled(for: .kitsu), kitsu.isSignedIn { Task { await kitsu.entry(variables) } }
        if manager.isSyncEnabled(for: .mal), mal.isSignedIn { Task { await mal.entry(variables) } }
        if manager.isSyncEnabled(for: .simkl), simkl.isSignedIn { Task { await simkl.entry(variables) } }
    }

    /// `delete()`
    static func delete(mediaID: Int, malID: Int?) {
        let manager = TrackerAccountManager.shared
        if manager.isSyncEnabled(for: .kitsu), kitsu.isSignedIn { Task { await kitsu.deleteEntry(mediaID: mediaID) } }
        if manager.isSyncEnabled(for: .mal), mal.isSignedIn { Task { await mal.deleteEntry(mediaID: mediaID, malID: malID) } }
        if manager.isSyncEnabled(for: .simkl), simkl.isSignedIn { Task { await simkl.deleteEntry(mediaID: mediaID) } }
    }

    /// What a sign out forgets: the list, and the login the next start would load it with.
    static func signedOut(_ kind: TrackerKind) {
        switch kind {
        case .kitsu: kitsu.signedOut()
        case .mal: mal.signedOut()
        case .simkl: simkl.signedOut()
        default: break
        }
    }
}
