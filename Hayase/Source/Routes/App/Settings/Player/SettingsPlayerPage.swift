//
//  SettingsPlayerPage.swift
//  Hayase
//
//  Mirrors: src/routes/app/settings/player/+page.svelte: the sections of the Player settings page.
//

import Foundation

extension SettingsSectionCatalog {
    static let playerSections: [Section] = [
        Section(header: "Subtitle Settings", rows: [
            Row(title: "Subtitle Render Resolution Limit",
                description: "Max resolution to render subtitles at. If your resolution is higher than this setting the subtitles will be upscaled lineary. This will GREATLY improve rendering speeds for complex typesetting for slower devices. It's best to lower this on mobile devices which often have high pixel density where their effective resolution might be ~1440p while having small screens and slow processors.",
                kind: .selectable(userDefaultsKey: Settings.Keys.subtitleRenderHeight, options: Self.subtitleResolutions, defaultKey: Settings.Defaults.subtitleRenderHeight)),
            Row(title: "Subtitle Dialogue Style Overrides",
                description: "Selectively override the default dialogue style for subtitles. This will not change the style of typesetting [Fancy 3D Signs and Songs].\n\nWarning: the heuristic used for deciding when to override the style is rather rough, and enabling this option can lead to incorrectly rendered subtitles.",
                kind: .previewGrid(.subtitleStyle)),
        ], tab: .player),

        Section(header: "Language Settings", rows: [
            Row(title: "Preferred Subtitle Language",
                description: "What subtitle language to automatically select when a video is loaded if it exists. This won't find torrents with this language automatically. If not found defaults to English.",
                kind: .selectable(userDefaultsKey: Settings.Keys.subtitleLanguage, options: Self.languageCodes, defaultKey: Settings.Defaults.subtitleLanguage)),
            Row(title: "Preferred Audio Language",
                description: "What audio language to automatically select when a video is loaded if it exists. This won't find torrents with this language automatically. If not found defaults to Japanese.",
                kind: .selectable(userDefaultsKey: Settings.Keys.audioLanguage, options: Self.languageCodes, defaultKey: Settings.Defaults.audioLanguage)),
        ], tab: .player),

        Section(header: "Playback Settings", rows: [
            Row(title: "Auto-Play Next Episode",
                description: "Automatically starts playing next episode when a video ends.",
                kind: .toggle(userDefaultsKey: Settings.Keys.playerAutoplay, defaultValue: Settings.Defaults.playerAutoplay)),
            Row(title: "Pause On Lost Visibility",
                description: "Pauses/Resumes video playback when the app loses visibility.",
                kind: .toggle(userDefaultsKey: Settings.Keys.playerPause, defaultValue: Settings.Defaults.playerPause)),
            Row(title: "PiP On Lost Visibility",
                description: "Automatically enters Picture in Picture mode when the app loses visibility.",
                kind: .toggle(userDefaultsKey: Settings.Keys.playerAutoPiP, defaultValue: Settings.Defaults.playerAutoPiP)),
            Row(title: "Auto-Complete Episodes",
                description: "Automatically marks episodes as complete when you finish watching them. Requires Account login.",
                kind: .toggle(userDefaultsKey: Settings.Keys.autocomplete, defaultValue: Settings.Defaults.autocomplete)),
            Row(title: "Deband Video",
                description: "Reduces banding [compression artifacts] on dark and compressed videos. High performance impact. Recommended for seasonal web releases, not recommended for high quality blu-ray videos.",
                kind: .toggle(userDefaultsKey: Settings.Keys.deband, defaultValue: Settings.Defaults.deband)),
            Row(title: "Seek Duration",
                description: "Seconds to skip forward or backward when using the seek buttons or keyboard shortcuts. Higher values might negatively impact buffering speeds.",
                kind: .editableNumber(userDefaultsKey: Settings.Keys.seekDuration, defaultValue: Settings.Defaults.seekDuration, suffix: "sec", min: 1, max: 50)),
            Row(title: "Auto-Skip Intro/Outro",
                description: "Attempt to automatically skip intro and outro. This WILL sometimes skip incorrect chapters, as some of the chapter data is community sourced.",
                kind: .toggle(userDefaultsKey: Settings.Keys.playerSkip, defaultValue: Settings.Defaults.playerSkip)),
            Row(title: "Auto-Skip Filler",
                description: "Automatically skip filler episodes. This WILL skip ENTIRE episodes.",
                kind: .toggle(userDefaultsKey: Settings.Keys.skipFiller, defaultValue: Settings.Defaults.skipFiller)),
        ], tab: .player),

        Section(header: "Interface Settings", rows: [
            Row(title: "Minimal UI",
                description: "Forces minimalistic player UI, hides controls.",
                kind: .toggle(userDefaultsKey: Settings.Keys.minimalPlayerUI, defaultValue: Settings.Defaults.minimalPlayerUI)),
        ], tab: .player),
    ]
}
