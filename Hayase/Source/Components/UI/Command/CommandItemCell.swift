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

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        selectedBackgroundView = UIView()
        selectedBackgroundView?.backgroundColor = UIColor.HayaseTheme.accent

        checkContainer.translatesAutoresizingMaskIntoConstraints = false
        checkContainer.layer.cornerRadius = 3
        checkContainer.layer.masksToBounds = true

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

        NSLayoutConstraint.activate([
            checkContainer.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            checkContainer.widthAnchor.constraint(equalToConstant: 16),
            checkContainer.heightAnchor.constraint(equalToConstant: 16),

            checkView.centerXAnchor.constraint(equalTo: checkContainer.centerXAnchor),
            checkView.centerYAnchor.constraint(equalTo: checkContainer.centerYAnchor),
            checkView.widthAnchor.constraint(equalToConstant: 12),
            checkView.heightAnchor.constraint(equalToConstant: 12),

            titleLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
        ])
    }

    func configure(option: CommandOption, selected: Bool, multiple: Bool, selectStyle: Bool = false) {
        titleLabel.text = option.label
        checkContainer.layer.borderWidth = multiple ? 1 : 0
        checkContainer.layer.borderColor = UIColor.HayaseTheme.primary.cgColor
        checkContainer.backgroundColor = selected && !selectStyle ? UIColor.HayaseTheme.primary : .clear
        checkView.tintColor = selectStyle ? UIColor.HayaseTheme.foreground : UIColor.HayaseTheme.primaryForeground
        checkView.isHidden = !selected

        checkLeadingConstraint?.isActive = multiple
        checkTrailingConstraint?.isActive = !multiple
        titleLeadingToCheckConstraint?.isActive = multiple
        titleLeadingToContentConstraint?.isActive = !multiple
        titleTrailingToCheckConstraint?.isActive = !multiple
        titleTrailingToContentConstraint?.isActive = multiple
    }
}
