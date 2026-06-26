//
//  DownloadsViewController.swift
//  Hayase
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

    private var selectedTabIndex: Int = 0
    private static let settingsTabIndex = 4

    // MARK: - Page header

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

    // MARK: - Tab bar & containers

    private var tabButtons: [UIButton] = []
    private let tabBarContainer = UIView()

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

    // MARK: - Files tab

    private let filesView = UIView()
    private var filesTableView: UITableView!
    private let filesSearchField: UITextField = {
        let tf = UITextField()
        tf.placeholder = "Search by File Name..."
        tf.font = .nunito(ofSize: 14)
        tf.borderStyle = .none
        tf.backgroundColor = .secondarySystemBackground
        tf.layer.cornerRadius = 6
        tf.clipsToBounds = true
        tf.clearButtonMode = .whileEditing
        tf.returnKeyType = .search
        let icon = UIImageView(image: UIImage.hayaseIcon("search"))
        icon.tintColor = .secondaryLabel
        icon.contentMode = .scaleAspectFit
        icon.frame = CGRect(x: 8, y: 0, width: 24, height: 20)
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 32, height: 20))
        container.addSubview(icon)
        tf.leftView = container
        tf.leftViewMode = .always
        return tf
    }()
    private var fileEntries: [FileEntry] = []
    private var filteredFileEntries: [FileEntry] = []

    /// Column sort state for the Files tab (mirrors Hayase addSortBy plugin with toggleOrder: ['asc','desc']).
    /// Tap cycle: unsorted → asc → desc → unsorted.
    private enum FileSortColumn: Int { case name = 0, size = 1, progress = 2, streams = 3 }
    private var filesSortColumn: FileSortColumn?
    private var filesSortAscending: Bool = true

    private static let filesRowHeight: CGFloat = 48

    // MARK: - Peers tab

    private let peersView = UIView()
    private var peersTableView: UITableView!
    private var peerInfos: [PeerInfo] = []

    // MARK: - Library tab

    private let libraryView = UIView()
    private var libraryTableView: UITableView!
    private let librarySearchField: UITextField = {
        let tf = UITextField()
        tf.placeholder = "Search by Torrent Name..."
        tf.font = .nunito(ofSize: 14)
        tf.borderStyle = .none
        tf.backgroundColor = .secondarySystemBackground
        tf.layer.cornerRadius = 6
        tf.clipsToBounds = true
        tf.clearButtonMode = .whileEditing
        tf.returnKeyType = .search
        let icon = UIImageView(image: UIImage.hayaseIcon("search"))
        icon.tintColor = .secondaryLabel
        icon.contentMode = .scaleAspectFit
        icon.frame = CGRect(x: 8, y: 0, width: 24, height: 20)
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 32, height: 20))
        container.addSubview(icon)
        tf.leftView = container
        tf.leftViewMode = .always
        return tf
    }()
    private var filteredLibraryEntries: [(hash: String, handle: TorrentHandle, entity: Torrents?)] = []

    private var webStatus: WebTorrentBridgeStatus?
    private var webInfo: WebTorrentTorrentInfo?
    private var webProtocol: WebTorrentProtocolStatus?
    private var webFileInfos: [WebTorrentFileInfo] = []
    private var webFilteredFileInfos: [WebTorrentFileInfo] = []
    private var webFileInfoHash: String?
    private var webPeerInfos: [WebTorrentPeerInfo] = []
    private var webLibraryEntries: [WebTorrentLibraryEntry] = []
    private var webFilteredLibraryEntries: [WebTorrentLibraryEntry] = []
    private var webUpdateInFlight = false
    private var webLastError: Error?

    private var selectedLibraryHashes: Set<String> = []
    private let librarySelectionLabel: UILabel = {
        let l = UILabel()
        l.font = .nunito(ofSize: 13)
        l.textColor = .secondaryLabel
        l.text = "0 of 0 row(s) selected."
        l.textAlignment = .right
        return l
    }()

    // MARK: - Empty state

    private let emptyLabel: UILabel = {
        let l = UILabel()
        l.text = "No active downloads"
        l.textColor = .secondaryLabel
        l.font = .nunito(ofSize: 17)
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
                                  image: UIImage.hayaseIcon("download"),
                                  selectedImage: UIImage.hayaseIcon("download"))
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
        buildFilesUI()
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

    private var isWebTorrentMode: Bool {
        TorrentBackendManager.shared.currentKind == .webtorrent
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

    private func readSnapshot<T>(from handle: TorrentHandle?, default defaultValue: T, _ body: (TorrentHandle.Snapshot) -> T) -> T {
        guard let handle else { return defaultValue }
        return TorrentService.sharedTorrentService.withActiveHandle(handle, default: defaultValue) { activeHandle in
            body(activeHandle.snapshot)
        }
    }

    private func snapshotName(for handle: TorrentHandle) -> String {
        readSnapshot(from: handle, default: "") { $0.name }
    }

    // MARK: - Torrent selection

    private func autoSelectFirstTorrent() {
        if isWebTorrentMode {
            selectedHandle = nil
            selectedEntity = nil
            if selectedHex.isEmpty {
                selectedHex = webStatus?.infoHash ?? webLibraryEntries.first?.hash ?? ""
            }
            emptyLabel.isHidden = !selectedHex.isEmpty || webStatus != nil || !webLibraryEntries.isEmpty
            return
        }

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
        if let first = handles.sorted(by: { snapshotName(for: $0.value) < snapshotName(for: $1.value) }).first {
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
        selectedTabIndex = 0
        updateTabButtonAppearances()
        showTab(0)
        update()
    }

    // MARK: - Page header setup

    private func setupPageHeader() {
        pageTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        pageSubtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        tabBarContainer.translatesAutoresizingMaskIntoConstraints = false

        let separator = UIView()
        separator.backgroundColor = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false

        let tabGrid = buildTabGrid()
        tabGrid.translatesAutoresizingMaskIntoConstraints = false
        tabBarContainer.addSubview(tabGrid)

        view.addSubview(pageTitleLabel)
        view.addSubview(pageSubtitleLabel)
        view.addSubview(separator)
        view.addSubview(tabBarContainer)

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

            tabBarContainer.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 12),
            tabBarContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            tabBarContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            tabGrid.topAnchor.constraint(equalTo: tabBarContainer.topAnchor),
            tabGrid.leadingAnchor.constraint(equalTo: tabBarContainer.leadingAnchor),
            tabGrid.trailingAnchor.constraint(equalTo: tabBarContainer.trailingAnchor),
            tabGrid.bottomAnchor.constraint(equalTo: tabBarContainer.bottomAnchor),
        ])
    }

    private func setupContainerView() {
        containerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(containerView)

        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: tabBarContainer.bottomAnchor, constant: 8),
            containerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func setupEmptyLabel() {
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(emptyLabel)
        NSLayoutConstraint.activate([
            emptyLabel.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
        ])
    }

    // MARK: - Tab bar

    private func buildTabGrid() -> UIView {
        let vStack = UIStackView()
        vStack.axis = .vertical
        vStack.spacing = 4

        tabButtons.removeAll()

        let titles = ["Overview", "Files", "Peers", "Library", "Settings"]
        for rowStart in stride(from: 0, to: titles.count, by: 2) {
            let hStack = UIStackView()
            hStack.axis = .horizontal
            hStack.spacing = 8
            hStack.distribution = .fillEqually

            let btn1 = makeTabButton(title: titles[rowStart], tag: rowStart)
            hStack.addArrangedSubview(btn1)
            tabButtons.append(btn1)

            if rowStart + 1 < titles.count {
                let btn2 = makeTabButton(title: titles[rowStart + 1], tag: rowStart + 1)
                hStack.addArrangedSubview(btn2)
                tabButtons.append(btn2)
            }

            vStack.addArrangedSubview(hStack)
        }

        return vStack
    }

    private func makeTabButton(title: String, tag: Int) -> UIButton {
        let btn = UIButton(type: .system)
        btn.setTitle(title, for: .normal)
        btn.contentHorizontalAlignment = .leading
        btn.titleLabel?.font = .nunito(ofSize: 14, weight: .semibold)
        btn.layer.cornerRadius = 6
        btn.contentEdgeInsets = UIEdgeInsets(top: 10, left: 14, bottom: 10, right: 14)
        btn.tag = tag
        btn.addTarget(self, action: #selector(tabButtonTapped(_:)), for: .touchUpInside)
        updateTabButtonAppearance(btn, isSelected: tag == selectedTabIndex)
        return btn
    }

    private func updateTabButtonAppearance(_ btn: UIButton, isSelected: Bool) {
        if isSelected {
            btn.backgroundColor = .label
            btn.setTitleColor(.systemBackground, for: .normal)
        } else {
            btn.backgroundColor = .clear
            btn.setTitleColor(.label, for: .normal)
        }
    }

    private func updateTabButtonAppearances() {
        for btn in tabButtons {
            updateTabButtonAppearance(btn, isSelected: btn.tag == selectedTabIndex)
        }
    }

    @objc private func tabButtonTapped(_ sender: UIButton) {
        let index = sender.tag
        if index == Self.settingsTabIndex {
            let settingsVC = SettingsViewController()
            navigationController?.pushViewController(settingsVC, animated: true)
        } else {
            selectedTabIndex = index
            updateTabButtonAppearances()
            showTab(index)
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
        filesView.removeFromSuperview()
        peersView.removeFromSuperview()
        libraryView.removeFromSuperview()

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
            filesView.isHidden = false
            containerView.addSubview(filesView)
            filesView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                filesView.topAnchor.constraint(equalTo: containerView.topAnchor),
                filesView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
                filesView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
                filesView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            ])
            refreshFiles()

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

        case 3:  // Library
            libraryView.isHidden = false
            containerView.addSubview(libraryView)
            libraryView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                libraryView.topAnchor.constraint(equalTo: containerView.topAnchor),
                libraryView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
                libraryView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
                libraryView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            ])
            refreshLibrary()

        default:
            break
        }
    }

    // MARK: - Files tab

    private func buildFilesUI() {
        filesView.backgroundColor = .systemBackground

        filesSearchField.translatesAutoresizingMaskIntoConstraints = false
        filesSearchField.addTarget(self, action: #selector(filesSearchChanged), for: .editingChanged)
        filesView.addSubview(filesSearchField)

        let borderContainer = UIView()
        borderContainer.layer.cornerRadius = 6
        borderContainer.layer.borderWidth = 1
        borderContainer.layer.borderColor = UIColor.separator.cgColor
        borderContainer.clipsToBounds = true
        borderContainer.translatesAutoresizingMaskIntoConstraints = false
        filesView.addSubview(borderContainer)

        filesTableView = UITableView(frame: .zero, style: .plain)
        filesTableView.translatesAutoresizingMaskIntoConstraints = false
        filesTableView.delegate = self
        filesTableView.dataSource = self
        filesTableView.register(FileEntryTableCell.self, forCellReuseIdentifier: FileEntryTableCell.reuseID)
        filesTableView.rowHeight = Self.filesRowHeight
        filesTableView.estimatedRowHeight = Self.filesRowHeight
        filesTableView.backgroundColor = .systemBackground
        filesTableView.separatorInset = .zero
        if #available(iOS 15.0, *) {
            filesTableView.sectionHeaderTopPadding = 0
        }
        borderContainer.addSubview(filesTableView)

        NSLayoutConstraint.activate([
            filesSearchField.topAnchor.constraint(equalTo: filesView.topAnchor, constant: 16),
            filesSearchField.leadingAnchor.constraint(equalTo: filesView.leadingAnchor, constant: 16),
            filesSearchField.trailingAnchor.constraint(equalTo: filesView.trailingAnchor, constant: -16),
            filesSearchField.heightAnchor.constraint(equalToConstant: 36),

            borderContainer.topAnchor.constraint(equalTo: filesSearchField.bottomAnchor, constant: 12),
            borderContainer.leadingAnchor.constraint(equalTo: filesView.leadingAnchor, constant: 16),
            borderContainer.trailingAnchor.constraint(equalTo: filesView.trailingAnchor, constant: -16),
            borderContainer.bottomAnchor.constraint(equalTo: filesView.bottomAnchor, constant: -16),

            filesTableView.topAnchor.constraint(equalTo: borderContainer.topAnchor),
            filesTableView.leadingAnchor.constraint(equalTo: borderContainer.leadingAnchor),
            filesTableView.trailingAnchor.constraint(equalTo: borderContainer.trailingAnchor),
            filesTableView.bottomAnchor.constraint(equalTo: borderContainer.bottomAnchor),
        ])
    }

    @objc private func filesSearchChanged() {
        refreshFiles()
    }

    private func refreshFiles() {
        if isWebTorrentMode {
            refreshWebTorrentFiles()
            return
        }

        fileEntries = readSnapshot(from: selectedHandle, default: []) { $0.files }
        let query = filesSearchField.text?.lowercased() ?? ""
        if query.isEmpty {
            filteredFileEntries = fileEntries
        } else {
            filteredFileEntries = fileEntries.filter { $0.name.lowercased().contains(query) }
        }
        // Apply column sort (mirrors Hayase addSortBy plugin: asc → desc → clear)
        if let sortCol = filesSortColumn {
            let ascending = filesSortAscending
            let sequential = readSnapshot(from: selectedHandle, default: false) { $0.isSequential }
            filteredFileEntries.sort { a, b in
                switch sortCol {
                case .name:
                    return ascending ? a.name < b.name : a.name > b.name
                case .size:
                    return ascending ? a.size < b.size : a.size > b.size
                case .progress:
                    return ascending ? a.progress < b.progress : a.progress > b.progress
                case .streams:
                    let aS = (sequential && a.priority != .dontDownload) ? 1 : 0
                    let bS = (sequential && b.priority != .dontDownload) ? 1 : 0
                    return ascending ? aS < bS : aS > bS
                }
            }
        }
        filesTableView?.reloadData()
    }

    private func refreshWebTorrentFiles() {
        let query = filesSearchField.text?.lowercased() ?? ""
        webFilteredFileInfos = query.isEmpty
            ? webFileInfos
            : webFileInfos.filter { $0.name.lowercased().contains(query) }

        if let sortCol = filesSortColumn {
            let ascending = filesSortAscending
            webFilteredFileInfos.sort { a, b in
                switch sortCol {
                case .name:
                    return ascending ? a.name < b.name : a.name > b.name
                case .size:
                    return ascending ? a.size < b.size : a.size > b.size
                case .progress:
                    return ascending ? a.progress < b.progress : a.progress > b.progress
                case .streams:
                    return ascending ? a.selections < b.selections : a.selections > b.selections
                }
            }
        }
        filesTableView?.reloadData()
    }

    private func refreshPeers() {
        if isWebTorrentMode {
            peersTableView?.reloadData()
            return
        }

        if let selectedHandle {
            peerInfos = TorrentService.sharedTorrentService.withActiveHandle(selectedHandle, default: []) { $0.peerInfo() }
        } else {
            peerInfos = []
        }
        peersTableView?.reloadData()
    }

    // MARK: - Data update

    private func update() {
        if isWebTorrentMode {
            updateWebTorrent()
            return
        }

        let snap = readSnapshot(from: selectedHandle, default: nil) { Optional($0) }
        guard let snap else { return }

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

        // Update files tab if visible
        if selectedTabIndex == 1 {
            refreshFiles()
        }

        // Update peers tab if visible
        if selectedTabIndex == 2 {
            refreshPeers()
        }

        // Update library tab if visible
        if selectedTabIndex == 3 {
            refreshLibrary()
        }
    }

    private func updateWebTorrent() {
        guard !webUpdateInFlight else { return }
        webUpdateInFlight = true

        let manager = TorrentBackendManager.shared
        manager.webTorrentStatus { [weak self] statusResult in
            guard let self else { return }

            let status = try? statusResult.get()
            let requestedHash = status?.infoHash ?? self.selectedHex

            let group = DispatchGroup()
            var nextInfo: WebTorrentTorrentInfo?
            var nextFiles: [WebTorrentFileInfo] = []
            var nextPeers: [WebTorrentPeerInfo] = []
            var nextLibrary: [WebTorrentLibraryEntry] = []
            var nextProtocol: WebTorrentProtocolStatus?
            var nextError: Error?

            if case .failure(let error) = statusResult {
                nextError = error
            }

            group.enter()
            manager.webTorrentLibrary { result in
                if case .success(let entries) = result { nextLibrary = entries }
                group.leave()
            }

            if !requestedHash.isEmpty {
                group.enter()
                manager.webTorrentInfo(hash: requestedHash) { result in
                    if case .success(let info) = result { nextInfo = info }
                    group.leave()
                }

                group.enter()
                manager.webTorrentFileInfo(hash: requestedHash) { result in
                    if case .success(let files) = result { nextFiles = files }
                    group.leave()
                }

                group.enter()
                manager.webTorrentPeerInfo(hash: requestedHash) { result in
                    if case .success(let peers) = result { nextPeers = peers }
                    group.leave()
                }

                group.enter()
                manager.webTorrentProtocolStatus(hash: requestedHash) { result in
                    if case .success(let protocolStatus) = result { nextProtocol = protocolStatus }
                    group.leave()
                }
            }

            group.notify(queue: .main) { [weak self] in
                guard let self else { return }
                self.webUpdateInFlight = false
                self.applyWebTorrentState(status: status,
                                           info: nextInfo,
                                           files: nextFiles,
                                           peers: nextPeers,
                                           library: nextLibrary,
                                           protocolStatus: nextProtocol,
                                           error: nextError)
            }
        }
    }

    private func applyWebTorrentState(status: WebTorrentBridgeStatus?,
                                      info: WebTorrentTorrentInfo?,
                                      files: [WebTorrentFileInfo],
                                      peers: [WebTorrentPeerInfo],
                                      library: [WebTorrentLibraryEntry],
                                      protocolStatus: WebTorrentProtocolStatus?,
                                      error: Error?) {
        if let status { webStatus = status }
        if let info { webInfo = info }
        if let protocolStatus { webProtocol = protocolStatus }
        if !peers.isEmpty { webPeerInfos = peers }
        if !library.isEmpty { webLibraryEntries = library }
        webLastError = error

        let resolvedStatus = status ?? webStatus
        let resolvedInfo = info ?? webInfo
        let resolvedProtocol = protocolStatus ?? webProtocol
        let resolvedLibrary = library.isEmpty ? webLibraryEntries : library

        let knownHashes = Set(resolvedLibrary.map { $0.hash } + [resolvedStatus?.infoHash, resolvedInfo?.hash].compactMap { $0 })
        if !selectedHex.isEmpty && !knownHashes.isEmpty && !knownHashes.contains(selectedHex) {
            selectedHex = ""
        }
        if selectedHex.isEmpty {
            selectedHex = resolvedStatus?.infoHash ?? resolvedInfo?.hash ?? resolvedLibrary.first?.hash ?? ""
        }

        if webFileInfoHash != selectedHex && !files.isEmpty {
            webFileInfos = []
            webFileInfoHash = selectedHex.isEmpty ? nil : selectedHex
        }
        if !files.isEmpty {
            webFileInfos = files
            webFileInfoHash = selectedHex.isEmpty ? (resolvedInfo?.hash ?? resolvedStatus?.infoHash) : selectedHex
        }

        let hasTorrent = !selectedHex.isEmpty || resolvedStatus?.infoHash != nil || resolvedInfo != nil || !resolvedLibrary.isEmpty
        emptyLabel.isHidden = hasTorrent
        if !hasTorrent {
            clearWebTorrentOverview(error: error)
            refreshFiles()
            refreshPeers()
            refreshLibrary()
            return
        }

        let currentLibraryEntry = resolvedLibrary.first { $0.hash == selectedHex } ?? resolvedLibrary.first
        nameLabel.text = resolvedInfo?.name ?? currentLibraryEntry?.name ?? resolvedStatus?.source ?? "WebTorrent"
        hashLabel.text = selectedHex.isEmpty ? (resolvedStatus?.infoHash ?? "—") : selectedHex

        let progress = resolvedInfo?.progress ?? resolvedStatus?.progress ?? currentLibraryEntry?.progress ?? 0
        let completed = progress >= 0.999
        statusBadge.text = completed ? "Seeding" : resolvedStatus?.phase.replacingOccurrences(of: "-", with: " ").capitalized ?? "Downloading"
        statusBadge.backgroundColor = completed ? .systemBlue : .systemGreen
        bigPercentLabel.text = String(format: "%.1f%%", progress * 100)
        progressBar.progress = Float(max(0, min(progress, 1)))

        let downloaded = resolvedInfo?.size.downloaded ?? resolvedStatus?.downloaded ?? 0
        let uploaded = resolvedInfo?.size.uploaded ?? resolvedStatus?.uploaded ?? 0
        let total = resolvedInfo?.size.total ?? resolvedStatus?.total ?? currentLibraryEntry?.size ?? 0
        downloadedValue.text = TorrentDetailViewController.fastPrettyBytes(downloaded)
        uploadedValue.text = TorrentDetailViewController.fastPrettyBytes(uploaded)
        totalSizeValue.text = TorrentDetailViewController.fastPrettyBytes(total)

        if let pieces = resolvedInfo?.pieces, pieces.total > 0 {
            piecesValue.text = "\(pieces.total) × \(TorrentDetailViewController.fastPrettyBytes(pieces.size))"
        } else {
            piecesValue.text = "—"
        }

        let down = resolvedInfo?.speed.down ?? resolvedStatus?.downloadSpeed ?? 0
        let up = resolvedInfo?.speed.up ?? resolvedStatus?.uploadSpeed ?? 0
        downSpeedValue.text = TorrentDetailViewController.fastPrettyBits(down * 8) + "/s"
        upSpeedValue.text = TorrentDetailViewController.fastPrettyBits(up * 8) + "/s"
        etaValue.text = webTorrentETA(fromMilliseconds: resolvedInfo?.time.remaining)
            ?? TorrentDetailViewController.eta(remaining: total > downloaded ? total - downloaded : 0, rate: down)
        elapsedValue.text = webTorrentETA(fromMilliseconds: resolvedInfo?.time.elapsed)
            ?? TorrentDetailViewController.eta(seconds: Int(max(0, -startDate.timeIntervalSinceNow)))

        seedersValue.text = "\(resolvedInfo?.peers.seeders ?? 0)"
        leechersValue.text = "\(resolvedInfo?.peers.leechers ?? 0)"
        wiresValue.text = "\(resolvedInfo?.peers.wires ?? resolvedStatus?.wires ?? 0)"

        setDot(dhtDot, enabled: resolvedProtocol?.dht ?? resolvedStatus?.dht ?? false)
        setDot(lsdDot, enabled: resolvedProtocol?.lsd ?? false)
        setDot(pexDot, enabled: resolvedProtocol?.pex ?? resolvedStatus?.pex ?? false)
        setDot(natDot, enabled: resolvedProtocol?.nat ?? false)
        setDot(forwardDot, enabled: resolvedProtocol?.forwarding ?? false)
        setDot(persistDot, enabled: resolvedProtocol?.persisting ?? UserDefaults.standard.bool(forKey: "pref_persistFiles"))
        setDot(streamingDot, enabled: resolvedProtocol?.streaming ?? false)

        if selectedTabIndex == 1 { refreshFiles() }
        if selectedTabIndex == 2 { refreshPeers() }
        if selectedTabIndex == 3 { refreshLibrary() }
    }

    private func webTorrentETA(fromMilliseconds value: Double?) -> String? {
        guard let value, value.isFinite, value > 0 else { return nil }
        return TorrentDetailViewController.eta(seconds: Int(value / 1000))
    }

    private func clearWebTorrentOverview(error: Error?) {
        nameLabel.text = error?.localizedDescription ?? "No active WebTorrent download"
        hashLabel.text = "—"
        statusBadge.text = error == nil ? "Idle" : "Error"
        statusBadge.backgroundColor = error == nil ? .secondaryLabel : .systemRed
        bigPercentLabel.text = "0.0%"
        progressBar.progress = 0
        for label in [downloadedValue, uploadedValue, totalSizeValue, piecesValue,
                      downSpeedValue, upSpeedValue, etaValue, elapsedValue,
                      seedersValue, leechersValue, wiresValue] {
            label.text = "—"
        }
        for dot in [dhtDot, lsdDot, pexDot, natDot, forwardDot, persistDot, streamingDot] {
            setDot(dot, enabled: false)
        }
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
        let grid = makeProgressStatRow([
            StatItem(label: downloadedValue, title: "Downloaded", icon: "download",   color: .systemGreen),
            StatItem(label: uploadedValue,   title: "Uploaded",   icon: "upload",     color: .systemBlue),
            StatItem(label: totalSizeValue,  title: "Total Size", icon: "hard-drive", color: .systemGray),
            StatItem(label: piecesValue,     title: "Pieces",     icon: "puzzle",     color: .systemGray),
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

    private func makeProtocolStatusSection() -> UIView {
        let container = UIStackView()
        container.axis = .vertical
        container.spacing = 12

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

        let borderContainer = UIView()
        borderContainer.layer.cornerRadius = 6
        borderContainer.layer.borderWidth = 1
        borderContainer.layer.borderColor = UIColor.separator.cgColor
        borderContainer.clipsToBounds = true
        borderContainer.translatesAutoresizingMaskIntoConstraints = false
        peersView.addSubview(borderContainer)

        peersTableView = UITableView(frame: .zero, style: .plain)
        peersTableView.translatesAutoresizingMaskIntoConstraints = false
        peersTableView.delegate = self
        peersTableView.dataSource = self
        peersTableView.register(PeerInfoCell.self, forCellReuseIdentifier: PeerInfoCell.reuseID)
        peersTableView.rowHeight = 48
        peersTableView.estimatedRowHeight = 48
        peersTableView.backgroundColor = .systemBackground
        peersTableView.separatorInset = .zero
        peersTableView.allowsSelection = false
        borderContainer.addSubview(peersTableView)

        NSLayoutConstraint.activate([
            borderContainer.topAnchor.constraint(equalTo: peersView.topAnchor, constant: 16),
            borderContainer.leadingAnchor.constraint(equalTo: peersView.leadingAnchor, constant: 16),
            borderContainer.trailingAnchor.constraint(equalTo: peersView.trailingAnchor, constant: -16),
            borderContainer.bottomAnchor.constraint(equalTo: peersView.bottomAnchor, constant: -16),

            peersTableView.topAnchor.constraint(equalTo: borderContainer.topAnchor),
            peersTableView.leadingAnchor.constraint(equalTo: borderContainer.leadingAnchor),
            peersTableView.trailingAnchor.constraint(equalTo: borderContainer.trailingAnchor),
            peersTableView.bottomAnchor.constraint(equalTo: borderContainer.bottomAnchor),
        ])
    }

    // MARK: - Build Library UI

    private func buildLibraryUI() {
        libraryView.backgroundColor = .systemBackground

        librarySearchField.translatesAutoresizingMaskIntoConstraints = false
        librarySearchField.addTarget(self, action: #selector(librarySearchChanged), for: .editingChanged)
        libraryView.addSubview(librarySearchField)

        let rescanBtn = UIButton(type: .system)
        let rescanConfig = UIImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        rescanBtn.setImage(UIImage.hayaseIcon("refresh-cw", withConfiguration: rescanConfig), for: .normal)
        rescanBtn.tintColor = .label
        rescanBtn.backgroundColor = .secondarySystemBackground
        rescanBtn.layer.cornerRadius = 6
        rescanBtn.addTarget(self, action: #selector(rescanLibrary), for: .touchUpInside)
        rescanBtn.translatesAutoresizingMaskIntoConstraints = false

        let deleteBtn = UIButton(type: .system)
        let deleteConfig = UIImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        deleteBtn.setImage(UIImage.hayaseIcon("trash-2", withConfiguration: deleteConfig), for: .normal)
        deleteBtn.tintColor = .white
        deleteBtn.backgroundColor = .systemRed
        deleteBtn.layer.cornerRadius = 6
        deleteBtn.addTarget(self, action: #selector(deleteSelectedLibraryEntries), for: .touchUpInside)
        deleteBtn.translatesAutoresizingMaskIntoConstraints = false

        let buttonRow = UIStackView(arrangedSubviews: [rescanBtn, deleteBtn])
        buttonRow.axis = .horizontal
        buttonRow.spacing = 8
        buttonRow.translatesAutoresizingMaskIntoConstraints = false
        libraryView.addSubview(buttonRow)

        librarySelectionLabel.translatesAutoresizingMaskIntoConstraints = false
        libraryView.addSubview(librarySelectionLabel)

        let borderContainer = UIView()
        borderContainer.layer.cornerRadius = 6
        borderContainer.layer.borderWidth = 1
        borderContainer.layer.borderColor = UIColor.separator.cgColor
        borderContainer.clipsToBounds = true
        borderContainer.translatesAutoresizingMaskIntoConstraints = false
        libraryView.addSubview(borderContainer)

        libraryTableView = UITableView(frame: .zero, style: .plain)
        libraryTableView.translatesAutoresizingMaskIntoConstraints = false
        libraryTableView.delegate = self
        libraryTableView.dataSource = self
        libraryTableView.register(LibraryColumnCell.self, forCellReuseIdentifier: LibraryColumnCell.reuseID)
        libraryTableView.rowHeight = 56
        libraryTableView.estimatedRowHeight = 56
        libraryTableView.backgroundColor = .systemBackground
        libraryTableView.separatorInset = .zero
        borderContainer.addSubview(libraryTableView)

        NSLayoutConstraint.activate([
            rescanBtn.widthAnchor.constraint(equalToConstant: 36),
            rescanBtn.heightAnchor.constraint(equalToConstant: 36),
            deleteBtn.widthAnchor.constraint(equalToConstant: 36),
            deleteBtn.heightAnchor.constraint(equalToConstant: 36),

            librarySearchField.topAnchor.constraint(equalTo: libraryView.topAnchor, constant: 16),
            librarySearchField.leadingAnchor.constraint(equalTo: libraryView.leadingAnchor, constant: 16),
            librarySearchField.trailingAnchor.constraint(equalTo: buttonRow.leadingAnchor, constant: -8),
            librarySearchField.heightAnchor.constraint(equalToConstant: 36),

            buttonRow.topAnchor.constraint(equalTo: libraryView.topAnchor, constant: 16),
            buttonRow.trailingAnchor.constraint(equalTo: libraryView.trailingAnchor, constant: -16),

            librarySelectionLabel.topAnchor.constraint(equalTo: librarySearchField.bottomAnchor, constant: 8),
            librarySelectionLabel.leadingAnchor.constraint(equalTo: libraryView.leadingAnchor, constant: 16),
            librarySelectionLabel.trailingAnchor.constraint(equalTo: libraryView.trailingAnchor, constant: -16),

            borderContainer.topAnchor.constraint(equalTo: librarySelectionLabel.bottomAnchor, constant: 8),
            borderContainer.leadingAnchor.constraint(equalTo: libraryView.leadingAnchor, constant: 16),
            borderContainer.trailingAnchor.constraint(equalTo: libraryView.trailingAnchor, constant: -16),
            borderContainer.bottomAnchor.constraint(equalTo: libraryView.bottomAnchor, constant: -16),

            libraryTableView.topAnchor.constraint(equalTo: borderContainer.topAnchor),
            libraryTableView.leadingAnchor.constraint(equalTo: borderContainer.leadingAnchor),
            libraryTableView.trailingAnchor.constraint(equalTo: borderContainer.trailingAnchor),
            libraryTableView.bottomAnchor.constraint(equalTo: borderContainer.bottomAnchor),
        ])
    }

    @objc private func librarySearchChanged() {
        refreshLibrary()
    }

    @objc private func rescanLibrary() {
        if isWebTorrentMode {
            update()
        } else {
            refreshLibrary()
        }
    }

    private func refreshLibrary() {
        if isWebTorrentMode {
            let query = librarySearchField.text?.lowercased() ?? ""
            webFilteredLibraryEntries = query.isEmpty
                ? webLibraryEntries
                : webLibraryEntries.filter { $0.name.lowercased().contains(query) || $0.hash.lowercased().contains(query) }
            let currentHashes = Set(webFilteredLibraryEntries.map { $0.hash })
            selectedLibraryHashes.formIntersection(currentHashes)
            updateLibrarySelectionLabel()
            libraryTableView?.reloadData()
            return
        }

        libraryEntries = TorrentService.sharedTorrentService.handles
            .map { (hash: $0.key, handle: $0.value,
                    entity: TorrentService.sharedTorrentService.GetTorrentEntitiesFromHash($0.key).first) }
            .sorted { snapshotName(for: $0.handle) < snapshotName(for: $1.handle) }
        let query = librarySearchField.text?.lowercased() ?? ""
        if query.isEmpty {
            filteredLibraryEntries = libraryEntries
        } else {
            filteredLibraryEntries = libraryEntries.filter {
                snapshotName(for: $0.handle).lowercased().contains(query)
            }
        }
        // Prune selections that no longer exist
        let currentHashes = Set(filteredLibraryEntries.map { $0.hash })
        selectedLibraryHashes.formIntersection(currentHashes)
        updateLibrarySelectionLabel()
        libraryTableView?.reloadData()
    }

    private func updateLibrarySelectionLabel() {
        let rowCount = isWebTorrentMode ? webFilteredLibraryEntries.count : filteredLibraryEntries.count
        librarySelectionLabel.text = "\(selectedLibraryHashes.count) of \(rowCount) row(s) selected."
    }

    @objc private func deleteSelectedLibraryEntries() {
        guard !selectedLibraryHashes.isEmpty else { return }

        let count = selectedLibraryHashes.count
        let alert = UIAlertController(
            title: "Delete \(count) torrent\(count == 1 ? "" : "s")?",
            message: "This will remove the selected torrent\(count == 1 ? "" : "s") and delete all associated files.",
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            guard let self = self else { return }
            let hashes = Array(self.selectedLibraryHashes)

            if self.isWebTorrentMode {
                TorrentBackendManager.shared.deleteWebTorrents(hashes: hashes) { [weak self] _ in
                    DispatchQueue.main.async {
                        guard let self else { return }
                        if hashes.contains(self.selectedHex) { self.selectedHex = "" }
                        self.selectedLibraryHashes.removeAll()
                        self.update()
                    }
                }
                return
            }

            let service = TorrentService.sharedTorrentService
            for hash in hashes {
                if let handle = service.handles[hash] {
                    service.safeRemoveTorrent(handle, deleteFiles: true)
                }
            }
            // Clear selected torrent if it was deleted
            if hashes.contains(self.selectedHex) {
                self.selectedHandle = nil
                self.selectedHex = ""
                self.selectedEntity = nil
            }
            self.selectedLibraryHashes.removeAll()
            self.refreshLibrary()
        })
        present(alert, animated: true)
    }

    // MARK: - UI helpers

    private func makeIcon(_ name: String, tint: UIColor, size: CGFloat) -> UIImageView {
        let config = UIImage.SymbolConfiguration(pointSize: size, weight: .medium)
        let iv = UIImageView(image: UIImage.hayaseIcon(name, withConfiguration: config))
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
        titleLabel.font = .nunito(ofSize: 24, weight: .bold)
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
}

// MARK: - UITableViewDataSource & UITableViewDelegate

extension DownloadsViewController: UITableViewDataSource, UITableViewDelegate {

    private func emptyTableCell(text: String) -> UITableViewCell {
        let cell = UITableViewCell()
        cell.textLabel?.text = text
        cell.textLabel?.textAlignment = .center
        cell.textLabel?.textColor = .secondaryLabel
        cell.textLabel?.font = .nunito(ofSize: 14)
        cell.selectionStyle = .none
        return cell
    }

    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if tableView === filesTableView {
            return max(isWebTorrentMode ? webFilteredFileInfos.count : filteredFileEntries.count, 1)
        } else if tableView === peersTableView {
            return max(isWebTorrentMode ? webPeerInfos.count : peerInfos.count, 1)
        } else if tableView === libraryTableView {
            return max(isWebTorrentMode ? webFilteredLibraryEntries.count : filteredLibraryEntries.count, 1)
        }
        return 0
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if tableView === filesTableView {
            if isWebTorrentMode {
                if webFilteredFileInfos.isEmpty {
                    return emptyTableCell(text: "No files loaded yet.")
                }
                guard let cell = tableView.dequeueReusableCell(
                    withIdentifier: FileEntryTableCell.reuseID, for: indexPath) as? FileEntryTableCell else { return UITableViewCell() }
                guard indexPath.row < webFilteredFileInfos.count else { return cell }
                cell.configure(entry: webFilteredFileInfos[indexPath.row])
                return cell
            }

            if filteredFileEntries.isEmpty {
                return emptyTableCell(text: "No files downloaded yet.")
            }
            guard let cell = tableView.dequeueReusableCell(
                withIdentifier: FileEntryTableCell.reuseID, for: indexPath) as? FileEntryTableCell else { return UITableViewCell() }
            guard indexPath.row < filteredFileEntries.count else { return cell }
            let entry = filteredFileEntries[indexPath.row]
            let isStreaming = readSnapshot(from: selectedHandle, default: false) { $0.isSequential }
                && entry.priority != .dontDownload
            cell.configure(entry: entry, streamCount: isStreaming ? 1 : 0)
            return cell
        } else if tableView === peersTableView {
            if isWebTorrentMode {
                if webPeerInfos.isEmpty {
                    return emptyTableCell(text: "No peers connected yet.")
                }
                guard let cell = tableView.dequeueReusableCell(
                    withIdentifier: PeerInfoCell.reuseID, for: indexPath) as? PeerInfoCell else { return UITableViewCell() }
                guard indexPath.row < webPeerInfos.count else { return cell }
                cell.configure(peer: webPeerInfos[indexPath.row])
                return cell
            }

            if peerInfos.isEmpty {
                return emptyTableCell(text: "No peers connected yet.")
            }
            guard let cell = tableView.dequeueReusableCell(
                withIdentifier: PeerInfoCell.reuseID, for: indexPath) as? PeerInfoCell else { return UITableViewCell() }
            guard indexPath.row < peerInfos.count else { return cell }
            cell.configure(peer: peerInfos[indexPath.row])
            return cell
        } else if tableView === libraryTableView {
            if isWebTorrentMode {
                if webFilteredLibraryEntries.isEmpty {
                    return emptyTableCell(text: "No torrents downloaded yet.")
                }
                guard let cell = tableView.dequeueReusableCell(
                    withIdentifier: LibraryColumnCell.reuseID, for: indexPath) as? LibraryColumnCell else { return UITableViewCell() }
                guard indexPath.row < webFilteredLibraryEntries.count else { return cell }
                let entry = webFilteredLibraryEntries[indexPath.row]
                cell.configure(entry: entry)
                cell.accessoryType = selectedLibraryHashes.contains(entry.hash) ? .checkmark : .none
                return cell
            }

            if filteredLibraryEntries.isEmpty {
                return emptyTableCell(text: "No torrents downloaded yet.")
            }
            guard let cell = tableView.dequeueReusableCell(
                withIdentifier: LibraryColumnCell.reuseID, for: indexPath) as? LibraryColumnCell else { return UITableViewCell() }
            guard indexPath.row < filteredLibraryEntries.count else { return cell }
            let entry = filteredLibraryEntries[indexPath.row]
            cell.configure(handle: entry.handle, entity: entry.entity)
            cell.accessoryType = selectedLibraryHashes.contains(entry.hash) ? .checkmark : .none
            return cell
        }
        return UITableViewCell()
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if tableView === libraryTableView {
            if isWebTorrentMode {
                guard indexPath.row < webFilteredLibraryEntries.count else { return }
                let entry = webFilteredLibraryEntries[indexPath.row]
                selectedHex = entry.hash
                if selectedLibraryHashes.contains(entry.hash) {
                    selectedLibraryHashes.remove(entry.hash)
                } else {
                    selectedLibraryHashes.insert(entry.hash)
                }
                updateLibrarySelectionLabel()
                tableView.reloadRows(at: [indexPath], with: .none)
                update()
                return
            }

            guard indexPath.row < filteredLibraryEntries.count else { return }
            let entry = filteredLibraryEntries[indexPath.row]
            if selectedLibraryHashes.contains(entry.hash) {
                selectedLibraryHashes.remove(entry.hash)
            } else {
                selectedLibraryHashes.insert(entry.hash)
            }
            updateLibrarySelectionLabel()
            tableView.reloadRows(at: [indexPath], with: .none)
        }
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        if tableView === filesTableView {
            return makeFileColumnHeader()
        } else if tableView === peersTableView {
            return makeColumnHeader(columns: [
                ("IP Address", nil),
                ("Client", 55),
                ("Progress", 50),
                ("DL", 35),
                ("UL", 35),
                ("Down", 40),
                ("Up", 40),
                ("Flags", 40),
            ])
        } else if tableView === libraryTableView {
            return makeColumnHeader(columns: [
                ("Series", nil),
                ("Episode", 55),
                ("Files", 35),
                ("Size", 50),
                ("Status", 45),
            ])
        }
        return nil
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        if tableView === filesTableView || tableView === peersTableView || tableView === libraryTableView {
            return 48
        }
        return 0
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        if tableView === filesTableView {
            return (isWebTorrentMode ? webFilteredFileInfos.isEmpty : filteredFileEntries.isEmpty) ? 160 : Self.filesRowHeight
        } else if tableView === peersTableView {
            return (isWebTorrentMode ? webPeerInfos.isEmpty : peerInfos.isEmpty) ? 160 : 48
        } else if tableView === libraryTableView {
            return (isWebTorrentMode ? webFilteredLibraryEntries.isEmpty : filteredLibraryEntries.isEmpty) ? 160 : 56
        }
        return UITableView.automaticDimension
    }

    private func makeColumnHeader(columns: [(String, CGFloat?)]) -> UIView {
        let header = UIView()
        header.backgroundColor = .systemBackground

        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 8
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -16),
            stack.centerYAnchor.constraint(equalTo: header.centerYAnchor),
        ])

        for (title, fixedWidth) in columns {
            let label = UILabel()
            label.text = title
            label.font = .nunito(ofSize: 12, weight: .medium)
            label.textColor = .secondaryLabel
            if let w = fixedWidth {
                label.widthAnchor.constraint(equalToConstant: w).isActive = true
                label.setContentHuggingPriority(.required, for: .horizontal)
                label.setContentCompressionResistancePriority(.required, for: .horizontal)
            } else {
                label.setContentHuggingPriority(.defaultLow, for: .horizontal)
                label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            }
            stack.addArrangedSubview(label)
        }

        let separator = UIView()
        separator.backgroundColor = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(separator)
        NSLayoutConstraint.activate([
            separator.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: header.bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: 0.5),
        ])

        return header
    }

    /// Builds a sortable column header for the Files tab.
    /// Matches Hayase's addSortBy plugin: tapping a column cycles asc → desc → clear.
    private func makeFileColumnHeader() -> UIView {
        let header = UIView()
        header.backgroundColor = .systemBackground

        let columns: [(String, CGFloat?, FileSortColumn)] = [
            ("File Name", nil, .name),
            ("Size", 60, .size),
            ("Progress", 70, .progress),
            ("Streams", 50, .streams),
        ]

        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 8
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -16),
            stack.centerYAnchor.constraint(equalTo: header.centerYAnchor),
        ])

        for (title, fixedWidth, sortCol) in columns {
            let isActive = filesSortColumn == sortCol

            let btn = UIButton(type: .system)
            btn.tag = sortCol.rawValue
            btn.setTitle(title, for: .normal)
            if isActive {
                let icon = filesSortAscending ? "arrow-up" : "arrow-down"
                btn.setImage(UIImage.hayaseIcon(icon, withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .medium)), for: .normal)
                btn.imageEdgeInsets = UIEdgeInsets(top: 0, left: -2, bottom: 0, right: 2)
                btn.titleEdgeInsets = UIEdgeInsets(top: 0, left: 2, bottom: 0, right: -2)
            } else {
                btn.setImage(nil, for: .normal)
                btn.imageEdgeInsets = .zero
                btn.titleEdgeInsets = .zero
            }
            btn.titleLabel?.font = .nunito(ofSize: 12, weight: .medium)
            btn.setTitleColor(isActive ? .label : .secondaryLabel, for: .normal)
            btn.tintColor = isActive ? .secondaryLabel : .clear
            btn.contentHorizontalAlignment = .left
            btn.addTarget(self, action: #selector(fileColumnHeaderTapped(_:)), for: .touchUpInside)

            if let w = fixedWidth {
                btn.widthAnchor.constraint(equalToConstant: w).isActive = true
                btn.setContentHuggingPriority(.required, for: .horizontal)
                btn.setContentCompressionResistancePriority(.required, for: .horizontal)
            } else {
                btn.setContentHuggingPriority(.defaultLow, for: .horizontal)
                btn.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            }
            stack.addArrangedSubview(btn)
        }

        let separator = UIView()
        separator.backgroundColor = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(separator)
        NSLayoutConstraint.activate([
            separator.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: header.bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: 0.5),
        ])

        return header
    }

    /// Handles tap on a Files column header button.
    /// Tap cycle per column: unsorted -> ascending -> descending -> unsorted.
    /// Matches Hayase's column sort dropdown with Asc/Desc options.
    @objc private func fileColumnHeaderTapped(_ sender: UIButton) {
        guard let col = FileSortColumn(rawValue: sender.tag) else { return }
        if filesSortColumn == col {
            if filesSortAscending {
                filesSortAscending = false
            } else {
                filesSortColumn = nil   // third tap: clear sort
            }
        } else {
            filesSortColumn = col
            filesSortAscending = true
        }
        refreshFiles()
    }
}

// MARK: - FileEntryTableCell

final class FileEntryTableCell: UITableViewCell {
    static let reuseID = "FileEntryTableCell"

    private let nameLabel: UILabel = {
        let l = UILabel()
        l.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        l.textColor = .label
        l.numberOfLines = 2
        l.lineBreakMode = .byTruncatingTail
        l.setContentHuggingPriority(.defaultLow, for: .horizontal)
        l.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return l
    }()

    private let sizeLabel: UILabel = {
        let l = UILabel()
        l.font = .nunito(ofSize: 12)
        l.textColor = .label
        l.textAlignment = .left
        return l
    }()

    private let progressBar: UIProgressView = {
        let pv = UIProgressView(progressViewStyle: .bar)
        pv.layer.cornerRadius = 3
        pv.clipsToBounds = true
        pv.trackTintColor = .secondarySystemFill
        pv.progressTintColor = .white
        return pv
    }()

    private let progressLabel: UILabel = {
        let l = UILabel()
        l.font = .nunito(ofSize: 10)
        l.textColor = .secondaryLabel
        l.textAlignment = .center
        return l
    }()

    private let streamsLabel: UILabel = {
        let l = UILabel()
        l.font = .nunito(ofSize: 12)
        l.textColor = .label
        l.textAlignment = .left
        return l
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupCellUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupCellUI()
    }

    private func setupCellUI() {
        selectionStyle = .none

        // Progress: bar on top, label below
        let progressStack = UIStackView(arrangedSubviews: [progressBar, progressLabel])
        progressStack.axis = .vertical
        progressStack.spacing = 2
        progressStack.alignment = .fill

        // Horizontal stack matching column header widths:
        // File Name (flex) | Size (60) | Progress (70) | Streams (50)
        let stack = UIStackView(arrangedSubviews: [nameLabel, sizeLabel, progressStack, streamsLabel])
        stack.axis = .horizontal
        stack.spacing = 8
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -8),

            progressBar.heightAnchor.constraint(equalToConstant: 6),

            // Match column header widths
            sizeLabel.widthAnchor.constraint(equalToConstant: 60),
            progressStack.widthAnchor.constraint(equalToConstant: 70),
            streamsLabel.widthAnchor.constraint(equalToConstant: 50),
        ])

        sizeLabel.setContentHuggingPriority(.required, for: .horizontal)
        sizeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        streamsLabel.setContentHuggingPriority(.required, for: .horizontal)
        streamsLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    func configure(entry: FileEntry, streamCount: Int) {
        nameLabel.text = entry.name
        sizeLabel.text = TorrentDetailViewController.fastPrettyBytes(entry.size)
        let progress = Float(entry.progress)
        progressBar.progress = progress
        progressLabel.text = String(format: "%.1f%%", progress * 100)
        streamsLabel.text = "\(streamCount)"
    }

    func configure(entry: WebTorrentFileInfo) {
        nameLabel.text = entry.name
        sizeLabel.text = TorrentDetailViewController.fastPrettyBytes(entry.size)
        let progress = Float(max(0, min(entry.progress, 1)))
        progressBar.progress = progress
        progressLabel.text = String(format: "%.1f%%", progress * 100)
        streamsLabel.text = "\(entry.selections)"
    }
}

// MARK: - LibraryColumnCell

/// Columnar library cell matching Hayase table layout.
/// Displays data aligned with column headers: Series | Episode | Files | Size | Status
final class LibraryColumnCell: UITableViewCell {
    static let reuseID = "LibraryColumnCell"

    private let seriesLabel: UILabel = {
        let l = UILabel()
        l.font = .nunito(ofSize: 14)
        l.textColor = .label
        l.numberOfLines = 2
        l.lineBreakMode = .byTruncatingTail
        l.setContentHuggingPriority(.defaultLow, for: .horizontal)
        l.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return l
    }()

    private let episodeLabel: UILabel = {
        let l = UILabel()
        l.font = .nunito(ofSize: 14)
        l.textColor = .secondaryLabel
        l.textAlignment = .left
        return l
    }()

    private let filesLabel: UILabel = {
        let l = UILabel()
        l.font = .nunito(ofSize: 14)
        l.textColor = .label
        l.textAlignment = .left
        return l
    }()

    private let sizeLabel: UILabel = {
        let l = UILabel()
        l.font = .nunito(ofSize: 14)
        l.textColor = .label
        l.textAlignment = .left
        return l
    }()

    private let statusLabel: UILabel = {
        let l = UILabel()
        l.font = .nunito(ofSize: 12, weight: .medium)
        l.textAlignment = .center
        l.layer.cornerRadius = 4
        l.clipsToBounds = true
        return l
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupCellUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupCellUI()
    }

    private func setupCellUI() {
        selectionStyle = .none
        backgroundColor = .clear

        let stack = UIStackView(arrangedSubviews: [seriesLabel, episodeLabel, filesLabel, sizeLabel, statusLabel])
        stack.axis = .horizontal
        stack.spacing = 8
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            stack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

            // Match column header widths exactly
            episodeLabel.widthAnchor.constraint(equalToConstant: 55),
            filesLabel.widthAnchor.constraint(equalToConstant: 35),
            sizeLabel.widthAnchor.constraint(equalToConstant: 50),
            statusLabel.widthAnchor.constraint(equalToConstant: 45),
        ])

        episodeLabel.setContentHuggingPriority(.required, for: .horizontal)
        episodeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        filesLabel.setContentHuggingPriority(.required, for: .horizontal)
        filesLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        sizeLabel.setContentHuggingPriority(.required, for: .horizontal)
        sizeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        statusLabel.setContentHuggingPriority(.required, for: .horizontal)
        statusLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    func configure(entry: WebTorrentLibraryEntry) {
        seriesLabel.text = entry.name.isEmpty ? entry.hash : entry.name
        if let episode = entry.episode, episode > 0 {
            episodeLabel.text = "\(episode)"
        } else {
            episodeLabel.text = "?"
        }
        filesLabel.text = "\(entry.files)"
        sizeLabel.text = TorrentDetailViewController.fastPrettyBytes(entry.size)
        if entry.progress >= 0.999 {
            statusLabel.text = "✓"
            statusLabel.textColor = .systemGreen
        } else {
            statusLabel.text = String(format: "%.0f%%", max(0, min(entry.progress, 1)) * 100)
            statusLabel.textColor = .systemBlue
        }
    }

    func configure(handle: TorrentHandle, entity: Torrents?) {
        let snap = TorrentService.sharedTorrentService.withActiveHandle(handle, default: nil) { activeHandle -> TorrentHandle.Snapshot? in
            activeHandle.snapshot
        }
        guard let snap else {
            seriesLabel.text = entity?.animes?.animeTitleEnglish ?? entity?.animes?.animeTitleJapanese ?? "?"
            episodeLabel.text = "?"
            filesLabel.text = "0"
            sizeLabel.text = "—"
            statusLabel.text = "—"
            statusLabel.textColor = .secondaryLabel
            return
        }

        // Series name from CoreData
        let animeName = entity?.animes?.animeTitleEnglish
            ?? entity?.animes?.animeTitleJapanese
            ?? "?"
        seriesLabel.text = animeName

        // Episode count
        let videoCount = entity?.videos?.count ?? 0
        episodeLabel.text = videoCount > 0 ? "\(videoCount)" : "?"

        // Files count
        filesLabel.text = "\(snap.files.count)"

        // Size
        sizeLabel.text = TorrentDetailViewController.fastPrettyBytes(snap.total)

        // Status
        let isComplete = snap.total > 0 && snap.totalDone >= snap.total
        if isComplete {
            statusLabel.text = "✓"
            statusLabel.textColor = .systemGreen
        } else {
            let progress: Float = snap.total > 0
                ? Float(Double(snap.totalDone) / Double(snap.total))
                : 0
            statusLabel.text = String(format: "%.0f%%", progress * 100)
            statusLabel.textColor = .systemBlue
        }
    }
}

// MARK: - PeerInfoCell

/// Peer info cell matching Hayase peers table.
/// Columns: IP Address | Client | Progress | DL | UL | Downloaded | Uploaded | Flags
final class PeerInfoCell: UITableViewCell {
    static let reuseID = "PeerInfoCell"

    private let ipLabel: UILabel = {
        let l = UILabel()
        l.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        l.textColor = .label
        l.lineBreakMode = .byTruncatingTail
        l.setContentHuggingPriority(.defaultLow, for: .horizontal)
        l.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return l
    }()

    private let clientLabel: UILabel = {
        let l = UILabel()
        l.font = .nunito(ofSize: 11)
        l.textColor = .label
        l.lineBreakMode = .byTruncatingTail
        return l
    }()

    private let progressLabel: UILabel = {
        let l = UILabel()
        l.font = .nunito(ofSize: 11)
        l.textColor = .label
        l.textAlignment = .left
        return l
    }()

    private let dlSpeedLabel: UILabel = {
        let l = UILabel()
        l.font = .nunito(ofSize: 10)
        l.textColor = .label
        l.textAlignment = .left
        l.adjustsFontSizeToFitWidth = true
        l.minimumScaleFactor = 0.7
        return l
    }()

    private let ulSpeedLabel: UILabel = {
        let l = UILabel()
        l.font = .nunito(ofSize: 10)
        l.textColor = .label
        l.textAlignment = .left
        l.adjustsFontSizeToFitWidth = true
        l.minimumScaleFactor = 0.7
        return l
    }()

    private let downloadedLabel: UILabel = {
        let l = UILabel()
        l.font = .nunito(ofSize: 10)
        l.textColor = .label
        l.textAlignment = .left
        l.adjustsFontSizeToFitWidth = true
        l.minimumScaleFactor = 0.7
        return l
    }()

    private let uploadedLabel: UILabel = {
        let l = UILabel()
        l.font = .nunito(ofSize: 10)
        l.textColor = .label
        l.textAlignment = .left
        l.adjustsFontSizeToFitWidth = true
        l.minimumScaleFactor = 0.7
        return l
    }()

    private let flagsLabel: UILabel = {
        let l = UILabel()
        l.font = .monospacedSystemFont(ofSize: 9, weight: .regular)
        l.textColor = .secondaryLabel
        l.textAlignment = .left
        l.lineBreakMode = .byTruncatingTail
        return l
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupCellUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupCellUI()
    }

    private func setupCellUI() {
        selectionStyle = .none
        backgroundColor = .clear

        let stack = UIStackView(arrangedSubviews: [
            ipLabel, clientLabel, progressLabel,
            dlSpeedLabel, ulSpeedLabel,
            downloadedLabel, uploadedLabel, flagsLabel
        ])
        stack.axis = .horizontal
        stack.spacing = 8
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            stack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

            // Match column header widths
            clientLabel.widthAnchor.constraint(equalToConstant: 55),
            progressLabel.widthAnchor.constraint(equalToConstant: 50),
            dlSpeedLabel.widthAnchor.constraint(equalToConstant: 35),
            ulSpeedLabel.widthAnchor.constraint(equalToConstant: 35),
            downloadedLabel.widthAnchor.constraint(equalToConstant: 40),
            uploadedLabel.widthAnchor.constraint(equalToConstant: 40),
            flagsLabel.widthAnchor.constraint(equalToConstant: 40),
        ])

        for label in [clientLabel, progressLabel, dlSpeedLabel, ulSpeedLabel,
                      downloadedLabel, uploadedLabel, flagsLabel] {
            label.setContentHuggingPriority(.required, for: .horizontal)
            label.setContentCompressionResistancePriority(.required, for: .horizontal)
        }
    }

    func configure(peer: PeerInfo) {
        ipLabel.text = peer.ip
        clientLabel.text = String(peer.client.prefix(21))
        progressLabel.text = String(format: "%.1f%%", peer.progress * 100)
        dlSpeedLabel.text = TorrentDetailViewController.fastPrettyBits(UInt64(max(0, peer.downloadSpeed)) * 8) + "/s"
        ulSpeedLabel.text = TorrentDetailViewController.fastPrettyBits(UInt64(max(0, peer.uploadSpeed)) * 8) + "/s"
        downloadedLabel.text = TorrentDetailViewController.fastPrettyBytes(UInt64(max(0, peer.totalDownload)))
        uploadedLabel.text = TorrentDetailViewController.fastPrettyBytes(UInt64(max(0, peer.totalUpload)))
        flagsLabel.text = peer.connectionFlags.joined(separator: " ")
    }

    func configure(peer: WebTorrentPeerInfo) {
        ipLabel.text = peer.ip
        clientLabel.text = String(peer.client.prefix(21))
        progressLabel.text = String(format: "%.1f%%", max(0, min(peer.progress, 1)) * 100)
        dlSpeedLabel.text = TorrentDetailViewController.fastPrettyBits(peer.speed.down * 8) + "/s"
        ulSpeedLabel.text = TorrentDetailViewController.fastPrettyBits(peer.speed.up * 8) + "/s"
        downloadedLabel.text = TorrentDetailViewController.fastPrettyBytes(peer.size.downloaded)
        uploadedLabel.text = TorrentDetailViewController.fastPrettyBytes(peer.size.uploaded)
        flagsLabel.text = peer.flags.joined(separator: " ")
    }
}
