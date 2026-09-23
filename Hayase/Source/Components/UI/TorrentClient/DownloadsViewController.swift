//
//  DownloadsViewController.swift
//  Hayase
//
//  Mirrors: src/routes/app/client/+layout.svelte, src/routes/app/client/+page.ts, src/routes/app/client/+page.svelte, src/lib/components/SettingsNav.svelte
//

import UIKit
import CoreData
import LibTorrent

// MARK: - DownloadsViewController

/// Hayase-style torrent client page with tabbed interface:
/// Overview, Files, Peers, Trackers, Library, Settings.
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
    private var clientRoute: Route.ClientRoute = .root
    private static let settingsTabIndex = 5

    // MARK: - Page header

    private let pageTitleLabel: UILabel = {
        let l = UILabel()
        l.font = .nunito(ofSize: 24, weight: .bold)
        l.textColor = TorrentClientStyle.foreground
        l.text = "Torrent Client"
        return l
    }()

    private let pageSubtitleLabel: UILabel = {
        let l = UILabel()
        l.font = .nunito(ofSize: 16, weight: .regular)
        l.textColor = TorrentClientStyle.mutedForeground
        l.text = "Monitor your torrents, and configure settings for your torrent client."
        l.numberOfLines = 0
        return l
    }()

    private var pageTitleTopConstraint: NSLayoutConstraint?
    private var pageTitleLeadingConstraint: NSLayoutConstraint?
    private var pageTitleTrailingConstraint: NSLayoutConstraint?
    private var pageSubtitleTrailingConstraint: NSLayoutConstraint?
    private var headerSeparatorTopConstraint: NSLayoutConstraint?
    private var headerSeparatorLeadingConstraint: NSLayoutConstraint?
    private var headerSeparatorTrailingConstraint: NSLayoutConstraint?

    // MARK: - Tab bar & containers

    private var tabButtons: [HayaseNavTabButton] = []
    private var tabButtonHeightConstraints: [NSLayoutConstraint] = []
    private var tabButtonMinWidthConstraints: [NSLayoutConstraint] = []
    private let tabBarContainer = UIView()
    private let tabScrollView = UIScrollView()
    private let tabStackView = UIStackView()
    private let bodyStackView = UIStackView()
    private let headerSeparator = UIView()
    private let globeView = Globe()
    private let webTorrentVersionLabel: UILabel = {
        let label = UILabel()
        label.text = "WebTorrent v3.0.16"
        label.font = .nunito(ofSize: 12, weight: .light)
        label.textColor = TorrentClientStyle.mutedForeground
        label.numberOfLines = 1
        return label
    }()
    private var tabBarWidthConstraint: NSLayoutConstraint?
    private var tabBarHeightConstraint: NSLayoutConstraint?
    private var tabStackWidthConstraint: NSLayoutConstraint?
    private var tabStackHeightConstraint: NSLayoutConstraint?
    private var tabScrollBottomToContainerConstraint: NSLayoutConstraint?
    private var tabScrollBottomToFooterConstraint: NSLayoutConstraint?
    private var globeWidthConstraint: NSLayoutConstraint?
    private var bodyTopConstraint: NSLayoutConstraint?
    private var bodyLeadingConstraint: NSLayoutConstraint?
    private var bodyTrailingConstraint: NSLayoutConstraint?
    private var lastWideClientLayout: Bool?

    private let containerView = UIView()

    private var tabContentViews: [UIView] {
        [overviewScrollView, filesView, peersView, trackersView, libraryView]
    }

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
        l.textColor = TorrentClientStyle.foreground
        l.numberOfLines = 1
        l.lineBreakMode = .byTruncatingTail
        return l
    }()

    private let statusBadge: TorrentPillBadge = {
        let l = TorrentPillBadge(horizontalPadding: 10, verticalPadding: 2)
        l.font = .nunito(ofSize: 12, weight: .bold)
        l.textColor = TorrentClientStyle.primaryForeground
        l.textAlignment = .center
        return l
    }()

    private let hashLabel: UILabel = {
        let l = UILabel()
        l.font = .nunito(ofSize: 14)
        l.textColor = TorrentClientStyle.mutedForeground
        l.numberOfLines = 1
        l.lineBreakMode = .byTruncatingMiddle
        return l
    }()

    private let bigPercentLabel: UILabel = {
        let l = UILabel()
        l.font = .nunito(ofSize: 24, weight: .bold)
        l.textColor = TorrentClientStyle.foreground
        return l
    }()

    private let progressBar: UIProgressView = {
        let pv = UIProgressView(progressViewStyle: .bar)
        pv.layer.cornerRadius = 6
        pv.clipsToBounds = true
        pv.trackTintColor = TorrentClientStyle.accent
        pv.progressTintColor = TorrentClientStyle.primary
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
    private weak var overviewStatsStack: UIStackView?
    private weak var protocolColumnsStack: TorrentResponsiveGrid?
    private weak var progressStatsGrid: TorrentResponsiveGrid?
    private var viewportWidth: CGFloat {
        view.window?.rootViewController?.view.bounds.width ?? view.bounds.width
    }

    // MARK: - Files tab

    private let filesView = UIView()
    private var filesTableView: UITableView!
    private let filesSearchField = TorrentClientStyle.makeSearchField(placeholder: "Search by File Name...")
    private var fileEntries: [FileEntry] = []
    private var filteredFileEntries: [FileEntry] = []

    /// Column sort state for the Files tab (mirrors Hayase addSortBy plugin with toggleOrder: ['asc','desc']).
    /// Tap cycle: unsorted → asc → desc → unsorted.
    private enum FileSortColumn: Int { case name = 0, size = 1, progress = 2, streams = 3 }
    private var filesSortColumn: FileSortColumn?
    private var filesSortAscending: Bool = true

    private static let filesRowHeight: CGFloat = 56

    // MARK: - Peers tab

    private let peersView = UIView()
    private var peersHorizontalScrollView: UIScrollView!
    private var peersTableView: UITableView!
    private enum PeerSortColumn: Int {
        case ip = 0
        case client = 1
        case progress = 2
        case download = 3
        case upload = 4
        case downloaded = 5
        case uploaded = 6
        case country = 7
    }
    private var peersSortColumn: PeerSortColumn?
    private var peersSortAscending = true

    // MARK: - Trackers tab

    private let trackersView = UIView()
    private var trackersTableView: UITableView!
    private var webTrackerRows: [(announce: String, info: WebTorrentTrackerInfo)] = []
    private var webTrackersInFlight = false
    private var lastWebTrackerRefresh = Date.distantPast
    private let trackerRefreshInterval: TimeInterval = 10

    // MARK: - Library tab

    private let libraryView = UIView()
    private var libraryTableView: UITableView!
    private let librarySearchField = TorrentClientStyle.makeSearchField(placeholder: "Search by Torrent Name...")
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
    private var webSnapshotGeneration = 0
    private var webLastError: Error?
    private var animeTitleCache: [Int: String] = [:]
    private var pendingAnimeTitles: Set<Int> = []

    private var selectedLibraryHashes: Set<String> = []
    private var librarySortColumn: Int?
    private var librarySortAscending = true
    private var libraryActionInFlight = false
    private var pendingLibraryPlaybackService: VideoService?
    private var pendingLibraryPlaybackObserver: NSObjectProtocol?
    private var pendingLibraryPlaybackTimeout: DispatchWorkItem?
    private var openingLibraryPlaybackHash: String?
    private static let libraryPlaybackTimeout: TimeInterval = 120

    private let librarySelectionLabel: UILabel = {
        let l = UILabel()
        l.font = .nunito(ofSize: 14)
        l.textColor = TorrentClientStyle.mutedForeground
        l.text = "0 of 0 row(s) selected."
        l.textAlignment = .right
        return l
    }()
    private let libraryRescanButton = UIButton(type: .system)
    private let libraryDeleteButton = UIButton(type: .system)

    // MARK: - Empty state

    private let emptyLabel: UILabel = {
        let l = UILabel()
        l.text = "No active downloads"
        l.textColor = TorrentClientStyle.mutedForeground
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
        TorrentClientStyle.configureRootView(view)
        navigationController?.navigationBar.prefersLargeTitles = false

        setupPageHeader()
        setupContainerView()
        setupEmptyLabel()
        buildOverviewUI()
        buildFilesUI()
        buildPeersUI()
        buildTrackersUI()
        buildLibraryUI()
        installTabPages()
        setupNotifications()

        if clientRoute == .root {
            tabContentViews.forEach { $0.isHidden = true }
            emptyLabel.isHidden = true
        } else {
            autoSelectFirstTorrent()
            showTab(selectedTabIndex)
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.navigationBar.prefersLargeTitles = false
        guard clientRoute != .root else {
            stopTimer()
            return
        }
        autoSelectFirstTorrent()
        startTimer()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopTimer()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateResponsiveClientLayoutIfNeeded()

    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        stopTimer()
        cancelPendingLibraryPlayback()
    }

    private var isWebTorrentMode: Bool {
        TorrentBackendManager.shared.currentKind == .webtorrent
    }

    // MARK: - Timer

    private func startTimer() {
        stopTimer()
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.update()
        }
        RunLoop.main.add(timer, forMode: .common)
        updateTimer = timer
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
            emptyLabel.isHidden = selectedTabIndex != 0 || !shouldShowGlobalEmptyState()
            return
        }

        let handles = TorrentService.sharedTorrentService.handles
        // Keep current selection if still valid
        if !selectedHex.isEmpty,
           handles[selectedHex] != nil {
            selectedHandle = handles[selectedHex]
            selectedEntity = TorrentService.sharedTorrentService.GetTorrentEntitiesFromHash(selectedHex).first
            emptyLabel.isHidden = selectedTabIndex != 0 || !shouldShowGlobalEmptyState()
            return
        }
        // Auto-select first handle sorted by name
        if let first = handles.sorted(by: { snapshotName(for: $0.value) < snapshotName(for: $1.value) }).first {
            selectedHex = first.key
            selectedHandle = first.value
            selectedEntity = TorrentService.sharedTorrentService.GetTorrentEntitiesFromHash(first.key).first
            emptyLabel.isHidden = selectedTabIndex != 0 || !shouldShowGlobalEmptyState()
        } else {
            selectedHandle = nil
            selectedHex = ""
            selectedEntity = nil
            emptyLabel.isHidden = selectedTabIndex != 0 || !shouldShowGlobalEmptyState()
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
        for label in [pageTitleLabel, pageSubtitleLabel] {
            label.setContentHuggingPriority(.required, for: .vertical)
            label.setContentCompressionResistancePriority(.required, for: .vertical)
        }
        TorrentClientStyle.configureSeparator(headerSeparator)
        headerSeparator.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(pageTitleLabel)
        view.addSubview(pageSubtitleLabel)
        view.addSubview(headerSeparator)

        pageTitleTopConstraint = pageTitleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: TorrentClientStyle.compactPadding)
        pageTitleLeadingConstraint = pageTitleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: TorrentClientStyle.compactPadding)
        pageTitleTrailingConstraint = pageTitleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -TorrentClientStyle.compactPadding)
        pageSubtitleTrailingConstraint = pageSubtitleLabel.trailingAnchor.constraint(equalTo: pageTitleLabel.trailingAnchor)
        headerSeparatorTopConstraint = headerSeparator.topAnchor.constraint(equalTo: pageSubtitleLabel.bottomAnchor, constant: TorrentClientStyle.compactSeparatorSpacing)
        headerSeparatorLeadingConstraint = headerSeparator.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: TorrentClientStyle.compactPadding)
        headerSeparatorTrailingConstraint = headerSeparator.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -TorrentClientStyle.compactPadding)

        NSLayoutConstraint.activate([
            pageTitleTopConstraint!,
            pageTitleLeadingConstraint!,
            pageTitleTrailingConstraint!,

            pageSubtitleLabel.topAnchor.constraint(equalTo: pageTitleLabel.bottomAnchor, constant: 2),
            pageSubtitleLabel.leadingAnchor.constraint(equalTo: pageTitleLabel.leadingAnchor),
            pageSubtitleTrailingConstraint!,

            headerSeparatorTopConstraint!,
            headerSeparatorLeadingConstraint!,
            headerSeparatorTrailingConstraint!,
            headerSeparator.heightAnchor.constraint(equalToConstant: 1),
        ])
    }

    private func setupContainerView() {
        setupTabNavigation()

        bodyStackView.axis = .vertical
        bodyStackView.spacing = 8
        bodyStackView.alignment = .fill
        bodyStackView.distribution = .fill
        bodyStackView.translatesAutoresizingMaskIntoConstraints = false

        tabBarContainer.translatesAutoresizingMaskIntoConstraints = false
        containerView.translatesAutoresizingMaskIntoConstraints = false
        TorrentClientStyle.configurePlainContentView(tabBarContainer)
        TorrentClientStyle.configurePlainContentView(containerView)
        [tabBarContainer, containerView, bodyStackView].forEach { $0.isOpaque = false }
        bodyStackView.addArrangedSubview(tabBarContainer)
        bodyStackView.addArrangedSubview(containerView)
        view.addSubview(bodyStackView)

        globeView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(globeView)

        tabBarWidthConstraint = tabBarContainer.widthAnchor.constraint(equalToConstant: TorrentClientStyle.sidebarWidth)
        tabBarHeightConstraint = tabBarContainer.heightAnchor.constraint(equalToConstant: 44)
        tabBarHeightConstraint?.isActive = true
        globeWidthConstraint = globeView.widthAnchor.constraint(equalToConstant: 400)
        bodyTopConstraint = bodyStackView.topAnchor.constraint(equalTo: headerSeparator.bottomAnchor, constant: TorrentClientStyle.compactSeparatorSpacing)
        bodyLeadingConstraint = bodyStackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: TorrentClientStyle.compactPadding)
        bodyTrailingConstraint = bodyStackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -TorrentClientStyle.compactPadding)

        NSLayoutConstraint.activate([
            bodyTopConstraint!,
            bodyLeadingConstraint!,
            bodyTrailingConstraint!,
            bodyStackView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            containerView.heightAnchor.constraint(greaterThanOrEqualToConstant: 0),
            containerView.widthAnchor.constraint(lessThanOrEqualToConstant: TorrentClientStyle.clientContentMaxWidth),
            globeWidthConstraint!,
            globeView.heightAnchor.constraint(equalTo: globeView.widthAnchor),
            globeView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            globeView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
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

    private func installTabPages() {
        for tabView in tabContentViews {
            guard tabView.superview == nil else { continue }
            tabView.isOpaque = false
            tabView.translatesAutoresizingMaskIntoConstraints = false
            tabView.isHidden = true
            containerView.addSubview(tabView)
            NSLayoutConstraint.activate([
                tabView.topAnchor.constraint(equalTo: containerView.topAnchor),
                tabView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
                tabView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
                tabView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            ])
        }
        containerView.sendSubviewToBack(globeView)
        containerView.bringSubviewToFront(emptyLabel)
    }

    // MARK: - Tab bar

    private func setupTabNavigation() {
        tabScrollView.showsHorizontalScrollIndicator = false
        tabScrollView.showsVerticalScrollIndicator = false
        tabScrollView.clipsToBounds = false
        tabScrollView.translatesAutoresizingMaskIntoConstraints = false

        tabStackView.axis = .horizontal
        tabStackView.spacing = 8
        tabStackView.alignment = .fill
        tabStackView.distribution = .fill
        tabStackView.translatesAutoresizingMaskIntoConstraints = false

        tabButtons.removeAll()
        tabButtonHeightConstraints.removeAll()
        tabButtonMinWidthConstraints.removeAll()
        let titles = ["Overview", "Files", "Peers", "Trackers", "Library", "Settings"]
        for (index, title) in titles.enumerated() {
            let button = makeTabButton(title: title, tag: index)
            tabStackView.addArrangedSubview(button)
            tabButtons.append(button)
        }

        tabScrollView.addSubview(tabStackView)
        tabBarContainer.addSubview(tabScrollView)
        webTorrentVersionLabel.translatesAutoresizingMaskIntoConstraints = false
        tabBarContainer.addSubview(webTorrentVersionLabel)

        tabStackWidthConstraint = tabStackView.widthAnchor.constraint(equalTo: tabScrollView.frameLayoutGuide.widthAnchor)
        tabStackHeightConstraint = tabStackView.heightAnchor.constraint(equalTo: tabScrollView.frameLayoutGuide.heightAnchor)
        tabStackHeightConstraint?.isActive = true
        tabScrollBottomToContainerConstraint = tabScrollView.bottomAnchor.constraint(equalTo: tabBarContainer.bottomAnchor)
        tabScrollBottomToFooterConstraint = tabScrollView.bottomAnchor.constraint(equalTo: webTorrentVersionLabel.topAnchor, constant: -12)
        tabScrollBottomToContainerConstraint?.isActive = true

        NSLayoutConstraint.activate([
            tabScrollView.topAnchor.constraint(equalTo: tabBarContainer.topAnchor),
            tabScrollView.leadingAnchor.constraint(equalTo: tabBarContainer.leadingAnchor),
            tabScrollView.trailingAnchor.constraint(equalTo: tabBarContainer.trailingAnchor),

            tabStackView.topAnchor.constraint(equalTo: tabScrollView.contentLayoutGuide.topAnchor),
            tabStackView.leadingAnchor.constraint(equalTo: tabScrollView.contentLayoutGuide.leadingAnchor),
            tabStackView.trailingAnchor.constraint(equalTo: tabScrollView.contentLayoutGuide.trailingAnchor),
            tabStackView.bottomAnchor.constraint(equalTo: tabScrollView.contentLayoutGuide.bottomAnchor),
            webTorrentVersionLabel.leadingAnchor.constraint(equalTo: tabBarContainer.leadingAnchor, constant: 8),
            webTorrentVersionLabel.trailingAnchor.constraint(lessThanOrEqualTo: tabBarContainer.trailingAnchor, constant: -8),
            webTorrentVersionLabel.bottomAnchor.constraint(equalTo: tabBarContainer.bottomAnchor, constant: -20),
        ])
    }

    private func makeTabButton(title: String, tag: Int) -> HayaseNavTabButton {
        let btn = HayaseNavTabButton()
        btn.setTitle(title, for: .normal)
        btn.contentHorizontalAlignment = .leading
        btn.titleLabel?.font = .nunito(ofSize: 14, weight: .semibold)
        btn.layer.cornerRadius = 6
        btn.contentEdgeInsets = UIEdgeInsets(top: 10, left: 32, bottom: 10, right: 32)  // size=lg: h-10 px-8
        btn.tag = tag
        btn.addTarget(self, action: #selector(tabButtonTapped(_:)), for: .touchUpInside)
        let height = btn.heightAnchor.constraint(equalToConstant: 40)  // size=lg: h-10 = 40px
        let minWidth = btn.widthAnchor.constraint(greaterThanOrEqualToConstant: 120)
        height.isActive = true
        minWidth.isActive = true
        tabButtonHeightConstraints.append(height)
        tabButtonMinWidthConstraints.append(minWidth)
        updateTabButtonAppearance(btn)
        HayaseNavTabButton.select(tag: selectedTabIndex, in: [btn], animated: false)
        return btn
    }

    private func updateResponsiveClientLayoutIfNeeded() {
        let width = viewportWidth
        let medium = width >= 768  // Tailwind md = 48rem = 768px
        let wide = TorrentClientStyle.isWideClientLayout(width: width)  // Tailwind lg = 64rem = 1024px
        lastWideClientLayout = wide

        let compactRoot = !medium && clientRoute == .root
        tabBarContainer.isHidden = !medium && !compactRoot
        containerView.isHidden = compactRoot

        bodyStackView.axis = wide ? .horizontal : .vertical
        bodyStackView.spacing = wide ? TorrentClientStyle.sidebarGap : 8
        tabStackView.axis = (wide || !medium) ? .vertical : .horizontal
        tabStackView.alignment = (wide || !medium) ? .fill : .center
        tabStackView.spacing = (wide || !medium) ? 4 : 8  // gap-y-1 / gap-x-2
        tabScrollView.alwaysBounceHorizontal = medium && !wide
        tabScrollView.alwaysBounceVertical = wide || !medium

        tabBarWidthConstraint?.isActive = wide
        // Compact index has only the menu: let its scroll viewport fill the
        // remaining height instead of forcing the header to absorb that space.
        tabBarHeightConstraint?.isActive = medium && !wide
        tabBarHeightConstraint?.constant = 36 + 12 + 20 + webTorrentVersionLabel.font.lineHeight
        tabStackWidthConstraint?.isActive = wide || !medium
        tabStackHeightConstraint?.isActive = medium && !wide
        let showsVersion = width >= 640
        tabScrollBottomToContainerConstraint?.isActive = !showsVersion
        tabScrollBottomToFooterConstraint?.isActive = showsVersion
        webTorrentVersionLabel.isHidden = !showsVersion

        for (index, button) in tabButtons.enumerated() {
            let height = medium ? CGFloat(36) : CGFloat(40)  // default h-9 / lg h-10
            tabButtonHeightConstraints[safe: index]?.constant = height
            tabButtonMinWidthConstraints[safe: index]?.isActive = medium
            button.contentEdgeInsets = medium
                ? UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)   // default px-4 py-2
                : UIEdgeInsets(top: 10, left: 32, bottom: 10, right: 32) // lg px-8, h-10
        }

        globeView.isHidden = false
        globeView.transform = .identity
        let viewportWidth = self.viewportWidth
        let globeSize: CGFloat = viewportWidth >= 1920 ? 600 : 400
        globeWidthConstraint?.constant = globeSize
        globeView.setViewportWidth(viewportWidth)

        let padding = medium ? TorrentClientStyle.regularPadding : TorrentClientStyle.compactPadding  // p-3 md:p-10
        let separatorSpacing = medium ? TorrentClientStyle.regularSeparatorSpacing : TorrentClientStyle.compactSeparatorSpacing  // my-3 md:my-6
        pageTitleTopConstraint?.constant = padding
        let outerInset = max(padding, (view.bounds.width - TorrentClientStyle.contentMaxWidth) / 2)
        pageTitleLeadingConstraint?.constant = outerInset
        pageTitleTrailingConstraint?.constant = -outerInset
        headerSeparatorTopConstraint?.constant = separatorSpacing
        headerSeparatorLeadingConstraint?.constant = outerInset
        headerSeparatorTrailingConstraint?.constant = -outerInset
        bodyTopConstraint?.constant = separatorSpacing
        bodyLeadingConstraint?.constant = outerInset
        bodyTrailingConstraint?.constant = -outerInset
        overviewStatsStack?.axis = width >= 1280 ? .horizontal : .vertical
        overviewStatsStack?.distribution = width >= 1280 ? .fillEqually : .fill
        overviewStatsStack?.spacing = width >= 1280 ? 48 : 0
        progressStatsGrid?.setColumns(medium ? 4 : 2)
        protocolColumnsStack?.setColumns(wide ? 3 : (medium ? 2 : 1))

        updateTabButtonAppearances()
    }

    private func updateTabButtonAppearance(_ btn: UIButton) {
        let medium = viewportWidth >= 768  // bg-muted md:bg-transparent
        btn.backgroundColor = medium ? .clear : TorrentClientStyle.muted
    }

    private func updateTabButtonAppearances() {
        for btn in tabButtons {
            updateTabButtonAppearance(btn)
        }
        HayaseNavTabButton.select(tag: clientRoute == .root ? -1 : selectedTabIndex, in: tabButtons, animated: false)
    }

    func applyRoute(_ route: Route.ClientRoute) {
        clientRoute = route
        if let index = tabIndex(for: route) {
            selectedTabIndex = index
        }
        guard isViewLoaded else { return }

        if route == .root {
            stopTimer()
            HayaseNavTabButton.select(tag: -1, in: tabButtons, animated: true)
            tabContentViews.forEach { $0.isHidden = true }
            emptyLabel.isHidden = true
            updateResponsiveClientLayoutIfNeeded()
            return
        }

        autoSelectFirstTorrent()
        if view.window != nil {
            startTimer()
        }
        HayaseNavTabButton.select(tag: selectedTabIndex, in: tabButtons, animated: true)
        showTab(selectedTabIndex)
        updateResponsiveClientLayoutIfNeeded()
    }

    private func clientRoute(for tabIndex: Int) -> Route.ClientRoute? {
        switch tabIndex {
        case 0: return .overview
        case 1: return .files
        case 2: return .peers
        case 3: return .trackers
        case 4: return .library
        default: return nil
        }
    }

    private func tabIndex(for route: Route.ClientRoute) -> Int? {
        switch route {
        case .root: return nil
        case .overview: return 0
        case .files: return 1
        case .peers: return 2
        case .trackers: return 3
        case .library: return 4
        }
    }

    @objc private func tabButtonTapped(_ sender: UIButton) {
        let index = sender.tag
        if index == Self.settingsTabIndex {
            Router.shared.navigate(.settings(.client), hostTabIndex: hayaseTabIndex, noScroll: true)
        } else if let route = clientRoute(for: index) {
            Router.shared.navigate(.client(route), hostTabIndex: hayaseTabIndex, noScroll: true)
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
            pageTitleLabel.text = "Tracker Status"
            pageSubtitleLabel.text = "Trackers for the currently active torrent, their status, and statistics about seeders/leechers and download amount."
        case 4:
            pageTitleLabel.text = "Torrent Library"
            pageSubtitleLabel.text = "All of your downloaded torrents. If Persist Files is enabled then your previously downloaded torrents will show up here."
        default:
            break
        }
    }

    // MARK: - Tab switching

    private func showTab(_ index: Int) {
        updatePageHeader(for: index)
        for (tabIndex, tabView) in tabContentViews.enumerated() {
            tabView.isHidden = tabIndex != index
        }

        emptyLabel.isHidden = isWebTorrentMode || index != 0 || !shouldShowGlobalEmptyState()

        switch index {
        case 0:
            update()
        case 1:
            refreshFiles()
        case 2:
            refreshPeers()
        case 3:
            refreshTrackers(force: true)
        case 4:
            refreshLibrary()
        default:
            break
        }
    }

    private func shouldShowGlobalEmptyState() -> Bool {
        if isWebTorrentMode {
            return selectedHex.isEmpty && webStatus == nil && webLibraryEntries.isEmpty
        }
        return selectedHandle == nil
    }

    // MARK: - Files tab

    private func buildFilesUI() {
        TorrentClientStyle.configurePlainContentView(filesView)

        filesSearchField.translatesAutoresizingMaskIntoConstraints = false
        filesSearchField.addTarget(self, action: #selector(filesSearchChanged), for: .editingChanged)
        filesView.addSubview(filesSearchField)

        let borderContainer = UIView()
        TorrentClientStyle.configureTableShell(borderContainer)
        borderContainer.translatesAutoresizingMaskIntoConstraints = false
        filesView.addSubview(borderContainer)

        filesTableView = UITableView(frame: .zero, style: .plain)
        filesTableView.translatesAutoresizingMaskIntoConstraints = false
        filesTableView.delegate = self
        filesTableView.dataSource = self
        filesTableView.register(FileEntryTableCell.self, forCellReuseIdentifier: FileEntryTableCell.reuseID)
        filesTableView.rowHeight = Self.filesRowHeight
        filesTableView.estimatedRowHeight = Self.filesRowHeight
        TorrentClientStyle.configureTableView(filesTableView)
        TorrentClientStyle.installScrollableTable(filesTableView, in: borderContainer, minimumWidth: 640)

        NSLayoutConstraint.activate([
            filesSearchField.topAnchor.constraint(equalTo: filesView.topAnchor),
            filesSearchField.leadingAnchor.constraint(equalTo: filesView.leadingAnchor),
            filesSearchField.trailingAnchor.constraint(equalTo: filesView.trailingAnchor),
            filesSearchField.heightAnchor.constraint(equalToConstant: 36),

            borderContainer.topAnchor.constraint(equalTo: filesSearchField.bottomAnchor, constant: 8),
            borderContainer.leadingAnchor.constraint(equalTo: filesView.leadingAnchor),
            borderContainer.trailingAnchor.constraint(equalTo: filesView.trailingAnchor),
            borderContainer.bottomAnchor.constraint(equalTo: filesView.bottomAnchor),

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
        globeView.setPeers(currentPeerRows())
        peersTableView?.reloadData()
    }

    private func currentPeerRows() -> [TorrentClientPeerRow] {
        var rows = isWebTorrentMode ? webPeerInfos.map(TorrentClientPeerRow.init(peer:)) : []

        guard let sortColumn = peersSortColumn else { return rows }
        let ascending = peersSortAscending
        rows.sort { lhs, rhs in
            let result: ComparisonResult
            switch sortColumn {
            case .ip:
                result = lhs.ip.localizedStandardCompare(rhs.ip)
            case .client:
                result = lhs.client.localizedCaseInsensitiveCompare(rhs.client)
            case .progress:
                result = lhs.progress == rhs.progress ? .orderedSame : (lhs.progress < rhs.progress ? .orderedAscending : .orderedDescending)
            case .download:
                result = lhs.downloadSpeed == rhs.downloadSpeed ? .orderedSame : (lhs.downloadSpeed < rhs.downloadSpeed ? .orderedAscending : .orderedDescending)
            case .upload:
                result = lhs.uploadSpeed == rhs.uploadSpeed ? .orderedSame : (lhs.uploadSpeed < rhs.uploadSpeed ? .orderedAscending : .orderedDescending)
            case .downloaded:
                result = lhs.downloaded == rhs.downloaded ? .orderedSame : (lhs.downloaded < rhs.downloaded ? .orderedAscending : .orderedDescending)
            case .uploaded:
                result = lhs.uploaded == rhs.uploaded ? .orderedSame : (lhs.uploaded < rhs.uploaded ? .orderedAscending : .orderedDescending)
            case .country:
                result = lhs.ip.localizedStandardCompare(rhs.ip) // source accessor is the IP
            }
            return ascending ? result == .orderedAscending : result == .orderedDescending
        }
        return rows
    }

    @objc private func handlePeerHeaderTap(_ sender: UIButton) {
        guard let column = PeerSortColumn(rawValue: sender.tag) else { return }
        if peersSortColumn == column {
            if peersSortAscending {
                peersSortAscending = false
            } else {
                peersSortColumn = nil
                peersSortAscending = true
            }
        } else {
            peersSortColumn = column
            peersSortAscending = true
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
        let isStreaming = snap.state == .downloading && snap.isSequential
        etaValue.text     = isStreaming ? "Streaming" : TorrentDetailViewController.eta(remaining: remaining, rate: snap.downloadRate)
        elapsedValue.text = TorrentDetailViewController.eta(seconds: elapsed)

        // Peers & Connections
        seedersValue.text  = "\(snap.numberOfSeeds)"
        leechersValue.text = "\(snap.numberOfLeechers)"
        wiresValue.text    = "\(snap.numberOfPeers)"
        globeView.setPeers(currentPeerRows())

        // Protocol status dots
        setDot(dhtDot, enabled: snap.isDhtRunning)
        setDot(lsdDot, enabled: snap.isLsdRunning)
        setDot(pexDot, enabled: snap.isPexEnabled)
        setDot(natDot, enabled: true)
        setDot(forwardDot, enabled: snap.hasIncomingConnections)
        setDot(persistDot, enabled: Settings.persistFiles)

        setDot(streamingDot, enabled: isStreaming)

        // Update files tab if visible
        if selectedTabIndex == 1 {
            refreshFiles()
        }

        // Update peers tab if visible
        if selectedTabIndex == 2 {
            refreshPeers()
        }

        if selectedTabIndex == 3 {
            refreshTrackers(force: false)
        }

        if selectedTabIndex == 4 {
            refreshLibrary()
        }
    }

    private func updateWebTorrent() {
        guard !webUpdateInFlight else { return }
        webUpdateInFlight = true

        let manager = TorrentBackendManager.shared
        let selectionAtRequest = selectedHex
        let generationAtRequest = webSnapshotGeneration
        manager.webTorrentStatus { [weak self] statusResult in
            DispatchQueue.main.async {
                guard let self else { return }

                let status = try? statusResult.get()
                let requestedHash = status?.infoHash ?? self.selectedHex

                let group = DispatchGroup()
                var nextInfo: WebTorrentTorrentInfo?
                var nextFiles: [WebTorrentFileInfo]?
                var nextPeers: [WebTorrentPeerInfo] = []
                var nextLibrary: [WebTorrentLibraryEntry]?
                var nextProtocol: WebTorrentProtocolStatus?
                var nextError: Error?

                if case .failure(let error) = statusResult {
                    nextError = error
                }

                group.enter()
                manager.webTorrentLibrary { result in
                    DispatchQueue.main.async {
                        if case .success(let entries) = result { nextLibrary = entries }
                        group.leave()
                    }
                }

                if !requestedHash.isEmpty {
                    group.enter()
                    manager.webTorrentInfo(hash: requestedHash) { result in
                        DispatchQueue.main.async {
                            if case .success(let info) = result { nextInfo = info }
                            group.leave()
                        }
                    }

                    group.enter()
                    manager.webTorrentFileInfo(hash: requestedHash) { result in
                        DispatchQueue.main.async {
                            if case .success(let files) = result { nextFiles = files }
                            group.leave()
                        }
                    }

                    group.enter()
                    manager.webTorrentPeerInfo(hash: requestedHash) { result in
                        DispatchQueue.main.async {
                            if case .success(let peers) = result { nextPeers = peers }
                            group.leave()
                        }
                    }

                    group.enter()
                    manager.webTorrentProtocolStatus(hash: requestedHash) { result in
                        DispatchQueue.main.async {
                            if case .success(let protocolStatus) = result { nextProtocol = protocolStatus }
                            group.leave()
                        }
                    }
                }

                group.notify(queue: .main) { [weak self] in
                    guard let self else { return }
                    self.webUpdateInFlight = false
                    guard self.isWebTorrentMode, self.selectedHex == selectionAtRequest,
                          self.webSnapshotGeneration == generationAtRequest else { return }
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
    }

    private func applyWebTorrentState(status: WebTorrentBridgeStatus?,
                                      info: WebTorrentTorrentInfo?,
                                      files: [WebTorrentFileInfo]?,
                                      peers: [WebTorrentPeerInfo],
                                      library: [WebTorrentLibraryEntry]?,
                                      protocolStatus: WebTorrentProtocolStatus?,
                                      error: Error?) {
        if let status {
            if let hash = status.infoHash, !hash.isEmpty { selectedHex = hash }
            if status.infoHash != webStatus?.infoHash {
                webInfo = nil
                webProtocol = nil
                webFileInfos = []
                webTrackerRows = []
            }
            webStatus = status
        }
        if let info { webInfo = info }
        if let protocolStatus { webProtocol = protocolStatus }
        webPeerInfos = peers
        // nil is a failed request; [] is a successful empty response.
        if let library { webLibraryEntries = library }
        webLastError = error
        globeView.setPeers(currentPeerRows())

        let resolvedStatus = status ?? webStatus
        let resolvedInfo = info ?? webInfo
        let resolvedProtocol = protocolStatus ?? webProtocol
        let resolvedLibrary = webLibraryEntries

        let knownHashes = Set(resolvedLibrary.map { $0.hash } + [resolvedStatus?.infoHash, resolvedInfo?.hash].compactMap { $0 })
        if !selectedHex.isEmpty && library != nil && !knownHashes.contains(selectedHex) {
            selectedHex = ""
        }
        if selectedHex.isEmpty {
            selectedHex = resolvedStatus?.infoHash ?? resolvedInfo?.hash ?? resolvedLibrary.first?.hash ?? ""
        }

        if webFileInfoHash != selectedHex {
            webFileInfos = []
            webFileInfoHash = selectedHex.isEmpty ? nil : selectedHex
        }
        if let files {
            webFileInfos = files
            webFileInfoHash = selectedHex.isEmpty ? (resolvedInfo?.hash ?? resolvedStatus?.infoHash) : selectedHex
        }

        let hasTorrent = !selectedHex.isEmpty || resolvedStatus?.infoHash != nil || resolvedInfo != nil || !resolvedLibrary.isEmpty
        emptyLabel.isHidden = true // Each source tab owns its empty state.
        if !hasTorrent {
            clearWebTorrentOverview(error: error)
            webTrackerRows = []
            refreshFiles()
            refreshPeers()
            refreshTrackers(force: false)
            refreshLibrary()
            return
        }

        let currentLibraryEntry = resolvedLibrary.first { $0.hash == selectedHex } ?? resolvedLibrary.first
        nameLabel.text = resolvedInfo?.name ?? currentLibraryEntry?.name ?? resolvedStatus?.source ?? "WebTorrent"
        hashLabel.text = selectedHex.isEmpty ? (resolvedStatus?.infoHash ?? "—") : selectedHex

        let progress = resolvedInfo?.progress ?? resolvedStatus?.progress ?? currentLibraryEntry?.progress ?? 0
        let completed = progress == 1
        statusBadge.text = completed ? "Seeding" : "Downloading"
        statusBadge.backgroundColor = completed ? TorrentClientStyle.blue500 : TorrentClientStyle.green500
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
        if resolvedProtocol?.streaming == true {
            etaValue.text = "Streaming"
        } else {
            etaValue.text = webTorrentETA(fromMilliseconds: resolvedInfo?.time.remaining)
                ?? TorrentDetailViewController.eta(remaining: total > downloaded ? total - downloaded : 0, rate: down)
        }
        let elapsed = resolvedInfo?.time.elapsed ?? 0 // elapsed is seconds, unlike remaining.
        elapsedValue.text = TorrentDetailViewController.eta(seconds: Int(elapsed.isFinite ? max(0, min(elapsed, Double(Int.max / 2))) : 0))

        seedersValue.text = "\(resolvedInfo?.peers.seeders ?? 0)"
        leechersValue.text = "\(resolvedInfo?.peers.leechers ?? 0)"
        wiresValue.text = "\(resolvedInfo?.peers.wires ?? resolvedStatus?.wires ?? 0)"

        setDot(dhtDot, enabled: resolvedProtocol?.dht ?? resolvedStatus?.dht ?? false)
        setDot(lsdDot, enabled: resolvedProtocol?.lsd ?? false)
        setDot(pexDot, enabled: resolvedProtocol?.pex ?? resolvedStatus?.pex ?? false)
        setDot(natDot, enabled: resolvedProtocol?.nat ?? false)
        setDot(forwardDot, enabled: resolvedProtocol?.forwarding ?? false)
        setDot(persistDot, enabled: resolvedProtocol?.persisting ?? Settings.persistFiles)
        setDot(streamingDot, enabled: resolvedProtocol?.streaming ?? false)

        if selectedTabIndex == 1 { refreshFiles() }
        if selectedTabIndex == 2 { refreshPeers() }
        if selectedTabIndex == 3 { refreshTrackers(force: false) }
        if selectedTabIndex == 4 { refreshLibrary() }
    }

    private func webTorrentETA(fromMilliseconds value: Double?) -> String? {
        guard let value else { return nil }
        let seconds = value.isFinite ? max(0, min(value / 1000, Double(Int.max / 2))) : 0
        return TorrentDetailViewController.eta(seconds: Int(seconds))
    }

    private func clearWebTorrentOverview(error: Error?) {
        if let error { NSLog("[Torrent Client] %@", error.localizedDescription) }
        nameLabel.text = "No Name Provided"
        hashLabel.text = ""
        statusBadge.text = "Downloading"
        statusBadge.backgroundColor = TorrentClientStyle.green500
        bigPercentLabel.text = "0.0%"
        progressBar.progress = 0
        [downloadedValue, uploadedValue, totalSizeValue].forEach { $0.text = TorrentDetailViewController.fastPrettyBytes(0) }
        piecesValue.text = "0 × " + TorrentDetailViewController.fastPrettyBytes(0)
        [downSpeedValue, upSpeedValue].forEach { $0.text = TorrentDetailViewController.fastPrettyBits(0) + "/s" }
        [etaValue, elapsedValue].forEach { $0.text = "0s" }
        [seedersValue, leechersValue, wiresValue].forEach { $0.text = "0" }
        for dot in [dhtDot, lsdDot, pexDot, natDot, forwardDot, persistDot, streamingDot] {
            setDot(dot, enabled: false)
        }
    }

    private func setDot(_ dot: UIView, enabled: Bool) {
        dot.backgroundColor = enabled ? TorrentClientStyle.green500 : TorrentClientStyle.red500
    }

    // MARK: - Build Overview UI

    private func buildOverviewUI() {
        overviewScrollView.backgroundColor = .clear
        overviewScrollView.isOpaque = false
        overviewScrollView.translatesAutoresizingMaskIntoConstraints = false
        [downloadedValue, uploadedValue, totalSizeValue, piecesValue,
         downSpeedValue, upSpeedValue, etaValue, elapsedValue,
         seedersValue, leechersValue, wiresValue].forEach {
            $0.textColor = TorrentClientStyle.foreground
        }

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 48
        stack.translatesAutoresizingMaskIntoConstraints = false
        overviewScrollView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: overviewScrollView.topAnchor),
            stack.leadingAnchor.constraint(equalTo: overviewScrollView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: overviewScrollView.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: overviewScrollView.bottomAnchor, constant: -8),
            stack.widthAnchor.constraint(equalTo: overviewScrollView.widthAnchor),
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

        let dlIcon = makeIcon("hard-drive-download", tint: TorrentClientStyle.foreground, size: 20)
        let progressTitle = UILabel()
        progressTitle.font = .nunito(ofSize: 24, weight: .bold)
        progressTitle.text = "Progress"
        progressTitle.textColor = TorrentClientStyle.foreground

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
            StatItem(label: downloadedValue, title: "Downloaded", icon: "download",   color: TorrentClientStyle.green500),
            StatItem(label: uploadedValue,   title: "Uploaded",   icon: "upload",     color: TorrentClientStyle.blue500),
            StatItem(label: totalSizeValue,  title: "Total Size", icon: "hard-drive", color: TorrentClientStyle.mutedForeground),
            StatItem(label: piecesValue,     title: "Pieces",     icon: "puzzle",     color: TorrentClientStyle.mutedForeground),
        ])
        container.addArrangedSubview(grid)

        return container
    }

    private func makeThreeColumnGrid() -> UIView {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 0
        overviewStatsStack = stack

        // Speed & Transfer
        stack.addArrangedSubview(makeFlatSection(
            title: "Speed & Transfer",
            icon: "wifi",
            items: [
                StatItem(label: downSpeedValue, title: "Download", icon: "download", color: TorrentClientStyle.green500),
                StatItem(label: upSpeedValue,   title: "Upload",   icon: "upload",   color: TorrentClientStyle.blue500),
            ]
        ))

        // Time Information
        stack.addArrangedSubview(makeFlatSection(
            title: "Time Information",
            icon: "clock",
            items: [
                StatItem(label: etaValue,     title: "Remaining", icon: "clock-fading", color: TorrentClientStyle.orange500),
                StatItem(label: elapsedValue, title: "Elapsed",   icon: "timer",        color: TorrentClientStyle.purple500),
            ]
        ))

        // Peers & Connections
        stack.addArrangedSubview(makeFlatSection(
            title: "Peers & Connections",
            icon: "users",
            items: [
                StatItem(label: seedersValue,  title: "Seeders",  icon: "user-round-plus",  color: TorrentClientStyle.green500),
                StatItem(label: leechersValue, title: "Leechers", icon: "user-round-minus", color: TorrentClientStyle.blue500),
                StatItem(label: wiresValue,    title: "Wires",    icon: "link",             color: TorrentClientStyle.purple500),
            ]
        ))

        return stack
    }

    private func makeProtocolStatusSection() -> UIView {
        let container = UIStackView()
        container.axis = .vertical
        container.spacing = 24
        container.isLayoutMarginsRelativeArrangement = true
        container.layoutMargins = UIEdgeInsets(top: 24, left: 0, bottom: 24, right: 0)

        let iconView = makeIcon("network", tint: TorrentClientStyle.foreground, size: 20)
        let title = UILabel()
        title.text = "Protocol Status"
        title.font = .nunito(ofSize: 24, weight: .bold)
        title.textColor = TorrentClientStyle.foreground
        let titleRow = UIStackView(arrangedSubviews: [iconView, title])
        titleRow.axis = .horizontal
        titleRow.spacing = 8
        titleRow.alignment = .center
        container.addArrangedSubview(titleRow)

        let columns = TorrentResponsiveGrid(cells: [makeProtocolColumn("Network Discovery", [
            ("DHT", "Distributed Hash Table for peer discovery", dhtDot),
            ("LSD", "Local Service Discovery on network", lsdDot),
            ("PEX", "Peer Exchange with other clients", pexDot),
        ]), makeProtocolColumn("Connection", [
            ("NAT", "NAT-PMP/UPnP automatic forwarding", natDot),
            ("Forwarding", "Accepting inbound connections", forwardDot),
        ]), makeProtocolColumn("Storage", [
            ("Persisting", "Storing all torrents", persistDot),
            ("Streaming", "Downloading only required pieces", streamingDot),
        ])], gap: 48)
        protocolColumnsStack = columns
        container.addArrangedSubview(columns)
        return container
    }

    private func makeProtocolColumn(_ header: String, _ rows: [(String, String, UIView)]) -> UIView {
        let col = UIStackView()
        col.axis = .vertical
        col.spacing = 12

        let headerLabel = UILabel()
        headerLabel.text = header
        headerLabel.font = .nunito(ofSize: 16, weight: .medium)
        headerLabel.textColor = TorrentClientStyle.foreground
        col.addArrangedSubview(headerLabel)
        col.setCustomSpacing(16, after: headerLabel)

        for (name, desc, dot) in rows {
            let nameLabel = UILabel()
            nameLabel.text = name
            nameLabel.font = .nunito(ofSize: 14, weight: .regular)
            nameLabel.textColor = TorrentClientStyle.foreground

            let descLabel = UILabel()
            descLabel.text = desc
            descLabel.font = .nunito(ofSize: 12, weight: .regular)
            descLabel.textColor = TorrentClientStyle.mutedForeground
            descLabel.numberOfLines = 0

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
        TorrentClientStyle.configurePlainContentView(peersView)

        let borderContainer = UIView()
        TorrentClientStyle.configureTableShell(borderContainer)
        borderContainer.translatesAutoresizingMaskIntoConstraints = false
        peersView.addSubview(borderContainer)

        peersHorizontalScrollView = UIScrollView()
        peersHorizontalScrollView.translatesAutoresizingMaskIntoConstraints = false
        peersHorizontalScrollView.showsHorizontalScrollIndicator = true
        peersHorizontalScrollView.showsVerticalScrollIndicator = false
        peersHorizontalScrollView.alwaysBounceHorizontal = false
        peersHorizontalScrollView.alwaysBounceVertical = false
        peersHorizontalScrollView.backgroundColor = .clear
        borderContainer.addSubview(peersHorizontalScrollView)

        peersTableView = UITableView(frame: .zero, style: .plain)
        peersTableView.translatesAutoresizingMaskIntoConstraints = false
        peersTableView.delegate = self
        peersTableView.dataSource = self
        peersTableView.register(PeerInfoCell.self, forCellReuseIdentifier: PeerInfoCell.reuseID)
        peersTableView.rowHeight = 56
        peersTableView.estimatedRowHeight = 56
        TorrentClientStyle.configureTableView(peersTableView)
        peersTableView.allowsSelection = false
        peersHorizontalScrollView.addSubview(peersTableView)

        NSLayoutConstraint.activate([
            borderContainer.topAnchor.constraint(equalTo: peersView.topAnchor),
            borderContainer.leadingAnchor.constraint(equalTo: peersView.leadingAnchor),
            borderContainer.trailingAnchor.constraint(equalTo: peersView.trailingAnchor),
            borderContainer.bottomAnchor.constraint(equalTo: peersView.bottomAnchor),

            peersHorizontalScrollView.topAnchor.constraint(equalTo: borderContainer.topAnchor),
            peersHorizontalScrollView.leadingAnchor.constraint(equalTo: borderContainer.leadingAnchor),
            peersHorizontalScrollView.trailingAnchor.constraint(equalTo: borderContainer.trailingAnchor),
            peersHorizontalScrollView.bottomAnchor.constraint(equalTo: borderContainer.bottomAnchor),

            peersTableView.topAnchor.constraint(equalTo: peersHorizontalScrollView.contentLayoutGuide.topAnchor),
            peersTableView.leadingAnchor.constraint(equalTo: peersHorizontalScrollView.contentLayoutGuide.leadingAnchor),
            peersTableView.trailingAnchor.constraint(equalTo: peersHorizontalScrollView.contentLayoutGuide.trailingAnchor),
            peersTableView.bottomAnchor.constraint(equalTo: peersHorizontalScrollView.contentLayoutGuide.bottomAnchor),
            peersTableView.heightAnchor.constraint(equalTo: peersHorizontalScrollView.frameLayoutGuide.heightAnchor),
            peersTableView.widthAnchor.constraint(greaterThanOrEqualTo: peersHorizontalScrollView.frameLayoutGuide.widthAnchor),
            peersTableView.widthAnchor.constraint(greaterThanOrEqualToConstant: PeerTableLayout.minimumContentWidth),
        ])
    }

    // MARK: - Build Trackers UI

    private func buildTrackersUI() {
        TorrentClientStyle.configurePlainContentView(trackersView)

        let borderContainer = UIView()
        TorrentClientStyle.configureTableShell(borderContainer)
        borderContainer.translatesAutoresizingMaskIntoConstraints = false
        trackersView.addSubview(borderContainer)

        trackersTableView = UITableView(frame: .zero, style: .plain)
        trackersTableView.translatesAutoresizingMaskIntoConstraints = false
        trackersTableView.delegate = self
        trackersTableView.dataSource = self
        trackersTableView.register(TrackerStatusCell.self, forCellReuseIdentifier: TrackerStatusCell.reuseID)
        trackersTableView.rowHeight = 56
        trackersTableView.estimatedRowHeight = 56
        TorrentClientStyle.configureTableView(trackersTableView)
        trackersTableView.allowsSelection = false
        TorrentClientStyle.installScrollableTable(trackersTableView, in: borderContainer, minimumWidth: 800)

        NSLayoutConstraint.activate([
            borderContainer.topAnchor.constraint(equalTo: trackersView.topAnchor),
            borderContainer.leadingAnchor.constraint(equalTo: trackersView.leadingAnchor),
            borderContainer.trailingAnchor.constraint(equalTo: trackersView.trailingAnchor),
            borderContainer.bottomAnchor.constraint(equalTo: trackersView.bottomAnchor),

        ])
    }

    private func refreshTrackers(force: Bool) {
        guard isWebTorrentMode else {
            webTrackerRows = []
            trackersTableView?.reloadData()
            return
        }
        guard !selectedHex.isEmpty else {
            webTrackerRows = []
            trackersTableView?.reloadData()
            return
        }
        guard force || Date().timeIntervalSince(lastWebTrackerRefresh) >= trackerRefreshInterval else { return }
        guard !webTrackersInFlight else { return }

        webTrackersInFlight = true
        let hash = selectedHex
        TorrentBackendManager.shared.webTorrentTrackers(hash: hash) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.webTrackersInFlight = false
                guard self.isWebTorrentMode, self.selectedHex == hash else { return }
                self.lastWebTrackerRefresh = Date()
                if case .success(let trackers) = result {
                    self.webTrackerRows = trackers
                        .map { (announce: $0.key, info: $0.value) }
                        .sorted { $0.announce.localizedCaseInsensitiveCompare($1.announce) == .orderedAscending }
                }
                self.trackersTableView?.reloadData()
            }
        }
    }

    // MARK: - Build Library UI

    private func buildLibraryUI() {
        TorrentClientStyle.configurePlainContentView(libraryView)

        librarySearchField.translatesAutoresizingMaskIntoConstraints = false
        librarySearchField.addTarget(self, action: #selector(librarySearchChanged), for: .editingChanged)
        libraryView.addSubview(librarySearchField)

        let rescanConfig = UIImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        libraryRescanButton.setImage(UIImage.hayaseIcon("folder-sync", withConfiguration: rescanConfig), for: .normal)
        TorrentClientStyle.configureIconButton(libraryRescanButton, variant: .secondary)
        libraryRescanButton.addTarget(self, action: #selector(rescanLibrary), for: .touchUpInside)
        libraryRescanButton.translatesAutoresizingMaskIntoConstraints = false

        let deleteConfig = UIImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        libraryDeleteButton.setImage(UIImage.hayaseIcon("trash", withConfiguration: deleteConfig), for: .normal)
        TorrentClientStyle.configureIconButton(libraryDeleteButton, variant: .destructive)
        libraryDeleteButton.addTarget(self, action: #selector(deleteSelectedLibraryEntries), for: .touchUpInside)
        libraryDeleteButton.translatesAutoresizingMaskIntoConstraints = false

        let buttonRow = UIStackView(arrangedSubviews: [libraryRescanButton, libraryDeleteButton])
        buttonRow.axis = .horizontal
        buttonRow.spacing = 8
        buttonRow.translatesAutoresizingMaskIntoConstraints = false
        libraryView.addSubview(buttonRow)

        librarySelectionLabel.translatesAutoresizingMaskIntoConstraints = false
        libraryView.addSubview(librarySelectionLabel)

        let borderContainer = UIView()
        TorrentClientStyle.configureTableShell(borderContainer)
        borderContainer.translatesAutoresizingMaskIntoConstraints = false
        libraryView.addSubview(borderContainer)

        libraryTableView = UITableView(frame: .zero, style: .plain)
        libraryTableView.translatesAutoresizingMaskIntoConstraints = false
        libraryTableView.delegate = self
        libraryTableView.dataSource = self
        libraryTableView.register(LibraryColumnCell.self, forCellReuseIdentifier: LibraryColumnCell.reuseID)
        libraryTableView.rowHeight = 56
        libraryTableView.estimatedRowHeight = 56
        TorrentClientStyle.configureTableView(libraryTableView)
        TorrentClientStyle.installScrollableTable(libraryTableView, in: borderContainer, minimumWidth: 1200)

        NSLayoutConstraint.activate([
            libraryRescanButton.widthAnchor.constraint(equalToConstant: 36),
            libraryRescanButton.heightAnchor.constraint(equalToConstant: 36),
            libraryDeleteButton.widthAnchor.constraint(equalToConstant: 36),
            libraryDeleteButton.heightAnchor.constraint(equalToConstant: 36),

            librarySearchField.topAnchor.constraint(equalTo: libraryView.topAnchor),
            librarySearchField.leadingAnchor.constraint(equalTo: libraryView.leadingAnchor),
            librarySearchField.trailingAnchor.constraint(equalTo: buttonRow.leadingAnchor, constant: -8),
            librarySearchField.heightAnchor.constraint(equalToConstant: 36),

            buttonRow.topAnchor.constraint(equalTo: libraryView.topAnchor),
            buttonRow.trailingAnchor.constraint(equalTo: libraryView.trailingAnchor),

            librarySelectionLabel.topAnchor.constraint(equalTo: librarySearchField.bottomAnchor, constant: 8),
            librarySelectionLabel.leadingAnchor.constraint(equalTo: libraryView.leadingAnchor),
            librarySelectionLabel.trailingAnchor.constraint(equalTo: libraryView.trailingAnchor),

            borderContainer.topAnchor.constraint(equalTo: librarySelectionLabel.bottomAnchor, constant: 8),
            borderContainer.leadingAnchor.constraint(equalTo: libraryView.leadingAnchor),
            borderContainer.trailingAnchor.constraint(equalTo: libraryView.trailingAnchor),
            borderContainer.bottomAnchor.constraint(equalTo: libraryView.bottomAnchor),

        ])
    }

    @objc private func librarySearchChanged() {
        refreshLibrary()
    }

    @objc private func rescanLibrary() {
        let hashes = Array(selectedLibraryHashes)
        guard !hashes.isEmpty, !libraryActionInFlight else { return }

        if isWebTorrentMode {
            libraryActionInFlight = true
            updateLibrarySelectionLabel()
            SettingsToast.show("Rescanning torrents...\nThis may take a VERY long while depending on the number of torrents.", in: view)
            TorrentBackendManager.shared.rescanWebTorrents(hashes: hashes) { [weak self] result in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.libraryActionInFlight = false
                    self.updateLibrarySelectionLabel()
                    if case .failure(let error) = result { self.showLibraryActionError(error) }
                    else { SettingsToast.show("Rescan complete", in: self.view) }
                    self.update()
                }
            }
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
            if let column = librarySortColumn {
                webFilteredLibraryEntries.sort {
                    TorrentLibrarySort.less($0, $1, column: column, ascending: librarySortAscending)
                }
            }
            let currentHashes = Set(webLibraryEntries.map { $0.hash })
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
        if let column = librarySortColumn {
            let models = Dictionary(uniqueKeysWithValues: filteredLibraryEntries.map { entry in
                let snapshot = readSnapshot(from: entry.handle, default: nil) { Optional($0) }
                let size = snapshot?.total ?? 0
                let model = WebTorrentLibraryEntry(mediaID: entry.entity?.animes?.animeAnilistId?.intValue,
                                                   episode: entry.entity?.videos?.count,
                                                   files: snapshot?.files.count ?? 0, hash: entry.hash,
                                                   progress: size > 0 ? Double(snapshot?.totalDone ?? 0) / Double(size) : 0,
                                                   date: nil, size: size,
                                                   name: entry.entity?.torrentName ?? snapshot?.name ?? entry.hash)
                return (entry.hash, model)
            })
            filteredLibraryEntries.sort {
                guard let lhs = models[$0.hash], let rhs = models[$1.hash] else { return $0.hash < $1.hash }
                return TorrentLibrarySort.less(lhs, rhs, column: column, ascending: librarySortAscending)
            }
        }
        let currentHashes = Set(libraryEntries.map { $0.hash })
        selectedLibraryHashes.formIntersection(currentHashes)
        updateLibrarySelectionLabel()
        libraryTableView?.reloadData()
    }

    private func librarySeriesTitle(for entry: WebTorrentLibraryEntry) -> String {
        guard let mediaID = entry.mediaID, mediaID > 0 else { return "?" }
        if let cached = animeTitleCache[mediaID] { return cached }

        let context = CoreDataService.sharedCoreDataService.mainQueueContext
        let request = NSFetchRequest<Animes>(entityName: Animes.entityName)
        request.predicate = NSPredicate(format: "animeAnilistId == %@", NSNumber(value: mediaID))
        request.fetchLimit = 1

        if let anime = (try? context.fetch(request))?.first {
            let title = AniListUtil.title(for: anime)
            if title != "TBA" {
                animeTitleCache[mediaID] = title
                return title
            }
        }

        if pendingAnimeTitles.insert(mediaID).inserted {
            AniListClient.shared.singleTitleResult(id: mediaID) { [weak self] result in
                guard let self else { return }
                self.pendingAnimeTitles.remove(mediaID)
                switch result {
                case .success(let title): self.animeTitleCache[mediaID] = title?.userPreferred ?? "?"
                case .failure: self.animeTitleCache[mediaID] = "?"
                }
                self.libraryTableView?.reloadData()
            }
        }
        return "..."
    }

    private func updateLibrarySelectionLabel() {
        let rowCount = isWebTorrentMode ? webFilteredLibraryEntries.count : filteredLibraryEntries.count
        librarySelectionLabel.text = "\(selectedLibraryHashes.count) of \(rowCount) row(s) selected."
        let hasSelection = !selectedLibraryHashes.isEmpty && !libraryActionInFlight
        TorrentClientStyle.setIconButtonEnabled(libraryRescanButton, enabled: hasSelection, variant: .secondary)
        TorrentClientStyle.setIconButtonEnabled(libraryDeleteButton, enabled: hasSelection, variant: .destructive)
    }

    private var allVisibleLibraryRowsSelected: Bool {
        let hashes = Set(isWebTorrentMode ? webFilteredLibraryEntries.map { $0.hash } : filteredLibraryEntries.map { $0.hash })
        return !hashes.isEmpty && hashes.isSubset(of: selectedLibraryHashes)
    }

    private func toggleLibrarySelection(hash: String, tableView: UITableView?, indexPath: IndexPath) {
        if selectedLibraryHashes.contains(hash) {
            selectedLibraryHashes.remove(hash)
        } else {
            selectedLibraryHashes.insert(hash)
        }
        updateLibrarySelectionLabel()
        tableView?.reloadData() // refresh the select-all header too
    }

    private func openNativeLibraryEntry(_ entry: (hash: String, handle: TorrentHandle, entity: Torrents?)) {
        if restoreMiniPlayerIfAlreadyPlaying(hash: entry.hash, episode: nil) { return }

        selectedHex = entry.hash
        selectedHandle = entry.handle
        selectedEntity = entry.entity

        guard let entity = entry.entity else {
            selectedTabIndex = 0
            updateTabButtonAppearances()
            showTab(0)
            return
        }

        if openNativePlayerIfPossible(entity: entity, handle: entry.handle) {
            return
        }

        let videoList = VideoListViewController()
        videoList.torrentEntity = entity
        navigationController?.pushViewController(videoList, animated: true)
    }

    private func openNativePlayerIfPossible(entity: Torrents, handle: TorrentHandle) -> Bool {
        let context = CoreDataService.sharedCoreDataService.mainQueueContext
        let fetch = NSFetchRequest<Videos>(entityName: Videos.entityName)
        fetch.predicate = NSPredicate(format: "torrents == %@", entity)
        fetch.sortDescriptors = [NSSortDescriptor(key: "videoIndex", ascending: true),
                                 NSSortDescriptor(key: "videoName", ascending: true)]
        let videos = (try? context.fetch(fetch)) ?? []
        guard let selectedVideo = videos.first else { return false }

        let selectedIndex = selectedVideo.videoIndex?.uintValue ?? 0
        let videoService = VideoService(torrentEntity: entity)
        videoService.torrentHandle = handle
        videoService.selectFileForStreaming(selectedIndex)
        let resolvedPath = videoService.UpdateFilePathForFileIndex(selectedIndex)
        if !resolvedPath.isEmpty, selectedVideo.videoPath != resolvedPath {
            selectedVideo.videoPath = resolvedPath
            try? context.save()
        }

        MiniPlayerManager.shared.close()
        let player = VideoPlayerViewController()
        player.videoEntity = selectedVideo
        player.torrentHandle = handle
        player.videoService = videoService
        player.fileIndex = selectedIndex
        let mediaID = entity.animes?.animeAnilistId?.intValue ?? 0
        player.anilistID = mediaID
        player.episodeNumber = TorrentBatchResolver.extractEpisodeNumber(from: selectedVideo.videoName ?? "") ?? 0
        player.totalEpisodes = entity.animes?.animeTotalEps?.intValue ?? 0
        player.allVideos = videos
        player.currentVideoIndex = videos.firstIndex(of: selectedVideo) ?? 0
        player.onEpisodeChange = { [weak self] episode, media in
            self?.handleEpisodeChangeFromTorrentClient(episode: episode,
                                                       media: media,
                                                       fallbackMediaID: mediaID)
        }
        Router.shared.navigateToPlayer(player, hostTabIndex: hayaseTabIndex)
        return true
    }

    private func openWebTorrentLibraryEntry(_ entry: WebTorrentLibraryEntry) {
        if restoreMiniPlayerIfAlreadyPlaying(hash: entry.hash, episode: entry.episode) { return }
        guard openingLibraryPlaybackHash != entry.hash else { return }
        guard let torrentEntity = torrentEntityForLibraryEntry(entry) else { return }

        cancelPendingLibraryPlayback()
        openingLibraryPlaybackHash = entry.hash
        selectedHex = entry.hash

        let episode = entry.episode ?? 0
        let mediaID = entry.mediaID ?? torrentEntity.animes?.animeAnilistId?.intValue ?? 0
        let videoService = VideoService(torrentEntity: torrentEntity, episode: episode, backendKind: .webtorrent)
        pendingLibraryPlaybackService = videoService

        showLibraryPlaybackLoading(entryName: entry.name)

        pendingLibraryPlaybackObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name(VideoService.LocalVideosDidUpdateNotification),
            object: nil,
            queue: .main
        ) { [weak self, weak videoService] _ in
            guard let self, let videoService else { return }
            self.finishWebTorrentLibraryPlayback(videoService: videoService,
                                                 torrentEntity: torrentEntity,
                                                 mediaID: mediaID,
                                                 episode: episode)
        }

        let timeout = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.presentedViewController?.dismiss(animated: false)
            self.openingLibraryPlaybackHash = nil
            self.cancelPendingLibraryPlayback()
            self.showLibraryPlaybackError("Timed out while preparing this torrent.")
        }
        pendingLibraryPlaybackTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.libraryPlaybackTimeout, execute: timeout)

        videoService.UpdateLocalVideo()
    }

    private func torrentEntityForLibraryEntry(_ entry: WebTorrentLibraryEntry) -> Torrents? {
        let context = CoreDataService.sharedCoreDataService.mainQueueContext
        let request = NSFetchRequest<Torrents>(entityName: Torrents.entityName)
        request.predicate = NSPredicate(format: "torrentHashString == %@", entry.hash)
        request.fetchLimit = 1

        let torrentEntity = (try? context.fetch(request).first)
            ?? NSEntityDescription.insertNewObject(forEntityName: Torrents.entityName, into: context) as? Torrents

        guard let torrentEntity else { return nil }
        torrentEntity.torrentHashString = entry.hash
        torrentEntity.torrentName = entry.name.isEmpty ? entry.hash : entry.name
        if torrentEntity.torrentDownloadURL?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
            torrentEntity.torrentDownloadURL = "magnet:?xt=urn:btih:\(entry.hash)"
        }
        torrentEntity.torrentSize = NSNumber(value: Double(entry.size) / 1024.0 / 1024.0)

        if let mediaID = entry.mediaID, mediaID > 0 {
            torrentEntity.animes = animeEntity(mediaID: mediaID, fallbackTitle: entry.name)
        }

        try? context.save()
        CoreDataService.sharedCoreDataService.saveRootContext {}
        return torrentEntity
    }

    private func animeEntity(mediaID: Int, fallbackTitle: String) -> Animes? {
        let context = CoreDataService.sharedCoreDataService.mainQueueContext
        let request = NSFetchRequest<Animes>(entityName: Animes.entityName)
        request.predicate = NSPredicate(format: "animeAnilistId == %@", NSNumber(value: mediaID))
        request.fetchLimit = 1
        if let existing = (try? context.fetch(request))?.first { return existing }

        guard let anime = NSEntityDescription.insertNewObject(forEntityName: Animes.entityName, into: context) as? Animes else {
            return nil
        }
        anime.animeAnilistId = NSNumber(value: mediaID)
        anime.animeTitleEnglish = fallbackTitle
        anime.animeTitleJapanese = fallbackTitle
        return anime
    }

    private func finishWebTorrentLibraryPlayback(videoService: VideoService,
                                                 torrentEntity: Torrents,
                                                 mediaID: Int,
                                                 episode: Int) {
        let context = CoreDataService.sharedCoreDataService.mainQueueContext
        let fetch = NSFetchRequest<Videos>(entityName: Videos.entityName)
        fetch.predicate = NSPredicate(format: "torrents == %@", torrentEntity)
        fetch.sortDescriptors = [NSSortDescriptor(key: "videoIndex", ascending: true),
                                 NSSortDescriptor(key: "videoName", ascending: true)]
        let videos = (try? context.fetch(fetch)) ?? []

        if videos.isEmpty && videoService.lastError == nil { return }

        presentedViewController?.dismiss(animated: false)
        cancelPendingLibraryPlayback(clearService: false)

        guard videoService.lastError == nil, !videos.isEmpty else {
            let message = videoService.lastError?.localizedDescription ?? "No playable video files were found."
            openingLibraryPlaybackHash = nil
            pendingLibraryPlaybackService = nil
            showLibraryPlaybackError(message)
            return
        }

        let selectedVideo = bestVideoForLibraryPlayback(videos: videos, episode: episode)
        let selectedIndex = selectedVideo.videoIndex?.uintValue ?? 0
        videoService.selectFileForStreaming(selectedIndex)
        let resolvedPath = videoService.UpdateFilePathForFileIndex(selectedIndex)
        if !resolvedPath.isEmpty, selectedVideo.videoPath != resolvedPath {
            selectedVideo.videoPath = resolvedPath
            try? context.save()
        }

        MiniPlayerManager.shared.close()
        let player = VideoPlayerViewController()
        player.videoEntity = selectedVideo
        player.torrentHandle = nil
        player.videoService = videoService
        player.fileIndex = selectedIndex
        player.anilistID = mediaID
        player.episodeNumber = episode > 0 ? episode : (TorrentBatchResolver.extractEpisodeNumber(from: selectedVideo.videoName ?? "") ?? 0)
        player.totalEpisodes = torrentEntity.animes?.animeTotalEps?.intValue ?? 0
        player.allVideos = videos
        player.currentVideoIndex = videos.firstIndex(of: selectedVideo) ?? 0
        player.onEpisodeChange = { [weak self] episode, media in
            self?.handleEpisodeChangeFromTorrentClient(episode: episode,
                                                       media: media,
                                                       fallbackMediaID: mediaID)
        }
        openingLibraryPlaybackHash = nil
        pendingLibraryPlaybackService = nil
        Router.shared.navigateToPlayer(player, hostTabIndex: hayaseTabIndex)
    }

    private func handleEpisodeChangeFromTorrentClient(episode: Int,
                                                      media: AnimeItem?,
                                                      fallbackMediaID: Int) {
        if let media {
            presentEpisodeSearch(media: media, episode: episode)
            return
        }

        guard fallbackMediaID > 0 else { return }
        AniListClient.shared.fetchAnimeByIdsResult([fallbackMediaID]) { [weak self] result in
            switch result {
            case .success(let items):
                guard let media = items.first else { return }
                DispatchQueue.main.async {
                    self?.presentEpisodeSearch(media: media, episode: episode)
                }
            case .failure(let error):
                NSLog("[Downloads] AniList lookup failed for episode change: %@", error.description)
            }
        }
    }

    private func presentEpisodeSearch(media: AnimeItem, episode: Int) {
        MiniPlayerManager.shared.close()

        let searchVC = ExtensionSearchViewController()
        searchVC.animeItem = media
        searchVC.initialEpisode = episode
        searchVC.shouldAutoSelectOnSearch = true

        let presenter = Self.topViewController() ?? self
        searchVC.prepareOverlayPresentation(from: presenter)
        presenter.present(searchVC, animated: true)
    }

    private static func topViewController() -> UIViewController? {
        guard let appDelegate = UIApplication.shared.delegate as? AppDelegate,
              let window = appDelegate.window else { return nil }
        var viewController = window.rootViewController
        while let presented = viewController?.presentedViewController,
              !presented.isBeingDismissed {
            viewController = presented
        }
        return viewController
    }

    private func restoreMiniPlayerIfAlreadyPlaying(hash: String, episode: Int?) -> Bool {
        guard MiniPlayerManager.shared.isActive,
              let player = MiniPlayerManager.shared.activePlayer else { return false }

        let activeHash = player.videoEntity?.torrents?.torrentHashString
            ?? player.torrentHandle?.infoHashes.best.hex
        guard activeHash == hash else { return false }

        if let episode, episode > 0, player.episodeNumber > 0, player.episodeNumber != episode {
            return false
        }

        Router.shared.navigate(.player, hostTabIndex: hayaseTabIndex)
        return true
    }

    private func bestVideoForLibraryPlayback(videos: [Videos], episode: Int) -> Videos {
        guard episode > 0 else { return videos.first! }

        if let exact = videos.first(where: { TorrentBatchResolver.extractEpisodeNumber(from: $0.videoName ?? "") == episode }) {
            return exact
        }

        let parsed = videos.compactMap { video -> (video: Videos, episode: Int)? in
            guard let ep = TorrentBatchResolver.extractEpisodeNumber(from: video.videoName ?? "") else { return nil }
            return (video, ep)
        }.sorted { $0.episode < $1.episode }

        if let match = parsed.first(where: { $0.episode == episode })?.video { return match }
        if let first = parsed.first, let last = parsed.last, episode >= first.episode, episode <= last.episode {
            return parsed.min { abs($0.episode - episode) < abs($1.episode - episode) }?.video ?? videos.first!
        }
        if episode <= videos.count {
            let sorted = videos.sorted { ($0.videoName ?? "").localizedStandardCompare($1.videoName ?? "") == .orderedAscending }
            return sorted[episode - 1]
        }
        return videos.first!
    }

    private func cancelPendingLibraryPlayback(clearService: Bool = true) {
        if let observer = pendingLibraryPlaybackObserver {
            NotificationCenter.default.removeObserver(observer)
            pendingLibraryPlaybackObserver = nil
        }
        pendingLibraryPlaybackTimeout?.cancel()
        pendingLibraryPlaybackTimeout = nil
        openingLibraryPlaybackHash = nil
        if clearService { pendingLibraryPlaybackService = nil }
    }

    private func showLibraryPlaybackLoading(entryName: String) {
        let alert = UIAlertController(title: "Preparing Player",
                                      message: entryName.isEmpty ? "Loading torrent metadata…" : entryName,
                                      preferredStyle: .alert)
        let spinner = UIActivityIndicatorView(style: .medium)
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.startAnimating()
        alert.view.addSubview(spinner)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: alert.view.centerXAnchor),
            spinner.bottomAnchor.constraint(equalTo: alert.view.bottomAnchor, constant: -18),
        ])
        present(alert, animated: true)
    }

    private func showLibraryPlaybackError(_ message: String) {
        let alert = UIAlertController(title: "Failed to Open Torrent", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .cancel))
        present(alert, animated: true)
    }

    @objc private func deleteSelectedLibraryEntries() {
        guard !selectedLibraryHashes.isEmpty, !libraryActionInFlight else { return }

        let hashes = Array(selectedLibraryHashes)
        let count = hashes.count
        let names = isWebTorrentMode
            ? webLibraryEntries.filter { hashes.contains($0.hash) }.map { $0.name.isEmpty ? $0.hash : $0.name }
            : libraryEntries.filter { hashes.contains($0.hash) }.map { snapshotName(for: $0.handle) }
        let alert = UIAlertController(
            title: "Are you absolutely sure?",
            message: "You are about to permanently delete \(count) torrent(s) from your library. This action cannot be undone.\n\n" + names.joined(separator: "\n"),
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            guard let self = self else { return }

            if self.isWebTorrentMode {
                self.libraryActionInFlight = true
                self.updateLibrarySelectionLabel()
                TorrentBackendManager.shared.deleteWebTorrents(hashes: hashes) { [weak self] result in
                    DispatchQueue.main.async {
                        guard let self else { return }
                        self.libraryActionInFlight = false
                        if case .failure(let error) = result {
                            self.updateLibrarySelectionLabel()
                            self.showLibraryActionError(error)
                            return
                        }
                        self.webLibraryEntries.removeAll { hashes.contains($0.hash) }
                        self.webSnapshotGeneration += 1
                        if hashes.contains(self.selectedHex) {
                            self.selectedHex = ""
                            self.webStatus = nil
                            self.webInfo = nil
                            self.webProtocol = nil
                            self.webFileInfos = []
                            self.webPeerInfos = []
                            self.webTrackerRows = []
                        }
                        self.selectedLibraryHashes.removeAll()
                        self.refreshLibrary()
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

    private func showLibraryActionError(_ error: Error) {
        NSLog("[Torrent Library] %@", error.localizedDescription)
        SettingsToast.show(error.localizedDescription, in: view)
    }

    @objc private func libraryHeaderTapped(_ sender: UIButton) {
        if sender.tag == 7 {
            let hashes = Set(isWebTorrentMode ? webFilteredLibraryEntries.map { $0.hash } : filteredLibraryEntries.map { $0.hash })
            if hashes.isSubset(of: selectedLibraryHashes) {
                selectedLibraryHashes.subtract(hashes)
            } else {
                selectedLibraryHashes.formUnion(hashes)
            }
        } else if librarySortColumn == sender.tag {
            librarySortAscending.toggle()
        } else {
            librarySortColumn = sender.tag
            librarySortAscending = true
        }
        refreshLibrary()
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

    private func makeFlatSection(title: String, icon: String, items: [StatItem]) -> UIView {
        let container = UIStackView()
        container.axis = .vertical
        container.spacing = 12

        let iconView = makeIcon(icon, tint: TorrentClientStyle.foreground, size: 20)
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .nunito(ofSize: 24, weight: .bold)
        titleLabel.textColor = TorrentClientStyle.foreground

        let titleRow = UIStackView(arrangedSubviews: [iconView, titleLabel])
        titleRow.axis = .horizontal
        titleRow.spacing = 8
        titleRow.alignment = .center

        let paddedTitle = UIStackView(arrangedSubviews: [titleRow])
        paddedTitle.axis = .vertical
        paddedTitle.layoutMargins = UIEdgeInsets(top: 24, left: 0, bottom: 12, right: 0)
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
        let iconView = makeIcon(item.icon, tint: item.color, size: 16)
        let titleLabel = UILabel()
        titleLabel.text = item.title
        titleLabel.font = .nunito(ofSize: 14, weight: .medium)
        titleLabel.textColor = TorrentClientStyle.mutedForeground

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
        let row = TorrentResponsiveGrid(cells: items.map { makeProgressStatCell($0) }, gap: 16)
        progressStatsGrid = row
        return row
    }

    private func makeProgressStatCell(_ item: StatItem) -> UIView {
        let iconView = makeIcon(item.icon, tint: item.color, size: 16)

        let titleLabel = UILabel()
        titleLabel.text = item.title
        titleLabel.font = .nunito(ofSize: 14, weight: .regular)
        titleLabel.textColor = TorrentClientStyle.mutedForeground

        item.label.font = .nunito(ofSize: 14, weight: .medium)
        item.label.adjustsFontSizeToFitWidth = true
        item.label.minimumScaleFactor = 0.6

        let text = UIStackView(arrangedSubviews: [titleLabel, item.label])
        text.axis = .vertical
        let stack = UIStackView(arrangedSubviews: [iconView, text])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 8
        return stack
    }
}

// MARK: - UITableViewDataSource & UITableViewDelegate

extension DownloadsViewController: UITableViewDataSource, UITableViewDelegate {

    private func emptyTableCell(text: String) -> UITableViewCell {
        let cell = UITableViewCell()
        TorrentClientStyle.configureTableCell(cell)
        cell.textLabel?.text = text
        cell.textLabel?.textAlignment = .center
        cell.textLabel?.textColor = TorrentClientStyle.mutedForeground
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
            return max(currentPeerRows().count, 1)
        } else if tableView === trackersTableView {
            return max(webTrackerRows.count, 1)
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
            let rows = currentPeerRows()
            if rows.isEmpty {
                return emptyTableCell(text: "No peers connected yet.")
            }
            guard let cell = tableView.dequeueReusableCell(
                withIdentifier: PeerInfoCell.reuseID, for: indexPath) as? PeerInfoCell else { return UITableViewCell() }
            guard indexPath.row < rows.count else { return cell }
            cell.configure(row: rows[indexPath.row])
            return cell
        } else if tableView === trackersTableView {
            if webTrackerRows.isEmpty {
                return emptyTableCell(text: "Loading...")
            }
            guard let cell = tableView.dequeueReusableCell(
                withIdentifier: TrackerStatusCell.reuseID, for: indexPath) as? TrackerStatusCell else { return UITableViewCell() }
            guard indexPath.row < webTrackerRows.count else { return cell }
            let row = webTrackerRows[indexPath.row]
            cell.configure(announce: row.announce, info: row.info)
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
                cell.configure(entry: entry,
                               seriesTitle: librarySeriesTitle(for: entry),
                               isSelected: selectedLibraryHashes.contains(entry.hash),
                               compact: false)
                cell.onOpen = { [weak self] in
                    self?.openWebTorrentLibraryEntry(entry)
                }
                cell.onSelectionToggle = { [weak self, weak tableView] in
                    self?.toggleLibrarySelection(hash: entry.hash, tableView: tableView, indexPath: indexPath)
                }
                return cell
            }

            if filteredLibraryEntries.isEmpty {
                return emptyTableCell(text: "No torrents downloaded yet.")
            }
            guard let cell = tableView.dequeueReusableCell(
                withIdentifier: LibraryColumnCell.reuseID, for: indexPath) as? LibraryColumnCell else { return UITableViewCell() }
            guard indexPath.row < filteredLibraryEntries.count else { return cell }
            let entry = filteredLibraryEntries[indexPath.row]
            cell.configure(handle: entry.handle,
                           entity: entry.entity,
                           isSelected: selectedLibraryHashes.contains(entry.hash),
                           compact: false)
            cell.onOpen = { [weak self] in
                self?.openNativeLibraryEntry(entry)
            }
            cell.onSelectionToggle = { [weak self, weak tableView] in
                self?.toggleLibrarySelection(hash: entry.hash, tableView: tableView, indexPath: indexPath)
            }
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
                openWebTorrentLibraryEntry(entry)
                return
            }

            guard indexPath.row < filteredLibraryEntries.count else { return }
            let entry = filteredLibraryEntries[indexPath.row]
            openNativeLibraryEntry(entry)
        }
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        if tableView === filesTableView {
            return makeFileColumnHeader()
        } else if tableView === peersTableView {
            return makeColumnHeader(columns: PeerTableLayout.columns,
                                    sortableColumnIndices: Set(0...7),
                                    activeColumnIndex: peersSortColumn?.rawValue,
                                    sortAscending: peersSortAscending,
                                    target: self,
                                    action: #selector(handlePeerHeaderTap(_:)), onSort: { [weak self] index, ascending in
                                        self?.peersSortColumn = PeerSortColumn(rawValue: index)
                                        self?.peersSortAscending = ascending
                                        self?.refreshPeers()
                                    })
        } else if tableView === trackersTableView {
            return makeColumnHeader(columns: [
                ("Tracker", nil),
                ("Status", 86),
                ("Downloaded", 96),
                ("Seeders", 76),
                ("Leechers", 86),
            ])
        } else if tableView === libraryTableView {
            return makeColumnHeader(columns: [
                ("Series", 288),
                ("Episode", 60),
                ("Files", 45),
                ("Size", 76),
                ("Status", 110),
                ("Date", 96),
                ("Torrent Name", nil),
                ("", 32),
            ], sortableColumnIndices: Set(0...7), activeColumnIndex: librarySortColumn,
               sortAscending: librarySortAscending, target: self, action: #selector(libraryHeaderTapped(_:)),
               selectAll: allVisibleLibraryRowsSelected, onSort: { [weak self] index, ascending in
                   self?.librarySortColumn = index
                   self?.librarySortAscending = ascending
                   self?.refreshLibrary()
               })
        }
        return nil
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        if tableView === filesTableView || tableView === peersTableView || tableView === trackersTableView || tableView === libraryTableView {
            return 48
        }
        return 0
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        if tableView === filesTableView {
            return (isWebTorrentMode ? webFilteredFileInfos.isEmpty : filteredFileEntries.isEmpty) ? 160 : UITableView.automaticDimension
        } else if tableView === peersTableView {
            return currentPeerRows().isEmpty ? 160 : 56
        } else if tableView === trackersTableView {
            return webTrackerRows.isEmpty ? 160 : 56
        } else if tableView === libraryTableView {
            let isEmpty = isWebTorrentMode ? webFilteredLibraryEntries.isEmpty : filteredLibraryEntries.isEmpty
            if isEmpty { return 160 }
            return UITableView.automaticDimension
        }
        return UITableView.automaticDimension
    }

    private func makeColumnHeader(columns: [(String, CGFloat?)],
                                  sortableColumnIndices: Set<Int> = [],
                                  activeColumnIndex: Int? = nil,
                                  sortAscending: Bool = true,
                                  target: Any? = nil,
                                  action: Selector? = nil,
                                  selectAll: Bool? = nil,
                                  onSort: ((Int, Bool) -> Void)? = nil) -> UIView {
        ColumnHeader.make(columns: columns,
                          sortableColumnIndices: sortableColumnIndices,
                          activeColumnIndex: activeColumnIndex,
                          sortAscending: sortAscending,
                          target: target,
                          action: action, selectAll: selectAll, onSort: onSort)
    }

    /// Uses the same Asc/Desc menu and shared header as peers and library.
    private func makeFileColumnHeader() -> UIView {
        makeColumnHeader(columns: [("File Name", nil), ("Size", 80), ("Progress", 128), ("Streams", 70)],
                         sortableColumnIndices: Set(0...3), activeColumnIndex: filesSortColumn?.rawValue,
                         sortAscending: filesSortAscending, target: self, action: #selector(fileColumnHeaderTapped(_:)),
                         onSort: { [weak self] index, ascending in
                             self?.filesSortColumn = FileSortColumn(rawValue: index)
                             self?.filesSortAscending = ascending
                             self?.refreshFiles()
                         })
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
