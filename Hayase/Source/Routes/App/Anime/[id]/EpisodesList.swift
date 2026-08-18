//
//  EpisodesList.swift
//  Hayase
//
//  Created by scigward.
//  Mirrors: routes/app/anime/[id]/EpisodesList.svelte
//

import UIKit

// MARK: - AniZip episode model

struct AniZipEpisode {
    let number: Int
    let title: String
    let overview: String
    let imageURL: String?
    let airDate: Date?
    let runtime: Int
    let rating: String?
    let isFiller: Bool
}

// MARK: - FilteredEpisode

struct FilteredEpisode {
    let key: String
    let entry: AniZipEpisodeEntry
    let airdatems: Double?
    let anidbEid: Int?
}

// MARK: - Episode card style

private enum EpisodeCardStyle {
    static let cardRadius: CGFloat = 6
    static let cardHeight: CGFloat = 112
    static let thumbnailMaxWidth: CGFloat = 208
    static let defaultThumbnailAspectRatio: CGFloat = 9.0 / 16.0
    static let thumbnailBadgeBackground = UIColor(white: 23/255, alpha: 0.8)
    static let selectedBackground = UIColor(white: 23/255, alpha: 1)
    static let trackBackground = UIColor(white: 38/255, alpha: 1)
    static let fillerBackground = UIColor(red: 250/255, green: 204/255, blue: 21/255, alpha: 1)
    static let followerRing = UIColor(white: 10/255, alpha: 1)
    static let cardBackground = UIColor(white: 10/255, alpha: 1)

    // EpisodesList.svelte expands the scroll viewport with -ml-14/pl-14
    // and -mr-3/pr-3. Keep the card's visual start unchanged while
    // giving selected scale/ring/shadow enough in-bounds space to draw.
    static let overflowLeadingSlack: CGFloat = 56
    static let overflowTrailingSlack: CGFloat = 12
    static let cardHorizontalPadding: CGFloat = 12
    static let rowVerticalPadding: CGFloat = 14
}

// MARK: - EpisodeRatingBadgeView

private final class EpisodeRatingBadgeView: UIView {
    private let iconView: UIImageView = {
        // interface EpisodesList.svelte: Star class='text-yellow-400' = Tailwind #facc15 = rgb(250,204,21)
        let image = UIImage.hayaseFilledIcon("star", pointSize: 10)?
            .withTintColor(UIColor(red: 250/255, green: 204/255, blue: 21/255, alpha: 1), renderingMode: .alwaysOriginal)
        let view = UIImageView(image: image)
        view.contentMode = .scaleAspectFit
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let label: UILabel = {
        let label = UILabel()
        label.font = .nunito(ofSize: 9.6)
        label.textColor = UIColor.HayaseTheme.secondaryForeground
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        backgroundColor = EpisodeCardStyle.thumbnailBadgeBackground
        layer.cornerRadius = 4
        clipsToBounds = true

        // interface: Star mr-1 = 4pt gap between star and rating text
        let stack = UIStackView(arrangedSubviews: [iconView, label])
        stack.axis = .horizontal
        stack.spacing = 4
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 10),
            iconView.heightAnchor.constraint(equalToConstant: 10),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
        ])
    }

    func configure(ratingText: String) {
        label.text = ratingText
        isHidden = false
    }
}

// MARK: - EpisodeCardView

final class EpisodeCardView: UIView, UIGestureRecognizerDelegate {

    var onTap: ((Int) -> Void)?
    var onContentHeightChanged: (() -> Void)?
    private var episodeNumber: Int = 0

    private let thumbImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.backgroundColor = UIColor(white: 0.10, alpha: 1)
        iv.layer.cornerRadius = EpisodeCardStyle.cardRadius
        iv.layer.maskedCorners = [.layerMinXMinYCorner, .layerMinXMaxYCorner]
        return iv
    }()

    private let runtimeBadge: PaddedLabel = {
        let l = PaddedLabel()
        l.font = .nunito(ofSize: 9.6)
        l.textColor = UIColor(white: 0.98, alpha: 1)
        l.backgroundColor = EpisodeCardStyle.thumbnailBadgeBackground
        l.contentInsets = UIEdgeInsets(top: 2, left: 4, bottom: 2, right: 4)
        l.layer.cornerRadius = 4
        l.clipsToBounds = true
        l.isHidden = true
        return l
    }()

    private let ratingBadge = EpisodeRatingBadgeView()

    private let fillerBadge: PaddedLabel = {
        let l = PaddedLabel()
        l.text = "Filler"
        l.font = .nunito(ofSize: 9.6, weight: .bold)
        l.textColor = UIColor.HayaseTheme.primaryForeground
        l.backgroundColor = EpisodeCardStyle.fillerBackground
        l.contentInsets = UIEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
        l.layer.cornerRadius = 4
        l.layer.maskedCorners = [.layerMinXMinYCorner]
        l.clipsToBounds = true
        l.isHidden = true
        return l
    }()

    private let numberLabel: UILabel = {
        let l = UILabel()
        l.font = .nunito(ofSize: 12.8, weight: .bold)
        l.textColor = UIColor.HayaseTheme.secondaryForeground
        l.numberOfLines = 1
        return l
    }()

    private let progressBar: UIView = {
        let outer = UIView()
        outer.backgroundColor = EpisodeCardStyle.trackBackground
        return outer
    }()
    private let progressFill: UIView = {
        let v = UIView()
        v.backgroundColor = .white
        return v
    }()
    private var progressFillWidthConstraint: NSLayoutConstraint?
    private var savedProgressFraction: Double = 0

    private let overviewLabel: UILabel = {
        let l = UILabel()
        l.font = .nunito(ofSize: 9.6)
        // interface EpisodesList.svelte: text-muted-foreground, dark theme hsl(240 5% 64.9%) = #a1a1aa.
        l.textColor = UIColor(red: 161/255, green: 161/255, blue: 170/255, alpha: 1)
        l.numberOfLines = 0
        l.lineBreakMode = .byClipping
        l.clipsToBounds = true
        // Interface uses an overflow-hidden text block, not a fixed line clamp.
        // Let Auto Layout clip it to the space left above the mt-auto metadata row.
        l.setContentHuggingPriority(.defaultHigh, for: .vertical)
        l.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        return l
    }()

    private let metaLabel: UILabel = {
        let l = UILabel()
        l.font = .nunito(ofSize: 9.6)
        l.textColor = UIColor.HayaseTheme.secondaryForeground
        return l
    }()

    private let followerStack = FollowerAvatarStackView()
    private let ringLayer = CAShapeLayer()

    private let playOverlayView: UIView = {
        let v = UIView()
        v.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        v.alpha = 0
        v.isUserInteractionEnabled = false
        v.layer.cornerRadius = EpisodeCardStyle.cardRadius
        v.layer.maskedCorners = [.layerMinXMinYCorner, .layerMinXMaxYCorner]
        v.clipsToBounds = true
        return v
    }()

    private let playOverlayIcon: UIImageView = {
        let iv = UIImageView(image: UIImage.hayaseFilledIcon("play", pointSize: 24))
        iv.tintColor = .white
        iv.contentMode = .scaleAspectFit
        iv.alpha = 0
        iv.transform = CGAffineTransform(scaleX: 0.75, y: 0.75)
        return iv
    }()

    private let spoilerBlurView: UIVisualEffectView = {
        let view = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
        view.alpha = 0.72
        view.isHidden = true
        view.isUserInteractionEnabled = false
        view.layer.cornerRadius = EpisodeCardStyle.cardRadius
        view.layer.maskedCorners = [.layerMinXMinYCorner, .layerMinXMaxYCorner]
        view.clipsToBounds = true
        return view
    }()

    private var currentImageURL: String?
    private var imageTask: URLSessionDataTask?

    private var textLeadingToThumb: NSLayoutConstraint!
    private var textLeadingToCard: NSLayoutConstraint!
    private var thumbWidthPreferred: NSLayoutConstraint!
    private var thumbMaxWidth: NSLayoutConstraint!
    private var thumbAspectConstraint: NSLayoutConstraint?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        backgroundColor = EpisodeCardStyle.cardBackground
        layer.cornerRadius = EpisodeCardStyle.cardRadius
        clipsToBounds = false
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowRadius = 0
        layer.shadowOpacity = 0
        layer.shadowOffset = CGSize(width: 0, height: 0)

        ringLayer.fillColor = UIColor.clear.cgColor
        ringLayer.lineWidth = 1
        ringLayer.zPosition = 10
        ringLayer.isHidden = true
        layer.addSublayer(ringLayer)

        [thumbImageView, spoilerBlurView, playOverlayView, runtimeBadge, ratingBadge].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }
        playOverlayIcon.translatesAutoresizingMaskIntoConstraints = false
        playOverlayView.addSubview(playOverlayIcon)
        fillerBadge.translatesAutoresizingMaskIntoConstraints = false
        addSubview(fillerBadge)

        progressBar.translatesAutoresizingMaskIntoConstraints = false
        progressFill.translatesAutoresizingMaskIntoConstraints = false
        progressBar.addSubview(progressFill)
        progressFillWidthConstraint = progressFill.widthAnchor.constraint(equalToConstant: 0)
        progressFillWidthConstraint?.isActive = true
        NSLayoutConstraint.activate([
            progressFill.topAnchor.constraint(equalTo: progressBar.topAnchor),
            progressFill.bottomAnchor.constraint(equalTo: progressBar.bottomAnchor),
            progressFill.leadingAnchor.constraint(equalTo: progressBar.leadingAnchor),
        ])

        let spacer = UIView()
        spacer.setContentHuggingPriority(.defaultLow - 1, for: .vertical)
        spacer.setContentCompressionResistancePriority(.defaultLow - 1, for: .vertical)

        let metaContainer = UIView()
        metaLabel.translatesAutoresizingMaskIntoConstraints = false
        metaContainer.addSubview(metaLabel)
        NSLayoutConstraint.activate([
            metaLabel.topAnchor.constraint(equalTo: metaContainer.topAnchor, constant: 8),
            metaLabel.leadingAnchor.constraint(equalTo: metaContainer.leadingAnchor),
            metaLabel.trailingAnchor.constraint(equalTo: metaContainer.trailingAnchor),
            metaLabel.bottomAnchor.constraint(equalTo: metaContainer.bottomAnchor),
        ])

        let followersContainer = UIView()
        followerStack.translatesAutoresizingMaskIntoConstraints = false
        followersContainer.addSubview(followerStack)
        NSLayoutConstraint.activate([
            followerStack.topAnchor.constraint(equalTo: followersContainer.topAnchor, constant: 4),
            followerStack.leadingAnchor.constraint(greaterThanOrEqualTo: followersContainer.leadingAnchor),
            followerStack.trailingAnchor.constraint(equalTo: followersContainer.trailingAnchor, constant: -2),
            followerStack.bottomAnchor.constraint(equalTo: followersContainer.bottomAnchor),
        ])

        let bottomRow = UIStackView(arrangedSubviews: [metaContainer, UIView(), followersContainer])
        bottomRow.axis = .horizontal
        bottomRow.spacing = 8
        bottomRow.alignment = .top
        bottomRow.setContentCompressionResistancePriority(.required, for: .vertical)

        let textStack = UIStackView(arrangedSubviews: [numberLabel, progressBar, overviewLabel, spacer, bottomRow])
        textStack.axis = .vertical
        textStack.spacing = 0
        textStack.setCustomSpacing(8, after: numberLabel)
        textStack.setCustomSpacing(8, after: progressBar)
        textStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(textStack)

        thumbWidthPreferred = thumbImageView.widthAnchor.constraint(equalTo: widthAnchor, multiplier: 0.5)
        thumbWidthPreferred.priority = UILayoutPriority(999)
        thumbMaxWidth = thumbImageView.widthAnchor.constraint(lessThanOrEqualToConstant: EpisodeCardStyle.thumbnailMaxWidth)

        textLeadingToThumb = textStack.leadingAnchor.constraint(equalTo: thumbImageView.trailingAnchor, constant: 16)
        textLeadingToCard = textStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16)
        textLeadingToThumb.isActive = true
        textLeadingToCard.isActive = false

        NSLayoutConstraint.activate([
            heightAnchor.constraint(lessThanOrEqualToConstant: EpisodeCardStyle.cardHeight),

            thumbImageView.topAnchor.constraint(equalTo: topAnchor),
            thumbImageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            thumbImageView.bottomAnchor.constraint(equalTo: bottomAnchor),
            thumbWidthPreferred,
            thumbMaxWidth,

            spoilerBlurView.topAnchor.constraint(equalTo: thumbImageView.topAnchor),
            spoilerBlurView.leadingAnchor.constraint(equalTo: thumbImageView.leadingAnchor),
            spoilerBlurView.trailingAnchor.constraint(equalTo: thumbImageView.trailingAnchor),
            spoilerBlurView.bottomAnchor.constraint(equalTo: thumbImageView.bottomAnchor),

            playOverlayView.topAnchor.constraint(equalTo: thumbImageView.topAnchor),
            playOverlayView.leadingAnchor.constraint(equalTo: thumbImageView.leadingAnchor),
            playOverlayView.trailingAnchor.constraint(equalTo: thumbImageView.trailingAnchor),
            playOverlayView.bottomAnchor.constraint(equalTo: thumbImageView.bottomAnchor),
            playOverlayIcon.centerXAnchor.constraint(equalTo: playOverlayView.centerXAnchor),
            playOverlayIcon.centerYAnchor.constraint(equalTo: playOverlayView.centerYAnchor),
            playOverlayIcon.widthAnchor.constraint(equalToConstant: 24),
            playOverlayIcon.heightAnchor.constraint(equalToConstant: 24),

            runtimeBadge.leadingAnchor.constraint(equalTo: thumbImageView.leadingAnchor, constant: 4),
            runtimeBadge.bottomAnchor.constraint(equalTo: thumbImageView.bottomAnchor, constant: -4),

            ratingBadge.trailingAnchor.constraint(equalTo: thumbImageView.trailingAnchor, constant: -4),
            ratingBadge.bottomAnchor.constraint(equalTo: thumbImageView.bottomAnchor, constant: -4),

            textLeadingToThumb,
            textStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            textStack.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            textStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),

            progressBar.heightAnchor.constraint(equalToConstant: 2),

            fillerBadge.trailingAnchor.constraint(equalTo: trailingAnchor),
            fillerBadge.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        let tap = UITapGestureRecognizer(target: self, action: #selector(cardTapped))
        tap.cancelsTouchesInView = false
        tap.delegate = self
        addGestureRecognizer(tap)
        let press = UILongPressGestureRecognizer(target: self, action: #selector(pressChanged(_:)))
        press.minimumPressDuration = 0
        press.cancelsTouchesInView = false
        press.delegate = self
        addGestureRecognizer(press)
    }

    @objc private func cardTapped() {
        onTap?(episodeNumber)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }

    @objc private func pressChanged(_ recognizer: UILongPressGestureRecognizer) {
        switch recognizer.state {
        case .began:
            setPressed(true, animated: true)
        case .ended, .cancelled, .failed:
            setPressed(false, animated: true)
        default:
            break
        }
    }

    private func setPressed(_ pressed: Bool, animated: Bool) {
        let changes = {
            self.transform = pressed ? CGAffineTransform(scaleX: 1.05, y: 1.05) : .identity
            self.backgroundColor = pressed ? EpisodeCardStyle.selectedBackground : EpisodeCardStyle.cardBackground
            self.playOverlayView.alpha = pressed ? 1 : 0
            self.playOverlayIcon.alpha = pressed ? 1 : 0
            self.playOverlayIcon.transform = pressed ? .identity : CGAffineTransform(scaleX: 0.75, y: 0.75)
            self.layer.shadowRadius = pressed ? 18 : 0
            self.layer.shadowOpacity = pressed ? 0.45 : 0
            self.layer.shadowOffset = pressed ? CGSize(width: 0, height: 8) : .zero
            self.layer.zPosition = pressed ? 2 : (self.ringLayer.isHidden ? 0 : 1)
        }
        if animated {
            UIView.animate(withDuration: 0.2, delay: 0, options: [.allowUserInteraction, .beginFromCurrentState], animations: changes)
        } else {
            changes()
        }
    }

    private func setThumbnailAspectRatio(_ ratio: CGFloat, active: Bool) {
        thumbAspectConstraint?.isActive = false
        thumbAspectConstraint = nil

        guard active, ratio.isFinite, ratio > 0 else { return }

        let constraint = thumbImageView.heightAnchor.constraint(equalTo: thumbImageView.widthAnchor, multiplier: ratio)
        // CSS gives the image its natural ratio, then max-h-28 may cap it.
        // Keep the cap authoritative when an episode image is taller than 112pt.
        constraint.priority = UILayoutPriority(750)
        constraint.isActive = true
        thumbAspectConstraint = constraint
    }

    private func applyThumbnailImage(_ image: UIImage, from urlString: String, animated: Bool) {
        guard currentImageURL == urlString else { return }

        let oldRatio = thumbAspectConstraint?.multiplier
        let ratio = image.size.height / max(image.size.width, 1)
        setThumbnailAspectRatio(ratio, active: true)

        let setImage = { self.thumbImageView.image = image }
        if animated {
            UIView.transition(with: thumbImageView, duration: 0.2,
                              options: [.transitionCrossDissolve, .beginFromCurrentState],
                              animations: setImage)
        } else {
            setImage()
        }

        if oldRatio.map({ abs($0 - ratio) > 0.01 }) ?? true {
            onContentHeightChanged?()
        }
    }

    func configure(with episode: AniZipEpisode, anilistID: Int = 0, anilistProgress: Int = 0,
                   accentColor: UIColor = .white, isListCompleted: Bool = false,
                   isRepeating: Bool = false, hideSpoilers: Bool = false,
                   followers: [AniListUserSummary] = [],
                   onHeightChange: (() -> Void)? = nil) {
        onContentHeightChanged = onHeightChange
        episodeNumber = episode.number
        numberLabel.text = "\(episode.number). \(episode.title)"
        overviewLabel.text = episode.overview
        overviewLabel.isHidden = false
        followerStack.configure(users: followers,
                                avatarSize: 16,
                                ringWidth: 2,
                                ringColor: EpisodeCardStyle.followerRing)

        let effectiveProgress = isListCompleted ? 0 : anilistProgress
        let isWatchedOnAniList = effectiveProgress > 0 && episode.number <= effectiveProgress && !isListCompleted
        let isTarget = episode.number == effectiveProgress + 1
        let isSpoiler = hideSpoilers && !isWatchedOnAniList && !isTarget
        thumbImageView.alpha = isWatchedOnAniList ? 0.2 : 1.0
        spoilerBlurView.isHidden = !isSpoiler
        overviewLabel.alpha = isSpoiler ? 0.35 : 1
        alpha = 1.0

        progressFill.backgroundColor = accentColor

        let showFullBar = isWatchedOnAniList || isListCompleted
        if showFullBar {
            progressBar.backgroundColor = accentColor
            progressBar.isHidden = false
            savedProgressFraction = 1.0
            setNeedsLayout()
        } else if anilistID > 0,
                  let saved = WatchProgressService.shared.getProgress(anilistID: anilistID, episode: episode.number) {
            progressBar.backgroundColor = EpisodeCardStyle.trackBackground
            progressBar.isHidden = false
            let progressPercent = ceil(saved.fraction * 100) / 100
            savedProgressFraction = min(max(progressPercent, 0), 1)
            setNeedsLayout()
        } else {
            progressBar.isHidden = true
            savedProgressFraction = 0
        }

        if let date = episode.airDate {
            metaLabel.text = AniListUtil.since(date)
            metaLabel.isHidden = false
        } else {
            metaLabel.isHidden = true
        }

        if episode.runtime > 0 {
            runtimeBadge.text = "\(episode.runtime)m"
            runtimeBadge.isHidden = false
        } else {
            runtimeBadge.isHidden = true
        }

        if let rating = episode.rating {
            ratingBadge.configure(ratingText: isSpoiler ? "5.00" : rating)
            ratingBadge.isHidden = false
        } else {
            ratingBadge.isHidden = true
        }

        if episode.isFiller {
            ringLayer.strokeColor = EpisodeCardStyle.fillerBackground.cgColor
            ringLayer.isHidden = false
            fillerBadge.isHidden = false
        } else if isTarget {
            ringLayer.strokeColor = accentColor.cgColor
            ringLayer.isHidden = false
            fillerBadge.isHidden = true
        } else {
            ringLayer.isHidden = true
            fillerBadge.isHidden = true
        }
        layer.zPosition = ringLayer.isHidden ? 0 : 1

        currentImageURL = episode.imageURL
        thumbImageView.image = nil
        imageTask?.cancel()
        imageTask = nil

        let hasImage = episode.imageURL != nil && !episode.imageURL!.isEmpty
        thumbImageView.isHidden = !hasImage
        playOverlayView.isHidden = !hasImage
        spoilerBlurView.isHidden = !hasImage || !isSpoiler
        runtimeBadge.isHidden = !hasImage || episode.runtime <= 0
        ratingBadge.isHidden = !hasImage || episode.rating == nil
        thumbWidthPreferred.isActive = hasImage
        thumbMaxWidth.isActive = hasImage
        textLeadingToThumb.isActive = hasImage
        textLeadingToCard.isActive = !hasImage
        setThumbnailAspectRatio(EpisodeCardStyle.defaultThumbnailAspectRatio, active: hasImage)

        if let urlStr = episode.imageURL, let url = URL(string: urlStr) {
            if let cached = SharedImageCache.shared.object(forKey: urlStr as NSString) {
                applyThumbnailImage(cached, from: urlStr, animated: false)
                return
            }

            let captured = urlStr
            imageTask = URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
                guard let data = data, let img = UIImage(data: data) else { return }
                SharedImageCache.shared.setObject(img, forKey: captured as NSString)
                DispatchQueue.main.async {
                    self?.applyThumbnailImage(img, from: captured, animated: true)
                }
            }
            imageTask?.resume()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let ringRect = bounds.insetBy(dx: -0.5, dy: -0.5)
        ringLayer.path = UIBezierPath(roundedRect: ringRect, cornerRadius: EpisodeCardStyle.cardRadius + 0.5).cgPath

        guard !progressBar.isHidden, progressBar.bounds.width > 0 else { return }
        progressFillWidthConstraint?.constant = progressBar.bounds.width * CGFloat(savedProgressFraction)
    }

    func reset() {
        imageTask?.cancel()
        imageTask = nil
        currentImageURL = nil
        thumbImageView.image = nil
        thumbImageView.isHidden = false
        thumbWidthPreferred.isActive = true
        thumbMaxWidth.isActive = true
        setThumbnailAspectRatio(EpisodeCardStyle.defaultThumbnailAspectRatio, active: true)
        textLeadingToThumb.isActive = true
        textLeadingToCard.isActive = false
        numberLabel.text = nil
        overviewLabel.text = nil
        metaLabel.text = nil
        runtimeBadge.isHidden = true
        ratingBadge.isHidden = true
        fillerBadge.isHidden = true
        playOverlayView.isHidden = false
        playOverlayView.alpha = 0
        playOverlayIcon.alpha = 0
        playOverlayIcon.transform = CGAffineTransform(scaleX: 0.75, y: 0.75)
        spoilerBlurView.isHidden = true
        overviewLabel.alpha = 1
        followerStack.reset()
        setPressed(false, animated: false)
        ringLayer.isHidden = true
        ringLayer.strokeColor = nil
        layer.zPosition = 0
        alpha = 1.0
        thumbImageView.alpha = 1.0
        progressBar.isHidden = true
        progressBar.backgroundColor = EpisodeCardStyle.trackBackground
        savedProgressFraction = 0
        progressFillWidthConstraint?.constant = 0
        episodeNumber = 0
        onTap = nil
        onContentHeightChanged = nil
    }
}

// MARK: - Episode overflow support

private protocol EpisodeOverflowRendering: AnyObject {}

extension EpisodeOverflowRendering where Self: UITableViewCell {
    func allowEpisodeOverflowRendering() {
        [self, contentView].forEach { view in
            view.clipsToBounds = false
            view.layer.masksToBounds = false
        }

        // UITableView uses private wrapper views around visible cells. Those
        // wrappers can be recreated during reuse, so clear clipping on every
        // layout pass instead of relying on only the cell/contentView flags.
        var current = superview
        while let view = current {
            view.clipsToBounds = false
            view.layer.masksToBounds = false
            current = view.superview
        }
    }
}

// MARK: - EpisodeCell

final class EpisodeCell: UITableViewCell, EpisodeOverflowRendering {
    static let reuseID = "AniDetailEpCell"

    let cardView = EpisodeCardView()
    private let overflowViewport = UIView()
    private var cardLeadingConstraint: NSLayoutConstraint?
    private var cardTrailingConstraint: NSLayoutConstraint?
    private var pageSideInset: CGFloat = 0
    private var cardIsTarget = false

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        backgroundColor = .clear
        clipsToBounds = false
        contentView.clipsToBounds = false
        selectionStyle = .none

        overflowViewport.clipsToBounds = false
        overflowViewport.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(overflowViewport)

        cardView.translatesAutoresizingMaskIntoConstraints = false
        overflowViewport.addSubview(cardView)

        cardLeadingConstraint = cardView.leadingAnchor.constraint(
            equalTo: overflowViewport.leadingAnchor,
            constant: EpisodeCardStyle.overflowLeadingSlack + EpisodeCardStyle.cardHorizontalPadding)
        cardTrailingConstraint = cardView.trailingAnchor.constraint(
            equalTo: overflowViewport.trailingAnchor,
            constant: -(EpisodeCardStyle.overflowTrailingSlack + EpisodeCardStyle.cardHorizontalPadding))

        NSLayoutConstraint.activate([
            overflowViewport.topAnchor.constraint(equalTo: contentView.topAnchor),
            overflowViewport.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            overflowViewport.leadingAnchor.constraint(
                equalTo: contentView.leadingAnchor,
                constant: -EpisodeCardStyle.overflowLeadingSlack),
            overflowViewport.trailingAnchor.constraint(
                equalTo: contentView.trailingAnchor,
                constant: EpisodeCardStyle.overflowTrailingSlack),

            cardView.topAnchor.constraint(
                equalTo: overflowViewport.topAnchor,
                constant: EpisodeCardStyle.rowVerticalPadding),
            cardView.bottomAnchor.constraint(
                equalTo: overflowViewport.bottomAnchor,
                constant: -EpisodeCardStyle.rowVerticalPadding),
            cardLeadingConstraint!,
            cardTrailingConstraint!,
        ])
    }

    func configure(with episode: AniZipEpisode, anilistID: Int = 0, anilistProgress: Int = 0,
                   accentColor: UIColor = .white, isListCompleted: Bool = false,
                   isRepeating: Bool = false, hideSpoilers: Bool = false,
                   followers: [AniListUserSummary] = [],
                   onHeightChange: (() -> Void)? = nil) {
        cardView.configure(with: episode, anilistID: anilistID, anilistProgress: anilistProgress,
                           accentColor: accentColor, isListCompleted: isListCompleted,
                           isRepeating: isRepeating, hideSpoilers: hideSpoilers,
                           followers: followers, onHeightChange: onHeightChange)
        cardIsTarget = episode.number == (isListCompleted ? 0 : anilistProgress) + 1
        updateCardInsets()
    }

    private func updateCardInsets() {
        let inset = cardIsTarget ? CGFloat(0) : EpisodeCardStyle.cardHorizontalPadding
        cardLeadingConstraint?.constant = EpisodeCardStyle.overflowLeadingSlack + pageSideInset + inset
        cardTrailingConstraint?.constant = -(EpisodeCardStyle.overflowTrailingSlack + pageSideInset + inset)
    }

    func applyPageSideInset(_ inset: CGFloat) {
        pageSideInset = inset
        updateCardInsets()
    }

    func applyPaddingForSizeClass(isRegular: Bool) {
        // Kept for old call sites; current layout uses applyPageSideInset(_:).
        _ = isRegular
    }

    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        allowEpisodeOverflowRendering()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        allowEpisodeOverflowRendering()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        cardView.reset()
        cardIsTarget = false
        updateCardInsets()
    }
}

// MARK: - EpisodePairCell

final class EpisodePairCell: UITableViewCell, EpisodeOverflowRendering {
    static let reuseID = "EpisodePairCell"

    let leftCard = EpisodeCardView()
    let rightCard = EpisodeCardView()
    var onTapEpisode: ((Int) -> Void)?

    private let overflowViewport = UIView()
    private let stack = UIStackView()
    private let leftContainer = UIView()
    private let rightContainer = UIView()
    private var stackLeadingConstraint: NSLayoutConstraint?
    private var stackTrailingConstraint: NSLayoutConstraint?
    private var leftCardLeadingConstraint: NSLayoutConstraint?
    private var leftCardTrailingConstraint: NSLayoutConstraint?
    private var rightCardLeadingConstraint: NSLayoutConstraint?
    private var rightCardTrailingConstraint: NSLayoutConstraint?
    private var pageSideInset: CGFloat = 0

    private var leftCardVerticalConstraints: [NSLayoutConstraint] = []
    private var rightCardVerticalConstraints: [NSLayoutConstraint] = []

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        backgroundColor = .clear
        clipsToBounds = false
        contentView.clipsToBounds = false
        overflowViewport.clipsToBounds = false
        leftContainer.clipsToBounds = false
        rightContainer.clipsToBounds = false
        selectionStyle = .none

        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false

        leftCard.translatesAutoresizingMaskIntoConstraints = false
        rightCard.translatesAutoresizingMaskIntoConstraints = false

        overflowViewport.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(overflowViewport)
        leftContainer.addSubview(leftCard)
        rightContainer.addSubview(rightCard)
        stack.addArrangedSubview(leftContainer)
        stack.addArrangedSubview(rightContainer)
        overflowViewport.addSubview(stack)

        stackLeadingConstraint = stack.leadingAnchor.constraint(
            equalTo: overflowViewport.leadingAnchor,
            constant: EpisodeCardStyle.overflowLeadingSlack)
        stackTrailingConstraint = stack.trailingAnchor.constraint(
            equalTo: overflowViewport.trailingAnchor,
            constant: -EpisodeCardStyle.overflowTrailingSlack)
        leftCardLeadingConstraint = leftCard.leadingAnchor.constraint(equalTo: leftContainer.leadingAnchor, constant: 12)
        leftCardTrailingConstraint = leftCard.trailingAnchor.constraint(equalTo: leftContainer.trailingAnchor, constant: -12)
        rightCardLeadingConstraint = rightCard.leadingAnchor.constraint(equalTo: rightContainer.leadingAnchor, constant: 12)
        rightCardTrailingConstraint = rightCard.trailingAnchor.constraint(equalTo: rightContainer.trailingAnchor, constant: -12)

        leftCardVerticalConstraints = makeCenteredCardVerticalConstraints(card: leftCard, in: leftContainer)
        rightCardVerticalConstraints = makeCenteredCardVerticalConstraints(card: rightCard, in: rightContainer)

        NSLayoutConstraint.activate([
            overflowViewport.topAnchor.constraint(equalTo: contentView.topAnchor),
            overflowViewport.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            overflowViewport.leadingAnchor.constraint(
                equalTo: contentView.leadingAnchor,
                constant: -EpisodeCardStyle.overflowLeadingSlack),
            overflowViewport.trailingAnchor.constraint(
                equalTo: contentView.trailingAnchor,
                constant: EpisodeCardStyle.overflowTrailingSlack),

            stack.topAnchor.constraint(
                equalTo: overflowViewport.topAnchor,
                constant: EpisodeCardStyle.rowVerticalPadding),
            stack.bottomAnchor.constraint(
                equalTo: overflowViewport.bottomAnchor,
                constant: -EpisodeCardStyle.rowVerticalPadding),
            stackLeadingConstraint!,
            stackTrailingConstraint!,

            leftCardLeadingConstraint!,
            leftCardTrailingConstraint!,
            rightCardLeadingConstraint!,
            rightCardTrailingConstraint!,
        ] + leftCardVerticalConstraints + rightCardVerticalConstraints)
    }

    private func makeCenteredCardVerticalConstraints(card: EpisodeCardView, in container: UIView) -> [NSLayoutConstraint] {
        [
            card.topAnchor.constraint(greaterThanOrEqualTo: container.topAnchor),
            card.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor),
            card.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ]
    }

    private func setRightCardPresent(_ isPresent: Bool) {
        rightCard.isHidden = !isPresent

        // Keep the empty second grid column for odd episode counts, but do not
        // let the hidden reusable card contribute a fake row height.
        rightCardVerticalConstraints.forEach { $0.isActive = isPresent }
    }

    func configure(left: AniZipEpisode, right: AniZipEpisode?, anilistID: Int, anilistProgress: Int,
                   accentColor: UIColor, isListCompleted: Bool,
                   isRepeating: Bool = false, hideSpoilers: Bool = false,
                   followersByEpisode: [Int: [AniListUserSummary]] = [:],
                   onHeightChange: (() -> Void)? = nil) {
        leftCard.configure(with: left, anilistID: anilistID, anilistProgress: anilistProgress,
                           accentColor: accentColor, isListCompleted: isListCompleted,
                           isRepeating: isRepeating, hideSpoilers: hideSpoilers,
                           followers: followersByEpisode[left.number] ?? [],
                           onHeightChange: onHeightChange)
        applyTargetPadding(toLeftCard: true, isTarget: left.number == (isListCompleted ? 0 : anilistProgress) + 1)
        leftCard.onTap = { [weak self] num in self?.onTapEpisode?(num) }

        if let right = right {
            setRightCardPresent(true)
            rightCard.configure(with: right, anilistID: anilistID, anilistProgress: anilistProgress,
                                accentColor: accentColor, isListCompleted: isListCompleted,
                                isRepeating: isRepeating, hideSpoilers: hideSpoilers,
                                followers: followersByEpisode[right.number] ?? [],
                                onHeightChange: onHeightChange)
            applyTargetPadding(toLeftCard: false, isTarget: right.number == (isListCompleted ? 0 : anilistProgress) + 1)
            rightCard.onTap = { [weak self] num in self?.onTapEpisode?(num) }
            rightContainer.isHidden = false
        } else {
            rightCard.reset()
            setRightCardPresent(false)
            applyTargetPadding(toLeftCard: false, isTarget: false)
            rightContainer.isHidden = false
        }
    }

    private func applyTargetPadding(toLeftCard: Bool, isTarget: Bool) {
        let inset = isTarget ? CGFloat(0) : EpisodeCardStyle.cardHorizontalPadding
        if toLeftCard {
            leftCardLeadingConstraint?.constant = inset
            leftCardTrailingConstraint?.constant = -inset
        } else {
            rightCardLeadingConstraint?.constant = inset
            rightCardTrailingConstraint?.constant = -inset
        }
    }

    func applyPageSideInset(_ inset: CGFloat) {
        pageSideInset = inset
        stackLeadingConstraint?.constant = EpisodeCardStyle.overflowLeadingSlack + pageSideInset
        stackTrailingConstraint?.constant = -(EpisodeCardStyle.overflowTrailingSlack + pageSideInset)
    }

    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        allowEpisodeOverflowRendering()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        allowEpisodeOverflowRendering()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        leftCard.reset()
        rightCard.reset()
        setRightCardPresent(true)
        rightContainer.isHidden = false
        applyTargetPadding(toLeftCard: true, isTarget: false)
        applyTargetPadding(toLeftCard: false, isTarget: false)
        onTapEpisode = nil
    }
}

// MARK: - PaginationBarView

final class PaginationBarView: UIView {

    var onPageChange: ((Int) -> Void)?

    private(set) var currentPage: Int = 1
    private(set) var totalPages: Int = 1
    private var totalCount: Int = 0
    private var perPage: Int = 16

    private let infoLabel: UILabel = {
        let l = UILabel()
        l.font = .nunito(ofSize: 13)
        l.textColor = UIColor(white: 0.63, alpha: 1)
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let prevButton: UIButton = {
        let b = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)
        b.setImage(UIImage.hayaseIcon("chevron-left", withConfiguration: config), for: .normal)
        b.tintColor = .white
        b.translatesAutoresizingMaskIntoConstraints = false
        b.widthAnchor.constraint(equalToConstant: 36).isActive = true
        b.heightAnchor.constraint(equalToConstant: 36).isActive = true
        b.layer.cornerRadius = 6
        return b
    }()

    private let nextButton: UIButton = {
        let b = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)
        b.setImage(UIImage.hayaseIcon("chevron-right", withConfiguration: config), for: .normal)
        b.tintColor = .white
        b.translatesAutoresizingMaskIntoConstraints = false
        b.widthAnchor.constraint(equalToConstant: 36).isActive = true
        b.heightAnchor.constraint(equalToConstant: 36).isActive = true
        b.layer.cornerRadius = 6
        return b
    }()

    private let pageStack: UIStackView = {
        let sv = UIStackView()
        sv.axis = .horizontal
        sv.spacing = 8
        sv.alignment = .center
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()

    private let controlsStack: UIStackView = {
        let sv = UIStackView()
        sv.axis = .horizontal
        sv.spacing = 8
        sv.alignment = .center
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()

    private let compactInfoLabel: UILabel = {
        let label = UILabel()
        label.font = .nunito(ofSize: 13)
        label.textColor = UIColor(white: 0.63, alpha: 1)
        label.textAlignment = .center
        label.numberOfLines = 1
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isHidden = true
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }()

    private var infoLeadingConstraint: NSLayoutConstraint?
    private var controlsLeadingConstraint: NSLayoutConstraint?
    private var controlsTrailingConstraint: NSLayoutConstraint?
    private var renderedInfoText: NSAttributedString?
    private var lastAppliedCompactMode: Bool?

    /// Explicit width used to pick the compact/expanded pagination layout.
    ///
    /// `effectivePaginationWidth` normally prefers the window width because the
    /// anime page always spans the whole window. The player's episode sheet is a
    /// narrow (≤550pt) container inside a potentially very wide window, so it sets
    /// this to its own width to keep the compact layout.
    var responsiveWidthOverride: CGFloat? {
        didSet {
            guard responsiveWidthOverride != oldValue else { return }
            applyResponsiveModeIfNeeded(force: true)
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear

        prevButton.addTarget(self, action: #selector(prevTapped), for: .touchUpInside)
        nextButton.addTarget(self, action: #selector(nextTapped), for: .touchUpInside)

        controlsStack.addArrangedSubview(prevButton)
        controlsStack.addArrangedSubview(pageStack)
        controlsStack.addArrangedSubview(compactInfoLabel)
        controlsStack.addArrangedSubview(nextButton)

        addSubview(infoLabel)
        addSubview(controlsStack)

        infoLeadingConstraint = infoLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16)
        controlsLeadingConstraint = controlsStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16)
        controlsTrailingConstraint = controlsStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16)

        NSLayoutConstraint.activate([
            infoLeadingConstraint!,
            infoLabel.centerYAnchor.constraint(equalTo: controlsStack.centerYAnchor),

            controlsTrailingConstraint!,
            controlsStack.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            controlsStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),

            heightAnchor.constraint(greaterThanOrEqualToConstant: 60),
        ])
    }

    func applyPaddingForSizeClass(isRegular: Bool) {
        let width = superview?.bounds.width ?? bounds.width
        let sidePad = isRegular
            ? AnimeDetailViewController.interfacePageSideInset(for: width)
            : CGFloat(16)
        infoLeadingConstraint?.constant = sidePad
        controlsLeadingConstraint?.constant = sidePad
        controlsTrailingConstraint?.constant = -sidePad
        applyResponsiveModeIfNeeded()
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(currentPage: Int, totalCount: Int, perPage: Int) {
        self.currentPage = currentPage
        self.totalCount = totalCount
        self.perPage = perPage
        self.totalPages = max(1, Int(ceil(Double(totalCount) / Double(perPage))))
        rebuild()
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        applyResponsiveModeIfNeeded()
    }

    // MARK: - Pagination algorithm

    private struct PageItem {
        let page: Int
        let isEllipsis: Bool
    }

    private func computePages() -> [PageItem] {
        let siblingCount = 1
        let edgeSize = 4 * siblingCount
        let tp = totalPages

        let startPage = max(1, tp - currentPage < edgeSize ? tp - edgeSize : currentPage - siblingCount)
        let endPage = min(tp, currentPage < edgeSize ? 1 + edgeSize : currentPage + siblingCount)

        var items: [PageItem] = []

        if startPage > 1 {
            items.append(PageItem(page: 1, isEllipsis: false))
            if startPage > 2 {
                items.append(PageItem(page: startPage - 1, isEllipsis: true))
            }
        }

        for i in startPage...endPage {
            items.append(PageItem(page: i, isEllipsis: false))
        }

        if endPage < tp {
            if endPage < tp - 1 {
                items.append(PageItem(page: endPage + 1, isEllipsis: true))
            }
            items.append(PageItem(page: tp, isEllipsis: false))
        }

        return items
    }

    private func rebuild() {
        let rangeStart = (currentPage - 1) * perPage
        let rangeEnd = min(currentPage * perPage, totalCount)
        let boldAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.nunito(ofSize: 13, weight: .bold),
            .foregroundColor: UIColor(white: 0.63, alpha: 1)
        ]
        let normalAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.nunito(ofSize: 13),
            .foregroundColor: UIColor(white: 0.63, alpha: 1)
        ]
        let str = NSMutableAttributedString()
        str.append(NSAttributedString(string: "Showing ", attributes: normalAttrs))
        str.append(NSAttributedString(string: "\(rangeStart + 1)", attributes: boldAttrs))
        str.append(NSAttributedString(string: " to ", attributes: normalAttrs))
        str.append(NSAttributedString(string: "\(rangeEnd)", attributes: boldAttrs))
        str.append(NSAttributedString(string: " of ", attributes: normalAttrs))
        str.append(NSAttributedString(string: "\(totalCount)", attributes: boldAttrs))
        str.append(NSAttributedString(string: " episodes", attributes: normalAttrs))
        renderedInfoText = str
        infoLabel.attributedText = str

        prevButton.isEnabled = currentPage > 1
        prevButton.alpha = currentPage > 1 ? 1.0 : 0.5
        nextButton.isEnabled = currentPage < totalPages
        nextButton.alpha = currentPage < totalPages ? 1.0 : 0.5

        pageStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        let pages = computePages()
        for item in pages {
            if item.isEllipsis {
                let label = UILabel()
                label.text = "..."
                label.font = .nunito(ofSize: 14)
                label.textColor = UIColor.HayaseTheme.secondaryForeground
                label.textAlignment = .center
                label.widthAnchor.constraint(equalToConstant: 36).isActive = true
                label.heightAnchor.constraint(equalToConstant: 36).isActive = true
                pageStack.addArrangedSubview(label)
            } else {
                let btn = UIButton(type: .system)
                btn.setTitle("\(item.page)", for: .normal)
                btn.titleLabel?.font = .nunito(ofSize: 14, weight: .medium)
                btn.tag = item.page
                btn.widthAnchor.constraint(equalToConstant: 36).isActive = true
                btn.heightAnchor.constraint(equalToConstant: 36).isActive = true
                btn.layer.cornerRadius = 6
                btn.clipsToBounds = true
                btn.addTarget(self, action: #selector(pageTapped(_:)), for: .touchUpInside)

                if item.page == currentPage {
                    btn.layer.borderWidth = 1
                    btn.layer.borderColor = UIColor(red: 39/255, green: 39/255, blue: 42/255, alpha: 1).cgColor
                    btn.setTitleColor(.white, for: .normal)
                    btn.backgroundColor = .clear
                } else {
                    btn.layer.borderWidth = 0
                    btn.setTitleColor(UIColor.HayaseTheme.secondaryForeground, for: .normal)
                    btn.backgroundColor = .clear
                }

                pageStack.addArrangedSubview(btn)
            }
        }

        pageStack.isHidden = false
        compactInfoLabel.attributedText = str
        applyResponsiveModeIfNeeded(force: true)
    }

    private func applyResponsiveModeIfNeeded(force: Bool = false) {
        let isCompact = effectivePaginationWidth < 768
        guard force || lastAppliedCompactMode != isCompact else { return }
        lastAppliedCompactMode = isCompact

        infoLabel.isHidden = isCompact
        pageStack.isHidden = isCompact
        compactInfoLabel.attributedText = renderedInfoText
        compactInfoLabel.isHidden = !isCompact

        controlsLeadingConstraint?.isActive = isCompact
        controlsTrailingConstraint?.isActive = true
    }

    private var effectivePaginationWidth: CGFloat {
        if let responsiveWidthOverride, responsiveWidthOverride > 1 { return responsiveWidthOverride }
        if let window, window.bounds.width > 1 { return window.bounds.width }
        if bounds.width > 1 { return bounds.width }
        if let superview, superview.bounds.width > 1 { return superview.bounds.width }
        return UIScreen.main.bounds.width
    }

    @objc private func prevTapped() {
        guard currentPage > 1 else { return }
        onPageChange?(currentPage - 1)
    }

    @objc private func nextTapped() {
        guard currentPage < totalPages else { return }
        onPageChange?(currentPage + 1)
    }

    @objc private func pageTapped(_ sender: UIButton) {
        let page = sender.tag
        guard page >= 1, page <= totalPages, page != currentPage else { return }
        onPageChange?(page)
    }
}

// MARK: - Episode fetching

extension AnimeDetailViewController {

    func makeEpisodeCell(for indexPath: IndexPath) -> UITableViewCell {
        let cols = usesSingleEpisodeGridTrack ? 1 : episodeColumnCount
        let pageSideInset = AnimeDetailViewController.interfacePageSideInset(for: tableView.frame.width)
        let currentAnilistID = animeItem?.id ?? (animeEntity?.animeAnilistId?.intValue ?? 0)
        let isCompleted = currentListStatus == "COMPLETED"
        let isRepeating = currentListStatus == "REPEATING"
        let hideSpoilers = Settings.hideSpoilers
        if cols >= 2 {
            guard let cell = tableView.dequeueReusableCell(
                withIdentifier: EpisodePairCell.reuseID, for: indexPath) as? EpisodePairCell else {
                return UITableViewCell()
            }
            let leftIdx = indexPath.row * 2
            let rightIdx = leftIdx + 1
            guard let leftEp = paginatedEpisodes[safe: leftIdx] else { return cell }
            let rightEp = paginatedEpisodes[safe: rightIdx]
            cell.configure(left: leftEp, right: rightEp, anilistID: currentAnilistID,
                           anilistProgress: anilistProgress, accentColor: currentAnimeAccent,
                           isListCompleted: isCompleted,
                           isRepeating: isRepeating, hideSpoilers: hideSpoilers,
                           followersByEpisode: followingEntriesByEpisode,
                           onHeightChange: { [weak self] in self?.scheduleEpisodeHeightInvalidation() })
            cell.onTapEpisode = { [weak self] epNumber in
                self?.openExtensionSearch(episode: epNumber)
            }
            cell.applyPageSideInset(pageSideInset)
            return cell
        } else {
            guard let cell = tableView.dequeueReusableCell(
                withIdentifier: EpisodeCell.reuseID, for: indexPath) as? EpisodeCell else {
                return UITableViewCell()
            }
            guard let ep = paginatedEpisodes[safe: indexPath.row] else { return cell }
            cell.configure(with: ep, anilistID: currentAnilistID, anilistProgress: anilistProgress,
                           accentColor: currentAnimeAccent, isListCompleted: isCompleted,
                           isRepeating: isRepeating, hideSpoilers: hideSpoilers,
                           followers: followingEntriesByEpisode[ep.number] ?? [],
                           onHeightChange: { [weak self] in self?.scheduleEpisodeHeightInvalidation() })
            cell.cardView.onTap = { [weak self] epNumber in
                self?.openExtensionSearch(episode: epNumber)
            }
            cell.applyPageSideInset(pageSideInset)
            return cell
        }
    }

    /// Compute episode count matching web's `episodes(media)` utility (src/lib/modules/anilist/util.ts).
    /// Falls back to airing schedule data + user progress when `media.episodes` is nil (airing anime).
    private func computeEpisodeCount(schedResult: MediaScheduleResult?, anilistEpisodes: Int?) -> Int? {
        // If AniList provides a confirmed episode count, use it (matches web: if (media.episodes) return media.episodes)
        if let eps = anilistEpisodes { return eps }

        // Fallback: max(last aired episode, last upcoming episode, user progress)
        // Matches web: Math.max(upcoming, past, progress)
        let schedule = schedResult?.schedule ?? [:]
        let lastAired = schedule.keys.max() ?? 0
        let progress = animeItem?.mediaListEntry?.progress ?? 0
        let best = max(lastAired, progress)
        return best > 0 ? best : nil
    }

    func fetchEpisodes() {
        let anilistId: Int?
        if let entity = animeEntity {
            anilistId = entity.animeAnilistId?.intValue
        } else {
            anilistId = animeItem?.id
        }
        guard let id = anilistId else { return }

        let anilistEpisodes: Int?
        if let entity = animeEntity {
            anilistEpisodes = entity.animeTotalEps?.intValue
        } else {
            anilistEpisodes = animeItem?.episodes
        }

        let format = animeItem?.format

        AniZipService.shared.episodes(anilistID: id) { [weak self] anizipResponse in
            guard let self = self else { return }

            // If anizip has no data for this anime (e.g. brand new airing anime), create an
            // empty response so episodes can still be built from the AniList airing schedule.
            // Matches web: makeEpisodeList(media, eps) handles eps=null gracefully.
            let response = anizipResponse ?? AniZipEpisodesResponse(
                titles: nil, episodes: nil, episodeCount: nil,
                specialCount: nil, images: nil, mappings: nil)

            let hasAnidbId = response.mappings?.anidb_id != nil

            if !hasAnidbId, let fmt = format, ["SPECIAL", "OVA", "ONA"].contains(fmt) {
                self.resolveParentID(format: fmt) { [weak self] parentID in
                    guard let self = self else { return }
                    if let parentID = parentID {
                        AniListClient.shared.fetchMediaAiringScheduleResult(anilistID: id) { [weak self] result in
                            guard let self = self else { return }
                            let schedResult: MediaScheduleResult?
                            switch result {
                            case .success(let schedule):
                                schedResult = schedule
                            case .failure(let error):
                                NSLog("[AnimeDetail] Media schedule failed: %@", error.description)
                                schedResult = nil
                            }

                            var alSchedule: [Int: Date] = schedResult?.schedule ?? [:]
                            let resolvedCount = self.computeEpisodeCount(schedResult: schedResult, anilistEpisodes: anilistEpisodes)

                            if alSchedule[1] == nil {
                                let item = self.animeItem
                                let allTitles = [item?.titleEnglish, item?.titleRomaji].compactMap { $0 }
                                let singleEp = self.isSingleEpisode(
                                    format: fmt, titles: allTitles,
                                    synonyms: item?.synonyms ?? [],
                                    duration: item?.duration, episodes: anilistEpisodes)
                                if singleEp, let sd = schedResult?.startDate,
                                   let y = sd.year {
                                    let m = sd.month ?? 1
                                    let d = sd.day ?? 1
                                    var comps = DateComponents()
                                    comps.year = y; comps.month = m; comps.day = d
                                    if let date = Calendar(identifier: .gregorian).date(from: comps) {
                                        alSchedule[1] = date
                                    }
                                }
                            }

                            AniZipService.shared.episodes(anilistID: parentID) { [weak self] parentResponse in
                                guard let self = self else { return }
                                let finalResponse = parentResponse ?? response
                                self.processEpisodeResponse(finalResponse, anilistEpisodes: resolvedCount,
                                                            anilistId: id, alSchedule: alSchedule)
                            }
                        }
                    } else {
                        // No parent found - still try airing schedule for episode count
                        if anilistEpisodes == nil {
                            AniListClient.shared.fetchMediaAiringScheduleResult(anilistID: id) { [weak self] result in
                                guard let self = self else { return }
                                let schedResult: MediaScheduleResult?
                                switch result {
                                case .success(let schedule):
                                    schedResult = schedule
                                case .failure(let error):
                                    NSLog("[AnimeDetail] Media schedule failed: %@", error.description)
                                    schedResult = nil
                                }
                                let resolvedCount = self.computeEpisodeCount(schedResult: schedResult, anilistEpisodes: anilistEpisodes)
                                let alSchedule: [Int: Date] = schedResult?.schedule ?? [:]
                                self.processEpisodeResponse(response, anilistEpisodes: resolvedCount,
                                                            anilistId: id, alSchedule: alSchedule)
                            }
                        } else {
                            self.processEpisodeResponse(response, anilistEpisodes: anilistEpisodes, anilistId: id)
                        }
                    }
                }
                return
            }

            // For ALL anime: if anilistEpisodes is nil (airing/new anime), fetch airing schedule
            // to compute episode count from aired/notaired data, matching web's episodes() fallback.
            if anilistEpisodes == nil {
                AniListClient.shared.fetchMediaAiringScheduleResult(anilistID: id) { [weak self] result in
                    guard let self = self else { return }
                    let schedResult: MediaScheduleResult?
                    switch result {
                    case .success(let schedule):
                        schedResult = schedule
                    case .failure(let error):
                        NSLog("[AnimeDetail] Media schedule failed: %@", error.description)
                        schedResult = nil
                    }
                    let resolvedCount = self.computeEpisodeCount(schedResult: schedResult, anilistEpisodes: anilistEpisodes)
                    let alSchedule: [Int: Date] = schedResult?.schedule ?? [:]
                    self.processEpisodeResponse(response, anilistEpisodes: resolvedCount,
                                                anilistId: id, alSchedule: alSchedule)
                }
            } else {
                self.processEpisodeResponse(response, anilistEpisodes: anilistEpisodes, anilistId: id)
            }
        }
    }

    private func resolveParentID(format: String, completion: @escaping (Int?) -> Void) {
        if let item = animeItem, !item.relations.isEmpty {
            let parentID = ["PARENT", "PREQUEL", "SEQUEL"].lazy.compactMap { relType -> Int? in
                item.relations.first { $0.relationType == relType }?.media.id
            }.first
            completion(parentID)
            return
        }

        guard let id = animeItem?.id ?? animeEntity?.animeAnilistId?.intValue else {
            completion(nil)
            return
        }
        AniListClient.shared.fetchDetailForItemResult(id: id) { [weak self] result in
            switch result {
            case .success(let rels):
                self?.animeItem?.relations = rels
                self?.relations = rels
                let parentID = ["PARENT", "PREQUEL", "SEQUEL"].lazy.compactMap { relType -> Int? in
                    rels.first { $0.relationType == relType }?.media.id
                }.first
                completion(parentID)
            case .failure(let error):
                NSLog("[AnimeDetail] Parent relation fallback failed: %@", error.description)
                completion(nil)
            }
        }
    }

    private func isMovie(format: String?, titles: [String], synonyms: [String], duration: Int?, episodes: Int?) -> Bool {
        if format == "MOVIE" { return true }
        let allNames = titles + synonyms
        if allNames.contains(where: { $0.lowercased().contains("movie") }) { return true }
        return (duration ?? 0) > 80 && episodes == 1
    }

    private func isSingleEpisode(format: String?, titles: [String], synonyms: [String], duration: Int?, episodes: Int?) -> Bool {
        let movie = isMovie(format: format, titles: titles, synonyms: synonyms, duration: duration, episodes: episodes)
        return episodes == 1 || (movie && episodes == nil)
    }

    // `static` so the extracted `buildEpisodeList(from:...)` can call it without a
    // view controller instance (the player's episode sheet has none).
    private static func episodeByAirDate(
        alDate: Date?,
        filtered: [String: FilteredEpisode],
        episode: Int
    ) -> FilteredEpisode? {
        guard let alDate = alDate else {
            return filtered["\(episode)"]
        }
        let alMs = alDate.timeIntervalSince1970 * 1000

        var closest: [FilteredEpisode] = []
        var closestDist = Double.infinity
        for entry in filtered.values {
            let dist = abs((entry.airdatems ?? 0) - alMs)
            if dist < closestDist {
                closestDist = dist
                closest = [entry]
            } else if dist == closestDist {
                closest.append(entry)
            }
        }

        guard !closest.isEmpty else { return filtered["\(episode)"] }

        return closest.min(by: {
            let lhs = Int($0.entry.episode) ?? Int($0.key) ?? 0
            let rhs = Int($1.entry.episode) ?? Int($1.key) ?? 0
            return abs(lhs - episode) < abs(rhs - episode)
        })
    }

    private static func sanitizedEpisodeNotes(_ text: String) -> String {
        var result = text
        result = result.replacingOccurrences(
            of: #"\n?\(?Source: [^)]+\)?\n?"#,
            with: "",
            options: .regularExpression)
        result = result.replacingOccurrences(
            of: #"\n?Notes?:[ |\n][^\n]+\n?"#,
            with: "",
            options: .regularExpression)
        return result
    }

    /// Maps an AniZip `/episodes` payload into the `AniZipEpisode` list rendered by
    /// `EpisodeCardView`, without touching any view state.
    ///
    /// Extracted from `processEpisodeResponse` so the player's episode sheet can reuse
    /// the exact same mapping: the interface does the same thing by rendering
    /// `EpisodesList.svelte` inside `ui/player/episodesmodal.svelte`.
    ///
    /// - Parameter fallbackRuntime: media duration used when AniZip has no per-episode
    ///   runtime (detail page passes `animeItem?.duration`).
    static func buildEpisodeList(from response: AniZipEpisodesResponse,
                                 anilistEpisodes: Int?,
                                 alSchedule: [Int: Date]? = nil,
                                 fallbackRuntime: Int? = nil) -> [AniZipEpisode] {
        let episodesDict = response.episodes ?? [:]
        let episodesResCount = response.episodeCount
        let specialCount = response.specialCount ?? 0

        let count = anilistEpisodes ?? episodesResCount ?? 0

        var filtered: [String: FilteredEpisode] = [:]
        for (key, ep) in episodesDict {
            let airdate = ep.airdate
            var airdatems: Double? = nil
            if let airdate = airdate {
                if let d = ISO8601DateFormatter().date(from: airdate) {
                    airdatems = d.timeIntervalSince1970 * 1000
                } else {
                    let fmt = DateFormatter()
                    fmt.dateFormat = "yyyy-MM-dd"
                    fmt.locale = Locale(identifier: "en_US_POSIX")
                    if let d = fmt.date(from: airdate) {
                        airdatems = d.timeIntervalSince1970 * 1000
                    }
                }
            }
            filtered[key] = FilteredEpisode(key: key, entry: ep, airdatems: airdatems, anidbEid: ep.anidbEid)
        }

        let hasSpecial = specialCount > 0
        let hasCountMatch = (anilistEpisodes ?? 0) == (episodesResCount ?? 0)

        let now = Date().timeIntervalSince1970 * 1000

        var parsed: [AniZipEpisode] = []
        guard count > 0 else { return parsed }

        for episode in 1...count {
            let hasEpisode = episodesDict["\(episode)"] != nil

            let needsValidation = !(!hasSpecial || (hasEpisode && hasCountMatch))

            let resolvedEntry: FilteredEpisode?
            if needsValidation {
                let alDate = alSchedule?[episode]
                resolvedEntry = episodeByAirDate(alDate: alDate, filtered: filtered, episode: episode)

                if let resolved = resolvedEntry {
                    var keysToRemove: [String] = []
                    for (key, entry) in filtered {
                        if let eid = entry.anidbEid, let resolvedEid = resolved.anidbEid, eid == resolvedEid {
                            keysToRemove.append(key)
                        } else if let entryMs = entry.airdatems, entryMs < (resolved.airdatems ?? now) {
                            keysToRemove.append(key)
                        }
                    }
                    for key in keysToRemove {
                        filtered.removeValue(forKey: key)
                    }
                }
            } else {
                resolvedEntry = filtered["\(episode)"]
            }

            let ep = resolvedEntry?.entry
            let title = ep?.title?["en"] ?? "Episode \(episode)"
            let overview = sanitizedEpisodeNotes(ep?.summary ?? ep?.overview ?? "")
            let imageURL = ep?.image
            let airDateRaw = ep?.airdate
            let airDate: Date? = {
                // First try anizip's airdate
                if let raw = airDateRaw {
                    if let d = ISO8601DateFormatter().date(from: raw) { return d }
                    let fmt = DateFormatter()
                    fmt.dateFormat = "yyyy-MM-dd"
                    fmt.locale = Locale(identifier: "en_US_POSIX")
                    if let d = fmt.date(from: raw) { return d }
                }
                // Fallback to AniList airing schedule date (matches web's airingAt ?? airdate)
                return alSchedule?[episode]
            }()
            let runtime = ep?.length ?? ep?.runtime ?? fallbackRuntime ?? 0
            let rating = ep?.rating

            parsed.append(AniZipEpisode(
                number: episode,
                title: title,
                overview: overview, imageURL: imageURL, airDate: airDate,
                runtime: runtime, rating: rating, isFiller: false))
        }

        return parsed
    }

    private func processEpisodeResponse(_ response: AniZipEpisodesResponse, anilistEpisodes: Int?, anilistId: Int,
                                        alSchedule: [Int: Date]? = nil) {
        let parsed = AnimeDetailViewController.buildEpisodeList(
            from: response,
            anilistEpisodes: anilistEpisodes,
            alSchedule: alSchedule,
            fallbackRuntime: animeItem?.duration)

        guard !parsed.isEmpty else {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.episodes = []
                self.currentEpisodePage = 1
                self.tableView.reloadSections(IndexSet([Section.episodes.rawValue, Section.episodePagination.rawValue]), with: .none)
            }
            return
        }

        AnimeDetailViewController.loadFillerSet(for: anilistId) { fillerSet in
            let finalEpisodes = parsed.map { ep in
                AniZipEpisode(number: ep.number, title: ep.title, overview: ep.overview,
                              imageURL: ep.imageURL, airDate: ep.airDate, runtime: ep.runtime,
                              rating: ep.rating, isFiller: fillerSet.contains(ep.number))
            }
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.episodes = finalEpisodes
                if self.currentEpisodePage > self.totalEpisodePages {
                    self.currentEpisodePage = 1
                }
                self.tableView.reloadSections(IndexSet([Section.episodes.rawValue, Section.episodePagination.rawValue]), with: .none)
            }
        }
    }

    // MARK: - Filler cache

    private static var _fillerMap: [Int: Set<Int>] = [:]
    private static var _fillerMapLoaded = false
    private static var _fillerMapCallbacks: [([Int: Set<Int>]) -> Void] = []
    private static let _fillerQueue = DispatchQueue(label: "com.nyais.fillerCache")

    static func loadFillerSet(for anilistId: Int, completion: @escaping (Set<Int>) -> Void) {
        _fillerQueue.async {
            if _fillerMapLoaded {
                let set = _fillerMap[anilistId] ?? []
                completion(set)
                return
            }
            let isFirst = _fillerMapCallbacks.isEmpty
            _fillerMapCallbacks.append { map in completion(map[anilistId] ?? []) }
            guard isFirst else { return }

            guard let url = URL(string: "https://raw.githubusercontent.com/ThaUnknown/filler-scrape/master/filler.json") else { return }
            URLSession.shared.dataTask(with: url) { data, _, _ in
                var map: [Int: Set<Int>] = [:]
                if let data = data,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    for (key, val) in json {
                        if let aid = Int(key), let raw = val as? [Any] {
                            map[aid] = Set(raw.compactMap { ($0 as? NSNumber)?.intValue })
                        }
                    }
                }
                _fillerQueue.async {
                    let callbacks = _fillerMapCallbacks
                    _fillerMap = map
                    _fillerMapLoaded = true
                    _fillerMapCallbacks = []
                    for cb in callbacks { cb(map) }
                }
            }.resume()
        }
    }
}
