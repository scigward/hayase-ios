//
//  SelectTrigger.swift
//  Hayase
//
//  UIKit counterpart for the matching interface component.
//

// Mirrors: interface/src/lib/components/ui/select/select-trigger.svelte
// `flex h-9 w-full items-center justify-between rounded-md border border-input bg-muted px-3 py-2
// text-sm shadow-sm select:bg-accent`: the value on the left (`line-clamp-1`, normal weight) and a
// CaretSort `h-4 w-4 opacity-50` on the right. It is not the combobox's button, which has `px-4`,
// `font-medium` and no border; the picker it opens is `CommandPopoverViewController` with
// `showsSearch: false`, the counterpart of `select-content.svelte`.

import UIKit

final class SelectTriggerView: UIControl {
    private var isPointerOver = false
    private var appliedSelected = false
    private let valueLabel = UILabel()
    private let caretView = UIImageView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        backgroundColor = UIColor.HayaseTheme.muted
        layer.cornerRadius = 6   // rounded-md
        layer.borderWidth = 1    // border
        layer.borderColor = UIColor.HayaseTheme.input.cgColor   // border-input
        // shadow-sm
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.05
        layer.shadowOffset = CGSize(width: 0, height: 1)
        layer.shadowRadius = 1
        addGestureRecognizer(UIHoverGestureRecognizer(target: self, action: #selector(hoverChanged(_:))))
        isAccessibilityElement = true
        accessibilityTraits = [.button]
        translatesAutoresizingMaskIntoConstraints = false

        valueLabel.font = .nunito(ofSize: 14, weight: .regular)   // text-sm
        valueLabel.numberOfLines = 1
        valueLabel.lineBreakMode = .byTruncatingTail   // [&>span]:line-clamp-1
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        valueLabel.isUserInteractionEnabled = false

        caretView.image = RadixIcons.caretSort(size: 16)   // CaretSort h-4 w-4
        caretView.tintColor = UIColor.HayaseTheme.foreground.withAlphaComponent(0.5)   // opacity-50
        caretView.contentMode = .scaleAspectFit
        caretView.translatesAutoresizingMaskIntoConstraints = false
        caretView.isUserInteractionEnabled = false

        addSubview(valueLabel)
        addSubview(caretView)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 36),   // h-9
            // px-3 inside the 1pt border
            valueLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 13),
            valueLabel.trailingAnchor.constraint(lessThanOrEqualTo: caretView.leadingAnchor),
            valueLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            caretView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -13),
            caretView.centerYAnchor.constraint(equalTo: centerYAnchor),
            caretView.widthAnchor.constraint(equalToConstant: 16),
            caretView.heightAnchor.constraint(equalToConstant: 16),
        ])
        // the value gives way to the caret
        valueLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    /// The shown value. A placeholder is `data-[placeholder]:[&>span]:text-muted-foreground`.
    func configure(text: String, placeholder: Bool) {
        valueLabel.text = text
        valueLabel.textColor = placeholder ? UIColor.HayaseTheme.mutedForeground : UIColor.HayaseTheme.foreground
        accessibilityLabel = text
    }

    override var isHighlighted: Bool {
        didSet { updateSelectState() }
    }

    override var isEnabled: Bool {
        didSet { alpha = isEnabled ? 1 : 0.5 }   // disabled:opacity-50
    }

    @objc private func hoverChanged(_ recognizer: UIHoverGestureRecognizer) {
        isPointerOver = recognizer.state == .began || recognizer.state == .changed
        updateSelectState()
    }

    /// `select:bg-accent`: hover, focus-visible or active. The trigger has no `transition-colors`.
    private func updateSelectState() {
        let selected = isEnabled && (isHighlighted || isPointerOver)
        guard selected != appliedSelected else { return }
        appliedSelected = selected
        backgroundColor = selected ? UIColor.HayaseTheme.accent : UIColor.HayaseTheme.muted
    }
}
