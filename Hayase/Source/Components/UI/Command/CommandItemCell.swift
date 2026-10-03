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
    private var checkContainerSizeConstraints: [NSLayoutConstraint] = []
    private var titleTrailingToSelectConstraint: NSLayoutConstraint?

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

        // `pr-8` of a select item, where the text ends
        titleTrailingToSelectConstraint = titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -32)

        checkSizeConstraints = [
            checkView.widthAnchor.constraint(equalToConstant: 12),
            checkView.heightAnchor.constraint(equalToConstant: 12),
        ]
        checkContainerSizeConstraints = [
            checkContainer.widthAnchor.constraint(equalToConstant: 16),
            checkContainer.heightAnchor.constraint(equalToConstant: 16),
        ]
        let fixedConstraints: [NSLayoutConstraint] = [
            checkContainer.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

            checkView.centerXAnchor.constraint(equalTo: checkContainer.centerXAnchor),
            checkView.centerYAnchor.constraint(equalTo: checkContainer.centerYAnchor),

            titleLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
        ]
        NSLayoutConstraint.activate(fixedConstraints)
        NSLayoutConstraint.activate(checkSizeConstraints)
        NSLayoutConstraint.activate(checkContainerSizeConstraints)
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
        // `<Check className=…>` never reaches the svg, which keeps svelte-radix's default 24; the
        // select item's `<Check class='h-4 w-4'>` does, in a `h-3.5 w-3.5` span at `right-2`
        let checkSize: CGFloat = selectStyle ? 16 : 24
        checkView.image = RadixIcons.check(size: checkSize)
        checkSizeConstraints.forEach { $0.constant = checkSize }
        checkContainerSizeConstraints.forEach { $0.constant = selectStyle ? 14 : 16 }

        checkLeadingConstraint?.isActive = multiple
        checkTrailingConstraint?.isActive = !multiple
        titleLeadingToCheckConstraint?.isActive = multiple
        titleLeadingToContentConstraint?.isActive = !multiple
        // a select item keeps its `pr-8` whether or not it is the chosen one
        titleTrailingToCheckConstraint?.isActive = !multiple && !selectStyle
        titleTrailingToSelectConstraint?.isActive = selectStyle
        titleTrailingToContentConstraint?.isActive = multiple
    }
}
