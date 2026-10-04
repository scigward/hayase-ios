// Mirrors: src/lib/components/ui/extensions/{extensions,ExtensionSettings}.svelte
import UIKit

final class SettingsExtensionsView: UIView, SettingsResponsiveView {
    var onSizeChanged: (() -> Void)?
    private weak var parent: UIViewController?
    private let root = UIStackView()
    private let tabs = UIStackView()
    private let imports = UIStackView()
    private let list = UIStackView()
    private let input = Input(placeholder: "https://example.com/manifest.json")
    private let importButton = SettingsTypography.button("Import Extensions", weight: .bold)
    private var tabButtons: [UIButton] = []
    private var selectedTab = 0
    private var importWidth: NSLayoutConstraint?
    private var tabsWidth: NSLayoutConstraint?
    private var observer: NSObjectProtocol?
    private var displayedConfigs: [String: ExtensionConfig] = [:]
    private var mediumLayout: Bool?

    init(parent: UIViewController) {
        self.parent = parent
        super.init(frame: .zero)
        root.axis = .vertical
        root.spacing = 12
        root.translatesAutoresizingMaskIntoConstraints = false
        addSubview(root)
        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: topAnchor), root.leadingAnchor.constraint(equalTo: leadingAnchor),
            root.trailingAnchor.constraint(equalTo: trailingAnchor), root.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        let tabContainer = UIView()
        tabs.distribution = .fillEqually
        tabs.backgroundColor = UIColor.HayaseTheme.secondary
        tabs.layer.cornerRadius = 8
        tabs.isLayoutMarginsRelativeArrangement = true
        tabs.layoutMargins = UIEdgeInsets(top: 4, left: 4, bottom: 4, right: 4)
        tabs.translatesAutoresizingMaskIntoConstraints = false
        tabContainer.addSubview(tabs)
        NSLayoutConstraint.activate([
            tabs.topAnchor.constraint(equalTo: tabContainer.topAnchor),
            tabs.bottomAnchor.constraint(equalTo: tabContainer.bottomAnchor),
            tabs.leadingAnchor.constraint(equalTo: tabContainer.leadingAnchor),
            tabs.trailingAnchor.constraint(lessThanOrEqualTo: tabContainer.trailingAnchor),
            tabs.heightAnchor.constraint(equalToConstant: 36),
        ])
        tabsWidth = tabs.widthAnchor.constraint(equalTo: tabContainer.widthAnchor)
        tabsWidth?.isActive = true
        for (index, title) in ["Extensions", "Repositories"].enumerated() {
            let button = UIButton(type: .custom)
            button.setTitle(title, for: .normal)
            button.titleLabel?.font = .nunito(ofSize: 14, weight: .medium)
            button.layer.cornerRadius = 6
            button.addAction(UIAction { [weak self] _ in
                self?.selectedTab = index
                self?.reload()
            }, for: .touchUpInside)
            tabs.addArrangedSubview(button)
            tabButtons.append(button)
        }
        imports.axis = .vertical
        imports.spacing = 12
        input.keyboardType = .URL
        input.heightAnchor.constraint(equalToConstant: 36).isActive = true
        input.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        input.attributedPlaceholder = NSAttributedString(string: "https://example.com/manifest.json", attributes: [
            .foregroundColor: UIColor.HayaseTheme.mutedForeground,
        ])
        input.attachTooltip("Destination URL of the extension manifest to import extensions from. This can be a direct URL to a .json file, an npm package prefixed with npm:, a file in a github repository prefixed with gh: or a file with the file: prefix and the code inlined as text.", maximumWidth: 208)
        SettingsTypography.applyButtonShadow(to: input, small: true)
        importButton.setImage(UIImage.hayaseIcon("plus", pointSize: 19.2), for: .normal)
        (importButton as? SelectButton)?.selectsWhenDisabled = true
        importButton.tintColor = UIColor.HayaseTheme.primaryForeground
        importButton.imageEdgeInsets.right = 8
        imports.addArrangedSubview(input)
        imports.addArrangedSubview(importButton)
        importWidth = importButton.widthAnchor.constraint(equalToConstant: 224)
        importButton.addAction(UIAction { [weak self] _ in self?.importExtensions() }, for: .touchUpInside)
        list.axis = .vertical
        list.spacing = 8
        [tabContainer, imports, list].forEach { root.addArrangedSubview($0) }
        // Finish singleton initialization before observing the defaults it loads.
        reload()
        observer = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification,
            object: nil, queue: .main) { [weak self] _ in
                // didChange can fire synchronously inside configs/options.didSet.
                // Read only after that mutation's exclusive access has ended.
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.displayedConfigs != ExtensionService.shared.configs else { return }
                    self.reload()
                }
            }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }

    func updateLayout(viewportWidth: CGFloat) {
        importWidth?.isActive = viewportWidth >= 640
        imports.axis = viewportWidth >= 640 ? .horizontal : .vertical
        if mediumLayout != (viewportWidth >= 768) {
            mediumLayout = viewportWidth >= 768
            tabsWidth?.isActive = false
            tabsWidth = viewportWidth >= 768 ? tabs.widthAnchor.constraint(equalToConstant: 288)
                : tabs.widthAnchor.constraint(equalTo: root.widthAnchor)
            tabsWidth?.isActive = true
        }
    }

    private func reload() {
        displayedConfigs = ExtensionService.shared.configs
        for (index, button) in tabButtons.enumerated() {
            button.backgroundColor = index == selectedTab ? UIColor.HayaseTheme.foreground : .clear
            button.setTitleColor(index == selectedTab ? UIColor.HayaseTheme.background : UIColor.HayaseTheme.mutedForeground, for: .normal)
            button.accessibilityTraits = index == selectedTab ? [.button, .selected] : .button
            button.layer.shadowOpacity = index == selectedTab ? 0.1 : 0
            button.layer.shadowColor = UIColor.black.cgColor
            button.layer.shadowOffset = CGSize(width: 0, height: 1)
            button.layer.shadowRadius = 1.5
        }
        list.arrangedSubviews.forEach { list.removeArrangedSubview($0); $0.removeFromSuperview() }
        let configs = displayedConfigs.values.sorted { $0.id < $1.id }
        if configs.isEmpty {
            let empty = UIStackView(arrangedSubviews: [
                SettingsTypography.label("Looks like there's nothing here...", size: 24, lineHeight: 32),
                SettingsTypography.label(selectedTab == 0 ? "Import some extensions." : "Import some extensions in the field above.",
                    size: 14, lineHeight: 20, color: UIColor.HayaseTheme.mutedForeground),
            ])
            empty.axis = .vertical
            empty.spacing = 16
            empty.alignment = .center
            empty.isLayoutMarginsRelativeArrangement = true
            empty.layoutMargins = UIEdgeInsets(top: 24, left: 16, bottom: 24, right: 16)
            list.addArrangedSubview(empty)
        } else if selectedTab == 0 {
            for config in configs {
                let card = SettingsExtensionCardView(config: config)
                card.onOptions = { [weak self] in self?.showOptions(config) }
                card.onSource = { [weak self] in self?.showSource(config) }
                card.onDelete = { [weak self] in
                    Task { @MainActor [weak self] in
                        await ExtensionService.shared.delete(id: config.id)
                        self?.reload()
                    }
                }
                card.onSizeChanged = { [weak self] in self?.onSizeChanged?() }
                list.addArrangedSubview(card)
            }
        } else {
            for (source, members) in Dictionary(grouping: configs, by: { $0.update ?? "" }).sorted(by: { $0.key < $1.key }) {
                let label = source.hasPrefix("http") ? URL(string: source)?.host ?? source : source
                let remove = SelectButton(frame: .zero)
                remove.applyGhostVariant()
                remove.dimsWhenDisabled = true
                remove.setLayeredIcon(.trash, size: 16)
                remove.layer.cornerRadius = 4
                remove.accessibilityLabel = "Delete repository \(label)"
                remove.widthAnchor.constraint(equalToConstant: 25.6).isActive = true
                remove.heightAnchor.constraint(equalToConstant: 25.6).isActive = true
                remove.addAction(UIAction { [weak self, weak remove] _ in
                    remove?.isEnabled = false
                    Task { @MainActor [weak self] in
                        for config in members { await ExtensionService.shared.delete(id: config.id) }
                        self?.reload()
                    }
                }, for: .touchUpInside)
                let identity = UIStackView(arrangedSubviews: [repositoryIcon(source),
                    SettingsTypography.label(label, size: 16, lineHeight: 24)])
                identity.spacing = 8
                identity.alignment = .center
                let row = UIStackView(arrangedSubviews: [
                    identity, UIView(),
                    SettingsTypography.label("\(members.count) Extensions", size: 12, lineHeight: 16,
                        color: UIColor.HayaseTheme.mutedForeground), remove,
                ])
                row.spacing = 12
                row.alignment = .center
                row.isLayoutMarginsRelativeArrangement = true
                row.layoutMargins = UIEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)
                row.backgroundColor = UIColor.HayaseTheme.muted
                row.layer.cornerRadius = 6
                list.addArrangedSubview(row)
            }
        }
        onSizeChanged?()
    }

    private func importExtensions() {
        let address = input.text ?? ""
        importButton.isEnabled = false
        importButton.setTitle("Importing extensions....", for: .normal)
        Task { @MainActor [weak self] in
            do { try await ExtensionService.shared.importExtension(from: address) }
            catch {
                guard !Task.isCancelled else { return }
                AppErrorToast.show(error.localizedDescription, title: (error as? ExtensionError)?.toastTitle ?? "Invalid extension URI")
            }
            self?.importButton.isEnabled = true
            self?.importButton.setTitle("Import Extensions", for: .normal)
            self?.reload()
        }
    }

    private func showOptions(_ config: ExtensionConfig) {
        let dialog = SettingsDialogViewController(title: "\(config.name) Settings")
        for (key, option) in (config.options ?? [:]).sorted(by: { $0.key < $1.key }) {
            // Unset values stay unset: string/number defaults are placeholders, not saved input.
            let current = ExtensionService.shared.options[config.id]?.options[key]
            let control: UIView
            switch option.type {
            case "boolean":
                let toggle = HayaseSwitch()
                toggle.setOn(current == .bool(true), animated: false)
                toggle.addAction(UIAction { [weak toggle] _ in
                    ExtensionService.shared.setOption(.bool(toggle?.isOn ?? false), key: key, for: config.id)
                }, for: .valueChanged)
                control = toggle
            case "select":
                // `<Select.Root>`: a trigger and a list without a search, not the combobox
                let select = SelectTriggerView()
                // `<Select.Value placeholder={options.default}>`: the default is shown, muted, until one is chosen
                let chosen = ExtensionService.shared.options[config.id]?.options[key]
                let hasSelection = chosen != nil && chosen != .null
                select.configure(text: (hasSelection ? chosen : option.default)?.stringValue ?? "", placeholder: !hasSelection)
                select.addAction(UIAction { [weak dialog, weak select] _ in
                    guard let select else { return }
                    let values = option.values ?? []
                    let selected = ExtensionService.shared.options[config.id]?.options[key]
                    let selectedIndex = selected.flatMap { $0 == .null ? nil : values.firstIndex(of: $0) }
                    let picker = CommandPopoverViewController(title: option.description,
                        groups: [CommandGroup(options: values.enumerated().map {
                            CommandOption(value: String($0.offset), label: $0.element.stringValue)
                        })],
                        selectedValues: selectedIndex.map { [String($0)] } ?? [],
                        allowsMultiple: false, sourceView: select, showsSearch: false)
                    picker.onSelectionChanged = { [weak select] selectedIDs in
                        guard let id = selectedIDs.first, let index = Int(id), values.indices.contains(index) else { return }
                        let value = values[index]
                        ExtensionService.shared.setOption(value, key: key, for: config.id)
                        select?.configure(text: (value == .null ? option.default : value).stringValue,
                                          placeholder: value == .null)
                    }
                    dialog?.present(picker, animated: false)
                }, for: .touchUpInside)
                control = select
            case "string", "number":
                let field = SettingsInputControl(value: current?.stringValue ?? "", placeholder: option.default.stringValue,
                    width: 400, numeric: option.type == "number")
                field.onChange = { value in
                    if option.type == "number" {
                        if value.isEmpty {
                            ExtensionService.shared.clearOption(key: key, for: config.id)
                            return
                        }
                        guard let number = Double(value), number.isFinite else { return }
                        ExtensionService.shared.setOption(.number(number), key: key, for: config.id)
                    } else { ExtensionService.shared.setOption(.string(value), key: key, for: config.id) }
                }
                control = field
            default:
                continue // The interface has no row for an unknown option type.
            }
            let label = SettingsTypography.label(option.description, size: 14, lineHeight: 21, weight: .bold)
            label.setContentHuggingPriority(.defaultLow, for: .horizontal)
            control.setContentHuggingPriority(.required, for: .horizontal)
            control.setContentCompressionResistancePriority(.required, for: .horizontal)
            let group = UIStackView(arrangedSubviews: [label, control])
            group.axis = option.type == "boolean" ? .horizontal : .vertical
            group.spacing = 8
            group.alignment = option.type == "boolean" ? .center : .fill
            dialog.content.addArrangedSubview(group)
        }
        let close = SettingsTypography.button("Close", secondary: true)
        close.addAction(UIAction { [weak dialog] _ in dialog?.close() }, for: .touchUpInside)
        dialog.content.addArrangedSubview(close)
        parent?.present(dialog, animated: false)
    }

    private func showSource(_ config: ExtensionConfig) {
        let dialog = SettingsDialogViewController(title: "\(config.name) Source Code", maximumWidth: CGFloat.greatestFiniteMagnitude)
        dialog.preferredPanelWidthFraction = 0.8
        dialog.preferredPanelHeightFraction = 0.7
        let code = UITextView()
        code.isEditable = false
        code.backgroundColor = .clear
        code.textColor = UIColor.HayaseTheme.foreground
        let sourceFont = UIFont.monospacedSystemFont(ofSize: 16, weight: .regular)
        func sourceText(_ text: String) -> NSAttributedString {
            CSSText.string(text, font: sourceFont, color: UIColor.HayaseTheme.foreground,
                lineHeight: 24, lineBreak: .byCharWrapping)
        }
        func displaySource(_ text: String, in view: UITextView) {
            view.attributedText = sourceText(text)
            // The web code element is w-max: preserve long lines and horizontal scrolling.
            let width = text.components(separatedBy: .newlines).reduce(CGFloat.zero) {
                max($0, ($1 as NSString).size(withAttributes: [.font: sourceFont]).width)
            }
            view.textContainer.widthTracksTextView = false
            view.textContainer.size = CGSize(width: max(1, ceil(width) + 1), height: CGFloat.greatestFiniteMagnitude)
        }
        code.attributedText = sourceText("Loading...")
        code.textContainer.lineBreakMode = .byCharWrapping // break-all / whitespace-pre-wrap
        code.textContainerInset = .zero
        code.textContainer.lineFragmentPadding = 0
        code.setContentHuggingPriority(.defaultLow, for: .vertical)
        code.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        dialog.content.addArrangedSubview(code)
        let close = SettingsTypography.button("Close", secondary: true)
        close.addAction(UIAction { [weak dialog] _ in dialog?.close() }, for: .touchUpInside)
        dialog.content.addArrangedSubview(close)
        parent?.present(dialog, animated: false)
        Task { @MainActor [weak code] in
            do {
                let source = try await ExtensionService.shared.sourceCode(for: config.id)
                if let code { displaySource(source, in: code) }
            } catch {
                if let code { displaySource(error.localizedDescription, in: code) }
            }
        }
    }

    /// Repository protocol icons, including the interface's inline npm SVG and 1px Globe stroke.
    private func repositoryIcon(_ source: String) -> UIImageView {
        let image: UIImage?
        if source.hasPrefix("gh:") {
            image = UIImage.hayaseIcon("git-branch", pointSize: 20)
        } else {
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 20))
            image = renderer.image { context in
                let cg = context.cgContext
                if source.hasPrefix("npm:") {
                    cg.scaleBy(x: 20.0 / 128, y: 20.0 / 128)
                    cg.setFillColor(UIColor.white.cgColor)
                    cg.addPath(SVGPath.path("M2 38.5h124v43.71H64v7.29H36.44v-7.29H2Zm6.89 36.43h13.78V53.07h6.89v21.86h6.89V45.79H8.89Zm34.44-29.14v36.42h13.78v-7.28h13.78V45.79Zm13.78 7.29H64v14.56h-6.89Zm20.67-7.29v29.14h13.78V53.07h6.89v21.86h6.89V53.07h6.89v21.86h6.89V45.79Z"))
                    cg.fillPath()
                } else {
                    cg.scaleBy(x: 20.0 / 24, y: 20.0 / 24)
                    cg.setStrokeColor(UIColor.white.cgColor)
                    cg.setLineWidth(1)
                    cg.setLineCap(.round)
                    cg.setLineJoin(.round)
                    cg.strokeEllipse(in: CGRect(x: 2, y: 2, width: 20, height: 20))
                    cg.addPath(SVGPath.path("M12 2a14.5 14.5 0 0 0 0 20a14.5 14.5 0 0 0 0-20M2 12h20"))
                    cg.strokePath()
                }
            }.withRenderingMode(.alwaysTemplate)
        }
        let icon = UIImageView(image: image)
        icon.tintColor = UIColor.HayaseTheme.mutedForeground
        icon.contentMode = .scaleAspectFit
        icon.widthAnchor.constraint(equalToConstant: 20).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 20).isActive = true
        return icon
    }
}
