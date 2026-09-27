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
//  - Content-warning agreement (`prevAgreed`) was being persisted to
//    `UserDefaults`, so once agreed it never asked again — meaning every
//    later app launch silently reconnected the moment this tab was opened,
//    with no warning page and no explicit "Continue". The real
//    `modules/irc/index.ts` store is a plain in-memory `writable(false)`,
//    reset every fresh page load; the flag now lives as `IRCLobby.prevAgreed`
//    to match that (see IRCLobby.swift). `exitTapped` also now navigates
//    home, matching `quit()`'s `goto('/#/app/home')` instead of just
//    re-showing the warning page on the same tab.
//  - Content-warning page and the chat header/input bar are now matched
//    against `chat/+page.svelte` and `interface.svelte` directly: real
//    two-tone triangle-alert icon (amber fill, background-colored stroke,
//    matching `fill='#f59e0b'` over `class='text-background'`), `secondary`/
//    `destructive` button tokens at their actual `h-10 px-8` content-hugging
//    size instead of a fixed 220×44 pair, header title/description sizing
//    and the `!my-6` 24pt separator margin, and `bg-muted`/`rounded-md`
//    icon buttons and textarea. The invented "N online" label is gone — it
//    doesn't exist anywhere in the web source.
//  - Outgoing bubbles used `--primary` (white); the actual source is a fixed
//    `theme` color (`tailwind.config.ts`, not a CSS variable), now
//    `UIColor.HayaseTheme.theme`. Incoming bubbles used `--accent` (8%
//    white) instead of `--muted` (4% white, what `bg-muted` actually is).
//  - Corner-rounding quirk: because Messages.svelte's two `class:rounded-*`
//    bindings don't remove the always-present static `rounded-r-xl`, an
//    outgoing bubble actually ends up with `rounded-t-xl rounded-r-xl
//    rounded-l-xl` all at once (all four corners rounded, no "tail"), while
//    an incoming bubble keeps one sharp corner. Replicated as-is rather than
//    "fixed" to a symmetric tail on both sides.
//  - Avatars (message list and userlist) now go through the existing
//    `FollowerAvatarStackView`/`ProfileCardViewController` (Profile.swift)
//    instead of a plain `UIImageView` — this gives them the real
//    `ring-4 ring-background` ring `Profile.svelte`'s default avatar class
//    has, and, more importantly, a tap opens the actual native profile
//    card, replacing the earlier "open AniList in the browser" stand-in for
//    `ChatProfile.svelte`'s in-app popover, and, since this pass, fetching
//    the tapped user's full profile first via the new
//    `AniListClient.fetchUserProfileResult(id:)` and `Profile.swift`'s new
//    optional `detailFetcher` — mirroring `client.user(Number(user.id))` —
//    so the card's bio/banner/stats are populated rather than stuck at
//    their built-in empty-state fallback (see ChatUserListCell.swift and
//    Profile.swift's own header comments for why this fetches-then-presents
//    instead of presenting immediately and patching the card in place once
//    data arrives).
//  - The userlist is now an always-visible panel: a 288pt side panel on
//    wide layouts (mirrors `UserList.svelte`), and, on narrow ones, a
//    strip above the chat column instead of hidden entirely — matching
//    `flex md:flex-row flex-col-reverse`, which renders the row's last DOM
//    child (`UserList`) first on narrow widths rather than removing it.
//    An earlier pass hid it on narrow specifically to match
//    `W2GViewController`'s existing wide/narrow pattern. Checked directly
//    this time rather than assumed: `w2g/[id]/+page.svelte` has this exact
//    same `flex-col-reverse` structure, and `W2GViewController.swift`
//    really does hide its own userlist on narrow the same way — so that
//    was a real precedent, just a shared copy of the same gap rather than
//    a considered simplification, and W2G's copy is still unfixed. Out of
//    scope for this pass (this file is about Chat), but worth fixing
//    there too via the same `rowContainer` approach.
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

// MARK: - ContentWarningIconView

/// Mirrors `<TriangleAlert class='text-background max-w-full' size='12rem'
/// fill='#f59e0b' />` in `chat/+page.svelte`. Lucide icons stroke
/// `currentColor` by default; `text-background` sets that to the page's
/// `--background` (black in dark theme), while the `fill` prop overrides
/// the default `fill='none'` on every path in the icon — so the closed
/// triangle body fills amber while its outline, and the '!' mark (which
/// has no enclosed area for a fill to apply to), stay background-colored.
///
/// Corner rounding is approximated as straight chords between the actual
/// path's arc endpoints (radius 2 on a 24-unit grid) rather than true
/// elliptical arcs — at this icon's fixed 192pt size the difference isn't
/// visually distinguishable, and it avoids hand-porting SVG arc math for a
/// single decorative icon.
private final class ContentWarningIconView: UIView {
    private static let gridSize: CGFloat = 24
    private static let amber = UIColor(red: 0xF5 / 255.0, green: 0x9E / 255.0, blue: 0x0B / 255.0, alpha: 1)

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        contentMode = .redraw
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ rect: CGRect) {
        let scale = rect.width / Self.gridSize
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * scale, y: y * scale) }

        // m21.73 18-8-14a2 2 0 0 0-3.48 0l-8 14A2 2 0 0 0 4 21h16a2 2 0 0 0 1.73-3Z
        let triangle = UIBezierPath()
        triangle.move(to: p(21.73, 18))
        triangle.addLine(to: p(13.73, 4))
        triangle.addLine(to: p(10.25, 4))
        triangle.addLine(to: p(2.25, 18))
        triangle.addLine(to: p(4, 21))
        triangle.addLine(to: p(20, 21))
        triangle.close()
        triangle.lineJoinStyle = .round
        triangle.lineWidth = 2 * scale
        Self.amber.setFill()
        UIColor.HayaseTheme.background.setStroke()
        triangle.fill()
        triangle.stroke()

        // M12 9v4
        let mark = UIBezierPath()
        mark.move(to: p(12, 9))
        mark.addLine(to: p(12, 13))
        mark.lineCapStyle = .round
        mark.lineWidth = 2 * scale
        UIColor.HayaseTheme.background.setStroke()
        mark.stroke()

        // M12 17h.01
        let dot = UIBezierPath()
        dot.move(to: p(12, 17))
        dot.addLine(to: p(12.01, 17))
        dot.lineCapStyle = .round
        dot.lineWidth = 2 * scale
        UIColor.HayaseTheme.background.setStroke()
        dot.stroke()
    }
}

// MARK: - HayaseChatViewController

final class HayaseChatViewController: UIViewController {
    private let stack = UIStackView()
    private let chatContainer = UIView()

    private let messagesTableView = UITableView()
    /// Mirrors `<div class='flex md:flex-row flex-col-reverse size-full
    /// min-h-0'>` — the row wrapping the chat column and the userlist.
    private let rowContainer = UIView()
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

    private static let minInputHeight: CGFloat = 36
    private static let maxInputHeight: CGFloat = 120

    // Wide/narrow adaptive layout for the userlist panel — mirrors
    // W2GViewController's wideLayoutConstraints/narrowLayoutConstraints/
    // isWideLayout/updateLayoutForCurrentWidth pattern exactly.
    private var wideLayoutConstraints: [NSLayoutConstraint] = []
    private var narrowLayoutConstraints: [NSLayoutConstraint] = []
    private var isWideLayout: Bool?
    private lazy var compactUsersHeight = userListTableView.heightAnchor.constraint(equalToConstant: 0)

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
    /// breakpoint: `md:` = 768px of the app viewport.
    private func updateLayoutForCurrentWidth() {
        let wide = (view.window?.rootViewController?.view.bounds.width ?? view.bounds.width) >= 768
        compactUsersHeight.constant = min(CGFloat(users.count) * 40 + 8, max(0, rowContainer.bounds.height * 0.4))
        guard wide != isWideLayout else { return }
        isWideLayout = wide

        if wide {
            NSLayoutConstraint.deactivate(narrowLayoutConstraints)
            NSLayoutConstraint.activate(wideLayoutConstraints)
        } else {
            NSLayoutConstraint.deactivate(wideLayoutConstraints)
            NSLayoutConstraint.activate(narrowLayoutConstraints)
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
        let agreed = IRCLobby.prevAgreed
        stack.isHidden = agreed
        chatContainer.isHidden = !agreed
        if agreed {
            attachToLobby()
        } else {
            renderWarning()
        }
    }

    private func renderWarning() {
        let warning = ContentWarningIconView()
        warning.translatesAutoresizingMaskIntoConstraints = false
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
        if let lastSubview = stack.arrangedSubviews.last {
            stack.setCustomSpacing(28, after: lastSubview)
        }
        stack.addArrangedSubview(buttons)

        // variant='secondary' size='lg': bg-secondary text-secondary-foreground h-10 px-8.
        let nope = makeButton(title: "Nope", background: UIColor.HayaseTheme.secondary, foreground: UIColor.HayaseTheme.secondaryForeground)
        nope.addTarget(self, action: #selector(nopeTapped), for: .touchUpInside)
        // variant='destructive' size='lg': bg-destructive text-destructive-foreground h-10 px-8.
        let cont = makeButton(title: "Continue", background: UIColor.HayaseTheme.destructive, foreground: UIColor.HayaseTheme.destructiveForeground)
        cont.addTarget(self, action: #selector(continueTapped), for: .touchUpInside)
        buttons.addArrangedSubview(nope)
        buttons.addArrangedSubview(cont)
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
        // size='lg': h-10 px-8; base: text-sm font-medium.
        button.titleLabel?.font = .nunito(ofSize: 14, weight: .medium)
        button.tintColor = foreground
        button.backgroundColor = background
        button.layer.cornerRadius = 6 // rounded-md
        button.contentEdgeInsets = UIEdgeInsets(top: 0, left: 32, bottom: 0, right: 32)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.heightAnchor.constraint(equalToConstant: 40).isActive = true
        return button
    }

    @objc private func nopeTapped() {
        Router.shared.navigate(.home, hostTabIndex: hayaseTabIndex)
    }

    @objc private func continueTapped() {
        IRCLobby.prevAgreed = true
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
        titleLabel.font = .nunito(ofSize: 24, weight: .bold) // text-2xl font-bold
        titleLabel.textColor = UIColor.HayaseTheme.foreground

        let descriptionLabel = UILabel()
        descriptionLabel.text = "Chat with other users of the app, share your thoughts, ask questions and have fun!"
        descriptionLabel.font = .nunito(ofSize: 16) // default text size, text-muted-foreground
        descriptionLabel.textColor = UIColor.HayaseTheme.mutedForeground
        descriptionLabel.numberOfLines = 0

        let headerStack = UIStackView(arrangedSubviews: [titleLabel, descriptionLabel])
        headerStack.axis = .vertical
        headerStack.spacing = 2 // space-y-0.5
        headerStack.translatesAutoresizingMaskIntoConstraints = false
        chatContainer.addSubview(headerStack)

        let separator = UIView()
        separator.backgroundColor = UIColor.HayaseTheme.border
        separator.translatesAutoresizingMaskIntoConstraints = false
        chatContainer.addSubview(separator)

        rowContainer.translatesAutoresizingMaskIntoConstraints = false
        chatContainer.addSubview(rowContainer)

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
        rowContainer.addSubview(messagesTableView)

        // Mirrors UserList.svelte's side panel on wide layouts (288pt,
        // trailing edge, full row height) and, on narrow ones, the same
        // component sitting above the chat column instead of beside it —
        // `flex-col-reverse` renders UserList (the row's last DOM child)
        // first, so it's on top, capped at 40% of the row's height
        // (`max-h-[40%] overflow-y-auto`, matched here as a flat 40% of
        // rowContainer rather than a true self-sizing-with-cap height; see
        // the narrowLayoutConstraints comment below). No separator between
        // the two on wide layouts — W2GViewController's equivalent panel
        // doesn't have one either (its userListTableView sits directly
        // against chatTableView's trailing edge), and this used to add one
        // that didn't match, which is what looked like a stray vertical
        // line.
        userListTableView.translatesAutoresizingMaskIntoConstraints = false
        userListTableView.backgroundColor = .clear
        userListTableView.separatorStyle = .none
        userListTableView.dataSource = self
        userListTableView.register(ChatUserListCell.self, forCellReuseIdentifier: ChatUserListCell.reuseID)
        userListTableView.estimatedRowHeight = 44
        userListTableView.rowHeight = UITableView.automaticDimension
        rowContainer.addSubview(userListTableView)

        // Mirrors irc.svelte's `{#await $irc}` loading state, shown until
        // both registration and our own channel join complete.
        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
        loadingIndicator.color = UIColor.HayaseTheme.mutedForeground
        loadingIndicator.isHidden = true
        rowContainer.addSubview(loadingIndicator)

        loadingLabel.text = "Loading..."
        loadingLabel.font = .nunito(ofSize: 18)
        loadingLabel.textColor = UIColor.HayaseTheme.mutedForeground
        loadingLabel.translatesAutoresizingMaskIntoConstraints = false
        loadingLabel.isHidden = true
        rowContainer.addSubview(loadingLabel)

        let inputBar = UIView()
        inputBar.translatesAutoresizingMaskIntoConstraints = false
        chatContainer.addSubview(inputBar)

        exitButton.setImage(UIImage.hayaseIcon("door-open", pointSize: 18), for: .normal)
        exitButton.tintColor = UIColor.HayaseTheme.foreground
        exitButton.backgroundColor = UIColor.HayaseTheme.muted // variant='outline': bg-muted
        exitButton.layer.cornerRadius = 6 // rounded-md
        exitButton.clipsToBounds = true
        exitButton.addTarget(self, action: #selector(exitTapped), for: .touchUpInside)
        exitButton.translatesAutoresizingMaskIntoConstraints = false

        // isScrollEnabled = false is required for a UITextView to size
        // itself from its content under Auto Layout — with it left at the
        // default `true`, the `>=36 / <=120` height constraints below had
        // nothing driving them toward a natural size and settled on 120pt
        // on first layout, producing an oversized input box.
        inputTextView.isScrollEnabled = false
        inputTextView.font = .nunito(ofSize: 14) // text-sm
        inputTextView.textColor = UIColor.HayaseTheme.foreground
        inputTextView.backgroundColor = UIColor.HayaseTheme.muted // bg-muted (unaffected by border-0 override)
        inputTextView.layer.cornerRadius = 6 // rounded-md
        inputTextView.textContainerInset = UIEdgeInsets(top: 8, left: 12, bottom: 8, right: 12) // py-2 px-3
        inputTextView.translatesAutoresizingMaskIntoConstraints = false
        inputTextView.delegate = self
        inputBar.addSubview(inputTextView)

        placeholderLabel.text = "Message"
        placeholderLabel.font = .nunito(ofSize: 14)
        placeholderLabel.textColor = UIColor.HayaseTheme.mutedForeground
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        placeholderLabel.isUserInteractionEnabled = false
        inputTextView.addSubview(placeholderLabel)

        sendButton.setImage(UIImage.hayaseIcon("send-horizontal", pointSize: 18), for: .normal)
        sendButton.tintColor = UIColor.HayaseTheme.foreground
        sendButton.backgroundColor = UIColor.HayaseTheme.muted // variant='outline': bg-muted
        sendButton.layer.cornerRadius = 6 // rounded-md
        sendButton.clipsToBounds = true
        sendButton.addTarget(self, action: #selector(sendTapped), for: .touchUpInside)
        sendButton.translatesAutoresizingMaskIntoConstraints = false

        inputBar.addSubview(exitButton)
        inputBar.addSubview(sendButton)

        inputTextViewHeightConstraint = inputTextView.heightAnchor.constraint(equalToConstant: Self.minInputHeight)

        NSLayoutConstraint.activate([
            // separator's own 24pt top/bottom margin (!my-6) always applies,
            // regardless of breakpoint — only the header/separator's shared
            // horizontal+top inset (p-3 / md:p-10) is breakpoint-dependent,
            // set below in wide/narrowLayoutConstraints.
            separator.topAnchor.constraint(equalTo: headerStack.bottomAnchor, constant: 24),
            separator.heightAnchor.constraint(equalToConstant: 1),

            // rowContainer's own position never depends on the breakpoint —
            // only how messagesTableView/userListTableView arrange
            // *within* it does (set in wide/narrowLayoutConstraints below).
            rowContainer.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 24),
            rowContainer.leadingAnchor.constraint(equalTo: chatContainer.leadingAnchor),
            rowContainer.trailingAnchor.constraint(equalTo: chatContainer.trailingAnchor),
            rowContainer.bottomAnchor.constraint(equalTo: inputBar.topAnchor, constant: -16), // mt-4

            // px-4, unconditional (no `md:` variant on the message column).
            messagesTableView.leadingAnchor.constraint(equalTo: rowContainer.leadingAnchor, constant: 16),

            loadingIndicator.centerXAnchor.constraint(equalTo: messagesTableView.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: messagesTableView.centerYAnchor, constant: -12),
            loadingLabel.centerXAnchor.constraint(equalTo: messagesTableView.centerXAnchor),
            loadingLabel.topAnchor.constraint(equalTo: loadingIndicator.bottomAnchor, constant: 8),

            // Input stays within the message column (px-4/pb-4).
            inputBar.leadingAnchor.constraint(equalTo: chatContainer.leadingAnchor, constant: 16),
            inputBar.bottomAnchor.constraint(equalTo: chatContainer.bottomAnchor, constant: -16),

            exitButton.leadingAnchor.constraint(equalTo: inputBar.leadingAnchor),
            // No `mt-auto` on the web's DoorOpen button (unlike SendHorizontal
            // below) — with a fixed size-9 height and the row's default
            // align-items: stretch, it sits at the row's top, not its bottom.
            exitButton.topAnchor.constraint(equalTo: inputBar.topAnchor),
            exitButton.widthAnchor.constraint(equalToConstant: 36),
            exitButton.heightAnchor.constraint(equalToConstant: 36),

            inputTextView.leadingAnchor.constraint(equalTo: exitButton.trailingAnchor, constant: 8), // gap-2
            inputTextView.topAnchor.constraint(equalTo: inputBar.topAnchor),
            inputTextView.bottomAnchor.constraint(equalTo: inputBar.bottomAnchor),
            inputTextViewHeightConstraint,

            placeholderLabel.leadingAnchor.constraint(equalTo: inputTextView.leadingAnchor, constant: 12),
            placeholderLabel.topAnchor.constraint(equalTo: inputTextView.topAnchor, constant: 8),

            sendButton.leadingAnchor.constraint(equalTo: inputTextView.trailingAnchor, constant: 8), // gap-2
            sendButton.trailingAnchor.constraint(equalTo: inputBar.trailingAnchor),
            sendButton.bottomAnchor.constraint(equalTo: inputBar.bottomAnchor), // mt-auto
            sendButton.widthAnchor.constraint(equalToConstant: 36),
            sendButton.heightAnchor.constraint(equalToConstant: 36),
        ])

        // Header/separator get p-3 (12pt) narrow / md:p-10 (40pt) wide, on
        // top/leading/trailing alike; the separator's own bottom margin
        // (!my-6, 24pt, set above) is what actually separates it from
        // rowContainer, matching pb-0 on the padded header container.
        //
        // Wide (`md:flex-row`): messages left, userlist right — 288pt,
        // full rowContainer height, no divider.
        //
        // Narrow (`flex-col-reverse`): userlist ABOVE messages, not hidden
        // — `flex-col-reverse` renders the row's last DOM child (UserList)
        // first, with content height capped at 40% of the message area.
        wideLayoutConstraints = [
            inputBar.trailingAnchor.constraint(equalTo: userListTableView.leadingAnchor, constant: -16),
            headerStack.topAnchor.constraint(equalTo: chatContainer.topAnchor, constant: 40),
            headerStack.leadingAnchor.constraint(equalTo: chatContainer.leadingAnchor, constant: 40),
            headerStack.trailingAnchor.constraint(equalTo: chatContainer.trailingAnchor, constant: -40),
            separator.leadingAnchor.constraint(equalTo: chatContainer.leadingAnchor, constant: 40),
            separator.trailingAnchor.constraint(equalTo: chatContainer.trailingAnchor, constant: -40),

            userListTableView.topAnchor.constraint(equalTo: rowContainer.topAnchor),
            userListTableView.trailingAnchor.constraint(equalTo: rowContainer.trailingAnchor),
            userListTableView.bottomAnchor.constraint(equalTo: chatContainer.bottomAnchor, constant: -8),
            userListTableView.widthAnchor.constraint(equalToConstant: 288),

            messagesTableView.topAnchor.constraint(equalTo: rowContainer.topAnchor),
            messagesTableView.trailingAnchor.constraint(equalTo: userListTableView.leadingAnchor),
            messagesTableView.bottomAnchor.constraint(equalTo: rowContainer.bottomAnchor),
        ]

        narrowLayoutConstraints = [
            inputBar.trailingAnchor.constraint(equalTo: chatContainer.trailingAnchor, constant: -16),
            headerStack.topAnchor.constraint(equalTo: chatContainer.topAnchor, constant: 12),
            headerStack.leadingAnchor.constraint(equalTo: chatContainer.leadingAnchor, constant: 12),
            headerStack.trailingAnchor.constraint(equalTo: chatContainer.trailingAnchor, constant: -12),
            separator.leadingAnchor.constraint(equalTo: chatContainer.leadingAnchor, constant: 12),
            separator.trailingAnchor.constraint(equalTo: chatContainer.trailingAnchor, constant: -12),

            userListTableView.topAnchor.constraint(equalTo: rowContainer.topAnchor),
            userListTableView.leadingAnchor.constraint(equalTo: rowContainer.leadingAnchor),
            userListTableView.trailingAnchor.constraint(equalTo: rowContainer.trailingAnchor),
            compactUsersHeight, // content-sized, capped at max-h-[40%]

            messagesTableView.topAnchor.constraint(equalTo: userListTableView.bottomAnchor),
            messagesTableView.trailingAnchor.constraint(equalTo: rowContainer.trailingAnchor),
            messagesTableView.bottomAnchor.constraint(equalTo: rowContainer.bottomAnchor),
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
            self.userListTableView.reloadData()
        }
        if client.isReady {
            loadingIndicator.stopAnimating()
            loadingIndicator.isHidden = true
            loadingLabel.isHidden = true
            messagesTableView.isHidden = false
            messages = client.messages
            users = client.users.values.sorted { $0.name.lowercased() < $1.name.lowercased() }
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
        IRCLobby.prevAgreed = false
        render()
        Router.shared.navigate(.home, hostTabIndex: hayaseTabIndex)
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
    private static let avatarSize: CGFloat = 32 // size-8, Profile.svelte's default

    private let profileStack = FollowerAvatarStackView()
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

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .none

        let cv = contentView
        let avatarSize = Self.avatarSize

        profileStack.translatesAutoresizingMaskIntoConstraints = false
        cv.addSubview(profileStack)

        headerRow.translatesAutoresizingMaskIntoConstraints = false
        cv.addSubview(headerRow)

        nameLabel.font = .nunito(ofSize: 14, weight: .bold)
        nameLabel.textColor = UIColor.HayaseTheme.foreground
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        headerRow.addSubview(nameLabel)

        timeLabel.font = .nunito(ofSize: 10)
        timeLabel.textColor = UIColor.HayaseTheme.mutedForeground
        timeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
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
            profileStack.widthAnchor.constraint(equalToConstant: avatarSize),
            profileStack.heightAnchor.constraint(equalToConstant: avatarSize),
            profileStack.bottomAnchor.constraint(equalTo: cv.bottomAnchor, constant: -4), // mt-auto

            nameLabel.topAnchor.constraint(equalTo: headerRow.topAnchor),
            nameLabel.bottomAnchor.constraint(equalTo: headerRow.bottomAnchor),
            nameLabel.leadingAnchor.constraint(equalTo: headerRow.leadingAnchor, constant: 4),
            timeLabel.centerYAnchor.constraint(equalTo: nameLabel.centerYAnchor),
            timeLabel.leadingAnchor.constraint(equalTo: nameLabel.trailingAnchor, constant: 8),
            timeLabel.trailingAnchor.constraint(equalTo: headerRow.trailingAnchor),
            headerRow.leadingAnchor.constraint(greaterThanOrEqualTo: cv.leadingAnchor, constant: 4),
            headerRow.trailingAnchor.constraint(lessThanOrEqualTo: cv.trailingAnchor, constant: -4),

            bubbleLabel.topAnchor.constraint(equalTo: bubbleBackground.topAnchor, constant: 8),
            bubbleLabel.leadingAnchor.constraint(equalTo: bubbleBackground.leadingAnchor, constant: 12),
            bubbleLabel.trailingAnchor.constraint(equalTo: bubbleBackground.trailingAnchor, constant: -12),
            bubbleLabel.bottomAnchor.constraint(equalTo: bubbleBackground.bottomAnchor, constant: -8),

            // This -4 bottom inset (shared by every row, header or
            // continuation) is what stands in for `mb-1` (4px), applied to
            // every message bubble on web regardless of position in its
            // group. headerHiddenConstraint below adds no further offset,
            // so two bubbles in the same group end up exactly 4pt apart,
            // not 4+4.
            bubbleBackground.bottomAnchor.constraint(equalTo: cv.bottomAnchor, constant: -4),
        ])

        headerTopConstraint = headerRow.topAnchor.constraint(equalTo: cv.topAnchor, constant: 12) // mt-3
        headerVisibleConstraint = bubbleBackground.topAnchor.constraint(equalTo: headerRow.bottomAnchor, constant: 4) // pb-1
        headerHiddenConstraint = bubbleBackground.topAnchor.constraint(equalTo: cv.topAnchor, constant: 0)

        incomingConstraints = [
            profileStack.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 4),
            headerRow.leadingAnchor.constraint(equalTo: profileStack.trailingAnchor, constant: 8),
            bubbleBackground.leadingAnchor.constraint(equalTo: profileStack.trailingAnchor, constant: 8),
            bubbleBackground.trailingAnchor.constraint(lessThanOrEqualTo: cv.trailingAnchor, constant: -100),
        ]

        outgoingConstraints = [
            profileStack.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -4),
            headerRow.trailingAnchor.constraint(equalTo: profileStack.leadingAnchor, constant: -8),
            bubbleBackground.trailingAnchor.constraint(equalTo: profileStack.leadingAnchor, constant: -8),
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
        profileStack.reset()
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

        if showAvatar {
            let summary = AniListUserSummary(id: Int(message.user.id) ?? 0,
                                             name: message.user.name,
                                             avatarURL: message.user.avatarURL)
            let isGuest = message.user.isGuest
            profileStack.configure(users: [summary],
                                    avatarSize: Self.avatarSize,
                                    ringWidth: 4,
                                    ringColor: UIColor.HayaseTheme.background) { id, completion in
                guard !isGuest else {
                    completion(nil)
                    return
                }
                AniListClient.shared.fetchUserProfileResult(id: id) { result in
                    completion(try? result.get())
                }
            }
        } else {
            profileStack.reset()
        }

        // `bg-muted` (incoming) / fixed `theme` accent (`!bg-theme`, outgoing).
        bubbleBackground.backgroundColor = isOutgoing ? UIColor.HayaseTheme.theme : UIColor.HayaseTheme.muted
        bubbleBackground.layer.cornerRadius = 12
        // Quirk, not a style choice: Messages.svelte always includes the
        // static `rounded-t-xl rounded-r-xl`, then adds `rounded-l-xl` via
        // `class:` for outgoing messages *without* removing the static
        // `rounded-r-xl` (Svelte's `class:` doesn't dedupe with a static
        // class list). So outgoing bubbles end up with rounded-t + rounded-r
        // + rounded-l all at once — every corner rounded, no "tail" — while
        // incoming keeps the static rounded-t + rounded-r only (one sharp
        // corner, bottom-left, next to the avatar).
        bubbleBackground.layer.maskedCorners = isOutgoing
            ? [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner]
            : [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMaxXMaxYCorner]
    }
}

