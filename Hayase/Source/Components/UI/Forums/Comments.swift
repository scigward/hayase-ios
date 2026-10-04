//
//  Comments.swift
//  Hayase
//
//  Native UIKit shell for AniList forum thread detail.
//  Mirrors: src/routes/app/anime/[id]/thread/[threadId]/+layout.ts, src/routes/app/anime/[id]/thread/[threadId]/+page.svelte, src/lib/components/ui/forums/Comments.svelte
//

import UIKit

final class ThreadDetailViewController: UIViewController {

    // MARK: - Init
    private let threadID: Int
    private let animeID: Int?
    private let threadTitle: String
    private let accentColor: UIColor
    private let isEmbeddedInAnimePage: Bool
    private let preloadedThread: AniListThread?
    private let perPage = 15
    var onContentHeightChange: (() -> Void)?
    private var currentPage = 1
    private var currentThread: AniListThread?
    private var currentCommentsPage: AniListCommentPage?
    private weak var postView: ThreadPostView?
    var routeThreadID: Int { threadID }

    init(threadID: Int,
         animeID: Int? = nil,
         title: String,
         accentColor: UIColor? = nil,
         embeddedInAnimePage: Bool = false,
         preloadedThread: AniListThread? = nil) {
        self.threadID = threadID
        self.animeID = animeID
        self.threadTitle = title
        let cachedAccent = animeID
            .flatMap { Router.shared.cachedAnimeItem(for: $0) }
            .flatMap { ExtensionSearchViewController.uiColor(fromHex: $0.coverColor ?? "") }
        self.accentColor = accentColor ?? cachedAccent ?? UIColor.HayaseTheme.secondary
        self.isEmbeddedInAnimePage = embeddedInAnimePage
        self.preloadedThread = preloadedThread
        super.init(nibName: nil, bundle: nil)
        self.title = title
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Views
    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
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
            renderLoadingComments()
            fetchComments(page: 1)
        } else {
            fetchThread()
        }
    }

    // MARK: - Setup
    private func setupView() {
        view.backgroundColor = isEmbeddedInAnimePage ? .clear : UIColor.HayaseTheme.background

        contentStack.axis = .vertical
        contentStack.spacing = 16
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(spinner)

        if isEmbeddedInAnimePage {
            view.addSubview(contentStack)
            NSLayoutConstraint.activate([
                contentStack.topAnchor.constraint(equalTo: view.topAnchor),
                contentStack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                contentStack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                contentStack.bottomAnchor.constraint(equalTo: view.bottomAnchor),

                spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            ])
        } else {
            scrollView.backgroundColor = .clear
            scrollView.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(scrollView)
            scrollView.addSubview(contentStack)

            NSLayoutConstraint.activate([
                scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
                scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

                contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 16),
                contentStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 16),
                contentStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -16),
                contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -32),
                contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -32),

                spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            ])
        }
    }

    // MARK: - Fetch
    private func fetchThread() {
        spinner.startAnimating()
        AniListForumClient.shared.threadDetailResult(threadID: threadID, page: currentPage) { [weak self] result in
            guard let self else { return }
            self.spinner.stopAnimating()
            switch result {
            case .success(let payload):
                self.currentThread = payload.thread
                self.currentCommentsPage = payload.comments
                self.render(thread: payload.thread, commentsPage: payload.comments)
            case .failure(let error):
                self.showError(error.localizedDescription)
            }
        }
    }

    private func fetchComments(page: Int) {
        currentPage = page
        renderLoadingComments()
        AniListForumClient.shared.commentsResult(threadID: threadID, page: page) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let page):
                self.currentCommentsPage = page
                self.render(thread: self.currentThread, commentsPage: page)
            case .failure(let error):
                self.showCommentsError(error.localizedDescription)
            }
        }
    }

    // MARK: - Render
    private func render(thread: AniListThread?, commentsPage: AniListCommentPage) {
        renderBase(thread: thread)
        renderComments(thread: thread, commentsPage: commentsPage)
    }

    private func renderBase(thread: AniListThread?) {
        contentStack.arrangedSubviews.forEach { view in
            contentStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        contentStack.addArrangedSubview(makeHeader(title: thread?.title ?? threadTitle))

        let postView = ThreadPostView()
        self.postView = postView
        postView.onContentHeightChange = { [weak self] in
            self?.notifyContentHeightChanged()
        }
        postView.configure(thread: thread,
                           accentColor: accentColor,
                           onNavigatePath: { [weak self] path in
            self?.navigate(path: path)
        }, onLike: { [weak self] in
            self?.toggleThreadLike()
        }, onReply: { [weak self] in
            guard let thread else { return }
            self?.presentWriter(threadID: thread.id)
        })
        contentStack.addArrangedSubview(postView)
        contentStack.setCustomSpacing(40, after: postView)

        let repliesLabel = UILabel()
        repliesLabel.font = .nunito(ofSize: threadTitleFontSize, weight: .bold)
        repliesLabel.textColor = UIColor.HayaseTheme.foreground
        repliesLabel.text = "\(thread?.replyCount ?? currentCommentsPage?.total ?? 0) Replies"
        repliesLabel.numberOfLines = 1
        contentStack.addArrangedSubview(repliesLabel)
    }

    private func renderComments(thread: AniListThread?, commentsPage: AniListCommentPage) {
        let comments = commentsPage.comments
        if comments.isEmpty {
            contentStack.addArrangedSubview(makeEmptyState())
        } else {
            for comment in comments {
                let view = ThreadCommentView(comment: comment,
                                             isLocked: thread?.isLocked ?? false,
                                             onContentHeightChange: { [weak self] in
                    self?.notifyContentHeightChanged()
                }, onNavigatePath: { [weak self] path in
                    self?.navigate(path: path)
                }, onLike: { [weak self] comment in
                    self?.toggleCommentLike(comment)
                }, onReply: { [weak self] comment, _ in
                    self?.presentWriter(threadID: self?.threadID, parentCommentID: comment.id)
                }, onEdit: { [weak self] comment, _ in
                    self?.presentWriter(threadID: self?.threadID, id: comment.id, value: comment.comment)
                }, onDelete: { [weak self] comment, _ in
                    self?.deleteComment(comment)
                })
                contentStack.addArrangedSubview(view)
                contentStack.setCustomSpacing(0, after: view)
            }
        }
        contentStack.addArrangedSubview(makePaginationView(commentsPage: commentsPage))
        notifyContentHeightChanged()
    }

    private func renderLoadingComments() {
        renderBase(thread: currentThread)
        for _ in 0..<4 {
            let skeleton = ThreadCommentSkeletonView()
            contentStack.addArrangedSubview(skeleton)
            contentStack.setCustomSpacing(0, after: skeleton)
        }
        if let currentCommentsPage {
            contentStack.addArrangedSubview(makePaginationView(commentsPage: currentCommentsPage))
        }
        notifyContentHeightChanged()
    }


    private func makePaginationView(commentsPage: AniListCommentPage) -> ThreadPaginationView {
        let view = ThreadPaginationView()
        view.configure(count: commentsPage.total,
                       perPage: perPage,
                       currentPage: currentPage) { [weak self] page in
            self?.fetchComments(page: page)
        }
        return view
    }

    private func showCommentsError(_ message: String) {
        renderBase(thread: currentThread)
        contentStack.addArrangedSubview(makeErrorState(message))
        if let currentCommentsPage {
            contentStack.addArrangedSubview(makePaginationView(commentsPage: currentCommentsPage))
        }
        notifyContentHeightChanged()
    }

    private func makeHeader(title: String) -> UIView {
        let row = UIStackView()
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 8

        let backButton = Button(iconName: "chevron-left", pointSize: 16)
        backButton.applyGhostVariant()
        backButton.addTarget(self, action: #selector(goBack), for: .touchUpInside)
        row.addArrangedSubview(backButton)

        let titleLabel = UILabel()
        titleLabel.font = .nunito(ofSize: threadTitleFontSize, weight: .bold)
        titleLabel.textColor = UIColor.HayaseTheme.foreground
        titleLabel.text = title.isEmpty ? "No thread title..." : title
        titleLabel.numberOfLines = 1
        row.addArrangedSubview(titleLabel)
        return row
    }

    private func makeEmptyState() -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.heightAnchor.constraint(equalToConstant: 320).isActive = true

        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)

        let title = UILabel()
        title.text = "Ooops!"
        title.font = .nunito(ofSize: 36, weight: .bold)
        title.textColor = UIColor.HayaseTheme.foreground
        stack.addArrangedSubview(title)

        let subtitle = UILabel()
        subtitle.text = "Looks like there's nothing here yet!"
        subtitle.font = .nunito(ofSize: 18)
        subtitle.textColor = UIColor.HayaseTheme.mutedForeground
        subtitle.textAlignment = .center
        subtitle.numberOfLines = 0
        stack.addArrangedSubview(subtitle)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -16),
        ])
        return container
    }

    private func showError(_ message: String) {
        contentStack.arrangedSubviews.forEach { view in
            contentStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        contentStack.addArrangedSubview(makeHeader(title: threadTitle))
        contentStack.addArrangedSubview(makeErrorState(message))
        notifyContentHeightChanged()
    }

    private func makeErrorState(_ message: String) -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.heightAnchor.constraint(equalToConstant: 320).isActive = true

        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)

        let title = UILabel()
        title.text = "Ooops!"
        title.font = .nunito(ofSize: 36, weight: .bold)
        title.textColor = UIColor.HayaseTheme.foreground
        stack.addArrangedSubview(title)

        let subtitle = UILabel()
        subtitle.text = "Looks like something went wrong!"
        subtitle.font = .nunito(ofSize: 18)
        subtitle.textColor = UIColor.HayaseTheme.mutedForeground
        stack.addArrangedSubview(subtitle)

        let detail = UILabel()
        detail.text = message
        detail.font = .nunito(ofSize: 18)
        detail.textColor = UIColor.HayaseTheme.mutedForeground
        detail.textAlignment = .center
        detail.numberOfLines = 0
        stack.addArrangedSubview(detail)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -16),
        ])
        return container
    }


    // MARK: - Actions
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
        AniListForumClient.shared.toggleLikeResult(id: thread.id,
                                                   type: "THREAD",
                                                   wasLiked: wasLiked,
                                                   likeCount: count) { [weak self] result in
            guard let self else { return }
            guard self.currentThread?.id == thread.id else { return }
            switch result {
            case .success(let state):
                self.currentThread?.isLiked = state.isLiked
                self.currentThread?.likeCount = state.likeCount
                self.postView?.updateLike(isLiked: state.isLiked, count: state.likeCount)
            case .failure(let error):
                self.currentThread?.isLiked = wasLiked
                self.currentThread?.likeCount = count
                self.postView?.updateLike(isLiked: wasLiked, count: count)
                self.showActionError(error.localizedDescription)
            }
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
            case .failure(let error):
                self.updateVisibleCommentLike(id: comment.id, isLiked: wasLiked, count: count)
                self.showActionError(error.localizedDescription)
            }
        }
    }

    private func updateVisibleCommentLike(id: Int, isLiked: Bool, count: Int) {
        for case let view as ThreadCommentView in contentStack.arrangedSubviews {
            if view.updateLike(commentID: id, isLiked: isLiked, count: count) { break }
        }
    }

    private func finishVisibleCommentLikeAttempt(id: Int) {
        for case let view as ThreadCommentView in contentStack.arrangedSubviews {
            if view.finishLikeAttempt(commentID: id) { break }
        }
    }

    private func presentWriter(threadID: Int?, id: Int? = nil, parentCommentID: Int? = nil, value: String = "") {
        guard let threadID,
              !(currentThread?.isLocked ?? false),
              TrackerAccountManager.shared.isLoggedIn(.anilist) else { return }
        let writer = ThreadWriteViewController(value: value)
        writer.onSend = { [weak self] comment in
            self?.saveComment(id: id, threadID: threadID, parentCommentID: parentCommentID, comment: comment)
        }
        present(writer, animated: true)
    }

    private func saveComment(id: Int?, threadID: Int, parentCommentID: Int?, comment: String) {
        AniListForumClient.shared.commentResult(id: id,
                                                threadID: threadID,
                                                parentCommentID: parentCommentID,
                                                comment: comment,
                                                rootCommentID: threadID) { [weak self] result in
            switch result {
            case .success:
                self?.fetchThread()
            case .failure(let error):
                self?.showActionError(error.localizedDescription)
            }
        }
    }

    private func deleteComment(_ comment: AniListThreadComment) {
        guard !(currentThread?.isLocked ?? false), TrackerAccountManager.shared.isLoggedIn(.anilist) else { return }
        AniListForumClient.shared.deleteCommentResult(id: comment.id, rootCommentID: threadID) { [weak self] result in
            switch result {
            case .success:
                self?.fetchThread()
            case .failure(let error):
                self?.showActionError(error.localizedDescription)
            }
        }
    }

    private func showActionError(_ message: String) {
        let alert = UIAlertController(title: "Ooops!", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Close", style: .default))
        present(alert, animated: true)
    }

    private var threadTitleFontSize: CGFloat {
        UIScreen.main.bounds.width >= 768 ? 24 : 20
    }

    private func notifyContentHeightChanged() {
        guard isEmbeddedInAnimePage else { return }
        DispatchQueue.main.async { [weak self] in
            self?.onContentHeightChange?()
        }
    }

    @objc private func goBack() {
        if let animeID {
            _ = Router.shared.navigate(path: "/app/anime/\(animeID)", hostTabIndex: hayaseTabIndex)
        } else {
            navigationController?.popViewController(animated: true)
        }
    }

    private func navigate(path: String) {
        _ = Router.shared.navigate(path: path, hostTabIndex: hayaseTabIndex)
    }
}

// MARK: - ThreadPostView

//  Native UIKit counterpart for the main forum thread card.

final class ThreadPostView: UIView {
    private let rootStack = UIStackView()
    private let headerRow = UIStackView()
    private let userRow = UIStackView()
    private let avatarStack = FollowerAvatarStackView()
    private let usernameLabel = UILabel()
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

        userRow.axis = .horizontal
        userRow.alignment = .center
        userRow.spacing = 16
        headerRow.addArrangedSubview(userRow)

        avatarStack.translatesAutoresizingMaskIntoConstraints = false
        userRow.addArrangedSubview(avatarStack)

        usernameLabel.font = .nunito(ofSize: 20, weight: .bold)
        usernameLabel.textColor = UIColor.HayaseTheme.secondaryForeground
        usernameLabel.numberOfLines = 1
        usernameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        userRow.addArrangedSubview(usernameLabel)

        headerRow.addArrangedSubview(UIView())
        headerRow.addArrangedSubview(statsView)

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
        dateLabel.font = .nunito(ofSize: 9.6)
        dateLabel.textColor = UIColor.HayaseTheme.mutedForeground
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
                   accentColor: UIColor,
                   onNavigatePath: @escaping (String) -> Void,
                   onLike: @escaping () -> Void,
                   onReply: @escaping () -> Void) {
        self.onLike = onLike
        self.onReply = onReply

        let user = thread?.user
        avatarStack.reset()
        if let user {
            avatarStack.configure(users: [user], avatarSize: 32, ringWidth: 0, ringColor: .clear)
        }
        usernameLabel.text = user?.name ?? thread?.userName ?? "Unknown"
        statsView.configure(likes: thread?.likeCount ?? 0,
                            views: thread?.viewCount ?? 0,
                            replies: thread?.replyCount ?? 0,
                            locked: thread?.isLocked ?? false,
                            liked: thread?.isLiked ?? false,
                            fontSize: 12.8)
        dateLabel.text = thread?.sinceString ?? ""

        let canInteract = !(thread?.isLocked ?? false) && TrackerAccountManager.shared.isLoggedIn(.anilist)
        canLike = canInteract && thread != nil
        likeButton.setFilled(thread?.isLiked ?? false)
        likeButton.isEnabled = canLike
        replyButton.isEnabled = canInteract && thread != nil

        bodyHost.arrangedSubviews.forEach { view in
            bodyHost.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        let shadow = AniListShadowView(html: thread?.body ?? "", kind: .thread)
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

        badgeStack.arrangedSubviews.forEach { view in
            badgeStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        let categories = thread?.categories ?? []
        for category in categories {
            badgeStack.addArrangedSubview(makeBadge(title: category, color: accentColor))
        }
    }

    private func makeBadge(title: String, color: UIColor) -> UILabel {
        let badge = ThreadBadgeLabel()
        badge.text = title
        badge.font = .nunito(ofSize: 9.6, weight: .bold)
        badge.textColor = ExtensionSearchViewController.luminanceContrastColor(for: color)
        badge.backgroundColor = color
        badge.layer.cornerRadius = 4
        badge.clipsToBounds = true
        badge.textAlignment = .center
        return badge
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
