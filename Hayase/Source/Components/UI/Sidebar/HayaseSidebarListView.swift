//
//  HayaseSidebarListView.swift
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

    func setSelectedIndex(_ index: Int, animated: Bool) {
        for (route, button) in routeButtons {
            button.setActive(route.tabIndex == index && route != .profile, animated: animated)
        }
    }

    func refreshDynamicState() {
        routeButtons[.w2g]?.setStatusDotVisible(W2GLobby.shared.client != nil)
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
                                               name: TrackerAccountManager.didChange,
                                               object: nil)
        refreshDynamicState()
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
            logoButton.widthAnchor.constraint(equalToConstant: 48),
            logoButton.heightAnchor.constraint(equalToConstant: 40),
        ])
        stack.addArrangedSubview(logoButton)
        stack.setCustomSpacing(4, after: logoButton)
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
            button.setSidebarImage(UIImage.hayaseIcon("log-in"), pointSize: 18, renderingMode: .alwaysTemplate)
            return
        }

        profileAvatarTask = URLSession.shared.dataTask(with: url) { [weak button] data, _, _ in
            guard let data, let image = UIImage(data: data) else { return }
            let avatar = Self.roundedAvatar(from: image, size: 24)
            DispatchQueue.main.async {
                button?.setSidebarImage(avatar, pointSize: 24, renderingMode: .alwaysOriginal)
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

    override var isHighlighted: Bool {
        didSet {
            alpha = isHighlighted ? 0.72 : 1
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let side = min(bounds.width, bounds.height)
        let inset: CGFloat = 5
        let scale = (side - inset * 2) / 66.145833
        var transform = CGAffineTransform(translationX: (bounds.width - side) / 2 + inset,
                                          y: (bounds.height - side) / 2 + inset)
            .scaledBy(x: scale, y: scale)
        shapeLayer.path = Self.logoPath().copy(using: &transform)
    }

    private func setup() {
        backgroundColor = .clear
        shapeLayer.fillColor = UIColor.HayaseTheme.foreground.cgColor
        layer.addSublayer(shapeLayer)
    }

    private static func logoPath() -> CGPath {
        let path = UIBezierPath()
        path.move(to: CGPoint(x: 0.00000117, y: 61.5156237))
        path.addLine(to: CGPoint(x: 0.00000117, y: 4.6302097))
        path.addLine(to: CGPoint(x: 66.145832, y: 41.6718737))
        path.addLine(to: CGPoint(x: 66.145832, y: 61.5156237))
        path.addLine(to: CGPoint(x: 18.520837, y: 34.7927137))
        path.addLine(to: CGPoint(x: 18.520837, y: 51.1968737))
        path.close()
        path.move(to: CGPoint(x: 66.145832, y: 31.0885537))
        path.addLine(to: CGPoint(x: 42.597916, y: 17.8593797))
        path.addLine(to: CGPoint(x: 66.145832, y: 4.6302097))
        path.close()
        return path.cgPath
    }
}
