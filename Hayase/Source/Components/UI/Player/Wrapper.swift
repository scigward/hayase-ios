// Mirrors: src/lib/components/ui/player/wrapper.svelte, src/lib/components/ui/player/player.svelte, src/routes/+layout.svelte, src/app.css

/// Hayase wrapper.svelte — in-app mini-player manager.
///
/// In Hayase, the player component (wrapper.svelte) is always mounted in the
/// layout. When the user navigates away from `/app/player`, it switches to
/// mini-player mode: a 22rem-wide floating window at the bottom-right corner,
/// draggable, with click-to-restore. The torrent session stays alive.
///
/// Keep the mini-player in the app shell, above route content but below modal
/// presentations. This mirrors the web wrapper's z-[49] below dialog portals'
/// z-50, so their single striped backdrop covers the mini-player too.
import UIKit
import CoreData

/// Reports finger down / up, which `mobile:active:paused-show` needs and gesture
/// recognizers (a tap or drag cancels the touch) would hide.
private final class MiniPlayerContainerView: UIView, UIGestureRecognizerDelegate {
    var onPress: ((Bool) -> Void)?
    var onBackgroundTouchBegan: (() -> Void)?

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldReceive touch: UITouch) -> Bool {
        // UIControl touches do not stop ancestor recognizers automatically.
        // Match interface's stopPropagation on playback/cast controls.
        var candidate = touch.view
        while let view = candidate {
            if view is UIControl { return false }
            if view === self { break }
            candidate = view.superview
        }
        if gestureRecognizer is UITapGestureRecognizer { onBackgroundTouchBegan?() }
        return true
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        onPress?(true)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        onPress?(false)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        onPress?(false)
    }
}

final class MiniPlayerManager {

    static let shared = MiniPlayerManager()

    // MARK: - Constants (Hayase wrapper.svelte)

    /// Hayase wrapper.svelte: `max-w-[22rem] px-4` with a `w-full aspect-video`
    /// child. Tailwind uses border-box sizing, so the visible rounded player is
    /// min(viewport, 352pt) minus 32pt horizontal padding.
    private let maxOuterWidth: CGFloat = 352
    private let edgePadding: CGFloat = 16
    /// Corner radius matching Hayase's `[&>*]:rounded-lg` (`--radius: 0.5rem`).
    private let cornerRadius: CGFloat = 8
    /// Snap animation (Hayase: `transition-transform duration-[500ms]
    /// ease-[cubic-bezier(0.3,1.5,0.8,1)]`).
    private let snapDuration: TimeInterval = 0.5
    private static let fadeInKey = "miniPlayerFadeIn"
    /// The key of the rise from the bottom edge, which a drag or a snap takes over from.
    private static let riseKey = "miniPlayerRise"
    /// How much of the video is visible when tucked to the edge (Hayase: `.paused
    /// { --padding-right: calc(100% - 3rem) }` leaves 3rem of the box, which is 2rem of
    /// video once the `px-4` padding is taken off).
    private let peekWidth: CGFloat = 32
    /// Keep the WebTorrent restore VideoService alive until metadata has been
    /// fetched and a player owns it. Without this strong reference the service
    /// is deallocated before its async playTorrent callback can post results.
    private var pendingWebTorrentRestoreService: VideoService?
    private var pendingWebTorrentRestoreObserver: NSObjectProtocol?
    private var pendingWebTorrentRestoreTimeout: DispatchWorkItem?
    private let webTorrentRestoreTimeout: TimeInterval = 120
    private let innerContainerTag = 100
    private let overlayTag = 101
    private var miniCastTimeLabel: UILabel?
    private var miniCastProgressFill: UIView?
    private var miniCastProgressFillWidth: NSLayoutConstraint?
    private var miniCastProgressContainer: UIView?

    private static let bannerBackdropDidChange = Notification.Name("HayaseHomeBannerBackdropDidChange")
    private static let bannerBackdropRouteKey = "route"
    private static let bannerBackdropAlphaKey = "alpha"
    private static let bannerBackdropPlayerRoute = "player"

    // MARK: - State

    /// The active fullscreen player VC. Kept alive while the mini-player is
    /// visible so all player/streaming state is preserved.
    private(set) var activePlayer: VideoPlayerViewController?

    /// The shell's root view owns the mini-player; UIKit presentations are
    /// layered above it in the same window.
    private weak var hostView: UIView?

    /// The floating container inside the app shell.
    private var containerView: UIView?

    private var playPauseButton: GhostButton?

    /// True when the mini-player is currently visible.
    var isActive: Bool { containerView != nil && activePlayer != nil }

    // MARK: - Dragging state (Hayase pointer events)

    /// Whether the user is currently dragging the mini-player.
    private var isDragging = false
    private var isRestoring = false

    // MARK: - Tuck/peek state (Hayase .paused / idle behavior)

    /// Whether the mini-player is currently tucked to the edge (mostly hidden).
    private var isTucked = false
    /// A finger is down on the mini-player (`mobile:active:paused-show`).
    private var isPressed = false
    /// A first tap on the peek reveals controls; only a subsequent video tap opens the player.
    private var isRevealedForInteraction = false
    private var touchBeganTucked = false
    private var settleAnimator: UIViewPropertyAnimator?
    /// The fully-revealed frame saved on snap / reposition.
    private var revealedFrame: CGRect = .zero
    /// Whether the container last snapped to the right side (`true`) or left (`false`).
    private var isSnappedToRight = true
    private var isSnappedToTop = false

    func containsMiniPlayer(_ view: UIView?) -> Bool {
        guard let container = containerView else { return false }
        var candidate = view
        while let current = candidate {
            if current === container { return true }
            candidate = current.superview
        }
        return false
    }

    private func hostPlayerSurfaceInMiniContainer(_ player: VideoPlayerViewController, inner: UIView) {
        if ExternalDisplayManager.shared.updateLocalPresentationHost(
            for: player,
            view: inner,
            layout: .fillBounds
        ) {
            return
        }

        let surface = player.surfaceView
        surface.translatesAutoresizingMaskIntoConstraints = true
        surface.frame = inner.bounds
        surface.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        inner.insertSubview(surface, at: 0)
    }

    private func hostPlayerSurfaceInFullscreen(_ player: VideoPlayerViewController) {
        if ExternalDisplayManager.shared.updateLocalPresentationHost(
            for: player,
            view: player.view,
            layout: .pinnedToEdges
        ) {
            return
        }

        let surface = player.surfaceView
        surface.translatesAutoresizingMaskIntoConstraints = false
        player.view.insertSubview(surface, at: 0)
        NSLayoutConstraint.activate([
            surface.topAnchor.constraint(equalTo: player.view.topAnchor),
            surface.bottomAnchor.constraint(equalTo: player.view.bottomAnchor),
            surface.leadingAnchor.constraint(equalTo: player.view.leadingAnchor),
            surface.trailingAnchor.constraint(equalTo: player.view.trailingAnchor),
        ])
    }

    // MARK: - Session State Persistence (Hayase server.active store)

    /// UserDefaults key for persisting the active mini-player session.
    /// Mirrors Hayase's `server.active` store: when the app relaunches, if this
    /// key has data the mini-player is restored automatically (just like Hayase
    /// re-mounts the player component on reload when a torrent session exists).
    private static let sessionStateKey: String = {
        // the session of the earlier name is taken over, once
        let defaults = UserDefaults.standard
        if let legacy = defaults.dictionary(forKey: "nyais_miniPlayerSessionState") {
            if defaults.object(forKey: "miniPlayerSessionState") == nil { defaults.set(legacy, forKey: "miniPlayerSessionState") }
            defaults.removeObject(forKey: "nyais_miniPlayerSessionState")
        }
        return "miniPlayerSessionState"
    }()

    // MARK: - Init

    private init() {}

    // MARK: - Public API

    /// Minimizes the fullscreen player into the in-app mini-player.
    /// Equivalent to Hayase's `isMiniplayer = true` (navigating away from
    /// `/app/player`).
    func minimize(_ player: VideoPlayerViewController,
                  removalAnimated: Bool = true,
                  fadeIn: Bool = false) {
        // If there's already a different player active, close it first.
        if let existing = activePlayer, existing !== player {
            close()
        }
        guard let host = miniPlayerHost() else { return }
        activePlayer = player
        hostView = host

        // Create the mini-player container (shadow + rounded corners).
        let container = makeContainer()
        host.addSubview(container)
        containerView = container

        // Reparent locally, or just move the external-output placeholder while
        // the external display keeps ownership of the actual MPV surface.
        guard let inner = container.viewWithTag(innerContainerTag) else { return }
        hostPlayerSurfaceInMiniContainer(player, inner: inner)

        // Add mini-player controls overlay.
        addOverlay(to: container)

        player.onCastStateChanged = { [weak self] in
            guard let self, let container = self.containerView else { return }
            self.addOverlay(to: container)
        }
        player.onCastTick = { [weak self] elapsed, duration in
            self?.updateMiniCastProgress(elapsed: elapsed, duration: duration)
        }

        // Root view transitions fade wrapper.svelte with the destination.
        isPressed = false
        isRevealedForInteraction = false
        isTucked = player.isPaused
        isSnappedToRight = true
        isSnappedToTop = false
        repositionContainer()
        container.alpha = 1
        if fadeIn {
            // Core Animation, because the route transition makes its changes with UIView animations off
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0
            fade.toValue = 1
            fade.duration = 0.25
            fade.timingFunction = CAMediaTimingFunction(controlPoints: 0.25, 0.1, 0.25, 1)
            container.layer.add(fade, forKey: Self.fadeInKey)
        }

        // Flag to prevent viewWillDisappear from tearing down the player.
        // Keep this state for the entire mini-player lifetime: tab and modal
        // appearance callbacks can arrive after a nonanimated pop/dismiss.
        player.isMinimizing = true
        let finishMinimize: () -> Void = { [weak self] in
            // Reposition after removal in case safe area insets changed.
            self?.repositionContainer()
        }
        if let nav = player.navigationController,
           nav.viewControllers.contains(player) {
            nav.popViewController(animated: removalAnimated)
            if removalAnimated, let coordinator = player.transitionCoordinator {
                coordinator.animate(alongsideTransition: nil) { _ in
                    finishMinimize()
                }
            } else {
                finishMinimize()
            }
        } else if player.presentingViewController != nil {
            player.dismiss(animated: removalAnimated, completion: finishMinimize)
        } else {
            finishMinimize()
        }

        // wrapper.svelte: the class change is a `transition-transform` from no transform to the place of the
        // mini-player (`translate3d(0, -1rem, 0)`, further right while paused), so it rises from the bottom edge
        // with the same bounce.
        let rise = CABasicAnimation(keyPath: "position")
        rise.fromValue = NSValue(cgPoint: CGPoint(x: revealedFrame.midX, y: revealedFrame.midY + edgePadding))
        rise.toValue = NSValue(cgPoint: container.layer.position)
        rise.duration = snapDuration
        rise.timingFunction = CAMediaTimingFunction(controlPoints: 0.3, 1.5, 0.8, 1)
        container.layer.add(rise, forKey: Self.riseKey)

        // Persist session state so the mini-player can be restored on relaunch
        // (Hayase: server.active persists via the store).
        saveSessionState(player)
    }

    /// Restores the fullscreen player from the mini-player.
    /// Equivalent to Hayase's `goto('/app/player/')` on mini-player click.
    func restore() {
        guard !isRestoring,
              let player = activePlayer,
              let container = containerView else { return }

        // Keep controls/state intact if there is no available presenter.
        guard let presenter = topViewController(), presenter !== player else { return }
        isTucked = false
        isPressed = false
        isRevealedForInteraction = false
        if settleAnimator?.state == .active { settleAnimator?.stopAnimation(true) }
        settleAnimator = nil
        playPauseButton = nil

        isRestoring = true

        player.onCastStateChanged = nil
        player.onCastTick = nil
        miniCastTimeLabel = nil
        miniCastProgressFill = nil
        miniCastProgressFillWidth = nil
        miniCastProgressContainer = nil

        // Restore the local presentation target. If external output owns the
        // surface, only its placeholder moves until that output ends.
        hostPlayerSurfaceInFullscreen(player)

        // Remove the mini-player from the shell before presenting the player.
        container.removeFromSuperview()
        containerView = nil
        hostView = nil

        // Restore the player route. iPhone presents fullscreen; iPad returns
        // to the app shell route so the sidebar remains visible.
        publishPlayerSidebarBackdropClear()
        player.isMinimizing = true          // prevent tearDownPlayer on restore too
        // wrapper.svelte keeps the same player mounted and the root layout
        // explicitly skips a view transition when entering /app/player on
        // mobile. Reattach in-place without UIKit's cross-dissolve/push so a
        // mini-player tap has the same immediate expansion semantics.
        presenter.presentHayasePlayer(player, animated: false) { [weak self] in
            player.isMinimizing = false
            self?.isRestoring = false
        }
    }

    /// Fully closes the mini-player and tears down the player + streaming.
    /// Equivalent to the user closing the Hayase player entirely.
    func close() {
        guard let player = activePlayer else { return }

        cancelPendingWebTorrentRestore()
        isRestoring = false
        isTucked = false
        isPressed = false
        isRevealedForInteraction = false
        if settleAnimator?.state == .active { settleAnimator?.stopAnimation(true) }
        settleAnimator = nil
        playPauseButton = nil
        player.onCastStateChanged = nil
        player.onCastTick = nil
        miniCastTimeLabel = nil
        miniCastProgressFill = nil
        miniCastProgressFillWidth = nil
        miniCastProgressContainer = nil

        // Clear persisted session so it won't auto-restore on next launch.
        clearSessionState()

        // Animate out before tearing down.
        if let container = containerView {
            UIView.animate(withDuration: 0.25, animations: {
                container.alpha = 0
                container.transform = CGAffineTransform(scaleX: 0.5, y: 0.5)
            }, completion: { [weak self] _ in
                container.removeFromSuperview()
                if self?.containerView === container {
                    self?.containerView = nil
                    self?.hostView = nil
                }
            })
        }

        player.tearDownPlayer()
        activePlayer = nil
    }

    // MARK: - Layout

    /// Repositions the mini-player container to the bottom-right corner,
    /// accounting for the shell's logical bounds and safe area insets. Called:
    /// - Immediately in minimize() so the container is positioned correctly
    /// - In the dismiss completion to adjust for safe area changes
    /// - From the shell's viewDidLayoutSubviews for rotation handling
    func repositionContainer() {
        guard let container = containerView,
              let host = hostView,
              !isDragging else { return }
        let bounds = host.bounds
        let size = miniSize(in: host)
        let safeBottom = host.safeAreaInsets.bottom
        let frame = CGRect(
            x: isSnappedToRight ? bounds.width - size.width - edgePadding : edgePadding,
            y: isSnappedToTop ? edgePadding + host.safeAreaInsets.top : bounds.height - size.height - safeBottom - edgePadding,
            width: size.width, height: size.height)
        revealedFrame = frame
        container.bounds.size = size
        if let inner = container.viewWithTag(innerContainerTag) {
            inner.frame = CGRect(origin: .zero, size: size)
        }
        if isTucked {
            var tuckedFrame = frame
            tuckedFrame.origin.x = isSnappedToRight ? bounds.width - peekWidth : -(frame.width - peekWidth)
            container.frame = tuckedFrame
        } else {
            container.frame = frame
        }
    }

    // MARK: - Host + Container creation

    /// The video keeps its own proportions, `aspect-video` only applies while there is none.
    private func miniSize(in host: UIView) -> CGSize {
        let visibleWidth = max(peekWidth, min(maxOuterWidth, host.bounds.width) - (edgePadding * 2))
        let aspect = activePlayer?.videoAspectRatio ?? 16.0 / 9.0
        return CGSize(width: visibleWidth, height: visibleWidth / aspect)
    }

    private func miniPlayerHost() -> UIView? {
        (UIApplication.shared.delegate as? AppDelegate)?.window?.rootViewController?.view
    }

    /// Builds the floating mini-player container view (Hayase wrapper.svelte
    /// mini-player div with rounded corners and shadow).
    private func makeContainer() -> UIView {
        let fallbackWidth = maxOuterWidth - (edgePadding * 2)
        let v = MiniPlayerContainerView(frame: CGRect(x: 0, y: 0, width: fallbackWidth, height: fallbackWidth * 9 / 16))
        v.onPress = { [weak self] pressed in
            self?.isPressed = pressed
            self?.settle()
        }
        v.onBackgroundTouchBegan = { [weak self] in
            guard let self else { return }
            // Capture before press-to-reveal changes the tucked frame/state.
            self.touchBeganTucked = self.isTucked ||
                (self.activePlayer?.isPaused == true && !self.isRevealedForInteraction)
        }
        // Inner container clips content to rounded corners.
        let inner = UIView(frame: v.bounds)
        inner.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        inner.backgroundColor = .black
        inner.clipsToBounds = true
        inner.layer.cornerRadius = cornerRadius
        inner.tag = innerContainerTag
        v.addSubview(inner)

        // Gestures (Hayase pointer events: drag + tap).
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.delegate = v
        v.addGestureRecognizer(pan)
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tap.delegate = v
        tap.require(toFail: pan)
        v.addGestureRecognizer(tap)

        return v
    }

    /// Adds the normal player's bottom-centered ghost play/pause button, or
    /// the Now Casting display (`player.svelte` / `castplayer.svelte` mini branches).
    /// Re-callable: removes any existing overlay first so cast state changes
    /// while already minimized can rebuild it in place.
    func refreshLoadingState(for player: VideoPlayerViewController) {
        guard activePlayer === player, let containerView else { return }
        addOverlay(to: containerView)
    }

    private func addOverlay(to container: UIView) {
        guard let inner = container.viewWithTag(innerContainerTag) else { return }
        inner.viewWithTag(overlayTag)?.removeFromSuperview()
        playPauseButton = nil
        guard let player = activePlayer, !player.isLoadingMetadata else { return }

        let overlay = UIView()
        overlay.tag = overlayTag
        overlay.translatesAutoresizingMaskIntoConstraints = false
        inner.addSubview(overlay)
        NSLayoutConstraint.activate([
            overlay.topAnchor.constraint(equalTo: inner.topAnchor),
            overlay.bottomAnchor.constraint(equalTo: inner.bottomAnchor),
            overlay.leadingAnchor.constraint(equalTo: inner.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: inner.trailingAnchor),
        ])

        if player.isCasting {
            overlay.backgroundColor = UIColor.HayaseTheme.background   // bg-background
            buildCastOverlay(in: overlay)
        } else {
            // interface: absolute bottom-0, justify-center; ghost size='icon', mb-1.
            let button = GhostButton(frame: .zero)
            button.translatesAutoresizingMaskIntoConstraints = false
            button.tintColor = UIColor.HayaseTheme.foreground
            button.clipsToBounds = false
            button.addTarget(self, action: #selector(toggleMiniPlayback), for: .touchUpInside)
            overlay.addSubview(button)
            NSLayoutConstraint.activate([
                button.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
                button.bottomAnchor.constraint(equalTo: overlay.bottomAnchor, constant: -4),
                button.widthAnchor.constraint(equalToConstant: 36),
                button.heightAnchor.constraint(equalToConstant: 36),
            ])
            playPauseButton = button
            setPlayPauseImage(isPaused: player.isPaused)
        }
    }

    @objc private func toggleMiniPlayback() {
        activePlayer?.togglePlayPause()
    }

    private func setPlayPauseImage(isPaused: Bool) {
        // iconSizes.lg = 1.2rem; Play has 2pt horizontal padding in interface.
        playPauseButton?.setImage(UIImage.hayaseFilledIcon(isPaused ? "play" : "pause",
                                                         pointSize: 19.2), for: .normal)
        playPauseButton?.imageEdgeInsets = UIEdgeInsets(top: 0, left: isPaused ? 2 : 0,
                                                       bottom: 0, right: isPaused ? 2 : 0)
        playPauseButton?.imageView?.clipsToBounds = false
        playPauseButton?.imageView?.layer.shadowColor = UIColor.black.cgColor
        playPauseButton?.imageView?.layer.shadowOffset = .zero
        playPauseButton?.imageView?.layer.shadowOpacity = 1
        playPauseButton?.imageView?.layer.shadowRadius = 7
        playPauseButton?.accessibilityLabel = isPaused ? "Play" : "Pause"
    }

    /// `isMiniplayer` branch: no max-w-[320px] cap, no `{#if !isMiniplayer}`
    /// controls row, otherwise the same title/EpisodesModal/progress content
    /// as the full player. Not shared code with VideoPlayerViewController's
    /// copy (different files, different owning types) — kept in sync by
    /// value, flagged here rather than silently duplicated unremarked.
    private func buildCastOverlay(in overlay: UIView) {
        guard let player = activePlayer else { return }

        let titleLabel = UILabel()
        titleLabel.text = "Now Casting"
        titleLabel.textColor = UIColor.HayaseTheme.foreground
        titleLabel.font = .nunito(ofSize: 24, weight: .bold)   // text-2xl font-bold
        titleLabel.numberOfLines = 1

        let animeTitleButton = UIButton(type: .system)
        animeTitleButton.setTitleColor(UIColor.HayaseTheme.foreground, for: .normal)
        animeTitleButton.titleLabel?.font = .nunito(ofSize: 18, weight: .regular)   // text-lg font-normal
        animeTitleButton.titleLabel?.numberOfLines = 1
        animeTitleButton.contentHorizontalAlignment = .leading
        animeTitleButton.setTitle(player.animeTitleForDisplay(), for: .normal)
        animeTitleButton.titleLabel?.layer.shadowColor = UIColor.black.cgColor
        animeTitleButton.titleLabel?.layer.shadowOffset = .zero
        animeTitleButton.titleLabel?.layer.shadowOpacity = 0.8
        animeTitleButton.titleLabel?.layer.shadowRadius = 3
        // episodesmodal.svelte's title uses `use:click`, which calls
        // e.stopPropagation() — the tap navigates to the anime page and does
        // NOT also trigger the outer wrapper's openPlayer(). A real button
        // here gets that for free (it consumes the touch before the
        // container's own tap gesture sees it).
        animeTitleButton.addAction(UIAction { [weak self] _ in
            guard let self, let player = self.activePlayer else { return }
            player.flashInteractiveButton(animeTitleButton)
            player.openAnimeDetailFromTitle()
        }, for: .touchUpInside)

        let episodeButton = UIButton(type: .system)
        episodeButton.setTitleColor(UIColor.HayaseTheme.castMutedText, for: .normal)
        episodeButton.titleLabel?.font = .nunito(ofSize: 14, weight: .light)   // text-sm font-light
        episodeButton.titleLabel?.numberOfLines = 1
        episodeButton.contentHorizontalAlignment = .leading
        episodeButton.setTitle(player.episodeDescriptionForDisplay(), for: .normal)
        episodeButton.titleLabel?.layer.shadowColor = UIColor.black.cgColor
        episodeButton.titleLabel?.layer.shadowOffset = .zero
        episodeButton.titleLabel?.layer.shadowOpacity = 0.8
        episodeButton.titleLabel?.layer.shadowRadius = 3
        episodeButton.addAction(UIAction { [weak self] _ in
            guard let self, let player = self.activePlayer, let presenter = self.topViewController() else { return }
            player.flashInteractiveButton(episodeButton)
            player.presentEpisodeListSheet(from: presenter)
        }, for: .touchUpInside)

        let timeLabel = UILabel()
        timeLabel.textColor = UIColor.HayaseTheme.foreground
        timeLabel.font = .nunito(ofSize: 14, weight: .light)
        timeLabel.textAlignment = .right

        let progressContainer = UIView()
        progressContainer.clipsToBounds = true
        progressContainer.layer.cornerRadius = 2
        let progressTrack = UIView()
        progressTrack.backgroundColor = UIColor.HayaseTheme.castProgressTrack
        let progressFill = UIView()
        progressFill.backgroundColor = UIColor.HayaseTheme.primary
        progressContainer.addSubview(progressTrack)
        progressContainer.addSubview(progressFill)

        let column = UIStackView(arrangedSubviews: [titleLabel, animeTitleButton, episodeButton, timeLabel, progressContainer])
        column.axis = .vertical
        column.spacing = 8   // gap-2
        column.alignment = .fill
        column.setCustomSpacing(16, after: titleLabel)          // gap-2 + mb-2
        column.setCustomSpacing(20, after: episodeButton)        // gap-2 + mt-3
        overlay.addSubview(column)

        [column, progressContainer, progressTrack, progressFill].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
        }

        let fillWidth = progressFill.widthAnchor.constraint(equalTo: progressContainer.widthAnchor, multiplier: 0)
        NSLayoutConstraint.activate([
            column.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
            column.centerYAnchor.constraint(equalTo: overlay.centerYAnchor),
            column.leadingAnchor.constraint(greaterThanOrEqualTo: overlay.leadingAnchor, constant: 32),   // px-8
            column.trailingAnchor.constraint(lessThanOrEqualTo: overlay.trailingAnchor, constant: -32),

            progressContainer.heightAnchor.constraint(equalToConstant: 4),   // h-1
            progressTrack.leadingAnchor.constraint(equalTo: progressContainer.leadingAnchor),
            progressTrack.trailingAnchor.constraint(equalTo: progressContainer.trailingAnchor),
            progressTrack.topAnchor.constraint(equalTo: progressContainer.topAnchor),
            progressTrack.heightAnchor.constraint(equalToConstant: 2),
            progressFill.leadingAnchor.constraint(equalTo: progressContainer.leadingAnchor),
            progressFill.topAnchor.constraint(equalTo: progressContainer.topAnchor),
            progressFill.heightAnchor.constraint(equalToConstant: 2),
            fillWidth,
        ])

        miniCastTimeLabel = timeLabel
        miniCastProgressFill = progressFill
        miniCastProgressFillWidth = fillWidth
        miniCastProgressContainer = progressContainer
    }

    /// `on:click={openPlayer}` on castplayer.svelte's outer wrapper —
    /// the existing container-level tap gesture (handleTap, unchanged)
    /// restores the fullscreen player for any tap not consumed by the title/
    /// episode buttons above (which stop their own touches from reaching it,
    /// matching `use:click`'s stopPropagation on web).
    private func updateMiniCastProgress(elapsed: Double, duration: Double) {
        guard let timeLabel = miniCastTimeLabel,
              let fill = miniCastProgressFill,
              let container = miniCastProgressContainer,
              let oldWidth = miniCastProgressFillWidth else { return }
        timeLabel.text = "\(fmtDisplayTime(elapsed)) / \(fmtDisplayTime(duration))"
        let progress = duration > 0 ? CGFloat(elapsed / duration) : 0
        oldWidth.isActive = false
        let newWidth = fill.widthAnchor.constraint(equalTo: container.widthAnchor, multiplier: min(max(progress, 0), 1))
        newWidth.isActive = true
        miniCastProgressFillWidth = newWidth
    }

    private func fmtDisplayTime(_ seconds: Double) -> String {
        let s = max(0, Int(safe: seconds))
        let h = s / 3600; let m = (s % 3600) / 60; let sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec)
                     : String(format: "%d:%02d", m, sec)
    }

    // MARK: - Gesture handlers (Hayase wrapper.svelte pointer events)

    /// Pan gesture — dragging the mini-player. On release, snaps to the
    /// nearest corner (Hayase's endDragging logic).
    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let container = containerView,
              let rootView = hostView else { return }
        let translation = gesture.translation(in: rootView)

        switch gesture.state {
        case .began:
            if let animator = settleAnimator, animator.state == .active {
                animator.stopAnimation(false)
                animator.finishAnimation(at: .current)
            }
            settleAnimator = nil
            container.layer.removeAnimation(forKey: Self.riseKey)
            isDragging = true
            // If tucked, un-tuck so the drag starts from wherever the container is.
            if isTucked { isTucked = false }
        case .changed:
            container.center = CGPoint(
                x: container.center.x + translation.x,
                y: container.center.y + translation.y)
            gesture.setTranslation(.zero, in: rootView)
        case .ended, .cancelled:
            isDragging = false
            snapToNearestCorner()
        default:
            break
        }
    }

    /// A peek tap reveals the paused mini-player without navigating or resuming.
    /// This touch adaptation leaves its controls reachable after finger release.
    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended, !isDragging, !isRestoring else { return }
        if touchBeganTucked {
            touchBeganTucked = false
            isRevealedForInteraction = true
            settle()
            return
        }
        Router.shared.navigate(.player)
    }

    // MARK: - Corner snapping (Hayase endDragging)

    /// Hayase's endDragging: determines which half (top/bottom, left/right)
    /// the center is in, then snaps to the corresponding corner.
    private func snapToNearestCorner() {
        guard let container = containerView,
              let host = hostView else { return }
        let center = container.center
        let safeInsets = host.safeAreaInsets

        let isTop = center.y < host.bounds.height / 2
        let isLeft = center.x < host.bounds.width / 2

        let targetX: CGFloat
        let targetY: CGFloat

        let size = miniSize(in: host)

        if isLeft {
            targetX = edgePadding
        } else {
            targetX = host.bounds.width - size.width - edgePadding
        }

        if isTop {
            targetY = edgePadding + safeInsets.top
        } else {
            targetY = host.bounds.height - size.height - safeInsets.bottom - edgePadding
        }

        isSnappedToRight = !isLeft
        isSnappedToTop = isTop
        let targetFrame = CGRect(
            x: targetX, y: targetY,
            width: size.width, height: size.height)
        revealedFrame = targetFrame

        settle()
    }

    // MARK: - Tuck / Reveal (Hayase .paused)

    /// Moves the mini-player to where it belongs: tucked to its edge, leaving `peekWidth`
    /// of the video, while the video is paused, and whole while it plays or is pressed
    /// (Hayase: `!$isPlaying && 'paused'` plus `mobile:active:paused-show`), with the
    /// `transition-transform duration-[500ms] ease-[cubic-bezier(0.3,1.5,0.8,1)]` the
    /// class change is animated with.
    private func settle(isPaused: Bool? = nil) {
        guard let container = containerView,
              let host = hostView,
              !isDragging, !isRestoring else { return }
        isTucked = (isPaused ?? (activePlayer?.isPaused == true)) && !isPressed && !isRevealedForInteraction
        container.layer.removeAnimation(forKey: Self.riseKey)
        var frame = revealedFrame
        if isTucked {
            frame.origin.x = isSnappedToRight ? host.bounds.width - peekWidth : -(frame.width - peekWidth)
        }
        if let animator = settleAnimator, animator.state == .active {
            animator.stopAnimation(false)
            animator.finishAnimation(at: .current)
        }
        let animator = UIViewPropertyAnimator(
            duration: snapDuration,
            timingParameters: UICubicTimingParameters(controlPoint1: CGPoint(x: 0.3, y: 1.5),
                                                      controlPoint2: CGPoint(x: 0.8, y: 1)))
        animator.addAnimations { container.frame = frame }
        settleAnimator = animator
        animator.startAnimation()
    }

    // MARK: - Helpers

    private func topViewController() -> UIViewController? {
        guard let appDelegate = UIApplication.shared.delegate as? AppDelegate,
              let window = appDelegate.window else { return nil }
        var vc = window.rootViewController
        while let presented = vc?.presentedViewController, !presented.isBeingDismissed {
            vc = presented
        }
        return vc
    }

    private func publishPlayerSidebarBackdropClear() {
        NotificationCenter.default.post(name: Self.bannerBackdropDidChange,
                                        object: nil,
                                        userInfo: [
                                            Self.bannerBackdropRouteKey: Self.bannerBackdropPlayerRoute,
                                            Self.bannerBackdropAlphaKey: CGFloat(0),
                                        ])
    }

    /// Called from the player's didChangePause delegate: a paused video tucks away at once,
    /// a playing one comes back out.
    func updatePlayPauseIcon(isPaused: Bool) {
        setPlayPauseImage(isPaused: isPaused)
        isRevealedForInteraction = false
        settle(isPaused: isPaused)
    }

    // MARK: - Session State Persistence

    private static func isHTTPStreamPath(_ path: String) -> Bool {
        let lower = path.lowercased()
        return lower.hasPrefix("http://") || lower.hasPrefix("https://")
    }

    /// Saves the minimum data required to restore the mini-player on relaunch.
    /// Mirrors Hayase's `server.active` store — we just need enough metadata
    /// to load the torrent again and reconnect to the right file.
    private func saveSessionState(_ player: VideoPlayerViewController) {
        guard let path = player.videoEntity?.videoPath else { return }

        let torrentEntity = player.videoEntity?.torrents
        let hash = torrentEntity?.torrentHashString ?? ""
        guard !hash.isEmpty else { return }

        let source = torrentEntity?.torrentDownloadURL ?? ""
        var state: [String: Any] = [
            "backend":       "webtorrent",
            "torrentHash":   hash,
            "magnetLink":    source,
            "torrentLink":   source,
            "torrentName":   torrentEntity?.torrentName ?? player.videoEntity?.videoName ?? hash,
            "fileIndex":     player.fileIndex,
            "videoPath":     path,
            "anilistID":     player.anilistID,
            "episodeNumber": player.episodeNumber,
            "totalEpisodes": player.totalEpisodes
        ]
        // `last-torrent` is `{ media, id, episode }`: the whole media is kept, since its id is what the backend keeps
        // the library entry by and what the player shows of it comes from it
        let media = player.videoService?.media
            ?? Router.shared.cachedAnimeItem(for: player.anilistID)
            ?? torrentEntity?.animes.map { AniListUtil.animeItem(from: $0) }
        if let media, let data = try? JSONEncoder().encode(media) { state["media"] = data }
        if let object = media?.extensionMediaJSON, JSONSerialization.isValidJSONObject(object),
           let data = try? JSONSerialization.data(withJSONObject: object) {
            state["mediaJSON"] = data
        }
        UserDefaults.standard.set(state, forKey: Self.sessionStateKey)
    }

    /// Clears the persisted session state (called on explicit close).
    private func clearSessionState() {
        UserDefaults.standard.removeObject(forKey: Self.sessionStateKey)
    }

    /// Clears the persisted session state if the given player was the one
    /// that saved it. Called from VideoPlayerViewController.tearDownPlayer()
    /// so that a normal dismiss (without minimizing) also clears stale state.
    func clearSessionStateIfNeeded(for player: VideoPlayerViewController) {
        let hash = player.videoEntity?.torrents?.torrentHashString ?? ""
        guard !hash.isEmpty,
              let state = UserDefaults.standard.dictionary(forKey: Self.sessionStateKey),
              let savedHash = state["torrentHash"] as? String,
              savedHash == hash else { return }
        clearSessionState()
    }

    /// `playHash`: `this.last.set({ id: infoHash, media, episode })`. The torrent that is played is the one that comes
    /// back at launch, whether the player was ever minimized or not.
    func saveSession(of player: VideoPlayerViewController) {
        saveSessionState(player)
    }

    /// Re-saves the session state if a mini-player is currently active.
    /// Called from AppDelegate.applicationDidEnterBackground so the latest
    /// playback position is persisted before the system may kill the app.
    func resaveSessionStateIfActive() {
        guard let player = activePlayer else { return }
        saveSessionState(player)
    }

    // MARK: - Session Restore (Hayase: server.active auto-mount on launch)

    /// Attempts to restore the mini-player from a previously saved session.
    ///
    /// Flow mirrors Hayase's wrapper.svelte: if `server.active` has a value
    /// when the app mounts, the player component renders in mini-player mode
    /// immediately. Here, we check UserDefaults for saved session state, load
    /// the torrent again, create a VideoPlayerViewController with the same
    /// properties, and show it as a mini-player.
    func restoreSessionIfNeeded() {
        // Don't restore if a mini-player is already active.
        guard !isActive else { return }

        guard let state = UserDefaults.standard.dictionary(forKey: Self.sessionStateKey),
              let hash = state["torrentHash"] as? String,
              let fileIndexValue = state["fileIndex"],
              !hash.isEmpty else {
            return
        }

        let fileIndex: UInt
        if let intValue = fileIndexValue as? Int, intValue >= 0 {
            fileIndex = UInt(intValue)
        } else if let uintValue = fileIndexValue as? UInt {
            fileIndex = uintValue
        } else {
            fileIndex = 0
        }

        let anilistID = state["anilistID"] as? Int ?? 0
        let episodeNumber = state["episodeNumber"] as? Int ?? 0
        let totalEpisodes = state["totalEpisodes"] as? Int ?? 0

        // A session saved by the removed native backend has a file path, not a bridge URL.
        let backend = state["backend"] as? String
        let savedPath = state["videoPath"] as? String ?? ""
        guard backend == "webtorrent" || Self.isHTTPStreamPath(savedPath) else {
            clearSessionState()
            return
        }

        restoreWebTorrentSession(state: state,
                                 hash: hash,
                                 fileIndex: fileIndex,
                                 anilistID: anilistID,
                                 episodeNumber: episodeNumber,
                                 totalEpisodes: totalEpisodes)
    }

    private func restoreWebTorrentSession(state: [String: Any],
                                          hash: String,
                                          fileIndex: UInt,
                                          anilistID: Int,
                                          episodeNumber: Int,
                                          totalEpisodes: Int) {
        cancelPendingWebTorrentRestore()

        let context = CoreDataService.sharedCoreDataService.mainQueueContext
        let torrentEntity: Torrents
        let request = NSFetchRequest<Torrents>(entityName: Torrents.entityName)
        request.predicate = NSPredicate(format: "torrentHashString == %@", hash)
        request.fetchLimit = 1

        if let existing = (try? context.fetch(request))?.first {
            torrentEntity = existing
        } else if let created = NSEntityDescription.insertNewObject(forEntityName: Torrents.entityName,
                                                                     into: context) as? Torrents {
            torrentEntity = created
            torrentEntity.torrentHashString = hash
        } else {
            clearSessionState()
            return
        }

        let restoredSource = (state["torrentLink"] as? String)
            ?? (state["magnetLink"] as? String)
            ?? (state["source"] as? String)
            ?? ""
        torrentEntity.torrentName = (state["torrentName"] as? String) ?? torrentEntity.torrentName ?? hash
        if torrentEntity.torrentDownloadURL?.isEmpty ?? true {
            torrentEntity.torrentDownloadURL = restoredSource
        }
        // The session starts empty at launch, so the media is made again: without it the backend is told that
        // the torrent has no media (its library entry loses it) and the player names the episode by its file.
        var savedItem = (state["media"] as? Data).flatMap { try? JSONDecoder().decode(AnimeItem.self, from: $0) }
        if savedItem != nil, let data = state["mediaJSON"] as? Data {
            savedItem?.extensionMediaJSON = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        }
        VideoService.linkAnime(mediaID: anilistID, to: torrentEntity, item: savedItem) { [weak self] in
            guard let self, let player = self.activePlayer else { return }
            player.refreshMediaTitle()
            if let container = self.containerView { self.addOverlay(to: container) }
        }
        try? context.save()

        let videoService = VideoService(torrentEntity: torrentEntity, episode: episodeNumber)
        videoService.media = savedItem
        pendingWebTorrentRestoreService = videoService

        pendingWebTorrentRestoreObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name(VideoService.LocalVideosDidUpdateNotification),
            object: nil,
            queue: .main
        ) { [weak self, weak videoService] _ in
            guard let self, let videoService else { return }
            self.finishWebTorrentSessionRestore(videoService: videoService,
                                                torrentEntity: torrentEntity,
                                                hash: hash,
                                                fileIndex: fileIndex,
                                                anilistID: anilistID,
                                                episodeNumber: episodeNumber,
                                                totalEpisodes: totalEpisodes)
        }

        let timeout = DispatchWorkItem { [weak self] in
            guard let self else { return }
            print("MiniPlayerManager: WebTorrent restore timed out for \(hash)")
            self.cancelPendingWebTorrentRestore()
            self.clearSessionState()
        }
        pendingWebTorrentRestoreTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + webTorrentRestoreTimeout, execute: timeout)

        videoService.UpdateLocalVideo()
    }

    private func finishWebTorrentSessionRestore(videoService: VideoService,
                                                torrentEntity: Torrents,
                                                hash: String,
                                                fileIndex: UInt,
                                                anilistID: Int,
                                                episodeNumber: Int,
                                                totalEpisodes: Int) {
        let context = CoreDataService.sharedCoreDataService.mainQueueContext
        let fetch = NSFetchRequest<Videos>(entityName: Videos.entityName)
        fetch.predicate = NSPredicate(format: "torrents == %@", torrentEntity)
        fetch.sortDescriptors = [NSSortDescriptor(key: "videoIndex", ascending: true),
                                 NSSortDescriptor(key: "videoName", ascending: true)]
        let videos = (try? context.fetch(fetch)) ?? []

        if videos.isEmpty && videoService.lastError == nil {
            return
        }

        cancelPendingWebTorrentRestore(clearService: false)

        guard videoService.lastError == nil, !videos.isEmpty else {
            print("MiniPlayerManager: WebTorrent restore failed: \(videoService.lastError?.localizedDescription ?? "no playable files")")
            pendingWebTorrentRestoreService = nil
            clearSessionState()
            return
        }

        guard let selectedVideo = videos.first(where: { ($0.videoIndex?.uintValue ?? UInt.max) == fileIndex }) ?? videos.first else {
            pendingWebTorrentRestoreService = nil
            clearSessionState()
            return
        }
        let selectedIndex = selectedVideo.videoIndex?.uintValue ?? fileIndex
        let resolvedPath = videoService.UpdateFilePathForFileIndex(selectedIndex)
        if !resolvedPath.isEmpty, selectedVideo.videoPath != resolvedPath {
            selectedVideo.videoPath = resolvedPath
            try? context.save()
        }

        let player = VideoPlayerViewController()
        player.videoEntity = selectedVideo
        player.videoService = videoService
        player.fileIndex = selectedIndex
        player.anilistID = anilistID
        player.episodeNumber = episodeNumber
        player.totalEpisodes = totalEpisodes
        player.allVideos = videos
        player.currentVideoIndex = videos.firstIndex(of: selectedVideo) ?? 0
        player.onEpisodeChange = { [weak self] episode, media in
            self?.handleRestoredEpisodeChange(episode: episode, anilistID: media?.id ?? anilistID)
        }
        player.shouldStartPaused = true
        _ = player.view

        showAsMiniPlayer(player)
        pendingWebTorrentRestoreService = nil
    }

    private func cancelPendingWebTorrentRestore(clearService: Bool = true) {
        if let observer = pendingWebTorrentRestoreObserver {
            NotificationCenter.default.removeObserver(observer)
            pendingWebTorrentRestoreObserver = nil
        }
        pendingWebTorrentRestoreTimeout?.cancel()
        pendingWebTorrentRestoreTimeout = nil
        if clearService {
            pendingWebTorrentRestoreService = nil
        }
    }

    /// Shows a player directly as a mini-player (no dismiss animation).
    /// Used for session restore on app launch where the player was never
    /// presented fullscreen.
    private func showAsMiniPlayer(_ player: VideoPlayerViewController) {
        if let existing = activePlayer, existing !== player {
            close()
        }
        guard let host = miniPlayerHost() else { return }
        activePlayer = player
        player.isMinimizing = true

        hostView = host

        let container = makeContainer()
        host.addSubview(container)
        containerView = container

        // Reparent locally, or just move the external-output placeholder while
        // the external display keeps ownership of the actual MPV surface.
        guard let inner = container.viewWithTag(innerContainerTag) else { return }
        hostPlayerSurfaceInMiniContainer(player, inner: inner)

        addOverlay(to: container)

        player.onCastStateChanged = { [weak self] in
            guard let self, let container = self.containerView else { return }
            self.addOverlay(to: container)
        }
        player.onCastTick = { [weak self] elapsed, duration in
            self?.updateMiniCastProgress(elapsed: elapsed, duration: duration)
        }

        // Start tucked to the right edge (Hayase: mini-player appears
        // at the edge on launch, user taps to reveal).
        isPressed = false
        isRevealedForInteraction = false
        isTucked = true
        isSnappedToRight = true
        isSnappedToTop = false
        repositionContainer()
        container.alpha = 1
        player.resumeStatsUpdates()
        saveSessionState(player)
    }

    // MARK: - Restored Episode Change

    /// Handles an episode change request from a session-restored player whose
    /// `onEpisodeChange` was wired up during `restoreSessionIfNeeded()`.
    /// Mirrors `ExtensionSearchViewController.handleEpisodeChangeFromPlayer()`:
    /// closes the mini-player, fetches the anime metadata, then navigates to a
    /// new `ExtensionSearchViewController` with auto-select enabled.
    private func handleRestoredEpisodeChange(episode: Int, anilistID: Int) {
        guard anilistID > 0 else { return }

        // Close the current mini-player (tears down player + torrent stream).
        close()

        // Fetch the AnimeItem so the search VC has full metadata for queries.
        AniListClient.shared.singleMediaResult(id: anilistID) { [weak self] result in
            switch result {
            case .success(let items):
                guard let animeItem = items.first else { return }
                DispatchQueue.main.async {
                    self?.presentSearchVC(animeItem: animeItem, episode: episode)
                }
            case .failure(let error):
                NSLog("[MiniPlayer] AniList lookup failed: %@", error.description)
            }
        }
    }

    /// Finds the topmost navigation controller and pushes an
    /// `ExtensionSearchViewController` configured to auto-select the best
    /// result — the same seamless transition that `handleEpisodeChangeFromPlayer`
    /// provides in the normal (non-restore) flow.
    private func presentSearchVC(animeItem: AnimeItem, episode: Int) {
        guard let appDelegate = UIApplication.shared.delegate as? AppDelegate,
              let window = appDelegate.window else { return }

        let searchVC = ExtensionSearchViewController()
        searchVC.animeItem = animeItem
        searchVC.initialEpisode = episode
        searchVC.shouldAutoSelectOnSearch = true

        if let presenter = topViewController() {
            searchVC.prepareOverlayPresentation(from: presenter)
            presenter.present(searchVC, animated: true)
            return
        }

        searchVC.prepareOverlayPresentation(from: window.rootViewController)
        window.rootViewController?.present(searchVC, animated: true)
    }
}

// MARK: - The player's side of wrapper.svelte (fullscreen, and the surface that the mini-player takes)

extension VideoPlayerViewController {
    func enterFullscreenForPlayerRouteIfNeeded() {
        guard UIDevice.current.userInterfaceIdiom == .phone,
              Router.shared.currentRoute == .player,
              !isMinimizing else { return }
        enterFullscreenPresentation()
    }

    func toggleFullscreenPresentation() {
        if isFullscreenPresentation {
            exitFullscreenPresentation()
        } else {
            enterFullscreenPresentation()
        }
    }

    func enterFullscreenPresentation() {
        guard !isFullscreenPresentation else { return }
        isFullscreenPresentation = true
        hayaseSidebarController?.setPlayerFullscreenActive(true)
        setNeedsStatusBarAppearanceUpdate()
        setNeedsUpdateOfHomeIndicatorAutoHidden()
    }

    func exitFullscreenPresentation() {
        guard isFullscreenPresentation else { return }
        isFullscreenPresentation = false
        hayaseSidebarController?.setPlayerFullscreenActive(false)
        setNeedsStatusBarAppearanceUpdate()
        setNeedsUpdateOfHomeIndicatorAutoHidden()
    }

    var isFullscreenForRouteNavigation: Bool {
        isFullscreenPresentation
    }

    func exitFullscreenForRouteNavigationIfNeeded() {
        if isFullscreenPresentation {
            exitFullscreenPresentation()
        }
    }

    /// Returns the MPV surface view so MiniPlayerManager can reparent it.
    var surfaceView: MPVSurfaceView { surface }

    /// Toggles play/pause from the mini-player.
    func togglePlayPause() {
        playPauseTapped()
    }
}
