// Mirrors: src/lib/components/ui/player/player.svelte, src/lib/components/ui/player/episodesmodal.svelte

import UIKit
import AVKit
import CoreMedia
import UniformTypeIdentifiers

// MARK: - SegmentedSeekBar (interface seekbar.svelte)

/// A chapter-segmented progress bar matching the Hayase web interface seekbar.svelte.
/// Each chapter forms a separate rounded bar segment with small gaps between them.
/// Replaces UISlider + chapterLayer for a faithful recreation of the web player.
private final class SegmentedSeekBar: UIControl, KeyboardEventListener {

    // MARK: - Public State

    /// Current playback progress 0–1.
    var value: CGFloat = 0 {
        didSet { layoutSegmentFills() }
    }
    var buffer: CGFloat = 0 {
        didSet { layoutSegmentFills() }
    }
    private var initialSeekOffset: CGFloat = 0
    var onHover: ((CGFloat?) -> Void)?

    /// `seekBarKey`: the keys of the bar while it is the focused element
    enum Key {
        case rewind
        case forward
        case playPause
    }
    var onKey: ((Key) -> Void)?

    /// `seekBarKey`: the arrows seek and nothing else gets them; Enter plays or pauses
    func keyDown(_ event: KeyboardEvent) {
        switch event.key {
        case KeyboardEvent.Key.arrowLeft, KeyboardEvent.Key.arrowRight:
            event.preventDefault()
            event.stopPropagation()
            onKey?(event.key == KeyboardEvent.Key.arrowLeft ? .rewind : .forward)
        case KeyboardEvent.Key.enter:
            onKey?(.playPause)
        default:
            break
        }
    }
    private var hoverValue: CGFloat = 0

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
    private var segmentViews: [(container: UIView, bg: CALayer, buffered: CALayer, hover: CALayer, fill: CALayer)] = []

    // MARK: - Constants (matching interface seekbar.svelte)

    /// Bar height when not being touched (h-0.5 = 2px in interface CSS).
    private let normalHeight: CGFloat = 2
    /// Bar height when being touched (h-1 = 4px in interface CSS).
    private let activeHeight: CGFloat = 4
    /// Gap between chapter segments (ml-0.5 = 2px in interface CSS).
    private let segmentGap: CGFloat = 2
    /// Corner radius per segment (rounded-[2px] in interface CSS).
    private let segmentRadius: CGFloat = 2
    /// Real vertical padding on each side (py-4 = 16px in interface CSS).
    /// The touch target IS the padded frame — no invisible hit-test override needed.
    private let verticalPadding: CGFloat = 16
    /// Background color: rgba(217,217,217,0.4) from interface.
    private let bgColor = UIColor(red: 217/255, green: 217/255, blue: 217/255, alpha: 0.4)
    /// Progress fill color: white from interface.
    private var fillColor: UIColor { UIColor.HayaseTheme.primary }

    private var barHeight: CGFloat = 2

    // MARK: - Intrinsic size

    /// Returns the natural height: real padding on each side + the active bar height.
    /// This makes the layout system aware of the full touch-target frame,
    /// matching interface seekbar.svelte's py-4 padded container architecture.
    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: verticalPadding * 2 + activeHeight)
    }

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        rebuildSegmentViews()
        addGestureRecognizer(UIHoverGestureRecognizer(target: self, action: #selector(pointerMoved(_:))))
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

            let buffered = CALayer()
            buffered.backgroundColor = bgColor.cgColor
            container.layer.addSublayer(buffered)
            let hover = CALayer()
            hover.backgroundColor = bgColor.cgColor
            container.layer.addSublayer(hover)

            let fill = CALayer()
            fill.backgroundColor = fillColor.cgColor
            container.layer.addSublayer(fill)

            addSubview(container)
            segmentViews.append((container, bg, buffered, hover, fill))
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
        // Center the thin visual bar within the real padded frame,
        // just like interface's py-4 + flex items-center.
        let cy = bounds.midY

        for (i, seg) in segments.enumerated() {
            guard i < segmentViews.count else { break }
            let gap = i > 0 ? segmentGap : 0
            let w = max(0, totalWidth * seg.size - gap)
            let seek = isSeeking ? value : hoverValue
            let h = seek > seg.offset && seek < seg.offset + seg.size ? activeHeight : normalHeight
            let (container, bg, _, _, _) = segmentViews[i]
            container.frame = CGRect(x: totalWidth * seg.offset + gap, y: cy - h / 2, width: w, height: h)
            container.layer.cornerRadius = min(segmentRadius, h / 2)

            CATransaction.begin()
            CATransaction.setDisableActions(true)
            bg.frame = container.bounds
            CATransaction.commit()

        }
    }

    private func layoutSegmentFills() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (i, seg) in segments.enumerated() {
            guard i < segmentViews.count else { break }
            let (container, _, buffered, hover, fill) = segmentViews[i]
            buffered.frame = CGRect(x: 0, y: 0, width: container.bounds.width * localFill(buffer, offset: seg.offset, size: seg.size), height: container.bounds.height)
            hover.frame = CGRect(x: 0, y: 0, width: container.bounds.width * localFill(hoverValue, offset: seg.offset, size: seg.size), height: container.bounds.height)
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
        // Interface touch seeking is relative: touching far from playback does
        // not jump immediately; subsequent movement adjusts the current position.
        initialSeekOffset = touch.type == .direct ? fractionForTouch(touch) - value : 0
        value = min(max(fractionForTouch(touch) - initialSeekOffset, 0), 1)
        onHover?(nil)
        animateHeight(activeHeight)
        sendActions(for: .touchDown)
        sendActions(for: .valueChanged)
        return true
    }

    override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        value = min(max(fractionForTouch(touch) - initialSeekOffset, 0), 1)
        layoutSegmentFrames()
        sendActions(for: .valueChanged)
        return true
    }

    override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        if let t = touch { value = min(max(fractionForTouch(t) - initialSeekOffset, 0), 1) }
        isSeeking = false
        initialSeekOffset = 0
        animateHeight(normalHeight)
        sendActions(for: .touchUpInside)
    }

    override func cancelTracking(with event: UIEvent?) {
        isSeeking = false
        initialSeekOffset = 0
        animateHeight(normalHeight)
        sendActions(for: .touchCancel)
    }

    private func fractionForTouch(_ touch: UITouch) -> CGFloat {
        let x = touch.location(in: self).x
        return min(max(x / max(bounds.width, 1), 0), 1)
    }

    @objc private func pointerMoved(_ gesture: UIHoverGestureRecognizer) {
        guard !isSeeking else { return }
        let hovering = gesture.state == .began || gesture.state == .changed
        hoverValue = hovering ? min(1, max(0, gesture.location(in: self).x / max(1, bounds.width))) : 0
        layoutSegmentFrames()
        layoutSegmentFills()
        onHover?(hovering ? hoverValue : nil)
    }

    private func animateHeight(_ h: CGFloat) {
        guard barHeight != h else { return }
        barHeight = h
        UIView.animate(withDuration: 0.075) {
            self.layoutSegmentFrames()
            self.layoutSegmentFills()
        }
    }
}

// MARK: - Interface Player Overlays

private final class InterfaceSpinnerView: UIView {
    private let spinnerLayer = CAShapeLayer()
    private var isAnimating = false
    private var revealWork: DispatchWorkItem?

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

    private func ensureSpinAnimation() {
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

private final class InterfaceProgressButton: UIControl {
    private let label = UILabel()
    private let progressView = UIView()
    private var pendingCompletion = false
    var isAnimatingProgress: Bool { pendingCompletion }
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

final class VideoPlayerViewController: UIViewController, UIDocumentPickerDelegate, KeyboardEventListener {

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        surface.mpv.addSubtitleFile(url: url.path)
    }

    // MARK: - Input (set before presenting)

    var videoEntity: Videos?
    private var metadataLoadingView: PlayerMetadataLoadingView?
    private var metadataLoadingOwner: AnyObject?
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
    private var currentResolvedVideoFile: TorrentBatchResolver.ResolvedItem<Videos>?

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

    // MARK: - Overlay

    private let overlay       = UIView()
    private let bottomBar     = UIView()
    private let bottomGradient = CAGradientLayer()
    private let mobileOptionsButton = SelectButton(frame: .zero)
    private let mobileControlsStack = UIStackView()
    private let mobilePrevButton = SelectButton(frame: .zero)
    private let mobilePlayPauseButton = SelectButton(frame: .zero)
    private let mobileNextButton = SelectButton(frame: .zero)
    private let bufferingSpinner = InterfaceSpinnerView()
    private let fastForwardBadge = UIView()
    private let fastForwardLabel = UILabel()
    private let fastForwardIcon = UIImageView(image: UIImage.hayaseFilledIcon("fast-forward", pointSize: 12))
    private let skipChapterButton = InterfaceProgressButton()

    // Hayase downloadstats.svelte — floating HUD at top center
    private let statsHUD = UIStackView()
    private let statsPeersLabel = TextShadowLabel()
    private let statsDownLabel = TextShadowLabel()
    private let statsUpLabel = TextShadowLabel()

    // Bottom bar — above seekbar row
    private let titleLabel    = TextShadowLabel()
    private let episodeLabel  = TextShadowLabel()   // Hayase episodesmodal.svelte: session.description below title
    private let chapterLabel  = TextShadowLabel()
    private let timeLabel     = TextShadowLabel()

    // Bottom bar — seekbar row
    private let seekBar       = SegmentedSeekBar()

    // Bottom bar — controls row
    private let prevButton      = UIButton(type: .system)
    private let playPauseButton = UIButton(type: .system)
    private let nextButton      = UIButton(type: .system)
    private let speedLabel      = UILabel()
    private let optionsButton   = UIButton(type: .system)
    private let airPlayPicker   = AVRoutePickerView()
    // Mirrors: hayase-app/interface/src/lib/components/ui/player/castplayer.svelte
    // (non-miniplayer branch; VideoPlayerViewController is always the full
    // player — the miniplayer branch is built separately in
    // MiniPlayerManager, which owns its own container/window).
    private let nowCastingContainer = UIView()
    private let nowCastingColumn = UIStackView()
    private let nowCastingTitleLabel = UILabel()                       // "Now Casting"
    private let nowCastingAnimeTitleButton = UIButton(type: .system)   // episodesmodal.svelte title div
    private let nowCastingEpisodeButton = UIButton(type: .system)      // episodesmodal.svelte Sheet.Trigger
    private let nowCastingTimeLabel = UILabel()
    private let nowCastingErrorLabel = UILabel()   // {:catch error} — error.stack, replaces time+progress on failure
    private let nowCastingProgressContainer = UIView()   // h-1 rounded-[2px] overflow-clip
    private let nowCastingProgressTrack = UIView()       // h-0.5
    private let nowCastingProgressFill = UIView()        // h-0.5
    private var nowCastingProgressFillWidth: NSLayoutConstraint?
    private let nowCastingControlsRow = UIStackView()
    private let nowCastingStopButton = DestructiveButton(type: .system)
    private let nowCastingPrevButton = GhostButton(type: .system)
    private let nowCastingPlaylistButton = GhostButton(type: .system)
    private let nowCastingNextButton = GhostButton(type: .system)
    private var castElapsedTimer: Timer?
    private var castStartTime: Date?
    private var castDuration: Double = 0
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
    /// Matches Hayase player.svelte: prevents duplicate tracking calls.
    private var trackingCompleted = false
    private var isSeeking = false
    private var pendingSeekDisplayTime: Double?
    private var tracks: [MPVTrack] = []
    private var chapters: [MPVChapter] = [] // Note: Streamyfin's renderer doesn't fetch chapters by default
    private var playbackRate: Double = 1.0
    private var subtitleDelay: Double = 0.0
    private var showRemainingTime = false
    private var controlsVisible = true
    private var hideWork: DispatchWorkItem?
    private var doubleTapSeekRestoreWork: DispatchWorkItem?
    private var isBuffering = true
    private var isFastForwarding = false
    private var playbackRateBeforeFastForward = 1.0
    private var wasPausedBeforeFastForward = false
    private var wasPausedBeforeScrub: Bool?
    /// chapters.ts: the chapters the player works with (whole, with what is skippable marked), the ones the
    /// file has, and the loading of them
    private var chapterModel: [Chapter] = []
    private var chaptersHandler: Chapters?
    private var fileChapters: [MPVChapter] = []
    private var chaptersLoadedDuration: Double = 0
    private var chaptersTask: Task<Void, Never>?
    /// `currentSkippable`
    private var currentSkippableChapter: Chapter?
    private var visibilityPauseWasPlaying = false
    private var autoPiPRequested = false
    private var appVisibilityObservers: [NSObjectProtocol] = []
    /// The double-tap recognizer, stored so single-tap can require(toFail:) it.
    private var doubleTapRecognizer: UITapGestureRecognizer?
    private var longPressRecognizer: UILongPressGestureRecognizer?
    private var statsTimer: Timer?
    private var technicalStatsView: PlayerTechnicalStatsView?
    private var technicalStatsTimer: Timer?
    private let thumbnailer = PlayerThumbnailer()
    private let seekingImage = UIImageView()
    private let seekPreview = PlayerSeekPreviewView()
    private var previewRequest = UUID()
    private var webStatsUpdateInFlight = false
    // Hayase castplayer.svelte / native.getDisplays — Chromecast/DLNA discovery
    // is push-based on the bridge side (mDNS/SSDP), but our RPC transport is
    // plain request/response, so we poll for the current snapshot instead of
    // subscribing. WebTorrent backend only, same as interface.
    private var castDisplaysTimer: Timer?
    private var webTorrentDisplays: [WebTorrentDisplay] = []
    private var activeCastDisplay: WebTorrentDisplay? {
        didSet { onCastStateChanged?() }
    }
    /// MiniPlayerManager reads these to build the miniplayer's own
    /// castplayer.svelte `isMiniplayer` branch — it can't reuse this VC's
    /// view once minimized (reparented into a different window), so it
    /// needs the state and a tick callback instead.
    var isCasting: Bool { activeCastDisplay != nil }
    var activeCastDisplayName: String? { activeCastDisplay?.friendlyName }
    var onCastStateChanged: (() -> Void)?
    var onCastTick: ((_ elapsed: Double, _ duration: Double) -> Void)?
    private var isEOFTriggered = false // Used to emulate the missing MPV_EVENT_END_FILE
    private var lastSeekTime: Date?    // Tracks last seek to prevent false EOF triggers
    /// Pending playback position (seconds) to restore once MPV reports a valid
    /// duration. Using a stored value + event-driven trigger instead of a fixed
    /// delay ensures the seek works for both local files and HTTP streams (where
    /// MPV can take several seconds to buffer enough data to start playback).
    private var pendingRestoreTime: Double?
    /// subtitles.ts: the subtitle files of the torrent and of the subtitle extensions, and the fonts
    private var subtitles: Subtitles?
    /// Throttle watch-progress saves to avoid writing UserDefaults on every
    /// position callback. Saves every 5 seconds during active playback.
    private var lastProgressSaveTime: Date = .distantPast
    private var isFullscreenPresentation = false

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
            client.mediaIndexChanged(playlistIndex)
            client.playerStateChanged(W2GPlayerState(paused: isPaused, time: floor(currentTime)))
        }
    }

    private var currentW2GTorrentHash: String? {
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

    private func observeAppVisibility() {
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
        saveProgress()
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
    private var handlesKeybinds: Bool {
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
    @objc private func elementDidNavigate(_ notification: Notification) {
        guard let element = notification.object as? UIView, element.isDescendant(of: view) else { return }
        setControls(visible: true)
    }

    private func runPlayerKeybind(_ id: String, shift: Bool) {
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
            surface.mpv.setSubtitleTrack(track?.id ?? -1)
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

    private func toggleTechnicalStats() {
        if let panel = technicalStatsView {
            panel.removeFromSuperview()
            technicalStatsView = nil
            technicalStatsTimer?.invalidate()
            technicalStatsTimer = nil
            return
        }
        let panel = PlayerTechnicalStatsView()
        panel.translatesAutoresizingMaskIntoConstraints = false
        panel.onClose = { [weak self] in self?.toggleTechnicalStats() }
        overlay.addSubview(panel)
        NSLayoutConstraint.activate([
            panel.topAnchor.constraint(equalTo: overlay.topAnchor, constant: 20),
            panel.leadingAnchor.constraint(equalTo: overlay.leadingAnchor, constant: 20),
            panel.widthAnchor.constraint(equalToConstant: 288),
        ])
        technicalStatsView = panel
        updateTechnicalStats()
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in self?.updateTechnicalStats() }
        RunLoop.main.add(timer, forMode: .common)
        technicalStatsTimer = timer
    }

    /// The video's own width over height, once mpv knows it (the miniplayer is sized by it).
    var videoAspectRatio: CGFloat? {
        let info = surface.mpv.getTechnicalInfo()
        guard let width = info["videoWidth"] as? Int, let height = info["videoHeight"] as? Int,
              width > 0, height > 0 else { return nil }
        return CGFloat(width) / CGFloat(height)
    }

    private func updateTechnicalStats() {
        guard let panel = technicalStatsView else { return }
        let info = surface.mpv.getTechnicalInfo()
        let width = (info["videoWidth"] as? Int) ?? 0
        let height = (info["videoHeight"] as? Int) ?? 0
        panel.update([
            "Resolution": "\(width)x\(height)", "Viewport": "\(Int(surface.bounds.width))x\(Int(surface.bounds.height))",
            "FPS": (info["fps"] as? Double).map { String(format: "%.1f", $0) } ?? "-",
            "Dropped Frames": String((info["droppedFrames"] as? Int) ?? 0),
            "Position": "\(fmtTime(currentTime)) / \(fmtTime(duration))",
            "Speed": String(format: "x%.2f", playbackRate), "Volume": String(format: "%.0f%%", surface.mpv.getVolume()),
            "Subtitle Delay": String(format: "%.1fs", subtitleDelay),
            // Native state is named honestly; DOM HAVE_* and frame callback counters
            // do not exist in MPV. Unavailable counters retain the interface's '-'.
            "Ready State": isBuffering ? "Buffering" : isPaused ? "Paused" : "Playing",
            "Audio": String(tracks.filter { $0.type == "audio" }.count),
            "Video": String(tracks.filter { $0.type == "video" }.count),
            "Health": "\(Int(safe: (info["cacheSeconds"] as? Double) ?? 0)) s",
        ])
    }
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
        statsHUD.isUserInteractionEnabled = false // downloadstats.svelte pointer-events-none
        statsHUD.isHidden = true
        // text-shadow-lg is drawn by the labels; SVGs use drop-shadow.

        statsHUD.addArrangedSubview(makeStatsHUDItem(icon: "users", label: statsPeersLabel))
        statsHUD.addArrangedSubview(makeStatsHUDItem(icon: "chevron-down", label: statsDownLabel))
        statsHUD.addArrangedSubview(makeStatsHUDItem(icon: "chevron-up", label: statsUpLabel))

        overlay.addSubview(statsHUD)
        NSLayoutConstraint.activate([
            statsHUD.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            statsHUD.centerXAnchor.constraint(equalTo: view.centerXAnchor),
        ])
    }

    private func makeStatsHUDItem(icon: String, label: TextShadowLabel) -> UIStackView {
        // Tailwind drop-shadow chains two filters; the wrapper shadows the
        // icon plus its first shadow, while its alignment box stays 18pt.
        let iconContainer = UIView()
        iconContainer.translatesAutoresizingMaskIntoConstraints = false
        iconContainer.layer.shadowColor = UIColor.black.cgColor
        iconContainer.layer.shadowOpacity = 0.06
        iconContainer.layer.shadowOffset = CGSize(width: 0, height: 1)
        iconContainer.layer.shadowRadius = 1
        let imageView = UIImageView(image: UIImage.hayaseIcon(icon, pointSize: 18))
        imageView.tintColor = UIColor.HayaseTheme.foreground
        imageView.contentMode = .scaleAspectFit
        imageView.layer.shadowColor = UIColor.black.cgColor
        imageView.layer.shadowOpacity = 0.1
        imageView.layer.shadowOffset = CGSize(width: 0, height: 1)
        imageView.layer.shadowRadius = 2
        imageView.translatesAutoresizingMaskIntoConstraints = false
        iconContainer.addSubview(imageView)
        NSLayoutConstraint.activate([
            iconContainer.widthAnchor.constraint(equalToConstant: 18),
            iconContainer.heightAnchor.constraint(equalToConstant: 18),
            imageView.leadingAnchor.constraint(equalTo: iconContainer.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: iconContainer.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: iconContainer.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: iconContainer.bottomAnchor),
        ])

        label.font = .nunito(ofSize: 18, weight: .bold)
        label.lineHeight = 28
        label.usesFixedLineBox = true
        label.textColor = UIColor.HayaseTheme.foreground
        label.setContentHuggingPriority(.required, for: .horizontal)

        let stack = UIStackView(arrangedSubviews: [iconContainer, label])
        stack.axis = .horizontal
        stack.spacing = 8
        stack.alignment = .center
        return stack
    }

    private func setupMobilePlayerControls() {
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

    private func configureMobileControlButton(_ button: SelectButton,
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
            fastForwardLabel.heightAnchor.constraint(equalToConstant: 14),

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

    /// Mirrors: hayase-app/interface/src/lib/components/ui/player/castplayer.svelte
    /// (non-miniplayer branch) and episodesmodal.svelte. `$breakpoints['4xs']`
    /// is `(min-width: 280px)` — true on every iOS device — so the buttons
    /// always use the 4xs-true sizing (size-12/24px icons/h-12 text-lg), never
    /// the non-4xs fallback.
    private func setupNowCastingView() {
        nowCastingContainer.translatesAutoresizingMaskIntoConstraints = false
        nowCastingContainer.backgroundColor = UIColor.HayaseTheme.background   // bg-background
        nowCastingContainer.isHidden = true
        view.addSubview(nowCastingContainer)

        nowCastingTitleLabel.text = "Now Casting"
        nowCastingTitleLabel.textColor = UIColor.HayaseTheme.foreground
        nowCastingTitleLabel.font = .nunito(ofSize: 24, weight: .bold)   // text-2xl font-bold
        nowCastingTitleLabel.numberOfLines = 1   // line-clamp-1

        // episodesmodal.svelte title div: text-lg font-normal, text-shadow-lg —
        // shadow parameters match Hayase's existing titleLabel approximation
        // of the same three-layer text-shadow-lg (same component, same look).
        nowCastingAnimeTitleButton.setTitleColor(UIColor.HayaseTheme.foreground, for: .normal)
        nowCastingAnimeTitleButton.titleLabel?.font = .nunito(ofSize: 18, weight: .regular)   // text-lg font-normal
        nowCastingAnimeTitleButton.titleLabel?.numberOfLines = 1   // line-clamp-1
        nowCastingAnimeTitleButton.titleLabel?.lineBreakMode = .byTruncatingTail
        nowCastingAnimeTitleButton.contentHorizontalAlignment = .leading
        nowCastingAnimeTitleButton.titleLabel?.layer.shadowColor = UIColor.black.cgColor
        nowCastingAnimeTitleButton.titleLabel?.layer.shadowOffset = .zero
        nowCastingAnimeTitleButton.titleLabel?.layer.shadowOpacity = 0.8
        nowCastingAnimeTitleButton.titleLabel?.layer.shadowRadius = 3
        nowCastingAnimeTitleButton.addTarget(self, action: #selector(titleTapped), for: .touchUpInside)

        // episodesmodal.svelte Sheet.Trigger: text-[rgba(217,217,217,0.6)]
        // text-sm font-light, text-shadow-lg — not muted-foreground, a
        // distinct literal color (see UIColor.HayaseTheme.castMutedText).
        nowCastingEpisodeButton.setTitleColor(UIColor.HayaseTheme.castMutedText, for: .normal)
        nowCastingEpisodeButton.titleLabel?.font = .nunito(ofSize: 14, weight: .light)   // text-sm font-light
        nowCastingEpisodeButton.titleLabel?.numberOfLines = 1   // line-clamp-1
        nowCastingEpisodeButton.titleLabel?.lineBreakMode = .byTruncatingTail
        nowCastingEpisodeButton.contentHorizontalAlignment = .leading
        nowCastingEpisodeButton.titleLabel?.layer.shadowColor = UIColor.black.cgColor
        nowCastingEpisodeButton.titleLabel?.layer.shadowOffset = .zero
        nowCastingEpisodeButton.titleLabel?.layer.shadowOpacity = 0.8
        nowCastingEpisodeButton.titleLabel?.layer.shadowRadius = 3
        nowCastingEpisodeButton.addTarget(self, action: #selector(episodeLabelTapped), for: .touchUpInside)

        // `ml-auto self-end ... mt-3` — right-aligned within the full-width
        // column, no text-shadow-lg here (only the two episodesmodal lines get it).
        nowCastingTimeLabel.textColor = UIColor.HayaseTheme.foreground
        nowCastingTimeLabel.font = .nunito(ofSize: 14, weight: .light)   // text-sm font-light
        nowCastingTimeLabel.textAlignment = .right

        // `relative w-full h-1 ... rounded-[2px]` wrapping two absolutely
        // positioned h-0.5 bars; absolute children with no top/bottom ignore
        // the parent's items-center, keeping their static (top) position.
        nowCastingProgressContainer.clipsToBounds = true
        nowCastingProgressContainer.layer.cornerRadius = 2   // rounded-[2px]
        nowCastingProgressTrack.backgroundColor = UIColor.HayaseTheme.castProgressTrack
        nowCastingProgressFill.backgroundColor = UIColor.HayaseTheme.primary   // bg-primary
        nowCastingProgressContainer.addSubview(nowCastingProgressTrack)
        nowCastingProgressContainer.addSubview(nowCastingProgressFill)

        nowCastingErrorLabel.textColor = UIColor.HayaseTheme.castError   // text-red-500
        nowCastingErrorLabel.font = .nunito(ofSize: 14, weight: .light)   // text-sm font-light
        nowCastingErrorLabel.numberOfLines = 0   // whitespace-pre-wrap — a stack trace can wrap multiple lines
        nowCastingErrorLabel.isHidden = true

        nowCastingStopButton.setImage(UIImage.hayaseFilledIcon("square", pointSize: 24), for: .normal)   // size='24px' fill='currentColor'
        nowCastingStopButton.addTarget(self, action: #selector(stopCastingTapped), for: .touchUpInside)

        nowCastingPrevButton.setImage(UIImage.hayaseFilledIcon("skip-back", pointSize: 24), for: .normal)   // fill='currentColor' strokeWidth='1'
        nowCastingPrevButton.tintColor = UIColor.HayaseTheme.foreground
        nowCastingPrevButton.addTarget(self, action: #selector(prevTapped), for: .touchUpInside)

        nowCastingNextButton.setImage(UIImage.hayaseFilledIcon("skip-forward", pointSize: 24), for: .normal)
        nowCastingNextButton.tintColor = UIColor.HayaseTheme.foreground
        nowCastingNextButton.addTarget(self, action: #selector(nextTapped), for: .touchUpInside)

        nowCastingPlaylistButton.setTitle("Playlist", for: .normal)   // px-8 h-12 text-lg font-bold py-0
        nowCastingPlaylistButton.titleLabel?.font = .nunito(ofSize: 18, weight: .bold)
        nowCastingPlaylistButton.setTitleColor(UIColor.HayaseTheme.foreground, for: .normal)
        nowCastingPlaylistButton.contentEdgeInsets = UIEdgeInsets(top: 0, left: 32, bottom: 0, right: 32)
        nowCastingPlaylistButton.setContentHuggingPriority(.required, for: .horizontal)   // don't stretch — only the trailing spacer does
        nowCastingPlaylistButton.addTarget(self, action: #selector(nowCastingPlaylistTapped), for: .touchUpInside)

        // `flex w-full pt-3 gap-2` — left-packed, not stretched or spread;
        // a trailing spacer (low hugging) absorbs the rest of the row's width.
        let trailingSpacer = UIView()
        nowCastingControlsRow.axis = .horizontal
        nowCastingControlsRow.spacing = 8   // gap-2
        nowCastingControlsRow.alignment = .center
        nowCastingControlsRow.distribution = .fill
        [nowCastingStopButton, nowCastingPrevButton, nowCastingPlaylistButton, nowCastingNextButton, trailingSpacer]
            .forEach { nowCastingControlsRow.addArrangedSubview($0) }

        nowCastingColumn.axis = .vertical
        nowCastingColumn.spacing = 8   // gap-2
        nowCastingColumn.alignment = .fill   // text-left; flex-col default align-items:stretch
        [nowCastingTitleLabel, nowCastingAnimeTitleButton, nowCastingEpisodeButton,
         nowCastingTimeLabel, nowCastingProgressContainer, nowCastingErrorLabel, nowCastingControlsRow].forEach {
            nowCastingColumn.addArrangedSubview($0)
        }
        nowCastingColumn.setCustomSpacing(16, after: nowCastingTitleLabel)          // gap-2 + mb-2
        nowCastingColumn.setCustomSpacing(20, after: nowCastingEpisodeButton)       // gap-2 + mt-3 (on the label after)
        nowCastingColumn.setCustomSpacing(20, after: nowCastingProgressContainer)   // gap-2 + pt-3 (on the row after)
        nowCastingColumn.setCustomSpacing(20, after: nowCastingErrorLabel)          // same, when {:catch} replaces time+progress
        nowCastingContainer.addSubview(nowCastingColumn)

        [nowCastingColumn, nowCastingProgressContainer, nowCastingProgressTrack, nowCastingProgressFill,
         nowCastingControlsRow, nowCastingStopButton, nowCastingPrevButton, nowCastingPlaylistButton,
         nowCastingNextButton, trailingSpacer].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
        }

        let fillWidth = nowCastingProgressFill.widthAnchor.constraint(equalTo: nowCastingProgressContainer.widthAnchor, multiplier: 0)
        nowCastingProgressFillWidth = fillWidth

        NSLayoutConstraint.activate([
            nowCastingColumn.centerXAnchor.constraint(equalTo: nowCastingContainer.centerXAnchor),
            nowCastingColumn.centerYAnchor.constraint(equalTo: nowCastingContainer.centerYAnchor),
            nowCastingColumn.widthAnchor.constraint(lessThanOrEqualToConstant: 320),   // max-w-[320px]
            nowCastingColumn.leadingAnchor.constraint(greaterThanOrEqualTo: nowCastingContainer.leadingAnchor, constant: 32),   // px-8
            nowCastingColumn.trailingAnchor.constraint(lessThanOrEqualTo: nowCastingContainer.trailingAnchor, constant: -32),

            nowCastingProgressContainer.heightAnchor.constraint(equalToConstant: 4),   // h-1
            nowCastingProgressTrack.leadingAnchor.constraint(equalTo: nowCastingProgressContainer.leadingAnchor),
            nowCastingProgressTrack.trailingAnchor.constraint(equalTo: nowCastingProgressContainer.trailingAnchor),
            nowCastingProgressTrack.topAnchor.constraint(equalTo: nowCastingProgressContainer.topAnchor),
            nowCastingProgressTrack.heightAnchor.constraint(equalToConstant: 2),   // h-0.5
            nowCastingProgressFill.leadingAnchor.constraint(equalTo: nowCastingProgressContainer.leadingAnchor),
            nowCastingProgressFill.topAnchor.constraint(equalTo: nowCastingProgressContainer.topAnchor),
            nowCastingProgressFill.heightAnchor.constraint(equalToConstant: 2),   // h-0.5
            fillWidth,

            nowCastingStopButton.widthAnchor.constraint(equalToConstant: 48),   // size-12
            nowCastingStopButton.heightAnchor.constraint(equalToConstant: 48),
            nowCastingPrevButton.widthAnchor.constraint(equalToConstant: 48),
            nowCastingPrevButton.heightAnchor.constraint(equalToConstant: 48),
            nowCastingNextButton.widthAnchor.constraint(equalToConstant: 48),
            nowCastingNextButton.heightAnchor.constraint(equalToConstant: 48),
            nowCastingPlaylistButton.heightAnchor.constraint(equalToConstant: 48),   // h-12
        ])
        NSLayoutConstraint.activate([
            nowCastingContainer.topAnchor.constraint(equalTo: view.topAnchor),
            nowCastingContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            nowCastingContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            nowCastingContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
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

        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleHoldToFastForward(_:)))
        longPress.minimumPressDuration = 1.0
        longPress.allowableMovement = 40
        longPress.delegate = self
        view.addGestureRecognizer(longPress)
        longPressRecognizer = longPress
    }

    /// Single-tap: toggle controls visibility.
    @objc private func handleSingleTap(_ gesture: UITapGestureRecognizer) {
        setControls(visible: isPaused || isBuffering || !controlsVisible)
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
        Double(Settings.seekDuration) ?? 2
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

    private func renderSeekTargetUI(time: Double) {
        seekBar.value = duration > 0 ? CGFloat(time / duration) : 0
        if showRemainingTime {
            timeLabel.content = "-\(fmtTime(max(0, duration - time))) / \(fmtTime(duration))"
        } else {
            timeLabel.content = "\(fmtTime(time)) / \(fmtTime(duration))"
        }
        chapterLabel.content = chapterTitle(at: time)
    }

    private func showPlayerAnimation(icon: String) {
        guard !Settings.minimalPlayerUI else { return }
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

    private func showPlayerTextAnimation(_ text: String) {
        guard !Settings.minimalPlayerUI else { return }
        let label = UILabel()
        label.text = text
        label.font = .nunito(ofSize: 36, weight: .bold)
        label.textColor = UIColor.HayaseTheme.foreground
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isUserInteractionEnabled = false
        overlay.addSubview(label)
        NSLayoutConstraint.activate([label.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
                                     label.centerYAnchor.constraint(equalTo: overlay.centerYAnchor)])
        UIView.animate(withDuration: 0.4, delay: 0, options: [.curveLinear], animations: {
            label.alpha = 0
            label.transform = CGAffineTransform(scaleX: 1.2, y: 1.2)
        }, completion: { _ in label.removeFromSuperview() })
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
    private func loadVideoURL() {
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
        restoreProgress(path: path)
        startStatsTimer()

        // castplayer.svelte's prev/next are the same functions the normal
        // player uses, so skipping episodes while casting re-sends the new
        // file to the same display rather than leaving the TV on the old one.
        if let display = activeCastDisplay {
            startCasting(to: display)
        }
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
        startCastDisplaysTimer()
        guard isWebTorrentPlayback else { return }
        statsHUD.isHidden = Settings.minimalPlayerUI
        updateWebTorrentStats()
        let timer = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.updateWebTorrentStats()
        }
        RunLoop.main.add(timer, forMode: .common)
        statsTimer = timer
    }

    private var isWebTorrentPlayback: Bool {
        guard videoEntity?.torrents != nil,
              let path = videoEntity?.videoPath?.lowercased() else { return false }
        return path.hasPrefix("http://") || path.hasPrefix("https://")
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
                // The cast request returns at once; how the session went is reported in the status.
                if let display = self.activeCastDisplay, let message = status.cast?[display.host]?.error {
                    self.showCastError(message)
                }
            }
        }
    }

    private func applyWebTorrentStats(peers: Int, downloadSpeed: UInt64, uploadSpeed: UInt64) {
        statsHUD.isHidden = Settings.minimalPlayerUI
        statsPeersLabel.content = "\(peers)"
        statsDownLabel.content = "\(fmtBits(downloadSpeed * 8))/s"
        statsUpLabel.content = "\(fmtBits(uploadSpeed * 8))/s"
    }



    /// Formats bits per second into a human-readable string (Hayase fastPrettyBits).
    private func fmtBits(_ bps: UInt64) -> String {
        guard bps > 0 else { return "0 b" }
        let units = [" b", " kb", " Mb", " Gb", " Tb"]
        let exponent = min(Int(floor(log10(Double(bps)) / 3)), units.count - 1)
        let value = (Double(bps) / pow(1000, Double(exponent)) * 10).rounded() / 10
        // fastPrettyBits converts toFixed(1) back to Number: 27 Mb, not
        // 27.0 Mb, and 59 kb, not 59 Kb. Keep the HUD's intrinsic width equal.
        let number = value.rounded() == value ? String(format: "%.0f", value) : String(format: "%.1f", value)
        return number + units[exponent]
    }

    // MARK: - Casting (Hayase castplayer.svelte / native.getDisplays / castPlay / castClose)

    /// Starts polling the WebTorrent bridge for Chromecast/DLNA displays.
    /// Mirrors `native.getDisplays(cb)` in native.ts, which on interface's
    /// real (non-browser) desktop build is backed by the same
    /// listenDisplay()/chromecasts+dlnas discovery this bridge now exposes —
    /// polled here since our transport is request/response, not push.
    /// Interval matches the actual rescan cadence in torrent-client's
    /// ChromeCasts/DLNAs classes (`setInterval(() => this.update(), 1 * 60 *
    /// 1000)` in both) — polling faster than the source itself refreshes
    /// would just re-fetch the same list.
    private func startCastDisplaysTimer() {
        castDisplaysTimer?.invalidate()
        guard isWebTorrentPlayback else { return }
        updateCastDisplays()
        let timer = Timer(timeInterval: 60.0, repeats: true) { [weak self] _ in
            self?.updateCastDisplays()
        }
        RunLoop.main.add(timer, forMode: .common)
        castDisplaysTimer = timer
    }

    private func updateCastDisplays() {
        TorrentBackendManager.shared.webTorrentListDisplays { [weak self] result in
            DispatchQueue.main.async {
                guard let self, case .success(let displays) = result else { return }
                self.webTorrentDisplays = displays
            }
        }
    }

    /// MIME type for the cast receiver's `contentType`. Hayase doesn't have
    /// a shared extension→MIME helper elsewhere yet, so this stays local and
    /// narrow — it only needs to cover the containers WebTorrent playback
    /// actually serves.
    private func castContentType(forPath path: String) -> String {
        switch (path as NSString).pathExtension.lowercased() {
        case "mkv": return "video/x-matroska"
        case "webm": return "video/webm"
        case "mp4", "m4v": return "video/mp4"
        default: return "application/octet-stream"
        }
    }

    /// Mirrors: hayase-app/interface/src/lib/components/ui/player/castplayer.svelte
    /// `actualMedia` (lines 76-99) — same field set, same source per field:
    /// contentId/contentType/customData come from the file being cast, not
    /// from AniList; metadata.title/subtitle come from the session (anime
    /// title/episode description), duration is intentionally the anime's
    /// AniList-reported duration, not the actual file's real duration (see
    /// castDurationSeconds below).
    private func castMediaPayload() -> [String: Any]? {
        guard let entity = videoEntity,
              let contentId = entity.videoLanPath ?? entity.videoPath else { return nil }

        let metadata: [String: Any] = [
            "metadataType": 2,
            "posterUrl": entity.torrents?.animes?.animeImgL ?? "",
            "title": animeTitleText(),
            "seriesTitle": animeTitleText(),
            "subtitle": episodeDescriptionText(),
            "episodeTitle": episodeDescriptionText(),
            "episode": episodeNumber,
            "episodeNumber": episodeNumber,
        ]

        return [
            "contentId": contentId,
            "contentType": castContentType(forPath: entity.videoName ?? contentId),
            "metadata": metadata,
            "customData": [
                "hash": entity.torrents?.torrentHashString ?? "",
                "id": entity.videoIndex?.intValue ?? Int(fileIndex),
                "audioLanguage": Settings.audioLanguage,
                "subtitleLanguage": Settings.subtitleLanguage,
            ],
            "streamType": "BUFFERED",
            "mediaCategory": "VIDEO",
        ]
    }

    /// `(mediaInfo.media.duration ?? 24) * 60` — the anime's AniList duration
    /// in minutes, not the real file duration. The cast device reports no
    /// position back to us, so this — like web — is a fiction used only to
    /// size the progress bar and to feed checkCompletion's threshold.
    private func castDurationSeconds() -> Double {
        Double((currentResolvedVideo?.media?.duration ?? 24) * 60)
    }

    private func startCasting(to display: WebTorrentDisplay) {
        guard let media = castMediaPayload() else { return }
        let hash = videoEntity?.torrents?.torrentHashString ?? ""
        let id = videoEntity?.videoIndex?.intValue ?? Int(fileIndex)

        activeCastDisplay = display
        nowCastingAnimeTitleButton.setTitle(animeTitleText(), for: .normal)
        nowCastingEpisodeButton.setTitle(episodeDescriptionText(), for: .normal)
        nowCastingPrevButton.isEnabled = prevButton.isEnabled
        nowCastingNextButton.isEnabled = nextButton.isEnabled
        nowCastingErrorLabel.isHidden = true
        nowCastingTimeLabel.isHidden = false
        nowCastingProgressContainer.isHidden = false
        nowCastingContainer.isHidden = false
        surface.mpv.pausePlayback()
        startCastElapsedTimer()

        TorrentBackendManager.shared.webTorrentPlayDisplay(host: display.host, hash: hash, id: id, media: media) { [weak self] result in
            guard let self, case .failure(let error) = result else { return }
            DispatchQueue.main.async {
                guard self.activeCastDisplay == display else { return }
                self.showCastError(error.localizedDescription)
            }
        }
    }

    /// {:catch error} — the time/progress area is replaced by the error text; the rest of the
    /// screen (title, EpisodesModal, Stop/Prev/Playlist/Next) stays exactly as-is, no auto-dismiss.
    private func showCastError(_ message: String) {
        castElapsedTimer?.invalidate()
        nowCastingTimeLabel.isHidden = true
        nowCastingProgressContainer.isHidden = true
        nowCastingErrorLabel.isHidden = false
        nowCastingErrorLabel.text = message
    }

    /// `const elapsed = writable(0, set => setInterval(() => set((Date.now() -
    /// startTime) / 1000), 1000))` — reuses currentTime/duration/
    /// checkCompletion so AniList progress tracking behaves identically to
    /// local playback (see checkCompletion above), just fed a clock instead
    /// of MPV's real position.
    private func startCastElapsedTimer() {
        castElapsedTimer?.invalidate()
        castStartTime = Date()
        castDuration = castDurationSeconds()
        updateCastElapsedUI()
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateCastElapsedUI()
        }
        RunLoop.main.add(timer, forMode: .common)
        castElapsedTimer = timer
    }

    private func updateCastElapsedUI() {
        guard let castStartTime else { return }
        let elapsed = min(Date().timeIntervalSince(castStartTime), castDuration)
        nowCastingTimeLabel.text = "\(fmtTime(elapsed)) / \(fmtTime(castDuration))"
        let progress = castDuration > 0 ? CGFloat(elapsed / castDuration) : 0
        nowCastingProgressFillWidth?.isActive = false
        nowCastingProgressFillWidth = nowCastingProgressFill.widthAnchor.constraint(
            equalTo: nowCastingProgressContainer.widthAnchor, multiplier: min(max(progress, 0), 1))
        nowCastingProgressFillWidth?.isActive = true
        checkCompletion(currentTime: elapsed, duration: castDuration, persistProgress: false)
        onCastTick?(elapsed, castDuration)
    }

    @objc private func stopCastingTapped() {
        stopCasting()
    }

    private func stopCasting() {
        guard let display = activeCastDisplay else { return }
        activeCastDisplay = nil
        castElapsedTimer?.invalidate()
        castElapsedTimer = nil
        castStartTime = nil
        nowCastingContainer.isHidden = true
        surface.mpv.play()
        TorrentBackendManager.shared.webTorrentCloseDisplay(host: display.host) { _ in }
    }

    /// Mirrors: hayase-app/interface/src/lib/components/ui/player/castplayer.svelte
    /// Dialog.Root/Dialog.Content (lines 131-144) via CastPlaylistDialog.
    @objc private func nowCastingPlaylistTapped() {
        let videos = playlistVideos
        guard !videos.isEmpty else { return }
        let items = videos.map { video in
            CastPlaylistDialog.Item(title: video.videoName ?? "Untitled") { [weak self] in
                self?.selectPlaylistVideo(video)
            }
        }
        let dialog = CastPlaylistDialog(items: items)
        present(dialog, animated: true)
    }

    // MARK: - Title helpers (Hayase episodesmodal.svelte / mediahandler.svelte)

    /// MiniPlayerManager's own copy of the Now Casting overlay reads these —
    /// it can't call the private version below (different file), and can't
    /// reuse this VC's view once minimized (reparented into another window).
    func animeTitleForDisplay() -> String { animeTitleText() }
    func episodeDescriptionForDisplay() -> String { episodeDescriptionText() }

    // MARK: - Media session (player.svelte: native.setMediaSession, setActionHandler)

    /// What the lock screen, Control Centre and remote controls show and can do for this episode. The handlers
    /// of previous and next track exist only when the episode has one (`prev?.()`).
    private func updateMediaSession(canGoPrev: Bool, canGoNext: Bool) {
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
    private func reportMediaSessionState(position: Double) {
        let state: MediaSession.PlaybackState = duration > 0 ? (isPaused ? .paused : .playing) : .none
        MediaSession.shared.setPlayBackState(owner: self, state: state)
        guard duration > 0 else { return }
        MediaSession.shared.setPositionState(owner: self, duration: duration, position: position,
                                             playbackRate: playbackRate, state: state)
    }

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


    // MARK: - Watch progress

    private func saveProgress() {
        guard let path = videoEntity?.videoPath, duration > 0 else { return }
        WatchProgressService.shared.setProgress(
            videoPath: path, anilistID: anilistID, episode: episodeNumber,
            currentTime: currentTime, duration: duration)
    }

    /// Matches Hayase player.svelte checkCompletion():
    /// When the user is within max(180s, 10% of duration) of the end,
    /// automatically update AniList progress for this episode. Takes
    /// explicit time/duration so the cast elapsed-clock (castplayer.svelte's
    /// own local `elapsed`/`duration`) can reuse this without touching local
    /// playback's real currentTime/duration — otherwise stopping a cast and
    /// resuming local playback would resume against the anime's estimated
    /// duration instead of the actual file's.
    private func checkCompletion(currentTime: Double? = nil, duration: Double? = nil, persistProgress: Bool = true) {
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
            if persistProgress { saveProgress() }
            AniListTracking.shared.watch(anilistID: anilistID, episodeProgress: episodeNumber, episodesHint: totalEpisodes)
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
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
        mobilePrevButton.alpha = mobilePrevButton.isEnabled ? 1 : 0.5
        mobileNextButton.alpha = mobileNextButton.isEnabled ? 1 : 0.5
        updateInterfaceOverlayVisibility(animated: false)
    }

    // MARK: - Time UI

    private func updateTimeUI() {
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

    private func fmtTime(_ secs: Double) -> String {
        let s = max(0, Int(safe: secs))
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
        (chapterWindow(at: time)?.title ?? "").capitalized
    }

    /// `loadChapters`: the chapters of the file (or, when it has none to read, AniSkip's) made whole, with
    /// what is skippable marked. They replace the file's own once they are there.
    private func loadChapters() {
        guard duration > 0, let handler = chaptersHandler else { return }
        chaptersLoadedDuration = duration
        let duration = self.duration
        // the chapters of the file know where they start; one ends where the next starts
        let sorted = fileChapters.sorted { $0.time < $1.time }
        let raw = sorted.enumerated().map { index, chapter in
            RawChapter(start: chapter.time * 1000,
                       end: (index + 1 < sorted.count ? sorted[index + 1].time : duration) * 1000,
                       text: chapter.title)
        }
        let malID = videoService?.media?.malId ?? Router.shared.cachedAnimeItem(for: currentMediaID)?.malId
        let fileExtension = ((videoEntity?.videoName ?? "") as NSString).pathExtension.lowercased()
        chaptersTask?.cancel()
        chaptersTask = Task { @MainActor [weak self] in
            let loaded = await handler.loadChapters(fileChapters: raw, malID: malID,
                                                    readsChaptersOfContainer: ["mkv", "webm"].contains(fileExtension),
                                                    duration: duration)
            guard let self, !Task.isCancelled, self.chaptersHandler === handler, !loaded.isEmpty else { return }
            self.chapterModel = loaded
            self.chapters = loaded.enumerated().map { MPVChapter(index: $0.offset, title: $0.element.text, time: $0.element.start) }
            self.updateChapterMarkers()
            self.updateSkipChapterButton()
        }
    }

    /// `checkSkippableChapters`
    private func updateSkipChapterButton() {
        guard let current = Chapters.find(currentTime, in: chapterModel) else { return }
        let next = current.skippable ? current : nil
        guard next != currentSkippableChapter else { return }
        let wasAutoskippable = currentSkippableChapter?.autoskippable ?? false
        currentSkippableChapter = next
        if let next {
            skipChapterButton.setTitle("Skip \(next.skiptype ?? "")")
            skipChapterButton.stopProgress()
            let w2gAllowsSkip = W2GLobby.shared.client.map { $0.peers.count > 1 } ?? true
            // an opening or ending that is not on its first episode skips by itself, after the button has run
            if Settings.playerSkip, next.autoskippable, !wasAutoskippable, w2gAllowsSkip {
                skipChapterButton.startProgress(duration: 3)
            }
        } else {
            skipChapterButton.stopProgress()
        }
        updateInterfaceOverlayVisibility(animated: true)
    }

    /// `skip()`: past the chapter, 85 seconds on in a long one that is not skippable, or where 90 seconds /
    /// the end of the episode is when there is no chapter.
    private func skipCurrentChapter() {
        guard duration > 0 else { return }
        let target: Double
        if let current = Chapters.find(currentTime, in: chapterModel) {
            if !current.skippable && current.length > 100 {
                target = currentTime + 85
            } else {
                target = current.end + 0.5
                currentSkippableChapter = nil
            }
        } else if currentTime < 10 {
            target = 90
        } else if duration - currentTime < 90 {
            target = duration
        } else {
            target = currentTime + 85
        }
        let targetTime = min(duration, target)
        surface.mpv.seek(to: targetTime)
        lastSeekTime = Date()
        isSeeking = true
        pendingSeekDisplayTime = targetTime
        currentSkippableChapter = nil
        skipChapterButton.stopProgress()
        renderSeekTargetUI(time: targetTime)
        updateInterfaceOverlayVisibility(animated: true)
        scheduleHide()

        doubleTapSeekRestoreWork?.cancel()
        let restoreWork = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.doubleTapSeekRestoreWork = nil
            self.isSeeking = false
            self.pendingSeekDisplayTime = nil
            self.updateTimeUI()
        }
        doubleTapSeekRestoreWork = restoreWork
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: restoreWork)
    }

    // MARK: - Actions

    @objc private func playPauseTapped() {
        showPlayerAnimation(icon: isPaused ? "play" : "pause")
        surface.mpv.togglePause()
        if !controlsVisible { setControls(visible: true) } else { scheduleHide() }
    }

    @objc private func prevTapped() {
        navigateEpisode(by: -1)
    }

    @objc private func nextTapped() {
        navigateEpisode(by: 1)
    }

    private func navigateEpisode(by delta: Int) {
        guard let currentEpisode = currentEpisodeForNavigation else { return }

        resolveNavigationEpisode(from: currentEpisode, delta: delta, mediaID: currentMediaID) { [weak self] targetEpisode in
            guard let self, let targetEpisode else { return }
            self.saveProgress()
            self.playEpisode(targetEpisode, media: nil)
        }
    }

    private func resolveNavigationEpisode(from currentEpisode: Int,
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
    private func playEpisode(_ episode: Int, media: AnimeItem?) {
        let mediaID = media?.id ?? currentMediaID
        if let file = resolvedVideoFile(forEpisode: episode, mediaID: mediaID) {
            switchToResolvedVideoFile(file)
        } else if let match = videoMatchByFilename(forEpisode: episode) {
            switchToVideo(match, episode: episode, media: media ?? currentResolvedVideoFile?.media)
        } else {
            requestEpisodeChange(episode, media: media)
        }
    }

    private func resolvedVideoFile(forEpisode targetEp: Int,
                                   mediaID: Int) -> TorrentBatchResolver.ResolvedItem<Videos>? {
        resolvedVideoFiles.first { resolvedFile in
            resolvedFile.episodeReference.matches(targetEp)
                && resolvedFile.media?.id == mediaID
                && videoMatch(for: resolvedFile) != nil
        }
    }

    private var currentResolvedVideo: TorrentBatchResolver.ResolvedItem<Videos>? {
        if let currentResolvedVideoFile, matchesVideo(currentResolvedVideoFile, fileIndex) {
            return currentResolvedVideoFile
        }
        return resolvedVideoFiles.first { matchesVideo($0, fileIndex) }
    }

    private var currentMediaID: Int {
        currentResolvedVideo?.media?.id ?? anilistID
    }

    private var currentEpisodeForNavigation: Int? {
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

    private var canNavigateToPreviousEpisode: Bool {
        guard let episode = currentEpisodeForNavigation else { return false }
        return canNavigate(to: episode - 1)
    }

    private var canNavigateToNextEpisode: Bool {
        guard let episode = currentEpisodeForNavigation else { return false }
        return canNavigate(to: episode + 1)
    }

    private func canNavigate(to episode: Int) -> Bool {
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

    private func videoMatchByFilename(forEpisode episode: Int) -> (video: Videos, index: Int)? {
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

    private var playlistIndex: Int {
        if let index = resolvedVideoFiles.firstIndex(where: { matchesVideo($0, fileIndex) }) {
            return index
        }
        return currentVideoIndex
    }

    private var currentEpisodeLimit: Int {
        if let media = currentResolvedVideo?.media {
            return TorrentBatchResolver.episodes(for: media)
        }
        return totalEpisodes
    }

    private var playlistVideos: [Videos] {
        if !resolvedVideoFiles.isEmpty {
            return resolvedVideoFiles.compactMap { videoMatch(for: $0)?.video }
        }
        return allVideos
    }

    /// options.svelte Playlist item and castplayer.svelte's Playlist dialog
    /// both call `selectFile(file)` — same underlying switch either way.
    private func selectPlaylistVideo(_ video: Videos) {
        if let idx = allVideos.firstIndex(of: video), idx != currentVideoIndex {
            let targetEpisode = episodeNumber + (idx - currentVideoIndex)
            switchToVideo((video: video, index: idx), episode: targetEpisode)
        }
    }

    private func matchesVideo(_ file: TorrentBatchResolver.ResolvedItem<Videos>, _ index: UInt) -> Bool {
        videoMatch(for: file)?.video.videoIndex?.uintValue == index
    }

    private func videoMatch(for file: TorrentBatchResolver.ResolvedItem<Videos>) -> (video: Videos, index: Int)? {
        allVideos.enumerated().first { _, video in
            video.objectID == file.item.objectID
                || video.videoIndex == file.item.videoIndex
        }.map { ($0.element, $0.offset) }
    }

    private func episodeNumber(for file: TorrentBatchResolver.ResolvedItem<Videos>) -> Int {
        file.episodeReference.intValue ?? episodeNumber
    }

    private func switchToResolvedVideoFile(_ file: TorrentBatchResolver.ResolvedItem<Videos>) {
        guard let match = videoMatch(for: file) else { return }
        currentResolvedVideoFile = file
        switchToVideo(match, episode: episodeNumber(for: file), media: file.media)
    }

    /// Switches to a different video file within the same torrent batch.
    private func switchToVideo(_ match: (video: Videos, index: Int), episode: Int, media: AnimeItem? = nil) {
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
    private func requestEpisodeChange(_ episode: Int, media: AnimeItem?) {
        onEpisodeChange?(episode, media ?? currentResolvedVideo?.media)
    }

    // MARK: - Title / episode navigation (Hayase episodesmodal.svelte)

    /// interface episodesmodal.svelte:
    /// ```
    /// <button class='text-lg ... hover:text-muted-foreground hover:underline'
    ///         onclick={() => goto(`/#/app/anime/${mediaInfo.media.id}`)}>
    ///   {mediaInfo.session.title}
    /// </button>
    /// ```
    @objc private func titleTapped() {
        // Same episodesmodal.svelte component, same hover:underline touch
        // equivalent — the Now Casting screen's own title button needs the
        // same flash, not the (now-hidden) main player's titleLabel.
        if activeCastDisplay != nil {
            flashInteractiveButton(nowCastingAnimeTitleButton)
        } else {
            flashInteractiveLabel(titleLabel)
        }
        openAnimeDetailFromTitle()
    }

    /// interface episodesmodal.svelte: the description doubles as the `Sheet.Trigger`
    /// that reveals the full episode list.
    @objc private func episodeLabelTapped() {
        if activeCastDisplay != nil {
            flashInteractiveButton(nowCastingEpisodeButton)
        } else {
            flashInteractiveLabel(episodeLabel)
        }
        presentEpisodeListSheet()
    }

    /// Touch equivalent of Tailwind's `hover:text-muted-foreground hover:underline` —
    /// a brief muted + underlined flash so the tap is acknowledged.
    private func flashInteractiveLabel(_ label: TextShadowLabel) {
        guard let text = label.content, !text.isEmpty, !label.underlinesText else { return }
        let color = label.textColor ?? .white
        let highlight = UIColor.HayaseTheme.mutedForeground
        // Preserve the label's CSS leading/baseline during and after feedback.
        label.textColor = highlight
        label.underlinesText = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { [weak label] in
            guard let label else { return }
            label.underlinesText = false
            label.textColor = color
        }
    }

    /// Same flash, for the Now Casting screen's title/episode `UIButton`s —
    /// mutating `titleLabel` directly on a button fights its own state-based
    /// title management, so this goes through setAttributedTitle instead.
    /// Not private: MiniPlayerManager's own cast overlay buttons reuse this
    /// rather than duplicating the same logic in a second file.
    func flashInteractiveButton(_ button: UIButton) {
        guard let text = button.title(for: .normal), !text.isEmpty else { return }
        let font = button.titleLabel?.font ?? .nunito(ofSize: 14)
        let color = button.titleColor(for: .normal) ?? .white
        let highlight = UIColor.HayaseTheme.mutedForeground
        button.setAttributedTitle(NSAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: highlight,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .underlineColor: highlight,
        ]), for: .normal)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { [weak button] in
            guard let button else { return }
            button.setAttributedTitle(nil, for: .normal)
            button.setTitle(text, for: .normal)
            button.setTitleColor(color, for: .normal)
            button.titleLabel?.font = font
        }
    }

    /// Mirrors episodesmodal.svelte's plain `goto()` to `/app/anime/[id]`; the app shell owns player exit/minimization.
    func openAnimeDetailFromTitle() {
        let mediaID = currentMediaID
        guard mediaID > 0 else { return }

        saveProgress()
        if let media = currentResolvedVideo?.media {
            Router.shared.cacheAnimeItem(media)
        }
        Router.shared.navigate(.anime(id: mediaID))
    }

    var isFullscreenForRouteNavigation: Bool {
        isFullscreenPresentation
    }

    func exitFullscreenForRouteNavigationIfNeeded() {
        if isFullscreenPresentation {
            exitFullscreenPresentation()
        }
    }

    /// interface episodesmodal.svelte: `<Sheet.Content class='w-full sm:w-[550px] ...'>`
    /// hosting `<EpisodesList {eps} media={media.data.Media} />`.
    /// `presenter` defaults to self; MiniPlayerManager's cast overlay passes
    /// the actual top view controller instead, since a minimized player's
    /// own view isn't part of the visible hierarchy and can't present.
    func presentEpisodeListSheet(from presenter: UIViewController? = nil) {
        let mediaID = currentMediaID
        guard mediaID > 0 else { return }

        let playingEpisode = currentEpisodeForNavigation ?? episodeNumber

        let sheet = PlayerEpisodeListViewController()
        sheet.anilistID = mediaID
        sheet.currentEpisode = playingEpisode
        sheet.media = currentResolvedVideo?.media
        sheet.totalEpisodesHint = currentEpisodeLimit
        // interface EpisodesList.svelte card click: `playEp(media, episode)`.
        sheet.onSelectEpisode = { [weak self] episode, media in
            guard let self else { return }
            let current = self.currentEpisodeForNavigation ?? self.episodeNumber
            guard episode != current else { return }
            self.saveProgress()
            self.playEpisode(episode, media: media)
        }
        sheet.onDismiss = { [weak self] in
            self?.scheduleHide()
        }

        let host = presenter ?? self
        // Keep the controls up for as long as the sheet is open.
        hideWork?.cancel()
        sheet.prepareSheetPresentation(from: host)
        host.present(sheet, animated: true)
    }

    @objc private func toggleTimeFormat() {
        showRemainingTime.toggle()
        updateTimeUI()
    }

    @objc private func seekBegan() {
        guard wasPausedBeforeScrub == nil else { return }
        wasPausedBeforeScrub = isPaused
        if !isPaused { surface.mpv.pausePlayback() }
        doubleTapSeekRestoreWork?.cancel()
        doubleTapSeekRestoreWork = nil
        isSeeking = true
        hideWork?.cancel()
        updateInterfaceOverlayVisibility(animated: true)
    }

    @objc private func seekChanged() {
        let t = Double(seekBar.value) * duration
        if showRemainingTime {
            timeLabel.content = "-\(fmtTime(max(0, duration - t))) / \(fmtTime(duration))"
        } else {
            timeLabel.content = "\(fmtTime(t)) / \(fmtTime(duration))"
        }
        chapterLabel.content = chapterTitle(at: t)
        previewRequest = UUID()
        let request = previewRequest
        thumbnailer.thumbnail(at: t) { [weak self] image in
            guard let self, self.previewRequest == request, self.seekBar.isSeeking else { return }
            self.seekingImage.image = image
            self.seekingImage.contentMode = self.surface.displayLayer.videoGravity == .resizeAspectFill ? .scaleAspectFill : .scaleAspectFit
            self.seekingImage.isHidden = image == nil
        }
        updateInterfaceOverlayVisibility(animated: true)
    }

    @objc private func seekEnded() {
        guard let wasPaused = wasPausedBeforeScrub else { return }
        wasPausedBeforeScrub = nil
        previewRequest = UUID()
        seekingImage.isHidden = true
        let seekFraction = Double(seekBar.value)
        let targetTime = seekFraction * duration
        pendingSeekDisplayTime = targetTime
        lastSeekTime = Date()

        surface.mpv.seek(to: targetTime)
        showPlayerAnimation(icon: targetTime > currentTime ? "fast-forward" : "rewind")
        if !wasPaused { surface.mpv.play() }
        updateInterfaceOverlayVisibility(animated: true)
        scheduleHide()

        doubleTapSeekRestoreWork?.cancel()
        let restoreWork = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.doubleTapSeekRestoreWork = nil
            self.isSeeking = false
            self.pendingSeekDisplayTime = nil
            self.updateTimeUI()
        }
        doubleTapSeekRestoreWork = restoreWork
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: restoreWork)
    }

    @objc private func optionsTapped() {
        hideWork?.cancel()
        showOptionsSheet()
    }

    private func showSeekPreview(at fraction: CGFloat?) {
        previewRequest = UUID()
        guard let fraction, fraction > 0, duration > 0 else { seekPreview.isHidden = true; return }
        let request = previewRequest
        let time = Double(fraction) * duration
        let title = chapterTitle(at: time)
        seekPreview.configure(title: title, time: fmtTime(time), image: nil)
        seekPreview.isHidden = false
        positionSeekPreview(fraction: fraction)
        thumbnailer.thumbnail(at: time) { [weak self] image in
            guard let self, self.previewRequest == request else { return }
            self.seekPreview.configure(title: title, time: self.fmtTime(time), image: image)
            self.positionSeekPreview(fraction: fraction)
        }
    }

    private func positionSeekPreview(fraction: CGFloat) {
        let bar = seekBar.convert(seekBar.bounds, to: overlay)
        let centerX = bar.minX + min(max(70, bar.width * fraction), max(70, bar.width - 70))
        let size = seekPreview.intrinsicContentSize
        seekPreview.frame = CGRect(x: centerX - size.width / 2, y: bar.maxY - 36 - size.height,
                                   width: size.width, height: size.height)
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
        for dict in renderer.getVideoTracks() {
            if let track = makeTrack(from: dict, type: "video") {
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

    /// `screenshot` of util.ts: the frame is copied, and a toast says so with an action to have it as a file
    private func captureScreenshot() {
        surface.mpv.captureScreenshotPNGData { [weak self] data in
            guard let self else { return }
            guard let data else {
                // the interface downloads the file when it cannot copy it; there is no frame to give here
                AppErrorToast.show("", title: "Failed to copy screenshot to clipboard.", duration: 4)
                return
            }

            UIPasteboard.general.setData(data, forPasteboardType: "public.png")
            AppErrorToast.success("Saved screenshot to clipboard",
                                  description: "Click here to download it as a PNG file instead.",
                                  action: ToastAction(label: "Download") { [weak self] in
                                      self?.downloadScreenshot(data)
                                  })
        }
    }

    /// `download()` of util.ts: the PNG as `screenshot_<time>.png`, which the share sheet puts in Files
    private func downloadScreenshot(_ data: Data) {
        let name = "screenshot_\(Int(Date().timeIntervalSince1970 * 1000)).png"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            AppErrorToast.show(error.localizedDescription, title: "Failed to save file!")
            return
        }
        let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let popover = activity.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
        }
        (presentedViewController ?? self).present(activity, animated: true)
    }

    private func showOptionsSheet(openMenu: String? = nil) {
        guard presentedViewController == nil else { return }
        // Keep this synchronous path cheap so the menu appears immediately.
        // MKV language parsing can touch disk and is done from track readiness instead.
        let freshTracks = currentTracksForOptions()
        self.tracks = freshTracks

        let optionsVC = PlayerOptionsController()
        optionsVC.preparePresentation()

        // Populate data
        optionsVC.audioTracks = freshTracks.filter { $0.type == "audio" }
        optionsVC.videoTracks = freshTracks.filter { $0.type == "video" }
        optionsVC.subtitleTracks = freshTracks.filter { $0.type == "sub" }
        optionsVC.chapters = chapters
        optionsVC.currentSpeed = playbackRate
        optionsVC.subtitleDelay = subtitleDelay
        optionsVC.isDebandActive = Settings.deband
        optionsVC.isFullscreenActive = isFullscreenPresentation
        optionsVC.allVideos = playlistVideos
        optionsVC.currentVideoEntity = videoEntity
        optionsVC.displays = webTorrentDisplays

        if #available(iOS 15.0, *) {
            optionsVC.isPiPActive = pipController?.isPictureInPictureActive ?? false
        }

        // Wire callbacks
        optionsVC.onSelectAudioTrack = { [weak self] trackId in
            self?.surface.mpv.setAudioTrack(trackId)
            self?.showPlayerTextAnimation(freshTracks.first { $0.type == "audio" && $0.id == trackId }?.title ?? "Default")
        }

        optionsVC.onSelectVideoTrack = { [weak self] trackId in
            self?.surface.mpv.setVideoTrack(trackId)
            self?.showPlayerTextAnimation(freshTracks.first { $0.type == "video" && $0.id == trackId }?.title ?? "Default")
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
            self?.selectPlaylistVideo(video)
        }

        optionsVC.onToggleDeband = {
            Settings.deband.toggle()
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

        optionsVC.onScreenshot = { [weak self] in
            self?.captureScreenshot()
        }

        optionsVC.onSubtitleDelayChanged = { [weak self] delay in
            self?.subtitleDelay = delay
            self?.surface.mpv.setSubtitleDelay(delay)
        }
        optionsVC.onAddSubtitleFile = { [weak self] in
            let types = ["ass", "ssa", "srt", "vtt", "sub"].map { UTType(filenameExtension: $0) ?? .data }
            let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
            picker.delegate = self
            self?.present(picker, animated: true)
        }

        optionsVC.onSelectDisplay = { [weak self] display in
            self?.startCasting(to: display)
        }

        optionsVC.onDismiss = { [weak self] in
            self?.scheduleHide()
        }
        optionsVC.onKeybindAction = { [weak self] id, shift in self?.runPlayerKeybind(id, shift: shift) }
        if let openMenu { optionsVC.openRootMenu(named: openMenu) }

        present(optionsVC, animated: true)
    }

    func enterFullscreenForPlayerRouteIfNeeded() {
        guard UIDevice.current.userInterfaceIdiom == .phone,
              Router.shared.currentRoute == .player,
              !isMinimizing else { return }
        enterFullscreenPresentation()
    }

    private func toggleFullscreenPresentation() {
        if isFullscreenPresentation {
            exitFullscreenPresentation()
        } else {
            enterFullscreenPresentation()
        }
    }

    private func enterFullscreenPresentation() {
        guard !isFullscreenPresentation else { return }
        isFullscreenPresentation = true
        hayaseSidebarController?.setPlayerFullscreenActive(true)
        setNeedsStatusBarAppearanceUpdate()
        setNeedsUpdateOfHomeIndicatorAutoHidden()
    }

    private func exitFullscreenPresentation() {
        guard isFullscreenPresentation else { return }
        isFullscreenPresentation = false
        hayaseSidebarController?.setPlayerFullscreenActive(false)
        setNeedsStatusBarAppearanceUpdate()
        setNeedsUpdateOfHomeIndicatorAutoHidden()
    }

    // Auto-plays next episode (Hayase web: next() called at EOF)
    private func handleFileEnded() {
        guard Settings.playerAutoplay,
              !(MiniPlayerManager.shared.isActive && MiniPlayerManager.shared.activePlayer === self),
              (W2GLobby.shared.client?.peers.count ?? 2) > 1,
              let currentEpisode = currentEpisodeForNavigation,
              canNavigate(to: currentEpisode + 1) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.nextTapped() }
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
        let prefAudio = Settings.audioLanguage
        let prefSub   = Settings.subtitleLanguage

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
        fileChapters = chapters
        chaptersLoadedDuration = 0
        loadChapters()
    }

    // MARK: - Mini-player support (Hayase wrapper.svelte)

    /// Returns the MPV surface view so MiniPlayerManager can reparent it.
    var surfaceView: MPVSurfaceView { surface }

    /// Toggles play/pause from the mini-player.
    func togglePlayPause() {
        playPauseTapped()
    }
}

// MARK: - PiPControllerDelegate (System PiP — streamyfin)

@available(iOS 15.0, *)
extension VideoPlayerViewController: PiPControllerDelegate {

    func pipController(_ controller: PiPController, willStartPictureInPicture: Bool) {
        // Hide in-app overlay while system PiP is active.
        setControls(visible: false)
    }

    func pipController(_ controller: PiPController, didStartPictureInPicture started: Bool) {
        guard !started else { return }
        autoPiPRequested = false
        if Settings.playerPause,
           UIApplication.shared.applicationState == .background,
           !isPaused {
            visibilityPauseWasPlaying = true
            surface.mpv.pausePlayback()
        }
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
