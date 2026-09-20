//
//  HayaseProgressBarWindow.swift
//  Hayase
//
//  Made by scigward.
//
//  Mirrors: src/routes/+layout.svelte (ProgressBar, zIndex 100, position: fixed)
//

import UIKit

// MARK: - HayaseProgressBarWindow

/// Keeps the bar above everything in the scene, including the modally presented player.
final class HayaseProgressBarWindow: UIWindow {
    let bar = HayaseProgressBar()

    override init(windowScene: UIWindowScene) {
        super.init(windowScene: windowScene)
        windowLevel = UIWindow.Level.normal + 1
        backgroundColor = .clear
        isUserInteractionEnabled = false

        let host = HostController()
        rootViewController = host
        bar.translatesAutoresizingMaskIntoConstraints = false
        host.view.addSubview(bar)
        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: host.view.topAnchor),
            bar.leadingAnchor.constraint(equalTo: host.view.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: host.view.trailingAnchor),
            bar.heightAnchor.constraint(equalToConstant: HayaseProgressBar.barHeight),
        ])
        isHidden = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
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
