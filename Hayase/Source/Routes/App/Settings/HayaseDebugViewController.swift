//
//  HayaseDebugViewController.swift
//  Hayase
//
//  Native counterpart of src/routes/app/debug/+page.svelte.
//

import UIKit
import AVFoundation

final class HayaseDebugViewController: UIViewController {
    private let stack = UIStackView()
    private static let routeTransition = HayaseRouteTransition()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.HayaseTheme.background
        navigationController?.setNavigationBarHidden(true, animated: false)

        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)

        let back = UIButton(type: .system)
        back.setImage(UIImage.hayaseIcon("arrow-left"), for: .normal)
        back.tintColor = UIColor.HayaseTheme.foreground
        back.contentHorizontalAlignment = .leading
        back.addTarget(self, action: #selector(close), for: .touchUpInside)
        back.heightAnchor.constraint(equalToConstant: 32).isActive = true
        stack.addArrangedSubview(back)

        let title = UILabel()
        title.text = "Debug Page"
        title.font = .nunito(ofSize: 24, weight: .bold)
        title.textColor = UIColor.HayaseTheme.foreground
        stack.addArrangedSubview(title)

        let subtitle = UILabel()
        subtitle.text = "If you're here because you're looking for support with Hayase, you're in the right place!"
        subtitle.font = .nunito(ofSize: 14)
        subtitle.textColor = UIColor.HayaseTheme.mutedForeground
        subtitle.numberOfLines = 0
        stack.addArrangedSubview(subtitle)

        stack.addArrangedSubview(makeCard(
            title: "App and Device Info",
            description: "Save app and device debug info and capabilities, such as version information and settings to a file.",
            action: #selector(saveDeviceInfo)
        ))
        stack.addArrangedSubview(makeCard(
            title: "Device Logs",
            description: "Save captured streaming, torrent, and player logs to a file. Check the contents before sharing because logs can contain sensitive information.",
            action: #selector(saveLogs)
        ))
        stack.addArrangedSubview(makeCard(
            title: "Copy App and Device Info",
            description: "Copy app version and device information to the clipboard.",
            action: #selector(copyDeviceInfo), buttonTitle: "Copy"
        ))
        stack.addArrangedSubview(makeCard(
            title: "Settings",
            description: "Save current settings to a file with account credentials redacted.",
            action: #selector(saveSettings)
        ))
        stack.addArrangedSubview(makeCard(
            title: "Torrent Capabilities",
            description: "Save the active torrent backend configuration and available device storage.",
            action: #selector(saveTorrentCapabilities)
        ))
        stack.addArrangedSubview(makeCard(
            title: "Media Capabilities",
            description: "Save native media-session and export capabilities for this device.",
            action: #selector(saveMediaCapabilities)
        ))
        stack.addArrangedSubview(makeCard(
            title: "Native Torrent Backend",
            description: "Switch between the native libtorrent and WebTorrent backends.",
            action: #selector(selectTorrentBackend), buttonTitle: "Select"
        ))
        stack.addArrangedSubview(makeCard(
            title: "Streaming Logger",
            description: "Configure the native streaming, torrent, and player logger.",
            action: #selector(configureStreamingLogger), buttonTitle: "Configure"
        ))
        stack.addArrangedSubview(makeCard(
            title: "Exclusive Audio Session",
            description: "Experiment: stop the player from making the audio session mixable, so other apps' audio no longer plays under the video. Applies from the next player.",
            action: #selector(configureExclusiveAudio), buttonTitle: "Configure"
        ))

        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -12),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -40),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -24),
        ])
    }

    private func makeCard(title: String, description: String, action: Selector,
                          buttonTitle: String = "Save") -> UIView {
        let card = UIView()
        card.backgroundColor = UIColor.HayaseTheme.muted
        card.layer.cornerRadius = 6

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .nunito(ofSize: 16, weight: .bold)
        titleLabel.textColor = UIColor.HayaseTheme.foreground
        let descriptionLabel = UILabel()
        descriptionLabel.text = description
        descriptionLabel.font = .nunito(ofSize: 12)
        descriptionLabel.textColor = UIColor.HayaseTheme.mutedForeground
        descriptionLabel.numberOfLines = 0
        let text = UIStackView(arrangedSubviews: [titleLabel, descriptionLabel])
        text.axis = .vertical
        text.spacing = 4

        let button = UIButton(type: .system)
        button.setTitle(buttonTitle, for: .normal)
        button.setTitleColor(UIColor.HayaseTheme.primaryForeground, for: .normal)
        button.titleLabel?.font = .nunito(ofSize: 14, weight: .bold)
        button.backgroundColor = UIColor.HayaseTheme.primary
        button.layer.cornerRadius = 6
        button.contentEdgeInsets = UIEdgeInsets(top: 9, left: 18, bottom: 9, right: 18)
        button.addTarget(self, action: action, for: .touchUpInside)
        button.setContentHuggingPriority(.required, for: .horizontal)

        let row = UIStackView(arrangedSubviews: [text, button])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            row.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 24),
            row.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -24),
            row.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16),
        ])
        return card
    }

    @objc private func close() {
        guard let navigationController else { return }
        Self.routeTransition.perform(in: navigationController.view) {
            navigationController.popViewController(animated: false)
        }
    }

    @objc private func saveDeviceInfo() {
        let info: [String: Any] = [
            "appVersion": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown",
            "build": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown",
            "systemName": UIDevice.current.systemName,
            "systemVersion": UIDevice.current.systemVersion,
            "deviceModel": UIDevice.current.model,
            "screen": "\(Int(UIScreen.main.bounds.width))x\(Int(UIScreen.main.bounds.height))@\(UIScreen.main.scale)x",
            "memoryBytes": ProcessInfo.processInfo.physicalMemory,
            "processorCount": ProcessInfo.processInfo.processorCount,
        ]
        shareJSON(info, name: "hayase-device-info")
    }

    @objc private func copyDeviceInfo() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        UIPasteboard.general.string = "Hayase v\(version) (\(build))\niOS \(UIDevice.current.systemVersion)\n\(UIDevice.current.model)\n"
    }

    @objc private func saveLogs() {
        let output = StreamingLogger.shared.entries.map(\.displayString).joined(separator: "\n")
        share(Data(output.utf8), name: "hayase-logs", extension: "log", errorTitle: "Failed to copy logs!")
    }

    @objc private func saveSettings() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        var values = UserDefaults.standard.persistentDomain(forName: bundleID) ?? [:]
        ["pref_nzbPassword", "pref_nzbLogin", "pref_simklClientSecret"].forEach {
            if values[$0] != nil { values[$0] = "***" }
        }
        values = values.filter { $0.key.hasPrefix("pref_") || $0.key.hasPrefix("tracker_sync_") }
        shareJSON(values, name: "hayase-settings")
    }

    @objc private func saveTorrentCapabilities() {
        var info = TorrentBackendSettings().dictionary()
        if let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first,
           let values = try? caches.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]) {
            info["availableStorageBytes"] = values.volumeAvailableCapacityForImportantUsage ?? 0
        }
        info["backend"] = TorrentBackendKind.current().rawValue
        shareJSON(info, name: "hayase-torrent-capabilities")
    }

    @objc private func saveMediaCapabilities() {
        let session = AVAudioSession.sharedInstance()
        let info: [String: Any] = [
            "sampleRate": session.sampleRate,
            "outputChannels": session.outputNumberOfChannels,
            "maximumOutputChannels": session.maximumOutputNumberOfChannels,
            "maximumFramesPerSecond": UIScreen.main.maximumFramesPerSecond,
            "exportPresets": AVAssetExportSession.allExportPresets(),
        ]
        shareJSON(info, name: "hayase-media-capabilities")
    }

    @objc private func selectTorrentBackend() {
        let options = TorrentBackendKind.settingsOptions
        let picker = CommandPopoverViewController(
            title: "Native Torrent Backend", placeholder: "Search...",
            groups: [CommandGroup(options: options.map {
                CommandOption(value: $0.key, label: $0.label)
            })],
            selectedValues: [TorrentBackendKind.current().rawValue],
            allowsMultiple: false, sourceView: view
        )
        picker.onSelectionChanged = { values in
            guard let value = values.first else { return }
            Settings.write(value, forKey: TorrentBackendKind.userDefaultsKey)
            TorrentBackendManager.shared.backendSelectionDidChange()
        }
        present(picker, animated: true)
    }

    @objc private func configureStreamingLogger() {
        presentEnableSheet(title: "Streaming Logger", key: "pref_showLogger")
    }

    @objc private func configureExclusiveAudio() {
        presentEnableSheet(title: "Exclusive Audio Session", key: "pref_audioExclusive")
    }

    private func presentEnableSheet(title: String, key: String) {
        let enabled = UserDefaults.standard.bool(forKey: key)
        let alert = UIAlertController(title: title,
                                      message: enabled ? "Currently enabled" : "Currently disabled",
                                      preferredStyle: .actionSheet)
        for option in [("Enable", true), ("Disable", false)] {
            alert.addAction(UIAlertAction(title: option.0, style: .default) { _ in
                Settings.write(option.1, forKey: key)
            })
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        if let popover = alert.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
        }
        present(alert, animated: true)
    }

    private func shareJSON(_ object: [String: Any], name: String) {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) else {
            showError("The debug data could not be encoded.")
            return
        }
        share(data, name: name, extension: "json")
    }

    private func share(_ data: Data, name: String, extension fileExtension: String,
                       errorTitle: String = "Failed to save file!") {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name).\(fileExtension)")
        do {
            try data.write(to: url, options: .atomic)
            let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            activity.completionWithItemsHandler = { _, _, _, error in
                guard let error else { return }
                DispatchQueue.main.async { AppErrorToast.show(error.localizedDescription, title: errorTitle) }
            }
            if let popover = activity.popoverPresentationController {
                popover.sourceView = view
                popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
            }
            present(activity, animated: true)
        } catch {
            AppErrorToast.show(error.localizedDescription, title: errorTitle)
        }
    }

    private func showError(_ message: String) {
        AppErrorToast.show(message, title: "Failed to save file!")
    }
}
