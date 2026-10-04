//
//  Badge.swift
//  Hayase
//
//  UIKit counterpart for the interface badge component.
//

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
