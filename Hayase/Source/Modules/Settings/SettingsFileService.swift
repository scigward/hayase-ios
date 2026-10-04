// Mirrors: src/routes/app/settings/app/+page.svelte and modules/settings/defaults.ts.
import Foundation
import CoreFoundation

enum SettingsFileService {
    private struct Field {
        let web: String
        let native: String
        let fallback: Any
    }

    // Account credentials, sync toggles and debug are separate stores upstream.
    // Export the settings object, with web names and numeric JSON values.
    private static let fields: [Field] = [
        .init(web: "volume", native: "volume", fallback: 1.0),
        .init(web: "playerAutoplay", native: Settings.Keys.playerAutoplay, fallback: true),
        .init(web: "playerAutoPiP", native: Settings.Keys.playerAutoPiP, fallback: false),
        .init(web: "playerPause", native: Settings.Keys.playerPause, fallback: true),
        .init(web: "playerAutocomplete", native: Settings.Keys.autocomplete, fallback: true),
        .init(web: "playerDeband", native: Settings.Keys.deband, fallback: false),
        .init(web: "subtitleStyle", native: Settings.Keys.subtitleStyle, fallback: "none"),
        .init(web: "subtitleRenderHeight", native: Settings.Keys.subtitleRenderHeight, fallback: Settings.Defaults.subtitleRenderHeight),
        .init(web: "subtitleLanguage", native: Settings.Keys.subtitleLanguage, fallback: "eng"),
        .init(web: "audioLanguage", native: Settings.Keys.audioLanguage, fallback: "jpn"),
        .init(web: "playerSeek", native: Settings.Keys.seekDuration, fallback: 2.0),
        .init(web: "playerSkip", native: Settings.Keys.playerSkip, fallback: false),
        .init(web: "playerSkipFiller", native: Settings.Keys.skipFiller, fallback: false),
        .init(web: "minimalPlayerUI", native: Settings.Keys.minimalPlayerUI, fallback: false),
        .init(web: "searchQuality", native: Settings.Keys.searchQuality, fallback: "1080"),
        .init(web: "searchAutoSelect", native: Settings.Keys.searchAutoSelect, fallback: true),
        .init(web: "lookupPreference", native: Settings.Keys.lookupPreference, fallback: "quality"),
        .init(web: "torrentPersist", native: Settings.Keys.persistFiles, fallback: false),
        .init(web: "torrentDHT", native: "pref_disableDHT", fallback: false),
        .init(web: "torrentPeX", native: "pref_disablePeX", fallback: false),
        .init(web: "torrentStreamedDownload", native: Settings.Keys.streamedDownload, fallback: true),
        .init(web: "torrentSpeed", native: "pref_torrentSpeed", fallback: 40.0),
        .init(web: "maxConns", native: "pref_maxConns", fallback: 80.0),
        .init(web: "torrentPort", native: "pref_torrentPort", fallback: 0.0),
        .init(web: "dhtPort", native: "pref_dhtPort", fallback: 0.0),
        .init(web: "nzbDomain", native: "pref_nzbDomain", fallback: ""),
        .init(web: "nzbLogin", native: "pref_nzbLogin", fallback: ""),
        .init(web: "nzbPassword", native: Settings.Keys.nzbPassword, fallback: ""),
        .init(web: "nzbPort", native: "pref_nzbPort", fallback: 119.0),
        .init(web: "nzbPoolSize", native: "pref_nzbPoolSize", fallback: 4.0),
        .init(web: "showHentai", native: Settings.Keys.showHentai, fallback: false),
        .init(web: "hideSpoilers", native: Settings.Keys.hideSpoilers, fallback: false),
        .init(web: "showNavigation", native: Settings.Keys.showNavigation, fallback: false),
        .init(web: "titleType", native: Settings.Keys.titleType, fallback: "ANILIST"),
        .init(web: "uiScale", native: Settings.Keys.uiScale, fallback: 1.0),
    ]
    private static let extrasKey = "hayase.interfaceSettingsExtras"
    /// OAuth client settings. A settings file must not be able to swap the client a login
    /// goes through, so the legacy format's free-form keys skip these.
    private static let clientKeys: Set<String> = [
        "pref_anilistClientID", "pref_malClientID", "pref_simklClientID", "pref_simklClientSecret",
    ]
    private static let extraKeys: Set<String> = [
        "playerCustom", "enableDoH", "doHURL", "hideToTray",
        "showDetailsInRPC", "angle", "enableExternal", "playerPath",
        "theme", "customThemeColors", "torrentPath", "androidStorageType",
    ]

    static func exportData() throws -> Data {
        let defaults = UserDefaults.standard
        var values = defaults.dictionary(forKey: extrasKey) ?? [:]
        for field in fields {
            values[field.web] = (try? normalized(Settings.storedValue(forKey: field.native) ?? field.fallback, field: field))
                ?? field.fallback
        }
        // The web range control stores playerSeek as a string, unlike numeric inputs.
        if let seek = values["playerSeek"] as? Double {
            values["playerSeek"] = seek.rounded() == seek ? String(format: "%.0f", seek) : String(seek)
        }
        values["androidStorageType"] = defaults.string(forKey: "pref_torrentLocation") == "documents" ? "internal" : "cache"
        values["torrentPath"] = TorrentBackendSettings().path
        guard let data = JSONSerialization.safeData(values, options: [.prettyPrinted, .sortedKeys]) else {
            throw CocoaError(.coderInvalidValue)
        }
        return data
    }

    static func importData(_ data: Data) throws {
        guard let values = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let bundleID = Bundle.main.bundleIdentifier else { throw ImportError.invalidFormat }
        let legacy = !values.isEmpty && values.keys.allSatisfy(isLegacyKey)
        let allowed = Set(fields.map(\.web)).union(extraKeys)
        guard legacy || values.keys.allSatisfy({ allowed.contains($0) }) else { throw ImportError.invalidFormat }

        // Validate everything before replacing any persisted values.
        var replacement: [String: Any] = [:]
        for field in fields {
            let value = try normalized(values[legacy ? field.native : field.web] ?? field.fallback, field: field)
            // Existing native numeric inputs/readers store numbers as strings.
            if field.fallback is Double, field.native != Settings.Keys.uiScale,
               field.native != "volume", let number = value as? Double {
                replacement[field.native] = number.rounded() == number ? String(format: "%.0f", number) : String(number)
            } else {
                replacement[field.native] = value
            }
        }
        if legacy {
            guard values.values.allSatisfy({ $0 is String || $0 is NSNumber }) else { throw ImportError.invalidFormat }
            for (key, value) in values where !fields.contains(where: { $0.native == key }) && !clientKeys.contains(key) {
                replacement[key] = value
            }
        } else {
            let extras = values.filter { extraKeys.contains($0.key) }
            guard PropertyListSerialization.propertyList(extras, isValidFor: .binary) else { throw ImportError.invalidFormat }
            replacement[extrasKey] = extras
            let location = values["androidStorageType"] as? String ?? "cache"
            guard ["cache", "internal", "sdcard"].contains(location) else { throw ImportError.invalidFormat }
            replacement["pref_torrentLocation"] = location == "cache" ? "cache" : "documents"
        }

        Keychain.set(replacement.removeValue(forKey: Settings.Keys.nzbPassword) as? String, forKey: Settings.Keys.nzbPassword)
        let defaults = UserDefaults.standard
        var domain = defaults.persistentDomain(forName: bundleID) ?? [:]
        fields.forEach { domain.removeValue(forKey: $0.native) }
        domain.removeValue(forKey: extrasKey)
        replacement.forEach { domain[$0.key] = $0.value }
        defaults.setPersistentDomain(domain, forName: bundleID)
        // Consumers see the complete new state, including defaults for omitted keys.
        for key in Set(fields.map(\.native)).union(replacement.keys) {
            NotificationCenter.default.post(name: Settings.didChange, object: nil, userInfo: ["key": key])
        }
    }

    private static func normalized(_ value: Any, field: Field) throws -> Any {
        if let fallback = field.fallback as? NSNumber, CFGetTypeID(fallback) == CFBooleanGetTypeID() {
            guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else {
                throw ImportError.invalidFormat
            }
            return number.boolValue
        }
        if field.fallback is Double {
            let number: Double?
            if let string = value as? String { number = Double(string) }
            else if let scalar = value as? NSNumber, CFGetTypeID(scalar) != CFBooleanGetTypeID() { number = scalar.doubleValue }
            else { number = nil }
            guard let number, number.isFinite else { throw ImportError.invalidFormat }
            let range: ClosedRange<Double>
            switch field.web {
            case "volume": range = 0...1
            case "uiScale": range = 0.3...2.5
            case "playerSeek", "torrentSpeed": range = 1...50
            case "maxConns": range = 1...512
            case "nzbPoolSize": range = 0...128
            default: range = 0...65535
            }
            guard range.contains(number),
                  ["volume", "uiScale", "playerSeek", "torrentSpeed"].contains(field.web) || number.rounded() == number else {
                throw ImportError.invalidFormat
            }
            return number
        }
        guard let string = value as? String else { throw ImportError.invalidFormat }
        let choices: [String]?
        switch field.web {
        case "subtitleStyle": choices = ["none", "gandhisans", "notosans", "roboto"]
        case "subtitleRenderHeight": choices = ["0", "480", "720", "1080", "1440"]
        case "searchQuality": choices = ["", "480", "720", "1080", "2160"]
        case "lookupPreference": choices = ["quality", "size", "seeders"]
        case "titleType": choices = ["ANILIST", "ROMAJI", "ENGLISH", "NATIVE"]
        default: choices = nil
        }
        guard choices?.contains(string) ?? true else { throw ImportError.invalidFormat }
        return string
    }

    @MainActor static func resetPreferences() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        // The web clears stores and restarts. Stop native owners before clearing
        // persistence so they cannot keep using or re-save the previous session.
        MiniPlayerManager.shared.close()
        W2GLobby.shared.leave()
        TrackerKind.allCases.forEach { TrackerAccountManager.shared.logout($0) }
        ExtensionService.shared.reset()
        URLCache.shared.removeAllCachedResponses()
        AniListOperationCache.shared.clearViewerScopedEntries()
        UserDefaults.standard.removePersistentDomain(forName: bundleID)
        Keychain.removeAll()
        for field in fields {
            NotificationCenter.default.post(name: Settings.didChange, object: nil, userInfo: ["key": field.native])
        }
        NotificationCenter.default.post(name: Settings.didChange, object: nil, userInfo: ["key": Settings.Keys.debugLevel])
        NotificationCenter.default.post(name: LocalTracking.didChange, object: nil)
        NotificationCenter.default.post(name: WatchProgressService.didChange, object: nil)
    }

    private static func isLegacyKey(_ key: String) -> Bool {
        key.hasPrefix("pref_") || key.hasPrefix("tracker_sync_")
    }

    enum ImportError: LocalizedError {
        case invalidFormat
        var errorDescription: String? { "The selected file is not a valid Hayase settings file." }
    }
}
