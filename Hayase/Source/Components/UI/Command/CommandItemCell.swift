//
//  CommandItemCell.swift
//  Hayase
//
//  UIKit counterpart for the matching interface component.
//

import UIKit

final class CommandItemCell: UITableViewCell {
    static let reuseID = "CommandItemCell"

    private let checkContainer = UIView()
    private let checkView = UIImageView()
    private let titleLabel = UILabel()
    private var checkLeadingConstraint: NSLayoutConstraint?
    private var checkTrailingConstraint: NSLayoutConstraint?
    private var titleLeadingToCheckConstraint: NSLayoutConstraint?
    private var titleLeadingToContentConstraint: NSLayoutConstraint?
    private var titleTrailingToCheckConstraint: NSLayoutConstraint?
    private var titleTrailingToContentConstraint: NSLayoutConstraint?
    private var checkSizeConstraints: [NSLayoutConstraint] = []

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    /// Items sit inside their group's `p-1`.
    override var frame: CGRect {
        get { super.frame }
        set {
            var inset = newValue
            inset.origin.x += 4
            inset.size.width -= 8
            super.frame = inset
        }
    }

    private func setup() {
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        selectedBackgroundView = UIView()
        selectedBackgroundView?.backgroundColor = UIColor.HayaseTheme.accent
        selectedBackgroundView?.layer.cornerRadius = 4   // rounded-sm

        checkContainer.translatesAutoresizingMaskIntoConstraints = false
        checkContainer.layer.cornerRadius = 4   // rounded-sm
        // the Check icon is 24pt in its 16pt box and overflows it
        checkContainer.layer.masksToBounds = false

        checkView.image = UIImage.hayaseIcon("check")?
            .withConfiguration(UIImage.SymbolConfiguration(pointSize: 12, weight: .bold))
        checkView.contentMode = .scaleAspectFit
        checkView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = .nunito(ofSize: 14, weight: .regular)
        titleLabel.textColor = UIColor.HayaseTheme.foreground
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(checkContainer)
        contentView.addSubview(titleLabel)
        checkContainer.addSubview(checkView)

        checkLeadingConstraint = checkContainer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8)
        checkTrailingConstraint = checkContainer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8)
        titleLeadingToCheckConstraint = titleLabel.leadingAnchor.constraint(equalTo: checkContainer.trailingAnchor, constant: 8)
        titleLeadingToContentConstraint = titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8)
        titleTrailingToCheckConstraint = titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: checkContainer.leadingAnchor, constant: -8)
        titleTrailingToContentConstraint = titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -8)

        checkSizeConstraints = [
            checkView.widthAnchor.constraint(equalToConstant: 12),
            checkView.heightAnchor.constraint(equalToConstant: 12),
        ]
        let fixedConstraints: [NSLayoutConstraint] = [
            checkContainer.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            checkContainer.widthAnchor.constraint(equalToConstant: 16),
            checkContainer.heightAnchor.constraint(equalToConstant: 16),

            checkView.centerXAnchor.constraint(equalTo: checkContainer.centerXAnchor),
            checkView.centerYAnchor.constraint(equalTo: checkContainer.centerYAnchor),

            titleLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
        ]
        NSLayoutConstraint.activate(fixedConstraints)
        NSLayoutConstraint.activate(checkSizeConstraints)
    }

    func configure(option: CommandOption, selected: Bool, multiple: Bool, selectStyle: Bool = false) {
        titleLabel.text = option.label
        checkContainer.layer.borderWidth = multiple ? 1 : 0
        // an unselected box has `opacity-50`
        checkContainer.layer.borderColor = UIColor.HayaseTheme.primary
            .withAlphaComponent(selected || selectStyle ? 1 : 0.5).cgColor
        checkContainer.backgroundColor = selected && !selectStyle ? UIColor.HayaseTheme.primary : .clear
        checkView.tintColor = selectStyle ? UIColor.HayaseTheme.foreground : UIColor.HayaseTheme.primaryForeground
        checkView.isHidden = !selected
        // `<Check className=…>` never reaches the svg, which keeps svelte-radix's default 24
        let checkSize: CGFloat = selectStyle ? 12 : 24
        checkView.image = selectStyle
            ? UIImage.hayaseIcon("check")?.withConfiguration(UIImage.SymbolConfiguration(pointSize: 12, weight: .bold))
            : RadixIcons.check(size: checkSize)
        checkSizeConstraints.forEach { $0.constant = checkSize }

        checkLeadingConstraint?.isActive = multiple
        checkTrailingConstraint?.isActive = !multiple
        titleLeadingToCheckConstraint?.isActive = multiple
        titleLeadingToContentConstraint?.isActive = !multiple
        titleTrailingToCheckConstraint?.isActive = !multiple
        titleTrailingToContentConstraint?.isActive = multiple
    }
}
