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

    private class NyaaRSSParser: NSObject, XMLParserDelegate {
        struct TorrentItem {
            var name: String = ""
            var downloadURL: String?
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
                    if let url = item.downloadURL,
                       let range = url.range(of: #"/download/(\d+)\.torrent"#, options: .regularExpression) {
                        let digits = String(url[range]).components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
                        item.nyaaId = Int(digits)
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

    /// Download the .torrent file from nyaa.si and add it to the LibTorrent session.
    /// Resolves the download URL from torrentDownloadURL, falling back to the nyaa ID.
    /// Calls `completion` on the main thread with (TorrentHandle, TorrentFile) or an Error.
    func UpdateTorrentEntityInController(_ torrentEntity: Torrents,
                                        completion: @escaping (Result<(handle: TorrentHandle, torrentFile: TorrentFile), Error>) -> Void) {
        // Prefer the RSS-provided enclosure URL; fall back to nyaa ID-based URL.
        let downloadURL: URL? = {
            if let s = torrentEntity.torrentDownloadURL, let u = URL(string: s) { return u }
            if let id = torrentEntity.torrentNyaaId?.intValue, id > 0 {
                return URL(string: "https://nyaa.si/download/\(id).torrent")
            }
            return nil
        }()

        guard let url = downloadURL else {
            DispatchQueue.main.async {
                completion(.failure(NSError(domain: "TorrentService", code: 0,
                    userInfo: [NSLocalizedDescriptionKey:
                        "No download URL available.\nNo torrentDownloadURL and no nyaaId stored for this torrent.\nTry searching for the torrent again."])))
            }
            return
        }

        downloadTorrentData(from: url, torrentEntity: torrentEntity, completion: completion)
    }

    /// Internal: fetch the .torrent binary from `url` and add it to the LibTorrent session.
    private func downloadTorrentData(from url: URL,
                                     torrentEntity: Torrents,
                                     completion: @escaping (Result<(handle: TorrentHandle, torrentFile: TorrentFile), Error>) -> Void) {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        // Full iOS Safari User-Agent — nyaa.si (Cloudflare) may block weaker UA strings.
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent")
        request.setValue("application/x-bittorrent, application/octet-stream, */*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue("https://nyaa.si", forHTTPHeaderField: "Referer")

        print("TorrentService: downloading from \(url)")

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }

            let httpStatus = (response as? HTTPURLResponse)?.statusCode ?? 0

            if let error = error {
                print("TorrentService: network error (HTTP \(httpStatus)): \(error)")
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }

            guard let data = data, !data.isEmpty else {
                print("TorrentService: empty response (HTTP \(httpStatus)) from \(url)")
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "TorrentService", code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "Server returned an empty response (HTTP \(httpStatus)).\nURL: \(url)"])))
                }
                return
            }

            // Log the first bytes so we can diagnose HTML vs binary torrent responses.
            let preview = String(bytes: data.prefix(100), encoding: .utf8) ?? "<binary \(data.count) bytes>"
            print("TorrentService: \(data.count) bytes (HTTP \(httpStatus)): \(preview.prefix(100))")

            guard let torrentFile = TorrentFile(with: data) else {
                // The server returned something, but it's not a valid .torrent file.
                // Likely Cloudflare HTML or a redirect page.
                let snippet = String(bytes: data.prefix(100), encoding: .utf8) ?? "<binary>"
                print("TorrentService: invalid torrent data (HTTP \(httpStatus)): \(snippet)")
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "TorrentService", code: 2,
                        userInfo: [NSLocalizedDescriptionKey:
                            "Server did not return a valid .torrent file (HTTP \(httpStatus)).\n" +
                            "Server response:\n\(snippet)"])))
                }
                return
            }

            let hexHash = torrentFile.infoHashes.best.hex
            print("TorrentService: parsed '\(torrentFile.name)' hash=\(hexHash) files=\(torrentFile.files.count)")

            DispatchQueue.main.async {
                torrentEntity.torrentHashString = hexHash
                try? CoreDataService.sharedCoreDataService.mainQueueContext.save()

                // 1. Already tracked in our active handles dict?
                if let existingHandle = self.handles[hexHash] {
                    print("TorrentService: reusing active handle for \(hexHash)")
                    completion(.success((handle: existingHandle, torrentFile: torrentFile)))
                    return
                }

                // 2. Add to session. addTorrent() synchronously calls didAddTorrent (which
                //    stores the handle in self.handles) and returns the new TorrentHandle.
                if let newHandle = self.session.addTorrent(torrentFile) {
                    print("TorrentService: addTorrent() succeeded, files=\(torrentFile.files.count)")
                    self.handles[hexHash] = newHandle
                    completion(.success((handle: newHandle, torrentFile: torrentFile)))
                    return
                }

                // 3. addTorrent() returned nil — torrent already exists in the libtorrent session
                //    (duplicate add; C++ throws std::exception internally → nil return).
                //    Find the existing handle by hex string comparison.
                print("TorrentService: addTorrent() returned nil (duplicate), searching session")
                if let restoredHandle = self.session.torrents.first(where: {
                    $0.infoHashes.best.hex == hexHash
                }) {
                    print("TorrentService: found existing handle in session.torrents")
                    self.handles[hexHash] = restoredHandle
                    completion(.success((handle: restoredHandle, torrentFile: torrentFile)))
                    return
                }

                // 4. Genuinely not found — report failure.
                print("TorrentService: handle not found after add attempt")
                completion(.failure(NSError(domain: "TorrentService", code: 3,
                    userInfo: [NSLocalizedDescriptionKey:
                        "Torrent file parsed successfully but could not be added to the download session.\n" +
                        "Hash: \(hexHash)"])))
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

