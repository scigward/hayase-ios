//
//  Transition.swift
//  Hayase
//
//  Mirrors: src/lib/components/ui/button/transition.svelte: a button whose icon is swapped for another with
//  `scaleBlurFade`, held for a moment and swapped back (the share button, which shows a check once the link is
//  copied).
//

import UIKit

extension SelectButton {
    /// TransitionButton: the icon is swapped for another with `scaleBlurFade`, held, and
    /// swapped back. Each icon scales and blurs as it fades, over 300ms with cubicOut.
    func swapIcon(to image: UIImage?, hold: TimeInterval) {
        guard let imageView, let base = imageView.image, let image, !isSwappingIcon else { return }
        isSwappingIcon = true
        let tint = self.tintColor ?? UIColor.HayaseTheme.foreground
        let padding = Self.swapBlurRadius * 3
        let frame = imageView.frame.insetBy(dx: -padding, dy: -padding)

        func makeLayer(_ image: UIImage) -> (layer: CALayer, frames: [CGImage]) {
            let frames = Self.blurFrames(of: image, tint: tint, padding: padding)
            let layer = CALayer()
            layer.frame = frame
            layer.contents = frames.first
            layer.contentsScale = UIScreen.main.scale
            return (layer, frames)
        }
        let outgoing = makeLayer(base)
        let incoming = makeLayer(image)
        incoming.layer.opacity = 0
        self.layer.addSublayer(outgoing.layer)
        self.layer.addSublayer(incoming.layer)
        imageView.alpha = 0

        func scaleBlurFade(_ layer: CALayer, frames: [CGImage], entering: Bool) {
            let group = CAAnimationGroup()
            let timing = CAMediaTimingFunction(controlPoints: 0.33, 1, 0.68, 1)   // cubicOut
            let (from, to): (Float, Float) = entering ? (0, 1) : (1, 0)
            let opacity = CABasicAnimation(keyPath: "opacity")
            opacity.fromValue = from
            opacity.toValue = to
            let scale = CABasicAnimation(keyPath: "transform.scale")
            scale.fromValue = max(from, 0.001)
            scale.toValue = max(to, 0.001)
            let blur = CAKeyframeAnimation(keyPath: "contents")
            let ordered = entering ? Array(frames.reversed()) : frames
            blur.values = ordered
            blur.keyTimes = (0..<ordered.count).map { NSNumber(value: Double($0) / Double(max(1, ordered.count - 1))) }
            blur.calculationMode = .discrete
            group.animations = [opacity, scale, blur]
            group.duration = 0.3
            group.timingFunction = timing
            layer.add(group, forKey: "scaleBlurFade")
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.opacity = to
            layer.transform = CATransform3DMakeScale(CGFloat(max(to, 0.001)), CGFloat(max(to, 0.001)), 1)
            layer.contents = entering ? frames.first : frames.last
            CATransaction.commit()
        }

        scaleBlurFade(outgoing.layer, frames: outgoing.frames, entering: false)
        scaleBlurFade(incoming.layer, frames: incoming.frames, entering: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + hold) { [weak self] in
            scaleBlurFade(incoming.layer, frames: incoming.frames, entering: false)
            scaleBlurFade(outgoing.layer, frames: outgoing.frames, entering: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                outgoing.layer.removeFromSuperlayer()
                incoming.layer.removeFromSuperlayer()
                imageView.alpha = 1
                self?.isSwappingIcon = false
            }
        }
    }

    /// blur(4px) at the start of the swap, in points.
    static let swapBlurRadius: CGFloat = 4

    /// The icon in `tint` at each blur from none up to `swapBlurRadius`, on a canvas with room
    /// for the blur to spread.
    static func blurFrames(of image: UIImage, tint: UIColor, padding: CGFloat) -> [CGImage] {
        let scale = UIScreen.main.scale
        let size = CGSize(width: image.size.width + 2 * padding, height: image.size.height + 2 * padding)
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        let tinted = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.withTintColor(tint, renderingMode: .alwaysOriginal)
                .draw(at: CGPoint(x: padding, y: padding))
        }
        guard let cgImage = tinted.cgImage else { return [] }
        let input = CIImage(cgImage: cgImage)
        let context = CIContext()
        let steps = 8
        return (0...steps).compactMap { step in
            guard step > 0 else { return cgImage }
            let output = input.applyingFilter("CIGaussianBlur",
                parameters: [kCIInputRadiusKey: swapBlurRadius * CGFloat(step) / CGFloat(steps) * scale])
            return context.createCGImage(output, from: input.extent)
        }
    }
}
