// W2GViewController.swift — W2G lobby page with chat, user list, invite/quit
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

    /// Tracks whether we are showing the landing (create/join) or the lobby (chat) UI.
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

    // MARK: - Lobby UI Elements (shown when a lobby is active)

    private let titleLabel = UILabel()
    private let codeLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let separatorView = UIView()

    private let chatTableView = UITableView()
    private let userListTableView = UITableView()

    private let quitButton = UIButton(type: .system)
    private let inviteButton = UIButton(type: .system)
    private let messageField = UITextField()
    private let sendButton = UIButton(type: .system)

    private let bottomBar = UIStackView()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        navigationItem.title = "Watch Together"

        // Listen for lobby changes so we can swap between landing/lobby.
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
        updateUI()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateUI()
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
    }

    // MARK: - State Management

    private func updateUI() {
        let hasLobby = client != nil
        if hasLobby && !isShowingLobby {
            showLobbyUI()
        } else if !hasLobby && isShowingLobby {
            showLandingUI()
        } else if !hasLobby {
            showLandingUI()
        } else {
            // Already showing lobby, just refresh
            codeLabel.text = client?.code ?? ""
            reloadData()
        }
    }

    private func showLandingUI() {
        isShowingLobby = false
        landingScrollView.isHidden = false
        // Hide lobby elements
        for v in lobbyViews { v.isHidden = true }
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

    /// All lobby-specific views (hidden when showing landing).
    private var lobbyViews: [UIView] {
        [titleLabel, codeLabel, subtitleLabel, separatorView,
         chatTableView, userListTableView, bottomBar]
    }

    // MARK: - Landing UI Setup (create/join page, mirrors web /app/w2g/+page.ts)

    private func setupLandingUI() {
        landingScrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(landingScrollView)

        landingStack.axis = .vertical
        landingStack.spacing = 16
        landingStack.alignment = .fill
        landingStack.translatesAutoresizingMaskIntoConstraints = false
        landingScrollView.addSubview(landingStack)

        // Title
        landingTitleLabel.text = "Watch Together"
        landingTitleLabel.font = .nunito(ofSize: 24, weight: .bold)
        landingTitleLabel.textColor = .white

        // Subtitle
        landingSubtitleLabel.text = "Watch videos together with friends in real-time. Create a lobby or join an existing one."
        landingSubtitleLabel.font = .nunito(ofSize: 14)
        landingSubtitleLabel.textColor = UIColor(white: 0.5, alpha: 1)
        landingSubtitleLabel.numberOfLines = 0

        // Separator
        landingSeparator.backgroundColor = UIColor(white: 0.2, alpha: 1)
        landingSeparator.translatesAutoresizingMaskIntoConstraints = false

        // Create lobby button
        createButton.setTitle("Create Lobby", for: .normal)
        createButton.titleLabel?.font = .nunito(ofSize: 16, weight: .semibold)
        createButton.setTitleColor(.white, for: .normal)
        createButton.backgroundColor = UIColor(red: 0.35, green: 0.6, blue: 1.0, alpha: 1.0)
        createButton.layer.cornerRadius = 10
        createButton.addTarget(self, action: #selector(createLobbyTapped), for: .touchUpInside)
        createButton.translatesAutoresizingMaskIntoConstraints = false

        // "or join" label
        joinSeparatorLabel.text = "or join an existing lobby"
        joinSeparatorLabel.font = .nunito(ofSize: 14)
        joinSeparatorLabel.textColor = UIColor(white: 0.5, alpha: 1)
        joinSeparatorLabel.textAlignment = .center

        // Join code field
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
        joinCodeField.translatesAutoresizingMaskIntoConstraints = false

        // Join button
        joinButton.setTitle("Join Lobby", for: .normal)
        joinButton.titleLabel?.font = .nunito(ofSize: 16, weight: .semibold)
        joinButton.setTitleColor(.white, for: .normal)
        joinButton.backgroundColor = UIColor(white: 0.15, alpha: 1)
        joinButton.layer.cornerRadius = 10
        joinButton.addTarget(self, action: #selector(joinLobbyTapped), for: .touchUpInside)
        joinButton.translatesAutoresizingMaskIntoConstraints = false

        landingStack.addArrangedSubview(landingTitleLabel)
        landingStack.addArrangedSubview(landingSubtitleLabel)
        landingStack.addArrangedSubview(landingSeparator)
        landingStack.addArrangedSubview(createButton)
        landingStack.addArrangedSubview(joinSeparatorLabel)
        landingStack.addArrangedSubview(joinCodeField)
        landingStack.addArrangedSubview(joinButton)

        let safe = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            landingScrollView.topAnchor.constraint(equalTo: safe.topAnchor),
            landingScrollView.leadingAnchor.constraint(equalTo: safe.leadingAnchor),
            landingScrollView.trailingAnchor.constraint(equalTo: safe.trailingAnchor),
            landingScrollView.bottomAnchor.constraint(equalTo: safe.bottomAnchor),

            landingStack.topAnchor.constraint(equalTo: landingScrollView.topAnchor, constant: 24),
            landingStack.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 24),
            landingStack.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -24),

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
        // Start hidden — landing is shown first
        for v in lobbyViews { v.isHidden = true }
    }

    // MARK: - Setup Header (matches web's space-y-0.5 p-3 header)

    private func setupHeader() {
        // Title: "Watch Together" + code label
        titleLabel.text = "Watch Together"
        titleLabel.font = .nunito(ofSize: 24, weight: .bold)
        titleLabel.textColor = .white

        codeLabel.text = client?.code ?? ""
        codeLabel.font = .nunito(ofSize: 18, weight: .semibold)
        codeLabel.textColor = UIColor(white: 0.5, alpha: 1)

        subtitleLabel.text = "Watch videos together with friends in real-time. You can invite others to your lobby and chat while watching."
        subtitleLabel.font = .nunito(ofSize: 14)
        subtitleLabel.textColor = UIColor(white: 0.5, alpha: 1)
        subtitleLabel.numberOfLines = 0

        separatorView.backgroundColor = UIColor(white: 0.2, alpha: 1)

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
        chatTableView.register(W2GChatCell.self, forCellReuseIdentifier: W2GChatCell.reuseID)
        chatTableView.dataSource = self
        chatTableView.delegate = self
        chatTableView.transform = CGAffineTransform(scaleX: 1, y: -1) // flip for bottom-anchored scrolling
        chatTableView.keyboardDismissMode = .onDrag
        chatTableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(chatTableView)

        // User list table
        userListTableView.backgroundColor = .clear
        userListTableView.separatorStyle = .none
        userListTableView.register(W2GUserCell.self, forCellReuseIdentifier: W2GUserCell.reuseID)
        userListTableView.dataSource = self
        userListTableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(userListTableView)
    }

    // MARK: - Setup Bottom Bar (matches web's flex mt-4 gap-2)

    private func setupBottomBar() {
        // Quit button
        configureIconButton(quitButton, lucideId: "door-open", action: #selector(quitTapped))

        // Invite button
        configureIconButton(inviteButton, lucideId: "user-plus", action: #selector(inviteTapped))

        // Message input
        messageField.placeholder = "Message"
        messageField.font = .nunito(ofSize: 14)
        messageField.textColor = .white
        messageField.backgroundColor = UIColor(white: 0.1, alpha: 1)
        messageField.layer.cornerRadius = 8
        messageField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 0))
        messageField.leftViewMode = .always
        messageField.returnKeyType = .send
        messageField.delegate = self
        messageField.autocorrectionType = .no

        // Send button
        configureIconButton(sendButton, lucideId: "send-horizontal", action: #selector(sendTapped))

        bottomBar.axis = .horizontal
        bottomBar.spacing = 8
        bottomBar.alignment = .center
        bottomBar.translatesAutoresizingMaskIntoConstraints = false

        bottomBar.addArrangedSubview(quitButton)
        bottomBar.addArrangedSubview(inviteButton)
        bottomBar.addArrangedSubview(messageField)
        bottomBar.addArrangedSubview(sendButton)

        view.addSubview(bottomBar)
    }

    private func configureIconButton(_ button: UIButton, lucideId: String, action: Selector) {
        let config = UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)
        button.setImage(UIImage.hayaseIcon(lucideId, withConfiguration: config), for: .normal)
        button.tintColor = .white
        button.addTarget(self, action: action, for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 40),
            button.heightAnchor.constraint(equalToConstant: 40)
        ])
    }

    // MARK: - Layout Constraints
    //
    // Responsive layout mirroring web's `flex md:flex-row flex-col-reverse`:
    //   - Narrow screens (iPhone): chat on top, user list hidden (toggle-able)
    //     or stacked below when there's enough vertical space.
    //   - Wide screens (iPad / landscape): chat left, user list right (md:w-72).

    /// Constraints activated only in wide (side-by-side) layout.
    private var wideLayoutConstraints: [NSLayoutConstraint] = []
    /// Constraints activated only in narrow (stacked) layout.
    private var narrowLayoutConstraints: [NSLayoutConstraint] = []
    /// Tracks current layout class to avoid redundant re-layouts.
    private var isWideLayout: Bool?

    private func setupLobbyConstraints() {
        let pad: CGFloat = 16
        let safe = view.safeAreaLayoutGuide

        // Always-active constraints
        NSLayoutConstraint.activate([
            // Title row
            titleLabel.topAnchor.constraint(equalTo: safe.topAnchor, constant: pad),
            titleLabel.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: pad),

            codeLabel.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            codeLabel.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 16),

            // Subtitle: web uses space-y-0.5 = 2pt gap
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            subtitleLabel.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: pad),
            subtitleLabel.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -pad),

            // Separator: web uses <Separator class='!my-6' /> = 24pt vertical margin
            separatorView.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 24),
            separatorView.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: pad),
            separatorView.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -pad),
            separatorView.heightAnchor.constraint(equalToConstant: 0.5),

            // Bottom bar (always pinned to bottom)
            bottomBar.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: pad),
            bottomBar.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -pad),
            bottomBar.bottomAnchor.constraint(equalTo: safe.bottomAnchor, constant: -pad),
            bottomBar.heightAnchor.constraint(equalToConstant: 44),

            // Message field fills remaining space in bottom bar
            messageField.heightAnchor.constraint(equalToConstant: 36),
        ])

        // Wide layout: chat left, user list right (md:flex-row, md:w-72 = 288pt)
        wideLayoutConstraints = [
            userListTableView.topAnchor.constraint(equalTo: separatorView.bottomAnchor, constant: 8),
            userListTableView.trailingAnchor.constraint(equalTo: safe.trailingAnchor),
            userListTableView.widthAnchor.constraint(equalToConstant: 288), // md:w-72
            userListTableView.bottomAnchor.constraint(equalTo: bottomBar.topAnchor, constant: -8),

            chatTableView.topAnchor.constraint(equalTo: separatorView.bottomAnchor, constant: 8),
            chatTableView.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 16), // px-4
            chatTableView.trailingAnchor.constraint(equalTo: userListTableView.leadingAnchor),
            chatTableView.bottomAnchor.constraint(equalTo: bottomBar.topAnchor, constant: -8),
        ]

        // Narrow layout: chat fills width, user list hidden
        // (mirrors web's `flex-col-reverse` mobile where user list collapses)
        narrowLayoutConstraints = [
            chatTableView.topAnchor.constraint(equalTo: separatorView.bottomAnchor, constant: 8),
            chatTableView.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 16), // px-4
            chatTableView.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -16),
            chatTableView.bottomAnchor.constraint(equalTo: bottomBar.topAnchor, constant: -8),
        ]

        updateLayoutForCurrentWidth()
    }

    /// Activates the appropriate layout based on screen width.
    /// Web breakpoint: `md:` = 768px. On iOS, treat width >= 600pt as "wide".
    private func updateLayoutForCurrentWidth() {
        let wide = view.bounds.width >= 600
        guard wide != isWideLayout else { return }
        isWideLayout = wide

        if wide {
            NSLayoutConstraint.deactivate(narrowLayoutConstraints)
            NSLayoutConstraint.activate(wideLayoutConstraints)
            userListTableView.isHidden = false
        } else {
            NSLayoutConstraint.deactivate(wideLayoutConstraints)
            NSLayoutConstraint.activate(narrowLayoutConstraints)
            userListTableView.isHidden = true
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

    @objc private func dismissKeyboard() {
        view.endEditing(true)
    }

    @objc private func createLobbyTapped() {
        // Mirrors web /app/w2g/+page.ts:
        //   const lastVal = get(server.last)
        //   w2globby.value ??= new W2GClient(code, true,
        //     lastVal?.media.id ? { mediaId: lastVal.media.id, episode: lastVal.episode, torrent: lastVal.id } : undefined)
        //
        // Grab the currently-playing torrent state (like web's `server.last`)
        // so peers who join later receive the host's media via `sendInitialSessionState`.
        let media = currentPlayerMediaState()
        W2GLobby.shared.createHostLobby(media: media)
        // updateUI() is called automatically via the W2GLobby.didChange notification.
    }

    @objc private func joinLobbyTapped() {
        guard let code = joinCodeField.text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !code.isEmpty else { return }
        joinCodeField.resignFirstResponder()
        // Mirrors web /app/w2g/[id]/+page.ts: joins an existing lobby by code.
        W2GLobby.shared.joinLobby(code: code)
    }

    @objc private func quitTapped() {
        W2GLobby.shared.leave()
        // updateUI() swaps back to landing via the notification.
    }

    @objc private func inviteTapped() {
        guard let link = client?.inviteLink else { return }
        let ac = UIActivityViewController(
            activityItems: ["Invite people to your Watch Together lobby", URL(string: link) as Any],
            applicationActivities: nil
        )
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
        client?.peers.values.map(\.user) ?? []
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
            guard let cell = tableView.dequeueReusableCell(withIdentifier: W2GChatCell.reuseID, for: indexPath) as? W2GChatCell else { return UITableViewCell() }
            let msgs = reversedMessages
            if let msg = msgs[safe: indexPath.row] {
                // Message grouping (mirrors web Messages.svelte groupMessages):
                // In the flipped table, row 0 = newest. The visual "above" is row+1.
                // Show header (name+time) when this is the first message in a group
                // (the message visually above is from a different user or doesn't exist).
                // Show avatar when this is the last message in a group (the message
                // visually below is from a different user or doesn't exist).
                let prevSameUser = msgs[safe: indexPath.row + 1]?.user.id == msg.user.id
                let nextSameUser = indexPath.row > 0 && msgs[safe: indexPath.row - 1]?.user.id == msg.user.id
                let showHeader = !prevSameUser  // first in group (top in visual order)
                let showAvatar = !nextSameUser  // last in group (bottom in visual order)
                cell.configure(with: msg, showHeader: showHeader, showAvatar: showAvatar)
            }
            cell.contentView.transform = CGAffineTransform(scaleX: 1, y: -1) // un-flip cell
            return cell
        } else {
            guard let cell = tableView.dequeueReusableCell(withIdentifier: W2GUserCell.reuseID, for: indexPath) as? W2GUserCell else { return UITableViewCell() }
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
        if textField === joinCodeField {
            joinLobbyTapped()
        } else {
            sendCurrentMessage()
        }
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
            self.chatTableView.reloadData()
            // Auto-scroll to newest message (row 0 in flipped table).
            // Mirrors web's `overflow-anchor: auto` + `content-end`.
            if (client.messages.count) > 0 {
                self.chatTableView.scrollToRow(at: IndexPath(row: 0, section: 0), at: .top, animated: true)
            }
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
        // Check mini-player first, then any fullscreen player in the app.
        let player = MiniPlayerManager.shared.activePlayer ?? findPresentedPlayer()
        guard let player,
              let hash = w2gTorrentHash(from: player),
              player.anilistID > 0 else {
            return nil
        }
        return W2GMediaState(torrent: hash, mediaId: player.anilistID, episode: player.episodeNumber)
    }

    private func w2gTorrentHash(from player: VideoPlayerViewController) -> String? {
        if let hash = player.torrentHandle?.infoHashes.best.hex.trimmingCharacters(in: .whitespacesAndNewlines),
           !hash.isEmpty {
            return hash
        }

        let hash = player.videoEntity?.torrents?.torrentHashString?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return hash.isEmpty ? nil : hash
    }

    /// Walk the entire presented-VC chain from the root to find a VideoPlayerViewController.
    /// This is broader than `findActiveW2GPlayer()` which only checks from `self`.
    private func findPresentedPlayer() -> VideoPlayerViewController? {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = windowScene.windows.first(where: { $0.isKeyWindow })?.rootViewController else {
            return nil
        }
        var vc: UIViewController? = rootVC
        while let presented = vc?.presentedViewController {
            if let player = presented as? VideoPlayerViewController { return player }
            vc = presented
        }
        return nil
    }

    /// Add the host's torrent by hash and present the player.
    /// Mirrors web's W2GClient `_onMsg` media handler:
    ///   const media = (await client.single(mediaId)).data?.Media
    ///   server.play(torrent, media, episode)
    private func playW2GMedia(_ mediaState: W2GMediaState) {
        let hash = mediaState.torrent
        let anilistID = mediaState.mediaId
        let episode = mediaState.episode
        guard !hash.isEmpty else { return }

        // Close any existing mini-player before starting a new session.
        MiniPlayerManager.shared.close()

        // Show a HUD while preparing.
        let hud = UIAlertController(title: "W2G", message: "Adding torrent from host…", preferredStyle: .alert)
        present(hud, animated: true)

        // Mirrors web: `const media = (await client.single(mediaId)).data?.Media`
        // Fetch AniList info first (if we have an ID), then add the torrent.
        if anilistID > 0 {
            AniListClient.shared.fetchAnimeByIds([anilistID]) { [weak self] items in
                guard let self else { return }
                self.continueW2GPlay(hash: hash, anilistID: anilistID, episode: episode, animeItem: items.first, hud: hud)
            }
        } else {
            continueW2GPlay(hash: hash, anilistID: anilistID, episode: episode, animeItem: nil, hud: hud)
        }
    }

    /// Second half of `playW2GMedia`: add the torrent by hash and present the player.
    /// Mirrors web's `server.play(torrent, media, episode)`.
    private func continueW2GPlay(hash: String, anilistID: Int, episode: Int, animeItem: AnimeItem?, hud: UIAlertController) {
        let entity = findOrCreateW2GTorrent(hash: hash, anilistID: anilistID, animeItem: animeItem)

        // Set initial AniList state (mirrors web: `client.setInitialState(media, episode)`).
        AniListTracking.shared.setInitialState(anilistID: anilistID, episode: episode)

        switch TorrentBackendManager.shared.currentKind {
        case .webtorrent:
            playW2GWebTorrent(entity: entity,
                              anilistID: anilistID,
                              episode: episode,
                              animeItem: animeItem,
                              hud: hud)
        case .native:
            playW2GNative(hash: hash,
                          entity: entity,
                          anilistID: anilistID,
                          episode: episode,
                          animeItem: animeItem,
                          hud: hud)
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
            entity.torrentName = animeItem?.titleEnglish ?? animeItem?.titleRomaji ?? hash
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

    private func playW2GNative(hash: String, entity: Torrents, anilistID: Int, episode: Int, animeItem: AnimeItem?, hud: UIAlertController) {
        // Add the torrent by hash (magnet URI).
        // Mirrors web: `native.playTorrent(torrent, media.id, episode)`.
        guard let handle = TorrentService.sharedTorrentService.readdTorrent(hash: hash, magnetLink: nil) else {
            hud.dismiss(animated: true) { [weak self] in
                self?.showW2GError("Could not add the host's torrent.")
            }
            return
        }

        w2gWaitForMetadataAndPlay(handle: handle,
                                  entity: entity,
                                  anilistID: anilistID,
                                  episode: episode,
                                  animeItem: animeItem,
                                  hud: hud)
    }

    private func playW2GWebTorrent(entity: Torrents, anilistID: Int, episode: Int, animeItem: AnimeItem?, hud: UIAlertController) {
        hud.message = "Fetching WebTorrent metadata…"

        let videoService = VideoService(torrentEntity: entity, episode: episode)
        let context = CoreDataService.sharedCoreDataService.mainQueueContext
        var observer: NSObjectProtocol?
        var didFinish = false

        let finish: (Result<[Videos], Error>) -> Void = { [weak self, weak videoService] result in
            guard let self else { return }
            guard !didFinish else { return }
            didFinish = true
            if let observer {
                NotificationCenter.default.removeObserver(observer)
            }

            hud.dismiss(animated: true) { [weak self, weak videoService] in
                guard let self, let videoService else { return }
                switch result {
                case .success(let videos):
                    self.presentW2GWebTorrentPlayer(videoService: videoService,
                                                    entity: entity,
                                                    videos: videos,
                                                    anilistID: anilistID,
                                                    episode: episode,
                                                    animeItem: animeItem)
                case .failure(let error):
                    self.showW2GError(error.localizedDescription)
                }
            }
        }

        observer = NotificationCenter.default.addObserver(
            forName: NSNotification.Name(VideoService.LocalVideosDidUpdateNotification),
            object: nil,
            queue: .main
        ) { [weak videoService] _ in
            guard let videoService else { return }

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

        DispatchQueue.main.asyncAfter(deadline: .now() + 60) { [weak videoService] in
            guard !didFinish else { return }
            let error = videoService?.lastError ?? NSError(
                domain: "Hayase.W2G.WebTorrent",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Could not fetch WebTorrent metadata from peers."])
            finish(.failure(error))
        }
    }

    private func presentW2GWebTorrentPlayer(videoService: VideoService,
                                            entity: Torrents,
                                            videos: [Videos],
                                            anilistID: Int,
                                            episode: Int,
                                            animeItem: AnimeItem?) {
        guard !videos.isEmpty else { return }
        let sortedVideos = videos.sorted {
            let left = $0.videoIndex?.intValue ?? Int.max
            let right = $1.videoIndex?.intValue ?? Int.max
            if left != right { return left < right }
            return ($0.videoName ?? "") < ($1.videoName ?? "")
        }

        let selectedPosition: Int
        if let clientIndex = W2GLobby.shared.client?.index,
           clientIndex >= 0,
           clientIndex < sortedVideos.count {
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
        let index = UInt(video.videoIndex?.intValue ?? selectedPosition)
        _ = videoService.UpdateFilePathForFileIndex(index)

        MiniPlayerManager.shared.close()
        let player = VideoPlayerViewController()
        player.videoEntity       = video
        player.torrentHandle     = nil
        player.videoService      = videoService
        player.fileIndex         = index
        player.anilistID         = anilistID
        player.episodeNumber     = episode
        player.totalEpisodes     = (entity.animes?.animeTotalEps?.intValue) ?? animeItem?.episodes ?? 0
        player.allVideos         = sortedVideos
        player.currentVideoIndex = selectedPosition
        Router.shared.navigateToPlayer(player, hostTabIndex: tabBarController?.selectedIndex)
    }

    private func showW2GError(_ message: String) {
        let alert = UIAlertController(title: "Error", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .cancel))
        present(alert, animated: true)
    }

    /// Polls the torrent handle until metadata is available, then presents the player.
    private func w2gWaitForMetadataAndPlay(handle: TorrentHandle, entity: Torrents, anilistID: Int, episode: Int, animeItem: AnimeItem?, hud: UIAlertController, attempt: Int = 0) {
        let snap = TorrentService.sharedTorrentService.withActiveHandle(handle, default: nil) { activeHandle -> TorrentHandle.Snapshot? in
            activeHandle.updateSnapshot()
            return activeHandle.snapshot
        }
        guard let snap else { return }

        // Update HUD status.
        let peers = snap.numberOfPeers
        switch snap.state {
        case .downloadingMetadata:
            hud.message = peers > 0
                ? "Fetching metadata… (\(peers) peer\(peers == 1 ? "" : "s"))"
                : "Connecting to DHT and trackers…"
        case .downloading, .finished, .seeding:
            if !snap.files.isEmpty {
                // Metadata ready — present the player.
                hud.dismiss(animated: true) { [weak self] in
                    self?.presentW2GPlayer(handle: handle, entity: entity, anilistID: anilistID, episode: episode, animeItem: animeItem)
                }
                return
            }
            hud.message = "Preparing file list…"
        default:
            hud.message = "Connecting to peers…"
        }

        // 60 attempts × 1s polling = 60s timeout for metadata fetch.
        guard attempt < 60 else {
            hud.dismiss(animated: true) { [weak self] in
                let alert = UIAlertController(title: "Timeout", message: "Could not fetch torrent metadata from peers.", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "OK", style: .cancel))
                self?.present(alert, animated: true)
            }
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.w2gWaitForMetadataAndPlay(handle: handle, entity: entity, anilistID: anilistID, episode: episode, animeItem: animeItem, hud: hud, attempt: attempt + 1)
        }
    }

    /// Present the video player for a W2G torrent with metadata ready.
    private func presentW2GPlayer(handle: TorrentHandle, entity: Torrents, anilistID: Int, episode: Int, animeItem: AnimeItem?) {
        let context = CoreDataService.sharedCoreDataService.mainQueueContext

        // Create a VideoService to manage streaming for this torrent.
        let vs = VideoService(torrentEntity: entity)
        vs.torrentHandle = handle

        // Resolve the target file index for the episode.
        let snapshot = TorrentService.sharedTorrentService.withActiveHandle(handle, default: nil) { activeHandle -> TorrentHandle.Snapshot? in
            activeHandle.snapshot
        }
        guard let snapshot else { return }
        let files = snapshot.files
        let resolver = TorrentBatchResolver()
        let resolvedVideos = resolver.resolveAll(files: files)
        let playableFiles = resolvedVideos.isEmpty ? files : resolvedVideos.map { $0.entry }
        let playableFileIndices = Set(playableFiles.map { Int($0.index) })
        func fileIndex<T: BinaryInteger>(from value: T?) -> UInt? {
            guard let value else { return nil }
            return UInt(exactly: value)
        }

        func fileIndex<T: BinaryInteger>(from value: T) -> UInt? {
            fileIndex(from: Optional(value))
        }
        guard var targetIndex = fileIndex(from: playableFiles.first?.index) else { return }
        if let match = resolver.resolve(files: files, targetEpisode: episode),
           let index = fileIndex(from: match.entry.index) {
            targetIndex = index
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

        let presentResolved: (UInt) -> Void = { [weak self] resolvedIndex in
            guard let self else { return }
            var targetIndex = resolvedIndex

            // Upstream W2G sends the playlist index, not the libtorrent file index.
            // Translate it through the playable video list before selecting a file.
            if let clientIndex = W2GLobby.shared.client?.index,
               clientIndex > 0,
               clientIndex < playableFiles.count {
                guard let playableFile = playableFiles[safe: clientIndex],
                      let index = fileIndex(from: playableFile.index) else { return }
                targetIndex = index
            }

            let targetVideo = videos.first { ($0.videoIndex?.intValue ?? -1) == Int(targetIndex) } ?? videos.first
            guard let video = targetVideo else { return }

            vs.selectFileForStreaming(targetIndex)
            _ = vs.UpdateFilePathForFileIndex(targetIndex)

            MiniPlayerManager.shared.close()
            let player = VideoPlayerViewController()
            player.videoEntity       = video
            player.torrentHandle     = handle
            player.videoService      = vs
            player.fileIndex         = targetIndex
            player.anilistID         = anilistID
            player.episodeNumber     = episode
            player.totalEpisodes     = (entity.animes?.animeTotalEps?.intValue) ?? animeItem?.episodes ?? 0
            player.allVideos         = videos
            player.currentVideoIndex = videos.firstIndex(of: video) ?? 0
            Router.shared.navigateToPlayer(player, hostTabIndex: self.tabBarController?.selectedIndex)
        }

        if let targetMedia = animeItem ?? w2gResolverTargetMedia(entity: entity, anilistID: anilistID) {
            resolver.resolve(files: files, targetEpisode: episode, targetMedia: targetMedia) { result in
                let resolvedIndex = result.target.flatMap { fileIndex(from: $0.entry.index) } ?? targetIndex
                presentResolved(resolvedIndex)
            }
        } else {
            presentResolved(targetIndex)
        }
    }

    private func w2gResolverTargetMedia(entity: Torrents, anilistID: Int) -> AnimeItem? {
        if let anime = entity.animes,
           let id = anime.animeAnilistId?.intValue,
           id > 0 {
            return AnimeItem(
                id: id,
                titleEnglish: anime.animeTitleEnglish,
                titleRomaji: anime.animeTitleJapanese,
                coverURL: anime.animeImgL ?? anime.animeImgM,
                score: anime.animeScore?.floatValue,
                status: anime.animeStatus,
                episodes: anime.animeTotalEps?.intValue,
                bannerURL: anime.animeImgS,
                genres: [],
                description: anime.animeDescription)
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

// MARK: - W2GChatCell (mirrors Messages.svelte)
//
// Web layout per message group:
//   <div class='flex flex-row mt-3' [flex-row-reverse if outgoing]>
//     <img class='w-10 h-10 rounded-full p-1 mt-auto' />     ← avatar at bottom of group
//     <div class='flex flex-col px-2 items-start [items-end]'>
//       <div class='pb-1 flex flex-row items-center px-1'>
//         <div class='font-bold text-sm'>{name}</div>         ← 14px bold
//         <div class='text-muted-foreground pl-2 text-[10px]'>{time}</div>
//       </div>
//       {#each _messages as message}
//         <div class='bg-muted py-2 px-3 rounded-t-xl rounded-r-xl mb-1 text-xs'>  ← 12px
//           {message}
//         </div>
//       {/each}
//     </div>
//   </div>
//
// Key details:
// - Avatar: 40pt with 4pt padding = 32pt visible, anchored to bottom (mt-auto)
// - Incoming: avatar left, items-start, rounded-t-xl rounded-r-xl (no bottom-left round)
// - Outgoing: avatar right (flex-row-reverse), items-end, bg-theme, rounded-t-xl rounded-l-xl

private final class W2GChatCell: UITableViewCell {
    static let reuseID = "W2GChatCell"

    // Subviews
    private let avatarImageView = UIImageView()
    private let headerRow = UIView()       // contains name + time
    private let nameLabel = UILabel()
    private let timeLabel = UILabel()
    private let bubbleBackground = UIView()
    private let bubbleLabel = UILabel()

    // Pre-built constraint sets toggled via isActive
    private var incomingConstraints: [NSLayoutConstraint] = []
    private var outgoingConstraints: [NSLayoutConstraint] = []
    private var headerVisibleConstraint: NSLayoutConstraint!   // bubble top → header bottom
    private var headerHiddenConstraint: NSLayoutConstraint!    // bubble top → cell top (no header)
    private var headerTopConstraint: NSLayoutConstraint!       // header top → cell top

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .none

        let cv = contentView
        let avatarSize: CGFloat = 32  // w-10 h-10 p-1 → visible 32pt

        // Avatar: rounded-full mt-auto
        avatarImageView.layer.cornerRadius = avatarSize / 2
        avatarImageView.clipsToBounds = true
        avatarImageView.contentMode = .scaleAspectFill
        avatarImageView.translatesAutoresizingMaskIntoConstraints = false
        cv.addSubview(avatarImageView)

        // Header row (name + time)
        headerRow.translatesAutoresizingMaskIntoConstraints = false
        cv.addSubview(headerRow)

        nameLabel.font = .nunito(ofSize: 14, weight: .bold) // text-sm
        nameLabel.textColor = .white
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        headerRow.addSubview(nameLabel)

        timeLabel.font = .nunito(ofSize: 10) // text-[10px]
        timeLabel.textColor = UIColor(white: 0.5, alpha: 1)
        timeLabel.translatesAutoresizingMaskIntoConstraints = false
        headerRow.addSubview(timeLabel)

        // Bubble
        bubbleBackground.translatesAutoresizingMaskIntoConstraints = false
        cv.addSubview(bubbleBackground)

        bubbleLabel.font = .nunito(ofSize: 12) // text-xs
        bubbleLabel.textColor = .white
        bubbleLabel.numberOfLines = 0
        bubbleLabel.translatesAutoresizingMaskIntoConstraints = false
        bubbleBackground.addSubview(bubbleLabel)

        // --- Always-active constraints ---
        NSLayoutConstraint.activate([
            avatarImageView.widthAnchor.constraint(equalToConstant: avatarSize),
            avatarImageView.heightAnchor.constraint(equalToConstant: avatarSize),
            avatarImageView.bottomAnchor.constraint(equalTo: cv.bottomAnchor, constant: -4),

            nameLabel.topAnchor.constraint(equalTo: headerRow.topAnchor),
            nameLabel.bottomAnchor.constraint(equalTo: headerRow.bottomAnchor),
            nameLabel.leadingAnchor.constraint(equalTo: headerRow.leadingAnchor, constant: 4),
            timeLabel.centerYAnchor.constraint(equalTo: nameLabel.centerYAnchor),
            timeLabel.leadingAnchor.constraint(equalTo: nameLabel.trailingAnchor, constant: 8),

            bubbleLabel.topAnchor.constraint(equalTo: bubbleBackground.topAnchor, constant: 8),
            bubbleLabel.leadingAnchor.constraint(equalTo: bubbleBackground.leadingAnchor, constant: 12),
            bubbleLabel.trailingAnchor.constraint(equalTo: bubbleBackground.trailingAnchor, constant: -12),
            bubbleLabel.bottomAnchor.constraint(equalTo: bubbleBackground.bottomAnchor, constant: -8),

            bubbleBackground.bottomAnchor.constraint(equalTo: cv.bottomAnchor, constant: -4),
        ])

        // --- Toggleable constraints ---
        headerTopConstraint = headerRow.topAnchor.constraint(equalTo: cv.topAnchor, constant: 12) // mt-3
        headerVisibleConstraint = bubbleBackground.topAnchor.constraint(equalTo: headerRow.bottomAnchor, constant: 4)
        headerHiddenConstraint = bubbleBackground.topAnchor.constraint(equalTo: cv.topAnchor, constant: 2)

        incomingConstraints = [
            avatarImageView.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 4),
            headerRow.leadingAnchor.constraint(equalTo: avatarImageView.trailingAnchor, constant: 8),
            bubbleBackground.leadingAnchor.constraint(equalTo: avatarImageView.trailingAnchor, constant: 8),
            // max-w-[calc(100%-100px)] in web — leave 100pt for avatar side + margin
            bubbleBackground.trailingAnchor.constraint(lessThanOrEqualTo: cv.trailingAnchor, constant: -100),
        ]

        outgoingConstraints = [
            avatarImageView.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -4),
            headerRow.trailingAnchor.constraint(equalTo: avatarImageView.leadingAnchor, constant: -8),
            bubbleBackground.trailingAnchor.constraint(equalTo: avatarImageView.leadingAnchor, constant: -8),
            // max-w-[calc(100%-100px)] in web — leave 100pt for avatar side + margin
            bubbleBackground.leadingAnchor.constraint(greaterThanOrEqualTo: cv.leadingAnchor, constant: 100),
        ]
    }

    required init?(coder: NSCoder) { fatalError() }

    override func prepareForReuse() {
        super.prepareForReuse()
        NSLayoutConstraint.deactivate(incomingConstraints)
        NSLayoutConstraint.deactivate(outgoingConstraints)
        headerVisibleConstraint.isActive = false
        headerHiddenConstraint.isActive = false
        headerTopConstraint.isActive = false
        avatarImageView.image = nil
        avatarImageView.alpha = 1
    }

    func configure(with message: W2GChatMessage, showHeader: Bool, showAvatar: Bool) {
        nameLabel.text = message.user.name
        timeLabel.text = DateFormatter.localizedString(from: message.date, dateStyle: .none, timeStyle: .short)
        bubbleLabel.text = message.message

        let isOutgoing = message.type == .outgoing

        // Direction
        NSLayoutConstraint.activate(isOutgoing ? outgoingConstraints : incomingConstraints)

        // Header (name + time) — first message in group
        headerRow.isHidden = !showHeader
        headerTopConstraint.isActive = showHeader
        headerVisibleConstraint.isActive = showHeader
        headerHiddenConstraint.isActive = !showHeader

        // Avatar — visible only for last message in group (mt-auto positioning)
        avatarImageView.alpha = showAvatar ? 1 : 0
        if showAvatar { loadAvatar(url: message.user.avatarURL) }

        // Bubble color: bg-muted (incoming) vs bg-theme (outgoing)
        bubbleBackground.backgroundColor = isOutgoing
            ? UIColor(red: 0.35, green: 0.6, blue: 1.0, alpha: 1.0)
            : UIColor(white: 0.15, alpha: 1.0)

        // Corner rounding — web: rounded-t-xl + one bottom corner
        // Incoming: all except bottom-left (rounded-r-xl)
        // Outgoing: all except bottom-right (rounded-l-xl)
        bubbleBackground.layer.cornerRadius = 12
        bubbleBackground.layer.maskedCorners = isOutgoing
            ? [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner]
            : [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMaxXMaxYCorner]
    }

    private func loadAvatar(url: String?) {
        avatarImageView.image = nil
        let urlStr = url ?? W2GChatUser.defaultAvatarURL
        guard let url = URL(string: urlStr) else {
            avatarImageView.backgroundColor = UIColor(white: 0.2, alpha: 1)
            return
        }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data, let img = UIImage(data: data) else { return }
            DispatchQueue.main.async { self?.avatarImageView.image = img }
        }.resume()
    }
}

// MARK: - W2GUserCell (mirrors UserList.svelte)
//
// Web layout per user:
//   <div class='flex items-center pb-2'>
//     <img class='w-10 h-10 rounded-full p-1 mt-auto' />   ← 32pt visible avatar
//     <div class='text-md pl-2'>{name}</div>                ← 16px, 8pt left margin
//     <ExternalLink size='18' class='ml-auto text-blue-600' /> ← AniList link
//   </div>

private final class W2GUserCell: UITableViewCell {
    static let reuseID = "W2GUserCell"

    private let avatarImageView = UIImageView()
    private let nameLabel = UILabel()
    private let linkButton = UIButton(type: .system)

    private var userID: String = ""

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .none

        let avatarSize: CGFloat = 32  // w-10 h-10 p-1 → 32pt visible

        // Avatar: rounded-full
        avatarImageView.layer.cornerRadius = avatarSize / 2
        avatarImageView.clipsToBounds = true
        avatarImageView.contentMode = .scaleAspectFill
        avatarImageView.translatesAutoresizingMaskIntoConstraints = false

        // Name: text-md (16px), pl-2 (8pt)
        nameLabel.font = .nunito(ofSize: 16)
        nameLabel.textColor = .white
        nameLabel.translatesAutoresizingMaskIntoConstraints = false

        // External link button: ml-auto text-blue-600, ExternalLink size=18
        let linkConfig = UIImage.SymbolConfiguration(pointSize: 16, weight: .regular)
        linkButton.setImage(UIImage.hayaseIcon("external-link", withConfiguration: linkConfig), for: .normal)
        linkButton.tintColor = UIColor(red: 0.22, green: 0.42, blue: 0.93, alpha: 1.0) // blue-600
        linkButton.translatesAutoresizingMaskIntoConstraints = false
        linkButton.addTarget(self, action: #selector(openProfile), for: .touchUpInside)

        contentView.addSubview(avatarImageView)
        contentView.addSubview(nameLabel)
        contentView.addSubview(linkButton)

        NSLayoutConstraint.activate([
            // Avatar: left with padding, pb-2 = 8pt bottom, px-5 = 20pt from web
            avatarImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20), // px-5
            avatarImageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            avatarImageView.widthAnchor.constraint(equalToConstant: avatarSize),
            avatarImageView.heightAnchor.constraint(equalToConstant: avatarSize),
            avatarImageView.topAnchor.constraint(greaterThanOrEqualTo: contentView.topAnchor, constant: 4),
            avatarImageView.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -8), // pb-2

            // Name: pl-2 = 8pt
            nameLabel.leadingAnchor.constraint(equalTo: avatarImageView.trailingAnchor, constant: 8),
            nameLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

            // Link button: ml-auto (trailing), match px-5 padding
            linkButton.leadingAnchor.constraint(greaterThanOrEqualTo: nameLabel.trailingAnchor, constant: 8),
            linkButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20), // px-5
            linkButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            linkButton.widthAnchor.constraint(equalToConstant: 28),
            linkButton.heightAnchor.constraint(equalToConstant: 28),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func openProfile() {
        guard !userID.isEmpty,
              let url = URL(string: "https://anilist.co/user/" + userID) else { return }
        UIApplication.shared.open(url)
    }

    func configure(with user: W2GChatUser) {
        nameLabel.text = user.name
        userID = user.id
        avatarImageView.image = nil
        guard let url = URL(string: user.resolvedAvatarURL) else {
            avatarImageView.backgroundColor = UIColor(white: 0.2, alpha: 1)
            return
        }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data, let img = UIImage(data: data) else { return }
            DispatchQueue.main.async { self?.avatarImageView.image = img }
        }.resume()
    }
}
