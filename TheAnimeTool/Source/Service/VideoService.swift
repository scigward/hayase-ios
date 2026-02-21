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
            case .success(let (handle, torrentFile)):
                self.ClearCurrentTorrentEntityAndVideos()
                self.UpdateLocalVideosWithHandle(handle, torrentFile: torrentFile)
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

    func UpdateLocalVideosWithHandle(_ handle: TorrentHandle, torrentFile: TorrentFile) {
        // Store handle + hash immediately so the notification filter can match future updates.
        self.torrentHandle = handle
        self.torrentEntity.torrentHashString = handle.infoHashes.best.hex
        try? CoreDataService.sharedCoreDataService.mainQueueContext.save()

        // Use torrentFile.files for immediate CoreData population.
        // These entries (isPrototype=true) are parsed directly from the .torrent binary data
        // and are ALWAYS available — unlike snapshot.files which requires torrent_file() to be
        // non-null in libtorrent, which only happens after add_torrent_alert is processed
        // (~500 ms later on the alerts thread).
        // This matches iTorrent's approach: TorrentFile.files is used for pre-add display;
        // snapshot.files (with real download progress) arrives via didReceiveUpdateForTorrent.
        let files = torrentFile.files
        guard !files.isEmpty else {
            print("VideoService: torrent file has no entries")
            NotificationCenter.default.post(
                name: NSNotification.Name(VideoService.LocalVideosDidUpdateNotification), object: nil)
            return
        }
        let context = CoreDataService.sharedCoreDataService.mainQueueContext
        for entry in files {
            guard let v = NSEntityDescription.insertNewObject(forEntityName: Videos.entityName, into: context) as? Videos else {
                print("VideoService: unexpected entity type for \(Videos.entityName)")
                continue
            }
            v.videoName = entry.name
            v.videoSize = NSNumber(value: Double(entry.size) / 1024.0 / 1024.0)
            v.videoIndex = NSNumber(value: entry.index)
            v.torrents = torrentEntity
            // videoPath resolved later by UpdateFilePathForFileIndex once snapshot is populated.
        }
        do {
            try context.save()
        } catch {
            print("VideoService: CoreData save error: \(error)")
            NotificationCenter.default.post(
                name: NSNotification.Name(VideoService.LocalVideosDidUpdateNotification), object: nil)
            return
        }
        NotificationCenter.default.post(
            name: NSNotification.Name(VideoService.LocalVideosDidUpdateNotification), object: nil)
    }

    func UpdateProgressForFileIndex(_ index: UInt) -> Float {
        guard let handle = torrentHandle else { return 0 }
        // Use the already-updated snapshot (set by background queue in TorrentService)
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
        // Use the already-updated snapshot (set by background queue in TorrentService)
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
        // Use the snapshot already updated by TorrentService's background queue
        guard let entry = handle.snapshot.files.first(where: { $0.index == Int(index) }) else { return nil }
        return entry.priority == FileEntry.Priority.dontDownload
    }

    func SetDoNotDownloadForFileIndex(_ index: UInt, flag: Bool) {
        guard let handle = torrentHandle else { return }
        let priority: FileEntry.Priority = flag ? .dontDownload : .defaultPriority
        handle.setFilePriority(priority, at: Int(index))
    }

    func UpdateTorrentFileInfos() {
        // No-op: snapshot is kept current by TorrentService's background-queue updateSnapshot()
    }

    @objc private func HandleTorrentInControllerDidUpdate(_ notification: Notification) {
        guard let handle = notification.userInfo?["torrentHandle"] as? TorrentHandle else { return }
        // snapshot was already updated on global background queue in TorrentService
        // before this notification was posted.
        let handleHex = handle.infoHashes.best.hex
        guard let expectedHex = torrentEntity.torrentHashString, handleHex == expectedHex else { return }
        self.torrentHandle = handle
        // CoreData is already populated from torrentFile.files in UpdateLocalVideosWithHandle.
        // Just notify the UI to refresh progress values read from handle.snapshot.
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

