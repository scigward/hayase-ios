//
//  SettingsAppPage.swift
//  Hayase
//
//  Mirrors: src/routes/app/settings/app/+page.svelte: the sections of the App settings page.
//

import Foundation

extension SettingsSectionCatalog {
    static let appSections: [Section] = [
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
    ]
}
