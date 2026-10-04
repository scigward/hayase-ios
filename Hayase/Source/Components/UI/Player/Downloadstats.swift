//
//  Downloadstats.swift
//  Hayase
//
//  Mirrors: src/lib/components/ui/player/downloadstats.svelte: the peers, the download speed and the upload speed of
//  the torrent that are over the video, which are asked for while it plays.
//

import UIKit
import AVKit
import CoreMedia
import UniformTypeIdentifiers

extension VideoPlayerViewController {
    /// Hayase downloadstats.svelte — floating HUD at top center showing
    /// peers, download speed + upload speed.
    /// Positioned at top center like the Hayase web player.
    /// Added to the overlay so it fades out with controls when the user
    /// is inactive — matching Hayase's `class:opacity-0={immersed}`.
    func setupStatsHUD() {
        statsHUD.translatesAutoresizingMaskIntoConstraints = false
        statsHUD.axis = .horizontal
        statsHUD.spacing = 16
        statsHUD.alignment = .center
        statsHUD.isUserInteractionEnabled = false // downloadstats.svelte pointer-events-none
        statsHUD.isHidden = true
        // text-shadow-lg is drawn by the labels; SVGs use drop-shadow.

        statsHUD.addArrangedSubview(makeStatsHUDItem(icon: "users", label: statsPeersLabel))
        statsHUD.addArrangedSubview(makeStatsHUDItem(icon: "chevron-down", label: statsDownLabel))
        statsHUD.addArrangedSubview(makeStatsHUDItem(icon: "chevron-up", label: statsUpLabel))

        overlay.addSubview(statsHUD)
        NSLayoutConstraint.activate([
            statsHUD.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            statsHUD.centerXAnchor.constraint(equalTo: view.centerXAnchor),
        ])
    }

    func makeStatsHUDItem(icon: String, label: TextShadowLabel) -> UIStackView {
        // Tailwind drop-shadow chains two filters; the wrapper shadows the
        // icon plus its first shadow, while its alignment box stays 18pt.
        let iconContainer = UIView()
        iconContainer.translatesAutoresizingMaskIntoConstraints = false
        iconContainer.layer.shadowColor = UIColor.black.cgColor
        iconContainer.layer.shadowOpacity = 0.06
        iconContainer.layer.shadowOffset = CGSize(width: 0, height: 1)
        iconContainer.layer.shadowRadius = 1
        let imageView = UIImageView(image: UIImage.hayaseIcon(icon, pointSize: 18))
        imageView.tintColor = UIColor.HayaseTheme.foreground
        imageView.contentMode = .scaleAspectFit
        imageView.layer.shadowColor = UIColor.black.cgColor
        imageView.layer.shadowOpacity = 0.1
        imageView.layer.shadowOffset = CGSize(width: 0, height: 1)
        imageView.layer.shadowRadius = 2
        imageView.translatesAutoresizingMaskIntoConstraints = false
        iconContainer.addSubview(imageView)
        NSLayoutConstraint.activate([
            iconContainer.widthAnchor.constraint(equalToConstant: 18),
            iconContainer.heightAnchor.constraint(equalToConstant: 18),
            imageView.leadingAnchor.constraint(equalTo: iconContainer.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: iconContainer.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: iconContainer.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: iconContainer.bottomAnchor),
        ])

        label.font = .nunito(ofSize: 18, weight: .bold)
        label.lineHeight = 28
        label.usesFixedLineBox = true
        label.textColor = UIColor.HayaseTheme.foreground
        label.setContentHuggingPriority(.required, for: .horizontal)

        let stack = UIStackView(arrangedSubviews: [iconContainer, label])
        stack.axis = .horizontal
        stack.spacing = 8
        stack.alignment = .center
        return stack
    }

    func resumeStatsUpdates() {
        startStatsTimer()
    }

    func startStatsTimer() {
        statsTimer?.invalidate()
        startCastDisplaysTimer()
        guard isWebTorrentPlayback else { return }
        statsHUD.isHidden = Settings.minimalPlayerUI
        updateWebTorrentStats()
        let timer = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.updateWebTorrentStats()
        }
        RunLoop.main.add(timer, forMode: .common)
        statsTimer = timer
    }

    var isWebTorrentPlayback: Bool {
        guard videoEntity?.torrents != nil,
              let path = videoEntity?.videoPath?.lowercased() else { return false }
        return path.hasPrefix("http://") || path.hasPrefix("https://")
    }

    func updateWebTorrentStats() {
        guard isWebTorrentPlayback, !webStatsUpdateInFlight else { return }
        webStatsUpdateInFlight = true

        // The bridge status endpoint is the reliable live source for player HUD
        // counters. torrentInfo can legitimately lag while metadata is being
        // refreshed, which used to leave webStatsUpdateInFlight stuck or show
        // stale/zero values until a seek or pause kicked the player again.
        TorrentBackendManager.shared.webTorrentStatus { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.webStatsUpdateInFlight = false
                guard case .success(let status) = result else { return }
                self.applyWebTorrentStats(peers: status.wires,
                                           downloadSpeed: status.downloadSpeed ?? 0,
                                           uploadSpeed: status.uploadSpeed ?? 0)
                // The cast request returns at once; how the session went is reported in the status.
                if let display = self.activeCastDisplay, let message = status.cast?[display.host]?.error {
                    self.showCastError(message)
                }
            }
        }
    }

    func applyWebTorrentStats(peers: Int, downloadSpeed: UInt64, uploadSpeed: UInt64) {
        statsHUD.isHidden = Settings.minimalPlayerUI
        statsPeersLabel.content = "\(peers)"
        statsDownLabel.content = "\(fmtBits(downloadSpeed * 8))/s"
        statsUpLabel.content = "\(fmtBits(uploadSpeed * 8))/s"
    }

    /// Formats bits per second into a human-readable string (Hayase fastPrettyBits).
    func fmtBits(_ bps: UInt64) -> String {
        guard bps > 0 else { return "0 b" }
        let units = [" b", " kb", " Mb", " Gb", " Tb"]
        let exponent = min(Int(floor(log10(Double(bps)) / 3)), units.count - 1)
        let value = (Double(bps) / pow(1000, Double(exponent)) * 10).rounded() / 10
        // fastPrettyBits converts toFixed(1) back to Number: 27 Mb, not
        // 27.0 Mb, and 59 kb, not 59 Kb. Keep the HUD's intrinsic width equal.
        let number = value.rounded() == value ? String(format: "%.0f", value) : String(format: "%.1f", value)
        return number + units[exponent]
    }
}
