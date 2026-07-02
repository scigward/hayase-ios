//
//  Profile.swift
//  Hayase
//
//  Created by scigward.
//  Mirrors: lib/components/ui/profile/Profile.svelte
//

import UIKit

final class FollowerAvatarStackView: UIStackView {
    private var buttons: [ProfileButton] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        axis = .horizontal
        spacing = -4
        alignment = .center
        isHidden = true
    }

    func configure(users: [AniListUserSummary],
                   avatarSize: CGFloat = 32,
                   ringWidth: CGFloat = 4,
                   ringColor: UIColor = UIColor.HayaseTheme.background) {
        reset()
        let visibleUsers = users.filter { !$0.name.isEmpty }
        isHidden = visibleUsers.isEmpty
        visibleUsers.forEach { user in
            let button = ProfileButton(user: user,
                                       avatarSize: avatarSize,
                                       ringWidth: ringWidth,
                                       ringColor: ringColor)
            button.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                button.widthAnchor.constraint(equalToConstant: avatarSize),
                button.heightAnchor.constraint(equalToConstant: avatarSize),
            ])
            buttons.append(button)
            addArrangedSubview(button)
        }
    }

    func reset() {
        buttons.forEach { $0.prepareForReuse() }
        buttons.removeAll()
        arrangedSubviews.forEach { view in
            removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        isHidden = true
    }
}

private final class ProfileButton: UIControl {
    private let user: AniListUserSummary
    private let avatarView: ProfileAvatarView

    init(user: AniListUserSummary,
         avatarSize: CGFloat,
         ringWidth: CGFloat,
         ringColor: UIColor) {
        self.user = user
        self.avatarView = ProfileAvatarView(user: user,
                                            avatarSize: avatarSize,
                                            ringWidth: ringWidth,
                                            ringColor: ringColor)
        super.init(frame: .zero)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup() {
        accessibilityLabel = user.name
        addTarget(self, action: #selector(showProfile), for: .touchUpInside)

        avatarView.isUserInteractionEnabled = false
        avatarView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(avatarView)
        NSLayoutConstraint.activate([
            avatarView.topAnchor.constraint(equalTo: topAnchor),
            avatarView.leadingAnchor.constraint(equalTo: leadingAnchor),
            avatarView.trailingAnchor.constraint(equalTo: trailingAnchor),
            avatarView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    func prepareForReuse() {
        avatarView.prepareForReuse()
    }

    @objc private func showProfile() {
        guard let presenter = nearestViewController else { return }
        let card = ProfileCardViewController(user: user)
        card.modalPresentationStyle = .popover
        card.preferredContentSize = CGSize(width: 308, height: 328)
        if let popover = card.popoverPresentationController {
            popover.sourceView = self
            popover.sourceRect = bounds
            popover.permittedArrowDirections = [.up, .down, .left, .right]
            popover.backgroundColor = .clear
            popover.delegate = card
        }
        presenter.present(card, animated: true)
    }
}

private final class ProfileAvatarView: UIView {
    private var imageTask: URLSessionDataTask?
    private let user: AniListUserSummary
    private let imageView = UIImageView()
    private let fallbackLabel = UILabel()
    private let skeletonView = UIView()

    init(user: AniListUserSummary,
         avatarSize: CGFloat,
         ringWidth: CGFloat,
         ringColor: UIColor) {
        self.user = user
        super.init(frame: .zero)
        layer.cornerRadius = avatarSize / 2
        layer.borderWidth = ringWidth
        layer.borderColor = ringColor.cgColor
        setup()
        loadAvatar()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2
        imageView.layer.cornerRadius = bounds.height / 2
        skeletonView.layer.cornerRadius = bounds.height / 2
    }

    private func setup() {
        backgroundColor = UIColor.HayaseTheme.background
        clipsToBounds = true

        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)

        fallbackLabel.text = user.name
        fallbackLabel.font = .nunito(ofSize: 8, weight: .bold)
        fallbackLabel.textColor = UIColor.HayaseTheme.foreground
        fallbackLabel.textAlignment = .center
        fallbackLabel.adjustsFontSizeToFitWidth = true
        fallbackLabel.minimumScaleFactor = 0.35
        fallbackLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(fallbackLabel)

        skeletonView.backgroundColor = UIColor.HayaseTheme.muted
        skeletonView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(skeletonView)

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor),

            fallbackLabel.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            fallbackLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            fallbackLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            fallbackLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),

            skeletonView.topAnchor.constraint(equalTo: topAnchor),
            skeletonView.leadingAnchor.constraint(equalTo: leadingAnchor),
            skeletonView.trailingAnchor.constraint(equalTo: trailingAnchor),
            skeletonView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    private func loadAvatar() {
        guard let urlString = user.avatarURL,
              !urlString.isEmpty,
              let url = URL(string: urlString) else {
            skeletonView.isHidden = true
            return
        }
        if let cached = SharedImageCache.shared.object(forKey: urlString as NSString) {
            imageView.image = cached
            fallbackLabel.isHidden = true
            skeletonView.isHidden = true
            return
        }
        startSkeleton()
        imageTask = URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let self else { return }
            guard let data,
                  let image = UIImage(data: data) else {
                DispatchQueue.main.async { self.stopSkeleton(showFallback: true) }
                return
            }
            SharedImageCache.shared.setObject(image, forKey: urlString as NSString)
            DispatchQueue.main.async {
                self.imageView.image = image
                self.stopSkeleton(showFallback: false)
            }
        }
        imageTask?.resume()
    }

    private func startSkeleton() {
        skeletonView.isHidden = false
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 0.35
        pulse.toValue = 0.85
        pulse.duration = 0.75
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        skeletonView.layer.add(pulse, forKey: "profile-avatar-skeleton")
    }

    private func stopSkeleton(showFallback: Bool) {
        skeletonView.layer.removeAnimation(forKey: "profile-avatar-skeleton")
        skeletonView.isHidden = true
        fallbackLabel.isHidden = !showFallback && imageView.image != nil
    }

    func prepareForReuse() {
        imageTask?.cancel()
        imageTask = nil
        skeletonView.layer.removeAnimation(forKey: "profile-avatar-skeleton")
    }
}

private final class ProfileCardViewController: UIViewController, UIPopoverPresentationControllerDelegate {
    private let user: AniListUserSummary
    private let rootGradient = CAGradientLayer()
    private let coreView = UIView()
    private let headerView = UIView()
    private let bannerImageView = UIImageView()
    private let avatarView: ProfileAvatarView
    private var bannerTask: URLSessionDataTask?

    init(user: AniListUserSummary) {
        self.user = user
        self.avatarView = ProfileAvatarView(user: user,
                                            avatarSize: 80,
                                            ringWidth: 0,
                                            ringColor: .clear)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        bannerTask?.cancel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupView()
        loadBanner()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        rootGradient.frame = view.bounds
        coreView.layer.cornerRadius = 6
        headerView.layer.cornerRadius = 6
        bannerImageView.layer.cornerRadius = 6
        bannerImageView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
    }

    private func setupView() {
        view.backgroundColor = .clear
        rootGradient.colors = [
            profileBaseColor.cgColor,
            UIColor(red: 34/255, green: 33/255, blue: 30/255, alpha: 1).cgColor,
        ]
        rootGradient.startPoint = CGPoint(x: 0.5, y: 0)
        rootGradient.endPoint = CGPoint(x: 0.5, y: 1)
        view.layer.insertSublayer(rootGradient, at: 0)
        view.layer.cornerRadius = 6
        view.clipsToBounds = true

        coreView.backgroundColor = mixedCoreColor
        coreView.clipsToBounds = true
        coreView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(coreView)

        headerView.backgroundColor = user.bannerURL == nil ? UIColor.HayaseTheme.primary.withAlphaComponent(0.1) : .clear
        headerView.translatesAutoresizingMaskIntoConstraints = false
        coreView.addSubview(headerView)

        bannerImageView.contentMode = .scaleAspectFill
        bannerImageView.alpha = 0.5
        bannerImageView.clipsToBounds = true
        bannerImageView.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(bannerImageView)

        avatarView.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(avatarView)

        let nameLabel = UILabel()
        nameLabel.text = user.name
        nameLabel.font = .nunito(ofSize: 24, weight: .heavy)
        nameLabel.textColor = UIColor.HayaseTheme.foreground
        nameLabel.numberOfLines = 1
        nameLabel.lineBreakMode = .byTruncatingTail

        let detailLabel = UILabel()
        detailLabel.text = detailText
        detailLabel.font = .nunito(ofSize: 11, weight: .regular)
        detailLabel.textColor = UIColor.HayaseTheme.foreground.withAlphaComponent(0.8)
        detailLabel.numberOfLines = 1
        detailLabel.lineBreakMode = .byTruncatingTail

        let textStack = UIStackView(arrangedSubviews: [nameLabel, detailLabel])
        textStack.axis = .vertical
        textStack.spacing = 1
        textStack.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(textStack)

        let bubbleView = makeBubbleView()
        if let bubbleView {
            bubbleView.translatesAutoresizingMaskIntoConstraints = false
            headerView.addSubview(bubbleView)
        }

        let aboutLabel = UILabel()
        aboutLabel.text = sanitizedHTML(user.about) ?? "No user description"
        aboutLabel.font = .nunito(ofSize: 14, weight: .regular)
        aboutLabel.textColor = UIColor.HayaseTheme.foreground
        aboutLabel.numberOfLines = 0
        aboutLabel.translatesAutoresizingMaskIntoConstraints = false

        let aboutScroll = UIScrollView()
        aboutScroll.showsVerticalScrollIndicator = true
        aboutScroll.translatesAutoresizingMaskIntoConstraints = false
        aboutScroll.addSubview(aboutLabel)
        coreView.addSubview(aboutScroll)

        let statsLabel = UILabel()
        statsLabel.text = statsText
        statsLabel.font = .nunito(ofSize: 11, weight: .regular)
        statsLabel.textColor = UIColor.HayaseTheme.foreground.withAlphaComponent(0.8)
        statsLabel.numberOfLines = 1
        statsLabel.lineBreakMode = .byTruncatingTail
        statsLabel.translatesAutoresizingMaskIntoConstraints = false
        coreView.addSubview(statsLabel)

        NSLayoutConstraint.activate([
            coreView.topAnchor.constraint(equalTo: view.topAnchor, constant: 4),
            coreView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 4),
            coreView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -4),
            coreView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -4),

            headerView.topAnchor.constraint(equalTo: coreView.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: coreView.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: coreView.trailingAnchor),
            headerView.heightAnchor.constraint(equalToConstant: 105),

            bannerImageView.topAnchor.constraint(equalTo: headerView.topAnchor),
            bannerImageView.leadingAnchor.constraint(equalTo: headerView.leadingAnchor),
            bannerImageView.trailingAnchor.constraint(equalTo: headerView.trailingAnchor),
            bannerImageView.bottomAnchor.constraint(equalTo: headerView.bottomAnchor),

            avatarView.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 12),
            avatarView.bottomAnchor.constraint(equalTo: headerView.bottomAnchor, constant: -12),
            avatarView.widthAnchor.constraint(equalToConstant: 80),
            avatarView.heightAnchor.constraint(equalToConstant: 80),

            textStack.leadingAnchor.constraint(equalTo: avatarView.trailingAnchor, constant: 12),
            textStack.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -12),
            textStack.bottomAnchor.constraint(equalTo: avatarView.bottomAnchor, constant: -2),

            aboutScroll.topAnchor.constraint(equalTo: headerView.bottomAnchor, constant: 8),
            aboutScroll.leadingAnchor.constraint(equalTo: coreView.leadingAnchor, constant: 16),
            aboutScroll.trailingAnchor.constraint(equalTo: coreView.trailingAnchor, constant: -16),
            aboutScroll.heightAnchor.constraint(lessThanOrEqualToConstant: 200),

            aboutLabel.topAnchor.constraint(equalTo: aboutScroll.contentLayoutGuide.topAnchor),
            aboutLabel.leadingAnchor.constraint(equalTo: aboutScroll.contentLayoutGuide.leadingAnchor),
            aboutLabel.trailingAnchor.constraint(equalTo: aboutScroll.contentLayoutGuide.trailingAnchor),
            aboutLabel.bottomAnchor.constraint(equalTo: aboutScroll.contentLayoutGuide.bottomAnchor),
            aboutLabel.widthAnchor.constraint(equalTo: aboutScroll.frameLayoutGuide.widthAnchor),

            statsLabel.topAnchor.constraint(equalTo: aboutScroll.bottomAnchor, constant: 8),
            statsLabel.leadingAnchor.constraint(equalTo: coreView.leadingAnchor, constant: 16),
            statsLabel.trailingAnchor.constraint(equalTo: coreView.trailingAnchor, constant: -16),
            statsLabel.bottomAnchor.constraint(equalTo: coreView.bottomAnchor, constant: -8),
        ])

        if let bubbleView {
            NSLayoutConstraint.activate([
                bubbleView.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: -20),
                bubbleView.topAnchor.constraint(equalTo: headerView.topAnchor, constant: -44),
            ])
        }
    }

    private func makeBubbleView() -> UIView? {
        guard let bubble = user.donatorBadge, !bubble.isEmpty, bubble != "Donator" else { return nil }
        let label = UILabel()
        label.text = bubble
        label.font = .nunito(ofSize: 14, weight: .regular)
        label.textColor = UIColor.HayaseTheme.primaryForeground
        label.numberOfLines = 1
        label.setContentHuggingPriority(.required, for: .horizontal)

        let bubbleView = UIView()
        bubbleView.backgroundColor = blend(.white, profileBaseColor, amount: 0.33)
        bubbleView.layer.cornerRadius = 16
        bubbleView.translatesAutoresizingMaskIntoConstraints = false
        bubbleView.addSubview(label)
        label.translatesAutoresizingMaskIntoConstraints = false

        let dotLarge = UIView()
        dotLarge.backgroundColor = bubbleView.backgroundColor
        dotLarge.layer.cornerRadius = 10
        dotLarge.translatesAutoresizingMaskIntoConstraints = false
        bubbleView.addSubview(dotLarge)

        let dotSmall = UIView()
        dotSmall.backgroundColor = bubbleView.backgroundColor
        dotSmall.layer.cornerRadius = 5
        dotSmall.translatesAutoresizingMaskIntoConstraints = false
        bubbleView.addSubview(dotSmall)

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: bubbleView.topAnchor, constant: 8),
            label.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor, constant: -16),
            label.bottomAnchor.constraint(equalTo: bubbleView.bottomAnchor, constant: -8),

            dotLarge.topAnchor.constraint(equalTo: bubbleView.topAnchor, constant: 42),
            dotLarge.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor, constant: 10),
            dotLarge.widthAnchor.constraint(equalToConstant: 20),
            dotLarge.heightAnchor.constraint(equalToConstant: 20),

            dotSmall.topAnchor.constraint(equalTo: bubbleView.topAnchor, constant: 70),
            dotSmall.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor, constant: 20),
            dotSmall.widthAnchor.constraint(equalToConstant: 10),
            dotSmall.heightAnchor.constraint(equalToConstant: 10),
        ])
        return bubbleView
    }

    private var profileBaseColor: UIColor {
        UIColor(hexString: user.profileColor) ?? .black
    }

    private var mixedCoreColor: UIColor {
        blend(UIColor(red: 20/255, green: 20/255, blue: 20/255, alpha: 1), profileBaseColor, amount: 0.7)
    }

    private var detailText: String {
        var parts: [String] = []
        if user.isFollower { parts.append("Follows you") }
        let joined = AniListUtil.since(Date(timeIntervalSince1970: user.createdAt))
        parts.append("Joined \(joined)")
        return parts.joined(separator: "  ")
    }

    private var statsText: String {
        let watched = AniListUtil.since(Date(timeIntervalSinceNow: -Double(user.minutesWatched) * 60))
            .replacingOccurrences(of: "ago", with: "watched")
        return "\(user.animeCount) anime  \(user.episodesWatched) episodes  \(watched)"
    }

    private func loadBanner() {
        guard let urlString = user.bannerURL,
              !urlString.isEmpty,
              let url = URL(string: urlString) else { return }
        if let cached = SharedImageCache.shared.object(forKey: urlString as NSString) {
            bannerImageView.image = cached
            return
        }
        bannerTask = URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data,
                  let image = UIImage(data: data) else { return }
            SharedImageCache.shared.setObject(image, forKey: urlString as NSString)
            DispatchQueue.main.async {
                self?.bannerImageView.image = image
            }
        }
        bannerTask?.resume()
    }

    private func sanitizedHTML(_ html: String?) -> String? {
        guard let html, !html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let stripped = html
            .replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#039;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return stripped.isEmpty ? nil : stripped
    }

    private func blend(_ first: UIColor, _ second: UIColor, amount: CGFloat) -> UIColor {
        var r1: CGFloat = 0
        var g1: CGFloat = 0
        var b1: CGFloat = 0
        var a1: CGFloat = 0
        var r2: CGFloat = 0
        var g2: CGFloat = 0
        var b2: CGFloat = 0
        var a2: CGFloat = 0
        first.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        second.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return UIColor(red: r1 * (1 - amount) + r2 * amount,
                       green: g1 * (1 - amount) + g2 * amount,
                       blue: b1 * (1 - amount) + b2 * amount,
                       alpha: a1 * (1 - amount) + a2 * amount)
    }

    func adaptivePresentationStyle(for controller: UIPresentationController) -> UIModalPresentationStyle {
        .none
    }
}

private extension UIResponder {
    var nearestViewController: UIViewController? {
        var responder: UIResponder? = self
        while let current = responder {
            if let viewController = current as? UIViewController { return viewController }
            responder = current.next
        }
        return nil
    }
}

private extension UIColor {
    convenience init?(hexString: String?) {
        guard let hex = hexString?.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        var cleanHex = hex
        if cleanHex.hasPrefix("#") { cleanHex = String(cleanHex.dropFirst()) }
        guard cleanHex.count == 6, let rgb = UInt64(cleanHex, radix: 16) else { return nil }
        self.init(red: CGFloat((rgb >> 16) & 0xFF) / 255,
                  green: CGFloat((rgb >> 8) & 0xFF) / 255,
                  blue: CGFloat(rgb & 0xFF) / 255,
                  alpha: 1)
    }
}
