//
//  SettingsViewController.swift
//  Hayase
//
//  Mirrors: src/routes/app/settings/+layout.svelte, src/routes/app/settings/+page.ts,
//  src/routes/app/settings/+page.svelte, src/lib/components/SettingsNav.svelte,
//  src/lib/components/SettingCard.svelte
//
//  Native visual port of the responsive settings shell and SettingCard pages.
//  Existing iOS-backed settings behavior is preserved; newly introduced controls
//  remain visual-only until their native storage/services are wired.

import UIKit
import SafariServices

// MARK: - SettingsViewController

fileprivate enum SettingsPreviewKind {
    case subtitleStyle
    case colorTheme
}

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
        case appActions
        case slider(String)
        case button(String)
        /// UI-only preview chooser used by the web settings for subtitle styles and themes.
        case previewGrid(SettingsPreviewKind)
        /// The web changelog's initial loading presentation. Networking is intentionally deferred.
        case changelogPlaceholder
        /// Account card — full tracker account card (AniList, Kitsu, MAL, Local).
        case account(TrackerKind)
        case accountPlaceholder(String)
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

    // MARK: - Colors

    private let bgColor = UIColor.HayaseTheme.background
    private let mutedFg = UIColor.HayaseTheme.mutedForeground
    private let separatorColor = UIColor.HayaseTheme.border

    // MARK: - State

    private var selectedTab: SettingsTab = .player
    private var settingsRoute: Route.SettingsRoute = .root
    private var tabButtons: [HayaseNavTabButton] = []
    private var tabButtonHeightConstraints: [NSLayoutConstraint] = []
    private weak var headerTabStack: UIStackView?
    private var tableView: UITableView!
    private let headingStack = UIStackView()
    private let pageSeparator = UIView()
    private let bodyContainer = UIView()
    private let bodyContent = UIView()
    private var asideView: UIView!
    private var asideWidthConstraint: NSLayoutConstraint?
    private var bodyLayoutConstraints: [NSLayoutConstraint] = []
    private var horizontalPageConstraints: [NSLayoutConstraint] = []
    private var headingTopConstraint: NSLayoutConstraint?
    private var separatorTopConstraint: NSLayoutConstraint?
    private var bodyTopConstraint: NSLayoutConstraint?
    private var currentWideLayout: Bool?
    private var currentShowsInlineAside: Bool?
    private var currentMediumLayout: Bool?
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
                description: "Max resolution to render subtitles at. If your resolution is higher than this setting the subtitles will be upscaled lineary. This will GREATLY improve rendering speeds for complex typesetting for slower devices. It's best to lower this on mobile devices which often have high pixel density where their effective resolution might be ~1440p while having small screens and slow processors.",
                kind: .selectable(userDefaultsKey: Settings.Keys.subtitleRenderHeight, options: Self.subtitleResolutions, defaultKey: Settings.Defaults.subtitleRenderHeight)),
            Row(title: "Subtitle Dialogue Style Overrides",
                description: "Selectively override the default dialogue style for subtitles. This will not change the style of typesetting [Fancy 3D Signs and Songs].\n\nWarning: the heuristic used for deciding when to override the style is rather rough, and enabling this option can lead to incorrectly rendered subtitles.",
                kind: .previewGrid(.subtitleStyle)),
        ], tab: .player),

        Section(header: "Language Settings", rows: [
            Row(title: "Preferred Subtitle Language",
                description: "What subtitle language to automatically select when a video is loaded if it exists. This won't find torrents with this language automatically. If not found defaults to English.",
                kind: .selectable(userDefaultsKey: Settings.Keys.subtitleLanguage, options: Self.languageCodes, defaultKey: Settings.Defaults.subtitleLanguage)),
            Row(title: "Preferred Audio Language",
                description: "What audio language to automatically select when a video is loaded if it exists. This won't find torrents with this language automatically. If not found defaults to Japanese.",
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
                description: "Automatically marks episodes as complete when you finish watching them. Requires Account login.",
                kind: .toggle(userDefaultsKey: Settings.Keys.autocomplete, defaultValue: Settings.Defaults.autocomplete)),
            Row(title: "Deband Video",
                description: "Reduces banding [compression artifacts] on dark and compressed videos. High performance impact. Recommended for seasonal web releases, not recommended for high quality blu-ray videos.",
                kind: .toggle(userDefaultsKey: Settings.Keys.deband, defaultValue: Settings.Defaults.deband)),
            Row(title: "Seek Duration",
                description: "Seconds to skip forward or backward when using the seek buttons or keyboard shortcuts. Higher values might negatively impact buffering speeds.",
                kind: .editableNumber(userDefaultsKey: Settings.Keys.seekDuration, defaultValue: Settings.Defaults.seekDuration, suffix: "sec", min: 1, max: 50)),
            Row(title: "Auto-Skip Intro/Outro",
                description: "Attempt to automatically skip intro and outro. This WILL sometimes skip incorrect chapters, as some of the chapter data is community sourced.",
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

        Section(header: "Torrent Client Settings", rows: [
            Row(title: "Torrent Download Location",
                description: "Path to the folder used to store torrents. By default this is the OS's TEMP/TMP cache folder, which might lose data when your OS tries to reclaim storage.",
                kind: .value("Default")),
            Row(title: "Torrent Backend",
                description: "Switches between the native libtorrent backend and Hayase's WebTorrent backend.",
                kind: .selectable(userDefaultsKey: TorrentBackendKind.userDefaultsKey, options: Self.torrentBackends, defaultKey: TorrentBackendKind.defaultKind.rawValue)),
            Row(title: "Persist Files",
                description: "Keeps torrents files instead of deleting them after a new torrent is played. This doesn't seed the files, only keeps them on your drive. This will quickly fill up your storage.",
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
                description: "Forwarded port used for incoming torrent connections. 0 automatically finds an open unused port. Change this to a specific port if you forwarded manually, or if you use a VPN",
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

        Section(header: "NZB Client Settings", rows: [
            Row(title: "Provider Domain",
                description: "The domain of your NZB provider, without the protocol. For example, if your provider is accessed at https://news.example.com, just enter news.example.com here.",
                kind: .value("news.example.com")),
            Row(title: "Provider Login",
                description: "The Login/Username for your NZB provider.",
                kind: .value("admin")),
            Row(title: "Provider Password",
                description: "The Password for your NZB provider. This is stored in plaintext in the settings file, so be aware of that.",
                kind: .value("••••••••")),
            Row(title: "Connection Port",
                description: "The port used to connect to your NZB provider. 119 is the default for NNTP.",
                kind: .value("119")),
            Row(title: "Connection Pool Size",
                description: "The number of simultaneous connections to use for downloading from your NZB provider. Higher values might increase download speeds but can cause issues with some providers if set too high.\n\nThis is shared between extension, so if you have multiple NZB extensions configured they will share the same pool of connections.",
                kind: .value("5")),
        ], tab: .client),

        // ── Interface tab (Hayase /app/settings/interface/) ──

        Section(header: "Display Preferences", rows: [
            Row(title: "Title Language",
                description: "What language should anime titles be displayed in.",
                kind: .selectable(userDefaultsKey: Settings.Keys.titleType, options: Self.titleTypes, defaultKey: Settings.Defaults.titleType)),
            Row(title: "Show Hentai",
                description: "Shows hentai content throughout the app. If disabled all hentai content will be hidden and not shown in search results, but shown if present in your list.\n\nThis is also an AniList account setting, so make sure it is enabled in account settings as well to avoid inconsistencies.",
                kind: .toggle(userDefaultsKey: Settings.Keys.showHentai, defaultValue: Settings.Defaults.showHentai)),
            Row(title: "Hide Spoilers",
                description: "Hides potential spoilers such as titles, descriptions, episode images and ratings throughout the app.",
                kind: .toggle(userDefaultsKey: Settings.Keys.hideSpoilers, defaultValue: Settings.Defaults.hideSpoilers)),
        ], tab: .interface_),

        Section(header: "Appearance", rows: [
            Row(title: "Color Theme",
                description: "Select a color theme for the interface.",
                kind: .previewGrid(.colorTheme)),
            Row(title: "Navigation Buttons",
                description: "Show backwards/forwards navigation buttons for when mouse buttons aren't available.",
                kind: .toggle(userDefaultsKey: "pref_showNavigation", defaultValue: false)),
            Row(title: "UI Scale",
                description: "Change the zoom level of the interface.",
                kind: .slider("1.0")),
        ], tab: .interface_),

        // ── Extensions tab (Hayase /app/settings/extensions/) ──

        Section(header: "Lookup Settings", rows: [
            Row(title: "Torrent Quality",
                description: "What quality to use when trying to find torrents. None might rarely find less results than specific qualities. This doesn't exclude other qualities from being found like 4K or weird DVD resolutions. Non-1080p resolutions might not be available for all shows, or find way less results.",
                kind: .selectable(userDefaultsKey: Settings.Keys.searchQuality, options: Self.videoResolutions, defaultKey: Settings.Defaults.searchQuality)),
            Row(title: "Auto-Select Torrents",
                description: "Automatically selects torrents based on quality and amount of seeders. Disable this to have more precise control over played torrents.",
                kind: .toggle(userDefaultsKey: Settings.Keys.searchAutoSelect, defaultValue: Settings.Defaults.searchAutoSelect)),
            Row(title: "Lookup Preference",
                description: "What to prioritize when looking for and sorting results. Quality will focus on the best quality available which often means big file sizes, Size will focus on the smallest file size available, and Availability will pick results with the most peers regardless of size and quality.",
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
            Row(title: "Simkl",
                description: "Connect your Simkl account for anime tracking and list sync.",
                kind: .accountPlaceholder("Simkl")),
            Row(title: "Local",
                description: "Local-only tracking. Works offline.",
                kind: .account(.local)),
        ], tab: .accounts),

        // ── App tab (Hayase /app/settings/app/) ──

        Section(header: "App Settings", rows: [
            Row(title: "App Actions", description: "", kind: .appActions),
        ], tab: .app),

        Section(header: "Debug Settings", rows: [
            Row(title: "Logging Levels",
                description: "Enable logging of specific parts of the app. These logs are saved to %appdata$/Hayase/logs/main.log or ~/config/Hayase/logs/main.log.",
                kind: .value("None")),
            Row(title: "Debug page",
                description: "Go to the debug page to access additional debugging features.",
                kind: .button("Go to Debug Page")),
            Row(title: "Copy App and Device Info",
                description: "Copy app and device debug info and capabilities, such as version information and settings to clipboard.",
                kind: .action),
        ], tab: .app),

        Section(header: "", rows: [
            Row(title: "Changelog",
                description: "New updates and improvements to Hayase.",
                kind: .changelogPlaceholder),
        ], tab: .changelog),


    ]

    // MARK: - viewDidLoad

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Settings"
        view.backgroundColor = bgColor
        navigationController?.setNavigationBarHidden(true, animated: false)

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
        tableView.register(HayaseAccountPlaceholderCell.self,
                           forCellReuseIdentifier: HayaseAccountPlaceholderCell.reuseID)
        tableView.register(HayaseSettingsPreviewGridCell.self,
                           forCellReuseIdentifier: HayaseSettingsPreviewGridCell.reuseID)
        tableView.register(HayaseChangelogPlaceholderCell.self,
                           forCellReuseIdentifier: HayaseChangelogPlaceholderCell.reuseID)
        tableView.register(HayaseAppActionsCell.self,
                           forCellReuseIdentifier: HayaseAppActionsCell.reuseID)
        tableView.register(HayaseSettingSliderCell.self,
                           forCellReuseIdentifier: HayaseSettingSliderCell.reuseID)
        tableView.sectionHeaderTopPadding = 0

        setupPageLayout()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateResponsiveSettingsNavigation()
        sizeInlineAsideIfNeeded()
    }

    // MARK: - Page layout

    private func setupPageLayout() {
        let pageTitle = UILabel()
        pageTitle.text = "Settings"
        pageTitle.font = .nunito(ofSize: 24, weight: .bold)
        pageTitle.textColor = UIColor.HayaseTheme.foreground

        let subtitle = UILabel()
        subtitle.text = "Manage your app settings, preferences and accounts."
        subtitle.font = .nunito(ofSize: 16)
        subtitle.textColor = mutedFg
        subtitle.numberOfLines = 0

        headingStack.axis = .vertical
        headingStack.spacing = 2
        headingStack.addArrangedSubview(pageTitle)
        headingStack.addArrangedSubview(subtitle)
        headingStack.translatesAutoresizingMaskIntoConstraints = false

        pageSeparator.backgroundColor = separatorColor
        pageSeparator.translatesAutoresizingMaskIntoConstraints = false
        bodyContainer.translatesAutoresizingMaskIntoConstraints = false
        bodyContent.translatesAutoresizingMaskIntoConstraints = false
        asideView = buildAsideView()

        view.addSubview(headingStack)
        view.addSubview(pageSeparator)
        view.addSubview(bodyContainer)
        bodyContainer.addSubview(bodyContent)
        bodyContent.addSubview(tableView)

        let headingWidth = headingStack.widthAnchor.constraint(equalTo: view.widthAnchor, constant: -24)
        let separatorWidth = pageSeparator.widthAnchor.constraint(equalTo: view.widthAnchor, constant: -24)
        let bodyWidth = bodyContent.widthAnchor.constraint(equalTo: bodyContainer.widthAnchor, constant: -24)
        [headingWidth, separatorWidth, bodyWidth].forEach { $0.priority = .defaultHigh }
        horizontalPageConstraints = [
            headingStack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            headingStack.widthAnchor.constraint(lessThanOrEqualToConstant: 1440),
            headingStack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 12),
            headingStack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -12),
            pageSeparator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            pageSeparator.widthAnchor.constraint(lessThanOrEqualToConstant: 1440),
            pageSeparator.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 12),
            pageSeparator.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -12),
            bodyContent.centerXAnchor.constraint(equalTo: bodyContainer.centerXAnchor),
            bodyContent.widthAnchor.constraint(lessThanOrEqualToConstant: 1440),
            bodyContent.leadingAnchor.constraint(greaterThanOrEqualTo: bodyContainer.leadingAnchor, constant: 12),
            bodyContent.trailingAnchor.constraint(lessThanOrEqualTo: bodyContainer.trailingAnchor, constant: -12),
            headingWidth,
            separatorWidth,
            bodyWidth,
        ]

        let headingTop = headingStack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12)
        let separatorTop = pageSeparator.topAnchor.constraint(equalTo: headingStack.bottomAnchor, constant: 12)
        let bodyTop = bodyContainer.topAnchor.constraint(equalTo: pageSeparator.bottomAnchor, constant: 12)
        headingTopConstraint = headingTop
        separatorTopConstraint = separatorTop
        bodyTopConstraint = bodyTop
        NSLayoutConstraint.activate(horizontalPageConstraints + [
            headingTop,
            separatorTop,
            pageSeparator.heightAnchor.constraint(equalToConstant: 1),
            bodyTop,
            bodyContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bodyContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bodyContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            bodyContent.topAnchor.constraint(equalTo: bodyContainer.topAnchor),
            bodyContent.bottomAnchor.constraint(equalTo: bodyContainer.bottomAnchor),
        ])

        updatePagePadding()
        updateBodyLayout(force: true)
    }

    private func updatePagePadding() {
        let medium = view.bounds.width >= 768
        let padding: CGFloat = medium ? 40 : 12
        horizontalPageConstraints[2].constant = padding
        horizontalPageConstraints[3].constant = -padding
        horizontalPageConstraints[6].constant = padding
        horizontalPageConstraints[7].constant = -padding
        horizontalPageConstraints[10].constant = padding
        horizontalPageConstraints[11].constant = -padding
        horizontalPageConstraints[12].constant = -2 * padding
        horizontalPageConstraints[13].constant = -2 * padding
        horizontalPageConstraints[14].constant = -2 * padding

        headingTopConstraint?.constant = padding
        separatorTopConstraint?.constant = medium ? 24 : 12
        bodyTopConstraint?.constant = medium ? 24 : 12
        tableView.contentInset.bottom = medium ? 0 : 40
    }

    /// Builds the support card, SettingsNav, and build information from +layout.svelte.
    private func buildAsideView() -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        let supportCard = makeSupportCard()
        let tabGrid = buildTabGrid()
        let versionLabel = UILabel()
        versionLabel.text = "Interface v\(appVersion())\nNative \(appVersion())\niOS \(UIDevice.current.systemVersion) \(UIDevice.current.model)\nLicense Information"
        versionLabel.font = .nunito(ofSize: 12, weight: .light)
        versionLabel.textColor = mutedFg
        versionLabel.numberOfLines = 0

        let topStack = UIStackView(arrangedSubviews: [supportCard, tabGrid])
        topStack.axis = .vertical
        topStack.spacing = 0
        topStack.setCustomSpacing(16, after: supportCard)
        topStack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(topStack)
        container.addSubview(versionLabel)

        NSLayoutConstraint.activate([
            topStack.topAnchor.constraint(equalTo: container.topAnchor),
            topStack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            topStack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            versionLabel.topAnchor.constraint(greaterThanOrEqualTo: topStack.bottomAnchor, constant: 12),
            versionLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            versionLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            versionLabel.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -20),
        ])
        let widthConstraint = container.widthAnchor.constraint(equalToConstant: UIScreen.main.bounds.width)
        widthConstraint.isActive = true
        asideWidthConstraint = widthConstraint
        return container
    }

    private func makeSupportCard() -> UIView {
        let card = UIView()
        card.backgroundColor = UIColor(red: 232 / 255, green: 121 / 255, blue: 249 / 255, alpha: 1)
        card.layer.cornerRadius = 4
        card.clipsToBounds = true

        let artwork = UIImageView(image: HayaseSettingsArtwork.flowers)
        artwork.contentMode = .scaleAspectFill
        artwork.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(artwork)

        let title = UILabel()
        title.text = "Support the Project"
        title.font = .nunito(ofSize: 16, weight: .bold)
        title.textColor = UIColor.HayaseTheme.secondary

        let message = UILabel()
        message.text = "Please consider supporting the development of Hayase by donating!"
        message.font = .nunito(ofSize: 12)
        message.textColor = UIColor.HayaseTheme.secondary
        message.numberOfLines = 0

        let donate = UIButton(type: .system)
        donate.setTitle("Donate", for: .normal)
        donate.setImage(UIImage.hayaseIcon("heart"), for: .normal)
        donate.tintColor = UIColor(red: 250 / 255, green: 104 / 255, blue: 182 / 255, alpha: 1)
        donate.setTitleColor(UIColor.HayaseTheme.primaryForeground, for: .normal)
        donate.backgroundColor = UIColor.HayaseTheme.primary
        donate.titleLabel?.font = .nunito(ofSize: 14, weight: .bold)
        donate.layer.cornerRadius = 6
        donate.contentEdgeInsets = UIEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        donate.imageEdgeInsets.right = 8
        donate.heightAnchor.constraint(equalToConstant: 36).isActive = true
        donate.addTarget(self, action: #selector(donateTapped), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [title, message, donate])
        stack.axis = .vertical
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)
        NSLayoutConstraint.activate([
            artwork.topAnchor.constraint(equalTo: card.topAnchor),
            artwork.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            artwork.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            artwork.bottomAnchor.constraint(equalTo: card.bottomAnchor),
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -24),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16),
        ])
        return card
    }

    @objc private func donateTapped() {
        guard let url = URL(string: "https://github.com/sponsors/ThaUnknown/") else { return }
        UIApplication.shared.open(url)
    }

    private func updateBodyLayout(force: Bool = false) {
        guard isViewLoaded, tableView != nil, asideView != nil else { return }
        let wide = view.bounds.width >= 1024
        let showsInlineAside = !wide && (settingsRoute == .root || view.bounds.width >= 768)
        guard force || wide != currentWideLayout || showsInlineAside != currentShowsInlineAside else { return }
        currentWideLayout = wide
        currentShowsInlineAside = showsInlineAside

        NSLayoutConstraint.deactivate(bodyLayoutConstraints)
        bodyLayoutConstraints.removeAll()
        tableView.tableHeaderView = nil
        asideView.removeFromSuperview()
        tableView.removeFromSuperview()
        bodyContent.addSubview(tableView)
        tableView.translatesAutoresizingMaskIntoConstraints = false

        if wide {
            asideWidthConstraint?.constant = 240
            asideView.translatesAutoresizingMaskIntoConstraints = false
            bodyContent.addSubview(asideView)
            bodyLayoutConstraints = [
                asideView.topAnchor.constraint(equalTo: bodyContent.topAnchor),
                asideView.leadingAnchor.constraint(equalTo: bodyContent.leadingAnchor),
                asideView.bottomAnchor.constraint(equalTo: bodyContent.bottomAnchor),
                tableView.topAnchor.constraint(equalTo: bodyContent.topAnchor),
                tableView.leadingAnchor.constraint(equalTo: asideView.trailingAnchor, constant: 48),
                tableView.trailingAnchor.constraint(equalTo: bodyContent.trailingAnchor),
                tableView.bottomAnchor.constraint(equalTo: bodyContent.bottomAnchor),
            ]
        } else {
            bodyLayoutConstraints = [
                tableView.topAnchor.constraint(equalTo: bodyContent.topAnchor),
                tableView.leadingAnchor.constraint(equalTo: bodyContent.leadingAnchor),
                tableView.trailingAnchor.constraint(equalTo: bodyContent.trailingAnchor),
                tableView.bottomAnchor.constraint(equalTo: bodyContent.bottomAnchor),
            ]
            if showsInlineAside {
                asideView.translatesAutoresizingMaskIntoConstraints = false
                tableView.tableHeaderView = asideView
                sizeInlineAsideIfNeeded()
            }
        }
        NSLayoutConstraint.activate(bodyLayoutConstraints)
    }

    private func sizeInlineAsideIfNeeded() {
        guard !isUpdatingHeader,
              tableView.tableHeaderView === asideView,
              tableView.bounds.width > 0 else { return }
        let width = tableView.bounds.width
        asideWidthConstraint?.constant = width
        let target = CGSize(width: width, height: UIView.layoutFittingCompressedSize.height)
        let height = asideView.systemLayoutSizeFitting(
            target,
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height
        guard abs(asideView.frame.width - width) > 0.5 || abs(asideView.frame.height - height) > 0.5 else { return }
        isUpdatingHeader = true
        asideView.frame = CGRect(x: 0, y: 0, width: width, height: height)
        tableView.tableHeaderView = asideView
        isUpdatingHeader = false
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

        let crossedMediumBreakpoint = currentMediumLayout != nil && currentMediumLayout != medium
        currentMediumLayout = medium

        updatePagePadding()
        updateBodyLayout()

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

        if crossedMediumBreakpoint {
            UIView.performWithoutAnimation {
                tableView.reloadData()
            }
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
            HayaseNavTabButton.select(tag: targetTab.rawValue, in: tabButtons, animated: true)
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

    private func handleAction(title: String) {
        switch title {
        case "Reset Everything To Default", "Reset EVERYTHING To Default":
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

    private func controlWidth(for row: Row) -> CGFloat {
        switch row.title {
        case "Title Language":
            return 240
        case "Preferred Subtitle Language", "Preferred Audio Language":
            return 144
        case "DNS Over HTTPS URL", "Provider Domain", "Provider Login", "Provider Password":
            return 320
        default:
            return 128
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
        guard !visibleSections[section].header.isEmpty else { return nil }
        // Hayase: <div class='font-weight-bold text-xl font-bold'>Section Name</div>
        let container = UIView()
        container.backgroundColor = .clear
        let label = UILabel()
        label.text = visibleSections[section].header
        label.font = .nunito(ofSize: 20, weight: .bold)
        label.textColor = UIColor.HayaseTheme.foreground
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 6),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -6),
        ])
        return container
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        guard section >= 0, section < visibleSections.count,
              !visibleSections[section].header.isEmpty else { return 0.01 }
        return UITableView.automaticDimension
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard indexPath.section >= 0, indexPath.section < visibleSections.count,
              indexPath.row >= 0, indexPath.row < visibleSections[indexPath.section].rows.count else {
            return UITableViewCell()
        }
        let row = visibleSections[indexPath.section].rows[indexPath.row]
        let horizontal = view.bounds.width >= 768
        switch row.kind {
        case .toggle(let key, let def):
            guard let cell = tableView.dequeueReusableCell(
                withIdentifier: HayaseSettingToggleCell.reuseID, for: indexPath) as? HayaseSettingToggleCell else { return UITableViewCell() }
            cell.configure(title: row.title, description: row.description,
                           key: key, defaultValue: def, horizontal: horizontal)
            cell.onToggled = { [weak self] toggledKey in
                self?.applyTorrentSettingsIfNeeded(forKey: toggledKey)
            }
            cell.backgroundColor = bgColor
            return cell
        case .value(let val):
            guard let cell = tableView.dequeueReusableCell(
                withIdentifier: HayaseSettingValueCell.reuseID, for: indexPath) as? HayaseSettingValueCell else { return UITableViewCell() }
            cell.configure(title: row.title, description: row.description, value: val,
                           isLink: false, horizontal: horizontal, controlWidth: controlWidth(for: row))
            cell.backgroundColor = bgColor
            return cell
        case .selectable(let key, let options, let defaultKey):
            guard let cell = tableView.dequeueReusableCell(
                withIdentifier: HayaseSettingValueCell.reuseID, for: indexPath) as? HayaseSettingValueCell else { return UITableViewCell() }
            let storedKey = UserDefaults.standard.string(forKey: key) ?? defaultKey
            let displayValue = options.first(where: { $0.key == storedKey })?.label ?? storedKey
            cell.configure(title: row.title, description: row.description, value: displayValue,
                           isLink: false, horizontal: horizontal, controlWidth: controlWidth(for: row))
            cell.selectionStyle = .default
            cell.backgroundColor = bgColor
            return cell
        case .editableNumber(let key, let defaultValue, let suffix, _, _):
            guard let cell = tableView.dequeueReusableCell(
                withIdentifier: HayaseSettingValueCell.reuseID, for: indexPath) as? HayaseSettingValueCell else { return UITableViewCell() }
            let stored = UserDefaults.standard.string(forKey: key) ?? defaultValue
            let display = suffix.isEmpty ? stored : "\(stored) \(suffix)"
            cell.configure(title: row.title, description: row.description, value: display,
                           isLink: false, horizontal: horizontal, controlWidth: controlWidth(for: row))
            cell.selectionStyle = .default
            cell.backgroundColor = bgColor
            return cell
        case .link:
            guard let cell = tableView.dequeueReusableCell(
                withIdentifier: HayaseSettingValueCell.reuseID, for: indexPath) as? HayaseSettingValueCell else { return UITableViewCell() }
            cell.configure(title: row.title, description: row.description, value: nil,
                           isLink: true, horizontal: horizontal)
            cell.backgroundColor = bgColor
            return cell
        case .navigate:
            guard let cell = tableView.dequeueReusableCell(
                withIdentifier: HayaseSettingValueCell.reuseID, for: indexPath) as? HayaseSettingValueCell else { return UITableViewCell() }
            cell.configure(title: row.title, description: row.description, value: "Manage Extensions",
                           isLink: false, horizontal: horizontal, filledControl: true)
            cell.backgroundColor = bgColor
            return cell
        case .action:
            guard let cell = tableView.dequeueReusableCell(
                withIdentifier: HayaseSettingValueCell.reuseID, for: indexPath) as? HayaseSettingValueCell else { return UITableViewCell() }
            cell.configure(title: row.title, description: row.description, value: nil,
                           isLink: false, horizontal: horizontal)
            cell.backgroundColor = bgColor
            return cell
        case .appActions:
            guard let cell = tableView.dequeueReusableCell(
                withIdentifier: HayaseAppActionsCell.reuseID,
                for: indexPath) as? HayaseAppActionsCell else { return UITableViewCell() }
            cell.configure(horizontal: horizontal)
            cell.onAction = { [weak self] title in
                self?.handleAction(title: title)
            }
            cell.backgroundColor = bgColor
            return cell
        case .slider(let displayValue):
            guard let cell = tableView.dequeueReusableCell(
                withIdentifier: HayaseSettingSliderCell.reuseID,
                for: indexPath) as? HayaseSettingSliderCell else { return UITableViewCell() }
            cell.configure(title: row.title, description: row.description,
                           displayValue: displayValue, horizontal: horizontal)
            cell.backgroundColor = bgColor
            return cell
        case .button(let label):
            guard let cell = tableView.dequeueReusableCell(
                withIdentifier: HayaseSettingValueCell.reuseID, for: indexPath) as? HayaseSettingValueCell else { return UITableViewCell() }
            cell.configure(title: row.title, description: row.description, value: label,
                           isLink: false, horizontal: horizontal, filledControl: true)
            cell.backgroundColor = bgColor
            return cell
        case .previewGrid(let kind):
            guard let cell = tableView.dequeueReusableCell(
                withIdentifier: HayaseSettingsPreviewGridCell.reuseID,
                for: indexPath) as? HayaseSettingsPreviewGridCell else { return UITableViewCell() }
            cell.configure(title: row.title, description: row.description,
                           kind: kind, twoColumns: view.bounds.width >= 640)
            cell.backgroundColor = bgColor
            return cell
        case .changelogPlaceholder:
            guard let cell = tableView.dequeueReusableCell(
                withIdentifier: HayaseChangelogPlaceholderCell.reuseID,
                for: indexPath) as? HayaseChangelogPlaceholderCell else { return UITableViewCell() }
            cell.configure(title: row.title, description: row.description,
                           wide: view.bounds.width >= 640)
            cell.backgroundColor = bgColor
            return cell
        case .account(let tracker):
            guard let cell = tableView.dequeueReusableCell(
                withIdentifier: HayaseAccountCardCell.reuseID, for: indexPath) as? HayaseAccountCardCell else { return UITableViewCell() }
            cell.configure(tracker: tracker, parentVC: self)
            cell.backgroundColor = bgColor
            return cell
        case .accountPlaceholder(let service):
            guard let cell = tableView.dequeueReusableCell(
                withIdentifier: HayaseAccountPlaceholderCell.reuseID,
                for: indexPath) as? HayaseAccountPlaceholderCell else { return UITableViewCell() }
            cell.configure(service: service)
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
            handleAction(title: row.title)
        case .account(_), .accountPlaceholder(_), .previewGrid(_), .changelogPlaceholder, .appActions, .slider(_), .button(_):
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
        if case .accountPlaceholder = row.kind { return 140 }
        if case .previewGrid = row.kind { return 420 }
        if case .changelogPlaceholder = row.kind { return 620 }
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
//
// Mirrors SettingCard.svelte: muted card, 24/16 padding, 12pt gap, and
// vertical compact / horizontal md layout.

final class HayaseSettingToggleCell: UITableViewCell {
    static let reuseID = "HayaseSettingToggleCell"

    private let cardView = UIView()
    private let titleLabel = UILabel()
    private let descriptionLabel = UILabel()
    private let textStack = UIStackView()
    private let contentStack = UIStackView()
    private let toggle = UISwitch()
    private var userDefaultsKey = ""
    var onToggled: ((String) -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        selectionStyle = .none
        backgroundColor = .clear
        contentView.backgroundColor = .clear

        cardView.backgroundColor = UIColor.HayaseTheme.muted
        cardView.layer.cornerRadius = 6
        cardView.layer.masksToBounds = true
        cardView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(cardView)

        titleLabel.font = .nunito(ofSize: 16, weight: .bold)
        titleLabel.textColor = UIColor.HayaseTheme.foreground
        titleLabel.numberOfLines = 0

        descriptionLabel.font = .nunito(ofSize: 12)
        descriptionLabel.textColor = UIColor.HayaseTheme.mutedForeground
        descriptionLabel.numberOfLines = 0

        textStack.axis = .vertical
        textStack.spacing = 4
        textStack.addArrangedSubview(titleLabel)
        textStack.addArrangedSubview(descriptionLabel)

        toggle.onTintColor = UIColor.HayaseTheme.primary
        toggle.thumbTintColor = UIColor.HayaseTheme.primaryForeground
        toggle.transform = CGAffineTransform(scaleX: 0.82, y: 0.82)
        toggle.addTarget(self, action: #selector(toggled), for: .valueChanged)
        toggle.setContentHuggingPriority(.required, for: .horizontal)
        toggle.setContentCompressionResistancePriority(.required, for: .horizontal)

        contentStack.axis = .horizontal
        contentStack.alignment = .center
        contentStack.spacing = 12
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.addArrangedSubview(textStack)
        contentStack.addArrangedSubview(toggle)
        cardView.addSubview(contentStack)

        NSLayoutConstraint.activate([
            cardView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 6),
            cardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            cardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            cardView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6),
            contentStack.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 16),
            contentStack.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 24),
            contentStack.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -24),
            contentStack.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -16),
        ])
    }

    func configure(title: String,
                   description: String,
                   key: String,
                   defaultValue: Bool,
                   horizontal: Bool) {
        titleLabel.text = title
        descriptionLabel.text = description
        userDefaultsKey = key
        let stored = UserDefaults.standard.object(forKey: key) as? Bool ?? defaultValue
        toggle.setOn(stored, animated: false)
        applyLayout(horizontal: horizontal)
    }

    private func applyLayout(horizontal: Bool) {
        contentStack.axis = horizontal ? .horizontal : .vertical
        contentStack.alignment = horizontal ? .center : .leading
    }

    @objc private func toggled(_ sender: UISwitch) {
        Settings.write(sender.isOn, forKey: userDefaultsKey)
        onToggled?(userDefaultsKey)
    }
}

// MARK: - HayaseSettingValueCell

final class HayaseSettingValueCell: UITableViewCell {
    static let reuseID = "HayaseSettingValueCell"

    private let cardView = UIView()
    private let titleLabel = UILabel()
    private let descriptionLabel = UILabel()
    private let textStack = UIStackView()
    private let contentStack = UIStackView()
    private let controlView = UIView()
    private let valueLabel = UILabel()
    private var controlWidthConstraint: NSLayoutConstraint?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        backgroundColor = .clear
        contentView.backgroundColor = .clear

        cardView.backgroundColor = UIColor.HayaseTheme.muted
        cardView.layer.cornerRadius = 6
        cardView.layer.masksToBounds = true
        cardView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(cardView)

        titleLabel.font = .nunito(ofSize: 16, weight: .bold)
        titleLabel.textColor = UIColor.HayaseTheme.foreground
        titleLabel.numberOfLines = 0

        descriptionLabel.font = .nunito(ofSize: 12)
        descriptionLabel.textColor = UIColor.HayaseTheme.mutedForeground
        descriptionLabel.numberOfLines = 0

        textStack.axis = .vertical
        textStack.spacing = 4
        textStack.addArrangedSubview(titleLabel)
        textStack.addArrangedSubview(descriptionLabel)

        controlView.backgroundColor = .clear
        controlView.layer.borderWidth = 1
        controlView.layer.borderColor = UIColor.HayaseTheme.input.cgColor
        controlView.layer.cornerRadius = 6

        valueLabel.font = .nunito(ofSize: 14)
        valueLabel.textColor = UIColor.HayaseTheme.foreground
        valueLabel.numberOfLines = 1
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        controlView.addSubview(valueLabel)
        NSLayoutConstraint.activate([
            valueLabel.leadingAnchor.constraint(equalTo: controlView.leadingAnchor, constant: 12),
            valueLabel.trailingAnchor.constraint(equalTo: controlView.trailingAnchor, constant: -12),
            valueLabel.centerYAnchor.constraint(equalTo: controlView.centerYAnchor),
            controlView.heightAnchor.constraint(equalToConstant: 36),
        ])
        controlWidthConstraint = controlView.widthAnchor.constraint(equalToConstant: 128)
        controlWidthConstraint?.priority = .defaultHigh
        controlWidthConstraint?.isActive = true
        controlView.setContentHuggingPriority(.required, for: .horizontal)
        controlView.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)

        contentStack.axis = .horizontal
        contentStack.alignment = .center
        contentStack.spacing = 12
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.addArrangedSubview(textStack)
        contentStack.addArrangedSubview(controlView)
        cardView.addSubview(contentStack)

        NSLayoutConstraint.activate([
            cardView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 6),
            cardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            cardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            cardView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6),
            contentStack.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 16),
            contentStack.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 24),
            contentStack.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -24),
            contentStack.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -16),
        ])
    }

    func configure(title: String,
                   description: String,
                   value: String?,
                   isLink: Bool,
                   horizontal: Bool,
                   controlWidth: CGFloat = 128,
                   filledControl: Bool = false) {
        titleLabel.text = title
        descriptionLabel.text = description
        valueLabel.text = value
        controlView.isHidden = value == nil
        controlWidthConstraint?.constant = controlWidth
        controlView.backgroundColor = filledControl ? UIColor.HayaseTheme.primary : .clear
        controlView.layer.borderWidth = filledControl ? 0 : 1
        valueLabel.textColor = filledControl ? UIColor.HayaseTheme.primaryForeground : UIColor.HayaseTheme.foreground
        valueLabel.textAlignment = filledControl ? .center : .natural
        accessoryType = isLink ? .disclosureIndicator : .none
        selectionStyle = (isLink || value != nil) ? .default : .none
        contentStack.axis = horizontal ? .horizontal : .vertical
        contentStack.alignment = horizontal ? .center : .leading
    }
}

// MARK: - HayaseAppActionsCell

/// Matches the web app page's one-column / md three-column action-button grid.
final class HayaseAppActionsCell: UITableViewCell {
    static let reuseID = "HayaseAppActionsCell"

    private let stack = UIStackView()
    var onAction: ((String) -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        selectionStyle = .none
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        stack.spacing = 12
        stack.distribution = .fillEqually
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        let importButton = makeButton("Import Settings From File", destructive: false)
        let exportButton = makeButton("Export Settings To File", destructive: false)
        let resetButton = makeButton("Reset EVERYTHING To Default", destructive: true)
        [importButton, exportButton, resetButton].forEach {
            $0.heightAnchor.constraint(greaterThanOrEqualToConstant: 40).isActive = true
            stack.addArrangedSubview($0)
        }

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 6),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6),
        ])
    }

    func configure(horizontal: Bool) {
        stack.axis = horizontal ? .horizontal : .vertical
    }

    private func makeButton(_ title: String, destructive: Bool) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.setTitleColor(destructive ? UIColor.HayaseTheme.destructiveForeground : UIColor.HayaseTheme.primaryForeground,
                             for: .normal)
        button.titleLabel?.font = .nunito(ofSize: 14, weight: .bold)
        button.titleLabel?.adjustsFontSizeToFitWidth = true
        button.titleLabel?.minimumScaleFactor = 0.75
        button.backgroundColor = destructive ? UIColor.HayaseTheme.destructive : UIColor.HayaseTheme.primary
        button.layer.cornerRadius = 6
        button.addTarget(self, action: #selector(actionTapped(_:)), for: .touchUpInside)
        return button
    }

    @objc private func actionTapped(_ sender: UIButton) {
        guard let title = sender.title(for: .normal) else { return }
        onAction?(title)
    }
}

// MARK: - HayaseSettingSliderCell

final class HayaseSettingSliderCell: UITableViewCell {
    static let reuseID = "HayaseSettingSliderCell"

    private let titleLabel = UILabel()
    private let descriptionLabel = UILabel()
    private let valueLabel = UILabel()
    private let slider = UISlider()
    private let contentStack = UIStackView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        selectionStyle = .none
        backgroundColor = .clear
        contentView.backgroundColor = .clear

        let card = UIView()
        card.backgroundColor = UIColor.HayaseTheme.muted
        card.layer.cornerRadius = 6
        card.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(card)

        titleLabel.font = .nunito(ofSize: 16, weight: .bold)
        titleLabel.textColor = UIColor.HayaseTheme.foreground
        titleLabel.numberOfLines = 0
        descriptionLabel.font = .nunito(ofSize: 12)
        descriptionLabel.textColor = UIColor.HayaseTheme.mutedForeground
        descriptionLabel.numberOfLines = 0
        let text = UIStackView(arrangedSubviews: [titleLabel, descriptionLabel])
        text.axis = .vertical
        text.spacing = 4

        slider.minimumValue = 0.3
        slider.maximumValue = 2.5
        slider.value = 1
        slider.minimumTrackTintColor = UIColor.HayaseTheme.primary
        slider.maximumTrackTintColor = UIColor.HayaseTheme.secondary
        slider.widthAnchor.constraint(equalToConstant: 240).isActive = true
        slider.isUserInteractionEnabled = false
        valueLabel.font = .nunito(ofSize: 12)
        valueLabel.textColor = UIColor.HayaseTheme.mutedForeground
        valueLabel.setContentHuggingPriority(.required, for: .horizontal)
        let control = UIStackView(arrangedSubviews: [slider, valueLabel])
        control.axis = .horizontal
        control.alignment = .center
        control.spacing = 12

        contentStack.axis = .horizontal
        contentStack.alignment = .center
        contentStack.spacing = 12
        contentStack.addArrangedSubview(text)
        contentStack.addArrangedSubview(control)
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(contentStack)

        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 6),
            card.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            card.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            card.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6),
            contentStack.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            contentStack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 24),
            contentStack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -24),
            contentStack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16),
        ])
    }

    func configure(title: String, description: String, displayValue: String, horizontal: Bool) {
        titleLabel.text = title
        descriptionLabel.text = description
        valueLabel.text = displayValue
        contentStack.axis = horizontal ? .horizontal : .vertical
        contentStack.alignment = horizontal ? .center : .leading
    }
}

// MARK: - HayaseSettingsPreviewGridCell

/// UI-only counterpart of the web ToggleGroup preview grids. Selection wiring is
/// deliberately deferred, but the complete option set and responsive layout are present.
final class HayaseSettingsPreviewGridCell: UITableViewCell {
    static let reuseID = "HayaseSettingsPreviewGridCell"

    private let cardView = UIView()
    private let titleLabel = UILabel()
    private let descriptionLabel = UILabel()
    private let gridStack = UIStackView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        selectionStyle = .none
        backgroundColor = .clear
        contentView.backgroundColor = .clear

        cardView.backgroundColor = UIColor.HayaseTheme.muted
        cardView.layer.cornerRadius = 6
        cardView.layer.masksToBounds = true
        cardView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(cardView)

        titleLabel.font = .nunito(ofSize: 16, weight: .bold)
        titleLabel.textColor = UIColor.HayaseTheme.foreground
        titleLabel.numberOfLines = 0

        descriptionLabel.font = .nunito(ofSize: 12)
        descriptionLabel.textColor = UIColor.HayaseTheme.mutedForeground
        descriptionLabel.numberOfLines = 0

        gridStack.axis = .vertical
        gridStack.spacing = 12

        let stack = UIStackView(arrangedSubviews: [titleLabel, descriptionLabel, gridStack])
        stack.axis = .vertical
        stack.spacing = 4
        stack.setCustomSpacing(12, after: descriptionLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(stack)

        NSLayoutConstraint.activate([
            cardView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 6),
            cardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            cardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            cardView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6),
            stack.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -24),
            stack.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -16),
        ])
    }

    fileprivate func configure(title: String,
                               description: String,
                               kind: SettingsPreviewKind,
                               twoColumns: Bool) {
        titleLabel.text = title
        descriptionLabel.text = description
        clearGrid()

        let tiles: [UIView]
        switch kind {
        case .subtitleStyle:
            tiles = [
                makeSubtitleTile(title: "None", sample: "🚫", selected: true),
                makeSubtitleTile(title: "Gandhi Sans Bold", sample: "Never give up on your dreams!", selected: false),
                makeSubtitleTile(title: "Noto Sans Bold", sample: "The story continues...", selected: false),
                makeSubtitleTile(title: "Roboto Bold", sample: "Let's go!", selected: false),
            ]
        case .colorTheme:
            tiles = [
                makeThemeTile(title: "Blackout", background: UIColor(red: 0.035, green: 0.035, blue: 0.043, alpha: 1), foreground: .white, accent: UIColor(red: 0.82, green: 0.22, blue: 0.49, alpha: 1), selected: true),
                makeThemeTile(title: "Whiteout", background: UIColor(white: 0.97, alpha: 1), foreground: UIColor(white: 0.08, alpha: 1), accent: UIColor(white: 0.15, alpha: 1), selected: false),
                makeThemeTile(title: "Catppuccin", background: UIColor(red: 0.12, green: 0.12, blue: 0.18, alpha: 1), foreground: UIColor(red: 0.80, green: 0.84, blue: 0.96, alpha: 1), accent: UIColor(red: 0.80, green: 0.65, blue: 0.97, alpha: 1), selected: false),
                makeThemeTile(title: "Dracula", background: UIColor(red: 0.16, green: 0.16, blue: 0.21, alpha: 1), foreground: UIColor(red: 0.97, green: 0.97, blue: 0.95, alpha: 1), accent: UIColor(red: 1.0, green: 0.47, blue: 0.78, alpha: 1), selected: false),
                makeThemeTile(title: "Amber", background: UIColor(red: 0.10, green: 0.08, blue: 0.04, alpha: 1), foreground: UIColor(red: 1.0, green: 0.91, blue: 0.66, alpha: 1), accent: UIColor(red: 0.96, green: 0.62, blue: 0.04, alpha: 1), selected: false),
                makeThemeTile(title: "Lavender", background: UIColor(red: 0.10, green: 0.08, blue: 0.16, alpha: 1), foreground: UIColor(red: 0.92, green: 0.88, blue: 1, alpha: 1), accent: UIColor(red: 0.60, green: 0.48, blue: 0.94, alpha: 1), selected: false),
                makeThemeTile(title: "System", background: UIColor.HayaseTheme.background, foreground: UIColor.HayaseTheme.foreground, accent: UIColor.HayaseTheme.primary, selected: false),
                makeThemeTile(title: "Custom", background: UIColor(red: 0.08, green: 0.11, blue: 0.13, alpha: 1), foreground: UIColor(red: 0.78, green: 0.96, blue: 0.90, alpha: 1), accent: UIColor(red: 0.19, green: 0.78, blue: 0.62, alpha: 1), selected: false),
            ]
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

    private func clearGrid() {
        for row in gridStack.arrangedSubviews {
            gridStack.removeArrangedSubview(row)
            row.removeFromSuperview()
        }
    }

    private func makeSubtitleTile(title: String, sample: String, selected: Bool) -> UIView {
        let tile = previewContainer(selected: selected)
        tile.backgroundColor = UIColor.HayaseTheme.background.withAlphaComponent(0.4)

        let name = previewLabel(title, size: 20, weight: .bold, color: UIColor.HayaseTheme.foreground)
        let sampleLabel = previewLabel(sample, size: title == "None" ? 36 : 17, weight: .bold, color: .white)
        sampleLabel.textAlignment = .center
        sampleLabel.layer.shadowColor = UIColor.black.cgColor
        sampleLabel.layer.shadowOpacity = 1
        sampleLabel.layer.shadowRadius = 2
        sampleLabel.layer.shadowOffset = CGSize(width: 1, height: 1)

        let video = UIView()
        video.backgroundColor = UIColor(white: 0.08, alpha: 1)
        video.layer.cornerRadius = 4
        video.translatesAutoresizingMaskIntoConstraints = false
        video.addSubview(sampleLabel)
        sampleLabel.translatesAutoresizingMaskIntoConstraints = false
        tile.addSubview(name)
        tile.addSubview(video)

        NSLayoutConstraint.activate([
            tile.heightAnchor.constraint(equalToConstant: 174),
            name.topAnchor.constraint(equalTo: tile.topAnchor, constant: 16),
            name.leadingAnchor.constraint(equalTo: tile.leadingAnchor, constant: 16),
            name.trailingAnchor.constraint(lessThanOrEqualTo: tile.trailingAnchor, constant: -16),
            video.topAnchor.constraint(equalTo: name.bottomAnchor, constant: 10),
            video.leadingAnchor.constraint(equalTo: tile.leadingAnchor, constant: 12),
            video.trailingAnchor.constraint(equalTo: tile.trailingAnchor, constant: -12),
            video.bottomAnchor.constraint(equalTo: tile.bottomAnchor, constant: -12),
            sampleLabel.centerXAnchor.constraint(equalTo: video.centerXAnchor),
            sampleLabel.centerYAnchor.constraint(equalTo: video.centerYAnchor),
            sampleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: video.leadingAnchor, constant: 8),
            sampleLabel.trailingAnchor.constraint(lessThanOrEqualTo: video.trailingAnchor, constant: -8),
        ])
        return tile
    }

    private func makeThemeTile(title: String,
                               background: UIColor,
                               foreground: UIColor,
                               accent: UIColor,
                               selected: Bool) -> UIView {
        let tile = previewContainer(selected: selected)
        tile.backgroundColor = background.withAlphaComponent(0.92)

        let name = previewLabel(title, size: 20, weight: .bold, color: foreground)
        let sample = previewLabel("The quick brown fox", size: 12, weight: .regular, color: foreground.withAlphaComponent(0.85))
        let muted = previewLabel("Muted description text", size: 10, weight: .regular, color: foreground.withAlphaComponent(0.55))
        let primary = miniButton("Primary", background: accent, foreground: background)
        let secondary = miniButton("Secondary", background: foreground.withAlphaComponent(0.12), foreground: foreground)
        let ghost = miniButton("Ghost", background: .clear, foreground: foreground)
        let buttons = UIStackView(arrangedSubviews: [primary, secondary, ghost])
        buttons.axis = .horizontal
        buttons.spacing = 6
        buttons.alignment = .center

        let input = UIView()
        input.layer.borderWidth = 1
        input.layer.borderColor = foreground.withAlphaComponent(0.25).cgColor
        input.layer.cornerRadius = 4
        let inputLabel = previewLabel("Sample", size: 10, weight: .regular, color: foreground)
        input.addSubview(inputLabel)
        inputLabel.translatesAutoresizingMaskIntoConstraints = false

        let switchTrack = UIView()
        switchTrack.backgroundColor = foreground.withAlphaComponent(0.18)
        switchTrack.layer.cornerRadius = 7
        switchTrack.translatesAutoresizingMaskIntoConstraints = false
        let thumb = UIView()
        thumb.backgroundColor = foreground
        thumb.layer.cornerRadius = 5
        thumb.translatesAutoresizingMaskIntoConstraints = false
        switchTrack.addSubview(thumb)

        let sliderTrack = UIView()
        sliderTrack.backgroundColor = foreground.withAlphaComponent(0.18)
        sliderTrack.layer.cornerRadius = 1.5
        sliderTrack.translatesAutoresizingMaskIntoConstraints = false
        let sliderFill = UIView()
        sliderFill.backgroundColor = accent
        sliderFill.layer.cornerRadius = 1.5
        sliderFill.translatesAutoresizingMaskIntoConstraints = false
        sliderTrack.addSubview(sliderFill)

        let body = UIStackView(arrangedSubviews: [sample, muted, buttons, input, switchTrack, sliderTrack])
        body.axis = .vertical
        body.alignment = .center
        body.spacing = 5
        body.translatesAutoresizingMaskIntoConstraints = false
        tile.addSubview(name)
        tile.addSubview(body)

        NSLayoutConstraint.activate([
            tile.heightAnchor.constraint(equalToConstant: 190),
            name.topAnchor.constraint(equalTo: tile.topAnchor, constant: 16),
            name.leadingAnchor.constraint(equalTo: tile.leadingAnchor, constant: 16),
            name.trailingAnchor.constraint(lessThanOrEqualTo: tile.trailingAnchor, constant: -16),
            body.topAnchor.constraint(equalTo: name.bottomAnchor, constant: 12),
            body.centerXAnchor.constraint(equalTo: tile.centerXAnchor),
            body.widthAnchor.constraint(lessThanOrEqualToConstant: 260),
            body.leadingAnchor.constraint(greaterThanOrEqualTo: tile.leadingAnchor, constant: 12),
            body.trailingAnchor.constraint(lessThanOrEqualTo: tile.trailingAnchor, constant: -12),
            body.bottomAnchor.constraint(lessThanOrEqualTo: tile.bottomAnchor, constant: -12),
            input.heightAnchor.constraint(equalToConstant: 24),
            input.widthAnchor.constraint(equalTo: body.widthAnchor),
            inputLabel.leadingAnchor.constraint(equalTo: input.leadingAnchor, constant: 8),
            inputLabel.centerYAnchor.constraint(equalTo: input.centerYAnchor),
            switchTrack.widthAnchor.constraint(equalToConstant: 28),
            switchTrack.heightAnchor.constraint(equalToConstant: 14),
            thumb.widthAnchor.constraint(equalToConstant: 10),
            thumb.heightAnchor.constraint(equalToConstant: 10),
            thumb.leadingAnchor.constraint(equalTo: switchTrack.leadingAnchor, constant: 2),
            thumb.centerYAnchor.constraint(equalTo: switchTrack.centerYAnchor),
            sliderTrack.heightAnchor.constraint(equalToConstant: 3),
            sliderTrack.widthAnchor.constraint(equalTo: body.widthAnchor),
            sliderFill.leadingAnchor.constraint(equalTo: sliderTrack.leadingAnchor),
            sliderFill.topAnchor.constraint(equalTo: sliderTrack.topAnchor),
            sliderFill.bottomAnchor.constraint(equalTo: sliderTrack.bottomAnchor),
            sliderFill.widthAnchor.constraint(equalTo: sliderTrack.widthAnchor, multiplier: 0.4),
        ])
        return tile
    }

    private func previewContainer(selected: Bool) -> UIView {
        let view = UIView()
        view.layer.cornerRadius = 6
        view.layer.borderWidth = selected ? 2 : 1
        view.layer.borderColor = (selected ? UIColor.HayaseTheme.primary : UIColor.HayaseTheme.border).cgColor
        return view
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
        let label = previewLabel(title, size: 9, weight: .bold, color: foreground)
        label.backgroundColor = background
        label.textAlignment = .center
        label.layer.cornerRadius = 4
        label.layer.masksToBounds = true
        label.widthAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true
        label.heightAnchor.constraint(equalToConstant: 22).isActive = true
        return label
    }
}

// MARK: - HayaseChangelogPlaceholderCell

final class HayaseChangelogPlaceholderCell: UITableViewCell {
    static let reuseID = "HayaseChangelogPlaceholderCell"

    private let rootStack = UIStackView()
    private let intro = UIStackView()
    private let titleLabel = UILabel()
    private let descriptionLabel = UILabel()
    private let entries = UIStackView()
    private var entryViews: [HayaseChangelogSkeletonEntry] = []

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        selectionStyle = .none
        backgroundColor = .clear
        contentView.backgroundColor = .clear

        titleLabel.font = .nunito(ofSize: 36, weight: .bold)
        titleLabel.textColor = UIColor.HayaseTheme.foreground
        descriptionLabel.font = .nunito(ofSize: 14)
        descriptionLabel.textColor = UIColor.HayaseTheme.mutedForeground

        intro.axis = .vertical
        intro.spacing = 12
        intro.addArrangedSubview(titleLabel)
        intro.addArrangedSubview(descriptionLabel)
        intro.isLayoutMarginsRelativeArrangement = true
        intro.layoutMargins = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        intro.heightAnchor.constraint(equalToConstant: 240).isActive = true

        entries.axis = .vertical
        entries.spacing = 0
        for _ in 0..<5 {
            let entry = HayaseChangelogSkeletonEntry()
            entryViews.append(entry)
            entries.addArrangedSubview(entry)
        }

        rootStack.axis = .vertical
        rootStack.addArrangedSubview(intro)
        rootStack.addArrangedSubview(entries)
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(rootStack)
        NSLayoutConstraint.activate([
            rootStack.topAnchor.constraint(equalTo: contentView.topAnchor),
            rootStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            rootStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            rootStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
    }

    func configure(title: String, description: String, wide: Bool) {
        titleLabel.text = title
        descriptionLabel.text = description
        let left = wide ? max(0, contentView.bounds.width * 0.25) : 16
        intro.layoutMargins = UIEdgeInsets(top: 0, left: left, bottom: 0, right: 16)
        intro.alignment = .fill
        entryViews.forEach { $0.configure(wide: wide) }
    }
}

private final class HayaseChangelogSkeletonEntry: UIView {
    private let dateContainer = UIView()
    private let dateSkeleton = HayaseChangelogSkeletonEntry.skeleton(width: 112, height: 8)
    private let body = UIStackView()
    private let content = UIStackView()
    private lazy var wideDateWidth = dateContainer.widthAnchor.constraint(equalTo: widthAnchor, multiplier: 0.25)

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        let separator = UIView()
        separator.backgroundColor = UIColor.HayaseTheme.border
        separator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(separator)

        dateSkeleton.translatesAutoresizingMaskIntoConstraints = false
        dateContainer.addSubview(dateSkeleton)
        NSLayoutConstraint.activate([
            dateContainer.heightAnchor.constraint(greaterThanOrEqualToConstant: 24),
            dateSkeleton.topAnchor.constraint(equalTo: dateContainer.topAnchor, constant: 8),
            dateSkeleton.leadingAnchor.constraint(equalTo: dateContainer.leadingAnchor, constant: 16),
            dateSkeleton.trailingAnchor.constraint(lessThanOrEqualTo: dateContainer.trailingAnchor, constant: -12),
            dateSkeleton.bottomAnchor.constraint(lessThanOrEqualTo: dateContainer.bottomAnchor),
        ])

        let heading = Self.skeleton(width: 192, height: 16)
        let line1 = Self.skeleton(width: 128, height: 8)
        let line2 = Self.skeleton(width: 112, height: 8)
        body.addArrangedSubview(heading)
        body.addArrangedSubview(line1)
        body.addArrangedSubview(line2)
        body.axis = .vertical
        body.alignment = .leading
        body.spacing = 8
        body.setCustomSpacing(12, after: heading)
        content.axis = .horizontal
        content.alignment = .top
        content.spacing = 0
        content.translatesAutoresizingMaskIntoConstraints = false
        content.addArrangedSubview(dateContainer)
        content.addArrangedSubview(body)
        addSubview(content)

        NSLayoutConstraint.activate([
            separator.topAnchor.constraint(equalTo: topAnchor, constant: 24),
            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1),
            content.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 16),
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            content.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
        ])
        configure(wide: true)
    }

    func configure(wide: Bool) {
        wideDateWidth.isActive = false
        for view in content.arrangedSubviews {
            content.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        content.axis = wide ? .horizontal : .vertical
        content.spacing = wide ? 0 : 16
        if wide {
            content.addArrangedSubview(dateContainer)
            content.addArrangedSubview(body)
        } else {
            content.addArrangedSubview(body)
            content.addArrangedSubview(dateContainer)
        }
        wideDateWidth.isActive = wide
    }

    private static func skeleton(width: CGFloat, height: CGFloat) -> UIView {
        let view = UIView()
        view.backgroundColor = UIColor.HayaseTheme.primary.withAlphaComponent(0.05)
        view.layer.cornerRadius = min(4, height / 2)
        view.widthAnchor.constraint(equalToConstant: width).isActive = true
        view.heightAnchor.constraint(equalToConstant: height).isActive = true
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 0.45
        pulse.toValue = 1
        pulse.duration = 0.9
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        view.layer.add(pulse, forKey: "hayasePulse")
        return view
    }
}

// Legacy names retained for source compatibility.
typealias SettingsToggleCell = HayaseSettingToggleCell
typealias SettingsDetailCell = HayaseSettingValueCell
