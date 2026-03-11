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
        await workers[id]?.destroy()
        workers.removeValue(forKey: id)
        configs.removeValue(forKey: id)
        options.removeValue(forKey: id)
        // Remove cached JS file
        let file = try? extensionsDirectory().appendingPathComponent("\(id).js")
        if let file { try? FileManager.default.removeItem(at: file) }
    }

    // MARK: - ConfigManager.setEnabled / setOption

    func setEnabled(_ enabled: Bool, for id: String) {
        if options[id] != nil {
            options[id]!.enabled = enabled
        }
    }

    func setOption(_ value: AnyCodableValue, key: String, for id: String) {
        if options[id] != nil {
            options[id]!.options[key] = value
        }
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

    /// Search all enabled torrent extensions and deduplicate results.
    /// Mirrors Extensions.getResultsFromExtensions in extensions.ts.
    func search(query: TorrentQuery) async throws -> [TorrentResult] {
        // Mirrors Hayase: `await storage.ready` before checking extensions.size
        await readyTask?.value

        let enabledWorkers = workers.filter { id, _ in
            (options[id]?.enabled ?? false) && (configs[id]?.type == "torrent")
        }
        guard !enabledWorkers.isEmpty else {
            throw ExtensionError.noExtensions("No torrent extensions configured. Add extensions in Settings → Extensions.")
        }

        var all: [TorrentResult] = []
        var errors: [(id: String, error: Error)] = []

        let isMovie  = (query.mediaJSON["format"] as? String) == "MOVIE"
        let isSingleEp = (query.mediaJSON["episodes"] as? Int) == 1

        await withTaskGroup(of: ([TorrentResult], [(String, Error)]).self) { group in
            for (extId, worker) in enabledWorkers {
                let opts = options[extId]?.options.mapValues(\.jsonCompatible) ?? [:]
                group.addTask { @MainActor in
                    var results: [TorrentResult] = []
                    var errs: [(String, Error)] = []

                    // Always call single()
                    do {
                        var r = try await worker.single(query: query, options: opts)
                        for i in r.indices { r[i].extensionIds.insert(extId) }
                        results.append(contentsOf: r)
                    } catch { errs.append((extId, error)) }

                    // Call movie() for movie-format anime that are not single episodes
                    if isMovie && !isSingleEp {
                        do {
                            var r = try await worker.movie(query: query, options: opts)
                            for i in r.indices { r[i].extensionIds.insert(extId) }
                            results.append(contentsOf: r)
                        } catch { errs.append((extId, error)) }
                    }

                    // Call batch() for multi-episode non-movie anime
                    if !isMovie && !isSingleEp {
                        do {
                            var r = try await worker.batch(query: query, options: opts)
                            for i in r.indices { r[i].extensionIds.insert(extId) }
                            results.append(contentsOf: r)
                        } catch { errs.append((extId, error)) }
                    }

                    return (results, errs)
                }
            }

            for await (results, errs) in group {
                all.append(contentsOf: results)
                errors.append(contentsOf: errs)
            }
        }

        // Log errors but don't throw if we got some results
        for (extId, err) in errors {
            print("ExtensionService: extension \(extId) error: \(err)")
        }

        return dedupe(all)
    }

    // MARK: - Dedupe (mirrors Extensions.dedupe)

    private func dedupe(_ entries: [TorrentResult]) -> [TorrentResult] {
        let accuracyRank = ["high": 0, "medium": 1, "low": 2]
        var seen: [String: TorrentResult] = [:]
        for entry in entries {
            if var existing = seen[entry.hash] {
                // Merge extension IDs
                existing.extensionIds.formUnion(entry.extensionIds)
                // Take better accuracy
                let eRank = accuracyRank[entry.accuracy]    ?? 2
                let xRank = accuracyRank[existing.accuracy] ?? 2
                if eRank < xRank { existing.accuracy = entry.accuracy }
                // Prefer longer title
                if entry.title.count > existing.title.count { existing.title = entry.title }
                existing.link      = existing.link.isEmpty      ? entry.link      : existing.link
                existing.seeders   = existing.seeders   == 0    ? entry.seeders   : existing.seeders
                existing.leechers  = existing.leechers  == 0    ? entry.leechers  : existing.leechers
                existing.downloads = existing.downloads == 0    ? entry.downloads : existing.downloads
                existing.size      = existing.size      == 0    ? entry.size      : existing.size
                if existing.type == nil { existing.type = entry.type }
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

    /// mirrors CodeManager.initiate — loads cached code for all configured extensions
    private func initiate(configs: [ExtensionConfig]) async {
        await withTaskGroup(of: Void.self) { group in
            for config in configs {
                group.addTask { @MainActor in
                    guard let code = self.cachedCode(for: config.id) else { return }
                    await self.loadWorker(code: code, id: config.id)
                }
            }
        }
    }

    /// mirrors CodeManager.downloadScripts — fetches JS code for new/updated extensions
    @discardableResult
    private func downloadScripts(_ cfgs: [ExtensionConfig], update: Bool = false) async -> [String] {
        var invalid: [String] = []
        for config in cfgs {
            if workers[config.id] != nil && !update { continue }
            guard let codeURL = jsurl(config.code),
                  let (data, _) = try? await URLSession.shared.data(from: codeURL),
                  let code = String(data: data, encoding: .utf8) else {
                invalid.append(config.id)
                continue
            }
            // Cache the code
            cacheCode(code, for: config.id)
            await loadWorker(code: code, id: config.id)
        }
        return invalid
    }

    /// mirrors CodeManager._loadWorker — creates/replaces a WKWebView worker
    private func loadWorker(code: String, id: String) async {
        // Destroy old worker first
        if let old = workers[id] {
            old.destroy()
            workers.removeValue(forKey: id)
        }
        let worker = ExtensionWorker(id: id)
        do {
            try await worker.load(code: code)
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

    // MARK: - Code cache (mirrors idb-keyval set/getMany)

    private func extensionsDirectory() throws -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir  = base.appendingPathComponent("Extensions", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func cacheCode(_ code: String, for id: String) {
        guard let dir = try? extensionsDirectory() else { return }
        try? code.write(to: dir.appendingPathComponent("\(id).js"), atomically: true, encoding: .utf8)
    }

    private func cachedCode(for id: String) -> String? {
        guard let dir = try? extensionsDirectory() else { return nil }
        return try? String(contentsOf: dir.appendingPathComponent("\(id).js"), encoding: .utf8)
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
