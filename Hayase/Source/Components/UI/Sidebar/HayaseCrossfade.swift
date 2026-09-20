//
//  HayaseCrossfade.swift
//  Hayase
//
//  Made by scigward.
//
//  Mirrors: svelte/transition crossfade as configured in src/lib/components/ui/sidebar/SidebarButton.svelte (duration 150, cubicInOut)
//

import UIKit

// MARK: - HayaseCrossfade

/// Moves an active-tab pill onto its counterpart while fading, the way crossfade's send/receive pair does.
enum HayaseCrossfade {
    private static let duration: CFTimeInterval = 0.15  // duration: 150
    private static let samples = 24

    /// svelte/easing cubicInOut
    private static func easing(_ t: Double) -> Double {
        t < 0.5 ? 4 * t * t * t : 0.5 * pow(2 * t - 2, 3) + 1
    }

    /// in:send, the pill that becomes active
    static func send(_ pill: UIView, from counterpart: UIView) {
        animate(pill, counterpart: counterpart, entering: true)
    }

    /// out:receive, the pill that stops being active
    static func receive(_ pill: UIView, to counterpart: UIView) {
        animate(pill, counterpart: counterpart, entering: false)
    }

    private static func animate(_ pill: UIView, counterpart: UIView, entering: Bool) {
        guard pill.window != nil, counterpart.window != nil else { return }
        let node = pill.convert(pill.bounds, to: nil)
        let other = counterpart.convert(counterpart.bounds, to: nil)
        guard node.width > 0, node.height > 0 else { return }
        let dx = other.minX - node.minX
        let dy = other.minY - node.minY
        let dw = other.width / node.width
        let dh = other.height / node.height

        var transforms: [NSValue] = []
        var opacities: [Float] = []
        var keyTimes: [NSNumber] = []
        for index in 0...samples {
            let progress = Double(index) / Double(samples)
            let eased = easing(progress)
            let t = CGFloat(entering ? eased : 1 - eased)
            let u = 1 - t
            let scaleX = t + u * dw
            let scaleY = t + u * dh
            // transform-origin is top left, layers scale around their center
            let translateX = u * dx + (scaleX - 1) * node.width / 2
            let translateY = u * dy + (scaleY - 1) * node.height / 2
            let transform = CATransform3DConcat(CATransform3DMakeScale(scaleX, scaleY, 1),
                                                CATransform3DMakeTranslation(translateX, translateY, 0))
            transforms.append(NSValue(caTransform3D: transform))
            opacities.append(Float(t))
            keyTimes.append(NSNumber(value: progress))
        }

        let transformAnimation = CAKeyframeAnimation(keyPath: "transform")
        transformAnimation.values = transforms
        transformAnimation.keyTimes = keyTimes
        transformAnimation.duration = duration
        transformAnimation.calculationMode = .linear
        pill.layer.add(transformAnimation, forKey: "hayaseCrossfadeTransform")

        let opacityAnimation = CAKeyframeAnimation(keyPath: "opacity")
        opacityAnimation.values = opacities
        opacityAnimation.keyTimes = keyTimes
        opacityAnimation.duration = duration
        opacityAnimation.calculationMode = .linear
        pill.layer.add(opacityAnimation, forKey: "hayaseCrossfadeOpacity")
    }
}
