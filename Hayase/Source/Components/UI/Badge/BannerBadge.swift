//
//  BannerBadge.swift
//  Hayase
//
//  Mirrors: interface full-banner.svelte badge row.
//

import UIKit

/// A `label` is the row's plain `rounded px-3.5 h-7 bg-primary/10 text-sm` div. A `button` is
/// the `Button h-7 bg-primary/10 select:!bg-primary/15 select:!text-foreground` (rounded-md,
/// px-4). `select` is hover, focus-visible or active, so a touch is selected while it is down
/// and an iPad pointer while it hovers.
final class BannerBadge: UIControl {
    enum Kind {
        case label
        case button
    }

    private let kind: Kind
    private let restingTextColor: UIColor
    private let titleLabel = UILabel()
    private var isHovered = false
    private var appliedSelected = false

    init(text: String, textColor: UIColor, kind: Kind) {
        self.kind = kind
        self.restingTextColor = textColor
        super.init(frame: .zero)

        backgroundColor = Self.background(selected: false)
        layer.cornerRadius = kind == .button ? 6 : 4      // rounded-md : rounded
        layer.masksToBounds = true
        translatesAutoresizingMaskIntoConstraints = false

        titleLabel.text = text
        titleLabel.font = .nunito(ofSize: 14, weight: .bold)   // text-sm font-bold
        titleLabel.textColor = textColor
        titleLabel.numberOfLines = 1
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        let inset: CGFloat = kind == .button ? 16 : 14         // px-4 : px-3.5
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 28),      // h-7
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        // Both variants refuse to compress: `whitespace-nowrap` / `text-nowrap`.
        setContentCompressionResistancePriority(.required, for: .horizontal)
        setContentHuggingPriority(.required, for: .horizontal)

        if kind == .button {
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

    override var isHighlighted: Bool {
        didSet { updateSelectState(animated: true) }
    }

    @objc private func hoverChanged(_ recognizer: UIHoverGestureRecognizer) {
        isHovered = recognizer.state == .began || recognizer.state == .changed
        updateSelectState(animated: true)
    }

    private func updateSelectState(animated: Bool) {
        let selected = isHighlighted || isHovered
        guard selected != appliedSelected else { return }
        appliedSelected = selected
        let changes = {
            self.backgroundColor = Self.background(selected: selected)
            self.titleLabel.textColor = selected ? UIColor.HayaseTheme.foreground : self.restingTextColor
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
