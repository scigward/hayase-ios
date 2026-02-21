//
//  VideoService.swift
//  TheAnimeTool
//

import Foundation
import CoreData
import LibTorrent

public class VideoService: NSObject {
    enum VideoError: Error {
        case invalidIndex
    }
    static let LocalVideosDidUpdateNotification  = "LocalVideosDidUpdateNotification"
    static let LocalVideosWillUpdateNotification = "LocalVideosWillUpdateNotification"

    let torrentEntity: Torrents
    var torrentHandle: TorrentHandle? = nil

    init(torrentEntity: Torrents) {
        self.torrentEntity = torrentEntity
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(HandleTorrentInControllerDidUpdate), name: NSNotification.Name(TorrentService.TorrentInControllerDidUpdateNotification), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(HandleTorrentInControllerUpdateFailed), name: NSNotification.Name(TorrentService.TorrentInControllerUpdateFailedNotification), object: nil)
    }

    func UpdateLocalVideo() {
        TorrentService.sharedTorrentService.UpdateTorrentEntityInController(torrentEntity) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let handle):
                self.ClearCurrentTorrentEntityAndVideos()
                self.UpdateLocalVideosWithHandle(handle)
                // LocalVideosDidUpdateNotification is posted inside UpdateLocalVideosWithHandle
            case .failure(let error):
                print("VideoService: torrent update failed: \(error.localizedDescription)")
                NotificationCenter.default.post(
                    name: NSNotification.Name(VideoService.LocalVideosDidUpdateNotification),
                    object: nil)
            }
        }
    }

    func ClearCurrentTorrentEntityAndVideos() {
        let context = CoreDataService.sharedCoreDataService.mainQueueContext
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: Videos.entityName)
        if let count = try? context.count(for: request), count > 0 {
            context.deleteAllData(request)
        }
        if let handle = self.torrentHandle,
           self.torrentEntity.torrentFlagTemp?.boolValue == true {
            TorrentService.sharedTorrentService.session.removeTorrent(handle, deleteFiles: true)
            torrentEntity.torrentHashString = nil
            try? context.save()
        }
        self.torrentHandle = nil
    }

    func UpdateLocalVideosWithHandle(_ handle: TorrentHandle) {
        handle.updateSnapshot()
        let snap = handle.snapshot
        let context = CoreDataService.sharedCoreDataService.mainQueueContext
        self.torrentHandle = handle
        self.torrentEntity.torrentHashString = handle.infoHashes.best.hex

        NotificationCenter.default.post(name: NSNotification.Name(VideoService.LocalVideosWillUpdateNotification), object: nil)
        // isPrototype entries are libtorrent padding files used for piece alignment — skip them
        for entry in snap.files where !entry.isPrototype {
            let newVideoEntity = NSEntityDescription.insertNewObject(forEntityName: Videos.entityName, into: context) as! Videos
            newVideoEntity.videoName = entry.name
            newVideoEntity.videoPath = resolvedPath(for: entry, in: snap)
            newVideoEntity.videoSize = NSNumber(value: Double(entry.size) / 1024.0 / 1024.0)
            newVideoEntity.videoIndex = NSNumber(value: entry.index)
            newVideoEntity.torrents = torrentEntity
        }
        do { try context.save() } catch let error { print("Error updating local videos: \(error)"); return }
        NotificationCenter.default.post(name: NSNotification.Name(VideoService.LocalVideosDidUpdateNotification), object: nil)
    }

    func UpdateProgressForFileIndex(_ index: UInt) -> Float {
        guard let handle = torrentHandle else { return 0 }
        handle.updateSnapshot()
        let files = handle.snapshot.files
        guard let entry = files.first(where: { $0.index == Int(index) }) else { return 0 }
        let progress = entry.size > 0 ? Float(entry.downloaded) / Float(entry.size) : 0
        guard let hashHex = torrentEntity.torrentHashString else { return progress }
        let context = CoreDataService.sharedCoreDataService.mainQueueContext
        let fetchRequest = NSFetchRequest<Videos>(entityName: Videos.entityName)
        fetchRequest.predicate = NSPredicate(format: "torrents.torrentHashString == %@ AND videoIndex == %d", hashHex, index)
        if let videos = try? context.fetch(fetchRequest), !videos.isEmpty {
            videos[0].videoDownloadPercent = NSNumber(value: progress)
            try? context.save()
        }
        return progress
    }

    func UpdateFilePathForFileIndex(_ index: UInt) -> String {
        guard let handle = torrentHandle else { return "" }
        handle.updateSnapshot()
        let snap = handle.snapshot
        guard let entry = snap.files.first(where: { $0.index == Int(index) }) else { return "" }
        let filePath = resolvedPath(for: entry, in: snap)
        guard let hashHex = torrentEntity.torrentHashString else { return filePath }
        let context = CoreDataService.sharedCoreDataService.mainQueueContext
        let fetchRequest = NSFetchRequest<Videos>(entityName: Videos.entityName)
        fetchRequest.predicate = NSPredicate(format: "torrents.torrentHashString == %@ AND videoIndex == %d", hashHex, index)
        if let videos = try? context.fetch(fetchRequest), !videos.isEmpty {
            videos[0].videoPath = filePath
            try? context.save()
        }
        return filePath
    }

    func CheckIsDoNotDownloadForFileIndex(_ index: UInt) -> Bool? {
        guard let handle = torrentHandle else { return nil }
        guard let entry = handle.snapshot.files.first(where: { $0.index == Int(index) }) else { return nil }
        return entry.priority == FileEntry.Priority.dontDownload
    }

    func SetDoNotDownloadForFileIndex(_ index: UInt, flag: Bool) {
        guard let handle = torrentHandle else { return }
        let priority: FileEntry.Priority = flag ? .dontDownload : .defaultPriority
        handle.setFilePriority(priority, at: Int(index))
    }

    func UpdateTorrentFileInfos() {
        torrentHandle?.updateSnapshot()
    }

    @objc private func HandleTorrentInControllerDidUpdate(_ notification: Notification) {
        guard let handle = notification.userInfo?["torrentHandle"] as? TorrentHandle else { return }
        let handleHex = handle.infoHashes.best.hex
        guard let expectedHex = torrentEntity.torrentHashString, handleHex == expectedHex else { return }
        // Only handle background progress updates — initial add is handled by completion closure.
        guard torrentHandle != nil else { return }
        handle.updateSnapshot()
        self.torrentHandle = handle
        NotificationCenter.default.post(
            name: NSNotification.Name(VideoService.LocalVideosDidUpdateNotification), object: nil)
    }

    @objc private func HandleTorrentInControllerUpdateFailed(_ notification: Notification) {
        // Session-level error: make sure spinner stops
        guard torrentHandle == nil else { return } // already initialized
        let msg = (notification.userInfo?["error"] as? NSError)?.localizedDescription ?? "Unknown error"
        print("VideoService: session error: \(msg)")
        NotificationCenter.default.post(
            name: NSNotification.Name(VideoService.LocalVideosDidUpdateNotification), object: nil)
    }

    // MARK: - Private helpers

    /// Returns the absolute path for a `FileEntry` within the torrent's download directory.
    /// Logs a warning when `downloadPath` is not yet set (download hasn't started).
    private func resolvedPath(for entry: FileEntry, in snapshot: TorrentHandle.Snapshot) -> String {
        guard let base = snapshot.downloadPath else {
            print("VideoService: downloadPath not yet available for entry '\(entry.name)' — download may not have started")
            return ""
        }
        return base.appendingPathComponent(entry.path).path
    }
}

