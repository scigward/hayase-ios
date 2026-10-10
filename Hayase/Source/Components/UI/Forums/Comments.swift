//
//  Comments.swift
//  Hayase
//
//  Native UIKit shell for AniList forum thread detail.
//  Mirrors: src/routes/app/anime/[id]/thread/[threadId]/+layout.ts, src/routes/app/anime/[id]/thread/[threadId]/+page.svelte, src/lib/components/ui/forums/Comments.svelte
//

import UIKit

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
    private let perPage = 15
    var onContentHeightChange: (() -> Void)?
    /// The thread after the page changed it or heard of a newer one: the list that holds it takes it too.
    var onThreadChange: ((AniListThread) -> Void)?
    private var currentPage = 1
    private var currentThread: AniListThread?
    private var currentCommentsPage: AniListCommentPage?
    private var commentsLoading = false
    private var commentsError: String?
    private var appliedMedium: Bool?
    private var postView: ThreadPostView?
    /// `Write.svelte` keeps the text in its `value`: the button that was used opens a writer that has it again.
    private var drafts: [String: String] = [:]
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
    private let commentsStack = UIStackView()
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
        if let thread = preloadedThread ?? Router.shared.cachedThread(for: threadID) {
            currentThread = thread
            showPage()
            loadComments(page: 1)
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
        commentsStack.axis = .vertical

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
        commentsStack.spacing = gap
        if let postView { contentStack.setCustomSpacing(40 + gap, after: postView) }   // `mb-10` of the post
        headerView.setMedium(medium)
        updateRepliesLabel()
    }

    // MARK: - Fetch
    /// A route that has not got its thread (the interface's `+layout.ts` waits for it before the page shows).
    private func fetchThread() {
        spinner.startAnimating()
        AniListForumClient.shared.threadResult(threadID: threadID) { [weak self] result in
            guard let self else { return }
            self.spinner.stopAnimating()
            switch result {
            case .success(let thread):
                self.currentThread = thread
                if let thread { Router.shared.cacheThread(thread) }
                self.showPage()
                self.loadComments(page: 1)
            case .failure(let error):
                self.showError(error.localizedDescription)
            }
        }
    }

    /// `cache-and-network`: the thread the page opened with is shown, and what the network answers follows into the
    /// same page.
    private func refreshThread() {
        AniListForumClient.shared.threadResult(threadID: threadID) { [weak self] result in
            guard let self, case .success(let answered) = result, let thread = answered else { return }
            self.currentThread = thread
            self.postView?.update(thread: thread)
            self.updateRepliesLabel()
            self.threadDidChange()
        }
    }

    private func loadComments(page: Int) {
        currentPage = page
        commentsLoading = true
        commentsError = nil
        reloadCommentsArea()
        AniListForumClient.shared.commentsResult(threadID: threadID, page: page) { [weak self] result in
            guard let self, self.currentPage == page else { return }
            self.commentsLoading = false
            switch result {
            case .success(let commentsPage):
                self.currentCommentsPage = commentsPage
            case .failure(let error):
                self.commentsError = error.localizedDescription   // `$comments.error.message`
            }
            self.reloadCommentsArea()
        }
    }

    // MARK: - Render
    /// The header, the post and the replies label: they do not change with the comments.
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
            self?.presentWriter()
        })
        contentStack.addArrangedSubview(post)

        contentStack.addArrangedSubview(repliesLabel)
        contentStack.addArrangedSubview(commentsStack)
        applyMetrics()
    }

    private func updateRepliesLabel() {
        let medium = appliedMedium ?? isMedium
        repliesLabel.attributedText = CSSText.string("\(currentThread?.replyCount ?? 0) Replies",
                                                     font: .nunito(ofSize: medium ? 24 : 20, weight: .bold),
                                                     color: UIColor.HayaseTheme.foreground,
                                                     lineHeight: medium ? 32 : 30)
    }

    /// What `Comments.svelte` shows under the replies label, apart from the post: only this is built again when the
    /// page of comments, their loading or their list changes.
    private func reloadCommentsArea() {
        commentsStack.arrangedSubviews.forEach { view in
            commentsStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        if commentsLoading {
            for _ in 0..<4 {
                commentsStack.addArrangedSubview(ThreadCommentSkeletonView())
            }
        } else if let commentsError {
            commentsStack.addArrangedSubview(ThreadStateView(text: "Looks like something went wrong!", detail: commentsError))
        } else if let comments = currentCommentsPage?.comments, !comments.isEmpty {
            for comment in comments {
                commentsStack.addArrangedSubview(makeCommentView(comment))
            }
        } else {
            commentsStack.addArrangedSubview(ThreadStateView(text: "Looks like there's nothing here yet!"))
        }
        commentsStack.addArrangedSubview(makePaginationView())
        notifyContentHeightChanged()
    }

    private func makeCommentView(_ comment: AniListThreadComment) -> ThreadCommentView {
        ThreadCommentView(comment: comment,
                          isLocked: currentThread?.isLocked ?? false,
                          onContentHeightChange: { [weak self] in
            self?.notifyContentHeightChanged()
        }, onNavigatePath: { [weak self] path in
            self?.navigate(path: path)
        }, onLike: { [weak self] comment in
            self?.toggleCommentLike(comment)
        }, onReply: { [weak self] comment, _ in
            self?.presentWriter(parentCommentID: comment.id)
        }, onEdit: { [weak self] comment, _ in
            self?.presentWriter(id: comment.id, value: comment.comment)
        }, onDelete: { [weak self] comment, _ in
            self?.deleteComment(comment)
        })
    }

    /// `count = $comments.data?.Page?.pageInfo?.total ?? 0`: nothing until the page is there.
    private func makePaginationView() -> ThreadPaginationView {
        let view = ThreadPaginationView()
        let count = commentsLoading || commentsError != nil ? 0 : (currentCommentsPage?.total ?? 0)
        view.configure(count: count,
                       perPage: perPage,
                       currentPage: currentPage) { [weak self] page in
            self?.loadComments(page: page)
        }
        return view
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

    private func toggleCommentLike(_ comment: AniListThreadComment) {
        guard !(currentThread?.isLocked ?? false), TrackerAccountManager.shared.isLoggedIn(.anilist) else { return }
        let wasLiked = comment.isLiked ?? false
        let count = comment.likeCount
        updateVisibleCommentLike(id: comment.id, isLiked: !wasLiked, count: count + (wasLiked ? -1 : 1))
        AniListForumClient.shared.toggleLikeResult(id: comment.id,
                                                   type: "THREAD_COMMENT",
                                                   wasLiked: wasLiked,
                                                   likeCount: count) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let state):
                self.updateVisibleCommentLike(id: comment.id, isLiked: state.isLiked, count: state.likeCount)
            case .failure:
                self.updateVisibleCommentLike(id: comment.id, isLiked: wasLiked, count: count)
            }
        }
    }

    private func updateVisibleCommentLike(id: Int, isLiked: Bool, count: Int) {
        for case let view as ThreadCommentView in commentsStack.arrangedSubviews {
            if view.updateLike(commentID: id, isLiked: isLiked, count: count) { break }
        }
    }

    private func presentWriter(id: Int? = nil, parentCommentID: Int? = nil, value: String = "") {
        guard !(currentThread?.isLocked ?? false),
              TrackerAccountManager.shared.isLoggedIn(.anilist) else { return }
        let key = "\(id ?? 0)|\(parentCommentID ?? 0)"
        let writer = ThreadWriteViewController(value: drafts[key] ?? value)
        writer.onChange = { [weak self] text in self?.drafts[key] = text }
        writer.onSend = { [weak self] comment in
            self?.saveComment(id: id, parentCommentID: parentCommentID, comment: comment)
        }
        // the dialog fades by itself
        present(writer, animated: false)
    }

    /// The mutation invalidates the comments of the thread in the cache and the comments are asked for again; the
    /// thread is not (its reply count stays what it was). A failure says nothing, as in the interface.
    private func saveComment(id: Int?, parentCommentID: Int?, comment: String) {
        AniListForumClient.shared.commentResult(id: id,
                                                threadID: threadID,
                                                parentCommentID: parentCommentID,
                                                comment: comment,
                                                rootCommentID: threadID) { [weak self] result in
            guard let self, case .success = result else { return }
            self.loadComments(page: self.currentPage)
        }
    }

    private func deleteComment(_ comment: AniListThreadComment) {
        guard !(currentThread?.isLocked ?? false), TrackerAccountManager.shared.isLoggedIn(.anilist) else { return }
        AniListForumClient.shared.deleteCommentResult(id: comment.id, rootCommentID: threadID) { [weak self] result in
            guard let self, case .success = result else { return }
            self.loadComments(page: self.currentPage)
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

// MARK: - ThreadStateView

/// The "Ooops!" of `Threads.svelte` and `Comments.svelte`: `p-5 flex items-center justify-center w-full h-80`, a
/// title (`mb-1 font-bold text-4xl`) and lines of `text-lg text-muted-foreground`, an error's message the last.
final class ThreadStateView: UIView {
    init(text: String, detail: String? = nil) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 320).isActive = true   // `h-80`

        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        stack.addArrangedSubview(line("Ooops!", size: 36, lineHeight: 40, weight: .bold, color: UIColor.HayaseTheme.foreground))
        stack.setCustomSpacing(4, after: stack.arrangedSubviews[0])   // `mb-1`
        stack.addArrangedSubview(line(text, size: 18, lineHeight: 28, weight: .regular, color: UIColor.HayaseTheme.mutedForeground))
        if let detail {
            stack.addArrangedSubview(line(detail, size: 18, lineHeight: 28, weight: .regular, color: UIColor.HayaseTheme.mutedForeground))
        }

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -20),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    private func line(_ text: String, size: CGFloat, lineHeight: CGFloat, weight: UIFont.Weight, color: UIColor) -> UILabel {
        let label = UILabel()
        label.numberOfLines = 0
        label.attributedText = CSSText.string(text, font: .nunito(ofSize: size, weight: weight), color: color,
                                              lineHeight: lineHeight, alignment: .center, lineBreak: .byWordWrapping)
        return label
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
    private let footerRow = UIStackView()
    private let footerLeading = UIStackView()
    private let likeButton = ThreadForumIconButton(iconName: "heart")
    private let replyButton = ThreadForumIconButton(iconName: "reply")
    private let dateLabel = UILabel()
    private let dateContainer = UIStackView()
    private let badgeStack = UIStackView()
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

        footerRow.axis = .horizontal
        footerRow.alignment = .bottom
        footerRow.distribution = .fill
        footerRow.spacing = 8
        rootStack.addArrangedSubview(footerRow)

        footerLeading.axis = .horizontal
        footerLeading.alignment = .center
        footerLeading.spacing = 4
        footerRow.addArrangedSubview(footerLeading)

        likeButton.addTarget(self, action: #selector(likeTapped), for: .touchUpInside)
        footerLeading.addArrangedSubview(likeButton)

        replyButton.addTarget(self, action: #selector(replyTapped), for: .touchUpInside)
        footerLeading.addArrangedSubview(replyButton)

        dateContainer.axis = .horizontal
        dateContainer.layoutMargins = UIEdgeInsets(top: 0, left: 4, bottom: 0, right: 0)
        dateContainer.isLayoutMarginsRelativeArrangement = true
        dateContainer.addArrangedSubview(dateLabel)
        footerLeading.addArrangedSubview(dateContainer)

        footerRow.addArrangedSubview(UIView())

        badgeStack.axis = .horizontal
        badgeStack.alignment = .bottom
        badgeStack.spacing = 8
        footerRow.addArrangedSubview(badgeStack)

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
        dateLabel.attributedText = CSSText.string(thread?.sinceString ?? "", font: .nunito(ofSize: 9.6),
                                                  color: UIColor.HayaseTheme.secondaryForeground, lineHeight: 14.4)

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

        badgeStack.arrangedSubviews.forEach { view in
            badgeStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        if let shownBadgeColors {
            for category in thread?.categories ?? [] {
                badgeStack.addArrangedSubview(ThreadBadgeLabel.make(title: category, colors: shownBadgeColors))
            }
        }
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
