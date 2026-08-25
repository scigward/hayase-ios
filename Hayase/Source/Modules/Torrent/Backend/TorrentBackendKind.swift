//
//  TorrentBackendKind.swift
//  Hayase
//
//  Created by scigward.
//

import Foundation

enum TorrentBackendKind: String, CaseIterable {
    case native = "native"
    case webtorrent = "webtorrent"

    static let userDefaultsKey = "pref_torrentBackend"
    static let defaultKind: TorrentBackendKind = .webtorrent

    var label: String {
        switch self {
        case .native:
            return "Native (libtorrent)"
        case .webtorrent:
            return "WebTorrent"
        }
    }

    static func current(defaults: UserDefaults = .standard) -> TorrentBackendKind {
        let rawValue = defaults.string(forKey: userDefaultsKey) ?? defaultKind.rawValue
        return TorrentBackendKind(rawValue: rawValue) ?? defaultKind
    }

    static var settingsOptions: [(key: String, label: String)] {
        return allCases.map { ($0.rawValue, $0.label) }
    }
}
