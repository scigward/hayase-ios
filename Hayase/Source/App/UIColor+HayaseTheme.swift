//
//  UIColor+HayaseTheme.swift
//  Hayase
//

import UIKit

extension UIColor {
    enum HayaseTheme {
        /// interface theme-default: --background hsl(0 0% 0%).
        static let background = UIColor.black
        /// interface theme-default: --foreground hsl(0 0% 98%).
        static let foreground = UIColor(white: 0.98, alpha: 1)
        /// interface theme-default: --muted / --card hsl(0 0% 4%).
        static let muted = UIColor(white: 0.04, alpha: 1)
        static let card = UIColor(white: 0.04, alpha: 1)
        /// interface theme-default: --muted-foreground hsl(0 0% 50%).
        static let mutedForeground = UIColor(white: 0.5, alpha: 1)
        /// interface theme-default: --border hsl(0 0% 10%).
        static let border = UIColor(white: 0.10, alpha: 1)
        /// interface theme-default: --input hsl(0 0% 15%).
        static let input = UIColor(white: 0.15, alpha: 1)
        /// interface theme-default: --accent hsl(0 0% 8%).
        static let accent = UIColor(white: 0.08, alpha: 1)
    }
}
