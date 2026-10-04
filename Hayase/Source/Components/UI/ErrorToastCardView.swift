import UIKit

enum AppToastKind { case loading, success, error }

/// `action: { label, onClick }` of a toast: a button after the text, which also takes the toast away
struct ToastAction {
    let label: String
    let handler: () -> Void
}

/// What the toast stack needs of a card: where it is in the stack, how tall it is and when it goes.
protocol ToastCardView: UIView {
    var id: UUID { get }
    var onDismiss: ((Bool) -> Void)? { get set }
    func height(for width: CGFloat) -> CGFloat
    func startTimer()
    func dismiss(swiped: Bool)
}

extension ErrorToastCardView: ToastCardView {}

/// Sonner's styled toast. closeButton=false and richColors=false in interface.
final class ErrorToastCardView: UIView {
    let id: UUID
    var onDismiss: ((Bool) -> Void)?
    private let heading: UILabel
    private let detail: UILabel
    private let icon = UIImageView(image: ErrorToastCardView.errorIcon)
    private let loader = SonnerToastLoaderView()
    private let secondaryShadow = CALayer()
    private var timer: Timer?
    private var startedAt: Date?
    private var remaining: TimeInterval
    private var dismissing = false
    private var kind: AppToastKind
    private let action: ToastAction?
    private let actionButton = UIButton(type: .custom)
    /// `[data-button]` of svelte-sonner: 8pt either side of a 12pt label, 24pt high, and 6pt from the text
    private static let actionHeight: CGFloat = 24
    private static let actionGap: CGFloat = 6

    init(message: String, title: String, duration: TimeInterval,
         id: UUID = UUID(), kind: AppToastKind = .error, action: ToastAction? = nil) {
        self.id = id
        self.kind = kind
        self.action = action
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
        [icon, loader, heading, detail].forEach { addSubview($0) }
        if let action {
            // `group-[.toast]:bg-primary group-[.toast]:text-primary-foreground`, rounded 4px, text-xs
            actionButton.setTitle(action.label, for: .normal)
            actionButton.setTitleColor(UIColor.HayaseTheme.primaryForeground, for: .normal)
            actionButton.titleLabel?.font = UIFont.systemFont(ofSize: 12)
            actionButton.backgroundColor = UIColor.HayaseTheme.primary
            actionButton.layer.cornerRadius = 4
            actionButton.contentEdgeInsets = UIEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
            actionButton.addTarget(self, action: #selector(actionTapped), for: .touchUpInside)
            addSubview(actionButton)
        }
        updateIcon(animated: false)
        addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(pan(_:))))
        addGestureRecognizer(UIHoverGestureRecognizer(target: self, action: #selector(hover(_:))))
        isAccessibilityElement = true
        accessibilityLabel = title + "\n" + message
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { timer?.invalidate() }

    func update(title: String, kind: AppToastKind, duration: TimeInterval) {
        pauseTimer()
        remaining = duration
        self.kind = kind
        heading.attributedText = Self.label(title, weight: .medium, lineHeight: 19.5,
                                            color: UIColor.HayaseTheme.foreground).attributedText
        accessibilityLabel = title + "\n" + (detail.text ?? "")
        updateIcon(animated: true)
        setNeedsLayout()
        startTimer()
    }

    private func updateIcon(animated: Bool) {
        let loading = kind == .loading
        icon.image = kind == .success ? Self.successIcon : Self.errorIcon
        icon.isHidden = loading
        var customActions = [UIAccessibilityCustomAction(name: "Dismiss", target: self, selector: #selector(dismissForAccessibility))]
        if let action {
            customActions.insert(UIAccessibilityCustomAction(name: action.label, target: self, selector: #selector(actionForAccessibility)), at: 0)
        }
        accessibilityCustomActions = loading ? [] : customActions
        guard animated, !loading, !UIAccessibility.isReduceMotionEnabled else {
            icon.alpha = 1
            icon.transform = .identity
            loader.isHidden = !loading
            loader.alpha = 1
            loader.transform = .identity
            loader.setAnimating(loading)
            return
        }
        // Promise resolution's sonner-fade-in: scale(.8) and opacity 0 → 1,
        // 300ms CSS ease. Theme colors remain unchanged (richColors=false).
        icon.alpha = 0
        icon.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
        let timing = UICubicTimingParameters(controlPoint1: CGPoint(x: 0.25, y: 0.1),
                                             controlPoint2: CGPoint(x: 0.25, y: 1))
        let iconAnimator = UIViewPropertyAnimator(duration: 0.3, timingParameters: timing)
        iconAnimator.addAnimations { self.icon.alpha = 1; self.icon.transform = .identity }
        iconAnimator.startAnimation()
        let loaderAnimator = UIViewPropertyAnimator(duration: 0.2, timingParameters: timing)
        loaderAnimator.addAnimations {
            self.loader.alpha = 0
            self.loader.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
        }
        loaderAnimator.addCompletion { [weak self] _ in
            guard let self, self.kind != .loading else { return }
            self.loader.isHidden = true
            self.loader.setAnimating(false)
        }
        loaderAnimator.startAnimation()
    }

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

    private var actionWidth: CGFloat {
        guard action != nil else { return 0 }
        return ceil(actionButton.sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude, height: Self.actionHeight)).width)
    }

    /// What the text has of the row: the button is after it, with a gap
    private var actionSpace: CGFloat {
        action == nil ? 0 : actionWidth + Self.actionGap
    }

    func height(for width: CGFloat) -> CGFloat {
        let textWidth = max(1, width - 57 - actionSpace)
        let titleHeight = heading.sizeThatFits(CGSize(width: textWidth, height: CGFloat.greatestFiniteMagnitude)).height
        let descriptionHeight = detail.sizeThatFits(CGSize(width: textWidth, height: CGFloat.greatestFiniteMagnitude)).height
        let content = titleHeight + (descriptionHeight > 0 ? 2 + descriptionHeight : 0)
        return ceil(34 + max(16, content, action == nil ? 0 : Self.actionHeight))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = max(1, bounds.width - 57 - actionSpace)
        if action != nil {
            // `margin-left: auto`: at the end of the row, in the middle of it
            actionButton.frame = CGRect(x: bounds.width - 17 - actionWidth, y: bounds.midY - Self.actionHeight / 2,
                                        width: actionWidth, height: Self.actionHeight)
        }
        let titleHeight = heading.sizeThatFits(CGSize(width: width, height: CGFloat.greatestFiniteMagnitude)).height
        let descriptionHeight = detail.sizeThatFits(CGSize(width: width, height: CGFloat.greatestFiniteMagnitude)).height
        heading.frame = CGRect(x: 40, y: 17, width: width, height: titleHeight)
        detail.frame = CGRect(x: 40, y: 17 + titleHeight + 2, width: width, height: descriptionHeight)
        // Border + padding + icon margin(-3), SVG margin(-1); SVG is 20 in a 16px slot.
        icon.frame = CGRect(x: 13, y: bounds.midY - 10, width: 20, height: 20)
        loader.frame = CGRect(x: 14, y: bounds.midY - 8, width: 16, height: 16)
        // shadow-lg: 0 10px 15px -3px, 0 4px 6px -4px, both black/10.
        layer.shadowPath = UIBezierPath(roundedRect: bounds.insetBy(dx: 3, dy: 3), cornerRadius: 5).cgPath
        secondaryShadow.frame = bounds
        secondaryShadow.shadowPath = UIBezierPath(roundedRect: bounds.insetBy(dx: 4, dy: 4), cornerRadius: 4).cgPath
    }

    func startTimer() {
        guard kind != .loading, remaining.isFinite, !dismissing, timer == nil else { return }
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

    func dismiss(swiped: Bool = false) {
        guard !dismissing else { return }
        dismissing = true
        pauseTimer()
        onDismiss?(swiped)
    }

    /// `toast.action.onClick(event)`, and the toast goes unless the event was prevented
    @objc private func actionTapped() {
        action?.handler()
        dismiss(swiped: false)
    }

    @objc private func actionForAccessibility() -> Bool {
        actionTapped()
        return true
    }

    @objc private func dismissForAccessibility() -> Bool {
        guard kind != .loading else { return false }
        dismiss(swiped: false)
        return true
    }
    @objc private func hover(_ gesture: UIHoverGestureRecognizer) {
        if gesture.state == .began { pauseTimer() }
        else if gesture.state == .ended || gesture.state == .cancelled { startTimer() }
    }
    @objc private func pan(_ gesture: UIPanGestureRecognizer) {
        guard kind != .loading else { return }
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

    /// The matching filled circle/check from svelte-sonner@0.3.28 Icon.svelte.
    private static let successIcon: UIImage = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 20)).image { context in
        UIColor.white.setFill()
        UIBezierPath(ovalIn: CGRect(x: 2, y: 2, width: 16, height: 16)).fill()
        context.cgContext.setBlendMode(.clear)
        let check = UIBezierPath()
        check.move(to: CGPoint(x: 6.75, y: 10.75))
        check.addLine(to: CGPoint(x: 9.25, y: 13.25))
        check.addLine(to: CGPoint(x: 13.25, y: 7.75))
        check.lineWidth = 1.5
        check.lineCapStyle = .round
        check.lineJoinStyle = .round
        check.stroke()
    }.withRenderingMode(.alwaysTemplate)
}

/// Loader.svelte + Toaster.svelte: 12 radial bars, not UIKit's platform spinner.
private final class SonnerToastLoaderView: UIView {
    private let bars = (0..<12).map { _ in CALayer() }
    private var animating = false
    override init(frame: CGRect) {
        super.init(frame: frame)
        bars.forEach {
            $0.backgroundColor = UIColor(white: 0.435, alpha: 1).cgColor // Sonner --gray11
            $0.cornerRadius = 6
            layer.addSublayer($0)
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layoutSubviews() {
        super.layoutSubviews()
        for (index, bar) in bars.enumerated() {
            let angle = CGFloat(index) * .pi / 6
            let width = bounds.width * 0.24
            let height = bounds.height * 0.08
            let distance = width * 1.46
            bar.bounds = CGRect(x: 0, y: 0, width: width, height: height)
            bar.position = CGPoint(x: bounds.midX + bounds.width * 0.02 + cos(angle) * distance,
                                   y: bounds.midY + bounds.height * 0.001 + sin(angle) * distance)
            bar.transform = CATransform3DMakeRotation(angle, 0, 0, 1)
        }
    }
    func setAnimating(_ value: Bool) {
        animating = value
        refreshAnimation()
    }
    override func didMoveToWindow() { super.didMoveToWindow(); refreshAnimation() }
    private func refreshAnimation() {
        for (index, bar) in bars.enumerated() {
            bar.removeAnimation(forKey: "sonner-spin")
            guard animating, window != nil, !UIAccessibility.isReduceMotionEnabled else { continue }
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 1
            fade.toValue = 0.15
            fade.duration = 1.2
            fade.repeatCount = .infinity
            fade.timingFunction = CAMediaTimingFunction(name: .linear)
            fade.beginTime = CACurrentMediaTime() - 1.2 + Double(index) * 0.1
            bar.add(fade, forKey: "sonner-spin")
        }
    }
}
