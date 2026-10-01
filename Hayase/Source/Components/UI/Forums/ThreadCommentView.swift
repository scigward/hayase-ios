//
//  ThreadCommentView.swift
//  Hayase
//
//  Native UIKit counterpart for recursive AniList forum comments.
//

import UIKit

final class ThreadCommentView: UIView {
    private var comment: AniListThreadComment
    private let isLocked: Bool
    private let depth: Int
    private let rootCommentID: Int
    private let onContentHeightChange: (() -> Void)?
    private let onNavigatePath: (String) -> Void
    private let onLike: (AniListThreadComment) -> Void
    private let onReply: (AniListThreadComment, Int) -> Void
    private let onEdit: (AniListThreadComment, Int) -> Void
    private let onDelete: (AniListThreadComment, Int) -> Void

    private let rootStack = UIStackView()
    private let headerRow = UIStackView()
    private let userRow = UIStackView()
    private let avatarStack = FollowerAvatarStackView()
    private let usernameLabel = UILabel()
    private let likeStack = UIStackView()
    private let bodyHost = UIStackView()
    private let footerRow = UIStackView()
    private let likeButton = ThreadForumIconButton(iconName: "heart")
    private let replyButton = ThreadForumIconButton(iconName: "reply")
    private let editButton = ThreadForumIconButton(iconName: "pen-line")
    private let deleteButton = ThreadForumIconButton(iconName: "trash-2")
    private let dateLabel = UILabel()
    private let dateContainer = UIStackView()
    private var bodyHeightConstraint: NSLayoutConstraint?
    private var childViews: [ThreadCommentView] = []

    init(comment: AniListThreadComment,
         isLocked: Bool,
         depth: Int = 0,
         rootCommentID: Int? = nil,
         onContentHeightChange: (() -> Void)? = nil,
         onNavigatePath: @escaping (String) -> Void,
         onLike: @escaping (AniListThreadComment) -> Void,
         onReply: @escaping (AniListThreadComment, Int) -> Void,
         onEdit: @escaping (AniListThreadComment, Int) -> Void,
         onDelete: @escaping (AniListThreadComment, Int) -> Void) {
        self.comment = comment
        self.isLocked = isLocked
        self.depth = depth
        self.rootCommentID = rootCommentID ?? comment.id
        self.onContentHeightChange = onContentHeightChange
        self.onNavigatePath = onNavigatePath
        self.onLike = onLike
        self.onReply = onReply
        self.onEdit = onEdit
        self.onDelete = onDelete
        super.init(frame: .zero)
        setup()
        configure()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        backgroundColor = depth % 2 == 1 ? UIColor.HayaseTheme.background : hayaseCardBackground
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
        headerRow.layoutMargins = UIEdgeInsets(top: 0, left: 24, bottom: 0, right: 24)
        headerRow.isLayoutMarginsRelativeArrangement = true
        rootStack.addArrangedSubview(headerRow)

        userRow.axis = .horizontal
        userRow.alignment = .center
        userRow.spacing = 8
        headerRow.addArrangedSubview(userRow)

        avatarStack.translatesAutoresizingMaskIntoConstraints = false
        userRow.addArrangedSubview(avatarStack)

        usernameLabel.font = .nunito(ofSize: 16, weight: .bold)
        usernameLabel.textColor = UIColor.HayaseTheme.secondaryForeground
        usernameLabel.numberOfLines = 1
        usernameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        userRow.addArrangedSubview(usernameLabel)

        headerRow.addArrangedSubview(UIView())

        likeStack.axis = .horizontal
        likeStack.alignment = .center
        likeStack.spacing = 4
        let heart = UIImageView(image: UIImage.hayaseIcon("heart", withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .regular)))
        heart.tintColor = UIColor.HayaseTheme.secondaryForeground
        heart.contentMode = .scaleAspectFit
        heart.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            heart.widthAnchor.constraint(equalToConstant: 12),
            heart.heightAnchor.constraint(equalToConstant: 12),
        ])
        let count = UILabel()
        count.tag = 88
        count.font = .nunito(ofSize: 12.8)
        count.textColor = UIColor.HayaseTheme.secondaryForeground
        likeStack.addArrangedSubview(heart)
        likeStack.addArrangedSubview(count)
        headerRow.addArrangedSubview(likeStack)

        bodyHost.axis = .vertical
        bodyHost.layoutMargins = UIEdgeInsets(top: 0, left: 24, bottom: 0, right: 24)
        bodyHost.isLayoutMarginsRelativeArrangement = true
        rootStack.addArrangedSubview(bodyHost)
        rootStack.setCustomSpacing(8, after: headerRow)

        footerRow.axis = .horizontal
        footerRow.alignment = .center
        footerRow.spacing = 4
        footerRow.layoutMargins = UIEdgeInsets(top: 0, left: 24, bottom: 0, right: 24)
        footerRow.isLayoutMarginsRelativeArrangement = true
        rootStack.addArrangedSubview(footerRow)

        likeButton.addTarget(self, action: #selector(likeTapped), for: .touchUpInside)
        footerRow.addArrangedSubview(likeButton)

        replyButton.addTarget(self, action: #selector(replyTapped), for: .touchUpInside)
        footerRow.addArrangedSubview(replyButton)

        editButton.addTarget(self, action: #selector(editTapped), for: .touchUpInside)
        footerRow.addArrangedSubview(editButton)

        deleteButton.addTarget(self, action: #selector(deleteTapped), for: .touchUpInside)
        footerRow.addArrangedSubview(deleteButton)

        dateContainer.axis = .horizontal
        dateContainer.layoutMargins = UIEdgeInsets(top: 0, left: 4, bottom: 0, right: 0)
        dateContainer.isLayoutMarginsRelativeArrangement = true
        dateLabel.font = .nunito(ofSize: 9.6)
        dateLabel.textColor = UIColor.HayaseTheme.mutedForeground
        dateContainer.addArrangedSubview(dateLabel)
        footerRow.addArrangedSubview(dateContainer)
        footerRow.addArrangedSubview(UIView())

        NSLayoutConstraint.activate([
            rootStack.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            rootStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            rootStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            rootStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
        ])
    }

    private func configure() {
        avatarStack.reset()
        if let user = comment.user {
            avatarStack.configure(users: [user], avatarSize: 20, ringWidth: 0, ringColor: .clear)
        }
        usernameLabel.text = comment.user?.name ?? "N/A"
        (likeStack.arrangedSubviews.compactMap { $0 as? UILabel }.first { $0.tag == 88 })?.text = "\(comment.likeCount)"
        dateLabel.text = comment.sinceString

        let viewerID = Int(TrackerAccountManager.shared.viewer(for: .anilist)?.id ?? "")
        let canInteract = !isLocked && !comment.isLocked && TrackerAccountManager.shared.isLoggedIn(.anilist)
        let isOwner = viewerID == comment.user?.id
        likeButton.setFilled(comment.isLiked ?? false)
        likeButton.isEnabled = canInteract
        replyButton.isEnabled = canInteract
        editButton.isHidden = !isOwner
        deleteButton.isHidden = !isOwner
        editButton.isEnabled = canInteract
        deleteButton.isEnabled = canInteract

        let shadow = AniListShadowView(html: comment.comment, kind: .comment)
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

        for child in comment.childCommentItems {
            let wrapper = UIView()
            wrapper.translatesAutoresizingMaskIntoConstraints = false
            let childView = ThreadCommentView(comment: child,
                                              isLocked: isLocked,
                                              depth: depth + 1,
                                              rootCommentID: rootCommentID,
                                              onContentHeightChange: onContentHeightChange,
                                              onNavigatePath: onNavigatePath,
                                              onLike: onLike,
                                              onReply: onReply,
                                              onEdit: onEdit,
                                              onDelete: onDelete)
            childViews.append(childView)
            childView.translatesAutoresizingMaskIntoConstraints = false
            wrapper.addSubview(childView)
            NSLayoutConstraint.activate([
                childView.topAnchor.constraint(equalTo: wrapper.topAnchor, constant: 8),
                childView.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 16),
                childView.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -8),
                childView.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor, constant: -8),
            ])
            rootStack.insertArrangedSubview(wrapper, at: max(rootStack.arrangedSubviews.count - 1, 0))
        }
    }

    @objc private func likeTapped() {
        onLike(comment)
    }

    @discardableResult
    func updateLike(commentID: Int, isLiked: Bool, count: Int) -> Bool {
        if comment.id == commentID {
            comment.isLiked = isLiked
            comment.likeCount = count
            (likeStack.arrangedSubviews.compactMap { $0 as? UILabel }.first { $0.tag == 88 })?.text = "\(count)"
            likeButton.setFilled(isLiked)
            finishLikeAttempt(commentID: commentID)
            return true
        }
        return childViews.contains { $0.updateLike(commentID: commentID, isLiked: isLiked, count: count) }
    }

    @discardableResult
    func finishLikeAttempt(commentID: Int) -> Bool {
        if comment.id == commentID {
            likeButton.isEnabled = !isLocked && !comment.isLocked && TrackerAccountManager.shared.isLoggedIn(.anilist)
            return true
        }
        return childViews.contains { $0.finishLikeAttempt(commentID: commentID) }
    }

    @objc private func replyTapped() {
        onReply(comment, rootCommentID)
    }

    @objc private func editTapped() {
        onEdit(comment, rootCommentID)
    }

    @objc private func deleteTapped() {
        onDelete(comment, rootCommentID)
    }
}

final class ThreadForumIconButton: UIButton {
    private let iconName: String
    private let pointSize: CGFloat

    init(iconName: String, pointSize: CGFloat = 11.2) {
        self.iconName = iconName
        self.pointSize = pointSize
        super.init(frame: .zero)
        setup()
    }

    required init?(coder: NSCoder) {
        self.iconName = "circle-question-mark"
        self.pointSize = 11.2
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        backgroundColor = .clear
        tintColor = UIColor.HayaseTheme.foreground
        adjustsImageWhenHighlighted = true
        translatesAutoresizingMaskIntoConstraints = false
        setFilled(false)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 25.6),
            heightAnchor.constraint(equalToConstant: 25.6),
        ])
    }

    func setFilled(_ filled: Bool) {
        let image = filled
            ? HayaseIcon.filledImage(iconName, pointSize: pointSize)
            : UIImage.hayaseIcon(iconName, withConfiguration: UIImage.SymbolConfiguration(pointSize: pointSize, weight: .regular))
        setImage(image, for: .normal)
    }

    override var isEnabled: Bool {
        didSet { alpha = isEnabled ? 1 : 0.4 }
    }
}
