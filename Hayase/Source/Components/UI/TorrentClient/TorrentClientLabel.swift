import UIKit

/// CSS line boxes are independent of Nunito's ascender/descender metrics.
/// Keep those metrics available for painting without enlarging stack spacing.
final class TorrentClientLabel: UILabel {
    var lineHeight: CGFloat = 20 { didSet { applyLineHeight(); invalidateIntrinsicContentSize() } }
    var letterSpacing: CGFloat = 0 { didSet { applyLineHeight() } }
    var mutedText: String? { didSet { applyLineHeight() } }
    override var text: String? { didSet { applyLineHeight() } }
    override var font: UIFont! { didSet { applyLineHeight() } }
    override var textColor: UIColor! { didSet { applyLineHeight() } }
    override var textAlignment: NSTextAlignment { didSet { applyLineHeight() } }
    override var lineBreakMode: NSLineBreakMode { didSet { applyLineHeight() } }
    private var styling = false

    private func applyLineHeight() {
        guard !styling, let text, let font else { return }
        styling = true
        defer { styling = false }
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = lineHeight
        paragraph.maximumLineHeight = lineHeight
        paragraph.lineBreakMode = lineBreakMode
        paragraph.alignment = textAlignment
        let value = NSMutableAttributedString(string: text, attributes: [
            .font: font, .foregroundColor: textColor ?? UIColor.HayaseTheme.foreground,
            .paragraphStyle: paragraph, .baselineOffset: (lineHeight - font.lineHeight) / 2,
            .kern: letterSpacing,
        ])
        if let mutedText {
            let range = (text as NSString).range(of: mutedText)
            if range.location != NSNotFound {
                value.addAttribute(.foregroundColor, value: TorrentClientStyle.mutedForeground, range: range)
            }
        }
        attributedText = value
    }

    override var alignmentRectInsets: UIEdgeInsets {
        UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
    }

    override var intrinsicContentSize: CGSize {
        var size = super.intrinsicContentSize
        if numberOfLines == 1 { size.height = lineHeight }
        return size
    }

    override func drawText(in rect: CGRect) {
        super.drawText(in: bounds.inset(by: alignmentRectInsets))
    }
}

extension UIFont {
    static func geistMono(ofSize size: CGFloat) -> UIFont {
        // Bundled Google Fonts v1.701 matches @fontsource/geist-mono 5.3.0
        // in interface's lockfile; the variable font's default weight is 400.
        UIFont(name: "GeistMono-Regular", size: size) ?? .monospacedSystemFont(ofSize: size, weight: .regular)
    }
}
