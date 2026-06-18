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
            return Self.makeDiagonalStripeTile(size: CGSize(width: 10, height: 10),
                                               angleDegrees: 40,
                                               segments: [
                                                   (.init(white: 17.0 / 255.0, alpha: 0.267), 0, 1),
                                                   (.init(white: 85.0 / 255.0, alpha: 0.267), 1, 5),
                                                   (.init(white: 17.0 / 255.0, alpha: 0.267), 6, 10),
                                               ])
        case .striped:
            return Self.makeDiagonalStripeTile(size: CGSize(width: 12, height: 12),
                                               angleDegrees: 45,
                                               segments: [
                                                   (UIColor(red: 0x20 / 255.0, green: 0x20 / 255.0, blue: 0x20 / 255.0, alpha: 1), 0, 6),
                                                   (UIColor(red: 0x2a / 255.0, green: 0x2a / 255.0, blue: 0x2a / 255.0, alpha: 1), 6, 12),
                                               ])
        case .stripedMuted:
            return Self.makeDiagonalStripeTile(size: CGSize(width: 12, height: 12),
                                               angleDegrees: 45,
                                               segments: [
                                                   (UIColor(red: 0x1e / 255.0, green: 0x1e / 255.0, blue: 0x1e / 255.0, alpha: 1), 0, 6),
                                                   (UIColor(red: 0x16 / 255.0, green: 0x16 / 255.0, blue: 0x16 / 255.0, alpha: 1), 6, 12),
                                               ])
        }
    }

    private static func makeDiagonalStripeTile(size: CGSize,
                                               angleDegrees: CGFloat,
                                               segments: [(UIColor, CGFloat, CGFloat)]) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            let cg = context.cgContext
            cg.translateBy(x: size.width / 2, y: size.height / 2)
            cg.rotate(by: angleDegrees * .pi / 180)
            cg.translateBy(x: -size.width / 2, y: -size.height / 2)

            for x in stride(from: -size.width * 2, through: size.width * 3, by: size.width) {
                for (color, start, end) in segments {
                    color.setFill()
                    cg.fill(CGRect(x: x + start,
                                   y: -size.height * 2,
                                   width: end - start,
                                   height: size.height * 5))
                }
            }
        }
    }
}
