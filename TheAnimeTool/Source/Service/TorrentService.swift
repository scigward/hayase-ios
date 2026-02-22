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
    enum SortBy: Int {
        case Date = 1
        case Seeders
        case Leechers
        case Downloads
        case Size
        case Name
    }

    // MARK: - Singleton & notifications
    static let sharedTorrentService = TorrentService()
    static let LocalTorrentsWillUpdateNotification       = "LocalTorrentsWillUpdateNotification"
    static let LocalTorrentsDidUpdateNotification        = "LocalTorrentsDidUpdateNotification"
    static let TorrentInControllerDidUpdateNotification  = "TorrentInControllerDidUpdateNotification"
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
        settings.outgoingInterfaces = ""
        settings.listenInterfaces   = "0.0.0.0:0,[::]:0"
        settings.isDhtEnabled  = true
        settings.isLsdEnabled  = true
        settings.isUtpEnabled  = true
        settings.isUpnpEnabled = true
        settings.isNatEnabled  = true

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

    // MARK: - RSS parser for nyaa.si

    // Nyaa trackers included in the panel-footer magnet link on every torrent page.
    static let nyaaTrackers = [
        "http://nyaa.tracker.wf:7777/announce",
        "udp://open.stealth.si:80/announce",
        "udp://tracker.opentrackr.org:1337/announce",
        "udp://exodus.desync.com:6969/announce",
        "udp://tracker.torrent.eu.org:451/announce",
    ]

    private class NyaaRSSParser: NSObject, XMLParserDelegate {
        struct TorrentItem {
            var name: String = ""
            var downloadURL: String?   // kept for reference; overwritten with magnet URI when infoHash present
            var infoHash: String = ""  // from <nyaa:infoHash>; used to build the magnet URI
            var seeders: Int = 0
            var leechers: Int = 0
            var downloads: Int = 0
            var sizeMB: Float = 0
            var nyaaId: Int?
        }

        var items: [TorrentItem] = []
        private var currentItem: TorrentItem?
        private var currentText = ""
        private var inItem = false

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
            currentText = ""
            if elementName == "item" {
                currentItem = TorrentItem()
                inItem = true
            } else if elementName == "enclosure", inItem, let url = attributeDict["url"] {
                currentItem?.downloadURL = url
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            currentText += string
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
            let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard inItem else { return }
            switch elementName {
            case "title":
                currentItem?.name = text
            case "nyaa:seeders":
                currentItem?.seeders = Int(text) ?? 0
            case "nyaa:leechers":
                currentItem?.leechers = Int(text) ?? 0
            case "nyaa:downloads":
                currentItem?.downloads = Int(text) ?? 0
            case "nyaa:infoHash":
                currentItem?.infoHash = text.lowercased()
            case "nyaa:size":
                let parts = text.components(separatedBy: " ")
                if let val = Float(parts.first ?? "0") {
                    let unit = (parts.last ?? "MiB").lowercased()
                    if unit.hasPrefix("gib") {
                        currentItem?.sizeMB = val * 1024
                    } else if unit.hasPrefix("tib") {
                        currentItem?.sizeMB = val * 1024 * 1024
                    } else {
                        currentItem?.sizeMB = val
                    }
                }
            case "item":
                if var item = currentItem {
                    // Extract nyaaId from enclosure URL (used as .torrent download fallback).
                    if let url = item.downloadURL,
                       let range = url.range(of: #"/download/(\d+)\.torrent"#, options: .regularExpression) {
                        let digits = String(url[range]).components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
                        item.nyaaId = Int(digits)
                    }
                    // Build magnet URI from infoHash + nyaa trackers.
                    // This bypasses any HTTP/Cloudflare issues with the /download/*.torrent endpoint.
                    if !item.infoHash.isEmpty {
                        let encodedName = item.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                        if encodedName.isEmpty {
                            print("NyaaRSSParser: percent-encoding failed for '\(item.name)'; skipping magnet dn param")
                        }
                        let trParams = nyaaTrackers.map {
                            "&tr=" + ($0.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0)
                        }.joined()
                        item.downloadURL = "magnet:?xt=urn:btih:\(item.infoHash)&dn=\(encodedName)\(trParams)"
                    }
                    items.append(item)
                }
                currentItem = nil
                inItem = false
            default:
                break
            }
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

    func UpdateTempTorrentsWith(_ searchStr: String, page: Int = 1, sortBy: SortBy = .Date, isDesc: Bool = true) {
        self.ClearTempTorrents()
        let sortParam: String
        switch sortBy {
        case .Seeders:   sortParam = "seeders"
        case .Leechers:  sortParam = "leechers"
        case .Downloads: sortParam = "downloads"
        case .Size:      sortParam = "size"
        case .Name:      sortParam = "filename"
        default:         sortParam = "id"
        }
        let orderParam = isDesc ? "desc" : "asc"
        let encodedSearch = searchStr.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? searchStr
        let urlString = "https://nyaa.si/?page=rss&q=\(encodedSearch)&c=1_0&f=0&s=\(sortParam)&o=\(orderParam)"
        guard let url = URL(string: urlString) else { return }

        URLSession.shared.dataTask(with: url) { data, _, error in
            if let error = error {
                print("Error getting torrent data: \(error)")
                return
            }
            guard let data = data else { return }
            let rssParser = NyaaRSSParser()
            let xmlParser = XMLParser(data: data)
            xmlParser.delegate = rssParser
            xmlParser.parse()
            DispatchQueue.main.async {
                do {
                    try self.UpdateLocalTorrents(rssParser.items, isTemp: true)
                } catch let error {
                    print("Error updating local torrents: \(error)")
                }
            }
        }.resume()
    }

    private func UpdateLocalTorrents(_ items: [NyaaRSSParser.TorrentItem], isTemp: Bool) throws {
        NotificationCenter.default.post(name: NSNotification.Name(TorrentService.LocalTorrentsWillUpdateNotification), object: self)

        let context = CoreDataService.sharedCoreDataService.mainQueueContext
        for item in items {
            let newTorrent = NSEntityDescription.insertNewObject(forEntityName: Torrents.entityName, into: context) as! Torrents
            newTorrent.torrentName = item.name
            newTorrent.torrentNyaaId = item.nyaaId.map { NSNumber(value: $0) }
            newTorrent.torrentSeeders = NSNumber(value: item.seeders)
            newTorrent.torrentLeechers = NSNumber(value: item.leechers)
            newTorrent.torrentDownloads = NSNumber(value: item.downloads)
            newTorrent.torrentSize = NSNumber(value: item.sizeMB)
            newTorrent.torrentDownloadURL = item.downloadURL
            newTorrent.torrentFlagTemp = NSNumber(value: isTemp)
            newTorrent.torrentOrder = NSNumber(value: self.insertIndexForTempEntries)
            self.insertIndexForTempEntries += 1
        }

        do {
            try context.save()
        } catch {
            print("Error saving new torrent information")
            throw TorrentError.errorSavingCoreData
        }

        NotificationCenter.default.post(name: NSNotification.Name(TorrentService.LocalTorrentsDidUpdateNotification), object: self)
    }

    /// Add the torrent (from magnet URI or .torrent download) to the LibTorrent session.
    /// Prefers the magnet URI stored in torrentDownloadURL (built from nyaa:infoHash in RSS)
    /// which requires no HTTP download and bypasses all Cloudflare/rate-limit issues.
    /// Falls back to downloading the .torrent binary from nyaa.si when no infoHash was available.
    /// Calls `completion` on the main thread with a TorrentHandle or an Error.
    func UpdateTorrentEntityInController(_ torrentEntity: Torrents,
                                        completion: @escaping (Result<TorrentHandle, Error>) -> Void) {
        guard let urlString = torrentEntity.torrentDownloadURL,
              let url = URL(string: urlString) else {
            // No URL at all — last resort: nyaa ID direct download
            if let id = torrentEntity.torrentNyaaId?.intValue, id > 0,
               let fallbackURL = URL(string: "https://nyaa.si/download/\(id).torrent") {
                downloadTorrentFile(from: fallbackURL, torrentEntity: torrentEntity, completion: completion)
            } else {
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "TorrentService", code: 0,
                        userInfo: [NSLocalizedDescriptionKey:
                            "No download URL or info hash available for this torrent.\n" +
                            "Try searching for the torrent again."])))
                }
            }
            return
        }

        if url.scheme == "magnet" {
            addMagnetToSession(url, torrentEntity: torrentEntity, completion: completion)
        } else {
            downloadTorrentFile(from: url, torrentEntity: torrentEntity, completion: completion)
        }
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
                completion(.success(handle))
                return
            }

            // Duplicate — libtorrent already has this magnet; find the existing handle.
            if let hex = hexHash,
               let existing = self.session.torrents.first(where: { $0.infoHashes.best.hex == hex }) {
                print("TorrentService: magnet duplicate, found in session.torrents \(hex)")
                self.handles[hex] = existing
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
        request.setValue("https://nyaa.si", forHTTPHeaderField: "Referer")
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

    static func UtilMakeShortSearchString(_ string: String) -> String {
        let cleanStr = string.replacingOccurrences(of: "\\s*\\W\\s*", with: " ", options: .regularExpression, range: nil)
        let splittedStr = cleanStr.components(separatedBy: " ")
        let shortStr = String(format: "%@%@", splittedStr[0], splittedStr.count > 1 ? " \(splittedStr[1])" : "")
        return shortStr
    }
}

