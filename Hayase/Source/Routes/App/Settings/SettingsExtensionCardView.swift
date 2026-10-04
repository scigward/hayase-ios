// Mirrors: src/lib/components/ui/extensions/ExtensionCard.svelte; src/lib/components/ui/extensions/ExtensionSettings.svelte
// `preview` is the card of ExtensionInstallPrompt.svelte: the same card with only the source button in its
// `actions` slot, and with no status dot (the `leading` slot is empty there) of an extension that is not installed.
import UIKit

final class SettingsExtensionCardView: UIView, UIContextMenuInteractionDelegate {
    var onOptions: (() -> Void)?
    var onSource: (() -> Void)?
    var onDelete: (() -> Void)?
    var onSizeChanged: (() -> Void)?
    private let badges = BadgeFlowView()
    private var lastBadgeWidth: CGFloat = 0
    private var imageTask: URLSessionDataTask?
    private var statusTask: Task<Void, Never>?

    init(config: ExtensionConfig, preview: Bool = false) {
        super.init(frame: .zero)
        if !preview { addInteraction(UIContextMenuInteraction(delegate: self)) }
        backgroundColor = UIColor.HayaseTheme.muted
        layer.cornerRadius = 6
        let icon = UIImageView()
        icon.backgroundColor = UIColor.HayaseTheme.accent
        icon.contentMode = .scaleToFill
        icon.layer.cornerRadius = 6
        icon.clipsToBounds = true
        icon.widthAnchor.constraint(equalToConstant: 40).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 40).isActive = true
        let dot = UIView()
        dot.backgroundColor = UIColor(white: 180 / 255, alpha: 1)
        dot.layer.cornerRadius = 4.4
        dot.widthAnchor.constraint(equalToConstant: 8.8).isActive = true
        dot.heightAnchor.constraint(equalToConstant: 8.8).isActive = true
        dot.isHidden = preview
        let name = SettingsTypography.label(config.name, size: 16, lineHeight: 24, weight: .bold)
        name.numberOfLines = 1
        name.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let nameRow = UIStackView(arrangedSubviews: [dot, name])
        nameRow.spacing = 8
        nameRow.alignment = .center
        let id = SettingsTypography.label(config.id, size: 12, lineHeight: 16, color: UIColor.HayaseTheme.mutedForeground)
        id.numberOfLines = 1
        id.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let names = UIStackView(arrangedSubviews: [nameRow, id])
        names.axis = .vertical
        let header = UIStackView(arrangedSubviews: [icon, names])
        header.spacing = 12
        header.alignment = .top
        let left = UIStackView(arrangedSubviews: [header])
        left.axis = .vertical
        left.spacing = 12
        if let text = config.description, !text.isEmpty {
            let description = SettingsTypography.label(text, size: 14, lineHeight: 20,
                color: UIColor.HayaseTheme.mutedForeground)
            description.numberOfLines = 2
            left.addArrangedSubview(description)
        }
        let type = ["nzb": "NZB", "torrent": "Torrent", "subtitle": "Subtitle", "http": "HTTP"][config.type] ?? config.type
        var items: [BadgeFlowView.Item] = [.badge(config.version), .badge(type), .badge(config.accuracy.capitalized + " Accuracy")]
        if config.deprecated == true {
            items.append(.badge("Deprecated", color: UIColor(red: 133 / 255, green: 77 / 255, blue: 14 / 255, alpha: 1)))
        } else if config.manifestVersion != 2 {
            items.append(.badge("Outdated", color: UIColor(red: 127 / 255, green: 29 / 255, blue: 29 / 255, alpha: 1)))
        }
        if let ratio = config.ratio, ratio != .null, ratio != .number(0) { items.append(.badge("\(ratio.stringValue) Ratio")) }
        items.append(.badge(config.media.capitalized))
        if let languages = config.languages {
            let flags = languages.filter { TwemojiFlagArtwork.emoji(for: $0) != nil }
            if !flags.isEmpty { items.append(.flags(flags)) }
        }
        badges.setItems(items, fontSize: 14, rowSpacing: 8,
                       background: UIColor.HayaseTheme.accent, foreground: UIColor.HayaseTheme.foreground)
        left.addArrangedSubview(badges)
        let source = iconButton("code", label: "Source Code")
        let options = iconButton("bolt", label: "Extension Settings")
        source.addAction(UIAction { [weak self] _ in self?.onSource?() }, for: .touchUpInside)
        options.addAction(UIAction { [weak self] _ in self?.onOptions?() }, for: .touchUpInside)
        options.isEnabled = !(config.options?.isEmpty ?? true)
        options.alpha = options.isEnabled ? 1 : 0.5
        let buttons = UIStackView(arrangedSubviews: preview ? [source] : [source, options])
        let toggle = HayaseSwitch(hideState: true)
        toggle.accessibilityLabel = "Enable \(config.name)"
        toggle.setOn(ExtensionService.shared.options[config.id]?.enabled ?? false, animated: false)
        toggle.addAction(UIAction { [weak toggle] _ in
            ExtensionService.shared.setEnabled(toggle?.isOn ?? false, for: config.id)
        }, for: .valueChanged)
        let actions = UIStackView(arrangedSubviews: preview ? [buttons] : [buttons, UIView(), toggle])
        actions.axis = .vertical
        actions.alignment = .trailing
        actions.isLayoutMarginsRelativeArrangement = true
        actions.layoutMargins.bottom = 6
        // flex-1/min-w-0 belongs to the text column, not the action column.
        let actionsWidth = actions.widthAnchor.constraint(equalToConstant: 52)
        actionsWidth.priority = UILayoutPriority(999)
        actionsWidth.isActive = true
        actions.isHidden = !preview && ExtensionService.shared.options[config.id] == nil
        let row = UIStackView(arrangedSubviews: [left, actions])
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
        ])
        if let url = URL(string: config.icon) {
            imageTask = URLSession.shared.dataTask(with: url) { [weak icon] data, _, _ in
                guard let data, let image = UIImage(data: data) else { return }
                DispatchQueue.main.async { icon?.image = image }
            }
            imageTask?.resume()
        }
        guard !preview else { return }
        statusTask = Task { @MainActor [weak dot] in
            do {
                _ = try await ExtensionService.shared.workers[config.id]?.test()
                guard !Task.isCancelled else { return }
                dot?.backgroundColor = UIColor(red: 123 / 255, green: 213 / 255, blue: 85 / 255, alpha: 1)
                dot?.accessibilityLabel = "Extension online"
            } catch {
                guard !Task.isCancelled else { return }
                dot?.backgroundColor = UIColor(red: 200 / 255, green: 80 / 255, blue: 80 / 255, alpha: 1)
                dot?.accessibilityLabel = error.localizedDescription
            }
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { imageTask?.cancel(); statusTask?.cancel() }

    override func layoutSubviews() {
        super.layoutSubviews()
        if abs(lastBadgeWidth - badges.bounds.width) > 0.5 {
            lastBadgeWidth = badges.bounds.width
            badges.invalidateIntrinsicContentSize()
            onSizeChanged?()
        }
    }

    private func iconButton(_ icon: String, label: String) -> UIButton {
        let button = GhostButton(frame: .zero)
        button.setImage(UIImage.hayaseIcon(icon), for: .normal)
        button.tintColor = UIColor.HayaseTheme.foreground
        button.accessibilityLabel = label
        button.widthAnchor.constraint(equalToConstant: 26).isActive = true
        button.heightAnchor.constraint(equalToConstant: 26).isActive = true
        return button
    }

    func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
        UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            UIMenu(children: [UIAction(title: "Delete Extension", image: UIImage.hayaseIcon("trash-2"),
                attributes: .destructive) { [weak self] _ in self?.onDelete?() }])
        }
    }
}
