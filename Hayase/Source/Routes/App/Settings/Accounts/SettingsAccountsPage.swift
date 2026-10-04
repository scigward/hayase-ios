//
//  SettingsAccountsPage.swift
//  Hayase
//
//  Mirrors: src/routes/app/settings/accounts/+page.svelte: the sections of the Accounts settings page.
//

import AuthenticationServices
import Foundation
import UIKit

extension SettingsSectionCatalog {
    static let accountsSections: [Section] = [
        Section(header: "Account Settings", rows: [
            Row(title: "AniList",
                description: "Connect your AniList account for anime tracking, list sync, and metadata.",
                kind: .account(.anilist)),
            Row(title: "Kitsu",
                description: "Connect your Kitsu account for anime tracking and list sync.",
                kind: .account(.kitsu)),
            Row(title: "MyAnimeList",
                description: "Connect your MyAnimeList account for anime tracking and list sync.",
                kind: .account(.mal)),
            Row(title: "Simkl",
                description: "Connect your Simkl account for anime tracking and list sync.",
                kind: .account(.simkl)),
            Row(title: "Local",
                description: "Local-only tracking. Works offline.",
                kind: .account(.local)),
        ], tab: .accounts),
    ]
}

// MARK: - AccountsPage

// Mirrors: src/routes/app/settings/accounts/+page.svelte

final class HayaseAccountCardView: UIView {
    private let headerView = UIView()
    private let footerView = UIView()
    private let headerStack = UIStackView()
    private let avatarView = UIImageView()
    private let avatarFallback = UILabel()
    private let nameLabel = UILabel()
    private let serviceLabel = UILabel()
    private var iconView: UIView?
    private let loginButton = SelectButton(frame: .zero)
    private let settingsButton = SelectButton(frame: .zero)
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
        // Avatar.Fallback remains visible while the image loads, or when no image is available.
        avatarFallback.font = .nunito(ofSize: 16)
        avatarFallback.textColor = UIColor.HayaseTheme.foreground
        avatarFallback.textAlignment = .center
        avatarFallback.backgroundColor = UIColor.HayaseTheme.muted
        avatarFallback.layer.cornerRadius = 16
        avatarFallback.clipsToBounds = true
        avatarFallback.frame = avatarView.bounds
        avatarFallback.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        avatarView.addSubview(avatarFallback)
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
        loginButton.applySecondaryVariant()
        loginButton.titleLabel?.font = .nunito(ofSize: 14, weight: .medium)
        loginButton.setTitleColor(UIColor.HayaseTheme.secondaryForeground, for: .normal)
        loginButton.backgroundColor = UIColor.HayaseTheme.secondary
        loginButton.layer.cornerRadius = 6
        loginButton.contentEdgeInsets = UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
        loginButton.heightAnchor.constraint(equalToConstant: 36).isActive = true
        settingsButton.applyGhostVariant()
        settingsButton.setLayeredIcon(.bolt, size: 18)
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
        discussionsIcon.isUserInteractionEnabled = true
        offlineIcon.isUserInteractionEnabled = true
        discussionsIcon.attachTooltip("Has Discussions")
        offlineIcon.attachTooltip("Works Offline")
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
        avatarFallback.isHidden = false
        avatarFallback.text = nil

        // Sync toggle
        syncToggle.setOn(mgr.isSyncEnabled(for: tracker), animated: false)

        // Login state
        if tracker == .local {
            nameLabel.attributedText = CSSText.string("Other", font: .nunito(ofSize: 14),
                color: UIColor.HayaseTheme.foreground, lineHeight: 20)
            serviceLabel.attributedText = CSSText.string("Local", font: .nunito(ofSize: 9),
                color: UIColor.HayaseTheme.mutedForeground, lineHeight: 9 * 1.375)
            avatarView.isHidden = true
        } else if let viewer = mgr.viewer(for: tracker) {
            nameLabel.attributedText = CSSText.string(viewer.name, font: .nunito(ofSize: 14),
                color: UIColor.HayaseTheme.foreground, lineHeight: 20)
            serviceLabel.attributedText = CSSText.string(tracker.displayName, font: .nunito(ofSize: 9),
                color: UIColor.HayaseTheme.mutedForeground, lineHeight: 9 * 1.375)
            avatarFallback.text = viewer.name
            avatarView.isHidden = false
            avatarView.image = nil
            // Load avatar asynchronously
            if let urlStr = viewer.avatarURL, let url = URL(string: urlStr) {
                URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
                    guard let data = data, let image = UIImage(data: data) else { return }
                    DispatchQueue.main.async {
                        guard let self, self.avatarRequestID == requestID else { return }
                        self.avatarView.image = image
                        self.avatarFallback.isHidden = true
                    }
                }.resume()
            }
            loginButton.setTitle("Logout", for: .normal)
            loginButton.backgroundColor = UIColor.HayaseTheme.secondary
        } else {
            nameLabel.text = "Not logged in"
            nameLabel.font = .nunito(ofSize: 16)
            nameLabel.attributedText = CSSText.string("Not logged in", font: .nunito(ofSize: 16),
                color: UIColor.HayaseTheme.foreground, lineHeight: 24)
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

// MARK: - AccountCardView+Authentication

// Mirrors: src/routes/app/settings/accounts/+page.svelte (authentication controls)

extension HayaseAccountCardView {
    private static func reportLoginError(_ error: Error?) {
        guard let error else { return }
        if let nativeError = error as? ASWebAuthenticationSessionError,
           nativeError.code == .canceledLogin { return }
        AppErrorToast.show(error.localizedDescription, title: "Login failed!")
    }
    // MARK: - AniList Login


    func loginAniList() {
        guard let vc = parentVC else { return }
        let url = AniListAuth.authorizeURL

        // ASWebAuthenticationSession properly handles custom URL scheme redirects
        // (SFSafariViewController cannot navigate to custom schemes like hayase://).
        let session = ASWebAuthenticationSession(
            url: url,
            callbackURLScheme: "hayase"
        ) { [weak self] callbackURL, error in
            DispatchQueue.main.async { [weak self] in
                self?.authSession = nil
                self?.authPresentationContext = nil
                Self.reportLoginError(error)
                guard let callbackURL = callbackURL, error == nil else { return }

                // AniList implicit grant puts the token in the URL fragment:
                //   hayase://#access_token=xxx&token_type=Bearer&expires_in=xxx
                if let fragment = callbackURL.fragment {
                    let params = fragment.components(separatedBy: "&")
                        .reduce(into: [String: String]()) { dict, pair in
                            let parts = pair.components(separatedBy: "=")
                            if parts.count == 2 { dict[parts[0]] = parts[1] }
                        }
                    if let token = params["access_token"] {
                        let expiresIn = params["expires_in"].flatMap(TimeInterval.init)
                        AniListAuth.completeLogin(token: token, expiresIn: expiresIn)
                    }
                }
            }
        }
        let ctx = AniListAuthPresentationContext(anchor: vc)
        authPresentationContext = ctx
        session.presentationContextProvider = ctx
        session.prefersEphemeralWebBrowserSession = false
        authSession = session
        session.start()
    }

    // MARK: - Kitsu Login

    func loginKitsu() {
        guard let vc = parentVC else { return }
        let dialog = SettingsDialogViewController(title: "")
        let form = SettingsKitsuLoginForm(frame: .zero)
        form.addArrangedSubview(SettingsTypography.label("Kitsu Login", size: 20, lineHeight: 28, weight: .bold))
        let email = SettingsInputControl(value: "", placeholder: "email@website.com", width: 440)
        email.input.keyboardType = .emailAddress
        let password = SettingsInputControl(value: "", placeholder: "**************", width: 440, secure: true)
        for (title, input) in [("Login", email), ("Password", password)] {
            let row = UIStackView(arrangedSubviews: [SettingsTypography.label(title, size: 14, lineHeight: 21, weight: .bold), input])
            row.axis = .vertical
            row.spacing = 8
            form.addArrangedSubview(row)
        }
        form.addArrangedSubview(SettingsTypography.label(
            "Your password is not stored in the app, it is sent directly to Kitsu for authentication.",
            size: 14, lineHeight: 20, color: UIColor.HayaseTheme.mutedForeground))
        let login = SettingsTypography.button("Login", secondary: true)
        login.addAction(UIAction { [weak email, weak password] _ in
            // `ksclient.login(kitsuLogin, kitsuPassword)`: the dialog stays, only Cancel closes it
            KitsuAuth.login(email: email?.input.text ?? "", password: password?.input.text ?? "") { _ in }
        }, for: .touchUpInside)
        let cancel = SettingsTypography.button("Cancel", destructive: true)
        cancel.addAction(UIAction { [weak dialog] _ in dialog?.close() }, for: .touchUpInside)
        form.addArrangedSubview(SettingsKitsuLoginFooter(login: login, cancel: cancel))
        dialog.content.addArrangedSubview(form)
        vc.present(dialog, animated: false)
    }

    // MARK: - MAL Login

    func loginMAL() {
        guard let vc = parentVC else { return }
        let codeVerifier = MALAuth.generateCodeVerifier()
        let url = MALAuth.authorizeURL(codeChallenge: codeVerifier)

        let session = ASWebAuthenticationSession(
            url: url,
            callbackURLScheme: "hayase"
        ) { [weak self] callbackURL, error in
            DispatchQueue.main.async { [weak self] in
                self?.authSession = nil
                self?.authPresentationContext = nil
                Self.reportLoginError(error)
                guard let callbackURL = callbackURL, error == nil else { return }

                // MAL PKCE flow returns the code in the query string:
                //   hayase://callback?code=xxx
                if let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
                   let code = components.queryItems?.first(where: { $0.name == "code" })?.value {
                    MALAuth.completeLogin(code: code, codeVerifier: codeVerifier)
                }
            }
        }
        let ctx = AniListAuthPresentationContext(anchor: vc)
        authPresentationContext = ctx
        session.presentationContextProvider = ctx
        session.prefersEphemeralWebBrowserSession = false
        authSession = session
        session.start()
    }

    // MARK: - Simkl Login

    func loginSimkl() {
        guard let vc = parentVC else { return }
        guard !SimklAuth.clientID.isEmpty, !SimklAuth.clientSecret.isEmpty else {
            TrackerToast.error("Simkl Sync", "Simkl Client ID and Client Secret must be configured in Simkl settings.")
            return
        }
        let state = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        guard let url = SimklAuth.authorizeURL(state: state) else { return }
        let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "hayase") { [weak self] callbackURL, error in
            DispatchQueue.main.async { [weak self] in
                self?.authSession = nil
                self?.authPresentationContext = nil
                Self.reportLoginError(error)
                guard error == nil,
                      let callbackURL,
                      let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
                      components.queryItems?.first(where: { $0.name == "state" })?.value == state,
                      let code = components.queryItems?.first(where: { $0.name == "code" })?.value else { return }
                // The provider reports the original API error once, as on the web.
                SimklAuth.completeLogin(code: code) { _ in }
            }
        }
        let context = AniListAuthPresentationContext(anchor: vc)
        authPresentationContext = context
        session.presentationContextProvider = context
        session.prefersEphemeralWebBrowserSession = false
        authSession = session
        session.start()
    }


}

/// The login form's `space-y-4 px-4 sm:px-6 w-full`, inside Dialog.Header.
private final class SettingsKitsuLoginForm: UIStackView, SettingsResponsiveView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        axis = .vertical
        spacing = 16
        isLayoutMarginsRelativeArrangement = true
        updateLayout(viewportWidth: 0)
    }

    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func updateLayout(viewportWidth: CGFloat) {
        let padding: CGFloat = viewportWidth >= 640 ? 24 : 16
        layoutMargins = UIEdgeInsets(top: 0, left: padding, bottom: 0, right: padding)
        arrangedSubviews.compactMap { $0 as? SettingsResponsiveView }
            .forEach { $0.updateLayout(viewportWidth: viewportWidth) }
    }
}

/// `py-3 gap-3 flex flex-col sm:flex-row-reverse`: Login first on phones, on the right at sm.
private final class SettingsKitsuLoginFooter: UIStackView, SettingsResponsiveView {
    private let login: UIButton
    private let cancel: UIButton
    private let spacer = UIView()
    private var horizontal: Bool?

    init(login: UIButton, cancel: UIButton) {
        self.login = login
        self.cancel = cancel
        super.init(frame: .zero)
        spacing = 12
        isLayoutMarginsRelativeArrangement = true
        layoutMargins = UIEdgeInsets(top: 12, left: 0, bottom: 12, right: 0)
        updateLayout(viewportWidth: 0)
    }

    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func updateLayout(viewportWidth: CGFloat) {
        let next = viewportWidth >= 640
        guard horizontal != next else { return }
        horizontal = next
        login.setContentHuggingPriority(next ? .required : .defaultLow, for: .horizontal)
        cancel.setContentHuggingPriority(next ? .required : .defaultLow, for: .horizontal)
        arrangedSubviews.forEach { removeArrangedSubview($0); $0.removeFromSuperview() }
        axis = next ? .horizontal : .vertical
        let ordered: [UIView] = next ? [spacer, cancel, login] : [login, cancel]
        ordered.forEach { addArrangedSubview($0) }
    }
}

/// Provides the presentation anchor window for ASWebAuthenticationSession.
final class AniListAuthPresentationContext: NSObject, ASWebAuthenticationPresentationContextProviding {
    private weak var anchor: UIViewController?

    init(anchor: UIViewController) {
        self.anchor = anchor
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        anchor?.view.window ?? UIApplication.shared.windows.first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
}

// MARK: - AccountCardView+Settings

// Mirrors: src/routes/app/settings/accounts/+page.svelte (account settings dialogs)

extension HayaseAccountCardView {
    // MARK: - Settings dialogs

    func showAniListSettings() {
        let dialog = SettingsDialogViewController(title: "AniList Settings", maximumWidth: 896)
        dialog.centersCompactHeading = true
        dialog.panelColor = UIColor.HayaseTheme.background   // bg-background
        let viewer = TrackerAccountManager.shared.viewer(for: .anilist)
        let languages = [
            ("ROMAJI", "Romaji (Shingeki no Kyojin)"), ("ENGLISH", "English (Attack on Titan)"),
            ("NATIVE", "Native (進撃の巨人)"), ("ROMAJI_STYLISED", "Romaji Stylised"),
            ("ENGLISH_STYLISED", "English Stylised"), ("NATIVE_STYLISED", "Native Stylised"),
        ]
        let language = ComboBox(frame: .zero)
        language.layer.borderWidth = 1
        language.layer.borderColor = UIColor.HayaseTheme.input.cgColor
        let current = viewer?.titleLanguage ?? "ROMAJI"
        language.configure(text: languages.first(where: { $0.0 == current })?.1 ?? current, placeholder: false)
        language.isEnabled = viewer != nil
        let width = language.widthAnchor.constraint(equalToConstant: 240)
        width.priority = .defaultHigh
        width.isActive = true
        language.addAction(UIAction { [weak dialog, weak language] _ in
            guard let language else { return }
            let picker = CommandPopoverViewController(title: "Title Language", placeholder: "Search...",
                groups: [CommandGroup(options: languages.map { CommandOption(value: $0.0, label: $0.1) })],
                selectedValues: [TrackerAccountManager.shared.viewer(for: .anilist)?.titleLanguage ?? "ROMAJI"],
                allowsMultiple: false, sourceView: language)
            picker.onSelectionChanged = { [weak language] values in
                guard let value = values.first else { return }
                AniListClient.shared.updateUserResult(titleLanguage: value) { result in
                    switch result {
                    case .success(let viewer):
                        language?.configure(text: languages.first(where: { $0.0 == viewer.titleLanguage })?.1 ?? value, placeholder: false)
                    case .failure(let error): NSLog("[Settings] Failed to update language: %@", error.localizedDescription)
                    }
                }
            }
            dialog?.present(picker, animated: false)
        }, for: .touchUpInside)
        dialog.content.addArrangedSubview(SettingsCardView(title: "Title Language",
            description: "What language should anime titles be displayed in.", control: language))
        let adult = HayaseSwitch()
        adult.setOn(viewer?.displayAdultContent ?? false, animated: false)
        adult.isEnabled = viewer != nil
        adult.addAction(UIAction { [weak adult] _ in
            guard let adult else { return }
            AniListClient.shared.updateUserResult(displayAdultContent: adult.isOn) { [weak adult] result in
                adult?.setOn(TrackerAccountManager.shared.viewer(for: .anilist)?.displayAdultContent ?? false, animated: true)
                if case .failure(let error) = result {
                    NSLog("[Settings] Failed to update NSFW setting: %@", error.localizedDescription)
                }
            }
        }, for: .valueChanged)
        dialog.content.addArrangedSubview(SettingsCardView(title: "18+ Content",
            description: "Shows/Hides ALL 18+ content when logged into AniList. This includes lists, recommendations, search results, relations and more.",
            control: adult))
        dialog.content.addArrangedSubview(clientIDCard(service: "AniList", value: AniListAuth.clientID, width: 128) {
            AniListAuth.clientID = $0
        })
        parentVC?.present(dialog, animated: false)
    }

    func showMALSettings() {
        let dialog = SettingsDialogViewController(title: "MyAnimeList Settings", maximumWidth: 896)
        dialog.centersCompactHeading = true
        dialog.panelColor = UIColor.HayaseTheme.background   // bg-background
        dialog.content.addArrangedSubview(clientIDCard(service: "MyAnimeList", value: MALAuth.clientID, width: 384) {
            MALAuth.clientID = $0
        })
        parentVC?.present(dialog, animated: false)
    }

    private func clientIDCard(service: String, value: String, width: CGFloat,
                              onChange: @escaping (String) -> Void) -> UIView {
        let input = SettingsInputControl(value: value, placeholder: "\(service) Client ID", width: width,
            numeric: service == "AniList")
        input.onChange = onChange
        return SettingsCardView(title: "Client ID",
            description: "The Client ID used for \(service) authentication and API access. Change this if you want to use your own, or if the default one stops working.",
            control: input)
    }

    func showSimklSettings() {
        let dialog = SettingsDialogViewController(title: "Simkl Settings", maximumWidth: 896)
        dialog.centersCompactHeading = true
        dialog.panelColor = UIColor.HayaseTheme.background   // bg-background
        let identifier = SettingsInputControl(value: SimklAuth.clientID, placeholder: "Simkl Client ID", width: 384)
        identifier.onChange = { SimklAuth.clientID = $0 }
        let secret = SettingsInputControl(value: SimklAuth.clientSecret, placeholder: "Simkl Client Secret", width: 384, secure: true)
        secret.onChange = { SimklAuth.clientSecret = $0 }
        dialog.content.addArrangedSubview(SettingsCardView(title: "Client ID",
            description: "Required for authentication. Get yours at https://simkl.com/settings/developer/new", control: identifier))
        dialog.content.addArrangedSubview(SettingsCardView(title: "Client Secret",
            description: "Required for token exchange. Found in the same Simkl dev app settings.", control: secret))
        parentVC?.present(dialog, animated: false)
    }
}
