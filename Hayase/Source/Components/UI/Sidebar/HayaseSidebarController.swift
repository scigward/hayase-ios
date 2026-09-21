//
//  HayaseSidebarController.swift
//  Hayase
//
//  Made by scigward.
//
//  Mirrors: src/routes/app/+layout.svelte, src/routes/+layout.svelte (onNavigate, ProgressBar), src/lib/components/ui/sidebar/sidebar.svelte, src/routes/app/anime/[id]/+page.svelte (preserved tab state)
//

import UIKit

// MARK: - HayaseSidebarController

final class HayaseSidebarController: UIViewController {
    private static let homeBannerBackdropDidChange = Notification.Name("HayaseHomeBannerBackdropDidChange")
    private static let homeBannerBackdropURLKey = "url"
    private static let homeBannerBackdropAlphaKey = "alpha"
    private static let homeBannerBackdropScrollOffsetKey = "scrollOffset"
    private static let homeBannerBackdropHeightKey = "height"
    private static let homeBannerBackdropRouteKey = "route"
    private static let homeBannerBackdropHomeRoute = "home"
    private static let homeBannerBackdropAnimeRoute = "anime"
    private static let homeBannerBackdropPlayerRoute = "player"

    private let tabHost: UITabBarController
    private let router = Router.shared
    private let sidebarList = HayaseSidebarListView(mode: .desktop)
    private let mobileSidebarList = HayaseSidebarListView(mode: .mobile)
    private let contentContainer = UIView()
    private static let routeSnapshotLimit = 10

    private var progressWindow: HayaseProgressBarWindow?
    private let routeTransition = HayaseRouteTransition()
    private let mobileLauncher = UIView()
    private let mobileGridContainer = UIView()
    private let mobileToggleButton = UIButton(type: .system)
    private let sidebarContainer = UIView()
    private let sidebarBackdropImageView = UIImageView()
    private let sidebarBackdropGradientView = SidebarBackdropGradientView()
    private let sidebarBackdropCoverView = UIView()
    private var sidebarBackdropTask: URLSessionDataTask?
    private var sidebarBackdropURL: String?
    private var sidebarBackdropAlpha: CGFloat = 0
    private var sidebarBackdropCoverTransitionID = 0
    private var sidebarBackdropHeightConstraint: NSLayoutConstraint?
    private var sidebarWidthConstraint: NSLayoutConstraint?
    private var mobileLauncherWidthConstraint: NSLayoutConstraint?
    private var mobileLauncherHeightConstraint: NSLayoutConstraint?
    private var isMobileMenuOpen = false
    private var isDesktopMode: Bool?
    private var selectedIndexObservation: NSKeyValueObservation?
    private var isApplyingRoute = false
    private var routeObservationID: UUID?
    private var activeHistorySwipeDirection: HayaseHistorySwipe.Direction?
    private var historySwipe: HayaseHistorySwipe?
    private var routeSnapshots: [Route: UIView] = [:]
    private var routeSnapshotOrder: [Route] = []
    private var lastAppliedRoute: Route?
    private var routeScrollPositions: [Route: CGPoint] = [:]
    private var isNavigationLoading = false

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
        router.reset(to: Route(tabIndex: tabHost.selectedIndex) ?? .home, hostTabIndex: tabHost.selectedIndex)
        setupContentHost()
        setupDesktopSidebar()
        setupMobileSidebar()
        configureActions()
        observeBannerBackdrop()
        observeTabSelection()
        observeRouteChanges()
        apply(route: router.currentRoute, kind: .replace, options: .init(), animated: false)
        updateLayoutForCurrentWidth()
    }

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

    @objc private func routeBackCommand() {
        router.back()
    }

    @objc private func routeForwardCommand() {
        router.forward()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        hideHostedNavigationBars()
        updateSidebarBackground()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
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
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        hideHostedNavigationBars()
        updateLayoutForCurrentWidth()
    }

    private func installProgressBarIfNeeded() {
        guard progressWindow == nil, let scene = view.window?.windowScene else { return }
        progressWindow = HayaseProgressBarWindow(windowScene: scene)
    }

    private func setupContentHost() {
        hideNativeTabNavigation()
        tabHost.delegate = self

        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.backgroundColor = UIColor.HayaseTheme.background
        view.addSubview(contentContainer)

        addChild(tabHost)
        tabHost.view.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(tabHost.view)
        NSLayoutConstraint.activate([
            contentContainer.topAnchor.constraint(equalTo: view.topAnchor),
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

    private func installRouteHistoryGestures() {
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handleRouteHistoryPan(_:)))
        panGesture.maximumNumberOfTouches = 1
        panGesture.cancelsTouchesInView = false
        panGesture.delegate = self
        view.addGestureRecognizer(panGesture)
    }

    @objc private func handleRouteHistoryPan(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: view)
        switch gesture.state {
        case .began:
            beginHistorySwipe()
        case .changed:
            guard let swipe = historySwipe else { return }
            let dragged = swipe.direction == .back ? translation.x : -translation.x
            swipe.update(progress: max(dragged, 0) / view.bounds.width)
        case .ended:
            finishHistorySwipe(translation: translation, velocity: gesture.velocity(in: view))
        case .cancelled, .failed:
            historySwipe?.finish(completing: false) { [weak self] in
                self?.endHistorySwipe()
            }
            activeHistorySwipeDirection = nil
        default:
            break
        }
    }

    private func beginHistorySwipe() {
        guard historySwipe == nil,
              let direction = activeHistorySwipeDirection,
              let route = direction == .back ? router.previousRoute : router.nextRoute,
              let destination = routeSnapshots[route],
              destination.bounds.size == view.bounds.size,
              let current = view.snapshotView(afterScreenUpdates: false) else { return }
        historySwipe = HayaseHistorySwipe(direction: direction, current: current, destination: destination, host: view)
    }

    private func finishHistorySwipe(translation: CGPoint, velocity: CGPoint) {
        let direction = activeHistorySwipeDirection
        activeHistorySwipeDirection = nil
        let commits: Bool
        switch direction {
        case .back:
            commits = translation.x > 60 || velocity.x > 400
        case .forward:
            commits = translation.x < -60 || velocity.x < -400
        case .none:
            commits = false
        }
        guard let swipe = historySwipe else {
            if commits {
                if direction == .back { router.back() } else { router.forward() }
            }
            return
        }
        swipe.finish(completing: commits) { [weak self] in
            guard let self else { return }
            if commits {
                self.completeHistorySwipe(swipe)
            } else {
                self.endHistorySwipe()
            }
        }
    }

    private func completeHistorySwipe(_ swipe: HayaseHistorySwipe) {
        if let route = lastAppliedRoute {
            storeSnapshot(swipe.current, for: route)
        }
        let moved = swipe.direction == .back ? router.back() : router.forward()
        if !moved {
            endHistorySwipe()
        }
    }

    private func endHistorySwipe() {
        guard let swipe = historySwipe else { return }
        historySwipe = nil
        view.layoutIfNeeded()
        DispatchQueue.main.async {
            swipe.remove()
        }
    }

    private func captureSnapshotBeforeRouteChange(to route: Route) {
        guard historySwipe == nil, !isMobileMenuOpen,
              let previousRoute = lastAppliedRoute, previousRoute != route,
              let snapshot = view.snapshotView(afterScreenUpdates: false) else { return }
        storeSnapshot(snapshot, for: previousRoute)
    }

    private func storeSnapshot(_ snapshot: UIView, for route: Route) {
        snapshot.frame = view.bounds
        routeSnapshots[route] = snapshot
        routeSnapshotOrder.removeAll { $0 == route }
        routeSnapshotOrder.append(route)
        while routeSnapshotOrder.count > Self.routeSnapshotLimit {
            routeSnapshots.removeValue(forKey: routeSnapshotOrder.removeFirst())
        }
    }

    private func installInterfaceRoutes() {
        guard let viewControllers = tabHost.viewControllers else { return }
        tabHost.setViewControllers(Self.interfaceRoutes(from: viewControllers), animated: false)
    }

    private static func interfaceRoutes(from viewControllers: [UIViewController]) -> [UIViewController] {
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

    private func hideHostedNavigationBars() {
        hideNativeTabNavigation()
        hideNavigationChrome(in: tabHost)
    }

    private func hideNativeTabNavigation() {
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

    private func hideNavigationChrome(in viewController: UIViewController?) {
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

    private func setupDesktopSidebar() {
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

        sidebarWidthConstraint = sidebarContainer.widthAnchor.constraint(equalToConstant: 56)
        sidebarBackdropHeightConstraint = sidebarBackdropImageView.heightAnchor.constraint(equalToConstant: 368)
        NSLayoutConstraint.activate([
            sidebarContainer.topAnchor.constraint(equalTo: view.topAnchor),
            sidebarContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            sidebarContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            sidebarWidthConstraint!,
            contentContainer.leadingAnchor.constraint(equalTo: sidebarContainer.trailingAnchor),

            // sidebarlist.svelte renders <BannerImage class='w-14'>. The
            // inner image is still w-screen; the rail only clips the left 56pt.
            sidebarBackdropImageView.topAnchor.constraint(equalTo: sidebarContainer.topAnchor),
            sidebarBackdropImageView.leadingAnchor.constraint(equalTo: sidebarContainer.leadingAnchor),
            sidebarBackdropImageView.widthAnchor.constraint(equalTo: view.widthAnchor),
            // Updated in updateSidebarBackground(): web BannerImage is 90vh on
            // home at md+ widths and h-[23rem] on anime/detail routes.
            sidebarBackdropHeightConstraint!,

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

    private func setupMobileSidebar() {
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

        mobileToggleButton.translatesAutoresizingMaskIntoConstraints = false
        mobileToggleButton.tintColor = UIColor.HayaseTheme.foreground
        mobileToggleButton.setImage(UIImage.hayaseIcon("menu"), for: .normal)
        mobileToggleButton.imageEdgeInsets = UIEdgeInsets(top: 15, left: 15, bottom: 15, right: 15)
        mobileToggleButton.addTarget(self, action: #selector(toggleMobileMenu), for: .touchUpInside)
        mobileGridContainer.addSubview(mobileToggleButton)

        mobileLauncherWidthConstraint = mobileLauncher.widthAnchor.constraint(equalToConstant: 64)
        mobileLauncherHeightConstraint = mobileLauncher.heightAnchor.constraint(equalToConstant: 64)
        NSLayoutConstraint.activate([
            mobileLauncher.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),  // left-4 = 16px
            mobileLauncher.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16),  // bottom-4 = 16px
            mobileLauncherWidthConstraint!,
            mobileLauncherHeightConstraint!,

            mobileGridContainer.widthAnchor.constraint(equalToConstant: 160),
            mobileGridContainer.heightAnchor.constraint(equalToConstant: 160),
            mobileGridContainer.trailingAnchor.constraint(equalTo: mobileLauncher.trailingAnchor, constant: -8),
            mobileGridContainer.bottomAnchor.constraint(equalTo: mobileLauncher.bottomAnchor, constant: -8),

            mobileSidebarList.topAnchor.constraint(equalTo: mobileGridContainer.topAnchor),
            mobileSidebarList.leadingAnchor.constraint(equalTo: mobileGridContainer.leadingAnchor),
            mobileSidebarList.trailingAnchor.constraint(equalTo: mobileGridContainer.trailingAnchor),
            mobileSidebarList.bottomAnchor.constraint(equalTo: mobileGridContainer.bottomAnchor),

            mobileToggleButton.widthAnchor.constraint(equalToConstant: 48),
            mobileToggleButton.heightAnchor.constraint(equalToConstant: 48),
            mobileToggleButton.trailingAnchor.constraint(equalTo: mobileGridContainer.trailingAnchor),
            mobileToggleButton.bottomAnchor.constraint(equalTo: mobileGridContainer.bottomAnchor),
        ])

        let outsideTap = UITapGestureRecognizer(target: self, action: #selector(handleOutsideTap(_:)))
        outsideTap.cancelsTouchesInView = false
        view.addGestureRecognizer(outsideTap)
    }

    private func observeBannerBackdrop() {
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(homeBannerBackdropDidChange(_:)),
                                               name: Self.homeBannerBackdropDidChange,
                                               object: nil)
    }

    @objc private func homeBannerBackdropDidChange(_ notification: Notification) {
        let userInfo = notification.userInfo ?? [:]

        // The page banner is route-owned. Ignore late async image/fade updates
        // from a page that is no longer visible, otherwise the sidebar can keep
        // a stale detail/home backdrop until the app restarts.
        let route = userInfo[Self.homeBannerBackdropRouteKey] as? String
        if let route = route {
            if route == Self.homeBannerBackdropPlayerRoute {
                clearSidebarBackdrop()
                return
            }
            if let visibleRoute = visibleBannerBackdropRoute(), route != visibleRoute {
                return
            }
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

        updateSidebarBackground()

        guard let urlString = userInfo[Self.homeBannerBackdropURLKey] as? String,
              urlString != sidebarBackdropURL,
              let url = URL(string: urlString) else { return }

        sidebarBackdropURL = urlString
        sidebarBackdropTask?.cancel()

        if let cached = SharedImageCache.shared.object(forKey: urlString as NSString) {
            sidebarBackdropImageView.image = cached
            updateSidebarBackground()
            return
        }

        sidebarBackdropTask = URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data, let image = UIImage(data: data) else { return }
            SharedImageCache.shared.setObject(image, forKey: urlString as NSString)
            DispatchQueue.main.async {
                guard self?.sidebarBackdropURL == urlString else { return }
                UIView.transition(with: self?.sidebarBackdropImageView ?? UIImageView(),
                                  duration: 0.3,
                                  options: .transitionCrossDissolve,
                                  animations: { self?.sidebarBackdropImageView.image = image })
                self?.updateSidebarBackground()
            }
        }
        sidebarBackdropTask?.resume()
    }

    private func applySidebarBackdropScrollOffset(_ scrollOffset: CGFloat) {
        // Interface mounts the sidebar BannerImage at absolute top-left too.
        // The 56pt rail clips the full-width image; it never scroll-translates.
        sidebarBackdropImageView.transform = .identity
        sidebarBackdropGradientView.transform = .identity
    }

    private func transitionSidebarBackdrop(to alpha: CGFloat) {
        guard abs(alpha - sidebarBackdropAlpha) > 0.01 else { return }

        sidebarBackdropAlpha = alpha
        sidebarBackdropCoverTransitionID += 1
        let transitionID = sidebarBackdropCoverTransitionID
        sidebarBackdropImageView.layer.removeAllAnimations()
        sidebarBackdropGradientView.layer.removeAllAnimations()
        sidebarBackdropCoverView.layer.removeAllAnimations()

        if alpha <= 0.05 {
            sidebarBackdropImageView.alpha = 1
            sidebarBackdropGradientView.alpha = 1
            UIView.animate(withDuration: 0.3,
                           delay: 0,
                           options: [.allowUserInteraction, .beginFromCurrentState],
                           animations: {
                self.sidebarBackdropCoverView.alpha = 1
            }, completion: { [weak self] _ in
                guard let self, self.sidebarBackdropCoverTransitionID == transitionID else { return }
                self.sidebarBackdropImageView.alpha = alpha
                self.sidebarBackdropGradientView.alpha = alpha
            })
        } else {
            sidebarBackdropImageView.alpha = alpha
            sidebarBackdropGradientView.alpha = alpha
            UIView.animate(withDuration: 0.3,
                           delay: 0,
                           options: [.allowUserInteraction, .beginFromCurrentState]) {
                self.sidebarBackdropCoverView.alpha = 0
            }
        }
    }

    private func clearSidebarBackdrop() {
        sidebarBackdropTask?.cancel()
        sidebarBackdropTask = nil
        sidebarBackdropURL = nil
        sidebarBackdropAlpha = 0
        sidebarBackdropCoverTransitionID += 1
        sidebarBackdropImageView.layer.removeAllAnimations()
        sidebarBackdropGradientView.layer.removeAllAnimations()
        sidebarBackdropCoverView.layer.removeAllAnimations()
        sidebarBackdropImageView.image = nil
        sidebarBackdropImageView.alpha = 0
        sidebarBackdropImageView.transform = .identity
        sidebarBackdropGradientView.alpha = 0
        sidebarBackdropGradientView.transform = .identity
        sidebarBackdropCoverView.alpha = 0
        updateSidebarBackground()
    }

    private func configureActions() {
        let handler: (HayaseSidebarRoute) -> Void = { [weak self] route in
            self?.handle(route)
        }
        sidebarList.configure(actionHandler: handler)
        mobileSidebarList.configure(actionHandler: handler)
    }

    private func observeRouteChanges() {
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

    private func observeTabSelection() {
        selectedIndexObservation = tabHost.observe(\.selectedIndex, options: [.new]) { [weak self] tab, _ in
            DispatchQueue.main.async {
                guard let self,
                      !self.isApplyingRoute,
                      self.router.currentRoute.tabIndex != tab.selectedIndex,
                      let route = Route(tabIndex: tab.selectedIndex) else { return }
                self.router.sync(route, hostTabIndex: tab.selectedIndex)
            }
        }
    }

    @objc private func animeNavigationWillLoad() {
        beginNavigationProgress()
    }

    @objc private func animeNavigationDidFail() {
        finishNavigationProgress()
    }

    private func beginNavigationProgress() {
        guard !isNavigationLoading else { return }
        isNavigationLoading = true
        progressWindow?.bar.navigationWillBegin()
    }

    private func finishNavigationProgress() {
        isNavigationLoading = false
        progressWindow?.bar.navigationDidFinish()
        endHistorySwipe()
    }

    private func handle(_ route: HayaseSidebarRoute) {
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

    private func apply(route: Route, kind: Router.NavigationKind, options: Router.NavigationOptions, animated: Bool) {
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

    private struct RouteLoadPayload {
        var anime: AnimeItem?
        var thread: AniListThread?
    }

    /// Nested SvelteKit layouts load concurrently. Keep the old route visible until all route-level data is ready.
    private func loadRoute(_ route: Route, completion: @escaping (RouteLoadPayload) -> Void) {
        var payload = RouteLoadPayload(anime: nil, thread: nil)
        var pending = 0
        var failed = false

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
                    failed = true
                    NSLog("[Sidebar] Anime route preload failed: %@", error.description)
                    self.finishNavigationProgress()
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
                        failed = true
                        NSLog("[Sidebar] Thread route preload failed: %@", error.description)
                        self.finishNavigationProgress()
                    }
                }
            }
        }

        if pending == 0 { completion(payload) }
    }

    private func commit(route: Route,
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
               let navigationController = self.tabHost.viewControllers?[safe: targetIndex] as? UINavigationController {
                navigationController.popToRootViewController(animated: false)
                self.applyRouteState(route, to: navigationController)
            }
            if let targetIndex {
                self.isApplyingRoute = true
                if self.tabHost.selectedIndex != targetIndex {
                    self.tabHost.selectedIndex = targetIndex
                }
                self.isApplyingRoute = false
            }

            switch route {
            case .anime(let id):
                self.showAnimeRoute(id: id, threadID: nil, kind: kind, preloaded: preloaded.anime, preloadedThread: nil, animated: navigationAnimated)
            case .animeThread(let animeID, let threadID):
                self.showAnimeRoute(id: animeID, threadID: threadID, kind: kind, preloaded: preloaded.anime, preloadedThread: preloaded.thread, animated: navigationAnimated)
            case .player:
                self.showPlayerRoute(animated: uiAnimated)
            default:
                break
            }

            self.hideHostedNavigationBars()
            self.updateSidebarBackground()
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
            routeTransition.perform(in: contentContainer) { performRouteChange(true) }
        } else {
            performRouteChange(true)
        }
    }

    private func visiblePlayerForRouteExit() -> VideoPlayerViewController? {
        if let player = topVisibleHostedController() as? VideoPlayerViewController {
            return player
        }
        guard !MiniPlayerManager.shared.isActive,
              let player = router.cachedPlayer(),
              player.viewIfLoaded?.window != nil else { return nil }
        return player
    }

    private func usesViewTransition(for route: Route, kind: Router.NavigationKind, animated: Bool) -> Bool {
        // iOS runs its own back/forward animation, and entering the mobile player skips it.
        // SvelteKit still runs onNavigate for goto(..., { replaceState: true }).
        guard animated, (kind == .push || kind == .replace), route != .player else { return false }
        guard let player = visiblePlayerForRouteExit() else { return true }
        // Root +layout.svelte skips startViewTransition whenever fullscreenElement is set.
        // Phones force the player fullscreen; iPad can enter the same state manually.
        return UIDevice.current.userInterfaceIdiom != .phone && !player.isFullscreenForRouteNavigation
    }

    private func saveScrollPositionBeforeRouteChange(to route: Route) {
        guard let previousRoute = lastAppliedRoute, previousRoute != route,
              let offset = RouteScrollRestoration.capture(from: topVisibleHostedController()) else { return }
        routeScrollPositions[previousRoute] = offset
    }

    private func restoreScrollPositionIfNeeded(for route: Route, kind: Router.NavigationKind, noScroll: Bool) {
        switch kind {
        case .back, .forward:
            RouteScrollRestoration.restore(routeScrollPositions[route], in: topVisibleHostedController())
        case .push, .replace, .sync:
            guard !noScroll else { return }
            RouteScrollRestoration.scrollToTop(in: topVisibleHostedController())
        }
    }

    private func applyRouteState(_ route: Route, to navigationController: UINavigationController) {
        switch route {
        case .search(let state):
            (navigationController.viewControllers.first as? SearchViewController)?.applyRouteState(state)
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

    private func showAnimeRoute(id: Int,
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

    private func animeID(for route: Route) -> Int? {
        switch route {
        case .anime(let id): return id
        case .animeThread(let animeID, _): return animeID
        default: return nil
        }
    }

    private func animeRouteNeedsLoad(_ id: Int, route: Route) -> Bool {
        if router.takeLoadedAnimeRoute(id) { return false }
        guard let nav = hostNavigationController(for: route) else { return false }
        let detail = nav.viewControllers.compactMap { $0 as? AnimeDetailViewController }.last
        return detail?.routeAnimeID != id
    }

    private func hostNavigationController(for route: Route) -> UINavigationController? {
        guard let index = route.tabIndex ?? router.currentHostTabIndex else {
            return tabHost.selectedViewController as? UINavigationController
        }
        guard let viewControllers = tabHost.viewControllers,
              viewControllers.indices.contains(index) else { return nil }
        return viewControllers[index] as? UINavigationController
    }

    private func isCurrentAnimeRoute(_ id: Int) -> Bool {
        switch router.currentRoute {
        case .anime(let currentID), .animeThread(let currentID, _):
            return currentID == id
        default:
            return false
        }
    }

    private func pushAnimeDetail(item: AnimeItem,
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

    private func showPlayerRoute(animated: Bool) {
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

    private func updateSelection(for route: Route, animated: Bool) {
        sidebarList.setSelectedRoute(route, animated: animated)
        mobileSidebarList.setSelectedRoute(route, animated: animated)
        updateSidebarBackground()
    }

    private func updateLayoutForCurrentWidth() {
        hideNativeTabNavigation()
        let isDesktop = view.bounds.width >= 768  // Tailwind md = 48rem = 768px
        guard isDesktopMode != isDesktop else { return }
        isDesktopMode = isDesktop
        sidebarList.superview?.isHidden = !isDesktop
        mobileLauncher.isHidden = isDesktop
        sidebarWidthConstraint?.constant = isDesktop ? 56 : 0
        if !isDesktop {
            closeMobileMenu(animated: false)
        }
        updateSidebarBackground()

        if responsiveIndexRedirect(for: router.currentRoute) != nil {
            DispatchQueue.main.async { [weak self] in
                guard let self,
                      let redirectedRoute = self.responsiveIndexRedirect(for: self.router.currentRoute) else { return }
                self.router.replace(redirectedRoute, hostTabIndex: redirectedRoute.tabIndex)
            }
        }
    }

    private func responsiveIndexRedirect(for route: Route) -> Route? {
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

    private func updateSidebarBackground() {
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

    private func visibleBannerBackdropRoute() -> String? {
        let topController = topVisibleHostedController()
        if topController is BrowseAnimeViewController { return Self.homeBannerBackdropHomeRoute }
        if topController is AnimeDetailViewController { return Self.homeBannerBackdropAnimeRoute }
        return nil
    }

    private func topVisibleHostedController() -> UIViewController? {
        topVisibleController(from: tabHost.selectedViewController)
    }

    private func topVisibleController(from controller: UIViewController?) -> UIViewController? {
        guard let controller else { return nil }
        if let presented = controller.presentedViewController, !presented.isBeingDismissed {
            return topVisibleController(from: presented)
        }
        if let nav = controller as? UINavigationController {
            return topVisibleController(from: nav.topViewController)
        }
        return controller
    }

    @objc private func toggleMobileMenu() {
        isMobileMenuOpen.toggle()
        mobileLauncherWidthConstraint?.constant = isMobileMenuOpen ? 176 : 64
        mobileLauncherHeightConstraint?.constant = isMobileMenuOpen ? 176 : 64
        let icon = isMobileMenuOpen ? "x" : "menu"
        mobileToggleButton.setImage(UIImage.hayaseIcon(icon), for: .normal)
        UIViewPropertyAnimator(duration: 0.15,
                               controlPoint1: CGPoint(x: 0.4, y: 0),
                               controlPoint2: CGPoint(x: 0.2, y: 1)) {  // Tailwind transition: 150ms ease
            self.view.layoutIfNeeded()
        }.startAnimation()
    }

    private func closeMobileMenu(animated: Bool = true) {
        guard isMobileMenuOpen else { return }
        isMobileMenuOpen = false
        mobileLauncherWidthConstraint?.constant = 64
        mobileLauncherHeightConstraint?.constant = 64
        mobileToggleButton.setImage(UIImage.hayaseIcon("menu"), for: .normal)
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

    @objc private func handleOutsideTap(_ gesture: UITapGestureRecognizer) {
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

// MARK: - SidebarBackdropGradientView

private final class SidebarBackdropGradientView: UIView {
    private var centerX: CGFloat = 0.5918

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureView()
    }

    private func configureView() {
        backgroundColor = .clear
        isOpaque = false
    }

    func setCompact(_ compact: Bool) {
        let nextCenterX: CGFloat = compact ? 0.50 : 0.5918
        guard abs(nextCenterX - centerX) > 0.0001 else { return }
        centerX = nextCenterX
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard bounds.width > 0, bounds.height > 0,
              let context = UIGraphicsGetCurrentContext(),
              let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                        colors: [
                                            UIColor.black.withAlphaComponent(0.16).cgColor,
                                            UIColor.black.withAlphaComponent(0.16).cgColor,
                                            UIColor.black.cgColor,
                                        ] as CFArray,
                                        locations: [0.0, 0.3056, 1.0]) else { return }

        let center = CGPoint(x: bounds.width * centerX, y: bounds.height * 0.3497)
        context.saveGState()
        context.clip(to: bounds)
        context.translateBy(x: center.x, y: center.y)
        context.scaleBy(x: bounds.width * 0.75, y: bounds.height * 0.65)
        context.drawRadialGradient(gradient,
                                   startCenter: .zero,
                                   startRadius: 0,
                                   endCenter: .zero,
                                   endRadius: 1,
                                   options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        context.restoreGState()
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

    private var isCurrentRouteOwnedByRouter: Bool {
        switch router.currentRoute {
        case .anime, .animeThread, .player:
            return true
        default:
            return false
        }
    }
}
