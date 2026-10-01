//
//  LayeredIconView.swift
//  Hayase
//
//  Mirrors: interface icons/animated (clapperboard, pencilline and trash, whose parts move
//  independently, and the sidebar's home, search, calendar, users, messages, download, bolt and
//  login).
//

import UIKit

/// An animated icon drawn from its SVG parts in the icons' 24pt view box, scaled to the view.
/// The parts are separate layers so they can move on their own, as the SVG groups do.
final class LayeredIconView: UIView {
    enum Kind {
        case clapperboard
        case penLine
        case trash
        case home
        case search
        case calendar
        case users
        case messages
        case download
        case bolt
        /// login.svelte is the download icon turned a quarter to the left.
        case login
    }

    private let kind: Kind
    private let canvas = CALayer()
    /// The icon's `<svg>` element: what an animation on the root of the icon moves.
    private let root = CALayer()
    private var strokes: [CAShapeLayer] = []
    private var fills: [CAShapeLayer] = []
    /// Groups that animate, by name.
    private var groups: [CALayer] = []
    /// The parts with `target-animated-icon`, in document order.
    private var targets: [CALayer] = []

    private static let selectKey = "select"

    var tint: UIColor = UIColor.HayaseTheme.foreground {
        didSet {
            strokes.forEach { $0.strokeColor = tint.cgColor }
            fills.forEach { $0.fillColor = tint.cgColor }
        }
    }

    init(kind: Kind) {
        self.kind = kind
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        canvas.bounds = CGRect(x: 0, y: 0, width: 24, height: 24)
        root.bounds = canvas.bounds
        root.position = CGPoint(x: 12, y: 12)
        canvas.addSublayer(root)
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

    /// `transition-colors`: the icon takes its colour over `duration`, with Tailwind's ease.
    func setTint(_ color: UIColor, duration: TimeInterval) {
        CATransaction.begin()
        CATransaction.setDisableActions(duration == 0)
        CATransaction.setAnimationDuration(duration)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(controlPoints: 0.4, 0, 0.2, 1))
        tint = color
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

    /// `<circle r='1' fill=currentColor stroke='none'>`
    private func dot(cx: CGFloat, cy: CGFloat) -> CAShapeLayer {
        let dot = CAShapeLayer()
        dot.bounds = canvas.bounds
        dot.anchorPoint = .zero
        dot.position = .zero
        dot.path = CGPath(ellipseIn: CGRect(x: cx - 1, y: cy - 1, width: 2, height: 2), transform: nil)
        dot.fillColor = tint.cgColor
        dot.strokeColor = nil
        fills.append(dot)
        return dot
    }

    /// A `<circle>` as path data.
    private func circle(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) -> String {
        "M\(cx - r) \(cy)a\(r) \(r) 0 1 0 \(2 * r) 0a\(r) \(r) 0 1 0 \(-2 * r) 0"
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
            root.addSublayer(outer)
        case .penLine:
            root.addSublayer(shape("M12 20h9"))
            let origin = CGPoint(x: 16.376, y: 3.622)
            let pen = group(origin: origin)
            pen.addSublayer(shape("M16.376 3.622a1 1 0 0 1 3.002 3.002L7.368 18.635a2 2 0 0 1-.855.506l-2.872.838a.5.5 0 0 1-.62-.62l.838-2.872a2 2 0 0 1 .506-.854z"))
            let tip = group(origin: origin)
            tip.addSublayer(shape("m15 5 3 3"))
            root.addSublayer(pen)
            root.addSublayer(tip)
        case .trash:
            let lid = group(origin: CGPoint(x: 12, y: 12))
            lid.addSublayer(shape("M3 6h18"))
            lid.addSublayer(shape("M8 6V4c0-1 1-2 2-2h4c1 0 2 1 2 2v2"))
            let body = group(origin: CGPoint(x: 12, y: 12))
            body.addSublayer(shape("M19 8v12c0 1-1 2-2 2H7c-1 0-2-1-2-2V8"))
            root.addSublayer(lid)
            root.addSublayer(body)
        case .home:
            root.addSublayer(shape("M3 10a2 2 0 0 1 .709-1.528l7-5.999a2 2 0 0 1 2.582 0l7 5.999A2 2 0 0 1 21 10v9a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"))
            // stroke-dasharray: 22
            let door = shape("M15 21v-8a1 1 0 0 0-1-1h-4a1 1 0 0 0-1 1v8")
            door.lineDashPattern = [22, 22]
            root.addSublayer(door)
            targets = [door]
        case .search:
            root.addSublayer(shape(circle(11, 11, 8)))
            root.addSublayer(shape("m21 21-4.3-4.3"))
        case .calendar:
            root.addSublayer(shape("M8 2v4"))
            root.addSublayer(shape("M16 2v4"))
            root.addSublayer(shape("M5 4h14a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2z"))
            root.addSublayer(shape("M3 10h18"))
            for (cx, cy) in [(8, 14), (12, 14), (16, 14), (8, 18), (12, 18), (16, 18)] as [(CGFloat, CGFloat)] {
                let layer = dot(cx: cx, cy: cy)
                root.addSublayer(layer)
                targets.append(layer)
            }
        case .users:
            root.addSublayer(shape("M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"))
            root.addSublayer(shape(circle(9, 7, 4)))
            for data in ["M22 21v-2a4 4 0 0 0-3-3.87", "M16 3.13a4 4 0 0 1 0 7.75"] {
                let layer = shape(data)
                root.addSublayer(layer)
                targets.append(layer)
            }
        case .messages:
            root.addSublayer(shape("M14 9a2 2 0 0 1-2 2H6l-4 4V4a2 2 0 0 1 2-2h8a2 2 0 0 1 2 2z"))
            root.addSublayer(shape("M18 9h2a2 2 0 0 1 2 2v11l-4-4h-6a2 2 0 0 1-2-2v-1"))
        case .download, .login:
            root.addSublayer(shape("M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"))
            let arrow = group(origin: CGPoint(x: 12, y: 12))
            arrow.addSublayer(shape("M7 10L12 15L17 10"))
            arrow.addSublayer(shape("M12 15L12 3"))
            root.addSublayer(arrow)
            if kind == .login {
                root.transform = CATransform3DMakeRotation(-.pi / 2, 0, 0, 1)   // -rotate-90
            }
        case .bolt:
            root.addSublayer(shape("M21 16V8a2 2 0 0 0-1-1.73l-7-4a2 2 0 0 0-2 0l-7 4A2 2 0 0 0 3 8v8a2 2 0 0 0 1 1.73l7 4a2 2 0 0 0 2 0l7-4A2 2 0 0 0 21 16z"))
            root.addSublayer(shape(circle(12, 12, 4)))
        }
    }

    // MARK: - Animation

    /// What the icon does each time its button becomes selected (`animated-icon`).
    func selectionChanged(_ selected: Bool) {
        switch kind {
        case .clapperboard:
            guard selected else { return }
            // Both groups get clapperboardInner: 0.4s ease-in-out, swinging out and past.
            groups.forEach { $0.add(clapperboardSwing(), forKey: Self.selectKey) }
        case .penLine:
            guard selected else { return }
            // penWiggle: 0.5s ease-in-out, twice.
            groups.forEach { $0.add(penWiggle(), forKey: Self.selectKey) }
        case .trash:
            // The lid rises and the bin sinks by 1px, `transition: transform 0.2s ease-in`.
            slide(groups[0], to: selected ? -1 : 0)
            slide(groups[1], to: selected ? 1 : 0)
        case .home:
            guard selected else { return }
            targets.forEach { $0.add(doorDraw(), forKey: Self.selectKey) }
        case .search:
            guard selected else { return }
            root.add(searchBounce(), forKey: Self.selectKey)
        case .calendar:
            guard selected else { return }
            for (index, dot) in targets.enumerated() {
                dot.add(pulse(delay: Double(index) * 0.17, in: dot), forKey: Self.selectKey)
            }
        case .users:
            guard selected else { return }
            targets.forEach { $0.add(usersSlide(), forKey: Self.selectKey) }
        case .messages:
            guard selected else { return }
            // primaryAnimation: the same small wobble as bookmark.svelte
            root.add(SelectButton.IconAnimation.wobble.makeAnimation(), forKey: Self.selectKey)
        case .download, .login:
            // The arrow dips 2px and springs back, `transition: transform 0.3s cubic-bezier(.68,-.6,.32,1.6)`.
            slide(groups[0], to: selected ? 2 : 0, duration: 0.3,
                  timing: CAMediaTimingFunction(controlPoints: 0.68, -0.6, 0.32, 1.6))
        case .bolt:
            guard selected else { return }
            root.add(SelectButton.IconAnimation.boltSpin.makeAnimation(), forKey: Self.selectKey)
        }
    }

    /// `.animated-icon:not(:hover)… .target-animated-icon { animation: none }`: when the pointer
    /// leaves, an animation that is still running stops at once.
    func cancelAnimations() {
        root.removeAnimation(forKey: Self.selectKey)
        groups.forEach { $0.removeAnimation(forKey: Self.selectKey) }
        targets.forEach { $0.removeAnimation(forKey: Self.selectKey) }
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

    /// home.svelte `doorAnimation`: 0.6s ease-out. The door is drawn in from nothing, after the
    /// first 15% of the time, by walking its dash offset from 22 to 0 as it fades in.
    private func doorDraw() -> CAAnimationGroup {
        func keyframes(_ keyPath: String, _ values: [Double]) -> CAKeyframeAnimation {
            let animation = CAKeyframeAnimation(keyPath: keyPath)
            animation.values = values
            animation.keyTimes = [0, 0.15, 1]
            animation.timingFunctions = [CAMediaTimingFunction(name: .linear), CAMediaTimingFunction(name: .easeOut)]
            animation.duration = 0.6
            return animation
        }
        let group = CAAnimationGroup()
        group.animations = [keyframes("lineDashPhase", [22, 22, 0]), keyframes("opacity", [0, 0, 1])]
        group.duration = 0.6
        return group
    }

    /// search.svelte `search-bounce`: 1s ease-in-out on the `<svg>` element itself, so its
    /// offsets are CSS pixels (points) rather than view box units.
    private func searchBounce() -> CAKeyframeAnimation {
        let unit = 24 / max(bounds.width, 1)
        func offset(_ x: CGFloat, _ y: CGFloat) -> NSValue {
            NSValue(caTransform3D: CATransform3DMakeTranslation(x * unit, y * unit, 0))
        }
        let animation = CAKeyframeAnimation(keyPath: "transform")
        animation.values = [offset(0, 0), offset(0, -4), offset(-3, 0), offset(0, 0)]
        animation.keyTimes = [0, 0.25, 0.5, 1]
        animation.timingFunctions = (0..<3).map { _ in CAMediaTimingFunction(name: .easeInEaseOut) }
        animation.duration = 1
        return animation
    }

    /// calendar.svelte `pulse`: each dot dims to 30% and back over 0.8s (CSS `ease`), one after
    /// another 0.17s apart.
    private func pulse(delay: CFTimeInterval, in layer: CALayer) -> CAKeyframeAnimation {
        let animation = CAKeyframeAnimation(keyPath: "opacity")
        animation.values = [1, 0.3, 1]
        animation.keyTimes = [0, 0.5, 1]
        animation.timingFunctions = [CAMediaTimingFunction(name: .default), CAMediaTimingFunction(name: .default)]
        animation.duration = 0.8
        animation.beginTime = layer.convertTime(CACurrentMediaTime(), from: nil) + delay
        return animation
    }

    /// users.svelte `users-slide`: the two partner strokes slide 6 units left and back, 0.6s.
    private func usersSlide() -> CAKeyframeAnimation {
        let animation = CAKeyframeAnimation(keyPath: "transform.translation.x")
        animation.values = [0, -6, 0]
        animation.keyTimes = [0, 0.5, 1]
        let spring = CAMediaTimingFunction(controlPoints: 0.175, 0.885, 0.32, 1.275)
        animation.timingFunctions = [spring, spring]
        animation.duration = 0.6
        return animation
    }

    private func slide(_ group: CALayer, to offset: CGFloat, duration: CFTimeInterval = 0.2,
                       timing: CAMediaTimingFunction = CAMediaTimingFunction(name: .easeIn)) {
        let current = group.presentation()?.value(forKeyPath: "transform.translation.y") as? CGFloat ?? 0
        let animation = CABasicAnimation(keyPath: "transform.translation.y")
        animation.fromValue = current
        animation.toValue = offset
        animation.duration = duration
        animation.timingFunction = timing
        group.add(animation, forKey: "slide")
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        group.transform = CATransform3DMakeTranslation(0, offset, 0)
        CATransaction.commit()
    }
}
