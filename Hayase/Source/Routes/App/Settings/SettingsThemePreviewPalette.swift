// Mirrors: src/app.css (.theme-*). These are preview swatches, not theme activation.
import UIKit

struct SettingsThemePreviewPalette {
    let background: UIColor
    let foreground: UIColor
    let muted: UIColor
    let mutedForeground: UIColor
    let primary: UIColor
    let primaryForeground: UIColor
    let secondary: UIColor
    let input: UIColor

    static func named(_ name: String) -> Self {
        switch name {
        case "Whiteout": return Self(background: .white, foreground: .black, muted: hsl(0, 0, 92.16), mutedForeground: hsl(0, 0, 27.8431),
            primary: .black, primaryForeground: .white, secondary: hsl(0, 0, 88.2353), input: hsl(0, 0, 66.6667))
        case "Catppuccin": return Self(background: hsl(240, 21, 15), foreground: hsl(226, 64, 88), muted: hsl(240, 23, 9), mutedForeground: hsl(228, 24, 72),
            primary: hsl(23, 92, 75), primaryForeground: hsl(240, 23, 9), secondary: hsl(234, 13, 31), input: hsl(234, 13, 31))
        case "Dracula": return Self(background: hsl(231, 15, 18), foreground: hsl(60, 30, 96), muted: hsl(225, 15, 24), mutedForeground: hsl(225, 27, 51),
            primary: hsl(265, 89, 78), primaryForeground: hsl(232, 14, 11), secondary: hsl(235, 14, 15), input: hsl(232, 14, 31))
        case "Amber": return Self(background: hsl(38, 20, 2), foreground: hsl(0, 0, 96), muted: hsl(38, 20, 6), mutedForeground: hsl(0, 0, 55),
            primary: hsl(38, 92, 50), primaryForeground: hsl(0, 0, 10), secondary: hsl(38, 30, 18), input: hsl(38, 15, 18))
        case "Lavender": return Self(background: hsl(270, 15, 2), foreground: hsl(0, 0, 96), muted: hsl(270, 15, 6), mutedForeground: hsl(0, 0, 55),
            primary: hsl(270, 70, 60), primaryForeground: hsl(0, 0, 98), secondary: hsl(270, 30, 18), input: hsl(270, 15, 18))
        // Preview the web defaults; theme activation/editing remains intentionally unsupported.
        case "Custom": return Self(background: .black, foreground: rgb(0xfa), muted: rgb(0x0a), mutedForeground: rgb(0x7f),
            primary: rgb(0xfa), primaryForeground: rgb(0x1a), secondary: rgb(0x2a), input: rgb(0x33))
        default: return Self(background: UIColor.HayaseTheme.background, foreground: UIColor.HayaseTheme.foreground,
            muted: UIColor.HayaseTheme.muted,
            mutedForeground: UIColor.HayaseTheme.mutedForeground, primary: UIColor.HayaseTheme.primary,
            primaryForeground: UIColor.HayaseTheme.primaryForeground, secondary: UIColor.HayaseTheme.secondary,
            input: UIColor.HayaseTheme.input)
        }
    }

    private static func rgb(_ white: Int) -> UIColor {
        UIColor(white: CGFloat(white) / 255, alpha: 1)
    }

    private static func hsl(_ hue: CGFloat, _ saturation: CGFloat, _ lightness: CGFloat) -> UIColor {
        let s = saturation / 100, l = lightness / 100
        let brightness = l + s * min(l, 1 - l)
        return UIColor(hue: hue / 360, saturation: brightness == 0 ? 0 : 2 * (1 - l / brightness),
                       brightness: brightness, alpha: 1)
    }
}
