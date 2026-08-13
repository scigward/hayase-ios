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
//     <img class='w-10 h-10 rounded-full p-1 mt-auto' />   ← 32pt visible avatar
//     <div class='text-md pl-2'>{name}</div>                ← 16px, 8pt left margin
//     <ExternalLink size='18' class='ml-auto text-blue-600' /> ← AniList link
//   </div>

final class ChatUserListCell: UITableViewCell {
    static let reuseID = "ChatUserListCell"

    private let avatarImageView = UIImageView()
    private let nameLabel = UILabel()
    private let linkButton = UIButton(type: .system)

    private var userID: String = ""

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .none

        let avatarSize: CGFloat = 32  // w-10 h-10 p-1 → 32pt visible

        // Avatar: rounded-full
        avatarImageView.layer.cornerRadius = avatarSize / 2
        avatarImageView.clipsToBounds = true
        avatarImageView.contentMode = .scaleAspectFill
        avatarImageView.translatesAutoresizingMaskIntoConstraints = false

        // Name: text-md (16px), pl-2 (8pt)
        nameLabel.font = .nunito(ofSize: 16)
        nameLabel.textColor = .white
        nameLabel.translatesAutoresizingMaskIntoConstraints = false

        // External link button: ml-auto text-blue-600, ExternalLink size=18
        let linkConfig = UIImage.SymbolConfiguration(pointSize: 16, weight: .regular)
        linkButton.setImage(UIImage.hayaseIcon("external-link", withConfiguration: linkConfig), for: .normal)
        linkButton.tintColor = UIColor(red: 0.22, green: 0.42, blue: 0.93, alpha: 1.0) // blue-600
        linkButton.translatesAutoresizingMaskIntoConstraints = false
        linkButton.addTarget(self, action: #selector(openProfile), for: .touchUpInside)

        contentView.addSubview(avatarImageView)
        contentView.addSubview(nameLabel)
        contentView.addSubview(linkButton)

        NSLayoutConstraint.activate([
            // Avatar: left with padding, pb-2 = 8pt bottom, px-5 = 20pt from web
            avatarImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20), // px-5
            avatarImageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            avatarImageView.widthAnchor.constraint(equalToConstant: avatarSize),
            avatarImageView.heightAnchor.constraint(equalToConstant: avatarSize),
            avatarImageView.topAnchor.constraint(greaterThanOrEqualTo: contentView.topAnchor, constant: 4),
            avatarImageView.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -8), // pb-2

            // Name: pl-2 = 8pt
            nameLabel.leadingAnchor.constraint(equalTo: avatarImageView.trailingAnchor, constant: 8),
            nameLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

            // Link button: ml-auto (trailing), match px-5 padding
            linkButton.leadingAnchor.constraint(greaterThanOrEqualTo: nameLabel.trailingAnchor, constant: 8),
            linkButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20), // px-5
            linkButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            linkButton.widthAnchor.constraint(equalToConstant: 28),
            linkButton.heightAnchor.constraint(equalToConstant: 28),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func openProfile() {
        guard !userID.isEmpty,
              let url = URL(string: "https://anilist.co/user/" + userID) else { return }
        UIApplication.shared.open(url)
    }

    /// Guests (IRC only — W2G's `isGuest` always defaults to `false`) get no
    /// profile link, mirroring `ChatProfile.svelte`'s `!user.guest` check.
    func configure(with user: ChatListUser) {
        nameLabel.text = user.name
        userID = user.id
        linkButton.isHidden = user.isGuest
        avatarImageView.image = nil
        guard let url = URL(string: user.resolvedAvatarURL) else {
            avatarImageView.backgroundColor = UIColor(white: 0.2, alpha: 1)
            return
        }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data, let img = UIImage(data: data) else { return }
            DispatchQueue.main.async { self?.avatarImageView.image = img }
        }.resume()
    }
}