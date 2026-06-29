import UIKit
import AVKit
import CoreMedia
import LibTorrent

// MARK: - SegmentedSeekBar (interface seekbar.svelte)

/// A chapter-segmented progress bar matching the Hayase web interface seekbar.svelte.
/// Each chapter forms a separate rounded bar segment with small gaps between them.
/// Replaces UISlider + chapterLayer for a faithful recreation of the web player.
private final class SegmentedSeekBar: UIControl {

    // MARK: - Public State

    /// Current playback progress 0–1.
    var value: CGFloat = 0 {
        didSet { layoutSegmentFills() }
    }

    /// True while the user is touching/dragging the bar.
    private(set) var isSeeking = false

    // MARK: - Segments

    private struct Segment {
        let size: CGFloat   // fraction of total width (0–1)
        let offset: CGFloat // start position fraction (0–1)
    }

    private var segments: [Segment] = [Segment(size: 1.0, offset: 0.0)]

    // MARK: - UI

    /// Each element: (container view, background layer, progress fill layer).
    private var segmentViews: [(container: UIView, bg: CALayer, fill: CALayer)] = []

    // MARK: - Constants (matching interface seekbar.svelte)

    /// Bar height when not being touched (h-0.5 = 2px in interface CSS).
    private let normalHeight: CGFloat = 2
    /// Bar height when being touched (h-1 = 4px in interface CSS).
    private let activeHeight: CGFloat = 4
    /// Gap between chapter segments (ml-0.5 = 2px in interface CSS).
    private let segmentGap: CGFloat = 2
    /// Corner radius per segment (rounded-[2px] in interface CSS).
    private let segmentRadius: CGFloat = 2
    /// Background color: rgba(217,217,217,0.4) from interface.
    private let bgColor = UIColor(red: 217/255, green: 217/255, blue: 217/255, alpha: 0.4)
    /// Progress fill color: white from interface.
    private let fillColor = UIColor.white

    private var barHeight: CGFloat = 2

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        rebuildSegmentViews()
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Chapter Updates

    func setChapters(_ chapters: [MPVChapter], duration: Double) {
        guard duration > 0 else {
            segments = [Segment(size: 1.0, offset: 0.0)]
            rebuildSegmentViews()
            return
        }

        let sorted = chapters.sorted { $0.time < $1.time }
        var newSegments: [Segment] = []

        for (i, ch) in sorted.enumerated() {
            let start = ch.time / duration
            let end = i + 1 < sorted.count ? sorted[i + 1].time / duration : 1.0
            let size = CGFloat(max(0, end - start))
            if size > 0.001 {
                newSegments.append(Segment(size: size, offset: CGFloat(start)))
            }
        }

        if newSegments.isEmpty {
            newSegments = [Segment(size: 1.0, offset: 0.0)]
        }

        segments = newSegments
        rebuildSegmentViews()
    }

    // MARK: - Build Segment Views

    private func rebuildSegmentViews() {
        segmentViews.forEach { $0.container.removeFromSuperview() }
        segmentViews = []

        for _ in segments {
            let container = UIView()
            container.clipsToBounds = true
            container.layer.cornerRadius = segmentRadius
            container.isUserInteractionEnabled = false

            let bg = CALayer()
            bg.backgroundColor = bgColor.cgColor
            container.layer.addSublayer(bg)

            let fill = CALayer()
            fill.backgroundColor = fillColor.cgColor
            container.layer.addSublayer(fill)

            addSubview(container)
            segmentViews.append((container, bg, fill))
        }
        setNeedsLayout()
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutSegmentFrames()
        layoutSegmentFills()
    }

    private func layoutSegmentFrames() {
        let totalWidth = bounds.width
        let gaps = segmentGap * CGFloat(max(0, segments.count - 1))
        let usable = totalWidth - gaps
        let cy = bounds.midY

        var x: CGFloat = 0
        for (i, seg) in segments.enumerated() {
            guard i < segmentViews.count else { break }
            let w = usable * seg.size
            let (container, bg, _) = segmentViews[i]
            container.frame = CGRect(x: x, y: cy - barHeight / 2, width: w, height: barHeight)
            container.layer.cornerRadius = min(segmentRadius, barHeight / 2)

            CATransaction.begin()
            CATransaction.setDisableActions(true)
            bg.frame = container.bounds
            CATransaction.commit()

            x += w + segmentGap
        }
    }

    private func layoutSegmentFills() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (i, seg) in segments.enumerated() {
            guard i < segmentViews.count else { break }
            let (container, _, fill) = segmentViews[i]
            let localProgress = localFill(value, offset: seg.offset, size: seg.size)
            fill.frame = CGRect(x: 0, y: 0, width: container.bounds.width * localProgress, height: container.bounds.height)
        }
        CATransaction.commit()
    }

    /// Maps a global progress fraction to a local fill within a segment.
    private func localFill(_ global: CGFloat, offset: CGFloat, size: CGFloat) -> CGFloat {
        guard size > 0 else { return 0 }
        return min(max((global - offset) / size, 0), 1)
    }

    // MARK: - Touch Handling (UIControl)

    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        isSeeking = true
        value = fractionForTouch(touch)
        animateHeight(activeHeight)
        sendActions(for: .touchDown)
        sendActions(for: .valueChanged)
        return true
    }

    override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        value = fractionForTouch(touch)
        sendActions(for: .valueChanged)
        return true
    }

    override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        if let t = touch { value = fractionForTouch(t) }
        isSeeking = false
        animateHeight(normalHeight)
        sendActions(for: .touchUpInside)
    }

    override func cancelTracking(with event: UIEvent?) {
        isSeeking = false
        animateHeight(normalHeight)
        sendActions(for: .touchCancel)
    }

    /// Expand the hit area vertically for easier touch targeting (matching FatSlider's 20pt).
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        bounds.insetBy(dx: 0, dy: -20).contains(point)
    }

    private func fractionForTouch(_ touch: UITouch) -> CGFloat {
        let x = touch.location(in: self).x
        return min(max(x / max(bounds.width, 1), 0), 1)
    }

    private func animateHeight(_ h: CGFloat) {
        guard barHeight != h else { return }
        barHeight = h
        UIView.animate(withDuration: 0.075) {
            self.layoutSegmentFrames()
        }
    }
}

// MARK: - Interface Player Overlays

private final class InterfaceSpinnerView: UIView {
    private let spinnerLayer = CAShapeLayer()
    private var isAnimating = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        isHidden = true
        isUserInteractionEnabled = false
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.5
        layer.shadowRadius = 8
        layer.shadowOffset = .zero
        spinnerLayer.fillColor = UIColor.clear.cgColor
        spinnerLayer.strokeColor = UIColor.white.cgColor
        spinnerLayer.lineWidth = 3
        spinnerLayer.lineCap = .butt
        layer.addSublayer(spinnerLayer)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if isAnimating {
            ensureSpinAnimation()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let inset = spinnerLayer.lineWidth / 2
        let rect = bounds.insetBy(dx: inset, dy: inset)
        spinnerLayer.frame = bounds
        spinnerLayer.path = UIBezierPath(arcCenter: CGPoint(x: bounds.midX, y: bounds.midY),
                                         radius: min(rect.width, rect.height) / 2,
                                         startAngle: -.pi / 2,
                                         endAngle: 0,
                                         clockwise: true).cgPath
        if isAnimating {
            ensureSpinAnimation()
        }
    }

    func setAnimating(_ animating: Bool) {
        isAnimating = animating
        isHidden = !animating
        if animating {
            ensureSpinAnimation()
        } else {
            spinnerLayer.removeAnimation(forKey: "spin")
        }
    }

    private func ensureSpinAnimation() {
        guard !isHidden, window != nil, spinnerLayer.animation(forKey: "spin") == nil else { return }
        let rotation = CABasicAnimation(keyPath: "transform.rotation.z")
        rotation.fromValue = 0
        rotation.toValue = CGFloat.pi * 2
        rotation.duration = 0.8
        rotation.repeatCount = .infinity
        rotation.timingFunction = CAMediaTimingFunction(name: .linear)
        spinnerLayer.add(rotation, forKey: "spin")
    }
}

private final class InterfaceProgressButton: UIControl {
    private let label = UILabel()
    private let progressView = UIView()
    private var pendingCompletion = false
    var onTrigger: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor.HayaseTheme.primary
        layer.cornerRadius = 6
        clipsToBounds = true

        label.font = .nunito(ofSize: 14, weight: .bold)
        label.textColor = UIColor.HayaseTheme.primaryForeground
        label.textAlignment = .center
        label.isUserInteractionEnabled = false
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        progressView.backgroundColor = UIColor.HayaseTheme.background.withAlphaComponent(0.2)
        progressView.isUserInteractionEnabled = false
        progressView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(progressView)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 36),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 28),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -28),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            progressView.topAnchor.constraint(equalTo: topAnchor),
            progressView.leadingAnchor.constraint(equalTo: leadingAnchor),
            progressView.trailingAnchor.constraint(equalTo: trailingAnchor),
            progressView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        sendSubviewToBack(progressView)
        addTarget(self, action: #selector(triggerNow), for: .touchUpInside)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        if !pendingCompletion {
            progressView.transform = CGAffineTransform(translationX: bounds.width, y: 0)
        }
    }

    override var intrinsicContentSize: CGSize {
        let labelSize = label.intrinsicContentSize
        return CGSize(width: labelSize.width + 56, height: 36)
    }

    func setTitle(_ title: String) {
        label.text = title
        invalidateIntrinsicContentSize()
    }

    func startProgress(duration: TimeInterval) {
        guard !pendingCompletion else { return }
        pendingCompletion = true
        layoutIfNeeded()
        progressView.layer.removeAllAnimations()
        progressView.transform = .identity
        UIView.animate(withDuration: duration, delay: 0, options: [.curveLinear]) {
            self.progressView.transform = CGAffineTransform(translationX: self.bounds.width, y: 0)
        } completion: { [weak self] finished in
            guard let self, finished, self.pendingCompletion else { return }
            self.pendingCompletion = false
            self.progressView.transform = CGAffineTransform(translationX: self.bounds.width, y: 0)
            self.onTrigger?()
        }
    }

    func stopProgress() {
        pendingCompletion = false
        progressView.layer.removeAllAnimations()
        progressView.transform = CGAffineTransform(translationX: bounds.width, y: 0)
    }

    @objc private func triggerNow() {
        stopProgress()
        onTrigger?()
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
    private let mobileOptionsButton = UIButton(type: .system)
    private let mobileControlsStack = UIStackView()
    private let mobilePrevButton = UIButton(type: .system)
    private let mobilePlayPauseButton = UIButton(type: .system)
    private let mobileNextButton = UIButton(type: .system)
    private let bufferingSpinner = InterfaceSpinnerView()
    private let fastForwardBadge = UIView()
    private let fastForwardLabel = UILabel()
    private let fastForwardIcon = UIImageView(image: UIImage.hayaseFilledIcon("fast-forward", pointSize: 12))
    private let skipChapterButton = InterfaceProgressButton()

    // Hayase downloadstats.svelte — floating HUD at top center
    private let statsHUD = UIStackView()
    private let statsPeersLabel = UILabel()
    private let statsDownLabel = UILabel()
    private let statsUpLabel = UILabel()

    // Bottom bar — above seekbar row
    private let titleLabel    = UILabel()
    private let episodeLabel  = UILabel()   // Hayase episodesmodal.svelte: session.description below title
    private let chapterLabel  = UILabel()
    private let timeLabel     = UILabel()

    // Bottom bar — seekbar row
    private let seekBar       = SegmentedSeekBar()

    // Bottom bar — controls row
    private let prevButton      = UIButton(type: .system)
    private let playPauseButton = UIButton(type: .system)
    private let nextButton      = UIButton(type: .system)
    private let speedLabel      = UILabel()
    private let optionsButton   = UIButton(type: .system)
    private let airPlayPicker   = AVRoutePickerView()
    private let bottomLeftControls = UIStackView()
    private let bottomRightControls = UIStackView()
    private var bottomControlConstraints: [NSLayoutConstraint] = []
    private var mobileSeekBarBottomConstraint: NSLayoutConstraint?

    // MARK: - State

    private var duration: Double = 0
    private var currentTime: Double = 0
    private(set) var isPaused = false
    /// Set to `true` before loading a video to start it paused on the first
    /// play event. Used for session restore on app launch so the mini-player
    /// does not auto-play on launch.
    var shouldStartPaused = false
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
    private var isBuffering = true
    private var isFastForwarding = false
    private var playbackRateBeforeFastForward = 1.0
    private var wasPausedBeforeFastForward = false
    private var currentSkippableChapter: SkippableChapter?
    /// The double-tap recognizer, stored so single-tap can require(toFail:) it.
    private var doubleTapRecognizer: UITapGestureRecognizer?
    private var longPressRecognizer: UILongPressGestureRecognizer?
    private var statsTimer: Timer?
    private var webStatsUpdateInFlight = false
    private var isEOFTriggered = false // Used to emulate the missing MPV_EVENT_END_FILE
    private var lastSeekTime: Date?    // Tracks last seek to prevent false EOF triggers
    /// Pending playback position (seconds) to restore once MPV reports a valid
    /// duration. Using a stored value + event-driven trigger instead of a fixed
    /// delay ensures the seek works for both local files and HTTP streams (where
    /// MPV can take several seconds to buffer enough data to start playback).
    private var pendingRestoreTime: Double?
    /// Throttle watch-progress saves to avoid writing UserDefaults on every
    /// position callback. Saves every 5 seconds during active playback.
    private var lastProgressSaveTime: Date = .distantPast
    private var fullscreenPortal: FullscreenPortalState?
    private var isFullscreenTransitioning = false

    private struct SkippableChapter: Equatable {
        let title: String
        let end: Double
        let skipType: String
    }

    /// True while the player is being minimized to in-app PiP. Prevents
    /// viewWillDisappear from tearing down the streaming pipeline.
    var isMinimizing = false

    // MARK: - W2G integration (mirrors player.svelte W2G hooks)

    /// Observer for W2GLobby changes.
    private var w2gObserver: NSObjectProtocol?
    /// Suppresses outgoing W2G state updates while applying a remote state change.
    private var isApplyingRemoteW2GState = false

    /// Bind/re-bind the current W2G client's delegate for player sync.
    /// When a lobby is created while the player is already running, push
    /// the current media + player state to the new client so that peers
    /// who join later receive it via `sendInitialSessionState`.
    /// Mirrors web's `server.play()` calling `w2globby.value?.mediaChange(...)`.
    private func bindW2GClient() {
        guard let client = W2GLobby.shared.client else { return }
        // Use a closure-based approach: store a weak ref and handle events.
        w2gPlayerDelegate = client

        // If the lobby was just created while we're already playing, push
        // the current media + index + player state to the client so new peers
        // receive the correct initial state. This mirrors web's server.play()
        // calling w2globby.value?.mediaChange() — but since the lobby was
        // created after we started playing, that call was a no-op at the time.
        if client.media == nil,
           let hash = currentW2GTorrentHash, anilistID > 0 {
            client.mediaChange(W2GMediaState(torrent: hash, mediaId: anilistID, episode: episodeNumber))
            client.mediaIndexChanged(currentVideoIndex)
            client.playerStateChanged(W2GPlayerState(paused: isPaused, time: floor(currentTime)))
        }
    }

    private var currentW2GTorrentHash: String? {
        if let hash = torrentHandle?.infoHashes.best.hex.trimmingCharacters(in: .whitespacesAndNewlines),
           !hash.isEmpty {
            return hash
        }

        let hash = videoEntity?.torrents?.torrentHashString?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return hash.isEmpty ? nil : hash
    }

    /// Reference to the active W2G client for incoming player state.
    private weak var w2gPlayerDelegate: W2GClient? {
        didSet {
            // The W2GViewController is the primary delegate for peers/messages.
            // For player state, we observe via a lightweight trampoline.
            w2gPlayerDelegate?.onPlayerStateReceived = { [weak self] state in
                self?.applyRemoteW2GState(state)
            }
        }
    }

    /// Apply a remote W2G player state (seek + pause/play).
    /// Mirrors player.svelte `function updateState(state)`.
    ///
    /// The web simply sets `currentTime = state.time; paused = state.paused`
    /// because Svelte bindings propagate synchronously. On iOS, MPV seek is
    /// async, so we keep the guard flag set and clear it after a short delay
    /// to absorb the resulting position/pause callbacks that would otherwise
    /// echo back to peers.
    private func applyRemoteW2GState(_ state: W2GPlayerState) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isApplyingRemoteW2GState = true

            if abs(self.currentTime - state.time) > 2 {
                self.surface.mpv.seek(to: state.time)
            }
            if state.paused && !self.isPaused {
                self.surface.mpv.pausePlayback()
            } else if !state.paused && self.isPaused {
                self.surface.mpv.play()
            }

            // Clear the guard after a short delay to absorb async callbacks.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.isApplyingRemoteW2GState = false
            }
        }
    }

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

        // W2G: listen for remote player state changes.
        // Mirrors player.svelte: `$: $w2globby?.on('player', updateState)`.
        w2gObserver = NotificationCenter.default.addObserver(
            forName: W2GLobby.didChange, object: nil, queue: .main
        ) { [weak self] _ in
            self?.bindW2GClient()
        }
        bindW2GClient()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        applyInterfaceMobilePlayerLayout()
        updateChapterMarkers()
        // Hayase player.svelte: linear-gradient(to top, black 0%, black 35%, transparent 100%).
        bottomGradient.frame = bottomBar.bounds
        if bottomGradient.superlayer == nil {
            bottomGradient.colors = [
                UIColor.clear.cgColor,
                UIColor.black.withAlphaComponent(0.7).cgColor,
                UIColor.black.withAlphaComponent(0.85).cgColor,
            ]
            bottomGradient.locations = [0.0, 0.65, 1.0]
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
        Router.shared.clearCachedPlayer(self)
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
        // W2G cleanup
        if let obs = w2gObserver { NotificationCenter.default.removeObserver(obs) }
        w2gPlayerDelegate = nil
    }

    override var prefersStatusBarHidden: Bool              { true }
    override var preferredStatusBarUpdateAnimation: UIStatusBarAnimation { .none }
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

        // Download stats — top center (Hayase downloadstats.svelte)
        setupStatsHUD()
        setupMobilePlayerControls()
        // Bottom overlay with gradient
        setupBottomBar()
        setupInterfacePlayerOverlays()
    }

    /// Hayase downloadstats.svelte — floating HUD at top center showing
    /// peers, download speed + upload speed.
    /// Positioned at top center like the Hayase web player.
    /// Added to the overlay so it fades out with controls when the user
    /// is inactive — matching Hayase's `class:opacity-0={immersed}`.
    private func setupStatsHUD() {
        statsHUD.translatesAutoresizingMaskIntoConstraints = false
        statsHUD.axis = .horizontal
        statsHUD.spacing = 16
        statsHUD.alignment = .center
        statsHUD.isHidden = true
        // Text/icon shadow via layer (matches Hayase text-shadow-lg)
        statsHUD.layer.shadowColor = UIColor.black.cgColor
        statsHUD.layer.shadowOffset = .zero
        statsHUD.layer.shadowOpacity = 0.8
        statsHUD.layer.shadowRadius = 4

        statsHUD.addArrangedSubview(makeStatsHUDItem(icon: "users", label: statsPeersLabel))
        statsHUD.addArrangedSubview(makeStatsHUDItem(icon: "chevron-down", label: statsDownLabel))
        statsHUD.addArrangedSubview(makeStatsHUDItem(icon: "chevron-up", label: statsUpLabel))

        overlay.addSubview(statsHUD)
        NSLayoutConstraint.activate([
            statsHUD.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            statsHUD.centerXAnchor.constraint(equalTo: view.centerXAnchor),
        ])
    }

    private func makeStatsHUDItem(icon: String, label: UILabel) -> UIStackView {
        let imageView = UIImageView(image: UIImage.hayaseIcon(icon, withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .bold)))
        imageView.tintColor = .white
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalToConstant: 18),
            imageView.heightAnchor.constraint(equalToConstant: 18),
        ])

        label.font = .nunito(ofSize: 18, weight: .bold)
        label.textColor = .white
        label.setContentHuggingPriority(.required, for: .horizontal)

        let stack = UIStackView(arrangedSubviews: [imageView, label])
        stack.axis = .horizontal
        stack.spacing = 8
        stack.alignment = .center
        return stack
    }

    private func setupMobilePlayerControls() {
        mobileOptionsButton.translatesAutoresizingMaskIntoConstraints = false
        mobileOptionsButton.tintColor = .white
        mobileOptionsButton.backgroundColor = UIColor.HayaseTheme.background.withAlphaComponent(0.2)
        mobileOptionsButton.layer.cornerRadius = 24
        mobileOptionsButton.clipsToBounds = true
        mobileOptionsButton.setImage(UIImage.hayaseIcon("ellipsis-vertical"), for: .normal)
        mobileOptionsButton.imageEdgeInsets = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        mobileOptionsButton.addTarget(self, action: #selector(optionsTapped), for: .touchUpInside)
        overlay.addSubview(mobileOptionsButton)

        mobileControlsStack.translatesAutoresizingMaskIntoConstraints = false
        mobileControlsStack.axis = .horizontal
        mobileControlsStack.spacing = 40
        mobileControlsStack.alignment = .center
        overlay.addSubview(mobileControlsStack)

        configureMobileControlButton(mobilePrevButton,
                                     icon: "skip-back",
                                     size: 40,
                                     inset: 12,
                                     action: #selector(prevTapped))
        configureMobileControlButton(mobilePlayPauseButton,
                                     icon: "pause",
                                     size: 48,
                                     inset: 12,
                                     action: #selector(playPauseTapped))
        configureMobileControlButton(mobileNextButton,
                                     icon: "skip-forward",
                                     size: 40,
                                     inset: 12,
                                     action: #selector(nextTapped))

        mobileControlsStack.addArrangedSubview(mobilePrevButton)
        mobileControlsStack.addArrangedSubview(mobilePlayPauseButton)
        mobileControlsStack.addArrangedSubview(mobileNextButton)

        NSLayoutConstraint.activate([
            mobileOptionsButton.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),
            mobileOptionsButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            mobileOptionsButton.widthAnchor.constraint(equalToConstant: 48),
            mobileOptionsButton.heightAnchor.constraint(equalToConstant: 48),

            mobileControlsStack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            mobileControlsStack.centerYAnchor.constraint(equalTo: view.centerYAnchor),

            mobilePrevButton.widthAnchor.constraint(equalToConstant: 40),
            mobilePrevButton.heightAnchor.constraint(equalToConstant: 40),
            mobilePlayPauseButton.widthAnchor.constraint(equalToConstant: 48),
            mobilePlayPauseButton.heightAnchor.constraint(equalToConstant: 48),
            mobileNextButton.widthAnchor.constraint(equalToConstant: 40),
            mobileNextButton.heightAnchor.constraint(equalToConstant: 40),
        ])
    }

    private func configureMobileControlButton(_ button: UIButton,
                                              icon: String,
                                              size: CGFloat,
                                              inset: CGFloat,
                                              action: Selector) {
        button.translatesAutoresizingMaskIntoConstraints = false
        button.tintColor = .white
        button.backgroundColor = UIColor.HayaseTheme.background.withAlphaComponent(0.2)
        button.layer.cornerRadius = size / 2
        button.clipsToBounds = true
        button.setImage(UIImage.hayaseFilledIcon(icon), for: .normal)
        button.imageEdgeInsets = UIEdgeInsets(top: inset, left: inset, bottom: inset, right: inset)
        button.addTarget(self, action: action, for: .touchUpInside)
    }

    private func setupInterfacePlayerOverlays() {
        bufferingSpinner.translatesAutoresizingMaskIntoConstraints = false
        overlay.addSubview(bufferingSpinner)

        fastForwardBadge.translatesAutoresizingMaskIntoConstraints = false
        fastForwardBadge.backgroundColor = UIColor.HayaseTheme.background.withAlphaComponent(0.6)
        fastForwardBadge.layer.cornerRadius = 16
        fastForwardBadge.clipsToBounds = true
        fastForwardBadge.alpha = 0
        fastForwardBadge.isHidden = true
        fastForwardBadge.isUserInteractionEnabled = false

        fastForwardLabel.translatesAutoresizingMaskIntoConstraints = false
        fastForwardLabel.font = .nunito(ofSize: 14, weight: .bold)
        fastForwardLabel.textColor = .white
        fastForwardLabel.text = "x2"
        fastForwardLabel.setContentHuggingPriority(.required, for: .horizontal)

        fastForwardIcon.translatesAutoresizingMaskIntoConstraints = false
        fastForwardIcon.tintColor = .white
        fastForwardIcon.contentMode = .scaleAspectFit

        let fastForwardStack = UIStackView(arrangedSubviews: [fastForwardLabel, fastForwardIcon])
        fastForwardStack.translatesAutoresizingMaskIntoConstraints = false
        fastForwardStack.axis = .horizontal
        fastForwardStack.alignment = .center
        fastForwardStack.spacing = 8
        fastForwardBadge.addSubview(fastForwardStack)
        overlay.addSubview(fastForwardBadge)

        skipChapterButton.translatesAutoresizingMaskIntoConstraints = false
        skipChapterButton.alpha = 0
        skipChapterButton.isHidden = true
        skipChapterButton.onTrigger = { [weak self] in self?.skipCurrentChapter() }
        overlay.addSubview(skipChapterButton)

        NSLayoutConstraint.activate([
            bufferingSpinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            bufferingSpinner.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            bufferingSpinner.widthAnchor.constraint(equalToConstant: 40),
            bufferingSpinner.heightAnchor.constraint(equalToConstant: 40),

            fastForwardBadge.topAnchor.constraint(equalTo: view.topAnchor, constant: 40),
            fastForwardBadge.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            fastForwardStack.topAnchor.constraint(equalTo: fastForwardBadge.topAnchor, constant: 8),
            fastForwardStack.bottomAnchor.constraint(equalTo: fastForwardBadge.bottomAnchor, constant: -8),
            fastForwardStack.leadingAnchor.constraint(equalTo: fastForwardBadge.leadingAnchor, constant: 16),
            fastForwardStack.trailingAnchor.constraint(equalTo: fastForwardBadge.trailingAnchor, constant: -16),
            fastForwardIcon.widthAnchor.constraint(equalToConstant: 12),
            fastForwardIcon.heightAnchor.constraint(equalToConstant: 12),

            skipChapterButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40),
            skipChapterButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -160),
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
        titleLabel.font = .nunito(ofSize: 18, weight: .regular)
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
        episodeLabel.font = .nunito(ofSize: 14, weight: .light)
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
        chapterLabel.font = .nunito(ofSize: 12, weight: .light)
        chapterLabel.textAlignment = .right
        chapterLabel.lineBreakMode = .byTruncatingTail
        chapterLabel.text = ""
        bottomBar.addSubview(chapterLabel)

        timeLabel.translatesAutoresizingMaskIntoConstraints = false
        timeLabel.textColor = .white
        timeLabel.font = .nunito(ofSize: 13, weight: .light)
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

        // --- Row 2: Seekbar (full width, chapter-segmented — matching interface seekbar.svelte) ---
        seekBar.translatesAutoresizingMaskIntoConstraints = false
        seekBar.addTarget(self, action: #selector(seekBegan),   for: .touchDown)
        seekBar.addTarget(self, action: #selector(seekChanged), for: .valueChanged)
        seekBar.addTarget(self, action: #selector(seekEnded),   for: [.touchUpInside, .touchUpOutside])
        bottomBar.addSubview(seekBar)

        // --- Row 3: Controls ---
        // Left side: play/pause, prev, next
        [prevButton, playPauseButton, nextButton, optionsButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            $0.tintColor = .white
        }
        prevButton.setImage(UIImage.hayaseFilledIcon("skip-back"), for: .normal)
        playPauseButton.setImage(UIImage.hayaseFilledIcon("pause"), for: .normal)
        nextButton.setImage(UIImage.hayaseFilledIcon("skip-forward"), for: .normal)
        optionsButton.setImage(UIImage.hayaseIcon("ellipsis-vertical"), for: .normal)

        prevButton.addTarget(self,      action: #selector(prevTapped),      for: .touchUpInside)
        playPauseButton.addTarget(self, action: #selector(playPauseTapped), for: .touchUpInside)
        nextButton.addTarget(self,      action: #selector(nextTapped),      for: .touchUpInside)
        optionsButton.addTarget(self,   action: #selector(optionsTapped),   for: .touchUpInside)

        // Initial enable state mirrors loadVideoURL() logic — use episode bounds
        // rather than just allVideos array bounds so buttons are correct even
        // before MPV starts (important for mini-player restore where viewDidLoad
        // runs immediately via `_ = player.view`).
        prevButton.isEnabled  = episodeNumber > 1
        if totalEpisodes > 0 {
            nextButton.isEnabled = episodeNumber < totalEpisodes
        } else {
            nextButton.isEnabled = true
        }
        mobilePrevButton.isEnabled = prevButton.isEnabled
        mobileNextButton.isEnabled = nextButton.isEnabled

        bottomLeftControls.translatesAutoresizingMaskIntoConstraints = false
        bottomLeftControls.axis = .horizontal
        bottomLeftControls.spacing = 4
        bottomLeftControls.addArrangedSubview(playPauseButton)
        bottomLeftControls.addArrangedSubview(prevButton)
        bottomLeftControls.addArrangedSubview(nextButton)
        bottomBar.addSubview(bottomLeftControls)

        // Right side: speed label, options, AirPlay
        speedLabel.translatesAutoresizingMaskIntoConstraints = false
        speedLabel.textColor = .white
        speedLabel.font = .nunito(ofSize: 14, weight: .bold)
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

        bottomRightControls.translatesAutoresizingMaskIntoConstraints = false
        bottomRightControls.axis = .horizontal
        bottomRightControls.spacing = 4
        bottomRightControls.alignment = .center
        bottomRightControls.addArrangedSubview(speedLabel)
        bottomRightControls.addArrangedSubview(optionsButton)
        bottomRightControls.addArrangedSubview(airPlayPicker)
        bottomBar.addSubview(bottomRightControls)

        let pad: CGFloat = 24
        let baseConstraints = [
            // Row 1: title + episode (left), chapter + time (right)
            // Hayase: title on top, episode below; chapter above time on right
            titleLabel.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor, constant: pad),
            titleLabel.topAnchor.constraint(equalTo: bottomBar.topAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: chapterLabel.leadingAnchor, constant: -12),

            episodeLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            episodeLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            episodeLabel.trailingAnchor.constraint(lessThanOrEqualTo: timeLabel.leadingAnchor, constant: -12),

            chapterLabel.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor, constant: -pad),
            chapterLabel.bottomAnchor.constraint(equalTo: timeLabel.topAnchor, constant: -2),

            timeLabel.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor, constant: -pad),
            timeLabel.centerYAnchor.constraint(equalTo: episodeLabel.centerYAnchor),

            // Row 2: seekbar
            seekBar.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor, constant: pad),
            seekBar.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor, constant: -pad),
            seekBar.topAnchor.constraint(equalTo: episodeLabel.bottomAnchor, constant: 0),
            seekBar.heightAnchor.constraint(equalToConstant: 32),
        ]

        bottomControlConstraints = [
            // Row 3: controls
            bottomLeftControls.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor, constant: pad),
            bottomLeftControls.topAnchor.constraint(equalTo: seekBar.bottomAnchor, constant: 0),
            bottomLeftControls.bottomAnchor.constraint(equalTo: bottomBar.bottomAnchor, constant: -10),
            bottomLeftControls.heightAnchor.constraint(equalToConstant: 44),

            bottomRightControls.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor, constant: -pad),
            bottomRightControls.centerYAnchor.constraint(equalTo: bottomLeftControls.centerYAnchor),
            bottomRightControls.heightAnchor.constraint(equalToConstant: 44),

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
        ]
        mobileSeekBarBottomConstraint = seekBar.bottomAnchor.constraint(equalTo: bottomBar.bottomAnchor, constant: -12)
        NSLayoutConstraint.activate(baseConstraints + bottomControlConstraints)
        applyInterfaceMobilePlayerLayout()
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

        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleHoldToFastForward(_:)))
        longPress.minimumPressDuration = 1.0
        longPress.allowableMovement = 40
        longPress.delegate = self
        view.addGestureRecognizer(longPress)
        longPressRecognizer = longPress
    }

    /// Single-tap: toggle controls visibility.
    @objc private func handleSingleTap(_ gesture: UITapGestureRecognizer) {
        setControls(visible: !controlsVisible)
    }

    /// Double-tap: left/right quarters seek; center toggles fullscreen.
    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        let tapLocation = gesture.location(in: surface)
        handleInterfaceDoubleTap(at: tapLocation)
    }

    @objc private func handleHoldToFastForward(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began:
            startFastForward()
        case .ended, .cancelled, .failed:
            stopFastForward()
        default:
            break
        }
    }

    /// Returns the seek duration (seconds) from user settings (pref_seekDuration), defaulting to 2.
    private var seekDurationSeconds: Double {
        let stored = UserDefaults.standard.string(forKey: "pref_seekDuration") ?? "2"
        return Double(stored) ?? 2
    }

    /// Mirrors player.svelte mobile overlay: left/right quarter double-taps seek,
    /// the center double-tap falls through to fullscreen().
    private func handleInterfaceDoubleTap(at location: CGPoint) {
        let leftSeekEdge = surface.bounds.width * 0.25
        let rightSeekEdge = surface.bounds.width * 0.75
        if location.x < leftSeekEdge {
            performDoubleTapSeek(forward: false)
        } else if location.x > rightSeekEdge {
            performDoubleTapSeek(forward: true)
        } else {
            toggleFullscreenPresentation()
        }
    }

    private func performDoubleTapSeek(forward: Bool) {
        let seekAmount = seekDurationSeconds
        if forward {
            let newTime = min(duration, currentTime + seekAmount)
            let fraction = duration > 0 ? newTime / duration : 0
            streamer?.seekTo(fraction: fraction)
            surface.mpv.seek(by: seekAmount)
            currentTime = newTime
            lastSeekTime = Date()
            showPlayerAnimation(icon: "fast-forward")
        } else {
            let newTime = max(0, currentTime - seekAmount)
            let fraction = duration > 0 ? newTime / duration : 0
            streamer?.seekTo(fraction: fraction)
            surface.mpv.seek(by: -seekAmount)
            currentTime = newTime
            lastSeekTime = Date()
            showPlayerAnimation(icon: "rewind")
        }
        updateTimeUI()
    }

    private func showPlayerAnimation(icon: String) {
        guard let image = UIImage.hayaseFilledIcon(icon, pointSize: 64) else { return }
        let iconView = UIImageView(image: image)
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.tintColor = .white
        iconView.alpha = 1
        iconView.contentMode = .scaleAspectFit
        iconView.isUserInteractionEnabled = false
        overlay.addSubview(iconView)
        NSLayoutConstraint.activate([
            iconView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 64),
            iconView.heightAnchor.constraint(equalToConstant: 64),
        ])
        UIView.animate(withDuration: 0.4, delay: 0, options: [.curveLinear]) {
            iconView.alpha = 0
            iconView.transform = CGAffineTransform(scaleX: 1.2, y: 1.2)
        } completion: { _ in
            iconView.removeFromSuperview()
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
        currentSkippableChapter = nil
        skipChapterButton.stopProgress()
        updateChapterMarkers()
        updateBuffering(true)

        // Set up torrent streaming if the file is still downloading.
        setupStreamer { [weak self] in
            guard let self else { return }

            // Load MPV after the local HTTP server is ready. The server blocks
            // HTTP responses until required pieces are downloaded, so MPV
            // naturally waits for head data without a separate pre-wait.
            if let s = self.streamer, s.isActive {
                StreamingLogger.shared.info("Streaming — waiting for head pieces…")
            }
            self.loadVideoURL()
        }

        // Set initial AniList state (PLANNING → CURRENT, COMPLETED → REPEATING) for ep 1
        AniListTracking.shared.setInitialState(anilistID: anilistID, episode: episodeNumber)

        // W2G: notify peers about the media we're playing (mirrors web's
        // server.play() calling w2globby.value?.mediaChange({ torrent, mediaId, episode })).
        if let hash = currentW2GTorrentHash, anilistID > 0 {
            W2GLobby.shared.client?.mediaChange(
                W2GMediaState(torrent: hash, mediaId: anilistID, episode: episodeNumber)
            )
            W2GLobby.shared.client?.mediaIndexChanged(currentVideoIndex)
        }
    }

    /// Switch to a different file index within the same torrent, triggered by
    /// a remote W2G index event.
    /// Mirrors web mediahandler.svelte: `$: $w2globby?.on('index', index => { current = fileToMedaInfo(mediaInfo.resolvedFiles[index]) })`
    func applyRemoteW2GIndex(_ newIndex: Int) {
        guard newIndex >= 0, newIndex < allVideos.count else { return }
        let idx = UInt(newIndex)
        guard idx != fileIndex else { return }
        let video = allVideos[newIndex]
        // Estimate episode number from index offset (batch torrents map 1:1).
        // Same assumption as findVideoInBatch/switchToVideo — episode = base + delta.
        switchToVideo((video: video, index: newIndex), episode: episodeNumber + (newIndex - currentVideoIndex))
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
            // MKV duration probing: MPV's default is "no" (set in MPVWrapper
            // — we no longer set it to "yes" globally). We explicitly confirm
            // "no" here as a belt-and-suspenders guard. Without probing, MPV
            // reads duration from the MKV Info element in the first 1–2 pieces
            // instead of making a separate Range request to the tail. When
            // probe=yes (the old global default) MPV's tail request blocked
            // LocalStreamServer until tail pieces arrived; combined with tight
            // head-piece deadlines this split bandwidth across 12+ simultaneous
            // deadline pieces, causing 700 MB to be downloaded before playback
            // started (vs WebTorrent desktop's ~100 MB). Seeking still works
            // via force-seekable=yes; LocalStreamServer.waitForLocalPieces
            // blocks reactively on the exact tail pieces needed per seek.
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
            // Unknown total (ongoing anime like One Piece where AniList returns
            // episodes: nil). The web interface's episodes() helper falls back to
            // the latest aired episode from schedule data — iOS doesn't have that,
            // so always allow next navigation. There's always potentially a next
            // episode for an ongoing series.
            canGoNext = true
        }
        prevButton.isEnabled = canGoPrev
        nextButton.isEnabled = canGoNext
        mobilePrevButton.isEnabled = canGoPrev
        mobileNextButton.isEnabled = canGoNext
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

    /// Creates a TorrentStreamer and LocalStreamServer for the active file.
    /// The streamer manages piece deadlines for proactive prefetching and is
    /// only created when the file is still downloading. The HTTP server is
    /// always started so MPV reads from a consistent HTTP URL regardless of
    /// download state — this avoids issues (e.g. next-episode navigation
    /// stalling) that arise from switching between HTTP and file:// URLs.
    private func setupStreamer(completion: @escaping () -> Void) {
        // Stop any previous streamer / server
        streamServer?.stop()
        streamServer = nil
        streamer?.stop()
        streamer = nil

        guard let handle = torrentHandle else {
            completion()
            return
        }

        // Create a TorrentStreamer only when the file is not yet fully downloaded.
        // It manages piece deadlines for proactive prefetching; not needed once
        // all pieces are on disk.
        if !isFileFullyDownloaded() {
            let s = TorrentStreamer(torrentHandle: handle, fileIndex: fileIndex)
            s.start()
            streamer = s
            StreamingLogger.shared.info("Streamer started — pieces \(s.beginPiece)–\(s.endPiece) (\(s.totalFilePieces) total)")
        }

        // Always start a local HTTP server so MPV reads from HTTP regardless of
        // download state. The server gates responses on piece availability while
        // downloading; for fully-downloaded files all pieces return immediately.
        let path = videoEntity?.videoPath ?? ""
        guard !path.isEmpty else {
            completion()
            return
        }

        let server = LocalStreamServer(torrentHandle: handle, fileIndex: fileIndex, filePath: path)
        streamServer = server
        server.start { [weak self] result in
            guard let self, self.streamServer === server else { return }

            switch result {
            case .success:
                if UserDefaults.standard.bool(forKey: "pref_showLogger") { print("LocalStreamServer: started for file \(self.fileIndex) at \(server.url)") }
            case .failure(let error):
                self.streamServer = nil
                StreamingLogger.shared.error("Stream server failed: \(error.localizedDescription)")
                if UserDefaults.standard.bool(forKey: "pref_showLogger") { print("LocalStreamServer: failed to start — \(error)") }
                // Fall back to direct file path (original behavior)
            }
            completion()
        }
    }

    // MARK: - Matroska language parsing

    /// Returns a `file://` URL for the current MKV on disk (if available)
    /// so `matroska-swift` can parse subtitle track languages directly from
    /// the container header. Returns `nil` for non-file or unknown paths.
    private func mkvFileURLForLanguageParsing() -> URL? {
        guard let path = videoEntity?.videoPath, !path.isEmpty else { return nil }
        let url = URL(fileURLWithPath: path)
        let ext = url.pathExtension.lowercased()
        guard ext == "mkv" || ext == "webm" else { return nil }
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        return url
    }

    // MARK: - Download stats

    func resumeStatsUpdates() {
        startStatsTimer()
    }

    private func startStatsTimer() {
        statsTimer?.invalidate()
        guard torrentHandle != nil || isWebTorrentPlayback else { return }
        statsHUD.isHidden = false
        updateStats()
        let timer = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.updateStats()
        }
        RunLoop.main.add(timer, forMode: .common)
        statsTimer = timer
    }

    private var isWebTorrentPlayback: Bool {
        guard torrentHandle == nil,
              videoEntity?.torrents != nil,
              let path = videoEntity?.videoPath?.lowercased() else { return false }
        return path.hasPrefix("http://") || path.hasPrefix("https://")
    }

    private func updateStats() {
        if let handle = torrentHandle {
            updateNativeTorrentStats(handle: handle)
            return
        }

        updateWebTorrentStats()
    }

    private func updateWebTorrentStats() {
        guard isWebTorrentPlayback, !webStatsUpdateInFlight else { return }
        webStatsUpdateInFlight = true

        // The bridge status endpoint is the reliable live source for player HUD
        // counters. torrentInfo can legitimately lag while metadata is being
        // refreshed, which used to leave webStatsUpdateInFlight stuck or show
        // stale/zero values until a seek or pause kicked the player again.
        TorrentBackendManager.shared.webTorrentStatus { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.webStatsUpdateInFlight = false
                guard case .success(let status) = result else { return }
                self.applyWebTorrentStats(peers: status.wires,
                                           downloadSpeed: status.downloadSpeed ?? 0,
                                           uploadSpeed: status.uploadSpeed ?? 0)
            }
        }
    }

    private func applyWebTorrentStats(peers: Int, downloadSpeed: UInt64, uploadSpeed: UInt64) {
        statsHUD.isHidden = false
        statsPeersLabel.text = "\(peers)"
        statsDownLabel.text = "\(fmtBits(downloadSpeed * 8))/s"
        statsUpLabel.text = "\(fmtBits(uploadSpeed * 8))/s"
    }

    private func updateNativeTorrentStats(handle: TorrentHandle) {
        let state: (TorrentHandle.Snapshot, Bool)? = TorrentService.sharedTorrentService.withActiveHandle(handle, default: nil) { activeHandle in
            activeHandle.updateSnapshot()
            let snap = activeHandle.snapshot
            if snap.isSeed { return (snap, true) }
            if let entry = snap.files.first(where: { $0.index == Int(self.fileIndex) }) {
                return (snap, entry.size > 0 && entry.downloaded >= entry.size)
            }
            return (snap, false)
        }
        guard let (snap, isComplete) = state else { return }

        if isComplete {
            // Stop the streamer — piece management is no longer needed.
            // Do NOT stop streamServer here: MPV is still reading from the
            // HTTP URL. Stopping the server mid-playback causes read errors
            // and playback failure. The server is stopped in viewWillDisappear
            // and prev/next episode transitions.
            if streamer != nil {
                streamer?.stop()
                streamer = nil
            }
        }
        // Hayase downloadstats.svelte: Users, ChevronDown, ChevronUp.
        let peers = snap.numberOfSeeds
        let downBits = fmtBits(snap.downloadRate * 8)
        let upBits = fmtBits(snap.uploadRate * 8)
        statsPeersLabel.text = "\(peers)"
        statsDownLabel.text = "\(downBits)/s"
        statsUpLabel.text = "\(upBits)/s"
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
            return AniListUtil.title(for: anime)
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
        return TorrentService.sharedTorrentService.withActiveHandle(handle, default: true) { activeHandle in
            activeHandle.updateSnapshot()
            let snap = activeHandle.snapshot
            // isSeed means the entire torrent is downloaded — always reliable.
            if snap.isSeed { return true }
            // Check byte-level progress for the specific file we're playing.
            if let entry = snap.files.first(where: { $0.index == Int(self.fileIndex) }) {
                return entry.size > 0 && entry.downloaded >= entry.size
            }
            return false
        }
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
            saveProgress()
            AniListTracking.shared.watch(anilistID: anilistID, episodeProgress: episodeNumber)
        }
    }

    // MARK: - Controls visibility

    private func scheduleHide() {
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self,
                  !self.isPaused,
                  !self.isSeeking,
                  !self.isBuffering,
                  !self.isFastForwarding else { return }
            self.setControls(visible: false)
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
    }

    private func setControls(visible: Bool) {
        controlsVisible = visible
        overlay.alpha = 1
        updateInterfaceOverlayVisibility(animated: true)
        setNeedsStatusBarAppearanceUpdate()
        setNeedsUpdateOfHomeIndicatorAutoHidden()
        if visible { scheduleHide() }
    }

    private func updateInterfaceOverlayVisibility(animated: Bool) {
        overlay.alpha = 1
        bufferingSpinner.setAnimating(isBuffering)

        let controlsAlpha: CGFloat = controlsVisible ? 1 : 0
        let mobileControlsAlpha: CGFloat = controlsVisible && !isSeeking ? 1 : 0
        let showFastForward = isFastForwarding
        let showSkip = controlsVisible && currentSkippableChapter != nil

        if showFastForward { fastForwardBadge.isHidden = false }
        if showSkip { skipChapterButton.isHidden = false }

        mobileOptionsButton.isUserInteractionEnabled = controlsVisible
        mobileControlsStack.isUserInteractionEnabled = controlsVisible && !isSeeking
        bottomBar.isUserInteractionEnabled = controlsVisible
        skipChapterButton.isUserInteractionEnabled = showSkip

        let changes = {
            self.statsHUD.alpha = controlsAlpha
            self.mobileOptionsButton.alpha = controlsAlpha
            self.mobileControlsStack.alpha = mobileControlsAlpha
            self.bottomBar.alpha = controlsAlpha
            self.skipChapterButton.alpha = showSkip ? 1 : 0
            self.fastForwardBadge.alpha = showFastForward ? 1 : 0
            self.mobilePlayPauseButton.alpha = self.isBuffering ? 0.10 : 1
        }

        let completion: (Bool) -> Void = { _ in
            if !showFastForward { self.fastForwardBadge.isHidden = true }
            if !showSkip { self.skipChapterButton.isHidden = true }
        }

        if animated {
            UIView.animate(withDuration: 0.25, animations: changes, completion: completion)
        } else {
            changes()
            completion(true)
        }
    }

    private func updateBuffering(_ buffering: Bool) {
        guard isBuffering != buffering else { return }
        isBuffering = buffering
        if buffering {
            setControls(visible: true)
        } else {
            updateInterfaceOverlayVisibility(animated: true)
            if !isPaused { scheduleHide() }
        }
    }

    private func startFastForward() {
        guard !isFastForwarding else { return }
        playbackRateBeforeFastForward = playbackRate
        wasPausedBeforeFastForward = isPaused
        isFastForwarding = true
        if isPaused {
            surface.mpv.play()
        }
        playbackRate = 2
        surface.mpv.setSpeed(2)
        updateSpeedLabel()
        updateInterfaceOverlayVisibility(animated: true)
    }

    private func stopFastForward() {
        guard isFastForwarding else { return }
        isFastForwarding = false
        playbackRate = playbackRateBeforeFastForward
        surface.mpv.setSpeed(playbackRate)
        updateSpeedLabel()
        if wasPausedBeforeFastForward {
            surface.mpv.pausePlayback()
        }
        updateInterfaceOverlayVisibility(animated: true)
        if !wasPausedBeforeFastForward && !isPaused { scheduleHide() }
    }

    private func applyInterfaceMobilePlayerLayout() {
        NSLayoutConstraint.deactivate(bottomControlConstraints)
        mobileSeekBarBottomConstraint?.isActive = true
        bottomLeftControls.isHidden = true
        bottomRightControls.isHidden = true
        mobileControlsStack.isHidden = false
        mobileOptionsButton.isHidden = false
        updateInterfaceOverlayVisibility(animated: false)
    }

    // MARK: - Time UI

    private func updateTimeUI() {
        guard !isSeeking else { return }
        seekBar.value = duration > 0 ? CGFloat(currentTime / duration) : 0
        // Hayase format: "current / total" or "-remaining / total"
        if showRemainingTime {
            timeLabel.text = "-\(fmtTime(max(0, duration - currentTime))) / \(fmtTime(duration))"
        } else {
            timeLabel.text = "\(fmtTime(currentTime)) / \(fmtTime(duration))"
        }
        chapterLabel.text = chapterTitle(at: currentTime)
        updateSkipChapterButton()
    }

    private func fmtTime(_ secs: Double) -> String {
        let s = max(0, Int(secs))
        let h = s / 3600; let m = (s % 3600) / 60; let sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec)
                     : String(format: "%d:%02d", m, sec)
    }

    private func updateChapterMarkers() {
        seekBar.setChapters(chapters, duration: duration)
    }

    private func chapterWindow(at time: Double) -> (title: String, start: Double, end: Double)? {
        guard duration > 0, !chapters.isEmpty else { return nil }
        let sorted = chapters.sorted { $0.time < $1.time }
        for (index, chapter) in sorted.enumerated() {
            let start = max(0, chapter.time)
            let end = index + 1 < sorted.count ? sorted[index + 1].time : duration
            if time >= start && time <= end {
                return (chapter.title, start, min(duration, max(start, end)))
            }
        }
        return nil
    }

    private func chapterTitle(at time: Double) -> String {
        chapterWindow(at: time)?.title ?? ""
    }

    private func skippableChapter(at time: Double) -> SkippableChapter? {
        guard let chapter = chapterWindow(at: time),
              let skipType = skipType(for: chapter.title) else { return nil }
        return SkippableChapter(title: chapter.title, end: chapter.end, skipType: skipType)
    }

    private func skipType(for chapterText: String) -> String? {
        let patterns: [(String, String)] = [
            ("Opening", "^op$|opening$|^ncop|^opening "),
            ("Ending", "^ed$|ending$|^nced|^ending "),
            ("Intro", "^intro$"),
            ("Outro", "^outro$"),
            ("Credits", "^credits$"),
            ("Preview", "^preview$"),
            ("Recap", "recap"),
        ]
        let range = NSRange(chapterText.startIndex..<chapterText.endIndex, in: chapterText)
        for (skipType, pattern) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .anchorsMatchLines]) else {
                continue
            }
            if regex.firstMatch(in: chapterText, options: [], range: range) != nil {
                return skipType
            }
        }
        return nil
    }

    private func updateSkipChapterButton() {
        let next = skippableChapter(at: currentTime)
        guard next != currentSkippableChapter else { return }
        currentSkippableChapter = next
        if let next {
            skipChapterButton.setTitle("Skip \(next.skipType)")
            skipChapterButton.stopProgress()
        } else {
            skipChapterButton.stopProgress()
        }
        updateInterfaceOverlayVisibility(animated: true)
    }

    private func skipCurrentChapter() {
        guard let current = currentSkippableChapter ?? skippableChapter(at: currentTime),
              duration > 0 else { return }
        let targetTime = min(duration, current.end + 0.5)
        let fraction = max(0, min(1, targetTime / duration))
        streamer?.seekTo(fraction: fraction)
        surface.mpv.seek(to: targetTime)
        lastSeekTime = Date()
        currentTime = targetTime
        currentSkippableChapter = nil
        skipChapterButton.stopProgress()
        updateTimeUI()
        updateInterfaceOverlayVisibility(animated: true)
        scheduleHide()
    }

    // MARK: - Actions

    @objc private func playPauseTapped() {
        showPlayerAnimation(icon: isPaused ? "play" : "pause")
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
        if let idx = videoEntity?.videoIndex, idx.intValue >= 0 {
            fileIndex = UInt(idx.intValue)
            videoService?.selectFileForStreaming(fileIndex)
            _ = videoService?.UpdateFilePathForFileIndex(fileIndex)
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
        updateInterfaceOverlayVisibility(animated: true)
    }

    @objc private func seekChanged() {
        let t = Double(seekBar.value) * duration
        if showRemainingTime {
            timeLabel.text = "-\(fmtTime(max(0, duration - t))) / \(fmtTime(duration))"
        } else {
            timeLabel.text = "\(fmtTime(t)) / \(fmtTime(duration))"
        }
        chapterLabel.text = chapterTitle(at: t)
        updateInterfaceOverlayVisibility(animated: true)
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
        updateInterfaceOverlayVisibility(animated: true)
        scheduleHide()
    }

    @objc private func optionsTapped() {
        hideWork?.cancel()
        showOptionsSheet()
    }

    @objc private func speedLabelTapped() {
        hideWork?.cancel()
        showOptionsSheet()
    }

    /// Updates the speed label text. Hayase shows "x1.5" only when rate ≠ 1.
    private func updateSpeedLabel() {
        if playbackRate != 1.0 && playbackRate != 0.0 {
            speedLabel.text = "x\(String(format: "%g", playbackRate))"
        } else {
            speedLabel.text = ""
        }
    }

    // MARK: - Options sheet (Hayase options.svelte — tree-style menu)

    private func makeTrack(from dict: [String: Any], type: String) -> MPVTrack? {
        guard let id = dict["id"] as? Int else { return nil }
        return MPVTrack(id: id,
                        type: type,
                        title: dict["title"] as? String,
                        lang: dict["lang"] as? String,
                        isSelected: dict["selected"] as? Bool ?? false)
    }

    private func readTracks(from renderer: MPVWrapper, includeMkvLanguages: Bool = false) -> [MPVTrack] {
        let mkvURL = includeMkvLanguages ? mkvFileURLForLanguageParsing() : nil
        var result: [MPVTrack] = []

        for dict in renderer.getSubtitleTracks(mkvFileURL: mkvURL) {
            if let track = makeTrack(from: dict, type: "sub") {
                result.append(track)
            }
        }
        for dict in renderer.getAudioTracks() {
            if let track = makeTrack(from: dict, type: "audio") {
                result.append(track)
            }
        }

        return result
    }

    private func mergeCachedTrackMetadata(into freshTracks: [MPVTrack]) -> [MPVTrack] {
        guard !tracks.isEmpty else { return freshTracks }
        let cachedByKey = Dictionary(tracks.map { (trackKey($0), $0) }, uniquingKeysWith: { first, _ in first })

        return freshTracks.map { fresh in
            guard let cached = cachedByKey[trackKey(fresh)] else { return fresh }
            return MPVTrack(id: fresh.id,
                            type: fresh.type,
                            title: fresh.title ?? cached.title,
                            lang: fresh.lang ?? cached.lang,
                            isSelected: fresh.isSelected)
        }
    }

    private func currentTracksForOptions() -> [MPVTrack] {
        let freshTracks = readTracks(from: surface.mpv)
        guard !freshTracks.isEmpty else { return tracks }
        return mergeCachedTrackMetadata(into: freshTracks)
    }

    private func trackKey(_ track: MPVTrack) -> String {
        "\(track.type):\(track.id)"
    }

    private func showOptionsSheet() {
        // Keep this synchronous path cheap so the menu appears immediately.
        // MKV language parsing can touch disk and is done from track readiness instead.
        let freshTracks = currentTracksForOptions()
        self.tracks = freshTracks

        let optionsVC = PlayerOptionsController()
        optionsVC.modalPresentationStyle = .overFullScreen
        optionsVC.modalTransitionStyle = .crossDissolve

        // Populate data
        optionsVC.audioTracks = freshTracks.filter { $0.type == "audio" }
        optionsVC.subtitleTracks = freshTracks.filter { $0.type == "sub" }
        optionsVC.chapters = chapters
        optionsVC.currentSpeed = playbackRate
        optionsVC.subtitleDelay = subtitleDelay
        optionsVC.isDebandActive = UserDefaults.standard.bool(forKey: "pref_deband")
        optionsVC.isFullscreenActive = isFullscreenPresentation
        optionsVC.allVideos = allVideos
        optionsVC.currentVideoEntity = videoEntity

        if #available(iOS 15.0, *) {
            optionsVC.isPiPActive = pipController?.isPictureInPictureActive ?? false
        }

        // Wire callbacks
        optionsVC.onSelectAudioTrack = { [weak self] trackId in
            self?.surface.mpv.setAudioTrack(trackId)
        }

        optionsVC.onSelectSubtitleTrack = { [weak self] trackId in
            self?.surface.mpv.setSubtitleTrack(trackId)
        }

        optionsVC.onSetSpeed = { [weak self] rate in
            guard let self else { return }
            self.playbackRate = rate
            self.surface.mpv.setSpeed(rate)
            self.updateSpeedLabel()
        }

        optionsVC.onSeekTo = { [weak self] time in
            self?.surface.mpv.seek(to: time)
        }

        optionsVC.onSwitchVideo = { [weak self] video in
            guard let self else { return }
            if let idx = self.allVideos.firstIndex(of: video), idx != self.currentVideoIndex {
                let targetEpisode = self.episodeNumber + (idx - self.currentVideoIndex)
                self.switchToVideo((video: video, index: idx), episode: targetEpisode)
            }
        }

        optionsVC.onToggleDeband = { [weak self] in
            let current = UserDefaults.standard.bool(forKey: "pref_deband")
            let newValue = !current
            UserDefaults.standard.set(newValue, forKey: "pref_deband")
            self?.surface.mpv.setDeband(newValue)
        }

        optionsVC.onTogglePiP = { [weak self] in
            guard let self else { return }
            if #available(iOS 15.0, *) {
                if self.pipController?.isPictureInPictureActive ?? false {
                    self.pipController?.stopPictureInPicture()
                } else {
                    self.pipController?.startPictureInPicture()
                }
            }
        }

        optionsVC.onToggleFullscreen = { [weak self] in
            self?.toggleFullscreenPresentation()
        }

        optionsVC.onSubtitleDelayChanged = { [weak self] delay in
            self?.subtitleDelay = delay
            self?.surface.mpv.setSubtitleDelay(delay)
        }

        optionsVC.onDismiss = { [weak self] in
            self?.scheduleHide()
        }

        present(optionsVC, animated: true)
    }

    private var isFullscreenPresentation: Bool {
        fullscreenPortal != nil
    }

    private func toggleFullscreenPresentation() {
        guard !isFullscreenTransitioning else { return }

        if isFullscreenPresentation {
            exitFullscreenPresentation()
        } else if hayaseShouldEmbedPlayerInShell {
            enterFullscreenPresentation()
        }
    }

    private struct FullscreenPortalState {
        let overlay: UIView
        let placeholder: UIView
        weak var originalSuperview: UIView?
        let originalIndex: Int
        let originalFrame: CGRect
        let originalAutoresizingMask: UIView.AutoresizingMask
        let originalTranslatesAutoresizingMaskIntoConstraints: Bool
    }

    private func enterFullscreenPresentation() {
        guard fullscreenPortal == nil,
              let window = view.window,
              let originalSuperview = view.superview else { return }

        let originalIndex = originalSuperview.subviews.firstIndex(of: view) ?? originalSuperview.subviews.count
        let placeholder = UIView(frame: view.frame)
        placeholder.backgroundColor = view.backgroundColor ?? .black
        placeholder.autoresizingMask = view.autoresizingMask
        placeholder.isUserInteractionEnabled = false

        let overlay = UIView(frame: window.bounds)
        overlay.backgroundColor = .black
        overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        let state = FullscreenPortalState(
            overlay: overlay,
            placeholder: placeholder,
            originalSuperview: originalSuperview,
            originalIndex: originalIndex,
            originalFrame: view.frame,
            originalAutoresizingMask: view.autoresizingMask,
            originalTranslatesAutoresizingMaskIntoConstraints: view.translatesAutoresizingMaskIntoConstraints
        )

        isFullscreenTransitioning = true
        fullscreenPortal = state

        UIView.performWithoutAnimation {
            view.removeFromSuperview()
            originalSuperview.insertSubview(placeholder, at: min(originalIndex, originalSuperview.subviews.count))
            window.addSubview(overlay)

            view.translatesAutoresizingMaskIntoConstraints = true
            view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.frame = overlay.bounds
            overlay.addSubview(view)

            overlay.layoutIfNeeded()
            view.layoutIfNeeded()
        }

        isFullscreenTransitioning = false
        setNeedsStatusBarAppearanceUpdate()
        setNeedsUpdateOfHomeIndicatorAutoHidden()
    }

    private func exitFullscreenPresentation() {
        guard let state = fullscreenPortal else { return }
        guard let originalSuperview = state.originalSuperview else {
            cleanupBrokenFullscreenPortal()
            return
        }

        isFullscreenTransitioning = true

        UIView.performWithoutAnimation {
            view.removeFromSuperview()
            state.placeholder.removeFromSuperview()
            state.overlay.removeFromSuperview()

            view.translatesAutoresizingMaskIntoConstraints = state.originalTranslatesAutoresizingMaskIntoConstraints
            view.autoresizingMask = state.originalAutoresizingMask
            view.frame = state.originalFrame
            originalSuperview.insertSubview(view, at: min(state.originalIndex, originalSuperview.subviews.count))

            originalSuperview.layoutIfNeeded()
            view.layoutIfNeeded()
        }

        fullscreenPortal = nil
        isFullscreenTransitioning = false
        setNeedsStatusBarAppearanceUpdate()
        setNeedsUpdateOfHomeIndicatorAutoHidden()
    }

    private func cleanupBrokenFullscreenPortal() {
        fullscreenPortal?.overlay.removeFromSuperview()
        fullscreenPortal?.placeholder.removeFromSuperview()
        fullscreenPortal = nil
        isFullscreenTransitioning = false
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
        if duration > 0, position > 0 {
            updateBuffering(false)
        }

        // W2G: sync playback position to peers (mirrors player.svelte reactive binding).
        // Guard against feedback loop when applying remote state.
        if !isApplyingRemoteW2GState {
            W2GLobby.shared.client?.playerStateChanged(
                W2GPlayerState(paused: isPaused, time: floor(position))
            )
        }

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

        // Periodically save watch progress so it survives crashes / force-quits.
        // Throttled to once every 5 seconds to avoid excessive UserDefaults writes.
        if duration > 0, position > 0 {
            let now = Date()
            if now.timeIntervalSince(lastProgressSaveTime) >= 5.0 {
                lastProgressSaveTime = now
                saveProgress()
            }
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
        // Session restore: pause immediately on the first play event so the
        // mini-player does not auto-play on app launch.
        if !isPaused && shouldStartPaused {
            shouldStartPaused = false
            surface.mpv.pausePlayback()
            return  // The resulting pause callback handles all UI updates.
        }
        self.isPaused = isPaused

        // W2G: sync pause state to peers (mirrors player.svelte reactive binding).
        // Guard against feedback loop when applying remote state.
        if !isApplyingRemoteW2GState {
            W2GLobby.shared.client?.playerStateChanged(
                W2GPlayerState(paused: isPaused, time: floor(currentTime))
            )
        }

        playPauseButton.setImage(UIImage.hayaseFilledIcon(isPaused ? "play" : "pause"), for: .normal)
        mobilePlayPauseButton.setImage(UIImage.hayaseFilledIcon(isPaused ? "play" : "pause"), for: .normal)
        if isPaused {
            hideWork?.cancel()
            setControls(visible: true)
        } else {
            updateInterfaceOverlayVisibility(animated: true)
            scheduleHide()
        }

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
        updateBuffering(isLoading)
    }

    func renderer(_ renderer: MPVWrapper, didBecomeReadyToSeek: Bool) {
        // Video is completely loaded into memory
    }

    func renderer(_ renderer: MPVWrapper, didBecomeTracksReady: Bool) {
        // Read MPV's track list immediately. MKV metadata parsing is slower and
        // runs off the main thread so first paint/options taps are not blocked.
        let newTracks = mergeCachedTrackMetadata(into: readTracks(from: renderer))
        self.tracks = newTracks

        // Auto-select preferred audio/subtitle tracks from Language Settings.
        // Reads pref_audioLanguage / pref_subtitleLanguage set in Settings → Player.
        applyPreferredLanguages(renderer: renderer, tracks: newTracks)

        guard let mkvURL = mkvFileURLForLanguageParsing() else { return }
        let expectedPath = mkvURL.path
        DispatchQueue.global(qos: .utility).async { [weak self, weak renderer] in
            let languages = MatroskaMetadataService.shared.subtitleLanguages(for: mkvURL)
            guard !languages.isEmpty else { return }

            DispatchQueue.main.async { [weak self, weak renderer] in
                guard let self,
                      let renderer,
                      self.surface.mpv === renderer,
                      self.videoEntity?.videoPath == expectedPath else { return }

                self.tracks = self.tracks.map { track in
                    guard track.type == "sub",
                          let language = languages[track.id],
                          !language.isEmpty,
                          language != "und" else { return track }
                    return MPVTrack(id: track.id,
                                    type: track.type,
                                    title: track.title,
                                    lang: language,
                                    isSelected: track.isSelected)
                }
                self.applyPreferredLanguages(renderer: renderer, tracks: self.tracks)
            }
        }
    }

    /// Selects audio and subtitle tracks whose language matches the user's
    /// preferred languages (Settings → Player → Language Settings).
    /// Language codes in preferences are ISO 639-2/B (e.g. "eng", "jpn");
    /// track codes from MPV may be 2-letter ISO 639-1 ("en", "ja") or
    /// 3-letter. We normalise both sides via `Locale` for reliable matching.
    private func applyPreferredLanguages(renderer: MPVWrapper, tracks: [MPVTrack]) {
        let defaults = UserDefaults.standard
        let prefAudio = defaults.string(forKey: "pref_audioLanguage") ?? "jpn"
        let prefSub   = defaults.string(forKey: "pref_subtitleLanguage") ?? "eng"

        // Audio — pick first track whose language matches the preference
        if !prefAudio.isEmpty {
            let audioTracks = tracks.filter { $0.type == "audio" }
            if let match = audioTracks.first(where: { languageCodesMatch($0.lang, prefAudio) }),
               !match.isSelected {
                renderer.setAudioTrack(match.id)
            }
        }

        // Subtitle — pick first track whose language matches; empty pref = OFF
        if prefSub.isEmpty {
            // "None" selected in settings → disable subtitles
            let hasSub = tracks.contains { $0.type == "sub" && $0.isSelected }
            if hasSub { renderer.disableSubtitles() }
        } else {
            let subTracks = tracks.filter { $0.type == "sub" }
            if let match = subTracks.first(where: { languageCodesMatch($0.lang, prefSub) }),
               !match.isSelected {
                renderer.setSubtitleTrack(match.id)
            }
        }
    }

    /// Returns `true` when two language identifiers refer to the same language.
    /// Handles mixed ISO 639-1 / 639-2 codes (e.g. "en" vs "eng", "ja" vs "jpn").
    private func languageCodesMatch(_ trackLang: String?, _ prefLang: String) -> Bool {
        guard let trackLang = trackLang, !trackLang.isEmpty else { return false }
        if trackLang == prefLang { return true }
        // Normalise both to ISO 639-1 (2-letter) for comparison
        let trackNorm = Self.iso639to1[trackLang] ?? trackLang
        let prefNorm  = Self.iso639to1[prefLang]  ?? prefLang
        return trackNorm == prefNorm
    }

    /// ISO 639-2/B → ISO 639-1 mapping for languages supported in
    /// Settings → Player → Language Settings.
    /// Includes both bibliographic (639-2/B) and terminology (639-2/T) variants
    /// where they differ (e.g. "idn"/"ind" both → "id").
    private static let iso639to1: [String: String] = [
        "eng": "en",  "jpn": "ja",  "chi": "zh",  "zho": "zh",
        "por": "pt",  "spa": "es",  "ger": "de",  "deu": "de",
        "pol": "pl",  "cze": "cs",  "ces": "cs",  "dan": "da",
        "gre": "el",  "ell": "el",  "fin": "fi",  "fre": "fr",
        "fra": "fr",  "hun": "hu",  "ita": "it",  "kor": "ko",
        "dut": "nl",  "nld": "nl",  "nor": "no",  "rum": "ro",
        "ron": "ro",  "rus": "ru",  "slo": "sk",  "slk": "sk",
        "swe": "sv",  "ara": "ar",  "idn": "id",  "ind": "id",
        "heb": "he",  "vie": "vi",  "tha": "th",  "tur": "tr",
        "hin": "hi",  "ben": "bn",  "per": "fa",  "fas": "fa",
        "mal": "ml",
    ]

    func renderer(_ renderer: MPVWrapper, didSelectAudioOutput audioOutput: String) { }

    func renderer(_ renderer: MPVWrapper, didBecomeChaptersReady chapters: [MPVChapter]) {
        self.chapters = chapters
        updateChapterMarkers()
        updateSkipChapterButton()
    }

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
                while let presented = top.presentedViewController, !presented.isBeingDismissed { top = presented }
                guard top !== self else { completionHandler(false); return }
                top.presentHayasePlayer(self) {
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
