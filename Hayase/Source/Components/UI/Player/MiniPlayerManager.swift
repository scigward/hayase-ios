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

    /// True when the mini-player is currently visible.
    var isActive: Bool { miniWindow != nil && activePlayer != nil }

    // MARK: - Dragging state (Hayase pointer events)

    /// Whether the user is currently dragging the mini-player.
    private var isDragging = false

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
    func minimize(_ player: VideoPlayerViewController) {
        // If there's already a different player active, close it first.
        if let existing = activePlayer, existing !== player {
            close()
        }
        activePlayer = player

        // Capture the window scene from the player's window BEFORE dismissing.
        // After dismiss, the player's view.window is nil, so we grab it now.
        // This is the most reliable way to get a valid scene because we know
        // the player's window is currently visible on screen.
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
        guard let inner = container.viewWithTag(100) else { return }
        surface.frame = inner.bounds
        surface.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        inner.insertSubview(surface, at: 0)

        // Add mini-player controls overlay.
        addOverlay(to: container)

        // Position and show immediately — don't start invisible and don't
        // depend on the dismiss completion to make the container visible.
        // The dismiss cross-dissolve reveals the mini-player underneath.
        isTucked = false
        isSnappedToRight = true
        repositionContainer()
        container.alpha = 1

        // Start auto-hide timer so the mini-player tucks after a few seconds.
        resetAutoHideTimer()

        // Flag to prevent viewWillDisappear from tearing down the player.
        player.isMinimizing = true
        player.dismiss(animated: true) { [weak self] in
            player.isMinimizing = false
            // Reposition after dismiss in case safe area insets changed
            // (e.g., landscape → portrait rotation during the transition).
            self?.repositionContainer()
        }

        // Persist session state so the mini-player can be restored on relaunch
        // (Hayase: server.active persists via the store, libtorrent fastResume
        // restores the torrent on restart).
        saveSessionState(player)
    }

    /// Restores the fullscreen player from the mini-player.
    /// Equivalent to Hayase's `goto('/app/player/')` on mini-player click.
    func restore() {
        guard let player = activePlayer,
              let container = containerView else { return }

        cancelAutoHideTimer()
        isTucked = false

        // Find a presenting VC.
        guard let presenter = topViewController(), presenter !== player else { return }

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
        container.removeFromSuperview()
        containerView = nil
        miniWindow?.isHidden = true
        miniWindow = nil

        // Present the fullscreen player again.
        player.isMinimizing = true          // prevent tearDownPlayer on restore too
        player.modalPresentationStyle = .fullScreen
        player.modalTransitionStyle   = .crossDissolve
        presenter.present(player, animated: true) {
            player.isMinimizing = false
        }
    }

    /// Fully closes the mini-player and tears down the player + streaming.
    /// Equivalent to the user closing the Hayase player entirely.
    func close() {
        guard let player = activePlayer else { return }

        cancelAutoHideTimer()
        isTucked = false

        // Clear persisted session so it won't auto-restore on next launch.
        clearSessionState()

        // Animate out before tearing down.
        if let container = containerView {
            UIView.animate(withDuration: 0.25, animations: {
                container.alpha = 0
                container.transform = CGAffineTransform(scaleX: 0.5, y: 0.5)
            }, completion: { [weak self] _ in
                container.removeFromSuperview()
                self?.containerView = nil
                self?.miniWindow?.isHidden = true
                self?.miniWindow = nil
            })
        }

        player.tearDownPlayer()
        activePlayer = nil
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
        container.viewWithTag(100)?.frame = CGRect(origin: .zero, size: size)
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
        inner.clipsToBounds = true
        inner.layer.cornerRadius = cornerRadius
        inner.tag = 100 // used to find inner view
        v.addSubview(inner)

        // Gestures (Hayase pointer events: drag + tap).
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        v.addGestureRecognizer(pan)
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tap.require(toFail: pan)
        v.addGestureRecognizer(tap)

        return v
    }

    /// Adds the controls overlay (play/pause) to the mini-player.
    private func addOverlay(to container: UIView) {
        guard let inner = container.viewWithTag(100) else { return }

        let overlay = UIView()
        overlay.translatesAutoresizingMaskIntoConstraints = false
        overlay.backgroundColor = UIColor.black.withAlphaComponent(0.3)
        inner.addSubview(overlay)
        NSLayoutConstraint.activate([
            overlay.topAnchor.constraint(equalTo: inner.topAnchor),
            overlay.bottomAnchor.constraint(equalTo: inner.bottomAnchor),
            overlay.leadingAnchor.constraint(equalTo: inner.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: inner.trailingAnchor),
        ])

        // Play/Pause button — center.
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
        restore()
    }

    @objc private func playPauseTapped() {
        // Any button interaction resets the auto-hide timer.
        resetAutoHideTimer()
        activePlayer?.togglePlayPause()
        let icon = activePlayer?.isPaused == true ? "play" : "pause"
        playPauseButton?.setImage(UIImage.hayaseFilledIcon(icon), for: .normal)
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
    private func resetAutoHideTimer() {
        autoHideTimer?.invalidate()
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

    /// Updates the play/pause icon in the mini-player. Called from the
    /// player's didChangePause delegate.
    func updatePlayPauseIcon(isPaused: Bool) {
        let icon = isPaused ? "play" : "pause"
        playPauseButton?.setImage(UIImage.hayaseFilledIcon(icon), for: .normal)
    }

    // MARK: - Session State Persistence

    /// Saves the minimum data required to restore the mini-player on relaunch.
    /// Mirrors Hayase's `server.active` store — the torrent session is
    /// automatically restored by libtorrent's fastResume; we just need enough
    /// metadata to reconnect to the right handle and file.
    private func saveSessionState(_ player: VideoPlayerViewController) {
        guard let hash = player.torrentHandle?.infoHashes.best.hex,
              let path = player.videoEntity?.videoPath else { return }
        let magnetLink = player.videoEntity?.torrents?.torrentDownloadURL ?? ""
        let state: [String: Any] = [
            "torrentHash":   hash,
            "magnetLink":    magnetLink,
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
        guard let hash = player.torrentHandle?.infoHashes.best.hex,
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
        handle.updateSnapshot()
        let snapshot = handle.snapshot
        let resolvedPath: String
        if let entry = snapshot.files.first(where: { $0.index == Int(fileIndex) }),
           let base = snapshot.downloadPath {
            resolvedPath = base.appendingPathComponent(entry.path).path
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
        player.onEpisodeChange = { [weak self] episode in
            self?.handleRestoredEpisodeChange(episode: episode, anilistID: anilistID)
        }

        // Start the restored player paused so it does not auto-play on launch.
        player.shouldStartPaused = true

        // Force viewDidLoad → sets up surface, loads video, starts streaming.
        _ = player.view

        // Show as mini-player without presenting/dismissing.
        showAsMiniPlayer(player)
    }

    /// Shows a player directly as a mini-player (no dismiss animation).
    /// Used for session restore on app launch where the player was never
    /// presented fullscreen.
    private func showAsMiniPlayer(_ player: VideoPlayerViewController) {
        if let existing = activePlayer, existing !== player {
            close()
        }
        activePlayer = player

        let window = makePassthroughWindow(preferredScene: nil)
        miniWindow = window

        let container = makeContainer()
        window.rootViewController?.view.addSubview(container)
        containerView = container

        // Reparent the MPV surface into the mini-player container.
        let surface = player.surfaceView
        surface.translatesAutoresizingMaskIntoConstraints = true
        guard let inner = container.viewWithTag(100) else { return }
        surface.frame = inner.bounds
        surface.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        inner.insertSubview(surface, at: 0)

        addOverlay(to: container)

        // Start tucked to the right edge (Hayase: mini-player appears
        // at the edge on launch, user taps to reveal).
        isTucked = true
        isSnappedToRight = true
        repositionContainer()
        container.alpha = 1
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
        AniListClient.shared.fetchAnimeByIds([anilistID]) { [weak self] items in
            guard let animeItem = items.first else { return }
            DispatchQueue.main.async {
                self?.presentSearchVC(animeItem: animeItem, episode: episode)
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
        // Walk the VC hierarchy to find a navigation controller we can push onto.
        var vc = window.rootViewController
        // Dismiss any presented VCs (e.g. a fullscreen player that was just closed).
        while let presented = vc?.presentedViewController {
            vc = presented
        }
        let nav: UINavigationController?
        if let tabBar = vc as? UITabBarController {
            nav = tabBar.selectedViewController as? UINavigationController
        } else {
            nav = vc as? UINavigationController ?? vc?.navigationController
        }
        guard let navController = nav else { return }

        let searchVC = ExtensionSearchViewController()
        searchVC.animeItem = animeItem
        searchVC.initialEpisode = episode
        searchVC.shouldAutoSelectOnSearch = true
        navController.pushViewController(searchVC, animated: true)
    }
}
