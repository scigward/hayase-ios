import UIKit

/// Shared dialog/sheet close control, matching interface's transparent Cross2 button.
///
/// dialog-content.svelte: `absolute right-4 top-4 rounded-sm transition-opacity select:opacity-100
/// focus:ring-2 focus:ring-offset-2`, no opacity of its own. sheet-content.svelte and the schedule
/// drawer: the same with `opacity-70` and `hover:opacity-100` (`select:opacity-100`).
/// app.css, for every button: `&:active { transition: all 0.1s ease-in-out; transform: scale(0.98) }`.
final class HayaseCloseButton: UIButton, ActiveElementObserver {
    enum Style { case dialog, sheet }
    private let style: Style
    private let ringOffsetLayer = CAShapeLayer()
    private let focusRingLayer = CAShapeLayer()
    private var isPointerHovered = false
    /// `focus:ring-2`: a click gives a button the focus, and it keeps it while the dialog fades away.
    private var isPressFocused = false

    /// `transition-opacity`: 150ms with Tailwind's `cubic-bezier(0.4, 0, 0.2, 1)`.
    private static let opacityTiming = UICubicTimingParameters(controlPoint1: CGPoint(x: 0.4, y: 0),
                                                               controlPoint2: CGPoint(x: 0.2, y: 1))
    /// `:active`: `all 0.1s ease-in-out`
    private static let pressTiming = UICubicTimingParameters(controlPoint1: CGPoint(x: 0.42, y: 0),
                                                              controlPoint2: CGPoint(x: 0.58, y: 1))

    init(style: Style = .dialog) {
        self.style = style
        super.init(frame: .zero)
        accessibilityLabel = "Close"
        layer.cornerRadius = 4   // rounded-sm: `calc(var(--radius) - 4px)` of 0.5rem
        tintColor = UIColor.HayaseTheme.foreground
        backgroundColor = .clear
        setImage(Self.crossImage, for: .normal)
        adjustsImageWhenHighlighted = false
        for (ring, color) in [(ringOffsetLayer, UIColor.HayaseTheme.background),
                              (focusRingLayer, UIColor.HayaseTheme.ring)] {
            ring.fillColor = UIColor.clear.cgColor
            ring.strokeColor = color.cgColor
            ring.lineWidth = 2
            ring.opacity = 0
            layer.addSublayer(ring)
        }
        if style == .sheet {
            addGestureRecognizer(UIHoverGestureRecognizer(target: self, action: #selector(hoverChanged(_:))))
        }
        alpha = targetAlpha
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var intrinsicContentSize: CGSize { CGSize(width: 16, height: 16) }
    override func imageRect(forContentRect contentRect: CGRect) -> CGRect {
        CGRect(x: contentRect.midX - 8, y: contentRect.midY - 8, width: 16, height: 16)
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        // Tailwind focus:ring-2 focus:ring-offset-2: a 2pt gap in the color of the background, then a 2pt
        // ring. A box shadow follows the corners of the box, so each is as round as `rounded-sm` plus its
        // spread: the strokes are centered 1pt and 3pt out.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ringOffsetLayer.frame = bounds
        focusRingLayer.frame = bounds
        ringOffsetLayer.path = UIBezierPath(roundedRect: bounds.insetBy(dx: -1, dy: -1), cornerRadius: 5).cgPath
        focusRingLayer.path = UIBezierPath(roundedRect: bounds.insetBy(dx: -3, dy: -3), cornerRadius: 7).cgPath
        CATransaction.commit()
    }

    override var isHighlighted: Bool {
        didSet {
            guard isHighlighted != oldValue else { return }
            if isHighlighted { isPressFocused = true }
            updatePress()
            updateOpacity(timing: isHighlighted ? Self.pressTiming : Self.opacityTiming,
                          duration: isHighlighted ? 0.1 : 0.15)
            updateRing(animated: isHighlighted)
        }
    }

    /// Only a click leaves the button focused: a press that ends somewhere else does not.
    override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        if !isTouchInside { isPressFocused = false }
        super.endTracking(touch, with: event)
    }

    override func cancelTracking(with event: UIEvent?) {
        isPressFocused = false
        super.cancelTracking(with: event)
    }

    override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        super.didUpdateFocus(in: context, with: coordinator)
        updateRing(animated: false)
    }

    func activeElementDidChange() {
        updateRing(animated: false)
    }

    @objc private func hoverChanged(_ recognizer: UIHoverGestureRecognizer) {
        let hovered = recognizer.state == .began || recognizer.state == .changed
        guard isPointerHovered != hovered else { return }
        isPointerHovered = hovered
        updateOpacity(timing: Self.opacityTiming, duration: 0.15)
    }

    /// The scale of `:active` comes in over 0.1s. Out of it the button only has `transition-opacity`, which
    /// is not about the transform: it is back at once.
    private func updatePress() {
        if isHighlighted {
            let animator = UIViewPropertyAnimator(duration: UIAccessibility.isReduceMotionEnabled ? 0 : 0.1,
                                                  timingParameters: Self.pressTiming)
            animator.addAnimations { self.transform = CGAffineTransform(scaleX: 0.98, y: 0.98) }
            animator.startAnimation()
        } else {
            layer.removeAllAnimations()
            UIView.performWithoutAnimation { self.transform = .identity }
        }
    }

    private var targetAlpha: CGFloat {
        style == .sheet && !isHighlighted && !isPointerHovered ? 0.7 : 1
    }

    private func updateOpacity(timing: UICubicTimingParameters, duration: TimeInterval) {
        let target = targetAlpha
        guard alpha != target else { return }
        let animator = UIViewPropertyAnimator(duration: UIAccessibility.isReduceMotionEnabled ? 0 : duration,
                                              timingParameters: timing)
        animator.addAnimations { self.alpha = target }
        animator.startAnimation()
    }

    /// The ring comes in with the press, in the 0.1s of `:active`; it goes at once, when the focus does.
    private func updateRing(animated: Bool) {
        let target: Float = isActiveElement || isPressFocused ? 1 : 0
        guard ringOffsetLayer.opacity != target else { return }
        CATransaction.begin()
        if animated && target == 1 && !UIAccessibility.isReduceMotionEnabled {
            CATransaction.setAnimationDuration(0.1)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
        } else {
            CATransaction.setDisableActions(true)
        }
        ringOffsetLayer.opacity = target
        focusRingLayer.opacity = target
        CATransaction.commit()
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        bounds.insetBy(dx: -max(0, (44 - bounds.width) / 2),
                       dy: -max(0, (44 - bounds.height) / 2)).contains(point)
    }

    // Radix Cross2 is a 15x15 glyph rendered at 16px in the interface.
    private static let crossImage: UIImage = UIGraphicsImageRenderer(size: CGSize(width: 16, height: 16)).image { _ in
        let path = UIBezierPath()
        let scale: CGFloat = 16 / 15
        path.move(to: CGPoint(x: 3.625 * scale, y: 3.625 * scale))
        path.addLine(to: CGPoint(x: 11.375 * scale, y: 11.375 * scale))
        path.move(to: CGPoint(x: 11.375 * scale, y: 3.625 * scale))
        path.addLine(to: CGPoint(x: 3.625 * scale, y: 11.375 * scale))
        path.lineWidth = 1.15 * scale
        path.lineCapStyle = .round
        UIColor.black.setStroke()
        path.stroke()
    }.withRenderingMode(.alwaysTemplate)
}
