// Mirrors: src/routes/app/settings pages and src/lib/modules/settings/util.ts
import Foundation

// MARK: - Tab model

enum SettingsTab: Int, CaseIterable {
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

enum RowKind {
    case toggle(userDefaultsKey: String, defaultValue: Bool)
    /// Selectable value — tapping shows a picker with the given options.
    /// `userDefaultsKey` persists the choice; `options` maps stored-key → display label;
    /// `defaultKey` is the initial stored key.
    case selectable(userDefaultsKey: String, options: [(key: String, label: String)], defaultKey: String)
    /// Editable numeric value — tapping shows a text field.
    case editableNumber(userDefaultsKey: String, defaultValue: String, suffix: String, min: Int, max: Int)
    case editableText(userDefaultsKey: String, defaultValue: String, secure: Bool)
    case extensions
    case appActions
    case slider(userDefaultsKey: String, defaultValue: Double, min: Double, max: Double, step: Double)
    case button(String)
    /// Preview chooser used by the web settings for subtitle styles and themes.
    /// Themes intentionally remain preview-only until native theming is implemented.
    case previewGrid(SettingsPreviewKind)
    /// The web changelog presentation while its GitHub-backed contents load.
    case changelogPlaceholder
    /// Account card — full tracker account card.
    case account(TrackerKind)
}

struct Row {
    let title:       String
    let description: String
    let kind:        RowKind
}

struct Section {
    let header: String
    let rows:   [Row]
    let tab:    SettingsTab
}

enum SettingsSectionCatalog {
    // MARK: - Option lists (matching Hayase src/lib/modules/settings/util.ts)

    private static let languageCodes: [(key: String, label: String)] = [
        ("eng", "English"), ("enm", "English (Weeb)"), ("jpn", "Japanese"), ("chi", "Chinese"),
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

    private static let downloadLocations: [(key: String, label: String)] = [
        ("cache", "Cache"), ("documents", "Internal Storage"),
    ]

    private static let debugLevels: [(key: String, label: String)] = [
        ("", "None"), ("*", "All"), (Settings.torrentDebugNamespaces, "Torrent"), ("ui:*", "Interface"),
    ]

    // MARK: - All sections (full data, tagged by tab)

    static let sections: [Section] = [

        // ── Player tab (Hayase /app/settings/ — +page.svelte) ──

        Section(header: "Subtitle Settings", rows: [
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
                kind: .toggle(userDefaultsKey: Settings.Keys.playerAutoplay, defaultValue: Settings.Defaults.playerAutoplay)),
            Row(title: "Pause On Lost Visibility",
                description: "Pauses/Resumes video playback when the app loses visibility.",
                kind: .toggle(userDefaultsKey: Settings.Keys.playerPause, defaultValue: Settings.Defaults.playerPause)),
            Row(title: "PiP On Lost Visibility",
                description: "Automatically enters Picture in Picture mode when the app loses visibility.",
                kind: .toggle(userDefaultsKey: Settings.Keys.playerAutoPiP, defaultValue: Settings.Defaults.playerAutoPiP)),
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
                kind: .toggle(userDefaultsKey: Settings.Keys.playerSkip, defaultValue: Settings.Defaults.playerSkip)),
            Row(title: "Auto-Skip Filler",
                description: "Automatically skip filler episodes. This WILL skip ENTIRE episodes.",
                kind: .toggle(userDefaultsKey: Settings.Keys.skipFiller, defaultValue: Settings.Defaults.skipFiller)),
        ], tab: .player),

        Section(header: "Interface Settings", rows: [
            Row(title: "Minimal UI",
                description: "Forces minimalistic player UI, hides controls.",
                kind: .toggle(userDefaultsKey: Settings.Keys.minimalPlayerUI, defaultValue: Settings.Defaults.minimalPlayerUI)),
        ], tab: .player),

        // ── Client tab (Hayase /app/settings/client/) ──

        Section(header: "Security Settings", rows: [], tab: .client),

        Section(header: "Torrent Client Settings", rows: [
            Row(title: "Torrent Download Location",
                description: "Path to the folder used to store torrents. By default this is the OS's TEMP/TMP cache folder, which might lose data when your OS tries to reclaim storage.",
                kind: .selectable(userDefaultsKey: "pref_torrentLocation", options: Self.downloadLocations, defaultKey: "cache")),
            Row(title: "Persist Files",
                description: "Keeps torrents files instead of deleting them after a new torrent is played. This doesn't seed the files, only keeps them on your drive. This will quickly fill up your storage.",
                kind: .toggle(userDefaultsKey: Settings.Keys.persistFiles, defaultValue: Settings.Defaults.persistFiles)),
            Row(title: "Streamed Download",
                description: "Only downloads the data that's directly needed for playback, down to the minute, instead of downloading an entire batch of episodes. Will not buffer ahead more than a few seconds, and will stop downloading once the few second buffer is filled. Saves bandwidth and reduces strain on the peer swarm.",
                kind: .toggle(userDefaultsKey: Settings.Keys.streamedDownload, defaultValue: Settings.Defaults.streamedDownload)),
            Row(title: "Transfer Speed Limit",
                description: "Download/Upload speed limit for torrents, higher values increase CPU usage, and values higher than your storage write speeds will quickly fill up RAM.",
                kind: .editableNumber(userDefaultsKey: "pref_torrentSpeed", defaultValue: "40", suffix: "Mb/s", min: 1, max: 50)),
            Row(title: "Max Number of Connections",
                description: "Number of peers per torrent. Higher values will increase download speeds but might quickly fill up available ports if your ISP limits the maximum allowed number of open connections.",
                kind: .editableNumber(userDefaultsKey: "pref_maxConns", defaultValue: "80", suffix: "", min: 1, max: 512)),
            Row(title: "Forwarded Torrent Port",
                description: "Forwarded port used for incoming torrent connections. 0 automatically finds an open unused port. Change this to a specific port if you forwarded manually, or if you use a VPN",
                kind: .editableNumber(userDefaultsKey: "pref_torrentPort", defaultValue: "0", suffix: "", min: 0, max: 65535)),
            Row(title: "DHT Port",
                description: "Port used for DHT connections. 0 is automatic.",
                kind: .editableNumber(userDefaultsKey: "pref_dhtPort", defaultValue: "0", suffix: "", min: 0, max: 65535)),
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
                kind: .editableText(userDefaultsKey: "pref_nzbDomain", defaultValue: "", secure: false)),
            Row(title: "Provider Login",
                description: "The Login/Username for your NZB provider.",
                kind: .editableText(userDefaultsKey: "pref_nzbLogin", defaultValue: "", secure: false)),
            Row(title: "Provider Password",
                description: "The Password for your NZB provider. This is stored in plaintext in the settings file, so be aware of that.",
                kind: .editableText(userDefaultsKey: Settings.Keys.nzbPassword, defaultValue: "", secure: true)),
            Row(title: "Connection Port",
                description: "The port used to connect to your NZB provider. 119 is the default for NNTP.",
                kind: .editableNumber(userDefaultsKey: "pref_nzbPort", defaultValue: "119", suffix: "", min: 1, max: 65535)),
            Row(title: "Connection Pool Size",
                description: "The number of simultaneous connections to use for downloading from your NZB provider. Higher values might increase download speeds but can cause issues with some providers if set too high.\n\nThis is shared between extension, so if you have multiple NZB extensions configured they will share the same pool of connections.",
                kind: .editableNumber(userDefaultsKey: "pref_nzbPoolSize", defaultValue: "4", suffix: "", min: 1, max: 128)),
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
                kind: .toggle(userDefaultsKey: Settings.Keys.showNavigation, defaultValue: Settings.Defaults.showNavigation)),
            Row(title: "UI Scale",
                description: "Change the zoom level of the interface.",
                kind: .slider(userDefaultsKey: Settings.Keys.uiScale, defaultValue: Settings.Defaults.uiScale, min: 0.3, max: 2.5, step: 0.1)),
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
                kind: .extensions),
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
                kind: .account(.simkl)),
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
                kind: .selectable(userDefaultsKey: Settings.Keys.debugLevel, options: Self.debugLevels, defaultKey: Settings.Defaults.debugLevel)),
            Row(title: "Debug page",
                description: "Go to the debug page to access additional debugging features.",
                kind: .button("Go to Debug Page")),
        ], tab: .app),

        Section(header: "", rows: [
            Row(title: "Changelog",
                description: "New updates and improvements to Hayase.",
                kind: .changelogPlaceholder),
        ], tab: .changelog),


    ]
}
