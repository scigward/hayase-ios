//
//  TorrentService.swift
//  FinalProject
//
//  Created by Tieria C.Monk on 8/13/16.
//

import Foundation
import CoreData
import NDHpple

public class TorrentService: NSObject {
    enum TorrentError: Error {
        case invalidId
        case invalidPageData
        case invalidTorrentCount
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

    // XPath queries for nyaa.si table structure
    let TorrentEntriesXpath = "//table[contains(@class,'torrent-list')]//tbody/tr"
    let TorrentNameXpath = "//table[contains(@class,'torrent-list')]//tbody/tr/td[2]/a[1]"
    let TorrentSXpath = "//table[contains(@class,'torrent-list')]//tbody/tr/td[6]"
    let TorrentLXpath = "//table[contains(@class,'torrent-list')]//tbody/tr/td[7]"
    let TorrentDXpath = "//table[contains(@class,'torrent-list')]//tbody/tr/td[8]"
    let TorrentSizeXpath = "//table[contains(@class,'torrent-list')]//tbody/tr/td[4]"
    let TorrentDownloadXpath = "//table[contains(@class,'torrent-list')]//tbody/tr/td[3]/a[contains(@href,'.torrent')]"

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
        let urlString = "https://nyaa.si/?f=0&c=1_0&q=\(encodedSearch)&s=\(sortParam)&o=\(orderParam)&p=\(page)"
        guard let url = URL(string: urlString) else { return }

        URLSession.shared.dataTask(with: url) { data, _, error in
            if let error = error {
                print("Error getting torrent data: \(error)")
                return
            }
            guard let data = data else { return }
            do {
                try self.UpdateLocalTorrents(data, isTemp: true)
            } catch let error {
                print("Error updating local torrents: \(error)")
            }
        }.resume()
    }

    private func UpdateLocalTorrents(_ data: Data, isTemp: Bool) throws {
        guard let html = String(data: data, encoding: .utf8) else { return }
        let doc = NDHpple(HTMLData: html)
        let torrentNames = doc.searchWithXPathQuery(self.TorrentNameXpath).map { $0.firstChild?.content }
        let torrentS = doc.searchWithXPathQuery(self.TorrentSXpath).map { Int($0.firstChild?.content ?? "0") ?? 0 }
        let torrentL = doc.searchWithXPathQuery(self.TorrentLXpath).map { Int($0.firstChild?.content ?? "0") ?? 0 }
        let torrentD = doc.searchWithXPathQuery(self.TorrentDXpath).map { Int($0.firstChild?.content ?? "0") ?? 0 }
        let torrentSize = doc.searchWithXPathQuery(self.TorrentSizeXpath).map { item -> Float in
            let sizeStr = item.firstChild?.content ?? "0 MiB"
            let parts = sizeStr.components(separatedBy: " ")
            return Float(parts.first ?? "0") ?? 0
        }
        let torrentURL = doc.searchWithXPathQuery(self.TorrentDownloadXpath).map { item -> String? in
            guard let path = item.attributes["href"] as? String else { return nil }
            if path.hasPrefix("http") { return path }
            return "https://nyaa.si\(path)"
        }
        let torrentIds = torrentURL.map { item -> Int? in
            guard let url = item else { return nil }
            // Extract numeric ID from URL path like /download/1234567.torrent
            guard let range = url.range(of: #"/download/(\d+)\.torrent"#, options: .regularExpression) else { return nil }
            let match = String(url[range])
            let digits = match.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
            return Int(digits)
        }

        NotificationCenter.default.post(name: NSNotification.Name(TorrentService.LocalTorrentsWillUpdateNotification), object: self)

        let context = CoreDataService.sharedCoreDataService.mainQueueContext
        let torrentCount = torrentNames.count
        for i in 0..<torrentCount {
            let newTorrent = NSEntityDescription.insertNewObject(forEntityName: Torrents.entityName, into: context) as! Torrents
            newTorrent.torrentName = torrentNames[i]
            newTorrent.torrentNyaaId = torrentIds[i].map { NSNumber(value: $0) }
            newTorrent.torrentSeeders = NSNumber(value: torrentS[i])
            newTorrent.torrentLeechers = NSNumber(value: torrentL[i])
            newTorrent.torrentDownloads = NSNumber(value: torrentD[i])
            newTorrent.torrentSize = NSNumber(value: torrentSize[i])
            newTorrent.torrentDownloadURL = torrentURL[i]
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
            if let torrent = torrentController.torrentFromHash(hashString) as? Torrent {
                NotificationCenter.default.post(name: NSNotification.Name(TorrentService.TorrentInControllerDidUpdateNotification), object: self, userInfo: ["torrent": torrent])
                return
            } else {
                torrentEntity.torrentHashString = nil
                do { try CoreDataService.sharedCoreDataService.mainQueueContext.save() } catch { print("Error reset hash failed") }
            }
        }

        guard let url = torrentEntity.torrentDownloadURL else { return }
        torrentController.addTorrentFromURL(url)
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
