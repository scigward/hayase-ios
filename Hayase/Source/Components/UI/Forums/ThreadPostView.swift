//
//  ThreadPostView.swift
//  Hayase
//
//  Native UIKit counterpart for the main forum thread card.
//

import UIKit

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
        likeButton.setFilled(thread?.isLiked ?? false)
        likeButton.isEnabled = canInteract && thread != nil
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

    @objc private func likeTapped() {
        onLike?()
    }

    @objc private func replyTapped() {
        onReply?()
    }
}
