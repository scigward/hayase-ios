//
//  Comments.swift
//  Hayase
//
//  Mirrors: src/lib/components/ui/forums/Comments.svelte
//

import UIKit

// MARK: - ThreadCommentsView

/// `Comments.svelte`: the comments of a thread a page at a time (`perPage = 15`), each of them, the skeleton, the
/// states and the buttons of the pages, one under the other with the gap of the column it is in (`setGap`).
/// The comments, their likes, the writer and the deleting are all in here, as they are in the interface's `Comment`
/// and `Write`.
final class ThreadCommentsView: UIView {
    private let threadID: Int
    private let perPage = 15
    private let stack = UIStackView()
    private var currentPage = 1
    private var currentCommentsPage: AniListCommentPage?
    private var commentsLoading = false
    private var commentsError: String?
    /// `Write.svelte` keeps the text in its `value`: the button that was used opens a writer that has it again.
    private var drafts: [String: String] = [:]

    /// `export let isLocked`
    var isLocked = false
    var onContentHeightChange: (() -> Void)?
    var onNavigatePath: ((String) -> Void)?

    init(threadID: Int) {
        self.threadID = threadID
        super.init(frame: .zero)
        stack.axis = .vertical
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        loadComments(page: 1)   // `$: comments = client.comments(threadId, currentPage)`
    }

    required init?(coder: NSCoder) { fatalError() }

    /// The gap of the column the comments are in (`gap-4 md:gap-6`).
    func setGap(_ gap: CGFloat) {
        stack.spacing = gap
    }

    // MARK: - Comments
    private func loadComments(page: Int) {
        currentPage = page
        commentsLoading = true
        commentsError = nil
        reloadArea()
        AniListForumClient.shared.commentsResult(threadID: threadID, page: page) { [weak self] result in
            guard let self, self.currentPage == page else { return }
            self.commentsLoading = false
            switch result {
            case .success(let commentsPage):
                self.currentCommentsPage = commentsPage
            case .failure(let error):
                self.commentsError = error.localizedDescription   // `$comments.error.message`
            }
            self.reloadArea()
        }
    }

    /// Only this is built again when the page of comments, their loading or their list changes.
    private func reloadArea() {
        stack.arrangedSubviews.forEach { view in
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        if commentsLoading {
            for _ in 0..<4 {
                stack.addArrangedSubview(ThreadCommentSkeletonView())
            }
        } else if let commentsError {
            stack.addArrangedSubview(ThreadStateView(text: "Looks like something went wrong!", detail: commentsError))
        } else if let comments = currentCommentsPage?.comments, !comments.isEmpty {
            for comment in comments {
                stack.addArrangedSubview(makeCommentView(comment))
            }
        } else {
            stack.addArrangedSubview(ThreadStateView(text: "Looks like there's nothing here yet!"))
        }
        stack.addArrangedSubview(makePaginationView())
        notifyContentHeightChanged()
    }

    private func makeCommentView(_ comment: AniListThreadComment) -> ThreadCommentView {
        ThreadCommentView(comment: comment,
                          isLocked: isLocked,
                          onContentHeightChange: { [weak self] in
            self?.notifyContentHeightChanged()
        }, onNavigatePath: { [weak self] path in
            self?.onNavigatePath?(path)
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

    // MARK: - Actions
    private func toggleCommentLike(_ comment: AniListThreadComment) {
        guard !isLocked, TrackerAccountManager.shared.isLoggedIn(.anilist) else { return }
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
        for case let view as ThreadCommentView in stack.arrangedSubviews {
            if view.updateLike(commentID: id, isLiked: isLiked, count: count) { break }
        }
    }

    /// `Write.svelte`: a new comment on the thread, a reply to a comment (`parentCommentID`) or the edit of one (`id`).
    func presentWriter(id: Int? = nil, parentCommentID: Int? = nil, value: String = "") {
        guard !isLocked,
              TrackerAccountManager.shared.isLoggedIn(.anilist),
              let presenter = nearestViewController else { return }
        let key = "\(id ?? 0)|\(parentCommentID ?? 0)"
        let writer = ThreadWriteViewController(value: drafts[key] ?? value)
        writer.onChange = { [weak self] text in self?.drafts[key] = text }
        writer.onSend = { [weak self] comment in
            self?.saveComment(id: id, parentCommentID: parentCommentID, comment: comment)
        }
        // the dialog fades by itself
        presenter.present(writer, animated: false)
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
        guard !isLocked, TrackerAccountManager.shared.isLoggedIn(.anilist) else { return }
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
}

// MARK: - ThreadCommentSkeletonView

/// A comment on its way: `px-4 py-[18px] shrink-0 h-28 w-full bg-muted rounded-md flex flex-col` around four bars.
final class ThreadCommentSkeletonView: UIView {
    private let stack = UIStackView()

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

        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        stack.addArrangedSubview(bar(width: 150, height: 8))
        stack.addArrangedSubview(bar(width: 112, height: 6))
        stack.addArrangedSubview(bar(width: 80, height: 6))
        stack.addArrangedSubview(UIView())
        stack.addArrangedSubview(bar(width: 96, height: 8))

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 112),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 18),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -18),
        ])
    }

    private func bar(width: CGFloat, height: CGFloat) -> UIView {
        let view = HayaseSkeleton.makeBlock(cornerRadius: 4)   // `bg-primary/5 animate-pulse rounded`
        NSLayoutConstraint.activate([
            view.widthAnchor.constraint(equalToConstant: width),
            view.heightAnchor.constraint(equalToConstant: height),
        ])
        return view
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
