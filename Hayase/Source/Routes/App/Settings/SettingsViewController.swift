// Mirrors: src/routes/app/settings/+layout.svelte and +page.ts
import UIKit

enum SettingsPreviewKind: Equatable {
    case subtitleStyle
    case colorTheme
}

final class SettingsViewController: UIViewController {
    let settingsView = SettingsLayoutView(frame: .zero)
    var settingsRoute: Route.SettingsRoute = .root
    var selectedTab: SettingsTab = .player
    var changelogEntries: [HayaseChangelogEntry]?
    var changelogError: String?
    var pendingScale: Double?
    var previousScale: Double?
    var scaleCountdown = 10
    var scaleTimer: Timer?
    weak var scaleAlert: SettingsDialogViewController?

    init() { super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        tabBarItem = UITabBarItem(title: "Settings", image: UIImage.hayaseIcon("settings"),
                                 selectedImage: UIImage.hayaseIcon("settings"))
    }

    override func loadView() { view = settingsView }

    override var keyCommands: [UIKeyCommand]? {
        // Melt slider endpoint shortcuts; the event is still dispatched from the focused control.
        let endpoints: [UIKeyCommand] = [.keydown(UIKeyCommand.inputHome), .keydown(UIKeyCommand.inputEnd)]
        return endpoints + [KeyboardEvent.Key.arrowLeft, KeyboardEvent.Key.arrowRight,
         KeyboardEvent.Key.arrowUp, KeyboardEvent.Key.arrowDown].map {
            UIKeyCommand.keydown($0, modifierFlags: .command)
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Settings"
        navigationController?.setNavigationBarHidden(true, animated: false)
        settingsView.navigation.onSelect = { [weak self] tab in
            guard let self else { return }
            let route = self.route(for: tab)
            guard self.settingsRoute != route else { return }
            Router.shared.navigate(.settings(route), hostTabIndex: self.hayaseTabIndex, noScroll: true)
        }
        settingsView.navigation.onLicense = { [weak self] in self?.showLicense() }
        reloadContent()
        if settingsRoute == .changelog { loadChangelogIfNeeded() }
    }

    override func viewWillDisappear(_ animated: Bool) {
        view.endEditing(true)
        super.viewWillDisappear(animated)
    }

    deinit {
        scaleTimer?.invalidate()
        if let previousScale {
            Settings.uiScale = previousScale
            HayaseInterfaceScale.apply(previousScale)
        }
    }

    func openAccountsTab() { applyRoute(.accounts) }

    func applyRoute(_ route: Route.SettingsRoute) {
        let changed = settingsRoute != route
        if changed && isViewLoaded { view.endEditing(true) }
        settingsRoute = route
        selectedTab = tab(for: route)
        guard isViewLoaded else { return }
        settingsView.isIndex = route == .root
        settingsView.navigation.select(route == .root ? nil : selectedTab, animated: changed)
        if changed { reloadContent() }
        if route == .changelog { loadChangelogIfNeeded() }
    }

    func reloadContent() {
        guard isViewLoaded else { return }
        settingsView.isIndex = settingsRoute == .root
        settingsView.navigation.select(settingsRoute == .root ? nil : selectedTab, animated: false)
        var views: [UIView] = []
        if settingsRoute != .root {
            for section in SettingsSectionCatalog.sections where section.tab == selectedTab {
                if !section.header.isEmpty {
                    views.append(SettingsTypography.label(section.header, size: 20, lineHeight: 28, weight: .bold))
                }
                views.append(contentsOf: section.rows.map { makeRow($0) })
            }
        }
        settingsView.setContent(views)
    }

    func route(for tab: SettingsTab) -> Route.SettingsRoute {
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

    func tab(for route: Route.SettingsRoute) -> SettingsTab {
        switch route {
        case .root, .player: return .player
        case .client: return .client
        case .interface: return .interface_
        case .extensions: return .extensions
        case .accounts: return .accounts
        case .app: return .app
        case .changelog: return .changelog
        }
    }
}
