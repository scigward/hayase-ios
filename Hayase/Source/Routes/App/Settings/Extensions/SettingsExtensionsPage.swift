//
//  SettingsExtensionsPage.swift
//  Hayase
//
//  Mirrors: src/routes/app/settings/extensions/+page.svelte: the sections of the Extensions settings page.
//

import Foundation

extension SettingsSectionCatalog {
    static let extensionsSections: [Section] = [
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
    ]
}
