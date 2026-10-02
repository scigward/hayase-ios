//
//  UIColor+HSL.swift
//  Hayase
//

import UIKit

extension UIColor {
    /// CSS `hsl(from <color> h s <lightness>)`: the same hue and saturation at another
    /// lightness, as tailwind.config.ts derives `bg-custom-600` from `--custom`.
    func withHSLLightness(_ lightness: CGFloat) -> UIColor {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        getRed(&red, green: &green, blue: &blue, alpha: &alpha)

        let high = max(red, green, blue)
        let low = min(red, green, blue)
        let chroma = high - low
        let currentLightness = (high + low) / 2
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        if chroma > 0 {
            saturation = chroma / (1 - abs(2 * currentLightness - 1))
            if high == red {
                hue = (green - blue) / chroma
                if hue < 0 { hue += 6 }
            } else if high == green {
                hue = (blue - red) / chroma + 2
            } else {
                hue = (red - green) / chroma + 4
            }
        }

        let newChroma = (1 - abs(2 * lightness - 1)) * saturation
        let x = newChroma * (1 - abs(hue.truncatingRemainder(dividingBy: 2) - 1))
        let (r, g, b): (CGFloat, CGFloat, CGFloat)
        switch Int(safe: Double(hue)) {
        case 0: (r, g, b) = (newChroma, x, 0)
        case 1: (r, g, b) = (x, newChroma, 0)
        case 2: (r, g, b) = (0, newChroma, x)
        case 3: (r, g, b) = (0, x, newChroma)
        case 4: (r, g, b) = (x, 0, newChroma)
        default: (r, g, b) = (newChroma, 0, x)
        }
        let match = lightness - newChroma / 2
        return UIColor(red: r + match, green: g + match, blue: b + match, alpha: alpha)
    }
}
