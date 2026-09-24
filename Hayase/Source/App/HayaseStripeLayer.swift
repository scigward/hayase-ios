//
//  HayaseStripeLayer.swift
//  Hayase
//
//  Made by scigward.
//
//  Mirrors: src/app.css custom-bg, bg-striped, and bg-striped-muted.
//

import UIKit

enum HayaseStripePattern {
    case customBackground
    case striped
    case stripedMuted

    func makeLayer() -> CALayer {
        let layer = HayaseStripeTiledLayer(pattern: self)
        layer.contentsScale = UIScreen.main.scale
        layer.drawsAsynchronously = true
        return layer
    }

    func makeImage() -> UIImage {
        Self.cachedTile(for: self, scale: UIScreen.main.scale)
    }

    fileprivate var renderSpec: HayaseStripeRenderSpec {
        switch self {
        case .customBackground:
            return HayaseStripeRenderSpec(tileSize: CGSize(width: 120, height: 120),
                                          angleDegrees: 40,
                                          period: 10,
                                          horizontalCycles: 8,
                                          verticalCycles: 9,
                                          stops: [
                                            (.init(white: 17.0 / 255.0, alpha: 4.0 / 15.0), 0),
                                            (.init(white: 85.0 / 255.0, alpha: 4.0 / 15.0), 1),
                                            (.init(white: 85.0 / 255.0, alpha: 4.0 / 15.0), 5),
                                            (.init(white: 17.0 / 255.0, alpha: 4.0 / 15.0), 6),
                                            (.init(white: 17.0 / 255.0, alpha: 4.0 / 15.0), 10),
                                          ])
        case .striped:
            return HayaseStripeRenderSpec(tileSize: CGSize(width: 119, height: 119),
                                          angleDegrees: 45,
                                          period: 12,
                                          horizontalCycles: 7,
                                          verticalCycles: 7,
                                          stops: [
                                            (UIColor(red: 0x20 / 255.0, green: 0x20 / 255.0, blue: 0x20 / 255.0, alpha: 1), 0),
                                            (UIColor(red: 0x20 / 255.0, green: 0x20 / 255.0, blue: 0x20 / 255.0, alpha: 1), 6),
                                            (UIColor(red: 0x2a / 255.0, green: 0x2a / 255.0, blue: 0x2a / 255.0, alpha: 1), 6),
                                            (UIColor(red: 0x2a / 255.0, green: 0x2a / 255.0, blue: 0x2a / 255.0, alpha: 1), 12),
                                          ])
        case .stripedMuted:
            return HayaseStripeRenderSpec(tileSize: CGSize(width: 119, height: 119),
                                          angleDegrees: 45,
                                          period: 12,
                                          horizontalCycles: 7,
                                          verticalCycles: 7,
                                          stops: [
                                            (UIColor(red: 0x1e / 255.0, green: 0x1e / 255.0, blue: 0x1e / 255.0, alpha: 1), 0),
                                            (UIColor(red: 0x1e / 255.0, green: 0x1e / 255.0, blue: 0x1e / 255.0, alpha: 1), 6),
                                            (UIColor(red: 0x16 / 255.0, green: 0x16 / 255.0, blue: 0x16 / 255.0, alpha: 1), 6),
                                            (UIColor(red: 0x16 / 255.0, green: 0x16 / 255.0, blue: 0x16 / 255.0, alpha: 1), 12),
                                          ])
        }
    }

    private var cacheKey: String {
        switch self {
        case .customBackground: return "customBackground"
        case .striped: return "striped"
        case .stripedMuted: return "stripedMuted"
        }
    }

    private static var tileCache: [String: UIImage] = [:]
    private static let tileCacheQueue = DispatchQueue(label: "hayase.stripe.tile-cache")

    fileprivate static func cachedTile(for pattern: HayaseStripePattern, scale: CGFloat) -> UIImage {
        let spec = pattern.renderSpec
        let key = "\(pattern.cacheKey)-\(scale)"

        if let cached = tileCacheQueue.sync(execute: { tileCache[key] }) {
            return cached
        }

        let image = makeRepeatingLinearGradientTile(size: spec.tileSize,
                                                    scale: scale,
                                                    spec: spec)
        tileCacheQueue.sync {
            tileCache[key] = image
        }
        return image
    }

    private static func makeRepeatingLinearGradientTile(size: CGSize,
                                                        scale: CGFloat,
                                                        spec: HayaseStripeRenderSpec) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false

        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { context in
            drawPattern(in: context.cgContext,
                        bounds: CGRect(origin: .zero, size: size),
                        spec: spec)
        }
    }

    fileprivate static func drawPattern(in ctx: CGContext,
                                        bounds: CGRect,
                                        spec: HayaseStripeRenderSpec) {
        guard bounds.width > 0,
              bounds.height > 0,
              spec.period > 0,
              spec.stops.count > 1 else { return }

        let angle = spec.angleDegrees * .pi / 180
        let dx = sin(angle)
        let dy = -cos(angle)
        let perpendicularX = -dy
        let perpendicularY = dx
        let corners = [
            CGPoint(x: bounds.minX, y: bounds.minY),
            CGPoint(x: bounds.maxX, y: bounds.minY),
            CGPoint(x: bounds.minX, y: bounds.maxY),
            CGPoint(x: bounds.maxX, y: bounds.maxY)
        ]

        let projectedCorners = corners.map { $0.x * dx + $0.y * dy }
        let perpendicularCorners = corners.map { $0.x * perpendicularX + $0.y * perpendicularY }
        guard let minProjection = projectedCorners.min(),
              let maxProjection = projectedCorners.max(),
              let minPerpendicular = perpendicularCorners.min(),
              let maxPerpendicular = perpendicularCorners.max() else { return }

        // CSS starts the gradient line at the corner projection, not at
        // an arbitrary world-space zero. Keep its phase when the view resizes.
        let periodStart = minProjection
        let periodEnd = maxProjection + spec.period
        let perpendicularPadding = hypot(bounds.width, bounds.height)
        let perpendicularStart = minPerpendicular - perpendicularPadding
        let perpendicularHeight = maxPerpendicular - minPerpendicular + perpendicularPadding * 2

        ctx.saveGState()
        ctx.clip(to: bounds)
        ctx.concatenate(CGAffineTransform(a: dx,
                                          b: dy,
                                          c: perpendicularX,
                                          d: perpendicularY,
                                          tx: 0,
                                          ty: 0))

        var periodOrigin = periodStart
        while periodOrigin <= periodEnd {
            drawStops(in: ctx,
                      spec: spec,
                      periodOrigin: periodOrigin,
                      perpendicularStart: perpendicularStart,
                      perpendicularHeight: perpendicularHeight)
            periodOrigin += spec.period
        }

        ctx.restoreGState()
    }

    private static func drawStops(in ctx: CGContext,
                                  spec: HayaseStripeRenderSpec,
                                  periodOrigin: CGFloat,
                                  perpendicularStart: CGFloat,
                                  perpendicularHeight: CGFloat) {
        var previous = spec.stops[0]
        for current in spec.stops.dropFirst() {
            let start = periodOrigin + previous.1
            let end = periodOrigin + current.1
            let width = end - start
            guard width > 0 else {
                previous = current
                continue
            }

            let rect = CGRect(x: start,
                              y: perpendicularStart,
                              width: width,
                              height: perpendicularHeight)
            drawBand(in: ctx,
                     rect: rect,
                     startColor: previous.0,
                     endColor: current.0)
            previous = current
        }
    }

    private static func drawBand(in ctx: CGContext,
                                 rect: CGRect,
                                 startColor: UIColor,
                                 endColor: UIColor) {
        if startColor.isVisuallyEqual(to: endColor) {
            ctx.setFillColor(startColor.cgColor)
            ctx.fill(rect)
            return
        }

        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                        colors: [startColor.cgColor, endColor.cgColor] as CFArray,
                                        locations: [0, 1]) else { return }
        ctx.saveGState()
        ctx.clip(to: rect)
        ctx.drawLinearGradient(gradient,
                               start: CGPoint(x: rect.minX, y: rect.midY),
                               end: CGPoint(x: rect.maxX, y: rect.midY),
                               options: [])
        ctx.restoreGState()
    }
}

/// Shared visual for Hayase `custom-bg backdrop-blur-sm` surfaces.
///
/// Keep the blur with the striped backdrop so every place that enables the
/// stripe effect gets the same interface-style backdrop treatment.
final class HayaseStripedBackdropView: UIView {
    private let blurView: UIVisualEffectView = {
        let view = UIVisualEffectView(effect: nil)
        view.isUserInteractionEnabled = false
        return view
    }()

    private let stripeLayer: CALayer
    private var blurAnimator: UIViewPropertyAnimator?
    private var blurIntensity: CGFloat = 0.15

    init(pattern: HayaseStripePattern = .customBackground,
         dimColor: UIColor? = nil,
         blurAlpha: CGFloat = 0.15) {
        self.stripeLayer = pattern.makeLayer()
        super.init(frame: .zero)
        backgroundColor = dimColor ?? .clear
        addSubview(blurView)
        layer.addSublayer(stripeLayer)
        blurIntensity = min(max(blurAlpha, 0), 1)
    }

    required init?(coder: NSCoder) {
        self.stripeLayer = HayaseStripePattern.customBackground.makeLayer()
        super.init(coder: coder)
        backgroundColor = .clear
        addSubview(blurView)
        layer.addSublayer(stripeLayer)
    }

    private func configureBlur(intensity: CGFloat) {
        guard !UIAccessibility.isReduceTransparencyEnabled else { return }
        // Keep the backdrop live. Fading a fully blurred view blends sharp
        // pixels back in and creates double edges instead of a small blur.
        // UIKit has no public CSS blur-radius API; this is a light native blur.
        let animator = UIViewPropertyAnimator(duration: 1, curve: .linear) { [weak self] in
            self?.blurView.effect = UIBlurEffect(style: .regular)
        }
        animator.startAnimation()
        animator.pauseAnimation()
        animator.fractionComplete = intensity
        blurAnimator = animator
    }

    deinit { blurAnimator?.stopAnimation(true) }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        blurAnimator?.stopAnimation(true)
        blurAnimator = nil
        blurView.effect = nil
        if window != nil { configureBlur(intensity: blurIntensity) }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        blurView.frame = bounds
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        stripeLayer.frame = bounds
        CATransaction.commit()
    }
}

fileprivate struct HayaseStripeRenderSpec {
    let tileSize: CGSize
    let angleDegrees: CGFloat
    let period: CGFloat
    let horizontalCycles: CGFloat
    let verticalCycles: CGFloat
    let stops: [(UIColor, CGFloat)]

    var seamlessTileSize: CGSize {
        let angle = angleDegrees * .pi / 180
        let dx = abs(sin(angle))
        let dy = abs(cos(angle))
        return CGSize(width: dx > 0.001 ? period * horizontalCycles / dx : tileSize.width,
                      height: dy > 0.001 ? period * verticalCycles / dy : tileSize.height)
    }
}

private final class HayaseStripeTiledLayer: CALayer {
    private let pattern: HayaseStripePattern

    init(pattern: HayaseStripePattern) {
        self.pattern = pattern
        super.init()
        isOpaque = false
        needsDisplayOnBoundsChange = true
    }

    override init(layer: Any) {
        if let layer = layer as? HayaseStripeTiledLayer {
            self.pattern = layer.pattern
        } else {
            self.pattern = .customBackground
        }
        super.init(layer: layer)
    }

    required init?(coder: NSCoder) {
        self.pattern = .customBackground
        super.init(coder: coder)
    }

    override func draw(in ctx: CGContext) {
        guard bounds.width > 0,
              bounds.height > 0 else { return }

        if case .customBackground = pattern {
            // custom-bg has no CSS background-size. Draw its exact 40-degree,
            // 10-point repeat directly, avoiding fractional raster tile seams.
            HayaseStripePattern.drawPattern(in: ctx, bounds: bounds, spec: pattern.renderSpec)
            return
        }
        let tile = HayaseStripePattern.cachedTile(for: pattern, scale: contentsScale)
        guard let cgImage = tile.cgImage else { return }

        ctx.saveGState()
        ctx.clip(to: bounds)
        ctx.interpolationQuality = .none

        let tileSize = tile.size
        var y = floor(bounds.minY / tileSize.height) * tileSize.height
        while y < bounds.maxY {
            var x = floor(bounds.minX / tileSize.width) * tileSize.width
            while x < bounds.maxX {
                draw(cgImage, in: CGRect(origin: CGPoint(x: x, y: y), size: tileSize), context: ctx)
                x += tileSize.width
            }
            y += tileSize.height
        }

        ctx.restoreGState()
    }

    private func draw(_ image: CGImage, in rect: CGRect, context ctx: CGContext) {
        ctx.saveGState()
        ctx.translateBy(x: rect.minX, y: rect.minY + rect.height)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(image, in: CGRect(origin: .zero, size: rect.size))
        ctx.restoreGState()
    }
}

private extension UIColor {
    func isVisuallyEqual(to other: UIColor) -> Bool {
        var lhsRed: CGFloat = 0
        var lhsGreen: CGFloat = 0
        var lhsBlue: CGFloat = 0
        var lhsAlpha: CGFloat = 0
        var rhsRed: CGFloat = 0
        var rhsGreen: CGFloat = 0
        var rhsBlue: CGFloat = 0
        var rhsAlpha: CGFloat = 0

        guard getRed(&lhsRed, green: &lhsGreen, blue: &lhsBlue, alpha: &lhsAlpha),
              other.getRed(&rhsRed, green: &rhsGreen, blue: &rhsBlue, alpha: &rhsAlpha) else {
            return false
        }

        return lhsRed == rhsRed &&
               lhsGreen == rhsGreen &&
               lhsBlue == rhsBlue &&
               lhsAlpha == rhsAlpha
    }
}
