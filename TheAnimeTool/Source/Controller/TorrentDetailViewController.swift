// TorrentDetailViewController.swift
// TheAnimeTool
//
// Full replica of Hayase's overview.svelte:
//   header (name + status badge + hash), progress section (big% + bar + 3-stat grid),
//   Speed & Transfer (↓/↑), Time Information (ETA/Elapsed), Peers & Connections (S/L/P),
//   and a "View Files" button that pushes VideoListViewController.

import UIKit
import LibTorrent

final class TorrentDetailViewController: UIViewController {

    // MARK: - Properties

    var handle: TorrentHandle?
    var hexHash: String = ""
    var torrentEntity: Torrents?

    private var updateTimer: Timer?
    private let startDate = Date()

    // MARK: - Header labels

    private let nameLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 20, weight: .bold)
        l.textColor = .label
        l.numberOfLines = 3
        return l
    }()

    private let statusBadge: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 11, weight: .bold)
        l.textColor = .white
        l.textAlignment = .center
        l.layer.cornerRadius = 8
        l.clipsToBounds = true
        return l
    }()

    private let hashLabel: UILabel = {
        let l = UILabel()
        l.font = .monospacedSystemFont(ofSize: 9, weight: .regular)
        l.textColor = .tertiaryLabel
        l.numberOfLines = 1
        l.lineBreakMode = .byTruncatingMiddle
        return l
    }()

    // MARK: - Progress labels

    private let bigPercentLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 28, weight: .bold)
        l.textColor = .label
        return l
    }()

    private let progressBar = UIProgressView(progressViewStyle: .bar)

    // MARK: - Stat value labels

    private let downloadedValue  = TorrentDetailViewController.makeBigValue()
    private let uploadedValue    = TorrentDetailViewController.makeBigValue()
    private let totalSizeValue   = TorrentDetailViewController.makeBigValue()
    private let downSpeedValue   = TorrentDetailViewController.makeBigValue()
    private let upSpeedValue     = TorrentDetailViewController.makeBigValue()
    private let etaValue         = TorrentDetailViewController.makeBigValue()
    private let elapsedValue     = TorrentDetailViewController.makeBigValue()
    private let seedersValue     = TorrentDetailViewController.makeBigValue()
    private let leechersValue    = TorrentDetailViewController.makeBigValue()
    private let connectedValue   = TorrentDetailViewController.makeBigValue()

    private static func makeBigValue() -> UILabel {
        let l = UILabel()
        l.font = .systemFont(ofSize: 20, weight: .bold)
        l.textColor = .label
        return l
    }

    // MARK: - View Files button

    private lazy var viewFilesButton: UIButton = {
        let b = UIButton(type: .system)
        b.setTitle("  View Files", for: .normal)
        b.setImage(UIImage(systemName: "folder.fill"), for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        b.backgroundColor = .systemIndigo
        b.tintColor = .white
        b.layer.cornerRadius = 12
        b.contentEdgeInsets = UIEdgeInsets(top: 14, left: 20, bottom: 14, right: 20)
        b.addTarget(self, action: #selector(viewFilesTapped), for: .touchUpInside)
        return b
    }()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Download"
        view.backgroundColor = .systemGroupedBackground
        navigationController?.navigationBar.prefersLargeTitles = false
        setupProgressBar()
        buildScrollUI()
        update()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        startTimer()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopTimer()
    }

    deinit { stopTimer() }

    // MARK: - Timer

    private func startTimer() {
        stopTimer()
        updateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.update()
        }
    }

    private func stopTimer() {
        updateTimer?.invalidate()
        updateTimer = nil
    }

    // MARK: - Data update (matches overview.svelte live binding)

    private func update() {
        guard let snap = handle?.snapshot else { return }

        // Header
        nameLabel.text = snap.name.isEmpty ? "Unknown Torrent" : snap.name
        hashLabel.text = hexHash.isEmpty ? snap.name : hexHash

        // Use totalDone/total for the real download percentage.
        // snap.progress only counts "wanted" pieces (priority > 0), which
        // is unreliable when TorrentStreamer sets a narrow streaming window.
        let progress: Float = snap.total > 0 ? Float(Double(snap.totalDone) / Double(snap.total)) : 0
        let isComplete = snap.isSeed
        let isPaused   = snap.isPaused && !isComplete

        if isComplete {
            statusBadge.text = "  Seeding  "
            statusBadge.backgroundColor = .systemBlue
            progressBar.progressTintColor = .systemGreen
            bigPercentLabel.textColor = .systemGreen
            bigPercentLabel.text = "100%"
        } else if isPaused {
            statusBadge.text = "  Paused  "
            statusBadge.backgroundColor = .systemGray
            progressBar.progressTintColor = .systemGray
            bigPercentLabel.textColor = .secondaryLabel
            bigPercentLabel.text = String(format: "%.1f%%", progress * 100)
        } else {
            statusBadge.text = "  Downloading  "
            statusBadge.backgroundColor = .systemGreen
            progressBar.progressTintColor = .systemIndigo
            bigPercentLabel.textColor = .systemIndigo
            bigPercentLabel.text = String(format: "%.1f%%", progress * 100)
        }
        progressBar.progress = isComplete ? 1.0 : progress

        // Progress stats — use totalDone/total (not totalWantedDone/totalWanted)
        // for the same reason: "wanted" only counts prioritised pieces.
        downloadedValue.text = Self.fmtSize(snap.totalDone)
        let elapsed = Int(max(0, -startDate.timeIntervalSinceNow))
        // totalUploaded is not exposed by TorrentHandle.Snapshot; approximate from rate × session time
        uploadedValue.text  = elapsed > 0 && snap.uploadRate > 0
            ? "~\(Self.fmtSize(snap.uploadRate * UInt64(elapsed)))"
            : "—"
        totalSizeValue.text = Self.fmtSize(snap.total)

        // Speed & Transfer
        downSpeedValue.text = Self.fmtSpeed(snap.downloadRate)
        upSpeedValue.text   = Self.fmtSpeed(snap.uploadRate)

        // Time
        let remaining = snap.total > snap.totalDone
            ? snap.total - snap.totalDone : 0
        etaValue.text     = Self.fmtETA(remaining: remaining, rate: snap.downloadRate)
        elapsedValue.text = Self.fmtElapsed(elapsed)

        // Peers
        seedersValue.text   = "\(snap.numberOfSeeds)"
        leechersValue.text  = "\(snap.numberOfLeechers)"
        connectedValue.text = "\(snap.numberOfPeers)"
    }

    // MARK: - Actions

    @objc private func viewFilesTapped() {
        guard let vc = storyboard?.instantiateViewController(withIdentifier: "VideoListVC")
                as? VideoListViewController else { return }
        vc.torrentEntity = torrentEntity
        navigationController?.pushViewController(vc, animated: true)
    }

    // MARK: - UI construction

    private func setupProgressBar() {
        progressBar.layer.cornerRadius = 6
        progressBar.clipsToBounds = true
        progressBar.trackTintColor = .systemGray5
    }

    private func buildScrollUI() {
        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: scroll.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: scroll.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: scroll.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: scroll.bottomAnchor, constant: -24),
            stack.widthAnchor.constraint(equalTo: scroll.widthAnchor, constant: -32),
        ])

        // 1. Header
        stack.addArrangedSubview(makeHeaderView())

        // 2. Progress card
        stack.addArrangedSubview(makeCard(
            icon: "internaldrive.fill",
            iconColor: .systemIndigo,
            title: "Progress",
            content: makeProgressContent()
        ))

        // 3. Speed & Transfer card
        stack.addArrangedSubview(makeCard(
            icon: "wifi",
            iconColor: .systemBlue,
            title: "Speed & Transfer",
            content: makeStatGrid([
                .init(label: downSpeedValue, title: "Download", icon: "arrow.down", color: .systemGreen),
                .init(label: upSpeedValue,   title: "Upload",   icon: "arrow.up",   color: .systemBlue),
            ])
        ))

        // 4. Time Information card
        stack.addArrangedSubview(makeCard(
            icon: "clock",
            iconColor: .systemOrange,
            title: "Time Information",
            content: makeStatGrid([
                .init(label: etaValue,     title: "Remaining", icon: "hourglass.tophalf.filled", color: .systemOrange),
                .init(label: elapsedValue, title: "Elapsed",   icon: "timer",                    color: .systemPurple),
            ])
        ))

        // 5. Peers & Connections card
        stack.addArrangedSubview(makeCard(
            icon: "person.2.fill",
            iconColor: .systemTeal,
            title: "Peers & Connections",
            content: makeStatGrid([
                .init(label: seedersValue,   title: "Seeders",   icon: "person.fill.badge.plus",  color: .systemGreen),
                .init(label: leechersValue,  title: "Leechers",  icon: "person.fill.badge.minus", color: .systemRed),
                .init(label: connectedValue, title: "Connected", icon: "network",                 color: .systemPurple),
            ])
        ))

        // 6. View Files button
        viewFilesButton.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(viewFilesButton)
        viewFilesButton.heightAnchor.constraint(equalToConstant: 50).isActive = true
    }

    // MARK: - Section builders

    private func makeHeaderView() -> UIView {
        let badgeRow = hStack([statusBadge, spacer()])
        let v = vStack([nameLabel, badgeRow, hashLabel], spacing: 8)
        return v
    }

    private func makeProgressContent() -> UIView {
        let headerRow = hStack([
            icon("internaldrive.fill", .systemIndigo),
            subtitle("Downloaded"),
            spacer(),
            bigPercentLabel,
        ])
        progressBar.heightAnchor.constraint(equalToConstant: 12).isActive = true
        let grid = makeStatGrid([
            .init(label: downloadedValue, title: "Downloaded", icon: "arrow.down",    color: .systemGreen),
            .init(label: uploadedValue,   title: "Uploaded",   icon: "arrow.up",      color: .systemBlue),
            .init(label: totalSizeValue,  title: "Total",      icon: "internaldrive", color: .systemGray),
        ])
        return vStack([headerRow, progressBar, grid], spacing: 12)
    }

    // MARK: - Stat grid

    private struct StatItem {
        let label: UILabel
        let title: String
        let icon: String
        let color: UIColor
    }

    private func makeStatGrid(_ items: [StatItem]) -> UIView {
        let row = UIStackView(arrangedSubviews: items.map { makeStatCell($0) })
        row.axis = .horizontal
        row.distribution = .fillEqually
        row.spacing = 8
        return row
    }

    private func makeStatCell(_ item: StatItem) -> UIView {
        let container = UIView()
        container.backgroundColor = .tertiarySystemGroupedBackground
        container.layer.cornerRadius = 10
        container.clipsToBounds = true

        let iconLabel = hStack([icon(item.icon, item.color), subtitle(item.title)])
        let inner = vStack([iconLabel, item.label], spacing: 6)
        inner.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(inner)
        NSLayoutConstraint.activate([
            inner.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),
            inner.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
            inner.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            inner.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -10),
        ])
        return container
    }

    private func makeCard(icon iconName: String, iconColor: UIColor,
                          title cardTitle: String, content: UIView) -> UIView {
        let container = UIView()
        container.backgroundColor = .secondarySystemGroupedBackground
        container.layer.cornerRadius = 14
        container.clipsToBounds = true

        let header = hStack([icon(iconName, iconColor), sectionTitle(cardTitle)])
        let inner  = vStack([header, content], spacing: 16)
        inner.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(inner)
        NSLayoutConstraint.activate([
            inner.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
            inner.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            inner.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            inner.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -16),
        ])
        return container
    }

    // MARK: - UIView helpers

    private func vStack(_ views: [UIView], spacing: CGFloat = 8) -> UIStackView {
        let s = UIStackView(arrangedSubviews: views)
        s.axis = .vertical
        s.spacing = spacing
        return s
    }

    private func hStack(_ views: [UIView], spacing: CGFloat = 6) -> UIStackView {
        let s = UIStackView(arrangedSubviews: views)
        s.axis = .horizontal
        s.spacing = spacing
        s.alignment = .center
        return s
    }

    private func icon(_ name: String, _ color: UIColor) -> UIImageView {
        let iv = UIImageView(image: UIImage(systemName: name))
        iv.tintColor = color
        iv.contentMode = .scaleAspectFit
        iv.widthAnchor.constraint(equalToConstant: 16).isActive = true
        iv.heightAnchor.constraint(equalToConstant: 16).isActive = true
        return iv
    }

    private func sectionTitle(_ text: String) -> UILabel {
        let l = UILabel()
        l.text = text
        l.font = .systemFont(ofSize: 17, weight: .bold)
        l.textColor = .label
        return l
    }

    private func subtitle(_ text: String) -> UILabel {
        let l = UILabel()
        l.text = text
        l.font = .systemFont(ofSize: 11, weight: .medium)
        l.textColor = .secondaryLabel
        return l
    }

    private func spacer() -> UIView {
        let v = UIView()
        v.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return v
    }

    // MARK: - Format helpers (same logic as DownloadCell / overview.svelte utils)

    static func fmtSize(_ bytes: UInt64) -> String {
        if bytes == 0 { return "0 B" }
        if bytes >= 1_073_741_824 { return String(format: "%.1f GB", Double(bytes) / 1_073_741_824) }
        if bytes >= 1_048_576    { return String(format: "%.1f MB", Double(bytes) / 1_048_576) }
        if bytes >= 1_024        { return String(format: "%.0f KB", Double(bytes) / 1_024) }
        return "\(bytes) B"
    }

    static func fmtSpeed(_ bps: UInt64) -> String {
        if bps == 0 { return "0 B/s" }
        if bps >= 1_073_741_824 { return String(format: "%.1f GB/s", Double(bps) / 1_073_741_824) }
        if bps >= 1_048_576    { return String(format: "%.1f MB/s", Double(bps) / 1_048_576) }
        if bps >= 1_024        { return String(format: "%.0f KB/s", Double(bps) / 1_024) }
        return "\(bps) B/s"
    }

    static func fmtETA(remaining: UInt64, rate: UInt64) -> String {
        guard rate > 0, remaining > 0 else { return "∞" }
        let s = remaining / rate
        if s < 60   { return "\(s)s" }
        if s < 3600 { return "\(s/60)m \(s%60)s" }
        return "\(s/3600)h \(s%3600/60)m"
    }

    static func fmtElapsed(_ seconds: Int) -> String {
        if seconds <= 0  { return "0s" }
        if seconds < 60  { return "\(seconds)s" }
        if seconds < 3600 { return "\(seconds/60)m \(seconds%60)s" }
        return "\(seconds/3600)h \(seconds%3600/60)m"
    }
}
