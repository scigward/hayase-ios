// Mirrors: src/routes/app/settings/{player,client,interface,extensions,accounts,app,changelog}/+page.svelte
import UIKit

extension SettingsViewController {
    func makeRow(_ row: Row) -> UIView {
        switch row.kind {
        case .toggle(let key, let defaultValue):
            let toggle = HayaseSwitch()
            toggle.setOn(UserDefaults.standard.object(forKey: key) as? Bool ?? defaultValue, animated: false)
            toggle.addAction(UIAction { [weak self, weak toggle] _ in
                guard let toggle else { return }
                Settings.write(toggle.isOn, forKey: key)
                self?.applyTorrentSettingsIfNeeded(forKey: key)
            }, for: .valueChanged)
            return card(row, control: toggle)

        case .selectable(let key, let options, let defaultKey):
            let combo = makeCombo(row: row, key: key, options: options, defaultKey: defaultKey)
            guard key == "pref_torrentLocation" else { return card(row, control: combo) }
            let path = SettingsInputControl(value: TorrentBackendSettings().path,
                                            placeholder: "/tmp/webtorrent", width: 240)
            path.input.isUserInteractionEnabled = false
            path.input.layer.maskedCorners = [.layerMinXMinYCorner, .layerMinXMaxYCorner]
            combo.layer.maskedCorners = [.layerMaxXMinYCorner, .layerMaxXMaxYCorner]
            let control = UIStackView(arrangedSubviews: [path, combo])
            control.axis = .horizontal
            control.spacing = 0
            return card(row, control: control)

        case .editableNumber(let key, let fallback, let suffix, let lower, let upper):
            let input = SettingsInputControl(value: UserDefaults.standard.string(forKey: key) ?? fallback,
                                             placeholder: fallback, width: 128, numeric: true, suffix: suffix)
            let fraction = key == Settings.Keys.seekDuration || key == "pref_torrentSpeed"
            input.onChange = { [weak self] value in
                guard let number = Double(value), number.isFinite,
                      number >= Double(lower), number <= Double(upper),
                      fraction || Int(value) != nil else { return }
                Settings.write(value, forKey: key)
                self?.applyTorrentSettingsIfNeeded(forKey: key)
            }
            input.onCommit = { [weak self] value in
                self?.commitInput(value, key: key, fallback: fallback,
                                  numericRange: lower...upper, allowsFraction: fraction) ?? fallback
            }
            return card(row, control: input)

        case .editableText(let key, let fallback, let secure):
            let placeholders = ["pref_nzbDomain": "news.example.com", "pref_nzbLogin": "admin", Settings.Keys.nzbPassword: "admin1"]
            let input = SettingsInputControl(value: Settings.storedValue(forKey: key) as? String ?? fallback,
                                             placeholder: placeholders[key] ?? "", width: 320, secure: secure)
            input.onChange = { [weak self] value in
                Settings.write(value, forKey: key)
                self?.applyTorrentSettingsIfNeeded(forKey: key)
            }
            return card(row, control: input)

        case .slider(let key, let fallback, let min, let max, let step):
            let value = UserDefaults.standard.object(forKey: key) == nil ? fallback : UserDefaults.standard.double(forKey: key)
            let slider = SettingsSliderControl(value: value, min: min, max: max, step: step)
            let label = SettingsTypography.label(String(format: "%.1f", value), size: 12, lineHeight: 16,
                                                color: UIColor.HayaseTheme.mutedForeground)
            let control = SettingsSliderGroup(slider: slider, label: label)
            slider.addAction(UIAction { [weak self, weak slider, weak label] _ in
                guard let slider else { return }
                label?.text = String(format: "%.1f", slider.value)
                if key == Settings.Keys.uiScale { self?.pendingScale = slider.value }
                else { Settings.write(slider.value, forKey: key) }
            }, for: .valueChanged)
            slider.addAction(UIAction { [weak self] _ in
                if key == Settings.Keys.uiScale { self?.confirmScaleChange() }
            }, for: .editingDidEnd)
            return card(row, control: control)

        case .previewGrid(let kind):
            let preview = SettingsPreviewGridView(frame: .zero)
            let selected = kind == .subtitleStyle ? Settings.subtitleStyle : "default"
            preview.configure(title: row.title, description: row.description, kind: kind,
                              selectedValue: selected, twoColumns: settingsView.viewportWidth >= 640)
            if kind == .subtitleStyle {
                preview.onSelection = { [weak self, weak preview] value in
                    Settings.subtitleStyle = value
                    preview?.configure(title: row.title, description: row.description, kind: kind,
                                       selectedValue: value, twoColumns: (self?.settingsView.viewportWidth ?? 0) >= 640)
                }
            }
            return preview

        case .account(let tracker):
            let account = HayaseAccountCardView(frame: .zero)
            account.configure(tracker: tracker, parentVC: self)
            account.onSizeChanged = { [weak self] in self?.settingsView.invalidateContentSize() }
            return account

        case .appActions:
            return SettingsActionsView { [weak self] title in self?.handleAction(title: title) }

        case .extensions:
            let extensions = SettingsExtensionsView(parent: self)
            extensions.onSizeChanged = { [weak self] in self?.settingsView.invalidateContentSize() }
            return extensions

        case .changelogPlaceholder:
            let changelog = SettingsChangelogView(frame: .zero)
            changelog.configure(title: row.title, description: row.description,
                                wide: settingsView.viewportWidth >= 640,
                                loadedEntries: changelogEntries, error: changelogError)
            return changelog

        case .button(let title):
            let button = SettingsTypography.button(title)
            button.addAction(UIAction { [weak self] _ in
                guard let self, let navigation = self.navigationController else { return }
                self.localRouteTransition.perform(in: navigation.view) {
                    navigation.pushViewController(HayaseDebugViewController(), animated: false)
                }
            }, for: .touchUpInside)
            return card(row, control: button)

        }
    }

    private func card(_ row: Row, control: UIView) -> SettingsCardView {
        SettingsCardView(title: row.title, description: row.description, control: control)
    }

    private func makeCombo(row: Row, key: String, options: [(key: String, label: String)], defaultKey: String) -> ComboBox {
        let combo = ComboBox(frame: .zero)
        let value = key == Settings.Keys.debugLevel ? Settings.debugLevel : (UserDefaults.standard.string(forKey: key) ?? defaultKey)
        combo.configure(text: options.first(where: { $0.key == value })?.label ?? value, placeholder: false)
        combo.layer.borderWidth = 1
        combo.layer.borderColor = UIColor.HayaseTheme.input.cgColor
        let width = combo.widthAnchor.constraint(equalToConstant: controlWidth(for: row))
        width.priority = UILayoutPriority(999)
        width.isActive = true
        combo.setContentHuggingPriority(.required, for: .horizontal)
        combo.addAction(UIAction { [weak self, weak combo] _ in
            guard let combo else { return }
            self?.showSelectionPicker(title: row.title, key: key, options: options,
                                      defaultKey: defaultKey, anchor: combo)
        }, for: .touchUpInside)
        return combo
    }

    /// `<a href='/#/app/license'>License Information</a>`
    func showLicense() {
        Router.shared.navigate(.license)
    }
}

private final class SettingsSliderGroup: UIStackView, SettingsResponsiveView {
    init(slider: UIView, label: UIView) {
        super.init(frame: .zero)
        spacing = 12
        alignment = .center
        addArrangedSubview(slider)
        addArrangedSubview(label)
    }
    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func updateLayout(viewportWidth: CGFloat) {
        axis = viewportWidth >= 768 ? .horizontal : .vertical
        alignment = viewportWidth >= 768 ? .center : .leading
    }
}
