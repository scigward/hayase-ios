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
    /// Calls `completion` on the main thread with the TorrentHandle AND TorrentFile (always
    /// has its file list populated from the parsed .torrent data) or an error.
    func UpdateTorrentEntityInController(_ torrentEntity: Torrents,
                                        completion: @escaping (Result<(handle: TorrentHandle, torrentFile: TorrentFile), Error>) -> Void) {
        guard let urlString = torrentEntity.torrentDownloadURL,
              let url = URL(string: urlString) else {
            DispatchQueue.main.async {
                completion(.failure(NSError(domain: "TorrentService", code: 0,
                    userInfo: [NSLocalizedDescriptionKey: "Invalid or missing download URL"])))
            }
            return
        }

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.setValue("Mozilla/5.0 TheAnimeTool/1.0", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }

            if let error = error {
                print("TorrentService: download error: \(error)")
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }

            guard let data = data, !data.isEmpty else {
                print("TorrentService: empty response from \(urlString)")
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "TorrentService", code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "Empty response from server"])))
                }
                return
            }

            guard let torrentFile = TorrentFile(with: data) else {
                let httpStatus = (response as? HTTPURLResponse)?.statusCode ?? 0
                print("TorrentService: invalid torrent data (HTTP \(httpStatus), \(data.count) bytes)")
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "TorrentService", code: 2,
                        userInfo: [NSLocalizedDescriptionKey: "Server returned invalid torrent data (HTTP \(httpStatus))"])))
                }
                return
            }

            let hexHash = torrentFile.infoHashes.best.hex
            print("TorrentService: torrent parsed, hex=\(hexHash)")

            DispatchQueue.main.async {
                // Persist the hash
                torrentEntity.torrentHashString = hexHash
                try? CoreDataService.sharedCoreDataService.mainQueueContext.save()

                // 1. Already tracked in our handles dict?
                // handles is maintained by didAddTorrent/didRemoveTorrentWithHash, so any
                // entry present here belongs to an active torrent in the session.
                if let existingHandle = self.handles[hexHash] {
                    print("TorrentService: already tracked, using cached handle")
                    completion(.success((handle: existingHandle, torrentFile: torrentFile)))
                    return
                }

                // 2. Add to session — addTorrent() returns the TorrentHandle directly on success.
                //    notifyDelegatesWithAdd is also called synchronously inside addTorrent (which
                //    triggers didAddTorrent → synchronous updateSnapshot). We also store the return
                //    value directly for immediate use.
                if let newHandle = self.session.addTorrent(torrentFile) {
                    print("TorrentService: addTorrent succeeded")
                    self.handles[hexHash] = newHandle
                    completion(.success((handle: newHandle, torrentFile: torrentFile)))
                    return
                }

                // 3. addTorrent returned nil — the torrent already exists in the libtorrent session
                //    (duplicate, throws std::exception internally). Search session.torrents directly.
                print("TorrentService: addTorrent returned nil (duplicate), searching session.torrents")
                if let restoredHandle = self.session.torrents.first(where: {
                    $0.infoHashes.best.hex == hexHash
                }) {
                    print("TorrentService: found restored handle in session.torrents")
                    self.handles[hexHash] = restoredHandle
                    completion(.success((handle: restoredHandle, torrentFile: torrentFile)))
                    return
                }

                // 4. Truly not found — report failure
                print("TorrentService: handle not found in session")
                completion(.failure(NSError(domain: "TorrentService", code: 3,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to add torrent to session"])))
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

