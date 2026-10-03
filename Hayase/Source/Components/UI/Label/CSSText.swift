//
//  CSSText.swift
//  Hayase
//
//  Mirrors: how the interface's CSS sets text. Every element has a `line-height` of its own, and
//  the glyphs sit in the middle of each line box.
//

import UIKit

enum CSSText {
    /// The attributes of text with a fixed line box. UIKit puts glyphs at the bottom of a line
    /// box, CSS centres them, hence the baseline offset.
    static func attributes(font: UIFont,
                           color: UIColor,
                           lineHeight: CGFloat,
                           alignment: NSTextAlignment = .natural,
                           lineBreak: NSLineBreakMode = .byTruncatingTail,
                           kern: CGFloat = 0) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = lineHeight
        paragraph.maximumLineHeight = lineHeight
        paragraph.alignment = alignment
        paragraph.lineBreakMode = lineBreak
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph,
            .baselineOffset: (lineHeight - font.lineHeight) / 2,
        ]
        if kern != 0 { attributes[.kern] = kern }
        return attributes
    }

    static func string(_ text: String,
                       font: UIFont,
                       color: UIColor,
                       lineHeight: CGFloat,
                       alignment: NSTextAlignment = .natural,
                       lineBreak: NSLineBreakMode = .byTruncatingTail,
                       kern: CGFloat = 0) -> NSAttributedString {
        NSAttributedString(string: text,
                           attributes: attributes(font: font, color: color, lineHeight: lineHeight,
                                                  alignment: alignment, lineBreak: lineBreak, kern: kern))
    }

    /// Collapses white space as an HTML element with `white-space: normal` does: every run of
    /// spaces, tabs and line feeds becomes one space (a no-break space stays).
    static func collapsingWhitespace(_ text: String) -> String {
        text.replacingOccurrences(of: #"[ \t\n\r\f]+"#, with: " ", options: .regularExpression)
    }
}
