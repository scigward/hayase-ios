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

    static let languageCodes: [(key: String, label: String)] = [
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

    static let subtitleResolutions: [(key: String, label: String)] = [
        ("0", "None"), ("1440", "1440p"), ("1080", "1080p"), ("720", "720p"), ("480", "480p"),
    ]

    static let videoResolutions: [(key: String, label: String)] = [
        ("2160", "2160p"), ("1080", "1080p"), ("720", "720p"), ("480", "480p"), ("", "Any"),
    ]

    static let lookupPreferences: [(key: String, label: String)] = [
        ("quality", "Quality"), ("size", "Size"), ("seeders", "Availability"),
    ]

    static let titleTypes: [(key: String, label: String)] = [
        ("ANILIST", "Anilist Account Preference"),
        ("ROMAJI", "Romaji (Shingeki no Kyojin)"),
        ("ENGLISH", "English (Attack on Titan)"),
        ("NATIVE", "Native (進撃の巨人)"),
    ]

    static let downloadLocations: [(key: String, label: String)] = [
        ("cache", "Cache"), ("documents", "Internal Storage"),
    ]

    static let debugLevels: [(key: String, label: String)] = [
        ("", "None"), ("*", "All"), (Settings.torrentDebugNamespaces, "Torrent"), ("ui:*", "Interface"),
    ]

    // MARK: - All sections (full data, tagged by tab)

    /// The sections of every settings page, in the order of the tabs (each page is in its own file)
    static let sections: [Section] = playerSections + clientSections + interfaceSections + extensionsSections + accountsSections + appSections + changelogSections
}
