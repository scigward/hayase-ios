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
        let layer = HayaseStripeRenderingLayer(pattern: self)
        layer.contentsScale = UIScreen.main.scale
        layer.needsDisplayOnBoundsChange = true
        return layer
    }

    func makeImage() -> UIImage {
        let spec = renderSpec
        return Self.makeRepeatingLinearGradientTile(size: spec.tileSize,
                                                    angleDegrees: spec.angleDegrees,
                                                    period: spec.period,
                                                    stops: spec.stops)
    }

    fileprivate var renderSpec: HayaseStripeRenderSpec {
        switch self {
        case .customBackground:
            return HayaseStripeRenderSpec(tileSize: CGSize(width: 120, height: 120),
                                          angleDegrees: 40,
                                          period: 10,
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
                                          stops: [
                                            (UIColor(red: 0x1e / 255.0, green: 0x1e / 255.0, blue: 0x1e / 255.0, alpha: 1), 0),
                                            (UIColor(red: 0x1e / 255.0, green: 0x1e / 255.0, blue: 0x1e / 255.0, alpha: 1), 6),
                                            (UIColor(red: 0x16 / 255.0, green: 0x16 / 255.0, blue: 0x16 / 255.0, alpha: 1), 6),
                                            (UIColor(red: 0x16 / 255.0, green: 0x16 / 255.0, blue: 0x16 / 255.0, alpha: 1), 12),
                                          ])
        }
    }

    private static func makeRepeatingLinearGradientTile(size: CGSize,
                                                        angleDegrees: CGFloat,
                                                        period: CGFloat,
                                                        stops: [(UIColor, CGFloat)]) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            let cg = context.cgContext
            let scale = UIScreen.main.scale
            let pixelWidth = Int(size.width * scale)
            let pixelHeight = Int(size.height * scale)
            let angle = angleDegrees * .pi / 180
            let dx = sin(angle)
            let dy = -cos(angle)

            for py in 0..<pixelHeight {
                for px in 0..<pixelWidth {
                    let x = CGFloat(px) / scale
                    let y = CGFloat(py) / scale
                    let projected = x * dx + y * dy
                    let position = positiveModulo(projected, period)
                    color(at: position, stops: stops).setFill()
                    cg.fill(CGRect(x: x, y: y, width: 1 / scale, height: 1 / scale))
                }
            }
        }
    }

    fileprivate static func positiveModulo(_ value: CGFloat, _ modulus: CGFloat) -> CGFloat {
        let remainder = value.truncatingRemainder(dividingBy: modulus)
        return remainder >= 0 ? remainder : remainder + modulus
    }

    fileprivate static func color(at position: CGFloat, stops: [(UIColor, CGFloat)]) -> UIColor {
        guard let first = stops.first else { return .clear }
        var previous = first
        for current in stops.dropFirst() {
            if position <= current.1 {
                let distance = current.1 - previous.1
                if distance <= 0 { return current.0 }
                let t = (position - previous.1) / distance
                return interpolate(previous.0, current.0, t: min(max(t, 0), 1))
            }
            previous = current
        }
        return stops.last?.0 ?? first.0
    }

    private static func interpolate(_ lhs: UIColor, _ rhs: UIColor, t: CGFloat) -> UIColor {
        var lr: CGFloat = 0, lg: CGFloat = 0, lb: CGFloat = 0, la: CGFloat = 0
        var rr: CGFloat = 0, rg: CGFloat = 0, rb: CGFloat = 0, ra: CGFloat = 0
        lhs.getRed(&lr, green: &lg, blue: &lb, alpha: &la)
        rhs.getRed(&rr, green: &rg, blue: &rb, alpha: &ra)
        return UIColor(red: lr + (rr - lr) * t,
                       green: lg + (rg - lg) * t,
                       blue: lb + (rb - lb) * t,
                       alpha: la + (ra - la) * t)
    }
}

fileprivate struct HayaseStripeRenderSpec {
    let tileSize: CGSize
    let angleDegrees: CGFloat
    let period: CGFloat
    let stops: [(UIColor, CGFloat)]
}

private final class HayaseStripeRenderingLayer: CALayer {
    private let spec: HayaseStripeRenderSpec

    init(pattern: HayaseStripePattern) {
        self.spec = pattern.renderSpec
        super.init()
        isOpaque = false
        setNeedsDisplay()
    }

    override init(layer: Any) {
        if let layer = layer as? HayaseStripeRenderingLayer {
            self.spec = layer.spec
        } else {
            self.spec = HayaseStripePattern.customBackground.renderSpec
        }
        super.init(layer: layer)
    }

    required init?(coder: NSCoder) {
        self.spec = HayaseStripePattern.customBackground.renderSpec
        super.init(coder: coder)
    }

    override func draw(in ctx: CGContext) {
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

        let periodStart = floor(minProjection / spec.period) * spec.period - spec.period
        let periodEnd = ceil(maxProjection / spec.period) * spec.period + spec.period
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
                      periodOrigin: periodOrigin,
                      perpendicularStart: perpendicularStart,
                      perpendicularHeight: perpendicularHeight)
            periodOrigin += spec.period
        }

        ctx.restoreGState()
    }

    private func drawStops(in ctx: CGContext,
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

    private func drawBand(in ctx: CGContext,
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
