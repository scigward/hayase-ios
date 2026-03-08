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
    private var chapters: [MPVChapter] = []
    private var playbackRate: Double = 1.0
    private var subtitleDelay: Double = 0.0
    private var showRemainingTime = false
    private var controlsVisible = true
    private var hideWork: DispatchWorkItem?
    private var statsTimer: Timer?

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

        // Time label (tap to toggle remaining)
        timeLabel.translatesAutoresizingMaskIntoConstraints = false
        timeLabel.textColor = .white
        timeLabel.font = .monospacedSystemFont(ofSize: 13, weight: .medium)
        timeLabel.text = "0:00"
        timeLabel.isUserInteractionEnabled = true
        timeLabel.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(toggleTimeFormat)))
        bottomBar.addSubview(timeLabel)

        // Seekbar
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

        // Chapter tick marks overlay
        chapterLayer.translatesAutoresizingMaskIntoConstraints = false
        chapterLayer.isUserInteractionEnabled = false
        bottomBar.addSubview(chapterLayer)

        // Duration label
        durationLabel.translatesAutoresizingMaskIntoConstraints = false
        durationLabel.textColor = UIColor.white.withAlphaComponent(0.7)
        durationLabel.font = .monospacedSystemFont(ofSize: 13, weight: .medium)
        durationLabel.text = "0:00"
        bottomBar.addSubview(durationLabel)

        // Buttons
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
        surface.mpv.loadFile(path)
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
            self?.surface.mpv.seek(to: saved.currentTime)
        }
    }

    // MARK: - Download stats

    private func startStatsTimer() {
        statsTimer?.invalidate()
        guard let handle = torrentHandle else { return }
        let snap = handle.snapshot
        guard !snap.isFinished, !snap.isSeed, snap.progress < 1.0 else { return }
        statsLabel.isHidden = false
        updateStats()
        statsTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.updateStats()
        }
    }

    private func updateStats() {
        guard let handle = torrentHandle else { return }
        let snap = handle.snapshot
        if snap.isFinished || snap.isSeed || snap.progress >= 1.0 {
            statsTimer?.invalidate()
            statsLabel.isHidden = true
            return
        }
        let speed = fmtSpeed(snap.downloadRate)
        statsLabel.text = "↓ \(speed)  \(String(format: "%.1f%%", snap.progress * 100))"
    }

    private func fmtSpeed(_ bps: UInt64) -> String {
        if bps == 0            { return "0 B/s" }
        if bps >= 1_073_741_824 { return String(format: "%.1f GB/s", Double(bps) / 1_073_741_824) }
        if bps >= 1_048_576    { return String(format: "%.1f MB/s", Double(bps) / 1_048_576) }
        if bps >= 1_024        { return String(format: "%.0f KB/s", Double(bps) / 1_024) }
        return "\(bps) B/s"
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
        surface.mpv.seek(to: Double(seekBar.value) * duration)
        isSeeking = false
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

        sheet.addAction(UIAlertAction(title: "Sub Delay: \(String(format: "%.1fs", subtitleDelay))", style: .default) { [weak self] _ in
            self?.showSubDelayAlert()
        })

        if !chapters.isEmpty {
            sheet.addAction(UIAlertAction(title: "Chapters", style: .default) { [weak self] _ in
                self?.showChapterPicker()
            })
        }

        sheet.addAction(UIAlertAction(title: "Screenshot", style: .default) { [weak self] _ in
            self?.surface.mpv.screenshot()
            self?.scheduleHide()
        })

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
                self?.surface.mpv.setPlaybackRate(rate)
                self?.scheduleHide()
            })
        }
        picker.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in self?.scheduleHide() })
        popoverCentre(picker)
        present(picker, animated: true)
    }

    private func showSubDelayAlert() {
        let alert = UIAlertController(
            title: "Subtitle Delay",
            message: "Current: \(String(format: "%.1f", subtitleDelay))s  (negative = earlier)",
            preferredStyle: .alert)
        alert.addTextField { tf in
            tf.keyboardType = .decimalPad
            tf.text = String(format: "%.1f", self.subtitleDelay)
        }
        alert.addAction(UIAlertAction(title: "Apply", style: .default) { [weak self, weak alert] _ in
            if let text = alert?.textFields?.first?.text, let val = Double(text) {
                self?.subtitleDelay = val
                self?.surface.mpv.setSubtitleDelay(val)
            }
            self?.scheduleHide()
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in self?.scheduleHide() })
        present(alert, animated: true)
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
}

// MARK: - MPVWrapperDelegate

extension VideoPlayerViewController: MPVWrapperDelegate {

    func mpvTimeUpdated(current: Double, duration: Double) {
        self.currentTime = current
        self.duration    = duration
        updateTimeUI()
    }

    func mpvPauseChanged(_ isPaused: Bool) {
        self.isPaused = isPaused
        playPauseButton.setImage(UIImage(systemName: isPaused ? "play.fill" : "pause.fill"), for: .normal)
        if isPaused { hideWork?.cancel(); setControls(visible: true) }
    }

    func mpvFileEnded() {
        guard currentVideoIndex < allVideos.count - 1 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.nextTapped() }
    }

    func mpvTracksChanged(_ tracks: [MPVTrack]) {
        self.tracks = tracks
    }

    func mpvChaptersChanged(_ chapters: [MPVChapter]) {
        self.chapters = chapters
        updateChapterMarkers()
    }
}
