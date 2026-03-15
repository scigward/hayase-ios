import UIKit
import LibTorrent

final class VideoPlayerViewController: UIViewController {

    // MARK: - Input (set before presenting)

    var videoEntity: Videos?
    var torrentHandle: TorrentHandle?
    var videoService: VideoService?
    var fileIndex: UInt = 0
    var anilistID: Int = 0
    var episodeNumber: Int = 0
    var allVideos: [Videos] = []
    var currentVideoIndex: Int = 0

    // MARK: - Player components

    private let surface = MPVSurfaceView()

    // MARK: - Streaming

    private var streamer: TorrentStreamer?
    private var streamServer: LocalStreamServer?

    // MARK: - Overlay

    private let overlay       = UIView()
    private let topBar        = UIView()
    private let bottomBar     = UIView()

    // Top bar
    private let backButton    = UIButton(type: .system)
    private let titleLabel    = UILabel()
    private let statsLabel    = UILabel()

    // Bottom bar
    private let timeLabel     = UILabel()
    private let seekBar       = UISlider()
    private let durationLabel = UILabel()
    private let chapterLayer  = UIView()
    private let prevButton    = UIButton(type: .system)
    private let playPauseButton = UIButton(type: .system)
    private let nextButton    = UIButton(type: .system)
    private let optionsButton = UIButton(type: .system)

    // MARK: - State

    private var duration: Double = 0
    private var currentTime: Double = 0
    private var isPaused = false
    private var isSeeking = false
    private var tracks: [MPVTrack] = []
    private var chapters: [MPVChapter] = [] // Note: Streamyfin's renderer doesn't fetch chapters by default
    private var playbackRate: Double = 1.0
    private var subtitleDelay: Double = 0.0
    private var showRemainingTime = false
    private var controlsVisible = true
    private var hideWork: DispatchWorkItem?
    private var statsTimer: Timer?
    private var isEOFTriggered = false // Used to emulate the missing MPV_EVENT_END_FILE
    private var lastSeekTime: Date?    // Tracks last seek to prevent false EOF triggers

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupSurface()
        setupOverlay()
        setupGestures()
        
        surface.mpv.delegate = self
        loadCurrentVideo()
        scheduleHide()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateChapterMarkers()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        saveProgress()
        statsTimer?.invalidate()
        streamServer?.stop()
        streamer?.stop()
        surface.stop()
    }

    override var prefersStatusBarHidden: Bool              { !controlsVisible }
    override var preferredStatusBarUpdateAnimation: UIStatusBarAnimation { .fade }
    override var prefersHomeIndicatorAutoHidden: Bool      { !controlsVisible }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .landscape }
    override var shouldAutorotate: Bool                    { true }

    // MARK: - Surface setup

    private func setupSurface() {
        surface.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(surface)
        NSLayoutConstraint.activate([
            surface.topAnchor.constraint(equalTo: view.topAnchor),
            surface.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            surface.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            surface.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }

    // MARK: - Overlay setup

    private func setupOverlay() {
        overlay.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(overlay)
        NSLayoutConstraint.activate([
            overlay.topAnchor.constraint(equalTo: view.topAnchor),
            overlay.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            overlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        setupTopBar()
        setupBottomBar()
    }

    private func setupTopBar() {
        topBar.translatesAutoresizingMaskIntoConstraints = false
        topBar.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        overlay.addSubview(topBar)
        NSLayoutConstraint.activate([
            topBar.topAnchor.constraint(equalTo: view.topAnchor),
            topBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            topBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            topBar.heightAnchor.constraint(equalToConstant: 54),
        ])

        backButton.translatesAutoresizingMaskIntoConstraints = false
        backButton.setImage(UIImage(systemName: "chevron.left"), for: .normal)
        backButton.tintColor = .white
        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
        topBar.addSubview(backButton)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.textColor = .white
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textAlignment = .center
        titleLabel.text = videoEntity?.videoName ?? "Playing"
        topBar.addSubview(titleLabel)

        statsLabel.translatesAutoresizingMaskIntoConstraints = false
        statsLabel.textColor = .white
        statsLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        statsLabel.textAlignment = .right
        statsLabel.isHidden = true
        topBar.addSubview(statsLabel)

        NSLayoutConstraint.activate([
            backButton.leadingAnchor.constraint(equalTo: topBar.leadingAnchor, constant: 16),
            backButton.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            backButton.widthAnchor.constraint(equalToConstant: 44),
            backButton.heightAnchor.constraint(equalToConstant: 44),

            titleLabel.centerXAnchor.constraint(equalTo: topBar.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: backButton.trailingAnchor, constant: 8),

            statsLabel.trailingAnchor.constraint(equalTo: topBar.trailingAnchor, constant: -16),
            statsLabel.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            statsLabel.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 8),
        ])
    }

    private func setupBottomBar() {
        bottomBar.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        overlay.addSubview(bottomBar)
        NSLayoutConstraint.activate([
            bottomBar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            bottomBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        timeLabel.translatesAutoresizingMaskIntoConstraints = false
        timeLabel.textColor = .white
        timeLabel.font = .monospacedSystemFont(ofSize: 13, weight: .medium)
        timeLabel.text = "0:00"
        timeLabel.isUserInteractionEnabled = true
        timeLabel.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(toggleTimeFormat)))
        bottomBar.addSubview(timeLabel)

        seekBar.translatesAutoresizingMaskIntoConstraints = false
        seekBar.minimumValue = 0
        seekBar.maximumValue = 1
        seekBar.minimumTrackTintColor = .white
        seekBar.maximumTrackTintColor = UIColor.white.withAlphaComponent(0.3)
        seekBar.setThumbImage(circleThumb(diameter: 14), for: .normal)
        seekBar.addTarget(self, action: #selector(seekBegan),   for: .touchDown)
        seekBar.addTarget(self, action: #selector(seekChanged), for: .valueChanged)
        seekBar.addTarget(self, action: #selector(seekEnded),   for: [.touchUpInside, .touchUpOutside])
        bottomBar.addSubview(seekBar)

        chapterLayer.translatesAutoresizingMaskIntoConstraints = false
        chapterLayer.isUserInteractionEnabled = false
        bottomBar.addSubview(chapterLayer)

        durationLabel.translatesAutoresizingMaskIntoConstraints = false
        durationLabel.textColor = UIColor.white.withAlphaComponent(0.7)
        durationLabel.font = .monospacedSystemFont(ofSize: 13, weight: .medium)
        durationLabel.text = "0:00"
        bottomBar.addSubview(durationLabel)

        [prevButton, playPauseButton, nextButton, optionsButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            $0.tintColor = .white
        }
        prevButton.setImage(UIImage(systemName: "backward.end.fill"),  for: .normal)
        playPauseButton.setImage(UIImage(systemName: "pause.fill"),    for: .normal)
        nextButton.setImage(UIImage(systemName: "forward.end.fill"),   for: .normal)
        optionsButton.setImage(UIImage(systemName: "ellipsis.circle"), for: .normal)

        prevButton.addTarget(self,    action: #selector(prevTapped),      for: .touchUpInside)
        playPauseButton.addTarget(self, action: #selector(playPauseTapped), for: .touchUpInside)
        nextButton.addTarget(self,    action: #selector(nextTapped),      for: .touchUpInside)
        optionsButton.addTarget(self, action: #selector(optionsTapped),   for: .touchUpInside)

        prevButton.isEnabled    = allVideos.count > 1 && currentVideoIndex > 0
        nextButton.isEnabled    = allVideos.count > 1 && currentVideoIndex < allVideos.count - 1

        let btnStack = UIStackView(arrangedSubviews: [prevButton, playPauseButton, nextButton])
        btnStack.translatesAutoresizingMaskIntoConstraints = false
        btnStack.axis = .horizontal
        btnStack.spacing = 36
        bottomBar.addSubview(btnStack)
        bottomBar.addSubview(optionsButton)

        NSLayoutConstraint.activate([
            timeLabel.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor, constant: 14),
            timeLabel.topAnchor.constraint(equalTo: bottomBar.topAnchor, constant: 10),

            seekBar.leadingAnchor.constraint(equalTo: timeLabel.trailingAnchor, constant: 8),
            seekBar.trailingAnchor.constraint(equalTo: durationLabel.leadingAnchor, constant: -8),
            seekBar.centerYAnchor.constraint(equalTo: timeLabel.centerYAnchor),

            chapterLayer.leadingAnchor.constraint(equalTo: seekBar.leadingAnchor),
            chapterLayer.trailingAnchor.constraint(equalTo: seekBar.trailingAnchor),
            chapterLayer.centerYAnchor.constraint(equalTo: seekBar.centerYAnchor),
            chapterLayer.heightAnchor.constraint(equalToConstant: 4),

            durationLabel.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor, constant: -14),
            durationLabel.centerYAnchor.constraint(equalTo: timeLabel.centerYAnchor),

            btnStack.centerXAnchor.constraint(equalTo: bottomBar.centerXAnchor),
            btnStack.topAnchor.constraint(equalTo: seekBar.bottomAnchor, constant: 6),
            btnStack.bottomAnchor.constraint(equalTo: bottomBar.bottomAnchor, constant: -10),
            btnStack.heightAnchor.constraint(equalToConstant: 44),

            optionsButton.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor, constant: -14),
            optionsButton.centerYAnchor.constraint(equalTo: btnStack.centerYAnchor),
            optionsButton.widthAnchor.constraint(equalToConstant: 44),
            optionsButton.heightAnchor.constraint(equalToConstant: 44),
        ])
    }

    private func setupGestures() {
        let singleTap = UITapGestureRecognizer(target: self, action: #selector(surfaceTapped))
        singleTap.numberOfTapsRequired = 1
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(playPauseTapped))
        doubleTap.numberOfTapsRequired = 2
        singleTap.require(toFail: doubleTap)
        surface.addGestureRecognizer(singleTap)
        surface.addGestureRecognizer(doubleTap)
    }

    // MARK: - Video loading

    private func loadCurrentVideo() {
        guard let entity = videoEntity else { return }
        let path = entity.videoPath ?? ""
        guard !path.isEmpty else { return }
        
        // Reset states for new file
        isEOFTriggered = false
        chapters.removeAll()
        updateChapterMarkers()

        // Set up torrent streaming if the file is still downloading.
        setupStreamer()

        // If streaming, wait for head pieces on a background thread before
        // loading the URL.
        // must be on disk so MPV can parse immediately.
        if let currentStreamer = streamer, currentStreamer.isActive {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let ready = currentStreamer.waitForMetadataPieces(timeout: 30)
                if !ready {
                    print("VideoPlayerViewController: metadata wait timed out; continuing anyway")
                }
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    guard self.streamer === currentStreamer else { return }
                    self.loadVideoURL()
                }
            }
        } else {
            // File fully downloaded or streaming not needed — load immediately.
            loadVideoURL()
        }
    }

    /// Builds the URL and preset, loads the video into MPV, and starts stats.
    /// Separated from loadCurrentVideo() so it can be called after an async
    /// metadata pre-wait without duplicating the URL-building logic.
    private func loadVideoURL() {
        guard let entity = videoEntity else { return }
        let path = entity.videoPath ?? ""
        guard !path.isEmpty else { return }

        let url: URL
        let preset: PlayerPreset
        if let server = streamServer {
            // Streaming: serve the file via local HTTP so MPV handles
            // buffering and seeking natively. The server blocks responses
            // until the required pieces are downloaded.
            url = server.url
            // Enable MPV's stream cache for the HTTP stream. Without this,
            // MPV reads synchronously and can't buffer ahead, causing stalls.
            // These are set per-load so they don't affect local file playback.
            preset = PlayerPreset(commands: [
                ["set", "cache", "yes"],
                ["set", "cache-secs", "120"],
                ["set", "cache-pause-wait", "3"],
                ["set", "demuxer-max-bytes", "150MiB"],
                ["set", "demuxer-max-back-bytes", "50MiB"],
                ["set", "network-timeout", "120"],
            ])
        } else if path.starts(with: "http") {
            url = URL(string: path)!
            preset = PlayerPreset()
        } else {
            url = URL(fileURLWithPath: path)
            // Reset cache options in case they were set by a previous streaming load.
            preset = PlayerPreset(commands: [
                ["set", "cache", "no"],
            ])
        }

        surface.mpv.load(url: url, with: preset)
        
        titleLabel.text = entity.videoName ?? "Episode \(episodeNumber)"
        prevButton.isEnabled = currentVideoIndex > 0
        nextButton.isEnabled = currentVideoIndex < allVideos.count - 1
        restoreProgress(path: path)
        startStatsTimer()
    }

    private func restoreProgress(path: String) {
        guard let saved = WatchProgressService.shared.getProgress(videoPath: path),
              saved.isInProgress, saved.currentTime > 5 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.lastSeekTime = Date()
            self?.surface.mpv.seek(to: saved.currentTime)
        }
    }

    // MARK: - Streaming setup

    /// Creates a TorrentStreamer and LocalStreamServer for the active file
    /// if the torrent is still downloading. The streamer manages piece deadlines
    /// for proactive prefetching. The HTTP server serves the file to MPV,
    /// blocking byte-range responses until the required pieces are downloaded.
    /// This lets MPV handle buffering and seeking natively — no polling needed.
    private func setupStreamer() {
        // Stop any previous streamer / server
        streamServer?.stop()
        streamServer = nil
        streamer?.stop()
        streamer = nil

        guard let handle = torrentHandle else { return }
        // Only create a streamer when the file is not yet fully downloaded.
        // Use byte-level file progress (entry.downloaded >= entry.size) which
        // is accurate regardless of piece priority settings.
        guard !isFileFullyDownloaded() else { return }

        let s = TorrentStreamer(torrentHandle: handle, fileIndex: fileIndex)
        s.start()
        streamer = s

        // Start a local HTTP server so MPV reads from HTTP instead of a
        // file with holes. The server gates responses on piece availability.
        let path = videoEntity?.videoPath ?? ""
        guard !path.isEmpty else { return }

        let server = LocalStreamServer(torrentHandle: handle, fileIndex: fileIndex, filePath: path)
        do {
            try server.start()
            streamServer = server
            print("LocalStreamServer: started for file \(fileIndex) at \(server.url)")
        } catch {
            print("LocalStreamServer: failed to start — \(error)")
            // Fall back to direct file path (original behavior)
        }
    }

    // MARK: - Download stats

    private func startStatsTimer() {
        statsTimer?.invalidate()
        guard torrentHandle != nil else { return }
        guard !isFileFullyDownloaded() else { return }
        statsLabel.isHidden = false
        updateStats()
        statsTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.updateStats()
        }
    }

    private func updateStats() {
        guard let handle = torrentHandle else { return }
        let snap = handle.snapshot
        // Use byte-level file progress instead of snap.progress, which only
        // counts "wanted" pieces. Since TorrentStreamer sets most pieces to
        // priority 0, snap.progress can falsely report 1.0 when only a few
        // pieces are downloaded — causing the streamer to be stopped and
        // all subsequent seeks to fail (no pieces requested).
        if isFileFullyDownloaded() {
            statsTimer?.invalidate()
            statsLabel.isHidden = true
            // Stop the streamer — piece management is no longer needed.
            // Do NOT stop streamServer here: MPV is still reading from the
            // HTTP URL. Stopping the server mid-playback causes read errors
            // and playback failure. The server is stopped in viewWillDisappear
            // and prev/next episode transitions.
            streamer?.stop()
            streamer = nil
            return
        }
        let speed = fmtSpeed(snap.downloadRate)
        // Show file-level download fraction for accurate progress display.
        let fileFraction: Double
        if let entry = snap.files.first(where: { $0.index == Int(self.fileIndex) }), entry.size > 0 {
            fileFraction = Double(entry.downloaded) / Double(entry.size)
        } else {
            fileFraction = Double(snap.progress)
        }
        // When streaming, show buffer seconds ahead of playback.
        if let s = streamer, s.isActive, duration > 0 {
            let fraction = currentTime / duration
            let bufSec = s.bufferedSeconds(fromFraction: fraction, videoDuration: duration)
            statsLabel.text = "↓ \(speed)  buf \(String(format: "%.0fs", bufSec))  \(String(format: "%.1f%%", fileFraction * 100))"
        } else {
            statsLabel.text = "↓ \(speed)  \(String(format: "%.1f%%", fileFraction * 100))"
        }
    }

    private func fmtSpeed(_ bps: UInt64) -> String {
        if bps == 0            { return "0 B/s" }
        if bps >= 1_073_741_824 { return String(format: "%.1f GB/s", Double(bps) / 1_073_741_824) }
        if bps >= 1_048_576    { return String(format: "%.1f MB/s", Double(bps) / 1_048_576) }
        if bps >= 1_024        { return String(format: "%.0f KB/s", Double(bps) / 1_024) }
        return "\(bps) B/s"
    }

    /// Checks whether the target file is fully downloaded using byte-level
    /// progress from libtorrent's file_progress(). This is immune to the
    /// "wanted pieces" issue where snap.progress falsely reports 1.0 when
    /// TorrentStreamer has set most pieces to priority 0.
    private func isFileFullyDownloaded() -> Bool {
        guard let handle = torrentHandle else { return true }
        handle.updateSnapshot()
        let snap = handle.snapshot
        // isSeed means the entire torrent is downloaded — always reliable.
        if snap.isSeed { return true }
        // Check byte-level progress for the specific file we're playing.
        if let entry = snap.files.first(where: { $0.index == Int(self.fileIndex) }) {
            return entry.size > 0 && entry.downloaded >= entry.size
        }
        return false
    }

    // MARK: - Watch progress

    private func saveProgress() {
        guard let path = videoEntity?.videoPath, duration > 0 else { return }
        WatchProgressService.shared.setProgress(
            videoPath: path, anilistID: anilistID, episode: episodeNumber,
            currentTime: currentTime, duration: duration)
    }

    // MARK: - Controls visibility

    private func scheduleHide() {
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.setControls(visible: false) }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
    }

    private func setControls(visible: Bool) {
        controlsVisible = visible
        UIView.animate(withDuration: 0.25) { self.overlay.alpha = visible ? 1 : 0 }
        setNeedsStatusBarAppearanceUpdate()
        setNeedsUpdateOfHomeIndicatorAutoHidden()
        if visible { scheduleHide() }
    }

    // MARK: - Time UI

    private func updateTimeUI() {
        guard !isSeeking else { return }
        seekBar.value = duration > 0 ? Float(currentTime / duration) : 0
        timeLabel.text = showRemainingTime
            ? "-" + fmtTime(max(0, duration - currentTime))
            : fmtTime(currentTime)
        durationLabel.text = fmtTime(duration)
    }

    private func fmtTime(_ secs: Double) -> String {
        let s = max(0, Int(secs))
        let h = s / 3600; let m = (s % 3600) / 60; let sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec)
                     : String(format: "%d:%02d", m, sec)
    }

    private func updateChapterMarkers() {
        chapterLayer.subviews.forEach { $0.removeFromSuperview() }
        guard duration > 0, chapterLayer.bounds.width > 0 else { return }
        for ch in chapters {
            let x = CGFloat(ch.time / duration) * chapterLayer.bounds.width
            let tick = UIView(frame: CGRect(x: x - 1, y: 0, width: 2, height: 4))
            tick.backgroundColor = UIColor.white.withAlphaComponent(0.8)
            chapterLayer.addSubview(tick)
        }
    }

    private func circleThumb(diameter: CGFloat) -> UIImage {
        let r = UIGraphicsImageRenderer(size: CGSize(width: diameter, height: diameter))
        return r.image { ctx in
            UIColor.white.setFill()
            ctx.cgContext.fillEllipse(in: CGRect(x: 0, y: 0, width: diameter, height: diameter))
        }
    }

    // MARK: - Actions

    @objc private func backTapped() {
        saveProgress()
        dismiss(animated: true)
    }

    @objc private func surfaceTapped() {
        setControls(visible: !controlsVisible)
    }

    @objc private func playPauseTapped() {
        surface.mpv.togglePause()
        if !controlsVisible { setControls(visible: true) } else { scheduleHide() }
    }

    @objc private func prevTapped() {
        guard currentVideoIndex > 0 else { return }
        saveProgress()
        streamServer?.stop()
        streamServer = nil
        streamer?.stop()
        streamer = nil
        currentVideoIndex -= 1
        videoEntity = allVideos[currentVideoIndex]
        episodeNumber = currentVideoIndex + 1
        if let idx = videoEntity?.videoIndex {
            fileIndex = UInt(idx.intValue)
            videoService?.selectFileForStreaming(fileIndex)
            videoService?.UpdateFilePathForFileIndex(fileIndex)
        }
        duration = 0; currentTime = 0
        loadCurrentVideo()
        scheduleHide()
    }

    @objc private func nextTapped() {
        guard currentVideoIndex < allVideos.count - 1 else { return }
        saveProgress()
        streamServer?.stop()
        streamServer = nil
        streamer?.stop()
        streamer = nil
        currentVideoIndex += 1
        videoEntity = allVideos[currentVideoIndex]
        episodeNumber = currentVideoIndex + 1
        if let idx = videoEntity?.videoIndex {
            fileIndex = UInt(idx.intValue)
            videoService?.selectFileForStreaming(fileIndex)
            videoService?.UpdateFilePathForFileIndex(fileIndex)
        }
        duration = 0; currentTime = 0
        loadCurrentVideo()
        scheduleHide()
    }

    @objc private func toggleTimeFormat() {
        showRemainingTime.toggle()
        updateTimeUI()
    }

    @objc private func seekBegan() {
        isSeeking = true
        hideWork?.cancel()
    }

    @objc private func seekChanged() {
        let t = Double(seekBar.value) * duration
        timeLabel.text = showRemainingTime ? "-" + fmtTime(max(0, duration - t)) : fmtTime(t)
    }

    @objc private func seekEnded() {
        let seekFraction = Double(seekBar.value)
        isSeeking = false
        lastSeekTime = Date()

        // Tell the streamer to prioritize pieces at the new position.
        // The HTTP server will block MPV's byte-range requests until
        // the required pieces are downloaded, so we can seek immediately.
        streamer?.seekTo(fraction: seekFraction)
        surface.mpv.seek(to: seekFraction * duration)
        scheduleHide()
    }

    @objc private func optionsTapped() {
        hideWork?.cancel()
        showOptionsSheet()
    }

    // MARK: - Options sheet

    private func showOptionsSheet() {
        let sheet = UIAlertController(title: "Options", message: nil, preferredStyle: .actionSheet)

        let subs = tracks.filter { $0.type == "sub" }
        if !subs.isEmpty {
            sheet.addAction(UIAlertAction(title: "Subtitles", style: .default) { [weak self] _ in
                self?.showTrackPicker(type: "sub", tracks: subs)
            })
        }

        let audio = tracks.filter { $0.type == "audio" }
        if audio.count > 1 {
            sheet.addAction(UIAlertAction(title: "Audio Track", style: .default) { [weak self] _ in
                self?.showTrackPicker(type: "audio", tracks: audio)
            })
        }

        sheet.addAction(UIAlertAction(title: "Speed: \(String(format: "%gx", playbackRate))", style: .default) { [weak self] _ in
            self?.showSpeedPicker()
        })

        // NOTE: Streamyfin's renderer doesn't expose setProperty publicly.
        // If you make commandSync / setProperty public in MPVLayerRenderer, you can uncomment these.
        /*
        sheet.addAction(UIAlertAction(title: "Sub Delay: \(String(format: "%.1fs", subtitleDelay))", style: .default) { [weak self] _ in
            self?.showSubDelayAlert()
        })
         
        sheet.addAction(UIAlertAction(title: "Screenshot", style: .default) { [weak self] _ in
             // Requires adding a public screenshot() func to MPVLayerRenderer calling: commandSync(handle, ["screenshot", "subtitles"])
             self?.scheduleHide()
        })
        */

        if !chapters.isEmpty {
            sheet.addAction(UIAlertAction(title: "Chapters", style: .default) { [weak self] _ in
                self?.showChapterPicker()
            })
        }

        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in
            self?.scheduleHide()
        })

        if let pop = sheet.popoverPresentationController {
            pop.sourceView = optionsButton
            pop.sourceRect = optionsButton.bounds
        }
        present(sheet, animated: true)
    }

    private func showTrackPicker(type: String, tracks: [MPVTrack]) {
        let title = type == "sub" ? "Subtitles" : "Audio"
        let picker = UIAlertController(title: title, message: nil, preferredStyle: .actionSheet)
        if type == "sub" {
            picker.addAction(UIAlertAction(title: "Off", style: .default) { [weak self] _ in
                self?.surface.mpv.setSubtitleTrack(0)
                self?.scheduleHide()
            })
        }
        for track in tracks {
            let mark = track.isSelected ? "✓ " : ""
            picker.addAction(UIAlertAction(title: mark + track.displayName, style: .default) { [weak self] _ in
                if type == "sub" { self?.surface.mpv.setSubtitleTrack(track.id) }
                else             { self?.surface.mpv.setAudioTrack(track.id) }
                self?.scheduleHide()
            })
        }
        picker.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in self?.scheduleHide() })
        popoverCentre(picker)
        present(picker, animated: true)
    }

    private func showSpeedPicker() {
        let speeds: [(String, Double)] = [
            ("0.5×", 0.5), ("0.75×", 0.75), ("1×", 1.0),
            ("1.25×", 1.25), ("1.5×", 1.5), ("2×", 2.0),
        ]
        let picker = UIAlertController(title: "Playback Speed", message: nil, preferredStyle: .actionSheet)
        for (label, rate) in speeds {
            let mark = rate == playbackRate ? "✓ " : ""
            picker.addAction(UIAlertAction(title: mark + label, style: .default) { [weak self] _ in
                self?.playbackRate = rate
                self?.surface.mpv.setSpeed(rate) // Adapted to use setSpeed
                self?.scheduleHide()
            })
        }
        picker.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in self?.scheduleHide() })
        popoverCentre(picker)
        present(picker, animated: true)
    }

    private func showChapterPicker() {
        let picker = UIAlertController(title: "Chapters", message: nil, preferredStyle: .actionSheet)
        for ch in chapters {
            picker.addAction(UIAlertAction(title: "\(fmtTime(ch.time))  \(ch.title)", style: .default) { [weak self] _ in
                self?.surface.mpv.seek(to: ch.time)
                self?.scheduleHide()
            })
        }
        picker.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in self?.scheduleHide() })
        popoverCentre(picker)
        present(picker, animated: true)
    }

    private func popoverCentre(_ vc: UIAlertController) {
        if let pop = vc.popoverPresentationController {
            pop.sourceView = view
            pop.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
            pop.permittedArrowDirections = []
        }
    }
    
    // Auto-plays next episode
    private func handleFileEnded() {
        guard currentVideoIndex < allVideos.count - 1 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.nextTapped() }
    }
}

// MARK: - MPVWrapperDelegate Integration

extension VideoPlayerViewController: MPVWrapperDelegate {

    func renderer(_ renderer: MPVWrapper, didUpdatePosition position: Double, duration: Double, cacheSeconds: Double) {
        self.currentTime = position
        self.duration    = duration
        updateTimeUI()

        // Feed playback position to the streamer so it can set piece deadlines
        // ahead of the current position. Pass duration so the streamer can check
        // whether the buffer is already sufficient and skip unnecessary requests.
        if duration > 0 {
            streamer?.updatePlaybackPosition(fraction: position / duration, videoDuration: duration)
        }
        
        // Emulating EOF (Streamyfin's renderer doesn't natively expose an EOF event).
        // Guard against false EOF triggers after a seek: when the server serves
        // partially-downloaded data, MPV may briefly report a position near the
        // end of the file before settling at the correct position. A 5-second
        // cooldown after the last seek prevents this from triggering handleFileEnded().
        let seekCooldownActive: Bool
        if let seekTime = lastSeekTime {
            seekCooldownActive = Date().timeIntervalSince(seekTime) < 5.0
        } else {
            seekCooldownActive = false
        }
        if duration > 0 && position > 0 && position >= duration - 0.5 && !seekCooldownActive {
            if !isEOFTriggered {
                isEOFTriggered = true
                handleFileEnded()
            }
        } else if position < duration - 1.0 {
            isEOFTriggered = false
        }
    }

    func renderer(_ renderer: MPVWrapper, didChangePause isPaused: Bool) {
        self.isPaused = isPaused
        playPauseButton.setImage(UIImage(systemName: isPaused ? "play.fill" : "pause.fill"), for: .normal)
        if isPaused { hideWork?.cancel(); setControls(visible: true) }
    }

    func renderer(_ renderer: MPVWrapper, didChangeLoading isLoading: Bool) {
        // Option to add a UIActivityIndicatorView here
    }

    func renderer(_ renderer: MPVWrapper, didBecomeReadyToSeek: Bool) {
        // Video is completely loaded into memory
    }

    func renderer(_ renderer: MPVWrapper, didBecomeTracksReady: Bool) {
        // Map the [[String: Any]] Dictionaries from Streamyfin into native Swift Structs
        var newTracks: [MPVTrack] = []
        
        for s in renderer.getSubtitleTracks() {
            if let id = s["id"] as? Int {
                newTracks.append(MPVTrack(id: id, type: "sub", title: s["title"] as? String, lang: s["lang"] as? String, isSelected: s["selected"] as? Bool ?? false))
            }
        }
        for a in renderer.getAudioTracks() {
            if let id = a["id"] as? Int {
                newTracks.append(MPVTrack(id: id, type: "audio", title: a["title"] as? String, lang: a["lang"] as? String, isSelected: a["selected"] as? Bool ?? false))
            }
        }
        self.tracks = newTracks
    }

    func renderer(_ renderer: MPVWrapper, didSelectAudioOutput audioOutput: String) { }
}