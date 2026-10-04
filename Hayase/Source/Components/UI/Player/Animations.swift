//
//  Animations.swift
//  Hayase
//
//  Mirrors: src/lib/components/ui/player/animations.svelte: the large icon (or text) that pulses in the middle of the
//  player when it plays, pauses, seeks or changes the volume, and is gone when the pulse ends.
//

import UIKit
import AVKit
import CoreMedia
import UniformTypeIdentifiers

extension VideoPlayerViewController {
    func showPlayerAnimation(icon: String) {
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

    func showPlayerTextAnimation(_ text: String) {
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
}
