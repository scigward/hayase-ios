// Mirrors interface Tree.Item and options.svelte's inline subtitle delay.
import UIKit

final class PlayerOptionCell: UITableViewCell {
    static let reuseID = "PlayerOptionCell"
    private let rowBackground = UIView()
    private let titleLabel = UILabel()
    private let detailLabel = UILabel()
    private let chevronImage = UIImageView()
    private var active = false
    private var dimmed = false
    private var titleTrailing: NSLayoutConstraint?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .none
        rowBackground.layer.cornerRadius = 2
        rowBackground.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(rowBackground)
        for label in [titleLabel, detailLabel] {
            label.translatesAutoresizingMaskIntoConstraints = false
            label.numberOfLines = 1
            label.lineBreakMode = .byTruncatingTail
            rowBackground.addSubview(label)
        }
        detailLabel.font = .nunito(ofSize: 14, weight: .bold)
        detailLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        chevronImage.image = UIImage.hayaseIcon("chevron-right", pointSize: 16)
        chevronImage.translatesAutoresizingMaskIntoConstraints = false
        rowBackground.addSubview(chevronImage)
        NSLayoutConstraint.activate([
            rowBackground.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            rowBackground.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            rowBackground.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 2),
            rowBackground.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -2),
            titleLabel.leadingAnchor.constraint(equalTo: rowBackground.leadingAnchor, constant: 16),
            titleLabel.centerYAnchor.constraint(equalTo: rowBackground.centerYAnchor),
            detailLabel.trailingAnchor.constraint(equalTo: rowBackground.trailingAnchor, constant: -8),
            detailLabel.centerYAnchor.constraint(equalTo: rowBackground.centerYAnchor),
            chevronImage.trailingAnchor.constraint(equalTo: rowBackground.trailingAnchor, constant: -8),
            chevronImage.centerYAnchor.constraint(equalTo: rowBackground.centerYAnchor),
            chevronImage.widthAnchor.constraint(equalToConstant: 16),
            chevronImage.heightAnchor.constraint(equalToConstant: 16),
        ])
        addGestureRecognizer(UIHoverGestureRecognizer(target: self, action: #selector(hover(_:))))
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(title: String, isActive: Bool, hasChevron: Bool, isBackRow: Bool,
                   isDimmed: Bool = false, detail: String? = nil, textSize: CGFloat = 14) {
        active = isActive
        dimmed = isDimmed
        titleLabel.text = title
        titleLabel.font = .nunito(ofSize: textSize, weight: .bold)
        titleLabel.numberOfLines = textSize == 12 ? 1 : 0
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = textSize == 12 ? 16 : 14
        paragraph.maximumLineHeight = paragraph.minimumLineHeight
        paragraph.lineBreakMode = textSize == 12 ? .byTruncatingTail : .byWordWrapping
        titleLabel.attributedText = NSAttributedString(string: title, attributes: [
            .font: titleLabel.font as Any, .paragraphStyle: paragraph,
            .baselineOffset: (paragraph.minimumLineHeight - titleLabel.font.lineHeight) / 2,
        ])
        detailLabel.text = detail
        detailLabel.isHidden = detail == nil
        chevronImage.isHidden = !hasChevron
        titleTrailing?.isActive = false
        if hasChevron {
            titleTrailing = titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: chevronImage.leadingAnchor, constant: -8)
        } else if detail != nil {
            titleTrailing = titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: detailLabel.leadingAnchor, constant: -8)
        } else {
            titleTrailing = titleLabel.trailingAnchor.constraint(equalTo: rowBackground.trailingAnchor)
        }
        titleTrailing?.isActive = true
        rowBackground.alpha = dimmed ? 0.3 : 1
        updateBackground(hovering: false)
        accessibilityLabel = detail.map { title + ", " + $0 } ?? title
        accessibilityTraits = isActive ? [.button, .selected] : .button
    }

    private func updateBackground(hovering: Bool) {
        rowBackground.backgroundColor = active ? UIColor.HayaseTheme.primary
            : hovering ? UIColor.HayaseTheme.accent : .clear
        titleLabel.textColor = active ? UIColor.HayaseTheme.background : UIColor.HayaseTheme.foreground
        detailLabel.textColor = active ? UIColor.HayaseTheme.background : UIColor.HayaseTheme.mutedForeground
        chevronImage.tintColor = titleLabel.textColor
    }

    override func setHighlighted(_ highlighted: Bool, animated: Bool) {
        super.setHighlighted(highlighted, animated: animated)
        updateBackground(hovering: highlighted)
    }
    @objc private func hover(_ gesture: UIHoverGestureRecognizer) {
        updateBackground(hovering: gesture.state == .began || gesture.state == .changed)
    }
}

final class PlayerSubtitleDelayCell: UITableViewCell {
    static let reuseID = "PlayerSubtitleDelayCell"
    var onValueChanged: ((Double) -> Void)?
    private let inputField = Input(placeholder: "")
    private let delayLabel = UILabel()
    private let secLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .none
        delayLabel.text = "Delay"
        secLabel.text = "sec"
        for label in [delayLabel, secLabel] {
            label.font = .nunito(ofSize: 14, weight: .bold)
            label.textColor = UIColor.HayaseTheme.foreground
            label.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(label)
        }
        inputField.keyboardType = .numbersAndPunctuation // Includes minus for negative delay.
        inputField.borderStyle = .none
        inputField.showsFocusRing = false // options.svelte border-0 !ring-0
        inputField.backgroundColor = UIColor.HayaseTheme.muted
        inputField.font = .nunito(ofSize: 14, weight: .bold)
        inputField.layer.cornerRadius = 2
        inputField.textAlignment = .right
        inputField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 48, height: 36))
        inputField.rightView = UIView(frame: CGRect(x: 0, y: 0, width: 48, height: 36))
        inputField.rightViewMode = .always
        inputField.addTarget(self, action: #selector(valueChanged), for: .editingChanged)
        contentView.addSubview(inputField)
        contentView.bringSubviewToFront(delayLabel)
        contentView.bringSubviewToFront(secLabel)
        let toolbar = UIToolbar()
        toolbar.sizeToFit()
        toolbar.items = [UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil),
                         UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(finishEditing))]
        inputField.inputAccessoryView = toolbar
        NSLayoutConstraint.activate([
            inputField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            inputField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            inputField.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            inputField.heightAnchor.constraint(equalToConstant: 36),
            delayLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            delayLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            secLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            secLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func prepareForReuse() { super.prepareForReuse(); onValueChanged = nil }
    func configure(value: Double) { inputField.text = String(format: "%.1f", value) }
    @objc private func finishEditing() { inputField.resignFirstResponder() }
    @objc private func valueChanged() {
        guard let text = inputField.text,
              let value = Double(text.replacingOccurrences(of: ",", with: ".")), value.isFinite else { return }
        onValueChanged?(value)
    }
}
