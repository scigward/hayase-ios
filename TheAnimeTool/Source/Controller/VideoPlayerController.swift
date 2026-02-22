//
//  VideoPlayerController.swift
//  FinalProject
//
//  Created by Tieria C.Monk on 8/18/16.
//
//

import AVKit
import LibTorrent

/// Matches Hayase's player.svelte capabilities:
/// - Picture-in-Picture (pip.ts: allowsPictureInPicturePlayback)
/// - Episode title in nav bar / Lock Screen
/// - Download stats overlay (downloadstats.svelte) while file is still buffering
/// - Playback speed control (speed.svelte: 0.5× … 2×)
/// - AirPlay / Route Picker (standard AVRoutePickerView)
class VideoPlayerController: AVPlayerViewController {
    var videoEntity: Videos? = nil
    /// The active LibTorrent handle for this torrent (used for live stats overlay).
    var torrentHandle: TorrentHandle? = nil
    /// Index of the file being played inside the torrent (for per-file stats).
    var fileIndex: UInt = 0

    /// The currently selected playback rate; applied when AVPlayer starts.
    var selectedRate: Float = 1.0

    private var statsTimer: Timer?
    private var statsOverlay: UILabel?
    private weak var speedButton: UIButton?

    override func viewDidLoad() {
        super.viewDidLoad()
        // Hayase pip.ts: PiP is a first-class feature
        allowsPictureInPicturePlayback = true
        // Episode title from video entity name
        if let name = videoEntity?.videoName, !name.isEmpty {
            title = name
        }
        setupSpeedControl()
        setupAirPlayButton()
        guard let videoPath = videoEntity?.videoPath else { return }
        let url = URL(fileURLWithPath: videoPath)
        DispatchQueue.global(qos: .default).async {
            let player = AVPlayer(url: url)
            DispatchQueue.main.async {
                self.player = player
                player.play()
                // Apply user-selected speed (play() resets rate to 1.0)
                if self.selectedRate != 1.0 { player.rate = self.selectedRate }
                self.setupDownloadStatsOverlay()
            }
        }
    }

    // MARK: - Speed control (Hayase speed.svelte)

    private func setupSpeedControl() {
        let button = UIButton(type: .system)
        button.setTitle("1×", for: .normal)
        button.titleLabel?.font = .monospacedSystemFont(ofSize: 14, weight: .semibold)
        button.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        button.tintColor = .white
        button.layer.cornerRadius = 6
        button.clipsToBounds = true
        button.translatesAutoresizingMaskIntoConstraints = false
        let speeds: [(String, Float)] = [
            ("0.5×", 0.5), ("0.75×", 0.75), ("1×", 1.0),
            ("1.25×", 1.25), ("1.5×", 1.5), ("2×", 2.0),
        ]
        let actions = speeds.map { label, rate -> UIAction in
            UIAction(title: label, state: rate == self.selectedRate ? .on : .off) { [weak self, weak button] _ in
                self?.selectedRate = rate
                self?.player?.rate = rate
                button?.setTitle(label, for: .normal)
            }
        }
        button.menu = UIMenu(title: "Playback Speed", children: actions.reversed())
        button.showsMenuAsPrimaryAction = true
        view.addSubview(button)
        NSLayoutConstraint.activate([
            button.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            button.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 8),
            button.widthAnchor.constraint(equalToConstant: 46),
            button.heightAnchor.constraint(equalToConstant: 30),
        ])
        speedButton = button
    }

    // MARK: - AirPlay route picker

    private func setupAirPlayButton() {
        let picker = AVRoutePickerView()
        picker.activeTintColor = .systemIndigo
        picker.tintColor = .white
        picker.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        picker.layer.cornerRadius = 6
        picker.clipsToBounds = true
        picker.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(picker)
        let leadingAnchor = speedButton?.trailingAnchor ?? view.safeAreaLayoutGuide.leadingAnchor
        NSLayoutConstraint.activate([
            picker.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            picker.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            picker.widthAnchor.constraint(equalToConstant: 36),
            picker.heightAnchor.constraint(equalToConstant: 30),
        ])
    }

    // MARK: - Download stats overlay (Hayase downloadstats.svelte)

    /// Shows a small HUD in the top-right corner with live download speed + buffer %
    /// while the file is still being downloaded. Auto-hides when download completes.
    private func setupDownloadStatsOverlay() {
        guard let handle = torrentHandle else { return }
        let snap = handle.snapshot
        // Only show overlay if the torrent is still actively downloading
        guard !snap.isFinished, !snap.isSeed, snap.progress < 1.0 else { return }

        let label = UILabel()
        label.font = .monospacedSystemFont(ofSize: 10, weight: .medium)
        label.textColor = .white
        label.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        label.layer.cornerRadius = 5
        label.clipsToBounds = true
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -8),
        ])
        statsOverlay = label

        updateStats()
        statsTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.updateStats()
        }
    }

    private func updateStats() {
        guard let handle = torrentHandle, let label = statsOverlay else { return }
        let snap = handle.snapshot
        if snap.isFinished || snap.isSeed || snap.progress >= 1.0 {
            // Download complete — hide the overlay
            statsTimer?.invalidate()
            statsTimer = nil
            label.removeFromSuperview()
            statsOverlay = nil
            return
        }
        let speed = Self.fmtSpeed(snap.downloadRate)
        let pct   = String(format: "%.1f%%", snap.progress * 100)
        label.text = "  ↓ \(speed)  \(pct)  "
    }

    /// Formats bytes/sec as a compact human-readable string ("3.2 MB/s", "512 KB/s").
    private static func fmtSpeed(_ bps: UInt64) -> String {
        if bps == 0 { return "0 B/s" }
        if bps >= 1_073_741_824 { return String(format: "%.1f GB/s", Double(bps) / 1_073_741_824) }
        if bps >= 1_048_576    { return String(format: "%.1f MB/s", Double(bps) / 1_048_576) }
        if bps >= 1_024        { return String(format: "%.0f KB/s", Double(bps) / 1_024) }
        return "\(bps) B/s"
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        statsTimer?.invalidate()
        statsTimer = nil
    }

    deinit {
        statsTimer?.invalidate()
    }
}
