//
//  BannerBadge.swift
//  Hayase
//
//  Mirrors: interface full-banner.svelte badge row.
//

import UIKit

/// A `label` is the row's plain `rounded px-3.5 h-7 bg-primary/10 text-sm` div. A `button` is
/// the default-variant `Button h-7 bg-primary/10 select:!bg-primary/15 select:!text-foreground`
/// (rounded-md, px-4, and the variant's `shadow`); a `ghostButton` is the same in the ghost
/// variant, which the genres use and which has no shadow. `select` is hover, focus-visible or
/// active, so a touch is selected while it is down and an iPad pointer while it hovers.
final class BannerBadge: UIControl {
    enum Kind {
        case label
        case button
        case ghostButton

        var isButton: Bool { self != .label }
    }

    private let kind: Kind
    private let restingTextColor: UIColor
    private let titleLabel = UILabel()
    private var isHovered = false
    private var appliedSelected = false
    private var pressAnimator: UIViewPropertyAnimator?
    /// `shadow` casts only outside the box, so a translucent fill does not show it through.
    private let shadowLayer = CALayer()
    private let shadowMask = CAShapeLayer()

    init(text: String, textColor: UIColor, kind: Kind) {
        self.kind = kind
        self.restingTextColor = textColor
        super.init(frame: .zero)

        backgroundColor = Self.background(selected: false)
        layer.cornerRadius = kind.isButton ? 6 : 4        // rounded-md : rounded
        layer.masksToBounds = false
        translatesAutoresizingMaskIntoConstraints = false

        if kind == .button { installShadow() }

        titleLabel.attributedText = Self.title(text, color: textColor)
        titleLabel.numberOfLines = 1
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        let inset: CGFloat = kind.isButton ? 16 : 14      // px-4 : px-3.5
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 28),      // h-7
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        // Both variants refuse to compress: `whitespace-nowrap` / `text-nowrap`.
        setContentCompressionResistancePriority(.required, for: .horizontal)
        setContentHuggingPriority(.required, for: .horizontal)

        if kind.isButton {
            accessibilityLabel = text
            accessibilityTraits = .button
            addGestureRecognizer(UIHoverGestureRecognizer(target: self, action: #selector(hoverChanged(_:))))
        } else {
            isUserInteractionEnabled = false
        }
    }

    required init?(coder: NSCoder) {
        nil
    }

    /// text-sm font-bold: 14pt on a 20pt line
    private static func title(_ text: String, color: UIColor) -> NSAttributedString {
        CSSText.string(text, font: .nunito(ofSize: 14, weight: .bold), color: color, lineHeight: 20,
                       lineBreak: .byClipping)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard kind == .button else { return }
        let box = UIBezierPath(roundedRect: bounds, cornerRadius: layer.cornerRadius)
        let outside = UIBezierPath(rect: bounds.insetBy(dx: -16, dy: -16))
        outside.append(box)
        // These layers are not a view's own, so Core Animation would slide them into place
        // over a quarter of a second; the mask going wrong on the way shows the shadow's black
        // inside the badge.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shadowLayer.frame = bounds
        shadowLayer.shadowPath = box.cgPath
        shadowMask.frame = bounds
        shadowMask.path = outside.cgPath
        CATransaction.commit()
    }

    /// shadow: 0 1px 3px 0 rgb(0 0 0 / 0.1), 0 1px 2px -1px rgb(0 0 0 / 0.1)
    private func installShadow() {
        shadowLayer.backgroundColor = UIColor.black.cgColor
        shadowLayer.cornerRadius = layer.cornerRadius
        shadowLayer.shadowColor = UIColor.black.cgColor
        shadowLayer.shadowOpacity = 0.1
        shadowLayer.shadowOffset = CGSize(width: 0, height: 1)
        shadowLayer.shadowRadius = 1.5
        shadowMask.fillRule = .evenOdd
        shadowLayer.mask = shadowMask
        layer.insertSublayer(shadowLayer, at: 0)
    }

    override var isHighlighted: Bool {
        didSet {
            updateSelectState(animated: true)
            updatePressScale()
        }
    }

    @objc private func hoverChanged(_ recognizer: UIHoverGestureRecognizer) {
        isHovered = recognizer.state == .began || recognizer.state == .changed
        updateSelectState(animated: true)
    }

    /// app.css, for every button: `&:active { transition: all 0.1s ease-in-out; transform: scale(0.98) }`
    private func updatePressScale() {
        pressAnimator?.stopAnimation(true)
        pressAnimator = nil
        guard isHighlighted else {
            transform = .identity
            return
        }
        let animator = UIViewPropertyAnimator(duration: 0.1,
                                              controlPoint1: CGPoint(x: 0.42, y: 0),
                                              controlPoint2: CGPoint(x: 0.58, y: 1)) {
            self.transform = CGAffineTransform(scaleX: 0.98, y: 0.98)
        }
        pressAnimator = animator
        animator.startAnimation()
    }

    private func updateSelectState(animated: Bool) {
        let selected = isHighlighted || isHovered
        guard selected != appliedSelected else { return }
        appliedSelected = selected
        let changes = {
            self.backgroundColor = Self.background(selected: selected)
            self.titleLabel.attributedText = Self.title(self.titleLabel.attributedText?.string ?? "",
                                                        color: selected ? UIColor.HayaseTheme.foreground
                                                                        : self.restingTextColor)
        }
        guard animated else {
            changes()
            return
        }
        // transition-colors: 150ms.
        UIView.transition(with: self, duration: 0.15,
                          options: [.transitionCrossDissolve, .allowUserInteraction, .beginFromCurrentState],
                          animations: changes)
    }

    /// bg-primary/10, select:!bg-primary/15.
    private static func background(selected: Bool) -> UIColor {
        UIColor.HayaseTheme.primary.withAlphaComponent(selected ? 0.15 : 0.10)
    }
}
