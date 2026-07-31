//
//  HayaseChatViewController.swift
//  Hayase
//
//  Made by scigward.
//
//  Mirrors: src/routes/app/chat/+page.svelte,
//           src/lib/components/ui/irc/irc.svelte + interface.svelte
//
//  Scope note: the userlist is presented as a simple alert-style list rather
//  than a dedicated sidebar panel (interface's `UserList` component), and
//  there's no keyboard "Enter-to-send / Shift+Enter-for-newline" shortcut —
//  physical-keyboard modifier detection is nontrivial on iOS and low-value
//  for a touch-first app; the Send button is the primary (and only)
//  submission path here, which is the actual feature, just without that one
//  desktop-specific nicety.

import UIKit

// MARK: - HayaseChatViewController

final class HayaseChatViewController: UIViewController {
    private let agreedKey = "hayase_chat_prevAgreed"
    private let stack = UIStackView()
    private let chatContainer = UIView()

    private let messagesTableView = UITableView()
    private var messages: [IRCChatMessage] = []
    private let loadingIndicator = UIActivityIndicatorView(style: .medium)
    private let loadingLabel = UILabel()

    private let inputTextView = UITextView()
    private let placeholderLabel = UILabel()
    private let sendButton = UIButton(type: .system)
    private let exitButton = UIButton(type: .system)
    private let userCountButton = UIButton(type: .system)

    private var ircClient: IRCClient?

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
            connectIfNeeded()
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
    // list, and a bottom input bar with an exit button and a send button.

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

        userCountButton.setTitle("0 online", for: .normal)
        userCountButton.titleLabel?.font = .nunito(ofSize: 13, weight: .semibold)
        userCountButton.tintColor = UIColor.HayaseTheme.mutedForeground
        userCountButton.contentHorizontalAlignment = .leading
        userCountButton.addTarget(self, action: #selector(userCountTapped), for: .touchUpInside)

        let headerStack = UIStackView(arrangedSubviews: [titleLabel, descriptionLabel, userCountButton])
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
        chatContainer.addSubview(messagesTableView)

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

        NSLayoutConstraint.activate([
            headerStack.topAnchor.constraint(equalTo: chatContainer.topAnchor, constant: 12),
            headerStack.leadingAnchor.constraint(equalTo: chatContainer.leadingAnchor, constant: 16),
            headerStack.trailingAnchor.constraint(equalTo: chatContainer.trailingAnchor, constant: -16),

            separator.topAnchor.constraint(equalTo: headerStack.bottomAnchor, constant: 12),
            separator.leadingAnchor.constraint(equalTo: chatContainer.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: chatContainer.trailingAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1),

            messagesTableView.topAnchor.constraint(equalTo: separator.bottomAnchor),
            messagesTableView.leadingAnchor.constraint(equalTo: chatContainer.leadingAnchor),
            messagesTableView.trailingAnchor.constraint(equalTo: chatContainer.trailingAnchor),
            messagesTableView.bottomAnchor.constraint(equalTo: inputBar.topAnchor, constant: -8),

            loadingIndicator.centerXAnchor.constraint(equalTo: messagesTableView.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: messagesTableView.centerYAnchor, constant: -12),
            loadingLabel.centerXAnchor.constraint(equalTo: messagesTableView.centerXAnchor),
            loadingLabel.topAnchor.constraint(equalTo: loadingIndicator.bottomAnchor, constant: 8),

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
            inputTextView.heightAnchor.constraint(greaterThanOrEqualToConstant: 36),
            inputTextView.heightAnchor.constraint(lessThanOrEqualToConstant: 120),

            placeholderLabel.leadingAnchor.constraint(equalTo: inputTextView.leadingAnchor, constant: 12),
            placeholderLabel.topAnchor.constraint(equalTo: inputTextView.topAnchor, constant: 9),

            sendButton.leadingAnchor.constraint(equalTo: inputTextView.trailingAnchor, constant: 8),
            sendButton.trailingAnchor.constraint(equalTo: inputBar.trailingAnchor),
            sendButton.bottomAnchor.constraint(equalTo: inputBar.bottomAnchor),
            sendButton.widthAnchor.constraint(equalToConstant: 36),
            sendButton.heightAnchor.constraint(equalToConstant: 36),
        ])
    }

    private func connectIfNeeded() {
        guard ircClient == nil else { return }
        loadingIndicator.startAnimating()
        loadingIndicator.isHidden = false
        loadingLabel.isHidden = false
        messagesTableView.isHidden = true

        let identity = IRCIdentity.current()
        let client = IRCClient(identity: identity)
        ircClient = client

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
            self.scrollToBottom()
        }
        client.onUsersChanged = { [weak client, weak self] in
            guard let client, let self else { return }
            self.userCountButton.setTitle("\(client.users.count) online", for: .normal)
        }
        client.onDisconnected = { [weak self] _ in
            self?.userCountButton.setTitle("Disconnected", for: .normal)
        }
        client.connect()
    }

    private func scrollToBottom() {
        guard !messages.isEmpty else { return }
        let indexPath = IndexPath(row: messages.count - 1, section: 0)
        messagesTableView.scrollToRow(at: indexPath, at: .bottom, animated: true)
    }

    @objc private func sendTapped() {
        let text = inputTextView.text ?? ""
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        ircClient?.say(text)
        inputTextView.text = ""
        textViewDidChange(inputTextView)
    }

    @objc private func exitTapped() {
        ircClient?.disconnect()
        ircClient = nil
        messages = []
        messagesTableView.reloadData()
        UserDefaults.standard.set(false, forKey: agreedKey)
        render()
    }

    @objc private func userCountTapped() {
        guard let client = ircClient else { return }
        let names = client.users.values.map(\.name).sorted()
        let message = names.isEmpty ? "No one else is here yet." : names.joined(separator: "\n")
        let alert = UIAlertController(title: "\(names.count) online", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - UITableViewDataSource

extension HayaseChatViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        messages.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: IRCMessageCell.reuseID, for: indexPath) as? IRCMessageCell else {
            return UITableViewCell()
        }
        cell.configure(with: messages[indexPath.row])
        return cell
    }
}

// MARK: - UITextViewDelegate

extension HayaseChatViewController: UITextViewDelegate {
    func textViewDidChange(_ textView: UITextView) {
        placeholderLabel.isHidden = !(textView.text?.isEmpty ?? true)
    }

    /// Mirrors the web textarea's `maxlength={256}`.
    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        let updated = (textView.text as NSString).replacingCharacters(in: range, with: text)
        return updated.count <= 256
    }
}

// MARK: - IRCMessageCell

private final class IRCMessageCell: UITableViewCell {
    static let reuseID = "IRCMessageCell"

    private let avatarImageView = UIImageView()
    private let nameLabel = UILabel()
    private let timeLabel = UILabel()
    private let messageLabel = UILabel()
    private var currentAvatarURLString: String?
    private var avatarTask: URLSessionDataTask?

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .none

        avatarImageView.translatesAutoresizingMaskIntoConstraints = false
        avatarImageView.layer.cornerRadius = 16
        avatarImageView.clipsToBounds = true
        avatarImageView.backgroundColor = UIColor.HayaseTheme.accent
        avatarImageView.contentMode = .scaleAspectFill

        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.font = .nunito(ofSize: 13, weight: .bold)
        nameLabel.textColor = UIColor.HayaseTheme.foreground

        timeLabel.translatesAutoresizingMaskIntoConstraints = false
        timeLabel.font = .nunito(ofSize: 10)
        timeLabel.textColor = UIColor.HayaseTheme.mutedForeground

        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        messageLabel.font = .nunito(ofSize: 14)
        messageLabel.textColor = UIColor.HayaseTheme.foreground
        messageLabel.numberOfLines = 0

        contentView.addSubview(avatarImageView)
        contentView.addSubview(nameLabel)
        contentView.addSubview(timeLabel)
        contentView.addSubview(messageLabel)

        NSLayoutConstraint.activate([
            avatarImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            avatarImageView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 6),
            avatarImageView.widthAnchor.constraint(equalToConstant: 32),
            avatarImageView.heightAnchor.constraint(equalToConstant: 32),
            avatarImageView.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -6),

            nameLabel.leadingAnchor.constraint(equalTo: avatarImageView.trailingAnchor, constant: 8),
            nameLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 6),

            timeLabel.leadingAnchor.constraint(equalTo: nameLabel.trailingAnchor, constant: 6),
            timeLabel.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -16),
            timeLabel.firstBaselineAnchor.constraint(equalTo: nameLabel.firstBaselineAnchor),

            messageLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            messageLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            messageLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 2),
            messageLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        avatarTask?.cancel()
        avatarTask = nil
        currentAvatarURLString = nil
        avatarImageView.image = nil
    }

    func configure(with message: IRCChatMessage) {
        nameLabel.text = message.user.name
        nameLabel.textColor = message.kind == .outgoing ? UIColor.HayaseTheme.primary : UIColor.HayaseTheme.foreground
        timeLabel.text = Self.timeFormatter.string(from: message.date)
        messageLabel.text = message.message
        loadAvatar(urlString: message.user.avatarURL)
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
