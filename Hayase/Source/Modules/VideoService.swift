//
//  VideoService.swift
//  Hayase
//

import Foundation
import CoreData

public class VideoService: NSObject {
    static let LocalVideosDidUpdateNotification  = "LocalVideosDidUpdateNotification"

    let torrentEntity: Torrents
    private let requestedEpisode: Int
    /// Forwarded to VideoListViewController so it can display an error alert.
    var lastError: Error? = nil
    /// The media the torrent is played for, when the caller has it already, so web seeds need
    /// no second lookup.
    var media: AnimeItem?
    /// The WebTorrent load this service started, which it drops with it.
    private var webTorrentPlay: WebTorrentPlayRequest?
    /// resolver.ts `otherFiles`: what the torrent holds that is not a video (subtitle files, fonts).
    private(set) var otherFiles: [WebTorrentFile] = []

    /// Set once the video rows of the torrent are in CoreData, so the spinner of a list is not
    /// stopped by a notification that arrives before there is anything to show.
    private var coreDataIsReady = false
    var hasFinishedUpdatingLocalVideos: Bool { coreDataIsReady || lastError != nil }

    init(torrentEntity: Torrents, episode: Int = 0) {
        self.torrentEntity = torrentEntity
        self.requestedEpisode = episode
        super.init()
    }

    deinit {
        // A load nobody is left to receive would otherwise carry on fetching metadata.
        webTorrentPlay?.cancel()
    }

    /// Hands the torrent back to the backend once playback of it has ended for good, not when
    /// it merely moves to the miniplayer. A load that was still pending is cancelled.
    func releaseWebTorrentSession() {
        webTorrentPlay?.release()
    }

    func UpdateLocalVideo() {
        // Mark CoreData as not ready so background update notifications do not
        // stop the spinner before we have data to show.
        coreDataIsReady = false
        lastError = nil

        let mediaID = torrentEntity.animes?.animeAnilistId?.intValue ?? 0
        webTorrentPlay?.cancel()
        webTorrentPlay = TorrentBackendManager.shared.playWebTorrent(torrentEntity: torrentEntity,
                                                                     mediaID: mediaID,
                                                                     episode: requestedEpisode) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success(let files):
                    self.ClearCurrentTorrentEntityAndVideos()
                    self.InsertVideosFromWebTorrentFiles(files)
                    WebTorrentDownloaded.shared.add(files.first?.hash)
                    WebTorrentWebSeeds.add(hash: files.first?.hash ?? "", mediaID: mediaID, media: self.media,
                                           episode: self.requestedEpisode > 0 ? self.requestedEpisode : nil,
                                           files: .batch(files.map { WebSeedFile(name: $0.name, index: $0.id) }))
                case .failure(let error):
                    print("VideoService: WebTorrent update failed: \(error.localizedDescription)")
                    self.lastError = error
                    NotificationCenter.default.post(
                        name: NSNotification.Name(VideoService.LocalVideosDidUpdateNotification),
                        object: nil)
                }
            }
        }
    }

    func ClearCurrentTorrentEntityAndVideos() {
        coreDataIsReady = false
        let context = CoreDataService.sharedCoreDataService.mainQueueContext
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: Videos.entityName)
        // Only delete video rows for THIS torrent entity.
        request.predicate = NSPredicate(format: "torrents == %@", torrentEntity)
        if let count = try? context.count(for: request), count > 0 {
            context.deleteAllData(request)
            try? context.save()
        }
    }

    /// Returns the number of bytes already downloaded for this file index. A file the backend serves
    /// is streamed, so it counts as there as a whole.
    func downloadedBytesForFileIndex(_ index: UInt) -> UInt64 {
        webTorrentVideoPath(forFileIndex: index) == nil ? 0 : totalBytesForFileIndex(index)
    }

    /// Returns the total size in bytes for this file index.
    func totalBytesForFileIndex(_ index: UInt) -> UInt64 {
        guard let video = videoForFileIndex(index),
              let sizeMB = video.videoSize?.doubleValue else { return 0 }
        return UInt64(max(sizeMB, 0) * 1024.0 * 1024.0)
    }

    /// The URL the backend serves the file at, or an empty string while there is none.
    func UpdateFilePathForFileIndex(_ index: UInt) -> String {
        webTorrentVideoPath(forFileIndex: index) ?? ""
    }

    func CheckIsDoNotDownloadForFileIndex(_ index: UInt) -> Bool? {
        webTorrentVideoPath(forFileIndex: index) == nil ? nil : false
    }

    private func InsertVideosFromWebTorrentFiles(_ files: [WebTorrentFile]) {
        let context = CoreDataService.sharedCoreDataService.mainQueueContext
        let videoFiles = files.filter { TorrentBatchResolver.isVideoFile($0.name) }
        otherFiles = files.filter { !TorrentBatchResolver.isVideoFile($0.name) }

        if let hash = files.first?.hash, !hash.isEmpty {
            torrentEntity.torrentHashString = hash
        }

        guard !videoFiles.isEmpty else {
            lastError = NSError(domain: "Hayase.WebTorrent",
                                code: 1,
                                userInfo: [NSLocalizedDescriptionKey: "WebTorrent metadata did not contain any playable video files."])
            coreDataIsReady = true
            NotificationCenter.default.post(
                name: NSNotification.Name(VideoService.LocalVideosDidUpdateNotification), object: nil)
            return
        }

        for file in videoFiles {
            guard let v = NSEntityDescription.insertNewObject(forEntityName: Videos.entityName, into: context) as? Videos else { continue }
            v.videoName = file.name
            v.videoSize = NSNumber(value: Double(file.size) / 1024.0 / 1024.0)
            v.videoIndex = NSNumber(value: file.id)
            v.videoPath = file.url
            v.videoLanPath = file.lan
            v.torrents = torrentEntity
        }

        do {
            try context.save()
            coreDataIsReady = true
            print("VideoService: WebTorrent populated CoreData with \(videoFiles.count) playable videos")
            NotificationCenter.default.post(
                name: NSNotification.Name(VideoService.LocalVideosDidUpdateNotification), object: nil)
        } catch {
            print("VideoService: WebTorrent CoreData save error: \(error)")
            lastError = error
            coreDataIsReady = true
            NotificationCenter.default.post(
                name: NSNotification.Name(VideoService.LocalVideosDidUpdateNotification), object: nil)
        }
    }

    private func webTorrentVideoPath(forFileIndex index: UInt) -> String? {
        guard let path = videoForFileIndex(index)?.videoPath else { return nil }
        let lowercased = path.lowercased()
        guard lowercased.hasPrefix("http://") || lowercased.hasPrefix("https://") else { return nil }
        return path
    }

    private func videoForFileIndex(_ index: UInt) -> Videos? {
        let context = CoreDataService.sharedCoreDataService.mainQueueContext
        let fetchRequest = NSFetchRequest<Videos>(entityName: Videos.entityName)
        fetchRequest.fetchLimit = 1
        fetchRequest.predicate = NSPredicate(format: "torrents == %@ AND videoIndex == %d", torrentEntity, Int(index))
        return (try? context.fetch(fetchRequest))?.first
    }
}
