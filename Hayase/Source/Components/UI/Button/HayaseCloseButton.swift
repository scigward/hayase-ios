import UIKit

/// Shared dialog/sheet close control, matching interface's transparent Cross2 button.
final class HayaseCloseButton: UIButton {
    enum Style { case dialog, sheet }
    private let style: Style
    private let ringOffsetLayer = CAShapeLayer()
    private let focusRingLayer = CAShapeLayer()
    private var isPointerHovered = false

    init(style: Style = .dialog) {
        self.style = style
        super.init(frame: .zero)
        accessibilityLabel = "Close"
        layer.cornerRadius = 2
        tintColor = UIColor.HayaseTheme.foreground
        backgroundColor = .clear
        setImage(Self.crossImage, for: .normal)
        adjustsImageWhenHighlighted = false
        for (ring, color) in [(ringOffsetLayer, UIColor.HayaseTheme.background),
                              (focusRingLayer, UIColor.HayaseTheme.ring)] {
            ring.fillColor = UIColor.clear.cgColor
            ring.strokeColor = color.cgColor
            ring.lineWidth = 2
            ring.isHidden = true
            layer.addSublayer(ring)
        }
        if style == .sheet {
            addGestureRecognizer(UIHoverGestureRecognizer(target: self, action: #selector(hoverChanged(_:))))
        }
        updateOpacity()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var intrinsicContentSize: CGSize { CGSize(width: 16, height: 16) }
    override func imageRect(forContentRect contentRect: CGRect) -> CGRect {
        CGRect(x: contentRect.midX - 8, y: contentRect.midY - 8, width: 16, height: 16)
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        // Tailwind focus:ring-2 focus:ring-offset-2: black 2px gap, then a 2px ring.
        ringOffsetLayer.frame = bounds
        focusRingLayer.frame = bounds
        ringOffsetLayer.path = UIBezierPath(roundedRect: bounds.insetBy(dx: -1, dy: -1), cornerRadius: 3).cgPath
        focusRingLayer.path = UIBezierPath(roundedRect: bounds.insetBy(dx: -3, dy: -3), cornerRadius: 5).cgPath
    }
    override var isHighlighted: Bool { didSet { updateAppearance() } }
    override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        super.didUpdateFocus(in: context, with: coordinator)
        updateAppearance()
    }
    @objc private func hoverChanged(_ recognizer: UIHoverGestureRecognizer) {
        let hovered = recognizer.state == .began || recognizer.state == .changed
        guard isPointerHovered != hovered else { return }
        isPointerHovered = hovered
        UIView.animate(withDuration: UIAccessibility.isReduceMotionEnabled ? 0 : 0.15,
                       delay: 0,
                       options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseInOut]) {
            self.updateOpacity()
        }
    }
    private func updateOpacity() {
        alpha = style == .sheet && !isHighlighted && !isPointerHovered ? 0.7 : 1
    }
    private func updateAppearance() {
        updateOpacity()
        let showRing = isFocused || isHighlighted
        ringOffsetLayer.isHidden = !showRing
        focusRingLayer.isHidden = !showRing
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
