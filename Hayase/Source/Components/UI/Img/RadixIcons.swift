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

    private static let downloadData = "M7.50005 1.04999C7.74858 1.04999 7.95005 1.25146 7.95005 1.49999V8.41359L10.1819 6.18179C10.3576 6.00605 10.6425 6.00605 10.8182 6.18179C10.994 6.35753 10.994 6.64245 10.8182 6.81819L7.81825 9.81819C7.64251 9.99392 7.35759 9.99392 7.18185 9.81819L4.18185 6.81819C4.00611 6.64245 4.00611 6.35753 4.18185 6.18179C4.35759 6.00605 4.64251 6.00605 4.81825 6.18179L7.05005 8.41359V1.49999C7.05005 1.25146 7.25152 1.04999 7.50005 1.04999ZM2.5 10C2.77614 10 3 10.2239 3 10.5V12C3 12.5539 3.44565 13 3.99635 13H11.0012C11.5529 13 12 12.5528 12 12V10.5C12 10.2239 12.2239 10 12.5 10C12.7761 10 13 10.2239 13 10.5V12C13 13.1041 12.1062 14 11.0012 14H3.99635C2.89019 14 2 13.103 2 12V10.5C2 10.2239 2.22386 10 2.5 10Z"

    /// Download: an arrow into a tray. With `strokeWidth` the glyph is also outlined by that much of the
    /// 15x15 box, as `stroke-width='0.5' stroke='currentColor'` does on the extension search's
    /// "already downloaded" mark.
    static func download(size: CGFloat, strokeWidth: CGFloat = 0) -> UIImage {
        render(downloadData, size: size, strokeWidth: strokeWidth)
    }

    /// File, the mark of a single episode in the extension search.
    static func file(size: CGFloat) -> UIImage {
        render("M3.5 2C3.22386 2 3 2.22386 3 2.5V12.5C3 12.7761 3.22386 13 3.5 13H11.5C11.7761 13 12 12.7761 12 12.5V6H8.5C8.22386 6 8 5.77614 8 5.5V2H3.5ZM9 2.70711L11.2929 5H9V2.70711ZM2 2.5C2 1.67157 2.67157 1 3.5 1H8.5C8.63261 1 8.75979 1.05268 8.85355 1.14645L12.8536 5.14645C12.9473 5.24021 13 5.36739 13 5.5V12.5C13 13.3284 12.3284 14 11.5 14H3.5C2.67157 14 2 13.3284 2 12.5V2.5Z",
               size: size)
    }

    private static let cache = NSCache<NSString, UIImage>()

    /// `fill-rule: evenodd` on a 15x15 view box, as a template image of `size` points.
    private static func render(_ data: String, size: CGFloat, strokeWidth: CGFloat = 0) -> UIImage {
        let side = max(size, 1)
        let key = "\(data.hashValue)@\(side)/\(strokeWidth)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let image = UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { renderer in
            let context = renderer.cgContext
            context.scaleBy(x: side / 15, y: side / 15)
            context.addPath(SVGPath.path(data))
            UIColor.black.setFill()
            if strokeWidth > 0 {
                // SVG strokes with a butt cap and a mitre join, which are the context's defaults
                UIColor.black.setStroke()
                context.setLineWidth(strokeWidth)
                context.drawPath(using: .eoFillStroke)
            } else {
                context.fillPath(using: .evenOdd)
            }
        }.withRenderingMode(.alwaysTemplate)
        cache.setObject(image, forKey: key)
        return image
    }
}
