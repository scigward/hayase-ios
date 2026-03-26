import UIKit
import AVKit
import CoreMedia
import LibTorrent

// MARK: - FatSlider

/// UISlider subclass with a larger touch target so the seekbar is easier to hit.
private final class FatSlider: UISlider {
    /// Extra vertical padding (each side) added to the slider's touch area.
    private let verticalHitPadding: CGFloat = 20

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        let expanded = bounds.insetBy(dx: 0, dy: -verticalHitPadding)
        return expanded.contains(point)
    }
}

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

    /// Callback fired when the user taps next/prev and the target episode is
    /// NOT in the current torrent batch. The presenting view controller should
    /// dismiss the player and initiate a new extension search for `episode`.
    /// Mirrors Hayase web's `playEpisode()` → `searchStore.set({ media, episode })`.
    var onEpisodeChange: ((_ episode: Int) -> Void)?

    /// Total number of episodes for this anime (from AniList metadata).
    /// Used to determine whether next/prev buttons should be enabled when the
    /// target episode is outside the current `allVideos` batch.
    var totalEpisodes: Int = 0

    // MARK: - Player components

    private let surface = MPVSurfaceView()
    /// System PiP controller (streamyfin). Provides the native iOS
    /// Picture-in-Picture window when the app goes to background.
    /// Stored as `Any?` because PiPController requires iOS 15+.
    private var _pipController: Any?

    @available(iOS 15.0, *)
    private var pipController: PiPController? {
        get { _pipController as? PiPController }
        set { _pipController = newValue }
    }

    // MARK: - Streaming

    private var streamer: TorrentStreamer?
    private var streamServer: LocalStreamServer?

    // MARK: - Overlay

    private let overlay       = UIView()
    private let bottomBar     = UIView()
    private let bottomGradient = CAGradientLayer()
    private let logOverlay    = LogOverlayView()

    // Floating back button (top-left, no background bar — matches Hayase)
    private let backButton    = UIButton(type: .system)

    // Hayase downloadstats.svelte — floating HUD at top center
    private let statsHUD      = UILabel()

    // Bottom bar — above seekbar row
    private let titleLabel    = UILabel()
    private let episodeLabel  = UILabel()   // Hayase episodesmodal.svelte: session.description below title
    private let chapterLabel  = UILabel()
    private let timeLabel     = UILabel()

    // Bottom bar — seekbar row
    private let seekBar       = FatSlider()
    private let chapterLayer  = UIView()

    // Bottom bar — controls row
    private let prevButton      = UIButton(type: .system)
    private let playPauseButton = UIButton(type: .system)
    private let nextButton      = UIButton(type: .system)
    private let speedLabel      = UILabel()
    private let optionsButton   = UIButton(type: .system)
    private let airPlayPicker   = AVRoutePickerView()

    // MARK: - State

    private var duration: Double = 0
    private var currentTime: Double = 0
    private(set) var isPaused = false
    /// Tracks whether the pause was explicitly requested by the user (tap on
    /// play/pause button) rather than caused by MPV (e.g. buffer underrun).
    /// Note: we no longer fully pause the torrent — downloading continues at
    /// reduced effective speed (no active deadline boosting) to match Hayase
    /// behavior and avoid blocking LocalStreamServer.waitForLocalPieces().
    private var userRequestedPause = false
    /// Matches Hayase player.svelte: prevents duplicate tracking calls.
    private var trackingCompleted = false
    private var isSeeking = false
    private var tracks: [MPVTrack] = []
    private var chapters: [MPVChapter] = [] // Note: Streamyfin's renderer doesn't fetch chapters by default
    private var playbackRate: Double = 1.0
    private var subtitleDelay: Double = 0.0
    private var showRemainingTime = false
    private var controlsVisible = true
    private var hideWork: DispatchWorkItem?
    /// The double-tap recognizer, stored so single-tap can require(toFail:) it.
    private var doubleTapRecognizer: UITapGestureRecognizer?
    private var statsTimer: Timer?
    private var isEOFTriggered = false // Used to emulate the missing MPV_EVENT_END_FILE
    private var lastSeekTime: Date?    // Tracks last seek to prevent false EOF triggers
    /// Pending playback position (seconds) to restore once MPV reports a valid
    /// duration. Using a stored value + event-driven trigger instead of a fixed
    /// delay ensures the seek works for both local files and HTTP streams (where
    /// MPV can take several seconds to buffer enough data to start playback).
    private var pendingRestoreTime: Double?
    /// True while the player is being minimized to in-app PiP. Prevents
    /// viewWillDisappear from tearing down the streaming pipeline.
    var isMinimizing = false

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupSurface()
        setupOverlay()
        setupGestures()
        
        surface.mpv.delegate = self
        ExternalDisplayManager.shared.register(self)

        // System PiP (streamyfin): create the AVPictureInPictureController
        // backed by the same AVSampleBufferDisplayLayer that MPV renders to.
        if #available(iOS 15.0, *) {
            let pip = PiPController(sampleBufferDisplayLayer: surface.displayLayer)
            pip.delegate = self
            self.pipController = pip
        }

        loadCurrentVideo()
        scheduleHide()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateChapterMarkers()
        // Apply gradient to bottom bar (Hayase gradient: black → transparent)
        bottomGradient.frame = bottomBar.bounds
        if bottomGradient.superlayer == nil {
            bottomGradient.colors = [
                UIColor.clear.cgColor,
                UIColor.black.withAlphaComponent(0.7).cgColor,
                UIColor.black.withAlphaComponent(0.85).cgColor,
            ]
            bottomGradient.locations = [0.0, 0.35, 1.0]
            bottomBar.layer.insertSublayer(bottomGradient, at: 0)
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // Don't tear down when minimizing to in-app PiP — the video keeps
        // playing in the mini-player (Hayase wrapper.svelte keeps the player
        // component mounted when navigating away from /app/player).
        guard !isMinimizing else { return }
        // Don't tear down while system PiP is active — the user may return
        // via the PiP restore button.
        if #available(iOS 15.0, *) {
            guard !(pipController?.isPictureInPictureActive ?? false) else { return }
        }
        tearDownPlayer()
    }

    /// Tears down all player resources. Called from viewWillDisappear when
    /// NOT minimizing, and from MiniPlayerManager when the user closes the
    /// mini-player.
    func tearDownPlayer() {
        saveProgress()
        MiniPlayerManager.shared.clearSessionStateIfNeeded(for: self)
        if #available(iOS 15.0, *) {
            pipController?.stopPictureInPicture()
        }
        statsTimer?.invalidate()
        ExternalDisplayManager.shared.unregister(self)
        streamServer?.stop()
        streamer?.stop()
        surface.stop()
        // Nil out references so no timer or callback can touch the handle
        // after the torrent is removed from the session (use-after-free).
        streamer = nil
        streamServer = nil
        torrentHandle = nil
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

        // Floating back button — top-left, no background bar (Hayase style)
        setupBackButton()
        // Download stats — top center (Hayase downloadstats.svelte)
        setupStatsHUD()
        // Bottom overlay with gradient
        setupBottomBar()

        // Log overlay — shows streaming errors/warnings at the bottom-left.
        // Tap to expand, long-press to copy all logs to clipboard.
        logOverlay.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(logOverlay)
        NSLayoutConstraint.activate([
            logOverlay.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 8),
            logOverlay.bottomAnchor.constraint(equalTo: bottomBar.topAnchor, constant: -8),
            logOverlay.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, multiplier: 0.5),
        ])
    }

    /// Floating back button at top-left (no top bar). Matches Hayase mobile
    /// layout where options/back is a floating button, not a bar.
    private func setupBackButton() {
        backButton.translatesAutoresizingMaskIntoConstraints = false
        backButton.setImage(UIImage(systemName: "chevron.left"), for: .normal)
        backButton.tintColor = .white
        backButton.backgroundColor = UIColor.black.withAlphaComponent(0.2)
        backButton.layer.cornerRadius = 22
        backButton.clipsToBounds = true
        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
        overlay.addSubview(backButton)
        NSLayoutConstraint.activate([
            backButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            backButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
            backButton.widthAnchor.constraint(equalToConstant: 44),
            backButton.heightAnchor.constraint(equalToConstant: 44),
        ])
    }

    /// Hayase downloadstats.svelte — floating HUD at top center showing
    /// peers, download speed + upload speed.
    /// Positioned at top center like the Hayase web player.
    /// Added to the overlay so it fades out with controls when the user
    /// is inactive — matching Hayase's `class:opacity-0={immersed}`.
    private func setupStatsHUD() {
        statsHUD.translatesAutoresizingMaskIntoConstraints = false
        statsHUD.font = .systemFont(ofSize: 14, weight: .bold)
        statsHUD.textColor = .white
        statsHUD.textAlignment = .center
        statsHUD.isHidden = true
        // Text shadow via layer (matches Hayase text-shadow-lg)
        statsHUD.layer.shadowColor = UIColor.black.cgColor
        statsHUD.layer.shadowOffset = .zero
        statsHUD.layer.shadowOpacity = 0.8
        statsHUD.layer.shadowRadius = 4
        overlay.addSubview(statsHUD)
        NSLayoutConstraint.activate([
            statsHUD.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            statsHUD.centerXAnchor.constraint(equalTo: view.centerXAnchor),
        ])
    }

    private func setupBottomBar() {
        bottomBar.translatesAutoresizingMaskIntoConstraints = false
        // Gradient background applied in viewDidLayoutSubviews
        bottomBar.clipsToBounds = true
        overlay.addSubview(bottomBar)
        NSLayoutConstraint.activate([
            bottomBar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            bottomBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        // --- Row 1: Title + Episode (left) + Chapter & Time (right) ---
        // Hayase episodesmodal.svelte: session.title (text-lg font-normal)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.textColor = .white
        titleLabel.font = .systemFont(ofSize: 18, weight: .regular)
        titleLabel.textAlignment = .left
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.text = animeTitleText()
        // Text shadow (Hayase text-shadow-lg)
        titleLabel.layer.shadowColor = UIColor.black.cgColor
        titleLabel.layer.shadowOffset = .zero
        titleLabel.layer.shadowOpacity = 0.8
        titleLabel.layer.shadowRadius = 3
        bottomBar.addSubview(titleLabel)

        // Hayase episodesmodal.svelte: session.description (text-sm font-light rgba(217,217,217,0.6))
        episodeLabel.translatesAutoresizingMaskIntoConstraints = false
        episodeLabel.textColor = UIColor(red: 217/255, green: 217/255, blue: 217/255, alpha: 0.6)
        episodeLabel.font = .systemFont(ofSize: 14, weight: .light)
        episodeLabel.textAlignment = .left
        episodeLabel.lineBreakMode = .byTruncatingTail
        episodeLabel.text = episodeDescriptionText()
        episodeLabel.layer.shadowColor = UIColor.black.cgColor
        episodeLabel.layer.shadowOffset = .zero
        episodeLabel.layer.shadowOpacity = 0.8
        episodeLabel.layer.shadowRadius = 3
        bottomBar.addSubview(episodeLabel)

        chapterLabel.translatesAutoresizingMaskIntoConstraints = false
        chapterLabel.textColor = UIColor(white: 0.85, alpha: 0.6) // rgba(217,217,217,0.6)
        chapterLabel.font = .systemFont(ofSize: 12, weight: .light)
        chapterLabel.textAlignment = .right
        chapterLabel.lineBreakMode = .byTruncatingTail
        chapterLabel.text = ""
        bottomBar.addSubview(chapterLabel)

        timeLabel.translatesAutoresizingMaskIntoConstraints = false
        timeLabel.textColor = .white
        timeLabel.font = .systemFont(ofSize: 13, weight: .light)
        timeLabel.textAlignment = .right
        timeLabel.text = "0:00 / 0:00"
        timeLabel.isUserInteractionEnabled = true
        timeLabel.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(toggleTimeFormat)))
        // Text shadow
        timeLabel.layer.shadowColor = UIColor.black.cgColor
        timeLabel.layer.shadowOffset = .zero
        timeLabel.layer.shadowOpacity = 0.8
        timeLabel.layer.shadowRadius = 3
        bottomBar.addSubview(timeLabel)

        // --- Row 2: Seekbar (full width) ---
        seekBar.translatesAutoresizingMaskIntoConstraints = false
        seekBar.minimumValue = 0
        seekBar.maximumValue = 1
        seekBar.minimumTrackTintColor = .white
        seekBar.maximumTrackTintColor = UIColor(white: 0.85, alpha: 0.4) // rgba(217,217,217,0.4)
        seekBar.setThumbImage(UIImage(), for: .normal)   // No visible thumb at rest — Hayase uses bar only
        seekBar.setThumbImage(circleThumb(diameter: 14), for: .highlighted)
        seekBar.addTarget(self, action: #selector(seekBegan),   for: .touchDown)
        seekBar.addTarget(self, action: #selector(seekChanged), for: .valueChanged)
        seekBar.addTarget(self, action: #selector(seekEnded),   for: [.touchUpInside, .touchUpOutside])
        bottomBar.addSubview(seekBar)

        chapterLayer.translatesAutoresizingMaskIntoConstraints = false
        chapterLayer.isUserInteractionEnabled = false
        bottomBar.addSubview(chapterLayer)

        // --- Row 3: Controls ---
        // Left side: play/pause, prev, next
        [prevButton, playPauseButton, nextButton, optionsButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            $0.tintColor = .white
        }
        prevButton.setImage(UIImage(systemName: "backward.end.fill"),  for: .normal)
        playPauseButton.setImage(UIImage(systemName: "pause.fill"),    for: .normal)
        nextButton.setImage(UIImage(systemName: "forward.end.fill"),   for: .normal)
        optionsButton.setImage(UIImage(systemName: "ellipsis"), for: .normal)
        // Rotate to vertical orientation, matching Hayase's EllipsisVertical icon
        optionsButton.transform = CGAffineTransform(rotationAngle: .pi / 2)

        prevButton.addTarget(self,      action: #selector(prevTapped),      for: .touchUpInside)
        playPauseButton.addTarget(self, action: #selector(playPauseTapped), for: .touchUpInside)
        nextButton.addTarget(self,      action: #selector(nextTapped),      for: .touchUpInside)
        optionsButton.addTarget(self,   action: #selector(optionsTapped),   for: .touchUpInside)

        prevButton.isEnabled  = allVideos.count > 1 && currentVideoIndex > 0
        nextButton.isEnabled  = allVideos.count > 1 && currentVideoIndex < allVideos.count - 1

        let leftStack = UIStackView(arrangedSubviews: [playPauseButton, prevButton, nextButton])
        leftStack.translatesAutoresizingMaskIntoConstraints = false
        leftStack.axis = .horizontal
        leftStack.spacing = 4
        bottomBar.addSubview(leftStack)

        // Right side: speed label, options, AirPlay
        speedLabel.translatesAutoresizingMaskIntoConstraints = false
        speedLabel.textColor = .white
        speedLabel.font = .systemFont(ofSize: 14, weight: .bold)
        speedLabel.textAlignment = .center
        speedLabel.text = "" // Hidden when 1x
        speedLabel.isUserInteractionEnabled = true
        speedLabel.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(speedLabelTapped)))
        bottomBar.addSubview(speedLabel)

        airPlayPicker.translatesAutoresizingMaskIntoConstraints = false
        airPlayPicker.activeTintColor = .systemIndigo
        airPlayPicker.tintColor = .white
        airPlayPicker.prioritizesVideoDevices = true
        bottomBar.addSubview(airPlayPicker)

        let rightStack = UIStackView(arrangedSubviews: [speedLabel, optionsButton, airPlayPicker])
        rightStack.translatesAutoresizingMaskIntoConstraints = false
        rightStack.axis = .horizontal
        rightStack.spacing = 4
        rightStack.alignment = .center
        bottomBar.addSubview(rightStack)

        let pad: CGFloat = 16
        NSLayoutConstraint.activate([
            // Row 1: title + episode (left), chapter + time (right)
            // Hayase: title on top, episode below; chapter above time on right
            titleLabel.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor, constant: pad + 8),
            titleLabel.topAnchor.constraint(equalTo: bottomBar.topAnchor, constant: 10),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: chapterLabel.leadingAnchor, constant: -12),

            episodeLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            episodeLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            episodeLabel.trailingAnchor.constraint(lessThanOrEqualTo: timeLabel.leadingAnchor, constant: -12),

            chapterLabel.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor, constant: -(pad + 8)),
            chapterLabel.bottomAnchor.constraint(equalTo: timeLabel.topAnchor, constant: -2),

            timeLabel.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor, constant: -(pad + 8)),
            timeLabel.centerYAnchor.constraint(equalTo: episodeLabel.centerYAnchor),

            // Row 2: seekbar
            seekBar.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor, constant: pad),
            seekBar.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor, constant: -pad),
            seekBar.topAnchor.constraint(equalTo: episodeLabel.bottomAnchor, constant: 0),
            seekBar.heightAnchor.constraint(equalToConstant: 32),

            chapterLayer.leadingAnchor.constraint(equalTo: seekBar.leadingAnchor),
            chapterLayer.trailingAnchor.constraint(equalTo: seekBar.trailingAnchor),
            chapterLayer.centerYAnchor.constraint(equalTo: seekBar.centerYAnchor),
            chapterLayer.heightAnchor.constraint(equalToConstant: 4),

            // Row 3: controls
            leftStack.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor, constant: pad),
            leftStack.topAnchor.constraint(equalTo: seekBar.bottomAnchor, constant: 0),
            leftStack.bottomAnchor.constraint(equalTo: bottomBar.bottomAnchor, constant: -10),
            leftStack.heightAnchor.constraint(equalToConstant: 44),

            rightStack.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor, constant: -pad),
            rightStack.centerYAnchor.constraint(equalTo: leftStack.centerYAnchor),
            rightStack.heightAnchor.constraint(equalToConstant: 44),

            playPauseButton.widthAnchor.constraint(equalToConstant: 48),
            playPauseButton.heightAnchor.constraint(equalToConstant: 48),
            prevButton.widthAnchor.constraint(equalToConstant: 48),
            prevButton.heightAnchor.constraint(equalToConstant: 48),
            nextButton.widthAnchor.constraint(equalToConstant: 48),
            nextButton.heightAnchor.constraint(equalToConstant: 48),

            speedLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 30),
            optionsButton.widthAnchor.constraint(equalToConstant: 48),
            optionsButton.heightAnchor.constraint(equalToConstant: 48),
            airPlayPicker.widthAnchor.constraint(equalToConstant: 48),
            airPlayPicker.heightAnchor.constraint(equalToConstant: 48),
        ])
    }

    private func setupGestures() {
        // Two standard UITapGestureRecognizers (count=1 and count=2) attached to
        // the root `view` — NOT the surface which sits beneath the overlay.
        // Single-tap `require(toFail:)` the double-tap so they never conflict.
        // This matches SwiftUI's onTapGesture(count:) behavior and is Apple's
        // recommended pattern for distinguishing single from double taps.
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        doubleTap.delegate = self
        view.addGestureRecognizer(doubleTap)
        doubleTapRecognizer = doubleTap

        let singleTap = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap(_:)))
        singleTap.numberOfTapsRequired = 1
        singleTap.require(toFail: doubleTap)
        singleTap.delegate = self
        view.addGestureRecognizer(singleTap)
    }

    /// Single-tap: toggle controls visibility.
    @objc private func handleSingleTap(_ gesture: UITapGestureRecognizer) {
        setControls(visible: !controlsVisible)
    }

    /// Double-tap: seek forward/backward depending on which half was tapped.
    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        let tapLocation = gesture.location(in: surface)
        performDoubleTapSeek(at: tapLocation)
    }

    /// Returns the seek duration (seconds) from user settings (pref_seekDuration), defaulting to 5.
    private var seekDurationSeconds: Double {
        let stored = UserDefaults.standard.string(forKey: "pref_seekDuration") ?? "5"
        return Double(stored) ?? 5
    }

    /// Double-tap on the left half of the screen seeks backward; right half seeks forward.
    /// The seek amount comes from the user's "Seek Duration" setting (pref_seekDuration).
    private func performDoubleTapSeek(at location: CGPoint) {
        let seekAmount = seekDurationSeconds
        if location.x < surface.bounds.midX {
            // Left half → seek backward
            let newTime = max(0, currentTime - seekAmount)
            let fraction = duration > 0 ? newTime / duration : 0
            streamer?.seekTo(fraction: fraction)
            surface.mpv.seek(by: -seekAmount)
            lastSeekTime = Date()
            showSeekIndicator(seconds: -seekAmount)
        } else {
            // Right half → seek forward
            let newTime = min(duration, currentTime + seekAmount)
            let fraction = duration > 0 ? newTime / duration : 0
            streamer?.seekTo(fraction: fraction)
            surface.mpv.seek(by: seekAmount)
            lastSeekTime = Date()
            showSeekIndicator(seconds: seekAmount)
        }
        if !controlsVisible { setControls(visible: true) }
        scheduleHide()
    }

    /// Briefly shows a "«10s" or "10s»" indicator on the tapped side.
    private func showSeekIndicator(seconds: Double) {
        let isForward = seconds > 0
        let text = isForward
            ? "\(Int(abs(seconds)))s »"
            : "« \(Int(abs(seconds)))s"
        let indicator = UILabel()
        indicator.text = text
        indicator.font = .systemFont(ofSize: 22, weight: .bold)
        indicator.textColor = .white
        indicator.textAlignment = .center
        indicator.alpha = 0
        indicator.layer.shadowColor = UIColor.black.cgColor
        indicator.layer.shadowOffset = .zero
        indicator.layer.shadowOpacity = 0.8
        indicator.layer.shadowRadius = 4
        indicator.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(indicator)
        NSLayoutConstraint.activate([
            indicator.centerYAnchor.constraint(equalTo: surface.centerYAnchor),
            isForward
                ? indicator.centerXAnchor.constraint(equalTo: surface.centerXAnchor, constant: surface.bounds.width * 0.25)
                : indicator.centerXAnchor.constraint(equalTo: surface.centerXAnchor, constant: -surface.bounds.width * 0.25),
        ])
        UIView.animate(withDuration: 0.15, animations: {
            indicator.alpha = 1
        }) { _ in
            UIView.animate(withDuration: 0.3, delay: 0.4, options: [], animations: {
                indicator.alpha = 0
            }) { _ in
                indicator.removeFromSuperview()
            }
        }
    }

    // MARK: - Video loading

    private func loadCurrentVideo() {
        guard let entity = videoEntity else { return }
        let path = entity.videoPath ?? ""
        guard !path.isEmpty else { return }
        
        // Reset states for new file
        trackingCompleted = false
        isEOFTriggered = false
        pendingRestoreTime = nil
        chapters.removeAll()
        updateChapterMarkers()

        // Set up torrent streaming if the file is still downloading.
        setupStreamer()

        // Load MPV immediately — the LocalStreamServer blocks HTTP responses
        // until the required pieces are downloaded, so MPV naturally waits for
        // head data (MKV header) without needing a separate pre-wait. This
        // removes the fixed 60 s metadata timeout: for low-seeder torrents the
        // player simply stays in its buffering state while the streaming logger
        // shows peer/seed counts, giving the user visibility into the
        // connection status. MPV's network-timeout (600 s) is the effective
        // upper bound.
        if let s = streamer, s.isActive {
            StreamingLogger.shared.info("Streaming — waiting for head pieces…")
        }
        loadVideoURL()

        // Set initial AniList state (PLANNING → CURRENT, COMPLETED → REPEATING) for ep 1
        AniListTracking.shared.setInitialState(anilistID: anilistID, episode: episodeNumber)
    }

    /// Builds the URL and preset, loads the video into MPV, and starts stats.
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
            //
            // Disable MKV duration probing for streaming via preset command.
            // probe-video-duration=yes (set at MPV init) causes MPV to seek to
            // the end of the file to read MKV Cues before starting playback.
            // For streaming, this blocks until ALL tail pieces are downloaded,
            // which with large piece sizes and low seeds means waiting for
            // 20–60%+ of the file. Disabling the probe lets MPV start playback
            // immediately from the MKV header in the first piece(s). Duration
            // is still available from the MKV Info element in the header.
            // Seeking works via force-seekable=yes; MPV fetches Cues on-demand
            // when the user seeks (LocalStreamServer blocks until the required
            // tail pieces are downloaded).
            //
            // NOTE: This uses a preset "set" command (not loadfile file-local
            // options) because mpv 0.36+ changed the loadfile signature to
            // `loadfile url flags index options` — the 4th arg is an integer
            // index, not options. File-local options at position 4 get silently
            // consumed as the index parameter and never take effect.
            preset = PlayerPreset(commands: [
                ["set", "demuxer-mkv-probe-video-duration", "no"],
                ["set", "cache", "yes"],
                ["set", "cache-secs", "180"],
                ["set", "cache-pause-wait", "5"],
                ["set", "demuxer-max-bytes", "250MiB"],
                ["set", "demuxer-max-back-bytes", "50MiB"],
                ["set", "network-timeout", "600"],
            ])
        } else if path.starts(with: "http"), let httpURL = URL(string: path) {
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
        
        // Hayase episodesmodal.svelte: title = anime name, description = episode info
        titleLabel.text = animeTitleText()
        episodeLabel.text = episodeDescriptionText()
        // Hayase mediahandler.svelte: hasPrev = episode > 1; hasNext = episode < totalEps.
        // Enable buttons based on episode bounds, not just allVideos array bounds.
        // When onEpisodeChange is set, out-of-batch navigation triggers a new search.
        let canGoPrev = episodeNumber > 1
        let canGoNext: Bool
        if totalEpisodes > 0 {
            canGoNext = episodeNumber < totalEpisodes
        } else {
            // Unknown total — allow next if there's a batch file OR callback
            canGoNext = currentVideoIndex < allVideos.count - 1 || onEpisodeChange != nil
        }
        prevButton.isEnabled = canGoPrev
        nextButton.isEnabled = canGoNext
        restoreProgress(path: path)
        startStatsTimer()
    }

    private func restoreProgress(path: String) {
        // Primary: look up by exact video path.
        var saved = WatchProgressService.shared.getProgress(videoPath: path)
        // Fallback: look up by anilistID + episode (covers re-added torrents
        // where the Torrents / Videos entities were recreated with different
        // paths while the user had already watched part of the episode).
        if saved == nil, anilistID > 0 {
            saved = WatchProgressService.shared.getProgress(anilistID: anilistID, episode: episodeNumber)
        }
        guard let saved, saved.isInProgress, saved.currentTime > 5 else { return }
        // Store the target time and apply it once MPV reports a valid duration
        // in didUpdatePosition. This works for both local files (where MPV is
        // ready almost immediately) and HTTP streams (where header buffering
        // can take several seconds or more).
        pendingRestoreTime = saved.currentTime
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
        StreamingLogger.shared.info("Streamer started — pieces \(s.beginPiece)–\(s.endPiece) (\(s.totalFilePieces) total)")

        // Start a local HTTP server so MPV reads from HTTP instead of a
        // file with holes. The server gates responses on piece availability.
        let path = videoEntity?.videoPath ?? ""
        guard !path.isEmpty else { return }

        let server = LocalStreamServer(torrentHandle: handle, fileIndex: fileIndex, filePath: path)
        do {
            try server.start()
            streamServer = server
            if UserDefaults.standard.bool(forKey: "pref_showLogger") { print("LocalStreamServer: started for file \(fileIndex) at \(server.url)") }
        } catch {
            StreamingLogger.shared.error("Stream server failed: \(error.localizedDescription)")
            if UserDefaults.standard.bool(forKey: "pref_showLogger") { print("LocalStreamServer: failed to start — \(error)") }
            // Fall back to direct file path (original behavior)
        }
    }

    // MARK: - Download stats

    private func startStatsTimer() {
        statsTimer?.invalidate()
        guard torrentHandle != nil else { return }
        guard !isFileFullyDownloaded() else { return }
        statsHUD.isHidden = false
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
            statsHUD.isHidden = true
            // Stop the streamer — piece management is no longer needed.
            // Do NOT stop streamServer here: MPV is still reading from the
            // HTTP URL. Stopping the server mid-playback causes read errors
            // and playback failure. The server is stopped in viewWillDisappear
            // and prev/next episode transitions.
            streamer?.stop()
            streamer = nil
            return
        }
        // Hayase downloadstats.svelte format: peers ↓speed ↑speed
        let peers = snap.numberOfSeeds
        let downBits = fmtBits(snap.downloadRate * 8)
        let upBits = fmtBits(snap.uploadRate * 8)
        statsHUD.text = "👤 \(peers)    ↓ \(downBits)/s    ↑ \(upBits)/s"
    }

    /// Formats bits per second into a human-readable string (Hayase fastPrettyBits).
    private func fmtBits(_ bps: UInt64) -> String {
        if bps == 0              { return "0 b" }
        if bps >= 1_000_000_000  { return String(format: "%.1f Gb", Double(bps) / 1_000_000_000) }
        if bps >= 1_000_000      { return String(format: "%.1f Mb", Double(bps) / 1_000_000) }
        if bps >= 1_000          { return String(format: "%.0f Kb", Double(bps) / 1_000) }
        return "\(bps) b"
    }

    // MARK: - Title helpers (Hayase episodesmodal.svelte / mediahandler.svelte)

    /// Returns the anime title for the title label.
    /// Hayase: `mediaInfo.session.title = title(media)` — the anime name.
    /// Falls back to the video file name if no anime metadata is linked.
    private func animeTitleText() -> String {
        if let anime = videoEntity?.torrents?.animes {
            if let t = anime.animeTitleEnglish, !t.isEmpty { return t }
            if let t = anime.animeTitleJapanese, !t.isEmpty { return t }
        }
        return videoEntity?.videoName ?? "Playing"
    }

    /// Returns the episode description for the episode label.
    /// Format: "Episode N/Total" when total is known, "Episode N" otherwise.
    private func episodeDescriptionText() -> String {
        let totalEps = videoEntity?.torrents?.animes?.animeTotalEps?.intValue ?? 0
        if totalEps > 0 {
            return "Episode \(episodeNumber)/\(totalEps)"
        }
        return "Episode \(episodeNumber)"
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

    /// Matches Hayase player.svelte checkCompletion():
    /// When the user is within max(180s, 10% of duration) of the end,
    /// automatically update AniList progress for this episode.
    private func checkCompletion() {
        // Desktop defaults playerAutocomplete to true — mirror with object(forKey:) ?? true
        let autocomplete = UserDefaults.standard.object(forKey: "pref_autocomplete") as? Bool ?? true
        guard !trackingCompleted, autocomplete,
              anilistID > 0, episodeNumber > 0,
              duration > 0, currentTime > 0 else { return }

        let fromEnd = max(180.0, duration / 10.0)
        if duration - fromEnd < currentTime {
            trackingCompleted = true
            AniListTracking.shared.watch(anilistID: anilistID, episodeProgress: episodeNumber)
        }
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
        UIView.animate(withDuration: 0.25) { [weak self] in self?.overlay.alpha = visible ? 1 : 0 }
        setNeedsStatusBarAppearanceUpdate()
        setNeedsUpdateOfHomeIndicatorAutoHidden()
        if visible { scheduleHide() }
    }

    // MARK: - Time UI

    private func updateTimeUI() {
        guard !isSeeking else { return }
        seekBar.value = duration > 0 ? Float(currentTime / duration) : 0
        // Hayase format: "current / total" or "-remaining / total"
        if showRemainingTime {
            timeLabel.text = "-\(fmtTime(max(0, duration - currentTime))) / \(fmtTime(duration))"
        } else {
            timeLabel.text = "\(fmtTime(currentTime)) / \(fmtTime(duration))"
        }
        // Update chapter label if chapters are available
        if let ch = chapters.last(where: { $0.time <= currentTime }) {
            chapterLabel.text = ch.title
        } else {
            chapterLabel.text = ""
        }
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
        // Hayase wrapper.svelte: navigating away from /app/player activates
        // mini-player mode instead of destroying the player component.
        MiniPlayerManager.shared.minimize(self)
    }

    @objc private func playPauseTapped() {
        // Track that this pause/unpause was user-initiated so didChangePause
        // knows to pause/resume the torrent. Without this flag, buffer stalls
        // (paused-for-cache) that flip the pause property would incorrectly
        // stop the torrent download, making stutters worse.
        userRequestedPause = !isPaused
        surface.mpv.togglePause()
        if !controlsVisible { setControls(visible: true) } else { scheduleHide() }
    }

    @objc private func prevTapped() {
        let targetEpisode = episodeNumber - 1
        guard targetEpisode >= 1 else { return }
        saveProgress()

        // Hayase web mediahandler.svelte playEpisode(): first check if the
        // target episode exists in the current torrent batch (resolvedFiles).
        if let batchVideo = findVideoInBatch(forEpisode: targetEpisode) {
            switchToVideo(batchVideo, episode: targetEpisode)
        } else {
            // Episode not in batch → trigger new extension search.
            // Mirrors web's `searchStore.set({ media, episode })`.
            requestEpisodeChange(targetEpisode)
        }
    }

    @objc private func nextTapped() {
        let targetEpisode = episodeNumber + 1
        let maxEp = totalEpisodes > 0 ? totalEpisodes : Int.max
        guard targetEpisode <= maxEp else { return }
        saveProgress()

        // Hayase web mediahandler.svelte playEpisode(): first check if the
        // target episode exists in the current torrent batch (resolvedFiles).
        if let batchVideo = findVideoInBatch(forEpisode: targetEpisode) {
            switchToVideo(batchVideo, episode: targetEpisode)
        } else {
            // Episode not in batch → trigger new extension search.
            requestEpisodeChange(targetEpisode)
        }
    }

    /// Finds a video in the current `allVideos` batch that matches the
    /// target episode. For batch torrents this checks adjacent indices.
    /// Mirrors web's `resolvedFiles.find(res => res.metadata.episode === episode)`.
    private func findVideoInBatch(forEpisode targetEp: Int) -> (video: Videos, index: Int)? {
        // For batch torrents, episodes are stored sequentially.
        // The episode offset for a given video at array index `i` is:
        //   episodeNumber - currentVideoIndex + i
        // i.e. the same relationship that was used: episodeNumber = currentVideoIndex + 1
        // But this only works if episodes map 1:1 to array indices starting from 1.
        // More robust: check if moving by (targetEp - episodeNumber) stays in bounds.
        let delta = targetEp - episodeNumber
        let targetIndex = currentVideoIndex + delta
        guard targetIndex >= 0 && targetIndex < allVideos.count else { return nil }
        return (allVideos[targetIndex], targetIndex)
    }

    /// Switches to a different video file within the same torrent batch.
    /// Called when the target episode IS found in `allVideos`.
    private func switchToVideo(_ match: (video: Videos, index: Int), episode: Int) {
        streamServer?.stop()
        streamServer = nil
        streamer?.stop()
        streamer = nil
        currentVideoIndex = match.index
        videoEntity = match.video
        episodeNumber = episode
        if let idx = videoEntity?.videoIndex {
            fileIndex = UInt(idx.intValue)
            videoService?.selectFileForStreaming(fileIndex)
            videoService?.UpdateFilePathForFileIndex(fileIndex)
        }
        duration = 0; currentTime = 0
        loadCurrentVideo()
        scheduleHide()
    }

    /// Requests an episode change for an episode NOT in the current batch.
    /// Saves progress, then fires `onEpisodeChange` so the presenting VC
    /// can dismiss the player and start a new search.
    private func requestEpisodeChange(_ episode: Int) {
        if let callback = onEpisodeChange {
            callback(episode)
        }
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
        if showRemainingTime {
            timeLabel.text = "-\(fmtTime(max(0, duration - t))) / \(fmtTime(duration))"
        } else {
            timeLabel.text = "\(fmtTime(t)) / \(fmtTime(duration))"
        }
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

    @objc private func speedLabelTapped() {
        hideWork?.cancel()
        showSpeedPicker()
    }

    /// Updates the speed label text. Hayase shows "x1.5" only when rate ≠ 1.
    private func updateSpeedLabel() {
        if playbackRate != 1.0 && playbackRate != 0.0 {
            speedLabel.text = "x\(String(format: "%g", playbackRate))"
        } else {
            speedLabel.text = ""
        }
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
                self?.surface.mpv.setSpeed(rate)
                self?.updateSpeedLabel()
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
    
    // Auto-plays next episode (Hayase web: next() called at EOF)
    private func handleFileEnded() {
        // Use the same logic as nextTapped — tries in-batch first, then
        // falls back to onEpisodeChange for a new extension search.
        let maxEp = totalEpisodes > 0 ? totalEpisodes : Int.max
        guard episodeNumber + 1 <= maxEp else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.nextTapped() }
    }
}

// MARK: - MPVWrapperDelegate Integration

extension VideoPlayerViewController: MPVWrapperDelegate {

    func renderer(_ renderer: MPVWrapper, didUpdatePosition position: Double, duration: Double, cacheSeconds: Double) {
        self.currentTime = position
        self.duration    = duration
        updateTimeUI()

        // Feed position/duration to system PiP so the progress bar stays in sync.
        // Also ensure the timebase rate matches the current playback state —
        // MPV may start playing without first firing a pause-change event, which
        // would leave the timebase at rate 0 and prevent auto-PiP from starting.
        if #available(iOS 15.0, *) {
            pipController?.setCurrentTimeFromSeconds(position, duration: duration)
            if !isPaused {
                pipController?.setPlaybackRate(1)
            }
        }

        // Apply deferred progress-restore seek once MPV reports a valid duration,
        // meaning the file/stream is loaded and seeking is possible.
        if let restoreTime = pendingRestoreTime, duration > 0 {
            pendingRestoreTime = nil
            lastSeekTime = Date()
            surface.mpv.seek(to: restoreTime)
        }

        // Feed playback position to the streamer so it can set piece deadlines
        // ahead of the current position. Pass duration so the streamer can check
        // whether the buffer is already sufficient and skip unnecessary requests.
        if duration > 0 {
            streamer?.updatePlaybackPosition(fraction: position / duration, videoDuration: duration)
        }

        // Check auto-completion (Hayase player.svelte checkCompletion)
        checkCompletion()

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

        // Keep the mini-player's play/pause icon in sync.
        MiniPlayerManager.shared.updatePlayPauseIcon(isPaused: isPaused)

        // Update system PiP timebase rate so the PiP window shows the
        // correct play/pause state and progress bar animation.
        if #available(iOS 15.0, *) {
            pipController?.setPlaybackRate(isPaused ? 0 : 1)
            pipController?.updatePlaybackState()
        }

        // Don't pause the torrent when the video is paused. Like Hayase,
        // we keep the torrent downloading at reduced effective speed (no
        // active piece deadline boosting while playback is stopped).
        // Fully pausing the torrent (handle.pause()) blocks
        // LocalStreamServer.waitForLocalPieces() indefinitely, which
        // breaks seeks while paused.
        if !isPaused {
            userRequestedPause = false
        }
    }

    func renderer(_ renderer: MPVWrapper, didChangeLoading isLoading: Bool) {
        // Torrent is never paused, so no safety-valve resume is needed.
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

    // MARK: - Mini-player support (Hayase wrapper.svelte)

    /// Returns the MPV surface view so MiniPlayerManager can reparent it.
    var surfaceView: MPVSurfaceView { surface }

    /// Toggles play/pause from the mini-player.
    func togglePlayPause() {
        surface.mpv.togglePause()
    }
}

// MARK: - PiPControllerDelegate (System PiP — streamyfin)

@available(iOS 15.0, *)
extension VideoPlayerViewController: PiPControllerDelegate {

    func pipController(_ controller: PiPController, willStartPictureInPicture: Bool) {
        // Hide in-app overlay while system PiP is active.
        setControls(visible: false)
    }

    func pipController(_ controller: PiPController, didStartPictureInPicture: Bool) {
        // System PiP started successfully.
    }

    func pipController(_ controller: PiPController, willStopPictureInPicture: Bool) {
        // System PiP is about to stop.
    }

    func pipController(_ controller: PiPController, didStopPictureInPicture: Bool) {
        // System PiP stopped — show controls again.
        setControls(visible: true)
        scheduleHide()
    }

    func pipController(_ controller: PiPController, restoreUserInterfaceForPictureInPictureStop completionHandler: @escaping (Bool) -> Void) {
        // The user tapped the PiP window to return to the app.
        // If the player is still presented, just report success.
        // If it was dismissed (e.g. from in-app mini-player), re-present it.
        if presentingViewController != nil || view.window != nil {
            completionHandler(true)
        } else {
            // Player was dismissed — try to present it again from the top VC.
            if let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene }).first,
               let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController {
                var top = root
                while let presented = top.presentedViewController { top = presented }
                self.modalPresentationStyle = .fullScreen
                top.present(self, animated: true) {
                    completionHandler(true)
                }
            } else {
                completionHandler(false)
            }
        }
    }

    func pipControllerPlay(_ controller: PiPController) {
        surface.mpv.play()
    }

    func pipControllerPause(_ controller: PiPController) {
        userRequestedPause = true
        surface.mpv.pausePlayback()
    }

    func pipController(_ controller: PiPController, skipByInterval interval: CMTime) {
        let seconds = CMTimeGetSeconds(interval)
        surface.mpv.seek(by: seconds)
    }

    func pipControllerIsPlaying(_ controller: PiPController) -> Bool {
        return !isPaused
    }

    func pipControllerDuration(_ controller: PiPController) -> Double {
        return duration
    }

    func pipControllerCurrentPosition(_ controller: PiPController) -> Double {
        return currentTime
    }
}

// MARK: - UIGestureRecognizerDelegate

extension VideoPlayerViewController: UIGestureRecognizerDelegate {
    /// Prevent the single/double-tap recognizers from firing when the user
    /// taps on a UIControl (buttons, sliders, switches, etc.).
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldReceive touch: UITouch) -> Bool {
        var v = touch.view
        while let current = v {
            if current is UIControl { return false }
            if current === view { break }
            v = current.superview
        }
        return true
    }
}