//
//  CommandItem.swift
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
    /// `select:bg-accent` while the pointer is over the item (cmdk selects an item on `pointermove`), at once as
    /// the class has no `transition-colors`
    private let hoverBackground = UIView()

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
        hoverBackground.backgroundColor = UIColor.HayaseTheme.accent
        hoverBackground.layer.cornerRadius = 4
        hoverBackground.alpha = 0
        hoverBackground.isUserInteractionEnabled = false
        hoverBackground.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        insertSubview(hoverBackground, at: 0)
        addGestureRecognizer(UIHoverGestureRecognizer(target: self, action: #selector(hoverChanged(_:))))

        checkContainer.translatesAutoresizingMaskIntoConstraints = false
        checkContainer.layer.cornerRadius = 4   // rounded-sm

        checkView.image = UIImage.hayaseIcon("check")?
            .withConfiguration(UIImage.SymbolConfiguration(pointSize: 12, weight: .bold))
        checkView.contentMode = .scaleAspectFit
        checkView.translatesAutoresizingMaskIntoConstraints = false

        // the text is a flex item that wraps where the box and the gap leave no more room
        titleLabel.numberOfLines = 0
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

    /// `px-2` on one side and the 16pt box with its `ml-2`/`mr-2` on the other (`pl-2 pr-8` in a select item)
    private static let textInset: CGFloat = 40
    /// `text-sm`: 14pt on a 20pt line
    private static let lineHeight: CGFloat = 20

    private static func textAttributes() -> [NSAttributedString.Key: Any] {
        let style = NSMutableParagraphStyle()
        style.minimumLineHeight = lineHeight
        style.maximumLineHeight = lineHeight
        style.lineBreakMode = .byWordWrapping
        return [.font: UIFont.nunito(ofSize: 14, weight: .regular),
                .foregroundColor: UIColor.HayaseTheme.foreground,
                .paragraphStyle: style]
    }

    /// An item is as tall as its text (`py-1.5` around the lines, 32pt for one) in a row `width` wide.
    static func height(for label: String, width: CGFloat) -> CGFloat {
        let room = max(width - textInset, 1)
        let text = (label as NSString).boundingRect(with: CGSize(width: room, height: .greatestFiniteMagnitude),
                                                    options: .usesLineFragmentOrigin,
                                                    attributes: textAttributes(), context: nil)
        return max(32, ceil(text.height) + 12)
    }

    override func layoutSubviews() {
        titleLabel.preferredMaxLayoutWidth = max(bounds.width - Self.textInset, 1)
        super.layoutSubviews()
        hoverBackground.frame = bounds
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        hoverBackground.alpha = 0
    }

    @objc private func hoverChanged(_ recognizer: UIHoverGestureRecognizer) {
        hoverBackground.alpha = recognizer.state == .began || recognizer.state == .changed ? 1 : 0
    }

    func configure(option: CommandOption, selected: Bool, multiple: Bool, selectStyle: Bool = false) {
        titleLabel.attributedText = NSAttributedString(string: option.label, attributes: Self.textAttributes())
        checkContainer.layer.borderWidth = multiple ? 1 : 0
        // an unselected box has `opacity-50`
        checkContainer.layer.borderColor = UIColor.HayaseTheme.primary
            .withAlphaComponent(selected || selectStyle ? 1 : 0.5).cgColor
        checkContainer.backgroundColor = selected && !selectStyle ? UIColor.HayaseTheme.primary : .clear
        checkView.tintColor = selectStyle ? UIColor.HayaseTheme.foreground : UIColor.HayaseTheme.primaryForeground
        checkView.isHidden = !selected
        // `<Check className=…>` never reaches the svg, which keeps svelte-radix's 24x24 attributes, but as a flex
        // item of the 16pt box it shrinks to 16 wide while its viewBox stays square, so the glyph draws at 16;
        // the select item's `<Check class='h-4 w-4'>` is 16 in a `h-3.5 w-3.5` span at `right-2`
        let checkSize: CGFloat = 16
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
