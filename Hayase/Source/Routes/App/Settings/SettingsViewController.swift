//
//  SettingsViewController.swift
//  Hayase
//
//  Mirrors: src/routes/app/settings/+layout.svelte, src/routes/app/settings/+page.ts,
//  src/routes/app/settings/+page.svelte, src/lib/components/SettingsNav.svelte,
//  src/lib/components/SettingCard.svelte
//
//  Native port of the responsive settings shell and SettingCard pages.
//  Existing iOS-backed behavior is preserved and the web settings controls are
//  connected to their native storage and services.

import UIKit
import SafariServices
import UniformTypeIdentifiers

// MARK: - SettingsViewController

enum SettingsPreviewKind: Equatable {
    case subtitleStyle
    case colorTheme
}

class SettingsViewController: UIViewController {

    // MARK: - Lifecycle

    init() {
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        tabBarItem = UITabBarItem(
            title: "Settings",
            image: UIImage.hayaseIcon("settings"),
            selectedImage: UIImage.hayaseIcon("settings"))
    }

    // MARK: - Colors

    private let bgColor = UIColor.HayaseTheme.background
    private let mutedFg = UIColor.HayaseTheme.mutedForeground
    private let separatorColor = UIColor.HayaseTheme.border

    // MARK: - State

    private var selectedTab: SettingsTab = .player
    private var settingsRoute: Route.SettingsRoute = .root
    private var tabButtons: [HayaseNavTabButton] = []
    private var tabButtonHeightConstraints: [NSLayoutConstraint] = []
    private weak var headerTabStack: UIStackView?
    private var tableView: UITableView!
    private let headingStack = UIStackView()
    private let localRouteTransition = HayaseRouteTransition()
    private let pageSeparator = UIView()
    private let bodyContainer = UIView()
    private let bodyContent = UIView()
    private var asideView: UIView!
    private var asideWidthConstraint: NSLayoutConstraint?
    private var bodyLayoutConstraints: [NSLayoutConstraint] = []
    private var horizontalPageConstraints: [NSLayoutConstraint] = []
    private var headingTopConstraint: NSLayoutConstraint?
    private var separatorTopConstraint: NSLayoutConstraint?
    private var bodyTopConstraint: NSLayoutConstraint?
    private var currentWideLayout: Bool?
    private var currentShowsInlineAside: Bool?
    private var currentMediumLayout: Bool?
    private var isUpdatingHeader = false
    private var changelogEntries: [HayaseChangelogEntry]?
    private var changelogError: String?
    private var pendingScale: Double?
    private var previousScale: Double?
    private var scaleCountdown = 10
    private var scaleTimer: Timer?
    private weak var scaleAlert: UIAlertController?

    /// Cached snapshot of sections for the currently selected tab.
    /// Stored (not computed) so that UIKit's data-source calls always see
    /// a stable row/section count between reloadData() calls.
    private lazy var visibleSections: [Section] = settingsRoute == .root
        ? []
        : allSections.filter { $0.tab == selectedTab }

    /// Re-caches `visibleSections` from `selectedTab`.
    /// Call this right before every `reloadData()` / `reloadRows(…)`.
    private func refreshVisibleSections() {
        visibleSections = allSections.filter { $0.tab == selectedTab }
    }

    private let allSections = SettingsSectionCatalog.sections

    // MARK: - viewDidLoad

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Settings"
        view.backgroundColor = bgColor
        navigationController?.setNavigationBarHidden(true, animated: false)

        tableView = UITableView(frame: .zero, style: .plain)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = bgColor
        tableView.separatorStyle = .none
        // Default (true) delays delivering touches to content views by
        // ~150ms while UIScrollView decides if this is a scroll — a common,
        // well-known contributor to buttons inside a scrolling container
        // feeling unresponsive or requiring an unnaturally precise tap.
        tableView.delaysContentTouches = false
        tableView.delegate   = self
        tableView.dataSource = self
        tableView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: 24, right: 0)
        tableView.register(HayaseSettingToggleCell.self,
                           forCellReuseIdentifier: HayaseSettingToggleCell.reuseID)
        tableView.register(HayaseSettingValueCell.self,
                           forCellReuseIdentifier: HayaseSettingValueCell.reuseID)
        tableView.register(HayaseAccountCardCell.self,
                           forCellReuseIdentifier: HayaseAccountCardCell.reuseID)
        tableView.register(HayaseSettingsPreviewGridCell.self,
                           forCellReuseIdentifier: HayaseSettingsPreviewGridCell.reuseID)
        tableView.register(HayaseChangelogPlaceholderCell.self,
                           forCellReuseIdentifier: HayaseChangelogPlaceholderCell.reuseID)
        tableView.register(HayaseAppActionsCell.self,
                           forCellReuseIdentifier: HayaseAppActionsCell.reuseID)
        tableView.register(HayaseSettingSliderCell.self,
                           forCellReuseIdentifier: HayaseSettingSliderCell.reuseID)
        tableView.sectionHeaderTopPadding = 0

        setupPageLayout()
        if settingsRoute == .changelog { loadChangelogIfNeeded() }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateResponsiveSettingsNavigation()
        sizeInlineAsideIfNeeded()
    }

    deinit {
        scaleTimer?.invalidate()
        if let previousScale {
            Settings.uiScale = previousScale
            HayaseInterfaceScale.apply(previousScale)
        }
    }

    private func confirmScaleChange() {
        guard let pendingScale, abs(pendingScale - Settings.uiScale) > 0.001 else { return }
        if previousScale == nil { previousScale = Settings.uiScale }
        Settings.uiScale = pendingScale
        HayaseInterfaceScale.apply(pendingScale)

        scaleTimer?.invalidate()
        scaleAlert?.dismiss(animated: false)
        scaleCountdown = 10
        let alert = UIAlertController(title: "Keep this UI scale?",
                                      message: scaleConfirmationMessage, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Revert", style: .destructive) { [weak self] _ in
            self?.revertScaleChange()
        })
        alert.addAction(UIAlertAction(title: "Keep Changes", style: .default) { [weak self] _ in
            self?.keepScaleChange()
        })
        scaleAlert = alert
        present(alert, animated: true)
        scaleTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.scaleCountdown -= 1
            if self.scaleCountdown <= 0 {
                self.revertScaleChange()
            } else {
                self.scaleAlert?.message = self.scaleConfirmationMessage
            }
        }
    }

    private var scaleConfirmationMessage: String {
        "The interface zoom has been changed. Reverting to the previous scale in \(scaleCountdown) seconds."
    }

    private func keepScaleChange() {
        scaleTimer?.invalidate()
        scaleTimer = nil
        previousScale = nil
        pendingScale = nil
        scaleAlert = nil
    }

    private func revertScaleChange() {
        scaleTimer?.invalidate()
        scaleTimer = nil
        if let previousScale {
            Settings.uiScale = previousScale
            HayaseInterfaceScale.apply(previousScale)
        }
        previousScale = nil
        pendingScale = nil
        scaleAlert?.dismiss(animated: true)
        scaleAlert = nil
        if isViewLoaded { tableView.reloadData() }
    }

    // MARK: - Page layout

    private func setupPageLayout() {
        let pageTitle = UILabel()
        pageTitle.text = "Settings"
        pageTitle.font = .nunito(ofSize: 24, weight: .bold)
        pageTitle.textColor = UIColor.HayaseTheme.foreground

        let subtitle = UILabel()
        subtitle.text = "Manage your app settings, preferences and accounts."
        subtitle.font = .nunito(ofSize: 16)
        subtitle.textColor = mutedFg
        subtitle.numberOfLines = 0

        headingStack.axis = .vertical
        headingStack.alignment = .fill
        headingStack.distribution = .fill
        headingStack.spacing = 2
        pageTitle.setContentHuggingPriority(.required, for: .vertical)
        subtitle.setContentHuggingPriority(.required, for: .vertical)
        headingStack.setContentHuggingPriority(.required, for: .vertical)
        headingStack.setContentCompressionResistancePriority(.required, for: .vertical)
        headingStack.addArrangedSubview(pageTitle)
        headingStack.addArrangedSubview(subtitle)
        headingStack.translatesAutoresizingMaskIntoConstraints = false

        pageSeparator.backgroundColor = separatorColor
        pageSeparator.translatesAutoresizingMaskIntoConstraints = false
        bodyContainer.translatesAutoresizingMaskIntoConstraints = false
        bodyContent.translatesAutoresizingMaskIntoConstraints = false
        asideView = buildAsideView()

        view.addSubview(headingStack)
        view.addSubview(pageSeparator)
        view.addSubview(bodyContainer)
        bodyContainer.addSubview(bodyContent)
        bodyContent.addSubview(tableView)

        let headingWidth = headingStack.widthAnchor.constraint(equalTo: view.widthAnchor, constant: -24)
        let separatorWidth = pageSeparator.widthAnchor.constraint(equalTo: view.widthAnchor, constant: -24)
        let bodyWidth = bodyContent.widthAnchor.constraint(equalTo: bodyContainer.widthAnchor, constant: -24)
        [headingWidth, separatorWidth, bodyWidth].forEach { $0.priority = .defaultHigh }
        horizontalPageConstraints = [
            headingStack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            headingStack.widthAnchor.constraint(lessThanOrEqualToConstant: 1440),
            headingStack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 12),
            headingStack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -12),
            pageSeparator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            pageSeparator.widthAnchor.constraint(lessThanOrEqualToConstant: 1440),
            pageSeparator.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 12),
            pageSeparator.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -12),
            bodyContent.centerXAnchor.constraint(equalTo: bodyContainer.centerXAnchor),
            bodyContent.widthAnchor.constraint(lessThanOrEqualToConstant: 1440),
            bodyContent.leadingAnchor.constraint(greaterThanOrEqualTo: bodyContainer.leadingAnchor, constant: 12),
            bodyContent.trailingAnchor.constraint(lessThanOrEqualTo: bodyContainer.trailingAnchor, constant: -12),
            headingWidth,
            separatorWidth,
            bodyWidth,
        ]

        // #root has safe-area top padding; +layout.svelte adds 12/40pt inside it.
        let headingTop = headingStack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12)
        let separatorTop = pageSeparator.topAnchor.constraint(equalTo: headingStack.bottomAnchor, constant: 12)
        let bodyTop = bodyContainer.topAnchor.constraint(equalTo: pageSeparator.bottomAnchor, constant: 12)
        bodyContainer.setContentHuggingPriority(.defaultLow, for: .vertical)
        headingTopConstraint = headingTop
        separatorTopConstraint = separatorTop
        bodyTopConstraint = bodyTop
        NSLayoutConstraint.activate(horizontalPageConstraints + [
            headingTop,
            separatorTop,
            pageSeparator.heightAnchor.constraint(equalToConstant: 1),
            bodyTop,
            bodyContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bodyContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bodyContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            bodyContent.topAnchor.constraint(equalTo: bodyContainer.topAnchor),
            bodyContent.bottomAnchor.constraint(equalTo: bodyContainer.bottomAnchor),
        ])

        updatePagePadding()
        updateBodyLayout(force: true)
    }

    private func updatePagePadding() {
        let medium = view.bounds.width >= 768
        let padding: CGFloat = medium ? 40 : 12
        horizontalPageConstraints[2].constant = padding
        horizontalPageConstraints[3].constant = -padding
        horizontalPageConstraints[6].constant = padding
        horizontalPageConstraints[7].constant = -padding
        horizontalPageConstraints[10].constant = padding
        horizontalPageConstraints[11].constant = -padding
        horizontalPageConstraints[12].constant = -2 * padding
        horizontalPageConstraints[13].constant = -2 * padding
        horizontalPageConstraints[14].constant = -2 * padding

        headingTopConstraint?.constant = padding
        separatorTopConstraint?.constant = medium ? 24 : 12
        bodyTopConstraint?.constant = medium ? 24 : 12
        tableView.contentInset.bottom = medium ? 0 : 40
    }

    /// Builds the support card, SettingsNav, and build information from +layout.svelte.
    private func buildAsideView() -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        let supportCard = makeSupportCard()
        let tabGrid = buildTabGrid()
        let versionLabel = UILabel()
        versionLabel.text = "Interface v\(appVersion())\nNative \(appVersion())\niOS \(UIDevice.current.systemVersion) \(UIDevice.current.model)\nLicense Information"
        versionLabel.font = .nunito(ofSize: 12, weight: .light)
        versionLabel.textColor = mutedFg
        versionLabel.numberOfLines = 0

        let topStack = UIStackView(arrangedSubviews: [supportCard, tabGrid])
        topStack.axis = .vertical
        topStack.spacing = 0
        topStack.setCustomSpacing(16, after: supportCard)
        topStack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(topStack)
        container.addSubview(versionLabel)

        NSLayoutConstraint.activate([
            topStack.topAnchor.constraint(equalTo: container.topAnchor),
            topStack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            topStack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            versionLabel.topAnchor.constraint(greaterThanOrEqualTo: topStack.bottomAnchor, constant: 12),
            versionLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            versionLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            versionLabel.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -20),
        ])
        let widthConstraint = container.widthAnchor.constraint(equalToConstant: 240)
        widthConstraint.isActive = true
        asideWidthConstraint = widthConstraint
        return container
    }

    private func makeSupportCard() -> UIView {
        let card = UIView()
        card.backgroundColor = UIColor(red: 232 / 255, green: 121 / 255, blue: 249 / 255, alpha: 1)
        card.layer.cornerRadius = 4
        card.clipsToBounds = true
        // Web uses background-image/cover; a constrained UIImageView would
        // contribute the 1573x433 artwork's intrinsic height to Auto Layout.
        card.layer.contents = HayaseSettingsArtwork.flowers?.cgImage
        card.layer.contentsGravity = .resizeAspectFill

        let title = UILabel()
        title.text = "Support the Project"
        title.font = .nunito(ofSize: 16, weight: .bold)
        title.textColor = UIColor.HayaseTheme.secondary

        let message = UILabel()
        message.text = "Please consider supporting the development of Hayase by donating!"
        message.font = .nunito(ofSize: 12)
        message.textColor = UIColor.HayaseTheme.secondary
        message.numberOfLines = 0

        let donate = UIButton(type: .system)
        donate.setTitle("Donate", for: .normal)
        donate.setImage(UIImage.hayaseIcon("heart"), for: .normal)
        donate.tintColor = UIColor(red: 250 / 255, green: 104 / 255, blue: 182 / 255, alpha: 1)
        donate.setTitleColor(UIColor.HayaseTheme.primaryForeground, for: .normal)
        donate.backgroundColor = UIColor.HayaseTheme.primary
        donate.titleLabel?.font = .nunito(ofSize: 14, weight: .bold)
        donate.layer.cornerRadius = 6
        donate.contentEdgeInsets = UIEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        donate.imageEdgeInsets.right = 8
        donate.heightAnchor.constraint(equalToConstant: 36).isActive = true
        donate.addTarget(self, action: #selector(donateTapped), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [title, message, donate])
        stack.axis = .vertical
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -24),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16),
        ])
        return card
    }

    @objc private func donateTapped() {
        guard let url = URL(string: "https://github.com/sponsors/ThaUnknown/") else { return }
        UIApplication.shared.open(url)
    }

    private func updateBodyLayout(force: Bool = false) {
        guard isViewLoaded, tableView != nil, asideView != nil else { return }
        let wide = view.bounds.width >= 1024
        let showsInlineAside = !wide && (settingsRoute == .root || view.bounds.width >= 768)
        guard force || wide != currentWideLayout || showsInlineAside != currentShowsInlineAside else { return }
        currentWideLayout = wide
        currentShowsInlineAside = showsInlineAside

        NSLayoutConstraint.deactivate(bodyLayoutConstraints)
        bodyLayoutConstraints.removeAll()
        tableView.tableHeaderView = nil
        asideView.removeFromSuperview()
        tableView.removeFromSuperview()
        bodyContent.addSubview(tableView)
        tableView.translatesAutoresizingMaskIntoConstraints = false

        if wide {
            asideWidthConstraint?.constant = 240
            asideView.translatesAutoresizingMaskIntoConstraints = false
            bodyContent.addSubview(asideView)
            bodyLayoutConstraints = [
                asideView.topAnchor.constraint(equalTo: bodyContent.topAnchor),
                asideView.leadingAnchor.constraint(equalTo: bodyContent.leadingAnchor),
                asideView.bottomAnchor.constraint(equalTo: bodyContent.bottomAnchor),
                tableView.topAnchor.constraint(equalTo: bodyContent.topAnchor),
                tableView.leadingAnchor.constraint(equalTo: asideView.trailingAnchor, constant: 48),
                tableView.trailingAnchor.constraint(equalTo: bodyContent.trailingAnchor),
                tableView.bottomAnchor.constraint(equalTo: bodyContent.bottomAnchor),
            ]
        } else {
            bodyLayoutConstraints = [
                tableView.topAnchor.constraint(equalTo: bodyContent.topAnchor),
                tableView.leadingAnchor.constraint(equalTo: bodyContent.leadingAnchor),
                tableView.trailingAnchor.constraint(equalTo: bodyContent.trailingAnchor),
                tableView.bottomAnchor.constraint(equalTo: bodyContent.bottomAnchor),
            ]
            if showsInlineAside {
                asideView.translatesAutoresizingMaskIntoConstraints = false
                tableView.tableHeaderView = asideView
                sizeInlineAsideIfNeeded()
            }
        }
        NSLayoutConstraint.activate(bodyLayoutConstraints)
    }

    private func sizeInlineAsideIfNeeded() {
        guard !isUpdatingHeader,
              tableView.tableHeaderView === asideView,
              tableView.bounds.width > 0 else { return }
        let width = tableView.bounds.width
        asideWidthConstraint?.constant = width
        let target = CGSize(width: width, height: UIView.layoutFittingCompressedSize.height)
        let height = asideView.systemLayoutSizeFitting(
            target,
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height
        guard abs(asideView.frame.width - width) > 0.5 || abs(asideView.frame.height - height) > 0.5 else { return }
        isUpdatingHeader = true
        asideView.frame = CGRect(x: 0, y: 0, width: width, height: height)
        tableView.tableHeaderView = asideView
        isUpdatingHeader = false
    }

    /// Builds SettingsNav.svelte's responsive navigation stack.
    private func buildTabGrid() -> UIView {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 4  // gap-y-1 = 4px
        stack.alignment = .fill
        stack.distribution = .fill
        headerTabStack = stack

        tabButtons.removeAll()
        tabButtonHeightConstraints.removeAll()

        for tab in SettingsTab.allCases {
            let button = makeTabButton(for: tab)
            stack.addArrangedSubview(button)
            tabButtons.append(button)
        }

        return stack
    }

    private func updateResponsiveSettingsNavigation() {
        guard isViewLoaded, let stack = headerTabStack else { return }
        let width = view.bounds.width
        let medium = width >= 768  // Tailwind md = 48rem = 768px
        let wide = width >= 1024   // Tailwind lg = 64rem = 1024px

        let crossedMediumBreakpoint = currentMediumLayout != nil && currentMediumLayout != medium
        currentMediumLayout = medium

        updatePagePadding()
        updateBodyLayout()

        // SettingsNav.svelte: flex-col md:flex-row lg:flex-col. Compact child routes hide the aside.
        stack.isHidden = !medium && settingsRoute != .root
        stack.axis = (medium && !wide) ? .horizontal : .vertical
        stack.spacing = (medium && !wide) ? 8 : 4  // gap-x-2 / gap-y-1
        stack.distribution = (medium && !wide) ? .fillProportionally : .fill

        for (index, button) in tabButtons.enumerated() {
            tabButtonHeightConstraints[safe: index]?.constant = medium ? 36 : 40  // default h-9 / lg h-10
            button.contentEdgeInsets = medium
                ? UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)   // default px-4 py-2
                : UIEdgeInsets(top: 10, left: 32, bottom: 10, right: 32) // lg px-8, h-10
            button.backgroundColor = medium ? .clear : UIColor.HayaseTheme.muted  // bg-muted md:bg-transparent
        }

        if crossedMediumBreakpoint {
            UIView.performWithoutAnimation {
                tableView.reloadData()
            }
        }

    }

    /// Creates a single tab button matching Hayase SettingsNav.svelte ghost button style.
    private func makeTabButton(for tab: SettingsTab) -> HayaseNavTabButton {
        let btn = HayaseNavTabButton()
        btn.setTitle(tab.title, for: .normal)
        btn.contentHorizontalAlignment = .leading
        btn.titleLabel?.font = .nunito(ofSize: 14, weight: .semibold)
        btn.layer.cornerRadius = 6   // rounded-md
        btn.contentEdgeInsets = UIEdgeInsets(top: 10, left: 32, bottom: 10, right: 32)  // size=lg: h-10 px-8
        let height = btn.heightAnchor.constraint(equalToConstant: 40)  // size=lg: h-10 = 40px
        height.isActive = true
        tabButtonHeightConstraints.append(height)
        btn.tag = tab.rawValue
        btn.addTarget(self, action: #selector(tabTapped(_:)), for: .touchUpInside)
        btn.backgroundColor = UIColor.HayaseTheme.muted  // bg-muted md:bg-transparent
        HayaseNavTabButton.select(tag: selectedTab.rawValue, in: [btn], animated: false)
        return btn
    }

    func openAccountsTab() {
        applyRoute(.accounts)
    }

    func applyRoute(_ route: Route.SettingsRoute) {
        settingsRoute = route
        let targetTab = settingsTab(for: route)

        guard isViewLoaded else {
            selectedTab = targetTab
            return
        }

        if route == .root {
            selectedTab = targetTab
            visibleSections = []
            HayaseNavTabButton.select(tag: -1, in: tabButtons, animated: true)
            UIView.performWithoutAnimation {
                tableView.reloadData()
            }
            updateResponsiveSettingsNavigation()
            return
        }

        if route == .changelog { loadChangelogIfNeeded() }

        if targetTab == selectedTab {
            HayaseNavTabButton.select(tag: targetTab.rawValue, in: tabButtons, animated: true)
            refreshVisibleSections()
            UIView.performWithoutAnimation {
                tableView.reloadData()
            }
        } else {
            setSelectedTab(targetTab)
        }
        updateResponsiveSettingsNavigation()
    }

    private func settingsRoute(for tab: SettingsTab) -> Route.SettingsRoute {
        switch tab {
        case .player: return .player
        case .client: return .client
        case .interface_: return .interface
        case .extensions: return .extensions
        case .accounts: return .accounts
        case .app: return .app
        case .changelog: return .changelog
        }
    }

    private func settingsTab(for route: Route.SettingsRoute) -> SettingsTab {
        switch route {
        case .root: return .player
        case .player: return .player
        case .client: return .client
        case .interface: return .interface_
        case .extensions: return .extensions
        case .accounts: return .accounts
        case .app: return .app
        case .changelog: return .changelog
        }
    }

    @objc private func tabTapped(_ sender: UIButton) {
        guard let tab = SettingsTab(rawValue: sender.tag), tab != selectedTab else { return }
        Router.shared.navigate(.settings(settingsRoute(for: tab)), hostTabIndex: hayaseTabIndex, noScroll: true)
    }

    private func setSelectedTab(_ tab: SettingsTab) {
        guard tab != selectedTab else { return }
        // Update model state + tab-button appearance + reload.
        //    ALL of this must happen with ZERO animation/transaction context.
        //    Even UIButton.backgroundColor changes create an implicit
        //    CATransaction; if reloadData() fires within that transaction,
        //    UIKit treats it as an incremental (animated) update and applies
        //    row-count consistency checks — crashing with "invalid number of
        //    rows in section N" whenever the section/row structure changes.
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        selectedTab = tab

        HayaseNavTabButton.select(tag: tab.rawValue, in: tabButtons, animated: true)

        // Refresh the cached section array and reload.
        refreshVisibleSections()
        UIView.performWithoutAnimation {
            tableView.reloadData()
        }

        CATransaction.commit()
    }

    // MARK: - Helpers

    private func appVersion() -> String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(v) (\(b))"
    }

    /// Keys whose changes must be forwarded to the active torrent backend.
    /// Mirrors Hayase's `torrentSettings` derived store that triggers `native.updateSettings`.
    private static let torrentSettingKeys: Set<String> = [
        TorrentBackendKind.userDefaultsKey,
        "pref_disableDHT", "pref_disablePeX",
        "pref_torrentPort", "pref_dhtPort",
        "pref_torrentSpeed", "pref_maxConns",
        "pref_torrentLocation", "pref_nzbDomain", "pref_nzbLogin",
        "pref_nzbPassword", "pref_nzbPort", "pref_nzbPoolSize",
        Settings.Keys.streamedDownload, Settings.Keys.persistFiles,
    ]

    /// If `key` is a torrent-session setting, re-apply settings to the live session.
    private func applyTorrentSettingsIfNeeded(forKey key: String) {
        if Self.torrentSettingKeys.contains(key) {
            if key == TorrentBackendKind.userDefaultsKey {
                TorrentBackendManager.shared.backendSelectionDidChange()
            } else {
                TorrentBackendManager.shared.applyCurrentSettings()
            }
        }
    }

    // MARK: - Selection picker (used for selectable rows)

    private func showSelectionPicker(title: String, key: String, options: [(key: String, label: String)], defaultKey: String, indexPath: IndexPath) {
        let currentKey = UserDefaults.standard.string(forKey: key) ?? defaultKey
        let cell = tableView.cellForRow(at: indexPath) as? HayaseSettingValueCell
        let picker = CommandPopoverViewController(
            title: title,
            placeholder: "Search...",
            groups: [CommandGroup(options: options.map {
                CommandOption(value: $0.key, label: $0.label)
            })],
            selectedValues: [currentKey],
            allowsMultiple: false,
            sourceView: cell?.selectionAnchor ?? tableView
        )
        picker.onSelectionChanged = { [weak self] values in
            guard let value = values.first else { return }
            Settings.write(value, forKey: key)
            self?.tableView.reloadData()
            self?.applyTorrentSettingsIfNeeded(forKey: key)
        }
        present(picker, animated: true)
    }

    // The web settings use inline inputs. Commit on editing end so the active
    // torrent session is updated without replacing the editing cell.
    private func commitInput(_ value: String, key: String, fallback: String,
                             numericRange: ClosedRange<Int>?, allowsFraction: Bool = false) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let result: String
        if let range = numericRange {
            if allowsFraction, let number = Double(trimmed), number.isFinite {
                result = String(Swift.min(Swift.max(number, Double(range.lowerBound)), Double(range.upperBound)))
            } else if let number = Int(trimmed) {
                result = String(Swift.min(Swift.max(number, range.lowerBound), range.upperBound))
            } else {
                return UserDefaults.standard.string(forKey: key) ?? fallback
            }
        } else {
            result = trimmed
        }
        Settings.write(result, forKey: key)
        applyTorrentSettingsIfNeeded(forKey: key)
        return result
    }

    // MARK: - Action handling

    private func handleAction(title: String) {
        switch title {
        case "Import Settings From File":
            let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.json], asCopy: true)
            picker.delegate = self
            present(picker, animated: true)
        case "Export Settings To File":
            exportSettings()
        case "Reset Everything To Default", "Reset EVERYTHING To Default":
            let alert = UIAlertController(title: "Reset Everything?",
                                          message: "This will reset ALL settings and data to their default values. This cannot be undone.",
                                          preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Reset", style: .destructive) { [weak self] _ in
                SettingsFileService.resetPreferences()
                TorrentBackendManager.shared.applyCurrentSettings()
                HayaseInterfaceScale.apply()
                self?.tableView.reloadData()
            })
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            present(alert, animated: true)
        case "Copy App and Device Info":
            var info = "Hayase v\(appVersion())\n"
            info += "iOS \(UIDevice.current.systemVersion)\n"
            info += "\(UIDevice.current.model)\n"
            UIPasteboard.general.string = info
        default:
            break
        }
    }

    private func exportSettings() {
        guard let data = try? SettingsFileService.exportData() else {
            presentMessage(title: "Export Failed", message: "The current settings could not be encoded.")
            return
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("hayase-settings.json")
        do {
            try data.write(to: url, options: .atomic)
            let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            if let popover = activity.popoverPresentationController {
                popover.sourceView = view
                popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
            }
            present(activity, animated: true)
        } catch {
            presentMessage(title: "Export Failed", message: error.localizedDescription)
        }
    }

    fileprivate func importSettings(from url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            try SettingsFileService.importData(data)
            TorrentBackendManager.shared.applyCurrentSettings()
            HayaseInterfaceScale.apply()
            refreshVisibleSections()
            tableView.reloadData()
            presentMessage(title: "Settings Imported", message: "Your settings were imported successfully.")
        } catch {
            presentMessage(title: "Import Failed", message: error.localizedDescription)
        }
    }

    private func presentMessage(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    private func controlWidth(for row: Row) -> CGFloat {
        switch row.title {
        case "Title Language":
            return 240
        case "Preferred Subtitle Language", "Preferred Audio Language":
            return 144
        case "DNS Over HTTPS URL", "Provider Domain", "Provider Login", "Provider Password":
            return 320
        default:
            return 128
        }
    }

    private func showRestartPlayerNoticeIfNeeded() {
        guard MiniPlayerManager.shared.activePlayer != nil else { return }
        let alert = UIAlertController(title: "Subtitle Style Updated",
                                      message: "The new dialogue style will be used the next time the video player starts.",
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    private func loadChangelogIfNeeded() {
        guard changelogEntries == nil, changelogError == nil else { return }
        SettingsChangelogService.shared.load { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let entries): self.changelogEntries = entries
            case .failure(let error): self.changelogError = error.localizedDescription
            }
            guard self.selectedTab == .changelog else { return }
            self.tableView.reloadData()
        }
    }
}

// MARK: - UITableViewDataSource

extension SettingsViewController: UITableViewDataSource {

    func numberOfSections(in tableView: UITableView) -> Int { visibleSections.count }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard section >= 0, section < visibleSections.count else { return 0 }
        return visibleSections[section].rows.count
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard section >= 0, section < visibleSections.count else { return nil }
        guard !visibleSections[section].header.isEmpty else { return nil }
        // Hayase: <div class='font-weight-bold text-xl font-bold'>Section Name</div>
        let container = UIView()
        container.backgroundColor = .clear
        let label = UILabel()
        label.text = visibleSections[section].header
        label.font = .nunito(ofSize: 20, weight: .bold)
        label.textColor = UIColor.HayaseTheme.foreground
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 6),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -6),
        ])
        return container
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        guard section >= 0, section < visibleSections.count,
              !visibleSections[section].header.isEmpty else { return 0.01 }
        return UITableView.automaticDimension
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard indexPath.section >= 0, indexPath.section < visibleSections.count,
              indexPath.row >= 0, indexPath.row < visibleSections[indexPath.section].rows.count else {
            return UITableViewCell()
        }
        let row = visibleSections[indexPath.section].rows[indexPath.row]
        let horizontal = view.bounds.width >= 768
        switch row.kind {
        case .toggle(let key, let def):
            guard let cell = tableView.dequeueReusableCell(
                withIdentifier: HayaseSettingToggleCell.reuseID, for: indexPath) as? HayaseSettingToggleCell else { return UITableViewCell() }
            cell.configure(title: row.title, description: row.description,
                           key: key, defaultValue: def, horizontal: horizontal)
            cell.onToggled = { [weak self] toggledKey in
                self?.applyTorrentSettingsIfNeeded(forKey: toggledKey)
            }
            cell.backgroundColor = bgColor
            return cell
        case .value(let val):
            guard let cell = tableView.dequeueReusableCell(
                withIdentifier: HayaseSettingValueCell.reuseID, for: indexPath) as? HayaseSettingValueCell else { return UITableViewCell() }
            cell.configure(title: row.title, description: row.description, value: val,
                           isLink: false, horizontal: horizontal, controlWidth: controlWidth(for: row))
            cell.backgroundColor = bgColor
            return cell
        case .selectable(let key, let options, let defaultKey):
            guard let cell = tableView.dequeueReusableCell(
                withIdentifier: HayaseSettingValueCell.reuseID, for: indexPath) as? HayaseSettingValueCell else { return UITableViewCell() }
            let storedKey = UserDefaults.standard.string(forKey: key) ?? defaultKey
            let displayValue = options.first(where: { $0.key == storedKey })?.label ?? storedKey
            if row.title == "Torrent Download Location" {
                cell.configureDownloadLocation(title: row.title, description: row.description,
                                               path: TorrentBackendSettings().path,
                                               choice: displayValue, horizontal: horizontal)
            } else {
                cell.configure(title: row.title, description: row.description, value: displayValue,
                               isLink: false, horizontal: horizontal,
                               controlWidth: controlWidth(for: row), selectable: true)
            }
            cell.selectionStyle = .default
            cell.backgroundColor = bgColor
            return cell
        case .editableNumber(let key, let defaultValue, let suffix, let min, let max):
            guard let cell = tableView.dequeueReusableCell(
                withIdentifier: HayaseSettingValueCell.reuseID, for: indexPath) as? HayaseSettingValueCell else { return UITableViewCell() }
            let stored = UserDefaults.standard.string(forKey: key) ?? defaultValue
            cell.configureInput(title: row.title, description: row.description, value: stored,
                                placeholder: defaultValue, secure: false, numeric: true,
                                suffix: suffix, horizontal: horizontal, controlWidth: 128)
            cell.onInputEnded = { [weak self] value in
                self?.commitInput(value, key: key, fallback: defaultValue,
                                  numericRange: min...max, allowsFraction: key == Settings.Keys.seekDuration) ?? stored
            }
            cell.backgroundColor = bgColor
            return cell
        case .editableText(let key, let defaultValue, let secure):
            guard let cell = tableView.dequeueReusableCell(
                withIdentifier: HayaseSettingValueCell.reuseID, for: indexPath) as? HayaseSettingValueCell else { return UITableViewCell() }
            let stored = UserDefaults.standard.string(forKey: key) ?? defaultValue
            let placeholder: String
            switch row.title {
            case "Provider Domain": placeholder = "news.example.com"
            case "Provider Login": placeholder = "admin"
            case "Provider Password": placeholder = "admin1"
            default: placeholder = ""
            }
            cell.configureInput(title: row.title, description: row.description, value: stored,
                                placeholder: placeholder, secure: secure, numeric: false,
                                suffix: "", horizontal: horizontal, controlWidth: 320)
            cell.onInputEnded = { [weak self] value in
                self?.commitInput(value, key: key, fallback: defaultValue, numericRange: nil) ?? stored
            }
            cell.backgroundColor = bgColor
            return cell
        case .link:
            guard let cell = tableView.dequeueReusableCell(
                withIdentifier: HayaseSettingValueCell.reuseID, for: indexPath) as? HayaseSettingValueCell else { return UITableViewCell() }
            cell.configure(title: row.title, description: row.description, value: nil,
                           isLink: true, horizontal: horizontal)
            cell.backgroundColor = bgColor
            return cell
        case .navigate:
            guard let cell = tableView.dequeueReusableCell(
                withIdentifier: HayaseSettingValueCell.reuseID, for: indexPath) as? HayaseSettingValueCell else { return UITableViewCell() }
            cell.configure(title: row.title, description: row.description, value: "Manage Extensions",
                           isLink: false, horizontal: horizontal, filledControl: true)
            cell.backgroundColor = bgColor
            return cell
        case .action:
            guard let cell = tableView.dequeueReusableCell(
                withIdentifier: HayaseSettingValueCell.reuseID, for: indexPath) as? HayaseSettingValueCell else { return UITableViewCell() }
            cell.configure(title: row.title, description: row.description, value: nil,
                           isLink: false, horizontal: horizontal)
            cell.backgroundColor = bgColor
            return cell
        case .appActions:
            guard let cell = tableView.dequeueReusableCell(
                withIdentifier: HayaseAppActionsCell.reuseID,
                for: indexPath) as? HayaseAppActionsCell else { return UITableViewCell() }
            cell.configure(horizontal: horizontal)
            cell.onAction = { [weak self] title in
                self?.handleAction(title: title)
            }
            cell.backgroundColor = bgColor
            return cell
        case .slider(let key, let defaultValue, let min, let max, let step):
            guard let cell = tableView.dequeueReusableCell(
                withIdentifier: HayaseSettingSliderCell.reuseID,
                for: indexPath) as? HayaseSettingSliderCell else { return UITableViewCell() }
            let stored = UserDefaults.standard.object(forKey: key) == nil
                ? defaultValue
                : UserDefaults.standard.double(forKey: key)
            cell.configure(title: row.title, description: row.description, value: stored,
                           min: min, max: max, step: step, horizontal: horizontal)
            cell.onValueChanged = { [weak self] value in
                if key == Settings.Keys.uiScale {
                    self?.pendingScale = value
                } else {
                    Settings.write(value, forKey: key)
                }
            }
            cell.onEditingEnded = key == Settings.Keys.uiScale ? { [weak self] in
                self?.confirmScaleChange()
            } : nil
            cell.backgroundColor = bgColor
            return cell
        case .button(let label):
            guard let cell = tableView.dequeueReusableCell(
                withIdentifier: HayaseSettingValueCell.reuseID, for: indexPath) as? HayaseSettingValueCell else { return UITableViewCell() }
            cell.configure(title: row.title, description: row.description, value: label,
                           isLink: false, horizontal: horizontal, filledControl: true)
            cell.backgroundColor = bgColor
            return cell
        case .previewGrid(let kind):
            guard let cell = tableView.dequeueReusableCell(
                withIdentifier: HayaseSettingsPreviewGridCell.reuseID,
                for: indexPath) as? HayaseSettingsPreviewGridCell else { return UITableViewCell() }
            let selectedValue = kind == .subtitleStyle ? Settings.subtitleStyle : "default"
            cell.configure(title: row.title, description: row.description,
                           kind: kind, selectedValue: selectedValue,
                           twoColumns: view.bounds.width >= 640)
            cell.onSelection = kind == .subtitleStyle ? { [weak self, weak tableView] value in
                Settings.subtitleStyle = value
                tableView?.reloadRows(at: [indexPath], with: .none)
                self?.showRestartPlayerNoticeIfNeeded()
            } : nil
            cell.backgroundColor = bgColor
            return cell
        case .changelogPlaceholder:
            guard let cell = tableView.dequeueReusableCell(
                withIdentifier: HayaseChangelogPlaceholderCell.reuseID,
                for: indexPath) as? HayaseChangelogPlaceholderCell else { return UITableViewCell() }
            cell.configure(title: row.title, description: row.description,
                           wide: view.bounds.width >= 640,
                           loadedEntries: changelogEntries,
                           error: changelogError)
            cell.backgroundColor = bgColor
            return cell
        case .account(let tracker):
            guard let cell = tableView.dequeueReusableCell(
                withIdentifier: HayaseAccountCardCell.reuseID, for: indexPath) as? HayaseAccountCardCell else { return UITableViewCell() }
            cell.configure(tracker: tracker, parentVC: self)
            cell.backgroundColor = bgColor
            return cell
        }
    }
}

// MARK: - UITableViewDelegate

extension SettingsViewController: UITableViewDelegate {

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard indexPath.section >= 0, indexPath.section < visibleSections.count,
              indexPath.row >= 0, indexPath.row < visibleSections[indexPath.section].rows.count else { return }
        let row = visibleSections[indexPath.section].rows[indexPath.row]
        switch row.kind {
        case .link(let urlStr):
            if let url = URL(string: urlStr) { present(SFSafariViewController(url: url), animated: true) }
        case .navigate:
            if row.title == "Manage Extensions" {
                let extVC = ExtensionsViewController()
                if let navigationController {
                    localRouteTransition.perform(in: navigationController.view) {
                        navigationController.pushViewController(extVC, animated: false)
                    }
                }
            }
        case .selectable(let key, let options, let defaultKey):
            showSelectionPicker(title: row.title, key: key, options: options, defaultKey: defaultKey, indexPath: indexPath)
        case .editableNumber, .editableText:
            break // Inline Input handles editing.
        case .action:
            handleAction(title: row.title)
        case .button(_):
            if row.title == "Debug page" {
                if let navigationController {
                    localRouteTransition.perform(in: navigationController.view) {
                        navigationController.pushViewController(HayaseDebugViewController(), animated: false)
                    }
                }
            }
        case .account(_), .previewGrid(_), .changelogPlaceholder, .appActions, .slider(_, _, _, _, _):
            break // Account cards handle their own interactions
        default:
            break
        }
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        UITableView.automaticDimension
    }

    func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat {
        guard indexPath.section >= 0, indexPath.section < visibleSections.count,
              indexPath.row >= 0, indexPath.row < visibleSections[indexPath.section].rows.count else { return 80 }
        let row = visibleSections[indexPath.section].rows[indexPath.row]
        if case .account = row.kind { return 140 }
        if case .previewGrid = row.kind { return 420 }
        if case .changelogPlaceholder = row.kind { return 620 }
        return 80
    }

    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        // No-op — UIView.animate here creates implicit CATransactions that
        // cause reloadData() during tab switches to be treated as an
        // incremental update, crashing with "invalid number of rows in
        // section N" when the section/row structure changes between tabs.
    }
}

extension SettingsViewController: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        importSettings(from: url)
    }
}
