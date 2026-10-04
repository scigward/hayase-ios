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
//    their built-in empty-state fallback (see UserList.swift and
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
//  (`Components/UI/Chat/UserList.swift`), a single implementation
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
//  Audited again against interface.svelte / Messages.svelte / MessageToast.svelte:
//  - Enter sends and Shift+Enter breaks the line (`Textarea`), a paste past
//    `maxlength` is cut to fit, and the field has the textarea's own
//    `select:` colours, ring and shadow.
//  - `{#await $irc}` replaces the whole page, header and input included, with
//    a spinner and "Loading...", and so does this now.
//  - The avatar sits at the top of a group, level with its header, as the
//    avatar column does in the flex row; times are `toLocaleTimeString()`
//    (with seconds); a group's side is its first message's; a bubble's text is
//    selected as a whole when it is tapped (`select-all`).
//  - The userlist keeps the order `Object.values($users)` gives it, not
//    alphabetical, and the list stays where it is while you read older
//    messages (a `flex-col-reverse` scroller does not jump to a new one).
//  - The warning's "NEVER" is bold, and its buttons are the real `secondary`
//    and `destructive` variants with their `select:` colours.
//  - The input stays above the keyboard.

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
/// The icon's own paths, with their true arcs, so its corners round as the SVG's do.
private final class ContentWarningIconView: UIView {
    private static let gridSize: CGFloat = 24
    private static let amber = UIColor(red: 0xF5 / 255.0, green: 0x9E / 255.0, blue: 0x0B / 255.0, alpha: 1)
    private static let paths = [
        "m21.73 18-8-14a2 2 0 0 0-3.48 0l-8 14A2 2 0 0 0 4 21h16a2 2 0 0 0 1.73-3Z",
        "M12 9v4",
        "M12 17h.01",
    ]

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
        for (index, data) in Self.paths.enumerated() {
            let path = UIBezierPath(cgPath: SVGPath.path(data))
            path.apply(CGAffineTransform(scaleX: scale, y: scale))
            path.lineWidth = 2 * scale
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            // fill='#f59e0b' on every path; only the triangle encloses anything
            if index == 0 {
                Self.amber.setFill()
                path.fill()
            }
            UIColor.HayaseTheme.background.setStroke()
            path.stroke()
        }
    }
}

// MARK: - SpinnerView

/// irc.svelte's loading spinner: `<svg width='24' height='24' stroke='currentColor' class='animate-spin'>`
/// drawing `M21 12a9 9 0 1 1-6.219-8.56`, one pixel wide, turning once a second.
private final class SpinnerView: UIView {
    private let arc = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        arc.path = SVGPath.path("M21 12a9 9 0 1 1-6.219-8.56")
        arc.fillColor = nil
        arc.strokeColor = UIColor.HayaseTheme.mutedForeground.cgColor
        arc.lineWidth = 1
        arc.frame = CGRect(x: 0, y: 0, width: 24, height: 24)
        layer.addSublayer(arc)
        NotificationCenter.default.addObserver(self, selector: #selector(restart),
                                               name: UIApplication.didBecomeActiveNotification, object: nil)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: 24, height: 24)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        restart()
    }

    @objc private func restart() {
        arc.removeAnimation(forKey: "spin")
        guard window != nil else { return }
        let spin = CABasicAnimation(keyPath: "transform.rotation.z")
        spin.fromValue = 0
        spin.toValue = 2 * CGFloat.pi
        spin.duration = 1
        spin.repeatCount = .infinity
        spin.timingFunction = CAMediaTimingFunction(name: .linear)
        arc.add(spin, forKey: "spin")
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
    /// `{#await $irc}`: while the session connects, the page is only this.
    private let loadingContainer = UIView()

    private let userListTableView = UITableView()
    private var users: [IRCUser] = []

    private let inputTextView = Textarea()
    private let sendButton = Button(iconName: "send-horizontal", pointSize: 18)
    private let exitButton = Button(iconName: "door-open", pointSize: 18)

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

    private enum Page {
        case warning, loading, chat
    }

    private func show(_ page: Page) {
        stack.isHidden = page != .warning
        loadingContainer.isHidden = page != .loading
        chatContainer.isHidden = page != .chat
    }

    private func render() {
        stack.arrangedSubviews.forEach {
            stack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        if IRCLobby.prevAgreed {
            attachToLobby()
        } else {
            show(.warning)
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
                top: 8, bold: "NEVER")

        let buttons = UIStackView()
        buttons.translatesAutoresizingMaskIntoConstraints = false
        buttons.axis = .horizontal
        buttons.spacing = 12
        buttons.alignment = .center
        if let lastSubview = stack.arrangedSubviews.last {
            stack.setCustomSpacing(28, after: lastSubview)
        }
        stack.addArrangedSubview(buttons)

        // variant='secondary' size='lg': bg-secondary text-secondary-foreground select:bg-secondary/60 h-10 px-8.
        let nope = makeButton(title: "Nope")
        nope.applySecondaryVariant()
        nope.addTarget(self, action: #selector(nopeTapped), for: .touchUpInside)
        // variant='destructive' size='lg': bg-destructive text-destructive-foreground select:bg-destructive/90 h-10 px-8.
        let cont = makeButton(title: "Continue")
        cont.restingBackground = UIColor.HayaseTheme.destructive
        cont.selectedBackground = UIColor.HayaseTheme.destructive.withAlphaComponent(0.9)
        cont.contentTint = UIColor.HayaseTheme.destructiveForeground
        cont.applyShadowSm()
        cont.addTarget(self, action: #selector(continueTapped), for: .touchUpInside)
        buttons.addArrangedSubview(nope)
        buttons.addArrangedSubview(cont)
    }

    private func addText(_ text: String,
                         top: CGFloat,
                         size: CGFloat = 16,
                         weight: UIFont.Weight = .regular,
                         color: UIColor = UIColor.HayaseTheme.mutedForeground,
                         bold: String? = nil) {
        let label = UILabel()
        let font = UIFont.nunito(ofSize: size, weight: weight)
        let attributed = NSMutableAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
        if let bold, let range = text.range(of: bold) {
            attributed.addAttribute(.font, value: UIFont.nunito(ofSize: size, weight: .bold), range: NSRange(range, in: text))
        }
        label.attributedText = attributed
        label.textAlignment = .center
        label.numberOfLines = 0
        if let previous = stack.arrangedSubviews.last {
            stack.setCustomSpacing(top, after: previous)
        }
        stack.addArrangedSubview(label)
    }

    private func makeButton(title: String) -> SelectButton {
        let button = SelectButton()
        button.setTitle(title, for: .normal)
        // size='lg': h-10 px-8; base: text-sm font-medium.
        button.titleLabel?.font = .nunito(ofSize: 14, weight: .medium)
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
            // Above the keyboard when it is up, the safe area's bottom when it is not.
            chatContainer.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
        ])

        loadingContainer.translatesAutoresizingMaskIntoConstraints = false
        loadingContainer.isHidden = true
        view.addSubview(loadingContainer)
        NSLayoutConstraint.activate([
            loadingContainer.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            loadingContainer.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            loadingContainer.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            loadingContainer.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
        ])
        let spinner = SpinnerView()
        spinner.translatesAutoresizingMaskIntoConstraints = false
        let loadingLabel = UILabel()
        loadingLabel.text = "Loading..."
        loadingLabel.font = .nunito(ofSize: 18)   // text-lg
        loadingLabel.textColor = UIColor.HayaseTheme.mutedForeground
        let loadingStack = UIStackView(arrangedSubviews: [spinner, loadingLabel])
        loadingStack.axis = .vertical
        loadingStack.alignment = .center
        loadingStack.spacing = 8   // mb-2
        loadingStack.translatesAutoresizingMaskIntoConstraints = false
        loadingContainer.addSubview(loadingStack)
        NSLayoutConstraint.activate([
            loadingStack.centerXAnchor.constraint(equalTo: loadingContainer.centerXAnchor),
            loadingStack.centerYAnchor.constraint(equalTo: loadingContainer.centerYAnchor),
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
        messagesTableView.register(ChatMessageCell.self, forCellReuseIdentifier: ChatMessageCell.reuseID)
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

        let inputBar = UIView()
        inputBar.translatesAutoresizingMaskIntoConstraints = false
        chatContainer.addSubview(inputBar)
        chatContainer.clipsToBounds = true   // overflow-clip

        // mt-4 above the input, given up before the input is when the page is too short for both
        let messagesToInput = rowContainer.bottomAnchor.constraint(equalTo: inputBar.topAnchor, constant: -16)
        messagesToInput.priority = .defaultHigh
        messagesToInput.isActive = true

        exitButton.addTarget(self, action: #selector(exitTapped), for: .touchUpInside)

        inputTextView.placeholder = "Message"
        inputTextView.maxLength = 256   // maxlength={256}
        inputTextView.onSubmit = { [weak self] in self?.sendTapped() }
        inputBar.addSubview(inputTextView)

        sendButton.addTarget(self, action: #selector(sendTapped), for: .touchUpInside)

        inputBar.addSubview(exitButton)
        inputBar.addSubview(sendButton)

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
            rowContainer.heightAnchor.constraint(greaterThanOrEqualToConstant: 0),

            // px-4, unconditional (no `md:` variant on the message column).
            messagesTableView.leadingAnchor.constraint(equalTo: rowContainer.leadingAnchor, constant: 16),

            // Input stays within the message column (px-4/pb-4).
            inputBar.leadingAnchor.constraint(equalTo: chatContainer.leadingAnchor, constant: 16),
            inputBar.bottomAnchor.constraint(equalTo: chatContainer.bottomAnchor, constant: -16),

            exitButton.leadingAnchor.constraint(equalTo: inputBar.leadingAnchor),
            // No `mt-auto` on the web's DoorOpen button (unlike SendHorizontal
            // below) — with a fixed size-9 height and the row's default
            // align-items: stretch, it sits at the row's top, not its bottom.
            exitButton.topAnchor.constraint(equalTo: inputBar.topAnchor),

            inputTextView.leadingAnchor.constraint(equalTo: exitButton.trailingAnchor, constant: 8), // gap-2
            inputTextView.topAnchor.constraint(equalTo: inputBar.topAnchor),
            inputTextView.bottomAnchor.constraint(equalTo: inputBar.bottomAnchor),

            sendButton.leadingAnchor.constraint(equalTo: inputTextView.trailingAnchor, constant: 8), // gap-2
            sendButton.trailingAnchor.constraint(equalTo: inputBar.trailingAnchor),
            sendButton.bottomAnchor.constraint(equalTo: inputBar.bottomAnchor), // mt-auto
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
            self?.show(.chat)
        }
        client.onMessagesChanged = { [weak self, weak client] in
            guard let self, let client else { return }
            self.apply(messages: client.messages)
        }
        client.onUsersChanged = { [weak client, weak self] in
            guard let client, let self else { return }
            self.users = client.orderedUsers
            self.userListTableView.reloadData()
        }
        if client.isReady {
            messages = client.messages
            users = client.orderedUsers
            messagesTableView.reloadData()
            userListTableView.reloadData()
            messagesTableView.scrollToNewestMessage()
            show(.chat)
        } else {
            show(.loading)
        }
    }

    private func apply(messages newMessages: [IRCChatMessage]) {
        messagesTableView.reloadFlippedMessages { messages = newMessages }
    }

    @objc private func sendTapped() {
        let text = inputTextView.text ?? ""
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        IRCLobby.shared.client?.say(text)
        inputTextView.text = ""
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

}

// MARK: - UITableViewDataSource

extension HayaseChatViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        tableView == messagesTableView ? messages.count : users.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if tableView == messagesTableView {
            guard let cell = tableView.dequeueReusableCell(withIdentifier: ChatMessageCell.reuseID, for: indexPath) as? ChatMessageCell else {
                return UITableViewCell()
            }
            let msgs = reversedMessages
            if msgs.indices.contains(indexPath.row) {
                // Message grouping (mirrors web Messages.svelte groupMessages): in the flipped
                // table, row 0 = newest. The visual "above" is row+1.
                let group = msgs.groupInfo(at: indexPath.row) { $0.user.id }
                cell.configure(with: msgs[indexPath.row].content, showHeader: group.showHeader,
                               isOutgoing: msgs[group.firstIndex].kind == .outgoing)
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
