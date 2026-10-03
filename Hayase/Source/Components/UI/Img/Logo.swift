//
//  Logo.swift
//  Hayase
//
//  Mirrors: src/lib/components/icons/Logo.svelte
//
//    <svg viewBox='0 0 66.145833 66.145833'>
//      <path fill='currentColor' d='M.00000117 61.5156237V4.6302097l66.145831 37.041664v19.84375l-47.624995-26.72291v16.40416zm66.145831-30.42707-23.547916-13.229174 23.547916-13.22917Z' />
//

import UIKit

enum HayaseLogo {
    /// The side of the svg's view box.
    static let viewBoxSide: CGFloat = 66.145833

    /// The path in view box units.
    static func path() -> CGPath {
        let path = UIBezierPath()
        path.move(to: CGPoint(x: 0.00000117, y: 61.5156237))
        path.addLine(to: CGPoint(x: 0.00000117, y: 4.6302097))
        path.addLine(to: CGPoint(x: 66.145832, y: 41.6718737))
        path.addLine(to: CGPoint(x: 66.145832, y: 61.5156237))
        path.addLine(to: CGPoint(x: 18.520837, y: 34.7927137))
        path.addLine(to: CGPoint(x: 18.520837, y: 51.1968737))
        path.close()
        path.move(to: CGPoint(x: 66.145832, y: 31.0885537))
        path.addLine(to: CGPoint(x: 42.597916, y: 17.8593797))
        path.addLine(to: CGPoint(x: 66.145832, y: 4.6302097))
        path.close()
        return path.cgPath
    }
}

/// The logo drawn like an `object-contain` svg: as large as fits the view, centred, and in the
/// text colour (`fill='currentColor'`).
final class LogoView: UIView {
    override class var layerClass: AnyClass { CAShapeLayer.self }

    private var shapeLayer: CAShapeLayer { layer as! CAShapeLayer }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        shapeLayer.fillColor = UIColor.HayaseTheme.foreground.cgColor
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let side = min(bounds.width, bounds.height)
        let scale = side / HayaseLogo.viewBoxSide
        var transform = CGAffineTransform(translationX: (bounds.width - side) / 2,
                                          y: (bounds.height - side) / 2).scaledBy(x: scale, y: scale)
        shapeLayer.path = HayaseLogo.path().copy(using: &transform)
    }
}
