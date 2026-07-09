//
//  ThreadDetailViewController.swift
//  Hayase
//
//  Native UIKit shell for AniList forum thread detail.
//  Mirrors: src/routes/app/anime/[id]/thread/[threadId]/+page.svelte
//

import UIKit

final class ThreadDetailViewController: UIViewController {

    // MARK: - Init
    private let threadID: Int
    private let threadTitle: String
    private let accentColor: UIColor
    private let perPage = 15
    private var currentPage = 1
    private var currentThread: AniListThread?
    private var currentCommentsPage: AniListCommentPage?
    var routeThreadID: Int { threadID }

    init(threadID: Int, title: String, accentColor: UIColor? = nil) {
        self.threadID = threadID
        self.threadTitle = title
        self.accentColor = accentColor ?? UIColor.HayaseTheme.secondary
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
        fetchThread()
    }

    // MARK: - Setup
    private func setupView() {
        view.backgroundColor = UIColor.HayaseTheme.background

        scrollView.backgroundColor = .clear
        scrollView.alwaysBounceVertical = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        contentStack.axis = .vertical
        contentStack.spacing = 16
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)

        view.addSubview(spinner)

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
        postView.configure(thread: thread,
                           fallbackTitle: threadTitle,
                           accentColor: accentColor,
                           onNavigatePath: { [weak self] path in
            self?.navigate(path: path)
        }, onLike: { [weak self] in
            guard let thread else { return }
            self?.toggleThreadLike(thread)
        }, onReply: { [weak self] in
            guard let thread else { return }
            self?.presentWriter(threadID: thread.id)
        })
        contentStack.addArrangedSubview(postView)
        contentStack.setCustomSpacing(40, after: postView)

        let repliesLabel = UILabel()
        repliesLabel.font = .nunito(ofSize: 20, weight: .bold)
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
                                             threadID: threadID,
                                             onNavigatePath: { [weak self] path in
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
            }
        }
        contentStack.addArrangedSubview(makePaginationView(commentsPage: commentsPage))
    }

    private func renderLoadingComments() {
        renderBase(thread: currentThread)
        for _ in 0..<4 {
            contentStack.addArrangedSubview(ThreadCommentSkeletonView())
        }
        if let currentCommentsPage {
            contentStack.addArrangedSubview(makePaginationView(commentsPage: currentCommentsPage))
        }
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
    }

    private func makeHeader(title: String) -> UIView {
        let row = UIStackView()
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 8

        let backButton = Button(iconName: "chevron-left", pointSize: 16)
        backButton.backgroundColor = .clear
        backButton.addTarget(self, action: #selector(goBack), for: .touchUpInside)
        row.addArrangedSubview(backButton)

        let titleLabel = UILabel()
        titleLabel.font = .nunito(ofSize: 20, weight: .bold)
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
    private func toggleThreadLike(_ thread: AniListThread) {
        guard !thread.isLocked, TrackerAccountManager.shared.isLoggedIn(.anilist) else { return }
        AniListForumClient.shared.toggleLikeResult(id: thread.id,
                                                   type: "THREAD",
                                                   wasLiked: thread.isLiked ?? false) { [weak self] result in
            switch result {
            case .success:
                self?.fetchThread()
            case .failure(let error):
                self?.showActionError(error.localizedDescription)
            }
        }
    }

    private func toggleCommentLike(_ comment: AniListThreadComment) {
        guard !(currentThread?.isLocked ?? false), !comment.isLocked, TrackerAccountManager.shared.isLoggedIn(.anilist) else { return }
        AniListForumClient.shared.toggleLikeResult(id: comment.id,
                                                   type: "THREAD_COMMENT",
                                                   wasLiked: comment.isLiked ?? false) { [weak self] result in
            switch result {
            case .success:
                self?.fetchComments(page: self?.currentPage ?? 1)
            case .failure(let error):
                self?.showActionError(error.localizedDescription)
            }
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
        guard !(currentThread?.isLocked ?? false), !comment.isLocked, TrackerAccountManager.shared.isLoggedIn(.anilist) else { return }
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

    @objc private func goBack() {
        navigationController?.popViewController(animated: true)
    }

    private func navigate(path: String) {
        _ = Router.shared.navigate(path: path, hostTabIndex: tabBarController?.selectedIndex)
    }
}
