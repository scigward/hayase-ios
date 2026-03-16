// TorrentDetailViewController.swift
// TheAnimeTool
//
// Full replica of Hayase's torrent client UI (overview.svelte).
// Provides three tabs via a segmented control:
//   - Overview: header, progress, speed/transfer, time, peers, protocol status
//   - Files: embeds VideoListViewController as a child VC
//   - Peers: simple peer/seed/leech summary

import UIKit
import LibTorrent

final class TorrentDetailViewController: UIViewController {

    // MARK: - Public properties (set by DownloadsViewController)

    var handle: TorrentHandle?
    var hexHash: String = ""
    var torrentEntity: Torrents?

    // MARK: - Private state

    private var updateTimer: Timer?
    private let startDate = Date()
    private var filesViewController: UIViewController?

    // MARK: - Segmented control & containers

    private let segmentedControl: UISegmentedControl = {
        let sc = UISegmentedControl(items: ["Overview", "Files", "Peers"])
        sc.selectedSegmentIndex = 0
        return sc
    }()

    private let containerView = UIView()

    private lazy var overviewScrollView: UIScrollView = {
        let sv = UIScrollView()
        sv.showsVerticalScrollIndicator = true
        sv.alwaysBounceVertical = true
        return sv
    }()

    private lazy var peersView: UIView = {
        let v = UIView()
        v.isHidden = true
        return v
    }()

    // MARK: - Overview: header labels

    private let nameLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 24, weight: .bold)
        l.textColor = .label
        l.numberOfLines = 2
        l.lineBreakMode = .byTruncatingTail
        return l
    }()

    private let statusBadge: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 12, weight: .bold)
        l.textColor = .white
        l.textAlignment = .center
        l.layer.cornerRadius = 10
        l.clipsToBounds = true
        return l
    }()

    private let hashLabel: UILabel = {
        let l = UILabel()
        l.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        l.textColor = .secondaryLabel
        l.numberOfLines = 1
        l.lineBreakMode = .byTruncatingMiddle
        return l
    }()

    // MARK: - Overview: progress section

    private let progressTitleLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 24, weight: .bold)
        l.textColor = .label
        l.text = "Progress"
        return l
    }()

    private let bigPercentLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 24, weight: .bold)
        l.textColor = .label
        return l
    }()

    private let progressBar: UIProgressView = {
        let pv = UIProgressView(progressViewStyle: .bar)
        pv.layer.cornerRadius = 6
        pv.clipsToBounds = true
        pv.trackTintColor = .secondarySystemFill
        return pv
    }()

    // MARK: - Overview: stat value labels

    private let downloadedValue  = TorrentDetailViewController.makeValueLabel()
    private let uploadedValue    = TorrentDetailViewController.makeValueLabel()
    private let totalSizeValue   = TorrentDetailViewController.makeValueLabel()
    private let piecesValue      = TorrentDetailViewController.makeValueLabel()

    private let downSpeedValue   = TorrentDetailViewController.makeValueLabel()
    private let upSpeedValue     = TorrentDetailViewController.makeValueLabel()
    private let etaValue         = TorrentDetailViewController.makeValueLabel()
    private let elapsedValue     = TorrentDetailViewController.makeValueLabel()
    private let seedersValue     = TorrentDetailViewController.makeValueLabel()
    private let leechersValue    = TorrentDetailViewController.makeValueLabel()
    private let wiresValue       = TorrentDetailViewController.makeValueLabel()

    // MARK: - Overview: protocol status dot labels

    private let dhtDot       = TorrentDetailViewController.makeDotLabel()
    private let lsdDot       = TorrentDetailViewController.makeDotLabel()
    private let pexDot       = TorrentDetailViewController.makeDotLabel()
    private let natDot       = TorrentDetailViewController.makeDotLabel()
    private let forwardDot   = TorrentDetailViewController.makeDotLabel()
    private let persistDot   = TorrentDetailViewController.makeDotLabel()
    private let streamingDot = TorrentDetailViewController.makeDotLabel()

    // MARK: - Peers tab labels

    private let peerSeedersValue  = TorrentDetailViewController.makeValueLabel()
    private let peerLeechersValue = TorrentDetailViewController.makeValueLabel()
    private let peerWiresValue    = TorrentDetailViewController.makeValueLabel()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Download"
        view.backgroundColor = .systemGroupedBackground
        navigationController?.navigationBar.prefersLargeTitles = false

        setupSegmentedControl()
        setupContainerView()
        buildOverviewUI()
        buildPeersUI()
        showTab(0)
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

    // MARK: - Segmented control

    private func setupSegmentedControl() {
        segmentedControl.translatesAutoresizingMaskIntoConstraints = false
        segmentedControl.addTarget(self, action: #selector(segmentChanged(_:)), for: .valueChanged)
        view.addSubview(segmentedControl)

        NSLayoutConstraint.activate([
            segmentedControl.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            segmentedControl.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            segmentedControl.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
        ])
    }

    private func setupContainerView() {
        containerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(containerView)

        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: segmentedControl.bottomAnchor, constant: 8),
            containerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    @objc private func segmentChanged(_ sender: UISegmentedControl) {
        showTab(sender.selectedSegmentIndex)
    }

    private func showTab(_ index: Int) {
        // Remove all child content
        overviewScrollView.removeFromSuperview()
        peersView.removeFromSuperview()
        removeFilesChild()

        switch index {
        case 0:
            overviewScrollView.isHidden = false
            containerView.addSubview(overviewScrollView)
            overviewScrollView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                overviewScrollView.topAnchor.constraint(equalTo: containerView.topAnchor),
                overviewScrollView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
                overviewScrollView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
                overviewScrollView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            ])
            update()

        case 1:
            embedFilesVC()

        case 2:
            peersView.isHidden = false
            containerView.addSubview(peersView)
            peersView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                peersView.topAnchor.constraint(equalTo: containerView.topAnchor),
                peersView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
                peersView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
                peersView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            ])
            updatePeersTab()

        default:
            break
        }
    }

    // MARK: - Files tab (child VC)

    private func embedFilesVC() {
        let sb = UIStoryboard(name: "Main", bundle: nil)
        guard let vc = sb.instantiateViewController(withIdentifier: "VideoListVC")
                as? VideoListViewController else { return }
        vc.torrentEntity = torrentEntity
        filesViewController = vc

        addChild(vc)
        vc.view.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(vc.view)
        NSLayoutConstraint.activate([
            vc.view.topAnchor.constraint(equalTo: containerView.topAnchor),
            vc.view.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            vc.view.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            vc.view.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
        ])
        vc.didMove(toParent: self)
    }

    private func removeFilesChild() {
        guard let vc = filesViewController else { return }
        vc.willMove(toParent: nil)
        vc.view.removeFromSuperview()
        vc.removeFromParent()
        filesViewController = nil
    }

    // MARK: - Data update (matches overview.svelte live binding)

    private func update() {
        guard let snap = handle?.snapshot else { return }

        // Header
        nameLabel.text = snap.name.isEmpty ? "No Name Provided" : snap.name
        hashLabel.text = hexHash.isEmpty ? snap.name : hexHash

        // Progress: use totalDone/total with Double intermediates for precision.
        // snap.progress only counts "wanted" pieces which is unreliable during streaming.
        let progress: Float = snap.total > 0
            ? Float(Double(snap.totalDone) / Double(snap.total))
            : 0
        // Don't rely on snap.isSeed — during streaming it becomes true when all
        // *wanted* pieces are done, even at 4% overall.
        let completed = snap.total > 0 && snap.totalDone >= snap.total

        // Status badge (Hayase: blue for Seeding, green for Downloading)
        if completed {
            statusBadge.text = "  Seeding  "
            statusBadge.backgroundColor = .systemBlue
        } else {
            statusBadge.text = "  Downloading  "
            statusBadge.backgroundColor = .systemGreen
        }

        // Progress percentage
        let pct = completed ? 100.0 : Double(progress) * 100.0
        bigPercentLabel.text = String(format: "%.1f%%", pct)
        progressBar.progress = completed ? 1.0 : progress

        // Progress stats
        downloadedValue.text = Self.fastPrettyBytes(snap.totalDone)

        let elapsed = Int(max(0, -startDate.timeIntervalSinceNow))
        uploadedValue.text = elapsed > 0 && snap.uploadRate > 0
            ? "~\(Self.fastPrettyBytes(snap.uploadRate * UInt64(elapsed)))"
            : "—"

        totalSizeValue.text = Self.fastPrettyBytes(snap.total)

        // Pieces: "{count} × {size}"
        let pieceCount = snap.pieces?.count ?? 0
        let pieceLenBytes = UInt64(snap.pieceLength)
        piecesValue.text = pieceCount > 0 && pieceLenBytes > 0
            ? "\(pieceCount) × \(Self.fastPrettyBytes(pieceLenBytes))"
            : "—"

        // Speed & Transfer — values in bits/sec (Hayase: fastPrettyBits)
        downSpeedValue.text = Self.fastPrettyBits(UInt64(snap.downloadRate) * 8)
        upSpeedValue.text   = Self.fastPrettyBits(UInt64(snap.uploadRate) * 8)

        // Time
        let remaining = snap.total > snap.totalDone ? snap.total - snap.totalDone : 0
        etaValue.text     = Self.eta(remaining: remaining, rate: snap.downloadRate)
        elapsedValue.text = Self.eta(seconds: elapsed)

        // Peers & Connections
        seedersValue.text  = "\(snap.numberOfSeeds)"
        leechersValue.text = "\(snap.numberOfLeechers)"
        wiresValue.text    = "\(snap.numberOfPeers)"

        // Protocol status dots
        setDot(dhtDot, enabled: true)
        setDot(lsdDot, enabled: true)
        setDot(pexDot, enabled: true)
        setDot(natDot, enabled: true)
        setDot(forwardDot, enabled: false) // conservative default; UPnP state not easily accessible
        setDot(persistDot, enabled: UserDefaults.standard.bool(forKey: "persist_downloads"))

        // Streaming: downloading + not all pieces wanted (some pieces have priority 0)
        let isStreaming: Bool = {
            guard snap.state == .downloading, let pieces = snap.pieces else { return false }
            return pieces.contains(where: { $0.intValue == 0 })
        }()
        setDot(streamingDot, enabled: isStreaming)

        // Update peers tab if visible
        if segmentedControl.selectedSegmentIndex == 2 {
            updatePeersTab()
        }
    }

    private func updatePeersTab() {
        guard let snap = handle?.snapshot else { return }
        peerSeedersValue.text  = "\(snap.numberOfSeeds)"
        peerLeechersValue.text = "\(snap.numberOfLeechers)"
        peerWiresValue.text    = "\(snap.numberOfPeers)"
    }

    // MARK: - Build Overview UI

    private func buildOverviewUI() {
        overviewScrollView.translatesAutoresizingMaskIntoConstraints = false

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 32
        stack.translatesAutoresizingMaskIntoConstraints = false
        overviewScrollView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: overviewScrollView.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: overviewScrollView.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: overviewScrollView.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: overviewScrollView.bottomAnchor, constant: -24),
            stack.widthAnchor.constraint(equalTo: overviewScrollView.widthAnchor, constant: -32),
        ])

        // 1. Header
        stack.addArrangedSubview(makeHeader())

        // 2. Progress
        stack.addArrangedSubview(makeProgressSection())

        // 3. Three-column grid: Speed & Transfer | Time Information | Peers & Connections
        stack.addArrangedSubview(makeThreeColumnGrid())

        // 4. Protocol Status
        stack.addArrangedSubview(makeProtocolStatusSection())
    }

    // MARK: - Header

    private func makeHeader() -> UIView {
        let badgeRow = UIStackView(arrangedSubviews: [statusBadge, hashLabel])
        badgeRow.axis = .horizontal
        badgeRow.spacing = 8
        badgeRow.alignment = .center

        let wrapper = UIStackView(arrangedSubviews: [nameLabel, badgeRow])
        wrapper.axis = .vertical
        wrapper.spacing = 8
        return wrapper
    }

    // MARK: - Progress section

    private func makeProgressSection() -> UIView {
        let container = UIStackView()
        container.axis = .vertical
        container.spacing = 16

        // Title row: icon + "Progress" ... percentage
        let titleRow = UIStackView()
        titleRow.axis = .horizontal
        titleRow.alignment = .center
        titleRow.spacing = 6

        let dlIcon = makeIcon("arrow.down.to.line", tint: .label, size: 20)
        let progressTitle = UILabel()
        progressTitle.font = .systemFont(ofSize: 24, weight: .bold)
        progressTitle.text = "Progress"
        progressTitle.textColor = .label

        let spacer = UIView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        titleRow.addArrangedSubview(dlIcon)
        titleRow.addArrangedSubview(progressTitle)
        titleRow.addArrangedSubview(spacer)
        titleRow.addArrangedSubview(bigPercentLabel)
        container.addArrangedSubview(titleRow)

        // Progress bar
        progressBar.heightAnchor.constraint(equalToConstant: 12).isActive = true
        container.addArrangedSubview(progressBar)

        // 4-column stat grid: Downloaded, Uploaded, Total Size, Pieces
        let grid = makeStatRow([
            StatItem(label: downloadedValue, title: "Downloaded", icon: "arrow.down",        color: .systemGreen),
            StatItem(label: uploadedValue,   title: "Uploaded",   icon: "arrow.up",          color: .systemBlue),
            StatItem(label: totalSizeValue,  title: "Total Size", icon: "internaldrive",     color: .systemGray),
            StatItem(label: piecesValue,     title: "Pieces",     icon: "puzzlepiece",       color: .systemGray),
        ])
        container.addArrangedSubview(grid)

        return container
    }

    // MARK: - Three-column grid

    private func makeThreeColumnGrid() -> UIView {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 16

        // Speed & Transfer
        stack.addArrangedSubview(makeSectionCard(
            title: "Speed & Transfer",
            items: [
                StatItem(label: downSpeedValue, title: "Download", icon: "arrow.down", color: .systemGreen),
                StatItem(label: upSpeedValue,   title: "Upload",   icon: "arrow.up",   color: .systemBlue),
            ]
        ))

        // Time Information
        stack.addArrangedSubview(makeSectionCard(
            title: "Time Information",
            items: [
                StatItem(label: etaValue,     title: "Remaining", icon: "hourglass.tophalf.filled", color: .systemOrange),
                StatItem(label: elapsedValue, title: "Elapsed",   icon: "timer",                    color: .systemPurple),
            ]
        ))

        // Peers & Connections
        stack.addArrangedSubview(makeSectionCard(
            title: "Peers & Connections",
            items: [
                StatItem(label: seedersValue,  title: "Seeders",  icon: "person.fill.badge.plus",  color: .systemGreen),
                StatItem(label: leechersValue, title: "Leechers", icon: "person.fill.badge.minus", color: .systemBlue),
                StatItem(label: wiresValue,    title: "Wires",    icon: "network",                 color: .systemPurple),
            ]
        ))

        return stack
    }

    // MARK: - Protocol Status section

    private func makeProtocolStatusSection() -> UIView {
        let container = UIStackView()
        container.axis = .vertical
        container.spacing = 12

        let title = UILabel()
        title.text = "Protocol Status"
        title.font = .systemFont(ofSize: 20, weight: .bold)
        title.textColor = .label
        container.addArrangedSubview(title)

        let columns = UIStackView()
        columns.axis = .horizontal
        columns.distribution = .fillEqually
        columns.spacing = 8

        columns.addArrangedSubview(makeProtocolColumn("Network Discovery", [
            ("DHT", dhtDot),
            ("LSD", lsdDot),
            ("PEX", pexDot),
        ]))
        columns.addArrangedSubview(makeProtocolColumn("Connection", [
            ("NAT", natDot),
            ("Forwarding", forwardDot),
        ]))
        columns.addArrangedSubview(makeProtocolColumn("Storage", [
            ("Persisting", persistDot),
            ("Streaming", streamingDot),
        ]))

        container.addArrangedSubview(columns)
        return container
    }

    private func makeProtocolColumn(_ header: String, _ rows: [(String, UILabel)]) -> UIView {
        let col = UIStackView()
        col.axis = .vertical
        col.spacing = 8

        let headerLabel = UILabel()
        headerLabel.text = header
        headerLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        headerLabel.textColor = .secondaryLabel
        col.addArrangedSubview(headerLabel)

        for (name, dot) in rows {
            let nameLabel = UILabel()
            nameLabel.text = name
            nameLabel.font = .systemFont(ofSize: 13, weight: .regular)
            nameLabel.textColor = .label

            let row = UIStackView(arrangedSubviews: [dot, nameLabel])
            row.axis = .horizontal
            row.spacing = 6
            row.alignment = .center
            col.addArrangedSubview(row)
        }

        return col
    }

    // MARK: - Build Peers UI

    private func buildPeersUI() {
        peersView.backgroundColor = .systemGroupedBackground

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        peersView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: peersView.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: peersView.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: peersView.trailingAnchor, constant: -16),
        ])

        let title = UILabel()
        title.text = "Peers & Connections"
        title.font = .systemFont(ofSize: 24, weight: .bold)
        title.textColor = .label
        stack.addArrangedSubview(title)

        stack.addArrangedSubview(makeStatRow([
            StatItem(label: peerSeedersValue,  title: "Seeders",  icon: "person.fill.badge.plus",  color: .systemGreen),
            StatItem(label: peerLeechersValue, title: "Leechers", icon: "person.fill.badge.minus", color: .systemBlue),
            StatItem(label: peerWiresValue,    title: "Wires",    icon: "network",                 color: .systemPurple),
        ]))
    }

    // MARK: - Reusable UI builders

    private struct StatItem {
        let label: UILabel
        let title: String
        let icon: String
        let color: UIColor
    }

    private func makeSectionCard(title: String, items: [StatItem]) -> UIView {
        let container = UIView()
        container.backgroundColor = .secondarySystemGroupedBackground
        container.layer.cornerRadius = 14
        container.clipsToBounds = true

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 17, weight: .bold)
        titleLabel.textColor = .label

        let grid = makeStatRow(items)

        let inner = UIStackView(arrangedSubviews: [titleLabel, grid])
        inner.axis = .vertical
        inner.spacing = 12
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

    private func makeStatRow(_ items: [StatItem]) -> UIView {
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

        let iconView = makeIcon(item.icon, tint: item.color, size: 14)
        let titleLabel = UILabel()
        titleLabel.text = item.title
        titleLabel.font = .systemFont(ofSize: 11, weight: .medium)
        titleLabel.textColor = .secondaryLabel

        let topRow = UIStackView(arrangedSubviews: [iconView, titleLabel])
        topRow.axis = .horizontal
        topRow.spacing = 4
        topRow.alignment = .center

        item.label.adjustsFontSizeToFitWidth = true
        item.label.minimumScaleFactor = 0.6

        let inner = UIStackView(arrangedSubviews: [topRow, item.label])
        inner.axis = .vertical
        inner.spacing = 6
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

    // MARK: - UIView helpers

    private static func makeValueLabel() -> UILabel {
        let l = UILabel()
        l.font = .systemFont(ofSize: 18, weight: .bold)
        l.textColor = .label
        return l
    }

    private static func makeDotLabel() -> UILabel {
        let l = UILabel()
        l.font = .systemFont(ofSize: 14)
        l.text = "●"
        return l
    }

    private func setDot(_ dot: UILabel, enabled: Bool) {
        dot.textColor = enabled ? .systemGreen : .systemRed
    }

    private func makeIcon(_ name: String, tint: UIColor, size: CGFloat) -> UIImageView {
        let config = UIImage.SymbolConfiguration(pointSize: size, weight: .medium)
        let iv = UIImageView(image: UIImage(systemName: name, withConfiguration: config))
        iv.tintColor = tint
        iv.contentMode = .scaleAspectFit
        iv.setContentHuggingPriority(.required, for: .horizontal)
        iv.setContentCompressionResistancePriority(.required, for: .horizontal)
        return iv
    }

    // MARK: - Format helpers (Hayase-compatible: SI units, 1000 divisor)

    /// Formats bytes using SI units (1000 divisor): B → kB → MB → GB → TB
    static func fastPrettyBytes(_ bytes: UInt64) -> String {
        let d = Double(bytes)
        if d < 1_000 { return "\(bytes) B" }
        if d < 1_000_000 { return String(format: "%.1f kB", d / 1_000) }
        if d < 1_000_000_000 { return String(format: "%.1f MB", d / 1_000_000) }
        if d < 1_000_000_000_000 { return String(format: "%.1f GB", d / 1_000_000_000) }
        return String(format: "%.1f TB", d / 1_000_000_000_000)
    }

    /// Formats bits using SI units (1000 divisor): b → kb → Mb → Gb → Tb
    static func fastPrettyBits(_ bits: UInt64) -> String {
        let d = Double(bits)
        if d < 1_000 { return "\(bits) b/s" }
        if d < 1_000_000 { return String(format: "%.1f kb/s", d / 1_000) }
        if d < 1_000_000_000 { return String(format: "%.1f Mb/s", d / 1_000_000) }
        if d < 1_000_000_000_000 { return String(format: "%.1f Gb/s", d / 1_000_000_000) }
        return String(format: "%.1f Tb/s", d / 1_000_000_000_000)
    }

    /// Formats seconds into up to 2 largest time units: "22y 5mo", "1h 2m", "2m 3s", "0s"
    static func eta(seconds: Int) -> String {
        guard seconds > 0 else { return "0s" }
        let units: [(String, Int)] = [
            ("y", 31_536_000), ("mo", 2_592_000), ("d", 86_400),
            ("h", 3_600), ("m", 60), ("s", 1),
        ]
        var remaining = seconds
        var parts: [String] = []
        for (suffix, divisor) in units {
            guard parts.count < 2 else { break }
            let count = remaining / divisor
            if count > 0 {
                parts.append("\(count)\(suffix)")
                remaining %= divisor
            }
        }
        return parts.isEmpty ? "0s" : parts.joined(separator: " ")
    }

    /// Overload: computes ETA from remaining bytes and download rate, then formats.
    static func eta(remaining: UInt64, rate: UInt64) -> String {
        guard rate > 0, remaining > 0 else { return "∞" }
        return eta(seconds: Int(remaining / rate))
    }
}
