import UIKit

// MARK: - ErrorToastCardView

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
    func setTimerPaused(_ paused: Bool)
    func dismiss(swiped: Bool)
}

extension ErrorToastCardView: ToastCardView {}

enum SonnerText {
    /// Styled title: CSS white-space:normal. Descriptions alone opt into whitespace-pre-line.
    static func normal(_ value: String) -> String {
        CSSText.collapsingWhitespace(value)
            .trimmingCharacters(in: CharacterSet(charactersIn: " "))
    }

    static func preLine(_ value: String) -> String {
        let lines = value.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n").components(separatedBy: "\n")
        var text = lines.map {
            $0.replacingOccurrences(of: "[\\t\\f ]+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: CharacterSet(charactersIn: " "))
        }.joined(separator: "\n")
        // A terminal preserved segment break does not add an empty CSS line box.
        if text.hasSuffix("\n") { text.removeLast() }
        return text
    }
}

/// Sonner's action is not a shadcn Button: no select-color dimming, only a keyboard focus shadow.
private final class SonnerToastActionButton: UIButton, ActiveElementObserver {
    private var focusShown = false

    override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        super.didUpdateFocus(in: context, with: coordinator)
        activeElementDidChange()
    }
    func activeElementDidChange() {
        let focused = isActiveElement
        guard focusShown != focused else { return }
        let previousOpacity = layer.presentation()?.shadowOpacity ?? layer.shadowOpacity
        let previousPath = layer.presentation()?.shadowPath ?? layer.shadowPath
        focusShown = focused
        setNeedsLayout()
        layoutIfNeeded()
        guard !UIAccessibility.isReduceMotionEnabled else {
            layer.removeAnimation(forKey: "sonner-action-focus")
            return
        }
        // [data-button] transitions its shadow (including spread) over 200ms CSS ease.
        let opacity = CABasicAnimation(keyPath: "shadowOpacity")
        opacity.fromValue = previousOpacity
        opacity.toValue = layer.shadowOpacity
        let spread = CABasicAnimation(keyPath: "shadowPath")
        spread.fromValue = previousPath
        spread.toValue = layer.shadowPath
        let animation = CAAnimationGroup()
        animation.animations = [opacity, spread]
        animation.duration = 0.2
        animation.timingFunction = CAMediaTimingFunction(controlPoints: 0.25, 0.1, 0.25, 1)
        layer.add(animation, forKey: "sonner-action-focus")
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = focusShown ? 0.4 : 0
        layer.shadowRadius = 0
        layer.shadowOffset = .zero
        let spread: CGFloat = focusShown ? 2 : 0
        layer.shadowPath = UIBezierPath(roundedRect: bounds.insetBy(dx: -spread, dy: -spread),
                                       cornerRadius: 4 + spread).cgPath
        CATransaction.commit()
    }
}

/// Sonner's styled toast. closeButton=false and richColors=false in interface.
final class ErrorToastCardView: UIView {
    let id: UUID
    var onDismiss: ((Bool) -> Void)?
    private let heading: UILabel
    private let detail: UILabel
    private let icon = UIImageView(image: SonnerToastIcon.errorIcon)
    private let loader = SonnerToastLoaderView()
    private let secondaryShadow = CALayer()
    private var timer: Timer?
    private var startedAt: Date?
    private var remaining: TimeInterval
    private var timerPaused = false
    private var swipeGesture: SonnerToastGesture?
    private var dismissing = false
    private var kind: AppToastKind
    private let action: ToastAction?
    private let actionButton = SonnerToastActionButton(frame: .zero)
    /// `[data-button]` of svelte-sonner: 8pt either side of a 12pt label, 24pt high, and 6pt from the text
    private static let actionHeight: CGFloat = 24
    private static let actionGap: CGFloat = 6

    init(message: String, title: String, duration: TimeInterval,
         id: UUID = UUID(), kind: AppToastKind = .error, action: ToastAction? = nil) {
        self.id = id
        self.kind = kind
        self.action = action
        heading = Self.label(SonnerText.normal(title), weight: .medium, lineHeight: 19.5, color: UIColor.HayaseTheme.foreground)
        detail = Self.label(SonnerText.preLine(message), weight: .regular, lineHeight: 18.2, color: UIColor.HayaseTheme.mutedForeground)
        remaining = duration
        super.init(frame: .zero)
        backgroundColor = UIColor.HayaseTheme.background
        layer.cornerRadius = 8
        // User-requested exception: hide the card border, but retain Sonner's 1px
        // layout allowance in the metrics below so size and spacing stay unchanged.
        layer.borderWidth = 0
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
            actionButton.setAttributedTitle(CSSText.string(SonnerText.normal(action.label),
                font: .systemFont(ofSize: 12), color: UIColor.HayaseTheme.primaryForeground,
                lineHeight: 18, alignment: .center), for: .normal)
            actionButton.setTitleColor(UIColor.HayaseTheme.primaryForeground, for: .normal)
            actionButton.titleLabel?.font = UIFont.systemFont(ofSize: 12)
            actionButton.backgroundColor = UIColor.HayaseTheme.primary
            actionButton.layer.cornerRadius = 4
            actionButton.contentEdgeInsets = UIEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
            actionButton.addTarget(self, action: #selector(actionTapped), for: .touchUpInside)
            addSubview(actionButton)
        }
        updateIcon(animated: false)
        swipeGesture = SonnerToastGesture(card: self) { [weak self] in self?.kind != .loading }
        isAccessibilityElement = true
        accessibilityLabel = title + "\n" + message
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { timer?.invalidate() }

    func update(title: String, kind: AppToastKind, duration: TimeInterval) {
        pauseTimer()
        remaining = duration
        self.kind = kind
        heading.attributedText = Self.label(SonnerText.normal(title), weight: .medium, lineHeight: 19.5,
                                            color: UIColor.HayaseTheme.foreground).attributedText
        accessibilityLabel = title + "\n" + (detail.text ?? "")
        updateIcon(animated: true)
        setNeedsLayout()
        startTimer()
    }

    private func updateIcon(animated: Bool) {
        let loading = kind == .loading
        icon.image = kind == .success ? SonnerToastIcon.successIcon : SonnerToastIcon.errorIcon
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
        label.attributedText = CSSText.string(value, font: font, color: color,
                                             lineHeight: lineHeight, lineBreak: .byWordWrapping)
        label.numberOfLines = 0
        return label
    }

    private var actionWidth: CGFloat {
        guard action != nil else { return 0 }
        return actionButton.sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude, height: Self.actionHeight)).width
    }

    /// What the text has of the row: the button is after it, with a gap
    private var actionSpace: CGFloat {
        action == nil ? 0 : actionWidth + Self.actionGap
    }

    func height(for width: CGFloat) -> CGFloat {
        let textWidth = max(1, width - 57 - actionSpace)
        let titleHeight = heading.sizeThatFits(CGSize(width: textWidth, height: CGFloat.greatestFiniteMagnitude)).height
        let descriptionHeight = detail.sizeThatFits(CGSize(width: textWidth, height: CGFloat.greatestFiniteMagnitude)).height
        let gap: CGFloat = titleHeight > 0 && descriptionHeight > 0 ? 2 : 0
        let content = titleHeight + gap + descriptionHeight
        return 34 + max(16, content, action == nil ? 0 : Self.actionHeight)
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
        let gap: CGFloat = titleHeight > 0 && descriptionHeight > 0 ? 2 : 0
        let textHeight = titleHeight + gap + descriptionHeight
        let textTop = (bounds.height - textHeight) / 2 // align-items:center, including action-only height.
        heading.frame = CGRect(x: 40, y: textTop, width: width, height: titleHeight)
        detail.frame = CGRect(x: 40, y: textTop + titleHeight + gap, width: width, height: descriptionHeight)
        // Border + padding + icon margin(-3), SVG margin(-1); SVG is 20 in a 16px slot.
        icon.frame = CGRect(x: 13, y: bounds.midY - 10, width: 20, height: 20)
        loader.frame = CGRect(x: 14, y: bounds.midY - 8, width: 16, height: 16)
        // shadow-lg: 0 10px 15px -3px, 0 4px 6px -4px, both black/10.
        layer.shadowPath = UIBezierPath(roundedRect: bounds.insetBy(dx: 3, dy: 3), cornerRadius: 5).cgPath
        secondaryShadow.frame = bounds
        secondaryShadow.shadowPath = UIBezierPath(roundedRect: bounds.insetBy(dx: 4, dy: 4), cornerRadius: 4).cgPath
    }

    func startTimer() {
        guard !timerPaused, kind != .loading, remaining.isFinite, !dismissing, timer == nil else { return }
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

    func setTimerPaused(_ paused: Bool) {
        timerPaused = paused
        if paused { pauseTimer() } else { startTimer() }
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
}
