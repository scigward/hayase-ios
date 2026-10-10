//
//  Page.swift
//  Hayase
//
//  Mirrors: src/routes/app/anime/[id]/thread/[threadId]/+page.svelte
//

import UIKit

// MARK: - ThreadDetailViewController

/// The thread route, inside the anime page: the children of the anime layout's `gap-4 md:gap-6` column are
/// the header, the post, the replies label and then everything `Comments.svelte` has (each comment, the skeleton,
/// the states and the page buttons), so the same gap is between all of them.
final class ThreadDetailViewController: UIViewController {

    // MARK: - Init
    private let threadID: Int
    private let animeID: Int
    private let threadTitle: String
    private let badgeColors: ThreadBadgeColors
    private let preloadedThread: AniListThread?
    var onContentHeightChange: (() -> Void)?
    /// The thread after the page changed it or heard of a newer one: the list that holds it takes it too.
    var onThreadChange: ((AniListThread) -> Void)?
    private var currentThread: AniListThread?
    private var appliedMedium: Bool?
    private var postView: ThreadPostView?
    private var commentsView: ThreadCommentsView?
    var routeThreadID: Int { threadID }

    init(threadID: Int,
         animeID: Int,
         title: String,
         coverColor: String?,
         preloadedThread: AniListThread? = nil) {
        self.threadID = threadID
        self.animeID = animeID
        self.threadTitle = title
        let cover = coverColor ?? Router.shared.cachedAnimeItem(for: animeID)?.coverColor
        self.badgeColors = ThreadBadgeColors(coverColor: cover)
        self.preloadedThread = preloadedThread
        super.init(nibName: nil, bundle: nil)
        self.title = title
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Views
    private let contentStack = UIStackView()
    private let headerView = ThreadPageHeaderView()
    private let repliesLabel = UILabel()
    private let spinner: UIActivityIndicatorView = {
        let view = UIActivityIndicatorView(style: .large)
        view.color = UIColor.HayaseTheme.foreground
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupView()
        if let thread = preloadedThread ?? ThreadRouteLoader.cached(threadID: threadID) {
            currentThread = thread
            showPage()
            refreshThread()
        } else {
            fetchThread()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // `md` is asked of the window, live
        if appliedMedium != isMedium {
            applyMetrics()
            notifyContentHeightChanged()
        }
    }

    // MARK: - Setup
    private func setupView() {
        view.backgroundColor = .clear

        contentStack.axis = .vertical
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        headerView.onBack = { [weak self] in self?.goBack() }
        repliesLabel.numberOfLines = 1

        view.addSubview(contentStack)
        view.addSubview(spinner)
        NSLayoutConstraint.activate([
            contentStack.topAnchor.constraint(equalTo: view.topAnchor),
            contentStack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            contentStack.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    /// `$breakpoints.md`, of the window
    private var isMedium: Bool {
        (view.window?.bounds.width ?? UIScreen.main.bounds.width) >= 768
    }

    /// What `md` changes: the gap of the column (`gap-4 md:gap-6`) and the size of the title and of the replies label
    /// (`text-[20px] md:text-2xl`).
    private func applyMetrics() {
        let medium = isMedium
        appliedMedium = medium
        let gap: CGFloat = medium ? 24 : 16
        contentStack.spacing = gap
        commentsView?.setGap(gap)
        if let postView { contentStack.setCustomSpacing(40 + gap, after: postView) }   // `mb-10` of the post
        headerView.setMedium(medium)
        updateRepliesLabel()
    }

    // MARK: - Fetch
    /// A route that has not got its thread (the interface's `+layout.ts` waits for it before the page shows).
    private func fetchThread() {
        spinner.startAnimating()
        ThreadRouteLoader.load(threadID: threadID) { [weak self] result in
            guard let self else { return }
            self.spinner.stopAnimating()
            switch result {
            case .success(let thread):
                self.currentThread = thread
                self.showPage()
            case .failure(let error):
                self.showError(error.localizedDescription)
            }
        }
    }

    /// `cache-and-network`: the thread the page opened with is shown, and what the network answers follows into the
    /// same page.
    private func refreshThread() {
        ThreadRouteLoader.load(threadID: threadID) { [weak self] result in
            guard let self, case .success(let answered) = result, let thread = answered else { return }
            self.currentThread = thread
            self.postView?.update(thread: thread)
            self.commentsView?.isLocked = thread.isLocked
            self.updateRepliesLabel()
            self.threadDidChange()
        }
    }

    // MARK: - Render
    /// The header, the post, the replies label and the comments.
    private func showPage() {
        contentStack.arrangedSubviews.forEach { view in
            contentStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        headerView.setTitle(currentThread.map { $0.rawTitle ?? "No thread title..." } ?? threadTitle)
        contentStack.addArrangedSubview(headerView)

        let post = ThreadPostView()
        postView = post
        post.onContentHeightChange = { [weak self] in
            self?.notifyContentHeightChanged()
        }
        post.configure(thread: currentThread,
                       badgeColors: badgeColors,
                       onNavigatePath: { [weak self] path in
            self?.navigate(path: path)
        }, onLike: { [weak self] in
            self?.toggleThreadLike()
        }, onReply: { [weak self] in
            self?.commentsView?.presentWriter()
        })
        contentStack.addArrangedSubview(post)

        contentStack.addArrangedSubview(repliesLabel)

        let comments = ThreadCommentsView(threadID: threadID)
        comments.isLocked = currentThread?.isLocked ?? false
        comments.onContentHeightChange = { [weak self] in
            self?.notifyContentHeightChanged()
        }
        comments.onNavigatePath = { [weak self] path in
            self?.navigate(path: path)
        }
        commentsView = comments
        contentStack.addArrangedSubview(comments)
        applyMetrics()
    }

    private func updateRepliesLabel() {
        let medium = appliedMedium ?? isMedium
        repliesLabel.attributedText = CSSText.string("\(currentThread?.replyCount ?? 0) Replies",
                                                     font: .nunito(ofSize: medium ? 24 : 20, weight: .bold),
                                                     color: UIColor.HayaseTheme.foreground,
                                                     lineHeight: medium ? 32 : 30)
    }

    private func showError(_ message: String) {
        contentStack.arrangedSubviews.forEach { view in
            contentStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        headerView.setTitle(threadTitle)
        contentStack.addArrangedSubview(headerView)
        contentStack.addArrangedSubview(ThreadStateView(text: "Looks like something went wrong!", detail: message))
        applyMetrics()
        notifyContentHeightChanged()
    }

    // MARK: - Actions
    /// The thread as the page has it now: the list and the cache have the same one.
    private func threadDidChange() {
        guard let currentThread else { return }
        Router.shared.cacheThread(currentThread)
        onThreadChange?(currentThread)
    }

    private func toggleThreadLike() {
        guard let thread = currentThread else { return }
        guard !thread.isLocked, TrackerAccountManager.shared.isLoggedIn(.anilist) else { return }
        // `optimistic.ToggleLikeV2`: the heart flips and the count moves before the answer
        let wasLiked = thread.isLiked ?? false
        let count = thread.likeCount
        let optimisticCount = count + (wasLiked ? -1 : 1)
        currentThread?.isLiked = !wasLiked
        currentThread?.likeCount = optimisticCount
        postView?.updateLike(isLiked: !wasLiked, count: optimisticCount)
        threadDidChange()
        AniListForumClient.shared.toggleLikeResult(id: thread.id,
                                                   type: "THREAD",
                                                   wasLiked: wasLiked,
                                                   likeCount: count) { [weak self] result in
            guard let self else { return }
            guard self.currentThread?.id == thread.id else { return }
            // a like that fails is undone, without a word: the interface has no message for it
            let state: (isLiked: Bool, likeCount: Int)
            switch result {
            case .success(let answered):
                state = answered
            case .failure:
                state = (wasLiked, count)
            }
            self.currentThread?.isLiked = state.isLiked
            self.currentThread?.likeCount = state.likeCount
            self.postView?.updateLike(isLiked: state.isLiked, count: state.likeCount)
            self.threadDidChange()
        }
    }

    private func notifyContentHeightChanged() {
        DispatchQueue.main.async { [weak self] in
            self?.onContentHeightChange?()
        }
    }

    private func goBack() {
        _ = Router.shared.navigate(path: "/app/anime/\(animeID)", hostTabIndex: hayaseTabIndex)
    }

    private func navigate(path: String) {
        _ = Router.shared.navigate(path: path, hostTabIndex: hayaseTabIndex)
    }
}

// MARK: - ThreadPageHeaderView

/// `flex items-center w-full`: the back button (`size-9 mr-2`) and the title (`text-[20px] md:text-2xl font-bold
/// line-clamp-1`). When the title is longer than the row both give way, in proportion to their sizes (the size of
/// the title is its whole text), as flex items do.
final class ThreadPageHeaderView: UIView {
    private let backButton = Button(iconName: "chevron-left", pointSize: 16)
    private let titleLabel = UILabel()
    private var titleWidth: NSLayoutConstraint!
    private var title = ""
    private var isMedium = true
    private var fullTitleWidth: CGFloat = 0
    var onBack: (() -> Void)?

    init() {
        super.init(frame: .zero)
        titleWidth = titleLabel.widthAnchor.constraint(equalToConstant: 0)
        backButton.applyGhostVariant()
        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
        titleLabel.numberOfLines = 1
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(backButton)
        addSubview(titleLabel)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 36),
            backButton.leadingAnchor.constraint(equalTo: leadingAnchor),
            backButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: backButton.trailingAnchor, constant: 8),   // `mr-2`
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleWidth,
        ])
        applyTitle()
    }

    required init?(coder: NSCoder) { fatalError() }

    func setTitle(_ title: String) {
        self.title = title
        applyTitle()
    }

    func setMedium(_ medium: Bool) {
        guard medium != isMedium else { return }
        isMedium = medium
        applyTitle()
    }

    private func applyTitle() {
        let text = CSSText.string(title, font: .nunito(ofSize: isMedium ? 24 : 20, weight: .bold),
                                  color: UIColor.HayaseTheme.foreground, lineHeight: isMedium ? 32 : 30)
        titleLabel.attributedText = text
        fullTitleWidth = ceil(text.size().width)
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let backBasis: CGFloat = 36
        let margin: CGFloat = 8
        let total = backBasis + fullTitleWidth
        let overflow = max(0, total + margin - bounds.width)
        let backWidth = backBasis - overflow * backBasis / total
        let titleWidthValue = max(0, fullTitleWidth - overflow * fullTitleWidth / total)
        if abs(backButton.widthConstraint.constant - backWidth) > 0.01 { backButton.widthConstraint.constant = backWidth }
        if abs(titleWidth.constant - titleWidthValue) > 0.01 { titleWidth.constant = titleWidthValue }
    }

    @objc private func backTapped() {
        onBack?()
    }
}

// MARK: - ThreadPostView

/// The post of the thread: `rounded-md bg-muted text-secondary-foreground flex w-full py-6 px-8 flex-col`.
final class ThreadPostView: UIView {
    private let rootStack = UIStackView()
    private let headerRow = UIStackView()
    private let userRow = UIStackView()
    private let avatarStack = FollowerAvatarStackView()
    private let usernameLabel = UILabel()
    private let statsHost = UIView()
    private let statsView = ThreadStatsView()
    private let bodyHost = UIStackView()
    /// `flex w-full justify-between mt-auto text-[9.6px]`: the buttons (`mr-1`) and the date (`ml-2`), and the categories,
    /// which go on more lines when the post is narrow
    private let footerRow = ThreadFooterRowView(alignment: .center, topInset: 0, itemSpacing: 4, dateGap: 8)
    private let likeButton = ThreadForumIconButton(iconName: "heart")
    private let replyButton = ThreadForumIconButton(iconName: "reply")
    private var bodyHeightConstraint: NSLayoutConstraint?
    private var shownBody: String?
    private var shownBadgeColors: ThreadBadgeColors?
    private var onNavigatePath: ((String) -> Void)?
    private var canLike = false
    var onContentHeightChange: (() -> Void)?
    private var onLike: (() -> Void)?
    private var onReply: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        backgroundColor = hayaseCardBackground
        layer.cornerRadius = 6
        clipsToBounds = true

        rootStack.axis = .vertical
        rootStack.spacing = 0
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rootStack)

        headerRow.axis = .horizontal
        headerRow.alignment = .top
        headerRow.distribution = .fill
        headerRow.spacing = 8
        rootStack.addArrangedSubview(headerRow)
        rootStack.setCustomSpacing(8, after: headerRow)   // `mb-2` of the user row

        userRow.axis = .horizontal
        userRow.alignment = .center
        userRow.spacing = 16   // `mr-4` of the avatar
        headerRow.addArrangedSubview(userRow)

        avatarStack.translatesAutoresizingMaskIntoConstraints = false
        userRow.addArrangedSubview(avatarStack)

        usernameLabel.numberOfLines = 1
        usernameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        userRow.addArrangedSubview(usernameLabel)

        headerRow.addArrangedSubview(UIView())

        // `ml-2 mt-0.5`
        statsView.translatesAutoresizingMaskIntoConstraints = false
        statsHost.addSubview(statsView)
        NSLayoutConstraint.activate([
            statsView.topAnchor.constraint(equalTo: statsHost.topAnchor, constant: 2),
            statsView.leadingAnchor.constraint(equalTo: statsHost.leadingAnchor),
            statsView.trailingAnchor.constraint(equalTo: statsHost.trailingAnchor),
            statsView.bottomAnchor.constraint(equalTo: statsHost.bottomAnchor),
        ])
        headerRow.addArrangedSubview(statsHost)

        bodyHost.axis = .vertical
        rootStack.addArrangedSubview(bodyHost)

        likeButton.addTarget(self, action: #selector(likeTapped), for: .touchUpInside)
        replyButton.addTarget(self, action: #selector(replyTapped), for: .touchUpInside)
        footerRow.setLeadingItems([likeButton, replyButton])
        // more lines of categories make the post taller, and the page has to be measured again
        footerRow.onContentHeightChange = { [weak self] in self?.onContentHeightChange?() }
        rootStack.addArrangedSubview(footerRow)

        NSLayoutConstraint.activate([
            rootStack.topAnchor.constraint(equalTo: topAnchor, constant: 24),
            rootStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 32),
            rootStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -32),
            rootStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -24),
        ])
    }

    func configure(thread: AniListThread?,
                   badgeColors: ThreadBadgeColors,
                   onNavigatePath: @escaping (String) -> Void,
                   onLike: @escaping () -> Void,
                   onReply: @escaping () -> Void) {
        self.onLike = onLike
        self.onReply = onReply
        self.onNavigatePath = onNavigatePath
        shownBadgeColors = badgeColors
        shownBody = nil
        update(thread: thread)
    }

    /// The thread again, for what changed: the body is only built again when it is another text, as the web view
    /// that draws it would flash.
    func update(thread: AniListThread?) {
        let user = thread?.user
        avatarStack.reset()
        if let user {
            avatarStack.configure(users: [user], avatarSize: 32, ringWidth: 0, ringColor: .clear)
        }
        // `{#if thread.user}`: no user, no avatar and no name
        usernameLabel.attributedText = user.map {
            CSSText.string($0.name, font: .nunito(ofSize: 20, weight: .bold),
                           color: UIColor.HayaseTheme.secondaryForeground, lineHeight: 20)   // `leading-none`
        }
        statsView.configure(likes: thread?.likeCount ?? 0,
                            views: thread?.viewCount ?? 0,
                            replies: thread?.replyCount ?? 0,
                            locked: thread?.isLocked ?? false,
                            liked: thread?.isLiked ?? false)

        let canInteract = !(thread?.isLocked ?? false) && TrackerAccountManager.shared.isLoggedIn(.anilist)
        canLike = canInteract && thread != nil
        likeButton.setFilled(thread?.isLiked ?? false)
        likeButton.isEnabled = canLike
        replyButton.isEnabled = canInteract && thread != nil

        let body = thread?.body ?? ""
        if body != shownBody {
            shownBody = body
            bodyHost.arrangedSubviews.forEach { view in
                bodyHost.removeArrangedSubview(view)
                view.removeFromSuperview()
            }
            let shadow = AniListShadowView(html: body, kind: .thread)
            shadow.onNavigatePath = onNavigatePath
            shadow.translatesAutoresizingMaskIntoConstraints = false
            bodyHost.addArrangedSubview(shadow)
            let height = shadow.heightAnchor.constraint(equalToConstant: 1)
            height.isActive = true
            bodyHeightConstraint = height
            shadow.onHeightChange = { [weak self] height in
                self?.bodyHeightConstraint?.constant = height
                self?.setNeedsLayout()
                self?.onContentHeightChange?()
            }
        }

        footerRow.setContent(date: CSSText.string(thread?.sinceString ?? "", font: .nunito(ofSize: 9.6),
                                                  color: UIColor.HayaseTheme.secondaryForeground, lineHeight: 14.4,
                                                  lineBreak: .byWordWrapping),
                             badges: shownBadgeColors.map { colors in
            (thread?.categories ?? []).map { ThreadBadgeLabel.make(title: $0, colors: colors) }
        } ?? [])
    }

    func updateLike(isLiked: Bool, count: Int) {
        statsView.updateLikes(count: count, liked: isLiked)
        likeButton.setFilled(isLiked)
        finishLikeAttempt()
    }

    func finishLikeAttempt() {
        likeButton.isEnabled = canLike
    }

    @objc private func likeTapped() {
        onLike?()
    }

    @objc private func replyTapped() {
        onReply?()
    }
}

// MARK: - Hosted by the anime layout

/// The anime layout's `<slot />`: the route of a thread takes the place of the tabs' content.
extension AnimeDetailViewController {

    func applyEmbeddedThreadRoute(threadID: Int?, title: String?) {
        loadViewIfNeeded()
        if embeddedThreadID == threadID, embeddedThreadTitle == title { return }
        embeddedThreadID = threadID
        embeddedThreadTitle = title
        if threadID == nil {
            activeSection = .episodes
            embeddedThreadViewController?.willMove(toParent: nil)
            embeddedThreadViewController?.view.removeFromSuperview()
            embeddedThreadViewController?.removeFromParent()
            embeddedThreadViewController = nil
        }
        applyTabBarLayoutForSizeClass()
        tableView.reloadData()
    }

    func makeEmbeddedThreadCell() -> UITableViewCell {
        guard let threadID = embeddedThreadID, let animeID = routeAnimeID else { return UITableViewCell() }
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.backgroundColor = .clear
        cell.contentView.backgroundColor = .clear
        cell.selectionStyle = .none

        let threadVC: ThreadDetailViewController
        let didCreateThreadController: Bool
        if let existing = embeddedThreadViewController, existing.routeThreadID == threadID {
            threadVC = existing
            didCreateThreadController = false
        } else {
            embeddedThreadViewController?.willMove(toParent: nil)
            embeddedThreadViewController?.view.removeFromSuperview()
            embeddedThreadViewController?.removeFromParent()
            threadVC = ThreadDetailViewController(threadID: threadID,
                                                  animeID: animeID,
                                                  title: embeddedThreadTitle ?? Router.shared.cachedThreadTitle(for: threadID) ?? "Thread",
                                                  coverColor: animeItem?.coverColor,
                                                  preloadedThread: ThreadRouteLoader.cached(threadID: threadID))
            threadVC.onContentHeightChange = { [weak self] in
                self?.invalidateEmbeddedThreadHeight()
            }
            threadVC.onThreadChange = { [weak self] thread in
                self?.updateListedThread(thread)
            }
            addChild(threadVC)
            embeddedThreadViewController = threadVC
            didCreateThreadController = true
        }

        threadVC.view.removeFromSuperview()
        threadVC.view.translatesAutoresizingMaskIntoConstraints = false
        cell.contentView.addSubview(threadVC.view)

        let sidePad = Self.interfacePageSideInset(for: viewportWidth)
        // +layout.svelte's outer column is gap-4 / md:gap-6. The genres and
        // tags row is the item immediately before <slot />, so preserve that
        // exact gap before the embedded thread route begins.
        let topGap: CGFloat = isMediumViewport ? 24 : 16
        NSLayoutConstraint.activate([
            threadVC.view.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: topGap),
            threadVC.view.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -40),   // `pb-10`
            threadVC.view.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: sidePad),
            threadVC.view.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor, constant: -sidePad),
        ])
        if didCreateThreadController {
            threadVC.didMove(toParent: self)
        }
        return cell
    }

    func invalidateEmbeddedThreadHeight() {
        guard embeddedThreadID != nil else { return }
        UIView.performWithoutAnimation {
            tableView.beginUpdates()
            tableView.endUpdates()
        }
    }
}
