//
//  SettingsViewController.swift
//  Hayase
//
//  Mirrors: src/routes/app/settings/+layout.svelte, src/routes/app/settings/+page.ts, src/routes/app/settings/+page.svelte, src/lib/components/SettingsNav.svelte
//
//
//  Navigation shell mirrors the responsive SettingsNav structure. The settings
//  controls themselves predate this navigation audit and are intentionally not
//  described here as source-identical.

import UIKit
import SafariServices

// MARK: - SettingsViewController

class SettingsViewController: UIViewController {

    // MARK: - Tab model

    private enum SettingsTab: Int, CaseIterable {
        case player = 0
        case client
        case interface_
        case extensions
        case accounts
        case app
        case changelog

        var title: String {
            switch self {
            case .player:     return "Player"
            case .client:     return "Client"
            case .interface_: return "Interface"
            case .extensions: return "Extensions"
            case .accounts:   return "Accounts"
            case .app:        return "App"
            case .changelog:  return "Changelog"
            }
        }
    }

    // MARK: - Row / Section model

    private enum RowKind {
        case toggle(userDefaultsKey: String, defaultValue: Bool)
        case value(String)
        /// Selectable value — tapping shows a picker with the given options.
        /// `userDefaultsKey` persists the choice; `options` maps stored-key → display label;
        /// `defaultKey` is the initial stored key.
        case selectable(userDefaultsKey: String, options: [(key: String, label: String)], defaultKey: String)
        /// Editable numeric value — tapping shows a text field.
        case editableNumber(userDefaultsKey: String, defaultValue: String, suffix: String, min: Int, max: Int)
        case link(String)
        case navigate
        case action
        /// Account card — full tracker account card (AniList, Kitsu, MAL, Local).
        case account(TrackerKind)
    }

    private struct Row {
        let title:       String
        let description: String
        let kind:        RowKind
    }

    private struct Section {
        let header: String
        let rows:   [Row]
        let tab:    SettingsTab
    }

    // MARK: - Lifecycle

    init() {
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        tabBarItem = UITabBarItem(
            title: "Settings",
            image: UIImage.hayaseIcon("settings"),
            selectedImage: UIImage.hayaseIcon("settings"))
    }

    // MARK: - Colors (matching Hayase dark theme)

    /// Page background — Hayase uses bg-black
    private let bgColor   = UIColor.black
    /// Card background — Hayase SettingCard: bg-neutral-950 (#0a0a0a)
    private let cardColor = UIColor(red: 0.039, green: 0.039, blue: 0.039, alpha: 1)
    /// Muted foreground — Hayase text-muted-foreground ≈ zinc-400
    private let mutedFg   = UIColor(red: 0.631, green: 0.631, blue: 0.671, alpha: 1)
    /// Separator color — Hayase <Separator> ≈ zinc-800 (#27272a)
    private let separatorColor = UIColor(red: 0.153, green: 0.153, blue: 0.165, alpha: 1)

    // MARK: - State

    private var selectedTab: SettingsTab = .player
    private var settingsRoute: Route.SettingsRoute = .root
    private var tabButtons: [HayaseNavTabButton] = []
    private var tabButtonHeightConstraints: [NSLayoutConstraint] = []
    private weak var headerTabStack: UIStackView?
    private var tableView: UITableView!
    /// Width constraint on the table header container — updated in viewDidLayoutSubviews
    /// so the header always matches the actual table view width (fixes iPad split-view sizing).
    private var headerWidthConstraint: NSLayoutConstraint?
    /// Reentrancy guard: prevents `viewDidLayoutSubviews` from re-setting
    /// `tableView.tableHeaderView` while a `reloadData()` is in progress.
    /// Setting the header triggers a layout pass, which re-enters
    /// `viewDidLayoutSubviews`, and can confuse UIKit's internal state
    /// tracking — causing "invalid number of rows in section" crashes.
    private var isUpdatingHeader = false

    /// Cached snapshot of sections for the currently selected tab.
    /// Stored (not computed) so that UIKit's data-source calls always see
    /// a stable row/section count between reloadData() calls.
    private lazy var visibleSections: [Section] = settingsRoute == .root
        ? []
        : allSections.filter { $0.tab == selectedTab }

    /// Re-caches `visibleSections` from `selectedTab`.
    /// Call this right before every `reloadData()` / `reloadRows(…)`.
    private func refreshVisibleSections() {
        visibleSections = allSections.filter { $0.tab == selectedTab }
    }

    // MARK: - Option lists (matching Hayase src/lib/modules/settings/util.ts)

    private static let languageCodes: [(key: String, label: String)] = [
        ("eng", "English"), ("jpn", "Japanese"), ("chi", "Chinese"),
        ("por", "Portuguese"), ("spa", "Spanish"), ("ger", "German"),
        ("pol", "Polish"), ("cze", "Czech"), ("dan", "Danish"),
        ("gre", "Greek"), ("fin", "Finnish"), ("fre", "French"),
        ("hun", "Hungarian"), ("ita", "Italian"), ("kor", "Korean"),
        ("dut", "Dutch"), ("nor", "Norwegian"), ("rum", "Romanian"),
        ("rus", "Russian"), ("slo", "Slovak"), ("swe", "Swedish"),
        ("ara", "Arabic"), ("idn", "Indonesian"), ("heb", "Hebrew"),
        ("vie", "Vietnamese"), ("tha", "Thai"), ("tur", "Turkish"),
        ("hin", "Hindi"), ("ben", "Bengali"), ("per", "Persian"),
        ("mal", "Malayalam"), ("", "None"),
    ]

    private static let subtitleResolutions: [(key: String, label: String)] = [
        ("0", "None"), ("1440", "1440p"), ("1080", "1080p"), ("720", "720p"), ("480", "480p"),
    ]

    private static let videoResolutions: [(key: String, label: String)] = [
        ("2160", "2160p"), ("1080", "1080p"), ("720", "720p"), ("480", "480p"), ("", "Any"),
    ]

    private static let lookupPreferences: [(key: String, label: String)] = [
        ("quality", "Quality"), ("size", "Size"), ("seeders", "Availability"),
    ]

    private static let titleTypes: [(key: String, label: String)] = [
        ("ANILIST", "Anilist Account Preference"),
        ("ROMAJI", "Romaji (Shingeki no Kyojin)"),
        ("ENGLISH", "English (Attack on Titan)"),
        ("NATIVE", "Native (進撃の巨人)"),
    ]

    private static let torrentBackends: [(key: String, label: String)] = TorrentBackendKind.settingsOptions

    // MARK: - All sections (full data, tagged by tab)

    private lazy var allSections: [Section] = [

        // ── Player tab (Hayase /app/settings/ — +page.svelte) ──

        Section(header: "Subtitle Settings", rows: [
            Row(title: "Find Missing Subtitle Fonts",
                description: "Automatically finds and loads fonts that are missing from a video's subtitles.",
                kind: .toggle(userDefaultsKey: "pref_missingFont", defaultValue: true)),
            Row(title: "Subtitle Render Resolution Limit",
                description: "Max resolution to render subtitles at. If your resolution is higher than this setting the subtitles will be upscaled linearly. This will GREATLY improve rendering speeds for complex typesetting for slower devices.",
                kind: .selectable(userDefaultsKey: Settings.Keys.subtitleRenderHeight, options: Self.subtitleResolutions, defaultKey: Settings.Defaults.subtitleRenderHeight)),
        ], tab: .player),

        Section(header: "Language Settings", rows: [
            Row(title: "Preferred Subtitle Language",
                description: "Subtitle language to select automatically when a video is loaded. Defaults to English.",
                kind: .selectable(userDefaultsKey: Settings.Keys.subtitleLanguage, options: Self.languageCodes, defaultKey: Settings.Defaults.subtitleLanguage)),
            Row(title: "Preferred Audio Language",
                description: "Audio language to select automatically when a video is loaded. Defaults to Japanese.",
                kind: .selectable(userDefaultsKey: Settings.Keys.audioLanguage, options: Self.languageCodes, defaultKey: Settings.Defaults.audioLanguage)),
        ], tab: .player),

        Section(header: "Playback Settings", rows: [
            Row(title: "Auto-Play Next Episode",
                description: "Automatically starts playing next episode when a video ends.",
                kind: .toggle(userDefaultsKey: "pref_autoplay", defaultValue: true)),
            Row(title: "Pause On Lost Visibility",
                description: "Pauses/Resumes video playback when the app goes to background.",
                kind: .toggle(userDefaultsKey: "pref_playerPause", defaultValue: true)),
            Row(title: "PiP On Lost Visibility",
                description: "Automatically enters Picture in Picture mode when the app loses visibility.",
                kind: .toggle(userDefaultsKey: "pref_autoPiP", defaultValue: false)),
            Row(title: "Auto-Complete Episodes",
                description: "Automatically marks episodes as complete when you finish watching them. Requires AniList login.",
                kind: .toggle(userDefaultsKey: Settings.Keys.autocomplete, defaultValue: Settings.Defaults.autocomplete)),
            Row(title: "Deband Video",
                description: "Reduces banding (compression artifacts) on dark and compressed videos. High performance impact. Recommended for seasonal web releases, not recommended for high quality blu-ray videos.",
                kind: .toggle(userDefaultsKey: Settings.Keys.deband, defaultValue: Settings.Defaults.deband)),
            Row(title: "Seek Duration",
                description: "Seconds to skip forward or backward when using the seek buttons. Higher values might negatively impact buffering speeds.",
                kind: .editableNumber(userDefaultsKey: Settings.Keys.seekDuration, defaultValue: Settings.Defaults.seekDuration, suffix: "sec", min: 1, max: 50)),
            Row(title: "Auto-Skip Intro/Outro",
                description: "Attempt to automatically skip intro and outro sections. This WILL sometimes skip incorrect chapters, as some of the chapter data is community sourced.",
                kind: .toggle(userDefaultsKey: "pref_skipIntro", defaultValue: false)),
            Row(title: "Auto-Skip Filler",
                description: "Automatically skip filler episodes. This WILL skip ENTIRE episodes.",
                kind: .toggle(userDefaultsKey: Settings.Keys.skipFiller, defaultValue: Settings.Defaults.skipFiller)),
        ], tab: .player),

        Section(header: "Interface Settings", rows: [
            Row(title: "Minimal UI",
                description: "Forces minimalistic player UI, hides controls.",
                kind: .toggle(userDefaultsKey: "pref_minimalUI", defaultValue: false)),
            Row(title: "Show Streaming Logger",
                description: "Keeps the streaming log overlay visible during playback instead of auto-hiding.",
                kind: .toggle(userDefaultsKey: "pref_showLogger", defaultValue: false)),  // iOS-specific: not in Hayase, kept per user request
        ], tab: .player),

        // ── Client tab (Hayase /app/settings/client/) ──

        Section(header: "Security Settings", rows: [
            Row(title: "Use DNS Over HTTPS",
                description: "Enables DNS Over HTTPS, useful if your ISP blocks certain domains.",
                kind: .toggle(userDefaultsKey: "pref_enableDoH", defaultValue: false)),
            Row(title: "DNS Over HTTPS URL",
                description: "What URL to use for querying DNS Over HTTPS.",
                kind: .editableNumber(userDefaultsKey: "pref_doHURL", defaultValue: "https://cloudflare-dns.com/dns-query", suffix: "", min: 0, max: 0)),
        ], tab: .client),

        Section(header: "Client Settings", rows: [
            Row(title: "Torrent Download Location",
                description: "Path to the folder used to store torrents. By default this is the app's cache folder, which might lose data when the OS tries to reclaim storage.",
                kind: .value("Default")),
            Row(title: "Torrent Backend",
                description: "Switches between the native libtorrent backend and Hayase's WebTorrent backend.",
                kind: .selectable(userDefaultsKey: TorrentBackendKind.userDefaultsKey, options: Self.torrentBackends, defaultKey: TorrentBackendKind.defaultKind.rawValue)),
            Row(title: "Persist Files",
                description: "Keeps torrent files instead of deleting them after a new torrent is played. This doesn't seed the files, only keeps them on your drive. This will quickly fill up your storage.",
                kind: .toggle(userDefaultsKey: Settings.Keys.persistFiles, defaultValue: Settings.Defaults.persistFiles)),
            Row(title: "Streamed Download",
                description: "Only downloads the data that's directly needed for playback, down to the minute, instead of downloading an entire batch of episodes. Will not buffer ahead more than a few seconds, and will stop downloading once the few second buffer is filled. Saves bandwidth and reduces strain on the peer swarm.",
                kind: .toggle(userDefaultsKey: Settings.Keys.streamedDownload, defaultValue: Settings.Defaults.streamedDownload)),
            Row(title: "Transfer Speed Limit",
                description: "Download/Upload speed limit for torrents, higher values increase CPU usage, and values higher than your storage write speeds will quickly fill up RAM.",
                kind: .editableNumber(userDefaultsKey: "pref_torrentSpeed", defaultValue: "40", suffix: "Mb/s", min: 1, max: 999)),
            Row(title: "Max Number of Connections",
                description: "Number of peers per torrent. Higher values will increase download speeds but might quickly fill up available ports if your ISP limits the maximum allowed number of open connections.",
                kind: .editableNumber(userDefaultsKey: "pref_maxConns", defaultValue: "50", suffix: "", min: 1, max: 512)),
            Row(title: "Forwarded Torrent Port",
                description: "Forwarded port used for incoming torrent connections. 0 automatically finds an open unused port. Change this to a specific port if you forwarded manually, or if you use a VPN.",
                kind: .editableNumber(userDefaultsKey: "pref_torrentPort", defaultValue: "0", suffix: "", min: 0, max: 65536)),
            Row(title: "DHT Port",
                description: "Port used for DHT connections. 0 is automatic.",
                kind: .editableNumber(userDefaultsKey: "pref_dhtPort", defaultValue: "0", suffix: "", min: 0, max: 65536)),
            Row(title: "Disable DHT",
                description: "Disables Distributed Hash Tables for use in private trackers to improve privacy. Might greatly reduce the amount of discovered peers.",
                kind: .toggle(userDefaultsKey: "pref_disableDHT", defaultValue: false)),
            Row(title: "Disable PeX",
                description: "Disables Peer Exchange for use in private trackers to improve privacy. Might greatly reduce the amount of discovered peers.",
                kind: .toggle(userDefaultsKey: "pref_disablePeX", defaultValue: false)),
        ], tab: .client),

        // ── Interface tab (Hayase /app/settings/interface/) ──

        Section(header: "Display Preferences", rows: [
            Row(title: "Title Language",
                description: "What language should anime titles be displayed in.",
                kind: .selectable(userDefaultsKey: Settings.Keys.titleType, options: Self.titleTypes, defaultKey: Settings.Defaults.titleType)),
        ], tab: .interface_),

        Section(header: "Visibility Settings", rows: [
            Row(title: "Show Hentai",
                description: "Shows hentai content throughout the app. If disabled all hentai content will be hidden and not shown in search results, but shown if present in your list.\n\nThis is also an AniList account setting, so make sure it is enabled in account settings as well to avoid inconsistencies.",
                kind: .toggle(userDefaultsKey: Settings.Keys.showHentai, defaultValue: Settings.Defaults.showHentai)),
            Row(title: "Hide Spoilers",
                description: "Hides potential spoilers such as titles, descriptions, episode images and ratings throughout the app.",
                kind: .toggle(userDefaultsKey: Settings.Keys.hideSpoilers, defaultValue: Settings.Defaults.hideSpoilers)),
        ], tab: .interface_),

        // ── Extensions tab (Hayase /app/settings/extensions/) ──

        Section(header: "Lookup Settings", rows: [
            Row(title: "Torrent Quality",
                description: "What quality to use when trying to find torrents. This doesn't exclude other qualities from being found. Non-1080p resolutions might not be available for all shows, or find way less results.",
                kind: .selectable(userDefaultsKey: Settings.Keys.searchQuality, options: Self.videoResolutions, defaultKey: Settings.Defaults.searchQuality)),
            Row(title: "Auto-Select Torrents",
                description: "Automatically selects torrents based on quality and amount of seeders. Disable this to have more precise control over played torrents.",
                kind: .toggle(userDefaultsKey: Settings.Keys.searchAutoSelect, defaultValue: Settings.Defaults.searchAutoSelect)),
            Row(title: "Lookup Preference",
                description: "What to prioritize when looking for and sorting results. Quality will focus on the best quality available, Size will focus on the smallest file size, and Availability will pick results with the most peers.",
                kind: .selectable(userDefaultsKey: Settings.Keys.lookupPreference, options: Self.lookupPreferences, defaultKey: Settings.Defaults.lookupPreference)),
        ], tab: .extensions),

        Section(header: "Extension Settings", rows: [
            Row(title: "Manage Extensions",
                description: "Install and configure Hayase-compatible torrent/NZB extensions.",
                kind: .navigate),
        ], tab: .extensions),

        // ── Accounts tab (Hayase /app/settings/accounts/) ──

        Section(header: "Account Settings", rows: [
            Row(title: "AniList",
                description: "Connect your AniList account for anime tracking, list sync, and metadata.",
                kind: .account(.anilist)),
            Row(title: "Kitsu",
                description: "Connect your Kitsu account for anime tracking and list sync.",
                kind: .account(.kitsu)),
            Row(title: "MyAnimeList",
                description: "Connect your MyAnimeList account for anime tracking and list sync.",
                kind: .account(.mal)),
            Row(title: "Local",
                description: "Local-only tracking. Works offline.",
                kind: .account(.local)),
        ], tab: .accounts),

        // ── App tab (Hayase /app/settings/app/) ──

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
        ], tab: .app),

        Section(header: "Debug Settings", rows: [
            Row(title: "Copy App and Device Info",
                description: "Copy app and device debug info and capabilities, such as version information and settings to clipboard.",
                kind: .action),
        ], tab: .app),


    ]

    // MARK: - viewDidLoad

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Settings"
        view.backgroundColor = bgColor
        navigationController?.navigationBar.prefersLargeTitles = true
        navigationItem.largeTitleDisplayMode = .always

        tableView = UITableView(frame: .zero, style: .plain)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = bgColor
        tableView.separatorStyle = .none
        // Default (true) delays delivering touches to content views by
        // ~150ms while UIScrollView decides if this is a scroll — a common,
        // well-known contributor to buttons inside a scrolling container
        // feeling unresponsive or requiring an unnaturally precise tap.
        tableView.delaysContentTouches = false
        tableView.delegate   = self
        tableView.dataSource = self
        tableView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: 24, right: 0)
        tableView.register(HayaseSettingToggleCell.self,
                           forCellReuseIdentifier: HayaseSettingToggleCell.reuseID)
        tableView.register(HayaseSettingValueCell.self,
                           forCellReuseIdentifier: HayaseSettingValueCell.reuseID)
        tableView.register(HayaseAccountCardCell.self,
                           forCellReuseIdentifier: HayaseAccountCardCell.reuseID)
        tableView.tableHeaderView = buildHeaderView()
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateResponsiveSettingsNavigation()
        // Recalculate table header height after layout, and keep its width pinned to the
        // actual table view width (important on iPad where the table may be narrower than the
        // screen, e.g. in split-view multitasking).
        guard !isUpdatingHeader else { return }
        guard let header = tableView.tableHeaderView else { return }
        let tableWidth = tableView.bounds.width
        guard tableWidth > 0 else { return }
        headerWidthConstraint?.constant = tableWidth
        let target = CGSize(width: tableWidth, height: UIView.layoutFittingCompressedSize.height)
        let size = header.systemLayoutSizeFitting(target,
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel)
        // Was an exact CGFloat equality check. systemLayoutSizeFitting over
        // nested stack views can return a fractionally different height
        // across otherwise-identical calls (Auto Layout constraint-solver
        // rounding), and reassigning tableHeaderView itself triggers another
        // layout pass — so an exact check could reassign the header
        // repeatedly across consecutive passes. isUpdatingHeader only
        // guards a *synchronous* re-entrant call, not a follow-up pass on
        // the next run-loop cycle, so this could keep re-triggering.
        // Repeated reassignment breaks touch-tracking continuity for any
        // button inside the header, since UIKit ties touchesBegan/Ended to
        // the specific view instance mid-gesture. A 0.5pt tolerance is far
        // below anything visually meaningful here.
        if abs(header.frame.size.height - size.height) > 0.5 {
            isUpdatingHeader = true
            header.frame.size.height = size.height
            tableView.tableHeaderView = header
            isUpdatingHeader = false
        }
    }

    // MARK: - Header view

    /// Builds the native header that contains the settings navigation and version label.
    private func buildHeaderView() -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false

        // Subtitle: "Manage your app settings, preferences and accounts."
        let subtitle = UILabel()
        subtitle.text = "Manage your app settings, preferences and accounts."
        subtitle.font = .nunito(ofSize: 14)
        subtitle.textColor = mutedFg
        subtitle.numberOfLines = 0

        // Separator: Hayase <Separator class='my-3 md:my-6'>
        let separator = UIView()
        separator.backgroundColor = separatorColor
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.heightAnchor.constraint(equalToConstant: 1).isActive = true

        // SettingsNav.svelte navigation.
        let tabGrid = buildTabGrid()

        // Version info: matches Hayase sidebar footer
        let versionLabel = UILabel()
        versionLabel.text = "Hayase v\(appVersion())"
        versionLabel.font = .nunito(ofSize: 12, weight: .light)
        versionLabel.textColor = mutedFg

        // Stack: subtitle → separator → tabGrid → version
        let stack = UIStackView(arrangedSubviews: [subtitle, separator, tabGrid, versionLabel])
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 4),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8),
        ])

        // Explicit width constraint so Auto Layout knows how wide to make the container.
        // viewDidLayoutSubviews keeps this in sync with the actual table view width, which
        // ensures the header spans the full width even on iPad (with or without split view).
        let widthConstraint = container.widthAnchor.constraint(equalToConstant: UIScreen.main.bounds.width)
        widthConstraint.isActive = true
        headerWidthConstraint = widthConstraint

        // Need a non-zero initial frame for the header sizing to work
        container.frame = CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: 200)
        return container
    }

    /// Builds SettingsNav.svelte's responsive navigation stack.
    private func buildTabGrid() -> UIView {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 4  // gap-y-1 = 4px
        stack.alignment = .fill
        stack.distribution = .fill
        headerTabStack = stack

        tabButtons.removeAll()
        tabButtonHeightConstraints.removeAll()

        for tab in SettingsTab.allCases {
            let button = makeTabButton(for: tab)
            stack.addArrangedSubview(button)
            tabButtons.append(button)
        }

        return stack
    }

    private func updateResponsiveSettingsNavigation() {
        guard isViewLoaded, let stack = headerTabStack else { return }
        let width = view.bounds.width
        let medium = width >= 768  // Tailwind md = 48rem = 768px
        let wide = width >= 1024   // Tailwind lg = 64rem = 1024px

        // SettingsNav.svelte: flex-col md:flex-row lg:flex-col. Compact child routes hide the aside.
        stack.isHidden = !medium && settingsRoute != .root
        stack.axis = (medium && !wide) ? .horizontal : .vertical
        stack.spacing = (medium && !wide) ? 8 : 4  // gap-x-2 / gap-y-1
        stack.distribution = (medium && !wide) ? .fillProportionally : .fill

        for (index, button) in tabButtons.enumerated() {
            tabButtonHeightConstraints[safe: index]?.constant = medium ? 36 : 40  // default h-9 / lg h-10
            button.contentEdgeInsets = medium
                ? UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)   // default px-4 py-2
                : UIEdgeInsets(top: 10, left: 32, bottom: 10, right: 32) // lg px-8, h-10
            button.backgroundColor = medium ? .clear : UIColor.HayaseTheme.muted  // bg-muted md:bg-transparent
        }

    }

    /// Creates a single tab button matching Hayase SettingsNav.svelte ghost button style.
    private func makeTabButton(for tab: SettingsTab) -> HayaseNavTabButton {
        let btn = HayaseNavTabButton()
        btn.setTitle(tab.title, for: .normal)
        btn.contentHorizontalAlignment = .leading
        btn.titleLabel?.font = .nunito(ofSize: 14, weight: .semibold)
        btn.layer.cornerRadius = 6   // rounded-md
        btn.contentEdgeInsets = UIEdgeInsets(top: 10, left: 32, bottom: 10, right: 32)  // size=lg: h-10 px-8
        let height = btn.heightAnchor.constraint(equalToConstant: 40)  // size=lg: h-10 = 40px
        height.isActive = true
        tabButtonHeightConstraints.append(height)
        btn.tag = tab.rawValue
        btn.addTarget(self, action: #selector(tabTapped(_:)), for: .touchUpInside)
        btn.backgroundColor = UIColor.HayaseTheme.muted  // bg-muted md:bg-transparent
        HayaseNavTabButton.select(tag: selectedTab.rawValue, in: [btn], animated: false)
        return btn
    }

    func openAccountsTab() {
        applyRoute(.accounts)
    }

    func applyRoute(_ route: Route.SettingsRoute) {
        settingsRoute = route
        let targetTab = settingsTab(for: route)

        guard isViewLoaded else {
            selectedTab = targetTab
            return
        }

        if route == .root {
            selectedTab = targetTab
            visibleSections = []
            HayaseNavTabButton.select(tag: -1, in: tabButtons, animated: true)
            UIView.performWithoutAnimation {
                tableView.reloadData()
            }
            updateResponsiveSettingsNavigation()
            return
        }

        if targetTab == selectedTab {
            refreshVisibleSections()
            UIView.performWithoutAnimation {
                tableView.reloadData()
            }
        } else {
            setSelectedTab(targetTab)
        }
        updateResponsiveSettingsNavigation()
    }

    private func settingsRoute(for tab: SettingsTab) -> Route.SettingsRoute {
        switch tab {
        case .player: return .player
        case .client: return .client
        case .interface_: return .interface
        case .extensions: return .extensions
        case .accounts: return .accounts
        case .app: return .app
        case .changelog: return .changelog
        }
    }

    private func settingsTab(for route: Route.SettingsRoute) -> SettingsTab {
        switch route {
        case .root: return .player
        case .player: return .player
        case .client: return .client
        case .interface: return .interface_
        case .extensions: return .extensions
        case .accounts: return .accounts
        case .app: return .app
        case .changelog: return .changelog
        }
    }

    @objc private func tabTapped(_ sender: UIButton) {
        guard let tab = SettingsTab(rawValue: sender.tag), tab != selectedTab else { return }
        Router.shared.navigate(.settings(settingsRoute(for: tab)), hostTabIndex: hayaseTabIndex, noScroll: true)
    }

    private func setSelectedTab(_ tab: SettingsTab) {
        guard tab != selectedTab else { return }
        // Update model state + tab-button appearance + reload.
        //    ALL of this must happen with ZERO animation/transaction context.
        //    Even UIButton.backgroundColor changes create an implicit
        //    CATransaction; if reloadData() fires within that transaction,
        //    UIKit treats it as an incremental (animated) update and applies
        //    row-count consistency checks — crashing with "invalid number of
        //    rows in section N" whenever the section/row structure changes.
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        selectedTab = tab

        HayaseNavTabButton.select(tag: tab.rawValue, in: tabButtons, animated: true)

        // Refresh the cached section array and reload.
        refreshVisibleSections()
        UIView.performWithoutAnimation {
            tableView.reloadData()
        }

        CATransaction.commit()
    }

    // MARK: - Helpers

    private func appVersion() -> String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(v) (\(b))"
    }

    /// Keys whose changes must be forwarded to the active torrent backend.
    /// Mirrors Hayase's `torrentSettings` derived store that triggers `native.updateSettings`.
    private static let torrentSettingKeys: Set<String> = [
        TorrentBackendKind.userDefaultsKey,
        "pref_disableDHT", "pref_disablePeX",
        "pref_torrentPort", "pref_dhtPort",
        "pref_torrentSpeed", "pref_maxConns",
        Settings.Keys.streamedDownload, Settings.Keys.persistFiles,
    ]

    /// If `key` is a torrent-session setting, re-apply settings to the live session.
    private func applyTorrentSettingsIfNeeded(forKey key: String) {
        if Self.torrentSettingKeys.contains(key) {
            if key == TorrentBackendKind.userDefaultsKey {
                TorrentBackendManager.shared.backendSelectionDidChange()
            } else {
                TorrentBackendManager.shared.applyCurrentSettings()
            }
        }
    }

    // MARK: - Selection picker (used for selectable rows)

    private func showSelectionPicker(title: String, key: String, options: [(key: String, label: String)], defaultKey: String, indexPath: IndexPath) {
        let currentKey = UserDefaults.standard.string(forKey: key) ?? defaultKey

        let alert = UIAlertController(title: title, message: nil, preferredStyle: .actionSheet)

        for option in options {
            let action = UIAlertAction(title: option.label, style: .default) { [weak self] _ in
                Settings.write(option.key, forKey: key)
                self?.tableView.reloadData()
                self?.applyTorrentSettingsIfNeeded(forKey: key)
            }
            if option.key == currentKey {
                action.setValue(true, forKey: "checked")
            }
            alert.addAction(action)
        }

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))

        // iPad popover anchor
        if let popover = alert.popoverPresentationController {
            if let cell = tableView.cellForRow(at: indexPath) {
                popover.sourceView = cell
                popover.sourceRect = cell.bounds
            } else {
                popover.sourceView = tableView
                popover.sourceRect = tableView.rectForRow(at: indexPath)
            }
        }

        present(alert, animated: true)
    }

    // MARK: - Editable number/text alert

    private func showEditableAlert(title: String, key: String, defaultValue: String, suffix: String, min: Int, max: Int, indexPath: IndexPath) {
        let currentValue = UserDefaults.standard.string(forKey: key) ?? defaultValue

        let alert = UIAlertController(title: title, message: suffix.isEmpty ? nil : "Enter a value", preferredStyle: .alert)
        alert.addTextField { textField in
            textField.text = currentValue
            textField.clearButtonMode = .whileEditing
            if min > 0 || max > 0 {
                textField.keyboardType = .numberPad
            }
            if !suffix.isEmpty {
                textField.placeholder = suffix
            }
        }
        alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak self] _ in
            guard let text = alert.textFields?.first?.text, !text.isEmpty else { return }
            // Validate numeric range if applicable
            if min > 0 || max > 0, let num = Int(text) {
                let clamped = Swift.min(Swift.max(num, min), max)
                Settings.write(String(clamped), forKey: key)
            } else {
                Settings.write(text, forKey: key)
            }
            self?.tableView.reloadData()
            self?.applyTorrentSettingsIfNeeded(forKey: key)
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }

    // MARK: - Action handling

    private func handleAction(row: Row) {
        switch row.title {
        case "Reset Everything To Default":
            let alert = UIAlertController(title: "Reset Everything?",
                                          message: "This will reset ALL settings and data to their default values. This cannot be undone.",
                                          preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Reset", style: .destructive) { _ in
                guard let domain = Bundle.main.bundleIdentifier else { return }
                UserDefaults.standard.removePersistentDomain(forName: domain)
                UserDefaults.standard.synchronize()
            })
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            present(alert, animated: true)
        case "Copy App and Device Info":
            var info = "Hayase v\(appVersion())\n"
            info += "iOS \(UIDevice.current.systemVersion)\n"
            info += "\(UIDevice.current.model)\n"
            UIPasteboard.general.string = info
        default:
            break
        }
    }
}

// MARK: - UITableViewDataSource

extension SettingsViewController: UITableViewDataSource {

    func numberOfSections(in tableView: UITableView) -> Int { visibleSections.count }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard section >= 0, section < visibleSections.count else { return 0 }
        return visibleSections[section].rows.count
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard section >= 0, section < visibleSections.count else { return nil }
        // Hayase: <div class='font-weight-bold text-xl font-bold'>Section Name</div>
        let container = UIView()
        container.backgroundColor = .clear
        let label = UILabel()
        label.text = visibleSections[section].header
        label.font = .nunito(ofSize: 20, weight: .bold)
        label.textColor = .white
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 20),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -6),
        ])
        return container
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        UITableView.automaticDimension
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard indexPath.section >= 0, indexPath.section < visibleSections.count,
              indexPath.row >= 0, indexPath.row < visibleSections[indexPath.section].rows.count else {
            return UITableViewCell()
        }
        let row = visibleSections[indexPath.section].rows[indexPath.row]
        switch row.kind {
        case .toggle(let key, let def):
            guard let cell = tableView.dequeueReusableCell(
                withIdentifier: HayaseSettingToggleCell.reuseID, for: indexPath) as? HayaseSettingToggleCell else { return UITableViewCell() }
            cell.configure(title: row.title, description: row.description,
                           key: key, defaultValue: def)
            cell.onToggled = { [weak self] toggledKey in
                self?.applyTorrentSettingsIfNeeded(forKey: toggledKey)
            }
            cell.backgroundColor = bgColor
            return cell
        case .value(let val):
            guard let cell = tableView.dequeueReusableCell(
                withIdentifier: HayaseSettingValueCell.reuseID, for: indexPath) as? HayaseSettingValueCell else { return UITableViewCell() }
            cell.configure(title: row.title, description: row.description, value: val, isLink: false)
            cell.backgroundColor = bgColor
            return cell
        case .selectable(let key, let options, let defaultKey):
            guard let cell = tableView.dequeueReusableCell(
                withIdentifier: HayaseSettingValueCell.reuseID, for: indexPath) as? HayaseSettingValueCell else { return UITableViewCell() }
            let storedKey = UserDefaults.standard.string(forKey: key) ?? defaultKey
            let displayValue = options.first(where: { $0.key == storedKey })?.label ?? storedKey
            cell.configure(title: row.title, description: row.description, value: displayValue, isLink: false)
            cell.selectionStyle = .default
            cell.backgroundColor = bgColor
            return cell
        case .editableNumber(let key, let defaultValue, let suffix, _, _):
            guard let cell = tableView.dequeueReusableCell(
                withIdentifier: HayaseSettingValueCell.reuseID, for: indexPath) as? HayaseSettingValueCell else { return UITableViewCell() }
            let stored = UserDefaults.standard.string(forKey: key) ?? defaultValue
            let display = suffix.isEmpty ? stored : "\(stored) \(suffix)"
            cell.configure(title: row.title, description: row.description, value: display, isLink: false)
            cell.selectionStyle = .default
            cell.backgroundColor = bgColor
            return cell
        case .link:
            guard let cell = tableView.dequeueReusableCell(
                withIdentifier: HayaseSettingValueCell.reuseID, for: indexPath) as? HayaseSettingValueCell else { return UITableViewCell() }
            cell.configure(title: row.title, description: row.description, value: nil, isLink: true)
            cell.backgroundColor = bgColor
            return cell
        case .navigate:
            guard let cell = tableView.dequeueReusableCell(
                withIdentifier: HayaseSettingValueCell.reuseID, for: indexPath) as? HayaseSettingValueCell else { return UITableViewCell() }
            cell.configure(title: row.title, description: row.description, value: nil, isLink: false)
            cell.accessoryType = .disclosureIndicator
            cell.backgroundColor = bgColor
            return cell
        case .action:
            guard let cell = tableView.dequeueReusableCell(
                withIdentifier: HayaseSettingValueCell.reuseID, for: indexPath) as? HayaseSettingValueCell else { return UITableViewCell() }
            cell.configure(title: row.title, description: row.description, value: nil, isLink: false)
            cell.backgroundColor = bgColor
            return cell
        case .account(let tracker):
            guard let cell = tableView.dequeueReusableCell(
                withIdentifier: HayaseAccountCardCell.reuseID, for: indexPath) as? HayaseAccountCardCell else { return UITableViewCell() }
            cell.configure(tracker: tracker, parentVC: self)
            cell.backgroundColor = bgColor
            return cell
        }
    }
}

// MARK: - UITableViewDelegate

extension SettingsViewController: UITableViewDelegate {

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard indexPath.section >= 0, indexPath.section < visibleSections.count,
              indexPath.row >= 0, indexPath.row < visibleSections[indexPath.section].rows.count else { return }
        let row = visibleSections[indexPath.section].rows[indexPath.row]
        switch row.kind {
        case .link(let urlStr):
            if let url = URL(string: urlStr) { present(SFSafariViewController(url: url), animated: true) }
        case .navigate:
            if row.title == "Manage Extensions" {
                let extVC = ExtensionsViewController()
                navigationController?.pushViewController(extVC, animated: true)
            }
        case .selectable(let key, let options, let defaultKey):
            showSelectionPicker(title: row.title, key: key, options: options, defaultKey: defaultKey, indexPath: indexPath)
        case .editableNumber(let key, let defaultValue, let suffix, let min, let max):
            showEditableAlert(title: row.title, key: key, defaultValue: defaultValue, suffix: suffix, min: min, max: max, indexPath: indexPath)
        case .action:
            handleAction(row: row)
        case .account:
            break // Account cards handle their own interactions
        default:
            break
        }
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        UITableView.automaticDimension
    }

    func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat {
        guard indexPath.section >= 0, indexPath.section < visibleSections.count,
              indexPath.row >= 0, indexPath.row < visibleSections[indexPath.section].rows.count else { return 80 }
        let row = visibleSections[indexPath.section].rows[indexPath.row]
        if case .account = row.kind { return 140 }
        return 80
    }

    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        // No-op — UIView.animate here creates implicit CATransactions that
        // cause reloadData() during tab switches to be treated as an
        // incremental update, crashing with "invalid number of rows in
        // section N" when the section/row structure changes between tabs.
    }
}

// MARK: - HayaseSettingToggleCell
// Matches Hayase SettingCard.svelte exactly:
//   <div class='flex flex-col md:flex-row md:items-center justify-between
//               bg-neutral-950 rounded-md px-6 py-4 gap-3'>
//     <Label class='space-1 block leading-[unset] grow'>
//       <div class='font-bold'>{title}</div>
//       <div class='text-muted-foreground text-xs whitespace-pre-wrap'>{description}</div>
//     </Label>
//     <Switch />
//   </div>

final class HayaseSettingToggleCell: UITableViewCell {
    static let reuseID = "HayaseSettingToggleCell"

    /// Card background — bg-neutral-950 (#0a0a0a)
    static let hayaseCardBg = UIColor(red: 0.039, green: 0.039, blue: 0.039, alpha: 1)

    private let cardView: UIView = {
        let v = UIView()
        v.backgroundColor = hayaseCardBg
        v.layer.cornerRadius = 6      // rounded-md = 6px
        v.layer.masksToBounds = true
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()
    private let titleLabel: UILabel = {
        let l = UILabel()
        l.font = .nunito(ofSize: 15, weight: .bold)    // font-bold
        l.textColor = .white
        l.numberOfLines = 1
        return l
    }()
    private let descLabel: UILabel = {
        let l = UILabel()
        l.font = .nunito(ofSize: 12)                   // text-xs = 12px
        l.textColor = UIColor(red: 0.631, green: 0.631, blue: 0.671, alpha: 1)  // text-muted-foreground
        l.numberOfLines = 0
        return l
    }()
    private let toggle: UISwitch = {
        let s = UISwitch()
        s.onTintColor = .systemIndigo
        return s
    }()
    private var udKey = ""
    /// Called after the toggle value is saved to UserDefaults.
    var onToggled: ((String) -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setup()
    }
    required init?(coder: NSCoder) { super.init(coder: coder); setup() }

    private func setup() {
        selectionStyle = .none
        backgroundColor = .clear
        contentView.backgroundColor = .clear

        contentView.addSubview(cardView)

        let textStack = UIStackView(arrangedSubviews: [titleLabel, descLabel])
        textStack.axis = .vertical
        textStack.spacing = 4
        textStack.translatesAutoresizingMaskIntoConstraints = false

        toggle.translatesAutoresizingMaskIntoConstraints = false
        toggle.setContentHuggingPriority(.required, for: .horizontal)
        toggle.setContentCompressionResistancePriority(.required, for: .horizontal)
        toggle.addTarget(self, action: #selector(toggled), for: .valueChanged)

        cardView.addSubview(textStack)
        cardView.addSubview(toggle)

        // Card margins: 16px horizontal, 6px vertical (space-y-3 = 12px total)
        NSLayoutConstraint.activate([
            cardView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 6),
            cardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            cardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            cardView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6),
        ])

        // Hayase: px-6 = 24px, py-4 = 16px, gap-3 = 12px
        NSLayoutConstraint.activate([
            textStack.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 24),
            textStack.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 16),
            textStack.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -16),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: toggle.leadingAnchor, constant: -12),

            toggle.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -24),
            toggle.centerYAnchor.constraint(equalTo: cardView.centerYAnchor),
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
        Settings.write(sender.isOn, forKey: udKey)
        onToggled?(udKey)
    }
}

// MARK: - HayaseSettingValueCell
// Same SettingCard style with a value label or disclosure indicator on the right.

final class HayaseSettingValueCell: UITableViewCell {
    static let reuseID = "HayaseSettingValueCell"

    static let hayaseCardBg = UIColor(red: 0.039, green: 0.039, blue: 0.039, alpha: 1)

    private let cardView: UIView = {
        let v = UIView()
        v.backgroundColor = hayaseCardBg
        v.layer.cornerRadius = 6
        v.layer.masksToBounds = true
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()
    private let titleLabel: UILabel = {
        let l = UILabel()
        l.font = .nunito(ofSize: 15, weight: .bold)
        l.textColor = .white
        l.numberOfLines = 1
        return l
    }()
    private let descLabel: UILabel = {
        let l = UILabel()
        l.font = .nunito(ofSize: 12)
        l.textColor = UIColor(red: 0.631, green: 0.631, blue: 0.671, alpha: 1)
        l.numberOfLines = 0
        return l
    }()
    private let valueLabel: UILabel = {
        let l = UILabel()
        l.font = .nunito(ofSize: 14)
        l.textColor = UIColor(red: 0.631, green: 0.631, blue: 0.671, alpha: 1)
        l.setContentHuggingPriority(.required, for: .horizontal)
        l.setContentCompressionResistancePriority(.required, for: .horizontal)
        return l
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setup()
    }
    required init?(coder: NSCoder) { super.init(coder: coder); setup() }

    private func setup() {
        backgroundColor = .clear
        contentView.backgroundColor = .clear

        contentView.addSubview(cardView)

        let textStack = UIStackView(arrangedSubviews: [titleLabel, descLabel])
        textStack.axis = .vertical
        textStack.spacing = 4
        textStack.translatesAutoresizingMaskIntoConstraints = false

        valueLabel.translatesAutoresizingMaskIntoConstraints = false

        cardView.addSubview(textStack)
        cardView.addSubview(valueLabel)

        // Card margins: 16px horizontal, 6px vertical
        NSLayoutConstraint.activate([
            cardView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 6),
            cardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            cardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            cardView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6),
        ])

        NSLayoutConstraint.activate([
            textStack.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 24),
            textStack.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 16),
            textStack.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -16),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: valueLabel.leadingAnchor, constant: -12),

            valueLabel.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -24),
            valueLabel.centerYAnchor.constraint(equalTo: cardView.centerYAnchor),
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
}

// Legacy cell types kept as typealiases so any existing code referencing them compiles.
typealias SettingsToggleCell = HayaseSettingToggleCell
typealias SettingsDetailCell = HayaseSettingValueCell

