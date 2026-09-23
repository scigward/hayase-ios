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

        titleLabel.font = .nunito(ofSize: 14, weight: .bold)
        titleLabel.textColor = UIColor.HayaseTheme.foreground
        titleLabel.numberOfLines = 0

        descriptionLabel.font = .nunito(ofSize: 12)
        descriptionLabel.textColor = UIColor.HayaseTheme.mutedForeground
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

        let name = previewLabel(title, size: 20, weight: .bold, color: UIColor.HayaseTheme.foreground)
        let sampleLabel = previewLabel(sample, size: title == "None" ? 36 : 17, weight: .bold, color: .white)
        sampleLabel.textAlignment = .center
        sampleLabel.isHidden = image != nil
        sampleLabel.layer.shadowColor = UIColor.black.cgColor
        sampleLabel.layer.shadowOpacity = 1
        sampleLabel.layer.shadowRadius = 2
        sampleLabel.layer.shadowOffset = CGSize(width: 1, height: 1)

        let video = UIView()
        video.isUserInteractionEnabled = false
        video.backgroundColor = .clear
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
        let name = previewLabel(title, size: 20, weight: .bold, color: palette.foreground)
        let sample = SettingsTypography.label("The quick brown fox", size: 12, lineHeight: 16,
            color: palette.foreground.withAlphaComponent(0.85))
        let muted = SettingsTypography.label("Muted description text", size: 10, lineHeight: 15, color: palette.mutedForeground)
        let buttons = UIStackView(arrangedSubviews: [
            miniButton("Primary", background: palette.primary, foreground: palette.primaryForeground),
            miniButton("Secondary", background: palette.secondary, foreground: palette.foreground),
            miniButton("Ghost", background: .clear, foreground: palette.foreground),
        ])
        buttons.spacing = 6
        let input = SettingsTypography.label("Sample", size: 10, lineHeight: 15, color: palette.foreground)
        input.backgroundColor = palette.background
        input.layer.cornerRadius = 6
        input.layer.borderWidth = 1
        input.layer.borderColor = palette.input.cgColor
        input.heightAnchor.constraint(equalToConstant: 24).isActive = true
        input.text = "   Sample"
        let switchTrack = UIView()
        switchTrack.backgroundColor = palette.input
        switchTrack.layer.cornerRadius = 8
        switchTrack.widthAnchor.constraint(equalToConstant: 32).isActive = true
        switchTrack.heightAnchor.constraint(equalToConstant: 16).isActive = true
        let thumb = UIView(frame: CGRect(x: 2, y: 2, width: 12, height: 12))
        thumb.backgroundColor = palette.background
        thumb.layer.cornerRadius = 6
        switchTrack.addSubview(thumb)
        let slider = UIView()
        slider.backgroundColor = palette.primary.withAlphaComponent(0.2)
        slider.layer.cornerRadius = 3
        slider.heightAnchor.constraint(equalToConstant: 6).isActive = true
        let fill = UIView()
        fill.backgroundColor = palette.primary
        fill.layer.cornerRadius = 3
        fill.translatesAutoresizingMaskIntoConstraints = false
        let sliderThumb = UIView()
        sliderThumb.backgroundColor = palette.background
        sliderThumb.layer.borderWidth = 1
        sliderThumb.layer.borderColor = palette.primary.withAlphaComponent(0.5).cgColor
        sliderThumb.layer.cornerRadius = 8
        sliderThumb.translatesAutoresizingMaskIntoConstraints = false
        slider.addSubview(fill)
        slider.addSubview(sliderThumb)
        NSLayoutConstraint.activate([
            fill.leadingAnchor.constraint(equalTo: slider.leadingAnchor),
            fill.topAnchor.constraint(equalTo: slider.topAnchor),
            fill.bottomAnchor.constraint(equalTo: slider.bottomAnchor),
            fill.widthAnchor.constraint(equalTo: slider.widthAnchor, multiplier: 0.4),
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
        let bodyWidth = body.widthAnchor.constraint(equalToConstant: 212)
        bodyWidth.priority = .defaultHigh
        NSLayoutConstraint.activate([
            name.topAnchor.constraint(equalTo: tile.topAnchor, constant: 16),
            name.leadingAnchor.constraint(equalTo: tile.leadingAnchor, constant: 16),
            body.topAnchor.constraint(equalTo: tile.topAnchor, constant: 48),
            body.bottomAnchor.constraint(equalTo: tile.bottomAnchor, constant: -32),
            body.centerXAnchor.constraint(equalTo: tile.centerXAnchor),
            bodyWidth,
            body.widthAnchor.constraint(lessThanOrEqualTo: tile.widthAnchor, constant: -48),
            input.widthAnchor.constraint(equalTo: body.widthAnchor),
            slider.widthAnchor.constraint(equalTo: body.widthAnchor),
        ])
        return tile
    }

    private func previewContainer(selected: Bool, value: String?) -> UIControl {
        let view = UIControl()
        view.layer.cornerRadius = 6
        view.backgroundColor = selected ? UIColor.HayaseTheme.accent : .clear
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
        let label = previewLabel(title, size: 12, weight: .medium, color: foreground)
        label.backgroundColor = background
        label.textAlignment = .center
        label.layer.cornerRadius = 2
        label.layer.masksToBounds = true
        label.widthAnchor.constraint(equalToConstant: ceil(label.intrinsicContentSize.width) + 16).isActive = true
        label.heightAnchor.constraint(equalToConstant: 25.6).isActive = true
        return label
    }
}
