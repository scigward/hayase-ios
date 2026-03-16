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

final class MiniPlayerManager {

    static let shared = MiniPlayerManager()

    // MARK: - Constants (Hayase wrapper.svelte)

    /// Hayase: `max-w-[22rem]` ≈ 352pt. Reduced for phone screens.
    private let miniWidth: CGFloat = 200
    /// 16:9 aspect ratio.
    private var miniHeight: CGFloat { miniWidth * 9 / 16 }
    /// Padding from screen edges.
    private let edgePadding: CGFloat = 12
    /// Corner radius matching Hayase's `[&>*]:rounded-lg`.
    private let cornerRadius: CGFloat = 12
    /// Snap animation (Hayase: `transition-transform duration-[500ms]
    /// ease-[cubic-bezier(0.3,1.5,0.8,1)]`).
    private let snapDuration: TimeInterval = 0.5

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

    // MARK: - Init

    private init() {}

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

        // Create a dedicated window for the mini-player so it floats above
        // all content regardless of which view controller is presented.
        let window = makePassthroughWindow()
        miniWindow = window

        // Create the mini-player container (shadow + rounded corners).
        let container = makeContainer()
        window.rootViewController?.view.addSubview(container)
        containerView = container

        // Reparent the MPV surface into the mini-player container.
        let surface = player.surfaceView
        surface.translatesAutoresizingMaskIntoConstraints = true
        let inner = container.viewWithTag(100)!
        surface.frame = inner.bounds
        surface.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        inner.insertSubview(surface, at: 0)

        // Add mini-player controls overlay.
        addOverlay(to: container)

        // Start with the container at the target position, but invisible.
        let safeBottom = window.safeAreaInsets.bottom
        let targetFrame = CGRect(
            x: window.bounds.width - miniWidth - edgePadding,
            y: window.bounds.height - miniHeight - edgePadding - safeBottom,
            width: miniWidth, height: miniHeight)
        container.frame = targetFrame
        container.alpha = 0
        container.transform = CGAffineTransform(scaleX: 0.6, y: 0.6)

        // Flag to prevent viewWillDisappear from tearing down the player.
        player.isMinimizing = true
        player.dismiss(animated: true) { [weak self] in
            player.isMinimizing = false
            // Animate the mini-player fading in with a scale-up.
            UIView.animate(
                withDuration: self?.snapDuration ?? 0.5,
                delay: 0,
                usingSpringWithDamping: 0.7,
                initialSpringVelocity: 0.5,
                options: .curveEaseOut
            ) {
                container.alpha = 1
                container.transform = .identity
            }
        }
    }

    /// Restores the fullscreen player from the mini-player.
    /// Equivalent to Hayase's `goto('/app/player/')` on mini-player click.
    func restore() {
        guard let player = activePlayer,
              let container = containerView else { return }

        // Find a presenting VC.
        guard let presenter = topViewController() else { return }

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

    // MARK: - Window + Container creation

    /// Creates the dedicated passthrough window for the mini-player.
    private func makePassthroughWindow() -> PassthroughWindow {
        let window = PassthroughWindow(frame: UIScreen.main.bounds)
        // Attach to the active window scene (required on iOS 13+).
        if let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) {
            window.windowScene = scene
        }
        // Above normal windows but below alerts/keyboards.
        window.windowLevel = .normal + 1
        window.backgroundColor = .clear
        window.isUserInteractionEnabled = true
        let rootVC = UIViewController()
        rootVC.view.backgroundColor = .clear
        window.rootViewController = rootVC
        window.isHidden = false
        return window
    }

    /// Builds the floating mini-player container view (Hayase wrapper.svelte
    /// mini-player div with rounded corners and shadow).
    private func makeContainer() -> UIView {
        let v = UIView(frame: CGRect(x: 0, y: 0, width: miniWidth, height: miniHeight))
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

    /// Adds the controls overlay (play/pause + close) to the mini-player.
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
        let icon = activePlayer?.isPaused == true ? "play.fill" : "pause.fill"
        ppBtn.setImage(UIImage(systemName: icon), for: .normal)
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

        // Close button — top-right (Hayase: click close destroys player).
        let closeBtn = UIButton(type: .system)
        closeBtn.translatesAutoresizingMaskIntoConstraints = false
        closeBtn.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        closeBtn.tintColor = .white
        closeBtn.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        overlay.addSubview(closeBtn)
        NSLayoutConstraint.activate([
            closeBtn.topAnchor.constraint(equalTo: overlay.topAnchor, constant: 6),
            closeBtn.trailingAnchor.constraint(equalTo: overlay.trailingAnchor, constant: -6),
            closeBtn.widthAnchor.constraint(equalToConstant: 28),
            closeBtn.heightAnchor.constraint(equalToConstant: 28),
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

    /// Tap gesture — restore fullscreen (Hayase: clicking mini-player calls
    /// `goto('/app/player/')`).
    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        restore()
    }

    @objc private func playPauseTapped() {
        activePlayer?.togglePlayPause()
        let icon = activePlayer?.isPaused == true ? "play.fill" : "pause.fill"
        playPauseButton?.setImage(UIImage(systemName: icon), for: .normal)
    }

    @objc private func closeTapped() {
        close()
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

        if isLeft {
            targetX = edgePadding
        } else {
            targetX = window.bounds.width - miniWidth - edgePadding
        }

        if isTop {
            targetY = edgePadding + safeInsets.top
        } else {
            targetY = window.bounds.height - miniHeight - edgePadding - safeInsets.bottom
        }

        // Hayase: `transition-transform duration-[500ms]
        // ease-[cubic-bezier(0.3,1.5,0.8,1)]` — a springy overshoot.
        UIView.animate(
            withDuration: snapDuration,
            delay: 0,
            usingSpringWithDamping: 0.6,
            initialSpringVelocity: 0.8,
            options: .curveEaseOut
        ) {
            container.frame = CGRect(
                x: targetX, y: targetY,
                width: self.miniWidth, height: self.miniHeight)
        }
    }

    // MARK: - Helpers

    private func topViewController() -> UIViewController? {
        guard let appDelegate = UIApplication.shared.delegate as? AppDelegate,
              let window = appDelegate.window else { return nil }
        var vc = window.rootViewController
        while let presented = vc?.presentedViewController {
            vc = presented
        }
        return vc
    }

    /// Updates the play/pause icon in the mini-player. Called from the
    /// player's didChangePause delegate.
    func updatePlayPauseIcon(isPaused: Bool) {
        let icon = isPaused ? "play.fill" : "pause.fill"
        playPauseButton?.setImage(UIImage(systemName: icon), for: .normal)
    }
}
