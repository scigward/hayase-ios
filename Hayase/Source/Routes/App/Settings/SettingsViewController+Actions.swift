// Mirrors: src/routes/app/settings/{app,interface,client}/+page.svelte
import UIKit
import UniformTypeIdentifiers

extension SettingsViewController {
    func confirmScaleChange() {
        guard let pendingScale, abs(pendingScale - Settings.uiScale) > 0.001 else { return }
        if previousScale == nil { previousScale = Settings.uiScale }
        Settings.uiScale = pendingScale
        HayaseInterfaceScale.apply(pendingScale)

        scaleTimer?.invalidate()
        scaleAlert?.dismiss(animated: false)
        scaleCountdown = 10
        let alert = SettingsDialogViewController(title: "Keep this UI scale?", maximumWidth: 448)
        let message = SettingsTypography.label(scaleConfirmationMessage, size: 14, lineHeight: 20,
            color: UIColor.HayaseTheme.mutedForeground)
        scaleMessageLabel = message
        alert.content.addArrangedSubview(message)
        let revert = SettingsTypography.button("Revert", destructive: true)
        revert.addAction(UIAction { [weak self] _ in
            self?.revertScaleChange()
        }, for: .touchUpInside)
        let keep = SettingsTypography.button("Keep Changes")
        keep.addAction(UIAction { [weak self] _ in
            self?.keepScaleChange()
        }, for: .touchUpInside)
        let actions = UIStackView(arrangedSubviews: [UIView(), revert, keep])
        actions.spacing = 8
        alert.content.addArrangedSubview(actions)
        alert.onClose = { [weak self] in self?.revertScaleChange() }
        scaleAlert = alert
        present(alert, animated: false)
        scaleTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.scaleCountdown -= 1
            if self.scaleCountdown <= 0 {
                self.revertScaleChange()
            } else {
                self.scaleMessageLabel?.text = self.scaleConfirmationMessage
            }
        }
    }

    var scaleConfirmationMessage: String {
        "The interface zoom has been changed. Reverting to the previous scale in \(scaleCountdown) seconds."
    }

    func keepScaleChange() {
        scaleTimer?.invalidate()
        scaleTimer = nil
        previousScale = nil
        pendingScale = nil
        scaleAlert?.dismiss(animated: false)
        scaleAlert = nil
    }

    func revertScaleChange() {
        scaleTimer?.invalidate()
        scaleTimer = nil
        if let previousScale {
            Settings.uiScale = previousScale
            HayaseInterfaceScale.apply(previousScale)
        }
        previousScale = nil
        pendingScale = nil
        scaleAlert?.dismiss(animated: false)
        scaleAlert = nil
        if isViewLoaded { reloadContent() }
    }

    // MARK: - Helpers

    /// Keys whose changes must be forwarded to the active torrent backend.
    /// Mirrors Hayase's `torrentSettings` derived store that triggers `native.updateSettings`.
    static let torrentSettingKeys: Set<String> = [
        TorrentBackendKind.userDefaultsKey,
        "pref_disableDHT", "pref_disablePeX",
        "pref_torrentPort", "pref_dhtPort",
        "pref_torrentSpeed", "pref_maxConns",
        "pref_torrentLocation", "pref_nzbDomain", "pref_nzbLogin",
        "pref_nzbPassword", "pref_nzbPort", "pref_nzbPoolSize",
        Settings.Keys.streamedDownload, Settings.Keys.persistFiles,
    ]

    /// If `key` is a torrent-session setting, re-apply settings to the live session.
    func applyTorrentSettingsIfNeeded(forKey key: String) {
        if Self.torrentSettingKeys.contains(key) {
            if key == TorrentBackendKind.userDefaultsKey {
                TorrentBackendManager.shared.backendSelectionDidChange()
            } else {
                TorrentBackendManager.shared.applyCurrentSettings()
            }
        }
    }

    func showSelectionPicker(title: String, key: String, options: [(key: String, label: String)],
                             defaultKey: String, anchor: ComboBox) {
        let picker = CommandPopoverViewController(
            title: title, placeholder: "Search...",
            groups: [CommandGroup(options: options.map { CommandOption(value: $0.key, label: $0.label) })],
            selectedValues: [UserDefaults.standard.string(forKey: key) ?? defaultKey],
            allowsMultiple: false, sourceView: anchor)
        picker.onSelectionChanged = { [weak self, weak anchor] values in
            guard let value = values.first else { return }
            Settings.write(value, forKey: key)
            anchor?.configure(text: options.first(where: { $0.key == value })?.label ?? value, placeholder: false)
            self?.applyTorrentSettingsIfNeeded(forKey: key)
            if key == "pref_torrentLocation" { self?.reloadContent() }
        }
        present(picker, animated: false)
    }

    // The web settings use inline inputs. Commit on editing end so the active
    // torrent session is updated without replacing the editing cell.
    func commitInput(_ value: String, key: String, fallback: String,
                             numericRange: ClosedRange<Int>?, allowsFraction: Bool = false) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let result: String
        if let range = numericRange {
            if allowsFraction, let number = Double(trimmed), number.isFinite {
                result = String(Swift.min(Swift.max(number, Double(range.lowerBound)), Double(range.upperBound)))
            } else if let number = Int(trimmed) {
                result = String(Swift.min(Swift.max(number, range.lowerBound), range.upperBound))
            } else {
                return UserDefaults.standard.string(forKey: key) ?? fallback
            }
        } else {
            result = trimmed
        }
        Settings.write(result, forKey: key)
        applyTorrentSettingsIfNeeded(forKey: key)
        return result
    }

    // MARK: - Action handling

    func handleAction(title: String) {
        switch title {
        case "Import Settings From File":
            let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.json], asCopy: true)
            picker.delegate = self
            present(picker, animated: true)
        case "Export Settings To File":
            exportSettings()
        case "Reset Everything To Default", "Reset EVERYTHING To Default":
            let alert = UIAlertController(title: "Reset Everything?",
                                          message: "This will reset ALL settings and data to their default values. This cannot be undone.",
                                          preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Reset", style: .destructive) { [weak self] _ in
                SettingsFileService.resetPreferences()
                TorrentBackendManager.shared.applyCurrentSettings()
                HayaseInterfaceScale.apply()
                self?.reloadContent()
            })
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            present(alert, animated: true)
        default:
            break
        }
    }

    func exportSettings() {
        guard let data = try? SettingsFileService.exportData() else {
            presentMessage(title: "Export Failed", message: "The current settings could not be encoded.")
            return
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("hayase-settings.json")
        do {
            try data.write(to: url, options: .atomic)
            let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            if let popover = activity.popoverPresentationController {
                popover.sourceView = view
                popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
            }
            present(activity, animated: true)
        } catch {
            presentMessage(title: "Export Failed", message: error.localizedDescription)
        }
    }

    func importSettings(from url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            try SettingsFileService.importData(data)
            TorrentBackendManager.shared.applyCurrentSettings()
            HayaseInterfaceScale.apply()
            reloadContent()
            presentMessage(title: "Settings Imported", message: "Your settings were imported successfully.")
        } catch {
            presentMessage(title: "Import Failed", message: error.localizedDescription)
        }
    }

    func presentMessage(title: String, message: String) {
        SettingsToast.show(title + "\n" + message, in: view)
    }

    func controlWidth(for row: Row) -> CGFloat {
        switch row.title {
        case "Title Language":
            return 240
        case "Preferred Subtitle Language", "Preferred Audio Language":
            return 144
        case "DNS Over HTTPS URL", "Provider Domain", "Provider Login", "Provider Password":
            return 320
        default:
            return 128
        }
    }

    func loadChangelogIfNeeded() {
        guard changelogEntries == nil, changelogError == nil else { return }
        SettingsChangelogService.shared.load { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let entries): self.changelogEntries = entries
            case .failure(let error): self.changelogError = error.localizedDescription
            }
            guard self.settingsRoute == .changelog, self.isViewLoaded else { return }
            self.reloadContent()
        }
    }
}

extension SettingsViewController: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        importSettings(from: url)
    }
}
