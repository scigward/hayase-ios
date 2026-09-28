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
    private let importButton = SettingsTypography.button("Import Extensions")
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
        importButton.setImage(UIImage.hayaseIcon("plus"), for: .normal)
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
                let remove = GhostButton(frame: .zero)
                remove.setImage(UIImage.hayaseIcon("trash-2"), for: .normal)
                remove.accessibilityLabel = "Delete repository \(label)"
                remove.widthAnchor.constraint(equalToConstant: 26).isActive = true
                remove.heightAnchor.constraint(equalToConstant: 26).isActive = true
                remove.addAction(UIAction { [weak self, weak remove] _ in
                    remove?.isEnabled = false
                    Task { @MainActor [weak self] in
                        for config in members { await ExtensionService.shared.delete(id: config.id) }
                        self?.reload()
                    }
                }, for: .touchUpInside)
                let row = UIStackView(arrangedSubviews: [
                    SettingsTypography.label(label, size: 16, lineHeight: 24), UIView(),
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
            let current = ExtensionService.shared.options[config.id]?.options[key] ?? option.default
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
                let combo = ComboBox(frame: .zero)
                combo.configure(text: current.stringValue, placeholder: false)
                combo.addAction(UIAction { [weak dialog, weak combo] _ in
                    guard let combo else { return }
                    let picker = CommandPopoverViewController(title: option.description, placeholder: "Search...",
                        groups: [CommandGroup(options: (option.values ?? []).map { CommandOption(value: $0, label: $0) })],
                        selectedValues: [ExtensionService.shared.options[config.id]?.options[key]?.stringValue ?? option.default.stringValue],
                        allowsMultiple: false, sourceView: combo)
                    picker.onSelectionChanged = { [weak combo] values in
                        guard let value = values.first else { return }
                        ExtensionService.shared.setOption(.string(value), key: key, for: config.id)
                        combo?.configure(text: value, placeholder: false)
                    }
                    dialog?.present(picker, animated: false)
                }, for: .touchUpInside)
                control = combo
            default:
                let field = SettingsInputControl(value: current.stringValue, placeholder: option.default.stringValue,
                    width: 400, numeric: option.type == "number")
                field.onChange = { value in
                    if option.type == "number" {
                        guard let number = Double(value), number.isFinite else { return }
                        ExtensionService.shared.setOption(.number(number), key: key, for: config.id)
                    } else { ExtensionService.shared.setOption(.string(value), key: key, for: config.id) }
                }
                control = field
            }
            let group = UIStackView(arrangedSubviews: [SettingsTypography.label(option.description, size: 14, lineHeight: 20, weight: .bold), control])
            group.axis = option.type == "boolean" ? .horizontal : .vertical
            group.spacing = 8
            group.alignment = option.type == "boolean" ? .center : .fill
            dialog.content.addArrangedSubview(group)
        }
        let close = SettingsTypography.button("Close")
        close.addAction(UIAction { [weak dialog] _ in dialog?.close() }, for: .touchUpInside)
        dialog.content.addArrangedSubview(close)
        parent?.present(dialog, animated: false)
    }

    private func showSource(_ config: ExtensionConfig) {
        let dialog = SettingsDialogViewController(title: "\(config.name) Source Code", maximumWidth: 1000)
        let code = UITextView()
        code.isEditable = false
        code.backgroundColor = .clear
        code.textColor = UIColor.HayaseTheme.foreground
        code.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        code.text = "Loading..."
        code.heightAnchor.constraint(equalToConstant: max(200, (parent?.view.bounds.height ?? 500) * 0.55)).isActive = true
        dialog.content.addArrangedSubview(code)
        let close = SettingsTypography.button("Close")
        close.addAction(UIAction { [weak dialog] _ in dialog?.close() }, for: .touchUpInside)
        dialog.content.addArrangedSubview(close)
        parent?.present(dialog, animated: false)
        Task { @MainActor [weak code] in
            do { code?.text = try await ExtensionService.shared.sourceCode(for: config.id) }
            catch { code?.text = error.localizedDescription }
        }
    }
}
