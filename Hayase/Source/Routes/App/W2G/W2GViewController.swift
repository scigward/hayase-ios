// W2GViewController.swift — W2G create/join screen and lobby with chat, user list, invite/quit
// Mirrors: hayase-app/interface/src/routes/app/w2g/[id]/+page.svelte
//
// Layout (matching the web):
//   ┌─────────────────────────────────────────────┐
//   │ Watch Together  <code>                       │
//   │ subtitle text + separator                    │
//   ├────────────────────────┬────────────────────┤
//   │                        │   User list (right) │
//   │   Chat messages        │   avatar + name     │
//   │   (scrollable)         │   avatar + name     │
//   │                        │                     │
//   ├────────────────────────┴────────────────────┤
//   │ [Quit] [Invite] [Message input...] [Send]   │
//   └─────────────────────────────────────────────┘

import UIKit
import CoreData
import LibTorrent

// MARK: - W2GViewController

final class W2GViewController: UIViewController {

    // MARK: - Tab bar init (set tabBarItem before viewDidLoad so tab bar reads it at launch)

    override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
        configureTabBarItem()
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureTabBarItem()
    }
    private func configureTabBarItem() {
        tabBarItem = UITabBarItem(
            title: "W2G",
            image: UIImage.hayaseIcon("users"),
            selectedImage: UIImage.hayaseIcon("users"))
    }

    // MARK: - Properties

    private var client: W2GClient? { W2GLobby.shared.client }

    /// The native root route offers manual joining; the web root auto-creates a lobby.
    private var isShowingLobby = false

    private var lobbyObserver: NSObjectProtocol?

    // MARK: - Landing UI Elements (shown when no lobby is active)

    private let landingScrollView = UIScrollView()
    private let landingStack = UIStackView()
    private let landingTitleLabel = UILabel()
    private let landingSubtitleLabel = UILabel()
    private let landingSeparator = UIView()
    private let createButton = UIButton(type: .system)
    private let joinSeparatorLabel = UILabel()
    private let joinCodeField = UITextField()
    private let joinButton = UIButton(type: .system)

    private var pendingWebTorrentPlayer: VideoPlayerViewController?
    private var pendingWebTorrentService: VideoService?
    private var pendingWebTorrentObserver: NSObjectProtocol?
    private var pendingWebTorrentResolving = false
    private var pendingNativePlayer: VideoPlayerViewController?

    // MARK: - Lobby UI Elements (shown when a lobby is active)

    private let titleLabel = UILabel()
    private let codeLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let separatorView = UIView()

    private let chatTableView = UITableView()
    private let userListTableView = UITableView()

    private let quitButton = Button(iconName: "door-open", pointSize: 18)
    private let inviteButton = Button(iconName: "user-plus", pointSize: 18)
    private let messageField = Textarea()
    private let sendButton = Button(iconName: "send-horizontal", pointSize: 18)

    private let bottomBar = UIStackView()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        navigationItem.title = "Watch Together"

        // Keep the landing and lobby views in sync with create/join/quit changes.
        lobbyObserver = NotificationCenter.default.addObserver(
            forName: W2GLobby.didChange, object: nil, queue: .main
        ) { [weak self] _ in
            self?.updateUI()
        }

        // Dismiss keyboard when tapping anywhere outside a text field.
        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)

        setupLandingUI()
        setupLobbyUI()
        if case .w2g(let id) = Router.shared.currentRoute {
            applyRoute(id: id)
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if case .w2g(let id) = Router.shared.currentRoute {
            applyRoute(id: id)
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // Mirrors web: onDestroy(() => { if ($w2globby?.destroyed) $w2globby = undefined })
        if client?.destroyed == true {
            W2GLobby.shared.client = nil
        }
    }

    deinit {
        if let obs = lobbyObserver {
            NotificationCenter.default.removeObserver(obs)
        }
        if let obs = pendingWebTorrentObserver {
            NotificationCenter.default.removeObserver(obs)
        }
    }

    // MARK: - State Management

    func applyRoute(id: String?) {
        if let id, !id.isEmpty {
            W2GLobby.shared.joinLobby(code: id)
        }
        if isViewLoaded { updateUI() }
    }

    private func updateUI() {
        if client != nil && !isShowingLobby {
            showLobbyUI()
        } else if client != nil {
            // Already showing lobby, just refresh
            codeLabel.text = client?.code ?? ""
            reloadData()
        } else {
            showLandingUI()
        }
    }

    private func showLandingUI() {
        isShowingLobby = false
        landingScrollView.isHidden = false
        for view in lobbyViews { view.isHidden = true }
    }

    private func showLobbyUI() {
        isShowingLobby = true
        landingScrollView.isHidden = true
        // Show lobby elements
        for v in lobbyViews { v.isHidden = false }

        client?.delegate = self
        codeLabel.text = client?.code ?? ""
        reloadData()
    }

    /// All lobby-specific views are hidden while the landing screen is shown.
    private var lobbyViews: [UIView] {
        [titleLabel, codeLabel, subtitleLabel, separatorView,
         chatTableView, userListTableView, bottomBar]
    }

    // MARK: - Landing UI Setup (native manual create/join screen)

    private func setupLandingUI() {
        landingScrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(landingScrollView)

        landingStack.axis = .vertical
        landingStack.spacing = 16
        landingStack.alignment = .fill
        landingStack.translatesAutoresizingMaskIntoConstraints = false
        landingScrollView.addSubview(landingStack)

        landingTitleLabel.text = "Watch Together"
        landingTitleLabel.font = .nunito(ofSize: 24, weight: .bold)
        landingTitleLabel.textColor = .white

        landingSubtitleLabel.text = "Watch videos together with friends in real-time. Create a lobby or join an existing one."
        landingSubtitleLabel.font = .nunito(ofSize: 14)
        landingSubtitleLabel.textColor = UIColor(white: 0.5, alpha: 1)
        landingSubtitleLabel.numberOfLines = 0

        landingSeparator.backgroundColor = UIColor(white: 0.2, alpha: 1)

        createButton.setTitle("Create Lobby", for: .normal)
        createButton.titleLabel?.font = .nunito(ofSize: 16, weight: .semibold)
        createButton.setTitleColor(.white, for: .normal)
        createButton.backgroundColor = UIColor(red: 0.35, green: 0.6, blue: 1, alpha: 1)
        createButton.layer.cornerRadius = 10
        createButton.addTarget(self, action: #selector(createLobbyTapped), for: .touchUpInside)

        joinSeparatorLabel.text = "or join an existing lobby"
        joinSeparatorLabel.font = .nunito(ofSize: 14)
        joinSeparatorLabel.textColor = UIColor(white: 0.5, alpha: 1)
        joinSeparatorLabel.textAlignment = .center

        joinCodeField.placeholder = "Enter lobby code"
        joinCodeField.font = .nunito(ofSize: 16)
        joinCodeField.textColor = .white
        joinCodeField.backgroundColor = UIColor(white: 0.1, alpha: 1)
        joinCodeField.layer.cornerRadius = 10
        joinCodeField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 16, height: 0))
        joinCodeField.leftViewMode = .always
        joinCodeField.autocapitalizationType = .none
        joinCodeField.autocorrectionType = .no
        joinCodeField.returnKeyType = .join
        joinCodeField.delegate = self

        joinButton.setTitle("Join Lobby", for: .normal)
        joinButton.titleLabel?.font = .nunito(ofSize: 16, weight: .semibold)
        joinButton.setTitleColor(.white, for: .normal)
        joinButton.backgroundColor = UIColor(white: 0.15, alpha: 1)
        joinButton.layer.cornerRadius = 10
        joinButton.addTarget(self, action: #selector(joinLobbyTapped), for: .touchUpInside)

        for item in [landingTitleLabel, landingSubtitleLabel, landingSeparator,
                     createButton, joinSeparatorLabel, joinCodeField, joinButton] {
            landingStack.addArrangedSubview(item)
        }

        let safe = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            landingScrollView.topAnchor.constraint(equalTo: safe.topAnchor),
            landingScrollView.leadingAnchor.constraint(equalTo: safe.leadingAnchor),
            landingScrollView.trailingAnchor.constraint(equalTo: safe.trailingAnchor),
            landingScrollView.bottomAnchor.constraint(equalTo: safe.bottomAnchor),
            landingStack.topAnchor.constraint(equalTo: landingScrollView.contentLayoutGuide.topAnchor, constant: 24),
            landingStack.bottomAnchor.constraint(equalTo: landingScrollView.contentLayoutGuide.bottomAnchor, constant: -24),
            landingStack.leadingAnchor.constraint(equalTo: landingScrollView.contentLayoutGuide.leadingAnchor, constant: 24),
            landingStack.trailingAnchor.constraint(equalTo: landingScrollView.contentLayoutGuide.trailingAnchor, constant: -24),
            landingStack.widthAnchor.constraint(equalTo: landingScrollView.frameLayoutGuide.widthAnchor, constant: -48),
            landingSeparator.heightAnchor.constraint(equalToConstant: 0.5),
            createButton.heightAnchor.constraint(equalToConstant: 48),
            joinCodeField.heightAnchor.constraint(equalToConstant: 48),
            joinButton.heightAnchor.constraint(equalToConstant: 48),
        ])
    }

    // MARK: - Lobby UI Setup (chat + user list, mirrors web /app/w2g/[id]/+page.svelte)

    private func setupLobbyUI() {
        setupHeader()
        setupMainContent()
        setupBottomBar()
        setupLobbyConstraints()
        // Start hidden until a lobby is created or joined.
        for v in lobbyViews { v.isHidden = true }
    }

    // MARK: - Setup Header (matches web's space-y-0.5 p-3 header)

    private func setupHeader() {
        // Title: "Watch Together" + code label
        titleLabel.text = "Watch Together"
        titleLabel.font = .nunito(ofSize: 24, weight: .bold)
        titleLabel.textColor = UIColor.HayaseTheme.foreground

        codeLabel.text = client?.code ?? ""
        codeLabel.font = .nunito(ofSize: 18, weight: .semibold)
        codeLabel.textColor = UIColor.HayaseTheme.mutedForeground

        subtitleLabel.text = "Watch videos together with friends in real-time. You can invite others to your lobby and chat while watching."
        subtitleLabel.font = .nunito(ofSize: 16)
        subtitleLabel.textColor = UIColor.HayaseTheme.mutedForeground
        subtitleLabel.numberOfLines = 0

        separatorView.backgroundColor = UIColor.HayaseTheme.border

        for v in [titleLabel, codeLabel, subtitleLabel, separatorView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(v)
        }
    }

    // MARK: - Setup Main Content (chat + user list)

    private func setupMainContent() {
        // Chat messages table
        chatTableView.backgroundColor = .clear
        chatTableView.separatorStyle = .none
        chatTableView.register(ChatMessageCell.self, forCellReuseIdentifier: ChatMessageCell.reuseID)
        chatTableView.dataSource = self
        chatTableView.delegate = self
        chatTableView.transform = CGAffineTransform(scaleX: 1, y: -1) // flip for bottom-anchored scrolling
        chatTableView.keyboardDismissMode = .onDrag
        chatTableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(chatTableView)

        // User list table
        userListTableView.backgroundColor = .clear
        userListTableView.separatorStyle = .none
        userListTableView.register(ChatUserListCell.self, forCellReuseIdentifier: ChatUserListCell.reuseID)
        userListTableView.dataSource = self
        userListTableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(userListTableView)
    }

    // MARK: - Setup Bottom Bar (matches web's flex mt-4 gap-2)

    private func setupBottomBar() {
        quitButton.addTarget(self, action: #selector(quitTapped), for: .touchUpInside)
        inviteButton.addTarget(self, action: #selector(inviteTapped), for: .touchUpInside)

        messageField.placeholder = "Message"
        messageField.maxLength = 256   // maxlength={256}
        messageField.onSubmit = { [weak self] in self?.sendCurrentMessage() }

        sendButton.addTarget(self, action: #selector(sendTapped), for: .touchUpInside)

        // `flex mt-4 gap-2`: the default `align-items: stretch` leaves the fixed-size buttons at the top.
        bottomBar.axis = .horizontal
        bottomBar.spacing = 8
        bottomBar.alignment = .top
        bottomBar.translatesAutoresizingMaskIntoConstraints = false

        bottomBar.addArrangedSubview(quitButton)
        bottomBar.addArrangedSubview(inviteButton)
        bottomBar.addArrangedSubview(messageField)
        bottomBar.addArrangedSubview(sendButton)

        view.addSubview(bottomBar)
    }

    // MARK: - Layout Constraints
    //
    // Responsive layout mirroring web's `flex md:flex-row flex-col-reverse`:
    //   - Narrow screens: user list above messages, capped at 40% of the body.
    //   - Wide screens (iPad / landscape): chat left, user list right (md:w-72).

    /// Constraints activated only in wide (side-by-side) layout.
    private var wideLayoutConstraints: [NSLayoutConstraint] = []
    /// Constraints activated only in narrow (stacked) layout.
    private var narrowLayoutConstraints: [NSLayoutConstraint] = []
    /// Tracks current layout class to avoid redundant re-layouts.
    private var isWideLayout: Bool?
    private lazy var compactUsersHeight = userListTableView.heightAnchor.constraint(equalToConstant: 0)

    private var headerInsets: [NSLayoutConstraint] = []

    private func setupLobbyConstraints() {
        let pad: CGFloat = 16
        let safe = view.safeAreaLayoutGuide
        // mt-4 above the input, given up before the input is when the page is too short for both.
        let chatBottom = chatTableView.bottomAnchor.constraint(equalTo: bottomBar.topAnchor, constant: -16)
        chatBottom.priority = .defaultHigh
        view.clipsToBounds = true   // overflow-clip

        // Always-active constraints
        NSLayoutConstraint.activate([
            // Title row

            // an inline span, so it sits on the title's baseline
            codeLabel.firstBaselineAnchor.constraint(equalTo: titleLabel.firstBaselineAnchor),
            codeLabel.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 16),

            // Subtitle: web uses space-y-0.5 = 2pt gap
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),

            // Separator: web uses <Separator class='!my-6' /> = 24pt vertical margin
            separatorView.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 24),
            separatorView.heightAnchor.constraint(equalToConstant: 1),

            // Bottom bar (always pinned to bottom)
            bottomBar.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: pad),
            // Above the keyboard when it is up, the safe area's bottom when it is not.
            bottomBar.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor, constant: -pad),
        ])

        headerInsets = [
            titleLabel.topAnchor.constraint(equalTo: safe.topAnchor, constant: pad),
            titleLabel.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: pad),
            subtitleLabel.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: pad),
            subtitleLabel.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -pad),
            separatorView.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: pad),
            separatorView.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -pad),
        ]
        NSLayoutConstraint.activate(headerInsets)

        // Wide layout: chat left, user list right (md:flex-row, md:w-72 = 288pt)
        wideLayoutConstraints = [
            bottomBar.trailingAnchor.constraint(equalTo: userListTableView.leadingAnchor, constant: -16),
            userListTableView.topAnchor.constraint(equalTo: separatorView.bottomAnchor, constant: 24),
            userListTableView.trailingAnchor.constraint(equalTo: safe.trailingAnchor),
            userListTableView.widthAnchor.constraint(equalToConstant: 288), // md:w-72
            userListTableView.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),

            chatTableView.topAnchor.constraint(equalTo: separatorView.bottomAnchor, constant: 24),
            chatTableView.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 16), // px-4
            chatTableView.trailingAnchor.constraint(equalTo: userListTableView.leadingAnchor),
            chatBottom,
        ]

        // Narrow layout: participants above messages (flex-col-reverse).
        narrowLayoutConstraints = [
            bottomBar.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -16),
            userListTableView.topAnchor.constraint(equalTo: separatorView.bottomAnchor, constant: 24),
            userListTableView.leadingAnchor.constraint(equalTo: safe.leadingAnchor),
            userListTableView.trailingAnchor.constraint(equalTo: safe.trailingAnchor),
            compactUsersHeight,
            chatTableView.topAnchor.constraint(equalTo: userListTableView.bottomAnchor),
            chatTableView.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 16), // px-4
            chatTableView.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -16),
            chatBottom,
        ]

        updateLayoutForCurrentWidth()
    }

    /// Activates the appropriate layout based on screen width.
    /// Web breakpoint: `md:` = 768px of the app viewport.
    private func updateLayoutForCurrentWidth() {
        let wide = (view.window?.rootViewController?.view.bounds.width ?? view.bounds.width) >= 768
        compactUsersHeight.constant = min(userListTableView.contentSize.height + 8, max(0, (view.bounds.height - separatorView.frame.maxY - 24) * 0.4))
        guard wide != isWideLayout else { return }
        isWideLayout = wide
        for (index, constraint) in headerInsets.enumerated() {
            constraint.constant = (index == 3 || index == 5 ? -1 : 1) * (wide ? 40 : 12)
        }

        if wide {
            NSLayoutConstraint.deactivate(narrowLayoutConstraints)
            NSLayoutConstraint.activate(wideLayoutConstraints)
            userListTableView.isHidden = false
        } else {
            NSLayoutConstraint.deactivate(wideLayoutConstraints)
            NSLayoutConstraint.activate(narrowLayoutConstraints)
            userListTableView.isHidden = false
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if isShowingLobby {
            updateLayoutForCurrentWidth()
        }
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: { _ in
            self.updateLayoutForCurrentWidth()
        })
    }

    // MARK: - Actions

    @objc private func dismissKeyboard(_ tap: UITapGestureRecognizer) {
        guard !(isShowingLobby && bottomBar.frame.contains(tap.location(in: view))) else { return }
        view.endEditing(true)
    }

    @objc private func createLobbyTapped() {
        W2GLobby.shared.createHostLobby(media: currentPlayerMediaState())
    }

    @objc private func joinLobbyTapped() {
        guard let code = joinCodeField.text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !code.isEmpty else { return }
        joinCodeField.resignFirstResponder()
        W2GLobby.shared.joinLobby(code: code)
    }

    @objc private func quitTapped() {
        // goto('/#/app/home'); $w2globby?.destroy()
        Router.shared.navigate(.home, hostTabIndex: hayaseTabIndex)
        W2GLobby.shared.leave()
    }

    @objc private func inviteTapped() {
        // TransitionButton: the icon becomes a check for as long as the click lasts.
        inviteButton.swapIcon(to: UIImage.hayaseIcon("check", pointSize: 16), hold: 0.8)
        guard let link = client?.inviteLink else { return }
        let ac = UIActivityViewController(
            activityItems: ["Invite people to your Watch Together lobby", URL(string: link) as Any],
            applicationActivities: nil
        )
        ac.setValue("Hayase W2G", forKey: "subject")   // native.share's title
        ac.popoverPresentationController?.sourceView = inviteButton
        present(ac, animated: true)
    }

    @objc private func sendTapped() {
        sendCurrentMessage()
    }

    private func sendCurrentMessage() {
        guard let text = messageField.text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return }
        client?.sendMessage(text)
        messageField.text = ""
    }

    // MARK: - Reload

    private func reloadData() {
        chatTableView.reloadData()
        userListTableView.reloadData()
    }

    // MARK: - Helper: sorted users

    private var sortedUsers: [W2GChatUser] {
        client?.orderedUsers ?? []
    }

    /// Messages in reverse order (table is flipped).
    private var reversedMessages: [W2GChatMessage] {
        client?.messages.reversed() ?? []
    }
}

// MARK: - UITableViewDataSource / Delegate

extension W2GViewController: UITableViewDataSource, UITableViewDelegate {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if tableView === chatTableView {
            return client?.messages.count ?? 0
        } else {
            return sortedUsers.count
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if tableView === chatTableView {
            guard let cell = tableView.dequeueReusableCell(withIdentifier: ChatMessageCell.reuseID, for: indexPath) as? ChatMessageCell else { return UITableViewCell() }
            let msgs = reversedMessages
            if msgs.indices.contains(indexPath.row) {
                // Message grouping (mirrors web Messages.svelte groupMessages): in the flipped
                // table, row 0 = newest. The visual "above" is row+1.
                let group = msgs.groupInfo(at: indexPath.row) { $0.user.id }
                cell.configure(with: msgs[indexPath.row].content, showHeader: group.showHeader,
                               isOutgoing: msgs[group.firstIndex].type == .outgoing)
            }
            cell.contentView.transform = CGAffineTransform(scaleX: 1, y: -1) // un-flip cell
            return cell
        } else {
            guard let cell = tableView.dequeueReusableCell(withIdentifier: ChatUserListCell.reuseID, for: indexPath) as? ChatUserListCell else { return UITableViewCell() }
            let users = sortedUsers
            if let user = users[safe: indexPath.row] {
                cell.configure(with: user)
            }
            return cell
        }
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        UITableView.automaticDimension
    }
}

// MARK: - UITextFieldDelegate

extension W2GViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        joinLobbyTapped()
        return true
    }
}

// MARK: - W2GClientDelegate

extension W2GViewController: W2GClientDelegate {
    func w2gClient(_ client: W2GClient, didReceiveIndexChange index: Int) {
        // Forward file-index change to the active player.
        // Mirrors web mediahandler.svelte: `$w2globby?.on('index', index => { current = fileToMedaInfo(mediaInfo.resolvedFiles[index]) })`
        guard let player = findActiveW2GPlayer() else { return }
        player.applyRemoteW2GIndex(index)
    }

    func w2gClient(_ client: W2GClient, didReceivePlayerState state: W2GPlayerState) {
        // Forwarded via onPlayerStateReceived callback (set by VideoPlayerViewController.bindW2GClient).
    }

    func w2gClient(_ client: W2GClient, didReceiveMediaChange media: W2GMediaState) {
        // Mirrors web: `server.play(torrent, media, episode)`
        // 1. Fetch AniList media info (web: `const media = (await client.single(mediaId)).data?.Media`)
        // 2. Add the torrent by hash
        // 3. Present the player
        playW2GMedia(media)
    }

    func w2gClientPeersDidChange(_ client: W2GClient) {
        DispatchQueue.main.async { [weak self] in
            self?.userListTableView.reloadData()
        }
    }

    func w2gClientMessagesDidChange(_ client: W2GClient) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            // The reversed web message list keeps the newest in view at the bottom and leaves
            // what you are reading where it is.
            self.chatTableView.reloadFlippedMessages {}
        }
    }
}

// MARK: - W2G Media Playback (mirrors web server.play)

extension W2GViewController {

    /// Find the active VideoPlayerViewController — either presented fullscreen
    /// or running in the mini-player. Returns nil if no player is active.
    private func findActiveW2GPlayer() -> VideoPlayerViewController? {
        // Mini-player.
        if let mini = MiniPlayerManager.shared.activePlayer { return mini }
        // Fullscreen (presented modally from this VC or a parent).
        var vc: UIViewController? = self
        while let presented = vc?.presentedViewController {
            if let player = presented as? VideoPlayerViewController { return player }
            vc = presented
        }
        return nil
    }

    /// Returns the media state of the currently-playing torrent, if any.
    /// Mirrors web's `server.last` persisted store which holds
    /// `{ media, id (torrent hash), episode }` of the last-played torrent.
    ///
    /// Web code in +page.ts:
    ///   const lastVal = get(server.last)
    ///   ... lastVal?.media.id ? { mediaId: lastVal.media.id, episode: lastVal.episode, torrent: lastVal.id } : undefined
    func currentPlayerMediaState() -> W2GMediaState? {
        guard let last = W2GMediaState.last, last.mediaId > 0 else { return nil }
        return last
    }

    /// Add the host's torrent by hash and present the player.
    /// Mirrors web's W2GClient `_onMsg` media handler:
    ///   const media = (await client.single(mediaId)).data?.Media
    ///   server.play(torrent, media, episode)
    private func playW2GMedia(_ mediaState: W2GMediaState) {
        let hash = mediaState.torrent
        let anilistID = mediaState.mediaId
        let episode = mediaState.episode
        guard !hash.isEmpty, anilistID > 0 else { return }

        // Close any existing mini-player before starting a new session.
        MiniPlayerManager.shared.close()

        // Mirrors web: `const media = (await client.single(mediaId)).data?.Media`
        // The interface only calls playHash when AniList supplies the media.
        AniListClient.shared.fetchAnimeByIdsResult([anilistID]) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let items):
                guard let media = items.first else { return }
                self.continueW2GPlay(hash: hash, anilistID: anilistID, episode: episode, animeItem: media)
            case .failure(let error):
                NSLog("[W2G] AniList lookup failed: %@", error.description)
            }
        }
    }

    /// Second half of `playW2GMedia`: add the torrent by hash and present the player.
    /// Mirrors web's `server.play(torrent, media, episode)`.
    private func continueW2GPlay(hash: String, anilistID: Int, episode: Int, animeItem: AnimeItem?) {
        guard client?.media?.torrent == hash else { return }
        let entity = findOrCreateW2GTorrent(hash: hash, anilistID: anilistID, animeItem: animeItem)

        // Set initial AniList state (mirrors web: `client.setInitialState(media, episode)`).
        AniListTracking.shared.setInitialState(anilistID: anilistID, episode: episode)

        switch TorrentBackendManager.shared.currentKind {
        case .webtorrent:
            playW2GWebTorrent(entity: entity,
                              anilistID: anilistID,
                              episode: episode,
                              animeItem: animeItem)
        case .native:
            let player = VideoPlayerViewController()
            pendingNativePlayer = player
            player.beginMetadataLoading(owner: self)
            player.onCancelMetadataLoading = { [weak self, weak player] in
                guard let self, self.pendingNativePlayer === player else { return }
                self.pendingNativePlayer = nil
            }
            Router.shared.navigateToPlayer(player, hostTabIndex: hayaseTabIndex)
            playW2GNative(hash: hash,
                          entity: entity,
                          anilistID: anilistID,
                          episode: episode,
                          animeItem: animeItem,
                          player: player)
        }
    }

    private func findOrCreateW2GTorrent(hash: String, anilistID: Int, animeItem: AnimeItem?) -> Torrents {
        let context = CoreDataService.sharedCoreDataService.mainQueueContext
        let request = NSFetchRequest<Torrents>(entityName: Torrents.entityName)
        request.predicate = NSPredicate(format: "torrentHashString == %@", hash)
        request.fetchLimit = 1

        let entity: Torrents
        if let existing = (try? context.fetch(request))?.first {
            entity = existing
        } else {
            entity = Torrents(context: context)
            entity.torrentHashString = hash
        }

        if entity.torrentName?.isEmpty ?? true {
            entity.torrentName = animeItem.map { AniListUtil.title(for: $0) } ?? hash
        }

        // WebTorrent can rehydrate a W2G torrent from the info hash alone.
        // Keep torrentHashString as the canonical W2G id and avoid inventing
        // a download URL; WebTorrentBackend falls back to an info-hash magnet.
        entity.torrentHashString = hash

        if anilistID > 0 {
            let animeRequest = Animes.fetchRequest()
            animeRequest.predicate = NSPredicate(format: "animeAnilistId == %d", anilistID)
            if let existing = (try? context.fetch(animeRequest))?.first as? Animes {
                entity.animes = existing
            } else if let item = animeItem {
                let anime = Animes(context: context)
                anime.animeAnilistId      = NSNumber(value: item.id)
                anime.animeTitleEnglish   = item.titleEnglish
                anime.animeTitleJapanese  = item.titleRomaji
                anime.animeTotalEps       = item.episodes.map { NSNumber(value: $0) }
                anime.animeScore          = item.score.map { NSNumber(value: $0) }
                anime.animeStatus         = item.status
                anime.animeDescription    = item.description
                anime.animeImgL           = item.coverURL
                anime.animeImgM           = item.coverURL
                entity.animes = anime
            }
        }

        try? context.save()
        return entity
    }

    private func playW2GNative(hash: String, entity: Torrents, anilistID: Int, episode: Int, animeItem: AnimeItem?, player: VideoPlayerViewController) {
        // Add the torrent by hash (magnet URI).
        // Mirrors web: `native.playTorrent(torrent, media.id, episode)`.
        guard let handle = TorrentService.sharedTorrentService.readdTorrent(hash: hash, magnetLink: nil) else {
            pendingNativePlayer = nil
            player.finishMetadataLoading(error: NSError(domain: "Hayase.W2G.Native", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Could not add the host's torrent."]))
            return
        }

        w2gWaitForMetadataAndPlay(handle: handle,
                                  entity: entity,
                                  anilistID: anilistID,
                                  episode: episode,
                                  animeItem: animeItem,
                                  player: player)
    }

    private func playW2GWebTorrent(entity: Torrents, anilistID: Int, episode: Int, animeItem: AnimeItem?) {
        cleanupPendingWebTorrent()
        let player = VideoPlayerViewController()
        pendingWebTorrentPlayer = player
        player.beginMetadataLoading(owner: self)
        player.onCancelMetadataLoading = { [weak self, weak player] in
            guard let self, self.pendingWebTorrentPlayer === player else { return }
            self.cleanupPendingWebTorrent()
        }
        Router.shared.navigateToPlayer(player, hostTabIndex: hayaseTabIndex)
        let videoService = VideoService(torrentEntity: entity, episode: episode)
        pendingWebTorrentService = videoService
        let context = CoreDataService.sharedCoreDataService.mainQueueContext
        let finish: (Result<[Videos], Error>) -> Void = { [weak self, weak videoService, weak player] result in
            guard let self, let videoService, let player,
                  self.pendingWebTorrentService === videoService,
                  self.pendingWebTorrentPlayer === player else { return }
            switch result {
            case .success(let videos):
                guard !self.pendingWebTorrentResolving else { return }
                self.pendingWebTorrentResolving = true
                self.presentW2GWebTorrentPlayer(player: player,
                                                videoService: videoService,
                                                entity: entity,
                                                videos: videos,
                                                anilistID: anilistID,
                                                episode: episode,
                                                animeItem: animeItem)
            case .failure(let error):
                self.cleanupPendingWebTorrent()
                player.finishMetadataLoading(error: error)
            }
        }

        pendingWebTorrentObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name(VideoService.LocalVideosDidUpdateNotification),
            object: nil,
            queue: .main
        ) { [weak videoService] _ in
            guard let videoService, videoService.hasFinishedUpdatingLocalVideos else { return }

            let fetch = NSFetchRequest<Videos>(entityName: Videos.entityName)
            fetch.predicate = NSPredicate(format: "torrents == %@", entity)
            fetch.sortDescriptors = [NSSortDescriptor(key: "videoIndex", ascending: true),
                                     NSSortDescriptor(key: "videoName", ascending: true)]
            let videos = (try? context.fetch(fetch)) ?? []

            if let error = videoService.lastError {
                finish(.failure(error))
            } else if !videos.isEmpty {
                finish(.success(videos))
            }
        }

        videoService.UpdateLocalVideo()

        DispatchQueue.main.asyncAfter(deadline: .now() + 60) { [weak self, weak videoService] in
            guard let self, self.pendingWebTorrentService === videoService else { return }
            let error = videoService?.lastError ?? NSError(
                domain: "Hayase.W2G.WebTorrent",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Could not fetch WebTorrent metadata from peers."])
            finish(.failure(error))
        }
    }

    private func cleanupPendingWebTorrent() {
        pendingWebTorrentResolving = false
        if let observer = pendingWebTorrentObserver {
            NotificationCenter.default.removeObserver(observer)
            pendingWebTorrentObserver = nil
        }
        pendingWebTorrentService = nil
        pendingWebTorrentPlayer = nil
    }

    private func presentW2GWebTorrentPlayer(player: VideoPlayerViewController,
                                            videoService: VideoService,
                                            entity: Torrents,
                                            videos: [Videos],
                                            anilistID: Int,
                                            episode: Int,
                                            animeItem: AnimeItem?) {
        guard !videos.isEmpty else { return }
        if let animeItem {
            TorrentBatchResolver().resolveItemsByAnime(from: videos,
                                                       targetEpisode: episode,
                                                       targetMedia: animeItem,
                                                       name: { $0.videoName }) { [weak self, weak player] result in
                guard let self, let player else { return }
                self.finishW2GWebTorrentPlayer(player: player,
                                               videoService: videoService,
                                               entity: entity,
                                               videos: videos,
                                               anilistID: anilistID,
                                               episode: episode,
                                               animeItem: animeItem,
                                               resolvedFiles: result.resolvedFiles,
                                               resolvedTarget: result.target?.item)
            }
        } else {
            finishW2GWebTorrentPlayer(player: player,
                                      videoService: videoService,
                                      entity: entity,
                                      videos: videos,
                                      anilistID: anilistID,
                                      episode: episode,
                                      animeItem: nil,
                                      resolvedFiles: [],
                                      resolvedTarget: nil)
        }
    }

    private func finishW2GWebTorrentPlayer(player: VideoPlayerViewController,
                                           videoService: VideoService,
                                           entity: Torrents,
                                           videos: [Videos],
                                           anilistID: Int,
                                           episode: Int,
                                           animeItem: AnimeItem?,
                                           resolvedFiles: [TorrentBatchResolver.ResolvedItem<Videos>],
                                           resolvedTarget: Videos?) {
        guard pendingWebTorrentPlayer === player,
              pendingWebTorrentService === videoService,
              client?.media?.torrent == entity.torrentHashString else { return }
        cleanupPendingWebTorrent()
        let sortedVideos = videos.sorted {
            let left = $0.videoIndex?.intValue ?? Int.max
            let right = $1.videoIndex?.intValue ?? Int.max
            if left != right { return left < right }
            return ($0.videoName ?? "") < ($1.videoName ?? "")
        }

        let indexedResolvedFile: TorrentBatchResolver.ResolvedItem<Videos>?
        if let clientIndex = W2GLobby.shared.client?.index,
           !resolvedFiles.isEmpty {
            indexedResolvedFile = resolvedFiles[safe: clientIndex]
        } else {
            indexedResolvedFile = nil
        }
        let selectedResolvedFile = indexedResolvedFile ?? resolvedFiles.first { file in
            guard let resolvedTarget else { return false }
            return file.item == resolvedTarget
        }
        let selectedPosition: Int
        if let selected = selectedResolvedFile?.item ?? resolvedTarget,
           let index = sortedVideos.firstIndex(of: selected) {
            selectedPosition = index
        } else if resolvedFiles.isEmpty,
                  let clientIndex = W2GLobby.shared.client?.index,
                  clientIndex >= 0, clientIndex < sortedVideos.count {
            selectedPosition = clientIndex
        } else if let match = sortedVideos.enumerated().first(where: { _, video in
            TorrentBatchResolver.extractEpisodeNumber(from: video.videoName ?? "") == episode
        }) {
            selectedPosition = match.offset
        } else if episode > 0, episode <= sortedVideos.count {
            selectedPosition = episode - 1
        } else {
            selectedPosition = 0
        }

        let video = sortedVideos[selectedPosition]
        let index = UInt(max(0, video.videoIndex?.intValue ?? selectedPosition))
        videoService.selectFileForStreaming(index)
        _ = videoService.UpdateFilePathForFileIndex(index)

        let selectedMedia = selectedResolvedFile?.media ?? animeItem
        player.videoEntity       = video
        player.torrentHandle     = nil
        player.videoService      = videoService
        player.fileIndex         = index
        player.anilistID         = selectedMedia?.id ?? anilistID
        player.episodeNumber     = selectedResolvedFile?.episodeReference.intValue ?? episode
        player.totalEpisodes     = selectedMedia.map { TorrentBatchResolver.episodeCount(for: $0) }
            ?? (entity.animes?.animeTotalEps?.intValue) ?? animeItem?.episodes ?? 0
        player.allVideos         = sortedVideos
        player.currentVideoIndex = selectedPosition
        player.batchFiles        = []
        player.resolvedVideoFiles = resolvedFiles
        player.onEpisodeChange   = { [weak self] episode, media in
            self?.handleW2GEpisodeChange(episode: episode,
                                         media: media,
                                         fallbackMediaID: anilistID,
                                         fallbackAnimeItem: animeItem,
                                         torrentEntity: entity)
        }
        player.finishMetadataLoading()
    }

    /// Polls the torrent handle until metadata is available, then presents the player.
    private func w2gWaitForMetadataAndPlay(handle: TorrentHandle, entity: Torrents, anilistID: Int, episode: Int, animeItem: AnimeItem?, player: VideoPlayerViewController, attempt: Int = 0) {
        guard pendingNativePlayer === player else { return }
        let snap = TorrentService.sharedTorrentService.withActiveHandle(handle, default: nil) { activeHandle -> TorrentHandle.Snapshot? in
            activeHandle.updateSnapshot()
            return activeHandle.snapshot
        }
        guard let snap else {
            pendingNativePlayer = nil
            player.finishMetadataLoading(error: NSError(domain: "Hayase.W2G.Native", code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Could not read the host's torrent state."]))
            return
        }

        switch snap.state {
        case .downloadingMetadata:
            break
        case .downloading, .finished, .seeding:
            if !snap.files.isEmpty {
                presentW2GPlayer(handle: handle, entity: entity, anilistID: anilistID,
                                 episode: episode, animeItem: animeItem, player: player)
                return
            }
        default:
            break
        }

        // 60 attempts × 1s polling = 60s timeout for metadata fetch.
        guard attempt < 60 else {
            pendingNativePlayer = nil
            player.finishMetadataLoading(error: NSError(domain: "Hayase.W2G.Native", code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Could not fetch torrent metadata from peers."]))
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self, weak player] in
            guard let player else { return }
            self?.w2gWaitForMetadataAndPlay(handle: handle, entity: entity, anilistID: anilistID, episode: episode, animeItem: animeItem, player: player, attempt: attempt + 1)
        }
    }

    /// Present the video player for a W2G torrent with metadata ready.
    private func presentW2GPlayer(handle: TorrentHandle, entity: Torrents, anilistID: Int, episode: Int, animeItem: AnimeItem?, player: VideoPlayerViewController) {
        let context = CoreDataService.sharedCoreDataService.mainQueueContext

        // Create a VideoService to manage streaming for this torrent.
        let vs = VideoService(torrentEntity: entity)
        vs.torrentHandle = handle

        // Resolve the target file index for the episode.
        let snapshot = TorrentService.sharedTorrentService.withActiveHandle(handle, default: nil) { activeHandle -> TorrentHandle.Snapshot? in
            activeHandle.snapshot
        }
        guard let snapshot else {
            failPendingNativePlayback(player, message: "Could not read the host's torrent metadata.")
            return
        }
        let files = snapshot.files
        let resolver = TorrentBatchResolver()
        let filenameResolution = resolver.resolveByFilename(files: files, targetEpisode: episode)
        let videoFiles = files.filter { TorrentBatchResolver.isVideoFile($0.name) }
        let playableFiles: [FileEntry]
        if filenameResolution.resolvedFiles.isEmpty {
            playableFiles = videoFiles
        } else {
            playableFiles = filenameResolution.resolvedFiles.map { $0.entry }
        }
        let playableFileIndices = Set(playableFiles.map { Int($0.index) })
        func fileIndex<T: BinaryInteger>(from value: T?) -> UInt? {
            guard let value else { return nil }
            return UInt(exactly: value)
        }

        func fileIndex<T: BinaryInteger>(from value: T) -> UInt? {
            fileIndex(from: Optional(value))
        }
        let initialFile = filenameResolution.target?.entry ?? playableFiles.first
        guard let targetIndex = fileIndex(from: initialFile?.index) else {
            failPendingNativePlayback(player, message: "The host's torrent has no playable video.")
            return
        }

        // Ensure Video CoreData entities exist for the torrent's files.
        // VideoService.UpdateLocalVideo populates these asynchronously, but for
        // W2G we need them now. Create minimal entries if they don't exist yet.
        let videoReq = NSFetchRequest<Videos>(entityName: Videos.entityName)
        videoReq.predicate = NSPredicate(format: "torrents == %@", entity)
        videoReq.sortDescriptors = [NSSortDescriptor(key: "videoIndex", ascending: true)]
        var videos = ((try? context.fetch(videoReq)) ?? [])
            .filter { playableFileIndices.contains($0.videoIndex?.intValue ?? -1) }
        if videos.isEmpty {
            // Populate from torrent file list.
            for file in playableFiles {
                let v = Videos(context: context)
                v.videoName = file.name
                v.videoSize = NSNumber(value: Double(file.size) / 1024.0 / 1024.0)
                v.videoIndex = NSNumber(value: file.index)
                // Build absolute path from downloadPath + relative file path.
                if let base = snapshot.downloadPath {
                    v.videoPath = base.appendingPathComponent(file.path).path
                } else {
                    v.videoPath = file.path
                }
                v.torrents = entity
                videos.append(v)
            }
            try? context.save()
        }

        let presentResolved: (UInt, [TorrentBatchResolver.ResolvedFile]) -> Void = { [weak self, weak player] resolvedIndex, batchFiles in
            guard let self, let player,
                  self.pendingNativePlayer === player,
                  self.client?.media?.torrent == entity.torrentHashString else { return }
            var targetIndex = resolvedIndex

            // Upstream W2G sends the playlist index. The web maps that index
            // through mediaInfo.resolvedFiles, not the raw torrent file array.
            if let clientIndex = W2GLobby.shared.client?.index, clientIndex >= 0 {
                if let batchFile = batchFiles[safe: clientIndex],
                   let index = fileIndex(from: batchFile.entry.index) {
                    targetIndex = index
                } else if let playableFile = playableFiles[safe: clientIndex],
                          let index = fileIndex(from: playableFile.index) {
                    targetIndex = index
                }
            }

            let targetVideo = videos.first { ($0.videoIndex?.intValue ?? -1) == Int(targetIndex) } ?? videos.first
            guard let video = targetVideo else {
                self.failPendingNativePlayback(player, message: "The host's torrent has no playable video.")
                return
            }

            vs.selectFileForStreaming(targetIndex)
            _ = vs.UpdateFilePathForFileIndex(targetIndex)

            let media = batchFiles.first { fileIndex(from: $0.entry.index) == Optional(targetIndex) }?.media

            self.pendingNativePlayer = nil
            player.videoEntity       = video
            player.torrentHandle     = handle
            player.videoService      = vs
            player.fileIndex         = targetIndex
            player.anilistID         = media?.id ?? anilistID
            player.episodeNumber     = batchFiles.first { fileIndex(from: $0.entry.index) == Optional(targetIndex) }?.episodeReference.intValue ?? episode
            player.totalEpisodes     = media.map { TorrentBatchResolver.episodeCount(for: $0) } ?? (entity.animes?.animeTotalEps?.intValue) ?? animeItem?.episodes ?? 0
            player.allVideos         = videos
            player.currentVideoIndex = videos.firstIndex(of: video) ?? 0
            player.batchFiles        = batchFiles
            player.onEpisodeChange   = { [weak self] episode, media in
                self?.handleW2GEpisodeChange(episode: episode,
                                             media: media,
                                             fallbackMediaID: media?.id ?? anilistID,
                                             fallbackAnimeItem: animeItem,
                                             torrentEntity: entity)
            }
            player.finishMetadataLoading()
        }

        if let targetMedia = animeItem ?? w2gResolverTargetMedia(entity: entity, anilistID: anilistID) {
            resolver.resolve(files: files, targetEpisode: episode, targetMedia: targetMedia) { result in
                let resolvedIndex = result.target.flatMap { fileIndex(from: $0.entry.index) } ?? targetIndex
                presentResolved(resolvedIndex, result.resolvedFiles)
            }
        } else {
            presentResolved(targetIndex, filenameResolution.resolvedFiles)
        }
    }

    private func failPendingNativePlayback(_ player: VideoPlayerViewController, message: String) {
        guard pendingNativePlayer === player else { return }
        pendingNativePlayer = nil
        player.finishMetadataLoading(error: NSError(domain: "Hayase.W2G.Native", code: 4,
            userInfo: [NSLocalizedDescriptionKey: message]))
    }

    private func handleW2GEpisodeChange(episode: Int,
                                        media: AnimeItem?,
                                        fallbackMediaID: Int,
                                        fallbackAnimeItem: AnimeItem?,
                                        torrentEntity: Torrents) {
        if let media {
            presentW2GEpisodeSearch(media: media, episode: episode)
            return
        }

        if let fallbackAnimeItem, hasSearchableTitle(fallbackAnimeItem) {
            presentW2GEpisodeSearch(media: fallbackAnimeItem, episode: episode)
            return
        }

        if let entityMedia = w2gResolverTargetMedia(entity: torrentEntity, anilistID: fallbackMediaID),
           hasSearchableTitle(entityMedia) {
            presentW2GEpisodeSearch(media: entityMedia, episode: episode)
            return
        }

        guard fallbackMediaID > 0 else { return }
        AniListClient.shared.fetchAnimeByIdsResult([fallbackMediaID]) { [weak self] result in
            switch result {
            case .success(let items):
                guard let media = items.first else { return }
                DispatchQueue.main.async {
                    self?.presentW2GEpisodeSearch(media: media, episode: episode)
                }
            case .failure(let error):
                NSLog("[W2G] AniList lookup failed for episode change: %@", error.description)
            }
        }
    }

    private func hasSearchableTitle(_ item: AnimeItem) -> Bool {
        [item.titleUserPreferred, item.titleRomaji, item.titleEnglish, item.titleNative]
            .contains { title in
                guard let value = title?.trimmingCharacters(in: .whitespacesAndNewlines) else { return false }
                return !value.isEmpty
            }
    }

    private func presentW2GEpisodeSearch(media: AnimeItem, episode: Int) {
        MiniPlayerManager.shared.close()

        let searchVC = ExtensionSearchViewController()
        searchVC.animeItem = media
        searchVC.initialEpisode = episode
        searchVC.shouldAutoSelectOnSearch = true

        let presenter = Self.topViewController() ?? self
        searchVC.prepareOverlayPresentation(from: presenter)
        presenter.present(searchVC, animated: true)
    }

    private static func topViewController() -> UIViewController? {
        guard let appDelegate = UIApplication.shared.delegate as? AppDelegate,
              let window = appDelegate.window else { return nil }

        var viewController = window.rootViewController
        while let presented = viewController?.presentedViewController,
              !presented.isBeingDismissed {
            viewController = presented
        }
        return viewController
    }

    private func w2gResolverTargetMedia(entity: Torrents, anilistID: Int) -> AnimeItem? {
        if let anime = entity.animes,
           let id = anime.animeAnilistId?.intValue,
           id > 0 {
            return AniListUtil.animeItem(from: anime)
        }

        guard anilistID > 0 else { return nil }
        return AnimeItem(
            id: anilistID,
            titleEnglish: nil,
            titleRomaji: nil,
            coverURL: nil,
            score: nil,
            status: nil,
            episodes: nil,
            bannerURL: nil,
            genres: [],
            description: nil)
    }
}
