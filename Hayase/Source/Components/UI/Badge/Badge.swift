//
//  Badge.swift
//  Hayase
//
//  UIKit counterpart for the interface badge component.
//

import UIKit

final class Badge: UIControl {
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
        layer.masksToBounds = true
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
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
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

    override var isFocused: Bool {
        didSet { updateRevealState(animated: true) }
    }

    override var intrinsicContentSize: CGSize {
        let titleSize = titleLabel.intrinsicContentSize
        let closeWidth: CGFloat = shouldRevealCloseIcon ? 20 : 0
        return CGSize(width: ceil(titleSize.width + closeWidth + 20),
                      height: max(22, ceil(titleSize.height + 6)))
    }

    private var shouldRevealCloseIcon: Bool {
        isHighlighted || isSelected || isFocused
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
