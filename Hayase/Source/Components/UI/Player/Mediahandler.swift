//
//  Mediahandler.swift
//  Hayase
//
//  Mirrors: src/lib/components/ui/player/mediahandler.svelte: which file of the torrent is played and how the player
//  goes to the next or the previous episode (skipping the fillers when it is asked to, going back to the search
//  when the episode is not in the files that are resolved), and what Watch Together says about the index.
//

import UIKit
import AVKit
import CoreMedia
import UniformTypeIdentifiers

extension VideoPlayerViewController {
    func loadCurrentVideo() {
        guard let entity = videoEntity else { return }
        let path = entity.videoPath ?? ""
        guard !path.isEmpty else { return }
        
        // Reset states for new file
        trackingCompleted = false
        isEOFTriggered = false
        pendingRestoreTime = nil
        chapters.removeAll()
        chapterModel = []
        fileChapters = []
        chaptersLoadedDuration = 0
        chaptersTask?.cancel()
        // `new Chapters(mediaInfo)`: the themes of the anime are asked for as the player is made
        chaptersHandler = Chapters(mediaID: currentMediaID, episode: episodeNumber)
        currentSkippableChapter = nil
        skipChapterButton.stopProgress()
        updateChapterMarkers()
        updateBuffering(true)

        // player.svelte: web seeds for the file being played.
        if let hash = entity.torrents?.torrentHashString,
           let name = entity.videoName,
           let index = entity.videoIndex?.intValue {
            WebTorrentWebSeeds.add(hash: hash, mediaID: currentMediaID, media: videoService?.media,
                                   episode: episodeNumber > 0 ? episodeNumber : nil,
                                   files: .single(WebSeedFile(name: name, index: index)))
        }

        loadVideoURL()

        // Set initial AniList state (PLANNING → CURRENT, COMPLETED → REPEATING) for ep 1
        AniListTracking.shared.setInitialState(anilistID: anilistID, episode: episodeNumber)

        // `this.last.set({ id: infoHash, media, episode })`, then, in a lobby, w2globby.mediaChange.
        MiniPlayerManager.shared.saveSession(of: self)
        if let hash = currentW2GTorrentHash, anilistID > 0 {
            W2GMediaState.last = W2GMediaState(torrent: hash, mediaId: anilistID, episode: episodeNumber)
            W2GLobby.shared.client?.mediaChange(
                W2GMediaState(torrent: hash, mediaId: anilistID, episode: episodeNumber)
            )
            W2GLobby.shared.client?.mediaIndexChanged(playlistIndex)
        }
    }

    /// Switch to a different file index within the same torrent, triggered by
    /// a remote W2G index event.
    /// Mirrors web mediahandler.svelte: `$: $w2globby?.on('index', index => { current = fileToMedaInfo(mediaInfo.resolvedFiles[index]) })`
    func applyRemoteW2GIndex(_ newIndex: Int) {
        if !resolvedVideoFiles.isEmpty {
            guard let file = resolvedVideoFiles[safe: newIndex],
                  !matchesVideo(file, fileIndex) else { return }
            switchToResolvedVideoFile(file)
            return
        }

        guard newIndex >= 0, newIndex < allVideos.count else { return }
        let video = allVideos[newIndex]
        guard video.videoIndex?.uintValue != fileIndex else { return }
        switchToVideo((video: video, index: newIndex), episode: episodeNumber + (newIndex - currentVideoIndex))
    }

    /// Builds the URL and preset, loads the video into MPV, and starts stats.
    func loadVideoURL() {
        guard let entity = videoEntity else { return }
        let path = entity.videoPath ?? ""
        guard !path.isEmpty else { return }

        let url: URL
        let preset: PlayerPreset
        if path.starts(with: "http"), let httpURL = URL(string: path) {
            url = httpURL
            preset = PlayerPreset()
        } else {
            url = URL(fileURLWithPath: path)
            // Reset cache + re-enable MKV probing for local files.
            // probe-video-duration=yes gives accurate duration + seek index
            // for fully-downloaded files with no blocking risk.
            preset = PlayerPreset(commands: [
                ["set", "demuxer-mkv-probe-video-duration", "yes"],
                ["set", "cache", "no"],
            ])
        }

        surface.mpv.load(url: url, with: preset)
        subtitles?.destroy()
        let loader = Subtitles(mpv: surface.mpv, videoName: entity.videoName ?? url.lastPathComponent)
        loader.start(otherFiles: videoService?.otherFiles ?? [],
                     item: videoService?.media ?? Router.shared.cachedAnimeItem(for: currentMediaID),
                     episode: episodeNumber)
        subtitles = loader
        thumbnailer.updateSource(url)
        seekingImage.isHidden = true
        seekPreview.isHidden = true
        previewRequest = UUID()
        
        // Hayase episodesmodal.svelte: title = anime name, description = episode info
        titleLabel.content = animeTitleText()
        episodeLabel.content = episodeDescriptionText()
        // Hayase mediahandler.svelte: hasPrev = episode > 1; hasNext = episode < totalEps.
        // Enable buttons based on episode bounds, not just allVideos array bounds.
        // When onEpisodeChange is set, out-of-batch navigation triggers a new search.
        let canGoPrev = canNavigateToPreviousEpisode
        let canGoNext = canNavigateToNextEpisode
        prevButton.isEnabled = canGoPrev
        nextButton.isEnabled = canGoNext
        mobilePrevButton.isEnabled = canGoPrev
        mobileNextButton.isEnabled = canGoNext
        nowCastingPrevButton.isEnabled = canGoPrev
        nowCastingNextButton.isEnabled = canGoNext
        updateMediaSession(canGoPrev: canGoPrev, canGoNext: canGoNext)
        loadAnimeProgress()
        startStatsTimer()

        // castplayer.svelte's prev/next are the same functions the normal
        // player uses, so skipping episodes while casting re-sends the new
        // file to the same display rather than leaving the TV on the old one.
        if let display = activeCastDisplay {
            startCasting(to: display)
        }
    }

    /// `loadAnimeProgress`: the episode that was played last of this media resumes five seconds before where it was
    func loadAnimeProgress() {
        guard currentMediaID > 0, episodeNumber > 0,
              let saved = WatchProgressService.shared.getAnimeProgress(mediaID: currentMediaID),
              saved.episode == episodeNumber else { return }
        // Store the target time and apply it once MPV reports a valid duration
        // in didUpdatePosition. This works for both local files (where MPV is
        // ready almost immediately) and HTTP streams (where header buffering
        // can take several seconds or more).
        pendingRestoreTime = max(saved.currentTime - 5, 0)
    }

    func navigateEpisode(by delta: Int) {
        guard let currentEpisode = currentEpisodeForNavigation else { return }

        resolveNavigationEpisode(from: currentEpisode, delta: delta, mediaID: currentMediaID) { [weak self] targetEpisode in
            guard let self, let targetEpisode else { return }
            self.playEpisode(targetEpisode, media: nil)
        }
    }

    func resolveNavigationEpisode(from currentEpisode: Int,
                                          delta: Int,
                                          mediaID: Int,
                                          completion: @escaping (Int?) -> Void) {
        let rawTarget = currentEpisode + delta
        guard Settings.skipFiller, mediaID > 0 else {
            completion(canNavigate(to: rawTarget) ? rawTarget : nil)
            return
        }

        AnimeDetailViewController.loadFillerSet(for: mediaID) { [weak self] fillerSet in
            DispatchQueue.main.async {
                guard let self else { return }
                var targetEpisode = rawTarget
                while fillerSet.contains(targetEpisode) {
                    targetEpisode += delta
                }
                if delta > 0 {
                    let limit = self.currentEpisodeLimit
                    if limit > 0 { targetEpisode = min(targetEpisode, limit) }
                } else {
                    targetEpisode = max(1, targetEpisode)
                }
                completion(self.canNavigate(to: targetEpisode) ? targetEpisode : nil)
            }
        }
    }

    /// Mirrors Hayase web mediahandler.svelte `playEpisode`: search the current
    /// resolved batch by AniList media and episode; otherwise start a new search.
    func playEpisode(_ episode: Int, media: AnimeItem?) {
        let mediaID = media?.id ?? currentMediaID
        if let file = resolvedVideoFile(forEpisode: episode, mediaID: mediaID) {
            switchToResolvedVideoFile(file)
        } else if let match = videoMatchByFilename(forEpisode: episode) {
            switchToVideo(match, episode: episode, media: media ?? currentResolvedVideoFile?.media)
        } else {
            requestEpisodeChange(episode, media: media)
        }
    }

    func resolvedVideoFile(forEpisode targetEp: Int,
                                   mediaID: Int) -> TorrentBatchResolver.ResolvedItem<Videos>? {
        resolvedVideoFiles.first { resolvedFile in
            resolvedFile.episodeReference.matches(targetEp)
                && resolvedFile.media?.id == mediaID
                && videoMatch(for: resolvedFile) != nil
        }
    }

    var currentResolvedVideo: TorrentBatchResolver.ResolvedItem<Videos>? {
        if let currentResolvedVideoFile, matchesVideo(currentResolvedVideoFile, fileIndex) {
            return currentResolvedVideoFile
        }
        return resolvedVideoFiles.first { matchesVideo($0, fileIndex) }
    }

    var currentMediaID: Int {
        currentResolvedVideo?.media?.id ?? anilistID
    }

    var currentEpisodeForNavigation: Int? {
        if let file = currentResolvedVideo {
            return file.episodeReference.intValue
        }
        if episodeNumber > 0 {
            return episodeNumber
        }
        if let parsedEpisode = TorrentBatchResolver.extractEpisodeNumber(from: videoEntity?.videoName ?? "") {
            return parsedEpisode
        }
        return nil
    }

    var canNavigateToPreviousEpisode: Bool {
        guard let episode = currentEpisodeForNavigation else { return false }
        return canNavigate(to: episode - 1)
    }

    var canNavigateToNextEpisode: Bool {
        guard let episode = currentEpisodeForNavigation else { return false }
        return canNavigate(to: episode + 1)
    }

    func canNavigate(to episode: Int) -> Bool {
        guard episode >= 1 else { return false }
        let limit = currentEpisodeLimit
        guard limit <= 0 || episode <= limit else { return false }

        if resolvedVideoFile(forEpisode: episode, mediaID: currentMediaID) != nil {
            return true
        }
        if videoMatchByFilename(forEpisode: episode) != nil {
            return true
        }
        return currentMediaID > 0 && onEpisodeChange != nil
    }

    func videoMatchByFilename(forEpisode episode: Int) -> (video: Videos, index: Int)? {
        guard !allVideos.isEmpty else { return nil }

        for (index, video) in allVideos.enumerated() {
            if TorrentBatchResolver.extractEpisodeNumber(from: video.videoName ?? "") == episode {
                return (video, index)
            }
        }

        guard allVideos.count > 1,
              let video = TorrentBatchResolver.selectByFilename(from: allVideos,
                                                                targetEpisode: episode,
                                                                name: { $0.videoName }),
              TorrentBatchResolver.extractEpisodeNumber(from: video.videoName ?? "") == episode,
              let index = allVideos.firstIndex(of: video) else {
            return nil
        }
        return (video, index)
    }

    var playlistIndex: Int {
        if let index = resolvedVideoFiles.firstIndex(where: { matchesVideo($0, fileIndex) }) {
            return index
        }
        return currentVideoIndex
    }

    var currentEpisodeLimit: Int {
        if let media = currentResolvedVideo?.media {
            return TorrentBatchResolver.episodes(for: media)
        }
        return totalEpisodes
    }

    var playlistVideos: [Videos] {
        if !resolvedVideoFiles.isEmpty {
            return resolvedVideoFiles.compactMap { videoMatch(for: $0)?.video }
        }
        return allVideos
    }

    /// options.svelte Playlist item and castplayer.svelte's Playlist dialog
    /// both call `selectFile(file)` — same underlying switch either way.
    func selectPlaylistVideo(_ video: Videos) {
        if let idx = allVideos.firstIndex(of: video), idx != currentVideoIndex {
            let targetEpisode = episodeNumber + (idx - currentVideoIndex)
            switchToVideo((video: video, index: idx), episode: targetEpisode)
        }
    }

    func matchesVideo(_ file: TorrentBatchResolver.ResolvedItem<Videos>, _ index: UInt) -> Bool {
        videoMatch(for: file)?.video.videoIndex?.uintValue == index
    }

    func videoMatch(for file: TorrentBatchResolver.ResolvedItem<Videos>) -> (video: Videos, index: Int)? {
        allVideos.enumerated().first { _, video in
            video.objectID == file.item.objectID
                || video.videoIndex == file.item.videoIndex
        }.map { ($0.element, $0.offset) }
    }

    func episodeNumber(for file: TorrentBatchResolver.ResolvedItem<Videos>) -> Int {
        file.episodeReference.intValue ?? episodeNumber
    }

    func switchToResolvedVideoFile(_ file: TorrentBatchResolver.ResolvedItem<Videos>) {
        guard let match = videoMatch(for: file) else { return }
        currentResolvedVideoFile = file
        switchToVideo(match, episode: episodeNumber(for: file), media: file.media)
    }

    /// Switches to a different video file within the same torrent batch.
    func switchToVideo(_ match: (video: Videos, index: Int), episode: Int, media: AnimeItem? = nil) {
        if media == nil {
            currentResolvedVideoFile = nil
        }
        currentVideoIndex = match.index
        videoEntity = match.video
        episodeNumber = episode
        if let media {
            anilistID = media.id
            totalEpisodes = TorrentBatchResolver.episodes(for: media)
        }
        if let idx = videoEntity?.videoIndex, idx.intValue >= 0 {
            fileIndex = UInt(idx.intValue)
            _ = videoService?.UpdateFilePathForFileIndex(fileIndex)
        }
        duration = 0; currentTime = 0
        loadCurrentVideo()
        scheduleHide()
    }

    /// Requests an episode change for an episode NOT in the current batch.
    /// The callback performs the web-equivalent `searchStore.set({ media, episode })`.
    func requestEpisodeChange(_ episode: Int, media: AnimeItem?) {
        onEpisodeChange?(episode, media ?? currentResolvedVideo?.media)
    }

    @objc func prevTapped() {
        navigateEpisode(by: -1)
    }

    @objc func nextTapped() {
        navigateEpisode(by: 1)
    }

    // Auto-plays next episode (Hayase web: next() called at EOF)
    func handleFileEnded() {
        guard Settings.playerAutoplay,
              !(MiniPlayerManager.shared.isActive && MiniPlayerManager.shared.activePlayer === self),
              (W2GLobby.shared.client?.peers.count ?? 2) > 1,
              let currentEpisode = currentEpisodeForNavigation,
              canNavigate(to: currentEpisode + 1) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.nextTapped() }
    }
}
