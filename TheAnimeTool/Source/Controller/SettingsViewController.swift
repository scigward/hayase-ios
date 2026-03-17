//
//  SettingsViewController.swift
//  TheAnimeTool
//
//  Matches Hayase's settings layout exactly:
//  • Flat SettingCard style: rounded-lg border p-4, title bold white, description muted
//  • No colored icon squares (those are iOS Settings style, not Hayase style)
//  • Dark background #0a0a0f, card bg #18181b, border #27272a
//  • Sections: bold text-xl header (matching <div class='font-weight-bold text-xl font-bold'>)
//  • Controls: UISwitch (indigo tint) for toggles, UILabel for values
//
//  Ported from Hayase settings pages:
//    /app/settings/         (Player: subtitle, language, playback, interface, external player)
//    /app/settings/client/  (Security, Client settings)
//    /app/settings/interface/ (Visibility, UI settings)
//    /app/settings/extensions/ (Lookup, Extensions)
//    /app/settings/accounts/  (Account settings)
//    /app/settings/app/       (App settings, Debug)
//

import UIKit
import SafariServices

// MARK: - SettingsViewController

class SettingsViewController: UIViewController {

    // MARK: - Row / Section model

    private enum RowKind {
        case toggle(userDefaultsKey: String, defaultValue: Bool)
        case value(String)
        case link(String)
        case navigate
        /// Button-style row (e.g. Import/Export/Reset).  Tapped but has no toggle or value.
        case action
    }

    private struct Row {
        let title:       String
        let description: String
        let kind:        RowKind
    }

    private struct Section {
        let header: String
        let rows:   [Row]
    }

    // MARK: - Lifecycle

    /// Programmatic initializer – used when pushed from TorrentDetailViewController.
    init() {
        super.init(nibName: nil, bundle: nil)
    }

    /// Storyboard initializer – used when created as a tab-bar root VC.
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        tabBarItem = UITabBarItem(
            title: "Settings",
            image: UIImage(systemName: "gearshape"),
            selectedImage: UIImage(systemName: "gearshape.fill"))
    }

    private var tableView: UITableView!
    private let bgColor  = UIColor(red: 0.039, green: 0.039, blue: 0.059, alpha: 1)   // #0a0a0f
    private let cardColor = UIColor(red: 0.094, green: 0.094, blue: 0.11,  alpha: 1)  // #18181b
    private let mutedFg  = UIColor(red: 0.631, green: 0.631, blue: 0.671, alpha: 1)   // #a1a1aa

    private lazy var sections: [Section] = [

        // ──────────────────────────────────────────────────────────
        // Player settings (Hayase /app/settings/ — +page.svelte)
        // ──────────────────────────────────────────────────────────

        // Subtitle Settings
        Section(header: "Subtitle Settings", rows: [
            Row(title: "Find Missing Subtitle Fonts",
                description: "Automatically finds and loads fonts that are missing from a video's subtitles.",
                kind: .toggle(userDefaultsKey: "pref_missingFont", defaultValue: false)),
            Row(title: "Subtitle Render Resolution Limit",
                description: "Max resolution to render subtitles at. If your resolution is higher than this setting the subtitles will be upscaled linearly. This will GREATLY improve rendering speeds for complex typesetting for slower devices.",
                kind: .value("1080p")),
        ]),
        // Language Settings
        Section(header: "Language Settings", rows: [
            Row(title: "Preferred Subtitle Language",
                description: "Subtitle language to select automatically when a video is loaded. Defaults to English.",
                kind: .value("English")),
            Row(title: "Preferred Audio Language",
                description: "Audio language to select automatically when a video is loaded. Defaults to Japanese.",
                kind: .value("Japanese")),
        ]),
        // Playback Settings — matches Hayase exactly
        Section(header: "Playback Settings", rows: [
            Row(title: "Auto-Play Next Episode",
                description: "Automatically starts playing next episode when a video ends.",
                kind: .toggle(userDefaultsKey: "pref_autoplay", defaultValue: true)),
            Row(title: "Pause On Lost Visibility",
                description: "Pauses/Resumes video playback when the app goes to background.",
                kind: .toggle(userDefaultsKey: "pref_playerPause", defaultValue: false)),
            Row(title: "PiP On Lost Visibility",
                description: "Automatically enters Picture in Picture mode when the app loses visibility.",
                kind: .toggle(userDefaultsKey: "pref_autoPiP", defaultValue: false)),
            Row(title: "Auto-Complete Episodes",
                description: "Automatically marks episodes as complete when you finish watching them. Requires AniList login.",
                kind: .toggle(userDefaultsKey: "pref_autocomplete", defaultValue: false)),
            Row(title: "Deband Video",
                description: "Reduces banding (compression artifacts) on dark and compressed videos. High performance impact. Recommended for seasonal web releases, not recommended for high quality blu-ray videos.",
                kind: .toggle(userDefaultsKey: "pref_deband", defaultValue: false)),
            Row(title: "Seek Duration",
                description: "Seconds to skip forward or backward when using the seek buttons. Higher values might negatively impact buffering speeds.",
                kind: .value("5 sec")),
            Row(title: "Auto-Skip Intro/Outro",
                description: "Attempt to automatically skip intro and outro sections. This WILL sometimes skip incorrect chapters, as some of the chapter data is community sourced.",
                kind: .toggle(userDefaultsKey: "pref_skipIntro", defaultValue: false)),
            Row(title: "Auto-Skip Filler",
                description: "Automatically skip filler episodes. This WILL skip ENTIRE episodes.",
                kind: .toggle(userDefaultsKey: "pref_skipFiller", defaultValue: false)),
        ]),
        // Interface Settings
        Section(header: "Interface Settings", rows: [
            Row(title: "Minimal UI",
                description: "Forces minimalistic player UI, hides controls.",
                kind: .toggle(userDefaultsKey: "pref_minimalUI", defaultValue: false)),
            Row(title: "Show Streaming Logger",
                description: "Keeps the streaming log overlay visible during playback instead of auto-hiding.",
                kind: .toggle(userDefaultsKey: "pref_showLogger", defaultValue: false)),
        ]),

        // ──────────────────────────────────────────────────────────
        // Client settings (Hayase /app/settings/client/)
        // ──────────────────────────────────────────────────────────

        // Security Settings
        Section(header: "Security Settings", rows: [
            Row(title: "Use DNS Over HTTPS",
                description: "Enables DNS Over HTTPS, useful if your ISP blocks certain domains.",
                kind: .toggle(userDefaultsKey: "pref_enableDoH", defaultValue: false)),
            Row(title: "DNS Over HTTPS URL",
                description: "What URL to use for querying DNS Over HTTPS.",
                kind: .value("https://cloudflare-dns.com/dns-query")),
        ]),
        // Client Settings
        Section(header: "Client Settings", rows: [
            Row(title: "Torrent Download Location",
                description: "Path to the folder used to store torrents. By default this is the app's cache folder, which might lose data when the OS tries to reclaim storage.",
                kind: .value("Default")),
            Row(title: "Persist Files",
                description: "Keeps torrent files instead of deleting them after a new torrent is played. This doesn't seed the files, only keeps them on your drive. This will quickly fill up your storage.",
                kind: .toggle(userDefaultsKey: "pref_persistFiles", defaultValue: false)),
            Row(title: "Streamed Download",
                description: "Only downloads the data that's directly needed for playback, down to the minute, instead of downloading an entire batch of episodes. Will not buffer ahead more than a few seconds, and will stop downloading once the few second buffer is filled. Saves bandwidth and reduces strain on the peer swarm.",
                kind: .toggle(userDefaultsKey: "pref_streamedDownload", defaultValue: false)),
            Row(title: "Transfer Speed Limit",
                description: "Download/Upload speed limit for torrents, higher values increase CPU usage, and values higher than your storage write speeds will quickly fill up RAM.",
                kind: .value("∞ Mb/s")),
            Row(title: "Max Number of Connections",
                description: "Number of peers per torrent. Higher values will increase download speeds but might quickly fill up available ports if your ISP limits the maximum allowed number of open connections.",
                kind: .value("55")),
            Row(title: "Forwarded Torrent Port",
                description: "Forwarded port used for incoming torrent connections. 0 automatically finds an open unused port. Change this to a specific port if you forwarded manually, or if you use a VPN.",
                kind: .value("0")),
            Row(title: "DHT Port",
                description: "Port used for DHT connections. 0 is automatic.",
                kind: .value("0")),
            Row(title: "Disable DHT",
                description: "Disables Distributed Hash Tables for use in private trackers to improve privacy. Might greatly reduce the amount of discovered peers.",
                kind: .toggle(userDefaultsKey: "pref_disableDHT", defaultValue: false)),
            Row(title: "Disable PeX",
                description: "Disables Peer Exchange for use in private trackers to improve privacy. Might greatly reduce the amount of discovered peers.",
                kind: .toggle(userDefaultsKey: "pref_disablePeX", defaultValue: false)),
        ]),

        // ──────────────────────────────────────────────────────────
        // Interface settings (Hayase /app/settings/interface/)
        // ──────────────────────────────────────────────────────────

        // Visibility Settings
        Section(header: "Visibility Settings", rows: [
            Row(title: "Show Hentai",
                description: "Shows hentai content throughout the app. If disabled all hentai content will be hidden and not shown in search results, but shown if present in your list.\n\nThis is also an AniList account setting, so make sure it is enabled in account settings as well to avoid inconsistencies.",
                kind: .toggle(userDefaultsKey: "pref_showHentai", defaultValue: false)),
            Row(title: "Hide Spoilers",
                description: "Hides potential spoilers such as titles, descriptions, episode images and ratings throughout the app.",
                kind: .toggle(userDefaultsKey: "pref_hideSpoilers", defaultValue: false)),
        ]),

        // ──────────────────────────────────────────────────────────
        // Extensions settings (Hayase /app/settings/extensions/)
        // ──────────────────────────────────────────────────────────

        // Lookup Settings
        Section(header: "Lookup Settings", rows: [
            Row(title: "Torrent Quality",
                description: "What quality to use when trying to find torrents. This doesn't exclude other qualities from being found. Non-1080p resolutions might not be available for all shows, or find way less results.",
                kind: .value("1080p")),
            Row(title: "Auto-Select Torrents",
                description: "Automatically selects torrents based on quality and amount of seeders. Disable this to have more precise control over played torrents.",
                kind: .toggle(userDefaultsKey: "pref_searchAutoSelect", defaultValue: true)),
            Row(title: "Lookup Preference",
                description: "What to prioritize when looking for and sorting results. Quality will focus on the best quality available, Size will focus on the smallest file size, and Availability will pick results with the most peers.",
                kind: .value("Quality")),
        ]),
        // Extensions
        Section(header: "Extensions", rows: [
            Row(title: "Manage Extensions",
                description: "Install and configure Hayase-compatible torrent/NZB extensions.",
                kind: .navigate),
        ]),

        // ──────────────────────────────────────────────────────────
        // Account settings (Hayase /app/settings/accounts/)
        // ──────────────────────────────────────────────────────────

        Section(header: "Account Settings", rows: [
            Row(title: "AniList",
                description: "Connect your AniList account for anime tracking, list sync, and metadata.",
                kind: .navigate),
        ]),

        // ──────────────────────────────────────────────────────────
        // App settings (Hayase /app/settings/app/)
        // ──────────────────────────────────────────────────────────

        Section(header: "App Settings", rows: [
            Row(title: "Import Settings From File",
                description: "Import a previously exported settings file.",
                kind: .action),
            Row(title: "Export Settings To File",
                description: "Export current settings to a file for backup.",
                kind: .action),
            Row(title: "Reset Everything To Default",
                description: "Resets ALL settings and data to their default values. This cannot be undone.",
                kind: .action),
        ]),
        // Debug Settings
        Section(header: "Debug Settings", rows: [
            Row(title: "Copy App and Device Info",
                description: "Copy app and device debug info and capabilities, such as version information and settings to clipboard.",
                kind: .action),
        ]),

        // ──────────────────────────────────────────────────────────
        // About
        // ──────────────────────────────────────────────────────────

        Section(header: "About", rows: [
            Row(title: "Version",
                description: "NyaiS — an iOS client inspired by Hayase.",
                kind: .value(appVersion())),
            Row(title: "Source Code",
                description: "View the NyaiS source code on GitHub.",
                kind: .link("https://github.com/scigward/NyaiS")),
            Row(title: "AniList",
                description: "Anime metadata powered by AniList GraphQL API.",
                kind: .link("https://anilist.co")),
        ]),
    ]

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Settings"
        view.backgroundColor = bgColor
        navigationController?.navigationBar.prefersLargeTitles = true
        navigationItem.largeTitleDisplayMode = .always

        tableView = UITableView(frame: view.bounds, style: .plain)
        tableView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        tableView.backgroundColor = bgColor
        tableView.separatorStyle = .none
        tableView.delegate   = self
        tableView.dataSource = self
        tableView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: 24, right: 0)
        tableView.register(HayaseSettingToggleCell.self,
                           forCellReuseIdentifier: HayaseSettingToggleCell.reuseID)
        tableView.register(HayaseSettingValueCell.self,
                           forCellReuseIdentifier: HayaseSettingValueCell.reuseID)

        // Hayase header: "Manage your app settings, preferences and accounts."
        let headerLabel = UILabel()
        headerLabel.text = "Manage your app settings, preferences and accounts."
        headerLabel.font = .systemFont(ofSize: 14)
        headerLabel.textColor = mutedFg
        headerLabel.numberOfLines = 0
        let headerContainer = UIView(frame: CGRect(x: 0, y: 0, width: 0, height: 40))
        headerLabel.translatesAutoresizingMaskIntoConstraints = false
        headerContainer.addSubview(headerLabel)
        NSLayoutConstraint.activate([
            headerLabel.leadingAnchor.constraint(equalTo: headerContainer.leadingAnchor, constant: 16),
            headerLabel.trailingAnchor.constraint(equalTo: headerContainer.trailingAnchor, constant: -16),
            headerLabel.topAnchor.constraint(equalTo: headerContainer.topAnchor, constant: 4),
            headerLabel.bottomAnchor.constraint(equalTo: headerContainer.bottomAnchor, constant: -4),
        ])
        tableView.tableHeaderView = headerContainer

        view.addSubview(tableView)
    }

    private func appVersion() -> String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(v) (\(b))"
    }
}

// MARK: - UITableViewDataSource

extension SettingsViewController: UITableViewDataSource {

    func numberOfSections(in tableView: UITableView) -> Int { sections.count }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        sections[section].rows.count
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        // Hayase: <div class='font-weight-bold text-xl font-bold'>Section Name</div>
        let container = UIView()
        container.backgroundColor = .clear
        let label = UILabel()
        label.text = sections[section].header
        label.font = .systemFont(ofSize: 20, weight: .bold)
        label.textColor = .white
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 24),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8),
        ])
        return container
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        UITableView.automaticDimension
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let row = sections[indexPath.section].rows[indexPath.row]
        switch row.kind {
        case .toggle(let key, let def):
            let cell = tableView.dequeueReusableCell(
                withIdentifier: HayaseSettingToggleCell.reuseID, for: indexPath) as! HayaseSettingToggleCell
            cell.configure(title: row.title, description: row.description,
                           key: key, defaultValue: def)
            cell.backgroundColor = cardColor
            return cell
        case .value(let val):
            let cell = tableView.dequeueReusableCell(
                withIdentifier: HayaseSettingValueCell.reuseID, for: indexPath) as! HayaseSettingValueCell
            cell.configure(title: row.title, description: row.description, value: val, isLink: false)
            cell.backgroundColor = cardColor
            return cell
        case .link:
            let cell = tableView.dequeueReusableCell(
                withIdentifier: HayaseSettingValueCell.reuseID, for: indexPath) as! HayaseSettingValueCell
            cell.configure(title: row.title, description: row.description, value: nil, isLink: true)
            cell.backgroundColor = cardColor
            return cell
        case .navigate:
            let cell = tableView.dequeueReusableCell(
                withIdentifier: HayaseSettingValueCell.reuseID, for: indexPath) as! HayaseSettingValueCell
            cell.configure(title: row.title, description: row.description, value: nil, isLink: false)
            cell.accessoryType = .disclosureIndicator
            cell.backgroundColor = cardColor
            return cell
        case .action:
            let cell = tableView.dequeueReusableCell(
                withIdentifier: HayaseSettingValueCell.reuseID, for: indexPath) as! HayaseSettingValueCell
            cell.configure(title: row.title, description: row.description, value: nil, isLink: false)
            cell.backgroundColor = cardColor
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
            if let url = URL(string: urlStr) { present(SFSafariViewController(url: url), animated: true) }
        case .navigate:
            if row.title == "Manage Extensions" {
                let extVC = ExtensionsViewController()
                navigationController?.pushViewController(extVC, animated: true)
            }
            // Other navigate rows (e.g. AniList) are UI placeholders — no wiring yet.
        case .action:
            // Action rows are UI placeholders — no wiring yet.
            break
        default:
            break
        }
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        UITableView.automaticDimension
    }

    func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat {
        80
    }
}

// MARK: - HayaseSettingToggleCell
// Matches Hayase SettingCard.svelte: rounded-lg border p-4 flex justify-between
// Left: title (font-bold) + description (text-sm text-muted-foreground)
// Right: UISwitch with indigo tint

final class HayaseSettingToggleCell: UITableViewCell {
    static let reuseID = "HayaseSettingToggleCell"

    private let titleLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 15, weight: .bold)
        l.textColor = .white
        l.numberOfLines = 1
        return l
    }()
    private let descLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 13)
        l.textColor = UIColor(red: 0.631, green: 0.631, blue: 0.671, alpha: 1)  // #a1a1aa
        l.numberOfLines = 0
        return l
    }()
    private let toggle: UISwitch = {
        let s = UISwitch()
        s.onTintColor = .systemIndigo
        return s
    }()
    private var udKey = ""

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setup()
    }
    required init?(coder: NSCoder) { super.init(coder: coder); setup() }

    private func setup() {
        selectionStyle = .none
        // Card: rounded-lg border p-4
        contentView.layer.cornerRadius = 8
        contentView.layer.masksToBounds = true
        contentView.layer.borderWidth = 1
        contentView.layer.borderColor = UIColor(white: 0.15, alpha: 1).cgColor  // --border dark

        let textStack = UIStackView(arrangedSubviews: [titleLabel, descLabel])
        textStack.axis = .vertical
        textStack.spacing = 4
        textStack.translatesAutoresizingMaskIntoConstraints = false

        toggle.translatesAutoresizingMaskIntoConstraints = false
        toggle.setContentHuggingPriority(.required, for: .horizontal)
        toggle.addTarget(self, action: #selector(toggled), for: .valueChanged)

        contentView.addSubview(textStack)
        contentView.addSubview(toggle)

        NSLayoutConstraint.activate([
            textStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            textStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            textStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: toggle.leadingAnchor, constant: -12),

            toggle.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            toggle.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
        ])
    }

    func configure(title: String, description: String, key: String, defaultValue: Bool) {
        titleLabel.text = title
        descLabel.text  = description
        udKey = key
        let stored = UserDefaults.standard.object(forKey: key) as? Bool ?? defaultValue
        toggle.setOn(stored, animated: false)
    }

    @objc private func toggled(_ sender: UISwitch) {
        UserDefaults.standard.set(sender.isOn, forKey: udKey)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        contentView.frame = contentView.frame.inset(by: UIEdgeInsets(top: 4, left: 16, bottom: 4, right: 16))
    }
}

// MARK: - HayaseSettingValueCell
// Same card style as HayaseSettingToggleCell but with a UILabel value on the right
// (or a chevron for links).

final class HayaseSettingValueCell: UITableViewCell {
    static let reuseID = "HayaseSettingValueCell"

    private let titleLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 15, weight: .bold)
        l.textColor = .white
        l.numberOfLines = 1
        return l
    }()
    private let descLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 13)
        l.textColor = UIColor(red: 0.631, green: 0.631, blue: 0.671, alpha: 1)
        l.numberOfLines = 0
        return l
    }()
    private let valueLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 14)
        l.textColor = UIColor(red: 0.631, green: 0.631, blue: 0.671, alpha: 1)
        l.setContentHuggingPriority(.required, for: .horizontal)
        return l
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setup()
    }
    required init?(coder: NSCoder) { super.init(coder: coder); setup() }

    private func setup() {
        contentView.layer.cornerRadius = 8
        contentView.layer.masksToBounds = true
        contentView.layer.borderWidth = 1
        contentView.layer.borderColor = UIColor(white: 0.15, alpha: 1).cgColor

        let textStack = UIStackView(arrangedSubviews: [titleLabel, descLabel])
        textStack.axis = .vertical
        textStack.spacing = 4
        textStack.translatesAutoresizingMaskIntoConstraints = false

        valueLabel.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(textStack)
        contentView.addSubview(valueLabel)

        NSLayoutConstraint.activate([
            textStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            textStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            textStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: valueLabel.leadingAnchor, constant: -12),

            valueLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            valueLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
        ])
    }

    func configure(title: String, description: String, value: String?, isLink: Bool) {
        titleLabel.text = title
        descLabel.text  = description
        valueLabel.text = value
        valueLabel.isHidden = value == nil
        accessoryType = isLink ? .disclosureIndicator : .none
        selectionStyle = isLink ? .default : .none
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        contentView.frame = contentView.frame.inset(by: UIEdgeInsets(top: 4, left: 16, bottom: 4, right: 16))
    }
}

// Legacy cell types kept as typealiases so any existing code referencing them compiles.
typealias SettingsToggleCell = HayaseSettingToggleCell
typealias SettingsDetailCell = HayaseSettingValueCell

