//
//  DownloadsViewController.swift
//  TheAnimeTool
//

import UIKit
import CoreData
import LibTorrent

// MARK: - DownloadsViewController

/// Hayase-style torrent client page with tabbed interface:
/// Overview, Files, Peers, Library, Settings.
/// Auto-selects the first active torrent and updates every second.
class DownloadsViewController: UIViewController {

    // MARK: - Properties

    private var updateTimer: Timer?
    private let startDate = Date()

    /// Currently selected torrent
    private var selectedHandle: TorrentHandle?
    private var selectedHex: String = ""
    private var selectedEntity: Torrents?

    /// All active handles for the library tab
    private var libraryEntries: [(hash: String, handle: TorrentHandle, entity: Torrents?)] = []

    private var previousSegmentIndex: Int = 0
    private static let settingsSegmentIndex = 4

    private var filesViewController: UIViewController?

    // MARK: - Page header

    private let pageTitleLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 22, weight: .bold)
        l.textColor = .label
        l.text = "Torrent Client"
        return l
    }()

    private let pageSubtitleLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 14, weight: .regular)
        l.textColor = .secondaryLabel
        l.text = "Monitor your torrents, and configure settings for your torrent client."
        l.numberOfLines = 0
        return l
    }()

    // MARK: - Segmented control & containers

    private let segmentedControl: UISegmentedControl = {
        let sc = UISegmentedControl(items: ["Overview", "Files", "Peers", "Library", "Settings"])
        sc.selectedSegmentIndex = 0
        return sc
    }()

    private let containerView = UIView()

    // MARK: - Overview UI elements

    private lazy var overviewScrollView: UIScrollView = {
        let sv = UIScrollView()
        sv.showsVerticalScrollIndicator = true
        sv.alwaysBounceVertical = true
        return sv
    }()

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

    // Progress stat values
    private let downloadedValue  = TorrentDetailViewController.makeValueLabel()
    private let uploadedValue    = TorrentDetailViewController.makeValueLabel()
    private let totalSizeValue   = TorrentDetailViewController.makeValueLabel()
    private let piecesValue      = TorrentDetailViewController.makeValueLabel()

    // Speed & Transfer / Time / Peers values
    private let downSpeedValue   = TorrentDetailViewController.makeValueLabel()
    private let upSpeedValue     = TorrentDetailViewController.makeValueLabel()
    private let etaValue         = TorrentDetailViewController.makeValueLabel()
    private let elapsedValue     = TorrentDetailViewController.makeValueLabel()
    private let seedersValue     = TorrentDetailViewController.makeValueLabel()
    private let leechersValue    = TorrentDetailViewController.makeValueLabel()
    private let wiresValue       = TorrentDetailViewController.makeValueLabel()

    // Protocol status dots
    private let dhtDot       = TorrentDetailViewController.makeDotLabel()
    private let lsdDot       = TorrentDetailViewController.makeDotLabel()
    private let pexDot       = TorrentDetailViewController.makeDotLabel()
    private let natDot       = TorrentDetailViewController.makeDotLabel()
    private let forwardDot   = TorrentDetailViewController.makeDotLabel()
    private let persistDot   = TorrentDetailViewController.makeDotLabel()
    private let streamingDot = TorrentDetailViewController.makeDotLabel()

    // MARK: - Peers tab

    private lazy var peersView: UIView = {
        let v = UIView()
        v.isHidden = true
        return v
    }()

    private let peerSeedersValue  = TorrentDetailViewController.makeValueLabel()
    private let peerLeechersValue = TorrentDetailViewController.makeValueLabel()
    private let peerWiresValue    = TorrentDetailViewController.makeValueLabel()

    // MARK: - Library tab

    private lazy var libraryScrollView: UIScrollView = {
        let sv = UIScrollView()
        sv.showsVerticalScrollIndicator = true
        sv.alwaysBounceVertical = true
        return sv
    }()

    private var libraryTableView: UITableView!
    private var libraryTableHeightConstraint: NSLayoutConstraint?

    // MARK: - Empty state

    private let emptyLabel: UILabel = {
        let l = UILabel()
        l.text = "No active downloads"
        l.textColor = .secondaryLabel
        l.font = .systemFont(ofSize: 17)
        l.textAlignment = .center
        l.isHidden = true
        return l
    }()

    // MARK: - StatItem

    private struct StatItem {
        let label: UILabel
        let title: String
        let icon: String
        let color: UIColor
    }

    // MARK: - Lifecycle

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        tabBarItem = UITabBarItem(title: "Downloads",
                                  image: UIImage(systemName: "arrow.down.circle"),
                                  selectedImage: UIImage(systemName: "arrow.down.circle.fill"))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Torrent Client"
        view.backgroundColor = .systemBackground
        navigationController?.navigationBar.prefersLargeTitles = false

        setupPageHeader()
        setupContainerView()
        setupEmptyLabel()
        buildOverviewUI()
        buildPeersUI()
        buildLibraryUI()
        setupNotifications()

        autoSelectFirstTorrent()
        showTab(0)
        update()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.navigationBar.prefersLargeTitles = false
        autoSelectFirstTorrent()
        startTimer()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopTimer()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        stopTimer()
    }

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

    // MARK: - Notifications

    private func setupNotifications() {
        NotificationCenter.default.addObserver(self,
            selector: #selector(handleTorrentUpdate),
            name: NSNotification.Name(TorrentService.TorrentInControllerDidUpdateNotification),
            object: nil)
    }

    @objc private func handleTorrentUpdate() {
        autoSelectFirstTorrent()
        update()
    }

    // MARK: - Torrent selection

    private func autoSelectFirstTorrent() {
        let handles = TorrentService.sharedTorrentService.handles
        // Keep current selection if still valid
        if !selectedHex.isEmpty,
           handles[selectedHex] != nil {
            selectedHandle = handles[selectedHex]
            selectedEntity = TorrentService.sharedTorrentService.GetTorrentEntitiesFromHash(selectedHex).first
            emptyLabel.isHidden = true
            return
        }
        // Auto-select first handle sorted by name
        if let first = handles.sorted(by: { $0.value.snapshot.name < $1.value.snapshot.name }).first {
            selectedHex = first.key
            selectedHandle = first.value
            selectedEntity = TorrentService.sharedTorrentService.GetTorrentEntitiesFromHash(first.key).first
            emptyLabel.isHidden = true
        } else {
            selectedHandle = nil
            selectedHex = ""
            selectedEntity = nil
            emptyLabel.isHidden = false
        }
    }

    private func selectTorrent(hex: String, handle: TorrentHandle) {
        selectedHex = hex
        selectedHandle = handle
        selectedEntity = TorrentService.sharedTorrentService.GetTorrentEntitiesFromHash(hex).first
        emptyLabel.isHidden = true
        segmentedControl.selectedSegmentIndex = 0
        previousSegmentIndex = 0
        showTab(0)
        update()
    }

    // MARK: - Page header setup

    private func setupPageHeader() {
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

    private func setupEmptyLabel() {
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(emptyLabel)
        NSLayoutConstraint.activate([
            emptyLabel.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
        ])
    }

    // MARK: - Segmented control

    @objc private func segmentChanged(_ sender: UISegmentedControl) {
        if sender.selectedSegmentIndex == Self.settingsSegmentIndex {
            sender.selectedSegmentIndex = previousSegmentIndex
            let settingsVC = SettingsViewController()
            navigationController?.pushViewController(settingsVC, animated: true)
        } else {
            previousSegmentIndex = sender.selectedSegmentIndex
            showTab(sender.selectedSegmentIndex)
        }
    }

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

    // MARK: - Tab switching

    private func showTab(_ index: Int) {
        overviewScrollView.removeFromSuperview()
        peersView.removeFromSuperview()
        libraryScrollView.removeFromSuperview()
        removeFilesChild()

        updatePageHeader(for: index)

        switch index {
        case 0:  // Overview
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

        case 1:  // Files
            embedFilesVC()

        case 2:  // Peers
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

        case 3:  // Library
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
        vc.torrentEntity = selectedEntity
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

    // MARK: - Data update

    private func update() {
        guard let snap = selectedHandle?.snapshot else { return }

        // Header
        nameLabel.text = snap.name.isEmpty ? "No Name Provided" : snap.name
        hashLabel.text = selectedHex.isEmpty ? "—" : selectedHex

        // Progress: use totalDone/total for precision (snap.progress is unreliable during streaming)
        let progress: Float = snap.total > 0
            ? Float(Double(snap.totalDone) / Double(snap.total))
            : 0
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
        downloadedValue.text = TorrentDetailViewController.fastPrettyBytes(snap.totalDone)
        uploadedValue.text = TorrentDetailViewController.fastPrettyBytes(snap.totalUpload)
        totalSizeValue.text = TorrentDetailViewController.fastPrettyBytes(snap.total)

        // Pieces: "{count} × {size}"
        let pieceCount = snap.pieces?.count ?? 0
        let pieceLenBytes = UInt64(snap.pieceLength)
        piecesValue.text = pieceCount > 0 && pieceLenBytes > 0
            ? "\(pieceCount) × \(TorrentDetailViewController.fastPrettyBytes(pieceLenBytes))"
            : "—"

        // Speed & Transfer (Hayase: fastPrettyBits(speed.down * 8))
        downSpeedValue.text = TorrentDetailViewController.fastPrettyBits(snap.downloadRate * 8) + "/s"
        upSpeedValue.text   = TorrentDetailViewController.fastPrettyBits(snap.uploadRate * 8) + "/s"

        // Time
        let remaining = snap.total > snap.totalDone ? snap.total - snap.totalDone : 0
        let elapsed = Int(max(0, -startDate.timeIntervalSinceNow))
        etaValue.text     = TorrentDetailViewController.eta(remaining: remaining, rate: snap.downloadRate)
        elapsedValue.text = TorrentDetailViewController.eta(seconds: elapsed)

        // Peers & Connections
        seedersValue.text  = "\(snap.numberOfSeeds)"
        leechersValue.text = "\(snap.numberOfLeechers)"
        wiresValue.text    = "\(snap.numberOfPeers)"

        // Protocol status dots
        setDot(dhtDot, enabled: snap.isDhtRunning)
        setDot(lsdDot, enabled: snap.isLsdRunning)
        setDot(pexDot, enabled: snap.isPexEnabled)
        setDot(natDot, enabled: true)
        setDot(forwardDot, enabled: snap.hasIncomingConnections)
        setDot(persistDot, enabled: UserDefaults.standard.bool(forKey: "pref_persistFiles"))

        let isStreaming = snap.state == .downloading && snap.isSequential
        setDot(streamingDot, enabled: isStreaming)

        // Update peers tab if visible
        if segmentedControl.selectedSegmentIndex == 2 {
            updatePeersTab()
        }
    }

    private func updatePeersTab() {
        guard let snap = selectedHandle?.snapshot else { return }
        peerSeedersValue.text  = "\(snap.numberOfSeeds)"
        peerLeechersValue.text = "\(snap.numberOfLeechers)"
        peerWiresValue.text    = "\(snap.numberOfPeers)"
    }

    private func setDot(_ dot: UIView, enabled: Bool) {
        dot.backgroundColor = enabled ? .systemGreen : .systemRed
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
        let grid = makeProgressStatRow([
            StatItem(label: downloadedValue, title: "Downloaded", icon: "arrow.down",    color: .systemGreen),
            StatItem(label: uploadedValue,   title: "Uploaded",   icon: "arrow.up",      color: .systemBlue),
            StatItem(label: totalSizeValue,  title: "Total Size", icon: "internaldrive", color: .systemGray),
            StatItem(label: piecesValue,     title: "Pieces",     icon: "puzzlepiece",   color: .systemGray),
        ])
        container.addArrangedSubview(grid)

        return container
    }

    private func makeThreeColumnGrid() -> UIView {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 0

        // Speed & Transfer
        stack.addArrangedSubview(makeFlatSection(
            title: "Speed & Transfer",
            icon: "wifi",
            items: [
                StatItem(label: downSpeedValue, title: "Download", icon: "arrow.down", color: .systemGreen),
                StatItem(label: upSpeedValue,   title: "Upload",   icon: "arrow.up",   color: .systemBlue),
            ]
        ))

        // Time Information
        stack.addArrangedSubview(makeFlatSection(
            title: "Time Information",
            icon: "clock",
            items: [
                StatItem(label: etaValue,     title: "Remaining", icon: "hourglass.tophalf.filled", color: .systemOrange),
                StatItem(label: elapsedValue, title: "Elapsed",   icon: "timer",                    color: .systemPurple),
            ]
        ))

        // Peers & Connections
        stack.addArrangedSubview(makeFlatSection(
            title: "Peers & Connections",
            icon: "person.2.fill",
            items: [
                StatItem(label: seedersValue,  title: "Seeders",  icon: "person.fill.badge.plus",  color: .systemGreen),
                StatItem(label: leechersValue, title: "Leechers", icon: "person.fill.badge.minus", color: .systemBlue),
                StatItem(label: wiresValue,    title: "Wires",    icon: "link",                    color: .systemPurple),
            ]
        ))

        return stack
    }

    private func makeProtocolStatusSection() -> UIView {
        let container = UIStackView()
        container.axis = .vertical
        container.spacing = 12

        let iconView = makeIcon("network", tint: .label, size: 20)
        let title = UILabel()
        title.text = "Protocol Status"
        title.font = .systemFont(ofSize: 24, weight: .bold)
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
        headerLabel.font = .systemFont(ofSize: 14, weight: .medium)
        headerLabel.textColor = .label
        col.addArrangedSubview(headerLabel)

        for (name, desc, dot) in rows {
            let nameLabel = UILabel()
            nameLabel.text = name
            nameLabel.font = .systemFont(ofSize: 13, weight: .regular)
            nameLabel.textColor = .label

            let descLabel = UILabel()
            descLabel.text = desc
            descLabel.font = .systemFont(ofSize: 10, weight: .regular)
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

        let iconView = makeIcon("person.2.fill", tint: .label, size: 20)
        let title = UILabel()
        title.text = "Peers & Connections"
        title.font = .systemFont(ofSize: 24, weight: .bold)
        title.textColor = .label
        let titleRow = UIStackView(arrangedSubviews: [iconView, title])
        titleRow.axis = .horizontal
        titleRow.spacing = 8
        titleRow.alignment = .center
        stack.addArrangedSubview(titleRow)

        stack.addArrangedSubview(makeFlatStatRow([
            StatItem(label: peerSeedersValue,  title: "Seeders",  icon: "person.fill.badge.plus",  color: .systemGreen),
            StatItem(label: peerLeechersValue, title: "Leechers", icon: "person.fill.badge.minus", color: .systemBlue),
            StatItem(label: peerWiresValue,    title: "Wires",    icon: "link",                    color: .systemPurple),
        ]))
    }

    // MARK: - Build Library UI

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

        let iconView = makeIcon("books.vertical.fill", tint: .label, size: 20)
        let title = UILabel()
        title.text = "Library"
        title.font = .systemFont(ofSize: 24, weight: .bold)
        title.textColor = .label
        let titleRow = UIStackView(arrangedSubviews: [iconView, title])
        titleRow.axis = .horizontal
        titleRow.spacing = 8
        titleRow.alignment = .center
        stack.addArrangedSubview(titleRow)

        let subtitle = UILabel()
        subtitle.text = "Downloaded torrents and their content."
        subtitle.font = .systemFont(ofSize: 14, weight: .regular)
        subtitle.textColor = .secondaryLabel
        stack.addArrangedSubview(subtitle)

        libraryTableView = UITableView(frame: .zero, style: .insetGrouped)
        libraryTableView.translatesAutoresizingMaskIntoConstraints = false
        libraryTableView.delegate = self
        libraryTableView.dataSource = self
        libraryTableView.register(LibraryEntryCell.self, forCellReuseIdentifier: LibraryEntryCell.reuseID)
        libraryTableView.rowHeight = UITableView.automaticDimension
        libraryTableView.estimatedRowHeight = 80
        libraryTableView.isScrollEnabled = false
        libraryTableView.backgroundColor = .clear

        stack.addArrangedSubview(libraryTableView)
        libraryTableView.heightAnchor.constraint(greaterThanOrEqualToConstant: 100).isActive = true
    }

    private func refreshLibrary() {
        libraryEntries = TorrentService.sharedTorrentService.handles
            .map { (hash: $0.key, handle: $0.value,
                    entity: TorrentService.sharedTorrentService.GetTorrentEntitiesFromHash($0.key).first) }
            .sorted { $0.handle.snapshot.name < $1.handle.snapshot.name }
        libraryTableView?.reloadData()

        DispatchQueue.main.async { [weak self] in
            guard let self = self, let tv = self.libraryTableView else { return }
            tv.layoutIfNeeded()
            self.libraryTableHeightConstraint?.isActive = false
            self.libraryTableHeightConstraint = tv.heightAnchor.constraint(
                equalToConstant: max(tv.contentSize.height, 100))
            self.libraryTableHeightConstraint?.isActive = true
        }
    }

    // MARK: - UI helpers

    private func makeIcon(_ name: String, tint: UIColor, size: CGFloat) -> UIImageView {
        let config = UIImage.SymbolConfiguration(pointSize: size, weight: .medium)
        let iv = UIImageView(image: UIImage(systemName: name, withConfiguration: config))
        iv.tintColor = tint
        iv.contentMode = .scaleAspectFit
        iv.setContentHuggingPriority(.required, for: .horizontal)
        iv.setContentCompressionResistancePriority(.required, for: .horizontal)
        return iv
    }

    private func makeFlatSection(title: String, icon: String, items: [StatItem]) -> UIView {
        let container = UIStackView()
        container.axis = .vertical
        container.spacing = 12

        let iconView = makeIcon(icon, tint: .label, size: 20)
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 24, weight: .bold)
        titleLabel.textColor = .label

        let titleRow = UIStackView(arrangedSubviews: [iconView, titleLabel])
        titleRow.axis = .horizontal
        titleRow.spacing = 8
        titleRow.alignment = .center

        let paddedTitle = UIStackView(arrangedSubviews: [titleRow])
        paddedTitle.axis = .vertical
        paddedTitle.layoutMargins = UIEdgeInsets(top: 16, left: 0, bottom: 0, right: 0)
        paddedTitle.isLayoutMarginsRelativeArrangement = true

        container.addArrangedSubview(paddedTitle)

        let grid = makeFlatStatRow(items)
        container.addArrangedSubview(grid)

        return container
    }

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
        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        titleLabel.textColor = .secondaryLabel

        let topRow = UIStackView(arrangedSubviews: [iconView, titleLabel])
        topRow.axis = .horizontal
        topRow.spacing = 4
        topRow.alignment = .center

        item.label.font = .systemFont(ofSize: 24, weight: .bold)
        item.label.adjustsFontSizeToFitWidth = true
        item.label.minimumScaleFactor = 0.5

        let stack = UIStackView(arrangedSubviews: [topRow, item.label])
        stack.axis = .vertical
        stack.spacing = 8
        return stack
    }

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
        titleLabel.font = .systemFont(ofSize: 12, weight: .regular)
        titleLabel.textColor = .secondaryLabel

        let topRow = UIStackView(arrangedSubviews: [iconView, titleLabel])
        topRow.axis = .horizontal
        topRow.spacing = 4
        topRow.alignment = .center

        item.label.font = .systemFont(ofSize: 14, weight: .medium)
        item.label.adjustsFontSizeToFitWidth = true
        item.label.minimumScaleFactor = 0.6

        let stack = UIStackView(arrangedSubviews: [topRow, item.label])
        stack.axis = .vertical
        stack.spacing = 4
        return stack
    }
}

// MARK: - UITableViewDataSource & UITableViewDelegate

extension DownloadsViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard tableView === libraryTableView else { return 0 }
        return libraryEntries.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(
            withIdentifier: LibraryEntryCell.reuseID, for: indexPath) as! LibraryEntryCell
        guard indexPath.row < libraryEntries.count else { return cell }
        let entry = libraryEntries[indexPath.row]
        cell.configure(handle: entry.handle, entity: entry.entity)
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard indexPath.row < libraryEntries.count else { return }
        let entry = libraryEntries[indexPath.row]
        selectTorrent(hex: entry.hash, handle: entry.handle)
    }
}
