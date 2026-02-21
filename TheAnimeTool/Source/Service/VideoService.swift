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
    /// Forwarded to VideoListViewController so it can display an error alert.
    var lastError: Error? = nil

    /// Guards against `HandleTorrentInControllerDidUpdate` stopping the spinner
    /// before `UpdateLocalVideosWithHandle` has finished populating CoreData.
    /// Persisted TorrentHashes in CoreData from previous sessions would otherwise
    /// match the ongoing background update stream and fire LocalVideosDidUpdateNotification
    /// before any video rows exist — resulting in a blank table with no spinner.
    private var coreDataIsReady = false

    init(torrentEntity: Torrents) {
        self.torrentEntity = torrentEntity
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(HandleTorrentInControllerDidUpdate), name: NSNotification.Name(TorrentService.TorrentInControllerDidUpdateNotification), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(HandleTorrentInControllerUpdateFailed), name: NSNotification.Name(TorrentService.TorrentInControllerUpdateFailedNotification), object: nil)
    }

    func UpdateLocalVideo() {
        // Mark CoreData as not ready so background update notifications do not
        // stop the spinner before we have data to show.
        coreDataIsReady = false
        lastError = nil
        TorrentService.sharedTorrentService.UpdateTorrentEntityInController(torrentEntity) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let (handle, torrentFile)):
                self.ClearCurrentTorrentEntityAndVideos()
                self.UpdateLocalVideosWithHandle(handle, torrentFile: torrentFile)
            case .failure(let error):
                print("VideoService: torrent update failed: \(error.localizedDescription)")
                self.lastError = error
                NotificationCenter.default.post(
                    name: NSNotification.Name(VideoService.LocalVideosDidUpdateNotification),
                    object: nil)
            }
        }
    }

    func ClearCurrentTorrentEntityAndVideos() {
        coreDataIsReady = false
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
        // Store handle + hash so the notification filter can match future progress updates.
        self.torrentHandle = handle
        self.torrentEntity.torrentHashString = handle.infoHashes.best.hex
        try? CoreDataService.sharedCoreDataService.mainQueueContext.save()

        // Use torrentFile.files (isPrototype=true entries parsed directly from .torrent binary)
        // for immediate CoreData population.  snapshot.files requires torrent_file() to be
        // non-null in libtorrent, which only happens after add_torrent_alert is processed on
        // the alerts thread (~500 ms after addTorrent() returns).  This matches iTorrent's
        // approach: TorrentFile.files for initial display; snapshot.files for live progress.
        let files = torrentFile.files
        guard !files.isEmpty else {
            print("VideoService: torrent file has no entries")
            coreDataIsReady = true
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
        }
        do {
            try context.save()
        } catch {
            print("VideoService: CoreData save error: \(error)")
            coreDataIsReady = true
            NotificationCenter.default.post(
                name: NSNotification.Name(VideoService.LocalVideosDidUpdateNotification), object: nil)
            return
        }
        // Mark ready BEFORE posting so that any re-entrant notification handler
        // sees the correct state.
        coreDataIsReady = true
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
        // CRITICAL: do not stop the spinner until CoreData has been populated.
        // Without this guard, a background update for a torrent whose hash was
        // persisted in CoreData from a previous session fires immediately after
        // VideoService is created — stopping the spinner before any video rows exist.
        guard coreDataIsReady else { return }
        guard let handle = notification.userInfo?["torrentHandle"] as? TorrentHandle else { return }
        let handleHex = handle.infoHashes.best.hex
        guard let expectedHex = torrentEntity.torrentHashString, handleHex == expectedHex else { return }
        self.torrentHandle = handle
        // CoreData is already populated from torrentFile.files in UpdateLocalVideosWithHandle.
        // Just notify the UI to refresh progress values read from handle.snapshot.
        NotificationCenter.default.post(
            name: NSNotification.Name(VideoService.LocalVideosDidUpdateNotification), object: nil)
    }

    @objc private func HandleTorrentInControllerUpdateFailed(_ notification: Notification) {
        guard torrentHandle == nil else { return } // already initialized — ignore session errors
        let msg = (notification.userInfo?["error"] as? NSError)?.localizedDescription ?? "Unknown error"
        print("VideoService: session error: \(msg)")
        // Only stop the spinner if we were still loading (coreDataIsReady == false)
        guard !coreDataIsReady else { return }
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

