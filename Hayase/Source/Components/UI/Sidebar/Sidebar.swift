//
//  Sidebar.swift
//  Hayase
//
//  Made by scigward.
//
//  Mirrors: src/lib/components/ui/sidebar/sidebar.svelte (the desktop and mobile sidebars and the backdrop of the banner), and the host of the routes (the stand-in for SvelteKit: it loads a route, shows it and keeps the state of the anime page).
//  What src/routes/+layout.svelte and src/routes/app/+layout.svelte do is in Routes/RootLayout.swift and Routes/App/AppLayout.swift, as extensions of this class.
//

import UIKit

// MARK: - HayaseSidebarController

final class HayaseSidebarController: UIViewController {
    static let homeBannerBackdropDidChange = Notification.Name("HayaseHomeBannerBackdropDidChange")
    static let homeBannerBackdropURLKey = "url"
    static let homeBannerBackdropAlphaKey = "alpha"
    static let homeBannerBackdropScrollOffsetKey = "scrollOffset"
    static let homeBannerBackdropHeightKey = "height"
    static let homeBannerBackdropRouteKey = "route"
    static let homeBannerBackdropMediaKey = "media"
    static let homeBannerBackdropClearKey = "clear"
    static let homeBannerBackdropHomeRoute = "home"
    static let homeBannerBackdropAnimeRoute = "anime"
    static let homeBannerBackdropPlayerRoute = "player"

    let tabHost: UITabBarController
    var routeControllers: [UIViewController] = []
    var selectedRouteIndex = 0
    let router = Router.shared
    let sidebarList = HayaseSidebarListView(mode: .desktop)
    let mobileSidebarList = HayaseSidebarListView(mode: .mobile)
    let contentContainer = UIView()
    /// Online.svelte sits above the sidebar and the page in routes/+layout.svelte.
    let onlineBar = HayaseOnlineBar()
    static let routeSnapshotLimit = 10

    var progressWindow: HayaseProgressBarWindow?
    let routeTransition = HayaseRouteTransition()
    let mobileLauncher = UIView()
    let mobileGridContainer = UIView()
    let mobileToggleButton = HayaseSidebarButton(route: nil, size: .mobile)
    let sidebarContainer = UIView()
    let sidebarBackdropImageView = UIImageView()
    let sidebarBackdropGradientView = BannerGradientView()
    let sidebarBackdropCoverView = UIView()
    var sidebarBackdropTask: URLSessionDataTask?
    var sidebarBackdropURL: String?
    /// The media the banner belongs to: `bannerSrc`, which banner-image.svelte keys on.
    var sidebarBackdropMediaID: Int?
    var sidebarBackdropAlpha: CGFloat = 0
    var sidebarBackdropCoverTransitionID = 0
    var sidebarBackdropHeightConstraint: NSLayoutConstraint?
    var sidebarWidthConstraint: NSLayoutConstraint?
    var mobileLauncherWidthConstraint: NSLayoutConstraint?
    var mobileLauncherHeightConstraint: NSLayoutConstraint?
    var isMobileMenuOpen = false
    var isDesktopMode: Bool?
    var playerFullscreenActive = false
    var routeObservationID: UUID?
    var activeHistorySwipeDirection: HayaseHistorySwipe.Direction?
    var historySwipe: HayaseHistorySwipe?
    var routeSnapshots: [Route: UIView] = [:]
    var routeSnapshotOrder: [Route] = []
    var lastAppliedRoute: Route?
    var routeScrollPositions: [Route: CGPoint] = [:]
    var isNavigationLoading = false

    init(tabBarController: UITabBarController) {
        self.tabHost = tabBarController
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.HayaseTheme.background
        installInterfaceRoutes()
        router.reset(to: Route(tabIndex: selectedRouteIndex) ?? .home, hostTabIndex: selectedRouteIndex)
        setupContentHost()
        setupDesktopSidebar()
        setupMobileSidebar()
        configureActions()
        observeBannerBackdrop()
        observeRouteChanges()
        apply(route: router.currentRoute, kind: .replace, options: .init(), animated: false)
        updateLayoutForCurrentWidth()
        // routes/app/+layout.svelte: `on:drop` and `on:paste` of the window
        view.addInteraction(UIDropInteraction(delegate: self))
    }

    override var canBecomeFirstResponder: Bool { true }

    override var prefersStatusBarHidden: Bool { true }
    override var childForStatusBarHidden: UIViewController? { nil }

    override var keyCommands: [UIKeyCommand]? {
        [
            UIKeyCommand(input: "[", modifierFlags: .command, action: #selector(routeBackCommand)),
            UIKeyCommand(input: UIKeyCommand.inputLeftArrow, modifierFlags: .alternate, action: #selector(routeBackCommand)),
            UIKeyCommand(input: "]", modifierFlags: .command, action: #selector(routeForwardCommand)),
            UIKeyCommand(input: UIKeyCommand.inputRightArrow, modifierFlags: .alternate, action: #selector(routeForwardCommand)),
        ]
    }

    @objc func routeBackCommand() {
        router.back()
    }

    @objc func routeForwardCommand() {
        router.forward()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        hideHostedNavigationBars()
        updateSidebarBackground()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // the window's paste and the keyboard shortcuts come to the app when nothing else has the keys
        if !isFirstResponder { becomeFirstResponder() }
        installProgressBarIfNeeded()
        hideHostedNavigationBars()
        updateSidebarBackground()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        HayaseInterfaceScale.apply(to: self, in: view.window)
        updateLayoutForCurrentWidth()
        updateSidebarBackground()
        hideHostedNavigationBars()
        MiniPlayerManager.shared.repositionContainer()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        hideHostedNavigationBars()
        updateLayoutForCurrentWidth()
    }

    func setupContentHost() {
        hideNativeTabNavigation()
        tabHost.delegate = self

        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.backgroundColor = UIColor.HayaseTheme.background
        view.addSubview(contentContainer)
        onlineBar.layer.zPosition = 40   // z-40
        view.addSubview(onlineBar)

        addChild(tabHost)
        tabHost.view.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(tabHost.view)
        NSLayoutConstraint.activate([
            onlineBar.topAnchor.constraint(equalTo: view.topAnchor),
            onlineBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            onlineBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            contentContainer.topAnchor.constraint(equalTo: onlineBar.bottomAnchor),
            contentContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            contentContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            tabHost.view.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            tabHost.view.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            tabHost.view.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            tabHost.view.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),
        ])
        tabHost.didMove(toParent: self)
        installRouteHistoryGestures()
    }

    func installInterfaceRoutes() {
        guard let viewControllers = tabHost.viewControllers else { return }
        let selectedController = tabHost.selectedViewController
        routeControllers = Self.interfaceRoutes(from: viewControllers)
        for (index, controller) in routeControllers.enumerated() {
            controller.hayaseLogicalRouteIndex = index
        }
        selectedRouteIndex = routeControllers.firstIndex { $0 === selectedController } ?? 0
        selectRouteController(at: selectedRouteIndex)
    }

    func selectRouteController(at index: Int) {
        guard routeControllers.indices.contains(index) else { return }
        let controller = routeControllers[index]
        selectedRouteIndex = index
        // The sidebar owns navigation. Give UIKit one visible tab, not seven:
        // otherwise compact UIKit moves Client/Settings under its More controller.
        // Retain each original navigation stack separately, including its player.
        if tabHost.selectedViewController !== controller || tabHost.viewControllers?.count != 1 {
            tabHost.setViewControllers([controller], animated: false)
        }
    }

    static func interfaceRoutes(from viewControllers: [UIViewController]) -> [UIViewController] {
        // Keep the storyboard-created navigation controllers intact. Moving
        // their root controllers into replacement navigation controllers here
        // changes UIKit ownership before the destination views have loaded.
        // That rewrite is unnecessary for Schedule, Client and Settings/Profile
        // and makes their storyboard relationship ownership invalid.
        var controllers = viewControllers
        guard controllers.count == 6 else { return controllers }
        let chat = UINavigationController(rootViewController: HayaseChatViewController())
        chat.setNavigationBarHidden(true, animated: false)
        controllers.insert(chat, at: 4)
        return controllers
    }

    func hideHostedNavigationBars() {
        hideNativeTabNavigation()
        hideNavigationChrome(in: tabHost)
    }

    func hideNativeTabNavigation() {
        tabHost.tabBar.isHidden = true
        tabHost.tabBar.alpha = 0
        tabHost.tabBar.isUserInteractionEnabled = false

        if #available(iOS 18.0, *) {
            tabHost.mode = .tabBar
            tabHost.setTabBarHidden(true, animated: false)
            tabHost.sidebar.isHidden = true
        }
        tabHost.view.setNeedsLayout()
    }

    func hideNavigationChrome(in viewController: UIViewController?) {
        guard let viewController else { return }
        if let tab = viewController as? UITabBarController {
            tab.tabBar.isHidden = true
            tab.tabBar.alpha = 0
            tab.tabBar.isUserInteractionEnabled = false
        }
        if let nav = viewController as? UINavigationController {
            nav.setNavigationBarHidden(true, animated: false)
            nav.isToolbarHidden = true
            nav.navigationBar.isHidden = true
            nav.navigationBar.alpha = 0
            nav.navigationBar.isUserInteractionEnabled = false
            nav.toolbar.isHidden = true
            nav.view.setNeedsLayout()
        }
        viewController.children.forEach { hideNavigationChrome(in: $0) }
        hideNavigationChrome(in: viewController.presentedViewController)
    }

    func setupDesktopSidebar() {
        sidebarList.translatesAutoresizingMaskIntoConstraints = false
        sidebarList.backgroundColor = .clear

        sidebarBackdropImageView.translatesAutoresizingMaskIntoConstraints = false
        sidebarBackdropImageView.contentMode = .scaleAspectFill
        sidebarBackdropImageView.clipsToBounds = true
        sidebarBackdropImageView.alpha = 0

        sidebarBackdropGradientView.translatesAutoresizingMaskIntoConstraints = false
        sidebarBackdropGradientView.alpha = 0

        sidebarBackdropCoverView.translatesAutoresizingMaskIntoConstraints = false
        sidebarBackdropCoverView.backgroundColor = UIColor.HayaseTheme.background
        sidebarBackdropCoverView.alpha = 0
        sidebarBackdropCoverView.isUserInteractionEnabled = false

        sidebarContainer.translatesAutoresizingMaskIntoConstraints = false
        sidebarContainer.backgroundColor = .clear
        sidebarContainer.clipsToBounds = true
        sidebarContainer.addSubview(sidebarBackdropImageView)
        sidebarContainer.addSubview(sidebarBackdropGradientView)
        sidebarContainer.addSubview(sidebarBackdropCoverView)
        sidebarContainer.addSubview(sidebarList)
        view.addSubview(sidebarContainer)

        let sidebarWidthConstraint = sidebarContainer.widthAnchor.constraint(equalToConstant: 56)
        self.sidebarWidthConstraint = sidebarWidthConstraint
        let sidebarBackdropHeightConstraint = sidebarBackdropImageView.heightAnchor.constraint(equalToConstant: 368)
        self.sidebarBackdropHeightConstraint = sidebarBackdropHeightConstraint
        NSLayoutConstraint.activate([
            sidebarContainer.topAnchor.constraint(equalTo: onlineBar.bottomAnchor),
            sidebarContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            sidebarContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            sidebarWidthConstraint,
            contentContainer.leadingAnchor.constraint(equalTo: sidebarContainer.trailingAnchor),

            // sidebarlist.svelte renders <BannerImage class='w-14'>. The
            // inner image is still w-screen; the rail only clips the left 56pt.
            sidebarBackdropImageView.topAnchor.constraint(equalTo: sidebarContainer.topAnchor),
            sidebarBackdropImageView.leadingAnchor.constraint(equalTo: sidebarContainer.leadingAnchor),
            sidebarBackdropImageView.widthAnchor.constraint(equalTo: view.widthAnchor),
            // Updated in updateSidebarBackground(): web BannerImage is 90vh on
            // home at md+ widths and h-[23rem] on anime/detail routes.
            sidebarBackdropHeightConstraint,

            sidebarBackdropGradientView.topAnchor.constraint(equalTo: sidebarBackdropImageView.topAnchor),
            sidebarBackdropGradientView.leadingAnchor.constraint(equalTo: sidebarBackdropImageView.leadingAnchor),
            sidebarBackdropGradientView.widthAnchor.constraint(equalTo: sidebarBackdropImageView.widthAnchor),
            sidebarBackdropGradientView.heightAnchor.constraint(equalTo: sidebarBackdropImageView.heightAnchor),

            sidebarBackdropCoverView.topAnchor.constraint(equalTo: sidebarContainer.topAnchor),
            sidebarBackdropCoverView.leadingAnchor.constraint(equalTo: sidebarContainer.leadingAnchor),
            sidebarBackdropCoverView.trailingAnchor.constraint(equalTo: sidebarContainer.trailingAnchor),
            sidebarBackdropCoverView.bottomAnchor.constraint(equalTo: sidebarContainer.bottomAnchor),

            // sidebar.svelte: w-14 p-2 md:pl-0. The web rail starts at
            // the viewport edge, not the safe-area edge, because the app owns
            // the full-screen layout.
            sidebarList.topAnchor.constraint(equalTo: sidebarContainer.topAnchor, constant: 8),
            sidebarList.leadingAnchor.constraint(equalTo: sidebarContainer.leadingAnchor),
            sidebarList.trailingAnchor.constraint(equalTo: sidebarContainer.trailingAnchor, constant: -8),
            sidebarList.bottomAnchor.constraint(equalTo: sidebarContainer.bottomAnchor, constant: -8),
        ])
    }

    func setupMobileSidebar() {
        mobileLauncher.translatesAutoresizingMaskIntoConstraints = false
        mobileLauncher.backgroundColor = UIColor.HayaseTheme.background
        mobileLauncher.layer.cornerRadius = 6
        mobileLauncher.clipsToBounds = true
        mobileLauncher.layer.zPosition = 50
        view.addSubview(mobileLauncher)

        mobileGridContainer.translatesAutoresizingMaskIntoConstraints = false
        mobileLauncher.addSubview(mobileGridContainer)

        mobileSidebarList.translatesAutoresizingMaskIntoConstraints = false
        mobileGridContainer.addSubview(mobileSidebarList)

        // Button variant='ghost' size='icon-lg' with the plain 150ms transition-colors
        mobileToggleButton.colorDuration = 0.15
        mobileToggleButton.setSidebarImage(UIImage.hayaseIcon("menu"), pointSize: 18, renderingMode: .alwaysTemplate)
        mobileToggleButton.onPress = { [weak self] in self?.toggleMobileMenu() }
        mobileGridContainer.addSubview(mobileToggleButton)

        let mobileLauncherWidthConstraint = mobileLauncher.widthAnchor.constraint(equalToConstant: 64)
        self.mobileLauncherWidthConstraint = mobileLauncherWidthConstraint
        let mobileLauncherHeightConstraint = mobileLauncher.heightAnchor.constraint(equalToConstant: 64)
        self.mobileLauncherHeightConstraint = mobileLauncherHeightConstraint
        NSLayoutConstraint.activate([
            mobileLauncher.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),  // left-4 = 16px
            mobileLauncher.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16),  // bottom-4 = 16px
            mobileLauncherWidthConstraint,
            mobileLauncherHeightConstraint,

            mobileGridContainer.widthAnchor.constraint(equalToConstant: 160),
            mobileGridContainer.heightAnchor.constraint(equalToConstant: 160),
            mobileGridContainer.trailingAnchor.constraint(equalTo: mobileLauncher.trailingAnchor, constant: -8),
            mobileGridContainer.bottomAnchor.constraint(equalTo: mobileLauncher.bottomAnchor, constant: -8),

            mobileSidebarList.topAnchor.constraint(equalTo: mobileGridContainer.topAnchor),
            mobileSidebarList.leadingAnchor.constraint(equalTo: mobileGridContainer.leadingAnchor),
            mobileSidebarList.trailingAnchor.constraint(equalTo: mobileGridContainer.trailingAnchor),
            mobileSidebarList.bottomAnchor.constraint(equalTo: mobileGridContainer.bottomAnchor),

            mobileToggleButton.trailingAnchor.constraint(equalTo: mobileGridContainer.trailingAnchor),
            mobileToggleButton.bottomAnchor.constraint(equalTo: mobileGridContainer.bottomAnchor),
        ])

        let outsideTap = UITapGestureRecognizer(target: self, action: #selector(handleOutsideTap(_:)))
        outsideTap.cancelsTouchesInView = false
        view.addGestureRecognizer(outsideTap)
    }

    func observeBannerBackdrop() {
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(homeBannerBackdropDidChange(_:)),
                                               name: Self.homeBannerBackdropDidChange,
                                               object: nil)
    }

    @objc func homeBannerBackdropDidChange(_ notification: Notification) {
        let userInfo = notification.userInfo ?? [:]

        // The page banner is route-owned, as `$page.route` gates banner-image.svelte. Ignore late
        // async image/fade updates from a page that is no longer the current route, otherwise
        // the sidebar keeps a stale detail/home backdrop until the app restarts.
        let route = userInfo[Self.homeBannerBackdropRouteKey] as? String
        if let route = route {
            if route == Self.homeBannerBackdropPlayerRoute {
                clearSidebarBackdrop()
                return
            }
            guard route == currentBannerRoute else { return }
        }
        if userInfo[Self.homeBannerBackdropClearKey] as? Bool == true {
            clearSidebarBackdrop()
            return
        }

        if let height = userInfo[Self.homeBannerBackdropHeightKey] as? CGFloat, height > 0 {
            sidebarBackdropHeightConstraint?.constant = height
        }

        if route == Self.homeBannerBackdropAnimeRoute {
            applySidebarBackdropScrollOffset(0)
        } else if let scrollOffset = userInfo[Self.homeBannerBackdropScrollOffsetKey] as? CGFloat {
            applySidebarBackdropScrollOffset(scrollOffset)
        } else if route == Self.homeBannerBackdropHomeRoute {
            applySidebarBackdropScrollOffset(0)
        }

        if let alpha = userInfo[Self.homeBannerBackdropAlphaKey] as? CGFloat {
            transitionSidebarBackdrop(to: min(max(alpha, 0), 1))
        }

        // {#key debounced.id}: a banner for another media replaces the old one at once, before
        // its own image is known.
        if let mediaID = userInfo[Self.homeBannerBackdropMediaKey] as? Int, mediaID != sidebarBackdropMediaID {
            flushSidebarBackdropImage()
            sidebarBackdropMediaID = mediaID
        }

        updateSidebarBackground()

        guard let urlString = userInfo[Self.homeBannerBackdropURLKey] as? String,
              urlString != sidebarBackdropURL,
              let url = URL(string: urlString) else { return }

        sidebarBackdropURL = urlString
        sidebarBackdropTask?.cancel()

        // banner-image.svelte replaces the banner element on every change: the old image is
        // gone at once and the new one loads in.
        sidebarBackdropImageView.layer.removeAllAnimations()
        sidebarBackdropImageView.subviews.forEach { $0.removeFromSuperview() }
        sidebarBackdropImageView.image = nil
        let announcedAt = CACurrentMediaTime()

        if let cached = SharedImageCache.shared.object(forKey: urlString as NSString) {
            LoadIn.show(cached, in: sidebarBackdropImageView, blurred: true)
            updateSidebarBackground()
            return
        }

        sidebarBackdropTask = URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data, let image = UIImage(data: data) else { return }
            SharedImageCache.shared.setObject(image, forKey: urlString as NSString)
            DispatchQueue.main.async {
                guard let self, self.sidebarBackdropURL == urlString else { return }
                LoadIn.show(image, in: self.sidebarBackdropImageView,
                            blurred: CACurrentMediaTime() - announcedAt < LoadIn.blurWindow)
                self.updateSidebarBackground()
            }
        }
        sidebarBackdropTask?.resume()
    }

    func applySidebarBackdropScrollOffset(_ scrollOffset: CGFloat) {
        // Interface mounts the sidebar BannerImage at absolute top-left too.
        // The 56pt rail clips the full-width image; it never scroll-translates.
        sidebarBackdropImageView.transform = .identity
        sidebarBackdropGradientView.transform = .identity
    }

    func transitionSidebarBackdrop(to alpha: CGFloat) {
        guard abs(alpha - sidebarBackdropAlpha) > 0.01 else { return }

        sidebarBackdropAlpha = alpha
        sidebarBackdropCoverTransitionID += 1
        let transitionID = sidebarBackdropCoverTransitionID
        sidebarBackdropImageView.layer.removeAllAnimations()
        sidebarBackdropGradientView.layer.removeAllAnimations()

        // banner-image.svelte: `transition-opacity duration-500`
        if alpha <= BannerImage.hiddenAlpha {
            sidebarBackdropImageView.alpha = 1
            sidebarBackdropGradientView.alpha = 1
            BannerImage.fade([sidebarBackdropCoverView], to: 1) { [weak self] in
                guard let self, self.sidebarBackdropCoverTransitionID == transitionID else { return }
                self.sidebarBackdropImageView.alpha = alpha
                self.sidebarBackdropGradientView.alpha = alpha
            }
        } else {
            sidebarBackdropImageView.alpha = alpha
            sidebarBackdropGradientView.alpha = alpha
            BannerImage.fade([sidebarBackdropCoverView], to: 0)
        }
    }

    /// Drops the banner image, and the load in flight for it, but not the fade state.
    func flushSidebarBackdropImage() {
        sidebarBackdropTask?.cancel()
        sidebarBackdropTask = nil
        sidebarBackdropURL = nil
        sidebarBackdropImageView.layer.removeAllAnimations()
        sidebarBackdropImageView.subviews.forEach { $0.removeFromSuperview() }
        sidebarBackdropImageView.image = nil
    }

    /// `bannerSrc.value = null`. `hideBanner` goes back to false, as a page sets it when it
    /// mounts, so the next banner shows in full unless its page says otherwise; leaving the
    /// alpha at zero showed a black rail whenever that page did not send one.
    func clearSidebarBackdrop() {
        flushSidebarBackdropImage()
        sidebarBackdropMediaID = nil
        sidebarBackdropAlpha = 1
        sidebarBackdropCoverTransitionID += 1
        sidebarBackdropGradientView.layer.removeAllAnimations()
        sidebarBackdropCoverView.layer.removeAllAnimations()
        sidebarBackdropImageView.alpha = 1
        sidebarBackdropImageView.transform = .identity
        sidebarBackdropGradientView.alpha = 1
        sidebarBackdropGradientView.transform = .identity
        sidebarBackdropCoverView.alpha = 0
        updateSidebarBackground()
    }

    func configureActions() {
        let handler: (HayaseSidebarRoute) -> Void = { [weak self] route in
            self?.handle(route)
        }
        sidebarList.configure(actionHandler: handler)
        mobileSidebarList.configure(actionHandler: handler)
    }

    func observeRouteChanges() {
        routeObservationID = router.observe { [weak self] route, kind, options in
            DispatchQueue.main.async {
                self?.apply(route: route, kind: kind, options: options, animated: true)
            }
        }
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(animeNavigationWillLoad),
                                               name: NSNotification.Name(Router.AnimeNavigationWillLoadNotification),
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(animeNavigationDidFail),
                                               name: NSNotification.Name(Router.AnimeNavigationFailedNotification),
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(animeNavigationWillLoad),
                                               name: NSNotification.Name(Router.ThreadNavigationWillLoadNotification),
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(animeNavigationDidFail),
                                               name: NSNotification.Name(Router.ThreadNavigationFailedNotification),
                                               object: nil)
    }

    @objc func animeNavigationWillLoad() {
        beginNavigationProgress()
    }

    @objc func animeNavigationDidFail() {
        finishNavigationProgress()
    }

    func handle(_ route: HayaseSidebarRoute) {
        if route == .donate {
            closeMobileMenu()
            if let url = URL(string: route.href) {
                UIApplication.shared.open(url)
            }
            return
        }

        guard let appRoute = route.appRoute else { return }
        router.navigate(appRoute)
    }

    func apply(route: Route, kind: Router.NavigationKind, options: Router.NavigationOptions, animated: Bool) {
        // Router notifications are delivered on the next main-queue turn.
        // Ignore an older queued destination if a redirect or a second sidebar
        // selection has already replaced it.
        guard router.currentRoute == route else { return }

        if let redirectedRoute = responsiveIndexRedirect(for: route) {
            router.replace(redirectedRoute, hostTabIndex: redirectedRoute.tabIndex, noScroll: options.noScroll)
            return
        }

        saveScrollPositionBeforeRouteChange(to: route)
        if animated {
            captureSnapshotBeforeRouteChange(to: route)
        }
        if animated {
            beginNavigationProgress()
        }
        loadRoute(route) { [weak self] preloaded in
            guard let self, self.router.currentRoute == route else { return }
            self.commit(route: route, kind: kind, options: options, animated: animated, preloaded: preloaded) { [weak self] in
                if animated {
                    self?.finishNavigationProgress()
                }
            }
        }
    }

    struct RouteLoadPayload {
        var anime: AnimeItem?
        var thread: AniListThread?
        /// A load that failed: the route shows the error page instead of its page.
        var error: Router.RouteError?
    }

    /// Nested SvelteKit layouts load concurrently. Keep the old route visible until all route-level data is ready.
    func loadRoute(_ route: Route, completion: @escaping (RouteLoadPayload) -> Void) {
        var payload = RouteLoadPayload(anime: nil, thread: nil)
        var pending = 0
        var failed = false

        // the navigation that already ran the load and failed (Router.navigateToAnime)
        if let error = router.takeRouteError(for: route) {
            payload.error = error
            completion(payload)
            return
        }

        func finishOne() {
            pending -= 1
            if pending == 0, !failed { completion(payload) }
        }

        if let id = animeID(for: route), animeRouteNeedsLoad(id, route: route) {
            pending += 1
            AnimeRouteLoader.load(id: id) { [weak self] result in
                guard let self, self.isCurrentAnimeRoute(id), !failed else { return }
                switch result {
                case .success(let item):
                    self.router.cacheAnimeItem(item)
                    payload.anime = item
                    finishOne()
                case .failure(let error):
                    NSLog("[Sidebar] Anime route preload failed: %@", error.description)
                    payload.error = Router.RouteError(status: 500, message: error.description)
                    finishOne()
                }
            }
        }

        if case .animeThread(_, let threadID) = route {
            if router.takeLoadedThreadRoute(threadID), let thread = router.cachedThread(for: threadID) {
                payload.thread = thread
            } else {
                pending += 1
                AniListForumClient.shared.threadResult(threadID: threadID) { [weak self] result in
                    guard let self, self.router.currentRoute == route, !failed else { return }
                    switch result {
                    case .success(let thread):
                        guard let thread else {
                            failed = true
                            self.finishNavigationProgress()
                            return
                        }
                        self.router.cacheThread(thread)
                        payload.thread = thread
                        finishOne()
                    case .failure(let error):
                        NSLog("[Sidebar] Thread route preload failed: %@", error.description)
                        payload.error = Router.RouteError(status: 500, message: error.description)
                        finishOne()
                    }
                }
            }
        }

        if pending == 0 { completion(payload) }
    }

    func commit(route: Route,
                        kind: Router.NavigationKind,
                        options: Router.NavigationOptions,
                        animated: Bool,
                        preloaded: RouteLoadPayload,
                        completion: @escaping () -> Void) {
        let playerToMinimize = route == .player ? nil : visiblePlayerForRouteExit()
        let usesTransition = usesViewTransition(for: route, kind: kind, animated: animated)
        // the swipe stage already showed the move
        let uiAnimated = animated && historySwipe == nil
        let navigationAnimated = uiAnimated && !usesTransition

        let performRouteChange: (Bool) -> Void = { [weak self] shouldMinimizePlayer in
            guard let self else { return }
            self.updateSelection(for: route, animated: uiAnimated)

            if shouldMinimizePlayer, let player = playerToMinimize {
                player.exitFullscreenForRouteNavigationIfNeeded()
                MiniPlayerManager.shared.minimize(
                    player,
                    removalAnimated: false,
                    fadeIn: usesTransition && !UIAccessibility.isReduceMotionEnabled
                )
            }

            let targetIndex = route.tabIndex ?? self.router.currentHostTabIndex
            if route.resetsTabStack,
               let targetIndex,
               let navigationController = self.routeControllers[safe: targetIndex] as? UINavigationController {
                navigationController.popToRootViewController(animated: false)
                self.applyRouteState(route, to: navigationController)
            }
            if let targetIndex {
                self.selectRouteController(at: targetIndex)
            }

            switch route {
            case .anime(let id):
                if let error = preloaded.error {
                    self.showErrorPage(error, for: route, animated: navigationAnimated)
                } else {
                    self.showAnimeRoute(id: id, threadID: nil, kind: kind, preloaded: preloaded.anime, preloadedThread: nil, animated: navigationAnimated)
                }
            case .animeThread(let animeID, let threadID):
                if let error = preloaded.error {
                    self.showErrorPage(error, for: route, animated: navigationAnimated)
                } else {
                    self.showAnimeRoute(id: animeID, threadID: threadID, kind: kind, preloaded: preloaded.anime, preloadedThread: preloaded.thread, animated: navigationAnimated)
                }
            case .player:
                self.showPlayerRoute(animated: uiAnimated)
            case .license:
                self.showLicenseRoute(animated: navigationAnimated)
            case .debug:
                self.showDebugRoute(animated: navigationAnimated)
            default:
                break
            }

            self.hideHostedNavigationBars()
            self.updateSidebarBackground()
            // banner-image.svelte drops the banner when navigation ends anywhere but Home or an
            // anime page, so the next one loads in afresh.
            if !route.keepsBanner { self.clearSidebarBackdrop() }
            self.lastAppliedRoute = route
            self.restoreScrollPositionIfNeeded(for: route, kind: kind, noScroll: options.noScroll)
            self.closeMobileMenu(animated: uiAnimated)
            completion()
        }

        // player.svelte awaits fullscreen exit before route commit; dismiss first so UIKit stack changes never overlap.
        if let player = playerToMinimize,
           player.navigationController?.viewControllers.contains(where: { $0 === player }) != true,
           player.presentingViewController != nil {
            player.exitFullscreenForRouteNavigationIfNeeded()
            player.isMinimizing = true
            // The web skips a view transition when leaving mobile fullscreen.
            // Do not add UIKit's modal cross-dissolve to that route change.
            player.dismiss(animated: false) {
                MiniPlayerManager.shared.minimize(player, removalAnimated: false)
                performRouteChange(false)
            }
            return
        }

        if usesTransition {
            routeTransition.perform(in: view) { performRouteChange(true) }
        } else {
            routeTransition.finish()
            performRouteChange(true)
        }
    }

    func visiblePlayerForRouteExit() -> VideoPlayerViewController? {
        if let player = topVisibleHostedController() as? VideoPlayerViewController {
            return player
        }
        guard !MiniPlayerManager.shared.isActive,
              let player = router.cachedPlayer(),
              player.viewIfLoaded?.window != nil else { return nil }
        return player
    }

    func applyRouteState(_ route: Route, to navigationController: UINavigationController) {
        switch route {
        case .search(let state):
            (navigationController.viewControllers.first as? SearchViewController)?.applyRouteState(state)
        case .w2g(let id):
            (navigationController.viewControllers.first as? W2GViewController)?.applyRoute(id: id)
        case .client(let clientRoute):
            (navigationController.viewControllers.first as? DownloadsViewController)?.applyRoute(clientRoute)
        case .settings(let settingsRoute):
            (navigationController.viewControllers.first as? SettingsViewController)?.applyRoute(settingsRoute)
        case .profile:
            (navigationController.viewControllers.first as? SettingsViewController)?.openAccountsTab()
        default:
            break
        }
    }

    func showAnimeRoute(id: Int,
                                threadID: Int?,
                                kind: Router.NavigationKind,
                                preloaded: AnimeItem?,
                                preloadedThread: AniListThread?,
                                animated: Bool) {
        guard let nav = tabHost.selectedViewController as? UINavigationController else { return }

        if let preloadedThread { router.cacheThread(preloadedThread) }

        if let detail = nav.topViewController as? AnimeDetailViewController,
           detail.routeAnimeID == id {
            detail.applyEmbeddedThreadRoute(threadID: threadID, title: nil)
            return
        }

        if let detail = nav.viewControllers.compactMap({ $0 as? AnimeDetailViewController }).last,
           detail.routeAnimeID == id {
            if threadID == nil,
               let sourceDetail = nav.topViewController as? AnimeDetailViewController,
               sourceDetail !== detail {
                detail.inheritPageTabState(from: sourceDetail)
            }
            nav.popToViewController(detail, animated: false)
            detail.applyEmbeddedThreadRoute(threadID: threadID, title: nil)
            return
        }

        if let item = preloaded ?? router.cachedFullAnimeItem(for: id) {
            pushAnimeDetail(item: item, threadID: threadID, in: nav, animated: animated)
        }
    }

    func animeID(for route: Route) -> Int? {
        switch route {
        case .anime(let id): return id
        case .animeThread(let animeID, _): return animeID
        default: return nil
        }
    }

    func animeRouteNeedsLoad(_ id: Int, route: Route) -> Bool {
        if router.takeLoadedAnimeRoute(id) { return false }
        guard let nav = hostNavigationController(for: route) else { return false }
        let detail = nav.viewControllers.compactMap { $0 as? AnimeDetailViewController }.last
        return detail?.routeAnimeID != id
    }

    func hostNavigationController(for route: Route) -> UINavigationController? {
        guard let index = route.tabIndex ?? router.currentHostTabIndex else {
            return tabHost.selectedViewController as? UINavigationController
        }
        guard routeControllers.indices.contains(index) else { return nil }
        return routeControllers[index] as? UINavigationController
    }

    func isCurrentAnimeRoute(_ id: Int) -> Bool {
        switch router.currentRoute {
        case .anime(let currentID), .animeThread(let currentID, _):
            return currentID == id
        default:
            return false
        }
    }

    func pushAnimeDetail(item: AnimeItem,
                                 threadID: Int?,
                                 in navigationController: UINavigationController,
                                 animated: Bool) {
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        guard let detail = storyboard.instantiateViewController(withIdentifier: "AnimeDetailVC") as? AnimeDetailViewController else { return }
        detail.animeItem = item
        if threadID == nil, let sourceDetail = navigationController.topViewController as? AnimeDetailViewController {
            detail.inheritPageTabState(from: sourceDetail)
        }
        navigationController.pushViewController(detail, animated: animated)
        detail.applyEmbeddedThreadRoute(threadID: threadID, title: nil)
        restoreScrollPositionIfNeeded(for: router.currentRoute, kind: .push, noScroll: false)
    }

    /// `routes/app/+error.svelte`: the page of a route whose load failed.
    func showErrorPage(_ error: Router.RouteError, for route: Route, animated: Bool) {
        guard let nav = hostNavigationController(for: route) else { return }
        nav.pushViewController(ErrorPageViewController(status: error.status, message: error.message), animated: animated)
    }

    /// `routes/app/debug/+page.svelte`
    func showDebugRoute(animated: Bool) {
        guard let nav = hostNavigationController(for: .debug) else { return }
        if nav.topViewController is HayaseDebugViewController { return }
        nav.pushViewController(HayaseDebugViewController(), animated: animated)
    }

    /// `routes/app/license/+page.svelte`
    func showLicenseRoute(animated: Bool) {
        guard let nav = hostNavigationController(for: .license) else { return }
        if nav.topViewController is LicensePageViewController { return }
        nav.pushViewController(LicensePageViewController(), animated: animated)
    }

    func showPlayerRoute(animated: Bool) {
        guard let player = router.cachedPlayer() else {
            MiniPlayerManager.shared.restore()
            return
        }

        if topVisibleHostedController() === player { return }

        if MiniPlayerManager.shared.isActive, MiniPlayerManager.shared.activePlayer === player {
            MiniPlayerManager.shared.restore()
            return
        }

        if let nav = tabHost.selectedViewController as? UINavigationController {
            if nav.topViewController === player { return }
            if nav.viewControllers.contains(where: { $0 === player }) {
                nav.popToViewController(player, animated: false)
                return
            }
        }

        player.isMinimizing = false
        let presenter = topVisibleHostedController() ?? tabHost
        presenter.presentHayasePlayer(player, animated: false)
    }

    func updateSelection(for route: Route, animated: Bool) {
        sidebarList.setSelectedRoute(route, animated: animated)
        mobileSidebarList.setSelectedRoute(route, animated: animated)
        updateSidebarBackground()
    }

    func updateLayoutForCurrentWidth() {
        hideNativeTabNavigation()
        let isDesktop = view.bounds.width >= 768  // Tailwind md = 48rem = 768px
        let modeChanged = isDesktopMode != isDesktop
        isDesktopMode = isDesktop
        applyPlayerShellChrome(isDesktop: isDesktop)
        guard modeChanged else { return }
        closeMobileMenu(animated: false)
        updateSidebarBackground()

        if responsiveIndexRedirect(for: router.currentRoute) != nil {
            DispatchQueue.main.async { [weak self] in
                guard let self,
                      let redirectedRoute = self.responsiveIndexRedirect(for: self.router.currentRoute) else { return }
                self.router.replace(redirectedRoute, hostTabIndex: redirectedRoute.tabIndex)
            }
        }
    }

    func setPlayerFullscreenActive(_ active: Bool) {
        guard playerFullscreenActive != active else { return }
        playerFullscreenActive = active
        if active { closeMobileMenu(animated: false) }
        applyPlayerShellChrome(isDesktop: view.bounds.width >= 768)
        UIView.performWithoutAnimation {
            view.layoutIfNeeded()
        }
    }

    func applyPlayerShellChrome(isDesktop: Bool) {
        let hidesShellChrome = playerFullscreenActive
        sidebarList.superview?.isHidden = !isDesktop || hidesShellChrome
        mobileLauncher.isHidden = isDesktop || hidesShellChrome
        sidebarWidthConstraint?.constant = isDesktop && !hidesShellChrome ? 56 : 0
    }

    func responsiveIndexRedirect(for route: Route) -> Route? {
        guard view.bounds.width >= 768 else { return nil }  // Tailwind md = 48rem = 768px
        switch route {
        case .client(.root):
            return .client(.overview)
        case .settings(.root):
            return .settings(.player)
        default:
            return nil
        }
    }

    func updateSidebarBackground() {
        let isBannerRoute = visibleBannerBackdropRoute() != nil
        let hasBackdrop = sidebarBackdropImageView.image != nil || sidebarBackdropURL != nil
        let showsBannerBackdrop = isBannerRoute && hasBackdrop

        // app/+layout.svelte and sidebarlist.svelte both render BannerImage at
        // absolute top-left. Keep the rail transparent on banner routes so the
        // clipped w-14 sidebar slice stays attached to the page banner.
        sidebarContainer.backgroundColor = showsBannerBackdrop ? .clear : UIColor.HayaseTheme.background
        sidebarBackdropImageView.isHidden = !showsBannerBackdrop
        sidebarBackdropGradientView.isHidden = !showsBannerBackdrop
        sidebarBackdropCoverView.isHidden = !showsBannerBackdrop
        sidebarBackdropGradientView.setCompact(view.bounds.width < 768)
        sidebarList.backgroundColor = .clear
    }

    /// The banner route the router is on, if any: the interface's `$page.route` test.
    var currentBannerRoute: String? {
        switch router.currentRoute {
        case .home: return Self.homeBannerBackdropHomeRoute
        case .anime, .animeThread: return Self.homeBannerBackdropAnimeRoute
        default: return nil
        }
    }

    func visibleBannerBackdropRoute() -> String? {
        let topController = topVisibleHostedController()
        if topController is HomeViewController { return Self.homeBannerBackdropHomeRoute }
        if topController is AnimeDetailViewController { return Self.homeBannerBackdropAnimeRoute }
        return nil
    }

    func topVisibleHostedController() -> UIViewController? {
        topVisibleController(from: tabHost.selectedViewController)
    }

    func topVisibleController(from controller: UIViewController?) -> UIViewController? {
        guard let controller else { return nil }
        if let presented = controller.presentedViewController, !presented.isBeingDismissed {
            return topVisibleController(from: presented)
        }
        if let nav = controller as? UINavigationController {
            return topVisibleController(from: nav.topViewController)
        }
        return controller
    }

    func toggleMobileMenu() {
        isMobileMenuOpen.toggle()
        mobileLauncherWidthConstraint?.constant = isMobileMenuOpen ? 176 : 64
        mobileLauncherHeightConstraint?.constant = isMobileMenuOpen ? 176 : 64
        let icon = isMobileMenuOpen ? "x" : "menu"
        mobileToggleButton.setSidebarImage(UIImage.hayaseIcon(icon), pointSize: 18, renderingMode: .alwaysTemplate)
        UIViewPropertyAnimator(duration: 0.15,
                               controlPoint1: CGPoint(x: 0.4, y: 0),
                               controlPoint2: CGPoint(x: 0.2, y: 1)) {  // Tailwind transition: 150ms ease
            self.view.layoutIfNeeded()
        }.startAnimation()
    }

    func closeMobileMenu(animated: Bool = true) {
        guard isMobileMenuOpen else { return }
        isMobileMenuOpen = false
        mobileLauncherWidthConstraint?.constant = 64
        mobileLauncherHeightConstraint?.constant = 64
        mobileToggleButton.setSidebarImage(UIImage.hayaseIcon("menu"), pointSize: 18, renderingMode: .alwaysTemplate)
        let changes = { self.view.layoutIfNeeded() }
        if animated {
            UIViewPropertyAnimator(duration: 0.15,
                                   controlPoint1: CGPoint(x: 0.4, y: 0),
                                   controlPoint2: CGPoint(x: 0.2, y: 1),
                                   animations: changes).startAnimation()  // Tailwind transition: 150ms ease
        } else {
            changes()
        }
    }

    @objc func handleOutsideTap(_ gesture: UITapGestureRecognizer) {
        guard isMobileMenuOpen else { return }
        let point = gesture.location(in: view)
        if !mobileLauncher.frame.contains(point) {
            closeMobileMenu()
        }
    }

    deinit {
        sidebarBackdropTask?.cancel()
        if let routeObservationID {
            router.removeObserver(routeObservationID)
        }
        NotificationCenter.default.removeObserver(self)
    }
}

extension HayaseSidebarController: UITabBarControllerDelegate, UIGestureRecognizerDelegate {
    func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
        hideHostedNavigationBars()
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let panGesture = gestureRecognizer as? UIPanGestureRecognizer else { return true }

        let start = panGesture.location(in: view)
        let velocity = panGesture.velocity(in: view)
        let edgeWidth: CGFloat = 32
        let isNearBackEdge = start.x <= edgeWidth
        let isNearForwardEdge = start.x >= view.bounds.width - edgeWidth
        guard isNearBackEdge || isNearForwardEdge else { return false }
        if abs(velocity.y) > abs(velocity.x) * 1.6 { return false }

        // Native pushed tool screens keep their local stack gesture. Main app
        // route history is only handled here when the visible stack is route-owned.
        if let nav = tabHost.selectedViewController as? UINavigationController,
           nav.viewControllers.count > 1,
           !isCurrentRouteOwnedByRouter {
            return false
        }

        if isNearBackEdge, router.canGoBack {
            activeHistorySwipeDirection = .back
            return true
        }
        if isNearForwardEdge, router.canGoForward {
            activeHistorySwipeDirection = .forward
            return true
        }

        activeHistorySwipeDirection = nil
        return false
    }

    // Buttons near the screen edge stay tappable: the history swipe never competes for a touch that lands on a control.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard gestureRecognizer is UIPanGestureRecognizer else { return true }
        if MiniPlayerManager.shared.containsMiniPlayer(touch.view) { return false }
        var candidate: UIView? = touch.view
        while let view = candidate {
            if view is UIControl { return false }
            candidate = view.superview
        }
        return true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        gestureRecognizer is UIPanGestureRecognizer
    }

    var isCurrentRouteOwnedByRouter: Bool {
        switch router.currentRoute {
        case .anime, .animeThread, .player, .license, .debug:
            return true
        default:
            return false
        }
    }
}

