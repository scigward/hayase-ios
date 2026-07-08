//
//  ThreadCommentView.swift
//  Hayase
//
//  Native UIKit counterpart for recursive AniList forum comments.
//

import UIKit

final class ThreadCommentView: UIView {
    private let comment: AniListThreadComment
    private let isLocked: Bool
    private let threadID: Int
    private let depth: Int
    private let onNavigatePath: (String) -> Void

    private let rootStack = UIStackView()
    private let headerRow = UIStackView()
    private let userRow = UIStackView()
    private let avatarStack = FollowerAvatarStackView()
    private let usernameLabel = UILabel()
    private let likeStack = UIStackView()
    private let bodyHost = UIStackView()
    private let footerRow = UIStackView()
    private let dateLabel = UILabel()
    private var bodyHeightConstraint: NSLayoutConstraint?

    init(comment: AniListThreadComment,
         isLocked: Bool,
         threadID: Int,
         depth: Int = 0,
         onNavigatePath: @escaping (String) -> Void) {
        self.comment = comment
        self.isLocked = isLocked
        self.threadID = threadID
        self.depth = depth
        self.onNavigatePath = onNavigatePath
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

        footerRow.axis = .horizontal
        footerRow.alignment = .center
        footerRow.spacing = 4
        footerRow.layoutMargins = UIEdgeInsets(top: 0, left: 24, bottom: 0, right: 24)
        footerRow.isLayoutMarginsRelativeArrangement = true
        rootStack.addArrangedSubview(footerRow)

        footerRow.addArrangedSubview(ThreadForumIconButton(iconName: "heart"))
        footerRow.addArrangedSubview(ThreadForumIconButton(iconName: "reply"))
        dateLabel.font = .nunito(ofSize: 9.6)
        dateLabel.textColor = UIColor.HayaseTheme.mutedForeground
        footerRow.addArrangedSubview(dateLabel)
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
        }

        for child in comment.childCommentItems {
            let wrapper = UIView()
            wrapper.translatesAutoresizingMaskIntoConstraints = false
            let childView = ThreadCommentView(comment: child,
                                              isLocked: isLocked || comment.isLocked,
                                              threadID: threadID,
                                              depth: depth + 1,
                                              onNavigatePath: onNavigatePath)
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
}

final class ThreadForumIconButton: UIButton {
    init(iconName: String) {
        super.init(frame: .zero)
        setup(iconName: iconName)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup(iconName: "circle-question-mark")
    }

    private func setup(iconName: String) {
        backgroundColor = .clear
        tintColor = UIColor.HayaseTheme.foreground
        setImage(UIImage.hayaseIcon(iconName, withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .regular)), for: .normal)
        isUserInteractionEnabled = false
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 28),
            heightAnchor.constraint(equalToConstant: 28),
        ])
    }
}
