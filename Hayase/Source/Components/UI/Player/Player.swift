//
//  Player.swift
//  Hayase
//
//  Mirrors: src/lib/components/ui/player/player.svelte: the video, its overlay and controls, the keys and gestures,
//  the progress that is kept, and Watch Together. What the interface keeps in the other files of `ui/player` is in the
//  files of the same names next to this one, as extensions of `VideoPlayerViewController`: `Animations`,
//  `Castplayer`, `Chapters`, `Downloadstats`, `Episodesmodal`, `Mediahandler`, `Options`, `Pip`, `Seekbar`,
//  `Statsfornerds`, `Subtitles`, `Wrapper` and `PlayerUtil` (`util.ts`).
//

import UIKit
import AVKit
import CoreMedia
import UniformTypeIdentifiers

// MARK: - Interface Player Overlays

final class InterfaceSpinnerView: UIView {
    let spinnerLayer = CAShapeLayer()
    var isAnimating = false
    var revealWork: DispatchWorkItem?

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
                                         startAngle: -3 * .pi / 4,
                                         endAngle: -.pi / 4,
                                         clockwise: true).cgPath
        if isAnimating {
            ensureSpinAnimation()
        }
    }

    func setAnimating(_ animating: Bool) {
        guard isAnimating != animating else { return }
        isAnimating = animating
        revealWork?.cancel()
        if animating {
            // player.svelte: in:fade duration=200, delay=500.
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.isAnimating else { return }
                self.alpha = 0
                self.isHidden = false
                self.ensureSpinAnimation()
                UIView.animate(withDuration: 0.2) { self.alpha = 1 }
            }
            revealWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
        } else {
            UIView.animate(withDuration: 0.2, animations: { self.alpha = 0 }) { [weak self] _ in
                guard let self, !self.isAnimating else { return }
                self.isHidden = true
                self.spinnerLayer.removeAnimation(forKey: "spin")
            }
        }
    }

    func ensureSpinAnimation() {
        guard !isHidden, window != nil, spinnerLayer.animation(forKey: "spin") == nil else { return }
        let rotation = CABasicAnimation(keyPath: "transform.rotation.z")
        rotation.fromValue = 0
        rotation.toValue = CGFloat.pi * 2
        rotation.duration = 1
        rotation.repeatCount = .infinity
        rotation.timingFunction = CAMediaTimingFunction(name: .linear)
        spinnerLayer.add(rotation, forKey: "spin")
    }
}

final class VideoPlayerViewController: UIViewController, UIDocumentPickerDelegate, KeyboardEventListener {

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        surface.mpv.addSubtitleFile(url: url.path)
    }

    // MARK: - Input (set before presenting)

    var videoEntity: Videos?
    var metadataLoadingView: PlayerMetadataLoadingView?
    var metadataLoadingOwner: AnyObject?
    var isLoadingMetadata: Bool { metadataLoadingView != nil }
    var onCancelMetadataLoading: (() -> Void)?

    func beginMetadataLoading(owner: AnyObject) {
        metadataLoadingOwner = owner
        loadViewIfNeeded()
        let loading = PlayerMetadataLoadingView(frame: surface.bounds)
        loading.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        surface.addSubview(loading)
        overlay.isHidden = true
        metadataLoadingView = loading
    }

    func finishMetadataLoading(error: Error? = nil) {
        onCancelMetadataLoading = nil
        metadataLoadingOwner = nil
        if let error {
            metadataLoadingView?.finishWithError()
            TorrentErrorToast.show(error.localizedDescription)
            return
        }
        metadataLoadingView?.removeFromSuperview()
        metadataLoadingView = nil
        overlay.isHidden = false
        loadCurrentVideo()
        scheduleHide()
        MiniPlayerManager.shared.refreshLoadingState(for: self)
    }
    var videoService: VideoService?
    var fileIndex: UInt = 0
    var anilistID: Int = 0
    var episodeNumber: Int = 0
    var allVideos: [Videos] = []
    var currentVideoIndex: Int = 0
    var resolvedVideoFiles: [TorrentBatchResolver.ResolvedItem<Videos>] = []
    var currentResolvedVideoFile: TorrentBatchResolver.ResolvedItem<Videos>?

    /// Callback fired when the user taps next/prev and the target episode is
    /// NOT in the current torrent batch. The presenting view controller should
    /// dismiss the player and initiate a new extension search for `episode`.
    /// Mirrors Hayase web's `playEpisode()` → `searchStore.set({ media, episode })`.
    var onEpisodeChange: ((_ episode: Int, _ media: AnimeItem?) -> Void)?

    /// Total number of episodes for this anime (from AniList metadata).
    /// Used to determine whether next/prev buttons should be enabled when the
    /// target episode is outside the current `allVideos` batch.
    var totalEpisodes: Int = 0

    // MARK: - Player components

    let surface = MPVSurfaceView()
    /// System PiP controller (streamyfin). Provides the native iOS
    /// Picture-in-Picture window when the app goes to background.
    /// Stored as `Any?` because PiPController requires iOS 15+.
    var _pipController: Any?

    // MARK: - Overlay

    let overlay       = UIView()
    let bottomBar     = UIView()
    let bottomGradient = CAGradientLayer()
    let mobileOptionsButton = SelectButton(frame: .zero)
    let mobileControlsStack = UIStackView()
    let mobilePrevButton = SelectButton(frame: .zero)
    let mobilePlayPauseButton = SelectButton(frame: .zero)
    let mobileNextButton = SelectButton(frame: .zero)
    let bufferingSpinner = InterfaceSpinnerView()
    let fastForwardBadge = UIView()
    let fastForwardLabel = UILabel()
    let fastForwardIcon = UIImageView(image: UIImage.hayaseFilledIcon("fast-forward", pointSize: 12))
    let skipChapterButton = InterfaceProgressButton()

    // Hayase downloadstats.svelte — floating HUD at top center
    let statsHUD = UIStackView()
    let statsPeersLabel = TextShadowLabel()
    let statsDownLabel = TextShadowLabel()
    let statsUpLabel = TextShadowLabel()

    // Bottom bar — above seekbar row
    let titleLabel    = TextShadowLabel()
    let episodeLabel  = TextShadowLabel()   // Hayase episodesmodal.svelte: session.description below title
    let chapterLabel  = TextShadowLabel()
    let timeLabel     = TextShadowLabel()

    // Bottom bar — seekbar row
    let seekBar       = SegmentedSeekBar()

    // Bottom bar — controls row
    let prevButton      = UIButton(type: .system)
    let playPauseButton = UIButton(type: .system)
    let nextButton      = UIButton(type: .system)
    let speedLabel      = UILabel()
    let optionsButton   = UIButton(type: .system)
    let airPlayPicker   = AVRoutePickerView()
    // Mirrors: hayase-app/interface/src/lib/components/ui/player/castplayer.svelte
    // (non-miniplayer branch; VideoPlayerViewController is always the full
    // player — the miniplayer branch is built separately in
    // MiniPlayerManager, which owns its own container/window).
    let nowCastingContainer = UIView()
    let nowCastingColumn = UIStackView()
    let nowCastingTitleLabel = UILabel()                       // "Now Casting"
    let nowCastingAnimeTitleButton = UIButton(type: .system)   // episodesmodal.svelte title div
    let nowCastingEpisodeButton = UIButton(type: .system)      // episodesmodal.svelte Sheet.Trigger
    let nowCastingTimeLabel = UILabel()
    let nowCastingErrorLabel = UILabel()   // {:catch error} — error.stack, replaces time+progress on failure
    let nowCastingProgressContainer = UIView()   // h-1 rounded-[2px] overflow-clip
    let nowCastingProgressTrack = UIView()       // h-0.5
    let nowCastingProgressFill = UIView()        // h-0.5
    var nowCastingProgressFillWidth: NSLayoutConstraint?
    let nowCastingControlsRow = UIStackView()
    let nowCastingStopButton = DestructiveButton(type: .system)
    let nowCastingPrevButton = GhostButton(type: .system)
    let nowCastingPlaylistButton = GhostButton(type: .system)
    let nowCastingNextButton = GhostButton(type: .system)
    var castElapsedTimer: Timer?
    var castStartTime: Date?
    var castDuration: Double = 0
    let bottomLeftControls = UIStackView()
    let bottomRightControls = UIStackView()
    var bottomControlConstraints: [NSLayoutConstraint] = []
    var mobileSeekBarBottomConstraint: NSLayoutConstraint?

    // MARK: - State

    var duration: Double = 0
    var currentTime: Double = 0
    var isPaused = false
    /// Set to `true` before loading a video to start it paused on the first
    /// play event. Used for session restore on app launch so the mini-player
    /// does not auto-play on launch.
    var shouldStartPaused = false
    /// Matches Hayase player.svelte: prevents duplicate tracking calls.
    var trackingCompleted = false
    var isSeeking = false
    var pendingSeekDisplayTime: Double?
    var tracks: [MPVTrack] = []
    var chapters: [MPVChapter] = [] // Note: Streamyfin's renderer doesn't fetch chapters by default
    var playbackRate: Double = 1.0
    var subtitleDelay: Double = 0.0
    var showRemainingTime = false
    var controlsVisible = true
    var hideWork: DispatchWorkItem?
    var doubleTapSeekRestoreWork: DispatchWorkItem?
    var isBuffering = true
    var isFastForwarding = false
    var playbackRateBeforeFastForward = 1.0
    var wasPausedBeforeFastForward = false
    var wasPausedBeforeScrub: Bool?
    /// chapters.ts: the chapters the player works with (whole, with what is skippable marked), the ones the
    /// file has, and the loading of them
    var chapterModel: [Chapter] = []
    var chaptersHandler: Chapters?
    var fileChapters: [MPVChapter] = []
    var chaptersLoadedDuration: Double = 0
    var chaptersTask: Task<Void, Never>?
    /// `currentSkippable`
    var currentSkippableChapter: Chapter?
    var visibilityPauseWasPlaying = false
    var autoPiPRequested = false
    var appVisibilityObservers: [NSObjectProtocol] = []
    /// The double-tap recognizer, stored so single-tap can require(toFail:) it.
    var doubleTapRecognizer: UITapGestureRecognizer?
    var longPressRecognizer: UILongPressGestureRecognizer?
    var statsTimer: Timer?
    var technicalStatsView: PlayerTechnicalStatsView?
    var technicalStatsTimer: Timer?
    let thumbnailer = PlayerThumbnailer()
    let seekingImage = UIImageView()
    let seekPreview = PlayerSeekPreviewView()
    var previewRequest = UUID()
    var webStatsUpdateInFlight = false
    // Hayase castplayer.svelte / native.getDisplays — Chromecast/DLNA discovery
    // is push-based on the bridge side (mDNS/SSDP), but our RPC transport is
    // plain request/response, so we poll for the current snapshot instead of
    // subscribing. WebTorrent backend only, same as interface.
    var castDisplaysTimer: Timer?
    var webTorrentDisplays: [WebTorrentDisplay] = []
    var onCastStateChanged: (() -> Void)?
    /// Stored here: an extension cannot hold a property that has an observer
    var activeCastDisplay: WebTorrentDisplay? {
        didSet { onCastStateChanged?() }
    }
    var onCastTick: ((_ elapsed: Double, _ duration: Double) -> Void)?
    var isEOFTriggered = false // Used to emulate the missing MPV_EVENT_END_FILE
    var lastSeekTime: Date?    // Tracks last seek to prevent false EOF triggers
    /// Pending playback position (seconds) to restore once MPV reports a valid
    /// duration. Using a stored value + event-driven trigger instead of a fixed
    /// delay ensures the seek works for both local files and HTTP streams (where
    /// MPV can take several seconds to buffer enough data to start playback).
    var pendingRestoreTime: Double?
    /// subtitles.ts: the subtitle files of the torrent and of the subtitle extensions, and the fonts
    var subtitles: Subtitles?
    /// Throttle watch-progress saves to avoid writing UserDefaults on every
    /// position callback. Saves every 5 seconds during active playback.
    /// `const saveProgressLoop = setInterval(saveAnimeProgress, 10000)`
    var saveProgressLoop: Timer?
    var isFullscreenPresentation = false

    /// True while the player is being minimized to in-app PiP. Prevents
    /// viewWillDisappear from tearing down the streaming pipeline.
    var isMinimizing = false

    // MARK: - W2G integration (mirrors player.svelte W2G hooks)

    /// Observer for W2GLobby changes.
    var w2gObserver: NSObjectProtocol?
    /// Suppresses outgoing W2G state updates while applying a remote state change.
    var isApplyingRemoteW2GState = false

    /// Bind/re-bind the current W2G client's delegate for player sync.
    /// When a lobby is created while the player is already running, push
    /// the current media + player state to the new client so that peers
    /// who join later receive it via `sendInitialSessionState`.
    /// Mirrors web's `server.play()` calling `w2globby.value?.mediaChange(...)`.
    func bindW2GClient() {
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
            client.mediaIndexChanged(playlistIndex)
            client.playerStateChanged(W2GPlayerState(paused: isPaused, time: floor(currentTime)))
        }
    }

    var currentW2GTorrentHash: String? {
        let hash = videoEntity?.torrents?.torrentHashString?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return hash.isEmpty ? nil : hash
    }

    /// Reference to the active W2G client for incoming player state.
    weak var w2gPlayerDelegate: W2GClient? {
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
    func applyRemoteW2GState(_ state: W2GPlayerState) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isApplyingRemoteW2GState = true

            // `currentTime = state.time; paused = state.paused`
            self.surface.mpv.seek(to: state.time)
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
        if let volume = UserDefaults.standard.object(forKey: "volume") as? Double {
            surface.mpv.setVolume(volume * 100)
        }
        ExternalDisplayManager.shared.register(self)

        // System PiP (streamyfin): create the AVPictureInPictureController
        // backed by the same AVSampleBufferDisplayLayer that MPV renders to.
        if #available(iOS 15.0, *) {
            let pip = PiPController(sampleBufferDisplayLayer: surface.displayLayer)
            pip.delegate = self
            self.pipController = pip
        }

        observeAppVisibility()
        NotificationCenter.default.addObserver(self, selector: #selector(elementDidNavigate(_:)),
                                               name: Navigate.didNavigate, object: nil)
        saveProgressLoop = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            self?.saveAnimeProgress()
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

    func observeAppVisibility() {
        let center = NotificationCenter.default
        appVisibilityObservers.append(center.addObserver(
            forName: UIApplication.willResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self, Settings.playerAutoPiP, !self.isPaused else { return }
            self.autoPiPRequested = self.pipController?.startPictureInPicture() ?? false
        })
        appVisibilityObservers.append(center.addObserver(
            forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self, Settings.playerPause, !self.isPaused,
                  !self.autoPiPRequested,
                  !(self.pipController?.isPictureInPictureActive ?? false) else { return }
            self.visibilityPauseWasPlaying = true
            self.surface.mpv.pausePlayback()
        })
        appVisibilityObservers.append(center.addObserver(
            forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            if self.autoPiPRequested {
                self.pipController?.stopPictureInPicture()
                self.autoPiPRequested = false
            }
            if self.visibilityPauseWasPlaying, self.isPaused {
                self.surface.mpv.play()
            }
            self.visibilityPauseWasPlaying = false
        })
        appVisibilityObservers.append(center.addObserver(
            forName: Settings.didChange, object: nil, queue: .main
        ) { [weak self] notification in
            guard let self, let key = notification.userInfo?["key"] as? String else { return }
            if key == Settings.Keys.playerAutoPiP {
                self.pipController?.setAutomaticStartEnabled(Settings.playerAutoPiP)
            } else if key == Settings.Keys.minimalPlayerUI {
                self.statsHUD.isHidden = Settings.minimalPlayerUI
            } else if key == Settings.Keys.deband {
                self.surface.mpv.setDeband(Settings.deband)
            } else if key == Settings.Keys.subtitleStyle {
                self.surface.mpv.applySubtitleStyle()
            } else if key == Settings.Keys.debugLevel {
                self.surface.mpv.applyLoggingLevel()
            }
        })
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // Presenting a native subtitle picker may cover the whole phone screen.
        // Covering the player is not leaving its route and must not stop MPV.
        guard presentedViewController == nil else { return }
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
        previewRequest = UUID()
        thumbnailer.cancel()
        technicalStatsTimer?.invalidate()
        technicalStatsTimer = nil
        exitFullscreenPresentation()
        onCancelMetadataLoading?()
        onCancelMetadataLoading = nil
        metadataLoadingOwner = nil
        appVisibilityObservers.forEach { NotificationCenter.default.removeObserver($0) }
        appVisibilityObservers.removeAll()
        saveProgressLoop?.invalidate()
        Router.shared.clearCachedPlayer(self)
        MiniPlayerManager.shared.clearSessionStateIfNeeded(for: self)
        if #available(iOS 15.0, *) {
            pipController?.stopPictureInPicture()
        }
        statsTimer?.invalidate()
        // Polling and the local elapsed clock stop with the player, but an
        // active cast session is left running — same as a real Chromecast/
        // AirPlay session, the display keeps playing independently of this
        // screen. The user stops it via the Now Casting screen's Stop
        // button, not by navigating away.
        castDisplaysTimer?.invalidate()
        castElapsedTimer?.invalidate()
        ExternalDisplayManager.shared.unregister(self)
        surface.stop()
        subtitles?.destroy()
        subtitles = nil
        MediaSession.shared.clear(owner: self)
        videoService?.releaseWebTorrentSession()
        // W2G cleanup
        if let obs = w2gObserver { NotificationCenter.default.removeObserver(obs) }
        w2gPlayerDelegate = nil
    }

    override var prefersStatusBarHidden: Bool              { true }
    override var canBecomeFirstResponder: Bool { true }
    /// `condition` of keybinds.svelte, `!isMiniplayer`, and no typing
    var handlesKeybinds: Bool {
        !PlayerKeyBindings.isEditing(in: viewIfLoaded) && !isMinimizing
            && !(MiniPlayerManager.shared.isActive && MiniPlayerManager.shared.activePlayer === self)
    }
    override var keyCommands: [UIKeyCommand]? {
        handlesKeybinds ? PlayerKeyBindings.commands() : nil
    }
    func keyDown(_ event: KeyboardEvent) {
        guard handlesKeybinds else { return }
        PlayerKeyBindings.run(event) { id, shift in runPlayerKeybind(id, shift: shift) }
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        becomeFirstResponder()
    }
    /// `on:navigate={() => resetMove(2000)}`: the controls are shown for the element that the focus moved to
    @objc func elementDidNavigate(_ notification: Notification) {
        guard let element = notification.object as? UIView, element.isDescendant(of: view) else { return }
        setControls(visible: true)
    }

    func runPlayerKeybind(_ id: String, shift: Bool) {
        switch id {
        case "play_arrow": playPauseTapped()
        case "screenshot_monitor": captureScreenshot()
        case "skip_next": if canNavigateToNextEpisode { nextTapped() }
        case "skip_previous": if canNavigateToPreviousEpisode { prevTapped() }
        case "deblur": Settings.deband.toggle()
        case "volume_off": surface.mpv.toggleMute()
        case "fullscreen": toggleFullscreenPresentation()
        case "picture_in_picture":
            if pipController?.isPictureInPictureActive == true { pipController?.stopPictureInPicture() }
            else { pipController?.startPictureInPicture() }
        case "fast_forward": performDoubleTapSeek(forward: true)
        case "fast_rewind": performDoubleTapSeek(forward: false)
        case "volume_up", "volume_down":
            let volume = min(100, max(0, surface.mpv.getVolume() + (id == "volume_up" ? 5 : -5)))
            surface.mpv.setVolume(volume)
            UserDefaults.standard.set(volume / 100, forKey: "volume")
            showPlayerAnimation(icon: id == "volume_up" ? "volume-2" : "volume-1")
        case "history", "update", "schedule":
            playbackRate = id == "schedule" ? 1 : min(16, max(0.1, playbackRate + (id == "update" ? 0.1 : -0.1)))
            surface.mpv.setSpeed(playbackRate)
            updateSpeedLabel()
        case "subtitle_delay_minus", "subtitle_delay_plus":
            subtitleDelay += id == "subtitle_delay_plus" ? 0.1 : -0.1
            surface.mpv.setSubtitleDelay(subtitleDelay)
        case "subtitles":
            let subtitles = currentTracksForOptions().filter { $0.type == "sub" }
            guard !subtitles.isEmpty else { return }
            let current = subtitles.firstIndex { $0.isSelected } ?? -1
            let next = current + (shift ? -1 : 1)
            // JS Array.at supports negative indices; beyond either end selects OFF.
            let index = next < 0 ? subtitles.count + next : next
            let track = subtitles.indices.contains(index) ? subtitles[index] : nil
            selectSubtitleTrack(track?.id ?? -1, in: subtitles)
            showPlayerTextAnimation(track?.title ?? track?.lang ?? "Off")
        case "fit_width":
            surface.displayLayer.videoGravity = surface.displayLayer.videoGravity == .resizeAspect ? .resizeAspectFill : .resizeAspect
        case "cast":
            if let options = presentedViewController as? PlayerOptionsController { options.openRootMenu(named: "Cast") }
            else { showOptionsSheet(openMenu: "Cast") }
        case "+90":
            skipCurrentChapter()
            showPlayerAnimation(icon: "fast-forward")
        case "list": toggleTechnicalStats()
        default: break
        }
    }

    /// The video's own width over height, once mpv knows it (the miniplayer is sized by it).
    var videoAspectRatio: CGFloat? {
        let info = surface.mpv.getTechnicalInfo()
        guard let width = info["videoWidth"] as? Int, let height = info["videoHeight"] as? Int,
              width > 0, height > 0 else { return nil }
        return CGFloat(width) / CGFloat(height)
    }

    override var preferredStatusBarUpdateAnimation: UIStatusBarAnimation { .none }
    override var prefersHomeIndicatorAutoHidden: Bool      { !controlsVisible }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .landscape }
    override var shouldAutorotate: Bool                    { true }

    // MARK: - Surface setup

    func setupSurface() {
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

    func setupOverlay() {
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
        seekingImage.frame = overlay.bounds
        seekingImage.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        seekingImage.contentMode = .scaleAspectFit
        seekingImage.backgroundColor = UIColor.HayaseTheme.background
        seekingImage.isHidden = true
        seekingImage.isUserInteractionEnabled = false
        overlay.addSubview(seekingImage)
        setupMobilePlayerControls()
        // Bottom overlay with gradient
        setupBottomBar()
        setupInterfacePlayerOverlays()
        seekPreview.isHidden = true
        overlay.addSubview(seekPreview)
        seekBar.onHover = { [weak self] fraction in self?.showSeekPreview(at: fraction) }
        // a click on the bar is nothing in the interface; for a UIControl it ends a seek
        seekBar.onDPadClick = {}
        seekBar.onKey = { [weak self] key in
            switch key {
            case .rewind: self?.performDoubleTapSeek(forward: false)
            case .forward: self?.performDoubleTapSeek(forward: true)
            case .playPause: self?.playPauseTapped()
            }
        }
    }

    func setupMobilePlayerControls() {
        mobileOptionsButton.translatesAutoresizingMaskIntoConstraints = false
        mobileOptionsButton.applyGhostVariant()
        mobileOptionsButton.restingBackground = UIColor.HayaseTheme.background.withAlphaComponent(0.2)
        mobileOptionsButton.tintColor = .white
        mobileOptionsButton.backgroundColor = UIColor.HayaseTheme.background.withAlphaComponent(0.2)
        mobileOptionsButton.layer.cornerRadius = 6
        mobileOptionsButton.clipsToBounds = true
        mobileOptionsButton.setImage(UIImage.hayaseIcon("ellipsis-vertical", pointSize: 22), for: .normal)
        mobileOptionsButton.imageEdgeInsets = UIEdgeInsets(top: 13, left: 13, bottom: 13, right: 13)
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
                                     inset: 10,
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

    func configureMobileControlButton(_ button: SelectButton,
                                              icon: String,
                                              size: CGFloat,
                                              inset: CGFloat,
                                              action: Selector) {
        button.translatesAutoresizingMaskIntoConstraints = false
        button.applyGhostVariant()
        button.restingBackground = UIColor.HayaseTheme.background.withAlphaComponent(0.2)
        button.tintColor = .white
        button.backgroundColor = UIColor.HayaseTheme.background.withAlphaComponent(0.2)
        button.layer.cornerRadius = size / 2
        button.clipsToBounds = true
        let iconSize = max(1, size - inset * 2)
        button.setImage(UIImage.hayaseFilledIcon(icon, pointSize: iconSize), for: .normal)
        button.imageEdgeInsets = UIEdgeInsets(top: inset, left: inset, bottom: inset, right: inset)
        button.addTarget(self, action: action, for: .touchUpInside)
    }

    func setupInterfacePlayerOverlays() {
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
            fastForwardLabel.heightAnchor.constraint(equalToConstant: 14),

            skipChapterButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40),
            skipChapterButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -160),
        ])
    }

    func setupBottomBar() {
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
        titleLabel.lineHeight = 18
        titleLabel.usesFixedLineBox = true
        titleLabel.textAlignment = .left
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.content = animeTitleText()
        // Text shadow (Hayase text-shadow-lg)
        // Hayase episodesmodal.svelte: the title is a link back to the anime page —
        // `<button class='... hover:text-muted-foreground hover:underline'
        //          onclick={() => goto(`/#/app/anime/${mediaInfo.media.id}`)}>`
        titleLabel.isUserInteractionEnabled = true
        titleLabel.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(titleTapped)))
        titleLabel.onDPadClick = { [weak self] in self?.titleTapped() }
        bottomBar.addSubview(titleLabel)

        // Hayase episodesmodal.svelte: session.description (text-sm font-light rgba(217,217,217,0.6))
        episodeLabel.translatesAutoresizingMaskIntoConstraints = false
        episodeLabel.textColor = UIColor(red: 217/255, green: 217/255, blue: 217/255, alpha: 0.6)
        episodeLabel.font = .nunito(ofSize: 14, weight: .light)
        episodeLabel.lineHeight = 14
        episodeLabel.usesFixedLineBox = true
        episodeLabel.textAlignment = .left
        episodeLabel.lineBreakMode = .byTruncatingTail
        episodeLabel.content = episodeDescriptionText()
        // Hayase episodesmodal.svelte: the description is the `Sheet.Trigger` that
        // opens the episode list — `<Sheet.Trigger class='... hover:underline'>`.
        episodeLabel.isUserInteractionEnabled = true
        episodeLabel.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(episodeLabelTapped)))
        episodeLabel.onDPadClick = { [weak self] in self?.episodeLabelTapped() }
        bottomBar.addSubview(episodeLabel)

        chapterLabel.translatesAutoresizingMaskIntoConstraints = false
        chapterLabel.textColor = UIColor(white: 0.85, alpha: 0.6) // rgba(217,217,217,0.6)
        chapterLabel.font = .nunito(ofSize: 14, weight: .light)
        chapterLabel.lineHeight = 14
        chapterLabel.usesFixedLineBox = true
        chapterLabel.textAlignment = .right
        chapterLabel.lineBreakMode = .byTruncatingTail
        chapterLabel.content = ""
        bottomBar.addSubview(chapterLabel)

        timeLabel.translatesAutoresizingMaskIntoConstraints = false
        timeLabel.textColor = .white
        timeLabel.font = .nunito(ofSize: 14, weight: .light)
        timeLabel.lineHeight = 14
        timeLabel.usesFixedLineBox = true
        timeLabel.textAlignment = .right
        timeLabel.content = "0:00 / 0:00"
        timeLabel.isUserInteractionEnabled = true
        timeLabel.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(toggleTimeFormat)))
        timeLabel.onDPadClick = { [weak self] in self?.toggleTimeFormat() }
        // Text shadow
        bottomBar.addSubview(timeLabel)

        // player.svelte: two gap-2 columns in a gap-1 flex row, aligned at the bottom.
        let titleColumn = UIStackView(arrangedSubviews: [titleLabel, episodeLabel])
        titleColumn.axis = .vertical
        titleColumn.spacing = 8
        titleColumn.alignment = .leading
        let timeColumn = UIStackView(arrangedSubviews: [chapterLabel, timeLabel])
        timeColumn.axis = .vertical
        timeColumn.spacing = 8
        timeColumn.alignment = .trailing
        timeColumn.setContentHuggingPriority(.required, for: .horizontal)
        timeColumn.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        // The time stays nowrap, but a long chapter must still truncate on phones.
        timeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        chapterLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let textRow = UIStackView(arrangedSubviews: [titleColumn, timeColumn])
        textRow.axis = .horizontal
        textRow.alignment = .bottom
        textRow.spacing = 4
        textRow.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.addSubview(textRow)
        for label in [titleLabel, episodeLabel] {
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }

        // --- Row 2: Seekbar (full width, chapter-segmented — matching interface seekbar.svelte) ---
        seekBar.translatesAutoresizingMaskIntoConstraints = false
        seekBar.addTarget(self, action: #selector(seekBegan),   for: .touchDown)
        seekBar.addTarget(self, action: #selector(seekChanged), for: .valueChanged)
        seekBar.addTarget(self, action: #selector(seekEnded),   for: [.touchUpInside, .touchUpOutside, .touchCancel])
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
        prevButton.isEnabled  = canNavigateToPreviousEpisode
        nextButton.isEnabled  = canNavigateToNextEpisode
        mobilePrevButton.isEnabled = prevButton.isEnabled
        mobileNextButton.isEnabled = nextButton.isEnabled
        nowCastingPrevButton.isEnabled = prevButton.isEnabled
        nowCastingNextButton.isEnabled = nextButton.isEnabled

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
        speedLabel.onDPadClick = { [weak self] in self?.speedLabelTapped() }
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

        setupNowCastingView()

        let pad: CGFloat = 24
        let baseConstraints = [
            // Row 1: title + episode (left), chapter + time (right)
            // Hayase: title on top, episode below; chapter above time on right
            textRow.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor, constant: pad),
            textRow.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor, constant: -pad),
            textRow.topAnchor.constraint(equalTo: bottomBar.topAnchor, constant: 12),

            // Row 2: seekbar (real padded frame: py-4 16pt × 2 + active bar 4pt = 36pt)
            seekBar.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor, constant: pad),
            seekBar.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor, constant: -pad),
            seekBar.topAnchor.constraint(equalTo: textRow.bottomAnchor),
            seekBar.heightAnchor.constraint(equalToConstant: 36),
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

    func setupGestures() {
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
    @objc func handleSingleTap(_ gesture: UITapGestureRecognizer) {
        setControls(visible: isPaused || isBuffering || !controlsVisible)
    }

    /// Double-tap: left/right quarters seek; center toggles fullscreen.
    @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        let tapLocation = gesture.location(in: surface)
        handleInterfaceDoubleTap(at: tapLocation)
    }

    @objc func handleHoldToFastForward(_ gesture: UILongPressGestureRecognizer) {
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
    var seekDurationSeconds: Double {
        Double(Settings.seekDuration) ?? 2
    }

    /// Mirrors player.svelte mobile overlay: left/right quarter double-taps seek,
    /// the center double-tap falls through to fullscreen().
    func handleInterfaceDoubleTap(at location: CGPoint) {
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

    func performDoubleTapSeek(forward: Bool) {
        doubleTapSeekRestoreWork?.cancel()
        isSeeking = true
        updateInterfaceOverlayVisibility(animated: false)

        let seekAmount = seekDurationSeconds
        let newTime: Double
        if forward {
            newTime = min(duration, currentTime + seekAmount)
            surface.mpv.seek(by: seekAmount)
            lastSeekTime = Date()
            showPlayerAnimation(icon: "fast-forward")
        } else {
            newTime = max(0, currentTime - seekAmount)
            surface.mpv.seek(by: -seekAmount)
            lastSeekTime = Date()
            showPlayerAnimation(icon: "rewind")
        }
        pendingSeekDisplayTime = newTime
        renderSeekTargetUI(time: newTime)

        let restoreWork = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.doubleTapSeekRestoreWork = nil
            self.isSeeking = false
            self.pendingSeekDisplayTime = nil
            self.updateTimeUI()
            self.updateInterfaceOverlayVisibility(animated: true)
        }
        doubleTapSeekRestoreWork = restoreWork
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: restoreWork)
    }

    // MARK: - Media session (player.svelte: native.setMediaSession, setActionHandler)

    /// What the lock screen, Control Centre and remote controls show and can do for this episode. The handlers
    /// of previous and next track exist only when the episode has one (`prev?.()`).
    func updateMediaSession(canGoPrev: Bool, canGoNext: Bool) {
        let anime = videoEntity?.torrents?.animes
        let total = max(totalEpisodes, anime?.animeTotalEps?.intValue ?? 0)
        // mediahandler.svelte: `Episode ${file.metadata.episode} / ${episodes(file.metadata.media) || '?'}`
        let description = "Episode \(episodeNumber) / \(total > 0 ? String(total) : "?")"
        MediaSession.shared.setMediaSession(owner: self, title: animeTitleText(), description: description,
                                            imageURL: anime?.animeImgL, duration: duration)
        var previous: (() -> Void)?
        if canGoPrev { previous = { [weak self] in self?.prevTapped() } }
        var next: (() -> Void)?
        if canGoNext { next = { [weak self] in self?.nextTapped() } }
        MediaSession.shared.setActionHandlers(owner: self, MediaSession.Handlers(
            play: { [weak self] in
                guard let self, self.isPaused else { return }
                self.surface.mpv.togglePause()
            },
            pause: { [weak self] in
                guard let self, !self.isPaused else { return }
                self.surface.mpv.togglePause()
            },
            seekTo: { [weak self] time in
                self?.lastSeekTime = Date()
                self?.surface.mpv.seek(to: time)
            },
            seekBackward: { [weak self] in
                guard let self else { return }
                self.lastSeekTime = Date()
                self.surface.mpv.seek(by: -self.seekDurationSeconds)
            },
            seekForward: { [weak self] in
                guard let self else { return }
                self.lastSeekTime = Date()
                self.surface.mpv.seek(by: self.seekDurationSeconds)
            },
            previousTrack: previous,
            nextTrack: next))
    }

    /// `native.setPlayBackState` and `native.setPositionState`: 'none' until the media is there.
    func reportMediaSessionState(position: Double) {
        let state: MediaSession.PlaybackState = duration > 0 ? (isPaused ? .paused : .playing) : .none
        MediaSession.shared.setPlayBackState(owner: self, state: state)
        guard duration > 0 else { return }
        MediaSession.shared.setPositionState(owner: self, duration: duration, position: position,
                                             playbackRate: playbackRate, state: state)
    }

    // MARK: - Watch progress

    /// `saveAnimeProgress`: every 10 seconds, while it plays
    func saveAnimeProgress() {
        guard currentMediaID > 0, episodeNumber > 0 else { return }
        if isBuffering || isPaused { return }
        // `$: safeduration = isFinite(duration) ? duration : currentTime`
        WatchProgressService.shared.setAnimeProgress(
            mediaID: currentMediaID,
            WatchProgress(episode: episodeNumber, currentTime: currentTime,
                          safeduration: duration.isFinite ? duration : currentTime))
    }

    /// Matches Hayase player.svelte checkCompletion():
    /// When the user is within max(180s, 10% of duration) of the end,
    /// automatically update AniList progress for this episode. Takes
    /// explicit time/duration so the cast elapsed-clock (castplayer.svelte's
    /// own local `elapsed`/`duration`) can reuse this without touching local
    /// playback's real currentTime/duration — otherwise stopping a cast and
    /// resuming local playback would resume against the anime's estimated
    /// duration instead of the actual file's.
    func checkCompletion(currentTime: Double? = nil, duration: Double? = nil) {
        let currentTime = currentTime ?? self.currentTime
        let duration = duration ?? self.duration
        // Desktop defaults playerAutocomplete to true — see Settings.autocomplete
        let autocomplete = Settings.autocomplete
        guard !trackingCompleted, autocomplete,
              anilistID > 0, episodeNumber > 0,
              duration > 0, currentTime > 0 else { return }

        let fromEnd = max(180.0, duration / 10.0)
        if duration - fromEnd < currentTime {
            trackingCompleted = true
            AniListTracking.shared.watch(anilistID: anilistID, episodeProgress: episodeNumber, episodesHint: totalEpisodes)
        }
    }

    // MARK: - Controls visibility

    func scheduleHide() {
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
    }

    func setControls(visible: Bool) {
        controlsVisible = visible
        overlay.alpha = 1
        updateInterfaceOverlayVisibility(animated: true)
        setNeedsStatusBarAppearanceUpdate()
        setNeedsUpdateOfHomeIndicatorAutoHidden()
        if visible { scheduleHide() }
    }

    func updateInterfaceOverlayVisibility(animated: Bool) {
        overlay.alpha = 1
        bufferingSpinner.setAnimating(isBuffering)

        let visible = !isFastForwarding && (controlsVisible || isPaused || isBuffering || isSeeking || isEOFTriggered)
        let controlsAlpha: CGFloat = visible ? 1 : 0
        let mobileControlsAlpha: CGFloat = visible && !isSeeking ? 1 : 0
        let showFastForward = isFastForwarding
        let showSkip = currentSkippableChapter != nil && (visible || skipChapterButton.isAnimatingProgress)

        if showFastForward && fastForwardBadge.isHidden {
            fastForwardBadge.isHidden = false
            fastForwardBadge.alpha = 0
            UIView.animate(withDuration: animated ? 0.4 : 0, delay: 0,
                           options: [.curveEaseInOut, .beginFromCurrentState]) { self.fastForwardBadge.alpha = 1 }
        } else if !showFastForward {
            fastForwardBadge.alpha = 0
            fastForwardBadge.isHidden = true
        }
        if showSkip { skipChapterButton.isHidden = false }

        mobileOptionsButton.isUserInteractionEnabled = visible
        mobileControlsStack.isUserInteractionEnabled = visible && !isSeeking
        bottomBar.isUserInteractionEnabled = visible
        skipChapterButton.isUserInteractionEnabled = showSkip

        let changes = {
            self.statsHUD.alpha = controlsAlpha
            self.mobileOptionsButton.alpha = controlsAlpha
            self.mobileControlsStack.alpha = mobileControlsAlpha
            self.bottomBar.alpha = controlsAlpha
            self.skipChapterButton.alpha = showSkip ? 1 : 0
            self.mobilePlayPauseButton.alpha = self.isBuffering ? 0.10 : 1
        }

        let completion: (Bool) -> Void = { _ in
            if !showSkip { self.skipChapterButton.isHidden = true }
        }

        if animated {
            UIView.animate(withDuration: 0.15, delay: visible ? 0 : 0.15,
                           options: [.curveEaseInOut, .beginFromCurrentState, .allowUserInteraction],
                           animations: changes, completion: completion)
        } else {
            changes()
            completion(true)
        }
    }

    func updateBuffering(_ buffering: Bool) {
        guard isBuffering != buffering else { return }
        isBuffering = buffering
        if buffering {
            setControls(visible: true)
        } else {
            updateInterfaceOverlayVisibility(animated: true)
            if !isPaused { scheduleHide() }
        }
    }

    func startFastForward() {
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

    func stopFastForward() {
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

    func applyInterfaceMobilePlayerLayout() {
        NSLayoutConstraint.deactivate(bottomControlConstraints)
        mobileSeekBarBottomConstraint?.isActive = true
        bottomLeftControls.isHidden = true
        bottomRightControls.isHidden = true
        mobileControlsStack.isHidden = false
        mobileOptionsButton.isHidden = false
        mobilePrevButton.alpha = mobilePrevButton.isEnabled ? 1 : 0.5
        mobileNextButton.alpha = mobileNextButton.isEnabled ? 1 : 0.5
        updateInterfaceOverlayVisibility(animated: false)
    }

    // MARK: - Time UI

    func updateTimeUI() {
        guard !isSeeking else { return }
        seekBar.value = duration > 0 ? CGFloat(currentTime / duration) : 0
        // Hayase format: "current / total" or "-remaining / total"
        if showRemainingTime {
            timeLabel.content = "-\(fmtTime(max(0, duration - currentTime))) / \(fmtTime(duration))"
        } else {
            timeLabel.content = "\(fmtTime(currentTime)) / \(fmtTime(duration))"
        }
        chapterLabel.content = chapterTitle(at: currentTime)
        updateSkipChapterButton()
    }

    func fmtTime(_ secs: Double) -> String {
        let s = max(0, Int(safe: secs))
        let h = s / 3600; let m = (s % 3600) / 60; let sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec)
                     : String(format: "%d:%02d", m, sec)
    }

    // MARK: - Actions

    @objc func playPauseTapped() {
        showPlayerAnimation(icon: isPaused ? "play" : "pause")
        surface.mpv.togglePause()
        if !controlsVisible { setControls(visible: true) } else { scheduleHide() }
    }

    @objc func toggleTimeFormat() {
        showRemainingTime.toggle()
        updateTimeUI()
    }

}

// MARK: - MPVWrapperDelegate Integration

extension VideoPlayerViewController: MPVWrapperDelegate {

    func renderer(_ renderer: MPVWrapper, didUpdatePosition position: Double, duration: Double, cacheSeconds: Double) {
        self.duration = duration
        // `$: chaptersHandler.loadChapters(safeduration)`: again whenever the length is another
        if duration > 0, chaptersLoadedDuration != duration { loadChapters() }
        if !isBuffering, !isSeeking, duration > 0, position > 0 { thumbnailer.rememberFrame(at: position, from: renderer) }
        seekBar.buffer = duration > 0 ? CGFloat(min(1, max(0, (position + cacheSeconds) / duration))) : 0
        if !isSeeking {
            self.currentTime = position
        }
        updateTimeUI()
        if duration > 0, position > 0 {
            updateBuffering(false)
        }
        reportMediaSessionState(position: position)

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
        // Session restore: pause immediately on the first play event so the
        // mini-player does not auto-play on app launch.
        if !isPaused && shouldStartPaused {
            shouldStartPaused = false
            surface.mpv.pausePlayback()
            return  // The resulting pause callback handles all UI updates.
        }
        self.isPaused = isPaused
        reportMediaSessionState(position: currentTime)

        // W2G: sync pause state to peers (mirrors player.svelte reactive binding).
        // Guard against feedback loop when applying remote state.
        if !isApplyingRemoteW2GState {
            W2GLobby.shared.client?.playerStateChanged(
                W2GPlayerState(paused: isPaused, time: floor(currentTime))
            )
        }

        playPauseButton.setImage(UIImage.hayaseFilledIcon(isPaused ? "play" : "pause"), for: .normal)
        mobilePlayPauseButton.setImage(UIImage.hayaseFilledIcon(isPaused ? "play" : "pause", pointSize: isPaused ? 24 : 28), for: .normal)
        let inset: CGFloat = isPaused ? 12 : 10
        mobilePlayPauseButton.imageEdgeInsets = UIEdgeInsets(top: inset, left: inset, bottom: inset, right: inset)
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
    }

    func renderer(_ renderer: MPVWrapper, didChangeLoading isLoading: Bool) {
        updateBuffering(isLoading)
        if !isLoading {
            ExternalDisplayManager.shared.videoDidBecomeReady(self)
        }

        // isLoading=false fires at MPV_EVENT_PLAYBACK_RESTART — mpv has a
        // decoded frame ready at the new position. Clear isSeeking so
        // didUpdatePosition can commit the real confirmed position and
        // updateTimeUI() can update the clock/scrubber normally again.
        if !isLoading, isSeeking {
            doubleTapSeekRestoreWork?.cancel()
            doubleTapSeekRestoreWork = nil
            isSeeking = false
            pendingSeekDisplayTime = nil
            updateInterfaceOverlayVisibility(animated: true)
        }
    }

    func renderer(_ renderer: MPVWrapper, didBecomeReadyToSeek: Bool) {
        // subtitle files that came in while the video loaded can be added now
        subtitles?.fileDidLoad()
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
                                    isSelected: track.isSelected,
                                    isForced: track.isForced,
                                    isDefault: track.isDefault)
                }
                self.applyPreferredLanguages(renderer: renderer, tracks: self.tracks)
            }
        }
    }

    func renderer(_ renderer: MPVWrapper, didSelectAudioOutput audioOutput: String) { }

    func renderer(_ renderer: MPVWrapper, didBecomeChaptersReady chapters: [MPVChapter]) {
        fileChapters = chapters
        chaptersLoadedDuration = 0
        loadChapters()
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
