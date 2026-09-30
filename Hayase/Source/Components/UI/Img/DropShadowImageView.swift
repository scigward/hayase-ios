//
//  DropShadowImageView.swift
//  Hayase
//
//  Mirrors: the clearlogo of interface full-banner.svelte (`Load` with `drop-shadow-lg`).
//

import UIKit

/// An image with the interface's `drop-shadow-lg`, twice over as in full-banner.svelte: the
/// `img` carries the filter, and so does the `overflow-clip` wrapper around it, so the
/// inner shadows are cut off at the image's box and the outer ones are cast from that.
final class DropShadowImageView: UIView, LoadInImageHost {
    var image: UIImage? {
        didSet { setNeedsDisplay() }
    }

    var imageContentMode: UIView.ContentMode { .scaleAspectFit }

    /// drop-shadow(0 10px 8px 4%) drop-shadow(0 4px 3px 10%), the first applied first.
    private static let shadows: [(offset: CGFloat, blur: CGFloat, alpha: CGFloat)] = [(10, 8, 0.04), (4, 3, 0.1)]

    /// Room around the image for its shadows. Layout sees only the image's own box.
    private static let bleed = UIEdgeInsets(top: 12, left: 16, bottom: 28, right: 16)

    override var alignmentRectInsets: UIEdgeInsets {
        Self.bleed
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        contentMode = .redraw
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func draw(_ rect: CGRect) {
        guard let image, image.size.width > 0, image.size.height > 0,
              let context = UIGraphicsGetCurrentContext() else { return }
        let box = bounds.inset(by: alignmentRectInsets)
        let scale = min(box.width / image.size.width, box.height / image.size.height)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let fitted = CGRect(x: box.midX - size.width / 2, y: box.midY - size.height / 2,
                            width: size.width, height: size.height)
        Self.withDropShadowLg(in: context) {
            context.saveGState()
            context.clip(to: box)
            Self.withDropShadowLg(in: context) {
                image.draw(in: fitted)
            }
            context.restoreGState()
        }
    }

    /// A CSS filter list applies its drop-shadows in order, each to the result of the one
    /// before. A shadow that is set when a transparency layer begins is cast by the layer as
    /// a whole, so nesting one layer per shadow gives the same chain.
    private static func withDropShadowLg(in context: CGContext, draw: () -> Void) {
        func cast(_ shadow: (offset: CGFloat, blur: CGFloat, alpha: CGFloat)) {
            context.setShadow(offset: CGSize(width: 0, height: shadow.offset),
                              blur: shadow.blur,
                              color: UIColor(white: 0, alpha: shadow.alpha).cgColor)
        }
        context.saveGState()
        cast(shadows[1])
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        cast(shadows[0])
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        draw()
        context.endTransparencyLayer()
        cast(shadows[1])
        context.endTransparencyLayer()
        context.restoreGState()
    }
}
