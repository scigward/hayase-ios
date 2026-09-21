// Settings UI cells shared across settings routes.
import UIKit

// MARK: - HayaseSettingToggleCell
//
// Mirrors SettingCard.svelte: muted card, 24/16 padding, 12pt gap, and
// vertical compact / horizontal md layout.

final class HayaseSettingToggleCell: UITableViewCell {
    static let reuseID = "HayaseSettingToggleCell"

    private let cardView = UIView()
    private let titleLabel = UILabel()
    private let descriptionLabel = UILabel()
    private let textStack = UIStackView()
    private let contentStack = UIStackView()
    private let toggle = UISwitch()
    private var userDefaultsKey = ""
    var onToggled: ((String) -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        selectionStyle = .none
        backgroundColor = .clear
        contentView.backgroundColor = .clear

        cardView.backgroundColor = UIColor.HayaseTheme.muted
        cardView.layer.cornerRadius = 6
        cardView.layer.masksToBounds = true
        cardView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(cardView)

        titleLabel.font = .nunito(ofSize: 16, weight: .bold)
        titleLabel.textColor = UIColor.HayaseTheme.foreground
        titleLabel.numberOfLines = 0

        descriptionLabel.font = .nunito(ofSize: 12)
        descriptionLabel.textColor = UIColor.HayaseTheme.mutedForeground
        descriptionLabel.numberOfLines = 0

        textStack.axis = .vertical
        textStack.spacing = 4
        textStack.addArrangedSubview(titleLabel)
        textStack.addArrangedSubview(descriptionLabel)

        toggle.onTintColor = UIColor.HayaseTheme.primary
        toggle.thumbTintColor = UIColor.HayaseTheme.primaryForeground
        toggle.transform = CGAffineTransform(scaleX: 0.82, y: 0.82)
        toggle.addTarget(self, action: #selector(toggled), for: .valueChanged)
        toggle.setContentHuggingPriority(.required, for: .horizontal)
        toggle.setContentCompressionResistancePriority(.required, for: .horizontal)

        contentStack.axis = .horizontal
        contentStack.alignment = .center
        contentStack.spacing = 12
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.addArrangedSubview(textStack)
        contentStack.addArrangedSubview(toggle)
        cardView.addSubview(contentStack)

        NSLayoutConstraint.activate([
            cardView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 6),
            cardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            cardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            cardView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6),
            contentStack.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 16),
            contentStack.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 24),
            contentStack.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -24),
            contentStack.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -16),
        ])
    }

    func configure(title: String,
                   description: String,
                   key: String,
                   defaultValue: Bool,
                   horizontal: Bool) {
        titleLabel.text = title
        descriptionLabel.text = description
        userDefaultsKey = key
        let stored = UserDefaults.standard.object(forKey: key) as? Bool ?? defaultValue
        toggle.setOn(stored, animated: false)
        applyLayout(horizontal: horizontal)
    }

    private func applyLayout(horizontal: Bool) {
        contentStack.axis = horizontal ? .horizontal : .vertical
        contentStack.alignment = horizontal ? .center : .leading
    }

    @objc private func toggled(_ sender: UISwitch) {
        Settings.write(sender.isOn, forKey: userDefaultsKey)
        onToggled?(userDefaultsKey)
    }
}

// MARK: - HayaseSettingValueCell

final class HayaseSettingValueCell: UITableViewCell {
    static let reuseID = "HayaseSettingValueCell"

    private let cardView = UIView()
    private let titleLabel = UILabel()
    private let descriptionLabel = UILabel()
    private let textStack = UIStackView()
    private let contentStack = UIStackView()
    private let controlView = UIView()
    private let comboBox = ComboBox()
    private let downloadLocationStack = UIStackView()
    private let downloadPathField = Input(placeholder: "/tmp/webtorrent")
    private let downloadLocationComboBox = ComboBox()
    private let valueLabel = UILabel()
    private let input = Input(placeholder: "")
    private var controlWidthConstraint: NSLayoutConstraint?
    private var comboWidthConstraint: NSLayoutConstraint?
    private var inputWidthConstraint: NSLayoutConstraint?
    var onInputEnded: ((String) -> String)?
    var selectionAnchor: UIView { downloadLocationStack.isHidden ? comboBox : downloadLocationComboBox }

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

        cardView.backgroundColor = UIColor.HayaseTheme.muted
        cardView.layer.cornerRadius = 6
        cardView.layer.masksToBounds = true
        cardView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(cardView)

        titleLabel.font = .nunito(ofSize: 16, weight: .bold)
        titleLabel.textColor = UIColor.HayaseTheme.foreground
        titleLabel.numberOfLines = 0

        descriptionLabel.font = .nunito(ofSize: 12)
        descriptionLabel.textColor = UIColor.HayaseTheme.mutedForeground
        descriptionLabel.numberOfLines = 0

        textStack.axis = .vertical
        textStack.spacing = 4
        textStack.addArrangedSubview(titleLabel)
        textStack.addArrangedSubview(descriptionLabel)

        controlView.backgroundColor = .clear
        controlView.layer.borderWidth = 1
        controlView.layer.borderColor = UIColor.HayaseTheme.input.cgColor
        controlView.layer.cornerRadius = 6

        valueLabel.font = .nunito(ofSize: 14)
        valueLabel.textColor = UIColor.HayaseTheme.foreground
        valueLabel.numberOfLines = 1
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        controlView.addSubview(valueLabel)
        NSLayoutConstraint.activate([
            valueLabel.leadingAnchor.constraint(equalTo: controlView.leadingAnchor, constant: 12),
            valueLabel.trailingAnchor.constraint(equalTo: controlView.trailingAnchor, constant: -12),
            valueLabel.centerYAnchor.constraint(equalTo: controlView.centerYAnchor),
            controlView.heightAnchor.constraint(equalToConstant: 36),
        ])
        controlWidthConstraint = controlView.widthAnchor.constraint(equalToConstant: 128)
        controlWidthConstraint?.priority = .defaultHigh
        controlWidthConstraint?.isActive = true
        controlView.setContentHuggingPriority(.required, for: .horizontal)
        controlView.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)

        comboBox.isUserInteractionEnabled = false // The table row handles selection.
        comboBox.backgroundColor = .clear
        comboBox.layer.borderWidth = 1
        comboBox.layer.borderColor = UIColor.HayaseTheme.input.cgColor
        comboWidthConstraint = comboBox.widthAnchor.constraint(equalToConstant: 128)
        comboWidthConstraint?.priority = .defaultHigh
        comboWidthConstraint?.isActive = true
        comboBox.setContentHuggingPriority(.required, for: .horizontal)
        comboBox.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        comboBox.isHidden = true

        input.layer.borderWidth = 1
        input.layer.borderColor = UIColor.HayaseTheme.input.cgColor
        input.heightAnchor.constraint(equalToConstant: 36).isActive = true
        inputWidthConstraint = input.widthAnchor.constraint(equalToConstant: 128)
        inputWidthConstraint?.priority = .defaultHigh
        inputWidthConstraint?.isActive = true
        input.setContentHuggingPriority(.required, for: .horizontal)
        input.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        input.addTarget(self, action: #selector(inputDidEndEditing), for: .editingDidEnd)
        input.addTarget(self, action: #selector(inputDidReturn), for: .editingDidEndOnExit)
        input.isHidden = true

        downloadLocationStack.axis = .horizontal
        downloadLocationStack.spacing = 0
        downloadLocationStack.alignment = .center
        downloadLocationStack.isHidden = true
        downloadPathField.isUserInteractionEnabled = false
        downloadPathField.layer.borderWidth = 1
        downloadPathField.layer.borderColor = UIColor.HayaseTheme.input.cgColor
        downloadPathField.layer.maskedCorners = [.layerMinXMinYCorner, .layerMinXMaxYCorner]
        downloadPathField.heightAnchor.constraint(equalToConstant: 36).isActive = true
        let pathWidth = downloadPathField.widthAnchor.constraint(equalToConstant: 240)
        pathWidth.priority = .defaultHigh
        pathWidth.isActive = true
        downloadLocationComboBox.isUserInteractionEnabled = false
        downloadLocationComboBox.layer.borderWidth = 1
        downloadLocationComboBox.layer.borderColor = UIColor.HayaseTheme.input.cgColor
        downloadLocationComboBox.layer.maskedCorners = [.layerMaxXMinYCorner, .layerMaxXMaxYCorner]
        let locationWidth = downloadLocationComboBox.widthAnchor.constraint(equalToConstant: 128)
        locationWidth.priority = .defaultHigh
        locationWidth.isActive = true
        downloadLocationStack.addArrangedSubview(downloadPathField)
        downloadLocationStack.addArrangedSubview(downloadLocationComboBox)
        downloadLocationStack.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)

        contentStack.axis = .horizontal
        contentStack.alignment = .center
        contentStack.spacing = 12
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.addArrangedSubview(textStack)
        contentStack.addArrangedSubview(controlView)
        contentStack.addArrangedSubview(comboBox)
        contentStack.addArrangedSubview(input)
        contentStack.addArrangedSubview(downloadLocationStack)
        cardView.addSubview(contentStack)

        NSLayoutConstraint.activate([
            downloadLocationStack.widthAnchor.constraint(lessThanOrEqualTo: contentStack.widthAnchor),
            cardView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 6),
            cardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            cardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            cardView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6),
            contentStack.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 16),
            contentStack.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 24),
            contentStack.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -24),
            contentStack.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -16),
        ])
    }

    func configure(title: String,
                   description: String,
                   value: String?,
                   isLink: Bool,
                   horizontal: Bool,
                   controlWidth: CGFloat = 128,
                   filledControl: Bool = false,
                   selectable: Bool = false) {
        titleLabel.text = title
        descriptionLabel.text = description
        valueLabel.text = value
        controlView.isHidden = value == nil || selectable
        comboBox.isHidden = !selectable
        input.isHidden = true
        downloadLocationStack.isHidden = true
        onInputEnded = nil
        comboBox.configure(text: value ?? "", placeholder: value == nil)
        controlWidthConstraint?.constant = controlWidth
        comboWidthConstraint?.constant = controlWidth
        controlView.backgroundColor = filledControl ? UIColor.HayaseTheme.primary : .clear
        controlView.layer.borderWidth = filledControl ? 0 : 1
        valueLabel.textColor = filledControl ? UIColor.HayaseTheme.primaryForeground : UIColor.HayaseTheme.foreground
        valueLabel.textAlignment = filledControl ? .center : .natural
        accessoryType = isLink ? .disclosureIndicator : .none
        selectionStyle = (isLink || value != nil) ? .default : .none
        contentStack.axis = horizontal ? .horizontal : .vertical
        contentStack.alignment = horizontal ? .center : .leading
    }

    func configureDownloadLocation(title: String, description: String,
                                   path: String, choice: String, horizontal: Bool) {
        configure(title: title, description: description, value: nil,
                  isLink: false, horizontal: horizontal)
        downloadPathField.text = path
        downloadLocationComboBox.configure(text: choice, placeholder: false)
        downloadLocationStack.isHidden = false
        selectionStyle = .default
    }

    func configureInput(title: String, description: String, value: String,
                        placeholder: String, secure: Bool, numeric: Bool,
                        suffix: String, horizontal: Bool, controlWidth: CGFloat) {
        configure(title: title, description: description, value: nil,
                  isLink: false, horizontal: horizontal)
        input.isHidden = false
        input.text = value
        input.attributedPlaceholder = NSAttributedString(
            string: placeholder,
            attributes: [.foregroundColor: UIColor.HayaseTheme.mutedForeground.withAlphaComponent(0.5)])
        input.isSecureTextEntry = secure
        input.keyboardType = numeric ? .numbersAndPunctuation : .default
        input.returnKeyType = .done
        inputWidthConstraint?.constant = controlWidth
        selectionStyle = .none

        if suffix.isEmpty {
            input.rightView = nil
            input.rightViewMode = .never
        } else {
            let label = UILabel(frame: CGRect(x: 0, y: 0, width: suffix == "Mb/s" ? 48 : 40, height: 36))
            label.text = suffix
            label.font = .nunito(ofSize: 14)
            label.textColor = UIColor.HayaseTheme.foreground
            input.rightView = label
            input.rightViewMode = .always
        }
    }

    @objc private func inputDidEndEditing() {
        guard let onInputEnded else { return }
        input.text = onInputEnded(input.text ?? "")
    }

    @objc private func inputDidReturn() {
        input.resignFirstResponder()
    }
}

// MARK: - HayaseAppActionsCell

/// Matches the web app page's one-column / md three-column action-button grid.
final class HayaseAppActionsCell: UITableViewCell {
    static let reuseID = "HayaseAppActionsCell"

    private let stack = UIStackView()
    var onAction: ((String) -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        selectionStyle = .none
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        stack.spacing = 12
        stack.distribution = .fillEqually
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        let importButton = makeButton("Import Settings From File", destructive: false)
        let exportButton = makeButton("Export Settings To File", destructive: false)
        let resetButton = makeButton("Reset EVERYTHING To Default", destructive: true)
        [importButton, exportButton, resetButton].forEach {
            $0.heightAnchor.constraint(greaterThanOrEqualToConstant: 40).isActive = true
            stack.addArrangedSubview($0)
        }

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 6),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6),
        ])
    }

    func configure(horizontal: Bool) {
        stack.axis = horizontal ? .horizontal : .vertical
    }

    private func makeButton(_ title: String, destructive: Bool) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.setTitleColor(destructive ? UIColor.HayaseTheme.destructiveForeground : UIColor.HayaseTheme.primaryForeground,
                             for: .normal)
        button.titleLabel?.font = .nunito(ofSize: 14, weight: .bold)
        button.titleLabel?.adjustsFontSizeToFitWidth = true
        button.titleLabel?.minimumScaleFactor = 0.75
        button.backgroundColor = destructive ? UIColor.HayaseTheme.destructive : UIColor.HayaseTheme.primary
        button.layer.cornerRadius = 6
        button.addTarget(self, action: #selector(actionTapped(_:)), for: .touchUpInside)
        return button
    }

    @objc private func actionTapped(_ sender: UIButton) {
        guard let title = sender.title(for: .normal) else { return }
        onAction?(title)
    }
}

// MARK: - HayaseSettingSliderCell

final class HayaseSettingSliderCell: UITableViewCell {
    static let reuseID = "HayaseSettingSliderCell"

    private let titleLabel = UILabel()
    private let descriptionLabel = UILabel()
    private let valueLabel = UILabel()
    private let slider = UISlider()
    private let contentStack = UIStackView()
    private var step: Float = 0.1
    var onValueChanged: ((Double) -> Void)?
    var onEditingEnded: (() -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        selectionStyle = .none
        backgroundColor = .clear
        contentView.backgroundColor = .clear

        let card = UIView()
        card.backgroundColor = UIColor.HayaseTheme.muted
        card.layer.cornerRadius = 6
        card.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(card)

        titleLabel.font = .nunito(ofSize: 16, weight: .bold)
        titleLabel.textColor = UIColor.HayaseTheme.foreground
        titleLabel.numberOfLines = 0
        descriptionLabel.font = .nunito(ofSize: 12)
        descriptionLabel.textColor = UIColor.HayaseTheme.mutedForeground
        descriptionLabel.numberOfLines = 0
        let text = UIStackView(arrangedSubviews: [titleLabel, descriptionLabel])
        text.axis = .vertical
        text.spacing = 4

        slider.minimumTrackTintColor = UIColor.HayaseTheme.primary
        slider.maximumTrackTintColor = UIColor.HayaseTheme.secondary
        let sliderWidth = slider.widthAnchor.constraint(equalToConstant: 240)
        sliderWidth.priority = .defaultHigh
        sliderWidth.isActive = true
        slider.addTarget(self, action: #selector(sliderChanged(_:)), for: .valueChanged)
        slider.addTarget(self, action: #selector(sliderEditingEnded),
                         for: [.touchUpInside, .touchUpOutside, .touchCancel])
        valueLabel.font = .nunito(ofSize: 12)
        valueLabel.textColor = UIColor.HayaseTheme.mutedForeground
        valueLabel.setContentHuggingPriority(.required, for: .horizontal)
        let control = UIStackView(arrangedSubviews: [slider, valueLabel])
        control.axis = .horizontal
        control.alignment = .center
        control.spacing = 12

        contentStack.axis = .horizontal
        contentStack.alignment = .center
        contentStack.spacing = 12
        contentStack.addArrangedSubview(text)
        contentStack.addArrangedSubview(control)
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(contentStack)

        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 6),
            card.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            card.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            card.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6),
            contentStack.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            contentStack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 24),
            contentStack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -24),
            contentStack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16),
        ])
    }

    func configure(title: String,
                   description: String,
                   value: Double,
                   min: Double,
                   max: Double,
                   step: Double,
                   horizontal: Bool) {
        titleLabel.text = title
        descriptionLabel.text = description
        slider.minimumValue = Float(min)
        slider.maximumValue = Float(max)
        self.step = Float(step)
        slider.setValue(Float(value), animated: false)
        valueLabel.text = String(format: "%.1f", value)
        contentStack.axis = horizontal ? .horizontal : .vertical
        contentStack.alignment = horizontal ? .center : .leading
    }

    @objc private func sliderChanged(_ sender: UISlider) {
        let rounded = (sender.value / step).rounded() * step
        sender.value = rounded
        valueLabel.text = String(format: "%.1f", rounded)
        onValueChanged?(Double(rounded))
    }

    @objc private func sliderEditingEnded() {
        onEditingEnded?()
    }
}

// MARK: - HayaseSettingsPreviewGridCell

/// UI-only counterpart of the web ToggleGroup preview grids. Selection wiring is
/// deliberately deferred, but the complete option set and responsive layout are present.
final class HayaseSettingsPreviewGridCell: UITableViewCell {
    static let reuseID = "HayaseSettingsPreviewGridCell"

    private let cardView = UIView()
    private let titleLabel = UILabel()
    private let descriptionLabel = UILabel()
    private let gridStack = UIStackView()
    private var tileValues: [ObjectIdentifier: String] = [:]
    var onSelection: ((String) -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        selectionStyle = .none
        backgroundColor = .clear
        contentView.backgroundColor = .clear

        cardView.backgroundColor = UIColor.HayaseTheme.muted
        cardView.layer.cornerRadius = 6
        cardView.layer.masksToBounds = true
        cardView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(cardView)

        titleLabel.font = .nunito(ofSize: 16, weight: .bold)
        titleLabel.textColor = UIColor.HayaseTheme.foreground
        titleLabel.numberOfLines = 0

        descriptionLabel.font = .nunito(ofSize: 12)
        descriptionLabel.textColor = UIColor.HayaseTheme.mutedForeground
        descriptionLabel.numberOfLines = 0

        gridStack.axis = .vertical
        gridStack.spacing = 12

        let stack = UIStackView(arrangedSubviews: [titleLabel, descriptionLabel, gridStack])
        stack.axis = .vertical
        stack.spacing = 4
        stack.setCustomSpacing(12, after: descriptionLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(stack)

        NSLayoutConstraint.activate([
            cardView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 6),
            cardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            cardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            cardView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6),
            stack.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -24),
            stack.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -16),
        ])
    }

    func configure(title: String,
                               description: String,
                               kind: SettingsPreviewKind,
                               selectedValue: String,
                               twoColumns: Bool) {
        titleLabel.text = title
        descriptionLabel.text = description
        clearGrid()
        tileValues.removeAll()

        let tiles: [UIView]
        switch kind {
        case .subtitleStyle:
            tiles = [
                makeSubtitleTile(title: "None", value: "none", sample: "🚫", image: nil, selected: selectedValue == "none"),
                makeSubtitleTile(title: "Gandhi Sans Bold", value: "gandhisans", sample: "", image: HayaseSettingsArtwork.gandhiSans, selected: selectedValue == "gandhisans"),
                makeSubtitleTile(title: "Noto Sans Bold", value: "notosans", sample: "", image: HayaseSettingsArtwork.notoSans, selected: selectedValue == "notosans"),
                makeSubtitleTile(title: "Roboto Bold", value: "roboto", sample: "", image: HayaseSettingsArtwork.roboto, selected: selectedValue == "roboto"),
            ]
        case .colorTheme:
            tiles = [
                makeThemeTile(title: "Blackout", background: UIColor(red: 0.035, green: 0.035, blue: 0.043, alpha: 1), foreground: .white, accent: UIColor(red: 0.82, green: 0.22, blue: 0.49, alpha: 1), selected: selectedValue == "default"),
                makeThemeTile(title: "Whiteout", background: UIColor(white: 0.97, alpha: 1), foreground: UIColor(white: 0.08, alpha: 1), accent: UIColor(white: 0.15, alpha: 1), selected: false),
                makeThemeTile(title: "Catppuccin", background: UIColor(red: 0.12, green: 0.12, blue: 0.18, alpha: 1), foreground: UIColor(red: 0.80, green: 0.84, blue: 0.96, alpha: 1), accent: UIColor(red: 0.80, green: 0.65, blue: 0.97, alpha: 1), selected: false),
                makeThemeTile(title: "Dracula", background: UIColor(red: 0.16, green: 0.16, blue: 0.21, alpha: 1), foreground: UIColor(red: 0.97, green: 0.97, blue: 0.95, alpha: 1), accent: UIColor(red: 1.0, green: 0.47, blue: 0.78, alpha: 1), selected: false),
                makeThemeTile(title: "Amber", background: UIColor(red: 0.10, green: 0.08, blue: 0.04, alpha: 1), foreground: UIColor(red: 1.0, green: 0.91, blue: 0.66, alpha: 1), accent: UIColor(red: 0.96, green: 0.62, blue: 0.04, alpha: 1), selected: false),
                makeThemeTile(title: "Lavender", background: UIColor(red: 0.10, green: 0.08, blue: 0.16, alpha: 1), foreground: UIColor(red: 0.92, green: 0.88, blue: 1, alpha: 1), accent: UIColor(red: 0.60, green: 0.48, blue: 0.94, alpha: 1), selected: false),
                makeThemeTile(title: "System", background: UIColor.HayaseTheme.background, foreground: UIColor.HayaseTheme.foreground, accent: UIColor.HayaseTheme.primary, selected: false),
                makeThemeTile(title: "Custom", background: UIColor(red: 0.08, green: 0.11, blue: 0.13, alpha: 1), foreground: UIColor(red: 0.78, green: 0.96, blue: 0.90, alpha: 1), accent: UIColor(red: 0.19, green: 0.78, blue: 0.62, alpha: 1), selected: false),
            ]
        }

        let columns = twoColumns ? 2 : 1
        for start in stride(from: 0, to: tiles.count, by: columns) {
            let row = UIStackView()
            row.axis = .horizontal
            row.alignment = .fill
            row.distribution = .fillEqually
            row.spacing = 12
            for index in start ..< min(start + columns, tiles.count) {
                row.addArrangedSubview(tiles[index])
            }
            if columns == 2 && row.arrangedSubviews.count == 1 {
                let spacer = UIView()
                spacer.isHidden = true
                row.addArrangedSubview(spacer)
            }
            gridStack.addArrangedSubview(row)
        }
    }

    private func clearGrid() {
        for row in gridStack.arrangedSubviews {
            gridStack.removeArrangedSubview(row)
            row.removeFromSuperview()
        }
    }

    private func makeSubtitleTile(title: String,
                                  value: String,
                                  sample: String,
                                  image: UIImage?,
                                  selected: Bool) -> UIView {
        let tile = previewContainer(selected: selected, value: value)
        tile.accessibilityLabel = title
        tile.backgroundColor = UIColor.HayaseTheme.background.withAlphaComponent(0.4)

        let name = previewLabel(title, size: 20, weight: .bold, color: UIColor.HayaseTheme.foreground)
        let sampleLabel = previewLabel(sample, size: title == "None" ? 36 : 17, weight: .bold, color: .white)
        sampleLabel.textAlignment = .center
        sampleLabel.isHidden = image != nil
        sampleLabel.layer.shadowColor = UIColor.black.cgColor
        sampleLabel.layer.shadowOpacity = 1
        sampleLabel.layer.shadowRadius = 2
        sampleLabel.layer.shadowOffset = CGSize(width: 1, height: 1)

        let video = UIView()
        video.backgroundColor = UIColor(white: 0.08, alpha: 1)
        video.layer.cornerRadius = 4
        video.clipsToBounds = true
        video.translatesAutoresizingMaskIntoConstraints = false
        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFill
        imageView.isHidden = image == nil
        imageView.translatesAutoresizingMaskIntoConstraints = false
        video.addSubview(imageView)
        video.addSubview(sampleLabel)
        sampleLabel.translatesAutoresizingMaskIntoConstraints = false
        tile.addSubview(video)
        tile.addSubview(name)

        NSLayoutConstraint.activate([
            name.topAnchor.constraint(equalTo: tile.topAnchor, constant: 16),
            name.leadingAnchor.constraint(equalTo: tile.leadingAnchor, constant: 16),
            name.trailingAnchor.constraint(lessThanOrEqualTo: tile.trailingAnchor, constant: -16),
            video.topAnchor.constraint(equalTo: tile.topAnchor),
            video.leadingAnchor.constraint(equalTo: tile.leadingAnchor),
            video.trailingAnchor.constraint(equalTo: tile.trailingAnchor),
            video.bottomAnchor.constraint(equalTo: tile.bottomAnchor),
            video.heightAnchor.constraint(equalTo: video.widthAnchor, multiplier: 9.0 / 16.0),
            imageView.topAnchor.constraint(equalTo: video.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: video.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: video.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: video.bottomAnchor),
            sampleLabel.centerXAnchor.constraint(equalTo: video.centerXAnchor),
            sampleLabel.centerYAnchor.constraint(equalTo: video.centerYAnchor),
            sampleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: video.leadingAnchor, constant: 8),
            sampleLabel.trailingAnchor.constraint(lessThanOrEqualTo: video.trailingAnchor, constant: -8),
        ])
        return tile
    }

    private func makeThemeTile(title: String,
                               background: UIColor,
                               foreground: UIColor,
                               accent: UIColor,
                               selected: Bool) -> UIView {
        let tile = previewContainer(selected: selected, value: nil)
        tile.backgroundColor = background.withAlphaComponent(0.92)

        let name = previewLabel(title, size: 20, weight: .bold, color: foreground)
        let sample = previewLabel("The quick brown fox", size: 12, weight: .regular, color: foreground.withAlphaComponent(0.85))
        let muted = previewLabel("Muted description text", size: 10, weight: .regular, color: foreground.withAlphaComponent(0.55))
        let primary = miniButton("Primary", background: accent, foreground: background)
        let secondary = miniButton("Secondary", background: foreground.withAlphaComponent(0.12), foreground: foreground)
        let ghost = miniButton("Ghost", background: .clear, foreground: foreground)
        let buttons = UIStackView(arrangedSubviews: [primary, secondary, ghost])
        buttons.axis = .horizontal
        buttons.spacing = 6
        buttons.alignment = .center

        let input = UIView()
        input.layer.borderWidth = 1
        input.layer.borderColor = foreground.withAlphaComponent(0.25).cgColor
        input.layer.cornerRadius = 4
        let inputLabel = previewLabel("Sample", size: 10, weight: .regular, color: foreground)
        input.addSubview(inputLabel)
        inputLabel.translatesAutoresizingMaskIntoConstraints = false

        let switchTrack = UIView()
        switchTrack.backgroundColor = foreground.withAlphaComponent(0.18)
        switchTrack.layer.cornerRadius = 7
        switchTrack.translatesAutoresizingMaskIntoConstraints = false
        let thumb = UIView()
        thumb.backgroundColor = foreground
        thumb.layer.cornerRadius = 5
        thumb.translatesAutoresizingMaskIntoConstraints = false
        switchTrack.addSubview(thumb)

        let sliderTrack = UIView()
        sliderTrack.backgroundColor = foreground.withAlphaComponent(0.18)
        sliderTrack.layer.cornerRadius = 1.5
        sliderTrack.translatesAutoresizingMaskIntoConstraints = false
        let sliderFill = UIView()
        sliderFill.backgroundColor = accent
        sliderFill.layer.cornerRadius = 1.5
        sliderFill.translatesAutoresizingMaskIntoConstraints = false
        sliderTrack.addSubview(sliderFill)

        let body = UIStackView(arrangedSubviews: [sample, muted, buttons, input, switchTrack, sliderTrack])
        body.axis = .vertical
        body.alignment = .center
        body.spacing = 5
        body.translatesAutoresizingMaskIntoConstraints = false
        tile.addSubview(name)
        tile.addSubview(body)

        NSLayoutConstraint.activate([
            tile.heightAnchor.constraint(equalToConstant: 190),
            name.topAnchor.constraint(equalTo: tile.topAnchor, constant: 16),
            name.leadingAnchor.constraint(equalTo: tile.leadingAnchor, constant: 16),
            name.trailingAnchor.constraint(lessThanOrEqualTo: tile.trailingAnchor, constant: -16),
            body.topAnchor.constraint(equalTo: name.bottomAnchor, constant: 12),
            body.centerXAnchor.constraint(equalTo: tile.centerXAnchor),
            body.widthAnchor.constraint(lessThanOrEqualToConstant: 260),
            body.leadingAnchor.constraint(greaterThanOrEqualTo: tile.leadingAnchor, constant: 12),
            body.trailingAnchor.constraint(lessThanOrEqualTo: tile.trailingAnchor, constant: -12),
            body.bottomAnchor.constraint(lessThanOrEqualTo: tile.bottomAnchor, constant: -12),
            input.heightAnchor.constraint(equalToConstant: 24),
            input.widthAnchor.constraint(equalTo: body.widthAnchor),
            inputLabel.leadingAnchor.constraint(equalTo: input.leadingAnchor, constant: 8),
            inputLabel.centerYAnchor.constraint(equalTo: input.centerYAnchor),
            switchTrack.widthAnchor.constraint(equalToConstant: 28),
            switchTrack.heightAnchor.constraint(equalToConstant: 14),
            thumb.widthAnchor.constraint(equalToConstant: 10),
            thumb.heightAnchor.constraint(equalToConstant: 10),
            thumb.leadingAnchor.constraint(equalTo: switchTrack.leadingAnchor, constant: 2),
            thumb.centerYAnchor.constraint(equalTo: switchTrack.centerYAnchor),
            sliderTrack.heightAnchor.constraint(equalToConstant: 3),
            sliderTrack.widthAnchor.constraint(equalTo: body.widthAnchor),
            sliderFill.leadingAnchor.constraint(equalTo: sliderTrack.leadingAnchor),
            sliderFill.topAnchor.constraint(equalTo: sliderTrack.topAnchor),
            sliderFill.bottomAnchor.constraint(equalTo: sliderTrack.bottomAnchor),
            sliderFill.widthAnchor.constraint(equalTo: sliderTrack.widthAnchor, multiplier: 0.4),
        ])
        return tile
    }

    private func previewContainer(selected: Bool, value: String?) -> UIControl {
        let view = UIControl()
        view.layer.cornerRadius = 6
        view.layer.borderWidth = selected ? 2 : 1
        view.layer.borderColor = (selected ? UIColor.HayaseTheme.primary : UIColor.HayaseTheme.border).cgColor
        if let value {
            tileValues[ObjectIdentifier(view)] = value
            view.isAccessibilityElement = true
            view.accessibilityTraits = selected ? [.button, .selected] : .button
            view.addTarget(self, action: #selector(tileTapped(_:)), for: .touchUpInside)
        }
        return view
    }

    @objc private func tileTapped(_ sender: UIControl) {
        guard let value = tileValues[ObjectIdentifier(sender)] else { return }
        onSelection?(value)
    }

    private func previewLabel(_ text: String,
                              size: CGFloat,
                              weight: UIFont.Weight,
                              color: UIColor) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .nunito(ofSize: size, weight: weight)
        label.textColor = color
        label.numberOfLines = 1
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    private func miniButton(_ title: String, background: UIColor, foreground: UIColor) -> UILabel {
        let label = previewLabel(title, size: 9, weight: .bold, color: foreground)
        label.backgroundColor = background
        label.textAlignment = .center
        label.layer.cornerRadius = 4
        label.layer.masksToBounds = true
        label.widthAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true
        label.heightAnchor.constraint(equalToConstant: 22).isActive = true
        return label
    }
}

// MARK: - HayaseChangelogPlaceholderCell

final class HayaseChangelogPlaceholderCell: UITableViewCell {
    static let reuseID = "HayaseChangelogPlaceholderCell"

    private let rootStack = UIStackView()
    private let intro = UIStackView()
    private let titleLabel = UILabel()
    private let descriptionLabel = UILabel()
    private let entries = UIStackView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        selectionStyle = .none
        backgroundColor = .clear
        contentView.backgroundColor = .clear

        titleLabel.font = .nunito(ofSize: 36, weight: .bold)
        titleLabel.textColor = UIColor.HayaseTheme.foreground
        descriptionLabel.font = .nunito(ofSize: 14)
        descriptionLabel.textColor = UIColor.HayaseTheme.mutedForeground

        intro.axis = .vertical
        intro.spacing = 12
        intro.addArrangedSubview(titleLabel)
        intro.addArrangedSubview(descriptionLabel)
        intro.isLayoutMarginsRelativeArrangement = true
        intro.layoutMargins = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        intro.heightAnchor.constraint(equalToConstant: 240).isActive = true

        entries.axis = .vertical
        entries.spacing = 0

        rootStack.axis = .vertical
        rootStack.addArrangedSubview(intro)
        rootStack.addArrangedSubview(entries)
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(rootStack)
        NSLayoutConstraint.activate([
            rootStack.topAnchor.constraint(equalTo: contentView.topAnchor),
            rootStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            rootStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            rootStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
    }

    func configure(title: String,
                   description: String,
                   wide: Bool,
                   loadedEntries: [HayaseChangelogEntry]?,
                   error: String?) {
        titleLabel.text = title
        descriptionLabel.text = description
        let left = wide ? max(0, contentView.bounds.width * 0.25) : 16
        intro.layoutMargins = UIEdgeInsets(top: 0, left: left, bottom: 0, right: 16)
        intro.alignment = .fill

        entries.arrangedSubviews.forEach {
            entries.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        if let loadedEntries {
            if loadedEntries.isEmpty {
                entries.addArrangedSubview(HayaseChangelogMessageView(
                    title: "No changes found",
                    message: "The changelog is currently empty."))
            } else {
                loadedEntries.forEach {
                    entries.addArrangedSubview(HayaseChangelogEntryView(entry: $0, wide: wide))
                }
            }
        } else if let error {
            entries.addArrangedSubview(HayaseChangelogMessageView(
                title: "Failed to load changelog",
                message: error))
        } else {
            for _ in 0..<5 {
                let entry = HayaseChangelogSkeletonEntry()
                entry.configure(wide: wide)
                entries.addArrangedSubview(entry)
            }
        }
    }
}

private final class HayaseChangelogEntryView: UIView {
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d, yyyy"
        return formatter
    }()

    init(entry: HayaseChangelogEntry, wide: Bool) {
        super.init(frame: .zero)

        let separator = UIView()
        separator.backgroundColor = UIColor.HayaseTheme.border
        separator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(separator)

        let dateLabel = UILabel()
        dateLabel.text = Self.dateFormatter.string(from: entry.date)
        dateLabel.font = .nunito(ofSize: 12)
        dateLabel.textColor = UIColor.HayaseTheme.mutedForeground

        let commitLabel = UILabel()
        commitLabel.text = String(entry.sha.prefix(6))
        commitLabel.font = .monospacedSystemFont(ofSize: 17, weight: .semibold)
        commitLabel.textColor = UIColor.HayaseTheme.foreground

        let bodyLabel = UILabel()
        bodyLabel.text = entry.body.replacingOccurrences(of: "- ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        bodyLabel.font = .nunito(ofSize: 14)
        bodyLabel.textColor = UIColor.HayaseTheme.mutedForeground
        bodyLabel.numberOfLines = 0

        let body = UIStackView(arrangedSubviews: [commitLabel, bodyLabel])
        body.axis = .vertical
        body.alignment = .fill
        body.spacing = 8

        let dateContainer = UIView()
        dateContainer.addSubview(dateLabel)
        dateLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            dateLabel.topAnchor.constraint(equalTo: dateContainer.topAnchor),
            dateLabel.leadingAnchor.constraint(equalTo: dateContainer.leadingAnchor, constant: wide ? 16 : 0),
            dateLabel.trailingAnchor.constraint(lessThanOrEqualTo: dateContainer.trailingAnchor, constant: -12),
            dateLabel.bottomAnchor.constraint(equalTo: dateContainer.bottomAnchor),
        ])

        let content = UIStackView()
        content.axis = wide ? .horizontal : .vertical
        content.alignment = .top
        content.spacing = wide ? 0 : 16
        if wide {
            content.addArrangedSubview(dateContainer)
            content.addArrangedSubview(body)
            dateContainer.widthAnchor.constraint(equalTo: content.widthAnchor, multiplier: 0.25).isActive = true
        } else {
            content.addArrangedSubview(body)
            content.addArrangedSubview(dateContainer)
        }
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)

        NSLayoutConstraint.activate([
            separator.topAnchor.constraint(equalTo: topAnchor, constant: 24),
            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1),
            content.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 16),
            content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: wide ? 0 : 16),
            content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            content.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private final class HayaseChangelogMessageView: UIView {
    init(title: String, message: String) {
        super.init(frame: .zero)
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .nunito(ofSize: 18, weight: .bold)
        titleLabel.textColor = UIColor.HayaseTheme.foreground
        let messageLabel = UILabel()
        messageLabel.text = message
        messageLabel.font = .nunito(ofSize: 13)
        messageLabel.textColor = UIColor.HayaseTheme.mutedForeground
        messageLabel.numberOfLines = 0
        let stack = UIStackView(arrangedSubviews: [titleLabel, messageLabel])
        stack.axis = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(greaterThanOrEqualToConstant: 180),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private final class HayaseChangelogSkeletonEntry: UIView {
    private let dateContainer = UIView()
    private let dateSkeleton = HayaseChangelogSkeletonEntry.skeleton(width: 112, height: 8)
    private let body = UIStackView()
    private let content = UIStackView()
    private lazy var wideDateWidth = dateContainer.widthAnchor.constraint(equalTo: widthAnchor, multiplier: 0.25)

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        let separator = UIView()
        separator.backgroundColor = UIColor.HayaseTheme.border
        separator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(separator)

        dateSkeleton.translatesAutoresizingMaskIntoConstraints = false
        dateContainer.addSubview(dateSkeleton)
        NSLayoutConstraint.activate([
            dateContainer.heightAnchor.constraint(greaterThanOrEqualToConstant: 24),
            dateSkeleton.topAnchor.constraint(equalTo: dateContainer.topAnchor, constant: 8),
            dateSkeleton.leadingAnchor.constraint(equalTo: dateContainer.leadingAnchor, constant: 16),
            dateSkeleton.trailingAnchor.constraint(lessThanOrEqualTo: dateContainer.trailingAnchor, constant: -12),
            dateSkeleton.bottomAnchor.constraint(lessThanOrEqualTo: dateContainer.bottomAnchor),
        ])

        let heading = Self.skeleton(width: 192, height: 16)
        let line1 = Self.skeleton(width: 128, height: 8)
        let line2 = Self.skeleton(width: 112, height: 8)
        body.addArrangedSubview(heading)
        body.addArrangedSubview(line1)
        body.addArrangedSubview(line2)
        body.axis = .vertical
        body.alignment = .leading
        body.spacing = 8
        body.setCustomSpacing(12, after: heading)
        content.axis = .horizontal
        content.alignment = .top
        content.spacing = 0
        content.translatesAutoresizingMaskIntoConstraints = false
        content.addArrangedSubview(dateContainer)
        content.addArrangedSubview(body)
        addSubview(content)

        NSLayoutConstraint.activate([
            separator.topAnchor.constraint(equalTo: topAnchor, constant: 24),
            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1),
            content.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 16),
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            content.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
        ])
        configure(wide: true)
    }

    func configure(wide: Bool) {
        wideDateWidth.isActive = false
        for view in content.arrangedSubviews {
            content.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        content.axis = wide ? .horizontal : .vertical
        content.spacing = wide ? 0 : 16
        if wide {
            content.addArrangedSubview(dateContainer)
            content.addArrangedSubview(body)
        } else {
            content.addArrangedSubview(body)
            content.addArrangedSubview(dateContainer)
        }
        wideDateWidth.isActive = wide
    }

    private static func skeleton(width: CGFloat, height: CGFloat) -> UIView {
        let view = UIView()
        view.backgroundColor = UIColor.HayaseTheme.primary.withAlphaComponent(0.05)
        view.layer.cornerRadius = min(4, height / 2)
        view.widthAnchor.constraint(equalToConstant: width).isActive = true
        view.heightAnchor.constraint(equalToConstant: height).isActive = true
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 0.45
        pulse.toValue = 1
        pulse.duration = 0.9
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        view.layer.add(pulse, forKey: "hayasePulse")
        return view
    }
}

// Legacy names retained for source compatibility.
typealias SettingsToggleCell = HayaseSettingToggleCell
typealias SettingsDetailCell = HayaseSettingValueCell
