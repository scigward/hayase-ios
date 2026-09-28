//
//  Settings.swift
//  Hayase
//
//  Created by scigward.
//

import Foundation

/// Centralized, typed access to the subset of `UserDefaults`-backed preferences
/// that were previously read with an independently-duplicated default in more
/// than one file — e.g. `pref_seekDuration` defaulted to `"2"` separately in
/// both `SettingsViewController` and `VideoPlayerViewController`. Every one of
/// those duplicated defaults happens to agree today, but nothing enforced
/// that; this file is now the single place that owns each key string and its
/// default, for both the settings UI and every consumer.
///
/// Scope is intentionally partial. Keys read from exactly one place — the
/// `nzb*`/`torrentSpeed`/`dhtPort`/etc. family already owned solely by
/// `TorrentBackendSettings`, or `pref_showLogger`, read identically as a
/// plain `false`-defaulting flag across ~15 player files — have no drift risk
/// today, so they're left as direct `UserDefaults` reads rather than migrated
/// for migration's sake. `pref_searchQuality`'s read in
/// `ExtensionSearchViewController` is also left alone where it intentionally
/// falls back to the in-context `currentResolution` rather than the global
/// default; only its plain read/write elsewhere routes through here.
///
/// Mirrors the shape of `interface`'s `modules/settings` (`defaults.ts` +
/// `settings.ts`), scoped to what Hayase currently ports. Hayase is iOS-only,
/// so there's no equivalent of `supports.ts` here — that file exists upstream
/// to gate defaults across Android/iOS/desktop/AndroidTV, which doesn't apply
/// to a single-platform app.
enum Settings {
    struct DisplayPreferences: Equatable {
        let title = Settings.titleType
        let hideSpoilers = Settings.hideSpoilers
        let showAdultContent = TrackerAccountManager.shared.viewer(for: .anilist)?.displayAdultContent ?? Settings.showHentai
        let accountLanguage = TrackerAccountManager.shared.viewer(for: .anilist)?.titleLanguage
    }

    /// Posted whenever a setting is written through this type, with the
    /// changed key in `userInfo["key"]`. Follows the same
    /// `NotificationCenter` convention already used elsewhere in the app
    /// (e.g. `W2GLobby.didChange`, `Local.didChange`).
    static let didChange = Notification.Name("HayaseSettingsDidChange")

    /// Raw `UserDefaults` key strings, identical to what's already on disk —
    /// existing installs need no migration.
    enum Keys {
        static let deband = "pref_deband"
        static let autocomplete = "pref_autocomplete"
        static let skipFiller = "pref_skipFiller"
        static let seekDuration = "pref_seekDuration"
        static let subtitleLanguage = "pref_subtitleLanguage"
        static let audioLanguage = "pref_audioLanguage"
        static let subtitleRenderHeight = "pref_subtitleRenderHeight"
        static let subtitleStyle = "pref_subtitleStyle"
        static let playerAutoplay = "pref_autoplay"
        static let playerPause = "pref_playerPause"
        static let playerAutoPiP = "pref_autoPiP"
        static let playerSkip = "pref_skipIntro"
        static let minimalPlayerUI = "pref_minimalUI"
        static let searchQuality = "pref_searchQuality"
        static let searchAutoSelect = "pref_searchAutoSelect"
        static let lookupPreference = "pref_lookupPreference"
        static let showHentai = "pref_showHentai"
        static let titleType = "pref_titleType"
        static let hideSpoilers = "pref_hideSpoilers"
        static let showNavigation = "pref_showNavigation"
        static let uiScale = "pref_uiScale"
        static let debugLevel = "pref_debugLevel"
        static let persistFiles = "pref_persistFiles"
        static let streamedDownload = "pref_streamedDownload"
    }

    /// Canonical default per key — referenced both here and by
    /// `SettingsViewController`'s row declarations, so there is exactly one
    /// literal default per setting rather than one per call site.
    enum Defaults {
        static let deband = false
        static let autocomplete = true
        static let skipFiller = false
        static let seekDuration = "2"
        static let subtitleLanguage = "eng"
        static let audioLanguage = "jpn"
        // Intentional user-requested iOS exception: default to 1080p, not the
        // interface's mobile 720p default. Preserve this when syncing upstream.
        static let subtitleRenderHeight = "1080"
        static let subtitleStyle = "none"
        static let playerAutoplay = true
        static let playerPause = true
        static let playerAutoPiP = false
        static let playerSkip = false
        static let minimalPlayerUI = false
        static let searchQuality = "1080"
        static let searchAutoSelect = true
        static let lookupPreference = "quality"
        static let showHentai = false
        static let titleType = "ANILIST"
        static let hideSpoilers = false
        static let showNavigation = false
        static let uiScale = 1.0
        static let debugLevel = ""
        static let persistFiles = false
        static let streamedDownload = true
    }

    /// Writes any settings key through the same path as the typed properties
    /// below, so `didChange` fires consistently regardless of whether the
    /// key has a typed accessor here. Used by `SettingsViewController`'s
    /// generic toggle/selectable/editableNumber row cells, which only know
    /// a key string at the point they write, not a specific property.
    static func write(_ value: Any?, forKey key: String) {
        UserDefaults.standard.set(value, forKey: key)
        NotificationCenter.default.post(name: didChange, object: nil, userInfo: ["key": key])
    }

    /// Reads a `Bool` the same way regardless of which literal default it
    /// happens to have, unlike the original call sites, which mixed
    /// `.bool(forKey:)` (implicit `false` default) and
    /// `.object(forKey:) as? Bool ?? true` depending on the setting.
    private static func readBool(_ key: String, default defaultValue: Bool) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? defaultValue
    }

    // MARK: - Player

    static var deband: Bool {
        get { readBool(Keys.deband, default: Defaults.deband) }
        set { write(newValue, forKey: Keys.deband) }
    }

    static var autocomplete: Bool {
        get { readBool(Keys.autocomplete, default: Defaults.autocomplete) }
        set { write(newValue, forKey: Keys.autocomplete) }
    }

    static var skipFiller: Bool {
        get { readBool(Keys.skipFiller, default: Defaults.skipFiller) }
        set { write(newValue, forKey: Keys.skipFiller) }
    }

    /// Stored as a string (matches the `editableNumber` settings row and
    /// interface's `playerSeek`); callers that need seconds as a `Double`
    /// convert locally, same as before.
    static var seekDuration: String {
        get { UserDefaults.standard.string(forKey: Keys.seekDuration) ?? Defaults.seekDuration }
        set { write(newValue, forKey: Keys.seekDuration) }
    }

    static var subtitleLanguage: String {
        get { UserDefaults.standard.string(forKey: Keys.subtitleLanguage) ?? Defaults.subtitleLanguage }
        set { write(newValue, forKey: Keys.subtitleLanguage) }
    }

    static var audioLanguage: String {
        get { UserDefaults.standard.string(forKey: Keys.audioLanguage) ?? Defaults.audioLanguage }
        set { write(newValue, forKey: Keys.audioLanguage) }
    }

    /// Subtitle render height in pixels as a string, `"0"` to follow the video size.
    static var subtitleRenderHeight: String {
        get { UserDefaults.standard.string(forKey: Keys.subtitleRenderHeight) ?? Defaults.subtitleRenderHeight }
        set { write(newValue, forKey: Keys.subtitleRenderHeight) }
    }

    static var subtitleStyle: String {
        get { UserDefaults.standard.string(forKey: Keys.subtitleStyle) ?? Defaults.subtitleStyle }
        set { write(newValue, forKey: Keys.subtitleStyle) }
    }

    static var playerAutoplay: Bool {
        get { readBool(Keys.playerAutoplay, default: Defaults.playerAutoplay) }
        set { write(newValue, forKey: Keys.playerAutoplay) }
    }

    static var playerPause: Bool {
        get { readBool(Keys.playerPause, default: Defaults.playerPause) }
        set { write(newValue, forKey: Keys.playerPause) }
    }

    static var playerAutoPiP: Bool {
        get { readBool(Keys.playerAutoPiP, default: Defaults.playerAutoPiP) }
        set { write(newValue, forKey: Keys.playerAutoPiP) }
    }

    static var playerSkip: Bool {
        get { readBool(Keys.playerSkip, default: Defaults.playerSkip) }
        set { write(newValue, forKey: Keys.playerSkip) }
    }

    static var minimalPlayerUI: Bool {
        get { readBool(Keys.minimalPlayerUI, default: Defaults.minimalPlayerUI) }
        set { write(newValue, forKey: Keys.minimalPlayerUI) }
    }

    // MARK: - Search / Extensions

    /// General-purpose accessor. `ExtensionSearchViewController`'s initial
    /// read of this preference intentionally falls back to the in-context
    /// `currentResolution` instead of `Defaults.searchQuality` and is left
    /// reading `UserDefaults` directly for that reason — see the file-level
    /// note above.
    static var searchQuality: String {
        get { UserDefaults.standard.string(forKey: Keys.searchQuality) ?? Defaults.searchQuality }
        set { write(newValue, forKey: Keys.searchQuality) }
    }

    static var searchAutoSelect: Bool {
        get { readBool(Keys.searchAutoSelect, default: Defaults.searchAutoSelect) }
        set { write(newValue, forKey: Keys.searchAutoSelect) }
    }

    static var lookupPreference: String {
        get { UserDefaults.standard.string(forKey: Keys.lookupPreference) ?? Defaults.lookupPreference }
        set { write(newValue, forKey: Keys.lookupPreference) }
    }

    // MARK: - Metadata / Display

    static var showHentai: Bool {
        get { readBool(Keys.showHentai, default: Defaults.showHentai) }
        set { write(newValue, forKey: Keys.showHentai) }
    }

    static var titleType: String {
        get { UserDefaults.standard.string(forKey: Keys.titleType) ?? Defaults.titleType }
        set { write(newValue, forKey: Keys.titleType) }
    }

    static var hideSpoilers: Bool {
        get { readBool(Keys.hideSpoilers, default: Defaults.hideSpoilers) }
        set { write(newValue, forKey: Keys.hideSpoilers) }
    }

    static var showNavigation: Bool {
        get { readBool(Keys.showNavigation, default: Defaults.showNavigation) }
        set { write(newValue, forKey: Keys.showNavigation) }
    }

    static var uiScale: Double {
        get {
            guard UserDefaults.standard.object(forKey: Keys.uiScale) != nil else {
                return Defaults.uiScale
            }
            return min(max(UserDefaults.standard.double(forKey: Keys.uiScale), 0.3), 2.5)
        }
        set { write(min(max(newValue, 0.3), 2.5), forKey: Keys.uiScale) }
    }

    static let torrentDebugNamespaces = "torrent:*,webtorrent:*,simple-peer,bittorrent-protocol,bittorrent-dht,bittorrent-lsd,torrent-discovery,bittorrent-tracker:*,ut_metadata,nat-pmp,nat-api"

    static var debugLevel: String {
        get {
            switch UserDefaults.standard.string(forKey: Keys.debugLevel) ?? Defaults.debugLevel {
            case "torrent": return torrentDebugNamespaces
            case "ui": return "ui:*"
            case let value: return value
            }
        }
        set { write(newValue, forKey: Keys.debugLevel) }
    }

    // MARK: - Torrent
    // (Only the two keys duplicated outside `TorrentBackendSettings` live
    // here; the rest of that struct's keys have a single owner already.)

    static var persistFiles: Bool {
        get { readBool(Keys.persistFiles, default: Defaults.persistFiles) }
        set { write(newValue, forKey: Keys.persistFiles) }
    }

    static var streamedDownload: Bool {
        get { readBool(Keys.streamedDownload, default: Defaults.streamedDownload) }
        set { write(newValue, forKey: Keys.streamedDownload) }
    }
}
