import UIKit

/// Sonner's styled error toast. closeButton=false and richColors=false in interface.
final class ErrorToastCardView: UIView {
    var onDismiss: ((Bool) -> Void)?
    private let heading: UILabel
    private let detail: UILabel
    private let icon = UIImageView(image: ErrorToastCardView.errorIcon)
    private let secondaryShadow = CALayer()
    private var timer: Timer?
    private var startedAt: Date?
    private var remaining: TimeInterval
    private var dismissing = false

    init(message: String, title: String, duration: TimeInterval) {
        heading = Self.label(title, weight: .medium, lineHeight: 19.5, color: UIColor.HayaseTheme.foreground)
        detail = Self.label(message, weight: .regular, lineHeight: 18.2, color: UIColor.HayaseTheme.mutedForeground)
        remaining = duration
        super.init(frame: .zero)
        backgroundColor = UIColor.HayaseTheme.background
        layer.cornerRadius = 8
        layer.borderWidth = 1
        layer.borderColor = UIColor.HayaseTheme.border.cgColor
        // interface overrides Sonner's shadow with Tailwind shadow-lg.
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.1
        layer.shadowOffset = CGSize(width: 0, height: 10)
        layer.shadowRadius = 7.5
        secondaryShadow.shadowColor = UIColor.black.cgColor
        secondaryShadow.shadowOpacity = 0.1
        secondaryShadow.shadowOffset = CGSize(width: 0, height: 4)
        secondaryShadow.shadowRadius = 3
        layer.insertSublayer(secondaryShadow, at: 0)
        icon.tintColor = UIColor.HayaseTheme.foreground
        [icon, heading, detail].forEach { addSubview($0) }
        addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(pan(_:))))
        addGestureRecognizer(UIHoverGestureRecognizer(target: self, action: #selector(hover(_:))))
        isAccessibilityElement = true
        accessibilityLabel = title + "\n" + message
        accessibilityCustomActions = [UIAccessibilityCustomAction(name: "Dismiss", target: self, selector: #selector(dismissForAccessibility))]
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { timer?.invalidate() }

    private static func label(_ value: String, weight: UIFont.Weight, lineHeight: CGFloat, color: UIColor) -> UILabel {
        let label = UILabel()
        // Sonner sets ui-sans-serif/system-ui on its own container, overriding Nunito.
        let font = UIFont.systemFont(ofSize: 13, weight: weight)
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = lineHeight
        paragraph.maximumLineHeight = lineHeight
        paragraph.lineBreakMode = .byWordWrapping
        label.attributedText = NSAttributedString(string: value, attributes: [
            .font: font, .foregroundColor: color, .paragraphStyle: paragraph,
        ])
        label.numberOfLines = 0
        return label
    }

    func height(for width: CGFloat) -> CGFloat {
        let textWidth = max(1, width - 57)
        let titleHeight = heading.sizeThatFits(CGSize(width: textWidth, height: CGFloat.greatestFiniteMagnitude)).height
        let descriptionHeight = detail.sizeThatFits(CGSize(width: textWidth, height: CGFloat.greatestFiniteMagnitude)).height
        return ceil(34 + max(16, titleHeight + (descriptionHeight > 0 ? 2 + descriptionHeight : 0)))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = max(1, bounds.width - 57)
        let titleHeight = heading.sizeThatFits(CGSize(width: width, height: CGFloat.greatestFiniteMagnitude)).height
        let descriptionHeight = detail.sizeThatFits(CGSize(width: width, height: CGFloat.greatestFiniteMagnitude)).height
        heading.frame = CGRect(x: 40, y: 17, width: width, height: titleHeight)
        detail.frame = CGRect(x: 40, y: 17 + titleHeight + 2, width: width, height: descriptionHeight)
        // Border + padding + icon margin(-3), SVG margin(-1); SVG is 20 in a 16px slot.
        icon.frame = CGRect(x: 13, y: bounds.midY - 10, width: 20, height: 20)
        // shadow-lg: 0 10px 15px -3px, 0 4px 6px -4px, both black/10.
        layer.shadowPath = UIBezierPath(roundedRect: bounds.insetBy(dx: 3, dy: 3), cornerRadius: 5).cgPath
        secondaryShadow.frame = bounds
        secondaryShadow.shadowPath = UIBezierPath(roundedRect: bounds.insetBy(dx: 4, dy: 4), cornerRadius: 4).cgPath
    }

    func startTimer() {
        guard !dismissing, timer == nil else { return }
        startedAt = Date()
        let timer = Timer(timeInterval: max(0.01, remaining), repeats: false) { [weak self] _ in self?.dismiss(swiped: false) }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func pauseTimer() {
        if let startedAt { remaining -= Date().timeIntervalSince(startedAt) }
        startedAt = nil
        timer?.invalidate()
        timer = nil
    }

    private func dismiss(swiped: Bool) {
        guard !dismissing else { return }
        dismissing = true
        pauseTimer()
        onDismiss?(swiped)
    }

    @objc private func dismissForAccessibility() -> Bool { dismiss(swiped: false); return true }
    @objc private func hover(_ gesture: UIHoverGestureRecognizer) {
        if gesture.state == .began { pauseTimer() }
        else if gesture.state == .ended || gesture.state == .cancelled { startTimer() }
    }
    @objc private func pan(_ gesture: UIPanGestureRecognizer) {
        let amount = min(0, gesture.translation(in: superview).y)
        switch gesture.state {
        case .began: pauseTimer()
        case .changed: transform = CGAffineTransform(translationX: 0, y: amount)
        case .ended, .cancelled:
            if gesture.state == .ended && amount <= -20 { dismiss(swiped: true) }
            else {
                UIView.animate(withDuration: UIAccessibility.isReduceMotionEnabled ? 0 : 0.4) { self.transform = .identity }
                startTimer()
            }
        default: break
        }
    }

    /// Sonner Icon.svelte's filled 20x20 error glyph, not Lucide's outlined circle-alert.
    private static let errorIcon: UIImage = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 20)).image { _ in
        let path = UIBezierPath(ovalIn: CGRect(x: 2, y: 2, width: 16, height: 16))
        path.append(UIBezierPath(roundedRect: CGRect(x: 9.25, y: 5, width: 1.5, height: 6), cornerRadius: 0.75))
        path.append(UIBezierPath(ovalIn: CGRect(x: 9, y: 13, width: 2, height: 2)))
        path.usesEvenOddFillRule = true
        UIColor.white.setFill()
        path.fill()
    }.withRenderingMode(.alwaysTemplate)
}
