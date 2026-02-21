//
//  VideoService.swift
//  FinalProject
//
//  Created by Tieria C.Monk on 8/17/16.
//

import Foundation
import CoreData

public class VideoService: NSObject {
    enum VideoError: Error {
        case invalidIndex
    }
    enum FileCheckState: Int {
        case On = 1
        case Off = 0
        case Mixed = -1
    }
    static let LocalVideosDidUpdateNotification = "LocalVideosDidUpdateNotification"
    static let LocalVideosWillUpdateNotification = "LocalVideosWillUpdateNotification"

    let torrentEntity: Torrents
    var torrent: Torrent? = nil

    init(torrentEntity: Torrents) {
        self.torrentEntity = torrentEntity
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(HandleTorrentInControllerDidUpdate), name: NSNotification.Name(TorrentService.TorrentInControllerDidUpdateNotification), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(HandleTorrentInControllerUpdateFailed), name: NSNotification.Name(TorrentService.TorrentInControllerUpdateFailedNotification), object: nil)
    }

    func UpdateLocalVideo() {
        TorrentService.sharedTorrentService.UpdateTorrentEntityInController(torrentEntity)
    }

    func ClearCurrentTorrentEntityAndVideos() {
        let context = CoreDataService.sharedCoreDataService.mainQueueContext
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: Videos.entityName)
        let videoCount = (try? context.count(for: request)) ?? 0
        if videoCount > 0 {
            context.deleteAllData(request)
        }

        if let hashString = self.torrentEntity.torrentHashString {
            if self.torrentEntity.torrentFlagTemp?.boolValue == true {
                TorrentService.sharedTorrentService.torrentController.removeTorrentsWithHashs([hashString], trashData: true)
                torrentEntity.torrentHashString = nil
                do { try context.save() } catch let error { print("Error clearing torrent data: \(error)") }
            }
        }
    }

    func UpdateLocalVideosWithTorrent(_ torrent: Torrent) {
        let context = CoreDataService.sharedCoreDataService.mainQueueContext
        self.torrentEntity.torrentHashString = torrent.hashString()
        self.torrent = torrent

        NotificationCenter.default.post(name: NSNotification.Name(VideoService.LocalVideosWillUpdateNotification), object: nil)
        let indexes = NSMutableIndexSet()
        let videoList = torrent.flatFileList() as! [FileListNode]
        for video in videoList {
            let newVideoEntity = NSEntityDescription.insertNewObject(forEntityName: Videos.entityName, into: context) as! Videos
            newVideoEntity.videoName = video.name()
            newVideoEntity.videoPath = video.path()
            newVideoEntity.videoSize = Float(video.size() / 1024 / 1024)
            newVideoEntity.videoIndex = NSNumber(value: Int(video.indexes().firstIndex))
            newVideoEntity.torrents = torrentEntity
            indexes.add(video.indexes() as IndexSet)
        }
        self.torrent?.setFileCheckState(FileCheckState.Off.rawValue, forIndexes: indexes)
        do { try context.save() } catch let error { print("Error updating local videos: \(error)"); return }
        NotificationCenter.default.post(name: NSNotification.Name(VideoService.LocalVideosDidUpdateNotification), object: nil)
    }

    func UpdateProgressForFileIndex(_ index: UInt) -> Float {
        self.UpdateTorrentFileInfos()
        let progress = Float(torrent?.fileProgressFromIndex(index) ?? 0)
        guard let hashString = torrent?.hashString() else { return progress }
        let context = CoreDataService.sharedCoreDataService.mainQueueContext
        let fetchRequest = NSFetchRequest<Videos>(entityName: Videos.entityName)
        fetchRequest.predicate = NSPredicate(format: "torrents.torrentHashString == %@ AND videoIndex == %d", hashString, index)
        guard let videos = try? context.fetch(fetchRequest), videos.count > 0 else { return progress }
        videos[0].videoDownloadPercent = NSNumber(value: progress)
        do { try context.save() } catch let error { print("Error saving video progress:\(error)") }
        return progress
    }

    func UpdateFilePathForFileIndex(_ index: UInt) -> String {
        self.UpdateTorrentFileInfos()
        guard let filePath = torrent?.fileLocationForFileIndex(index) else { return "" }
        guard let hashString = torrent?.hashString() else { return filePath }
        let context = CoreDataService.sharedCoreDataService.mainQueueContext
        let fetchRequest = NSFetchRequest<Videos>(entityName: Videos.entityName)
        fetchRequest.predicate = NSPredicate(format: "torrents.torrentHashString == %@ AND videoIndex == %d", hashString, index)
        guard let videos = try? context.fetch(fetchRequest), videos.count > 0 else { return filePath }
        videos[0].videoPath = filePath
        do { try context.save() } catch let error { print("Error saving video path:\(error)") }
        return filePath
    }

    func CheckIsDoNotDownloadForFileIndex(_ index: UInt) -> Bool? {
        return self.torrent?.isFileDoNotDownload(index) ?? nil
    }

    func SetDoNotDownloadForFileIndex(_ index: UInt, flag: Bool) {
        self.torrent?.setFileCheckState(Int(!flag), forIndexes: NSIndexSet(index: Int(index)))
    }

    func UpdateTorrentFileInfos() {
        torrent?.update()
        torrent?.updateFileStat()
    }

    @objc private func HandleTorrentInControllerDidUpdate(_ notification: Notification) {
        guard let torrent = notification.userInfo?["torrent"] as? Torrent else { print("Error no torrent in userinfo"); return }
        self.ClearCurrentTorrentEntityAndVideos()
        self.UpdateLocalVideosWithTorrent(torrent)
    }

    @objc private func HandleTorrentInControllerUpdateFailed(_ notification: Notification) {
        guard let error = notification.userInfo?["error"] as? NSError else { print("Error no error in userinfo"); return }
        if error.code == 1 {
            guard let hashString = error.userInfo["hashString"] as? String else { print("Error no hash in userinfo"); return }
            guard let torrent = TorrentService.sharedTorrentService.torrentController.torrentFromHash(hashString) as? Torrent else { return }
            self.ClearCurrentTorrentEntityAndVideos()
            self.UpdateLocalVideosWithTorrent(torrent)
        }
    }
}
