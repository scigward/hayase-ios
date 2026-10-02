//
//  RadixIcons.swift
//  Hayase
//
//  The icons the interface takes from `svelte-radix`, drawn from their own 15x15 geometry.
//

import UIKit

enum RadixIcons {
    /// MagnifyingGlass, which the search page's input and every command input use.
    static func magnifyingGlass(size: CGFloat) -> UIImage {
        render("M10 6.5C10 8.433 8.433 10 6.5 10C4.567 10 3 8.433 3 6.5C3 4.567 4.567 3 6.5 3C8.433 3 10 4.567 10 6.5ZM9.30884 10.0159C8.53901 10.6318 7.56251 11 6.5 11C4.01472 11 2 8.98528 2 6.5C2 4.01472 4.01472 2 6.5 2C8.98528 2 11 4.01472 11 6.5C11 7.56251 10.6318 8.53901 10.0159 9.30884L12.8536 12.1464C13.0488 12.3417 13.0488 12.6583 12.8536 12.8536C12.6583 13.0488 12.3417 13.0488 12.1464 12.8536L9.30884 10.0159Z",
               size: size)
    }

    /// CaretSort, the combobox's up and down carets.
    static func caretSort(size: CGFloat) -> UIImage {
        render("M4.93179 5.43179C4.75605 5.60753 4.75605 5.89245 4.93179 6.06819C5.10753 6.24392 5.39245 6.24392 5.56819 6.06819L7.49999 4.13638L9.43179 6.06819C9.60753 6.24392 9.89245 6.24392 10.0682 6.06819C10.2439 5.89245 10.2439 5.60753 10.0682 5.43179L7.81819 3.18179C7.73379 3.0974 7.61933 3.04999 7.49999 3.04999C7.38064 3.04999 7.26618 3.0974 7.18179 3.18179L4.93179 5.43179ZM10.0682 9.56819C10.2439 9.39245 10.2439 9.10753 10.0682 8.93179C9.89245 8.75606 9.60753 8.75606 9.43179 8.93179L7.49999 10.8636L5.56819 8.93179C5.39245 8.75606 5.10753 8.75606 4.93179 8.93179C4.75605 9.10753 4.75605 9.39245 4.93179 9.56819L7.18179 11.8182C7.35753 11.9939 7.64245 11.9939 7.81819 11.8182L10.0682 9.56819Z",
               size: size)
    }

    /// Check, the mark in a command item's box.
    static func check(size: CGFloat) -> UIImage {
        render("M11.4669 3.72684C11.7558 3.91574 11.8369 4.30308 11.648 4.59198L7.39799 11.092C7.29783 11.2452 7.13556 11.3467 6.95402 11.3699C6.77247 11.3931 6.58989 11.3355 6.45446 11.2124L3.70446 8.71241C3.44905 8.48022 3.43023 8.08494 3.66242 7.82953C3.89461 7.57412 4.28989 7.55529 4.5453 7.78749L6.75292 9.79441L10.6018 3.90792C10.7907 3.61902 11.178 3.53795 11.4669 3.72684Z",
               size: size)
    }

    private static let cache = NSCache<NSString, UIImage>()

    /// `fill-rule: evenodd` on a 15x15 view box, as a template image of `size` points.
    private static func render(_ data: String, size: CGFloat) -> UIImage {
        let side = max(size, 1)
        let key = "\(data.hashValue)@\(side)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let image = UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { renderer in
            let context = renderer.cgContext
            context.scaleBy(x: side / 15, y: side / 15)
            context.addPath(SVGPath.path(data))
            UIColor.black.setFill()
            context.fillPath(using: .evenOdd)
        }.withRenderingMode(.alwaysTemplate)
        cache.setObject(image, forKey: key)
        return image
    }
}
