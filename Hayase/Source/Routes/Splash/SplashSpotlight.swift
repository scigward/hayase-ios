//
//  SplashSpotlight.swift
//  Hayase
//
//  Mirrors: the six `.spotlight` elements of src/routes/+page.svelte
//
//    .spotlight {
//      filter: url('#chromaticAberration') blur(3px);
//      --dist-factor: calc((192 - min(var(--to-dist), 192)) / 192);
//      left: calc(var(--to-x) * 1px);  top: calc(var(--to-y) * 1px);
//      width: calc(var(--to-size) * 2.1px);  height: calc(var(--to-size) * 1px);
//      background: linear-gradient(to right, #fff, transparent);
//      opacity: calc(var(--dist-factor, 0) * var(--spotlight-opacity, 1));
//      transform: rotate(var(--to-angle)) perspective(calc(var(--to-size) * 2px)) rotateY(calc(var(--dist-factor) * -50deg - 20deg));
//      animation: spotlight-properties .1s ease-out .15s both, spotlight-fade .55s ease-out both;
//    }
//
//  with `origin-left` (the transform origin is the middle of the left edge), and the properties
//  running from their `--from-*` values to their `--to-*` ones. Each is a box of the gradient, drawn
//  twice, in the red and the cyan of the aberration, which are blurred 3px, held 4px right and 6px
//  left of each other until they meet at 0.25s, and put through the perspective.
//
//  What is not the same: the blur is made once, at the final size of the box, and the box is scaled for
//  the smaller one it starts as (the blur 3px grows with it), the offsets of the two colours are
//  scaled with it, and the filter's region (10% round the box) does not clip them.
//

import UIKit
import CoreImage

struct SplashSpotlightSpec {
    let toX: CGFloat
    let toY: CGFloat
    let toAngle: CGFloat
    let toSize: CGFloat
    let toDistance: CGFloat
    let fromX: CGFloat
    let fromY: CGFloat
    let fromDistance: CGFloat
    let fromAngle: CGFloat
    let fromSize: CGFloat

    /// `spotlightData`
    static let all: [SplashSpotlightSpec] = [
        .init(toX: 37, toY: 9, toAngle: -2.056662501122422, toSize: 8, toDistance: 15,
              fromX: 39, fromY: 9, fromDistance: 15, fromAngle: -2.08562414586023, fromSize: 5),
        .init(toX: 35.5, toY: 8.5, toAngle: -0.12083697915707219, toSize: 8, toDistance: 15,
              fromX: 35.5, fromY: 8.5, fromDistance: 15, fromAngle: -1.709436063929055, fromSize: 6),
        .init(toX: 9, toY: 13, toAngle: 3.0890095919788516, toSize: 16, toDistance: 15,
              fromX: 9, fromY: 13, fromDistance: 15, fromAngle: 1.6368324342229479, fromSize: 16),
        .init(toX: 24, toY: 12, toAngle: 2.1149541274082813, toSize: 20, toDistance: 15,
              fromX: 23, fromY: 11, fromDistance: 15, fromAngle: 1.6101247484847512, fromSize: 20),
        .init(toX: 32, toY: 20, toAngle: 1.07942520581382, toSize: 13, toDistance: 15,
              fromX: 35, fromY: 20, fromDistance: 15, fromAngle: 1.4487802605792384, fromSize: 13),
        .init(toX: 33, toY: 9, toAngle: -0.9299524305252777, toSize: 8, toDistance: 15,
              fromX: 33, fromY: 9, fromDistance: 15, fromAngle: -1.402804055149021, fromSize: 6),
    ]

    /// `--dist-factor` of a distance
    static func distanceFactor(_ distance: CGFloat) -> CGFloat {
        (192 - min(distance, 192)) / 192
    }
}

final class SplashSpotlightLayer {
    /// The layers of a spotlight hang off this one, which sits at the middle of the box's left edge.
    let root = CALayer()

    private let spec: SplashSpotlightSpec
    private let rotor = CALayer()
    private let scaler = CALayer()
    private let projector = CALayer()
    private let red = CALayer()
    private let cyan = CALayer()

    private static let blurRadius: CGFloat = 3
    private static let margin: CGFloat = 12     // room for the blur, which spreads about 3 radii
    private static let context = CIContext()

    /// `renderScale`: pixels to a point of the bitmaps. The logo is shown at five times its size to begin with, so they have the sharpness of that.
    init(spec: SplashSpotlightSpec, renderScale: CGFloat) {
        self.spec = spec
        let size = spec.toSize
        let width = size * 2.1
        let height = size
        let margin = Self.margin

        // The two layers hold the box in the red and the cyan of the filter, which is screened
        let frame = CGRect(x: -margin, y: -height / 2 - margin, width: width + 2 * margin, height: height + 2 * margin)
        for (layer, color) in [(red, UIColor(red: 1, green: 0, blue: 0, alpha: 1)), (cyan, UIColor(red: 0, green: 1, blue: 1, alpha: 1))] {
            layer.frame = frame
            layer.contents = Self.bitmap(width: width, height: height, color: color, scale: renderScale)
            layer.contentsGravity = .resize
            layer.minificationFilter = .trilinear
            layer.magnificationFilter = .linear
        }
        cyan.compositingFilter = "screenBlendMode"

        // transform: rotate(angle) perspective(size * 2px) rotateY(dist * -50deg - 20deg), the last one first
        let distance = SplashSpotlightSpec.distanceFactor(spec.toDistance)
        var perspective = CATransform3DIdentity
        perspective.m34 = -1 / (size * 2)
        let rotateY = CATransform3DMakeRotation((distance * -50 - 20) * .pi / 180, 0, 1, 0)
        projector.transform = CATransform3DConcat(rotateY, perspective)
        projector.addSublayer(red)
        projector.addSublayer(cyan)

        scaler.addSublayer(projector)
        rotor.addSublayer(scaler)
        root.addSublayer(rotor)

        // The model is the end of every animation
        root.position = CGPoint(x: spec.toX, y: spec.toY + size / 2)
        rotor.transform = CATransform3DMakeRotation(spec.toAngle, 0, 0, 1)
        root.opacity = 0
    }

    /// `linear-gradient(to right, #fff, transparent)` of a box, in a colour, blurred 3px.
    private static func bitmap(width: CGFloat, height: CGFloat, color: UIColor, scale: CGFloat) -> CGImage? {
        let pixels = CGSize(width: ceil((width + 2 * margin) * scale), height: ceil((height + 2 * margin) * scale))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: pixels, format: format).image { renderer in
            let context = renderer.cgContext
            context.scaleBy(x: scale, y: scale)
            let colors = [color.cgColor, color.withAlphaComponent(0).cgColor] as CFArray
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) else { return }
            context.clip(to: CGRect(x: margin, y: margin, width: width, height: height))
            context.drawLinearGradient(gradient, start: CGPoint(x: margin, y: 0), end: CGPoint(x: margin + width, y: 0), options: [])
        }
        guard let cgImage = image.cgImage else { return nil }
        let input = CIImage(cgImage: cgImage)
        let blurred = input.applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: blurRadius * scale])
        return context.createCGImage(blurred, from: input.extent) ?? cgImage
    }

    /// `animation: spotlight-properties .1s ease-out .15s both, spotlight-fade .55s ease-out both`, and the
    /// `<animate>` of the filter that brings the two colours together from 0.15s over 0.1s.
    func start(at now: CFTimeInterval) {
        let easeOut = CAMediaTimingFunction(controlPoints: 0, 0, 0.58, 1)
        let toSize = spec.toSize

        func add(_ layer: CALayer, _ keyPath: String, from: Any, to: Any, duration: TimeInterval, delay: TimeInterval,
                 timing: CAMediaTimingFunction) {
            let animation = CABasicAnimation(keyPath: keyPath)
            animation.fromValue = from
            animation.toValue = to
            animation.duration = duration
            animation.beginTime = layer.convertTime(now, from: nil) + delay
            animation.timingFunction = timing
            animation.fillMode = .both
            animation.isRemovedOnCompletion = false
            layer.add(animation, forKey: keyPath)
        }

        // The properties run from their `--from-*` values: the centre of the box's left edge, its angle, its size
        add(root, "position", from: NSValue(cgPoint: CGPoint(x: spec.fromX, y: spec.fromY + spec.fromSize / 2)),
            to: NSValue(cgPoint: CGPoint(x: spec.toX, y: spec.toY + toSize / 2)),
            duration: 0.1, delay: 0.15, timing: easeOut)
        add(rotor, "transform.rotation.z", from: spec.fromAngle, to: spec.toAngle, duration: 0.1, delay: 0.15, timing: easeOut)
        add(scaler, "transform.scale", from: spec.fromSize / toSize, to: 1, duration: 0.1, delay: 0.15, timing: easeOut)

        // opacity: dist-factor * spotlight-opacity, which runs from 1 to 0
        let distance = SplashSpotlightSpec.distanceFactor(spec.toDistance)
        add(root, "opacity", from: Float(distance), to: 0, duration: 0.55, delay: 0, timing: easeOut)

        // feOffset dx: red 4 to 0 and cyan -6 to 0, linear
        let linear = CAMediaTimingFunction(name: .linear)
        add(red, "transform.translation.x", from: 4, to: 0, duration: 0.1, delay: 0.15, timing: linear)
        add(cyan, "transform.translation.x", from: -6, to: 0, duration: 0.1, delay: 0.15, timing: linear)
    }
}
