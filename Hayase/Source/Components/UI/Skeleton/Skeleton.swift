//
//  Skeleton.swift
//  Hayase
//
//  Created by scigward.
//  Mirrors: interface bg-primary/5 animate-pulse skeleton blocks.
//

import UIKit

enum HayaseSkeleton {
    static let animationKey = "hayase-skeleton-pulse"
    static let color = UIColor.HayaseTheme.primary.withAlphaComponent(0.05)

    static func makeBlock(cornerRadius: CGFloat = 4) -> UIView {
        let view = UIView()
        view.backgroundColor = color
        view.layer.cornerRadius = cornerRadius
        view.clipsToBounds = true
        view.translatesAutoresizingMaskIntoConstraints = false
        startPulse(on: view)
        return view
    }

    static func startPulse(on view: UIView) {
        view.layer.removeAnimation(forKey: animationKey)
        view.layer.opacity = 1

        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 1
        pulse.toValue = 0.5
        pulse.duration = 2
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        view.layer.add(pulse, forKey: animationKey)
    }

    static func stopPulse(on view: UIView) {
        view.layer.removeAnimation(forKey: animationKey)
        view.layer.opacity = 1
    }
}
