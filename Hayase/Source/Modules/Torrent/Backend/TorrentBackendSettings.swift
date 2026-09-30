//
//  TorrentBackendSettings.swift
//  Hayase
//
//  Created by scigward.
//

import Foundation

struct TorrentBackendSettings: Encodable {
    let torrentPersist: Bool
    // The upstream Hayase torrent-client schema names these as torrentDHT and
    // torrentPeX, but the values are disable flags. false means enabled.
    let torrentDHT: Bool
    let torrentStreamedDownload: Bool
    let torrentSpeed: Double
    let maxConns: Int
    let torrentPort: Int
    let dhtPort: Int
    let torrentPeX: Bool
    let nzbDomain: String
    let nzbLogin: String
    let nzbPassword: String
    let nzbPort: Int
    let nzbPoolSize: Int
    let path: String

    init(defaults: UserDefaults = .standard) {
        // torrentPersist/torrentStreamedDownload read their key string and
        // default from `Settings` (the single source of truth shared with
        // SettingsViewController's row declarations), but still go through
        // the injected `defaults` — not the `Settings.persistFiles`/
        // `Settings.streamedDownload` computed properties, which always read
        // `.standard` and would silently ignore a non-standard `defaults`
        // passed in here. This keeps the constructor's injectability honest
        // for every field, not just most of them.
        torrentPersist = defaults.object(forKey: Settings.Keys.persistFiles) as? Bool ?? Settings.Defaults.persistFiles
        torrentDHT = defaults.bool(forKey: "pref_disableDHT")
        torrentStreamedDownload = defaults.object(forKey: Settings.Keys.streamedDownload) as? Bool ?? Settings.Defaults.streamedDownload
        let speed = Double(defaults.string(forKey: "pref_torrentSpeed") ?? "40") ?? 40
        torrentSpeed = speed.isFinite ? min(999, max(1, speed)) : 40
        maxConns = Self.clampedInt(defaults.string(forKey: "pref_maxConns"), defaultValue: 80, min: 1, max: 512)
        torrentPort = Self.clampedInt(defaults.string(forKey: "pref_torrentPort"), defaultValue: 0, min: 0, max: 65535)
        dhtPort = Self.clampedInt(defaults.string(forKey: "pref_dhtPort"), defaultValue: 0, min: 0, max: 65535)
        torrentPeX = defaults.bool(forKey: "pref_disablePeX")
        nzbDomain = defaults.string(forKey: "pref_nzbDomain") ?? ""
        nzbLogin = defaults.string(forKey: "pref_nzbLogin") ?? ""
        nzbPassword = Keychain.string(forKey: Settings.Keys.nzbPassword) ?? ""
        nzbPort = Self.clampedInt(defaults.string(forKey: "pref_nzbPort"), defaultValue: 119, min: 1, max: 65535)
        nzbPoolSize = Self.clampedInt(defaults.string(forKey: "pref_nzbPoolSize"), defaultValue: 4, min: 1, max: 128)
        path = Self.downloadPath(for: defaults.string(forKey: "pref_torrentLocation") ?? "cache")
    }

    /// client.ts only queries NZB extensions once a Usenet server is configured.
    /// Port and pool size are always set, since they are clamped to at least 1.
    var hasNZBServer: Bool {
        !nzbDomain.isEmpty && !nzbLogin.isEmpty && !nzbPassword.isEmpty
    }

    func dictionary() -> [String: Any] {
        return [
            "torrentPersist": torrentPersist,
            "torrentDHT": torrentDHT,
            "torrentStreamedDownload": torrentStreamedDownload,
            "torrentSpeed": torrentSpeed,
            "maxConns": maxConns,
            "torrentPort": torrentPort,
            "dhtPort": dhtPort,
            "torrentPeX": torrentPeX,
            "nzbDomain": nzbDomain,
            "nzbLogin": nzbLogin,
            "nzbPassword": nzbPassword,
            "nzbPort": nzbPort,
            "nzbPoolSize": nzbPoolSize,
            "path": path,
        ]
    }

    private static func clampedInt(_ value: String?, defaultValue: Int, min: Int, max: Int) -> Int {
        let parsed = Int(value ?? "") ?? defaultValue
        return Swift.min(Swift.max(parsed, min), max)
    }

    private static func downloadPath(for location: String) -> String {
        let manager = FileManager.default
        let directory: FileManager.SearchPathDirectory = location == "documents" ? .documentDirectory : .cachesDirectory
        let base = manager.urls(for: directory, in: .userDomainMask).first
            ?? manager.temporaryDirectory
        let url = base.appendingPathComponent("HayaseWebTorrent", isDirectory: true)
        try? manager.createDirectory(at: url, withIntermediateDirectories: true)
        return url.path
    }
}
