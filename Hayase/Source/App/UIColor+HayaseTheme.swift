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
        /// interface theme-default: --secondary hsl(240 3.7% 15.9%).
        static let secondary = UIColor(red: 0.153, green: 0.153, blue: 0.165, alpha: 1)
        /// interface theme-default: --secondary-foreground hsl(0 0% 98%).
        static let secondaryForeground = UIColor(white: 0.98, alpha: 1)
        /// interface theme-default: --primary hsl(0 0% 98%).
        static let primary = UIColor(white: 0.98, alpha: 1)
        /// interface theme-default: --primary-foreground hsl(0 0% 10%).
        static let primaryForeground = UIColor(white: 0.10, alpha: 1)
        /// interface theme-default: --destructive hsl(0 62.8% 30.6%).
        static let destructive = UIColor(red: 0.498, green: 0.114, blue: 0.114, alpha: 1)
        /// interface theme-default: --destructive-foreground hsl(0 0% 98%).
        static let destructiveForeground = UIColor(white: 0.98, alpha: 1)
    }
}
