//
//  SettingsClientPage.swift
//  Hayase
//
//  Mirrors: src/routes/app/settings/client/+page.svelte: the sections of the Client settings page.
//

import Foundation

extension SettingsSectionCatalog {
    static let clientSections: [Section] = [
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
                kind: .editableNumber(userDefaultsKey: "pref_nzbPort", defaultValue: "119", suffix: "", min: 0, max: 65535)),
            Row(title: "Connection Pool Size",
                description: "The number of simultaneous connections to use for downloading from your NZB provider. Higher values might increase download speeds but can cause issues with some providers if set too high.\n\nThis is shared between extension, so if you have multiple NZB extensions configured they will share the same pool of connections.",
                kind: .editableNumber(userDefaultsKey: "pref_nzbPoolSize", defaultValue: "4", suffix: "", min: 0, max: 128)),
        ], tab: .client),
    ]
}
