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

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func UpdateLocalVideo() {
        // Mark CoreData as not ready so background update notifications do not
        // stop the spinner before we have data to show.
        coreDataIsReady = false
        lastError = nil
        TorrentService.sharedTorrentService.UpdateTorrentEntityInController(torrentEntity) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let handle):
                self.ClearCurrentTorrentEntityAndVideos()
                self.UpdateLocalVideosWithHandle(handle)
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
        // Only delete video rows for THIS torrent entity.
        // Do NOT remove the torrent from the LibTorrent session — the download should
        // continue in the background while the user navigates away.
        request.predicate = NSPredicate(format: "torrents == %@", torrentEntity)
        if let count = try? context.count(for: request), count > 0 {
            context.deleteAllData(request)
            try? context.save()
        }
        self.torrentHandle = nil
    }

    /// Store the active handle and torrent hash.  CoreData is NOT populated here —
    /// for magnet links the file list is only available after metadata is fetched from
    /// peers/DHT, which triggers `didReceiveUpdateForTorrent` → `HandleTorrentInControllerDidUpdate`.
    /// That method watches for `snapshot.files.count > 0` and then populates CoreData.
    func UpdateLocalVideosWithHandle(_ handle: TorrentHandle) {
        self.torrentHandle = handle
        let hex = handle.infoHashes.best.hex
        torrentEntity.torrentHashString = hex
        try? CoreDataService.sharedCoreDataService.mainQueueContext.save()
        print("VideoService: handle stored hex=\(hex), waiting for metadata via snapshot updates")

        // Fast path: if metadata is already available (re-open of existing torrent or
        // .torrent file add), populate CoreData immediately.
        handle.updateSnapshot()
        let files = handle.snapshot.files
        if !files.isEmpty {
            print("VideoService: metadata available immediately, \(files.count) files")
            insertVideosFromSnapshot(files, snapshot: handle.snapshot)
        } else {
            print("VideoService: metadata not yet available — spinner stays until didReceiveUpdateForTorrent")
        }
    }

    /// Insert video rows from a fully-populated snapshot file list.
    private func insertVideosFromSnapshot(_ files: [FileEntry], snapshot: TorrentHandle.Snapshot) {
        let context = CoreDataService.sharedCoreDataService.mainQueueContext
        for entry in files {
            guard let v = NSEntityDescription.insertNewObject(forEntityName: Videos.entityName, into: context) as? Videos else { continue }
            v.videoName = entry.name
            v.videoSize = NSNumber(value: Double(entry.size) / 1024.0 / 1024.0)
            // Use entry.index (file's actual position in the torrent) not the array position —
            // the list may be sparse or reordered and the index must match libtorrent's indexing.
            v.videoIndex = NSNumber(value: entry.index)
            v.torrents = torrentEntity
        }
        do {
            try context.save()
            coreDataIsReady = true
            print("VideoService: CoreData populated with \(files.count) videos")
            NotificationCenter.default.post(
                name: NSNotification.Name(VideoService.LocalVideosDidUpdateNotification), object: nil)
        } catch {
            print("VideoService: CoreData save error: \(error)")
            // Still mark ready and notify so the spinner stops (shows empty state).
            coreDataIsReady = true
            NotificationCenter.default.post(
                name: NSNotification.Name(VideoService.LocalVideosDidUpdateNotification), object: nil)
        }
    }

    func UpdateProgressForFileIndex(_ index: UInt) -> Float {
        guard let handle = torrentHandle else { return 0 }
        // Read live download progress from the snapshot (updated by TorrentService background queue).
        // Do NOT write back to CoreData here — progress is display-only and saving during
        // cellForRowAt causes unnecessary CoreData churn every refresh tick.
        let files = handle.snapshot.files
        guard let entry = files.first(where: { $0.index == Int(index) }) else { return 0 }
        return entry.size > 0 ? Float(entry.downloaded) / Float(entry.size) : 0
    }

    /// Returns the number of bytes already downloaded for this file index (live from snapshot).
    func downloadedBytesForFileIndex(_ index: UInt) -> UInt64 {
        guard let handle = torrentHandle else { return 0 }
        guard let entry = handle.snapshot.files.first(where: { $0.index == Int(index) }) else { return 0 }
        return entry.downloaded
    }

    /// Returns the total size in bytes for this file index (live from snapshot).
    func totalBytesForFileIndex(_ index: UInt) -> UInt64 {
        guard let handle = torrentHandle else { return 0 }
        guard let entry = handle.snapshot.files.first(where: { $0.index == Int(index) }) else { return 0 }
        return entry.size
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

    /// Hayase approach: focus all download bandwidth on one episode.
    /// Sets every other file in the torrent to dontDownload so libtorrent
    /// dedicates all piece-picking to the file the user wants to watch.
    func selectFileForStreaming(_ fileIndex: UInt) {
        guard let handle = torrentHandle else { return }
        for entry in handle.snapshot.files {
            let priority: FileEntry.Priority = entry.index == Int(fileIndex) ? .defaultPriority : .dontDownload
            handle.setFilePriority(priority, at: Int(entry.index))
        }
    }

    func UpdateTorrentFileInfos() {
        // No-op: snapshot is kept current by TorrentService's background-queue updateSnapshot()
    }

    @objc private func HandleTorrentInControllerDidUpdate(_ notification: Notification) {
        guard let handle = notification.userInfo?["torrentHandle"] as? TorrentHandle else { return }
        let handleHex = handle.infoHashes.best.hex
        guard let expectedHex = torrentEntity.torrentHashString, handleHex == expectedHex else { return }
        self.torrentHandle = handle

        if !coreDataIsReady {
            // Metadata not yet committed to CoreData. For magnet links, hasMetadata is false
            // until the ut_metadata extension downloads it from DHT/peers. Once true, files
            // will also be populated (torrent_file() is non-null when has_metadata is true).
            guard handle.snapshot.hasMetadata else {
                let peers = handle.snapshot.numberOfPeers
                print("VideoService: snapshot update — hasMetadata=false, peers=\(peers) (waiting for metadata)")
                return  // Keep spinner running; post no notification.
            }
            let files = handle.snapshot.files
            print("VideoService: metadata arrived via update, \(files.count) files — populating CoreData")

            // Clear any stale video rows for this entity without touching the session.
            // (ClearCurrentTorrentEntityAndVideos also calls session.removeTorrent for temp
            //  torrents — we must NOT do that here or the download is killed mid-add.)
            let ctx = CoreDataService.sharedCoreDataService.mainQueueContext
            let clearReq = NSFetchRequest<NSFetchRequestResult>(entityName: Videos.entityName)
            clearReq.predicate = NSPredicate(format: "torrents == %@", torrentEntity)
            if let n = try? ctx.count(for: clearReq), n > 0 {
                ctx.deleteAllData(clearReq)
                try? ctx.save()
            }

            // Re-store handle and hash (ClearCurrentTorrentEntityAndVideos would have nil'd them).
            self.torrentHandle = handle
            torrentEntity.torrentHashString = handleHex
            insertVideosFromSnapshot(files, snapshot: handle.snapshot)
        } else {
            // CoreData already has video rows. Just notify the UI to refresh progress
            // values read live from handle.snapshot.
            NotificationCenter.default.post(
                name: NSNotification.Name(VideoService.LocalVideosDidUpdateNotification), object: nil)
        }
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