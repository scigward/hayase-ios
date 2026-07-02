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
        let card = ProfileCardViewController(user: user, sourceView: self)
        card.modalPresentationStyle = .overFullScreen
        card.modalTransitionStyle = .crossDissolve
        presenter.present(card, animated: false) {
            card.animateIn()
        }
    }

}

private final class ProfileAvatarView: UIView {
    private var imageTask: URLSessionDataTask?
    private let user: AniListUserSummary
    private let imageView = UIImageView()
    private let fallbackLabel = UILabel()
    private let skeletonView = UIView()
    private let ringLayer = CAShapeLayer()
    private let ringWidth: CGFloat
    private let ringColor: UIColor

    init(user: AniListUserSummary,
         avatarSize: CGFloat,
         ringWidth: CGFloat,
         ringColor: UIColor) {
        self.user = user
        self.ringWidth = ringWidth
        self.ringColor = ringColor
        super.init(frame: .zero)
        layer.cornerRadius = avatarSize / 2
        setup()
        loadAvatar()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let radius = bounds.height / 2
        layer.cornerRadius = radius
        imageView.layer.cornerRadius = radius
        skeletonView.layer.cornerRadius = radius

        ringLayer.isHidden = ringWidth <= 0
        ringLayer.fillColor = ringColor.cgColor
        ringLayer.path = UIBezierPath(ovalIn: bounds.insetBy(dx: -ringWidth, dy: -ringWidth)).cgPath
    }

    private func setup() {
        backgroundColor = .clear
        clipsToBounds = false
        layer.masksToBounds = false

        ringLayer.fillColor = ringColor.cgColor
        layer.insertSublayer(ringLayer, at: 0)

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

private final class ProfileCardViewController: UIViewController {
    private static let contentWidth: CGFloat = 300
    private static let outerPadding: CGFloat = 4
    private static let screenMargin: CGFloat = 12
    private static let sideOffset: CGFloat = 16

    private weak var sourceView: UIView?
    private let user: AniListUserSummary
    private let dismissControl = UIControl()
    private let cardShadowView = UIView()
    private let cardContentView = UIView()
    private let rootGradient = CAGradientLayer()
    private let coreView = UIView()
    private let headerView = UIView()
    private let bannerImageView = UIImageView()
    private let avatarView: ProfileAvatarView
    private var bannerTask: URLSessionDataTask?

    init(user: AniListUserSummary, sourceView: UIView) {
        self.user = user
        self.sourceView = sourceView
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
        dismissControl.frame = view.bounds
        layoutCard()
        rootGradient.frame = cardContentView.bounds
        coreView.layer.cornerRadius = 4
        headerView.layer.cornerRadius = 4
        bannerImageView.layer.cornerRadius = 4
        bannerImageView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
    }

    private func setupView() {
        view.backgroundColor = .clear
        view.isOpaque = false

        dismissControl.backgroundColor = .clear
        dismissControl.addTarget(self, action: #selector(dismissPopover), for: .touchUpInside)
        view.addSubview(dismissControl)

        cardShadowView.backgroundColor = .clear
        cardShadowView.layer.shadowColor = UIColor.black.cgColor
        cardShadowView.layer.shadowOpacity = 0.35
        cardShadowView.layer.shadowRadius = 12
        cardShadowView.layer.shadowOffset = CGSize(width: 0, height: 8)
        view.addSubview(cardShadowView)

        cardContentView.backgroundColor = .clear
        cardContentView.clipsToBounds = true
        cardContentView.layer.cornerRadius = 6
        cardShadowView.addSubview(cardContentView)

        rootGradient.colors = [
            profileBaseColor.cgColor,
            UIColor(red: 34/255, green: 33/255, blue: 30/255, alpha: 1).cgColor,
        ]
        rootGradient.startPoint = CGPoint(x: 0.5, y: 0)
        rootGradient.endPoint = CGPoint(x: 0.5, y: 1)
        cardContentView.layer.insertSublayer(rootGradient, at: 0)

        coreView.backgroundColor = mixedCoreColor
        coreView.clipsToBounds = true
        coreView.translatesAutoresizingMaskIntoConstraints = false
        cardContentView.addSubview(coreView)

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
        detailLabel.attributedText = detailText
        detailLabel.font = .nunito(ofSize: 11, weight: .regular)
        detailLabel.textColor = Self.detailTextColor
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
        aboutLabel.text = Self.sanitizedDescription(user.about) ?? "No user description"
        aboutLabel.font = .nunito(ofSize: 14, weight: .regular)
        aboutLabel.textColor = UIColor.HayaseTheme.foreground
        aboutLabel.numberOfLines = 0
        aboutLabel.translatesAutoresizingMaskIntoConstraints = false

        let aboutScroll = UIScrollView()
        aboutScroll.showsVerticalScrollIndicator = false
        aboutScroll.alwaysBounceVertical = false
        aboutScroll.translatesAutoresizingMaskIntoConstraints = false
        aboutScroll.addSubview(aboutLabel)
        coreView.addSubview(aboutScroll)

        let statsLabel = UILabel()
        statsLabel.attributedText = statsText
        statsLabel.font = .nunito(ofSize: 11, weight: .regular)
        statsLabel.textColor = Self.detailTextColor
        statsLabel.numberOfLines = 1
        statsLabel.lineBreakMode = .byTruncatingTail
        statsLabel.translatesAutoresizingMaskIntoConstraints = false
        coreView.addSubview(statsLabel)

        let aboutHeight = Self.aboutBlockHeight(for: aboutLabel.text ?? "")
        let statsHeight = ceil(statsLabel.font.lineHeight)

        NSLayoutConstraint.activate([
            coreView.topAnchor.constraint(equalTo: cardContentView.topAnchor, constant: Self.outerPadding),
            coreView.leadingAnchor.constraint(equalTo: cardContentView.leadingAnchor, constant: Self.outerPadding),
            coreView.trailingAnchor.constraint(equalTo: cardContentView.trailingAnchor, constant: -Self.outerPadding),
            coreView.bottomAnchor.constraint(equalTo: cardContentView.bottomAnchor, constant: -Self.outerPadding),

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
            textStack.bottomAnchor.constraint(equalTo: avatarView.bottomAnchor),

            aboutScroll.topAnchor.constraint(equalTo: headerView.bottomAnchor, constant: 8),
            aboutScroll.leadingAnchor.constraint(equalTo: coreView.leadingAnchor, constant: 16),
            aboutScroll.trailingAnchor.constraint(equalTo: coreView.trailingAnchor, constant: -16),
            aboutScroll.heightAnchor.constraint(equalToConstant: aboutHeight),

            aboutLabel.topAnchor.constraint(equalTo: aboutScroll.contentLayoutGuide.topAnchor, constant: 8),
            aboutLabel.leadingAnchor.constraint(equalTo: aboutScroll.contentLayoutGuide.leadingAnchor),
            aboutLabel.trailingAnchor.constraint(equalTo: aboutScroll.contentLayoutGuide.trailingAnchor),
            aboutLabel.bottomAnchor.constraint(equalTo: aboutScroll.contentLayoutGuide.bottomAnchor, constant: -8),
            aboutLabel.widthAnchor.constraint(equalTo: aboutScroll.frameLayoutGuide.widthAnchor),

            statsLabel.topAnchor.constraint(equalTo: aboutScroll.bottomAnchor, constant: 8),
            statsLabel.leadingAnchor.constraint(equalTo: coreView.leadingAnchor, constant: 16),
            statsLabel.trailingAnchor.constraint(equalTo: coreView.trailingAnchor, constant: -16),
            statsLabel.heightAnchor.constraint(equalToConstant: statsHeight),
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

    private static let detailTextColor = UIColor(red: 229/255, green: 229/255, blue: 229/255, alpha: 1)
    private static let separatorTextColor = UIColor(red: 115/255, green: 115/255, blue: 115/255, alpha: 1)

    private static func preferredSize(for user: AniListUserSummary) -> CGSize {
        let about = sanitizedDescription(user.about) ?? "No user description"
        let aboutHeight = aboutBlockHeight(for: about)
        let statsHeight = ceil(UIFont.nunito(ofSize: 11, weight: .regular).lineHeight)
        let height = outerPadding * 2 + 105 + 8 + aboutHeight + 8 + statsHeight + 8
        return CGSize(width: contentWidth + outerPadding * 2, height: ceil(height))
    }

    private static func aboutBlockHeight(for text: String) -> CGFloat {
        let font = UIFont.nunito(ofSize: 14, weight: .regular)
        let width = contentWidth - 32
        let rect = (text as NSString).boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude),
                                                   options: [.usesLineFragmentOrigin, .usesFontLeading],
                                                   attributes: [.font: font],
                                                   context: nil)
        return min(max(ceil(rect.height), ceil(font.lineHeight)) + 16, 200)
    }

    private func layoutCard() {
        let size = Self.preferredSize(for: user)
        let bounds = view.bounds
        let fallback = CGRect(x: bounds.midX, y: bounds.midY, width: 0, height: 0)
        let sourceRect: CGRect
        if let sourceView {
            sourceRect = sourceView.convert(sourceView.bounds, to: view)
        } else {
            sourceRect = fallback
        }
        let minX = Self.screenMargin
        let maxX = max(minX, bounds.width - size.width - Self.screenMargin)
        let targetX = min(max(sourceRect.midX - size.width / 2, minX), maxX)
        let belowY = sourceRect.maxY + Self.sideOffset
        let aboveY = sourceRect.minY - size.height - Self.sideOffset
        let targetY = belowY + size.height <= bounds.height - Self.screenMargin
            ? belowY
            : max(Self.screenMargin, aboveY)

        cardShadowView.frame = CGRect(origin: CGPoint(x: targetX, y: targetY), size: size)
        cardContentView.frame = cardShadowView.bounds
        cardShadowView.layer.shadowPath = UIBezierPath(roundedRect: cardShadowView.bounds, cornerRadius: 6).cgPath
    }

    func animateIn() {
        cardShadowView.alpha = 0
        cardShadowView.transform = CGAffineTransform(translationX: 0, y: -8).scaledBy(x: 0.95, y: 0.95)
        UIView.animate(withDuration: 0.15, delay: 0, options: [.curveEaseOut]) {
            self.cardShadowView.alpha = 1
            self.cardShadowView.transform = .identity
        }
    }

    @objc private func dismissPopover() {
        UIView.animate(withDuration: 0.12, delay: 0, options: [.curveEaseIn]) {
            self.cardShadowView.alpha = 0
            self.cardShadowView.transform = CGAffineTransform(translationX: 0, y: -4).scaledBy(x: 0.98, y: 0.98)
        } completion: { _ in
            self.dismiss(animated: false)
        }
    }

    private var profileBaseColor: UIColor {
        UIColor(cssColor: user.profileColor) ?? .black
    }

    private var mixedCoreColor: UIColor {
        blend(UIColor(red: 20/255, green: 20/255, blue: 20/255, alpha: 1), profileBaseColor, amount: 0.77)
    }

    private var detailText: NSAttributedString {
        var parts: [String] = []
        if user.isFollower { parts.append("Follows you") }
        let joined = AniListUtil.since(Date(timeIntervalSince1970: user.createdAt))
        parts.append("Joined \(joined)")
        return Self.detailsString(parts, font: .nunito(ofSize: 11, weight: .regular))
    }

    private var statsText: NSAttributedString {
        let watched = AniListUtil.since(Date(timeIntervalSinceNow: -Double(user.minutesWatched) * 60))
            .replacingOccurrences(of: "ago", with: "watched")
        return Self.detailsString(["\(user.animeCount) anime",
                                   "\(user.episodesWatched) episodes",
                                   watched],
                                  font: .nunito(ofSize: 11, weight: .regular))
    }

    private static func detailsString(_ parts: [String], font: UIFont) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for (index, part) in parts.enumerated() {
            if index > 0 {
                result.append(NSAttributedString(string: " • ", attributes: [
                    .font: UIFont.nunito(ofSize: 6.4, weight: .regular),
                    .foregroundColor: Self.separatorTextColor,
                    .baselineOffset: 1
                ]))
            }
            result.append(NSAttributedString(string: part, attributes: [
                .font: font,
                .foregroundColor: Self.detailTextColor
            ]))
        }
        return result
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

    private static func sanitizedDescription(_ html: String?) -> String? {
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
    convenience init?(cssColor: String?) {
        guard let raw = cssColor?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        let named: [String: String] = [
            "black": "#000000",
            "blue": "#0000ff",
            "gray": "#808080",
            "green": "#008000",
            "grey": "#808080",
            "orange": "#ffa500",
            "pink": "#ffc0cb",
            "purple": "#800080",
            "red": "#ff0000",
            "white": "#ffffff",
            "yellow": "#ffff00"
        ]
        var cleanHex = named[raw.lowercased()] ?? raw
        if cleanHex.hasPrefix("#") { cleanHex = String(cleanHex.dropFirst()) }
        guard cleanHex.count == 6, let rgb = UInt64(cleanHex, radix: 16) else { return nil }
        self.init(red: CGFloat((rgb >> 16) & 0xFF) / 255,
                  green: CGFloat((rgb >> 8) & 0xFF) / 255,
                  blue: CGFloat(rgb & 0xFF) / 255,
                  alpha: 1)
    }
}
