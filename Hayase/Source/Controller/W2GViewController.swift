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
            image: UIImage(systemName: "person.2"),
            selectedImage: UIImage(systemName: "person.2.fill"))
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
        landingTitleLabel.font = .systemFont(ofSize: 24, weight: .bold)
        landingTitleLabel.textColor = .white

        // Subtitle
        landingSubtitleLabel.text = "Watch videos together with friends in real-time. Create a lobby or join an existing one."
        landingSubtitleLabel.font = .systemFont(ofSize: 14)
        landingSubtitleLabel.textColor = UIColor(white: 0.5, alpha: 1)
        landingSubtitleLabel.numberOfLines = 0

        // Separator
        landingSeparator.backgroundColor = UIColor(white: 0.2, alpha: 1)
        landingSeparator.translatesAutoresizingMaskIntoConstraints = false

        // Create lobby button
        createButton.setTitle("Create Lobby", for: .normal)
        createButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        createButton.setTitleColor(.white, for: .normal)
        createButton.backgroundColor = UIColor(red: 0.35, green: 0.6, blue: 1.0, alpha: 1.0)
        createButton.layer.cornerRadius = 10
        createButton.addTarget(self, action: #selector(createLobbyTapped), for: .touchUpInside)
        createButton.translatesAutoresizingMaskIntoConstraints = false

        // "or join" label
        joinSeparatorLabel.text = "or join an existing lobby"
        joinSeparatorLabel.font = .systemFont(ofSize: 14)
        joinSeparatorLabel.textColor = UIColor(white: 0.5, alpha: 1)
        joinSeparatorLabel.textAlignment = .center

        // Join code field
        joinCodeField.placeholder = "Enter lobby code"
        joinCodeField.font = .systemFont(ofSize: 16)
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
        joinButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
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
        titleLabel.font = .systemFont(ofSize: 24, weight: .bold)
        titleLabel.textColor = .white

        codeLabel.text = client?.code ?? ""
        codeLabel.font = .systemFont(ofSize: 18, weight: .semibold)
        codeLabel.textColor = UIColor(white: 0.5, alpha: 1)

        subtitleLabel.text = "Watch videos together with friends in real-time. You can invite others to your lobby and chat while watching."
        subtitleLabel.font = .systemFont(ofSize: 14)
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
        // Quit button (DoorOpen icon equivalent)
        configureIconButton(quitButton, systemName: "door.left.hand.open", action: #selector(quitTapped))

        // Invite button (UserPlus icon equivalent)
        configureIconButton(inviteButton, systemName: "person.badge.plus", action: #selector(inviteTapped))

        // Message input
        messageField.placeholder = "Message"
        messageField.font = .systemFont(ofSize: 14)
        messageField.textColor = .white
        messageField.backgroundColor = UIColor(white: 0.1, alpha: 1)
        messageField.layer.cornerRadius = 8
        messageField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 0))
        messageField.leftViewMode = .always
        messageField.returnKeyType = .send
        messageField.delegate = self
        messageField.autocorrectionType = .no

        // Send button (SendHorizontal icon equivalent)
        configureIconButton(sendButton, systemName: "paperplane.fill", action: #selector(sendTapped))

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

    private func configureIconButton(_ button: UIButton, systemName: String, action: Selector) {
        let config = UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)
        button.setImage(UIImage(systemName: systemName, withConfiguration: config), for: .normal)
        button.tintColor = .white
        button.addTarget(self, action: action, for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 40),
            button.heightAnchor.constraint(equalToConstant: 40)
        ])
    }

    // MARK: - Layout Constraints

    private func setupLobbyConstraints() {
        let pad: CGFloat = 16
        let safe = view.safeAreaLayoutGuide

        NSLayoutConstraint.activate([
            // Title row
            titleLabel.topAnchor.constraint(equalTo: safe.topAnchor, constant: pad),
            titleLabel.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: pad),

            codeLabel.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            codeLabel.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 16),

            // Subtitle
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            subtitleLabel.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: pad),
            subtitleLabel.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -pad),

            // Separator
            separatorView.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 16),
            separatorView.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: pad),
            separatorView.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -pad),
            separatorView.heightAnchor.constraint(equalToConstant: 0.5),

            // User list (right side, 72pt wide matching web md:w-72)
            userListTableView.topAnchor.constraint(equalTo: separatorView.bottomAnchor, constant: 8),
            userListTableView.trailingAnchor.constraint(equalTo: safe.trailingAnchor),
            userListTableView.widthAnchor.constraint(equalToConstant: 200),

            // Chat (fills remaining space)
            chatTableView.topAnchor.constraint(equalTo: separatorView.bottomAnchor, constant: 8),
            chatTableView.leadingAnchor.constraint(equalTo: safe.leadingAnchor),
            chatTableView.trailingAnchor.constraint(equalTo: userListTableView.leadingAnchor),

            // Chat and user list fill the space down to the bottom bar.
            // IMPORTANT: Must use equalTo, not greaterThanOrEqualTo. UITableView has
            // no intrinsic height, so greaterThanOrEqualTo leaves the height ambiguous
            // (Auto Layout can satisfy all constraints with height = 0, making the
            // tables invisible even though messages exist in the data model).
            chatTableView.bottomAnchor.constraint(equalTo: bottomBar.topAnchor, constant: -8),
            userListTableView.bottomAnchor.constraint(equalTo: bottomBar.topAnchor, constant: -8),
            bottomBar.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: pad),
            bottomBar.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -pad),
            bottomBar.bottomAnchor.constraint(equalTo: safe.bottomAnchor, constant: -pad),
            bottomBar.heightAnchor.constraint(equalToConstant: 44),

            // Message field fills remaining space
            messageField.heightAnchor.constraint(equalToConstant: 36),
        ])
    }

    // MARK: - Actions

    @objc private func dismissKeyboard() {
        view.endEditing(true)
    }

    @objc private func createLobbyTapped() {
        // Mirrors web /app/w2g/+page.ts: creates a host lobby and redirects to lobby view.
        W2GLobby.shared.createHostLobby()
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
            let cell = tableView.dequeueReusableCell(withIdentifier: W2GChatCell.reuseID, for: indexPath) as! W2GChatCell
            let msgs = reversedMessages
            if indexPath.row < msgs.count {
                cell.configure(with: msgs[indexPath.row])
            }
            cell.contentView.transform = CGAffineTransform(scaleX: 1, y: -1) // un-flip cell
            return cell
        } else {
            let cell = tableView.dequeueReusableCell(withIdentifier: W2GUserCell.reuseID, for: indexPath) as! W2GUserCell
            let users = sortedUsers
            if indexPath.row < users.count {
                cell.configure(with: users[indexPath.row])
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
            self?.chatTableView.reloadData()
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
            AnimeService.sharedAnimeService.fetchAnimeByIds([anilistID]) { [weak self] items in
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
        // Add the torrent by hash (magnet URI).
        // Mirrors web: `native.playTorrent(torrent, media.id, episode)`.
        guard let handle = TorrentService.sharedTorrentService.readdTorrent(hash: hash, magnetLink: nil) else {
            hud.dismiss(animated: true) { [weak self] in
                let alert = UIAlertController(title: "Error", message: "Could not add the host's torrent.", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "OK", style: .cancel))
                self?.present(alert, animated: true)
            }
            return
        }

        // Find or create a Torrents CoreData entity for the hash.
        let context = CoreDataService.sharedCoreDataService.mainQueueContext
        let entity: Torrents = {
            let req = NSFetchRequest<Torrents>(entityName: Torrents.entityName)
            req.predicate = NSPredicate(format: "torrentHashString == %@", hash)
            req.fetchLimit = 1
            if let existing = (try? context.fetch(req))?.first { return existing }
            let t = Torrents(context: context)
            t.torrentHashString = hash
            return t
        }()

        // Link to AniList anime entity (create if needed from fetched item).
        // Mirrors web: `server.play(torrent, media, episode)` where `media` is the AniList Media object.
        if anilistID > 0 {
            let animeReq = Animes.fetchRequest()
            animeReq.predicate = NSPredicate(format: "animeAnilistId == %d", anilistID)
            if let existing = (try? context.fetch(animeReq))?.first as? Animes {
                entity.animes = existing
            } else if let item = animeItem {
                // Create Animes entity from AniList data (mirrors ExtensionSearchVC.startDownload).
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

        // Set initial AniList state (mirrors web: `client.setInitialState(media, episode)`).
        AniListTracking.shared.setInitialState(anilistID: anilistID, episode: episode)

        // Wait for metadata then present the player.
        w2gWaitForMetadataAndPlay(handle: handle, entity: entity, anilistID: anilistID, episode: episode, hud: hud)
    }

    /// Polls the torrent handle until metadata is available, then presents the player.
    private func w2gWaitForMetadataAndPlay(handle: TorrentHandle, entity: Torrents, anilistID: Int, episode: Int, hud: UIAlertController, attempt: Int = 0) {
        handle.updateSnapshot()
        let snap = handle.snapshot

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
                    self?.presentW2GPlayer(handle: handle, entity: entity, anilistID: anilistID, episode: episode)
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
            self?.w2gWaitForMetadataAndPlay(handle: handle, entity: entity, anilistID: anilistID, episode: episode, hud: hud, attempt: attempt + 1)
        }
    }

    /// Present the video player for a W2G torrent with metadata ready.
    private func presentW2GPlayer(handle: TorrentHandle, entity: Torrents, anilistID: Int, episode: Int) {
        let context = CoreDataService.sharedCoreDataService.mainQueueContext

        // Create a VideoService to manage streaming for this torrent.
        let vs = VideoService(torrentEntity: entity)
        vs.torrentHandle = handle

        // Resolve the target file index for the episode.
        let resolver = TorrentBatchResolver()
        var targetIndex: UInt = 0
        if let match = resolver.resolve(files: handle.snapshot.files, targetEpisode: episode) {
            targetIndex = UInt(match.entry.index)
        }

        // Use the W2G client's file index if set (the host may have sent an
        // index event before or along with the media event).
        if let clientIndex = W2GLobby.shared.client?.index, clientIndex > 0 {
            targetIndex = UInt(clientIndex)
        }

        vs.selectFileForStreaming(targetIndex)

        // Ensure Video CoreData entities exist for the torrent's files.
        // VideoService.UpdateLocalVideo populates these asynchronously, but for
        // W2G we need them now. Create minimal entries if they don't exist yet.
        let videoReq = NSFetchRequest<Videos>(entityName: Videos.entityName)
        videoReq.predicate = NSPredicate(format: "torrents == %@", entity)
        videoReq.sortDescriptors = [NSSortDescriptor(key: "videoIndex", ascending: true)]
        var videos = (try? context.fetch(videoReq)) ?? []
        if videos.isEmpty {
            // Populate from torrent file list.
            let snap = handle.snapshot
            for (i, file) in snap.files.enumerated() {
                let v = Videos(context: context)
                v.videoIndex = NSNumber(value: i)
                // Build absolute path from downloadPath + relative file path.
                if let base = snap.downloadPath {
                    v.videoPath = base.appendingPathComponent(file.path).path
                } else {
                    v.videoPath = file.path
                }
                v.torrents = entity
                videos.append(v)
            }
            try? context.save()
        }

        // Pick the target video entity.
        let targetVideo = videos.first { ($0.videoIndex?.intValue ?? -1) == Int(targetIndex) } ?? videos.first
        guard let video = targetVideo else { return }

        _ = vs.UpdateFilePathForFileIndex(targetIndex)

        // Present the player.
        MiniPlayerManager.shared.close()
        let player = VideoPlayerViewController()
        player.videoEntity       = video
        player.torrentHandle     = handle
        player.videoService      = vs
        player.fileIndex         = targetIndex
        player.anilistID         = anilistID
        player.episodeNumber     = episode
        player.totalEpisodes     = (entity.animes?.animeTotalEps?.intValue) ?? 0
        player.allVideos         = videos
        player.currentVideoIndex = videos.firstIndex(of: video) ?? 0
        player.modalPresentationStyle = .fullScreen
        player.modalTransitionStyle   = .crossDissolve
        present(player, animated: true)
    }
}

// MARK: - W2GChatCell (mirrors Messages.svelte)

private final class W2GChatCell: UITableViewCell {
    static let reuseID = "W2GChatCell"

    private let avatarImageView = UIImageView()
    private let nameLabel = UILabel()
    private let timeLabel = UILabel()
    private let bubbleLabel = UILabel()
    private let bubbleBackground = UIView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .none

        avatarImageView.layer.cornerRadius = 18
        avatarImageView.clipsToBounds = true
        avatarImageView.contentMode = .scaleAspectFill
        avatarImageView.translatesAutoresizingMaskIntoConstraints = false

        nameLabel.font = .systemFont(ofSize: 13, weight: .bold)
        nameLabel.textColor = .white
        nameLabel.translatesAutoresizingMaskIntoConstraints = false

        timeLabel.font = .systemFont(ofSize: 10)
        timeLabel.textColor = UIColor(white: 0.5, alpha: 1)
        timeLabel.translatesAutoresizingMaskIntoConstraints = false

        bubbleBackground.layer.cornerRadius = 12
        bubbleBackground.translatesAutoresizingMaskIntoConstraints = false

        bubbleLabel.font = .systemFont(ofSize: 13)
        bubbleLabel.textColor = .white
        bubbleLabel.numberOfLines = 0
        bubbleLabel.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(avatarImageView)
        contentView.addSubview(nameLabel)
        contentView.addSubview(timeLabel)
        contentView.addSubview(bubbleBackground)
        bubbleBackground.addSubview(bubbleLabel)

        NSLayoutConstraint.activate([
            avatarImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            avatarImageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),
            avatarImageView.widthAnchor.constraint(equalToConstant: 36),
            avatarImageView.heightAnchor.constraint(equalToConstant: 36),

            nameLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            nameLabel.leadingAnchor.constraint(equalTo: avatarImageView.trailingAnchor, constant: 8),

            timeLabel.centerYAnchor.constraint(equalTo: nameLabel.centerYAnchor),
            timeLabel.leadingAnchor.constraint(equalTo: nameLabel.trailingAnchor, constant: 8),

            bubbleBackground.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 4),
            bubbleBackground.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            bubbleBackground.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -60),
            bubbleBackground.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),

            bubbleLabel.topAnchor.constraint(equalTo: bubbleBackground.topAnchor, constant: 8),
            bubbleLabel.leadingAnchor.constraint(equalTo: bubbleBackground.leadingAnchor, constant: 12),
            bubbleLabel.trailingAnchor.constraint(equalTo: bubbleBackground.trailingAnchor, constant: -12),
            bubbleLabel.bottomAnchor.constraint(equalTo: bubbleBackground.bottomAnchor, constant: -8),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(with message: W2GChatMessage) {
        nameLabel.text = message.user.name
        timeLabel.text = DateFormatter.localizedString(from: message.date, dateStyle: .none, timeStyle: .short)
        bubbleLabel.text = message.message

        let isOutgoing = message.type == .outgoing
        // Web uses bg-muted for incoming, bg-theme for outgoing
        bubbleBackground.backgroundColor = isOutgoing
            ? UIColor(red: 0.35, green: 0.6, blue: 1.0, alpha: 1.0)  // theme color
            : UIColor(white: 0.15, alpha: 1.0)  // muted

        loadAvatar(url: message.user.avatarURL)
    }

    private func loadAvatar(url: String?) {
        avatarImageView.image = nil
        let urlStr = url ?? W2GChatUser.defaultAvatarURL
        guard let url = URL(string: urlStr) else {
            avatarImageView.backgroundColor = UIColor(white: 0.2, alpha: 1)
            return
        }
        // Simple async image load (no external lib needed for this use case).
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data, let img = UIImage(data: data) else { return }
            DispatchQueue.main.async { self?.avatarImageView.image = img }
        }.resume()
    }
}

// MARK: - W2GUserCell (mirrors UserList.svelte)

private final class W2GUserCell: UITableViewCell {
    static let reuseID = "W2GUserCell"

    private let avatarImageView = UIImageView()
    private let nameLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .none

        avatarImageView.layer.cornerRadius = 18
        avatarImageView.clipsToBounds = true
        avatarImageView.contentMode = .scaleAspectFill
        avatarImageView.translatesAutoresizingMaskIntoConstraints = false

        nameLabel.font = .systemFont(ofSize: 15)
        nameLabel.textColor = .white
        nameLabel.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(avatarImageView)
        contentView.addSubview(nameLabel)

        NSLayoutConstraint.activate([
            avatarImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            avatarImageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            avatarImageView.widthAnchor.constraint(equalToConstant: 36),
            avatarImageView.heightAnchor.constraint(equalToConstant: 36),
            avatarImageView.topAnchor.constraint(greaterThanOrEqualTo: contentView.topAnchor, constant: 4),
            avatarImageView.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -4),

            nameLabel.leadingAnchor.constraint(equalTo: avatarImageView.trailingAnchor, constant: 8),
            nameLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -12),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(with user: W2GChatUser) {
        nameLabel.text = user.name
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
