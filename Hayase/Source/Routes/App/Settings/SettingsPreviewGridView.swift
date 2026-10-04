// Mirrors: src/routes/app/settings/{player,interface}/+page.svelte
import UIKit

final class SettingsPreviewGridView: UIView, SettingsResponsiveView {

    private let cardView = UIView()
    private let titleLabel = UILabel()
    private let descriptionLabel = UILabel()
    private let gridStack = UIStackView()
    private var tileValues: [ObjectIdentifier: String] = [:]
    var onSelection: ((String) -> Void)?
    private var configuration: (String, String, SettingsPreviewKind, String)?
    private var currentTwoColumns = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        backgroundColor = .clear

        cardView.backgroundColor = UIColor.HayaseTheme.muted
        cardView.layer.cornerRadius = 6
        cardView.layer.masksToBounds = true
        cardView.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(cardView)

        titleLabel.numberOfLines = 0
        descriptionLabel.numberOfLines = 0

        gridStack.axis = .vertical
        gridStack.spacing = 12

        let stack = UIStackView(arrangedSubviews: [titleLabel, descriptionLabel, gridStack])
        stack.axis = .vertical
        stack.spacing = 0
        stack.setCustomSpacing(12, after: descriptionLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(stack)

        NSLayoutConstraint.activate([
            cardView.topAnchor.constraint(equalTo: self.topAnchor, constant: 0),
            cardView.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            cardView.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            cardView.bottomAnchor.constraint(equalTo: self.bottomAnchor, constant: 0),
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
        configuration = (title, description, kind, selectedValue)
        currentTwoColumns = twoColumns
        titleLabel.font = .nunito(ofSize: 14, weight: .bold)
        titleLabel.attributedText = SettingsTypography.label(title, size: 14, lineHeight: 21, weight: .bold).attributedText
        descriptionLabel.font = .nunito(ofSize: 12, weight: .medium)
        descriptionLabel.attributedText = SettingsTypography.label(description, size: 12, lineHeight: 16,
            weight: .medium, color: UIColor.HayaseTheme.mutedForeground).attributedText
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
            tiles = ["Blackout", "Whiteout", "Catppuccin", "Dracula", "Amber", "Lavender", "System", "Custom"].map {
                makeThemeTile(title: $0, palette: SettingsThemePreviewPalette.named($0))
            }
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

    func updateLayout(viewportWidth: CGFloat) {
        guard currentTwoColumns != (viewportWidth >= 640), let configuration else { return }
        configure(title: configuration.0, description: configuration.1, kind: configuration.2,
                  selectedValue: configuration.3, twoColumns: viewportWidth >= 640)
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
        tile.backgroundColor = selected ? UIColor.HayaseTheme.accent : .clear

        let name = previewLabel(title, size: 20, lineHeight: 28, weight: .bold, color: UIColor.HayaseTheme.foreground)
        let sampleLabel = previewLabel(sample, size: title == "None" ? 36 : 17,
            lineHeight: title == "None" ? 40 : 24, weight: .medium, color: .white)
        sampleLabel.textAlignment = .center
        sampleLabel.isHidden = image != nil

        let video = UIView()
        video.isUserInteractionEnabled = false
        video.backgroundColor = .clear
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
            name.centerXAnchor.constraint(equalTo: tile.centerXAnchor),
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

    private func makeThemeTile(title: String, palette: SettingsThemePreviewPalette) -> UIView {
        let tile = previewContainer(selected: false, value: nil)
        tile.backgroundColor = palette.background.withAlphaComponent(0.4)
        let name = previewLabel(title, size: 20, lineHeight: 28, weight: .bold, color: palette.foreground)
        let sample = SettingsTypography.label("The quick brown fox", size: 12, lineHeight: 16,
            weight: .medium, color: palette.foreground.withAlphaComponent(0.85))
        let muted = SettingsTypography.label("Muted description text", size: 10, lineHeight: 15,
            weight: .medium, color: palette.mutedForeground)
        let buttons = UIStackView(arrangedSubviews: [
            miniButton("Primary", background: palette.primary, foreground: palette.primaryForeground, shadow: false),
            miniButton("Secondary", background: palette.secondary, foreground: palette.foreground, shadow: true),
            miniButton("Ghost", background: .clear, foreground: palette.foreground),
        ])
        buttons.spacing = 6
        let input = UIView()
        input.backgroundColor = palette.muted
        input.layer.cornerRadius = 6
        input.layer.borderWidth = 1
        input.layer.borderColor = palette.input.cgColor
        SettingsTypography.applyButtonShadow(to: input, small: true)
        input.heightAnchor.constraint(equalToConstant: 24).isActive = true
        let inputLabel = SettingsTypography.label("Sample", size: 10, lineHeight: 15,
            weight: .medium, color: palette.foreground)
        inputLabel.translatesAutoresizingMaskIntoConstraints = false
        input.addSubview(inputLabel)
        NSLayoutConstraint.activate([
            inputLabel.leadingAnchor.constraint(equalTo: input.leadingAnchor, constant: 12),
            inputLabel.trailingAnchor.constraint(equalTo: input.trailingAnchor, constant: -12),
            inputLabel.centerYAnchor.constraint(equalTo: input.centerYAnchor),
        ])
        let switchTrack = UIView()
        switchTrack.backgroundColor = palette.input
        switchTrack.layer.cornerRadius = 8
        switchTrack.widthAnchor.constraint(equalToConstant: 32).isActive = true
        switchTrack.heightAnchor.constraint(equalToConstant: 16).isActive = true
        SettingsTypography.applyButtonShadow(to: switchTrack, small: true)
        let thumb = UIView(frame: CGRect(x: 2, y: 2, width: 12, height: 12))
        thumb.backgroundColor = palette.background
        thumb.layer.cornerRadius = 6
        // The same shadow-lg token as the shared HayaseSwitch thumb.
        thumb.layer.shadowColor = UIColor.black.cgColor
        thumb.layer.shadowOpacity = 0.1
        thumb.layer.shadowOffset = CGSize(width: 0, height: 10)
        thumb.layer.shadowRadius = 7.5
        thumb.layer.shadowPath = UIBezierPath(roundedRect: thumb.bounds.insetBy(dx: 3, dy: 3), cornerRadius: 3).cgPath
        switchTrack.addSubview(thumb)
        let slider = UIView()
        // Melt UI absolutely positions its 16pt thumb, so the web slider's
        // layout height remains the 6pt track height, with the thumb overflowing.
        slider.heightAnchor.constraint(equalToConstant: 6).isActive = true
        let sliderTrack = UIView()
        sliderTrack.backgroundColor = palette.primary.withAlphaComponent(0.2)
        sliderTrack.layer.cornerRadius = 3
        sliderTrack.clipsToBounds = true
        sliderTrack.translatesAutoresizingMaskIntoConstraints = false
        slider.addSubview(sliderTrack)
        let fill = UIView()
        fill.backgroundColor = palette.primary
        fill.translatesAutoresizingMaskIntoConstraints = false
        let sliderThumb = UIView()
        sliderThumb.backgroundColor = palette.background
        sliderThumb.layer.borderWidth = 1
        sliderThumb.layer.borderColor = palette.primary.withAlphaComponent(0.5).cgColor
        sliderThumb.layer.cornerRadius = 8
        SettingsTypography.applyButtonShadow(to: sliderThumb, small: false)
        sliderThumb.translatesAutoresizingMaskIntoConstraints = false
        sliderTrack.addSubview(fill)
        slider.addSubview(sliderThumb)
        NSLayoutConstraint.activate([
            sliderTrack.leadingAnchor.constraint(equalTo: slider.leadingAnchor),
            sliderTrack.trailingAnchor.constraint(equalTo: slider.trailingAnchor),
            sliderTrack.centerYAnchor.constraint(equalTo: slider.centerYAnchor),
            sliderTrack.heightAnchor.constraint(equalToConstant: 6),
            fill.leadingAnchor.constraint(equalTo: sliderTrack.leadingAnchor),
            fill.topAnchor.constraint(equalTo: sliderTrack.topAnchor),
            fill.bottomAnchor.constraint(equalTo: sliderTrack.bottomAnchor),
            fill.widthAnchor.constraint(equalTo: sliderTrack.widthAnchor, multiplier: 0.4),
            sliderThumb.centerXAnchor.constraint(equalTo: fill.trailingAnchor),
            sliderThumb.centerYAnchor.constraint(equalTo: slider.centerYAnchor),
            sliderThumb.widthAnchor.constraint(equalToConstant: 16),
            sliderThumb.heightAnchor.constraint(equalToConstant: 16),
        ])
        let body = UIStackView(arrangedSubviews: [sample, muted, buttons, input, switchTrack, slider])
        body.axis = .vertical
        body.alignment = .center
        body.spacing = 6
        body.setCustomSpacing(4, after: sample)
        body.translatesAutoresizingMaskIntoConstraints = false
        body.isUserInteractionEnabled = false
        tile.addSubview(name)
        tile.addSubview(body)
        let bodyWidth = body.widthAnchor.constraint(lessThanOrEqualTo: tile.widthAnchor, constant: -80)
        // Like CSS flex children, the sample buttons may overflow an exceptionally
        // narrow tile rather than breaking required Auto Layout constraints.
        bodyWidth.priority = .defaultHigh
        NSLayoutConstraint.activate([
            name.topAnchor.constraint(equalTo: tile.topAnchor, constant: 16),
            name.leadingAnchor.constraint(equalTo: tile.leadingAnchor, constant: 16),
            body.topAnchor.constraint(equalTo: tile.topAnchor, constant: 48),
            body.bottomAnchor.constraint(equalTo: tile.bottomAnchor, constant: -32),
            body.centerXAnchor.constraint(equalTo: tile.centerXAnchor),
            body.widthAnchor.constraint(lessThanOrEqualToConstant: 212),
            // The item has px-4 in addition to the body's px-6.
            bodyWidth,
            input.widthAnchor.constraint(equalTo: body.widthAnchor),
            slider.widthAnchor.constraint(equalTo: body.widthAnchor),
        ])
        return tile
    }

    private func previewContainer(selected: Bool, value: String?) -> UIControl {
        let view = SettingsPreviewTile()
        view.isOn = selected
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
                              lineHeight: CGFloat,
                              weight: UIFont.Weight,
                              color: UIColor) -> UILabel {
        let label = SettingsTypography.label(text, size: size, lineHeight: lineHeight, weight: weight, color: color)
        label.numberOfLines = 1
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    private func miniButton(_ title: String, background: UIColor, foreground: UIColor, shadow: Bool? = nil) -> UIView {
        let container = UIView()
        container.layer.cornerRadius = 4
        if let shadow { SettingsTypography.applyButtonShadow(to: container, small: shadow) }
        let label = previewLabel(title, size: 12, lineHeight: 16, weight: .medium, color: foreground)
        label.backgroundColor = background
        label.textAlignment = .center
        label.layer.cornerRadius = 4
        label.layer.masksToBounds = true
        container.addSubview(label)
        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: ceil(label.intrinsicContentSize.width) + 16),
            container.heightAnchor.constraint(equalToConstant: 25.6),
            label.topAnchor.constraint(equalTo: container.topAnchor),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        return container
    }
}

/// `<ToggleGroup.Item variant='ghost'>`: `data-[state=on]:bg-accent`, and `select:bg-secondary-foreground/30` while it is
/// hovered, focused or pressed, with the 150ms of `transition-colors`. It is a button, so app.css scales it to 0.98 while
/// it is pressed (`ActiveScale`).
private final class SettingsPreviewTile: UIControl, ActiveElementObserver {
    var isOn = false {
        didSet { if isOn != oldValue { applyBackground(animated: window != nil) } }
    }
    private var isPointerOver = false
    private var appliedSelected = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.cornerRadius = 6   // rounded-md
        addGestureRecognizer(UIHoverGestureRecognizer(target: self, action: #selector(hoverChanged(_:))))
        applyBackground(animated: false)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var isHighlighted: Bool {
        didSet { updateSelectState() }
    }

    func activeElementDidChange() {
        updateSelectState()
    }

    @objc private func hoverChanged(_ recognizer: UIHoverGestureRecognizer) {
        isPointerOver = recognizer.state == .began || recognizer.state == .changed
        updateSelectState()
    }

    private func updateSelectState() {
        let selected = isEnabled && (isHighlighted || isPointerOver || isActiveElement)
        guard selected != appliedSelected else { return }
        appliedSelected = selected
        applyBackground(animated: true)
    }

    private func applyBackground(animated: Bool) {
        let apply = {
            self.backgroundColor = self.appliedSelected
                ? UIColor.HayaseTheme.secondaryForeground.withAlphaComponent(0.3)
                : (self.isOn ? UIColor.HayaseTheme.accent : .clear)
        }
        guard animated else { apply(); return }
        UIView.transition(with: self, duration: 0.15,
                          options: [.transitionCrossDissolve, .allowUserInteraction, .beginFromCurrentState],
                          animations: apply)
    }
}
