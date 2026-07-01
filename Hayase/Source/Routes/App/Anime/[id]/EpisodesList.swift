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
    let rating: Double?
    let isFiller: Bool
}

// MARK: - FilteredEpisode

struct FilteredEpisode {
    let key: String
    let entry: AniZipEpisodeEntry
    let airdatems: Double?
    let anidbEid: Int?
}

// MARK: - FollowerAvatarStackView

final class FollowerAvatarStackView: UIStackView {
    private var imageTasks: [URLSessionDataTask] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        axis = .horizontal
        spacing = -6
        alignment = .center
        isHidden = true
    }

    required init(coder: NSCoder) {
        super.init(coder: coder)
        axis = .horizontal
        spacing = -6
        alignment = .center
        isHidden = true
    }

    func configure(users: [AniListUserSummary]) {
        reset()
        let visibleUsers = Array(users.filter { ($0.avatarURL?.isEmpty == false) }.prefix(4))
        isHidden = visibleUsers.isEmpty
        for user in visibleUsers {
            let avatar = UIImageView()
            avatar.backgroundColor = UIColor(white: 0.18, alpha: 1)
            avatar.contentMode = .scaleAspectFill
            avatar.clipsToBounds = true
            avatar.layer.cornerRadius = 8
            avatar.layer.borderWidth = 1
            avatar.layer.borderColor = UIColor.black.cgColor
            avatar.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                avatar.widthAnchor.constraint(equalToConstant: 16),
                avatar.heightAnchor.constraint(equalToConstant: 16),
            ])
            addArrangedSubview(avatar)

            guard let urlString = user.avatarURL, let url = URL(string: urlString) else { continue }
            let task = URLSession.shared.dataTask(with: url) { [weak avatar] data, _, _ in
                guard let data, let image = UIImage(data: data) else { return }
                DispatchQueue.main.async {
                    avatar?.image = image
                }
            }
            imageTasks.append(task)
            task.resume()
        }
    }

    func reset() {
        imageTasks.forEach { $0.cancel() }
        imageTasks.removeAll()
        arrangedSubviews.forEach { view in
            removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        isHidden = true
    }
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
        backgroundColor = UIColor.HayaseTheme.accent.withAlphaComponent(0.8)
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

    func configure(rating: Double) {
        label.text = String(format: "%.2f", rating)
        isHidden = false
    }
}

// MARK: - EpisodeCardView

final class EpisodeCardView: UIView, UIGestureRecognizerDelegate {

    var onTap: ((Int) -> Void)?
    private var episodeNumber: Int = 0

    private let thumbImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.backgroundColor = UIColor(white: 0.10, alpha: 1)
        iv.layer.cornerRadius = 6
        iv.layer.maskedCorners = [.layerMinXMinYCorner, .layerMinXMaxYCorner]
        return iv
    }()

    private let runtimeBadge: PaddedLabel = {
        let l = PaddedLabel()
        l.font = .nunito(ofSize: 9.6)
        l.textColor = UIColor(white: 0.98, alpha: 1)
        l.backgroundColor = UIColor(white: 0.09, alpha: 0.8)
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
        l.textColor = UIColor(white: 0.04, alpha: 1)
        l.backgroundColor = UIColor(red: 0.97, green: 0.81, blue: 0.00, alpha: 1)
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
        l.textColor = .white
        l.numberOfLines = 1
        return l
    }()

    private let progressBar: UIView = {
        let outer = UIView()
        outer.backgroundColor = UIColor(white: 0.16, alpha: 1)
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
        l.textColor = UIColor(white: 0.649, alpha: 1.0)
        l.numberOfLines = 3
        return l
    }()

    private let metaLabel: UILabel = {
        let l = UILabel()
        l.font = .nunito(ofSize: 9.6)
        l.textColor = .white
        return l
    }()

    private let followerStack = FollowerAvatarStackView()

    private let playOverlayView: UIView = {
        let v = UIView()
        v.backgroundColor = UIColor.HayaseTheme.background.withAlphaComponent(0.5)
        v.alpha = 0
        v.isUserInteractionEnabled = false
        v.layer.cornerRadius = 6
        v.layer.maskedCorners = [.layerMinXMinYCorner, .layerMinXMaxYCorner]
        v.clipsToBounds = true
        return v
    }()

    private let playOverlayIcon: UIImageView = {
        let iv = UIImageView(image: UIImage.hayaseFilledIcon("play", pointSize: 22))
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
        view.layer.cornerRadius = 6
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
        clipsToBounds = false
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowRadius = 0
        layer.shadowOpacity = 0
        layer.shadowOffset = CGSize(width: 0, height: 0)

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

        let bottomRow = UIStackView(arrangedSubviews: [metaLabel, UIView(), followerStack])
        bottomRow.axis = .horizontal
        bottomRow.spacing = 8
        bottomRow.alignment = .center

        let textStack = UIStackView(arrangedSubviews: [numberLabel, progressBar, overviewLabel, spacer, bottomRow])
        textStack.axis = .vertical
        textStack.spacing = 4
        textStack.setCustomSpacing(8, after: numberLabel)
        textStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(textStack)

        thumbWidthPreferred = thumbImageView.widthAnchor.constraint(equalTo: widthAnchor, multiplier: 0.5)
        thumbWidthPreferred.priority = UILayoutPriority(999)
        let episodeThumbnailMaxWidth: CGFloat = 208
        thumbMaxWidth = thumbImageView.widthAnchor.constraint(lessThanOrEqualToConstant: episodeThumbnailMaxWidth)

        textLeadingToThumb = textStack.leadingAnchor.constraint(equalTo: thumbImageView.trailingAnchor, constant: 16)
        textLeadingToCard = textStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16)
        textLeadingToThumb.isActive = true
        textLeadingToCard.isActive = false

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 112),

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
            playOverlayIcon.widthAnchor.constraint(equalToConstant: 28),
            playOverlayIcon.heightAnchor.constraint(equalToConstant: 28),

            runtimeBadge.leadingAnchor.constraint(equalTo: thumbImageView.leadingAnchor, constant: 4),
            runtimeBadge.bottomAnchor.constraint(equalTo: thumbImageView.bottomAnchor, constant: -4),

            ratingBadge.trailingAnchor.constraint(equalTo: thumbImageView.trailingAnchor, constant: -4),
            ratingBadge.bottomAnchor.constraint(equalTo: thumbImageView.bottomAnchor, constant: -4),

            textLeadingToThumb,
            textStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            textStack.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            textStack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -12),

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
            self.playOverlayView.alpha = pressed ? 1 : 0
            self.playOverlayIcon.alpha = pressed ? 1 : 0
            self.playOverlayIcon.transform = pressed ? .identity : CGAffineTransform(scaleX: 0.75, y: 0.75)
            self.layer.shadowRadius = pressed ? 18 : 0
            self.layer.shadowOpacity = pressed ? 0.45 : 0
            self.layer.shadowOffset = pressed ? CGSize(width: 0, height: 8) : .zero
        }
        if animated {
            UIView.animate(withDuration: 0.16, delay: 0, options: [.allowUserInteraction, .beginFromCurrentState], animations: changes)
        } else {
            changes()
        }
    }

    func configure(with episode: AniZipEpisode, anilistID: Int = 0, anilistProgress: Int = 0,
                   accentColor: UIColor = .white, isListCompleted: Bool = false,
                   isRepeating: Bool = false, hideSpoilers: Bool = false,
                   followers: [AniListUserSummary] = []) {
        episodeNumber = episode.number
        numberLabel.text = "\(episode.number). \(episode.title.isEmpty ? "Episode \(episode.number)" : episode.title)"
        overviewLabel.text = episode.overview
        overviewLabel.isHidden = episode.overview.isEmpty
        followerStack.configure(users: followers)

        let isWatchedOnAniList = anilistProgress > 0 && episode.number <= anilistProgress && !isListCompleted
        let isTarget = !isListCompleted && episode.number == anilistProgress + 1
        let isSpoiler = hideSpoilers && !isWatchedOnAniList && !isListCompleted && !isRepeating && !isTarget
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
           let saved = WatchProgressService.shared.getProgress(anilistID: anilistID, episode: episode.number),
           saved.isInProgress {
            progressBar.backgroundColor = UIColor(white: 0.16, alpha: 1)
            progressBar.isHidden = false
            savedProgressFraction = saved.fraction
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
            ratingBadge.configure(rating: isSpoiler ? 5.00 : rating)
            ratingBadge.isHidden = false
        } else {
            ratingBadge.isHidden = true
        }

        if episode.isFiller {
            layer.borderWidth = 1
            layer.borderColor = UIColor(red: 0.97, green: 0.81, blue: 0.00, alpha: 1).cgColor
            fillerBadge.isHidden = false
        } else if isTarget {
            layer.borderWidth = 1
            layer.borderColor = accentColor.cgColor
            fillerBadge.isHidden = true
        } else {
            layer.borderWidth = 0
            layer.borderColor = UIColor.clear.cgColor
            fillerBadge.isHidden = true
        }

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

        if let urlStr = episode.imageURL, let url = URL(string: urlStr) {
            let captured = urlStr
            imageTask = URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
                guard let data = data, let img = UIImage(data: data) else { return }
                DispatchQueue.main.async {
                    if self?.currentImageURL == captured {
                        UIView.transition(with: self?.thumbImageView ?? UIImageView(),
                                          duration: 0.2, options: .transitionCrossDissolve,
                                          animations: { self?.thumbImageView.image = img })
                    }
                }
            }
            imageTask?.resume()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
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
        layer.borderWidth = 0
        layer.borderColor = UIColor.clear.cgColor
        alpha = 1.0
        thumbImageView.alpha = 1.0
        progressBar.isHidden = true
        progressBar.backgroundColor = UIColor(white: 0.16, alpha: 1)
        savedProgressFraction = 0
        progressFillWidthConstraint?.constant = 0
        episodeNumber = 0
        onTap = nil
    }
}

// MARK: - EpisodeCell

final class EpisodeCell: UITableViewCell {
    static let reuseID = "AniDetailEpCell"

    let cardView = EpisodeCardView()
    private var cardLeadingConstraint: NSLayoutConstraint?
    private var cardTrailingConstraint: NSLayoutConstraint?

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

        cardView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(cardView)

        cardLeadingConstraint = cardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12)
        cardTrailingConstraint = cardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12)

        NSLayoutConstraint.activate([
            cardView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 14),
            cardView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -14),
            cardLeadingConstraint!,
            cardTrailingConstraint!,
        ])
    }

    func configure(with episode: AniZipEpisode, anilistID: Int = 0, anilistProgress: Int = 0,
                   accentColor: UIColor = .white, isListCompleted: Bool = false,
                   isRepeating: Bool = false, hideSpoilers: Bool = false,
                   followers: [AniListUserSummary] = []) {
        cardView.configure(with: episode, anilistID: anilistID, anilistProgress: anilistProgress,
                           accentColor: accentColor, isListCompleted: isListCompleted,
                           isRepeating: isRepeating, hideSpoilers: hideSpoilers,
                           followers: followers)
    }

    func applyPaddingForSizeClass(isRegular: Bool) {
        let sidePad: CGFloat = isRegular ? 68 : 12
        cardLeadingConstraint?.constant = sidePad
        cardTrailingConstraint?.constant = -sidePad
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        cardView.reset()
    }
}

// MARK: - EpisodePairCell

final class EpisodePairCell: UITableViewCell {
    static let reuseID = "EpisodePairCell"

    let leftCard = EpisodeCardView()
    let rightCard = EpisodeCardView()
    var onTapEpisode: ((Int) -> Void)?

    private let stack = UIStackView()
    private let leftContainer = UIView()
    private let rightContainer = UIView()
    private var leftCardLeadingConstraint: NSLayoutConstraint?
    private var leftCardTrailingConstraint: NSLayoutConstraint?
    private var rightCardLeadingConstraint: NSLayoutConstraint?
    private var rightCardTrailingConstraint: NSLayoutConstraint?

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
        leftContainer.clipsToBounds = false
        rightContainer.clipsToBounds = false
        selectionStyle = .none

        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false

        leftCard.translatesAutoresizingMaskIntoConstraints = false
        rightCard.translatesAutoresizingMaskIntoConstraints = false

        leftContainer.addSubview(leftCard)
        rightContainer.addSubview(rightCard)
        stack.addArrangedSubview(leftContainer)
        stack.addArrangedSubview(rightContainer)
        contentView.addSubview(stack)

        leftCardLeadingConstraint = leftCard.leadingAnchor.constraint(equalTo: leftContainer.leadingAnchor, constant: 12)
        leftCardTrailingConstraint = leftCard.trailingAnchor.constraint(equalTo: leftContainer.trailingAnchor, constant: -12)
        rightCardLeadingConstraint = rightCard.leadingAnchor.constraint(equalTo: rightContainer.leadingAnchor, constant: 12)
        rightCardTrailingConstraint = rightCard.trailingAnchor.constraint(equalTo: rightContainer.trailingAnchor, constant: -12)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 14),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -14),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 56),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -56),
            leftCard.topAnchor.constraint(equalTo: leftContainer.topAnchor),
            leftCard.bottomAnchor.constraint(equalTo: leftContainer.bottomAnchor),
            leftCardLeadingConstraint!,
            leftCardTrailingConstraint!,
            rightCard.topAnchor.constraint(equalTo: rightContainer.topAnchor),
            rightCard.bottomAnchor.constraint(equalTo: rightContainer.bottomAnchor),
            rightCardLeadingConstraint!,
            rightCardTrailingConstraint!,
        ])
    }

    func configure(left: AniZipEpisode, right: AniZipEpisode?, anilistID: Int, anilistProgress: Int,
                   accentColor: UIColor, isListCompleted: Bool,
                   isRepeating: Bool = false, hideSpoilers: Bool = false,
                   followersByEpisode: [Int: [AniListUserSummary]] = [:]) {
        leftCard.configure(with: left, anilistID: anilistID, anilistProgress: anilistProgress,
                           accentColor: accentColor, isListCompleted: isListCompleted,
                           isRepeating: isRepeating, hideSpoilers: hideSpoilers,
                           followers: followersByEpisode[left.number] ?? [])
        applyTargetPadding(toLeftCard: true, isTarget: !isListCompleted && left.number == anilistProgress + 1)
        leftCard.onTap = { [weak self] num in self?.onTapEpisode?(num) }

        if let right = right {
            rightCard.configure(with: right, anilistID: anilistID, anilistProgress: anilistProgress,
                                accentColor: accentColor, isListCompleted: isListCompleted,
                                isRepeating: isRepeating, hideSpoilers: hideSpoilers,
                                followers: followersByEpisode[right.number] ?? [])
            applyTargetPadding(toLeftCard: false, isTarget: !isListCompleted && right.number == anilistProgress + 1)
            rightCard.onTap = { [weak self] num in self?.onTapEpisode?(num) }
            rightContainer.isHidden = false
        } else {
            rightCard.reset()
            applyTargetPadding(toLeftCard: false, isTarget: false)
            rightContainer.isHidden = true
        }
    }

    private func applyTargetPadding(toLeftCard: Bool, isTarget: Bool) {
        let inset: CGFloat = isTarget ? 0 : 12
        if toLeftCard {
            leftCardLeadingConstraint?.constant = inset
            leftCardTrailingConstraint?.constant = -inset
        } else {
            rightCardLeadingConstraint?.constant = inset
            rightCardTrailingConstraint?.constant = -inset
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        leftCard.reset()
        rightCard.reset()
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
        let config = UIImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        b.setImage(UIImage.hayaseIcon("chevron-left", withConfiguration: config), for: .normal)
        b.tintColor = .white
        b.translatesAutoresizingMaskIntoConstraints = false
        b.widthAnchor.constraint(equalToConstant: 36).isActive = true
        b.heightAnchor.constraint(equalToConstant: 36).isActive = true
        return b
    }()

    private let nextButton: UIButton = {
        let b = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        b.setImage(UIImage.hayaseIcon("chevron-right", withConfiguration: config), for: .normal)
        b.tintColor = .white
        b.translatesAutoresizingMaskIntoConstraints = false
        b.widthAnchor.constraint(equalToConstant: 36).isActive = true
        b.heightAnchor.constraint(equalToConstant: 36).isActive = true
        return b
    }()

    private let pageStack: UIStackView = {
        let sv = UIStackView()
        sv.axis = .horizontal
        sv.spacing = 2
        sv.alignment = .center
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()

    private let controlsStack: UIStackView = {
        let sv = UIStackView()
        sv.axis = .horizontal
        sv.spacing = 2
        sv.alignment = .center
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()

    private let compactInfoLabel: UILabel = {
        let label = UILabel()
        label.font = .nunito(ofSize: 13)
        label.textColor = UIColor(white: 0.63, alpha: 1)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isHidden = true
        return label
    }()

    private var infoLeadingConstraint: NSLayoutConstraint?
    private var controlsTrailingConstraint: NSLayoutConstraint?
    private var controlsCenterXConstraint: NSLayoutConstraint?
    private var renderedInfoText: NSAttributedString?
    private var lastAppliedCompactMode: Bool?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear

        prevButton.addTarget(self, action: #selector(prevTapped), for: .touchUpInside)
        nextButton.addTarget(self, action: #selector(nextTapped), for: .touchUpInside)

        controlsStack.addArrangedSubview(prevButton)
        controlsStack.addArrangedSubview(pageStack)
        controlsStack.addArrangedSubview(nextButton)

        addSubview(infoLabel)
        addSubview(controlsStack)
        addSubview(compactInfoLabel)

        infoLeadingConstraint = infoLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16)
        controlsTrailingConstraint = controlsStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16)
        controlsCenterXConstraint = controlsStack.centerXAnchor.constraint(equalTo: centerXAnchor)

        NSLayoutConstraint.activate([
            infoLeadingConstraint!,
            infoLabel.centerYAnchor.constraint(equalTo: controlsStack.centerYAnchor),

            controlsTrailingConstraint!,
            controlsStack.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            controlsStack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -8),

            compactInfoLabel.topAnchor.constraint(equalTo: controlsStack.bottomAnchor, constant: 8),
            compactInfoLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 16),
            compactInfoLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -16),
            compactInfoLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            compactInfoLabel.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -8),

            heightAnchor.constraint(greaterThanOrEqualToConstant: 52),
        ])
    }

    func applyPaddingForSizeClass(isRegular: Bool) {
        let sidePad: CGFloat = isRegular ? 56 : 16
        infoLeadingConstraint?.constant = sidePad
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
        prevButton.alpha = currentPage > 1 ? 1.0 : 0.35
        nextButton.isEnabled = currentPage < totalPages
        nextButton.alpha = currentPage < totalPages ? 1.0 : 0.35

        pageStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        let pages = computePages()
        for item in pages {
            if item.isEllipsis {
                let label = UILabel()
                label.text = "..."
                label.font = .nunito(ofSize: 13)
                label.textColor = UIColor(white: 0.63, alpha: 1)
                label.textAlignment = .center
                label.widthAnchor.constraint(equalToConstant: 36).isActive = true
                label.heightAnchor.constraint(equalToConstant: 36).isActive = true
                pageStack.addArrangedSubview(label)
            } else {
                let btn = UIButton(type: .system)
                btn.setTitle("\(item.page)", for: .normal)
                btn.titleLabel?.font = .nunito(ofSize: 13, weight: .medium)
                btn.tag = item.page
                btn.widthAnchor.constraint(equalToConstant: 36).isActive = true
                btn.heightAnchor.constraint(equalToConstant: 36).isActive = true
                btn.layer.cornerRadius = 6
                btn.clipsToBounds = true
                btn.addTarget(self, action: #selector(pageTapped(_:)), for: .touchUpInside)

                if item.page == currentPage {
                    btn.layer.borderWidth = 1
                    btn.layer.borderColor = UIColor(white: 0.27, alpha: 1).cgColor
                    btn.setTitleColor(.white, for: .normal)
                    btn.backgroundColor = .clear
                } else {
                    btn.layer.borderWidth = 0
                    btn.setTitleColor(UIColor(white: 0.63, alpha: 1), for: .normal)
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
        compactInfoLabel.attributedText = renderedInfoText
        compactInfoLabel.isHidden = !isCompact
        controlsTrailingConstraint?.isActive = !isCompact
        controlsCenterXConstraint?.isActive = isCompact
    }

    private var effectivePaginationWidth: CGFloat {
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
        let cols = episodeColumnCount
        let currentAnilistID = animeItem?.id ?? (animeEntity?.animeAnilistId?.intValue ?? 0)
        let isCompleted = currentListStatus == "COMPLETED"
        let isRepeating = currentListStatus == "REPEATING"
        let hideSpoilers = UserDefaults.standard.bool(forKey: "pref_hideSpoilers")
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
                           followersByEpisode: followingEntriesByEpisode)
            cell.onTapEpisode = { [weak self] epNumber in
                self?.openExtensionSearch(episode: epNumber)
            }
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
                           followers: followingEntriesByEpisode[ep.number] ?? [])
            cell.cardView.onTap = { [weak self] epNumber in
                self?.openExtensionSearch(episode: epNumber)
            }
            cell.applyPaddingForSizeClass(isRegular: traitCollection.horizontalSizeClass == .regular)
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

    private func episodeByAirDate(
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
            guard let ms = entry.airdatems else { continue }
            let dist = abs(ms - alMs)
            if dist < closestDist {
                closestDist = dist
                closest = [entry]
            } else if dist == closestDist {
                closest.append(entry)
            }
        }

        guard !closest.isEmpty else { return filtered["\(episode)"] }

        return closest.min(by: {
            abs(Int($0.key) ?? 0 - episode) < abs(Int($1.key) ?? 0 - episode)
        })
    }

    private func processEpisodeResponse(_ response: AniZipEpisodesResponse, anilistEpisodes: Int?, anilistId: Int,
                                        alSchedule: [Int: Date]? = nil) {
        let episodesDict = response.episodes ?? [:]
        let episodesResCount = response.episodeCount
        let specialCount = response.specialCount ?? 0

        let count = anilistEpisodes ?? episodesResCount ?? 0

        var filtered: [String: FilteredEpisode] = [:]
        for (key, ep) in episodesDict {
            let airdate = ep.airdate ?? ep.airDate
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
        guard count > 0 else {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.episodes = []
                self.currentEpisodePage = 1
                self.tableView.reloadSections(IndexSet([Section.episodes.rawValue, Section.episodePagination.rawValue]), with: .none)
            }
            return
        }

        for episode in 1...count {
            let hasEpisode = episodesDict["\(episode)"] != nil

            let needsValidation = !(!hasSpecial || (hasEpisode && hasCountMatch))

            let resolvedEntry: FilteredEpisode?
            if needsValidation {
                let alDate = alSchedule?[episode]
                resolvedEntry = self.episodeByAirDate(alDate: alDate, filtered: filtered, episode: episode)

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
            let titles = ep?.title ?? [:]
            let title = titles["en"] ?? titles["x-jat"] ?? titles["ja"] ?? ""
            let overview = (ep?.overview ?? ep?.summary ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let imageURL = ep?.image
            let airDateRaw = ep?.airdate ?? ep?.airDate
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
            let runtime = ep?.length ?? ep?.runtime ?? 0
            let rating: Double? = ep?.rating.flatMap(Double.init)

            parsed.append(AniZipEpisode(
                number: episode,
                title: title.isEmpty ? "Episode \(episode)" : title,
                overview: overview, imageURL: imageURL, airDate: airDate,
                runtime: runtime, rating: rating, isFiller: false))
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
