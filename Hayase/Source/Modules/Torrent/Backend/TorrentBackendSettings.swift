//
//  TorrentBackendSettings.swift
//  Hayase
//
//  Created by scigward.
//

import Foundation

struct TorrentBackendSettings: Encodable {
    let torrentPersist: Bool
    let torrentDHT: Bool
    let torrentStreamedDownload: Bool
    let torrentSpeed: Int
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
        torrentPersist = defaults.bool(forKey: "pref_persistFiles")
        torrentDHT = defaults.bool(forKey: "pref_disableDHT")
        torrentStreamedDownload = defaults.object(forKey: "pref_streamedDownload") as? Bool ?? true
        torrentSpeed = Self.clampedInt(defaults.string(forKey: "pref_torrentSpeed"), defaultValue: 40, min: 1, max: 999)
        maxConns = Self.clampedInt(defaults.string(forKey: "pref_maxConns"), defaultValue: 55, min: 1, max: 512)
        torrentPort = Self.clampedInt(defaults.string(forKey: "pref_torrentPort"), defaultValue: 0, min: 0, max: 65535)
        dhtPort = Self.clampedInt(defaults.string(forKey: "pref_dhtPort"), defaultValue: 0, min: 0, max: 65535)
        torrentPeX = defaults.bool(forKey: "pref_disablePeX")
        nzbDomain = defaults.string(forKey: "pref_nzbDomain") ?? ""
        nzbLogin = defaults.string(forKey: "pref_nzbLogin") ?? ""
        nzbPassword = defaults.string(forKey: "pref_nzbPassword") ?? ""
        nzbPort = Self.clampedInt(defaults.string(forKey: "pref_nzbPort"), defaultValue: 0, min: 0, max: 65535)
        nzbPoolSize = Self.clampedInt(defaults.string(forKey: "pref_nzbPoolSize"), defaultValue: 0, min: 0, max: 128)
        path = Self.defaultDownloadPath()
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

    private static func defaultDownloadPath() -> String {
        let manager = FileManager.default
        let base = manager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? manager.temporaryDirectory
        let url = base.appendingPathComponent("HayaseWebTorrent", isDirectory: true)
        try? manager.createDirectory(at: url, withIntermediateDirectories: true)
        return url.path
    }
}
