//
//  TextShadowLabel.swift
//  Hayase
//
//  Mirrors: interface app.css `.text-shadow-lg`.
//

import UIKit

/// A label with the interface's `text-shadow-lg`: three 10% black shadows, at (0 1px 2px),
/// (0 3px 2px) and (0 4px 8px). Line height is set explicitly because the interface sets it
/// per element (`leading-tight`, `text-xs`, ...) rather than using the font's own.
final class TextShadowLabel: UILabel {
    private static let shadows: [(offset: CGFloat, blur: CGFloat)] = [(1, 2), (3, 2), (4, 8)]

    /// Room below the text for the shadows, so they are not cut off at the label's edge.
    private static let bleed: CGFloat = 12

    /// Single-line CSS elements use the declared line box for layout; glyphs
    /// and shadows may paint outside it. Opt in without changing home wrapping.
    var usesFixedLineBox = false {
        didSet {
            invalidateIntrinsicContentSize()
            setNeedsDisplay()
        }
    }

    var lineHeight: CGFloat = 0 {
        didSet { applyStyle(); invalidateIntrinsicContentSize() }
    }

    /// Plain text; use this instead of `text` so the line height applies.
    var content: String? {
        didSet { applyStyle() }
    }

    var underlinesText = false {
        didSet { applyStyle() }
    }

    override var font: UIFont! {
        didSet { applyStyle() }
    }

    override var textAlignment: NSTextAlignment {
        didSet { applyStyle() }
    }

    override var textColor: UIColor! {
        didSet { applyStyle() }
    }

    /// Assigning `attributedText` makes UILabel echo font, colour and alignment back through
    /// the observers above.
    private var isStyling = false

    private func applyStyle() {
        guard !isStyling else { return }
        isStyling = true
        defer { isStyling = false }
        guard let content, let font, lineHeight > 0 else {
            attributedText = nil
            text = content
            return
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = lineHeight
        paragraph.maximumLineHeight = lineHeight
        paragraph.alignment = textAlignment
        paragraph.lineBreakMode = lineBreakMode
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor ?? UIColor.label,
            .paragraphStyle: paragraph,
            // UIKit puts the text at the bottom of its line box, CSS centres it.
            .baselineOffset: (lineHeight - font.lineHeight) / 2,
        ]
        if underlinesText {
            attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
            attributes[.underlineColor] = textColor ?? UIColor.label
        }
        attributedText = NSAttributedString(string: content, attributes: attributes)
    }

    // MARK: - Shadow drawing

    /// Layout sees the text's own box; the bleed hangs below it.
    override var alignmentRectInsets: UIEdgeInsets {
        if usesFixedLineBox && numberOfLines == 1 && lineHeight > 0 {
            // CSS leading-none can be shorter than the font's ascenders. Keep
            // room for accents and side shadows without increasing row gaps.
            return UIEdgeInsets(top: Self.bleed, left: Self.bleed, bottom: Self.bleed, right: Self.bleed)
        }
        return UIEdgeInsets(top: 0, left: 0, bottom: Self.bleed, right: 0)
    }

    override var intrinsicContentSize: CGSize {
        var size = super.intrinsicContentSize
        if usesFixedLineBox && numberOfLines == 1 && lineHeight > 0 {
            // Intrinsic size describes the alignment rect. Auto Layout adds
            // the drawing bleed to the frame, outside the CSS line box.
            size.height = (text?.isEmpty ?? true) ? 0 : lineHeight
        }
        return size
    }

    override func textRect(forBounds bounds: CGRect, limitedToNumberOfLines numberOfLines: Int) -> CGRect {
        super.textRect(forBounds: bounds.inset(by: alignmentRectInsets),
                       limitedToNumberOfLines: numberOfLines)
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        if usesFixedLineBox && numberOfLines == 1 && lineHeight > 0 {
            // Painted shadow overflow does not enlarge a CSS link's hit box.
            return bounds.inset(by: alignmentRectInsets).contains(point)
        }
        return super.point(inside: point, with: event)
    }

    override func drawText(in rect: CGRect) {
        // UILabel draws into this rect independently of textRect(forBounds:).
        // Drawing into the shadow bleed centers text 6pt too low relative to
        // adjacent icons and changes the apparent gaps between stacked lines.
        let textRect = usesFixedLineBox && numberOfLines == 1 && lineHeight > 0
            ? bounds.inset(by: alignmentRectInsets)
            : rect
        guard let context = UIGraphicsGetCurrentContext() else {
            super.drawText(in: textRect)
            return
        }
        // A shadow follows the alpha of what casts it, while CSS shadows ignore the text's
        // own opacity; scale the shadow up to cancel it out.
        let textAlpha = max(textColor.cgColor.alpha, 0.01)
        let color = UIColor.black.withAlphaComponent(min(0.1 / textAlpha, 1)).cgColor
        // The glyphs are drawn far off to one side, and the shadow offset brings only the
        // shadow back, so the text itself is painted once, on top.
        let away: CGFloat = 10_000
        for shadow in Self.shadows {
            context.saveGState()
            context.translateBy(x: -away, y: 0)
            context.setShadow(offset: CGSize(width: away, height: shadow.offset), blur: shadow.blur, color: color)
            super.drawText(in: textRect)
            context.restoreGState()
        }
        super.drawText(in: textRect)
    }
}
