// TorrentDetailViewController.swift
// Hayase
//
// Full replica of Hayase's torrent client UI (overview.svelte).
// Provides five tabs via a segmented control matching Hayase's sidebar:
//   - Overview: header, progress, speed/transfer, time, peers, protocol status
//   - Files: embeds VideoListViewController as a child VC
//   - Peers: peer/seed/leech summary
//   - Library: downloaded content table (series, episode, files, size, status, date, name)
//   - Settings: navigates to the app SettingsViewController (matches Hayase's
//               client layout where Settings links to /app/settings/client/)

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
        let sc = UISegmentedControl(items: ["Overview", "Files", "Peers", "Library", "Settings"])
        sc.selectedSegmentIndex = 0
        return sc
    }()

    private let pageTitleLabel: UILabel = {
        let l = UILabel()
        l.font = .nunito(ofSize: 22, weight: .bold)
        l.textColor = .label
        l.text = "Torrent Client"
        return l
    }()

    private let pageSubtitleLabel: UILabel = {
        let l = UILabel()
        l.font = .nunito(ofSize: 14, weight: .regular)
        l.textColor = .secondaryLabel
        l.text = "Monitor your torrents, and configure settings for your torrent client."
        l.numberOfLines = 0
        return l
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

    private lazy var libraryScrollView: UIScrollView = {
        let sv = UIScrollView()
        sv.showsVerticalScrollIndicator = true
        sv.alwaysBounceVertical = true
        return sv
    }()

    // MARK: - Library tab: table for downloaded content
    private var libraryTableView: UITableView!
    private var libraryEntries: [(hash: String, handle: TorrentHandle, entity: Torrents?)] = []

    /// Tracks the last non-Settings segment so we can revert when Settings navigates away.
    private var previousSegmentIndex: Int = 0

    /// Index of the "Settings" segment in the segmented control.
    private static let settingsSegmentIndex = 4

    // MARK: - Overview: header labels

    private let nameLabel: UILabel = {
        let l = UILabel()
        l.font = .nunito(ofSize: 24, weight: .bold)
        l.textColor = .label
        l.numberOfLines = 2
        l.lineBreakMode = .byTruncatingTail
        return l
    }()

    private let statusBadge: TorrentPillBadge = {
        let l = TorrentPillBadge(horizontalPadding: 10, verticalPadding: 4)
        l.font = .nunito(ofSize: 12, weight: .bold)
        l.textColor = .white
        l.textAlignment = .center
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
        l.font = .nunito(ofSize: 24, weight: .bold)
        l.textColor = .label
        l.text = "Progress"
        return l
    }()

    private let bigPercentLabel: UILabel = {
        let l = UILabel()
        l.font = .nunito(ofSize: 24, weight: .bold)
        l.textColor = .label
        return l
    }()

    private let progressBar: UIProgressView = {
        let pv = UIProgressView(progressViewStyle: .bar)
        pv.layer.cornerRadius = 6
        pv.clipsToBounds = true
        pv.trackTintColor = .secondarySystemFill
        pv.progressTintColor = .white
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

    // MARK: - Overview: protocol status dots

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
        title = "Torrent Client"
        view.backgroundColor = .systemBackground
        navigationController?.navigationBar.prefersLargeTitles = false

        setupSegmentedControl()
        setupContainerView()
        buildOverviewUI()
        buildPeersUI()
        buildLibraryUI()
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
        pageTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        pageSubtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        segmentedControl.translatesAutoresizingMaskIntoConstraints = false
        segmentedControl.addTarget(self, action: #selector(segmentChanged(_:)), for: .valueChanged)

        let separator = UIView()
        separator.backgroundColor = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(pageTitleLabel)
        view.addSubview(pageSubtitleLabel)
        view.addSubview(separator)
        view.addSubview(segmentedControl)

        NSLayoutConstraint.activate([
            pageTitleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            pageTitleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            pageTitleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            pageSubtitleLabel.topAnchor.constraint(equalTo: pageTitleLabel.bottomAnchor, constant: 4),
            pageSubtitleLabel.leadingAnchor.constraint(equalTo: pageTitleLabel.leadingAnchor),
            pageSubtitleLabel.trailingAnchor.constraint(equalTo: pageTitleLabel.trailingAnchor),

            separator.topAnchor.constraint(equalTo: pageSubtitleLabel.bottomAnchor, constant: 12),
            separator.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            separator.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            separator.heightAnchor.constraint(equalToConstant: 0.5),

            segmentedControl.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 12),
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
        if sender.selectedSegmentIndex == Self.settingsSegmentIndex {
            // Revert to the previous tab so Settings doesn't stay selected
            sender.selectedSegmentIndex = previousSegmentIndex
            // Navigate to the app Settings page (matches Hayase: Settings → /app/settings/client/)
            let settingsVC = SettingsViewController()
            navigationController?.pushViewController(settingsVC, animated: true)
        } else {
            previousSegmentIndex = sender.selectedSegmentIndex
            showTab(sender.selectedSegmentIndex)
        }
    }

    /// Updates the page title and subtitle label to match Hayase's per-tab descriptions.
    private func updatePageHeader(for index: Int) {
        switch index {
        case 0:
            pageTitleLabel.text = "Torrent Client"
            pageSubtitleLabel.text = "Monitor your torrents, and configure settings for your torrent client."
        case 1:
            pageTitleLabel.text = "File List"
            pageSubtitleLabel.text = "Files in the currently active torrent, their download progress, and amount of active stream selections."
        case 2:
            pageTitleLabel.text = "Peer List"
            pageSubtitleLabel.text = "Peers connected to the currently active torrent, their statistics, region etc."
        case 3:
            pageTitleLabel.text = "Torrent Library"
            pageSubtitleLabel.text = "All of your downloaded torrents. If Persist Files is enabled then your previously downloaded torrents will show up here."
        default:
            break
        }
    }

    private func showTab(_ index: Int) {
        // Remove all child content
        overviewScrollView.removeFromSuperview()
        peersView.removeFromSuperview()
        libraryScrollView.removeFromSuperview()
        removeFilesChild()

        // Update header text for this tab
        updatePageHeader(for: index)

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

        case 3:
            libraryScrollView.isHidden = false
            containerView.addSubview(libraryScrollView)
            libraryScrollView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                libraryScrollView.topAnchor.constraint(equalTo: containerView.topAnchor),
                libraryScrollView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
                libraryScrollView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
                libraryScrollView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            ])
            refreshLibrary()

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
            statusBadge.text = "Seeding"
            statusBadge.backgroundColor = .systemBlue
        } else {
            statusBadge.text = "Downloading"
            statusBadge.backgroundColor = .systemGreen
        }

        // Progress percentage
        let pct = completed ? 100.0 : Double(progress) * 100.0
        bigPercentLabel.text = String(format: "%.1f%%", pct)
        progressBar.progress = completed ? 1.0 : progress

        // Progress stats
        downloadedValue.text = Self.fastPrettyBytes(snap.totalDone)

        uploadedValue.text = Self.fastPrettyBytes(snap.totalUpload)

        totalSizeValue.text = Self.fastPrettyBytes(snap.total)

        // Pieces: "{count} × {size}"
        let pieceCount = snap.pieces?.count ?? 0
        let pieceLenBytes = UInt64(snap.pieceLength)
        piecesValue.text = pieceCount > 0 && pieceLenBytes > 0
            ? "\(pieceCount) × \(Self.fastPrettyBytes(pieceLenBytes))"
            : "—"

        // Speed & Transfer — values in bits/sec (Hayase: fastPrettyBits(speed.down * 8))
        downSpeedValue.text = Self.fastPrettyBits(snap.downloadRate * 8) + "/s"
        upSpeedValue.text   = Self.fastPrettyBits(snap.uploadRate * 8) + "/s"

        // Time
        let remaining = snap.total > snap.totalDone ? snap.total - snap.totalDone : 0
        let elapsed = Int(max(0, -startDate.timeIntervalSinceNow))
        etaValue.text     = Self.eta(remaining: remaining, rate: snap.downloadRate)
        elapsedValue.text = Self.eta(seconds: elapsed)

        // Peers & Connections
        seedersValue.text  = "\(snap.numberOfSeeds)"
        leechersValue.text = "\(snap.numberOfLeechers)"
        wiresValue.text    = "\(snap.numberOfPeers)"

        // Protocol status dots — use actual snapshot values from LibTorrent-Swift
        // (matches Hayase overview.svelte which reads server.protocol store).
        setDot(dhtDot, enabled: snap.isDhtRunning)
        setDot(lsdDot, enabled: snap.isLsdRunning)
        setDot(pexDot, enabled: snap.isPexEnabled)
        setDot(natDot, enabled: true)   // UPnP/NAT-PMP is always enabled in settings
        setDot(forwardDot, enabled: snap.hasIncomingConnections)
        setDot(persistDot, enabled: UserDefaults.standard.bool(forKey: "pref_persistFiles"))

        // Streaming: downloading + sequential mode enabled (TorrentStreamer enables this)
        let isStreaming = snap.state == .downloading && snap.isSequential
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

        let dlIcon = makeIcon("hard-drive-download", tint: .label, size: 20)
        let progressTitle = UILabel()
        progressTitle.font = .nunito(ofSize: 24, weight: .bold)
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
        // Matches Hayase's flat layout: icon + muted label + value
        let grid = makeProgressStatRow([
            StatItem(label: downloadedValue, title: "Downloaded", icon: "download",   color: .systemGreen),
            StatItem(label: uploadedValue,   title: "Uploaded",   icon: "upload",     color: .systemBlue),
            StatItem(label: totalSizeValue,  title: "Total Size", icon: "hard-drive", color: .systemGray),
            StatItem(label: piecesValue,     title: "Pieces",     icon: "puzzle",     color: .systemGray),
        ])
        container.addArrangedSubview(grid)

        return container
    }

    // MARK: - Three-column grid

    private func makeThreeColumnGrid() -> UIView {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 0

        // Speed & Transfer
        stack.addArrangedSubview(makeFlatSection(
            title: "Speed & Transfer",
            icon: "wifi",
            items: [
                StatItem(label: downSpeedValue, title: "Download", icon: "download", color: .systemGreen),
                StatItem(label: upSpeedValue,   title: "Upload",   icon: "upload",   color: .systemBlue),
            ]
        ))

        // Time Information
        stack.addArrangedSubview(makeFlatSection(
            title: "Time Information",
            icon: "clock",
            items: [
                StatItem(label: etaValue,     title: "Remaining", icon: "clock-fading", color: .systemOrange),
                StatItem(label: elapsedValue, title: "Elapsed",   icon: "timer",        color: .systemPurple),
            ]
        ))

        // Peers & Connections
        stack.addArrangedSubview(makeFlatSection(
            title: "Peers & Connections",
            icon: "users",
            items: [
                StatItem(label: seedersValue,  title: "Seeders",  icon: "user-round-plus",  color: .systemGreen),
                StatItem(label: leechersValue, title: "Leechers", icon: "user-round-minus", color: .systemBlue),
                StatItem(label: wiresValue,    title: "Wires",    icon: "link",             color: .systemPurple),
            ]
        ))

        return stack
    }

    // MARK: - Protocol Status section

    private func makeProtocolStatusSection() -> UIView {
        let container = UIStackView()
        container.axis = .vertical
        container.spacing = 12

        // Title row with icon
        let iconView = makeIcon("network", tint: .label, size: 20)
        let title = UILabel()
        title.text = "Protocol Status"
        title.font = .nunito(ofSize: 24, weight: .bold)
        title.textColor = .label
        let titleRow = UIStackView(arrangedSubviews: [iconView, title])
        titleRow.axis = .horizontal
        titleRow.spacing = 8
        titleRow.alignment = .center
        container.addArrangedSubview(titleRow)

        let columns = UIStackView()
        columns.axis = .horizontal
        columns.distribution = .fillEqually
        columns.spacing = 8

        columns.addArrangedSubview(makeProtocolColumn("Network Discovery", [
            ("DHT", "Distributed Hash Table for peer discovery", dhtDot),
            ("LSD", "Local Service Discovery on network", lsdDot),
            ("PEX", "Peer Exchange with other clients", pexDot),
        ]))
        columns.addArrangedSubview(makeProtocolColumn("Connection", [
            ("NAT", "NAT-PMP/UPnP automatic forwarding", natDot),
            ("Forwarding", "Accepting inbound connections", forwardDot),
        ]))
        columns.addArrangedSubview(makeProtocolColumn("Storage", [
            ("Persisting", "Storing all torrents", persistDot),
            ("Streaming", "Downloading only required pieces", streamingDot),
        ]))

        container.addArrangedSubview(columns)
        return container
    }

    private func makeProtocolColumn(_ header: String, _ rows: [(String, String, UIView)]) -> UIView {
        let col = UIStackView()
        col.axis = .vertical
        col.spacing = 12

        let headerLabel = UILabel()
        headerLabel.text = header
        headerLabel.font = .nunito(ofSize: 14, weight: .medium)
        headerLabel.textColor = .label
        col.addArrangedSubview(headerLabel)

        for (name, desc, dot) in rows {
            let nameLabel = UILabel()
            nameLabel.text = name
            nameLabel.font = .nunito(ofSize: 13, weight: .regular)
            nameLabel.textColor = .label

            let descLabel = UILabel()
            descLabel.text = desc
            descLabel.font = .nunito(ofSize: 10, weight: .regular)
            descLabel.textColor = .secondaryLabel
            descLabel.numberOfLines = 2

            let textStack = UIStackView(arrangedSubviews: [nameLabel, descLabel])
            textStack.axis = .vertical
            textStack.spacing = 1

            let row = UIStackView(arrangedSubviews: [dot, textStack])
            row.axis = .horizontal
            row.spacing = 8
            row.alignment = .center
            col.addArrangedSubview(row)
        }

        return col
    }

    // MARK: - Build Peers UI

    private func buildPeersUI() {
        peersView.backgroundColor = .systemBackground

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

        let iconView = makeIcon("users", tint: .label, size: 20)
        let title = UILabel()
        title.text = "Peers & Connections"
        title.font = .nunito(ofSize: 24, weight: .bold)
        title.textColor = .label
        let titleRow = UIStackView(arrangedSubviews: [iconView, title])
        titleRow.axis = .horizontal
        titleRow.spacing = 8
        titleRow.alignment = .center
        stack.addArrangedSubview(titleRow)

        stack.addArrangedSubview(makeFlatStatRow([
            StatItem(label: peerSeedersValue,  title: "Seeders",  icon: "user-round-plus",  color: .systemGreen),
            StatItem(label: peerLeechersValue, title: "Leechers", icon: "user-round-minus", color: .systemBlue),
            StatItem(label: peerWiresValue,    title: "Wires",    icon: "link",             color: .systemPurple),
        ]))
    }

    // MARK: - Build Library UI (matches Hayase library/table.svelte)

    private func buildLibraryUI() {
        libraryScrollView.translatesAutoresizingMaskIntoConstraints = false

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        libraryScrollView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: libraryScrollView.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: libraryScrollView.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: libraryScrollView.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: libraryScrollView.bottomAnchor, constant: -24),
            stack.widthAnchor.constraint(equalTo: libraryScrollView.widthAnchor, constant: -32),
        ])

        // Section title with icon (matches Hayase)
        let iconView = makeIcon("library-big", tint: .label, size: 20)
        let title = UILabel()
        title.text = "Library"
        title.font = .nunito(ofSize: 24, weight: .bold)
        title.textColor = .label
        let titleRow = UIStackView(arrangedSubviews: [iconView, title])
        titleRow.axis = .horizontal
        titleRow.spacing = 8
        titleRow.alignment = .center
        stack.addArrangedSubview(titleRow)

        let subtitle = UILabel()
        subtitle.text = "Downloaded torrents and their content."
        subtitle.font = .nunito(ofSize: 14, weight: .regular)
        subtitle.textColor = .secondaryLabel
        stack.addArrangedSubview(subtitle)

        // Table view for library entries
        libraryTableView = UITableView(frame: .zero, style: .insetGrouped)
        libraryTableView.translatesAutoresizingMaskIntoConstraints = false
        libraryTableView.delegate = self
        libraryTableView.dataSource = self
        libraryTableView.register(LibraryEntryCell.self, forCellReuseIdentifier: LibraryEntryCell.reuseID)
        libraryTableView.rowHeight = UITableView.automaticDimension
        libraryTableView.estimatedRowHeight = 80
        libraryTableView.isScrollEnabled = false  // scrolling handled by parent scroll view
        libraryTableView.backgroundColor = .clear

        stack.addArrangedSubview(libraryTableView)

        // The table height constraint will be updated in refreshLibrary()
        libraryTableView.heightAnchor.constraint(greaterThanOrEqualToConstant: 100).isActive = true
    }

    private var libraryTableHeightConstraint: NSLayoutConstraint?

    private func refreshLibrary() {
        libraryEntries = TorrentService.sharedTorrentService.handles
            .map { (hash: $0.key, handle: $0.value, entity: TorrentService.sharedTorrentService.GetTorrentEntitiesFromHash($0.key).first) }
            .sorted { $0.handle.snapshot.name < $1.handle.snapshot.name }
        libraryTableView?.reloadData()

        // Resize table to fit content
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let tv = self.libraryTableView else { return }
            tv.layoutIfNeeded()
            self.libraryTableHeightConstraint?.isActive = false
            self.libraryTableHeightConstraint = tv.heightAnchor.constraint(equalToConstant: max(tv.contentSize.height, 100))
            self.libraryTableHeightConstraint?.isActive = true
        }
    }

    // MARK: - Reusable UI builders

    private struct StatItem {
        let label: UILabel
        let title: String
        let icon: String
        let color: UIColor
    }

    /// Flat section layout matching Hayase: icon + bold title header, then stat cells in a grid.
    private func makeFlatSection(title: String, icon: String, items: [StatItem]) -> UIView {
        let container = UIStackView()
        container.axis = .vertical
        container.spacing = 12

        // Section title with icon (matches Hayase's text-2xl font-bold with icon)
        let iconView = makeIcon(icon, tint: .label, size: 20)
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .nunito(ofSize: 24, weight: .bold)
        titleLabel.textColor = .label

        let titleRow = UIStackView(arrangedSubviews: [iconView, titleLabel])
        titleRow.axis = .horizontal
        titleRow.spacing = 8
        titleRow.alignment = .center

        // Add top padding to separate from previous section
        let paddedTitle = UIStackView(arrangedSubviews: [titleRow])
        paddedTitle.axis = .vertical
        paddedTitle.layoutMargins = UIEdgeInsets(top: 16, left: 0, bottom: 0, right: 0)
        paddedTitle.isLayoutMarginsRelativeArrangement = true

        container.addArrangedSubview(paddedTitle)

        // Stat cells in a horizontal grid (no card background)
        let grid = makeFlatStatRow(items)
        container.addArrangedSubview(grid)

        return container
    }

    /// Flat stat row — each cell has icon + label on top, large bold value below.
    /// No card background, matching Hayase's direct layout.
    private func makeFlatStatRow(_ items: [StatItem]) -> UIView {
        let row = UIStackView(arrangedSubviews: items.map { makeFlatStatCell($0) })
        row.axis = .horizontal
        row.distribution = .fillEqually
        row.spacing = 16
        return row
    }

    private func makeFlatStatCell(_ item: StatItem) -> UIView {
        let iconView = makeIcon(item.icon, tint: item.color, size: 14)
        let titleLabel = UILabel()
        titleLabel.text = item.title
        titleLabel.font = .nunito(ofSize: 13, weight: .medium)
        titleLabel.textColor = .secondaryLabel

        let topRow = UIStackView(arrangedSubviews: [iconView, titleLabel])
        topRow.axis = .horizontal
        topRow.spacing = 4
        topRow.alignment = .center

        item.label.font = .nunito(ofSize: 24, weight: .bold)
        item.label.adjustsFontSizeToFitWidth = true
        item.label.minimumScaleFactor = 0.5

        let stack = UIStackView(arrangedSubviews: [topRow, item.label])
        stack.axis = .vertical
        stack.spacing = 8
        return stack
    }

    /// Progress section stats — matches Hayase's compact grid:
    /// icon + muted label, then medium-weight value below.
    private func makeProgressStatRow(_ items: [StatItem]) -> UIView {
        let row = UIStackView(arrangedSubviews: items.map { makeProgressStatCell($0) })
        row.axis = .horizontal
        row.distribution = .fillEqually
        row.spacing = 12
        return row
    }

    private func makeProgressStatCell(_ item: StatItem) -> UIView {
        let iconView = makeIcon(item.icon, tint: item.color, size: 14)

        let titleLabel = UILabel()
        titleLabel.text = item.title
        titleLabel.font = .nunito(ofSize: 12, weight: .regular)
        titleLabel.textColor = .secondaryLabel

        let topRow = UIStackView(arrangedSubviews: [iconView, titleLabel])
        topRow.axis = .horizontal
        topRow.spacing = 4
        topRow.alignment = .center

        item.label.font = .nunito(ofSize: 14, weight: .medium)
        item.label.adjustsFontSizeToFitWidth = true
        item.label.minimumScaleFactor = 0.6

        let stack = UIStackView(arrangedSubviews: [topRow, item.label])
        stack.axis = .vertical
        stack.spacing = 4
        return stack
    }

    // MARK: - UIView helpers

    static func makeValueLabel() -> UILabel {
        let l = UILabel()
        l.font = .nunito(ofSize: 18, weight: .bold)
        l.textColor = .label
        return l
    }

    static func makeDotLabel() -> UIView {
        let v = UIView()
        v.layer.cornerRadius = 4
        v.clipsToBounds = true
        v.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            v.widthAnchor.constraint(equalToConstant: 8),
            v.heightAnchor.constraint(equalToConstant: 8),
        ])
        return v
    }

    private func setDot(_ dot: UIView, enabled: Bool) {
        dot.backgroundColor = enabled ? .systemGreen : .systemRed
    }

    private func makeIcon(_ name: String, tint: UIColor, size: CGFloat) -> UIImageView {
        let config = UIImage.SymbolConfiguration(pointSize: size, weight: .medium)
        let iv = UIImageView(image: UIImage.hayaseIcon(name, withConfiguration: config))
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
    /// (No /s suffix — callers append it as in Hayase's `{fastPrettyBits(...)}/s`)
    static func fastPrettyBits(_ bits: UInt64) -> String {
        let d = Double(bits)
        if d < 1_000 { return "\(bits) b" }
        if d < 1_000_000 { return String(format: "%.1f kb", d / 1_000) }
        if d < 1_000_000_000 { return String(format: "%.1f Mb", d / 1_000_000) }
        if d < 1_000_000_000_000 { return String(format: "%.1f Gb", d / 1_000_000_000) }
        return String(format: "%.1f Tb", d / 1_000_000_000_000)
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

// MARK: - Library Table UITableViewDataSource & UITableViewDelegate

extension TorrentDetailViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard tableView === libraryTableView else { return 0 }
        return libraryEntries.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(
            withIdentifier: LibraryEntryCell.reuseID, for: indexPath) as? LibraryEntryCell else { return UITableViewCell() }
        guard indexPath.row < libraryEntries.count else { return cell }
        let entry = libraryEntries[indexPath.row]
        cell.configure(handle: entry.handle, entity: entry.entity)
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        // Navigate to files view for the selected torrent
        guard indexPath.row < libraryEntries.count else { return }
        segmentedControl.selectedSegmentIndex = 1
        showTab(1)
    }
}

// MARK: - LibraryEntryCell (matches Hayase library/table.svelte)
/// Shows: Series (anime name) | Episode | Files | Size | Status | Torrent Name

final class LibraryEntryCell: UITableViewCell {
    static let reuseID = "LibraryEntryCell"

    private let seriesLabel: UILabel = {
        let l = UILabel()
        l.font = .nunito(ofSize: 14, weight: .semibold)
        l.textColor = .label
        l.numberOfLines = 1
        return l
    }()

    private let episodeLabel: UILabel = {
        let l = UILabel()
        l.font = .nunito(ofSize: 12, weight: .regular)
        l.textColor = .secondaryLabel
        return l
    }()

    private let filesLabel: UILabel = {
        let l = UILabel()
        l.font = .nunito(ofSize: 12, weight: .regular)
        l.textColor = .secondaryLabel
        return l
    }()

    private let sizeLabel: UILabel = {
        let l = UILabel()
        l.font = .nunito(ofSize: 12, weight: .regular)
        l.textColor = .secondaryLabel
        return l
    }()

    private let statusBadge: TorrentPillBadge = {
        let l = TorrentPillBadge(horizontalPadding: 6, verticalPadding: 2)
        l.font = .nunito(ofSize: 10, weight: .bold)
        l.textColor = .white
        l.textAlignment = .center
        return l
    }()

    private let torrentNameLabel: UILabel = {
        let l = UILabel()
        l.font = .nunito(ofSize: 11, weight: .regular)
        l.textColor = .tertiaryLabel
        l.numberOfLines = 2
        l.lineBreakMode = .byTruncatingTail
        return l
    }()

    private let progressBar: UIProgressView = {
        let pv = UIProgressView(progressViewStyle: .bar)
        pv.layer.cornerRadius = 2
        pv.clipsToBounds = true
        pv.trackTintColor = .secondarySystemFill
        return pv
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setup()
    }
    required init?(coder: NSCoder) { super.init(coder: coder); setup() }

    private func setup() {
        accessoryType = .disclosureIndicator
        backgroundColor = .clear

        // Top row: series + status
        let topRow = UIStackView(arrangedSubviews: [seriesLabel, statusBadge])
        topRow.axis = .horizontal
        topRow.spacing = 8
        topRow.alignment = .center

        // Info row: episode · files · size
        let infoRow = UIStackView(arrangedSubviews: [episodeLabel, filesLabel, sizeLabel])
        infoRow.axis = .horizontal
        infoRow.spacing = 12

        let mainStack = UIStackView(arrangedSubviews: [topRow, infoRow, progressBar, torrentNameLabel])
        mainStack.axis = .vertical
        mainStack.spacing = 6
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(mainStack)

        NSLayoutConstraint.activate([
            mainStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            mainStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            mainStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            mainStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10),
            progressBar.heightAnchor.constraint(equalToConstant: 3),
        ])
    }

    func configure(handle: TorrentHandle, entity: Torrents?) {
        let snap = handle.snapshot

        // Series name from CoreData Animes entity
        let animeName = entity?.animes?.animeTitleEnglish
            ?? entity?.animes?.animeTitleJapanese
            ?? "Unknown Series"
        seriesLabel.text = animeName

        // Episode from Videos entities
        let videoCount = entity?.videos?.count ?? 0
        episodeLabel.text = videoCount > 0 ? "📺 \(videoCount) episode(s)" : "📺 —"

        // Files count
        let fileCount = snap.files.count
        filesLabel.text = "📁 \(fileCount) files"

        // Size
        sizeLabel.text = "💾 \(TorrentDetailViewController.fastPrettyBytes(snap.total))"

        // Status badge
        let progress: Float = snap.total > 0
            ? Float(Double(snap.totalDone) / Double(snap.total))
            : 0
        let isComplete = snap.total > 0 && snap.totalDone >= snap.total

        if isComplete {
            statusBadge.text = "Complete"
            statusBadge.backgroundColor = .systemGreen
            progressBar.progress = 1.0
            progressBar.progressTintColor = .white
        } else {
            statusBadge.text = String(format: "%.0f%%", progress * 100)
            statusBadge.backgroundColor = .systemBlue
            progressBar.progress = progress
            progressBar.progressTintColor = .white
        }

        // Torrent name
        torrentNameLabel.text = snap.name.isEmpty ? "Unknown torrent" : snap.name
    }
}

// MARK: - TorrentPillBadge

/// Pill-shaped badge label with proper internal padding (used for Downloading/Seeding status).
/// Matches the existing ThreadBadgeLabel / PaddedBadgeLabel pattern.
final class TorrentPillBadge: UILabel {
    private let hPad: CGFloat
    private let vPad: CGFloat

    init(horizontalPadding: CGFloat = 10, verticalPadding: CGFloat = 4) {
        self.hPad = horizontalPadding
        self.vPad = verticalPadding
        super.init(frame: .zero)
        clipsToBounds = true
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    required init?(coder: NSCoder) {
        self.hPad = 10
        self.vPad = 4
        super.init(coder: coder)
        clipsToBounds = true
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.insetBy(dx: hPad, dy: vPad))
    }

    override var intrinsicContentSize: CGSize {
        let s = super.intrinsicContentSize
        return CGSize(width: s.width + hPad * 2, height: s.height + vPad * 2)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2
    }
}
