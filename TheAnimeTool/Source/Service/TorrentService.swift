//
//  TorrentService.swift
//  FinalProject
//
//  Created by Tieria C.Monk on 8/13/16.
//

import Foundation
import CoreData

public class TorrentService: NSObject {
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

    //singleton object
    static let sharedTorrentService = TorrentService()
    //notifications
    static let LocalTorrentsWillUpdateNotification = "LocalTorrentsWillUpdateNotification"
    static let LocalTorrentsDidUpdateNotification = "LocalTorrentsDidUpdateNotification"
    static let TorrentInControllerDidUpdateNotification = "TorrentInControllerDidUpdateNotification"
    static let TorrentInControllerUpdateFailedNotification = "TorrentInControllerUpdateFailedNotification"

    //torrent engine
    let torrentController: Controller

    var insertIndexForTempEntries = 0

    override init() {
        torrentController = Controller.sharedController() as! Controller
        torrentController.fixDocumentsDirectory()
        torrentController.transmissionInitialize()
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(HandleNewTorrentAdded), name: NSNotification.Name(rawValue: NotificationNewTorrentAdded), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(HandleAddTorrentFailed), name: NSNotification.Name(rawValue: NotificationAddNewTorrentFailed), object: nil)
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

    func UpdateTorrentEntityInController(_ torrentEntity: Torrents) {
        let torrentController = TorrentService.sharedTorrentService.torrentController

        if let hashString = torrentEntity.torrentHashString {
            if let torrent = torrentController.torrent(fromHash: hashString) as? Torrent {
                NotificationCenter.default.post(name: NSNotification.Name(TorrentService.TorrentInControllerDidUpdateNotification), object: self, userInfo: ["torrent": torrent])
                return
            } else {
                torrentEntity.torrentHashString = nil
                do { try CoreDataService.sharedCoreDataService.mainQueueContext.save() } catch { print("Error reset hash failed") }
            }
        }

        guard let url = torrentEntity.torrentDownloadURL else { return }
        torrentController.addTorrent(fromURL: url)
    }

    @objc private func HandleNewTorrentAdded(_ notification: Notification) {
        guard let torrent = notification.userInfo?["torrent"] as? Torrent else { print("Error no torrent in userinfo"); return }
        NotificationCenter.default.post(name: NSNotification.Name(TorrentService.TorrentInControllerDidUpdateNotification), object: self, userInfo: ["torrent": torrent])
    }

    @objc private func HandleAddTorrentFailed(_ notification: Notification) {
        guard let error = notification.userInfo?["error"] as? NSError else { print("Error no error in userinfo"); return }
        NotificationCenter.default.post(name: NSNotification.Name(TorrentService.TorrentInControllerUpdateFailedNotification), object: self, userInfo: ["error": error])
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
