//
//  SetupStoragePage.swift
//  Hayase
//
//  Mirrors: src/routes/setup/storage/+page.svelte
//
//    <Progress />
//    <div class='space-y-3 lg:max-w-4xl pt-5 h-full overflow-y-auto'>
//      <SettingCard class='bg-transparent' let:id title='Torrent Download Location' description=…>
//        <div class='flex'>
//          <Input type='url' bind:value={$settings.torrentPath} readonly {id} placeholder='/tmp/webtorrent' class='sm:w-60 rounded-r-none pointer-events-none' />
//          <SingleCombo bind:value={$settings.androidStorageType} items={androidDirectories} class='w-32 shrink-0 border-input border rounded-l-none ' onSelected={selectDownloadFolder} />
//        </div>
//      </SettingCard>
//      <SettingCard class='bg-transparent' let:id title='Persist Files' description=…><Switch {id} bind:checked={$settings.torrentPersist} /></SettingCard>
//    </div>
//    <Footer checks={[space]} />
//
//  The app is iOS, so the folder is chosen as it is on mobile, from a list of places (`SUPPORTS.isIOS`),
//  which here are the ones the client settings of the app offer: Cache and Internal Storage.
//

import UIKit

final class SetupStoragePage: SetupStepView {
    private static let locationKey = "pref_torrentLocation"
    private static let locations: [(key: String, label: String)] = [("cache", "Cache"), ("documents", "Internal Storage")]

    private let pathField = SetupReadOnlyField(text: TorrentBackendSettings().path,
                                                 placeholder: "/tmp/webtorrent", width: 240)
    private let combo = ComboBox(frame: .zero)
    private var shownPath = TorrentBackendSettings().path

    init() {
        super.init(step: 0, topPadding: 20, bottomPadding: 0)   // pt-5

        // <SingleCombo class='w-32 shrink-0 border-input border rounded-l-none' />
        let stored = UserDefaults.standard.string(forKey: Self.locationKey) ?? "cache"
        combo.configure(text: Self.locations.first(where: { $0.key == stored })?.label ?? stored, placeholder: false)
        combo.layer.borderWidth = 1
        combo.layer.borderColor = UIColor.HayaseTheme.input.cgColor
        combo.layer.maskedCorners = [.layerMaxXMinYCorner, .layerMaxXMaxYCorner]
        let comboWidth = combo.widthAnchor.constraint(equalToConstant: 128)
        comboWidth.priority = UILayoutPriority(999)
        comboWidth.isActive = true
        combo.setContentHuggingPriority(.required, for: .horizontal)
        combo.addAction(UIAction { [weak self] _ in self?.showLocationPicker() }, for: .touchUpInside)

        let location = UIStackView(arrangedSubviews: [pathField, combo])
        location.axis = .horizontal
        location.spacing = 0
        let locationCard = SettingsCardView(
            title: "Torrent Download Location",
            description: "Path to the folder used to store torrents. By default this is the OS's TEMP/TMP cache folder, which might lose data when your OS tries to reclaim storage.",
            control: location, transparent: true)
        // The field is read-only, and focusing a read-only field shows nothing, so the label has nothing to do for it.

        let persist = HayaseSwitch()
        persist.setOn(Settings.persistFiles, animated: false)
        persist.addAction(UIAction { [weak persist] _ in
            guard let persist else { return }
            Settings.write(persist.isOn, forKey: Settings.Keys.persistFiles)
            TorrentBackendManager.shared.applyCurrentSettings()
        }, for: .valueChanged)
        let persistCard = SettingsCardView(
            title: "Persist Files",
            description: "Keeps torrents files instead of deleting them after a new torrent is played. This doesn't seed the files, only keeps them on your drive. This will quickly fill up your storage.",
            control: persist, transparent: true)
        persistCard.labelTarget = persist

        setContent([locationCard, persistCard])
        footer.setChecks([checkSpaceRequirements()])
    }

    required init?(coder: NSCoder) {
        nil
    }

    // MARK: Download location

    /// `onSelected={selectDownloadFolder}`: the folder of the chosen place becomes the download path.
    private func showLocationPicker() {
        let current = UserDefaults.standard.string(forKey: Self.locationKey) ?? "cache"
        let picker = CommandPopoverViewController(
            title: "Torrent Download Location", placeholder: "Search...",
            groups: [CommandGroup(options: Self.locations.map { CommandOption(value: $0.key, label: $0.label) })],
            selectedValues: [current], allowsMultiple: false, sourceView: combo)
        picker.onSelectionChanged = { [weak self] values in
            guard let self, let value = values.first else { return }
            Settings.write(value, forKey: Self.locationKey)
            self.combo.configure(text: Self.locations.first(where: { $0.key == value })?.label ?? value, placeholder: false)
            TorrentBackendManager.shared.applyCurrentSettings()
            self.pathChanged()
        }
        presenter?.present(picker, animated: false)
    }

    /// `$settings.torrentPath` changed: the field shows it and the space is checked again.
    private func pathChanged() {
        let path = TorrentBackendSettings().path
        pathField.text = path
        guard path != shownPath else { return }
        shownPath = path
        footer.setChecks([checkSpaceRequirements()])
    }

    // MARK: Checks

    /// `checkSpaceRequirements`: the space left where the torrents go.
    private func checkSpaceRequirements() -> SetupCheck {
        let check = SetupCheck(title: "Storage Space", pending: "Checking available storage space...")
        let path = TorrentBackendSettings().path
        DispatchQueue.global(qos: .userInitiated).async {
            let space: Int64
            do {
                space = try Native.checkAvailableSpace(at: path)
            } catch {
                DispatchQueue.main.async {
                    AppErrorToast.show(error.localizedDescription, title: "Failed to check available storage space.", duration: 15)
                    check.resolve(.init(status: .error, text: "Could not determine available storage space."))
                }
                return
            }
            let shown = TorrentFormat.fastPrettyBytes(UInt64(max(0, space)))
            if space < 1_000_000_000 {
                check.resolve(.init(status: .error, text: "\(shown) available, 1GB is the recommended minimum."))
            } else if space < 5_000_000_000 {
                check.resolve(.init(status: .warning, text: "\(shown) available, 5GB is the recommended amount."))
            } else {
                check.resolve(.init(status: .success, text: "\(shown) available."))
            }
        }
        return check
    }
}

/// `<Input type='url' readonly … class='sm:w-60 rounded-r-none pointer-events-none' />`: a field of the
/// look of an input that takes no touch and shows a text. What does not fit between its paddings (`px-3`, inside
/// the 1pt border) is cut off there, with no ellipsis, as an input does.
private final class SetupReadOnlyField: UIView {
    private let label = UILabel()
    private let placeholder: String

    var text: String {
        didSet { render() }
    }

    init(text: String, placeholder: String, width: CGFloat) {
        self.text = text
        self.placeholder = placeholder
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        isUserInteractionEnabled = false              // pointer-events-none
        backgroundColor = UIColor.HayaseTheme.muted   // bg-muted
        layer.cornerRadius = 6
        layer.maskedCorners = [.layerMinXMinYCorner, .layerMinXMaxYCorner]   // rounded-r-none
        layer.borderWidth = 1                                                // border-input
        layer.borderColor = UIColor.HayaseTheme.input.cgColor
        // shadow-sm: 0 1px 2px 0 rgb(0 0 0 / 0.05)
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.05
        layer.shadowOffset = CGSize(width: 0, height: 1)
        layer.shadowRadius = 1

        label.font = .nunito(ofSize: 14, weight: .regular)   // text-sm
        label.numberOfLines = 1
        label.lineBreakMode = .byClipping
        label.clipsToBounds = true
        addSubview(label)
        render()

        isAccessibilityElement = true
        NSLayoutConstraint.activate([heightAnchor.constraint(equalToConstant: 36)])   // h-9
        let preferred = widthAnchor.constraint(equalToConstant: width)
        preferred.priority = .defaultHigh
        preferred.isActive = true
        setContentHuggingPriority(.required, for: .horizontal)
    }

    required init?(coder: NSCoder) {
        nil
    }

    private func render() {
        let empty = text.isEmpty
        label.text = empty ? placeholder : text
        label.textColor = empty ? UIColor.HayaseTheme.mutedForeground : UIColor.HayaseTheme.foreground
        accessibilityValue = text
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // px-3 inside the 1pt border, on both sides
        label.frame = CGRect(x: 13, y: 0, width: max(0, bounds.width - 26), height: bounds.height)
    }
}
