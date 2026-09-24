// Mirrors: src/lib/components/ui/player/wrapper.svelte, src/lib/components/ui/player/player.svelte, src/routes/+layout.svelte, src/app.css

/// Hayase wrapper.svelte — in-app mini-player manager.
///
/// In Hayase, the player component (wrapper.svelte) is always mounted in the
/// layout. When the user navigates away from `/app/player`, it switches to
/// mini-player mode: a 22rem-wide floating window at the bottom-right corner,
/// draggable, with click-to-restore. The torrent session stays alive.
///
/// This iOS port uses a dedicated UIWindow (PassthroughWindow) to host the
/// mini-player. The window sits at a higher window level than normal content,
/// guaranteeing the mini-player is always visible — even after the fullscreen
/// player is dismissed and the presenting view controller's view is shown.
/// Touches outside the mini-player container pass through to the main window.
import UIKit
import LibTorrent
import CoreData

// MARK: - PassthroughWindow

/// A UIWindow that passes touches through to the window behind it unless the
/// touch lands on a visible subview (the mini-player container). This lets the
/// mini-player float above all content without blocking interaction with the
/// rest of the app.
private final class PassthroughWindow: UIWindow {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        // If the hit is the window itself or the root VC's transparent view,
        // return nil so the touch falls through to the window below.
        if hit === self || hit === rootViewController?.view {
            return nil
        }
        return hit
    }
}

/// Root VC for the PassthroughWindow. Transparent, supports all orientations,
/// and repositions the mini-player container on layout changes (rotation).
private final class PassthroughRootViewController: UIViewController {
    override var shouldAutorotate: Bool { true }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .all }
    override var prefersStatusBarHidden: Bool { true }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        MiniPlayerManager.shared.repositionContainer()
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
    /// Corner radius matching Hayase's `[&>*]:rounded-lg`.
    private let cornerRadius: CGFloat = 12
    /// Snap animation (Hayase: `transition-transform duration-[500ms]
    /// ease-[cubic-bezier(0.3,1.5,0.8,1)]`).
    private let snapDuration: TimeInterval = 0.5
    /// How much of the mini-player is visible when tucked to the edge
    /// (Hayase: `.paused { --padding-right: calc(100% - 3rem) }` → 3rem ≈ 48pt).
    private let peekWidth: CGFloat = 48
    /// Seconds of inactivity before the mini-player auto-tucks to the edge.
    private let autoHideDelay: TimeInterval = 3.0
    /// Maximum number of retry attempts when restoring the mini-player session
    /// and the torrent metadata hasn't been parsed yet by libtorrent.
    /// Set high enough to cover re-added magnets that need DHT peer discovery
    /// (web interface also waits for native.playTorrent() to resolve).
    private let maxRestoreRetries = 30
    /// Delay between restore retries (seconds).
    private let restoreRetryDelay: TimeInterval = 1.0
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

    /// Dedicated window for the mini-player, above normal content.
    private var miniWindow: PassthroughWindow?

    /// The floating container inside the mini-player window.
    private var containerView: UIView?

    /// The play/pause button in the mini-player overlay.
    private var playPauseButton: UIButton?

    /// Active modal striped-backdrop count. The mini-player normally floats above
    /// app content in its own window, so app-level Dialog overlays do not cover it.
    /// Keep this ref-counted so overlapping dialogs cannot leave the stripe stuck on.
    private var externalStripeOverlayCount = 0

    /// Non-interactive visual overlay applied only while a striped app dialog is active.
    private var externalStripeOverlayView: HayaseStripedBackdropView?

    /// True when the mini-player is currently visible.
    var isActive: Bool { miniWindow != nil && activePlayer != nil }

    // MARK: - Dragging state (Hayase pointer events)

    /// Whether the user is currently dragging the mini-player.
    private var isDragging = false
    private var isRestoring = false

    // MARK: - Tuck/peek state (Hayase .paused / idle behavior)

    /// Whether the mini-player is currently tucked to the edge (mostly hidden).
    private var isTucked = false
    /// Timer that auto-tucks the mini-player after inactivity.
    private var autoHideTimer: Timer?
    /// The fully-revealed frame saved on snap / reposition.
    private var revealedFrame: CGRect = .zero
    /// Whether the container last snapped to the right side (`true`) or left (`false`).
    private var isSnappedToRight = true

    // MARK: - Session State Persistence (Hayase server.active store)

    /// UserDefaults key for persisting the active mini-player session.
    /// Mirrors Hayase's `server.active` store: when the app relaunches, if this
    /// key has data the mini-player is restored automatically (just like Hayase
    /// re-mounts the player component on reload when a torrent session exists).
    private static let sessionStateKey = "nyais_miniPlayerSessionState"

    // MARK: - Init

    private init() {
        // Observe torrent-will-be-removed notifications so we can tear down any
        // active mini-player whose torrent is about to be freed. Without this,
        // TorrentStreamer.stop() / LocalStreamServer / statsTimer would access
        // the deallocated TorrentHandle and crash (use-after-free / segfault).
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleTorrentWillBeRemoved(_:)),
            name: NSNotification.Name(TorrentService.TorrentWillBeRemovedNotification),
            object: nil)
    }

    /// Called when a torrent is about to be removed from the session.
    /// If the mini-player is streaming that torrent, close it immediately
    /// so that `tearDownPlayer()` runs BEFORE the handle is freed.
    @objc private func handleTorrentWillBeRemoved(_ notification: Notification) {
        guard let removedHash = notification.userInfo?["torrentHash"] as? String,
              let player = activePlayer,
              let playerHash = player.torrentHandle?.infoHashes.best.hex,
              playerHash == removedHash else { return }
        // The mini-player's torrent is being deleted — close immediately.
        close()
    }

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
        activePlayer = player

        // Prefer the player's current scene; route-driven modal exits fall back to the connected foreground scene below.
        let playerScene = player.view.window?.windowScene

        // Create a dedicated window for the mini-player so it floats above
        // all content regardless of which view controller is presented.
        let window = makePassthroughWindow(preferredScene: playerScene)
        miniWindow = window

        // Create the mini-player container (shadow + rounded corners).
        let container = makeContainer()
        window.rootViewController?.view.addSubview(container)
        containerView = container

        // Reparent the MPV surface into the mini-player container.
        let surface = player.surfaceView
        surface.translatesAutoresizingMaskIntoConstraints = true
        guard let inner = container.viewWithTag(innerContainerTag) else { return }
        surface.frame = inner.bounds
        surface.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        inner.insertSubview(surface, at: 0)

        // Add mini-player controls overlay.
        addOverlay(to: container)
        updateExternalStripeOverlay(animated: false)

        player.onCastStateChanged = { [weak self] in
            guard let self, let container = self.containerView else { return }
            self.addOverlay(to: container)
        }
        player.onCastTick = { [weak self] elapsed, duration in
            self?.updateMiniCastProgress(elapsed: elapsed, duration: duration)
        }

        // Root view transitions fade wrapper.svelte with the destination; do the same for the separate native mini window.
        isTucked = false
        isSnappedToRight = true
        repositionContainer()
        container.alpha = fadeIn ? 0 : 1
        if fadeIn {
            UIViewPropertyAnimator(duration: 0.25,
                                   controlPoint1: CGPoint(x: 0.25, y: 0.1),
                                   controlPoint2: CGPoint(x: 0.25, y: 1)) {
                container.alpha = 1
            }.startAnimation()
        }

        // Start auto-hide timer so the mini-player tucks after a few seconds.
        resetAutoHideTimer()

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

        // Persist session state so the mini-player can be restored on relaunch
        // (Hayase: server.active persists via the store, libtorrent fastResume
        // restores the torrent on restart).
        saveSessionState(player)
    }

    /// Restores the fullscreen player from the mini-player.
    /// Equivalent to Hayase's `goto('/app/player/')` on mini-player click.
    func restore() {
        guard !isRestoring,
              let player = activePlayer,
              let container = containerView else { return }

        cancelAutoHideTimer()
        isTucked = false

        // Find a presenting VC.
        guard let presenter = topViewController(), presenter !== player else { return }
        isRestoring = true

        player.onCastStateChanged = nil
        player.onCastTick = nil
        miniCastTimeLabel = nil
        miniCastProgressFill = nil
        miniCastProgressFillWidth = nil
        miniCastProgressContainer = nil

        // Reparent the surface back into the player VC's view.
        let surface = player.surfaceView
        surface.translatesAutoresizingMaskIntoConstraints = false
        player.view.insertSubview(surface, at: 0)
        NSLayoutConstraint.activate([
            surface.topAnchor.constraint(equalTo: player.view.topAnchor),
            surface.bottomAnchor.constraint(equalTo: player.view.bottomAnchor),
            surface.leadingAnchor.constraint(equalTo: player.view.leadingAnchor),
            surface.trailingAnchor.constraint(equalTo: player.view.trailingAnchor),
        ])

        // Tear down the mini-player window.
        externalStripeOverlayView?.removeFromSuperview()
        externalStripeOverlayView = nil
        container.removeFromSuperview()
        containerView = nil
        miniWindow?.isHidden = true
        miniWindow = nil

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

        cancelAutoHideTimer()
        cancelPendingWebTorrentRestore()
        isRestoring = false
        isTucked = false
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
                self?.externalStripeOverlayView?.removeFromSuperview()
                self?.externalStripeOverlayView = nil
                container.removeFromSuperview()
                self?.containerView = nil
                self?.miniWindow?.isHidden = true
                self?.miniWindow = nil
            })
        }

        player.tearDownPlayer()
        activePlayer = nil
    }

    // MARK: - External striped backdrop

    /// Called by app-level dialog presentation controllers when their
    /// `custom-bg backdrop-blur-sm` overlay is active. The mini-player lives in
    /// a higher window, so it needs a matching local overlay instead of relying
    /// on the presenting window's backdrop.
    func beginExternalStripeOverlay() {
        externalStripeOverlayCount += 1
        updateExternalStripeOverlay(animated: true)
    }

    /// Balances `beginExternalStripeOverlay()`. Never lets the counter go
    /// negative, which prevents a stale always-striped mini-player state.
    func endExternalStripeOverlay() {
        externalStripeOverlayCount = max(0, externalStripeOverlayCount - 1)
        updateExternalStripeOverlay(animated: true)
    }

    private func updateExternalStripeOverlay(animated: Bool) {
        guard let inner = containerView?.viewWithTag(innerContainerTag) else {
            externalStripeOverlayView = nil
            return
        }

        let shouldShow = externalStripeOverlayCount > 0
        if shouldShow {
            let overlay = externalStripeOverlayView ?? HayaseStripedBackdropView()
            externalStripeOverlayView = overlay
            overlay.frame = inner.bounds
            overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            overlay.isUserInteractionEnabled = false
            if overlay.superview !== inner {
                overlay.alpha = 0
                inner.addSubview(overlay)
            } else {
                inner.bringSubviewToFront(overlay)
            }
            animateStripeOverlay(overlay, alpha: 1, animated: animated)
        } else if let overlay = externalStripeOverlayView {
            animateStripeOverlay(overlay, alpha: 0, animated: animated) { [weak self, weak overlay] in
                overlay?.removeFromSuperview()
                if self?.externalStripeOverlayView === overlay {
                    self?.externalStripeOverlayView = nil
                }
            }
        }
    }

    private func animateStripeOverlay(_ overlay: UIView,
                                      alpha: CGFloat,
                                      animated: Bool,
                                      completion: (() -> Void)? = nil) {
        let changes = { overlay.alpha = alpha }
        guard animated else {
            changes()
            completion?()
            return
        }
        UIView.animate(withDuration: 0.15,
                       delay: 0,
                       options: [.curveEaseOut, .beginFromCurrentState],
                       animations: changes) { _ in
            completion?()
        }
    }

    // MARK: - Layout

    /// Repositions the mini-player container to the bottom-right corner,
    /// accounting for current screen bounds and safe area insets. Called:
    /// - Immediately in minimize() so the container is positioned correctly
    /// - In the dismiss completion to adjust for safe area changes
    /// - From the root VC's viewDidLayoutSubviews for rotation handling
    func repositionContainer() {
        guard let container = containerView,
              let window = miniWindow,
              !isDragging else { return }
        let bounds = window.bounds
        let size = miniSize(in: window)
        let safeBottom = window.safeAreaInsets.bottom
        let frame = CGRect(
            x: bounds.width - size.width - edgePadding,
            y: bounds.height - size.height - safeBottom - edgePadding,
            width: size.width, height: size.height)
        revealedFrame = frame
        isSnappedToRight = true
        container.bounds.size = size
        if let inner = container.viewWithTag(innerContainerTag) {
            inner.frame = CGRect(origin: .zero, size: size)
        }
        if isTucked {
            var tuckedFrame = frame
            tuckedFrame.origin.x = bounds.width - peekWidth
            container.frame = tuckedFrame
        } else {
            container.frame = frame
        }
    }

    // MARK: - Window + Container creation

    private func miniSize(in window: UIWindow) -> CGSize {
        let visibleWidth = max(peekWidth, min(maxOuterWidth, window.bounds.width) - (edgePadding * 2))
        return CGSize(width: visibleWidth, height: visibleWidth * 9 / 16)
    }

    /// Creates the dedicated passthrough window for the mini-player.
    /// - Parameter preferredScene: The window scene to use. Pass the
    ///   player's `view.window?.windowScene` captured before dismiss.
    private func makePassthroughWindow(preferredScene: UIWindowScene? = nil) -> PassthroughWindow {
        let window = PassthroughWindow(frame: UIScreen.main.bounds)
        // Attach to a window scene (required on iOS 13+). Without a scene,
        // the window is silently invisible. Use the preferred scene first
        // (captured from the player's window), then fall back to any
        // connected scene — don't filter by foregroundActive only, since
        // the scene may briefly be in a different state during transitions.
        let scene = preferredScene
            ?? UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive })
            ?? UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first
        if let scene = scene {
            window.windowScene = scene
        }
        // Above normal windows but below alerts/keyboards.
        window.windowLevel = .normal + 1
        window.backgroundColor = .clear
        window.isUserInteractionEnabled = true
        let rootVC = PassthroughRootViewController()
        rootVC.view.backgroundColor = .clear
        window.rootViewController = rootVC
        window.isHidden = false
        return window
    }

    /// Builds the floating mini-player container view (Hayase wrapper.svelte
    /// mini-player div with rounded corners and shadow).
    private func makeContainer() -> UIView {
        let fallbackWidth = maxOuterWidth - (edgePadding * 2)
        let v = UIView(frame: CGRect(x: 0, y: 0, width: fallbackWidth, height: fallbackWidth * 9 / 16))
        // Don't clip the outer view — it needs to show the shadow.
        v.clipsToBounds = false
        v.layer.shadowColor = UIColor.black.cgColor
        v.layer.shadowOpacity = 0.5
        v.layer.shadowRadius = 8
        v.layer.shadowOffset = CGSize(width: 0, height: 4)
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
        v.addGestureRecognizer(pan)
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tap.require(toFail: pan)
        v.addGestureRecognizer(tap)

        return v
    }

    /// Adds the controls overlay to the mini-player: play/pause normally, or
    /// (Mirrors: hayase-app/interface/src/lib/components/ui/player/castplayer.svelte,
    /// `isMiniplayer` branch) the Now Casting display while actively casting.
    /// Re-callable: removes any existing overlay first so cast state changes
    /// while already minimized can rebuild it in place.
    func refreshLoadingState(for player: VideoPlayerViewController) {
        guard activePlayer === player, let containerView else { return }
        addOverlay(to: containerView)
    }

    private func addOverlay(to container: UIView) {
        guard let inner = container.viewWithTag(innerContainerTag) else { return }
        inner.viewWithTag(overlayTag)?.removeFromSuperview()
        guard activePlayer?.isLoadingMetadata != true else { return }

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

        if activePlayer?.isCasting == true {
            overlay.backgroundColor = UIColor.HayaseTheme.background   // bg-background (opaque, unlike the 0.3-alpha play/pause overlay)
            buildCastOverlay(in: overlay)
        } else {
            overlay.backgroundColor = UIColor.black.withAlphaComponent(0.3)
            buildPlayPauseOverlay(in: overlay)
        }
    }

    private func buildPlayPauseOverlay(in overlay: UIView) {
        let ppBtn = UIButton(type: .system)
        ppBtn.translatesAutoresizingMaskIntoConstraints = false
        let icon = activePlayer?.isPaused == true ? "play" : "pause"
        ppBtn.setImage(UIImage.hayaseFilledIcon(icon), for: .normal)
        ppBtn.tintColor = .white
        ppBtn.addTarget(self, action: #selector(playPauseTapped), for: .touchUpInside)
        overlay.addSubview(ppBtn)
        playPauseButton = ppBtn
        NSLayoutConstraint.activate([
            ppBtn.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
            ppBtn.centerYAnchor.constraint(equalTo: overlay.centerYAnchor),
            ppBtn.widthAnchor.constraint(equalToConstant: 36),
            ppBtn.heightAnchor.constraint(equalToConstant: 36),
        ])
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
        let s = max(0, Int(seconds))
        let h = s / 3600; let m = (s % 3600) / 60; let sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec)
                     : String(format: "%d:%02d", m, sec)
    }

    // MARK: - Gesture handlers (Hayase wrapper.svelte pointer events)

    /// Pan gesture — dragging the mini-player. On release, snaps to the
    /// nearest corner (Hayase's endDragging logic).
    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let container = containerView,
              let rootView = miniWindow?.rootViewController?.view else { return }
        let translation = gesture.translation(in: rootView)

        switch gesture.state {
        case .began:
            isDragging = true
            cancelAutoHideTimer()
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

    /// Tap gesture — if tucked, reveal first; otherwise restore fullscreen
    /// (Hayase: clicking mini-player calls `goto('/app/player/')`).
    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        if isTucked {
            reveal()
            return
        }
        Router.shared.navigate(.player)
    }

    @objc private func playPauseTapped() {
        activePlayer?.togglePlayPause()
        // Routes through the same function the player's didChangePause
        // delegate uses, so this gets identical timer/tuck handling instead
        // of a second, separately-drifting copy of the same logic.
        updatePlayPauseIcon(isPaused: activePlayer?.isPaused == true)
    }

    // MARK: - Corner snapping (Hayase endDragging)

    /// Hayase's endDragging: determines which half (top/bottom, left/right)
    /// the center is in, then snaps to the corresponding corner.
    private func snapToNearestCorner() {
        guard let container = containerView,
              let window = miniWindow else { return }
        let center = container.center
        let safeInsets = window.safeAreaInsets

        let isTop = center.y < window.bounds.height / 2
        let isLeft = center.x < window.bounds.width / 2

        let targetX: CGFloat
        let targetY: CGFloat

        let size = miniSize(in: window)

        if isLeft {
            targetX = edgePadding
        } else {
            targetX = window.bounds.width - size.width - edgePadding
        }

        if isTop {
            targetY = edgePadding + safeInsets.top
        } else {
            targetY = window.bounds.height - size.height - safeInsets.bottom - edgePadding
        }

        isSnappedToRight = !isLeft
        let targetFrame = CGRect(
            x: targetX, y: targetY,
            width: size.width, height: size.height)
        revealedFrame = targetFrame

        // Hayase: `transition-transform duration-[500ms]
        // ease-[cubic-bezier(0.3,1.5,0.8,1)]` — a springy overshoot.
        UIView.animate(
            withDuration: snapDuration,
            delay: 0,
            usingSpringWithDamping: 0.6,
            initialSpringVelocity: 0.8,
            options: .curveEaseOut
        ) {
            container.frame = targetFrame
        } completion: { [weak self] _ in
            self?.resetAutoHideTimer()
        }
    }

    // MARK: - Tuck / Reveal (Hayase .paused idle behavior)

    /// Tucks the mini-player to the nearest horizontal edge, leaving only
    /// `peekWidth` visible. Matches Hayase's `.paused` CSS class:
    /// `--padding-right: calc(100% - 3rem)`.
    private func tuck() {
        guard let container = containerView,
              let window = miniWindow,
              !isDragging else { return }
        isTucked = true

        var tuckedFrame = revealedFrame
        if isSnappedToRight {
            tuckedFrame.origin.x = window.bounds.width - peekWidth
        } else {
            tuckedFrame.origin.x = -(revealedFrame.width - peekWidth)
        }

        UIView.animate(
            withDuration: snapDuration,
            delay: 0,
            usingSpringWithDamping: 0.8,
            initialSpringVelocity: 0.5,
            options: .curveEaseOut
        ) {
            container.frame = tuckedFrame
        }
    }

    /// Reveals the full mini-player from its tucked state. Starts the
    /// auto-hide timer so it will tuck again after `autoHideDelay`.
    private func reveal() {
        guard isTucked, let container = containerView else {
            resetAutoHideTimer()
            return
        }
        isTucked = false

        UIView.animate(
            withDuration: snapDuration,
            delay: 0,
            usingSpringWithDamping: 0.6,
            initialSpringVelocity: 0.8,
            options: .curveEaseOut
        ) {
            container.frame = self.revealedFrame
        }

        resetAutoHideTimer()
    }

    /// (Re)starts the auto-hide timer. After `autoHideDelay` seconds the
    /// mini-player tucks to the edge.
    ///
    /// Refuses to arm while the video is actually playing, regardless of
    /// which caller asked — several call sites (button taps, drag-end snap
    /// completions) used to call this unconditionally, so checking here
    /// once covers all of them instead of requiring every call site to
    /// remember to check first. `tuck()`'s own doc comment already called
    /// this ".paused / idle behavior"; this just makes that actually true.
    private func resetAutoHideTimer() {
        autoHideTimer?.invalidate()
        autoHideTimer = nil
        guard activePlayer?.isPaused == true else { return }
        autoHideTimer = Timer.scheduledTimer(
            withTimeInterval: autoHideDelay, repeats: false
        ) { [weak self] _ in
            self?.tuck()
        }
    }

    /// Cancels the auto-hide timer (e.g. on restore / close).
    private func cancelAutoHideTimer() {
        autoHideTimer?.invalidate()
        autoHideTimer = nil
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

    /// Updates the play/pause icon in the mini-player. Called from the
    /// player's didChangePause delegate.
    ///
    /// Also governs the auto-hide/tuck timer here, since this is the only
    /// place play/pause state actually reaches this class. Previously the
    /// timer was armed unconditionally whenever the mini-player was shown
    /// (see the "Start auto-hide timer" call right after minimizing) with
    /// no regard for play state at all — so it would tuck itself away
    /// during active playback despite the tuck() code being explicitly
    /// commented as ".paused / idle behavior". Matches interface, which
    /// doesn't hide/shrink its mini-player while a video is playing.
    func updatePlayPauseIcon(isPaused: Bool) {
        let icon = isPaused ? "play" : "pause"
        playPauseButton?.setImage(UIImage.hayaseFilledIcon(icon), for: .normal)

        if isPaused {
            resetAutoHideTimer()
        } else {
            if isTucked { reveal() }
            cancelAutoHideTimer()
        }
    }

    // MARK: - Session State Persistence

    private static func isHTTPStreamPath(_ path: String) -> Bool {
        let lower = path.lowercased()
        return lower.hasPrefix("http://") || lower.hasPrefix("https://")
    }

    /// Saves the minimum data required to restore the mini-player on relaunch.
    /// Mirrors Hayase's `server.active` store — the torrent session is
    /// automatically restored by libtorrent's fastResume; we just need enough
    /// metadata to reconnect to the right handle and file.
    private func saveSessionState(_ player: VideoPlayerViewController) {
        guard let path = player.videoEntity?.videoPath else { return }

        let torrentEntity = player.videoEntity?.torrents
        let isWebTorrent = player.torrentHandle == nil && Self.isHTTPStreamPath(path)
        let hash = player.torrentHandle?.infoHashes.best.hex
            ?? torrentEntity?.torrentHashString
            ?? ""
        guard !hash.isEmpty else { return }

        let source = torrentEntity?.torrentDownloadURL ?? ""
        let state: [String: Any] = [
            "backend":       isWebTorrent ? "webtorrent" : "native",
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
        UserDefaults.standard.set(state, forKey: Self.sessionStateKey)

        // Flush CoreData to disk so the Videos/Torrents entities survive a
        // force-quit. mainQueueContext.save() only pushes to the in-memory
        // rootContext; without this, a killed app loses all CoreData rows.
        let ctx = CoreDataService.sharedCoreDataService.mainQueueContext
        try? ctx.save()
        CoreDataService.sharedCoreDataService.saveRootContext {}
    }

    /// Clears the persisted session state (called on explicit close).
    private func clearSessionState() {
        UserDefaults.standard.removeObject(forKey: Self.sessionStateKey)
    }

    /// Clears the persisted session state if the given player was the one
    /// that saved it. Called from VideoPlayerViewController.tearDownPlayer()
    /// so that a normal dismiss (without minimizing) also clears stale state.
    func clearSessionStateIfNeeded(for player: VideoPlayerViewController) {
        let hash = player.torrentHandle?.infoHashes.best.hex
            ?? player.videoEntity?.torrents?.torrentHashString
            ?? ""
        guard !hash.isEmpty,
              let state = UserDefaults.standard.dictionary(forKey: Self.sessionStateKey),
              let savedHash = state["torrentHash"] as? String,
              savedHash == hash else { return }
        clearSessionState()
    }

    /// Re-saves the session state if a mini-player is currently active.
    /// Called from AppDelegate.applicationDidEnterBackground so the latest
    /// playback position is persisted before the system may kill the app.
    func resaveSessionStateIfActive() {
        guard let player = activePlayer else { return }
        saveSessionState(player)
    }

    // MARK: - Session Restore (Hayase: server.active auto-mount on launch)

    /// Number of retry attempts remaining when the torrent handle exists but
    /// its metadata (file list) has not been restored yet by libtorrent.
    private var restoreRetries = 0

    /// Attempts to restore the mini-player from a previously saved session.
    /// Called from AppDelegate after TorrentService has finished initializing
    /// (which restores libtorrent handles via fastResume).
    ///
    /// Flow mirrors Hayase's wrapper.svelte: if `server.active` has a value
    /// when the app mounts, the player component renders in mini-player mode
    /// immediately. Here, we check UserDefaults for saved session state, look
    /// up the torrent handle (already restored by libtorrent), create a
    /// VideoPlayerViewController with the same properties, and show it as a
    /// mini-player.
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

        let backend = state["backend"] as? String
        let savedPath = state["videoPath"] as? String ?? ""
        if backend == "webtorrent" || Self.isHTTPStreamPath(savedPath) {
            restoreWebTorrentSession(state: state,
                                     hash: hash,
                                     fileIndex: fileIndex,
                                     anilistID: anilistID,
                                     episodeNumber: episodeNumber,
                                     totalEpisodes: totalEpisodes)
            return
        }

        // Look up the torrent handle — try the handles dict first (populated
        // from libtorrent's fastResume during TorrentService.init()), then
        // fall back to re-adding the torrent via magnet link.  This mirrors
        // the Hayase web interface (server.play → native.playTorrent) which
        // always re-adds the torrent on page reload instead of relying on
        // libtorrent's auto-restore.
        let magnetLink = state["magnetLink"] as? String
        guard let handle = TorrentService.sharedTorrentService.readdTorrent(
            hash: hash, magnetLink: magnetLink) else {
            print("MiniPlayerManager: session restore — could not obtain torrent handle for \(hash), clearing state")
            clearSessionState()
            return
        }

        // Resolve the current video path from the torrent handle's snapshot.
        // The snapshot's downloadPath always reflects the CURRENT Documents
        // directory, so the path is correct even if the sandbox container UUID
        // changed between launches. This avoids relying on stale paths stored
        // in CoreData or UserDefaults.
        let snapshotState: (TorrentHandle.Snapshot, String)? = TorrentService.sharedTorrentService.withActiveHandle(handle, default: nil) { activeHandle in
            activeHandle.updateSnapshot()
            let snapshot = activeHandle.snapshot
            let resolvedPath: String
            if let entry = snapshot.files.first(where: { $0.index == Int(fileIndex) }),
               let base = snapshot.downloadPath {
                resolvedPath = base.appendingPathComponent(entry.path).path
            } else {
                resolvedPath = ""
            }
            return (snapshot, resolvedPath)
        }
        guard let (snapshot, resolvedSnapshotPath) = snapshotState else {
            clearSessionState()
            return
        }

        let resolvedPath: String
        if !resolvedSnapshotPath.isEmpty {
            resolvedPath = resolvedSnapshotPath
        } else if snapshot.files.isEmpty {
            // Metadata not yet available (fastResume hasn't finished parsing).
            // Retry after a short delay so libtorrent has time to restore the
            // file list from the resume data.
            if restoreRetries < maxRestoreRetries {
                restoreRetries += 1
                print("MiniPlayerManager: session restore — metadata not ready, retry \(restoreRetries)/\(maxRestoreRetries)")
                DispatchQueue.main.asyncAfter(deadline: .now() + restoreRetryDelay) { [weak self] in
                    self?.restoreSessionIfNeeded()
                }
            } else {
                print("MiniPlayerManager: session restore — metadata never became available, clearing state")
                restoreRetries = 0
                clearSessionState()
            }
            return
        } else {
            // Handle has files but the specific fileIndex wasn't found.
            // Fall back to the saved path as a best-effort attempt.
            resolvedPath = state["videoPath"] as? String ?? ""
        }

        guard !resolvedPath.isEmpty else {
            print("MiniPlayerManager: session restore — could not resolve video path, clearing state")
            clearSessionState()
            return
        }

        restoreRetries = 0

        // Look up the Videos entity from CoreData.
        let context = CoreDataService.sharedCoreDataService.mainQueueContext
        let fetchRequest = NSFetchRequest<Videos>(entityName: Videos.entityName)
        fetchRequest.predicate = NSPredicate(
            format: "torrents.torrentHashString == %@ AND videoIndex == %d",
            hash, Int(fileIndex))
        var entity: Videos?
        do {
            entity = try context.fetch(fetchRequest).first
        } catch {
            print("MiniPlayerManager: session restore — CoreData fetch failed: \(error)")
        }

        // If the Videos entity doesn't exist in CoreData (e.g. the rootContext
        // was never flushed to disk before the app was killed), create a
        // temporary entity so the player has something to work with.
        if entity == nil {
            // We need a Torrents parent. Try to find it or create one.
            let tReq = NSFetchRequest<Torrents>(entityName: Torrents.entityName)
            tReq.predicate = NSPredicate(format: "torrentHashString == %@", hash)
            var torrentEntity = (try? context.fetch(tReq))?.first
            if torrentEntity == nil {
                torrentEntity = NSEntityDescription.insertNewObject(
                    forEntityName: Torrents.entityName, into: context) as? Torrents
                torrentEntity?.torrentHashString = hash
                torrentEntity?.torrentName = snapshot.name
                torrentEntity?.torrentDownloadURL = state["magnetLink"] as? String
            }

            if let te = torrentEntity,
               let v = NSEntityDescription.insertNewObject(
                forEntityName: Videos.entityName, into: context) as? Videos {
                v.videoPath  = resolvedPath
                v.videoIndex = NSNumber(value: Int(fileIndex))
                v.torrents   = te
                if let fileEntry = snapshot.files.first(where: { $0.index == Int(fileIndex) }) {
                    v.videoName = fileEntry.name
                    v.videoSize = NSNumber(value: Double(fileEntry.size) / 1024.0 / 1024.0)
                }
                try? context.save()
                CoreDataService.sharedCoreDataService.saveRootContext {}
                entity = v
                print("MiniPlayerManager: session restore — created Videos entity on-the-fly")
            }
        }

        guard let entity else {
            print("MiniPlayerManager: session restore — could not obtain Videos entity, clearing state")
            clearSessionState()
            return
        }

        // Always refresh the videoPath from the resolved path so it reflects
        // the current sandbox directory (the path stored in CoreData may be
        // stale if the container UUID changed between launches).
        if entity.videoPath != resolvedPath {
            entity.videoPath = resolvedPath
            try? context.save()
        }

        // Fetch all video entities for this torrent so the player can show
        // next/prev buttons and navigate between episodes.
        let allReq = NSFetchRequest<Videos>(entityName: Videos.entityName)
        allReq.predicate = NSPredicate(format: "torrents.torrentHashString == %@", hash)
        allReq.sortDescriptors = [NSSortDescriptor(key: "videoIndex", ascending: true),
                                  NSSortDescriptor(key: "videoName", ascending: true)]
        let allVideos = (try? context.fetch(allReq)) ?? [entity]

        // Create a VideoService so piece prioritization and file path
        // resolution work correctly during playback. Without this, the
        // torrent downloads all files instead of focusing on the target.
        let torrentEntity = entity.torrents ?? {
            let tReq = NSFetchRequest<Torrents>(entityName: Torrents.entityName)
            tReq.predicate = NSPredicate(format: "torrentHashString == %@", hash)
            return (try? context.fetch(tReq))?.first
        }()
        var videoService: VideoService?
        if let te = torrentEntity {
            let vs = VideoService(torrentEntity: te)
            vs.torrentHandle = handle
            vs.selectFileForStreaming(fileIndex)
            videoService = vs
        }

        // Create the player with restored properties.
        let player = VideoPlayerViewController()
        player.videoEntity      = entity
        player.torrentHandle    = handle
        player.videoService     = videoService
        player.fileIndex        = fileIndex
        player.anilistID        = anilistID
        player.episodeNumber    = episodeNumber
        player.totalEpisodes    = totalEpisodes
        player.allVideos        = allVideos
        player.currentVideoIndex = allVideos.firstIndex(of: entity) ?? 0

        // Wire up episode change so restored players can navigate to
        // out-of-batch episodes. Mirrors ExtensionSearchViewController's
        // handleEpisodeChangeFromPlayer(): close mini-player → navigate to
        // search screen → auto-select best torrent.
        player.onEpisodeChange = { [weak self] episode, media in
            self?.handleRestoredEpisodeChange(episode: episode, anilistID: media?.id ?? anilistID)
        }

        // Start the restored player paused so it does not auto-play on launch.
        player.shouldStartPaused = true

        // Force viewDidLoad → sets up surface, loads video, starts streaming.
        _ = player.view

        // Show as mini-player without presenting/dismissing.
        showAsMiniPlayer(player)
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
        try? context.save()
        CoreDataService.sharedCoreDataService.saveRootContext {}

        let videoService = VideoService(torrentEntity: torrentEntity, episode: episodeNumber, backendKind: .webtorrent)
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

        let selectedVideo = videos.first { ($0.videoIndex?.uintValue ?? UInt.max) == fileIndex } ?? videos.first!
        let selectedIndex = selectedVideo.videoIndex?.uintValue ?? fileIndex
        let resolvedPath = videoService.UpdateFilePathForFileIndex(selectedIndex)
        if !resolvedPath.isEmpty, selectedVideo.videoPath != resolvedPath {
            selectedVideo.videoPath = resolvedPath
            try? context.save()
        }

        let player = VideoPlayerViewController()
        player.videoEntity = selectedVideo
        player.torrentHandle = nil
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
        activePlayer = player
        player.isMinimizing = true

        let window = makePassthroughWindow(preferredScene: nil)
        miniWindow = window

        let container = makeContainer()
        window.rootViewController?.view.addSubview(container)
        containerView = container

        // Reparent the MPV surface into the mini-player container.
        let surface = player.surfaceView
        surface.translatesAutoresizingMaskIntoConstraints = true
        guard let inner = container.viewWithTag(innerContainerTag) else { return }
        surface.frame = inner.bounds
        surface.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        inner.insertSubview(surface, at: 0)

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
        isTucked = true
        isSnappedToRight = true
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
        AniListClient.shared.fetchAnimeByIdsResult([anilistID]) { [weak self] result in
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
