//
//  Sidebarlist.swift
//  Hayase
//
//  Made by scigward.
//
//  Mirrors: src/lib/components/ui/sidebar/sidebarlist.svelte
//

import UIKit

// MARK: - HayaseSidebarListView

final class HayaseSidebarListView: UIView {
    enum LayoutMode {
        case desktop
        case mobile
    }

    private let mode: LayoutMode
    private let stack = UIStackView()
    private var routeButtons: [HayaseSidebarRoute: HayaseSidebarButton] = [:]
    private var actionHandler: ((HayaseSidebarRoute) -> Void)?
    private var profileAvatarTask: URLSessionDataTask?
    private var isAppActive = UIApplication.shared.applicationState == .active
    private var isPlayerRoute = false

    init(mode: LayoutMode) {
        self.mode = mode
        super.init(frame: .zero)
        setup()
    }

    required init?(coder: NSCoder) {
        self.mode = .desktop
        super.init(coder: coder)
        setup()
    }

    deinit {
        profileAvatarTask?.cancel()
        NotificationCenter.default.removeObserver(self)
    }

    func configure(actionHandler: @escaping (HayaseSidebarRoute) -> Void) {
        self.actionHandler = actionHandler
    }

    func setSelectedRoute(_ currentRoute: Route, animated: Bool) {
        isPlayerRoute = currentRoute == .player
        updateHeartbeat()
        let previous = routeButtons.values.first { $0.isActiveRoute }
        var next: HayaseSidebarButton?
        for (route, button) in routeButtons {
            let isActive = route.matches(currentRoute)
            button.setActive(isActive, animated: animated)
            if isActive { next = button }
        }
        guard animated, let previous, let next, previous !== next else { return }
        HayaseCrossfade.send(next.activePill, from: previous.activePill)
        HayaseCrossfade.receive(previous.activePill, to: next.activePill)
    }

    func setSelectedIndex(_ index: Int, animated: Bool) {
        guard let route = Route(tabIndex: index) else { return }
        setSelectedRoute(route, animated: animated)
    }

    func refreshDynamicState() {
        routeButtons[.w2g]?.setStatusDotVisible(W2GLobby.shared.client != nil)
        routeButtons[.chat]?.setStatusDotVisible(IRCLobby.shared.client != nil)
        refreshProfileButton()
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .clear

        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = mode == .desktop ? .vertical : .horizontal
        stack.alignment = mode == .desktop ? .leading : .center
        stack.distribution = .fill
        stack.spacing = mode == .desktop ? 8 : 0
        addSubview(stack)

        if mode == .desktop {
            NSLayoutConstraint.activate([
                stack.topAnchor.constraint(equalTo: topAnchor),
                stack.leadingAnchor.constraint(equalTo: leadingAnchor),
                stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
                stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
            buildDesktopList()
        } else {
            NSLayoutConstraint.activate([
                stack.topAnchor.constraint(equalTo: topAnchor),
                stack.leadingAnchor.constraint(equalTo: leadingAnchor),
                stack.trailingAnchor.constraint(equalTo: trailingAnchor),
                stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
            buildMobileGrid()
        }

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(dynamicStateChanged),
                                               name: W2GLobby.didChange,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(dynamicStateChanged),
                                               name: IRCLobby.didChange,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(dynamicStateChanged),
                                               name: TrackerAccountManager.didChange,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(appActivityChanged(_:)),
                                               name: UIApplication.didBecomeActiveNotification,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(appActivityChanged(_:)),
                                               name: UIApplication.willResignActiveNotification,
                                               object: nil)
        refreshDynamicState()
        updateHeartbeat()
    }

    /// sidebarlist.svelte `active`: the donate heart beats while the app has focus, off the player.
    private func updateHeartbeat() {
        routeButtons[.donate]?.setHeartbeat(isAppActive && !isPlayerRoute)
    }

    @objc private func appActivityChanged(_ notification: Notification) {
        isAppActive = notification.name == UIApplication.didBecomeActiveNotification
        updateHeartbeat()
    }

    private func buildDesktopList() {
        addLogoButton()
        addRoute(.home)
        addRoute(.search)
        addRoute(.schedule)
        addRoute(.w2g)
        addRoute(.chat)
        addRoute(.client)

        let spacer = UIView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(spacer)

        addRoute(.donate)
        addRoute(.settings)
        addRoute(.profile)
    }

    private func buildMobileGrid() {
        stack.axis = .vertical
        stack.spacing = 8
        let rows: [[HayaseSidebarRoute]] = [
            [.home, .search, .schedule],
            [.w2g, .chat, .client],
            [.donate, .settings],
        ]
        rows.enumerated().forEach { rowIndex, rowRoutes in
            let row = UIStackView()
            row.axis = .horizontal
            row.spacing = 8
            row.alignment = .center
            row.distribution = .fill
            stack.addArrangedSubview(row)
            rowRoutes.forEach { route in
                row.addArrangedSubview(makeButton(for: route, size: .mobile))
            }
            if rowIndex == rows.count - 1 {
                let menuSlot = UIView()
                menuSlot.translatesAutoresizingMaskIntoConstraints = false
                menuSlot.widthAnchor.constraint(equalToConstant: 48).isActive = true
                menuSlot.heightAnchor.constraint(equalToConstant: 48).isActive = true
                row.addArrangedSubview(menuSlot)
            }
        }
    }

    private func addLogoButton() {
        let logoButton = HayaseSidebarLogoButton()
        logoButton.translatesAutoresizingMaskIntoConstraints = false
        logoButton.accessibilityLabel = "Home"
        logoButton.addTarget(self, action: #selector(logoTapped), for: .touchUpInside)
        NSLayoutConstraint.activate([
            // Logo.svelte: h-10 mb-1. The SVG itself is 40pt tall.
            // Its visible path is positioned inside HayaseSidebarLogoButton
            // to match ml-2 px-2.5 from the web interface.
            logoButton.widthAnchor.constraint(equalToConstant: 48),
            logoButton.heightAnchor.constraint(equalToConstant: 40),
        ])
        stack.addArrangedSubview(logoButton)
        // sidebar.svelte has gap-2 (8pt) and Logo.svelte adds mb-1 (4pt).
        // UIStackView custom spacing replaces stack.spacing, so use 12pt here.
        stack.setCustomSpacing(12, after: logoButton)
    }

    private func addRoute(_ route: HayaseSidebarRoute) {
        stack.addArrangedSubview(makeButton(for: route, size: .desktop))
    }

    private func makeButton(for route: HayaseSidebarRoute, size: HayaseSidebarButton.SidebarSize) -> HayaseSidebarButton {
        let button = HayaseSidebarButton(route: route, size: size)
        routeButtons[route] = button
        button.onPress = { [weak self] in self?.actionHandler?(route) }
        return button
    }

    private func refreshProfileButton() {
        guard let button = routeButtons[.profile] else { return }
        profileAvatarTask?.cancel()
        guard let viewer = TrackerAccountManager.shared.viewer(for: .anilist),
              let urlString = viewer.avatarURL,
              let url = URL(string: urlString) else {
            button.setAvatar(nil)
            return
        }

        profileAvatarTask = URLSession.shared.dataTask(with: url) { [weak button] data, _, _ in
            guard let data, let image = UIImage(data: data) else { return }
            let avatar = Self.roundedAvatar(from: image, size: 24)
            DispatchQueue.main.async {
                button?.setAvatar(avatar)
            }
        }
        profileAvatarTask?.resume()
    }

    private static func roundedAvatar(from image: UIImage, size: CGFloat) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        return renderer.image { _ in
            UIBezierPath(roundedRect: CGRect(x: 0, y: 0, width: size, height: size), cornerRadius: 6).addClip()
            image.draw(in: CGRect(x: 0, y: 0, width: size, height: size))
        }
    }

    @objc private func logoTapped() {
        actionHandler?(.home)
    }

    @objc private func dynamicStateChanged() {
        refreshDynamicState()
    }
}

// MARK: - HayaseSidebarLogoButton

private final class HayaseSidebarLogoButton: UIControl {
    private let shapeLayer = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        // Exact CSS box model from sidebarlist.svelte:
        //   <Logo class="h-10 px-2.5 ml-2" />
        // Tailwind's border-box padding leaves a 20pt SVG content box inside
        // a 40pt-high element, shifted 8pt from the rail's left edge.
        let logoSide: CGFloat = 20
        let scale = logoSide / 66.145833
        var transform = CGAffineTransform(translationX: 18, y: 10)
            .scaledBy(x: scale, y: scale)
        shapeLayer.path = Self.logoPath().copy(using: &transform)
    }

    private func setup() {
        backgroundColor = .clear
        shapeLayer.fillColor = UIColor.HayaseTheme.foreground.cgColor
        layer.addSublayer(shapeLayer)
    }

    private static func logoPath() -> CGPath {
        HayaseLogo.path()
    }
}

// MARK: - HayaseSidebarRoute

//  Made by scigward.
//
//  Mirrors: src/lib/components/ui/sidebar/sidebarlist.svelte

// MARK: - HayaseSidebarRoute

enum HayaseSidebarRoute: Hashable, CaseIterable {
    case home
    case search
    case schedule
    case w2g
    case chat
    case client
    case donate
    case settings
    case profile

    var tabIndex: Int? {
        appRoute?.tabIndex
    }

    var appRoute: Route? {
        switch self {
        case .home: return .home
        case .search: return .search(nil)
        case .schedule: return .schedule
        case .w2g: return .w2g(id: nil)
        case .chat: return .chat
        case .client: return .client(.root)
        case .settings: return .settings(.root)
        case .profile: return .settings(.accounts)  // /app/profile redirects 307 to /app/settings/accounts
        case .donate: return nil
        }
    }

    var pathPrefix: String? {
        switch self {
        case .home: return "/app/home"
        case .search: return "/app/search"
        case .schedule: return "/app/schedule"
        case .w2g: return "/app/w2g"
        case .chat: return "/app/chat"
        case .client: return "/app/client"
        case .settings: return "/app/settings"
        case .profile: return "/app/profile"
        case .donate: return nil
        }
    }

    func matches(_ route: Route) -> Bool {
        guard let pathPrefix else { return false }
        return route.path == pathPrefix || route.path.hasPrefix(pathPrefix + "/")
    }

    var href: String {
        switch self {
        case .home: return "/#/app/home"
        case .search: return "/#/app/search"
        case .schedule: return "/#/app/schedule"
        case .w2g: return "/#/app/w2g"
        case .chat: return "/#/app/chat"
        case .client: return "/#/app/client"
        case .donate: return "https://github.com/sponsors/ThaUnknown/"
        case .settings: return "/#/app/settings"
        case .profile: return "/#/app/profile"
        }
    }

    var iconName: String {
        switch self {
        case .home: return "house"
        case .search: return "search"
        case .schedule: return "calendar-days"
        case .w2g: return "users"
        case .chat: return "messages-square"
        case .client: return "download"
        case .donate: return "heart"
        case .settings: return "bolt"
        case .profile: return "log-in"
        }
    }

    var accessibilityTitle: String {
        switch self {
        case .home: return "Home"
        case .search: return "Search"
        case .schedule: return "Schedule"
        case .w2g: return "Watch Together"
        case .chat: return "Chat"
        case .client: return "Client"
        case .donate: return "Donate"
        case .settings: return "Settings"
        case .profile: return "Profile"
        }
    }

    var isNativeRoute: Bool {
        tabIndex != nil
    }
}
