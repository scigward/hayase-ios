//
//  SetupExtensionsPage.swift
//  Hayase
//
//  Mirrors: src/routes/setup/extensions/+page.svelte
//
//    <Progress step={2} />
//    <div class='space-y-3 lg:max-w-4xl h-full overflow-y-auto w-full py-8'>
//      <SettingCard class='bg-transparent' title='Lookup Preference' description=…>
//        <SingleCombo bind:value={$settings.lookupPreference} items={lookupPreferences} class='w-32 shrink-0 border-input border' />
//      </SettingCard>
//      <div class='px-6'><Extensions /></div>
//    </div>
//    <Footer step={2} {checks} />
//
//  `$settings.lookupPreference = $hasForwarding ? 'quality' : 'seeders'` runs when the page is made, so
//  it sets the preference every time the page is shown. The check is a promise that does not settle
//  until an extension is installed, which keeps the footer on "Waiting for checks...".
//

import UIKit

final class SetupExtensionsPage: SetupStepView {
    private static let lookupPreferences: [(key: String, label: String)] = [
        ("quality", "Quality"), ("size", "Size"), ("seeders", "Availability"),
    ]

    private let combo = ComboBox(frame: .zero)
    private weak var parent: UIViewController?
    private var observer: NSObjectProtocol?
    private var lastState: (installed: Int, enabled: Int)?

    init(parent: UIViewController) {
        self.parent = parent
        super.init(step: 2, topPadding: 32, bottomPadding: 32)   // py-8

        Settings.lookupPreference = SetupFlow.hasPortForwarding ? "quality" : "seeders"

        // <SingleCombo … class='w-32 shrink-0 border-input border' />
        combo.configure(text: Self.label(of: Settings.lookupPreference), placeholder: false)
        combo.layer.borderWidth = 1
        combo.layer.borderColor = UIColor.HayaseTheme.input.cgColor
        let comboWidth = combo.widthAnchor.constraint(equalToConstant: 128)
        comboWidth.priority = UILayoutPriority(999)
        comboWidth.isActive = true
        combo.setContentHuggingPriority(.required, for: .horizontal)
        combo.addAction(UIAction { [weak self] _ in self?.showLookupPicker() }, for: .touchUpInside)
        let lookupCard = SettingsCardView(
            title: "Lookup Preference",
            description: "What to prioritize when looking for and sorting results. Quality will focus on the best quality available which often means big file sizes, Size will focus on the smallest file size available, and Availability will pick results with the most peers regardless of size and quality.",
            control: combo, transparent: true)

        // <div class='px-6'><Extensions /></div>
        let extensions = SettingsExtensionsView(parent: parent)
        extensions.onSizeChanged = { [weak self] in self?.invalidateContentSize() }
        setContent([lookupCard, SetupExtensionsInset(extensions: extensions)])

        refreshChecks(force: true)
        // The extensions are stored in the defaults, as `savedConfigs` and `savedOptions` are.
        observer = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification,
                                                          object: nil, queue: .main) { [weak self] _ in
            DispatchQueue.main.async { self?.refreshChecks(force: false) }
        }
    }

    required init?(coder: NSCoder) {
        nil
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    private static func label(of key: String) -> String {
        lookupPreferences.first(where: { $0.key == key })?.label ?? key
    }

    private func showLookupPicker() {
        let picker = CommandPopoverViewController(
            title: "Lookup Preference", placeholder: "Search...",
            groups: [CommandGroup(options: Self.lookupPreferences.map { CommandOption(value: $0.key, label: $0.label) })],
            selectedValues: [Settings.lookupPreference], allowsMultiple: false, sourceView: combo)
        picker.onSelectionChanged = { [weak self] values in
            guard let value = values.first else { return }
            Settings.lookupPreference = value
            self?.combo.configure(text: Self.label(of: value), placeholder: false)
        }
        parent?.present(picker, animated: false)
    }

    /// `checkExtensions`: a promise made again whenever the extensions or their options change.
    private func refreshChecks(force: Bool) {
        let installed = ExtensionService.shared.configs.count
        let enabled = ExtensionService.shared.options.values.filter { $0.enabled }.count
        if !force, let last = lastState, last.installed == installed, last.enabled == enabled { return }
        lastState = (installed, enabled)

        let check = SetupCheck(title: "Extensions Required", pending: "At least one extension needs to be installed.")
        if enabled > 0 && installed > 0 {
            check.resolve(.init(status: .success, text: "At least 1 extension is enabled."))
        } else if installed > 0 {
            check.resolve(.init(status: .warning, text: "At least 1 extension is installed, it's recommended to enable it."))
        }
        // with nothing installed the promise never resolves
        footer.setChecks([check])
    }
}

/// `<div class='px-6'>`
private final class SetupExtensionsInset: UIView, SettingsResponsiveView {
    private let extensions: SettingsExtensionsView

    init(extensions: SettingsExtensionsView) {
        self.extensions = extensions
        super.init(frame: .zero)
        extensions.translatesAutoresizingMaskIntoConstraints = false
        addSubview(extensions)
        NSLayoutConstraint.activate([
            extensions.topAnchor.constraint(equalTo: topAnchor),
            extensions.bottomAnchor.constraint(equalTo: bottomAnchor),
            extensions.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            extensions.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
        ])
    }

    required init?(coder: NSCoder) {
        nil
    }

    func updateLayout(viewportWidth: CGFloat) {
        extensions.updateLayout(viewportWidth: viewportWidth)
    }
}
