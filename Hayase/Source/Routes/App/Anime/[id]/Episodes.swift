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
    let info: [String: Any]
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
