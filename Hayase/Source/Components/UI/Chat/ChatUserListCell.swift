//
//  ChatUserListCell.swift
//  Hayase
//
//  Created by scigward.
//
//  A single reusable userlist row, shared between W2G and IRC chat.
//  Mirrors `UserList.svelte`, which interface itself shares between the two
//  the same way (`components/ui/chat/UserList.svelte`).
//
//  This used to be two separate, hand-copied implementations —
//  `W2GUserCell` (private to W2GViewController.swift) and `IRCUserCell`
//  (private to HayaseChatViewController.swift). The IRC copy drifted from
//  the W2G original in three visible ways: an extra vertical separator
//  view W2G's layout never had, a narrower fixed width (180pt vs W2G's
//  288pt / `md:w-72`), and avatar/label constraints that resolved to a much
//  taller row than W2G's ~44pt. Rather than hand-fix that copy and risk a
//  fourth divergence later, this extracts the original `W2GUserCell` body
//  verbatim (down to leaving image loading uncached, exactly as it was)
//  behind a small protocol, so there is exactly one implementation from
//  here on.
//
//  Fixed in this pass: the avatar used to be a plain `UIImageView` with an
//  "open AniList in the browser" button next to it (`ExternalLink`,
//  `openProfile()`). Neither exists in the actual web source — the real
//  `UserList.svelte` has no such button at all; each user's avatar is a
//  `ChatProfile.svelte`, which wraps a `Popover` that opens an in-app
//  profile card on tap. That card is already built natively
//  (`ProfileCardViewController` in Profile.swift, reached through the
//  public `FollowerAvatarStackView` façade), so this now reuses it directly
//  instead of the browser-opening stand-in — which also gets the avatar its
//  real `ring-4 ring-background` ring (`Profile.svelte`'s default avatar
//  class) for free. `Profile.swift` renders whatever `AniListUserSummary`
//  it's given rather than fetching by ID itself, and chat only has a
//  user's id/name/avatar, so the card's bio/banner/stats sit at their
//  built-in empty-state fallback here (see HayaseChatViewController.swift's
//  header comment for the reasoning on not adding a fetch-by-id call for
//  this pass). The real `Popover.Trigger` isn't guest-gated either — it
//  opens for every user, just with sparse data for ones the store can't
//  resolve — so this drops the previous `isGuest`-based hiding too.
//

import UIKit

/// The minimum shape `ChatUserListCell` needs from a user model. Both
/// `W2GChatUser` and `IRCUser` conform to this — see their own files for
/// the (trivial, additive) conformance.
protocol ChatListUser {
    var id: String { get }
    var name: String { get }
    /// Already-resolved (never nil) avatar URL. Named to match
    /// `W2GChatUser.resolvedAvatarURL`, which already has this exact shape.
    var resolvedAvatarURL: String { get }
    var isGuest: Bool { get }
}

extension ChatListUser {
    /// Default for conforming types that don't have a guest concept
    /// (currently just W2G). IRC overrides this with its real value.
    var isGuest: Bool { false }
}

// Web layout per user:
//   <div class='flex items-center pb-2'>
//     <ChatProfile {user} />                  ← Profile.svelte avatar, size-8
//                                                (32pt) + ring-4 ring-background,
//                                                tap opens a Popover profile card
//     <div class='text-md pl-2'>{name}</div>  ← 16px, 8pt left margin
//   </div>

final class ChatUserListCell: UITableViewCell {
    static let reuseID = "ChatUserListCell"
    private static let avatarSize: CGFloat = 32 // size-8

    private let profileStack = FollowerAvatarStackView()
    private let nameLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .none

        profileStack.translatesAutoresizingMaskIntoConstraints = false

        // Name: text-md (16px), pl-2 (8pt)
        nameLabel.font = .nunito(ofSize: 16)
        nameLabel.textColor = .white
        nameLabel.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(profileStack)
        contentView.addSubview(nameLabel)

        NSLayoutConstraint.activate([
            // Avatar: left with padding, pb-2 = 8pt bottom, px-5 = 20pt from web
            profileStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20), // px-5
            profileStack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            profileStack.widthAnchor.constraint(equalToConstant: Self.avatarSize),
            profileStack.heightAnchor.constraint(equalToConstant: Self.avatarSize),
            profileStack.topAnchor.constraint(greaterThanOrEqualTo: contentView.topAnchor, constant: 4),
            profileStack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -8), // pb-2

            // Name: pl-2 = 8pt
            nameLabel.leadingAnchor.constraint(equalTo: profileStack.trailingAnchor, constant: 8),
            nameLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -20), // px-5
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override func prepareForReuse() {
        super.prepareForReuse()
        profileStack.reset()
    }

    func configure(with user: ChatListUser) {
        nameLabel.text = user.name
        let summary = AniListUserSummary(id: Int(user.id) ?? 0,
                                         name: user.name,
                                         avatarURL: user.resolvedAvatarURL)
        profileStack.configure(users: [summary],
                                avatarSize: Self.avatarSize,
                                ringWidth: 4,
                                ringColor: UIColor.HayaseTheme.background)
    }
}
