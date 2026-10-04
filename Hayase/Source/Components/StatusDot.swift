//
//  StatusDot.swift
//  Hayase
//
//  Mirrors: src/lib/components/StatusDot.svelte: the dot of the status of a media in the viewer's list
//  (`inline-flex size-[0.55rem] me-1 rounded-full`), in the colour of the status.
//

import UIKit

enum StatusDot {
    /// `size-[0.55rem]`
    static let size: CGFloat = 8.8

    /// The colour of a status, which is the dot's and the check's: `CURRENT` is the default `variant`
    static func color(for status: String) -> UIColor {
        switch status {
        case "CURRENT": return UIColor(red: 61/255, green: 180/255, blue: 242/255, alpha: 1)
        case "PLANNING": return UIColor(red: 247/255, green: 154/255, blue: 99/255, alpha: 1)
        case "COMPLETED": return UIColor(red: 123/255, green: 213/255, blue: 85/255, alpha: 1)
        case "PAUSED": return UIColor(red: 250/255, green: 122/255, blue: 122/255, alpha: 1)
        case "REPEATING": return UIColor(red: 59/255, green: 174/255, blue: 234/255, alpha: 1)
        case "DROPPED": return UIColor(red: 200/255, green: 80/255, blue: 80/255, alpha: 1)
        case "PENDING": return UIColor(red: 180/255, green: 180/255, blue: 180/255, alpha: 1)
        default: return UIColor(red: 61/255, green: 180/255, blue: 242/255, alpha: 1)
        }
    }

    private static var images: [String: UIImage] = [:]

    static func image(for status: String) -> UIImage {
        if let image = images[status] { return image }
        let dotSize = CGSize(width: size, height: size)
        let image = UIGraphicsImageRenderer(size: dotSize).image { _ in
            color(for: status).setFill()
            UIBezierPath(ovalIn: CGRect(origin: .zero, size: dotSize)).fill()
        }
        images[status] = image
        return image
    }

    /// The dot in front of a title, which is inline: it sits on the baseline of the first line only, the text wraps
    /// beneath it, and `me-1` and the space that Svelte keeps between `{/if}` and the title are after it.
    static func prefix(for status: String, attributes: [NSAttributedString.Key: Any]) -> NSAttributedString {
        let dot = NSTextAttachment()
        dot.image = image(for: status)
        dot.bounds = CGRect(x: 0, y: 0, width: size, height: size)
        let attachment = NSMutableAttributedString(attachment: dot)
        var dotAttributes = attributes
        dotAttributes[.kern] = 4   // me-1
        attachment.addAttributes(dotAttributes, range: NSRange(location: 0, length: attachment.length))
        let result = NSMutableAttributedString(attributedString: attachment)
        result.append(NSAttributedString(string: " ", attributes: attributes))
        return result
    }
}
