//
//  Badge.swift
//  Hayase
//
//  UIKit counterpart for the interface badge component.
//

import CoreImage
import UIKit

final class Badge: UIControl, ActiveElementObserver {
    private let titleLabel = UILabel()
    private let closeIconView = UIImageView()
    private let stackView = UIStackView()
    private var closeWidthConstraint: NSLayoutConstraint!

    var text: String? {
        get { titleLabel.text }
        set { titleLabel.text = newValue }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        backgroundColor = UIColor.HayaseTheme.primary
        layer.cornerRadius = 6
        // badgeVariants default: shadow (0 1px 3px 0 and 0 1px 2px -1px, both 10% black)
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.1
        layer.shadowOffset = CGSize(width: 0, height: 1)
        layer.shadowRadius = 1.5
        isAccessibilityElement = true
        accessibilityTraits = [.button]
        translatesAutoresizingMaskIntoConstraints = true

        titleLabel.font = .nunito(ofSize: 12, weight: .semibold)
        titleLabel.textColor = UIColor.HayaseTheme.primaryForeground
        titleLabel.numberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingTail

        closeIconView.image = UIImage.hayaseIcon("x")?
            .withConfiguration(UIImage.SymbolConfiguration(pointSize: 12, weight: .regular))
        closeIconView.tintColor = UIColor.HayaseTheme.primaryForeground
        closeIconView.contentMode = .scaleAspectFit
        closeIconView.alpha = 0

        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.spacing = 0
        stackView.isUserInteractionEnabled = false
        stackView.addArrangedSubview(titleLabel)
        stackView.addArrangedSubview(closeIconView)
        addSubview(stackView)

        closeWidthConstraint = closeIconView.widthAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3),
            // px-2.5 inside a 1px border
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 11),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -11),
            closeWidthConstraint,
            closeIconView.heightAnchor.constraint(equalToConstant: 12),
        ])
        updateRevealState(animated: false)
    }

    override var isHighlighted: Bool {
        didSet { updateRevealState(animated: true) }
    }

    override var isSelected: Bool {
        didSet { updateRevealState(animated: true) }
    }

    override func didUpdateFocus(in context: UIFocusUpdateContext,
                                 with coordinator: UIFocusAnimationCoordinator) {
        super.didUpdateFocus(in: context, with: coordinator)
        coordinator.addCoordinatedAnimations {
            self.updateRevealState(animated: false)
        }
    }

    func activeElementDidChange() {
        updateRevealState(animated: true)
    }

    override var intrinsicContentSize: CGSize {
        let titleSize = titleLabel.intrinsicContentSize
        let closeWidth: CGFloat = shouldRevealCloseIcon ? 20 : 0
        return CGSize(width: ceil(titleSize.width + closeWidth + 22),
                      height: max(22, ceil(titleSize.height + 6)))
    }

    private var shouldRevealCloseIcon: Bool {
        isHighlighted || isSelected || isActiveElement
    }

    private func updateRevealState(animated: Bool) {
        let reveal = shouldRevealCloseIcon
        let changes = {
            self.closeIconView.alpha = reveal ? 1 : 0
            self.closeWidthConstraint.constant = reveal ? 20 : 0
            self.stackView.spacing = reveal ? 8 : 0
            self.layoutIfNeeded()
        }
        if animated {
            UIView.animate(withDuration: 0.16, animations: changes)
        } else {
            changes()
        }
        invalidateIntrinsicContentSize()
    }
}

final class PaddedLabel: UILabel {
    var contentInsets = UIEdgeInsets.zero {
        didSet { invalidateIntrinsicContentSize() }
    }

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: contentInsets))
    }

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(width: size.width + contentInsets.left + contentInsets.right,
                      height: size.height + contentInsets.top + contentInsets.bottom)
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let base = super.sizeThatFits(CGSize(
            width: max(0, size.width - contentInsets.left - contentInsets.right),
            height: max(0, size.height - contentInsets.top - contentInsets.bottom)))
        return CGSize(width: base.width + contentInsets.left + contentInsets.right,
                      height: base.height + contentInsets.top + contentInsets.bottom)
    }

    override func textRect(forBounds bounds: CGRect, limitedToNumberOfLines numberOfLines: Int) -> CGRect {
        let insetBounds = bounds.inset(by: contentInsets)
        return super.textRect(forBounds: insetBounds, limitedToNumberOfLines: numberOfLines)
    }
}

/// `flex-wrap gap-2`: the badges under the title in one row. Like the chips below, each badge is placed
/// by frame from its own size, so the row is right whenever its badges are swapped. A stack view in a
/// scroll view drew them on top of each other when the page had its media a second after it was
/// laid out, until something else (a tab change) made it lay out again.
final class BadgeRowScrollView: UIScrollView {
    private let gap: CGFloat = 8
    private let badgeHeight: CGFloat = 24
    private var badges: [UIView] = []

    func setBadges(_ newBadges: [UIView]) {
        badges.forEach { $0.removeFromSuperview() }
        badges = newBadges
        badges.forEach { addSubview($0) }
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        var x: CGFloat = 0
        let y = (bounds.height - badgeHeight) / 2
        for badge in badges {
            let width = ceil(badge.intrinsicContentSize.width)
            badge.frame = CGRect(x: x, y: y, width: width, height: badgeHeight)
            x += width + gap
        }
        let size = CGSize(width: max(0, x - gap), height: bounds.height)
        if contentSize != size { contentSize = size }
    }
}

/// `flex gap-2 items-center overflow-x-auto`: the genre and tag buttons in one scrolling row.
/// Each button is placed by frame from its measured text, so the row is right the moment it is laid
/// out; a stack view of buttons kept the widths from before the buttons were swapped and drew them
/// on top of each other until something else (a tab change) forced a new layout.
final class ChipRowScrollView: UIScrollView {
    private let gap: CGFloat = 8
    private let chipHeight: CGFloat = 28
    private var chips: [UIButton] = []

    func setChips(_ newChips: [UIButton]) {
        chips.forEach { $0.removeFromSuperview() }
        chips = newChips
        chips.forEach { addSubview($0) }
        setNeedsLayout()
    }

    private func width(of chip: UIButton) -> CGFloat {
        let font = chip.titleLabel?.font ?? .systemFont(ofSize: 14)
        let text = ((chip.title(for: .normal) ?? "") as NSString).size(withAttributes: [.font: font]).width
        return ceil(text) + chip.contentEdgeInsets.left + chip.contentEdgeInsets.right
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        var x: CGFloat = 0
        let y = (bounds.height - chipHeight) / 2
        for chip in chips {
            let w = width(of: chip)
            chip.frame = CGRect(x: x, y: y, width: w, height: chipHeight)
            x += w + gap
        }
        let size = CGSize(width: max(0, x - gap), height: bounds.height)
        if contentSize != size { contentSize = size }
    }
}

final class AnimeTagChipButton: UIButton, ActiveElementObserver {
    /// A tag, whose chip is dashed, and not a genre.
    var isTagChip = false
    var dashedBorder = false {
        didSet { setNeedsLayout() }
    }
    var isSpoilerChip = false {
        didSet { updateSpoilerRendering() }
    }

    private let dashLayer = CAShapeLayer()
    private let dashMask = CAShapeLayer()
    private static let blurContext = CIContext(options: nil)

    private let blurredTitleView = UIImageView()
    private var blurredTitleCacheKey: String?
    private var spoilerFrames: [Int: UIImage] = [:]
    private var lastRevealed: Bool?
    private var isPointerOverTitle = false
    private var isPointerOver = false

    /// `bg-secondary select:bg-secondary/60`, and `text-secondary-foreground` or the tag's
    /// `text-muted-foreground`, both `select:!text-custom`.
    var restingBackground: UIColor = .clear { didSet { applySelectColors(animated: false) } }
    var selectedBackground: UIColor = .clear { didSet { applySelectColors(animated: false) } }
    var restingTitleColor: UIColor = .white { didSet { applySelectColors(animated: false) } }
    var selectedTitleColor: UIColor = .white { didSet { applySelectColors(animated: false) } }
    private var appliedSelected = false

    override var isHighlighted: Bool {
        didSet {
            updateSpoilerRendering()
            updateSelectState()
        }
    }

    private func updateSelectState() {
        let selected = isHighlighted || isActiveElement || isPointerOver
        guard selected != appliedSelected else { return }
        appliedSelected = selected
        applySelectColors(animated: true)
    }

    private func applySelectColors(animated: Bool) {
        let changes = {
            self.backgroundColor = self.appliedSelected ? self.selectedBackground : self.restingBackground
            self.setTitleColor(self.appliedSelected ? self.selectedTitleColor : self.restingTitleColor, for: .normal)
        }
        guard animated, window != nil else {
            changes()
            return
        }
        // transition-colors: 150ms
        UIView.transition(with: self, duration: 0.15,
                          options: [.transitionCrossDissolve, .allowUserInteraction, .beginFromCurrentState],
                          animations: changes)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupLayers()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupLayers()
    }

    override func setTitle(_ title: String?, for state: UIControl.State) {
        super.setTitle(title, for: state)
        blurredTitleCacheKey = nil
        updateSpoilerRendering()
    }

    private func setupLayers() {
        dashLayer.fillColor = UIColor.clear.cgColor
        dashLayer.lineCap = .butt
        dashLayer.isHidden = true
        dashLayer.mask = dashMask
        layer.addSublayer(dashLayer)

        blurredTitleView.isUserInteractionEnabled = false
        blurredTitleView.contentMode = .center
        blurredTitleView.isHidden = true
        addSubview(blurredTitleView)
        addGestureRecognizer(UIHoverGestureRecognizer(target: self, action: #selector(spoilerHover(_:))))
    }

    @objc private func spoilerHover(_ gesture: UIHoverGestureRecognizer) {
        let hovering = gesture.state == .began || gesture.state == .changed
        isPointerOverTitle = hovering && (titleLabel?.frame.contains(gesture.location(in: self)) ?? false)
        isPointerOver = hovering
        updateSpoilerRendering()
        updateSelectState()
    }

    override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        super.didUpdateFocus(in: context, with: coordinator)
        activeElementDidChange()
    }

    func activeElementDidChange() {
        updateSpoilerRendering()
        updateSelectState()
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        updateDashedBorderPath()
        blurredTitleView.frame = titleLabel?.frame ?? bounds.insetBy(dx: contentEdgeInsets.left, dy: 0)
        updateSpoilerRendering()
    }

    private func updateDashedBorderPath() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        dashLayer.isHidden = !dashedBorder || bounds.isEmpty
        guard !dashLayer.isHidden else { return }

        // Interface: border-2 border-dashed border-secondary rounded-md, painted the
        // way iOS WebKit does (BorderPainter::drawBoxSideFromPath): a single dash
        // pattern along the outer rounded edge, stroked at twice the border width
        // and clipped to the outer shape so each dash fills the border ring.
        // CGPath(roundedRect:) is the path WebKit strokes on iOS, so the pattern
        // starts, and leaves its one uneven gap, where WebKit's does.
        let borderWidth: CGFloat = 2
        let radius = min(layer.cornerRadius, bounds.width / 2, bounds.height / 2)
        let path = CGPath(roundedRect: bounds, cornerWidth: radius, cornerHeight: radius, transform: nil)
        let dash = 3 * borderWidth
        var gap = dash
        let perimeter = 2 * (bounds.width + bounds.height - 4 * radius) + 2 * .pi * radius
        let dashCount = perimeter / dash
        // WebKit widens the gaps when an odd, non-integral number of dashes fits.
        if Int(safe: Double(dashCount)) % 2 == 1, dashCount != dashCount.rounded(.down) {
            gap += dash / (dashCount / 2)
        }

        dashLayer.frame = bounds
        dashLayer.path = path
        dashLayer.strokeColor = UIColor.HayaseTheme.secondary.cgColor
        dashLayer.lineWidth = 2 * borderWidth
        dashLayer.lineDashPattern = [NSNumber(value: Double(dash)), NSNumber(value: Double(gap))]
        dashLayer.lineDashPhase = dash
        dashLayer.contentsScale = window?.screen.scale ?? UIScreen.main.scale
        dashMask.frame = bounds
        dashMask.path = path
    }

    private func updateSpoilerRendering() {
        guard isSpoilerChip else {
            titleLabel?.alpha = 1
            blurredTitleView.isHidden = true
            blurredTitleView.layer.removeAnimation(forKey: "spoilerFilter")
            lastRevealed = nil
            return
        }
        // Tailwind select = hover, focus-visible, active. Blur only the text,
        // never the button's background or dashed border.
        let revealed = isHighlighted || isActiveElement || isPointerOverTitle
        let shouldAnimate = lastRevealed != nil && lastRevealed != revealed
            && window != nil && !UIAccessibility.isReduceMotionEnabled
        titleLabel?.alpha = 0
        blurredTitleView.isHidden = false
        renderBlurredTitleIfNeeded(animated: shouldAnimate)
        guard let clear = spoilerFrames[0], let blurred = spoilerFrames[12] else { return }
        lastRevealed = revealed
        blurredTitleView.image = revealed ? clear : blurred
        guard shouldAnimate, spoilerFrames.count == 13 else { return }

        // transition-[filter]: 150ms, Tailwind's cubic-bezier(0.4,0,0.2,1).
        // Cached Gaussian samples animate the filter itself, not two cross-fading texts.
        let indices = revealed ? Array((0...12).reversed()) : Array(0...12)
        let frames = indices.compactMap { spoilerFrames[$0] }
        var values: [Any] = frames.compactMap { $0.cgImage }
        if let current = blurredTitleView.layer.presentation()?.contents, !values.isEmpty {
            values[0] = current
        }
        let animation = CAKeyframeAnimation(keyPath: "contents")
        animation.values = values
        animation.keyTimes = (0..<values.count).map { NSNumber(value: Double($0) / Double(max(1, values.count - 1))) }
        animation.calculationMode = .discrete
        animation.duration = 0.15
        animation.timingFunction = CAMediaTimingFunction(controlPoints: 0.4, 0, 0.2, 1)
        blurredTitleView.layer.add(animation, forKey: "spoilerFilter")
    }

    private func renderBlurredTitleIfNeeded(animated: Bool) {
        guard let text = title(for: .normal), !text.isEmpty, bounds.height > 0 else { return }
        let font = titleLabel?.font ?? .systemFont(ofSize: 14)
        let color = currentTitleColor
        let scale = window?.screen.scale ?? UIScreen.main.scale
        let size = text.size(withAttributes: [.font: font])
        let targetSize = CGSize(width: ceil(size.width) + 36, height: ceil(size.height) + 36)
        let key = "\(text)|\(font.fontName)|\(font.pointSize)|\(scale)|\(color.description)"
        if key != blurredTitleCacheKey {
            blurredTitleCacheKey = key
            spoilerFrames.removeAll()
        }
        // Render just the endpoints on initial layout. Intermediate radii are
        // generated once, only when this particular tag is interacted with.
        let steps = animated ? Array(0...12) : [0, 12]
        guard steps.contains(where: { spoilerFrames[$0] == nil }) else { return }
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        let textImage = UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
            text.draw(at: CGPoint(x: (targetSize.width - size.width) / 2,
                                 y: (targetSize.height - size.height) / 2),
                      withAttributes: [.font: font, .foregroundColor: color])
        }
        guard let cgImage = textImage.cgImage else { return }
        let input = CIImage(cgImage: cgImage)
        for step in steps where spoilerFrames[step] == nil {
            if step == 0 { spoilerFrames[step] = textImage; continue }
            let output = input.applyingFilter("CIGaussianBlur",
                parameters: [kCIInputRadiusKey: CGFloat(step) / 2 * scale])
            guard let rendered = Self.blurContext.createCGImage(output, from: input.extent) else {
                spoilerFrames.removeAll()
                blurredTitleView.image = nil
                return
            }
            spoilerFrames[step] = UIImage(cgImage: rendered, scale: scale, orientation: .up)
        }
    }
}
