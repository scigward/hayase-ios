//
//  ClientLayout.swift
//  Hayase
//
//  Mirrors: src/routes/app/client/+layout.svelte, src/routes/app/client/+page.ts, src/routes/app/client/+page.svelte, src/lib/components/SettingsNav.svelte
//
//  The pages of the client are in the files of the interface's `ui/torrentclient`, as extensions of
//  `DownloadsViewController`: `Overview`, `Files/FilesTable`, `Peers/PeersTable`, `Trackers/TrackersTable` and
//  `Library/LibraryTable`.
//

import UIKit
import CoreData

// MARK: - DownloadsViewController

/// Hayase-style torrent client page with tabbed interface:
/// Overview, Files, Peers, Trackers, Library, Settings.
/// Auto-selects the first active torrent and updates every second.
class DownloadsViewController: UIViewController {

    // MARK: - Properties

    var updateTimer: Timer?

    /// The torrent being played
    var selectedHex: String = ""

    var selectedTabIndex: Int = 0
    var clientRoute: Route.ClientRoute = .root
    static let settingsTabIndex = 5

    // MARK: - Page header

    let pageTitleLabel: UILabel = {
        let l = TorrentClientLabel()
        l.lineHeight = 32
        l.font = .nunito(ofSize: 24, weight: .bold)
        l.textColor = TorrentClientStyle.foreground
        l.text = "Torrent Client"
        return l
    }()

    let pageSubtitleLabel: UILabel = {
        let l = TorrentClientLabel()
        l.lineHeight = 24
        l.font = .nunito(ofSize: 16, weight: .regular)
        l.textColor = TorrentClientStyle.mutedForeground
        l.text = "Monitor your torrents, and configure settings for your torrent client."
        l.numberOfLines = 0
        l.lineBreakMode = .byWordWrapping
        return l
    }()

    var pageTitleTopConstraint: NSLayoutConstraint?
    var pageTitleLeadingConstraint: NSLayoutConstraint?
    var pageTitleTrailingConstraint: NSLayoutConstraint?
    var pageSubtitleTrailingConstraint: NSLayoutConstraint?
    var headerSeparatorTopConstraint: NSLayoutConstraint?
    var headerSeparatorLeadingConstraint: NSLayoutConstraint?
    var headerSeparatorTrailingConstraint: NSLayoutConstraint?

    // MARK: - Tab bar & containers

    var tabButtons: [HayaseNavTabButton] = []
    var tabButtonHeightConstraints: [NSLayoutConstraint] = []
    let tabBarContainer = UIView()
    let tabScrollView = UIScrollView()
    let tabStackView = UIStackView()
    let bodyStackView = UIStackView()
    let headerSeparator = UIView()
    let globeView = Globe()
    let webTorrentVersionLabel: UILabel = {
        let label = TorrentClientLabel()
        label.lineHeight = 16
        label.text = "WebTorrent v3.0.16"
        label.font = .nunito(ofSize: 12, weight: .light)
        label.textColor = TorrentClientStyle.mutedForeground
        label.numberOfLines = 1
        return label
    }()
    var tabBarWidthConstraint: NSLayoutConstraint?
    var tabBarHeightConstraint: NSLayoutConstraint?
    var tabStackWidthConstraint: NSLayoutConstraint?
    var tabStackHeightConstraint: NSLayoutConstraint?
    var tabScrollBottomToContainerConstraint: NSLayoutConstraint?
    var tabScrollBottomToFooterConstraint: NSLayoutConstraint?
    var versionBottomConstraint: NSLayoutConstraint?
    var versionTopConstraint: NSLayoutConstraint?
    var globeWidthConstraint: NSLayoutConstraint?
    var bodyTopConstraint: NSLayoutConstraint?
    var bodyLeadingConstraint: NSLayoutConstraint?
    var bodyTrailingConstraint: NSLayoutConstraint?
    var lastWideClientLayout: Bool?

    let containerView = UIView()

    var tabContentViews: [UIView] {
        [overviewScrollView, filesView, peersView, trackersView, libraryView]
    }

    // MARK: - Overview UI elements

    lazy var overviewScrollView: UIScrollView = {
        let sv = UIScrollView()
        sv.showsVerticalScrollIndicator = true
        return sv
    }()

    let nameLabel: UILabel = {
        let l = TorrentClientLabel()
        l.lineHeight = 32
        l.font = .nunito(ofSize: 24, weight: .bold)
        l.textColor = TorrentClientStyle.foreground
        l.numberOfLines = 1
        l.lineBreakMode = .byTruncatingTail
        return l
    }()

    let statusBadge: TorrentPillBadge = {
        let l = TorrentPillBadge(horizontalPadding: 10, verticalPadding: 2)
        l.font = .nunito(ofSize: 12, weight: .bold)
        l.textColor = TorrentClientStyle.primaryForeground
        l.textAlignment = .center
        return l
    }()

    let hashLabel: UILabel = {
        let l = TorrentClientLabel()
        l.font = .nunito(ofSize: 14)
        l.textColor = TorrentClientStyle.mutedForeground
        l.numberOfLines = 1
        l.lineBreakMode = .byTruncatingMiddle
        return l
    }()

    let bigPercentLabel: UILabel = {
        let l = TorrentClientLabel()
        l.lineHeight = 32
        l.font = .nunito(ofSize: 24, weight: .bold)
        l.textColor = TorrentClientStyle.foreground
        return l
    }()

    let progressBar = TorrentClientProgressBar(height: 12)

    // Progress stat values
    let downloadedValue  = TorrentClientLabel()
    let uploadedValue    = TorrentClientLabel()
    let totalSizeValue   = TorrentClientLabel()
    let piecesValue      = TorrentClientLabel()

    // Speed & Transfer / Time / Peers values
    let downSpeedValue   = TorrentClientLabel()
    let upSpeedValue     = TorrentClientLabel()
    let etaValue         = TorrentClientLabel()
    let elapsedValue     = TorrentClientLabel()
    let seedersValue     = TorrentClientLabel()
    let leechersValue    = TorrentClientLabel()
    let wiresValue       = TorrentClientLabel()

    // Protocol status dots
    let dhtDot       = TorrentFormat.makeDotLabel()
    let lsdDot       = TorrentFormat.makeDotLabel()
    let pexDot       = TorrentFormat.makeDotLabel()
    let natDot       = TorrentFormat.makeDotLabel()
    let forwardDot   = TorrentFormat.makeDotLabel()
    let persistDot   = TorrentFormat.makeDotLabel()
    let streamingDot = TorrentFormat.makeDotLabel()
    weak var overviewStatsStack: UIStackView?
    weak var protocolColumnsStack: TorrentResponsiveGrid?
    weak var progressStatsGrid: TorrentResponsiveGrid?
    var viewportWidth: CGFloat {
        view.window?.rootViewController?.view.bounds.width ?? view.bounds.width
    }

    // MARK: - Files tab

    let filesView = UIView()
    var filesTableView: UITableView!
    let filesSearchField = TorrentClientStyle.makeSearchField(placeholder: "Search by File Name...")
    var filesColumnWidths: [CGFloat?] = TorrentClientColumnWidths.files(entries: [])
    var filesMinimumWidth: NSLayoutConstraint?

    /// Column sort state for the Files tab (mirrors Hayase addSortBy plugin with toggleOrder: ['asc','desc']).
    /// Source dropdown offers only ascending and descending order.
    enum FileSortColumn: Int { case name = 0, size = 1, progress = 2, streams = 3 }
    var filesSortColumn: FileSortColumn?
    var filesSortAscending: Bool = true

    static let filesRowHeight: CGFloat = 56

    // MARK: - Peers tab

    let peersView = UIView()
    var peersHorizontalScrollView: UIScrollView!
    var peersTableView: UITableView!
    enum PeerSortColumn: Int {
        case ip = 0
        case client = 1
        case progress = 2
        case download = 3
        case upload = 4
        case downloaded = 5
        case uploaded = 6
        case country = 7
    }
    var peersSortColumn: PeerSortColumn?
    var peersSortAscending = true
    var peerColumnWidths = PeerTableLayout.widths(for: [])
    var peersMinimumWidth: NSLayoutConstraint?

    // MARK: - Trackers tab

    let trackersView = UIView()
    var trackersTableView: UITableView!
    var trackerColumnWidths = TrackerTableLayout.widths(for: [])
    var trackersMinimumWidth: NSLayoutConstraint?
    var webTrackerRows: [(announce: String, info: WebTorrentTrackerInfo)] = []

    // MARK: - Library tab

    let libraryView = UIView()
    var libraryTableView: UITableView!
    let librarySearchField = TorrentClientStyle.makeSearchField(placeholder: "Search by Torrent Name...")
    var libraryColumnWidths: [CGFloat?] = TorrentClientColumnWidths.library(entries: [])
    var libraryMinimumWidth: NSLayoutConstraint?

    var webStatus: WebTorrentBridgeStatus?
    var webInfo: WebTorrentTorrentInfo?
    var webProtocol: WebTorrentProtocolStatus?
    var webFileInfos: [WebTorrentFileInfo] = []
    var webFilteredFileInfos: [WebTorrentFileInfo] = []
    var webFileInfoHash: String?
    var webPeerInfos: [WebTorrentPeerInfo] = []
    var webLibraryEntries: [WebTorrentLibraryEntry] = []
    var webFilteredLibraryEntries: [WebTorrentLibraryEntry] = []
    var webActiveInFlight = false
    var webStoresInFlight = Set<WebStore>()
    var webStoresFetchedAt: [WebStore: Date] = [:]
    var webSnapshotGeneration = 0
    var webLastError: Error?
    var animeTitleCache: [Int: String] = [:]
    var pendingAnimeTitles: Set<Int> = []
    /// The media whose title could not be asked for (`mediatitle.svelte` shows "?" for an `$query.error`): they are asked
    /// for again when the tab is shown, as the cell asks again when it is made again
    var failedAnimeTitles: Set<Int> = []

    var selectedLibraryHashes: Set<String> = []
    var librarySortColumn: Int?
    var librarySortAscending = true
    var libraryActionInFlight = false
    var pendingLibraryPlaybackService: VideoService?
    var pendingLibraryPlaybackObserver: NSObjectProtocol?
    var pendingLibraryPlaybackTimeout: DispatchWorkItem?
    var openingLibraryPlaybackHash: String?
    weak var pendingLibraryPlayer: VideoPlayerViewController?
    static let libraryPlaybackTimeout: TimeInterval = 120

    let librarySelectionLabel: UILabel = {
        let l = TorrentClientLabel()
        l.font = .nunito(ofSize: 14)
        l.textColor = TorrentClientStyle.mutedForeground
        l.text = "0 of 0 row(s) selected."
        l.textAlignment = .right
        return l
    }()
    let libraryRescanButton = SelectButton()
    let libraryDeleteButton = SelectButton()

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

    func startTimer() {
        stopTimer()
        webStoresFetchedAt.removeAll()
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.update()
        }
        RunLoop.main.add(timer, forMode: .common)
        updateTimer = timer
    }

    func stopTimer() {
        updateTimer?.invalidate()
        updateTimer = nil
    }

    // MARK: - Torrent selection

    /// `server.active`: the overview follows what is playing, never a library entry.
    func autoSelectFirstTorrent() {
        selectedHex = webStatus?.infoHash ?? ""
    }

    // MARK: - Page header setup

    func setupPageHeader() {
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

    func setupContainerView() {
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

    func installTabPages() {
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

    func setupTabNavigation() {
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

    func makeTabButton(title: String, tag: Int) -> HayaseNavTabButton {
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

    func updateResponsiveClientLayoutIfNeeded() {
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

    func updateTabButtonAppearance(_ btn: UIButton) {
        let medium = viewportWidth >= 768  // bg-muted md:bg-transparent
        btn.backgroundColor = medium ? .clear : TorrentClientStyle.muted
    }

    func updateTabButtonAppearances() {
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

    func clientRoute(for tabIndex: Int) -> Route.ClientRoute? {
        switch tabIndex {
        case 0: return .overview
        case 1: return .files
        case 2: return .peers
        case 3: return .trackers
        case 4: return .library
        default: return nil
        }
    }

    func tabIndex(for route: Route.ClientRoute) -> Int? {
        switch route {
        case .root: return nil
        case .overview: return 0
        case .files: return 1
        case .peers: return 2
        case .trackers: return 3
        case .library: return 4
        }
    }

    @objc func tabButtonTapped(_ sender: UIButton) {
        let index = sender.tag
        if index == Self.settingsTabIndex {
            Router.shared.navigate(.settings(.client), hostTabIndex: hayaseTabIndex, noScroll: true)
        } else if let route = clientRoute(for: index) {
            Router.shared.navigate(.client(route), hostTabIndex: hayaseTabIndex, noScroll: true)
        }
    }

    func updatePageHeader(for index: Int) {
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

    func showTab(_ index: Int) {
        updatePageHeader(for: index)
        // A store starts fresh when something subscribes to it.
        webStoresFetchedAt.removeAll()
        failedAnimeTitles.removeAll()
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

    // MARK: - Data update

    func update() {
        updateWebTorrent()
    }

    // MARK: - WebTorrent stores

    /// Each of interface's `server` stores (client.ts `_timedSafeStore`) polls only while something
    /// on screen reads it, on its own schedule and apart from the others, so a slow endpoint
    /// holds back none of the rest.
    enum WebStore {
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

    func updateWebTorrent() {
        refreshWebActive()
        for store in WebStore.shown(onTab: selectedTabIndex) {
            // The timer's own jitter must not cost a store its turn.
            let due = Date().timeIntervalSince(webStoresFetchedAt[store] ?? .distantPast) >= store.interval - 0.1
            if due && !webStoresInFlight.contains(store) { fetchWebStore(store) }
        }
    }

    /// The torrent being played, which interface holds in `server.active` and the bridge reports.
    func refreshWebActive() {
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
    func resetWebTorrentSnapshots() {
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

    func fetchWebStore(_ store: WebStore) {
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

    func renderWebStore(_ store: WebStore) {
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

}

// MARK: - UITableViewDataSource & UITableViewDelegate

extension DownloadsViewController: UITableViewDataSource, UITableViewDelegate {

    func emptyTableCell(text: String) -> UITableViewCell {
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

    func makeColumnHeader(columns: [(String, CGFloat?)],
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

}
