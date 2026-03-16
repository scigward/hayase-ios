/// Handles AirPlay / external display video output for the MPV player.
///
/// AVSampleBufferDisplayLayer only renders video locally — it does NOT
/// automatically route frames to AirPlay devices. When the user selects an
/// AirPlay receiver via AVRoutePickerView, only audio is routed through
/// AVAudioSession. To fix this, we detect external screen connections and
/// present the MPV surface on a new UIWindow attached to that screen.
///
/// This mirrors the behavior of AVPlayer's built-in AirPlay video support,
/// but for custom renderers.
import UIKit

final class ExternalDisplayManager {

    static let shared = ExternalDisplayManager()

    /// The window created on the external (AirPlay) screen.
    private var externalWindow: UIWindow?

    /// The view controller whose surface is currently on the external display.
    private weak var activePlayer: VideoPlayerViewController?

    /// Placeholder shown on the local device while video is on external display.
    private var placeholderView: UIView?

    private init() {
        // Listen for screen connect/disconnect (AirPlay mirroring, HDMI, etc.)
        NotificationCenter.default.addObserver(
            self, selector: #selector(screenDidConnect(_:)),
            name: UIScreen.didConnectNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(screenDidDisconnect(_:)),
            name: UIScreen.didDisconnectNotification, object: nil)

        // If an external screen is already connected at launch, handle it.
        // Use modern UIWindowScene API to find external screens.
        if let externalScreen = findExternalScreen() {
            setupExternalWindow(on: externalScreen)
        }
    }

    // MARK: - Public API

    /// Registers a player so its video surface is sent to external displays.
    func register(_ player: VideoPlayerViewController) {
        activePlayer = player
        // If an external screen is already connected, move the surface now.
        if let window = externalWindow {
            moveToExternal(window: window)
        }
    }

    /// Unregisters the player (called when the player is torn down).
    func unregister(_ player: VideoPlayerViewController) {
        guard activePlayer === player else { return }
        moveToLocal()
        activePlayer = nil
    }

    // MARK: - Screen notifications

    @objc private func screenDidConnect(_ note: Notification) {
        guard let screen = note.object as? UIScreen else { return }
        setupExternalWindow(on: screen)
        moveToExternal(window: externalWindow)
    }

    @objc private func screenDidDisconnect(_ note: Notification) {
        moveToLocal()
        externalWindow?.isHidden = true
        externalWindow = nil
    }

    // MARK: - External window management

    /// Finds an external screen using the modern UIWindowScene API.
    private func findExternalScreen() -> UIScreen? {
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            // External display scenes are not the main foreground scene.
            // Check if the screen is different from the main screen.
            if windowScene.screen !== UIScreen.main {
                return windowScene.screen
            }
        }
        return nil
    }

    private func setupExternalWindow(on screen: UIScreen) {
        let window = UIWindow(frame: screen.bounds)
        window.screen = screen
        window.rootViewController = UIViewController()
        window.rootViewController?.view.backgroundColor = .black
        window.isHidden = false
        externalWindow = window
    }

    /// Moves the MPV surface from the local player view to the external window.
    private func moveToExternal(window: UIWindow?) {
        guard let window, let player = activePlayer else { return }
        let surface = player.surfaceView

        // Create a placeholder on the local device.
        let placeholder = UIView()
        placeholder.backgroundColor = .black
        placeholder.translatesAutoresizingMaskIntoConstraints = false

        let label = UILabel()
        label.text = "Playing on AirPlay"
        label.textColor = UIColor(white: 0.7, alpha: 1)
        label.font = .systemFont(ofSize: 16, weight: .medium)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        placeholder.addSubview(label)

        let icon = UIImageView(image: UIImage(systemName: "airplayvideo"))
        icon.tintColor = UIColor(white: 0.7, alpha: 1)
        icon.contentMode = .scaleAspectFit
        icon.translatesAutoresizingMaskIntoConstraints = false
        placeholder.addSubview(icon)

        NSLayoutConstraint.activate([
            icon.centerXAnchor.constraint(equalTo: placeholder.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: placeholder.centerYAnchor, constant: -16),
            icon.widthAnchor.constraint(equalToConstant: 44),
            icon.heightAnchor.constraint(equalToConstant: 44),
            label.topAnchor.constraint(equalTo: icon.bottomAnchor, constant: 8),
            label.centerXAnchor.constraint(equalTo: placeholder.centerXAnchor),
        ])

        // Replace the surface in the player's view with the placeholder.
        let playerView = surface.superview ?? player.view!
        placeholder.frame = surface.frame
        placeholder.autoresizingMask = surface.autoresizingMask
        placeholder.translatesAutoresizingMaskIntoConstraints = surface.translatesAutoresizingMaskIntoConstraints
        playerView.insertSubview(placeholder, aboveSubview: surface)
        if !surface.translatesAutoresizingMaskIntoConstraints {
            NSLayoutConstraint.activate([
                placeholder.topAnchor.constraint(equalTo: playerView.topAnchor),
                placeholder.bottomAnchor.constraint(equalTo: playerView.bottomAnchor),
                placeholder.leadingAnchor.constraint(equalTo: playerView.leadingAnchor),
                placeholder.trailingAnchor.constraint(equalTo: playerView.trailingAnchor),
            ])
        }
        placeholderView = placeholder

        // Move the surface to the external screen's window.
        surface.translatesAutoresizingMaskIntoConstraints = true
        surface.frame = window.bounds
        surface.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        window.rootViewController?.view.addSubview(surface)
    }

    /// Moves the MPV surface back from the external window to the local player.
    private func moveToLocal() {
        guard let player = activePlayer else { return }
        let surface = player.surfaceView

        // Remove the placeholder.
        placeholderView?.removeFromSuperview()
        placeholderView = nil

        // Reparent the surface back into the player's view.
        surface.translatesAutoresizingMaskIntoConstraints = false
        player.view.insertSubview(surface, at: 0)
        NSLayoutConstraint.activate([
            surface.topAnchor.constraint(equalTo: player.view.topAnchor),
            surface.bottomAnchor.constraint(equalTo: player.view.bottomAnchor),
            surface.leadingAnchor.constraint(equalTo: player.view.leadingAnchor),
            surface.trailingAnchor.constraint(equalTo: player.view.trailingAnchor),
        ])
    }
}
