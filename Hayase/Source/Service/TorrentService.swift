//
//  TorrentService.swift
//  Hayase
//

import Foundation
import CoreData
import LibTorrent

public class TorrentService: NSObject, SessionDelegate {
    // MARK: - Types
    enum TorrentError: Error {
        case errorSavingCoreData
    }

    // MARK: - Singleton & notifications
    static let sharedTorrentService = TorrentService()
    static let TorrentInControllerDidUpdateNotification    = "TorrentInControllerDidUpdateNotification"
    static let TorrentInControllerUpdateFailedNotification = "TorrentInControllerUpdateFailedNotification"
    /// Posted on the main thread when a torrent is about to be removed from the
    /// session. `userInfo["torrentHash"]` contains the hex info-hash string.
    /// Consumers (e.g. MiniPlayerManager) observe this to tear down any player
    /// that is streaming the torrent being deleted, preventing use-after-free
    /// crashes in TorrentStreamer/LocalStreamServer.
    static let TorrentWillBeRemovedNotification = "TorrentServiceTorrentWillBeRemovedNotification"

    // MARK: - LibTorrent session + handle tracking
    let session: Session

    /// Hex-string keyed dict of active handles.
    /// Avoids TorrentHashes NSDictionary key-equality issues (TorrentHashes does not
    /// override isEqual:/hash, so NSDictionary lookups use pointer identity).
    /// All reads/writes happen on the main thread.
    private(set) var handles: [String: TorrentHandle] = [:]

    var insertIndexForTempEntries = 0

    /// Notification posted when torrent client settings change.
    /// TorrentDetailViewController and other consumers can observe this to refresh.
    static let SettingsDidChangeNotification = "TorrentServiceSettingsDidChangeNotification"

    override init() {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            fatalError("Documents directory unavailable")
        }
        let downloadsURL  = docs.appendingPathComponent("downloads")
        let torrentsURL   = docs.appendingPathComponent("torrents")
        let fastResumeURL = docs.appendingPathComponent("fastResume")

        [downloadsURL, torrentsURL, fastResumeURL].forEach {
            try? FileManager.default.createDirectory(at: $0, withIntermediateDirectories: true)
        }

        let settings = Self.makeSettings()

        session = Session(downloadsURL,
                         torrentsPath: torrentsURL,
                         fastResumePath: fastResumeURL,
                         settings: settings,
                         storages: [:])
        super.init()

        // Follow iTorrent init pattern: pause → snapshot restored torrents → resume → add delegate.
        // session.pause() prevents a deadlock where the alerts thread tries to read snapshot
        // data while updateSnapshot() is holding a lock on the same torrent.
        session.pause()
        for handle in session.torrents {
            handle.updateSnapshot()
            handles[handle.infoHashes.best.hex] = handle
            print("TorrentService: restored torrent '\(handle.snapshot.name)' hex=\(handle.infoHashes.best.hex)")
        }
        session.resume()
        session.add(self)   // register delegate AFTER pause/resume
    }

    // MARK: - Settings from UserDefaults (mirrors Hayase native.updateSettings)

    /// Build a Session.Settings from current UserDefaults values.
    /// Called at init and whenever the user changes client settings.
    private static func makeSettings() -> Session.Settings {
        let ud = UserDefaults.standard
        let settings = Session.Settings()
        settings.agentName        = "Hayase"

        // Torrent activity limits — default is 0 (no active torrents!) so we must set positive values.
        settings.maxActiveTorrents      = 4
        settings.maxDownloadingTorrents = 4
        settings.maxUploadingTorrents   = 4

        // Port settings — read from user prefs (Hayase: torrentPort, dhtPort).
        // 0 means auto-select (libtorrent picks an available port).
        let torrentPort = Int(ud.string(forKey: "pref_torrentPort") ?? "0") ?? 0
        let effectivePort = torrentPort > 0 ? torrentPort : 6881
        settings.port             = effectivePort
        settings.portBindRetries  = 10
        settings.listenInterfaces = "0.0.0.0:\(effectivePort)"
        settings.outgoingInterfaces = ""

        // Protocol features — honour Hayase "Disable DHT" / "Disable PeX" toggles.
        // Note: Hayase's torrentDHT/torrentPeX default to false (= not disabled = enabled).
        let disableDHT = ud.bool(forKey: "pref_disableDHT")
        let disablePeX = ud.bool(forKey: "pref_disablePeX")
        settings.isDhtEnabled  = !disableDHT
        settings.isLsdEnabled  = true
        settings.isUtpEnabled  = true
        settings.isUpnpEnabled = true
        settings.isNatEnabled  = true

        // Transfer speed limit (Mb/s → bytes/s).
        // Hayase default: 40 Mb/s.  0 = unlimited.
        let speedMbps = Int(ud.string(forKey: "pref_torrentSpeed") ?? "40") ?? 40
        let speedBytesPerSec = UInt(speedMbps) * 125_000   // Mb/s → bytes/s
        settings.maxDownloadSpeed = speedBytesPerSec
        settings.maxUploadSpeed   = speedBytesPerSec

        // Max connections per torrent (Hayase: maxConns, default 55).
        let maxConns = Int(ud.string(forKey: "pref_maxConns") ?? "55") ?? 55
        settings.connectionLimit = maxConns

        // Streamed download mode (Hayase: torrentStreamedDownload).
        settings.isStreamingMode = ud.bool(forKey: "pref_streamedDownload")

        // Persist files preference — read here so it participates in settings
        // change notifications.  The actual cleanup logic lives in
        // cleanupOtherTorrentsIfNeeded() which reads this key directly.
        let persistFiles = ud.bool(forKey: "pref_persistFiles")

        // PeX / Persist: these prefs are read and included so that changing them
        // triggers applyUserSettings().  Once LibTorrent-Swift exposes setters for
        // PeX control, wire `disablePeX` into the session settings here.
        _ = disablePeX
        _ = persistFiles

        // Disable HTTPS tracker cert validation — we don't bundle cacert.pem.
        settings.validateHttpsTrackers = false

        return settings
    }

    /// Re-read UserDefaults and apply updated settings to the live session.
    /// Call this when the user changes any client setting (speed, port, DHT, etc.).
    /// Mirrors Hayase's `torrentSettings.subscribe(native.updateSettings)`.
    func applyUserSettings() {
        session.settings = Self.makeSettings()
        NotificationCenter.default.post(name: NSNotification.Name(Self.SettingsDidChangeNotification), object: nil)
    }

    // MARK: - SessionDelegate
    // didAddTorrent fires synchronously from addTorrent() on the calling thread (main).
    // Call updateSnapshot() synchronously here — this matches iTorrent's prepareToAdd()
    // which calls updateSnapshot() synchronously before returning.
    public func torrentManager(_ manager: Session, didAddTorrent torrent: TorrentHandle) {
        torrent.updateSnapshot()
        handles[torrent.infoHashes.best.hex] = torrent
    }

    public func torrentManager(_ manager: Session, didRemoveTorrentWithHash hashesData: TorrentHashes) {
        let hex = hashesData.best.hex
        DispatchQueue.main.async { self.handles.removeValue(forKey: hex) }
    }

    // didReceiveUpdateForTorrent fires on the LibTorrent alerts background thread.
    // updateSnapshot() is called on a separate user-initiated background queue so
    // torrent_file() is accessed after libtorrent finishes processing the current alert.
    public func torrentManager(_ manager: Session, didReceiveUpdateForTorrent torrent: TorrentHandle) {
        let hex = torrent.infoHashes.best.hex
        DispatchQueue.global(qos: .userInitiated).async {
            torrent.updateSnapshot()
            DispatchQueue.main.async {
                // Guard against zombie updates: if the handle was removed between
                // the background snapshot and this main-thread callback (e.g. by
                // safeRemoveTorrent / removeOtherTorrents), don't re-add it.
                guard self.handles[hex] != nil else { return }
                self.handles[hex] = torrent
                NotificationCenter.default.post(
                    name: NSNotification.Name(TorrentService.TorrentInControllerDidUpdateNotification),
                    object: self,
                    userInfo: ["torrentHandle": torrent])
            }
        }
    }

    public func torrentManager(_ manager: Session, didErrorOccur error: Error) {
        print("TorrentService: session error: \(error)")
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: NSNotification.Name(TorrentService.TorrentInControllerUpdateFailedNotification),
                object: self,
                userInfo: ["error": error as NSError])
        }
    }

    /// Removes all active torrents (and their downloaded files) except the one
    /// matching `exceptHash`. Called when "Persist Files" is OFF to clean up
    /// previous torrents before a new one starts playing.
    ///
    /// Must be called AFTER the torrent handle is confirmed and `exceptHash` is
    /// the handle's actual `infoHashes.best.hex` — using the entity's hash or
    /// the magnet-extracted hash can cause a mismatch with the `handles` dict
    /// key, silently deleting the torrent the user is trying to play.
    private func removeOtherTorrents(exceptHash: String) {
        guard !exceptHash.isEmpty else {
            print("TorrentService: removeOtherTorrents — skipped (empty hash)")
            return
        }
        let toRemove = handles.filter { $0.key != exceptHash }
        for (hex, handle) in toRemove {
            print("TorrentService: persist OFF — removing torrent \(hex)")
            notifyWillRemove(hex: hex)
            // Remove from handles BEFORE session.removeTorrent() so that any
            // in-flight didReceiveUpdateForTorrent dispatches see the key is
            // gone and skip re-adding the zombie handle.
            handles.removeValue(forKey: hex)
            session.removeTorrent(handle, deleteFiles: true)
        }
    }

    /// If "Persist Files" is OFF, removes all torrents except the one with
    /// the given handle hash. Called after the torrent is successfully added
    /// or reused, guaranteeing the hash matches the `handles` dict key.
    private func cleanupOtherTorrentsIfNeeded(keepingHash hash: String) {
        let persistFiles = UserDefaults.standard.bool(forKey: "pref_persistFiles")
        if !persistFiles {
            removeOtherTorrents(exceptHash: hash)
        }
    }

    // MARK: - Public API

    /// Posts `TorrentWillBeRemovedNotification` synchronously on the main thread
    /// so that consumers (e.g. MiniPlayerManager) can tear down any active player
    /// referencing this torrent BEFORE the handle is freed by libtorrent.
    private func notifyWillRemove(hex: String) {
        NotificationCenter.default.post(
            name: NSNotification.Name(TorrentService.TorrentWillBeRemovedNotification),
            object: self,
            userInfo: ["torrentHash": hex])
    }

    /// Safely removes a torrent from the session. Posts a notification BEFORE
    /// removal so that any active player/streamer referencing the handle can
    /// tear down first, preventing use-after-free crashes.
    func safeRemoveTorrent(_ handle: TorrentHandle, deleteFiles: Bool) {
        let hex = handle.infoHashes.best.hex
        notifyWillRemove(hex: hex)
        // Remove from handles BEFORE session.removeTorrent() so that any
        // in-flight didReceiveUpdateForTorrent dispatches see the key is
        // gone and skip re-adding the zombie handle.
        handles.removeValue(forKey: hex)
        session.removeTorrent(handle, deleteFiles: deleteFiles)
    }

    func GetTorrentEntitiesFromHash(_ hashString: String) -> [Torrents] {
        let fetchRequest = NSFetchRequest<Torrents>(entityName: Torrents.entityName)
        fetchRequest.predicate = NSPredicate(format: "torrentHashString == %@", hashString)
        var res: [Torrents] = []
        do {
            res = try CoreDataService.sharedCoreDataService.mainQueueContext.fetch(fetchRequest)
        } catch let error {
            print("Error finding torrents from hash string: \(error)")
        }
        return res
    }

    /// Add the torrent (from magnet URI or .torrent file) to the LibTorrent session.
    /// Prefers the magnet URI stored in torrentDownloadURL.
    /// Falls back to downloading the .torrent binary when given an HTTP(S) URL.
    /// If the URL is missing or unsupported, constructs a magnet URI from the
    /// info-hash (covers extensions like Seadex that only provide a hash).
    /// When "Persist Files" is OFF (default), old torrents are cleaned up AFTER
    /// the new handle is confirmed — using the handle's actual hash to avoid
    /// accidentally deleting the torrent the user is trying to play.
    /// Calls `completion` on the main thread with a TorrentHandle or an Error.
    func UpdateTorrentEntityInController(_ torrentEntity: Torrents,
                                        completion: @escaping (Result<TorrentHandle, Error>) -> Void) {
        // Try to parse the stored download URL.
        let url: URL? = torrentEntity.torrentDownloadURL
            .flatMap { $0.isEmpty ? nil : URL(string: $0) }

        if let url, url.scheme == "magnet" {
            addMagnetToSession(url, torrentEntity: torrentEntity, completion: completion)
        } else if let url, url.scheme == "http" || url.scheme == "https" {
            downloadTorrentFile(from: url, torrentEntity: torrentEntity, completion: completion)
        } else if let magnetURL = magnetURLFromHash(torrentEntity.torrentHashString) {
            // No usable link — build a magnet URI from the info-hash.
            // This covers extensions (e.g. Seadex) that return only an info-hash
            // without a magnet URI or .torrent download URL.
            print("TorrentService: no usable link, constructed magnet from hash")
            addMagnetToSession(magnetURL, torrentEntity: torrentEntity, completion: completion)
        } else {
            DispatchQueue.main.async {
                completion(.failure(NSError(domain: "TorrentService", code: 0,
                    userInfo: [NSLocalizedDescriptionKey:
                        "No download URL or info-hash available for this torrent."])))
            }
        }
    }

    /// Build a `magnet:?xt=urn:btih:HASH` URL from a hex info-hash.
    /// Peer discovery relies on DHT, PeX, and trackers already embedded in
    /// the magnet URI or .torrent file.
    private func magnetURLFromHash(_ hash: String?) -> URL? {
        guard let hash, !hash.isEmpty else { return nil }
        return URL(string: "magnet:?xt=urn:btih:\(hash)")
    }

    /// Add a magnet URI to the LibTorrent session.
    /// The torrent handle is returned immediately; files become available once
    /// metadata is fetched from DHT/peers (triggers didReceiveUpdateForTorrent).
    private func addMagnetToSession(_ magnetURL: URL,
                                    torrentEntity: Torrents,
                                    completion: @escaping (Result<TorrentHandle, Error>) -> Void) {
        // Extract the 40-char hex info-hash from xt=urn:btih:HASH in the magnet URI.
        let hexHash: String? = URLComponents(url: magnetURL, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "xt" })?
            .value
            .flatMap { xt in
                let parts = xt.components(separatedBy: ":")
                return parts.last?.lowercased()
            }

        print("TorrentService: addMagnet hex=\(hexHash ?? "unknown") url=\(magnetURL.absoluteString.prefix(80))")

        DispatchQueue.main.async {
            // Persist the hash early so HandleTorrentInControllerDidUpdate can match updates.
            if let hex = hexHash {
                torrentEntity.torrentHashString = hex
                try? CoreDataService.sharedCoreDataService.mainQueueContext.save()
            }

            // Return existing handle if already active.
            if let hex = hexHash, let existing = self.handles[hex] {
                print("TorrentService: magnet already in session, reusing handle \(hex)")
                self.cleanupOtherTorrentsIfNeeded(keepingHash: hex)
                existing.forceReannounce()   // re-announce so we pick up fresh peers
                completion(.success(existing))
                return
            }

            // Add to session. Returns a handle immediately (snapshot.files is empty until
            // metadata arrives from DHT/peers and didReceiveUpdateForTorrent fires).
            // session.addTorrent() takes id<Downloadable> — use MagnetURI wrapper, not raw URL.
            guard let magnetURI = MagnetURI(with: magnetURL) else {
                completion(.failure(NSError(domain: "TorrentService", code: 4,
                    userInfo: [NSLocalizedDescriptionKey: "Invalid magnet URI: \(magnetURL.absoluteString.prefix(120))"])))
                return
            }
            if let handle = self.session.addTorrent(magnetURI) {
                let hex = handle.infoHashes.best.hex
                print("TorrentService: addTorrent(magnet) ok, hex=\(hex)")
                self.handles[hex] = handle
                self.cleanupOtherTorrentsIfNeeded(keepingHash: hex)
                if hexHash == nil {
                    torrentEntity.torrentHashString = hex
                    try? CoreDataService.sharedCoreDataService.mainQueueContext.save()
                }
                // Force-reannounce immediately so trackers are contacted right away
                // instead of waiting for libtorrent's default announce interval.
                handle.forceReannounce()
                completion(.success(handle))
                return
            }

            // Duplicate — libtorrent already has this magnet; find the existing handle.
            if let hex = hexHash,
               let existing = self.session.torrents.first(where: { $0.infoHashes.best.hex == hex }) {
                print("TorrentService: magnet duplicate, found in session.torrents \(hex)")
                self.handles[hex] = existing
                self.cleanupOtherTorrentsIfNeeded(keepingHash: hex)
                existing.forceReannounce()
                completion(.success(existing))
                return
            }

            completion(.failure(NSError(domain: "TorrentService", code: 4,
                userInfo: [NSLocalizedDescriptionKey:
                    "Could not add magnet link to the download session.\n" +
                    "Magnet: \(magnetURL.absoluteString.prefix(120))"])))
        }
    }

    /// Fallback: download the .torrent binary and add it to the session.
    /// Used for entries in CoreData that pre-date the magnet URI feature.
    private func downloadTorrentFile(from url: URL,
                                     torrentEntity: Torrents,
                                     completion: @escaping (Result<TorrentHandle, Error>) -> Void) {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent")
        request.setValue("application/x-bittorrent, */*;q=0.8", forHTTPHeaderField: "Accept")
        print("TorrentService: downloading .torrent from \(url)")

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            let httpStatus = (response as? HTTPURLResponse)?.statusCode ?? 0
            if let error = error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            guard let data = data, !data.isEmpty else {
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "TorrentService", code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "Empty response (HTTP \(httpStatus)) from \(url)"])))
                }
                return
            }
            let preview = String(bytes: data.prefix(120), encoding: .utf8) ?? "<binary \(data.count) bytes>"
            print("TorrentService: \(data.count) bytes (HTTP \(httpStatus)): \(preview.prefix(120))")

            guard let torrentFile = TorrentFile(with: data) else {
                let snippet = (String(bytes: data.prefix(200), encoding: .utf8) ?? "<binary>").prefix(200)
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "TorrentService", code: 2,
                        userInfo: [NSLocalizedDescriptionKey:
                            "Server returned HTML/invalid data instead of a .torrent file (HTTP \(httpStatus)).\n" +
                            "Response:\n\(snippet)\n\nTip: re-search the anime to get a fresh magnet link."])))
                }
                return
            }

            let hexHash = torrentFile.infoHashes.best.hex
            print("TorrentService: parsed '\(torrentFile.name)' hash=\(hexHash)")

            DispatchQueue.main.async {
                torrentEntity.torrentHashString = hexHash
                try? CoreDataService.sharedCoreDataService.mainQueueContext.save()

                if let existing = self.handles[hexHash] {
                    self.cleanupOtherTorrentsIfNeeded(keepingHash: hexHash)
                    completion(.success(existing))
                    return
                }
                if let handle = self.session.addTorrent(torrentFile) {
                    self.handles[hexHash] = handle
                    self.cleanupOtherTorrentsIfNeeded(keepingHash: hexHash)
                    handle.forceReannounce()
                    completion(.success(handle))
                    return
                }
                if let existing = self.session.torrents.first(where: { $0.infoHashes.best.hex == hexHash }) {
                    self.handles[hexHash] = existing
                    self.cleanupOtherTorrentsIfNeeded(keepingHash: hexHash)
                    completion(.success(existing))
                    return
                }
                completion(.failure(NSError(domain: "TorrentService", code: 3,
                    userInfo: [NSLocalizedDescriptionKey: "Could not add torrent to session (hash: \(hexHash))"])))
            }
        }.resume()
    }

    func ClearTempTorrents() {
        if self.insertIndexForTempEntries > 0 {
            let context = CoreDataService.sharedCoreDataService.mainQueueContext
            let request = NSFetchRequest<NSFetchRequestResult>(entityName: Torrents.entityName)
            request.predicate = NSPredicate(format: "torrentFlagTemp == YES")
            context.deleteAllData(request)
            self.insertIndexForTempEntries = 0
        }
    }
}

