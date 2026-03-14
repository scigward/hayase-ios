//
//  TorrentService.swift
//  TheAnimeTool
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

    // MARK: - LibTorrent session + handle tracking
    let session: Session

    /// Hex-string keyed dict of active handles.
    /// Avoids TorrentHashes NSDictionary key-equality issues (TorrentHashes does not
    /// override isEqual:/hash, so NSDictionary lookups use pointer identity).
    /// All reads/writes happen on the main thread.
    private(set) var handles: [String: TorrentHandle] = [:]

    var insertIndexForTempEntries = 0

    override init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let downloadsURL  = docs.appendingPathComponent("downloads")
        let torrentsURL   = docs.appendingPathComponent("torrents")
        let fastResumeURL = docs.appendingPathComponent("fastResume")

        [downloadsURL, torrentsURL, fastResumeURL].forEach {
            try? FileManager.default.createDirectory(at: $0, withIntermediateDirectories: true)
        }

        let settings = Session.Settings()
        settings.agentName        = "TheAnimeTool"
        // Torrent activity limits — default is 0 (no active torrents!) so we must set positive values.
        // With active_limit=0 libtorrent queues every torrent and never starts connecting.
        settings.maxActiveTorrents      = 4    // iTorrent default
        settings.maxDownloadingTorrents = 4
        settings.maxUploadingTorrents   = 4
        // Port settings — use a specific port so UPnP/NAT-PMP can forward it reliably.
        // Omit IPv6 wildcard ([::]) which can fail in sandboxed environments (LiveContainer).
        settings.port             = 6881
        settings.portBindRetries  = 10         // retry on conflict; iTorrent default
        settings.listenInterfaces = "0.0.0.0:6881"
        settings.outgoingInterfaces = ""       // OS default routing (matches all interfaces)
        // Protocol features
        settings.isDhtEnabled  = true
        settings.isLsdEnabled  = true
        settings.isUtpEnabled  = true
        settings.isUpnpEnabled = true
        settings.isNatEnabled  = true
        // Disable HTTPS tracker cert validation — we don't bundle cacert.pem.
        // Our nyaa trackers are HTTP/UDP so this has no effect on them; it just avoids
        // a silent SSL failure if any tracker ever redirects to HTTPS.
        settings.validateHttpsTrackers = false

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

    // MARK: - Public trackers
    // Well-known public BitTorrent announce endpoints. Appended to every torrent so peer
    // discovery works even when the magnet URI / .torrent file includes no tracker params.
    // Includes anime-specific trackers (nyaa, acgnxtracker, anidex, anirena) that are
    // critical for finding peers on low-seeder anime torrents — these are the same
    // trackers used by Hayase's torrent-client for reliable streaming.
    static let publicTrackers = [
        // General public trackers
        "udp://open.stealth.si:80/announce",
        "udp://tracker.opentrackr.org:1337/announce",
        "udp://exodus.desync.com:6969/announce",
        "udp://tracker.torrent.eu.org:451/announce",
        "udp://tracker.openbittorrent.com:6969/announce",
        // Anime-specific trackers — significantly improve peer discovery for anime releases
        "http://nyaa.tracker.wf:7777/announce",
        "http://open.acgnxtracker.com:80/announce",
        "http://anidex.moe:6969/announce",
        "http://tracker.anirena.com:80/announce",
    ]

    /// Append public fallback trackers to a handle so every torrent benefits from
    /// well-known announce endpoints even when the magnet URI / .torrent file
    /// doesn't include tracker parameters. libtorrent de-duplicates trackers
    /// internally, so calling this is safe even if the extension already provided
    /// the same URLs via `&tr=` parameters.
    private func addPublicTrackers(to handle: TorrentHandle) {
        for url in TorrentService.publicTrackers {
            handle.addTracker(url)
        }
    }

    // MARK: - Public API

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

    /// Build a `magnet:?xt=urn:btih:HASH&tr=...` URL from a hex info-hash,
    /// appending public trackers for better peer discovery.
    private func magnetURLFromHash(_ hash: String?) -> URL? {
        guard let hash, !hash.isEmpty else { return nil }
        var components = "magnet:?xt=urn:btih:\(hash)"
        for tracker in TorrentService.publicTrackers {
            if let encoded = tracker.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
                components += "&tr=\(encoded)"
            }
        }
        return URL(string: components)
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
                if hexHash == nil {
                    torrentEntity.torrentHashString = hex
                    try? CoreDataService.sharedCoreDataService.mainQueueContext.save()
                }
                // Append well-known public trackers so peer discovery doesn't depend
                // solely on the trackers the extension included (if any).
                self.addPublicTrackers(to: handle)
                // Force-reannounce immediately so trackers are contacted right away
                // instead of waiting for libtorrent's default announce interval.
                // MagnetURI.configureAfterAdded: is a no-op, so we must do this ourselves.
                handle.forceReannounce()
                completion(.success(handle))
                return
            }

            // Duplicate — libtorrent already has this magnet; find the existing handle.
            if let hex = hexHash,
               let existing = self.session.torrents.first(where: { $0.infoHashes.best.hex == hex }) {
                print("TorrentService: magnet duplicate, found in session.torrents \(hex)")
                self.handles[hex] = existing
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
                    completion(.success(existing))
                    return
                }
                if let handle = self.session.addTorrent(torrentFile) {
                    self.handles[hexHash] = handle
                    // Append well-known public trackers as fallback for peer discovery.
                    self.addPublicTrackers(to: handle)
                    handle.forceReannounce()
                    completion(.success(handle))
                    return
                }
                if let existing = self.session.torrents.first(where: { $0.infoHashes.best.hex == hexHash }) {
                    self.handles[hexHash] = existing
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

