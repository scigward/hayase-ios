// Mirrors: src/routes/app/settings/accounts/+page.svelte (account settings dialogs)
import UIKit

extension HayaseAccountCardView {
    // MARK: - Settings dialogs

    func showAniListSettings() {
        let dialog = SettingsDialogViewController(title: "AniList Settings", maximumWidth: 896)
        dialog.panelColor = UIColor.HayaseTheme.background   // bg-background
        let viewer = TrackerAccountManager.shared.viewer(for: .anilist)
        let languages = [
            ("ROMAJI", "Romaji (Shingeki no Kyojin)"), ("ENGLISH", "English (Attack on Titan)"),
            ("NATIVE", "Native (進撃の巨人)"), ("ROMAJI_STYLISED", "Romaji Stylised"),
            ("ENGLISH_STYLISED", "English Stylised"), ("NATIVE_STYLISED", "Native Stylised"),
        ]
        let language = ComboBox(frame: .zero)
        let current = viewer?.titleLanguage ?? "ROMAJI"
        language.configure(text: languages.first(where: { $0.0 == current })?.1 ?? current, placeholder: false)
        language.isEnabled = viewer != nil
        let width = language.widthAnchor.constraint(equalToConstant: 240)
        width.priority = .defaultHigh
        width.isActive = true
        language.addAction(UIAction { [weak dialog, weak language] _ in
            guard let language else { return }
            let picker = CommandPopoverViewController(title: "Title Language", placeholder: "Search...",
                groups: [CommandGroup(options: languages.map { CommandOption(value: $0.0, label: $0.1) })],
                selectedValues: [TrackerAccountManager.shared.viewer(for: .anilist)?.titleLanguage ?? "ROMAJI"],
                allowsMultiple: false, sourceView: language)
            picker.onSelectionChanged = { [weak language] values in
                guard let value = values.first else { return }
                AniListClient.shared.updateUserResult(titleLanguage: value) { result in
                    switch result {
                    case .success(let viewer):
                        language?.configure(text: languages.first(where: { $0.0 == viewer.titleLanguage })?.1 ?? value, placeholder: false)
                    case .failure(let error): NSLog("[Settings] Failed to update language: %@", error.localizedDescription)
                    }
                }
            }
            dialog?.present(picker, animated: false)
        }, for: .touchUpInside)
        dialog.content.addArrangedSubview(SettingsCardView(title: "Title Language",
            description: "What language should anime titles be displayed in.", control: language))
        let adult = HayaseSwitch()
        adult.setOn(viewer?.displayAdultContent ?? false, animated: false)
        adult.isEnabled = viewer != nil
        adult.addAction(UIAction { [weak adult] _ in
            guard let adult else { return }
            AniListClient.shared.updateUserResult(displayAdultContent: adult.isOn) { [weak adult] result in
                adult?.setOn(TrackerAccountManager.shared.viewer(for: .anilist)?.displayAdultContent ?? false, animated: true)
                if case .failure(let error) = result {
                    NSLog("[Settings] Failed to update NSFW setting: %@", error.localizedDescription)
                }
            }
        }, for: .valueChanged)
        dialog.content.addArrangedSubview(SettingsCardView(title: "18+ Content",
            description: "Shows/Hides ALL 18+ content when logged into AniList. This includes lists, recommendations, search results, relations and more.",
            control: adult))
        dialog.content.addArrangedSubview(clientIDCard(service: "AniList", value: AniListAuth.clientID, width: 128) {
            AniListAuth.clientID = $0
        })
        parentVC?.present(dialog, animated: false)
    }

    func showMALSettings() {
        let dialog = SettingsDialogViewController(title: "MyAnimeList Settings", maximumWidth: 896)
        dialog.panelColor = UIColor.HayaseTheme.background   // bg-background
        dialog.content.addArrangedSubview(clientIDCard(service: "MyAnimeList", value: MALAuth.clientID, width: 384) {
            MALAuth.clientID = $0
        })
        parentVC?.present(dialog, animated: false)
    }

    private func clientIDCard(service: String, value: String, width: CGFloat,
                              onChange: @escaping (String) -> Void) -> UIView {
        let input = SettingsInputControl(value: value, placeholder: "\(service) Client ID", width: width,
            numeric: service == "AniList")
        input.onChange = onChange
        return SettingsCardView(title: "Client ID",
            description: "The Client ID used for \(service) authentication and API access. Change this if you want to use your own, or if the default one stops working.",
            control: input)
    }

    func showSimklSettings() {
        let dialog = SettingsDialogViewController(title: "Simkl Settings", maximumWidth: 896)
        dialog.panelColor = UIColor.HayaseTheme.background   // bg-background
        let identifier = SettingsInputControl(value: SimklAuth.clientID, placeholder: "Simkl Client ID", width: 384)
        identifier.onChange = { SimklAuth.clientID = $0 }
        let secret = SettingsInputControl(value: SimklAuth.clientSecret, placeholder: "Simkl Client Secret", width: 384, secure: true)
        secret.onChange = { SimklAuth.clientSecret = $0 }
        dialog.content.addArrangedSubview(SettingsCardView(title: "Client ID",
            description: "Required for authentication. Get yours at https://simkl.com/settings/developer/new", control: identifier))
        dialog.content.addArrangedSubview(SettingsCardView(title: "Client Secret",
            description: "Required for token exchange. Found in the same Simkl dev app settings.", control: secret))
        parentVC?.present(dialog, animated: false)
    }
}
