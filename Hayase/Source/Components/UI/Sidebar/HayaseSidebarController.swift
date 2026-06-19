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
    private let tabBarControllerHost: UITabBarController
    private let sidebarList = HayaseSidebarListView(mode: .desktop)
    private let mobileSidebarList = HayaseSidebarListView(mode: .mobile)
    private let contentContainer = UIView()
    private let mobileLauncher = UIView()
    private let mobileGridContainer = UIView()
    private let mobileToggleButton = UIButton(type: .system)
    private let sidebarContainer = UIView()
    private var sidebarWidthConstraint: NSLayoutConstraint?
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
        observeTabSelection()
        updateSelection(animated: false)
        updateLayoutForCurrentWidth()
    }

    override var prefersStatusBarHidden: Bool { true }
    override var childForStatusBarHidden: UIViewController? { nil }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        hideHostedNavigationBars()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        hideHostedNavigationBars()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateLayoutForCurrentWidth()
        hideHostedNavigationBars()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        updateLayoutForCurrentWidth()
    }

    private func setupContentHost() {
        tabBarControllerHost.tabBar.isHidden = true
        tabBarControllerHost.tabBar.alpha = 0
        tabBarControllerHost.tabBar.isUserInteractionEnabled = false
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

    private func hideNavigationChrome(in viewController: UIViewController?) {
        guard let viewController else { return }
        if let tab = viewController as? UITabBarController {
            tab.tabBar.isHidden = true
            tab.tabBar.alpha = 0
            tab.tabBar.isUserInteractionEnabled = false
            tab.view.setNeedsLayout()
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

        sidebarContainer.translatesAutoresizingMaskIntoConstraints = false
        sidebarContainer.backgroundColor = .clear
        sidebarContainer.addSubview(sidebarList)
        view.addSubview(sidebarContainer)

        sidebarWidthConstraint = sidebarContainer.widthAnchor.constraint(equalToConstant: 56)
        NSLayoutConstraint.activate([
            sidebarContainer.topAnchor.constraint(equalTo: view.topAnchor),
            sidebarContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            sidebarContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            sidebarWidthConstraint!,
            contentContainer.leadingAnchor.constraint(equalTo: sidebarContainer.trailingAnchor),

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
        let selectedRoute = HayaseSidebarRoute.allCases.first { $0.tabIndex == tabBarControllerHost.selectedIndex }
        sidebarContainer.backgroundColor = selectedRoute == .home ? UIColor.HayaseTheme.background : .clear
        sidebarList.backgroundColor = .clear
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
}

extension HayaseSidebarController: UITabBarControllerDelegate {
    func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
        hideHostedNavigationBars()
        updateSelection(animated: true)
    }
}
