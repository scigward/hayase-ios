import UIKit

/// Shared dialog/sheet close control, matching interface's 16px Cross2.
final class HayaseCloseButton: UIButton {
    enum Style { case dialog, sheet }
    private let style: Style

    init(style: Style = .dialog) {
        self.style = style
        super.init(frame: .zero)
        accessibilityLabel = "Close"
        layer.cornerRadius = 2
        tintColor = style == .dialog ? UIColor.HayaseTheme.mutedForeground : UIColor.HayaseTheme.foreground
        backgroundColor = style == .dialog ? UIColor.HayaseTheme.accent.withAlphaComponent(0.7) : UIColor.HayaseTheme.secondary
        setImage(Self.crossImage, for: .normal)
        adjustsImageWhenHighlighted = false
        updateOpacity()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var intrinsicContentSize: CGSize { CGSize(width: 16, height: 16) }
    override func imageRect(forContentRect contentRect: CGRect) -> CGRect {
        CGRect(x: contentRect.midX - 8, y: contentRect.midY - 8, width: 16, height: 16)
    }
    override var isHighlighted: Bool { didSet { updateOpacity() } }
    private func updateOpacity() { alpha = style == .sheet && !isHighlighted ? 0.7 : 1 }
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        bounds.insetBy(dx: -max(0, (44 - bounds.width) / 2),
                       dy: -max(0, (44 - bounds.height) / 2)).contains(point)
    }

    // Radix Cross2 uses a thinner, smaller cross than Lucide's X.
    private static let crossImage: UIImage = UIGraphicsImageRenderer(size: CGSize(width: 15, height: 15)).image { context in
        let path = UIBezierPath()
        path.move(to: CGPoint(x: 4, y: 4))
        path.addLine(to: CGPoint(x: 11, y: 11))
        path.move(to: CGPoint(x: 11, y: 4))
        path.addLine(to: CGPoint(x: 4, y: 11))
        path.lineWidth = 1
        path.lineCapStyle = .round
        UIColor.black.setStroke()
        path.stroke()
    }.withRenderingMode(.alwaysTemplate)
}
