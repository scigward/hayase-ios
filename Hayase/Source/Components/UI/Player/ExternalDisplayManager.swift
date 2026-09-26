/// Handles dedicated external-display video output for the MPV player.
///
/// Normal iOS screen mirroring is left entirely to the system. Hayase only
/// creates an app-owned external window while a player is active, because the
/// custom MPV surface does not get AVPlayer-style AirPlay video routing for free.
import UIKit

final class ExternalDisplayManager {

    enum LocalSurfaceLayout {
        case pinnedToEdges
        case fillBounds
    }

    static let shared = ExternalDisplayManager()

    private final class LocalSurfaceHost {
        weak var view: UIView?
        var layout: LocalSurfaceLayout

        init(view: UIView, layout: LocalSurfaceLayout) {
            self.view = view
            self.layout = layout
        }
    }

    private var externalWindow: UIWindow?
    private var connectedExternalScreen: UIScreen?
    private weak var activePlayer: VideoPlayerViewController?
    private var isVideoOutputReady = false
    private var localSurfaceHost: LocalSurfaceHost?
    private var placeholderView: UIView?

    private init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenDidConnect(_:)),
            name: UIScreen.didConnectNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenDidDisconnect(_:)),
            name: UIScreen.didDisconnectNotification,
            object: nil
        )
        connectedExternalScreen = findExternalScreen()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Public API

    /// Registers the current MPV player without taking over the external screen.
    /// Dedicated output starts only after MPV has a decoded frame ready.
    func register(_ player: VideoPlayerViewController) {
        guard activePlayer !== player else { return }
        deactivateExternalOutput()
        activePlayer = player
        isVideoOutputReady = false
    }

    func videoDidBecomeReady(_ player: VideoPlayerViewController) {
        guard activePlayer === player else { return }
        isVideoOutputReady = true
        guard externalWindow == nil,
              let screen = connectedExternalScreen ?? findExternalScreen() else { return }
        connectedExternalScreen = screen
        activateExternalOutput(on: screen)
    }

    func unregister(_ player: VideoPlayerViewController) {
        guard activePlayer === player else { return }
        deactivateExternalOutput()
        activePlayer = nil
        isVideoOutputReady = false
        localSurfaceHost = nil
    }

    /// Updates where the player surface should return locally while the video is
    /// owned by the external display. Returns true when external output currently
    /// owns the surface, so the caller must not reparent it itself.
    @discardableResult
    func updateLocalPresentationHost(for player: VideoPlayerViewController,
                                     view: UIView,
                                     layout: LocalSurfaceLayout) -> Bool {
        guard activePlayer === player, externalWindow != nil else { return false }
        localSurfaceHost = LocalSurfaceHost(view: view, layout: layout)
        installPlaceholder(in: view, layout: layout)
        return true
    }

    // MARK: - Screen notifications

    @objc private func screenDidConnect(_ note: Notification) {
        guard let screen = note.object as? UIScreen,
              screen !== UIScreen.main else { return }
        connectedExternalScreen = screen
        guard activePlayer != nil, isVideoOutputReady else { return }
        activateExternalOutput(on: screen)
    }

    @objc private func screenDidDisconnect(_ note: Notification) {
        guard let screen = note.object as? UIScreen else { return }
        if connectedExternalScreen === screen {
            connectedExternalScreen = nil
        }
        guard externalWindow?.screen === screen else { return }
        deactivateExternalOutput()
    }

    // MARK: - External output lifecycle

    private func activateExternalOutput(on screen: UIScreen) {
        guard let player = activePlayer else { return }

        if let window = externalWindow, window.screen === screen {
            return
        }
        if externalWindow != nil {
            deactivateExternalOutput()
        }

        let surface = player.surfaceView
        guard let localView = surface.superview else { return }
        let localLayout: LocalSurfaceLayout = surface.translatesAutoresizingMaskIntoConstraints
            ? .fillBounds
            : .pinnedToEdges
        localSurfaceHost = LocalSurfaceHost(view: localView, layout: localLayout)

        let window = makeExternalWindow(on: screen)
        guard let externalRoot = window.rootViewController?.view else { return }
        externalWindow = window

        installPlaceholder(in: localView, layout: localLayout)
        detach(surface, from: localView)

        surface.translatesAutoresizingMaskIntoConstraints = true
        surface.frame = externalRoot.bounds
        surface.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        externalRoot.addSubview(surface)
        window.isHidden = false
    }

    private func deactivateExternalOutput() {
        guard externalWindow != nil else {
            removePlaceholder()
            return
        }

        if let player = activePlayer {
            if let host = localSurfaceHost, let localView = host.view {
                attach(player.surfaceView, to: localView, layout: host.layout)
            } else {
                attach(player.surfaceView, to: player.view, layout: .pinnedToEdges)
            }
        }

        removePlaceholder()
        externalWindow?.isHidden = true
        externalWindow?.rootViewController = nil
        externalWindow = nil
    }

    // MARK: - Window management

    private func findExternalScreen() -> UIScreen? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .map(\.screen)
            .first { $0 !== UIScreen.main }
    }

    private func makeExternalWindow(on screen: UIScreen) -> UIWindow {
        let window: UIWindow
        if let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.screen === screen }) {
            window = UIWindow(windowScene: windowScene)
            window.frame = windowScene.coordinateSpace.bounds
        } else {
            window = UIWindow(frame: screen.bounds)
            window.screen = screen
        }

        let root = UIViewController()
        root.view.backgroundColor = .black
        window.rootViewController = root
        return window
    }

    // MARK: - Surface hosting

    private func detach(_ surface: UIView, from host: UIView) {
        let constraints = host.constraints.filter { constraint in
            (constraint.firstItem as? UIView) === surface ||
            (constraint.secondItem as? UIView) === surface
        }
        NSLayoutConstraint.deactivate(constraints)
        surface.removeFromSuperview()
    }

    private func attach(_ surface: UIView,
                        to host: UIView,
                        layout: LocalSurfaceLayout) {
        if let currentHost = surface.superview {
            detach(surface, from: currentHost)
        }

        host.insertSubview(surface, at: 0)
        switch layout {
        case .pinnedToEdges:
            surface.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                surface.topAnchor.constraint(equalTo: host.topAnchor),
                surface.bottomAnchor.constraint(equalTo: host.bottomAnchor),
                surface.leadingAnchor.constraint(equalTo: host.leadingAnchor),
                surface.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            ])
        case .fillBounds:
            surface.translatesAutoresizingMaskIntoConstraints = true
            surface.frame = host.bounds
            surface.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        }
    }

    // MARK: - Local placeholder

    private func installPlaceholder(in host: UIView, layout: LocalSurfaceLayout) {
        removePlaceholder()

        let placeholder = makePlaceholder()
        placeholderView = placeholder
        host.insertSubview(placeholder, at: 0)

        switch layout {
        case .pinnedToEdges:
            placeholder.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                placeholder.topAnchor.constraint(equalTo: host.topAnchor),
                placeholder.bottomAnchor.constraint(equalTo: host.bottomAnchor),
                placeholder.leadingAnchor.constraint(equalTo: host.leadingAnchor),
                placeholder.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            ])
        case .fillBounds:
            placeholder.translatesAutoresizingMaskIntoConstraints = true
            placeholder.frame = host.bounds
            placeholder.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        }
    }

    private func removePlaceholder() {
        placeholderView?.removeFromSuperview()
        placeholderView = nil
    }

    private func makePlaceholder() -> UIView {
        let placeholder = UIView()
        placeholder.backgroundColor = .black

        let label = UILabel()
        label.text = "Playing on AirPlay"
        label.textColor = UIColor.HayaseTheme.mutedForeground
        label.font = .nunito(ofSize: 16, weight: .medium)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        placeholder.addSubview(label)

        let icon = UIImageView(image: UIImage.hayaseIcon("airplay"))
        icon.tintColor = UIColor.HayaseTheme.mutedForeground
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
        return placeholder
    }
}
