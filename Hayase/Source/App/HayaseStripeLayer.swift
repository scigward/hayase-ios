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
        let layer = CALayer()
        layer.backgroundColor = UIColor(patternImage: makeImage()).cgColor
        return layer
    }

    func makeImage() -> UIImage {
        switch self {
        case .customBackground:
            return Self.makeRepeatingLinearGradientTile(size: CGSize(width: 120, height: 120),
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
            return Self.makeRepeatingLinearGradientTile(size: CGSize(width: 119, height: 119),
                                                        angleDegrees: 45,
                                                        period: 12,
                                                        stops: [
                                                            (UIColor(red: 0x20 / 255.0, green: 0x20 / 255.0, blue: 0x20 / 255.0, alpha: 1), 0),
                                                            (UIColor(red: 0x20 / 255.0, green: 0x20 / 255.0, blue: 0x20 / 255.0, alpha: 1), 6),
                                                            (UIColor(red: 0x2a / 255.0, green: 0x2a / 255.0, blue: 0x2a / 255.0, alpha: 1), 6),
                                                            (UIColor(red: 0x2a / 255.0, green: 0x2a / 255.0, blue: 0x2a / 255.0, alpha: 1), 12),
                                                        ])
        case .stripedMuted:
            return Self.makeRepeatingLinearGradientTile(size: CGSize(width: 119, height: 119),
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
            let scale = renderer.format.scale
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

    private static func positiveModulo(_ value: CGFloat, _ modulus: CGFloat) -> CGFloat {
        let remainder = value.truncatingRemainder(dividingBy: modulus)
        return remainder >= 0 ? remainder : remainder + modulus
    }

    private static func color(at position: CGFloat, stops: [(UIColor, CGFloat)]) -> UIColor {
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
