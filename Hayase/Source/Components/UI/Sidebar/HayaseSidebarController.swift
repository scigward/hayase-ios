//
//  HayaseSidebarController.swift
//  Hayase
//
//  Made by scigward.
//
//  Mirrors: src/routes/app/+layout.svelte and src/lib/components/ui/sidebar/sidebar.svelte
//

import UIKit

// MARK: - HayaseSidebarController

final class HayaseSidebarController: UIViewController {
    private static let homeBannerBackdropDidChange = Notification.Name("HayaseHomeBannerBackdropDidChange")
    private static let homeBannerBackdropURLKey = "url"
    private static let homeBannerBackdropAlphaKey = "alpha"

    private let tabBarControllerHost: UITabBarController
    private let sidebarList = HayaseSidebarListView(mode: .desktop)
    private let mobileSidebarList = HayaseSidebarListView(mode: .mobile)
    private let contentContainer = UIView()
    private let mobileLauncher = UIView()
    private let mobileGridContainer = UIView()
    private let mobileToggleButton = UIButton(type: .system)
    private let sidebarContainer = UIView()
    private let sidebarBackdropImageView = UIImageView()
    private let sidebarBackdropGradientView = SidebarBackdropGradientView()
    private var sidebarBackdropTask: URLSessionDataTask?
    private var sidebarBackdropURL: String?
    private var sidebarWidthConstraint: NSLayoutConstraint?
    private var sidebarBackdropHeightConstraint: NSLayoutConstraint?
    private var mobileLauncherWidthConstraint: NSLayoutConstraint?
    private var mobileLauncherHeightConstraint: NSLayoutConstraint?
    private var isMobileMenuOpen = false
    private var isDesktopMode: Bool?
    private var selectedIndexObservation: NSKeyValueObservation?

    init(tabBarController: UITabBarController) {
        self.tabBarControllerHost = tabBarController
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.HayaseTheme.background
        installInterfaceRoutes()
        setupContentHost()
        setupDesktopSidebar()
        setupMobileSidebar()
        configureActions()
        observeBannerBackdrop()
        observeTabSelection()
        updateSelection(animated: false)
        updateLayoutForCurrentWidth()
    }

    override var prefersStatusBarHidden: Bool { true }
    override var childForStatusBarHidden: UIViewController? { nil }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        hideHostedNavigationBars()
        updateSidebarBackground()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        hideHostedNavigationBars()
        updateSidebarBackground()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateLayoutForCurrentWidth()
        updateSidebarBackground()
        hideHostedNavigationBars()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        hideHostedNavigationBars()
        updateLayoutForCurrentWidth()
    }

    private func setupContentHost() {
        hideNativeTabNavigation(in: tabBarControllerHost)
        tabBarControllerHost.delegate = self

        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.backgroundColor = UIColor.HayaseTheme.background
        view.addSubview(contentContainer)

        addChild(tabBarControllerHost)
        tabBarControllerHost.view.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(tabBarControllerHost.view)
        NSLayoutConstraint.activate([
            contentContainer.topAnchor.constraint(equalTo: view.topAnchor),
            contentContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            contentContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            tabBarControllerHost.view.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            tabBarControllerHost.view.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            tabBarControllerHost.view.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            tabBarControllerHost.view.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),
        ])
        tabBarControllerHost.didMove(toParent: self)
    }

    private func installInterfaceRoutes() {
        guard var controllers = tabBarControllerHost.viewControllers else { return }
        controllers = controllers.map { controller in
            if let nav = controller as? HayaseInterfaceNavigationController {
                return nav
            }
            if let nav = controller as? UINavigationController {
                return HayaseInterfaceNavigationController(wrapping: nav)
            }
            return controller
        }
        guard controllers.count == 6 else {
            tabBarControllerHost.setViewControllers(controllers, animated: false)
            return
        }
        let chat = HayaseInterfaceNavigationController(rootViewController: HayaseChatViewController())
        controllers.insert(chat, at: 4)
        tabBarControllerHost.setViewControllers(controllers, animated: false)
    }

    private func hideHostedNavigationBars() {
        hideNavigationChrome(in: tabBarControllerHost)
    }

    private func hideNativeTabNavigation(in tab: UITabBarController) {
        tab.tabBar.isHidden = true
        tab.tabBar.alpha = 0
        tab.tabBar.isUserInteractionEnabled = false

        if #available(iOS 18.0, *) {
            // iPadOS 18 can promote a UITabBarController into Apple's native
            // tab/sidebar chrome on regular-width screens. This app owns its
            // navigation UI, so keep UIKit's tab chrome fully disabled.
            tab.mode = .tabBar
            tab.setTabBarHidden(true, animated: false)
            tab.sidebar.isHidden = true
        }

        tab.view.setNeedsLayout()
    }

    private func hideNavigationChrome(in viewController: UIViewController?) {
        guard let viewController else { return }
        if let tab = viewController as? UITabBarController {
            hideNativeTabNavigation(in: tab)
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

        sidebarContainer.translatesAutoresizingMaskIntoConstraints = false
        sidebarContainer.backgroundColor = .clear
        sidebarContainer.clipsToBounds = true
        sidebarContainer.addSubview(sidebarBackdropImageView)
        sidebarContainer.addSubview(sidebarBackdropGradientView)
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

            // Web sidebarlist.svelte mounts <BannerImage class='w-14'> behind
            // the buttons. Keep the image screen-width and clip it to the rail
            // so anime pages show the same left slice as the main banner.
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

            sidebarList.topAnchor.constraint(equalTo: sidebarContainer.safeAreaLayoutGuide.topAnchor, constant: 8),
            sidebarList.leadingAnchor.constraint(equalTo: sidebarContainer.leadingAnchor),
            sidebarList.trailingAnchor.constraint(equalTo: sidebarContainer.trailingAnchor, constant: -8),
            sidebarList.bottomAnchor.constraint(equalTo: sidebarContainer.safeAreaLayoutGuide.bottomAnchor, constant: -8),
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
            mobileLauncher.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            mobileLauncher.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
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
        if let alpha = notification.userInfo?[Self.homeBannerBackdropAlphaKey] as? CGFloat {
            UIView.animate(withDuration: 0.5) {
                self.sidebarBackdropImageView.alpha = alpha
                self.sidebarBackdropGradientView.alpha = alpha
            }
        }

        updateSidebarBackground()

        guard let urlString = notification.userInfo?[Self.homeBannerBackdropURLKey] as? String,
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

    private func configureActions() {
        let handler: (HayaseSidebarRoute) -> Void = { [weak self] route in
            self?.handle(route)
        }
        sidebarList.configure(actionHandler: handler)
        mobileSidebarList.configure(actionHandler: handler)
    }

    private func observeTabSelection() {
        selectedIndexObservation = tabBarControllerHost.observe(\.selectedIndex, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.updateSelection(animated: true)
            }
        }
    }

    private func handle(_ route: HayaseSidebarRoute) {
        closeMobileMenu()

        if route == .donate {
            UIApplication.shared.open(URL(string: route.href)!)
            return
        }

        guard let index = route.tabIndex else { return }
        minimizeVisiblePlayerIfNeeded()
        tabBarControllerHost.selectedIndex = index
        if let nav = tabBarControllerHost.selectedViewController as? UINavigationController {
            nav.popToRootViewController(animated: false)
            if route == .profile,
               let settings = nav.viewControllers.first as? SettingsViewController {
                settings.openAccountsTab()
            }
        }
        updateSelection(animated: true)
    }

    private func minimizeVisiblePlayerIfNeeded() {
        guard let nav = tabBarControllerHost.selectedViewController as? UINavigationController,
              let player = nav.topViewController as? VideoPlayerViewController else { return }
        MiniPlayerManager.shared.minimize(player)
    }

    private func updateSelection(animated: Bool) {
        sidebarList.setSelectedIndex(tabBarControllerHost.selectedIndex, animated: animated)
        mobileSidebarList.setSelectedIndex(tabBarControllerHost.selectedIndex, animated: animated)
        updateSidebarBackground()
    }

    private func updateLayoutForCurrentWidth() {
        let isPhoneLandscape = traitCollection.userInterfaceIdiom == .phone
            && view.bounds.width > view.bounds.height
            && view.bounds.width >= 568
        let isDesktop = view.bounds.width >= 768 || traitCollection.horizontalSizeClass == .regular || isPhoneLandscape
        hideNativeTabNavigation(in: tabBarControllerHost)
        guard isDesktopMode != isDesktop else { return }
        isDesktopMode = isDesktop
        sidebarList.superview?.isHidden = !isDesktop
        mobileLauncher.isHidden = isDesktop
        sidebarWidthConstraint?.constant = isDesktop ? 56 : 0
        if !isDesktop {
            closeMobileMenu(animated: false)
        }
        updateSidebarBackground()
    }

    private func updateSidebarBackground() {
        let topController = topVisibleHostedController()
        let isHomeRoute = topController is BrowseAnimeViewController
        let isAnimeRoute = topController is AnimeDetailViewController
        let allowsBannerBackdrop = isHomeRoute || isAnimeRoute
        let showsBannerBackdrop = allowsBannerBackdrop && sidebarBackdropImageView.image != nil

        // interface renders BannerImage from sidebarlist.svelte on both /app/home
        // and /app/anime/*, clipped to w-14 behind the sidebar buttons. The
        // image height comes from banner-image.svelte: md home = 90vh, anime = 23rem.
        let homeHeight = max(view.bounds.height * 0.9, 368)
        sidebarBackdropHeightConstraint?.constant = isHomeRoute ? homeHeight : 368

        sidebarContainer.backgroundColor = showsBannerBackdrop ? .clear : UIColor.HayaseTheme.background
        sidebarBackdropImageView.isHidden = !showsBannerBackdrop
        sidebarBackdropGradientView.isHidden = !showsBannerBackdrop
        sidebarList.backgroundColor = .clear
    }

    private func topVisibleHostedController() -> UIViewController? {
        let selected = tabBarControllerHost.selectedViewController
        if let nav = selected as? UINavigationController {
            return nav.topViewController
        }
        return selected
    }

    @objc private func toggleMobileMenu() {
        isMobileMenuOpen.toggle()
        mobileLauncherWidthConstraint?.constant = isMobileMenuOpen ? 176 : 64
        mobileLauncherHeightConstraint?.constant = isMobileMenuOpen ? 176 : 64
        let icon = isMobileMenuOpen ? "x" : "menu"
        mobileToggleButton.setImage(UIImage.hayaseIcon(icon), for: .normal)
        UIView.animate(withDuration: 0.25, delay: 0, options: [.curveEaseInOut]) {
            self.view.layoutIfNeeded()
        }
    }

    private func closeMobileMenu(animated: Bool = true) {
        guard isMobileMenuOpen else { return }
        isMobileMenuOpen = false
        mobileLauncherWidthConstraint?.constant = 64
        mobileLauncherHeightConstraint?.constant = 64
        mobileToggleButton.setImage(UIImage.hayaseIcon("menu"), for: .normal)
        let changes = { self.view.layoutIfNeeded() }
        if animated {
            UIView.animate(withDuration: 0.25, delay: 0, options: [.curveEaseInOut], animations: changes)
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
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - SidebarBackdropGradientView

private final class SidebarBackdropGradientView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .clear
        isOpaque = false
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

        let center = CGPoint(x: bounds.width * 0.5918, y: bounds.height * 0.3497)
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

extension HayaseSidebarController: UITabBarControllerDelegate {
    func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
        hideHostedNavigationBars()
        updateSelection(animated: true)
    }
}
