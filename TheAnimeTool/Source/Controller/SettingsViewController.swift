//
//  SettingsViewController.swift
//  TheAnimeTool
//
//  A comprehensive settings screen modelled after Hayase's settings panel.
//  All rows are UI-only placeholders; functionality will be wired in a later pass.
//

import UIKit
import SafariServices

// MARK: - SettingsViewController

class SettingsViewController: UIViewController {

    // MARK: - Row / Section model

    private enum RowKind {
        case toggle(Bool)
        case detail(String)
        case navigation
        case link(String)
        case destructive
    }

    private struct Row {
        let title:    String
        let subtitle: String?
        let icon:     String        // SF Symbol name
        let iconBg:   UIColor
        let kind:     RowKind
    }

    private struct Section {
        let header: String
        let rows:   [Row]
    }

    // MARK: - Lifecycle

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        tabBarItem = UITabBarItem(
            title: "Settings",
            image: UIImage(systemName: "gearshape"),
            selectedImage: UIImage(systemName: "gearshape.fill"))
    }

    private var tableView: UITableView!
    private lazy var sections: [Section] = buildSections()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Settings"
        view.backgroundColor = .systemGroupedBackground
        navigationController?.navigationBar.prefersLargeTitles = true
        navigationItem.largeTitleDisplayMode = .always

        tableView = UITableView(frame: view.bounds, style: .insetGrouped)
        tableView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        tableView.delegate   = self
        tableView.dataSource = self
        tableView.register(SettingsToggleCell.self, forCellReuseIdentifier: SettingsToggleCell.reuseID)
        tableView.register(SettingsDetailCell.self, forCellReuseIdentifier: SettingsDetailCell.reuseID)
        view.addSubview(tableView)
    }

    // MARK: - Data

    private func buildSections() -> [Section] { [
        Section(header: "Player", rows: [
            Row(title: "Video Quality",
                subtitle: nil,
                icon: "tv", iconBg: .systemBlue,
                kind: .detail("Auto")),
            Row(title: "Autoplay Next Episode",
                subtitle: nil,
                icon: "play.circle.fill", iconBg: .systemGreen,
                kind: .toggle(true)),
            Row(title: "Skip Intro",
                subtitle: nil,
                icon: "forward.fill", iconBg: .systemOrange,
                kind: .toggle(true)),
            Row(title: "Intro Skip Duration",
                subtitle: nil,
                icon: "timer", iconBg: .systemOrange,
                kind: .detail("90 s")),
            Row(title: "Skip Outro",
                subtitle: nil,
                icon: "forward.end.fill", iconBg: .systemOrange,
                kind: .toggle(false)),
            Row(title: "Subtitle Language",
                subtitle: nil,
                icon: "textformat", iconBg: .systemPurple,
                kind: .detail("English")),
            Row(title: "Subtitle Size",
                subtitle: nil,
                icon: "textformat.size", iconBg: .systemPurple,
                kind: .detail("Medium")),
            Row(title: "Hardware Decoding",
                subtitle: "Improves performance on supported devices",
                icon: "cpu", iconBg: .systemGray,
                kind: .toggle(true)),
        ]),
        Section(header: "Downloads", rows: [
            Row(title: "Download Location",
                subtitle: nil,
                icon: "folder.fill", iconBg: .systemYellow,
                kind: .detail("Documents")),
            Row(title: "Max Concurrent Downloads",
                subtitle: nil,
                icon: "square.stack.fill", iconBg: .systemIndigo,
                kind: .detail("3")),
            Row(title: "Max Download Speed",
                subtitle: nil,
                icon: "arrow.down.circle.fill", iconBg: .systemGreen,
                kind: .detail("Unlimited")),
            Row(title: "Max Upload Speed",
                subtitle: nil,
                icon: "arrow.up.circle.fill", iconBg: .systemTeal,
                kind: .detail("Unlimited")),
            Row(title: "Delete After Watching",
                subtitle: "Automatically removes files after playback",
                icon: "trash.slash.fill", iconBg: .systemRed,
                kind: .toggle(false)),
            Row(title: "Download on Cellular",
                subtitle: "Allow downloads over mobile data",
                icon: "antenna.radiowaves.left.and.right", iconBg: .systemRed,
                kind: .toggle(false)),
        ]),
        Section(header: "Network", rows: [
            Row(title: "Listening Port",
                subtitle: nil,
                icon: "network", iconBg: .systemBlue,
                kind: .detail("6881")),
            Row(title: "Enable DHT",
                subtitle: "Distributed hash table for peer discovery",
                icon: "dot.radiowaves.left.and.right", iconBg: .systemGreen,
                kind: .toggle(true)),
            Row(title: "Enable UPnP / NAT-PMP",
                subtitle: "Automatic port forwarding",
                icon: "arrow.up.forward.square.fill", iconBg: .systemGreen,
                kind: .toggle(true)),
            Row(title: "Local Peer Discovery",
                subtitle: "Find peers on your local network",
                icon: "wifi", iconBg: .systemBlue,
                kind: .toggle(true)),
            Row(title: "Peer Connection Limit",
                subtitle: nil,
                icon: "person.3.fill", iconBg: .systemGray,
                kind: .detail("200")),
            Row(title: "Validate HTTPS Trackers",
                subtitle: nil,
                icon: "lock.shield.fill", iconBg: .systemOrange,
                kind: .toggle(false)),
        ]),
        Section(header: "Appearance", rows: [
            Row(title: "App Theme",
                subtitle: nil,
                icon: "moon.circle.fill", iconBg: .systemGray,
                kind: .detail("System")),
            Row(title: "Accent Color",
                subtitle: nil,
                icon: "paintbrush.fill", iconBg: .systemIndigo,
                kind: .detail("Indigo")),
            Row(title: "Grid Columns",
                subtitle: nil,
                icon: "square.grid.3x3.fill", iconBg: .systemBlue,
                kind: .detail("3")),
            Row(title: "Show Score Badge",
                subtitle: nil,
                icon: "star.fill", iconBg: .systemYellow,
                kind: .toggle(true)),
            Row(title: "Show Episode Thumbnails",
                subtitle: nil,
                icon: "photo.fill", iconBg: .systemTeal,
                kind: .toggle(true)),
        ]),
        Section(header: "Notifications", rows: [
            Row(title: "New Episode Alerts",
                subtitle: "Notify when a tracked anime airs",
                icon: "bell.badge.fill", iconBg: .systemRed,
                kind: .toggle(false)),
            Row(title: "Download Complete",
                subtitle: nil,
                icon: "checkmark.circle.fill", iconBg: .systemGreen,
                kind: .toggle(true)),
            Row(title: "Seeding Notification",
                subtitle: "Alert when torrent starts seeding",
                icon: "arrow.up.circle.fill", iconBg: .systemTeal,
                kind: .toggle(false)),
        ]),
        Section(header: "About", rows: [
            Row(title: "Version",
                subtitle: nil,
                icon: "info.circle.fill", iconBg: .systemBlue,
                kind: .detail(appVersion())),
            Row(title: "Source Code",
                subtitle: nil,
                icon: "chevron.left.forwardslash.chevron.right", iconBg: .systemGray,
                kind: .link("https://github.com/scigward/NyaiS")),
            Row(title: "LibTorrent-Swift",
                subtitle: "by XITRIX",
                icon: "link", iconBg: .systemGray,
                kind: .link("https://github.com/XITRIX/LibTorrent-Swift")),
            Row(title: "AniList API",
                subtitle: "Anime metadata provider",
                icon: "link", iconBg: .systemGreen,
                kind: .link("https://anilist.co")),
            Row(title: "Reset All Settings",
                subtitle: nil,
                icon: "arrow.counterclockwise", iconBg: .systemRed,
                kind: .destructive),
        ]),
    ]}

    private func appVersion() -> String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(v) (\(b))"
    }

    // MARK: - Icon rendering

    /// Renders an SF Symbol on a rounded-square coloured background (iOS Settings style).
    private func iconImage(symbol: String, bg: UIColor) -> UIImage {
        let size = CGSize(width: 28, height: 28)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            bg.setFill()
            UIBezierPath(roundedRect: CGRect(origin: .zero, size: size),
                         cornerRadius: 6).fill()
            let symbolCfg = UIImage.SymbolConfiguration(pointSize: 14, weight: .medium)
            if let sym = UIImage(systemName: symbol, withConfiguration: symbolCfg)?
                .withTintColor(.white, renderingMode: .alwaysOriginal) {
                let imgRect = CGRect(x: (size.width - 16) / 2,
                                     y: (size.height - 16) / 2,
                                     width: 16, height: 16)
                sym.draw(in: imgRect)
            }
        }
    }
}

// MARK: - UITableViewDataSource

extension SettingsViewController: UITableViewDataSource {

    func numberOfSections(in tableView: UITableView) -> Int { sections.count }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        sections[section].rows.count
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        sections[section].header
    }

    func tableView(_ tableView: UITableView,
                   cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let row = sections[indexPath.section].rows[indexPath.row]
        let icon = iconImage(symbol: row.icon, bg: row.iconBg)

        switch row.kind {
        case .toggle(let isOn):
            let cell = tableView.dequeueReusableCell(
                withIdentifier: SettingsToggleCell.reuseID,
                for: indexPath) as! SettingsToggleCell
            let key = "setting_\(indexPath.section)_\(indexPath.row)"
            // Persist via UserDefaults; fall back to schema default on first launch.
            let persisted = UserDefaults.standard.object(forKey: key) as? Bool ?? isOn
            cell.configure(icon: icon, title: row.title, subtitle: row.subtitle,
                           isOn: persisted, userDefaultsKey: key)
            return cell

        case .detail(let value):
            let cell = tableView.dequeueReusableCell(
                withIdentifier: SettingsDetailCell.reuseID,
                for: indexPath) as! SettingsDetailCell
            cell.configure(icon: icon, title: row.title, subtitle: row.subtitle,
                           detail: value, showChevron: false)
            return cell

        case .navigation:
            let cell = tableView.dequeueReusableCell(
                withIdentifier: SettingsDetailCell.reuseID,
                for: indexPath) as! SettingsDetailCell
            cell.configure(icon: icon, title: row.title, subtitle: row.subtitle,
                           detail: nil, showChevron: true)
            return cell

        case .link:
            let cell = tableView.dequeueReusableCell(
                withIdentifier: SettingsDetailCell.reuseID,
                for: indexPath) as! SettingsDetailCell
            cell.configure(icon: icon, title: row.title, subtitle: row.subtitle,
                           detail: nil, showChevron: true)
            return cell

        case .destructive:
            let cell = tableView.dequeueReusableCell(
                withIdentifier: SettingsDetailCell.reuseID,
                for: indexPath) as! SettingsDetailCell
            cell.configure(icon: icon, title: row.title, subtitle: nil,
                           detail: nil, showChevron: false, titleColor: .systemRed)
            return cell
        }
    }
}

// MARK: - UITableViewDelegate

extension SettingsViewController: UITableViewDelegate {

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let row = sections[indexPath.section].rows[indexPath.row]
        switch row.kind {
        case .link(let urlStr):
            guard let url = URL(string: urlStr) else { return }
            present(SFSafariViewController(url: url), animated: true)
        case .destructive:
            let alert = UIAlertController(
                title: "Reset All Settings",
                message: "This will restore all settings to their defaults. This cannot be undone.",
                preferredStyle: .actionSheet)
            alert.addAction(UIAlertAction(title: "Reset", style: .destructive) { _ in
                // Placeholder — settings persistence wired in a future pass.
            })
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            present(alert, animated: true)
        default:
            break
        }
    }

    func tableView(_ tableView: UITableView, shouldHighlightRowAt indexPath: IndexPath) -> Bool {
        let row = sections[indexPath.section].rows[indexPath.row]
        switch row.kind {
        case .toggle: return false
        default: return true
        }
    }
}

// MARK: - SettingsToggleCell

final class SettingsToggleCell: UITableViewCell {
    static let reuseID = "SettingsToggleCell"

    private let iconView   = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 12)
        l.textColor = .secondaryLabel
        l.numberOfLines = 2
        return l
    }()
    private let toggle = UISwitch()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setup()
    }
    required init?(coder: NSCoder) { super.init(coder: coder); setup() }

    private func setup() {
        selectionStyle = .none
        accessoryView = toggle

        iconView.contentMode = .scaleAspectFit
        iconView.layer.cornerRadius = 6
        iconView.clipsToBounds = true
        titleLabel.font = .systemFont(ofSize: 16)

        [iconView, titleLabel, subtitleLabel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview($0)
        }
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            iconView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 28),
            iconView.heightAnchor.constraint(equalToConstant: 28),

            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -60),
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),

            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            subtitleLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),
        ])
    }

    func configure(icon: UIImage, title: String, subtitle: String?, isOn: Bool,
                   userDefaultsKey: String) {
        iconView.image = icon
        titleLabel.text = title
        subtitleLabel.text = subtitle
        subtitleLabel.isHidden = subtitle == nil
        toggle.isOn = isOn
        toggle.removeTarget(nil, action: nil, for: .valueChanged)
        toggle.tag = 0 // unused; key stored via closure below
        // Store key in the cell so the action handler can persist the value.
        _udKey = userDefaultsKey
        toggle.addTarget(self, action: #selector(toggleChanged(_:)), for: .valueChanged)
    }

    private var _udKey: String = ""

    @objc private func toggleChanged(_ sender: UISwitch) {
        UserDefaults.standard.set(sender.isOn, forKey: _udKey)
    }
}

// MARK: - SettingsDetailCell

final class SettingsDetailCell: UITableViewCell {
    static let reuseID = "SettingsDetailCell"

    private let iconView    = UIImageView()
    private let titleLabel  = UILabel()
    private let subtitleLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 12)
        l.textColor = .secondaryLabel
        l.numberOfLines = 2
        return l
    }()
    private let detailLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 16)
        l.textColor = .secondaryLabel
        l.textAlignment = .right
        l.setContentHuggingPriority(.required, for: .horizontal)
        return l
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setup()
    }
    required init?(coder: NSCoder) { super.init(coder: coder); setup() }

    private func setup() {
        iconView.contentMode = .scaleAspectFit
        iconView.layer.cornerRadius = 6
        iconView.clipsToBounds = true
        titleLabel.font = .systemFont(ofSize: 16)

        [iconView, titleLabel, subtitleLabel, detailLabel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview($0)
        }
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            iconView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 28),
            iconView.heightAnchor.constraint(equalToConstant: 28),

            detailLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            detailLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            detailLabel.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 8),

            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),

            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: detailLabel.leadingAnchor, constant: -8),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            subtitleLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),
        ])
    }

    func configure(icon: UIImage, title: String, subtitle: String?,
                   detail: String?, showChevron: Bool,
                   titleColor: UIColor = .label) {
        iconView.image = icon
        titleLabel.text = title
        titleLabel.textColor = titleColor
        subtitleLabel.text = subtitle
        subtitleLabel.isHidden = subtitle == nil
        detailLabel.text = detail
        detailLabel.isHidden = detail == nil
        accessoryType = showChevron ? .disclosureIndicator : .none
        selectionStyle = showChevron ? .default : .none
    }
}
