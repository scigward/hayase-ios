//
//  ComboBox.swift
//  Hayase
//
//  UIKit counterpart for the matching interface component.
//

import UIKit

final class ComboBox: UIControl {
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
        layer.masksToBounds = true
        isAccessibilityElement = true
        accessibilityTraits = [.button]
        translatesAutoresizingMaskIntoConstraints = false

        valueLabel.font = .nunito(ofSize: 14, weight: .regular)
        valueLabel.numberOfLines = 1
        valueLabel.lineBreakMode = .byTruncatingTail
        valueLabel.translatesAutoresizingMaskIntoConstraints = false

        caretView.image = UIImage.hayaseIcon("chevrons-up-down")?
            .withConfiguration(UIImage.SymbolConfiguration(pointSize: 14, weight: .regular))
        caretView.tintColor = UIColor.HayaseTheme.mutedForeground.withAlphaComponent(0.65)
        caretView.contentMode = .scaleAspectFit
        caretView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(valueLabel)
        addSubview(caretView)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 36),
            valueLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            valueLabel.trailingAnchor.constraint(equalTo: caretView.leadingAnchor, constant: -8),
            valueLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            caretView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
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
        didSet {
            backgroundColor = isHighlighted
                ? UIColor.HayaseTheme.accent
                : UIColor.HayaseTheme.muted
        }
    }
}
