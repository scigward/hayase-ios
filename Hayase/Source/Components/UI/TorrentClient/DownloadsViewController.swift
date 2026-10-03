//
//  DownloadsViewController.swift
//  Hayase
//
//  Mirrors: src/routes/app/client/+layout.svelte, src/routes/app/client/+page.ts, src/routes/app/client/+page.svelte, src/lib/components/SettingsNav.svelte
//

import UIKit
import CoreData

// MARK: - DownloadsViewController

/// Hayase-style torrent client page with tabbed interface:
/// Overview, Files, Peers, Trackers, Library, Settings.
/// Auto-selects the first active torrent and updates every second.
class DownloadsViewController: UIViewController {

    // MARK: - Properties

    private var updateTimer: Timer?

    /// The torrent being played
    private var selectedHex: String = ""

    private var selectedTabIndex: Int = 0
    private var clientRoute: Route.ClientRoute = .root
    private static let settingsTabIndex = 5

    // MARK: - Page header

    private let pageTitleLabel: UILabel = {
        let l = TorrentClientLabel()
        l.lineHeight = 32
        l.font = .nunito(ofSize: 24, weight: .bold)
        l.textColor = TorrentClientStyle.foreground
        l.text = "Torrent Client"
        return l
    }()

    private let pageSubtitleLabel: UILabel = {
        let l = TorrentClientLabel()
        l.lineHeight = 24
        l.font = .nunito(ofSize: 16, weight: .regular)
        l.textColor = TorrentClientStyle.mutedForeground
        l.text = "Monitor your torrents, and configure settings for your torrent client."
        l.numberOfLines = 0
        l.lineBreakMode = .byWordWrapping
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
    private let tabBarContainer = UIView()
    private let tabScrollView = UIScrollView()
    private let tabStackView = UIStackView()
    private let bodyStackView = UIStackView()
    private let headerSeparator = UIView()
    private let globeView = Globe()
    private let webTorrentVersionLabel: UILabel = {
        let label = TorrentClientLabel()
        label.lineHeight = 16
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
    private var versionBottomConstraint: NSLayoutConstraint?
    private var versionTopConstraint: NSLayoutConstraint?
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
        return sv
    }()

    private let nameLabel: UILabel = {
        let l = TorrentClientLabel()
        l.lineHeight = 32
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
        let l = TorrentClientLabel()
        l.font = .nunito(ofSize: 14)
        l.textColor = TorrentClientStyle.mutedForeground
        l.numberOfLines = 1
        l.lineBreakMode = .byTruncatingMiddle
        return l
    }()

    private let bigPercentLabel: UILabel = {
        let l = TorrentClientLabel()
        l.lineHeight = 32
        l.font = .nunito(ofSize: 24, weight: .bold)
        l.textColor = TorrentClientStyle.foreground
        return l
    }()

    private let progressBar = TorrentClientProgressBar(height: 12)

    // Progress stat values
    private let downloadedValue  = TorrentClientLabel()
    private let uploadedValue    = TorrentClientLabel()
    private let totalSizeValue   = TorrentClientLabel()
    private let piecesValue      = TorrentClientLabel()

    // Speed & Transfer / Time / Peers values
    private let downSpeedValue   = TorrentClientLabel()
    private let upSpeedValue     = TorrentClientLabel()
    private let etaValue         = TorrentClientLabel()
    private let elapsedValue     = TorrentClientLabel()
    private let seedersValue     = TorrentClientLabel()
    private let leechersValue    = TorrentClientLabel()
    private let wiresValue       = TorrentClientLabel()

    // Protocol status dots
    private let dhtDot       = TorrentFormat.makeDotLabel()
    private let lsdDot       = TorrentFormat.makeDotLabel()
    private let pexDot       = TorrentFormat.makeDotLabel()
    private let natDot       = TorrentFormat.makeDotLabel()
    private let forwardDot   = TorrentFormat.makeDotLabel()
    private let persistDot   = TorrentFormat.makeDotLabel()
    private let streamingDot = TorrentFormat.makeDotLabel()
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
    private var filesColumnWidths: [CGFloat?] = TorrentClientColumnWidths.files(entries: [])
    private var filesMinimumWidth: NSLayoutConstraint?

    /// Column sort state for the Files tab (mirrors Hayase addSortBy plugin with toggleOrder: ['asc','desc']).
    /// Source dropdown offers only ascending and descending order.
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
    private var peerColumnWidths = PeerTableLayout.widths(for: [])
    private var peersMinimumWidth: NSLayoutConstraint?

    // MARK: - Trackers tab

    private let trackersView = UIView()
    private var trackersTableView: UITableView!
    private var trackerColumnWidths = TrackerTableLayout.widths(for: [])
    private var trackersMinimumWidth: NSLayoutConstraint?
    private var webTrackerRows: [(announce: String, info: WebTorrentTrackerInfo)] = []

    // MARK: - Library tab

    private let libraryView = UIView()
    private var libraryTableView: UITableView!
    private let librarySearchField = TorrentClientStyle.makeSearchField(placeholder: "Search by Torrent Name...")
    private var libraryColumnWidths: [CGFloat?] = TorrentClientColumnWidths.library(entries: [])
    private var libraryMinimumWidth: NSLayoutConstraint?

    private var webStatus: WebTorrentBridgeStatus?
    private var webInfo: WebTorrentTorrentInfo?
    private var webProtocol: WebTorrentProtocolStatus?
    private var webFileInfos: [WebTorrentFileInfo] = []
    private var webFilteredFileInfos: [WebTorrentFileInfo] = []
    private var webFileInfoHash: String?
    private var webPeerInfos: [WebTorrentPeerInfo] = []
    private var webLibraryEntries: [WebTorrentLibraryEntry] = []
    private var webFilteredLibraryEntries: [WebTorrentLibraryEntry] = []
    private var webActiveInFlight = false
    private var webStoresInFlight = Set<WebStore>()
    private var webStoresFetchedAt: [WebStore: Date] = [:]
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
    private weak var pendingLibraryPlayer: VideoPlayerViewController?
    private static let libraryPlaybackTimeout: TimeInterval = 120

    private let librarySelectionLabel: UILabel = {
        let l = TorrentClientLabel()
        l.font = .nunito(ofSize: 14)
        l.textColor = TorrentClientStyle.mutedForeground
        l.text = "0 of 0 row(s) selected."
        l.textAlignment = .right
        return l
    }()
    private let libraryRescanButton = SelectButton()
    private let libraryDeleteButton = SelectButton()

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
        buildOverviewUI()
        buildFilesUI()
        buildPeersUI()
        buildTrackersUI()
        buildLibraryUI()
        installTabPages()

        if clientRoute == .root {
            tabContentViews.forEach { $0.isHidden = true }
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

    // MARK: - Timer

    private func startTimer() {
        stopTimer()
        webStoresFetchedAt.removeAll()
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

    // MARK: - Torrent selection

    /// `server.active`: the overview follows what is playing, never a library entry.
    private func autoSelectFirstTorrent() {
        selectedHex = webStatus?.infoHash ?? ""
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

        let pageTitleTopConstraint = pageTitleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: TorrentClientStyle.compactPadding)
        self.pageTitleTopConstraint = pageTitleTopConstraint
        let pageTitleLeadingConstraint = pageTitleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: TorrentClientStyle.compactPadding)
        self.pageTitleLeadingConstraint = pageTitleLeadingConstraint
        let pageTitleTrailingConstraint = pageTitleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -TorrentClientStyle.compactPadding)
        self.pageTitleTrailingConstraint = pageTitleTrailingConstraint
        let pageSubtitleTrailingConstraint = pageSubtitleLabel.trailingAnchor.constraint(equalTo: pageTitleLabel.trailingAnchor)
        self.pageSubtitleTrailingConstraint = pageSubtitleTrailingConstraint
        let headerSeparatorTopConstraint = headerSeparator.topAnchor.constraint(equalTo: pageSubtitleLabel.bottomAnchor, constant: TorrentClientStyle.compactSeparatorSpacing)
        self.headerSeparatorTopConstraint = headerSeparatorTopConstraint
        let headerSeparatorLeadingConstraint = headerSeparator.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: TorrentClientStyle.compactPadding)
        self.headerSeparatorLeadingConstraint = headerSeparatorLeadingConstraint
        let headerSeparatorTrailingConstraint = headerSeparator.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -TorrentClientStyle.compactPadding)
        self.headerSeparatorTrailingConstraint = headerSeparatorTrailingConstraint

        NSLayoutConstraint.activate([
            pageTitleTopConstraint,
            pageTitleLeadingConstraint,
            pageTitleTrailingConstraint,

            pageSubtitleLabel.topAnchor.constraint(equalTo: pageTitleLabel.bottomAnchor, constant: 2),
            pageSubtitleLabel.leadingAnchor.constraint(equalTo: pageTitleLabel.leadingAnchor),
            pageSubtitleTrailingConstraint,

            headerSeparatorTopConstraint,
            headerSeparatorLeadingConstraint,
            headerSeparatorTrailingConstraint,
            headerSeparator.heightAnchor.constraint(equalToConstant: 1),
        ])
    }

    private func setupContainerView() {
        setupTabNavigation()

        bodyStackView.axis = .vertical
        bodyStackView.spacing = 0
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
        let globeWidthConstraint = globeView.widthAnchor.constraint(equalToConstant: 400)
        self.globeWidthConstraint = globeWidthConstraint
        let bodyTopConstraint = bodyStackView.topAnchor.constraint(equalTo: headerSeparator.bottomAnchor, constant: TorrentClientStyle.compactSeparatorSpacing)
        self.bodyTopConstraint = bodyTopConstraint
        let bodyLeadingConstraint = bodyStackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: TorrentClientStyle.compactPadding)
        self.bodyLeadingConstraint = bodyLeadingConstraint
        let bodyTrailingConstraint = bodyStackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -TorrentClientStyle.compactPadding)
        self.bodyTrailingConstraint = bodyTrailingConstraint

        NSLayoutConstraint.activate([
            bodyTopConstraint,
            bodyLeadingConstraint,
            bodyTrailingConstraint,
            bodyStackView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            containerView.heightAnchor.constraint(greaterThanOrEqualToConstant: 0),
            containerView.widthAnchor.constraint(lessThanOrEqualToConstant: TorrentClientStyle.clientContentMaxWidth),
            globeWidthConstraint,
            globeView.heightAnchor.constraint(equalTo: globeView.widthAnchor),
            globeView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            globeView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
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
                tabView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -8),
            ])
        }
        containerView.sendSubviewToBack(globeView)
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
        tabScrollBottomToFooterConstraint = tabScrollView.bottomAnchor.constraint(equalTo: webTorrentVersionLabel.topAnchor, constant: -20)
        versionBottomConstraint = webTorrentVersionLabel.bottomAnchor.constraint(equalTo: tabBarContainer.bottomAnchor, constant: -20)
        versionTopConstraint = webTorrentVersionLabel.topAnchor.constraint(equalTo: tabStackView.bottomAnchor, constant: 20)
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
        height.isActive = true
        tabButtonHeightConstraints.append(height)
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
        bodyStackView.spacing = wide ? TorrentClientStyle.sidebarGap : 0
        tabStackView.axis = (wide || !medium) ? .vertical : .horizontal
        tabStackView.alignment = (wide || !medium) ? .fill : .center
        tabStackView.spacing = (wide || !medium) ? 4 : 8  // gap-y-1 / gap-x-2

        tabBarWidthConstraint?.isActive = wide
        // Compact index has only the menu: let its scroll viewport fill the
        // remaining height instead of forcing the header to absorb that space.
        tabBarHeightConstraint?.isActive = medium && !wide
        tabBarHeightConstraint?.constant = 36 + 40 + 16
        tabStackWidthConstraint?.isActive = wide || !medium
        tabStackHeightConstraint?.isActive = medium && !wide
        let showsVersion = width >= 640
        versionBottomConstraint?.isActive = wide && showsVersion
        versionTopConstraint?.constant = medium ? 20 : 12
        versionTopConstraint?.isActive = !wide && showsVersion
        tabScrollBottomToFooterConstraint?.constant = medium ? -20 : -12
        tabScrollBottomToContainerConstraint?.isActive = !showsVersion
        tabScrollBottomToFooterConstraint?.isActive = showsVersion
        webTorrentVersionLabel.isHidden = !showsVersion

        for (index, button) in tabButtons.enumerated() {
            let height = medium ? CGFloat(36) : CGFloat(40)  // default h-9 / lg h-10
            tabButtonHeightConstraints[safe: index]?.constant = height
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
            updatePageHeader(for: 0)
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
        // A store starts fresh when something subscribes to it.
        webStoresFetchedAt.removeAll()
        for (tabIndex, tabView) in tabContentViews.enumerated() {
            tabView.isHidden = tabIndex != index
        }

        switch index {
        case 0:
            update()
        case 1:
            refreshFiles()
        case 2:
            refreshPeers()
        case 3:
            refreshTrackers()
        case 4:
            refreshLibrary()
        default:
            break
        }
        if index != 0 { updateWebTorrent() }
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
        filesMinimumWidth = TorrentClientStyle.installScrollableTable(filesTableView, in: borderContainer,
            minimumWidth: TorrentClientColumnWidths.minimumTableWidth(filesColumnWidths,
                flexibleMinimums: [0: TorrentClientColumnWidths.filesNameMinimum]))

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
        filesColumnWidths = TorrentClientColumnWidths.files(entries: webFilteredFileInfos)
        updateFileColumnLayout()
    }

    private func updateFileColumnLayout() {
        filesMinimumWidth?.constant = TorrentClientColumnWidths.minimumTableWidth(filesColumnWidths,
            flexibleMinimums: [0: TorrentClientColumnWidths.filesNameMinimum])
        filesTableView?.reloadData()
    }

    private func refreshPeers() {
        let rows = currentPeerRows()
        peerColumnWidths = PeerTableLayout.widths(for: rows)
        peersMinimumWidth?.constant = PeerTableLayout.minimumContentWidth(widths: peerColumnWidths)
        globeView.setPeers(rows)
        peersTableView?.reloadData()
    }

    private func currentPeerRows() -> [TorrentClientPeerRow] {
        var rows = webPeerInfos.map(TorrentClientPeerRow.init(peer:))

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
            peersSortAscending.toggle()
        } else {
            peersSortColumn = column
            peersSortAscending = true
        }
        peersTableView?.reloadData()
    }

    // MARK: - Data update

    private func update() {
        updateWebTorrent()
    }

    // MARK: - WebTorrent stores

    /// Each of interface's `server` stores (client.ts `_timedSafeStore`) polls only while something
    /// on screen reads it, on its own schedule and apart from the others, so a slow endpoint
    /// holds back none of the rest.
    private enum WebStore {
        case stats, protocolStatus, peers, files, trackers, library

        /// `stats` runs every 200ms there (3s when underpowered), which a phone spares its
        /// battery by doing once a second.
        var interval: TimeInterval {
            switch self {
            case .stats: return 1
            case .protocolStatus, .peers, .files: return 5
            case .trackers, .library: return 120
            }
        }

        /// Overview reads stats and protocol, and peers for its globe.
        static func shown(onTab tab: Int) -> [WebStore] {
            switch tab {
            case 0: return [.stats, .protocolStatus, .peers]
            case 1: return [.files]
            case 2: return [.peers]
            case 3: return [.trackers]
            case 4: return [.library]
            default: return []
            }
        }
    }

    private func updateWebTorrent() {
        refreshWebActive()
        for store in WebStore.shown(onTab: selectedTabIndex) {
            // The timer's own jitter must not cost a store its turn.
            let due = Date().timeIntervalSince(webStoresFetchedAt[store] ?? .distantPast) >= store.interval - 0.1
            if due && !webStoresInFlight.contains(store) { fetchWebStore(store) }
        }
    }

    /// The torrent being played, which interface holds in `server.active` and the bridge reports.
    private func refreshWebActive() {
        guard !webActiveInFlight else { return }
        webActiveInFlight = true
        TorrentBackendManager.shared.webTorrentStatus { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.webActiveInFlight = false
                switch result {
                case .success(let status):
                    if status.infoHash != self.webStatus?.infoHash { self.resetWebTorrentSnapshots() }
                    self.webStatus = status
                    self.selectedHex = status.infoHash ?? ""
                    self.webLastError = nil
                case .failure(let error):
                    self.webLastError = error
                }
                self.renderWebOverview()
            }
        }
    }

    /// Another torrent is playing: what was read for the last one no longer applies.
    private func resetWebTorrentSnapshots() {
        webSnapshotGeneration += 1
        webStoresFetchedAt.removeAll()
        webInfo = nil
        webProtocol = nil
        webFileInfos = []
        webTrackerRows = []
        webPeerInfos = []
        webFileInfoHash = nil
        refreshFiles()
        refreshPeers()
        refreshTrackers()
    }

    private func fetchWebStore(_ store: WebStore) {
        let manager = TorrentBackendManager.shared
        let hash = selectedHex
        // Everything but the library is about the torrent being played, and there is nothing to
        // ask while none is.
        guard store == .library || !hash.isEmpty else { return }
        let generation = webSnapshotGeneration
        webStoresInFlight.insert(store)

        func finish<T>(_ result: Result<T, Error>, apply: @escaping (T) -> Void) {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.webStoresInFlight.remove(store)
                self.webStoresFetchedAt[store] = Date()
                guard self.webSnapshotGeneration == generation else { return }
                // A failed refresh must not erase the last successful snapshot.
                guard case .success(let value) = result else {
                    if case .failure(let error) = result { NSLog("[Torrent Client] %@ refresh failed: %@", "\(store)", error.localizedDescription) }
                    return
                }
                apply(value)
                self.renderWebStore(store)
            }
        }

        switch store {
        case .stats:
            manager.webTorrentInfo(hash: hash) { result in finish(result) { [weak self] in self?.webInfo = $0 } }
        case .protocolStatus:
            manager.webTorrentProtocolStatus(hash: hash) { result in finish(result) { [weak self] in self?.webProtocol = $0 } }
        case .peers:
            manager.webTorrentPeerInfo(hash: hash) { result in finish(result) { [weak self] in self?.webPeerInfos = $0 } }
        case .files:
            manager.webTorrentFileInfo(hash: hash) { result in
                finish(result) { [weak self] in
                    self?.webFileInfos = $0
                    self?.webFileInfoHash = hash
                }
            }
        case .trackers:
            manager.webTorrentTrackers(hash: hash) { result in
                finish(result) { [weak self] in
                    self?.webTrackerRows = $0
                        .map { (announce: $0.key, info: $0.value) }
                        // torrent-client lists the trackers that answered first and the failed ones after;
                        // the keys come back unordered, so the groups are rebuilt.
                        .sorted {
                            if $0.info.failed != $1.info.failed { return !$0.info.failed }
                            return $0.announce.localizedCaseInsensitiveCompare($1.announce) == .orderedAscending
                        }
                }
            }
        case .library:
            manager.webTorrentLibrary { result in
                finish(result) { [weak self] in
                    self?.webLibraryEntries = $0
                    WebTorrentDownloaded.shared.replace(with: $0.map { $0.hash })
                }
            }
        }
    }

    private func renderWebStore(_ store: WebStore) {
        switch store {
        case .stats, .protocolStatus:
            renderWebOverview()
        case .peers:
            if selectedTabIndex == 2 { refreshPeers() } else { globeView.setPeers(currentPeerRows()) }
        case .files:
            if selectedTabIndex == 1 { refreshFiles() }
        case .trackers:
            refreshTrackers()
        case .library:
            refreshLibrary()
        }
    }

    private func renderWebOverview() {
        guard !selectedHex.isEmpty else {
            clearWebTorrentOverview(error: webLastError)
            return
        }
        let resolvedStatus = webStatus
        let resolvedInfo = webInfo
        let resolvedProtocol = webProtocol

        let torrentName = resolvedInfo?.name ?? ""
        nameLabel.text = torrentName.isEmpty ? "No Name Provided" : torrentName
        hashLabel.text = selectedHex

        let progress = resolvedInfo?.progress ?? resolvedStatus?.progress ?? 0
        let completed = progress == 1
        statusBadge.text = completed ? "Seeding" : "Downloading"
        statusBadge.backgroundColor = completed ? TorrentClientStyle.blue500 : TorrentClientStyle.green500
        bigPercentLabel.text = String(format: "%.1f%%", progress * 100)
        progressBar.progress = Float(max(0, min(progress, 1)))

        let downloaded = resolvedInfo?.size.downloaded ?? resolvedStatus?.downloaded ?? 0
        let uploaded = resolvedInfo?.size.uploaded ?? resolvedStatus?.uploaded ?? 0
        let total = resolvedInfo?.size.total ?? resolvedStatus?.total ?? 0
        downloadedValue.text = TorrentFormat.fastPrettyBytes(downloaded)
        uploadedValue.text = TorrentFormat.fastPrettyBytes(uploaded)
        totalSizeValue.text = TorrentFormat.fastPrettyBytes(total)

        setPiecesValue(total: resolvedInfo?.pieces.total ?? 0, size: resolvedInfo?.pieces.size ?? 0)

        let down = resolvedInfo?.speed.down ?? resolvedStatus?.downloadSpeed ?? 0
        let up = resolvedInfo?.speed.up ?? resolvedStatus?.uploadSpeed ?? 0
        downSpeedValue.text = TorrentFormat.fastPrettyBits(down * 8) + "/s"
        upSpeedValue.text = TorrentFormat.fastPrettyBits(up * 8) + "/s"
        if resolvedProtocol?.streaming == true {
            etaValue.text = "Streaming"
        } else {
            etaValue.text = webTorrentETA(fromMilliseconds: resolvedInfo?.time.remaining)
                ?? TorrentFormat.eta(remaining: total > downloaded ? total - downloaded : 0, rate: down)
        }
        let elapsed = resolvedInfo?.time.elapsed ?? 0 // elapsed is seconds, unlike remaining.
        elapsedValue.text = TorrentFormat.eta(seconds: Int(elapsed.isFinite ? max(0, min(elapsed, Double(Int.max / 2))) : 0))

        seedersValue.text = "\(resolvedInfo?.peers.seeders ?? 0)"
        leechersValue.text = "\(resolvedInfo?.peers.leechers ?? 0)"
        wiresValue.text = "\(resolvedInfo?.peers.wires ?? 0)"

        setDot(dhtDot, enabled: resolvedProtocol?.dht ?? resolvedStatus?.dht ?? false)
        setDot(lsdDot, enabled: resolvedProtocol?.lsd ?? false)
        setDot(pexDot, enabled: resolvedProtocol?.pex ?? resolvedStatus?.pex ?? false)
        setDot(natDot, enabled: resolvedProtocol?.nat ?? false)
        setDot(forwardDot, enabled: resolvedProtocol?.forwarding ?? false)
        setDot(persistDot, enabled: resolvedProtocol?.persisting ?? Settings.persistFiles)
        setDot(streamingDot, enabled: resolvedProtocol?.streaming ?? false)
    }

    private func webTorrentETA(fromMilliseconds value: Double?) -> String? {
        guard let value else { return nil }
        let seconds = value.isFinite ? max(0, min(value / 1000, Double(Int.max / 2))) : 0
        return TorrentFormat.eta(seconds: Int(seconds))
    }

    private func clearWebTorrentOverview(error: Error?) {
        if let error { NSLog("[Torrent Client] %@", error.localizedDescription) }
        nameLabel.text = "No Name Provided"
        hashLabel.text = ""
        statusBadge.text = "Downloading"
        statusBadge.backgroundColor = TorrentClientStyle.green500
        bigPercentLabel.text = "0.0%"
        progressBar.progress = 0
        [downloadedValue, uploadedValue, totalSizeValue].forEach { $0.text = TorrentFormat.fastPrettyBytes(0) }
        setPiecesValue(total: 0, size: 0)
        [downSpeedValue, upSpeedValue].forEach { $0.text = TorrentFormat.fastPrettyBits(0) + "/s" }
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
            stack.topAnchor.constraint(equalTo: overviewScrollView.contentLayoutGuide.topAnchor),
            stack.leadingAnchor.constraint(equalTo: overviewScrollView.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: overviewScrollView.contentLayoutGuide.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: overviewScrollView.contentLayoutGuide.bottomAnchor),
            stack.widthAnchor.constraint(equalTo: overviewScrollView.frameLayoutGuide.widthAnchor),
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
        statusBadge.setContentHuggingPriority(.required, for: .horizontal)
        statusBadge.setContentCompressionResistancePriority(.required, for: .horizontal)
        statusBadge.heightAnchor.constraint(equalToConstant: 20).isActive = true
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
        titleRow.spacing = 14 // gap-2 plus the heading icon's mr-1.5.

        let dlIcon = makeIcon("hard-drive-download", tint: TorrentClientStyle.foreground, size: 20)
        let progressTitle = TorrentClientLabel()
        progressTitle.lineHeight = 32
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
        let title = TorrentClientLabel()
        title.lineHeight = 24
        title.text = "Protocol Status"
        title.font = .nunito(ofSize: 24, weight: .bold)
        title.textColor = TorrentClientStyle.foreground
        let titleRow = UIStackView(arrangedSubviews: [iconView, title])
        titleRow.axis = .horizontal
        titleRow.spacing = 14
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

        let headerLabel = TorrentClientLabel()
        headerLabel.lineHeight = 24
        headerLabel.text = header
        headerLabel.font = .nunito(ofSize: 16, weight: .medium)
        headerLabel.textColor = TorrentClientStyle.foreground
        col.addArrangedSubview(headerLabel)
        col.setCustomSpacing(16, after: headerLabel)

        for (name, desc, dot) in rows {
            let nameLabel = TorrentClientLabel()
            nameLabel.text = name
            nameLabel.font = .nunito(ofSize: 14, weight: .regular)
            nameLabel.textColor = TorrentClientStyle.foreground

            let descLabel = TorrentClientLabel()
            descLabel.lineHeight = 16
            descLabel.text = desc
            descLabel.font = .nunito(ofSize: 12, weight: .regular)
            descLabel.textColor = TorrentClientStyle.mutedForeground
            descLabel.numberOfLines = 0

            let textStack = UIStackView(arrangedSubviews: [nameLabel, descLabel])
            textStack.axis = .vertical
            textStack.spacing = 0
            textStack.isLayoutMarginsRelativeArrangement = true
            textStack.layoutMargins = UIEdgeInsets(top: 0, left: 4, bottom: 0, right: 4)

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

        let peersMinimumWidth = peersTableView.widthAnchor.constraint(greaterThanOrEqualToConstant:
            PeerTableLayout.minimumContentWidth(widths: peerColumnWidths))
        self.peersMinimumWidth = peersMinimumWidth
        let preferredWidth = peersTableView.widthAnchor.constraint(equalTo: peersHorizontalScrollView.frameLayoutGuide.widthAnchor)
        preferredWidth.priority = .defaultHigh

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
            peersMinimumWidth,
            preferredWidth,
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
        trackersMinimumWidth = TorrentClientStyle.installScrollableTable(trackersTableView, in: borderContainer,
            minimumWidth: TrackerTableLayout.minimumContentWidth(widths: trackerColumnWidths))

        NSLayoutConstraint.activate([
            borderContainer.topAnchor.constraint(equalTo: trackersView.topAnchor),
            borderContainer.leadingAnchor.constraint(equalTo: trackersView.leadingAnchor),
            borderContainer.trailingAnchor.constraint(equalTo: trackersView.trailingAnchor),
            borderContainer.bottomAnchor.constraint(equalTo: trackersView.bottomAnchor),

        ])
    }

    private func refreshTrackers() {
        if selectedHex.isEmpty { webTrackerRows = [] }
        updateTrackerColumnLayout()
    }

    private func setPiecesValue(total: Int, size: UInt64) {
        piecesValue.mutedText = "×"
        piecesValue.text = "\(total) × \(TorrentFormat.fastPrettyBytes(size))"
    }

    private func updateTrackerColumnLayout() {
        trackerColumnWidths = TrackerTableLayout.widths(for: webTrackerRows)
        trackersMinimumWidth?.constant = TrackerTableLayout.minimumContentWidth(widths: trackerColumnWidths)
        trackersTableView?.reloadData()
    }

    // MARK: - Build Library UI

    private func buildLibraryUI() {
        TorrentClientStyle.configurePlainContentView(libraryView)

        librarySearchField.translatesAutoresizingMaskIntoConstraints = false
        librarySearchField.addTarget(self, action: #selector(librarySearchChanged), for: .editingChanged)
        libraryView.addSubview(librarySearchField)

        let rescanConfig = UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)
        libraryRescanButton.setImage(UIImage.hayaseIcon("folder-sync", withConfiguration: rescanConfig), for: .normal)
        TorrentClientStyle.configureIconButton(libraryRescanButton, variant: .secondary)
        libraryRescanButton.applySecondaryVariant()
        libraryRescanButton.accessibilityLabel = "Rescan torrents"
        libraryRescanButton.addTarget(self, action: #selector(rescanLibrary), for: .touchUpInside)
        libraryRescanButton.translatesAutoresizingMaskIntoConstraints = false

        TorrentClientStyle.configureIconButton(libraryDeleteButton, variant: .destructive)
        libraryDeleteButton.restingBackground = UIColor.HayaseTheme.destructive
        libraryDeleteButton.selectedBackground = UIColor.HayaseTheme.destructive.withAlphaComponent(0.9)
        libraryDeleteButton.restingTint = UIColor.HayaseTheme.destructiveForeground
        libraryDeleteButton.selectedTint = UIColor.HayaseTheme.destructiveForeground
        libraryDeleteButton.setLayeredIcon(.trash, size: 16)
        libraryDeleteButton.applyShadowSm()
        libraryDeleteButton.accessibilityLabel = "Delete torrents"
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
        libraryMinimumWidth = TorrentClientStyle.installScrollableTable(libraryTableView, in: borderContainer,
            minimumWidth: TorrentClientColumnWidths.minimumTableWidth(libraryColumnWidths,
                flexibleMinimums: [6: TorrentClientColumnWidths.libraryNameMinimum], hasSelectionColumn: true))

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

            borderContainer.topAnchor.constraint(equalTo: librarySelectionLabel.bottomAnchor, constant: 4),
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

        libraryActionInFlight = true
        updateLibrarySelectionLabel()
        let toast = AppErrorToast.startPromise(title: "Rescanning torrents...",
            description: "This may take a VERY long while depending on the number of torrents.")
        TorrentBackendManager.shared.rescanWebTorrents(hashes: hashes) { [weak self] result in
            DispatchQueue.main.async {
                if case .failure(let error) = result {
                    NSLog("[Torrent Library] %@", error.localizedDescription)
                    AppErrorToast.resolvePromise(toast, title: "Failed to rescan torrents\n" + error.localizedDescription, failed: true)
                } else { AppErrorToast.resolvePromise(toast, title: "Rescan complete") }
                guard let self else { return }
                self.libraryActionInFlight = false
                self.updateLibrarySelectionLabel()
                self.update()
            }
        }
    }

    private func refreshLibrary() {
        let query = librarySearchField.text?.lowercased() ?? ""
        webFilteredLibraryEntries = query.isEmpty
            ? webLibraryEntries
            : webLibraryEntries.filter { ($0.name.isEmpty ? $0.hash : $0.name).lowercased().contains(query) }
        if let column = librarySortColumn {
            webFilteredLibraryEntries.sort {
                TorrentLibrarySort.less($0, $1, column: column, ascending: librarySortAscending)
            }
        }
        let currentHashes = Set(webLibraryEntries.map { $0.hash })
        selectedLibraryHashes.formIntersection(currentHashes)
        updateLibrarySelectionLabel()
        libraryColumnWidths = TorrentClientColumnWidths.library(entries: webFilteredLibraryEntries)
        libraryMinimumWidth?.constant = TorrentClientColumnWidths.minimumTableWidth(libraryColumnWidths,
            flexibleMinimums: [6: TorrentClientColumnWidths.libraryNameMinimum], hasSelectionColumn: true)
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
        let rowCount = webFilteredLibraryEntries.count
        librarySelectionLabel.text = "\(selectedLibraryHashes.count) of \(rowCount) row(s) selected."
        let hasSelection = !selectedLibraryHashes.isEmpty && !libraryActionInFlight
        TorrentClientStyle.setIconButtonEnabled(libraryRescanButton, enabled: hasSelection, variant: .secondary)
        TorrentClientStyle.setIconButtonEnabled(libraryDeleteButton, enabled: hasSelection, variant: .destructive)
    }

    private var allVisibleLibraryRowsSelected: Bool {
        let hashes = Set(webFilteredLibraryEntries.map { $0.hash })
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

    private func openWebTorrentLibraryEntry(_ entry: WebTorrentLibraryEntry) {
        guard let sourceMediaID = entry.mediaID, sourceMediaID > 0, !entry.hash.isEmpty else { return }
        if restoreMiniPlayerIfAlreadyPlaying(hash: entry.hash, episode: entry.episode) { return }
        guard openingLibraryPlaybackHash != entry.hash else { return }
        guard let torrentEntity = torrentEntityForLibraryEntry(entry) else { return }

        cancelPendingLibraryPlayback()
        openingLibraryPlaybackHash = entry.hash
        selectedHex = entry.hash

        let episode = entry.episode ?? 0
        let mediaID = entry.mediaID ?? torrentEntity.animes?.animeAnilistId?.intValue ?? 0
        let videoService = VideoService(torrentEntity: torrentEntity, episode: episode)
        pendingLibraryPlaybackService = videoService

        MiniPlayerManager.shared.close()
        let player = VideoPlayerViewController()
        pendingLibraryPlayer = player
        player.beginMetadataLoading(owner: self)
        player.onCancelMetadataLoading = { [weak self] in self?.cancelPendingLibraryPlayback() }
        Router.shared.navigateToPlayer(player, hostTabIndex: hayaseTabIndex)

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
            let player = self.pendingLibraryPlayer
            self.openingLibraryPlaybackHash = nil
            self.cancelPendingLibraryPlayback()
            player?.finishMetadataLoading(error: NSError(domain: "TorrentLibraryPlayback", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Timed out while preparing this torrent."]))
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
        // Other playback services also emit this notification. Wait for this
        // request's fresh metadata instead of reopening cached video URLs.
        guard pendingLibraryPlaybackService === videoService,
              videoService.hasFinishedUpdatingLocalVideos else { return }
        let context = CoreDataService.sharedCoreDataService.mainQueueContext
        let fetch = NSFetchRequest<Videos>(entityName: Videos.entityName)
        fetch.predicate = NSPredicate(format: "torrents == %@", torrentEntity)
        fetch.sortDescriptors = [NSSortDescriptor(key: "videoIndex", ascending: true),
                                 NSSortDescriptor(key: "videoName", ascending: true)]
        let videos = (try? context.fetch(fetch)) ?? []

        if videos.isEmpty && videoService.lastError == nil { return }

        guard let player = pendingLibraryPlayer else { cancelPendingLibraryPlayback(); return }
        cancelPendingLibraryPlayback(clearService: false)

        guard videoService.lastError == nil, !videos.isEmpty else {
            let message = videoService.lastError?.localizedDescription ?? "No playable video files were found."
            openingLibraryPlaybackHash = nil
            pendingLibraryPlaybackService = nil
            player.finishMetadataLoading(error: videoService.lastError ?? NSError(domain: "TorrentLibraryPlayback", code: 2,
                userInfo: [NSLocalizedDescriptionKey: message]))
            return
        }

        guard let selectedVideo = bestVideoForLibraryPlayback(videos: videos, episode: episode) else {
            openingLibraryPlaybackHash = nil
            pendingLibraryPlaybackService = nil
            player.finishMetadataLoading(error: NSError(domain: "TorrentLibraryPlayback", code: 2,
                userInfo: [NSLocalizedDescriptionKey: "No playable video files were found."]))
            return
        }
        let selectedIndex = selectedVideo.videoIndex?.uintValue ?? 0
        let resolvedPath = videoService.UpdateFilePathForFileIndex(selectedIndex)
        if !resolvedPath.isEmpty, selectedVideo.videoPath != resolvedPath {
            selectedVideo.videoPath = resolvedPath
            try? context.save()
        }

        player.videoEntity = selectedVideo
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
        player.finishMetadataLoading()
    }

    private func handleEpisodeChangeFromTorrentClient(episode: Int,
                                                      media: AnimeItem?,
                                                      fallbackMediaID: Int) {
        if let media {
            presentEpisodeSearch(media: media, episode: episode)
            return
        }

        guard fallbackMediaID > 0 else { return }
        AniListClient.shared.singleMediaResult(id: fallbackMediaID) { [weak self] result in
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

        guard player.videoEntity?.torrents?.torrentHashString == hash else { return false }

        if let episode, episode > 0, player.episodeNumber > 0, player.episodeNumber != episode {
            return false
        }

        Router.shared.navigate(.player, hostTabIndex: hayaseTabIndex)
        return true
    }

    private func bestVideoForLibraryPlayback(videos: [Videos], episode: Int) -> Videos? {
        guard episode > 0 else { return videos.first }

        if let exact = videos.first(where: { TorrentBatchResolver.extractEpisodeNumber(from: $0.videoName ?? "") == episode }) {
            return exact
        }

        let parsed = videos.compactMap { video -> (video: Videos, episode: Int)? in
            guard let ep = TorrentBatchResolver.extractEpisodeNumber(from: video.videoName ?? "") else { return nil }
            return (video, ep)
        }.sorted { $0.episode < $1.episode }

        if let match = parsed.first(where: { $0.episode == episode })?.video { return match }
        if let first = parsed.first, let last = parsed.last, episode >= first.episode, episode <= last.episode {
            return parsed.min { abs($0.episode - episode) < abs($1.episode - episode) }?.video ?? videos.first
        }
        if episode <= videos.count {
            let sorted = videos.sorted { ($0.videoName ?? "").localizedStandardCompare($1.videoName ?? "") == .orderedAscending }
            return sorted[safe: episode - 1] ?? videos.first
        }
        return videos.first
    }

    private func cancelPendingLibraryPlayback(clearService: Bool = true) {
        if let observer = pendingLibraryPlaybackObserver {
            NotificationCenter.default.removeObserver(observer)
            pendingLibraryPlaybackObserver = nil
        }
        pendingLibraryPlaybackTimeout?.cancel()
        pendingLibraryPlaybackTimeout = nil
        openingLibraryPlaybackHash = nil
        pendingLibraryPlayer = nil
        if clearService { pendingLibraryPlaybackService = nil }
    }

    @objc private func deleteSelectedLibraryEntries() {
        guard !selectedLibraryHashes.isEmpty, !libraryActionInFlight else { return }

        let hashes = Array(selectedLibraryHashes)
        let names = webLibraryEntries.filter { hashes.contains($0.hash) }.map { $0.name.isEmpty ? $0.hash : $0.name }
        let dialog = TorrentLibraryDeleteDialog(names: names) { [weak self] in
            guard let self = self else { return }

            self.libraryActionInFlight = true
            self.updateLibrarySelectionLabel()
            let toast = AppErrorToast.startPromise(title: "Deleting torrents...",
                description: "This may take a while depending on the library size.")
            // torrent-client keeps what is being played, so the result is only known once the
            // library has been read again, as `server.updateLibrary()` does for interface.
            let manager = TorrentBackendManager.shared
            manager.deleteWebTorrents(hashes: hashes) { deleteResult in
                let reload = { (result: Result<[WebTorrentLibraryEntry], Error>) in
                    DispatchQueue.main.async { [weak self] in
                        let failure: Error?
                        switch result {
                        case .success(let entries):
                            self?.webLibraryEntries = entries
                            WebTorrentDownloaded.shared.replace(with: entries.map { $0.hash })
                            failure = nil
                        case .failure(let error):
                            failure = error
                        }
                        if let failure {
                            NSLog("[Torrent Library] %@", failure.localizedDescription)
                            AppErrorToast.resolvePromise(toast,
                                title: "Failed to delete torrents\n" + failure.localizedDescription, failed: true)
                        } else {
                            AppErrorToast.resolvePromise(toast, title: "Torrents deleted")
                        }
                        guard let self else { return }
                        self.libraryActionInFlight = false
                        if failure == nil { self.selectedLibraryHashes.removeAll() }
                        self.refreshLibrary()
                        self.update()
                    }
                }
                switch deleteResult {
                case .success:
                    manager.webTorrentLibrary(completion: reload)
                case .failure(let error):
                    reload(.failure(error))
                }
            }
        }
        present(dialog, animated: false)
    }

    // MARK: - UI helpers

    @objc private func libraryHeaderTapped(_ sender: UIButton) {
        if sender.tag == 7 {
            let hashes = Set(webFilteredLibraryEntries.map { $0.hash })
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
        iv.widthAnchor.constraint(equalToConstant: size).isActive = true
        iv.heightAnchor.constraint(equalToConstant: size).isActive = true
        return iv
    }

    private func makeFlatSection(title: String, icon: String, items: [StatItem]) -> UIView {
        let container = UIStackView()
        container.axis = .vertical
        container.spacing = 0

        let iconView = makeIcon(icon, tint: TorrentClientStyle.foreground, size: 20)
        let titleLabel = TorrentClientLabel()
        titleLabel.lineHeight = 24
        titleLabel.text = title
        titleLabel.font = .nunito(ofSize: 24, weight: .bold)
        titleLabel.textColor = TorrentClientStyle.foreground

        let titleRow = UIStackView(arrangedSubviews: [iconView, titleLabel])
        titleRow.axis = .horizontal
        titleRow.spacing = 14
        titleRow.alignment = .center

        let paddedTitle = UIStackView(arrangedSubviews: [titleRow])
        paddedTitle.axis = .vertical
        paddedTitle.layoutMargins = UIEdgeInsets(top: 24, left: 0, bottom: 24, right: 0)
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
        let titleLabel = TorrentClientLabel()
        titleLabel.text = item.title
        titleLabel.font = .nunito(ofSize: 14, weight: .medium)
        titleLabel.textColor = TorrentClientStyle.mutedForeground

        let topRow = UIStackView(arrangedSubviews: [iconView, titleLabel])
        topRow.axis = .horizontal
        topRow.spacing = 8
        topRow.alignment = .center

        item.label.font = .nunito(ofSize: 24, weight: .bold)
        (item.label as? TorrentClientLabel)?.lineHeight = 32

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

        let titleLabel = TorrentClientLabel()
        titleLabel.text = item.title
        titleLabel.font = .nunito(ofSize: 14, weight: .regular)
        titleLabel.textColor = TorrentClientStyle.mutedForeground

        item.label.font = .nunito(ofSize: 14, weight: .medium)

        let text = UIStackView(arrangedSubviews: [titleLabel, item.label])
        text.axis = .vertical
        let iconMargin = UIView()
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconMargin.addSubview(iconView)
        NSLayoutConstraint.activate([
            iconMargin.widthAnchor.constraint(equalToConstant: 24),
            iconMargin.heightAnchor.constraint(equalToConstant: 16),
            iconView.centerXAnchor.constraint(equalTo: iconMargin.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconMargin.centerYAnchor),
        ])
        let stack = UIStackView(arrangedSubviews: [iconMargin, text])
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
            return max(webFilteredFileInfos.count, 1)
        } else if tableView === peersTableView {
            return max(currentPeerRows().count, 1)
        } else if tableView === trackersTableView {
            return max(webTrackerRows.count, 1)
        } else if tableView === libraryTableView {
            return max(webFilteredLibraryEntries.count, 1)
        }
        return 0
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if tableView === filesTableView {
            if webFilteredFileInfos.isEmpty {
                return emptyTableCell(text: "No files downloaded yet.")
            }
            guard let cell = tableView.dequeueReusableCell(
                withIdentifier: FileEntryTableCell.reuseID, for: indexPath) as? FileEntryTableCell else { return UITableViewCell() }
            guard indexPath.row < webFilteredFileInfos.count else { return cell }
            cell.columnWidths = filesColumnWidths
            cell.configure(entry: webFilteredFileInfos[indexPath.row])
            return cell
        } else if tableView === peersTableView {
            let rows = currentPeerRows()
            if rows.isEmpty {
                return emptyTableCell(text: "No peers connected yet.")
            }
            guard let cell = tableView.dequeueReusableCell(
                withIdentifier: PeerInfoCell.reuseID, for: indexPath) as? PeerInfoCell else { return UITableViewCell() }
            guard indexPath.row < rows.count else { return cell }
            cell.configure(row: rows[indexPath.row], columnWidths: peerColumnWidths)
            return cell
        } else if tableView === trackersTableView {
            if webTrackerRows.isEmpty {
                return emptyTableCell(text: "Loading...")
            }
            guard let cell = tableView.dequeueReusableCell(
                withIdentifier: TrackerStatusCell.reuseID, for: indexPath) as? TrackerStatusCell else { return UITableViewCell() }
            guard indexPath.row < webTrackerRows.count else { return cell }
            let row = webTrackerRows[indexPath.row]
            cell.configure(announce: row.announce, info: row.info, columnWidths: trackerColumnWidths)
            return cell
        } else if tableView === libraryTableView {
            if webFilteredLibraryEntries.isEmpty {
                return emptyTableCell(text: "No torrents downloaded yet.")
            }
            guard let cell = tableView.dequeueReusableCell(
                withIdentifier: LibraryColumnCell.reuseID, for: indexPath) as? LibraryColumnCell else { return UITableViewCell() }
            guard indexPath.row < webFilteredLibraryEntries.count else { return cell }
            let entry = webFilteredLibraryEntries[indexPath.row]
            cell.columnWidths = libraryColumnWidths
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
        return UITableViewCell()
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if tableView === libraryTableView {
            guard indexPath.row < webFilteredLibraryEntries.count else { return }
            let entry = webFilteredLibraryEntries[indexPath.row]
            openWebTorrentLibraryEntry(entry)
        }
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        if tableView === filesTableView {
            return makeFileColumnHeader()
        } else if tableView === peersTableView {
            return makeColumnHeader(columns: PeerTableLayout.columns(widths: peerColumnWidths),
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
            return makeColumnHeader(columns: TrackerTableLayout.columns(widths: trackerColumnWidths))
        } else if tableView === libraryTableView {
            return makeColumnHeader(columns: [
                ("Series", libraryColumnWidths[0]),
                ("Episode", libraryColumnWidths[1]),
                ("Files", libraryColumnWidths[2]),
                ("Size", libraryColumnWidths[3]),
                ("Status", libraryColumnWidths[4]),
                ("Date", libraryColumnWidths[5]),
                ("Torrent Name", libraryColumnWidths[6]),
                ("", libraryColumnWidths[7]),
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
            return webFilteredFileInfos.isEmpty ? 160 : UITableView.automaticDimension
        } else if tableView === peersTableView {
            return currentPeerRows().isEmpty ? 160 : 56
        } else if tableView === trackersTableView {
            return webTrackerRows.isEmpty ? 160 : 56
        } else if tableView === libraryTableView {
            if webFilteredLibraryEntries.isEmpty { return 160 }
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
        makeColumnHeader(columns: [("File Name", filesColumnWidths[0]), ("Size", filesColumnWidths[1]),
                                  ("Progress", filesColumnWidths[2]), ("Streams", filesColumnWidths[3])],
                         sortableColumnIndices: Set(0...3), activeColumnIndex: filesSortColumn?.rawValue,
                         sortAscending: filesSortAscending, target: self, action: #selector(fileColumnHeaderTapped(_:)),
                         onSort: { [weak self] index, ascending in
                             self?.filesSortColumn = FileSortColumn(rawValue: index)
                             self?.filesSortAscending = ascending
                             self?.refreshFiles()
                         })
    }

    /// Handles tap on a Files column header button.
    /// Matches Hayase's column sort dropdown with Asc/Desc options.
    @objc private func fileColumnHeaderTapped(_ sender: UIButton) {
        guard let col = FileSortColumn(rawValue: sender.tag) else { return }
        if filesSortColumn == col {
            filesSortAscending.toggle()
        } else {
            filesSortColumn = col
            filesSortAscending = true
        }
        refreshFiles()
    }
}
