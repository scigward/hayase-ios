//
//  Episodes.swift
//  Hayase
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

// MARK: - EpisodeCardView

final class EpisodeCardView: UIView {

    var onTap: ((Int) -> Void)?
    private var episodeNumber: Int = 0

    private let thumbImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.backgroundColor = UIColor(white: 0.10, alpha: 1)
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

    private let ratingBadge: PaddedLabel = {
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

    static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        f.dateTimeStyle = .numeric
        f.locale = Locale(identifier: "en")
        return f
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
        clipsToBounds = true

        [thumbImageView, runtimeBadge, ratingBadge].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }
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

        let textStack = UIStackView(arrangedSubviews: [numberLabel, progressBar, overviewLabel, spacer, metaLabel])
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
        addGestureRecognizer(tap)
    }

    @objc private func cardTapped() {
        onTap?(episodeNumber)
    }

    func configure(with episode: AniZipEpisode, anilistID: Int = 0, anilistProgress: Int = 0,
                   accentColor: UIColor = .white, isListCompleted: Bool = false) {
        episodeNumber = episode.number
        numberLabel.text = "\(episode.number). \(episode.title.isEmpty ? "Episode \(episode.number)" : episode.title)"
        overviewLabel.text = episode.overview
        overviewLabel.isHidden = episode.overview.isEmpty

        let isWatchedOnAniList = anilistProgress > 0 && episode.number <= anilistProgress && !isListCompleted
        thumbImageView.alpha = isWatchedOnAniList ? 0.2 : 1.0
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
            metaLabel.text = EpisodeCardView.relativeDateFormatter.localizedString(for: date, relativeTo: Date())
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
            let ratingStr = String(format: "%.2f", rating)
            let starAttachment = NSTextAttachment()
            let starCfg = UIImage.SymbolConfiguration(pointSize: 10, weight: .regular)
            if let starImg = UIImage(systemName: "star.fill", withConfiguration: starCfg)?
                .withTintColor(UIColor(red: 0.97, green: 0.81, blue: 0.00, alpha: 1), renderingMode: .alwaysOriginal) {
                starAttachment.image = starImg
                starAttachment.bounds = CGRect(x: 0, y: -1.5, width: 10, height: 10)
            }
            let padded = NSMutableAttributedString(attachment: starAttachment)
            padded.append(NSAttributedString(string: " \(ratingStr)", attributes: [
                .foregroundColor: UIColor(white: 0.98, alpha: 1),
                .font: UIFont.nunito(ofSize: 9.6)
            ]))
            ratingBadge.attributedText = padded
            ratingBadge.isHidden = false
        } else {
            ratingBadge.isHidden = true
        }

        let isTarget = !isListCompleted && episode.number == anilistProgress + 1
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
                   accentColor: UIColor = .white, isListCompleted: Bool = false) {
        cardView.configure(with: episode, anilistID: anilistID, anilistProgress: anilistProgress,
                           accentColor: accentColor, isListCompleted: isListCompleted)
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

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 14),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -14),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 56),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -56),
            leftCard.topAnchor.constraint(equalTo: leftContainer.topAnchor),
            leftCard.bottomAnchor.constraint(equalTo: leftContainer.bottomAnchor),
            leftCard.leadingAnchor.constraint(equalTo: leftContainer.leadingAnchor, constant: 12),
            leftCard.trailingAnchor.constraint(equalTo: leftContainer.trailingAnchor, constant: -12),
            rightCard.topAnchor.constraint(equalTo: rightContainer.topAnchor),
            rightCard.bottomAnchor.constraint(equalTo: rightContainer.bottomAnchor),
            rightCard.leadingAnchor.constraint(equalTo: rightContainer.leadingAnchor, constant: 12),
            rightCard.trailingAnchor.constraint(equalTo: rightContainer.trailingAnchor, constant: -12),
        ])
    }

    func configure(left: AniZipEpisode, right: AniZipEpisode?, anilistID: Int, anilistProgress: Int,
                   accentColor: UIColor, isListCompleted: Bool) {
        leftCard.configure(with: left, anilistID: anilistID, anilistProgress: anilistProgress,
                           accentColor: accentColor, isListCompleted: isListCompleted)
        leftCard.onTap = { [weak self] num in self?.onTapEpisode?(num) }

        if let right = right {
            rightCard.configure(with: right, anilistID: anilistID, anilistProgress: anilistProgress,
                                accentColor: accentColor, isListCompleted: isListCompleted)
            rightCard.onTap = { [weak self] num in self?.onTapEpisode?(num) }
            rightContainer.isHidden = false
        } else {
            rightCard.reset()
            rightContainer.isHidden = true
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        leftCard.reset()
        rightCard.reset()
        rightContainer.isHidden = false
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
        b.setImage(UIImage(systemName: "chevron.left", withConfiguration: config), for: .normal)
        b.tintColor = .white
        b.translatesAutoresizingMaskIntoConstraints = false
        b.widthAnchor.constraint(equalToConstant: 36).isActive = true
        b.heightAnchor.constraint(equalToConstant: 36).isActive = true
        return b
    }()

    private let nextButton: UIButton = {
        let b = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        b.setImage(UIImage(systemName: "chevron.right", withConfiguration: config), for: .normal)
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

    private var infoLeadingConstraint: NSLayoutConstraint?
    private var controlsTrailingConstraint: NSLayoutConstraint?

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

        infoLeadingConstraint = infoLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16)
        controlsTrailingConstraint = controlsStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16)

        NSLayoutConstraint.activate([
            infoLeadingConstraint!,
            infoLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            controlsTrailingConstraint!,
            controlsStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            controlsStack.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: 8),
            controlsStack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -8),

            heightAnchor.constraint(greaterThanOrEqualToConstant: 52),
        ])
    }

    func applyPaddingForSizeClass(isRegular: Bool) {
        let sidePad: CGFloat = isRegular ? 56 : 16
        infoLeadingConstraint?.constant = sidePad
        controlsTrailingConstraint?.constant = -sidePad
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(currentPage: Int, totalCount: Int, perPage: Int) {
        self.currentPage = currentPage
        self.totalCount = totalCount
        self.perPage = perPage
        self.totalPages = max(1, Int(ceil(Double(totalCount) / Double(perPage))))
        rebuild()
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

        let isNarrow = (superview?.frame.width ?? UIScreen.main.bounds.width) < 600
        pageStack.isHidden = isNarrow
        infoLabel.isHidden = isNarrow

        if isNarrow {
            if controlsStack.arrangedSubviews.count == 3 {
                let compactInfo = UILabel()
                compactInfo.font = .nunito(ofSize: 13)
                compactInfo.textColor = UIColor(white: 0.63, alpha: 1)
                compactInfo.textAlignment = .center
                compactInfo.attributedText = str
                compactInfo.tag = 999
                compactInfo.translatesAutoresizingMaskIntoConstraints = false
                controlsStack.insertArrangedSubview(compactInfo, at: 2)
            } else if let compact = controlsStack.arrangedSubviews.first(where: { $0.tag == 999 }) as? UILabel {
                compact.attributedText = str
            }
        } else {
            if let compact = controlsStack.arrangedSubviews.first(where: { $0.tag == 999 }) {
                controlsStack.removeArrangedSubview(compact)
                compact.removeFromSuperview()
            }
        }
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
        if cols >= 2 {
            guard let cell = tableView.dequeueReusableCell(
                withIdentifier: EpisodePairCell.reuseID, for: indexPath) as? EpisodePairCell else {
                return UITableViewCell()
            }
            let leftIdx = indexPath.row * 2
            let rightIdx = leftIdx + 1
            let leftEp = paginatedEpisodes[leftIdx]
            let rightEp = rightIdx < paginatedEpisodes.count ? paginatedEpisodes[rightIdx] : nil
            cell.configure(left: leftEp, right: rightEp, anilistID: currentAnilistID,
                           anilistProgress: anilistProgress, accentColor: currentAnimeAccent,
                           isListCompleted: isCompleted)
            cell.onTapEpisode = { [weak self] epNumber in
                self?.openExtensionSearch(episode: epNumber)
            }
            return cell
        } else {
            guard let cell = tableView.dequeueReusableCell(
                withIdentifier: EpisodeCell.reuseID, for: indexPath) as? EpisodeCell else {
                return UITableViewCell()
            }
            let ep = paginatedEpisodes[indexPath.row]
            cell.configure(with: ep, anilistID: currentAnilistID, anilistProgress: anilistProgress,
                           accentColor: currentAnimeAccent, isListCompleted: isCompleted)
            cell.cardView.onTap = { [weak self] epNumber in
                self?.openExtensionSearch(episode: epNumber)
            }
            cell.applyPaddingForSizeClass(isRegular: traitCollection.horizontalSizeClass == .regular)
            return cell
        }
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

        AniZipService.shared.episodes(anilistID: id) { [weak self] response in
            guard let self = self, let response = response else { return }

            let hasAnidbId = response.mappings?.anidb_id != nil

            if !hasAnidbId, let fmt = format, ["SPECIAL", "OVA", "ONA"].contains(fmt) {
                self.resolveParentID(format: fmt) { [weak self] parentID in
                    guard let self = self else { return }
                    if let parentID = parentID {
                        AniListClient.shared.fetchMediaAiringSchedule(anilistID: id) { [weak self] schedResult in
                            guard let self = self else { return }

                            var alSchedule: [Int: Date] = schedResult?.schedule ?? [:]

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
                                self.processEpisodeResponse(finalResponse, anilistEpisodes: anilistEpisodes,
                                                            anilistId: id, alSchedule: alSchedule)
                            }
                        }
                    } else {
                        self.processEpisodeResponse(response, anilistEpisodes: anilistEpisodes, anilistId: id)
                    }
                }
                return
            }

            self.processEpisodeResponse(response, anilistEpisodes: anilistEpisodes, anilistId: id)
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
        AniListClient.shared.fetchDetailForItem(id: id) { [weak self] rels in
            self?.animeItem?.relations = rels
            self?.relations = rels
            let parentID = ["PARENT", "PREQUEL", "SEQUEL"].lazy.compactMap { relType -> Int? in
                rels.first { $0.relationType == relType }?.media.id
            }.first
            completion(parentID)
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

        var anizipBannerURL: String? = nil
        if let images = response.images {
            let fanart = images.first(where: { $0.coverType == "Fanart" })?.url
            let poster = images.first(where: { $0.coverType == "Poster" })?.url
            anizipBannerURL = fanart ?? poster
        }

        var parsed: [AniZipEpisode] = []
        guard count > 0 else {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.episodes = []
                self.currentEpisodePage = 1
                self.tableView.reloadSections(IndexSet([Section.episodes.rawValue, Section.episodePagination.rawValue]), with: .none)
                if let bannerURL = anizipBannerURL {
                    self.headerView.updateBanner(from: bannerURL)
                }
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
            let airDate: Date? = airDateRaw.flatMap { raw in
                if let d = ISO8601DateFormatter().date(from: raw) { return d }
                let fmt = DateFormatter()
                fmt.dateFormat = "yyyy-MM-dd"
                fmt.locale = Locale(identifier: "en_US_POSIX")
                return fmt.date(from: raw)
            }
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
                if let bannerURL = anizipBannerURL {
                    self.headerView.updateBanner(from: bannerURL)
                }
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

            let url = URL(string: "https://raw.githubusercontent.com/ThaUnknown/filler-scrape/master/filler.json")!
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
