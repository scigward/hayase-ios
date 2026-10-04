//
//  Menubar.swift
//  Hayase
//
//  Mirrors: src/lib/components/ui/menubar/menubar.svelte. Its window controls and navigation buttons are
//  desktop only (`!SUPPORTS.isAndroid && !SUPPORTS.isIOS`); the "Debug Mode!" ribbon sits outside that
//  branch and shows on every platform while a logging level is set (`{#if $debug}`).
//

import UIKit

// MARK: - DebugRibbonView

/// `<div class='ribbon z-[1000] text-center fixed font-bold pointer-events-none'>Debug Mode!</div>`
///
///     .ribbon {
///       background: #f63220;
///       box-shadow: 0 0 0 999px #f63220;
///       clip-path: inset(0 -100%);
///       inset: 0 auto auto 0;
///       transform-origin: 100% 0;
///       transform: translate(-29.3%) rotate(-45deg);
///     }
///
/// The box takes the width of its text (a fixed box shrinks to fit) and a 24pt line. The shadow would fill
/// the screen, and `clip-path: inset(0 -100%)` cuts it to a band as tall as the box and three boxes wide,
/// one on each side of it.
private final class DebugRibbonView: UIView {
    private static let red = UIColor(red: 0xf6 / 255, green: 0x32 / 255, blue: 0x20 / 255, alpha: 1)
    private static let lineHeight: CGFloat = 24   // text-base, 1.5 line height

    private let band = UIView()
    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false   // pointer-events-none
        backgroundColor = .clear

        label.text = "Debug Mode!"
        label.font = .nunito(ofSize: 16, weight: .bold)   // font-bold
        label.textColor = UIColor.HayaseTheme.foreground
        label.textAlignment = .center                       // text-center
        let width = ceil(label.intrinsicContentSize.width)
        let height = Self.lineHeight
        label.frame = CGRect(x: 0, y: 0, width: width, height: height)

        band.backgroundColor = Self.red
        band.frame = CGRect(x: -width, y: 0, width: width * 3, height: height)
        addSubview(band)
        addSubview(label)

        // inset: 0 auto auto 0, then transform-origin: 100% 0
        layer.anchorPoint = CGPoint(x: 1, y: 0)
        bounds = CGRect(x: 0, y: 0, width: width, height: height)
        layer.position = CGPoint(x: width, y: 0)
        // translate(-29.3%) rotate(-45deg): the box is turned first and then moved
        transform = CGAffineTransform(rotationAngle: -.pi / 4)
            .concatenating(CGAffineTransform(translationX: -0.293 * width, y: 0))
    }

    required init?(coder: NSCoder) {
        nil
    }
}

// MARK: - DebugRibbonWindow

/// `fixed` with `z-[1000]`: above the page, the progress bar and the player, and out of the way of touches.
final class DebugRibbonWindow: UIWindow {
    private static var shared: DebugRibbonWindow?
    private var observer: NSObjectProtocol?

    /// Puts the ribbon on the scene once. It shows and hides itself with the logging level.
    static func installIfNeeded(in scene: UIWindowScene?) {
        guard shared == nil, let scene else { return }
        shared = DebugRibbonWindow(windowScene: scene)
    }

    /// `$debug`, the logging level, is set while it is not empty.
    private static var isDebugging: Bool {
        !(UserDefaults.standard.string(forKey: Settings.Keys.debugLevel) ?? Settings.Defaults.debugLevel).isEmpty
    }

    override init(windowScene: UIWindowScene) {
        super.init(windowScene: windowScene)
        windowLevel = UIWindow.Level.normal + 2
        backgroundColor = .clear
        isUserInteractionEnabled = false

        let host = HostController()
        rootViewController = host
        let ribbon = DebugRibbonView()
        host.view.addSubview(ribbon)

        isHidden = !Self.isDebugging
        observer = NotificationCenter.default.addObserver(forName: Settings.didChange, object: nil, queue: .main) { [weak self] note in
            guard (note.userInfo?["key"] as? String) == Settings.Keys.debugLevel else { return }
            self?.isHidden = !Self.isDebugging
        }
    }

    required init?(coder: NSCoder) {
        nil
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    private final class HostController: UIViewController {
        override var prefersStatusBarHidden: Bool { true }

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .clear
            view.isUserInteractionEnabled = false
        }
    }
}
