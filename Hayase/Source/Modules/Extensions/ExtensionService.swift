// ExtensionService.swift
// iOS port of scigward/interface's extensions/storage.ts (ConfigManager + CodeManager).
//
// Key parity:
//   savedConfigs  → UserDefaults "ext.savedConfigs"  ([ExtensionConfig] as JSON)
//   savedOptions  → UserDefaults "ext.savedOptions"  ([ExtensionOptions] as JSON)
//   Extension JS code → Library/Application Support/Extensions/{id}.js
//   ConfigManager.import()  → ExtensionService.importExtension(from:)
//   ConfigManager.delete()  → ExtensionService.delete(id:)
//   ConfigManager.update()  → ExtensionService.update() (called at init)
//   Extensions.getResultsFromExtensions() → ExtensionService.search(query:)
//   Extensions.dedupe()     → ExtensionService.dedupe(_:)

import Foundation
import UIKit

// MARK: - URL helpers (mirrors jsurl / jsonurl in storage.ts)

// Extract scheme and path from a custom-scheme URI like "gh:user/repo/src/file.js"
// using raw string splitting instead of URL(string:).path, which returns "" for
// opaque URIs (no // authority) in Swift's RFC-3986 parser.
private func schemePath(_ raw: String) -> (scheme: String, path: String)? {
    guard let colon = raw.firstIndex(of: ":") else { return nil }
    let scheme = String(raw[raw.startIndex..<colon])
    let path   = String(raw[raw.index(after: colon)...])
    return (scheme, path)
}

private func jsurl(_ raw: String) -> URL? {
    if raw.hasPrefix("http") { return URL(string: raw) }
    guard let (scheme, path) = schemePath(raw) else { return nil }
    // Mirrors Hayase storage.ts jsurl() exactly:
    //   gh:[user]/[repo]/[...path] → https://esm.sh/gh/[user]/[repo]/es2022/[path].mjs
    //   npm:[pkg]/[...path]        → https://esm.sh/[pkg]/es2022/[path].mjs
    let parts = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
    switch scheme {
    case "gh":
        guard parts.count >= 2 else { return nil }
        let user = parts[0], repo = parts[1]
        let rest = parts.dropFirst(2).joined(separator: "/")
        let urlStr = rest.isEmpty
            ? "https://esm.sh/gh/\(user)/\(repo)/es2022/index.mjs"
            : "https://esm.sh/gh/\(user)/\(repo)/es2022/\(rest).mjs"
        return URL(string: urlStr)
    case "npm":
        guard !parts.isEmpty else { return nil }
        let pkg  = parts[0]
        let rest = parts.dropFirst().joined(separator: "/")
        let urlStr = rest.isEmpty
            ? "https://esm.sh/\(pkg)/es2022/index.mjs"
            : "https://esm.sh/\(pkg)/es2022/\(rest).mjs"
        return URL(string: urlStr)
    default: return nil
    }
}

private func jsonurl(_ raw: String) -> URL? {
    if raw.hasPrefix("http") { return URL(string: raw) }
    guard let (scheme, path) = schemePath(raw) else { return nil }
    switch scheme {
    case "gh":
        let base = "https://esm.sh/gh/\(path)"
        return URL(string: base.hasSuffix(".json") ? base : "\(base)/index.json")
    case "npm":
        let base = "https://esm.sh/\(path)"
        return URL(string: base.hasSuffix(".json") ? base : "\(base)/index.json")
    default: return nil
    }
}

// MARK: - ExtensionService

/// Singleton that manages Hayase-compatible JS torrent extensions.
/// Matches the behaviour of ConfigManager + CodeManager in storage.ts, and the
/// getResultsFromExtensions method from extensions.ts.
@MainActor
final class ExtensionService {

    static let shared = ExtensionService()

    // MARK: - Stored state (mirrors persisted svelte stores)

    /// Persisted extension configs (mirrors savedConfigs)
    private(set) var configs: [String: ExtensionConfig] = [:] {
        didSet { saveConfigs() }
    }
    /// Persisted extension options (mirrors savedOptions)
    private(set) var options: [String: ExtensionOptions] = [:] {
        didSet { saveOptions() }
    }

    // MARK: - Workers (mirrors CodeManager.extensions Map)

    /// Active extension workers keyed by extension ID
    private(set) var workers: [String: ExtensionWorker] = [:]

    /// Mirrors storage.ready — resolves when initiate() finishes loading cached workers.
    /// search() awaits this before checking workers, matching Hayase's
    /// `await storage.ready` in getResultsFromExtensions().
    private var readyTask: Task<Void, Never>?

    // MARK: - Initialisation

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let configsKey = "ext.savedConfigs"
    private let optionsKey = "ext.savedOptions"

    private init() {
        loadFromDefaults()
        Task { await update() }
        readyTask = Task { await initiate(configs: Array(configs.values)) }
    }

    // MARK: - ConfigManager.import (mirrors storage.ts import())

    /// Download and install extensions from a manifest URL.
    /// Mirrors ConfigManager.import(url).
    func importExtension(from rawURL: String) async throws {
        guard let url = jsonurl(rawURL) else {
            throw ExtensionError.invalidURL("Invalid extension manifest URL: \(rawURL)")
        }

        let (data, _) = try await URLSession.shared.data(from: url)
        guard let newConfigs = try? decoder.decode([ExtensionConfig].self, from: data) else {
            throw ExtensionError.invalidManifest("Make sure the link is a valid JSON config for Hayase")
        }

        var attemptedOverrides: [String] = []
        var valid: [ExtensionConfig] = []

        for c in newConfigs {
            guard validateConfig(c) else {
                throw ExtensionError.invalidManifest("Extension config for '\(c.name)' is invalid")
            }
            if configs[c.id] != nil {
                attemptedOverrides.append(c.id)
            } else {
                valid.append(c)
            }
        }

        let invalidIDs = await downloadScripts(valid)
        let good = valid.filter { !invalidIDs.contains($0.id) }
        ensureOptions(ids: good.map(\.id))
        for c in good { configs[c.id] = c }

        if !attemptedOverrides.isEmpty {
            throw ExtensionError.alreadyExists(
                "Extensions already exist and were not imported: \(attemptedOverrides.joined(separator: ", "))\n" +
                "Delete the existing extensions first to override them.")
        }
    }

    // MARK: - ConfigManager.delete (mirrors storage.ts delete())

    func delete(id: String) async {
        workers[id]?.destroy()
        workers.removeValue(forKey: id)
        configs.removeValue(forKey: id)
        options.removeValue(forKey: id)
    }

    // MARK: - ConfigManager.setEnabled / setOption

    func setEnabled(_ enabled: Bool, for id: String) {
        options[id]?.enabled = enabled
    }

    func setOption(_ value: AnyCodableValue, key: String, for id: String) {
        options[id]?.options[key] = value
    }

    func sourceCode(for id: String) async throws -> String {
        guard let config = configs[id], let url = jsurl(config.code) else {
            throw ExtensionError.invalidURL("Invalid extension source URL")
        }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true,
              let source = String(data: data, encoding: .utf8) else {
            throw ExtensionError.invalidManifest("Could not load extension source code")
        }
        return source
    }

    // MARK: - ConfigManager.update (mirrors storage.ts update())

    /// Fetch updated configs from all stored update URLs and reload changed extensions.
    func update() async {
        let updateURLs = Set(configs.values.compactMap(\.update))
        guard !updateURLs.isEmpty else { return }

        var newConfigs: [ExtensionConfig] = []
        await withTaskGroup(of: [ExtensionConfig]?.self) { group in
            for rawURL in updateURLs {
                group.addTask {
                    guard let url = jsonurl(rawURL),
                          let (data, _) = try? await URLSession.shared.data(from: url),
                          let arr = try? JSONDecoder().decode([ExtensionConfig].self, from: data) else { return nil }
                    return arr
                }
            }
            for await result in group { if let r = result { newConfigs.append(contentsOf: r) } }
        }

        let safeToUpdate = newConfigs.filter { c in
            validateConfig(c) &&
            ((configs[c.id]?.update == c.update && c.version != configs[c.id]?.version) || configs[c.id] == nil)
        }

        let invalidIDs = await downloadScripts(safeToUpdate, update: true)
        let good = safeToUpdate.filter { !invalidIDs.contains($0.id) }
        ensureOptions(ids: good.map(\.id))
        for c in good { configs[c.id] = c }
    }

    // MARK: - Extensions.getResultsFromExtensions (mirrors extensions.ts)

    /// High-level entry point matching Hayase's Extensions.getResultsFromExtensions(media:episode:resolution:).
    /// Fetches ALL IDs from api.ani.zip in a SINGLE request (episodes endpoint returns
    /// mappings + per-episode data), then delegates to search(query:).
    ///
    /// Mirrors Hayase's getResultsFromExtensions exactly:
    ///   const aniDBMeta = await this.ALToAniDB(media)
    ///   const { anidb_id: anidbAid, mal_id: malId, ... } = aniDBMeta?.mappings ?? {}
    ///   const { anidbEid, tvdbId: tvdbEId, absoluteEpisodeNumber } = await this.ALtoAniDBEpisode(...)
    func search(for item: AnimeItem,
                episode: Int,
                resolution: String,
                onUpdate: (([TorrentResult]) -> Void)? = nil) async throws -> [TorrentResult] {
        let ids = await fetchAniZipData(item: item, episode: episode)

        var query = TorrentQuery.make(from: item, episode: episode, resolution: resolution)
        query.anidbAid             = ids.aid
        query.anidbEid             = ids.eid
        query.malId                = ids.malId
        query.tvdbId               = ids.tvdbId
        query.tvdbEId              = ids.tvdbEId
        query.tmdbId               = ids.tmdbId
        query.kitsuId              = ids.kitsuId
        query.imdbId               = ids.imdbId
        // absoluteEpisodeNumber comes from the episode entry (separate from anidbEid).
        // Hayase: const { anidbEid, tvdbId: tvdbEId, absoluteEpisodeNumber } = ALtoAniDBEpisode(...)
        // When unavailable, leave nil — do NOT fallback to eid (anidbEid is a different field).
        query.absoluteEpisodeNumber = ids.absoluteEpisodeNumber

        return try await search(query: query, onUpdate: onUpdate)
    }

    /// Fetches ALL IDs from api.ani.zip in ONE request.
    ///
    /// Implements the equivalent of Hayase's ALToAniDB + ALtoAniDBEpisode using a single
    /// /v1/episodes?anilist_id=X request (same endpoint Hayase uses via _episodes()).
    ///
    /// Mirrors Hayase's ALToAniDB: if no anidb_id in mappings AND format is SPECIAL/OVA/ONA,
    /// falls back to the parent/prequel/sequel's ani.zip data (getParentForSpecial).
    ///
    /// Episode IDs are selected through the same makeEpisodeList path as interface:
    /// direct key lookup for normal shows, and air-date validation when specials/count
    /// mismatches require it.
    private func fetchAniZipData(item: AnimeItem, episode: Int) async -> (
        aid: Int?, eid: Int?,
        malId: Int?, tvdbId: Int?, tvdbEId: Int?,
        tmdbId: String?, kitsuId: Int?, imdbId: String?,
        absoluteEpisodeNumber: Int?
    ) {
        let empty = (aid: nil as Int?, eid: nil as Int?,
                     malId: nil as Int?, tvdbId: nil as Int?, tvdbEId: nil as Int?,
                     tmdbId: nil as String?, kitsuId: nil as Int?, imdbId: nil as String?,
                     absoluteEpisodeNumber: nil as Int?)

        guard var json = await fetchAniZipJSON(anilistID: item.id) else {
            return empty
        }

        // ── Hayase ALToAniDB: getParentForSpecial fallback ────────────────────────────
        // If no anidb_id in mappings AND format is SPECIAL/OVA/ONA, try the parent
        // relation's ani.zip data instead. Mirrors:
        //   const json = await _episodes(media.id)
        //   if (json?.mappings?.anidb_id) return json
        //   const parentID = getParentForSpecial(media)
        //   if (!parentID) return
        //   return await _episodes(parentID)
        let mappings = json["mappings"] as? [String: Any]
        let hasAnidbId = Self.intValue(mappings?["anidb_id"]) != nil

        if !hasAnidbId, let fmt = item.format,
           ["SPECIAL", "OVA", "ONA"].contains(fmt) {
            // getParentForSpecial: find PARENT, then PREQUEL, then SEQUEL relation
            let parentID = ["PARENT", "PREQUEL", "SEQUEL"].lazy.compactMap { relType -> Int? in
                item.relations.first { $0.relationType == relType }?.media.id
            }.first
            if let parentID, let parentJSON = await fetchAniZipJSON(anilistID: parentID) {
                json = parentJSON
            }
        }

        // ── Mappings: series-level IDs ────────────────────────────────────────────────
        // Mirrors: const { anidb_id: anidbAid, mal_id: malId, ... } = aniDBMeta?.mappings ?? {}
        let finalMappings = json["mappings"] as? [String: Any]
        let aid     = Self.intValue(finalMappings?["anidb_id"])
        let malId   = Self.intValue(finalMappings?["mal_id"])
        let tvdbId  = Self.intValue(finalMappings?["thetvdb_id"])
        let kitsuId = Self.intValue(finalMappings?["kitsu_id"])
        let tmdbId  = Self.stringValue(finalMappings?["themoviedb_id"])
        let imdbId  = Self.stringValue(finalMappings?["imdb_id"])

        // ── Episodes: same entry selection used by makeEpisodeList ───────────────────
        // Hayase passes torrent metadata through makeEpisodeList(media, episodesRes)[episode - 1],
        // not a separate endpoint. Keep the same default key lookup and special-airdate validation.
        var eid: Int?
        var tvdbEId: Int?
        var absoluteEpNum: Int?

        if let ep = Self.selectedEpisode(from: json, item: item, episode: episode) {
            eid           = Self.intValue(ep["anidbEid"])
            tvdbEId       = Self.intValue(ep["tvdbId"])
            absoluteEpNum = Self.intValue(ep["absoluteEpisodeNumber"])
        }

        print("ExtensionService: anilist_id=\(item.id) ep=\(episode) → anidbAid=\(aid.map(String.init) ?? "nil") anidbEid=\(eid.map(String.init) ?? "nil") malId=\(malId.map(String.init) ?? "nil")")
        return (aid, eid, malId, tvdbId, tvdbEId, tmdbId, kitsuId, imdbId, absoluteEpNum)
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let n = value as? NSNumber { return n.intValue }
        if let s = value as? String { return Int(s) ?? Int(Double(s) ?? 0) }
        return nil
    }

    private static func stringValue(_ value: Any?) -> String? {
        if let s = value as? String, !s.isEmpty { return s }
        if let n = value as? NSNumber { return n.stringValue }
        return nil
    }

    private struct RawAniZipEpisode {
        let key: String
        let data: [String: Any]
        let airdatems: Double?
        let anidbEid: Int?
    }

    private static func selectedEpisode(from json: [String: Any], item: AnimeItem, episode: Int) -> [String: Any]? {
        guard episode > 0, let episodes = json["episodes"] as? [String: Any] else { return nil }

        let hasSpecial = (intValue(json["specialCount"]) ?? 0) > 0
        let hasEpisode = episodes["\(episode)"] != nil
        let hasCountMatch = (item.episodes ?? 0) == (intValue(json["episodeCount"]) ?? 0)
        let needsValidation = !(!hasSpecial || (hasEpisode && hasCountMatch))

        guard needsValidation else {
            return episodes["\(episode)"] as? [String: Any]
        }

        var filtered: [String: RawAniZipEpisode] = [:]
        for (key, value) in episodes {
            guard let data = value as? [String: Any] else { continue }
            let airdatems = dateValue(data["airdate"] as? String)?.timeIntervalSince1970
            filtered[key] = RawAniZipEpisode(key: key,
                                             data: data,
                                             airdatems: airdatems,
                                             anidbEid: intValue(data["anidbEid"]))
        }

        let schedule = interfaceAiringSchedule(for: item)
        let now = Date().timeIntervalSince1970
        var resolved: RawAniZipEpisode?

        // Interface calls makeEpisodeList(media, episodesRes)[episode - 1]. Re-run that
        // sequential selection up to the requested episode so the same consumed-special
        // deletion rules are applied before returning torrent metadata for this episode.
        for current in 1...episode {
            let currentHasEpisode = episodes["\(current)"] != nil
            let currentNeedsValidation = !(!hasSpecial || (currentHasEpisode && hasCountMatch))
            let currentResolved = currentNeedsValidation
                ? episodeByAirDate(alDate: schedule[current], filtered: filtered, episode: current)
                : filtered["\(current)"]

            if currentNeedsValidation, let currentResolved {
                var keysToRemove: [String] = []
                for (key, value) in filtered {
                    if let eid = value.anidbEid, let resolvedEid = currentResolved.anidbEid, eid == resolvedEid {
                        keysToRemove.append(key)
                    } else if let entryMs = value.airdatems, entryMs < (currentResolved.airdatems ?? now) {
                        keysToRemove.append(key)
                    }
                }
                for key in keysToRemove {
                    filtered.removeValue(forKey: key)
                }
            }

            if current == episode {
                resolved = currentResolved
            }
        }

        return resolved?.data ?? episodes["\(episode)"] as? [String: Any]
    }

    private static func episodeByAirDate(alDate: Date?,
                                         filtered: [String: RawAniZipEpisode],
                                         episode: Int) -> RawAniZipEpisode? {
        guard let alDate, alDate.timeIntervalSince1970 != 0 else {
            return filtered["\(episode)"]
        }

        var closest: [RawAniZipEpisode] = []
        var closestDistance = Double.infinity
        for entry in filtered.values {
            let distance = abs((entry.airdatems ?? 0) - alDate.timeIntervalSince1970)
            if distance < closestDistance {
                closestDistance = distance
                closest = [entry]
            } else if distance == closestDistance {
                closest.append(entry)
            }
        }

        guard !closest.isEmpty else {
            return filtered["\(episode)"]
        }

        return closest.min { lhs, rhs in
            let lhsEp = intValue(lhs.data["episode"]) ?? Int(lhs.key) ?? 0
            let rhsEp = intValue(rhs.data["episode"]) ?? Int(rhs.key) ?? 0
            return abs(lhsEp - episode) < abs(rhsEp - episode)
        }
    }

    private static func dateValue(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        if let date = ISO8601DateFormatter().date(from: raw) { return date }
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        return fmt.date(from: raw)
    }

    private static func interfaceAiringSchedule(for item: AnimeItem) -> [Int: Date] {
        var schedule: [Int: Date] = [:]
        for node in item.airedSchedule + item.notYetAiredSchedule {
            guard schedule[node.episode] == nil, let airingAt = node.airingAt else { continue }
            schedule[node.episode] = Date(timeIntervalSince1970: Double(airingAt))
        }
        return schedule
    }

    /// Fetch raw JSON from api.ani.zip for a given AniList ID.
    /// Shared by fetchAniZipData for both the primary request and the parent fallback.
    private func fetchAniZipJSON(anilistID: Int) async -> [String: Any]? {
        guard let url = URL(string: "https://api.ani.zip/v1/episodes?anilist_id=\(anilistID)") else {
            return nil
        }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse).map({ $0.statusCode == 200 }) != false,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            print("ExtensionService: api.ani.zip fetch failed for anilist_id=\(anilistID)")
            return nil
        }
        return json
    }

    /// Search all enabled torrent extensions and deduplicate results.
    /// Mirrors Hayase interface's streamed search flow: every extension method is
    /// started immediately and each completed chunk is surfaced without waiting for
    /// slower extensions or tracker scraping.
    func search(query: TorrentQuery, onUpdate: (([TorrentResult]) -> Void)? = nil) async throws -> [TorrentResult] {
        await readyTask?.value

        if workers.isEmpty {
            let enabledConfigs = configs.filter { id, config in
                (options[id]?.enabled ?? false) && config.type == "torrent"
            }
            for (id, config) in enabledConfigs {
                guard workers[id] == nil, let url = jsurl(config.code) else { continue }
                await loadWorker(url: url, id: id)
            }
        }

        let enabledWorkers = workers.filter { id, _ in
            (options[id]?.enabled ?? false) && configs[id]?.type == "torrent"
        }
        guard !enabledWorkers.isEmpty else {
            let hasInstalled = configs.values.contains { config in
                (options[config.id]?.enabled ?? false) && config.type == "torrent"
            }
            if hasInstalled {
                throw ExtensionError.noExtensions("Extension failed to initialise. Try restarting the app.")
            }
            throw ExtensionError.noExtensions("No torrent extensions configured. Add extensions in Settings → Extensions.")
        }

        let fmt = query.mediaJSON["format"] as? String
        let titleDict = query.mediaJSON["title"] as? [String: Any]
        let allNames: [String] = (
            (titleDict?.values.compactMap { $0 as? String } ?? [])
            + ((query.mediaJSON["synonyms"] as? [String]) ?? [])
        )
        let mediaEpisodes = query.mediaJSON["episodes"] as? Int
        let mediaDuration = query.mediaJSON["duration"] as? Int
        let isMovie = fmt == "MOVIE"
            || allNames.contains { $0.lowercased().contains("movie") }
            || ((mediaDuration ?? 0) > 80 && mediaEpisodes == 1)
        let isSingleEp = mediaEpisodes == 1 || (isMovie && mediaEpisodes == nil)
        let checkMovie = !isSingleEp && isMovie
        let checkBatch = !isSingleEp && !isMovie

        var all: [TorrentResult] = []
        var errors: [(id: String, error: Error)] = []

        await withTaskGroup(of: SearchChunk.self) { group in
            for (extId, worker) in enabledWorkers {
                let opts = options[extId]?.options.mapValues(\.jsonCompatible) ?? [:]
                addSearchTask(to: &group, extId: extId, method: "single") {
                    try await worker.single(query: query, options: opts)
                }
                if checkMovie {
                    addSearchTask(to: &group, extId: extId, method: "movie") {
                        try await worker.movie(query: query, options: opts)
                    }
                }
                if checkBatch {
                    addSearchTask(to: &group, extId: extId, method: "batch") {
                        try await worker.batch(query: query, options: opts)
                    }
                }
            }

            for await chunk in group {
                if let error = chunk.error {
                    errors.append((chunk.extensionId, error))
                    print("ExtensionService: \(chunk.extensionId) \(chunk.method)() failed: \(error)")
                }

                if !chunk.results.isEmpty {
                    all.append(contentsOf: chunk.results)
                    let streamed = dedupe(all)
                    onUpdate?(streamed)
                }
            }
        }

        for (extId, error) in errors {
            print("ExtensionService: extension \(extId) error: \(error)")
        }

        if all.isEmpty && !errors.isEmpty {
            let messages = errors.prefix(3).map { "\($0.id): \($0.error.localizedDescription)" }
                .joined(separator: "\n")
            throw ExtensionError.callFailed(messages)
        }

        return dedupe(all)
    }

    private struct SearchChunk {
        let extensionId: String
        let method: String
        let results: [TorrentResult]
        let error: Error?
    }

    private func addSearchTask(to group: inout TaskGroup<SearchChunk>,
                               extId: String,
                               method: String,
                               operation: @escaping @MainActor () async throws -> [TorrentResult]) {
        group.addTask { @MainActor in
            do {
                var results = try await operation()
                for index in results.indices { results[index].extensionIds.insert(extId) }
                let counted = await Self.updatePeerCountsWithTimeout(results)
                return SearchChunk(extensionId: extId, method: method, results: counted, error: nil)
            } catch {
                return SearchChunk(extensionId: extId, method: method, results: [], error: error)
            }
        }
    }

    // MARK: - Update peer counts (mirrors web extensions.updatePeerCounts)

    /// Matches Hayase interface behavior: peer scraping improves a chunk when it
    /// finishes quickly, but search results are never blocked for more than 3s by
    /// tracker scrape latency.
    private static func updatePeerCountsWithTimeout(_ entries: [TorrentResult]) async -> [TorrentResult] {
        guard !entries.isEmpty else { return entries }
        return await withTaskGroup(of: [TorrentResult]?.self, returning: [TorrentResult].self) { group in
            group.addTask {
                await updatePeerCounts(entries)
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                return nil
            }

            for await result in group {
                group.cancelAll()
                return result ?? entries
            }
            return entries
        }
    }

    private static func updatePeerCounts(_ entries: [TorrentResult]) async -> [TorrentResult] {
        guard !entries.isEmpty else { return entries }
        let hashes = entries.map(\.hash)
        let scraped = await TrackerScrapeService.scrape(hashes: hashes)
        guard !scraped.isEmpty else { return entries }

        var updated = entries
        for scrapeResult in scraped {
            guard let index = updated.firstIndex(where: { $0.hash == scrapeResult.hash }) else { continue }
            updated[index].seeders = scrapeResult.complete
            updated[index].leechers = scrapeResult.incomplete
            updated[index].downloads = scrapeResult.downloaded
        }
        return updated
    }

    // MARK: - Dedupe (mirrors Extensions.dedupe)

    /// Mirrors web extensions.dedupe() exactly.
    /// - seeders/leechers: first non-zero wins (||=), values ≥ 30 000 are treated as bogus → 0
    /// - downloads/size/date: first non-zero/non-nil wins (||=)
    /// - id: first non-nil wins (??=)
    /// - type: best > alt > batch priority (lower index wins)
    private func dedupe(_ entries: [TorrentResult]) -> [TorrentResult] {
        let accuracyRank = ["high": 0, "medium": 1, "low": 2]
        let typeRank     = ["best": 0, "alt": 1, "batch": 2]
        var seen: [String: TorrentResult] = [:]
        for entry in entries {
            if var existing = seen[entry.hash] {
                // Merge extension IDs
                existing.extensionIds.formUnion(entry.extensionIds)
                // Take better accuracy (lower rank = better)
                let eRank = accuracyRank[entry.accuracy]    ?? 2
                let xRank = accuracyRank[existing.accuracy] ?? 2
                if eRank < xRank { existing.accuracy = entry.accuracy }
                // Prefer longer title
                if entry.title.count > existing.title.count { existing.title = entry.title }
                // link: first non-empty wins (??=)
                if existing.link.isEmpty { existing.link = entry.link }
                // id: first non-nil wins (??=)
                if existing.id == nil { existing.id = entry.id }
                // seeders/leechers: first non-zero wins, ≥30000 treated as bogus (web ||= with guard)
                if existing.seeders == 0 {
                    existing.seeders = entry.seeders >= 30_000 ? 0 : entry.seeders
                }
                if existing.leechers == 0 {
                    existing.leechers = entry.leechers >= 30_000 ? 0 : entry.leechers
                }
                // downloads/size: first non-zero wins (||=)
                if existing.downloads == 0 { existing.downloads = entry.downloads }
                if existing.size      == 0 { existing.size      = entry.size }
                // date: first non-nil wins (||=)
                if existing.date == nil { existing.date = entry.date }
                // type: best > alt > batch — lower index wins
                // Web: (rank(entry) <= rank(dupe) ? entry.type : dupe.type) ?? entry.type ?? dupe.type
                let eTypeRank = typeRank[entry.type    ?? "best"] ?? 0
                let xTypeRank = typeRank[existing.type ?? "best"] ?? 0
                let chosen = eTypeRank <= xTypeRank ? entry.type : existing.type
                existing.type = chosen ?? entry.type ?? existing.type
                seen[entry.hash] = existing
            } else {
                seen[entry.hash] = entry
            }
        }
        // Web returns Object.values(deduped) — no sorting here.
        // Sorting happens later in filterAndSortResults().
        return Array(seen.values)
    }

    // MARK: - Internal: CodeManager methods

    /// mirrors CodeManager.initiate — loads all configured extensions from their esm.sh URLs
    private func initiate(configs: [ExtensionConfig]) async {
        await withTaskGroup(of: Void.self) { group in
            for config in configs {
                group.addTask { @MainActor in
                    guard let url = jsurl(config.code) else {
                        print("ExtensionService: invalid code URL for \(config.id): \(config.code)")
                        return
                    }
                    await self.loadWorker(url: url, id: config.id)
                }
            }
        }
    }

    /// mirrors CodeManager.downloadScripts — resolves the esm.sh URL and loads the worker
    @discardableResult
    private func downloadScripts(_ cfgs: [ExtensionConfig], update: Bool = false) async -> [String] {
        var invalid: [String] = []
        for config in cfgs {
            if workers[config.id] != nil && !update { continue }
            guard let url = jsurl(config.code) else {
                print("ExtensionService: invalid code URL for \(config.id): \(config.code)")
                invalid.append(config.id)
                continue
            }
            await loadWorker(url: url, id: config.id)
            if workers[config.id] == nil {
                invalid.append(config.id)
            }
        }
        return invalid
    }

    /// mirrors CodeManager._loadWorker — creates/replaces a WKWebView worker
    private func loadWorker(url: URL, id: String) async {
        // Destroy old worker first
        if let old = workers[id] {
            old.destroy()
            workers.removeValue(forKey: id)
        }
        let worker = ExtensionWorker(id: id)
        do {
            try await worker.load(extensionURL: url)
            workers[id] = worker
            print("ExtensionService: loaded worker for \(id)")
        } catch {
            print("ExtensionService: failed to load worker for \(id): \(error)")
        }
    }

    // MARK: - Persistence helpers

    private func loadFromDefaults() {
        let ud = UserDefaults.standard
        if let d = ud.data(forKey: configsKey),
           let c = try? decoder.decode([String: ExtensionConfig].self, from: d) { configs = c }
        if let d = ud.data(forKey: optionsKey),
           let o = try? decoder.decode([String: ExtensionOptions].self, from: d) { options = o }
    }

    private func saveConfigs() {
        if let d = try? encoder.encode(configs) { UserDefaults.standard.set(d, forKey: configsKey) }
    }

    private func saveOptions() {
        if let d = try? encoder.encode(options) { UserDefaults.standard.set(d, forKey: optionsKey) }
    }

    private func ensureOptions(ids: [String], enabled: Bool = true) {
        for id in ids where options[id] == nil {
            options[id] = ExtensionOptions(options: [:], enabled: enabled)
        }
    }

    // MARK: - Validation (mirrors ConfigManager._validateConfig)

    private func validateConfig(_ config: ExtensionConfig) -> Bool {
        !config.name.isEmpty && !config.version.isEmpty && !config.id.isEmpty &&
        !config.type.isEmpty && !config.accuracy.isEmpty && !config.code.isEmpty
    }
}

// MARK: - ExtensionError

enum ExtensionError: LocalizedError {
    case invalidURL(String)
    case invalidManifest(String)
    case alreadyExists(String)
    case noExtensions(String)
    case callFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL(let m),
             .invalidManifest(let m),
             .alreadyExists(let m),
             .noExtensions(let m),
             .callFailed(let m): return m
        }
    }
}
