//
//  ComboBox.swift
//  Hayase
//
//  UIKit counterpart for the matching interface component.
//

import UIKit

final class ComboBox: UIControl, ActiveElementObserver {
    var restingBackgroundColor: UIColor = UIColor.HayaseTheme.muted {
        didSet { if !appliedSelected { backgroundColor = restingBackgroundColor } }
    }
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
        layer.cornerRadius = 6
        // outline variant, border-0: shadow-sm
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.05
        layer.shadowOffset = CGSize(width: 0, height: 1)
        layer.shadowRadius = 1
        addGestureRecognizer(UIHoverGestureRecognizer(target: self, action: #selector(hoverChanged(_:))))
        isAccessibilityElement = true
        accessibilityTraits = [.button]
        translatesAutoresizingMaskIntoConstraints = false

        valueLabel.font = .nunito(ofSize: 14, weight: .medium)   // text-sm font-medium of the Button
        valueLabel.numberOfLines = 1
        valueLabel.lineBreakMode = .byTruncatingTail
        valueLabel.translatesAutoresizingMaskIntoConstraints = false

        caretView.image = RadixIcons.caretSort(size: 16)   // CaretSort ml-2 h-4 w-4
        caretView.tintColor = UIColor.HayaseTheme.foreground.withAlphaComponent(0.5)   // opacity-50
        caretView.contentMode = .scaleAspectFit
        caretView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(valueLabel)
        addSubview(caretView)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 36),
            // size default: px-4
            valueLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            valueLabel.trailingAnchor.constraint(equalTo: caretView.leadingAnchor, constant: -8),
            valueLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            caretView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            caretView.centerYAnchor.constraint(equalTo: centerYAnchor),
            caretView.widthAnchor.constraint(equalToConstant: 16),
            caretView.heightAnchor.constraint(equalToConstant: 16),
        ])
    }

    func configure(text: String, placeholder: Bool) {
        valueLabel.text = text
        valueLabel.textColor = placeholder
            ? UIColor.HayaseTheme.mutedForeground.withAlphaComponent(0.5)
            : UIColor.HayaseTheme.foreground
        accessibilityLabel = text
    }

    override var isHighlighted: Bool {
        didSet { updateSelectState() }
    }

    @objc private func hoverChanged(_ recognizer: UIHoverGestureRecognizer) {
        isPointerOver = recognizer.state == .began || recognizer.state == .changed
        updateSelectState()
    }

    func activeElementDidChange() {
        updateSelectState()
    }

    /// select:bg-accent with `transition-colors`: 150ms.
    private func updateSelectState() {
        let selected = isHighlighted || isPointerOver || isActiveElement
        guard selected != appliedSelected else { return }
        appliedSelected = selected
        UIView.animate(withDuration: 0.15, delay: 0, options: [.allowUserInteraction, .beginFromCurrentState]) {
            self.backgroundColor = selected ? UIColor.HayaseTheme.accent : self.restingBackgroundColor
        }
    }
}
