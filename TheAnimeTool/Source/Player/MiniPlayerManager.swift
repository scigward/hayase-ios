/// Hayase wrapper.svelte — in-app mini-player manager.
///
/// In Hayase, the player component (wrapper.svelte) is always mounted in the
/// layout. When the user navigates away from `/app/player`, it switches to
/// mini-player mode: a 22rem-wide floating window at the bottom-right corner,
/// draggable, with click-to-restore. The torrent session stays alive.
///
/// This iOS port uses a floating UIView on the key window to replicate that
/// behavior. When the user taps back in the fullscreen player, the MPV surface
/// is reparented into a small container at the bottom-right. Tapping the
/// mini-player restores fullscreen. The close button fully tears down the
/// player and streaming pipeline.
import UIKit

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

    /// The floating container added to the key window.
    private var containerView: UIView?

    /// The play/pause button in the mini-player overlay.
    private var playPauseButton: UIButton?

    /// True when the mini-player is currently visible.
    var isActive: Bool { containerView?.superview != nil && activePlayer != nil }

    // MARK: - Dragging state (Hayase pointer events)

    /// Whether the user is currently dragging the mini-player.
    private var isDragging = false
    /// Offset from the touch point to the container's origin (for smooth drag).
    private var dragOffset: CGPoint = .zero

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

        // Create the floating container on the key window.
        guard let window = keyWindow() else { return }

        let container = makeContainer()
        window.addSubview(container)

        // Reparent the MPV surface into the mini-player's inner clipped view.
        let surface = player.surfaceView
        surface.translatesAutoresizingMaskIntoConstraints = true
        let inner = container.viewWithTag(100)!
        surface.frame = inner.bounds
        surface.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        inner.insertSubview(surface, at: 0)

        // Add mini-player controls overlay.
        addOverlay(to: container)

        containerView = container

        // Position off-screen to the right, then animate in.
        let safeBottom = window.safeAreaInsets.bottom
        let targetFrame = CGRect(
            x: window.bounds.width - miniWidth - edgePadding,
            y: window.bounds.height - miniHeight - edgePadding - safeBottom,
            width: miniWidth, height: miniHeight)
        container.frame = targetFrame.offsetBy(dx: miniWidth + edgePadding, dy: 0)

        // Flag to prevent viewWillDisappear from tearing down the player.
        player.isMinimizing = true
        player.dismiss(animated: true) { [weak self] in
            player.isMinimizing = false
            // Animate the mini-player sliding in from the right.
            UIView.animate(
                withDuration: self?.snapDuration ?? 0.5,
                delay: 0,
                usingSpringWithDamping: 0.7,
                initialSpringVelocity: 0.5,
                options: .curveEaseOut
            ) {
                container.frame = targetFrame
            }
        }
    }

    /// Restores the fullscreen player from the mini-player.
    /// Equivalent to Hayase's `goto('/app/player/')` on mini-player click.
    func restore() {
        guard let player = activePlayer, let container = containerView else { return }

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

        // Remove the mini-player container.
        container.removeFromSuperview()
        containerView = nil

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
            }, completion: { _ in
                container.removeFromSuperview()
            })
        }

        player.tearDownPlayer()
        containerView = nil
        activePlayer = nil
    }

    // MARK: - Container creation

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
        guard let container = containerView, let window = container.superview else { return }
        let translation = gesture.translation(in: window)

        switch gesture.state {
        case .began:
            isDragging = true
        case .changed:
            container.center = CGPoint(
                x: container.center.x + translation.x,
                y: container.center.y + translation.y)
            gesture.setTranslation(.zero, in: window)
        case .ended, .cancelled:
            isDragging = false
            snapToNearestCorner(in: window)
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
    private func snapToNearestCorner(in window: UIView) {
        guard let container = containerView else { return }
        let center = container.center
        let safeInsets = (window as? UIWindow)?.safeAreaInsets ?? .zero

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

    private func keyWindow() -> UIWindow? {
        if let appDelegate = UIApplication.shared.delegate as? AppDelegate {
            return appDelegate.window
        }
        return UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
    }

    private func topViewController() -> UIViewController? {
        var vc = keyWindow()?.rootViewController
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
