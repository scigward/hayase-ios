//
//  FullBannerFollowing.swift
//  Hayase
//
//  Mirrors: the block at the top of interface components/ui/banner/full-banner.svelte
//
//      <div class='md:pt-14 md:pl-10 p-4 flex space-x-2'>
//        <Avatars users={usersForCurrent} let:user> <Profile {user} class='inline-block size-8 fade-in' />
//        <div class='flex flex-col justify-between leading-none font-medium fade-in'>
//          <div class='text-muted-foreground text-xs'>{usersForCurrent[0]?.name ?? ''}</div>
//          <div class='text-sm'>Also Watched This Series</div>
//
//  The padding belongs to the banner, which places the block; this view is what is inside it.
//

import UIKit

final class FullBannerFollowingView: UIView {
    private let avatarContainer = UIView()
    private var avatarWidthConstraint: NSLayoutConstraint!
    private let nameLabel = UILabel()
    private let captionLabel = UILabel()
    /// The ids of the avatars on show, to tell a different set of followers from the same one.
    private var shownIDs: [Int] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        isHidden = true

        // text-xs (12pt on 16pt) over text-sm (14pt on 20pt), both font-medium: with no space left
        // over, `justify-between` has nothing to spread.
        nameLabel.attributedText = nil
        nameLabel.numberOfLines = 1
        captionLabel.numberOfLines = 1
        captionLabel.attributedText = CSSText.string("Also Watched This Series",
                                                     font: .nunito(ofSize: 14, weight: .medium),
                                                     color: UIColor.HayaseTheme.foreground, lineHeight: 20)

        let textStack = UIStackView(arrangedSubviews: [nameLabel, captionLabel])
        textStack.axis = .vertical
        textStack.alignment = .leading
        textStack.spacing = 0

        // `flex space-x-2`: the avatars, then the text 8pt after them, both from the top
        let row = UIStackView(arrangedSubviews: [avatarContainer, textStack])
        row.axis = .horizontal
        row.alignment = .top
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)

        avatarContainer.backgroundColor = .clear
        avatarWidthConstraint = avatarContainer.widthAnchor.constraint(equalToConstant: 32)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: topAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor),
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            avatarWidthConstraint,
            avatarContainer.heightAnchor.constraint(equalToConstant: 32),   // size-8
        ])
    }

    required init?(coder: NSCoder) {
        nil
    }

    /// No followers hides the block. Its first appearance fades in; so does a different set of
    /// followers, whose avatars are new elements of the keyed `{#each}`.
    func configure(users: [AniListUserSummary]) {
        guard let firstUser = users.first else {
            isHidden = true
            shownIDs = []
            rebuildAvatars(users: [])
            return
        }
        let appearing = isHidden
        let ids = users.map(\.id)
        let changed = ids != shownIDs
        shownIDs = ids
        nameLabel.attributedText = CSSText.string(firstUser.name, font: .nunito(ofSize: 12, weight: .medium),
                                                  color: UIColor.HayaseTheme.mutedForeground, lineHeight: 16)
        if changed { rebuildAvatars(users: users) }
        isHidden = false
        if appearing {
            layer.add(Self.mountFade(), forKey: "fade-in")
        } else if changed {
            avatarContainer.layer.add(Self.mountFade(), forKey: "fade-in")
        }
    }

    func reset() {
        layer.removeAllAnimations()
        avatarContainer.layer.removeAllAnimations()
        isHidden = true
        shownIDs = []
        nameLabel.attributedText = nil
        rebuildAvatars(users: [])
    }

    /// `Avatars`: each `size-8`, 8pt over the one before and with a 4pt cut out of it.
    private func rebuildAvatars(users: [AniListUserSummary]) {
        avatarContainer.subviews.forEach { $0.removeFromSuperview() }
        avatarWidthConstraint.constant = 32 + CGFloat(max(0, users.count - 1)) * 24
        guard !users.isEmpty else { return }
        let profiles = FollowerAvatarStackView()
        profiles.configure(users: users, avatarSize: 32, ringWidth: 0,
                           ringColor: UIColor.HayaseTheme.primary, overlap: 8, cutoutBorder: 4) { id, completion in
            AniListClient.shared.fetchUserProfileResult(id: id) { result in
                completion(try? result.get())
            }
        }
        profiles.translatesAutoresizingMaskIntoConstraints = false
        avatarContainer.addSubview(profiles)
        NSLayoutConstraint.activate([
            profiles.leadingAnchor.constraint(equalTo: avatarContainer.leadingAnchor),
            profiles.topAnchor.constraint(equalTo: avatarContainer.topAnchor),
            profiles.heightAnchor.constraint(equalToConstant: 32),
        ])
    }

    /// app.css `.fade-in`: `animation: fade-in ease .8s`.
    static func mountFade() -> CABasicAnimation {
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.duration = 0.8
        fade.timingFunction = CAMediaTimingFunction(controlPoints: 0.25, 0.1, 0.25, 1)
        return fade
    }
}
