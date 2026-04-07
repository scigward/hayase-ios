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
    func search(for item: AnimeItem, episode: Int, resolution: String) async throws -> [TorrentResult] {
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

        return try await search(query: query)
    }

    /// Fetches ALL IDs from api.ani.zip in ONE request.
    ///
    /// Implements the equivalent of Hayase's ALToAniDB + ALtoAniDBEpisode using a single
    /// /v1/episodes?anilist_id=X request (same endpoint Hayase uses via _episodes()).
    ///
    /// Mirrors Hayase's ALToAniDB: if no anidb_id in mappings AND format is SPECIAL/OVA/ONA,
    /// falls back to the parent/prequel/sequel's ani.zip data (getParentForSpecial).
    ///
    /// Key: uses direct dict key lookup (episodes["\(episode)"]) matching Hayase's
    /// filtered.get('' + episode) in the default makeEpisodeList path.
    ///
    /// Uses (x as? NSNumber)?.intValue for all int extraction — JSONSerialization always
    /// boxes JSON numbers as NSNumber; `as? Int` returns nil for Double-backed NSNumbers.
    private func fetchAniZipData(item: AnimeItem, episode: Int) async -> (
        aid: Int?, eid: Int?,
        malId: Int?, tvdbId: Int?, tvdbEId: Int?,
        tmdbId: Int?, kitsuId: Int?, imdbId: String?,
        absoluteEpisodeNumber: Int?
    ) {
        let empty = (aid: nil as Int?, eid: nil as Int?,
                     malId: nil as Int?, tvdbId: nil as Int?, tvdbEId: nil as Int?,
                     tmdbId: nil as Int?, kitsuId: nil as Int?, imdbId: nil as String?,
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
        let hasAnidbId = (mappings?["anidb_id"] as? NSNumber)?.intValue != nil

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
        let aid     = (finalMappings?["anidb_id"]      as? NSNumber)?.intValue
        let malId   = (finalMappings?["mal_id"]        as? NSNumber)?.intValue
        let tvdbId  = (finalMappings?["thetvdb_id"]    as? NSNumber)?.intValue
        let kitsuId = (finalMappings?["kitsu_id"]      as? NSNumber)?.intValue
        let tmdbId  = (finalMappings?["themoviedb_id"] as? NSNumber)?.intValue
        let imdbId  = finalMappings?["imdb_id"] as? String

        // ── Episodes: direct dict key lookup ─────────────────────────────────────────
        // Hayase: makeEpisodeList(media, episodesRes)[episode - 1]
        //
        // In the default case (no specials or count mismatch), makeEpisodeList does
        // a simple dict key lookup: filtered.get('' + episode). The ani.zip episodes
        // dict is keyed by episode number as a string ("1", "2", "3", etc.).
        // We match Hayase's approach exactly: look up episodes["\(episode)"] directly.
        var eid: Int?
        var tvdbEId: Int?
        var absoluteEpNum: Int?

        if let episodes = json["episodes"] as? [String: Any] {
            // Direct key lookup: episode 3 → episodes["3"]
            // Matches Hayase: filtered.get('' + episode)
            if let ep = episodes["\(episode)"] as? [String: Any] {
                eid          = (ep["anidbEid"]              as? NSNumber)?.intValue
                tvdbEId      = (ep["tvdbId"]                as? NSNumber)?.intValue
                absoluteEpNum = (ep["absoluteEpisodeNumber"] as? NSNumber)?.intValue
            }
        }

        print("ExtensionService: anilist_id=\(item.id) ep=\(episode) → anidbAid=\(aid.map(String.init) ?? "nil") anidbEid=\(eid.map(String.init) ?? "nil") malId=\(malId.map(String.init) ?? "nil")")
        return (aid, eid, malId, tvdbId, tvdbEId, tmdbId, kitsuId, imdbId, absoluteEpNum)
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
    /// Mirrors Extensions.getResultsFromExtensions in extensions.ts.
    func search(query: TorrentQuery) async throws -> [TorrentResult] {
        // Mirrors Hayase: `await storage.ready` before checking extensions.size
        await readyTask?.value

        // Lazy-load fallback: if workers is empty but enabled configs exist, the
        // initial load() may have failed before the WKWebView was ready.
        // Try loading now that the user is actively using the extension.
        if workers.isEmpty {
            let enabledConfigs = configs.filter { id, c in
                (options[id]?.enabled ?? false) && c.type == "torrent"
            }
            if !enabledConfigs.isEmpty {
                for (id, config) in enabledConfigs {
                    guard workers[id] == nil, let url = jsurl(config.code) else { continue }
                    await loadWorker(url: url, id: id)
                }
            }
        }

        let enabledWorkers = workers.filter { id, _ in
            (options[id]?.enabled ?? false) && (configs[id]?.type == "torrent")
        }
        guard !enabledWorkers.isEmpty else {
            // Give a more helpful message if extensions are installed but failed to load
            let hasInstalled = configs.values.contains { c in
                (options[c.id]?.enabled ?? false) && c.type == "torrent"
            }
            if hasInstalled {
                throw ExtensionError.noExtensions("Extension failed to initialise. Try restarting the app.")
            }
            throw ExtensionError.noExtensions("No torrent extensions configured. Add extensions in Settings → Extensions.")
        }

        var all: [TorrentResult] = []
        var errors: [(id: String, error: Error)] = []

        // Mirrors Hayase util.ts isMovie(media) exactly:
        //   if (media.format === 'MOVIE') return true
        //   if ([...Object.values(media.title ?? {}), ...media.synonyms ?? []]
        //       .some(title => title?.toLowerCase().includes('movie'))) return true
        //   return (media.duration ?? 0) > 80 && media.episodes === 1
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

        // Mirrors Hayase util.ts isSingleEpisode(media) exactly:
        //   return media.episodes === 1 || (isMovie(media) && !media.episodes)
        let isSingleEp = mediaEpisodes == 1 || (isMovie && mediaEpisodes == nil)

        let checkMovie = !isSingleEp && isMovie
        let checkBatch = !isSingleEp && !isMovie

        // Run all extension calls concurrently — mirrors Hayase's Promise.allSettled:
        //   promises.push(worker.single(options, opts))
        //   if (checkMovie) promises.push(worker.movie(options, opts))
        //   if (checkBatch) promises.push(worker.batch(options, opts))
        //   for (const result of await Promise.allSettled(promises)) { ... }
        //
        // Previously single/batch ran SEQUENTIALLY inside one task: if single() timed
        // out (30s), batch() wouldn't run until 30s later. Now each method is its own
        // concurrent task within an inner TaskGroup, so they all start at the same time.
        await withTaskGroup(of: ([TorrentResult], [(String, Error)]).self) { group in
            for (extId, worker) in enabledWorkers {
                let opts = options[extId]?.options.mapValues(\.jsonCompatible) ?? [:]
                group.addTask { @MainActor in
                    // Inner TaskGroup: single / batch / movie run concurrently per extension
                    await withTaskGroup(of: ([TorrentResult], Error?).self) { inner in
                        // Always call single()
                        inner.addTask { @MainActor in
                            do {
                                var r = try await worker.single(query: query, options: opts)
                                for i in r.indices { r[i].extensionIds.insert(extId) }
                                return (r, nil)
                            } catch {
                                print("ExtensionService: \(extId) single() failed: \(error)")
                                return ([], error)
                            }
                        }
                        // Call movie() for movie-format non-single-ep anime
                        if checkMovie {
                            inner.addTask { @MainActor in
                                do {
                                    var r = try await worker.movie(query: query, options: opts)
                                    for i in r.indices { r[i].extensionIds.insert(extId) }
                                    return (r, nil)
                                } catch {
                                    print("ExtensionService: \(extId) movie() failed: \(error)")
                                    return ([], error)
                                }
                            }
                        }
                        // Call batch() for multi-episode non-movie anime
                        if checkBatch {
                            inner.addTask { @MainActor in
                                do {
                                    var r = try await worker.batch(query: query, options: opts)
                                    for i in r.indices { r[i].extensionIds.insert(extId) }
                                    return (r, nil)
                                } catch {
                                    print("ExtensionService: \(extId) batch() failed: \(error)")
                                    return ([], error)
                                }
                            }
                        }

                        var results: [TorrentResult] = []
                        var errs: [(String, Error)] = []
                        for await (r, e) in inner {
                            results.append(contentsOf: r)
                            if let e { errs.append((extId, e)) }
                        }
                        return (results, errs)
                    }
                }
            }

            for await (results, errs) in group {
                all.append(contentsOf: results)
                errors.append(contentsOf: errs)
            }
        }

        // Surface extension errors in the UI when no results were found.
        // If we got some results, log errors silently (partial success is still useful).
        for (extId, err) in errors {
            print("ExtensionService: extension \(extId) error: \(err)")
        }

        if all.isEmpty && !errors.isEmpty {
            // All extensions returned errors — surface the first meaningful message so
            // ExtensionSearchViewController can show it in the red errorLabel instead
            // of the unhelpful "No results found".
            let msgs = errors.prefix(3).map { "\($0.id): \($0.error.localizedDescription)" }
                             .joined(separator: "\n")
            throw ExtensionError.callFailed(msgs)
        }

        return dedupe(all)
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
        // Sort: high accuracy first, then by seeders descending
        return seen.values.sorted {
            let r0 = accuracyRank[$0.accuracy] ?? 2
            let r1 = accuracyRank[$1.accuracy] ?? 2
            return r0 == r1 ? $0.seeders > $1.seeders : r0 < r1
        }
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
