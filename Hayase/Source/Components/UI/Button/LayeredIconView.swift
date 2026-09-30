//
//  LayeredIconView.swift
//  Hayase
//
//  Mirrors: interface icons/animated clapperboard.svelte, pencilline.svelte and trash.svelte,
//  whose parts move independently.
//

import UIKit

/// An animated icon drawn from its SVG parts in the icons' 24pt view box, scaled to the view.
/// The parts are separate layers so they can move on their own, as the SVG groups do.
final class LayeredIconView: UIView {
    enum Kind {
        case clapperboard
        case penLine
        case trash
    }

    private let kind: Kind
    private let canvas = CALayer()
    private var strokes: [CAShapeLayer] = []
    /// Groups that animate, by name.
    private var groups: [CALayer] = []

    var tint: UIColor = UIColor.HayaseTheme.foreground {
        didSet { strokes.forEach { $0.strokeColor = tint.cgColor } }
    }

    init(kind: Kind) {
        self.kind = kind
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        canvas.bounds = CGRect(x: 0, y: 0, width: 24, height: 24)
        layer.addSublayer(canvas)
        build()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        canvas.position = CGPoint(x: bounds.midX, y: bounds.midY)
        canvas.transform = CATransform3DMakeScale(bounds.width / 24, bounds.height / 24, 1)
        CATransaction.commit()
    }

    // MARK: - Parts

    private func shape(_ data: String) -> CAShapeLayer {
        let shape = CAShapeLayer()
        shape.bounds = canvas.bounds
        shape.anchorPoint = .zero
        shape.position = .zero
        shape.path = SVGPath.path(data)
        shape.fillColor = nil
        shape.strokeColor = tint.cgColor
        shape.lineWidth = 2
        shape.lineCap = .round
        shape.lineJoin = .round
        strokes.append(shape)
        return shape
    }

    /// A group whose `transform-origin` is `origin`, in the 24pt view box.
    private func group(origin: CGPoint) -> CALayer {
        let group = CALayer()
        group.bounds = canvas.bounds
        group.anchorPoint = CGPoint(x: origin.x / 24, y: origin.y / 24)
        group.position = origin
        groups.append(group)
        return group
    }

    private func build() {
        switch kind {
        case .clapperboard:
            // outer (origin 4px 20px) holds the clapper (origin 3px 11px) and the body
            let outer = group(origin: CGPoint(x: 4, y: 20))
            let clapper = group(origin: CGPoint(x: 3, y: 11))
            clapper.addSublayer(shape("M20.2 6 3 11l-.9-2.4c-.3-1.1.3-2.2 1.3-2.5l13.5-4c1.1-.3 2.2.3 2.5 1.3Z"))
            clapper.addSublayer(shape("m6.2 5.3 3.1 3.9"))
            clapper.addSublayer(shape("m12.4 3.4 3.1 4"))
            outer.addSublayer(clapper)
            outer.addSublayer(shape("M3 11h18v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2Z"))
            canvas.addSublayer(outer)
        case .penLine:
            canvas.addSublayer(shape("M12 20h9"))
            let origin = CGPoint(x: 16.376, y: 3.622)
            let pen = group(origin: origin)
            pen.addSublayer(shape("M16.376 3.622a1 1 0 0 1 3.002 3.002L7.368 18.635a2 2 0 0 1-.855.506l-2.872.838a.5.5 0 0 1-.62-.62l.838-2.872a2 2 0 0 1 .506-.854z"))
            let tip = group(origin: origin)
            tip.addSublayer(shape("m15 5 3 3"))
            canvas.addSublayer(pen)
            canvas.addSublayer(tip)
        case .trash:
            let lid = group(origin: CGPoint(x: 12, y: 12))
            lid.addSublayer(shape("M3 6h18"))
            lid.addSublayer(shape("M8 6V4c0-1 1-2 2-2h4c1 0 2 1 2 2v2"))
            let body = group(origin: CGPoint(x: 12, y: 12))
            body.addSublayer(shape("M19 8v12c0 1-1 2-2 2H7c-1 0-2-1-2-2V8"))
            canvas.addSublayer(lid)
            canvas.addSublayer(body)
        }
    }

    // MARK: - Animation

    /// What the icon does each time its button becomes selected (`animated-icon`).
    func selectionChanged(_ selected: Bool) {
        switch kind {
        case .clapperboard:
            guard selected else { return }
            // Both groups get clapperboardInner: 0.4s ease-in-out, swinging out and past.
            groups.forEach { $0.add(clapperboardSwing(), forKey: "select") }
        case .penLine:
            guard selected else { return }
            // penWiggle: 0.5s ease-in-out, twice.
            groups.forEach { $0.add(penWiggle(), forKey: "select") }
        case .trash:
            // The lid rises and the bin sinks by 1px, `transition: transform 0.2s ease-in`.
            slide(groups[0], to: selected ? -1 : 0)
            slide(groups[1], to: selected ? 1 : 0)
        }
    }

    private func clapperboardSwing() -> CAKeyframeAnimation {
        let animation = CAKeyframeAnimation(keyPath: "transform.rotation.z")
        animation.values = [0, -10, 16, 0].map { $0 * CGFloat.pi / 180 }
        animation.keyTimes = [0, 0.3, 0.6, 1].map { NSNumber(value: $0) }
        animation.timingFunctions = (0..<3).map { _ in CAMediaTimingFunction(name: .easeInEaseOut) }
        animation.duration = 0.4
        return animation
    }

    private func penWiggle() -> CAKeyframeAnimation {
        func pose(degrees: CGFloat, x: CGFloat, y: CGFloat) -> NSValue {
            // `rotate(a) translate(x, y)`: the offset is in the rotated frame.
            let rotation = CATransform3DMakeRotation(degrees * .pi / 180, 0, 0, 1)
            return NSValue(caTransform3D: CATransform3DTranslate(rotation, x, y, 0))
        }
        let animation = CAKeyframeAnimation(keyPath: "transform")
        animation.values = [pose(degrees: 0, x: 0, y: 0),
                            pose(degrees: -0.5, x: -1, y: 1.5),
                            pose(degrees: 0.5, x: 1.5, y: -1),
                            pose(degrees: 0, x: 0, y: 0)]
        animation.keyTimes = [0, 0.25, 0.75, 1].map { NSNumber(value: $0) }
        animation.timingFunctions = (0..<3).map { _ in CAMediaTimingFunction(name: .easeInEaseOut) }
        animation.duration = 0.5
        animation.repeatCount = 2
        return animation
    }

    private func slide(_ group: CALayer, to offset: CGFloat) {
        let current = group.presentation()?.value(forKeyPath: "transform.translation.y") as? CGFloat ?? 0
        let animation = CABasicAnimation(keyPath: "transform.translation.y")
        animation.fromValue = current
        animation.toValue = offset
        animation.duration = 0.2
        animation.timingFunction = CAMediaTimingFunction(name: .easeIn)
        group.add(animation, forKey: "slide")
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        group.transform = CATransform3DMakeTranslation(0, offset, 0)
        CATransaction.commit()
    }
}
