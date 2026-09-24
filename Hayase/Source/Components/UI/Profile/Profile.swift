//
//  Profile.swift
//  Hayase
//
//  Created by scigward.
//  Mirrors: lib/components/ui/profile/Profile.svelte
//
//  Added in this pass: an optional `detailFetcher` on
//  `FollowerAvatarStackView.configure`/`ProfileButton`, for callers whose
//  `AniListUserSummary` is only partially populated (chat's userlist/message
//  avatars, which only ever have id/name/avatar) to fetch the full profile
//  on tap before presenting, mirroring `ChatProfile.svelte`'s
//  `client.user(Number(user.id))`. Fetch-then-present rather than
//  present-then-refresh, since this view is built once in `viewDidLoad` from
//  whatever `user` it's handed — reworking it to patch itself in place as
//  data streams in would be a much larger, riskier change to a view that
//  already works correctly for its four existing callers (EpisodesList,
//  Layout's followers row, ThreadCommentView, ThreadPostView), none of which
//  pass this parameter and so see no behavior change at all.
//

import UIKit

final class FollowerAvatarStackView: UIStackView {
    private var buttons: [ProfileButton] = []
    private var cutoutBorder: CGFloat?

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

    /// `detailFetcher`, when provided, is called with a tapped user's id on
    /// tap; its result (or `nil` on failure) replaces the summary passed
    /// here for that presentation only. For callers whose `users` are
    /// already fully populated (the existing four call sites), leave this
    /// nil — the card presents the given summary as-is, unchanged from
    /// before this parameter existed.
    func configure(users: [AniListUserSummary],
                   avatarSize: CGFloat = 32,
                   ringWidth: CGFloat = 4,
                   ringColor: UIColor = UIColor.HayaseTheme.background,
                   overlap: CGFloat = 4, cutoutBorder: CGFloat? = nil,
                   detailFetcher: ((Int, @escaping (AniListUserSummary?) -> Void) -> Void)? = nil) {
        reset()
        spacing = -overlap
        self.cutoutBorder = cutoutBorder
        let visibleUsers = users.filter { !$0.name.isEmpty }
        isHidden = visibleUsers.isEmpty
        visibleUsers.forEach { user in
            let button = ProfileButton(user: user,
                                       avatarSize: avatarSize,
                                       ringWidth: ringWidth,
                                       ringColor: ringColor,
                                       imageInset: cutoutBorder == nil ? 0 : 1,
                                       detailFetcher: detailFetcher)
            button.translatesAutoresizingMaskIntoConstraints = false
            if cutoutBorder != nil {
                button.layer.cornerRadius = avatarSize / 2
                button.layer.borderWidth = 1
                button.layer.borderColor = UIColor.HayaseTheme.primary.cgColor
            }
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

    override func layoutSubviews() {
        super.layoutSubviews()
        for (index, button) in buttons.enumerated() {
            guard let border = cutoutBorder, index < buttons.count - 1 else {
                button.layer.mask = nil
                continue
            }
            // Avatars.svelte cuts a transparent gap around the NEXT avatar;
            // it does not paint an opaque ring around each current avatar.
            let radius = button.bounds.height / 2 + border
            let center = CGPoint(x: button.bounds.width * 1.5 + spacing, y: button.bounds.midY)
            let mask = (button.layer.mask as? AvatarCutoutLayer) ?? AvatarCutoutLayer()
            mask.contentsScale = window?.screen.scale ?? UIScreen.main.scale
            mask.frame = button.bounds
            mask.cutoutCenter = center
            mask.cutoutRadius = radius
            mask.setNeedsDisplay()
            button.layer.mask = mask
        }
    }
}

/// CSS radial mask: transparent through radius - 1, opaque at radius.
private final class AvatarCutoutLayer: CALayer {
    var cutoutCenter = CGPoint.zero
    var cutoutRadius: CGFloat = 0

    override func draw(in context: CGContext) {
        guard cutoutRadius > 0,
              let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                  colors: [UIColor.clear.cgColor, UIColor.black.cgColor] as CFArray,
                  locations: [0, 1]) else { return }
        context.drawRadialGradient(gradient,
            startCenter: cutoutCenter, startRadius: max(0, cutoutRadius - 1),
            endCenter: cutoutCenter, endRadius: cutoutRadius,
            options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    }
}

private final class ProfileButton: UIControl {
    private let user: AniListUserSummary
    private let avatarView: ProfileAvatarView
    private let detailFetcher: ((Int, @escaping (AniListUserSummary?) -> Void) -> Void)?

    init(user: AniListUserSummary,
         avatarSize: CGFloat,
         ringWidth: CGFloat,
         ringColor: UIColor,
         imageInset: CGFloat = 0,
         detailFetcher: ((Int, @escaping (AniListUserSummary?) -> Void) -> Void)? = nil) {
        self.user = user
        self.detailFetcher = detailFetcher
        self.avatarView = ProfileAvatarView(user: user,
                                            avatarSize: avatarSize,
                                            ringWidth: ringWidth,
                                            ringColor: ringColor)
        super.init(frame: .zero)
        setup(imageInset: imageInset)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup(imageInset: CGFloat) {
        accessibilityLabel = user.name
        addTarget(self, action: #selector(showProfile), for: .touchUpInside)

        avatarView.isUserInteractionEnabled = false
        avatarView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(avatarView)
        NSLayoutConstraint.activate([
            avatarView.topAnchor.constraint(equalTo: topAnchor, constant: imageInset),
            avatarView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: imageInset),
            avatarView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -imageInset),
            avatarView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -imageInset),
        ])
    }

    func prepareForReuse() {
        avatarView.prepareForReuse()
    }

    @objc private func showProfile() {
        guard let presenter = nearestViewController else { return }
        guard let detailFetcher else {
            present(user, from: presenter)
            return
        }
        // Fetch first, present once — a card that resized itself around
        // arriving data a moment after appearing would read as broken in a
        // modal presentation, unlike a reactively-laid-out web popover.
        isUserInteractionEnabled = false
        detailFetcher(user.id) { [weak self] detailed in
            guard let self else { return }
            self.isUserInteractionEnabled = true
            self.present(detailed ?? self.user, from: presenter)
        }
    }

    private func present(_ user: AniListUserSummary, from presenter: UIViewController) {
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

        skeletonView.backgroundColor = HayaseSkeleton.color
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
        HayaseSkeleton.startPulse(on: skeletonView)
    }

    private func stopSkeleton(showFallback: Bool) {
        HayaseSkeleton.stopPulse(on: skeletonView)
        skeletonView.isHidden = true
        fallbackLabel.isHidden = !showFallback && imageView.image != nil
    }

    func prepareForReuse() {
        imageTask?.cancel()
        imageTask = nil
        HayaseSkeleton.stopPulse(on: skeletonView)
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
    private var aboutHeight: CGFloat

    init(user: AniListUserSummary, sourceView: UIView) {
        self.user = user
        self.sourceView = sourceView
        self.avatarView = ProfileAvatarView(user: user,
                                            avatarSize: 80,
                                            ringWidth: 0,
                                            ringColor: .clear)
        self.aboutHeight = ProfileShadowView.estimatedHeight(for: user.about, width: Self.contentWidth - 32)
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
        cardShadowView.layer.shadowOpacity = 0.2
        cardShadowView.layer.shadowRadius = 3
        cardShadowView.layer.shadowOffset = CGSize(width: 0, height: 1)
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

        headerView.backgroundColor = bannerURLString == nil ? UIColor.HayaseTheme.primary.withAlphaComponent(0.1) : .clear
        headerView.translatesAutoresizingMaskIntoConstraints = false
        coreView.addSubview(headerView)

        bannerImageView.contentMode = .scaleAspectFill
        bannerImageView.alpha = 0
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
        detailLabel.font = .nunito(ofSize: 11, weight: .regular)
        detailLabel.textColor = Self.detailTextColor
        detailLabel.attributedText = detailText
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
            cardShadowView.addSubview(bubbleView)
        }

        let aboutView = ProfileShadowView(html: user.about)
        aboutView.translatesAutoresizingMaskIntoConstraints = false
        aboutView.onNavigatePath = { [weak self] path in
            self?.navigate(to: path)
        }
        coreView.addSubview(aboutView)

        let statsLabel = UILabel()
        statsLabel.font = .nunito(ofSize: 11, weight: .regular)
        statsLabel.textColor = Self.detailTextColor
        statsLabel.attributedText = statsText
        statsLabel.numberOfLines = 1
        statsLabel.lineBreakMode = .byTruncatingTail
        statsLabel.translatesAutoresizingMaskIntoConstraints = false
        coreView.addSubview(statsLabel)

        let statsHeight = ceil(statsLabel.font.lineHeight)
        let aboutHeightConstraint = aboutView.heightAnchor.constraint(equalToConstant: aboutHeight)
        aboutView.onHeightChange = { [weak self] height in
            guard let self else { return }
            self.aboutHeight = height
            aboutHeightConstraint.constant = height
            self.layoutCard()
            self.view.layoutIfNeeded()
        }

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

            aboutView.topAnchor.constraint(equalTo: headerView.bottomAnchor, constant: 8),
            aboutView.leadingAnchor.constraint(equalTo: coreView.leadingAnchor, constant: 16),
            aboutView.trailingAnchor.constraint(equalTo: coreView.trailingAnchor, constant: -16),
            aboutHeightConstraint,

            statsLabel.topAnchor.constraint(equalTo: aboutView.bottomAnchor, constant: 8),
            statsLabel.leadingAnchor.constraint(equalTo: coreView.leadingAnchor, constant: 16),
            statsLabel.trailingAnchor.constraint(equalTo: coreView.trailingAnchor, constant: -16),
            statsLabel.heightAnchor.constraint(equalToConstant: statsHeight),
            statsLabel.bottomAnchor.constraint(equalTo: coreView.bottomAnchor, constant: -8),
        ])

        if let bubbleView {
            NSLayoutConstraint.activate([
                bubbleView.leadingAnchor.constraint(equalTo: cardShadowView.leadingAnchor, constant: Self.outerPadding - 20),
                bubbleView.topAnchor.constraint(equalTo: cardShadowView.topAnchor, constant: Self.outerPadding - 44),
            ])
        }
    }

    private func makeBubbleView() -> UIView? {
        guard let bubble = user.donatorBadge, !bubble.isEmpty, bubble != "Donator" else { return nil }
        let label = UILabel()
        label.text = bubble
        label.font = .nunito(ofSize: 14, weight: .regular)
        label.textColor = .black
        label.numberOfLines = 1
        label.setContentHuggingPriority(.required, for: .horizontal)

        let bubbleView = UIView()
        bubbleView.backgroundColor = mixedBubbleColor
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

    private static let detailTextColor = UIColor.HayaseTheme.foreground.withAlphaComponent(0.8)
    private static let separatorTextColor = UIColor(red: 115/255, green: 115/255, blue: 115/255, alpha: 1)

    private static func preferredSize(aboutHeight: CGFloat) -> CGSize {
        let statsHeight = ceil(UIFont.nunito(ofSize: 11, weight: .regular).lineHeight)
        let height = outerPadding * 2 + 105 + 8 + aboutHeight + 8 + statsHeight + 8
        return CGSize(width: contentWidth + outerPadding * 2, height: ceil(height))
    }

    private func layoutCard() {
        let size = Self.preferredSize(aboutHeight: aboutHeight)
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
        mixOklab(UIColor(red: 20/255, green: 20/255, blue: 20/255, alpha: 1), weight: 0.3,
                 with: profileBaseColor, weight: 1)
    }

    private var mixedBubbleColor: UIColor {
        mixOklab(.white, weight: 1, with: profileBaseColor, weight: 0.5)
    }

    private var bannerURLString: String? {
        guard let value = user.bannerURL?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
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
                result.append(NSAttributedString(string: " ", attributes: [.font: font]))
                result.append(NSAttributedString(string: "•", attributes: [
                    .font: UIFont.nunito(ofSize: 6.4, weight: .regular),
                    .foregroundColor: Self.separatorTextColor,
                    .baselineOffset: 1
                ]))
                result.append(NSAttributedString(string: " ", attributes: [.font: font]))
            }
            result.append(NSAttributedString(string: part, attributes: [
                .font: font,
                .foregroundColor: Self.detailTextColor
            ]))
        }
        return result
    }

    private func loadBanner() {
        guard let urlString = bannerURLString,
              let url = URL(string: urlString) else { return }
        if let cached = SharedImageCache.shared.object(forKey: urlString as NSString) {
            bannerImageView.image = cached
            bannerImageView.alpha = Self.bannerImageAlpha
            return
        }
        bannerTask = URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data,
                  let image = UIImage(data: data) else { return }
            SharedImageCache.shared.setObject(image, forKey: urlString as NSString)
            DispatchQueue.main.async {
                guard let self else { return }
                self.bannerImageView.image = image
                UIView.animate(withDuration: 0.3, delay: 0, options: [.curveEaseOut]) {
                    self.bannerImageView.alpha = Self.bannerImageAlpha
                }
            }
        }
        bannerTask?.resume()
    }

    private static let bannerImageAlpha: CGFloat = 0.25

    private func navigate(to path: String) {
        let hostTabIndex = presentingViewController?.hayaseTabIndex
        dismiss(animated: false) {
            Router.shared.navigate(path: path, hostTabIndex: hostTabIndex)
        }
    }

    private func mixOklab(_ first: UIColor, weight firstWeight: CGFloat, with second: UIColor, weight secondWeight: CGFloat) -> UIColor {
        let total = firstWeight + secondWeight
        guard total > 0 else { return first }
        let firstLab = Oklab(color: first)
        let secondLab = Oklab(color: second)
        let firstAmount = firstWeight / total
        let secondAmount = secondWeight / total
        return Oklab(L: firstLab.L * firstAmount + secondLab.L * secondAmount,
                     a: firstLab.a * firstAmount + secondLab.a * secondAmount,
                     b: firstLab.b * firstAmount + secondLab.b * secondAmount,
                     alpha: firstLab.alpha * firstAmount + secondLab.alpha * secondAmount).color
    }

    private struct Oklab {
        let L: CGFloat
        let a: CGFloat
        let b: CGFloat
        let alpha: CGFloat

        init(L: CGFloat, a: CGFloat, b: CGFloat, alpha: CGFloat) {
            self.L = L
            self.a = a
            self.b = b
            self.alpha = alpha
        }

        init(color: UIColor) {
            var red: CGFloat = 0
            var green: CGFloat = 0
            var blue: CGFloat = 0
            var alpha: CGFloat = 0
            color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)

            let r = Self.linear(red)
            let g = Self.linear(green)
            let b = Self.linear(blue)
            let lmsL = 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b
            let lmsM = 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b
            let lmsS = 0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b
            let l = CGFloat(pow(Double(lmsL), 1.0 / 3.0))
            let m = CGFloat(pow(Double(lmsM), 1.0 / 3.0))
            let s = CGFloat(pow(Double(lmsS), 1.0 / 3.0))

            self.L = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s
            self.a = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
            self.b = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
            self.alpha = alpha
        }

        var color: UIColor {
            let l = L + 0.3963377774 * a + 0.2158037573 * b
            let m = L - 0.1055613458 * a - 0.0638541728 * b
            let s = L - 0.0894841775 * a - 1.2914855480 * b
            let l3 = l * l * l
            let m3 = m * m * m
            let s3 = s * s * s
            let red = 4.0767416621 * l3 - 3.3077115913 * m3 + 0.2309699292 * s3
            let green = -1.2684380046 * l3 + 2.6097574011 * m3 - 0.3413193965 * s3
            let blue = -0.0041960863 * l3 - 0.7034186147 * m3 + 1.7076147010 * s3
            return UIColor(red: Self.gamma(red), green: Self.gamma(green), blue: Self.gamma(blue), alpha: alpha)
        }

        private static func linear(_ value: CGFloat) -> CGFloat {
            value <= 0.04045 ? value / 12.92 : CGFloat(pow(Double((value + 0.055) / 1.055), 2.4))
        }

        private static func gamma(_ value: CGFloat) -> CGFloat {
            let clamped = min(max(value, 0), 1)
            return clamped <= 0.0031308 ? 12.92 * clamped : 1.055 * CGFloat(pow(Double(clamped), 1 / 2.4)) - 0.055
        }
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
