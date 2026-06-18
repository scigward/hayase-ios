//
//  AccountCardCell.swift
//  Hayase
//
//  A UITableViewCell that mirrors Hayase's account card layout from
//  /app/settings/accounts/+page.svelte. Each tracker (AniList, Kitsu, MAL,
//  Local) gets a card with:
//    • Header (bg-neutral-900 rounded-t-md): avatar + name / "Not logged in" + icon
//    • Footer (bg-neutral-950 rounded-b-md): Login/Logout button + sync toggle
//
//  Design tokens:
//    bg-neutral-900 = #171717   (header)
//    bg-neutral-950 = #0a0a0a   (footer)
//    text-muted-foreground ≈ zinc-400 (#a1a1aa)
//    rounded-t-md / rounded-b-md = 6px
//    px-6 = 24px, py-4 = 16px
//    gap-3 = 12px
//

import UIKit
import AuthenticationServices

// MARK: - HayaseAccountCardCell

final class HayaseAccountCardCell: UITableViewCell {
    static let reuseID = "HayaseAccountCardCell"

    // MARK: - Colors
    private static let headerBg = UIColor(red: 23/255, green: 23/255, blue: 23/255, alpha: 1)   // #171717
    private static let footerBg = UIColor(red: 10/255, green: 10/255, blue: 10/255, alpha: 1)   // #0a0a0a
    private static let mutedFg  = UIColor(red: 161/255, green: 161/255, blue: 170/255, alpha: 1) // text-muted-foreground

    // MARK: - Subviews

    /// Outer container that clips to rounded corners.
    private let cardContainer: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.clipsToBounds = true
        return v
    }()

    /// Top header section (bg-neutral-900, rounded top).
    private let headerView: UIView = {
        let v = UIView()
        v.backgroundColor = headerBg
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    /// Bottom footer section (bg-neutral-950, rounded bottom).
    private let footerView: UIView = {
        let v = UIView()
        v.backgroundColor = footerBg
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    // Header content
    private let avatarView: UIImageView = {
        let iv = UIImageView()
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.layer.cornerRadius = 4 // rounded-md
        iv.clipsToBounds = true
        iv.contentMode = .scaleAspectFill
        iv.backgroundColor = UIColor.darkGray
        return iv
    }()

    private let nameLabel: UILabel = {
        let l = UILabel()
        l.font = .nunito(ofSize: 14) // text-sm
        l.textColor = .white
        l.numberOfLines = 1
        return l
    }()

    private let serviceLabel: UILabel = {
        let l = UILabel()
        l.font = .nunito(ofSize: 9) // text-[9px]
        l.textColor = mutedFg // text-muted-foreground
        l.numberOfLines = 1
        return l
    }()

    /// Placeholder for the service icon (set dynamically).
    private var iconView: UIView?

    // Footer content
    private let loginButton: UIButton = {
        let b = UIButton(type: .system)
        b.setTitle("Login", for: .normal)
        b.titleLabel?.font = .nunito(ofSize: 13, weight: .medium)
        b.setTitleColor(.white, for: .normal)
        b.backgroundColor = UIColor(red: 38/255, green: 38/255, blue: 38/255, alpha: 1) // Hayase variant='secondary'
        b.layer.cornerRadius = 6
        b.contentEdgeInsets = UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
        b.translatesAutoresizingMaskIntoConstraints = false
        return b
    }()

    private let settingsButton: UIButton = {
        let b = UIButton(type: .system)
        b.setImage(UIImage.hayaseIcon("settings"), for: .normal)
        b.tintColor = .white
        b.translatesAutoresizingMaskIntoConstraints = false
        b.isHidden = true // Only shown for AniList and MAL
        return b
    }()

    private let syncToggle: UISwitch = {
        let s = UISwitch()
        s.onTintColor = .systemIndigo
        s.transform = CGAffineTransform(scaleX: 0.75, y: 0.75) // Smaller to match Hayase
        s.translatesAutoresizingMaskIntoConstraints = false
        return s
    }()

    private let syncLabel: UILabel = {
        let l = UILabel()
        l.text = "Enable Sync"
        l.font = .nunito(ofSize: 13)
        l.textColor = .white
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    // MARK: - State

    private var tracker: TrackerKind = .anilist
    weak var parentVC: UIViewController?

    // MARK: - Init

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        buildLayout()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        buildLayout()
    }

    // MARK: - Layout

    private func buildLayout() {
        selectionStyle = .none
        backgroundColor = .clear
        contentView.backgroundColor = .clear

        contentView.addSubview(cardContainer)

        // Card container margins (same as existing setting cards)
        NSLayoutConstraint.activate([
            cardContainer.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 6),
            cardContainer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            cardContainer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            cardContainer.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6),
        ])

        cardContainer.addSubview(headerView)
        cardContainer.addSubview(footerView)

        // Header: rounded-t-md
        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: cardContainer.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: cardContainer.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: cardContainer.trailingAnchor),
        ])

        // Footer: rounded-b-md, below header
        NSLayoutConstraint.activate([
            footerView.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            footerView.leadingAnchor.constraint(equalTo: cardContainer.leadingAnchor),
            footerView.trailingAnchor.constraint(equalTo: cardContainer.trailingAnchor),
            footerView.bottomAnchor.constraint(equalTo: cardContainer.bottomAnchor),
        ])

        // Apply rounded corners to header/footer
        headerView.layer.cornerRadius = 6
        headerView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        footerView.layer.cornerRadius = 6
        footerView.layer.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]

        // ─── Header content ───

        // Avatar
        headerView.addSubview(avatarView)

        // Name + service label stack
        let nameStack = UIStackView(arrangedSubviews: [nameLabel, serviceLabel])
        nameStack.axis = .vertical
        nameStack.spacing = 1
        nameStack.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(nameStack)

        // Hayase: px-6 py-4 gap-3
        NSLayoutConstraint.activate([
            avatarView.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 24),
            avatarView.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            avatarView.widthAnchor.constraint(equalToConstant: 32), // size-8
            avatarView.heightAnchor.constraint(equalToConstant: 32),

            nameStack.leadingAnchor.constraint(equalTo: avatarView.trailingAnchor, constant: 12), // gap-3
            nameStack.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),

            headerView.heightAnchor.constraint(greaterThanOrEqualToConstant: 64), // py-4 * 2 + content
        ])

        // Icon placeholder is added in configure()

        // ─── Footer content ───

        // Left side: login button + settings gear
        let leftStack = UIStackView(arrangedSubviews: [loginButton, settingsButton])
        leftStack.axis = .horizontal
        leftStack.spacing = 4
        leftStack.alignment = .center
        leftStack.translatesAutoresizingMaskIntoConstraints = false
        footerView.addSubview(leftStack)

        // Right side: sync toggle + label
        let rightStack = UIStackView(arrangedSubviews: [syncToggle, syncLabel])
        rightStack.axis = .horizontal
        rightStack.spacing = 6
        rightStack.alignment = .center
        rightStack.translatesAutoresizingMaskIntoConstraints = false
        footerView.addSubview(rightStack)

        NSLayoutConstraint.activate([
            leftStack.leadingAnchor.constraint(equalTo: footerView.leadingAnchor, constant: 24),
            leftStack.centerYAnchor.constraint(equalTo: footerView.centerYAnchor),

            rightStack.trailingAnchor.constraint(equalTo: footerView.trailingAnchor, constant: -24),
            rightStack.centerYAnchor.constraint(equalTo: footerView.centerYAnchor),

            leftStack.trailingAnchor.constraint(lessThanOrEqualTo: rightStack.leadingAnchor, constant: -8),

            footerView.heightAnchor.constraint(greaterThanOrEqualToConstant: 60), // Hayase ~68px
        ])

        loginButton.addTarget(self, action: #selector(loginTapped), for: .touchUpInside)
        settingsButton.addTarget(self, action: #selector(settingsTapped), for: .touchUpInside)
        syncToggle.addTarget(self, action: #selector(syncChanged), for: .valueChanged)

        // Observe tracker changes
        NotificationCenter.default.addObserver(self, selector: #selector(trackerDidChange), name: TrackerAccountManager.didChange, object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Configure

    func configure(tracker: TrackerKind, parentVC: UIViewController?) {
        self.tracker = tracker
        self.parentVC = parentVC

        // Service label
        serviceLabel.text = tracker.displayName

        // Replace icon
        iconView?.removeFromSuperview()
        let icon = TrackerIconFactory.makeIcon(for: tracker, size: 24)
        headerView.addSubview(icon)
        NSLayoutConstraint.activate([
            icon.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -24),
            icon.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
        ])
        iconView = icon

        // Settings button visibility
        settingsButton.isHidden = !(tracker == .anilist || tracker == .mal)

        // Local tracker has no login button
        loginButton.isHidden = tracker == .local

        // For local, hide avatar
        avatarView.isHidden = tracker == .local

        refreshState()
    }

    @objc private func trackerDidChange() {
        refreshState()
    }

    private func refreshState() {
        let mgr = TrackerAccountManager.shared

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
                        self?.avatarView.image = image
                    }
                }.resume()
            }
            loginButton.setTitle("Logout", for: .normal)
            loginButton.backgroundColor = UIColor(red: 38/255, green: 38/255, blue: 38/255, alpha: 1)
        } else {
            nameLabel.text = "Not logged in"
            avatarView.isHidden = true
            loginButton.setTitle("Login", for: .normal)
            loginButton.backgroundColor = UIColor(red: 38/255, green: 38/255, blue: 38/255, alpha: 1)
        }
    }

    // MARK: - Actions

    @objc private func loginTapped() {
        let mgr = TrackerAccountManager.shared

        if mgr.isLoggedIn(tracker) && tracker != .local {
            // Logout
            let alert = UIAlertController(title: "Logout from \(tracker.displayName)?", message: nil, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Logout", style: .destructive) { _ in
                mgr.logout(self.tracker)
            })
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            parentVC?.present(alert, animated: true)
        } else {
            // Login
            switch tracker {
            case .anilist:
                loginAniList()
            case .kitsu:
                loginKitsu()
            case .mal:
                loginMAL()
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
        default:
            break
        }
    }

    @objc private func syncChanged(_ sender: UISwitch) {
        TrackerAccountManager.shared.setSyncEnabled(sender.isOn, for: tracker)
    }

    // MARK: - AniList Login

    /// Active ASWebAuthenticationSession — must be retained until completion.
    private var authSession: ASWebAuthenticationSession?
    /// Retained presentation context for the auth session (presentationContextProvider is weak).
    private var authPresentationContext: AniListAuthPresentationContext?

    private func loginAniList() {
        guard let vc = parentVC else { return }
        let url = AniListAuth.authorizeURL

        // ASWebAuthenticationSession properly handles custom URL scheme redirects
        // (SFSafariViewController cannot navigate to custom schemes like hayase://).
        let session = ASWebAuthenticationSession(
            url: url,
            callbackURLScheme: "hayase"
        ) { [weak self] callbackURL, error in
            self?.authSession = nil
            self?.authPresentationContext = nil
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
                    AniListAuth.completeLogin(token: token)
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

    private func loginKitsu() {
        guard let vc = parentVC else { return }

        let alert = UIAlertController(title: "Kitsu Login", message: "Your password is not stored in the app, it is sent directly to Kitsu for authentication.", preferredStyle: .alert)
        alert.addTextField { tf in
            tf.placeholder = "email@website.com"
            tf.keyboardType = .emailAddress
            tf.autocapitalizationType = .none
        }
        alert.addTextField { tf in
            tf.placeholder = "Password"
            tf.isSecureTextEntry = true
        }
        alert.addAction(UIAlertAction(title: "Login", style: .default) { [weak alert] _ in
            guard let email = alert?.textFields?[0].text, !email.isEmpty,
                  let password = alert?.textFields?[1].text, !password.isEmpty else { return }
            KitsuAuth.login(email: email, password: password) { success in
                if !success {
                    let error = UIAlertController(title: "Login Failed", message: "Please check your credentials and try again.", preferredStyle: .alert)
                    error.addAction(UIAlertAction(title: "OK", style: .default))
                    vc.present(error, animated: true)
                }
            }
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .destructive))
        vc.present(alert, animated: true)
    }

    // MARK: - MAL Login

    private func loginMAL() {
        guard let vc = parentVC else { return }
        let codeVerifier = MALAuth.generateCodeVerifier()
        UserDefaults.standard.set(codeVerifier, forKey: "mal_code_verifier")
        let url = MALAuth.authorizeURL(codeChallenge: codeVerifier)

        let session = ASWebAuthenticationSession(
            url: url,
            callbackURLScheme: "hayase"
        ) { [weak self] callbackURL, error in
            self?.authSession = nil
            self?.authPresentationContext = nil
            guard let callbackURL = callbackURL, error == nil else { return }

            // MAL PKCE flow returns the code in the query string:
            //   hayase://callback?code=xxx
            if let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
               let code = components.queryItems?.first(where: { $0.name == "code" })?.value,
               let verifier = UserDefaults.standard.string(forKey: "mal_code_verifier") {
                MALAuth.completeLogin(code: code, codeVerifier: verifier)
            }
        }
        let ctx = AniListAuthPresentationContext(anchor: vc)
        authPresentationContext = ctx
        session.presentationContextProvider = ctx
        session.prefersEphemeralWebBrowserSession = false
        authSession = session
        session.start()
    }

    // MARK: - Settings dialogs

    private func showAniListSettings() {
        guard let vc = parentVC else { return }

        let alert = UIAlertController(title: "AniList Settings", message: nil, preferredStyle: .actionSheet)

        // Client ID
        alert.addAction(UIAlertAction(title: "Change Client ID (current: \(AniListAuth.clientID))", style: .default) { _ in
            let idAlert = UIAlertController(title: "AniList Client ID", message: "The Client ID used for AniList authentication and API access.", preferredStyle: .alert)
            idAlert.addTextField { tf in
                tf.text = AniListAuth.clientID
                tf.keyboardType = .numberPad
                tf.placeholder = "AniList Client ID"
            }
            idAlert.addAction(UIAlertAction(title: "Save", style: .default) { [weak idAlert] _ in
                if let text = idAlert?.textFields?.first?.text, !text.isEmpty {
                    AniListAuth.clientID = text
                }
            })
            idAlert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            vc.present(idAlert, animated: true)
        })

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))

        if let popover = alert.popoverPresentationController {
            popover.sourceView = settingsButton
            popover.sourceRect = settingsButton.bounds
        }

        vc.present(alert, animated: true)
    }

    private func showMALSettings() {
        guard let vc = parentVC else { return }

        let alert = UIAlertController(title: "MyAnimeList Settings", message: nil, preferredStyle: .actionSheet)

        alert.addAction(UIAlertAction(title: "Change Client ID (current: \(MALAuth.clientID))", style: .default) { _ in
            let idAlert = UIAlertController(title: "MAL Client ID", message: "The Client ID used for MyAnimeList authentication and API access.", preferredStyle: .alert)
            idAlert.addTextField { tf in
                tf.text = MALAuth.clientID
                tf.placeholder = "MyAnimeList Client ID"
            }
            idAlert.addAction(UIAlertAction(title: "Save", style: .default) { [weak idAlert] _ in
                if let text = idAlert?.textFields?.first?.text, !text.isEmpty {
                    MALAuth.clientID = text
                }
            })
            idAlert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            vc.present(idAlert, animated: true)
        })

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))

        if let popover = alert.popoverPresentationController {
            popover.sourceView = settingsButton
            popover.sourceRect = settingsButton.bounds
        }

        vc.present(alert, animated: true)
    }
}

// MARK: - SFSafariViewController compat wrapper
// Needed for import SafariServices in the cell.

import SafariServices

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
