//
//  SettingsInterfacePage.swift
//  Hayase
//
//  Mirrors: src/routes/app/settings/interface/+page.svelte: the sections of the Interface settings page.
//

import Foundation

extension SettingsSectionCatalog {
    static let interfaceSections: [Section] = [
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
    ]
}
