// Mirrors: src/routes/app/settings/accounts/+page.svelte
import UIKit
import AuthenticationServices

final class HayaseAccountCardView: UIView {
    private let headerView = UIView()
    private let footerView = UIView()
    private let headerStack = UIStackView()
    private let avatarView = UIImageView()
    private let nameLabel = UILabel()
    private let serviceLabel = UILabel()
    private var iconView: UIView?
    private let loginButton = UIButton(type: .custom)
    private let settingsButton = GhostButton(frame: .zero)
    private let syncToggle = HayaseSwitch(hideState: true)
    private let syncLabel = SettingsTypography.label("Enable Sync", size: 14, lineHeight: 14, weight: .medium)
    private let discussionsIcon = UIImageView(image: UIImage.hayaseIcon("messages-square"))
    private let offlineIcon = UIImageView(image: UIImage.hayaseIcon("cloud-off"))
    private var tracker: TrackerKind = .anilist
    private var avatarRequestID = UUID()
    weak var parentVC: UIViewController?
    var onSizeChanged: (() -> Void)?
    var authSession: ASWebAuthenticationSession?
    var authPresentationContext: AniListAuthPresentationContext?

    override init(frame: CGRect) {
        super.init(frame: frame)
        buildLayout()
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        buildLayout()
    }

    private func buildLayout() {
        headerView.backgroundColor = UIColor.HayaseTheme.accent
        footerView.backgroundColor = UIColor.HayaseTheme.muted
        headerView.layer.cornerRadius = 6
        headerView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        footerView.layer.cornerRadius = 6
        footerView.layer.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        let root = UIStackView(arrangedSubviews: [headerView, footerView])
        root.axis = .vertical
        root.translatesAutoresizingMaskIntoConstraints = false
        addSubview(root)
        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: topAnchor), root.leadingAnchor.constraint(equalTo: leadingAnchor),
            root.trailingAnchor.constraint(equalTo: trailingAnchor), root.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        avatarView.layer.cornerRadius = 6
        avatarView.clipsToBounds = true
        avatarView.contentMode = .scaleAspectFill
        let avatarWidth = avatarView.widthAnchor.constraint(equalToConstant: 32)
        avatarWidth.priority = UILayoutPriority(999)
        avatarWidth.isActive = true
        avatarView.heightAnchor.constraint(equalToConstant: 32).isActive = true
        nameLabel.font = .nunito(ofSize: 14)
        nameLabel.textColor = UIColor.HayaseTheme.foreground
        serviceLabel.font = .nunito(ofSize: 9)
        serviceLabel.textColor = UIColor.HayaseTheme.mutedForeground
        let names = UIStackView(arrangedSubviews: [nameLabel, serviceLabel])
        names.axis = .vertical
        // `use:click={() => native.openURL(…/user/{name})}` on the avatar and the name
        for profile in [avatarView, names] {
            profile.isUserInteractionEnabled = true
            profile.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(openProfile)))
            profile.onDPadClick = { [weak self] in self?.openProfile() }
        }
        headerStack.axis = .horizontal
        headerStack.alignment = .center
        headerStack.spacing = 12
        [avatarView, names, UIView()].forEach { headerStack.addArrangedSubview($0) }
        pin(headerStack, to: headerView)

        loginButton.setTitle("Login", for: .normal)
        loginButton.titleLabel?.font = .nunito(ofSize: 14, weight: .medium)
        loginButton.setTitleColor(UIColor.HayaseTheme.secondaryForeground, for: .normal)
        loginButton.backgroundColor = UIColor.HayaseTheme.secondary
        loginButton.layer.cornerRadius = 6
        loginButton.contentEdgeInsets = UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
        loginButton.heightAnchor.constraint(equalToConstant: 36).isActive = true
        settingsButton.setImage(UIImage.hayaseIcon("bolt"), for: .normal)
        settingsButton.tintColor = UIColor.HayaseTheme.foreground
        let settingsWidth = settingsButton.widthAnchor.constraint(equalToConstant: 36)
        settingsWidth.priority = UILayoutPriority(999)
        settingsWidth.isActive = true
        settingsButton.heightAnchor.constraint(equalToConstant: 36).isActive = true
        settingsButton.accessibilityLabel = "Account settings"
        syncToggle.accessibilityLabel = "Enable Sync"
        let left = UIStackView(arrangedSubviews: [loginButton, settingsButton])
        left.spacing = 8
        left.alignment = .center
        let sync = UIStackView(arrangedSubviews: [syncToggle, syncLabel])
        sync.spacing = 8
        sync.alignment = .center
        let right = UIStackView(arrangedSubviews: [discussionsIcon, offlineIcon, sync])
        right.spacing = 16
        right.alignment = .center
        for icon in [discussionsIcon, offlineIcon] {
            icon.tintColor = UIColor.HayaseTheme.mutedForeground
            icon.contentMode = .scaleAspectFit
            let width = icon.widthAnchor.constraint(equalToConstant: 16)
            width.priority = UILayoutPriority(999)
            width.isActive = true
            icon.heightAnchor.constraint(equalToConstant: 16).isActive = true
        }
        discussionsIcon.accessibilityLabel = "Has Discussions"
        offlineIcon.accessibilityLabel = "Works Offline"
        let footer = UIStackView(arrangedSubviews: [left, UIView(), right])
        footer.axis = .horizontal
        footer.alignment = .center
        footer.spacing = 8
        pin(footer, to: footerView)
        footerView.heightAnchor.constraint(greaterThanOrEqualToConstant: 68).isActive = true
        loginButton.addTarget(self, action: #selector(loginTapped), for: .touchUpInside)
        settingsButton.addTarget(self, action: #selector(settingsTapped), for: .touchUpInside)
        syncToggle.addTarget(self, action: #selector(syncChanged), for: .valueChanged)
        syncLabel.isUserInteractionEnabled = true
        syncLabel.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(toggleSync)))
        syncLabel.onDPadClick = { [weak self] in self?.toggleSync() }
        NotificationCenter.default.addObserver(self, selector: #selector(trackerDidChange),
                                               name: TrackerAccountManager.didChange, object: nil)
    }

    private func pin(_ stack: UIStackView, to container: UIView) {
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -16),
        ])
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    // MARK: - Configure

    func configure(tracker: TrackerKind, parentVC: UIViewController?) {
        self.tracker = tracker
        self.parentVC = parentVC

        // Service label
        serviceLabel.text = tracker.displayName

        // Replace icon
        if let iconView { headerStack.removeArrangedSubview(iconView); iconView.removeFromSuperview() }
        let icon = TrackerIconFactory.makeIcon(for: tracker, size: 24)
        headerStack.addArrangedSubview(icon)
        iconView = icon

        // Settings button visibility
        settingsButton.isHidden = !(tracker == .anilist || tracker == .mal || tracker == .simkl)

        // Local tracker has no login button
        loginButton.isHidden = tracker == .local

        // For local, hide avatar
        avatarView.isHidden = tracker == .local

        discussionsIcon.isHidden = tracker != .anilist
        offlineIcon.isHidden = tracker != .anilist && tracker != .local
        refreshState()
    }

    @objc private func openProfile() {
        guard let name = TrackerAccountManager.shared.viewer(for: tracker)?.name,
              let escaped = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return }
        let base: String
        switch tracker {
        case .anilist: base = "https://anilist.co/user/"
        case .kitsu: base = "https://kitsu.app/users/"
        case .mal: base = "https://myanimelist.net/profile/"
        case .simkl: base = "https://simkl.com/profile/"
        case .local: return
        }
        if let url = URL(string: base + escaped) { UIApplication.shared.open(url) }
    }

    @objc private func trackerDidChange() {
        if Thread.isMainThread { refreshState() }
        else { DispatchQueue.main.async { [weak self] in self?.refreshState() } }
    }

    private func refreshState() {
        let mgr = TrackerAccountManager.shared
        avatarRequestID = UUID()
        let requestID = avatarRequestID
        nameLabel.font = .nunito(ofSize: 14)
        serviceLabel.isHidden = false
        avatarView.image = nil

        // Sync toggle
        syncToggle.setOn(mgr.isSyncEnabled(for: tracker), animated: false)

        // Login state
        if tracker == .local {
            nameLabel.text = "Other"
            serviceLabel.text = "Local"
            avatarView.isHidden = true
        } else if let viewer = mgr.viewer(for: tracker) {
            nameLabel.text = viewer.name
            avatarView.isHidden = false
            avatarView.image = nil
            // Load avatar asynchronously
            if let urlStr = viewer.avatarURL, let url = URL(string: urlStr) {
                URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
                    guard let data = data, let image = UIImage(data: data) else { return }
                    DispatchQueue.main.async {
                        guard let self, self.avatarRequestID == requestID else { return }
                        self.avatarView.image = image
                    }
                }.resume()
            }
            loginButton.setTitle("Logout", for: .normal)
            loginButton.backgroundColor = UIColor.HayaseTheme.secondary
        } else {
            nameLabel.text = "Not logged in"
            nameLabel.font = .nunito(ofSize: 16)
            serviceLabel.isHidden = true
            avatarView.isHidden = true
            loginButton.setTitle("Login", for: .normal)
            loginButton.backgroundColor = UIColor.HayaseTheme.secondary
        }
        onSizeChanged?()
    }

    // MARK: - Actions

    @objc private func loginTapped() {
        let mgr = TrackerAccountManager.shared

        if mgr.isLoggedIn(tracker) && tracker != .local {
            mgr.logout(tracker)
            (UIApplication.shared.delegate as? AppDelegate)?.restartInterface()
        } else {
            // Login
            switch tracker {
            case .anilist:
                loginAniList()
            case .kitsu:
                loginKitsu()
            case .mal:
                loginMAL()
            case .simkl:
                loginSimkl()
            case .local:
                break
            }
        }
    }

    @objc private func settingsTapped() {
        switch tracker {
        case .anilist:
            showAniListSettings()
        case .mal:
            showMALSettings()
        case .simkl:
            showSimklSettings()
        default:
            break
        }
    }

    @objc private func syncChanged(_ sender: HayaseSwitch) {
        TrackerAccountManager.shared.setSyncEnabled(sender.isOn, for: tracker)
    }

    @objc private func toggleSync() {
        syncToggle.setOn(!syncToggle.isOn, animated: true)
        syncChanged(syncToggle)
    }

}
