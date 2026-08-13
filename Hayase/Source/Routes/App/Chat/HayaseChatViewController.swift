//
//  HayaseChatViewController.swift
//  Hayase
//
//  Made by scigward.
//
//  Mirrors: src/routes/app/chat/+page.svelte,
//           src/lib/components/ui/irc/irc.svelte + interface.svelte
//
//  Fixed in this pass:
//  - The connection now lives in `IRCLobby.shared` (mirrors `$irc` in
//    modules/irc/lobby.ts) instead of a private property on this class, so
//    it persists across navigation and the sidebar's status dot
//    (HayaseSidebarListView) can actually observe it — matching
//    sidebarlist.svelte's `{#if $irc}<StatusDot .../>{/if}` on the chat
//    button.
//  - The userlist is now an always-visible side panel on wide layouts
//    (mirrors `UserList.svelte`) and hidden entirely on narrow ones,
//    matching `W2GViewController`'s existing wide/narrow constraint-set
//    pattern exactly (600pt breakpoint, hide-on-narrow rather than a
//    stacked variant — W2G already made that same simplification, so this
//    matches established precedent instead of inventing a new one).
//  - The message input no longer grows to a fixed 120pt on first layout:
//    `UITextView` needs `isScrollEnabled = false` plus a manually-updated
//    height constraint to size itself from its content.
//  - Messages now use the same flipped-table-view + bubble-cell + grouping
//    technique as `W2GChatCell` (`W2GViewController.swift`), instead of a
//    plain one-row-per-message list with a manual scroll-to-bottom. This
//    also closes a gap flagged earlier and left unfixed: interface's shared
//    `Messages.svelte` (used by both W2G and IRC chat) visually clusters
//    consecutive messages from the same user under one avatar/header;
//    W2G's Swift port already implements that grouping, this now does too.
//  - Tapping a user in the userlist opens their AniList profile
//    (`https://anilist.co/user/<id>` via `UIApplication.shared.open`),
//    mirroring the pragmatic substitute W2G already uses for interface's
//    in-app `ChatProfile` popup. Hidden for guests, matching
//    `ChatProfile.svelte`'s `!user.guest` check.
//
//  On literally sharing UI code with W2G (asked about directly, initially
//  answered "not practical" — revisited after that answer turned out to be
//  wrong in practice): the userlist row is now `ChatUserListCell`
//  (`Components/UI/Chat/ChatUserListCell.swift`), a single implementation
//  used by both this screen and `W2GViewController`, behind a small
//  `ChatListUser` protocol both `IRCUser` and `W2GChatUser` conform to.
//  This replaced a hand-copied `IRCUserCell` that had already drifted from
//  the `W2GUserCell` it was copied from in three visible ways: an extra
//  vertical divider between the message list and userlist that W2G's
//  layout never had, a narrower fixed width (180pt vs W2G's 288pt /
//  `md:w-72`) that truncated usernames, and 0pt top padding below the
//  header separator instead of W2G's 8pt. All three were real, reported
//  bugs, not style preferences — copying the *technique* instead of the
//  *implementation* (the approach originally taken here) still leaves room
//  for exactly this kind of drift between two hand-maintained copies.
//  Messages remain two separate cells (`IRCMessageCell` /`W2GChatCell`) —
//  their underlying message types diverge more (IRC has no encryption
//  concept, W2G's `type`/`date` handling differs) and nothing has been
//  reported wrong with them, so that extraction is left for if/when it's
//  actually needed rather than done speculatively here.
//
//  Still not included: keyboard "Enter-to-send / Shift+Enter-for-newline" —
//  physical-keyboard modifier detection is nontrivial on iOS and low-value
//  for a touch-first app; the Send button is the primary (and only)
//  submission path here.

import UIKit

// MARK: - HayaseChatViewController

final class HayaseChatViewController: UIViewController {
    private let agreedKey = "hayase_chat_prevAgreed"
    private let stack = UIStackView()
    private let chatContainer = UIView()

    private let messagesTableView = UITableView()
    private var messages: [IRCChatMessage] = []
    /// Newest-first, matching the flipped table (row 0 = visually at the
    /// bottom = newest). Mirrors W2GViewController's `reversedMessages`.
    private var reversedMessages: [IRCChatMessage] { messages.reversed() }
    private let loadingIndicator = UIActivityIndicatorView(style: .medium)
    private let loadingLabel = UILabel()

    private let userListTableView = UITableView()
    private var users: [IRCUser] = []

    private let inputTextView = UITextView()
    private var inputTextViewHeightConstraint: NSLayoutConstraint!
    private let placeholderLabel = UILabel()
    private let sendButton = UIButton(type: .system)
    private let exitButton = UIButton(type: .system)
    private let userCountLabel = UILabel()

    private static let minInputHeight: CGFloat = 36
    private static let maxInputHeight: CGFloat = 120

    // Wide/narrow adaptive layout for the userlist panel — mirrors
    // W2GViewController's wideLayoutConstraints/narrowLayoutConstraints/
    // isWideLayout/updateLayoutForCurrentWidth pattern exactly.
    private var wideLayoutConstraints: [NSLayoutConstraint] = []
    private var narrowLayoutConstraints: [NSLayoutConstraint] = []
    private var isWideLayout: Bool?

    override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
        configureTabBarItem()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureTabBarItem()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.HayaseTheme.background
        setup()
        setupChatContainer()
        render()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if !chatContainer.isHidden {
            updateLayoutForCurrentWidth()
        }
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: { _ in
            self.updateLayoutForCurrentWidth()
        })
    }

    /// Mirrors W2GViewController's `updateLayoutForCurrentWidth()`. Web
    /// breakpoint: `md:` = 768px; treated as 600pt on iOS, same as W2G.
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

    private func configureTabBarItem() {
        tabBarItem = UITabBarItem(
            title: "Chat",
            image: UIImage.hayaseIcon("messages-square"),
            selectedImage: UIImage.hayaseIcon("messages-square"))
    }

    private func setup() {
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 0
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            stack.widthAnchor.constraint(lessThanOrEqualToConstant: 480),
        ])
    }

    private func render() {
        stack.arrangedSubviews.forEach {
            stack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        let agreed = UserDefaults.standard.bool(forKey: agreedKey)
        stack.isHidden = agreed
        chatContainer.isHidden = !agreed
        if agreed {
            attachToLobby()
        } else {
            renderWarning()
        }
    }

    private func renderWarning() {
        let warning = UIImageView(image: UIImage.hayaseIcon("triangle-alert"))
        warning.translatesAutoresizingMaskIntoConstraints = false
        warning.tintColor = UIColor(red: 245/255, green: 158/255, blue: 11/255, alpha: 1)
        warning.contentMode = .scaleAspectFit
        stack.addArrangedSubview(warning)
        NSLayoutConstraint.activate([
            warning.widthAnchor.constraint(equalToConstant: 192),
            warning.heightAnchor.constraint(equalToConstant: 192),
        ])

        let title = UILabel()
        title.text = "Content Warning"
        title.font = .nunito(ofSize: 30, weight: .bold)
        title.textColor = UIColor.HayaseTheme.foreground
        title.textAlignment = .center
        stack.addArrangedSubview(title)

        addText("This chat is completely unmoderated and may contain content that is not suitable for all audiences.",
                top: 20)
        addText("Be wary of impersonation.\nStaff will NEVER show up on this chat.",
                top: 8)

        let buttons = UIStackView()
        buttons.translatesAutoresizingMaskIntoConstraints = false
        buttons.axis = .horizontal
        buttons.spacing = 12
        buttons.alignment = .center
        buttons.distribution = .fillEqually
        if let lastSubview = stack.arrangedSubviews.last {
            stack.setCustomSpacing(28, after: lastSubview)
        }
        stack.addArrangedSubview(buttons)

        let nope = makeButton(title: "Nope", background: UIColor.HayaseTheme.accent, foreground: UIColor.HayaseTheme.foreground)
        nope.addTarget(self, action: #selector(nopeTapped), for: .touchUpInside)
        let cont = makeButton(title: "Continue", background: UIColor(red: 0.49, green: 0.11, blue: 0.11, alpha: 1),
                              foreground: UIColor.HayaseTheme.foreground)
        cont.addTarget(self, action: #selector(continueTapped), for: .touchUpInside)
        buttons.addArrangedSubview(nope)
        buttons.addArrangedSubview(cont)
        NSLayoutConstraint.activate([
            buttons.widthAnchor.constraint(equalToConstant: 220),
            buttons.heightAnchor.constraint(equalToConstant: 44),
        ])
    }

    private func addText(_ text: String,
                         top: CGFloat,
                         size: CGFloat = 16,
                         weight: UIFont.Weight = .regular,
                         color: UIColor = UIColor.HayaseTheme.mutedForeground) {
        let label = UILabel()
        label.text = text
        label.font = .nunito(ofSize: size, weight: weight)
        label.textColor = color
        label.textAlignment = .center
        label.numberOfLines = 0
        if let previous = stack.arrangedSubviews.last {
            stack.setCustomSpacing(top, after: previous)
        }
        stack.addArrangedSubview(label)
    }

    private func makeButton(title: String, background: UIColor, foreground: UIColor) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = .nunito(ofSize: 16, weight: .bold)
        button.tintColor = foreground
        button.backgroundColor = background
        button.layer.cornerRadius = 6
        return button
    }

    @objc private func nopeTapped() {
        Router.shared.navigate(.home, hostTabIndex: tabBarController?.selectedIndex)
    }

    @objc private func continueTapped() {
        UserDefaults.standard.set(true, forKey: agreedKey)
        render()
    }

    // MARK: - Chat panel
    // Mirrors interface.svelte's layout: title + description, a message
    // list with a userlist side panel, and a bottom input bar with an exit
    // button and a send button.

    private func setupChatContainer() {
        chatContainer.translatesAutoresizingMaskIntoConstraints = false
        chatContainer.isHidden = true
        view.addSubview(chatContainer)
        NSLayoutConstraint.activate([
            chatContainer.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            chatContainer.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            chatContainer.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            chatContainer.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
        ])

        let titleLabel = UILabel()
        titleLabel.text = "Global App Chat"
        titleLabel.font = .nunito(ofSize: 22, weight: .bold)
        titleLabel.textColor = UIColor.HayaseTheme.foreground

        let descriptionLabel = UILabel()
        descriptionLabel.text = "Chat with other users of the app, share your thoughts, ask questions and have fun!"
        descriptionLabel.font = .nunito(ofSize: 14)
        descriptionLabel.textColor = UIColor.HayaseTheme.mutedForeground
        descriptionLabel.numberOfLines = 0

        userCountLabel.text = "0 online"
        userCountLabel.font = .nunito(ofSize: 13, weight: .semibold)
        userCountLabel.textColor = UIColor.HayaseTheme.mutedForeground

        let headerStack = UIStackView(arrangedSubviews: [titleLabel, descriptionLabel, userCountLabel])
        headerStack.axis = .vertical
        headerStack.spacing = 4
        headerStack.translatesAutoresizingMaskIntoConstraints = false
        headerStack.setCustomSpacing(8, after: descriptionLabel)
        chatContainer.addSubview(headerStack)

        let separator = UIView()
        separator.backgroundColor = UIColor.HayaseTheme.border
        separator.translatesAutoresizingMaskIntoConstraints = false
        chatContainer.addSubview(separator)

        messagesTableView.translatesAutoresizingMaskIntoConstraints = false
        messagesTableView.backgroundColor = .clear
        messagesTableView.separatorStyle = .none
        messagesTableView.dataSource = self
        messagesTableView.register(IRCMessageCell.self, forCellReuseIdentifier: IRCMessageCell.reuseID)
        messagesTableView.keyboardDismissMode = .interactive
        messagesTableView.estimatedRowHeight = 56
        messagesTableView.rowHeight = UITableView.automaticDimension
        // Flip trick for "always anchored to newest message" auto-scroll,
        // matching W2GViewController's chatTableView exactly — avoids the
        // fragile "call scrollToRow after every reload" approach the first
        // pass used.
        messagesTableView.transform = CGAffineTransform(scaleX: 1, y: -1)
        chatContainer.addSubview(messagesTableView)

        // Mirrors UserList.svelte's side panel on wide layouts; hidden
        // entirely on narrow ones (see updateLayoutForCurrentWidth). No
        // separator between the two columns — W2GViewController's
        // equivalent panel doesn't have one either (its userListTableView
        // sits directly against chatTableView's trailing edge), and this
        // used to add one that didn't match, which is what looked like a
        // stray vertical line.
        userListTableView.translatesAutoresizingMaskIntoConstraints = false
        userListTableView.backgroundColor = .clear
        userListTableView.separatorStyle = .none
        userListTableView.dataSource = self
        userListTableView.register(ChatUserListCell.self, forCellReuseIdentifier: ChatUserListCell.reuseID)
        userListTableView.estimatedRowHeight = 44
        userListTableView.rowHeight = UITableView.automaticDimension
        chatContainer.addSubview(userListTableView)

        // Mirrors irc.svelte's `{#await $irc}` loading state, shown until
        // both registration and our own channel join complete.
        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
        loadingIndicator.color = UIColor.HayaseTheme.mutedForeground
        loadingIndicator.isHidden = true
        chatContainer.addSubview(loadingIndicator)

        loadingLabel.text = "Loading..."
        loadingLabel.font = .nunito(ofSize: 16)
        loadingLabel.textColor = UIColor.HayaseTheme.mutedForeground
        loadingLabel.translatesAutoresizingMaskIntoConstraints = false
        loadingLabel.isHidden = true
        chatContainer.addSubview(loadingLabel)

        let inputBar = UIView()
        inputBar.translatesAutoresizingMaskIntoConstraints = false
        chatContainer.addSubview(inputBar)

        exitButton.setImage(UIImage.hayaseIcon("door-open"), for: .normal)
        exitButton.tintColor = UIColor.HayaseTheme.foreground
        exitButton.addTarget(self, action: #selector(exitTapped), for: .touchUpInside)
        exitButton.translatesAutoresizingMaskIntoConstraints = false

        // isScrollEnabled = false is required for a UITextView to size
        // itself from its content under Auto Layout — with it left at the
        // default `true`, the `>=36 / <=120` height constraints below had
        // nothing driving them toward a natural size and settled on 120pt
        // on first layout, producing an oversized input box.
        inputTextView.isScrollEnabled = false
        inputTextView.font = .nunito(ofSize: 15)
        inputTextView.textColor = UIColor.HayaseTheme.foreground
        inputTextView.backgroundColor = UIColor.HayaseTheme.input
        inputTextView.layer.cornerRadius = 8
        inputTextView.textContainerInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        inputTextView.translatesAutoresizingMaskIntoConstraints = false
        inputTextView.delegate = self
        inputBar.addSubview(inputTextView)

        placeholderLabel.text = "Message"
        placeholderLabel.font = .nunito(ofSize: 15)
        placeholderLabel.textColor = UIColor.HayaseTheme.mutedForeground
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        placeholderLabel.isUserInteractionEnabled = false
        inputTextView.addSubview(placeholderLabel)

        sendButton.setImage(UIImage.hayaseIcon("send-horizontal"), for: .normal)
        sendButton.tintColor = UIColor.HayaseTheme.foreground
        sendButton.addTarget(self, action: #selector(sendTapped), for: .touchUpInside)
        sendButton.translatesAutoresizingMaskIntoConstraints = false

        inputBar.addSubview(exitButton)
        inputBar.addSubview(sendButton)

        inputTextViewHeightConstraint = inputTextView.heightAnchor.constraint(equalToConstant: Self.minInputHeight)

        NSLayoutConstraint.activate([
            headerStack.topAnchor.constraint(equalTo: chatContainer.topAnchor, constant: 12),
            headerStack.leadingAnchor.constraint(equalTo: chatContainer.leadingAnchor, constant: 16),
            headerStack.trailingAnchor.constraint(equalTo: chatContainer.trailingAnchor, constant: -16),

            separator.topAnchor.constraint(equalTo: headerStack.bottomAnchor, constant: 12),
            separator.leadingAnchor.constraint(equalTo: chatContainer.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: chatContainer.trailingAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1),

            messagesTableView.leadingAnchor.constraint(equalTo: chatContainer.leadingAnchor),

            loadingIndicator.centerXAnchor.constraint(equalTo: messagesTableView.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: messagesTableView.centerYAnchor, constant: -12),
            loadingLabel.centerXAnchor.constraint(equalTo: messagesTableView.centerXAnchor),
            loadingLabel.topAnchor.constraint(equalTo: loadingIndicator.bottomAnchor, constant: 8),

            // Input bar always spans the full width, under both the chat
            // and userlist columns — mirrors W2GViewController's bottomBar,
            // which is likewise constrained to the safe area directly
            // rather than to chatTableView.
            inputBar.leadingAnchor.constraint(equalTo: chatContainer.leadingAnchor, constant: 16),
            inputBar.trailingAnchor.constraint(equalTo: chatContainer.trailingAnchor, constant: -16),
            inputBar.bottomAnchor.constraint(equalTo: chatContainer.bottomAnchor, constant: -12),

            exitButton.leadingAnchor.constraint(equalTo: inputBar.leadingAnchor),
            exitButton.bottomAnchor.constraint(equalTo: inputBar.bottomAnchor),
            exitButton.widthAnchor.constraint(equalToConstant: 36),
            exitButton.heightAnchor.constraint(equalToConstant: 36),

            inputTextView.leadingAnchor.constraint(equalTo: exitButton.trailingAnchor, constant: 8),
            inputTextView.topAnchor.constraint(equalTo: inputBar.topAnchor),
            inputTextView.bottomAnchor.constraint(equalTo: inputBar.bottomAnchor),
            inputTextViewHeightConstraint,

            placeholderLabel.leadingAnchor.constraint(equalTo: inputTextView.leadingAnchor, constant: 12),
            placeholderLabel.topAnchor.constraint(equalTo: inputTextView.topAnchor, constant: 9),

            sendButton.leadingAnchor.constraint(equalTo: inputTextView.trailingAnchor, constant: 8),
            sendButton.trailingAnchor.constraint(equalTo: inputBar.trailingAnchor),
            sendButton.bottomAnchor.constraint(equalTo: inputBar.bottomAnchor),
            sendButton.widthAnchor.constraint(equalToConstant: 36),
            sendButton.heightAnchor.constraint(equalToConstant: 36),
        ])

        // Wide layout: messages left, userlist right — now matches
        // W2GViewController exactly (288pt width, 8pt top padding below the
        // header separator, no divider between the two columns).
        // Narrow layout: messages fill the width, userlist hidden.
        wideLayoutConstraints = [
            userListTableView.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 8),
            userListTableView.trailingAnchor.constraint(equalTo: chatContainer.trailingAnchor),
            userListTableView.bottomAnchor.constraint(equalTo: chatContainer.bottomAnchor),
            userListTableView.widthAnchor.constraint(equalToConstant: 288),

            messagesTableView.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 8),
            messagesTableView.trailingAnchor.constraint(equalTo: userListTableView.leadingAnchor),
            messagesTableView.bottomAnchor.constraint(equalTo: inputBar.topAnchor, constant: -8),
        ]

        narrowLayoutConstraints = [
            messagesTableView.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 8),
            messagesTableView.trailingAnchor.constraint(equalTo: chatContainer.trailingAnchor),
            messagesTableView.bottomAnchor.constraint(equalTo: inputBar.topAnchor, constant: -8),
        ]

        updateLayoutForCurrentWidth()
    }

    /// Mirrors `$irc ??= MessageClient.new(ident)`: reuses the shared lobby
    /// session if one is already connected/connecting, otherwise starts a
    /// new one. Wires this screen's callbacks either way, and immediately
    /// reflects current state if reattaching to a session that's already
    /// past `onReady` (rather than showing a loading screen for a
    /// connection that finished before this screen was even visible).
    private func attachToLobby() {
        let client = IRCLobby.shared.connect()

        client.onReady = { [weak self] in
            guard let self else { return }
            self.loadingIndicator.stopAnimating()
            self.loadingIndicator.isHidden = true
            self.loadingLabel.isHidden = true
            self.messagesTableView.isHidden = false
        }
        client.onMessagesChanged = { [weak self, weak client] in
            guard let self, let client else { return }
            self.messages = client.messages
            self.messagesTableView.reloadData()
            self.scrollToNewestMessage()
        }
        client.onUsersChanged = { [weak client, weak self] in
            guard let client, let self else { return }
            self.users = client.users.values.sorted { $0.name.lowercased() < $1.name.lowercased() }
            self.userCountLabel.text = "\(client.users.count) online"
            self.userListTableView.reloadData()
        }
        client.onDisconnected = { [weak self] _ in
            self?.userCountLabel.text = "Disconnected"
        }

        if client.isReady {
            loadingIndicator.stopAnimating()
            loadingIndicator.isHidden = true
            loadingLabel.isHidden = true
            messagesTableView.isHidden = false
            messages = client.messages
            users = client.users.values.sorted { $0.name.lowercased() < $1.name.lowercased() }
            userCountLabel.text = "\(client.users.count) online"
            messagesTableView.reloadData()
            userListTableView.reloadData()
            scrollToNewestMessage()
        } else {
            loadingIndicator.startAnimating()
            loadingIndicator.isHidden = false
            loadingLabel.isHidden = false
            messagesTableView.isHidden = true
        }
    }

    /// Mirrors W2GViewController's `w2gClientMessagesDidChange`: in the
    /// flipped table, row 0 is visually at the bottom (newest), so scrolling
    /// "to" row 0 is scrolling to the newest message.
    private func scrollToNewestMessage() {
        guard !messages.isEmpty else { return }
        messagesTableView.scrollToRow(at: IndexPath(row: 0, section: 0), at: .top, animated: true)
    }

    @objc private func sendTapped() {
        let text = inputTextView.text ?? ""
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        IRCLobby.shared.client?.say(text)
        inputTextView.text = ""
        textViewDidChange(inputTextView)
    }

    @objc private func exitTapped() {
        IRCLobby.shared.leave()
        messages = []
        users = []
        messagesTableView.reloadData()
        userListTableView.reloadData()
        UserDefaults.standard.set(false, forKey: agreedKey)
        render()
    }

    private func updateInputHeight() {
        let width = inputTextView.bounds.width
        guard width > 0 else { return }
        let fittingSize = inputTextView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        let clamped = min(max(fittingSize.height, Self.minInputHeight), Self.maxInputHeight)
        inputTextView.isScrollEnabled = fittingSize.height > Self.maxInputHeight
        guard inputTextViewHeightConstraint.constant != clamped else { return }
        inputTextViewHeightConstraint.constant = clamped
        UIView.animate(withDuration: 0.15) { self.view.layoutIfNeeded() }
    }
}

// MARK: - UITableViewDataSource

extension HayaseChatViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        tableView == messagesTableView ? messages.count : users.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if tableView == messagesTableView {
            guard let cell = tableView.dequeueReusableCell(withIdentifier: IRCMessageCell.reuseID, for: indexPath) as? IRCMessageCell else {
                return UITableViewCell()
            }
            let msgs = reversedMessages
            if let msg = msgs[safe: indexPath.row] {
                // Message grouping (mirrors web Messages.svelte groupMessages,
                // same technique as W2GChatCell): in the flipped table, row 0
                // = newest. The visual "above" is row+1. Show the header
                // (name+time) when this is the first message in a group (the
                // message visually above is from a different user or doesn't
                // exist). Show the avatar when this is the last message in a
                // group (the message visually below is from a different user
                // or doesn't exist).
                let prevSameUser = msgs[safe: indexPath.row + 1]?.user.id == msg.user.id
                let nextSameUser = indexPath.row > 0 && msgs[safe: indexPath.row - 1]?.user.id == msg.user.id
                let showHeader = !prevSameUser
                let showAvatar = !nextSameUser
                cell.configure(with: msg, showHeader: showHeader, showAvatar: showAvatar)
            }
            cell.contentView.transform = CGAffineTransform(scaleX: 1, y: -1) // un-flip cell
            return cell
        } else {
            guard let cell = tableView.dequeueReusableCell(withIdentifier: ChatUserListCell.reuseID, for: indexPath) as? ChatUserListCell else {
                return UITableViewCell()
            }
            if let user = users[safe: indexPath.row] {
                cell.configure(with: user)
            }
            return cell
        }
    }
}

private extension Array {
    /// Matches the `[safe:]` convention already used elsewhere in this
    /// codebase (e.g. `W2GViewController.swift`).
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - UITextViewDelegate

extension HayaseChatViewController: UITextViewDelegate {
    func textViewDidChange(_ textView: UITextView) {
        placeholderLabel.isHidden = !(textView.text?.isEmpty ?? true)
        updateInputHeight()
    }

    /// Mirrors the web textarea's `maxlength={256}`.
    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        let updated = (textView.text as NSString).replacingCharacters(in: range, with: text)
        return updated.count <= 256
    }
}

// MARK: - IRCMessageCell (mirrors Messages.svelte, same technique as W2GChatCell)
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
// This was a plain one-row-per-message list with no bubble/grouping in the
// first pass. `Messages.svelte` is shared between W2G and IRC chat, so IRC
// messages should look like this too — not just "for consistency with W2G"
// but because that's what interface's own shared component actually does.

private final class IRCMessageCell: UITableViewCell {
    static let reuseID = "IRCMessageCell"

    private let avatarImageView = UIImageView()
    private let headerRow = UIView()
    private let nameLabel = UILabel()
    private let timeLabel = UILabel()
    private let bubbleBackground = UIView()
    private let bubbleLabel = UILabel()

    private var incomingConstraints: [NSLayoutConstraint] = []
    private var outgoingConstraints: [NSLayoutConstraint] = []
    private var headerVisibleConstraint: NSLayoutConstraint!
    private var headerHiddenConstraint: NSLayoutConstraint!
    private var headerTopConstraint: NSLayoutConstraint!

    private var currentAvatarURLString: String?
    private var avatarTask: URLSessionDataTask?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .none

        let cv = contentView
        let avatarSize: CGFloat = 32

        avatarImageView.layer.cornerRadius = avatarSize / 2
        avatarImageView.clipsToBounds = true
        avatarImageView.contentMode = .scaleAspectFill
        avatarImageView.backgroundColor = UIColor.HayaseTheme.accent
        avatarImageView.translatesAutoresizingMaskIntoConstraints = false
        cv.addSubview(avatarImageView)

        headerRow.translatesAutoresizingMaskIntoConstraints = false
        cv.addSubview(headerRow)

        nameLabel.font = .nunito(ofSize: 14, weight: .bold)
        nameLabel.textColor = UIColor.HayaseTheme.foreground
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        headerRow.addSubview(nameLabel)

        timeLabel.font = .nunito(ofSize: 10)
        timeLabel.textColor = UIColor.HayaseTheme.mutedForeground
        timeLabel.translatesAutoresizingMaskIntoConstraints = false
        headerRow.addSubview(timeLabel)

        bubbleBackground.translatesAutoresizingMaskIntoConstraints = false
        cv.addSubview(bubbleBackground)

        bubbleLabel.font = .nunito(ofSize: 12)
        bubbleLabel.textColor = UIColor.HayaseTheme.foreground
        bubbleLabel.numberOfLines = 0
        bubbleLabel.translatesAutoresizingMaskIntoConstraints = false
        bubbleBackground.addSubview(bubbleLabel)

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

        headerTopConstraint = headerRow.topAnchor.constraint(equalTo: cv.topAnchor, constant: 12)
        headerVisibleConstraint = bubbleBackground.topAnchor.constraint(equalTo: headerRow.bottomAnchor, constant: 4)
        headerHiddenConstraint = bubbleBackground.topAnchor.constraint(equalTo: cv.topAnchor, constant: 2)

        incomingConstraints = [
            avatarImageView.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 4),
            headerRow.leadingAnchor.constraint(equalTo: avatarImageView.trailingAnchor, constant: 8),
            bubbleBackground.leadingAnchor.constraint(equalTo: avatarImageView.trailingAnchor, constant: 8),
            bubbleBackground.trailingAnchor.constraint(lessThanOrEqualTo: cv.trailingAnchor, constant: -100),
        ]

        outgoingConstraints = [
            avatarImageView.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -4),
            headerRow.trailingAnchor.constraint(equalTo: avatarImageView.leadingAnchor, constant: -8),
            bubbleBackground.trailingAnchor.constraint(equalTo: avatarImageView.leadingAnchor, constant: -8),
            bubbleBackground.leadingAnchor.constraint(greaterThanOrEqualTo: cv.leadingAnchor, constant: 100),
        ]
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        NSLayoutConstraint.deactivate(incomingConstraints)
        NSLayoutConstraint.deactivate(outgoingConstraints)
        headerVisibleConstraint.isActive = false
        headerHiddenConstraint.isActive = false
        headerTopConstraint.isActive = false
        avatarTask?.cancel()
        avatarTask = nil
        currentAvatarURLString = nil
        avatarImageView.image = nil
        avatarImageView.alpha = 1
    }

    func configure(with message: IRCChatMessage, showHeader: Bool, showAvatar: Bool) {
        nameLabel.text = message.user.name
        timeLabel.text = DateFormatter.localizedString(from: message.date, dateStyle: .none, timeStyle: .short)
        bubbleLabel.text = message.message

        let isOutgoing = message.kind == .outgoing

        NSLayoutConstraint.activate(isOutgoing ? outgoingConstraints : incomingConstraints)

        headerRow.isHidden = !showHeader
        headerTopConstraint.isActive = showHeader
        headerVisibleConstraint.isActive = showHeader
        headerHiddenConstraint.isActive = !showHeader

        avatarImageView.alpha = showAvatar ? 1 : 0
        if showAvatar { loadAvatar(urlString: message.user.avatarURL) }

        bubbleBackground.backgroundColor = isOutgoing ? UIColor.HayaseTheme.primary : UIColor.HayaseTheme.accent
        bubbleBackground.layer.cornerRadius = 12
        bubbleBackground.layer.maskedCorners = isOutgoing
            ? [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner]
            : [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMaxXMaxYCorner]
    }

    private func loadAvatar(urlString: String) {
        guard currentAvatarURLString != urlString else { return }
        currentAvatarURLString = urlString
        avatarTask?.cancel()
        avatarImageView.image = nil

        if let cached = SharedImageCache.shared.object(forKey: urlString as NSString) {
            avatarImageView.image = cached
            return
        }
        guard let url = URL(string: urlString) else { return }

        avatarTask = URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data, let image = UIImage(data: data) else { return }
            SharedImageCache.shared.setObject(image, forKey: urlString as NSString)
            DispatchQueue.main.async {
                guard let self, self.currentAvatarURLString == urlString else { return }
                self.avatarImageView.image = image
            }
        }
        avatarTask?.resume()
    }
}

