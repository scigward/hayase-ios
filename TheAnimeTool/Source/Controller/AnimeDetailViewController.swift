//
//  AnimeDetailViewController.swift
//  TheAnimeTool
//
//  Shows full anime details (banner, cover, synopsis, badges) fetched from AniList,
//  plus a per-episode list from the ani.zip API. Matches Hayase's anime/[id]/+layout.svelte.
//

import UIKit
import SafariServices

// MARK: - AniZip episode model

struct AniZipEpisode {
    let number: Int
    let title: String       // English title, or "Episode N" fallback
    let overview: String
    let imageURL: String?
    let airDate: String?
    let runtime: Int        // minutes; 0 if unknown
}

// MARK: - EpisodeCell
// Matches Hayase's EpisodesList.svelte exactly:
// • bg-neutral-950 (#0a0a0a) card, rounded-md (8pt), max-h-28 (112pt)
// • Image: left 50%, max-w-52 (208pt) — 16:9 aspect inside
// • Runtime badge: absolute bottom-left, bg-neutral-900/80, text-[9.6px]
// • Title: font-bold text-[12.8px] — "{episode}. {title}"
// • Progress: h-0.5 (2pt) bg-custom (blue approximation) when in progress
// • Summary: text-[9.6px] text-muted-foreground (#a1a1aa)
// • Airdate: text-[9.6px] pt-2

private final class EpisodeCell: UITableViewCell {
    static let reuseID = "AniDetailEpCell"

    // bg-neutral-950 = #0a0a0a
    private let cardView: UIView = {
        let v = UIView()
        v.backgroundColor = UIColor(white: 0.039, alpha: 1) // neutral-950
        v.layer.cornerRadius = 8  // rounded-md
        v.clipsToBounds = true
        return v
    }()

    private let thumbImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.backgroundColor = UIColor(white: 0.10, alpha: 1)
        return iv
    }()

    // Runtime badge: absolute bottom-left, bg-neutral-900/80, text-[9.6px]
    private let runtimeBadge: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 9.6)
        l.textColor = UIColor(white: 0.98, alpha: 1) // text-secondary-foreground
        l.backgroundColor = UIColor(white: 0.09, alpha: 0.8) // bg-neutral-900/80
        l.layer.cornerRadius = 3
        l.clipsToBounds = true
        l.isHidden = true
        return l
    }()

    // Title: font-bold text-[12.8px] line-clamp-1
    private let numberLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 12.8, weight: .bold)
        l.textColor = .white
        l.numberOfLines = 1
        return l
    }()

    // Progress bar: h-0.5 (2pt) bg-custom — shown when episode in progress
    private let progressBar: UIView = {
        let outer = UIView()
        outer.backgroundColor = UIColor(white: 0.16, alpha: 1) // track = neutral-800
        return outer
    }()
    private let progressFill: UIView = {
        let v = UIView()
        v.backgroundColor = .white   // approximates bg-custom (cover color)
        return v
    }()
    private var progressFillWidthConstraint: NSLayoutConstraint?
    /// Stored fraction for deferred layout — updated in layoutSubviews once bounds are valid.
    private var savedProgressFraction: Double = 0

    // Summary: text-[9.6px] text-muted-foreground
    private let overviewLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 9.6)
        l.textColor = UIColor(white: 0.649, alpha: 1.0) // --muted-foreground
        l.numberOfLines = 3
        return l
    }()

    // Airdate: text-[9.6px]
    private let metaLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 9.6)
        l.textColor = UIColor(white: 0.649, alpha: 1.0)
        return l
    }()

    private var currentImageURL: String?
    private var imageTask: URLSessionDataTask?

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

        [thumbImageView, runtimeBadge].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            cardView.addSubview($0)
        }

        // Progress bar: thin 2pt line
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

        let textStack = UIStackView(arrangedSubviews: [numberLabel, progressBar, overviewLabel, metaLabel])
        textStack.axis = .vertical
        textStack.spacing = 4
        textStack.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(textStack)

        NSLayoutConstraint.activate([
            // Card: margin 6pt top/bottom, 16pt left/right
            cardView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 6),
            cardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            cardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            cardView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6),
            // max-h-28 = 112pt — fixed height for consistent thumbnail sizes across all episode cards
            cardView.heightAnchor.constraint(equalToConstant: 112),

            // Thumbnail: left side, w-1/2 (50% — matches Hayase EpisodesList.svelte `w-1/2 shrink-0`), full height
            thumbImageView.topAnchor.constraint(equalTo: cardView.topAnchor),
            thumbImageView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),
            thumbImageView.bottomAnchor.constraint(equalTo: cardView.bottomAnchor),
            thumbImageView.widthAnchor.constraint(equalTo: cardView.widthAnchor, multiplier: 0.5),

            // Runtime badge: bottom-left of thumb
            runtimeBadge.leadingAnchor.constraint(equalTo: thumbImageView.leadingAnchor, constant: 4),
            runtimeBadge.bottomAnchor.constraint(equalTo: thumbImageView.bottomAnchor, constant: -4),

            // Text stack: right of thumbnail, with 16pt padding
            textStack.leadingAnchor.constraint(equalTo: thumbImageView.trailingAnchor, constant: 16),
            textStack.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -8),
            textStack.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 12),
            textStack.bottomAnchor.constraint(lessThanOrEqualTo: cardView.bottomAnchor, constant: -8),

            // Progress bar height: h-0.5 = 2pt
            progressBar.heightAnchor.constraint(equalToConstant: 2),
        ])
    }

    func configure(with episode: AniZipEpisode, anilistID: Int = 0) {
        numberLabel.text = "\(episode.number). \(episode.title.isEmpty ? "Episode \(episode.number)" : episode.title)"
        overviewLabel.text = episode.overview
        overviewLabel.isHidden = episode.overview.isEmpty

        // Progress bar (Hayase EpisodesList watchProgress indicator)
        if anilistID > 0,
           let saved = WatchProgressService.shared.getProgress(anilistID: anilistID, episode: episode.number),
           saved.isInProgress {
            progressBar.isHidden = false
            savedProgressFraction = saved.fraction
            setNeedsLayout()
        } else {
            progressBar.isHidden = true
            savedProgressFraction = 0
        }

        if let date = episode.airDate {
            metaLabel.text = date
            metaLabel.isHidden = false
        } else {
            metaLabel.isHidden = true
        }

        if episode.runtime > 0 {
            runtimeBadge.text = " \(episode.runtime)m "
            runtimeBadge.isHidden = false
        } else {
            runtimeBadge.isHidden = true
        }

        currentImageURL = episode.imageURL
        thumbImageView.image = nil
        imageTask?.cancel()
        imageTask = nil

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
        // Update progress fill width once bounds are known (avoids async timing issue)
        guard !progressBar.isHidden, progressBar.bounds.width > 0 else { return }
        progressFillWidthConstraint?.constant = progressBar.bounds.width * CGFloat(savedProgressFraction)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageTask?.cancel()
        imageTask = nil
        currentImageURL = nil
        thumbImageView.image = nil
        numberLabel.text = nil
        overviewLabel.text = nil
        metaLabel.text = nil
        runtimeBadge.isHidden = true
        progressBar.isHidden = true
        savedProgressFraction = 0
        progressFillWidthConstraint?.constant = 0
    }
}

// MARK: - HorizontalCardsCell
// A UITableViewCell containing a horizontal UICollectionView.
// tag 100 → Relations, tag 200 → Characters, tag 300 → Staff.

private final class HorizontalCardsCell: UITableViewCell {
    static let relationsReuseID  = "HorizontalRelationsCell"
    static let charactersReuseID = "HorizontalCharactersCell"
    static let staffReuseID      = "HorizontalStaffCell"

    let collectionView: UICollectionView

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.itemSize = CGSize(width: 90, height: 140)
        layout.minimumInteritemSpacing = 10
        layout.minimumLineSpacing = 10
        layout.sectionInset = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .clear
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.backgroundColor = .clear
        contentView.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            collectionView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }
}

// MARK: - RelationCardCell

private final class RelationCardCell: UICollectionViewCell {
    static let reuseID = "RelationCardCell"

    private let imageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.backgroundColor = .systemGray5
        iv.layer.cornerRadius = 6
        return iv
    }()

    private let titleLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 9, weight: .semibold)
        l.textColor = .label
        l.numberOfLines = 2
        return l
    }()

    private let typeLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 8, weight: .medium)
        l.textColor = .white
        l.backgroundColor = UIColor.systemIndigo.withAlphaComponent(0.85)
        l.layer.cornerRadius = 3
        l.clipsToBounds = true
        return l
    }()

    private var imageTask: URLSessionDataTask?
    private var currentURL: String?

    override init(frame: CGRect) {
        super.init(frame: frame)
        [imageView, titleLabel, typeLabel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview($0)
        }
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            imageView.heightAnchor.constraint(equalTo: contentView.widthAnchor, multiplier: 1.35),

            typeLabel.leadingAnchor.constraint(equalTo: imageView.leadingAnchor, constant: 4),
            typeLabel.bottomAnchor.constraint(equalTo: imageView.bottomAnchor, constant: -4),

            titleLabel.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 4),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            titleLabel.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(with relation: AnimeRelation) {
        let displayType = relation.relationType
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
        typeLabel.text = " \(displayType) "
        titleLabel.text = relation.media.titleEnglish ?? relation.media.titleRomaji
        loadImage(from: relation.media.coverURL)
    }

    private func loadImage(from urlString: String?) {
        imageTask?.cancel()
        imageTask = nil
        currentURL = urlString
        imageView.image = nil
        guard let urlString = urlString, let url = URL(string: urlString) else { return }
        let captured = urlString
        imageTask = URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data = data, let img = UIImage(data: data) else { return }
            DispatchQueue.main.async {
                if self?.currentURL == captured {
                    UIView.transition(with: self?.imageView ?? UIImageView(),
                                      duration: 0.2, options: .transitionCrossDissolve,
                                      animations: { self?.imageView.image = img })
                }
            }
        }
        imageTask?.resume()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageTask?.cancel(); imageTask = nil; currentURL = nil
        imageView.image = nil; titleLabel.text = nil; typeLabel.text = nil
    }
}

// MARK: - CharacterCardCell

private final class CharacterCardCell: UICollectionViewCell {
    static let reuseID = "CharacterCardCell"

    private let imageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.backgroundColor = .systemGray5
        iv.layer.cornerRadius = 6
        return iv
    }()

    private let nameLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 9, weight: .semibold)
        l.textColor = .label
        l.numberOfLines = 2
        return l
    }()

    private let roleLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 8, weight: .medium)
        l.textColor = .secondaryLabel
        l.numberOfLines = 1
        return l
    }()

    private var imageTask: URLSessionDataTask?
    private var currentURL: String?

    override init(frame: CGRect) {
        super.init(frame: frame)
        let stack = UIStackView(arrangedSubviews: [nameLabel, roleLabel])
        stack.axis = .vertical
        stack.spacing = 2
        [imageView, stack].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview($0)
        }
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            imageView.heightAnchor.constraint(equalTo: contentView.widthAnchor, multiplier: 1.35),

            stack.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 4),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(with character: AnimeCharacter) {
        nameLabel.text = character.name
        roleLabel.text = character.role.capitalized
        loadImage(from: character.imageURL)
    }

    private func loadImage(from urlString: String?) {
        imageTask?.cancel(); imageTask = nil
        currentURL = urlString
        imageView.image = nil
        guard let urlString = urlString, let url = URL(string: urlString) else { return }
        let captured = urlString
        imageTask = URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data = data, let img = UIImage(data: data) else { return }
            DispatchQueue.main.async {
                if self?.currentURL == captured {
                    UIView.transition(with: self?.imageView ?? UIImageView(),
                                      duration: 0.2, options: .transitionCrossDissolve,
                                      animations: { self?.imageView.image = img })
                }
            }
        }
        imageTask?.resume()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageTask?.cancel(); imageTask = nil; currentURL = nil
        imageView.image = nil; nameLabel.text = nil; roleLabel.text = nil
    }
}

// MARK: - StaffCardCell (anime/[id]/staff.svelte)

private final class StaffCardCell: UICollectionViewCell {
    static let reuseID = "StaffCardCell"

    private let imageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.backgroundColor = .systemGray5
        iv.layer.cornerRadius = 6
        return iv
    }()

    private let nameLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 9, weight: .semibold)
        l.textColor = .label
        l.numberOfLines = 2
        return l
    }()

    private let roleLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 8)
        l.textColor = .secondaryLabel
        l.numberOfLines = 1
        return l
    }()

    private var imageTask: URLSessionDataTask?
    private var currentURL: String?

    override init(frame: CGRect) {
        super.init(frame: frame)
        let stack = UIStackView(arrangedSubviews: [nameLabel, roleLabel])
        stack.axis = .vertical
        stack.spacing = 2
        [imageView, stack].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview($0)
        }
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            imageView.heightAnchor.constraint(equalTo: contentView.widthAnchor, multiplier: 1.35),

            stack.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 4),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(with member: AnimeStaffMember) {
        nameLabel.text = member.name
        roleLabel.text = member.role
        imageTask?.cancel(); imageTask = nil
        currentURL = member.imageURL
        imageView.image = nil
        guard let urlStr = member.imageURL, let url = URL(string: urlStr) else { return }
        let captured = urlStr
        imageTask = URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data = data, let img = UIImage(data: data) else { return }
            DispatchQueue.main.async {
                if self?.currentURL == captured {
                    UIView.transition(with: self?.imageView ?? UIImageView(),
                                      duration: 0.2, options: .transitionCrossDissolve,
                                      animations: { self?.imageView.image = img })
                }
            }
        }
        imageTask?.resume()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageTask?.cancel(); imageTask = nil; currentURL = nil
        imageView.image = nil; nameLabel.text = nil; roleLabel.text = nil
    }
}

// MARK: - ScoreBarChartView + StatsCell (anime/[id]/stats.svelte)

private final class ScoreBarChartView: UIView {
    private var arrangedStack: UIStackView?

    func configure(with points: [AnimeScorePoint]) {
        arrangedStack?.removeFromSuperview()
        arrangedStack = nil
        guard !points.isEmpty else { return }
        let maxAmount = points.map { $0.amount }.max() ?? 1
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.alignment = .bottom
        stack.spacing = 3
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        arrangedStack = stack
        for point in points {
            let col = UIView()
            let bar = UIView()
            // Shade darkens for higher scores (Hayase uses indigo gradient)
            let alpha = 0.4 + 0.6 * CGFloat(point.score) / 100.0
            bar.backgroundColor = UIColor.systemIndigo.withAlphaComponent(alpha)
            bar.layer.cornerRadius = 2
            bar.translatesAutoresizingMaskIntoConstraints = false
            let lbl = UILabel()
            lbl.text = "\(point.score)"
            lbl.font = .systemFont(ofSize: 7)
            lbl.textColor = .tertiaryLabel
            lbl.textAlignment = .center
            lbl.translatesAutoresizingMaskIntoConstraints = false
            col.addSubview(bar)
            col.addSubview(lbl)
            let fraction = max(0.04, CGFloat(point.amount) / CGFloat(maxAmount))
            NSLayoutConstraint.activate([
                lbl.bottomAnchor.constraint(equalTo: col.bottomAnchor),
                lbl.leadingAnchor.constraint(equalTo: col.leadingAnchor),
                lbl.trailingAnchor.constraint(equalTo: col.trailingAnchor),
                lbl.heightAnchor.constraint(equalToConstant: 14),
                bar.leadingAnchor.constraint(equalTo: col.leadingAnchor),
                bar.trailingAnchor.constraint(equalTo: col.trailingAnchor),
                bar.bottomAnchor.constraint(equalTo: lbl.topAnchor, constant: -2),
                bar.heightAnchor.constraint(equalTo: col.heightAnchor, multiplier: fraction * 0.85),
            ])
            stack.addArrangedSubview(col)
        }
    }
}

private final class StatsCell: UITableViewCell {
    static let reuseID = "AniDetailStatsCell"

    private let chartView = ScoreBarChartView()
    private let statusStack = UIStackView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setup()
    }
    required init?(coder: NSCoder) { super.init(coder: coder); setup() }

    private func makeTitle(_ text: String) -> UILabel {
        let l = UILabel()
        l.text = text
        l.font = .systemFont(ofSize: 14, weight: .semibold)
        l.textColor = .label
        return l
    }

    private func setup() {
        backgroundColor = .clear
        selectionStyle = .none
        chartView.translatesAutoresizingMaskIntoConstraints = false
        statusStack.axis = .vertical
        statusStack.spacing = 10
        let mainStack = UIStackView(arrangedSubviews: [
            makeTitle("Score Distribution"), chartView,
            makeTitle("Watching Status"), statusStack,
        ])
        mainStack.axis = .vertical
        mainStack.spacing = 14
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(mainStack)
        NSLayoutConstraint.activate([
            chartView.heightAnchor.constraint(equalToConstant: 90),
            mainStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            mainStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            mainStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            mainStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),
        ])
    }

    func configure(scores: [AnimeScorePoint], statuses: [AnimeStatusCount]) {
        chartView.configure(with: scores)
        statusStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let total = statuses.reduce(0) { $0 + $1.amount }
        for status in statuses {
            let fraction = total > 0 ? Float(status.amount) / Float(total) : 0
            let name = status.status.replacingOccurrences(of: "_", with: " ").capitalized
            let nameLabel = UILabel()
            nameLabel.text = name
            nameLabel.font = .systemFont(ofSize: 11)
            nameLabel.textColor = .label
            nameLabel.widthAnchor.constraint(equalToConstant: 80).isActive = true
            let progress = UIProgressView(progressViewStyle: .default)
            progress.setProgress(fraction, animated: false)
            progress.progressTintColor = Self.statusColor(for: status.status)
            progress.trackTintColor = .systemGray5
            let countLabel = UILabel()
            countLabel.text = "\(status.amount)"
            countLabel.font = .systemFont(ofSize: 11)
            countLabel.textColor = .secondaryLabel
            countLabel.textAlignment = .right
            countLabel.widthAnchor.constraint(equalToConstant: 52).isActive = true
            let row = UIStackView(arrangedSubviews: [nameLabel, progress, countLabel])
            row.axis = .horizontal
            row.spacing = 8
            row.alignment = .center
            statusStack.addArrangedSubview(row)
        }
    }

    private static func statusColor(for status: String) -> UIColor {
        switch status {
        case "CURRENT":   return .systemGreen
        case "COMPLETED": return .systemBlue
        case "PLANNING":  return .systemGray
        case "DROPPED":   return .systemRed
        case "PAUSED":    return .systemOrange
        default:          return .systemIndigo
        }
    }
}

// MARK: - AnimeInfoHeaderView
// Matches Hayase's anime/[id]/+layout.svelte exactly:
// • Cover: 100×142pt (180:256 ratio), rounded-6, left of text column
// • h2 romaji: font-light, text-muted-foreground (#a1a1aa), truncate 1 line — ABOVE h1
// • h1 title: font-black, text-3xl (30pt), text-white — below romaji
// • Badges row: bg-primary/10 (white/10%) rounded px-14 font-bold h-6 (24pt) — below title
// • Description: font-light text-sm text-muted-foreground line-clamp-4 — below cover row
// • Actions: Play (bg-white text-black w-full) + secondary icons (bg-#27272a white, 36×36pt)
//   NO findTorrentsButton
// • Genres: bg-secondary (#27272a) h-7 (28pt) rounded-md text-white chips
//
// Colors (dark mode only, as per app.css color-scheme:only dark):
//   --muted-foreground: hsl(240 5% 64.9%) = #a1a1aa
//   --secondary:        hsl(240 3.7% 15.9%) = #27272a

private final class AnimeInfoHeaderView: UIView {
    // Callbacks
    var onShare: (() -> Void)?
    var onOpenAniList: (() -> Void)?
    var onPlayTrailer: (() -> Void)?
    var onWatch: (() -> Void)?

    private var anilistId: Int?

    // MARK: - Color constants matching Hayase dark theme
    private static let mutedFg      = UIColor(white: 0.649, alpha: 1.0) // --muted-foreground
    private static let secondary     = UIColor(red: 0.153, green: 0.153, blue: 0.165, alpha: 1) // --secondary #27272a

    // MARK: - Banner (180pt, full-width — approximates global BannerImage in Hayase)
    private let bannerImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.backgroundColor = UIColor(white: 0.08, alpha: 1)
        return iv
    }()
    // Radial-gradient overlay matching banner-image.svelte: dark at edges, lighter at top-center
    private let bannerGradientLayer = CAGradientLayer()

    // MARK: - Cover (w-[180px] h-[256px] rounded  → proportional 100×142 on iPhone)
    private let coverImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.backgroundColor = UIColor(white: 0.16, alpha: 1)
        iv.layer.cornerRadius = 6   // rounded = 0.375rem ≈ 6pt
        return iv
    }()

    // MARK: - Text labels
    // h2: font-light text-muted-foreground text-lg line-clamp-1 — ABOVE h1
    private let romajiLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 17, weight: .light)
        l.textColor = UIColor(white: 0.649, alpha: 1.0)
        l.numberOfLines = 1
        return l
    }()

    // h1: font-black text-3xl text-white line-clamp-2
    private let titleLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 30, weight: .black)
        l.textColor = .white
        l.numberOfLines = 2
        return l
    }()

    // Badges row — bg-primary/10 pills. horizontal stack (scrollable)
    private let badgesStack: UIStackView = {
        let sv = UIStackView()
        sv.axis = .horizontal
        sv.spacing = 6
        sv.alignment = .center
        return sv
    }()
    private let badgesScrollView: UIScrollView = {
        let sv = UIScrollView()
        sv.showsHorizontalScrollIndicator = false
        sv.showsVerticalScrollIndicator = false
        return sv
    }()

    // Description: font-light text-sm text-muted-foreground line-clamp-4
    private let descriptionLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 14, weight: .light)
        l.textColor = UIColor(white: 0.649, alpha: 1.0)
        l.numberOfLines = 4
        return l
    }()

    // MARK: - Action buttons
    // Play button: bg-custom text-contrast (bg-white text-black since no cover color available)
    // grow = fills remaining width in actions row
    private let playButton: UIButton = {
        let b = UIButton(type: .system)
        b.setTitle("▶  Watch Now", for: .normal)
        b.tintColor = .black
        b.backgroundColor = .white
        b.titleLabel?.font = .systemFont(ofSize: 15, weight: .bold)
        b.layer.cornerRadius = 8
        b.layer.masksToBounds = true
        return b
    }()

    // Secondary icon buttons: bg-secondary (#27272a), white icon, 36×36pt, rounded-md (8pt)
    private let shareButton: UIButton = {
        let b = UIButton(type: .system)
        b.setImage(UIImage(systemName: "square.and.arrow.up"), for: .normal)
        b.tintColor = .white
        b.backgroundColor = UIColor(red: 0.153, green: 0.153, blue: 0.165, alpha: 1)
        b.layer.cornerRadius = 8
        b.layer.masksToBounds = true
        return b
    }()

    private let anilistButton: UIButton = {
        let b = UIButton(type: .system)
        b.setTitle("AL", for: .normal)
        b.tintColor = .white
        b.backgroundColor = UIColor(red: 0.153, green: 0.153, blue: 0.165, alpha: 1)
        b.titleLabel?.font = .systemFont(ofSize: 12, weight: .bold)
        b.layer.cornerRadius = 8
        b.layer.masksToBounds = true
        return b
    }()

    private let trailerButton: UIButton = {
        let b = UIButton(type: .system)
        b.setImage(UIImage(systemName: "film"), for: .normal)
        b.tintColor = .white
        b.backgroundColor = UIColor(red: 0.153, green: 0.153, blue: 0.165, alpha: 1)
        b.layer.cornerRadius = 8
        b.layer.masksToBounds = true
        b.isHidden = true
        return b
    }()

    // Genres: variant='secondary' h-7 (28pt) text-nowrap rounded-md
    private let genresStack: UIStackView = {
        let sv = UIStackView()
        sv.axis = .horizontal
        sv.spacing = 8
        sv.alignment = .center
        return sv
    }()
    private let genresScrollView: UIScrollView = {
        let sv = UIScrollView()
        sv.showsHorizontalScrollIndicator = false
        sv.showsVerticalScrollIndicator = false
        return sv
    }()

    private var bannerImageTask: URLSessionDataTask?
    private var coverImageTask: URLSessionDataTask?

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    // MARK: - Layout

    private func setup() {
        backgroundColor = UIColor(white: 0.04, alpha: 1) // --background dark

        // Banner gradient layer (dark edges → lighter center, like banner-image.svelte)
        bannerGradientLayer.colors = [UIColor.clear.cgColor, UIColor.black.withAlphaComponent(0.85).cgColor]
        bannerGradientLayer.locations = [0.2, 1.0]

        // Badges scrollview
        badgesScrollView.translatesAutoresizingMaskIntoConstraints = false
        badgesStack.translatesAutoresizingMaskIntoConstraints = false
        badgesScrollView.addSubview(badgesStack)
        NSLayoutConstraint.activate([
            badgesStack.topAnchor.constraint(equalTo: badgesScrollView.topAnchor),
            badgesStack.bottomAnchor.constraint(equalTo: badgesScrollView.bottomAnchor),
            badgesStack.leadingAnchor.constraint(equalTo: badgesScrollView.leadingAnchor),
            badgesStack.trailingAnchor.constraint(equalTo: badgesScrollView.trailingAnchor),
            badgesStack.heightAnchor.constraint(equalTo: badgesScrollView.heightAnchor),
        ])

        // Genres scrollview
        genresScrollView.translatesAutoresizingMaskIntoConstraints = false
        genresStack.translatesAutoresizingMaskIntoConstraints = false
        genresScrollView.addSubview(genresStack)
        NSLayoutConstraint.activate([
            genresStack.topAnchor.constraint(equalTo: genresScrollView.topAnchor),
            genresStack.bottomAnchor.constraint(equalTo: genresScrollView.bottomAnchor),
            genresStack.leadingAnchor.constraint(equalTo: genresScrollView.leadingAnchor),
            genresStack.trailingAnchor.constraint(equalTo: genresScrollView.trailingAnchor),
            genresStack.heightAnchor.constraint(equalTo: genresScrollView.heightAnchor),
        ])

        // Text column: [romajiLabel, titleLabel, badgesScrollView]
        // gap-1.5 between romaji+title, gap-2 before badges (≈ 6pt, 8pt)
        let textColumn = UIStackView(arrangedSubviews: [romajiLabel, titleLabel, badgesScrollView])
        textColumn.axis = .vertical
        textColumn.spacing = 6
        textColumn.alignment = .leading

        // Cover + text row: [coverImageView  textColumn]  — gap-5 = 20pt
        let coverTextRow = UIStackView(arrangedSubviews: [coverImageView, textColumn])
        coverTextRow.axis = .horizontal
        coverTextRow.spacing = 16
        coverTextRow.alignment = .bottom  // md:items-end

        // Action buttons: [playButton(grow)  shareButton  anilistButton  trailerButton]
        shareButton.addTarget(self, action: #selector(shareTapped), for: .touchUpInside)
        anilistButton.addTarget(self, action: #selector(anilistTapped), for: .touchUpInside)
        trailerButton.addTarget(self, action: #selector(trailerTapped), for: .touchUpInside)
        playButton.addTarget(self, action: #selector(playTapped), for: .touchUpInside)

        let actionsRow = UIStackView(arrangedSubviews: [playButton, shareButton, anilistButton, trailerButton])
        actionsRow.axis = .horizontal
        actionsRow.spacing = 8
        actionsRow.alignment = .fill

        // Main content: [coverTextRow, description, actionsRow, genresScrollView]
        let contentStack = UIStackView(arrangedSubviews: [coverTextRow, descriptionLabel, actionsRow, genresScrollView])
        contentStack.axis = .vertical
        contentStack.spacing = 16
        contentStack.isLayoutMarginsRelativeArrangement = true
        contentStack.layoutMargins = UIEdgeInsets(top: 12, left: 16, bottom: 24, right: 16)

        [bannerImageView, contentStack].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }
        bannerImageView.layer.addSublayer(bannerGradientLayer)

        NSLayoutConstraint.activate([
            // Banner: full-width, 180pt — approximates h-[23rem] from banner-image.svelte
            bannerImageView.topAnchor.constraint(equalTo: topAnchor),
            bannerImageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            bannerImageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            bannerImageView.heightAnchor.constraint(equalToConstant: 180),

            // Cover: w-[180px] h-[256px] ratio → 100×142 on phone
            coverImageView.widthAnchor.constraint(equalToConstant: 100),
            coverImageView.heightAnchor.constraint(equalToConstant: 142),

            // Badges scrollview height = 24pt (h-6)
            badgesScrollView.heightAnchor.constraint(equalToConstant: 24),

            // Actions row height = 36pt (h-9)
            actionsRow.heightAnchor.constraint(equalToConstant: 36),
            shareButton.widthAnchor.constraint(equalToConstant: 36),
            anilistButton.widthAnchor.constraint(equalToConstant: 36),
            trailerButton.widthAnchor.constraint(equalToConstant: 36),

            // Genres scrollview height = 28pt (h-7)
            genresScrollView.heightAnchor.constraint(equalToConstant: 28),

            // Content stack starts just where banner ends (they visually overlap via banner's gradient)
            contentStack.topAnchor.constraint(equalTo: bannerImageView.bottomAnchor, constant: -30),
            contentStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentStack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        bannerGradientLayer.frame = bannerImageView.bounds
    }

    // MARK: - Actions

    @objc private func shareTapped()   { onShare?() }
    @objc private func anilistTapped() { onOpenAniList?() }
    @objc private func trailerTapped() { onPlayTrailer?() }
    @objc private func playTapped()    { onWatch?() }

    // MARK: - Configure (Animes CoreData entity)

    func configure(with anime: Animes?) {
        guard let anime = anime else { return }
        anilistId = anime.animeAnilistId?.intValue

        // h2: romaji (or native). h1: English (or romaji).
        let english = anime.animeTitleEnglish
        let romaji  = anime.animeTitleJapanese
        titleLabel.text   = english ?? romaji ?? "Unknown"
        romajiLabel.text  = (english != nil && romaji != nil && english != romaji) ? romaji : nil
        romajiLabel.isHidden = romajiLabel.text == nil

        // Badges: bg-primary/10 pills
        rebuildBadges(score:   anime.animeScore?.floatValue,
                      status:  anime.animeStatus,
                      episodes: anime.animeTotalEps?.intValue,
                      nextEp:  anime.animeNextEps?.intValue,
                      format:  nil, season: nil)

        // Genre chips: not in CoreData, so hide
        genresScrollView.isHidden = true

        // Description: font-light text-sm text-muted-foreground
        let desc = anime.animeDescription?.trimmingCharacters(in: .whitespacesAndNewlines)
        descriptionLabel.text = (desc?.isEmpty ?? true) ? nil : desc

        trailerButton.isHidden = true

        loadImage(from: anime.animeImgS ?? anime.animeImgL ?? anime.animeImgM,
                  into: bannerImageView, task: &bannerImageTask)
        loadImage(from: anime.animeImgL ?? anime.animeImgM,
                  into: coverImageView, task: &coverImageTask)
    }

    // MARK: - Configure (AnimeItem from AniList)

    func configure(with item: AnimeItem) {
        anilistId = item.id

        let english = item.titleEnglish
        let romaji  = item.titleRomaji
        titleLabel.text  = english ?? romaji ?? "Unknown"
        // +layout.svelte: if romaji === title → show native; else show romaji
        // We show romaji when different from english
        romajiLabel.text = (english != nil && romaji != nil && english != romaji) ? romaji : nil
        romajiLabel.isHidden = romajiLabel.text == nil

        // Apply anime's cover colour to Watch Now button and badge pills
        // Mirrors Hayase +layout.svelte: style:--custom={media.coverImage?.color ?? '#fff'}
        // bg-custom text-contrast (luminance-based black/white text)
        let accent  = ExtensionSearchViewController.uiColor(fromHex: item.coverColor) ?? .white
        let contrast = ExtensionSearchViewController.luminanceContrastColor(for: accent)
        playButton.backgroundColor = accent
        playButton.tintColor = contrast

        rebuildBadges(score:    item.score,
                      status:   item.status,
                      episodes: item.episodes,
                      nextEp:   nil,
                      format:   item.format,
                      season:   nil,
                      accent:   accent,
                      contrastColor: contrast)

        genresStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for genre in item.genres.prefix(8) {
            genresStack.addArrangedSubview(makeGenreChip(text: genre))
        }
        genresScrollView.isHidden = item.genres.isEmpty

        let desc = item.description?.trimmingCharacters(in: .whitespacesAndNewlines)
        descriptionLabel.text = (desc?.isEmpty ?? true) ? nil : desc

        // Trailer button: show when YouTube trailer ID available
        trailerButton.isHidden = item.trailerYouTubeID == nil

        loadImage(from: item.bannerURL ?? item.coverURL, into: bannerImageView, task: &bannerImageTask)
        loadImage(from: item.coverURL, into: coverImageView, task: &coverImageTask)
    }

    // MARK: - Helpers

    /// Builds the badges row matching Hayase's +layout.svelte badge pills.
    /// Badges: duration/eps, format, status, season, score — all bg-custom (accent), rounded, font-bold h-6
    private func rebuildBadges(score: Float?, status: String?, episodes: Int?,
                                nextEp: Int?, format: String?, season: String?,
                                accent: UIColor = .white,
                                contrastColor: UIColor = UIColor(white: 0.07, alpha: 1)) {
        badgesStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        // duration/eps badge
        if let eps = episodes, eps > 0 {
            badgesStack.addArrangedSubview(makeBadge(text: "\(eps) eps", accent: accent, contrast: contrastColor))
        } else if let next = nextEp, next > 0 {
            badgesStack.addArrangedSubview(makeBadge(text: "Ep \(next) airing", accent: accent, contrast: contrastColor))
        }
        // format badge
        if let fmt = format {
            let display = fmt == "TV_SHORT" ? "TV Short" : fmt.replacingOccurrences(of: "_", with: " ").capitalized
            badgesStack.addArrangedSubview(makeBadge(text: display, accent: accent, contrast: contrastColor))
        }
        // status badge
        if let st = status {
            let display: String
            switch st {
            case "RELEASING":        display = "Airing"
            case "FINISHED":         display = "Finished"
            case "NOT_YET_RELEASED": display = "Upcoming"
            default:                 display = st.replacingOccurrences(of: "_", with: " ").capitalized
            }
            badgesStack.addArrangedSubview(makeBadge(text: display, accent: accent, contrast: contrastColor))
        }
        // score badge
        if let sc = score, sc > 0 {
            badgesStack.addArrangedSubview(makeBadge(text: String(format: "%.0f%%", sc), accent: accent, contrast: contrastColor))
        }
    }

    /// Badge pill: bg-custom (accent colour, mirrors Hayase --custom) rounded px-3.5 font-bold h-6 text-contrast
    private func makeBadge(text: String,
                            accent: UIColor = .white,
                            contrast: UIColor = UIColor(white: 0.07, alpha: 1)) -> UILabel {
        let l = UILabel()
        l.text = "  \(text)  "
        l.font = .systemFont(ofSize: 12, weight: .bold)
        l.textColor = contrast
        l.backgroundColor = accent
        l.layer.cornerRadius = 4   // rounded
        l.clipsToBounds = true
        l.setContentHuggingPriority(.required, for: .horizontal)
        return l
    }

    /// Genre chip: variant='secondary' h-7 (28pt) text-nowrap rounded-md
    /// bg-secondary (#27272a), text-secondary-foreground (white)
    private func makeGenreChip(text: String) -> UIView {
        let btn = UIButton(type: .system)
        btn.setTitle(text, for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 13, weight: .medium)
        btn.setTitleColor(.white, for: .normal)
        btn.backgroundColor = UIColor(red: 0.153, green: 0.153, blue: 0.165, alpha: 1) // --secondary
        btn.contentEdgeInsets = UIEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)
        btn.layer.cornerRadius = 6  // rounded-md
        btn.layer.masksToBounds = true
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.heightAnchor.constraint(equalToConstant: 28).isActive = true // h-7
        btn.setContentHuggingPriority(.required, for: .horizontal)
        return btn
    }

    private func loadImage(from urlString: String?,
                           into imageView: UIImageView,
                           task: inout URLSessionDataTask?) {
        task?.cancel()
        task = nil
        imageView.image = nil
        guard let urlString = urlString, !urlString.isEmpty, let url = URL(string: urlString) else { return }
        if let cached = SharedImageCache.shared.object(forKey: urlString as NSString) {
            imageView.image = cached
            return
        }
        let captured = urlString
        task = URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data = data, let img = UIImage(data: data) else { return }
            SharedImageCache.shared.setObject(img, forKey: captured as NSString)
            DispatchQueue.main.async {
                UIView.transition(with: imageView, duration: 0.3,
                                  options: .transitionCrossDissolve,
                                  animations: { imageView.image = img })
            }
        }
        task?.resume()
    }
}

// MARK: - AnimeDetailViewController

class AnimeDetailViewController: UIViewController {

    var animeEntity: Animes?
    var animeItem: AnimeItem?

    private var tableView: UITableView!
    private var headerView: AnimeInfoHeaderView!
    private var episodes: [AniZipEpisode] = []
    private var relations: [AnimeRelation] = []
    private var characters: [AnimeCharacter] = []
    private var staff: [AnimeStaffMember] = []
    private var scoreDistribution: [AnimeScorePoint] = []
    private var statusDistribution: [AnimeStatusCount] = []
    private var episodeFetchTask: URLSessionDataTask?

    // Active tab for the segmented control (Episodes | Relations | Characters | Staff | Stats)
    private var activeSection: Section = .episodes

    // Matches Hayase tabs: bg-muted container (#27272a), active = bg-foreground (#fafafa) text-background (black)
    private lazy var segControl: UISegmentedControl = {
        let sc = UISegmentedControl(items: ["Episodes", "Relations", "Chars", "Staff", "Stats"])
        sc.selectedSegmentIndex = 0
        // Tabs.List bg: --muted = #27272a
        sc.backgroundColor = UIColor(red: 0.153, green: 0.153, blue: 0.165, alpha: 1)
        // Active segment: bg-foreground (#fafafa) text-background (dark)
        sc.selectedSegmentTintColor = UIColor(white: 0.98, alpha: 1)
        sc.setTitleTextAttributes([.foregroundColor: UIColor(white: 0.649, alpha: 1)], for: .normal)
        sc.setTitleTextAttributes([.foregroundColor: UIColor(white: 0.04, alpha: 1), .font: UIFont.systemFont(ofSize: 13, weight: .bold)], for: .selected)
        sc.addTarget(self, action: #selector(segmentChanged), for: .valueChanged)
        return sc
    }()

    private lazy var segControlContainer: UIView = {
        let v = UIView()
        v.backgroundColor = UIColor(white: 0.04, alpha: 1) // --background dark
        segControl.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(segControl)
        NSLayoutConstraint.activate([
            segControl.topAnchor.constraint(equalTo: v.topAnchor, constant: 8),
            segControl.bottomAnchor.constraint(equalTo: v.bottomAnchor, constant: -8),
            segControl.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 16),
            segControl.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -16),
        ])
        return v
    }()

    // Section indices
    private enum Section: Int, CaseIterable {
        case episodes = 0, relations, characters, staff, stats
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        // Hayase anime/[id]/+layout.svelte has no navigation title — info is shown in the header
        title = nil
        navigationItem.largeTitleDisplayMode = .never
        view.backgroundColor = UIColor(white: 0.04, alpha: 1) // --background dark

        setupTableView()
        setupHeaderView()
        fetchEpisodes()
        fetchRelationsAndCharacters()
        fetchStaffAndStats()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Make the nav bar transparent so only the back chevron floats over the content.
        // This removes the black bar that appeared when title = nil left an empty nav bar.
        let nb = navigationController?.navigationBar
        nb?.setBackgroundImage(UIImage(), for: .default)
        nb?.shadowImage = UIImage()
        nb?.tintColor = .white  // back chevron visible over dark banner
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // Restore the standard nav bar appearance for other view controllers
        let nb = navigationController?.navigationBar
        nb?.setBackgroundImage(nil, for: .default)
        nb?.shadowImage = nil
        nb?.tintColor = nil
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        sizeHeaderView()
    }

    // MARK: - Setup

    private func setupTableView() {
        tableView = UITableView(frame: view.bounds, style: .plain)
        tableView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(EpisodeCell.self, forCellReuseIdentifier: EpisodeCell.reuseID)
        tableView.register(HorizontalCardsCell.self, forCellReuseIdentifier: HorizontalCardsCell.relationsReuseID)
        tableView.register(HorizontalCardsCell.self, forCellReuseIdentifier: HorizontalCardsCell.charactersReuseID)
        tableView.register(HorizontalCardsCell.self, forCellReuseIdentifier: HorizontalCardsCell.staffReuseID)
        tableView.register(StatsCell.self, forCellReuseIdentifier: StatsCell.reuseID)
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 100
        tableView.separatorStyle = .none
        tableView.backgroundColor = UIColor(white: 0.04, alpha: 1) // --background dark
        // Remove the automatic nav-bar/status-bar content inset so the header banner
        // extends behind the transparent nav bar (no black gap), matching Hayase where
        // the banner-image div is `absolute top-0` behind the sidebar/browser chrome.
        tableView.contentInsetAdjustmentBehavior = .never
        view.addSubview(tableView)
    }

    private func setupHeaderView() {
        headerView = AnimeInfoHeaderView()
        if let item = animeItem {
            headerView.configure(with: item)
        } else {
            headerView.configure(with: animeEntity)
        }
        headerView.onShare = { [weak self] in
            guard let self = self else { return }
            let title = self.animeItem?.titleEnglish ?? self.animeItem?.titleRomaji
                ?? self.animeEntity?.animeTitleEnglish ?? self.animeEntity?.animeTitleJapanese
                ?? "Anime"
            let id = self.animeItem?.id ?? self.animeEntity?.animeAnilistId?.intValue
            var items: [Any] = [title]
            if let id = id, let url = URL(string: "https://anilist.co/anime/\(id)") {
                items.append(url)
            }
            let activity = UIActivityViewController(activityItems: items, applicationActivities: nil)
            activity.popoverPresentationController?.sourceView = self.view
            self.present(activity, animated: true)
        }
        headerView.onOpenAniList = { [weak self] in
            guard let self = self else { return }
            let id = self.animeItem?.id ?? self.animeEntity?.animeAnilistId?.intValue
            guard let id = id, let url = URL(string: "https://anilist.co/anime/\(id)") else { return }
            UIApplication.shared.open(url)
        }
        headerView.onPlayTrailer = { [weak self] in
            guard let self = self,
                  let trailerID = self.animeItem?.trailerYouTubeID,
                  let url = URL(string: "https://www.youtube.com/watch?v=\(trailerID)") else { return }
            let safari = SFSafariViewController(url: url)
            self.present(safari, animated: true)
        }
        headerView.onWatch = { [weak self] in
            self?.openExtensionSearch(episode: 1)
        }

        // Wrap AnimeInfoHeaderView + segControlContainer in one container so the tab bar
        // scrolls WITH the content (Hayase: Tabs.Root is inside the scrollable div, not sticky).
        // With .plain UITableView, viewForHeaderInSection views are sticky; embedding in
        // tableHeaderView avoids stickiness entirely.
        let container = UIView()
        container.backgroundColor = .clear
        headerView.translatesAutoresizingMaskIntoConstraints = false
        segControlContainer.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(headerView)
        container.addSubview(segControlContainer)
        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: container.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            segControlContainer.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            segControlContainer.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            segControlContainer.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            segControlContainer.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        // 600 is a placeholder height — sizeHeaderView() corrects it in viewDidLayoutSubviews
        // using systemLayoutSizeFitting, which is the standard UITableView header sizing pattern.
        container.frame = CGRect(x: 0, y: 0, width: tableView.frame.width, height: 600)
        tableView.tableHeaderView = container
    }

    private func sizeHeaderView() {
        guard let container = tableView.tableHeaderView, tableView.frame.width > 0 else { return }
        let targetSize = CGSize(width: tableView.frame.width,
                                height: UIView.layoutFittingCompressedSize.height)
        let height = container.systemLayoutSizeFitting(
            targetSize,
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel).height
        if abs(container.frame.height - height) > 1 {
            container.frame.size.height = height
            tableView.tableHeaderView = container
        }
    }

    // MARK: - Fetch episodes (ani.zip)

    private func fetchEpisodes() {
        let anilistId: Int?
        if let entity = animeEntity {
            anilistId = entity.animeAnilistId?.intValue
        } else {
            anilistId = animeItem?.id
        }
        guard let id = anilistId else { return }
        var comps = URLComponents(string: "https://api.ani.zip/mappings")
        comps?.queryItems = [URLQueryItem(name: "anilist_id", value: String(id))]
        guard let url = comps?.url else { return }

        episodeFetchTask?.cancel()
        episodeFetchTask = URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let episodesDict = json["episodes"] as? [String: Any] else { return }

            var parsed: [AniZipEpisode] = []
            for (key, val) in episodesDict {
                guard let num = Int(key), num > 0,
                      let info = val as? [String: Any] else { continue }
                let titles = info["title"] as? [String: String] ?? [:]
                let title = titles["en"] ?? titles["x-jat"] ?? titles["ja"] ?? ""
                let overview = (info["overview"] as? String ?? info["summary"] as? String ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let imageURL = info["image"] as? String
                let airDate = info["airdate"] as? String ?? info["airDate"] as? String
                let runtime = info["length"] as? Int ?? info["runtime"] as? Int ?? 0
                parsed.append(AniZipEpisode(number: num, title: title, overview: overview,
                                            imageURL: imageURL, airDate: airDate, runtime: runtime))
            }
            parsed.sort { $0.number < $1.number }

            DispatchQueue.main.async { [weak self] in
                self?.episodes = parsed
                self?.tableView.reloadSections(IndexSet(integer: Section.episodes.rawValue), with: .fade)
            }
        }
        episodeFetchTask?.resume()
    }

    // MARK: - Fetch relations + characters (AniList detail query)

    private func fetchRelationsAndCharacters() {
        let id: Int?
        if let entity = animeEntity { id = entity.animeAnilistId?.intValue }
        else { id = animeItem?.id }
        guard let anilistId = id else { return }

        AnimeService.sharedAnimeService.fetchDetailForItem(id: anilistId) { [weak self] relations, characters in
            guard let self = self else { return }
            self.relations = relations
            self.characters = characters
            var sections = IndexSet()
            if !relations.isEmpty { sections.insert(Section.relations.rawValue) }
            if !characters.isEmpty { sections.insert(Section.characters.rawValue) }
            if !sections.isEmpty {
                self.tableView.reloadSections(sections, with: .fade)
            }
        }
    }

    // MARK: - Fetch staff + stats (anime/[id]/staff.svelte + anime/[id]/stats.svelte)

    private func fetchStaffAndStats() {
        let id: Int?
        if let entity = animeEntity { id = entity.animeAnilistId?.intValue }
        else { id = animeItem?.id }
        guard let anilistId = id else { return }

        AnimeService.sharedAnimeService.fetchStaffAndStats(id: anilistId) { [weak self] staffMembers, scores, statuses in
            guard let self = self else { return }
            self.staff = staffMembers
            self.scoreDistribution = scores
            self.statusDistribution = statuses
            var sections = IndexSet()
            if !staffMembers.isEmpty { sections.insert(Section.staff.rawValue) }
            if !scores.isEmpty || !statuses.isEmpty { sections.insert(Section.stats.rawValue) }
            if !sections.isEmpty {
                self.tableView.reloadSections(sections, with: .fade)
            }
        }
    }

    // MARK: - Segment control

    @objc private func segmentChanged() {
        guard let sec = Section(rawValue: segControl.selectedSegmentIndex) else { return }
        activeSection = sec
        tableView.reloadSections(IndexSet(integersIn: 0..<Section.allCases.count), with: .automatic)
    }

    // MARK: - Navigation

    /// Push the extension-based torrent search screen for the given episode number.
    private func openExtensionSearch(episode: Int) {
        let searchVC = ExtensionSearchViewController()
        searchVC.animeItem = animeItem
        searchVC.initialEpisode = episode
        navigationController?.pushViewController(searchVC, animated: true)
    }
}

// MARK: - UITableViewDataSource

extension AnimeDetailViewController: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        return Section.allCases.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section) {
        case .episodes:   return activeSection == .episodes  ? episodes.count : 0
        case .relations:  return (activeSection == .relations  && !relations.isEmpty)  ? 1 : 0
        case .characters: return (activeSection == .characters && !characters.isEmpty) ? 1 : 0
        case .staff:      return (activeSection == .staff      && !staff.isEmpty)      ? 1 : 0
        case .stats:      return (activeSection == .stats && (!scoreDistribution.isEmpty || !statusDistribution.isEmpty)) ? 1 : 0
        case .none: return 0
        }
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        // All section headers are returned via viewForHeaderInSection; suppress text headers here.
        return nil
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch Section(rawValue: indexPath.section) {
        case .episodes:
            guard let cell = tableView.dequeueReusableCell(
                withIdentifier: EpisodeCell.reuseID, for: indexPath) as? EpisodeCell else {
                return UITableViewCell()
            }
            let currentAnilistID = animeItem?.id ?? (animeEntity?.animeAnilistId?.intValue ?? 0)
            cell.configure(with: episodes[indexPath.row], anilistID: currentAnilistID)
            return cell

        case .relations:
            guard let cell = tableView.dequeueReusableCell(
                withIdentifier: HorizontalCardsCell.relationsReuseID,
                for: indexPath) as? HorizontalCardsCell else { return UITableViewCell() }
            cell.collectionView.tag = 100
            cell.collectionView.dataSource = self
            cell.collectionView.delegate = self
            cell.collectionView.register(RelationCardCell.self,
                                         forCellWithReuseIdentifier: RelationCardCell.reuseID)
            cell.collectionView.reloadData()
            return cell

        case .characters:
            guard let cell = tableView.dequeueReusableCell(
                withIdentifier: HorizontalCardsCell.charactersReuseID,
                for: indexPath) as? HorizontalCardsCell else { return UITableViewCell() }
            cell.collectionView.tag = 200
            cell.collectionView.dataSource = self
            cell.collectionView.delegate = self
            cell.collectionView.register(CharacterCardCell.self,
                                         forCellWithReuseIdentifier: CharacterCardCell.reuseID)
            cell.collectionView.reloadData()
            return cell

        case .staff:
            guard let cell = tableView.dequeueReusableCell(
                withIdentifier: HorizontalCardsCell.staffReuseID,
                for: indexPath) as? HorizontalCardsCell else { return UITableViewCell() }
            cell.collectionView.tag = 300
            cell.collectionView.dataSource = self
            cell.collectionView.delegate = self
            cell.collectionView.register(StaffCardCell.self,
                                         forCellWithReuseIdentifier: StaffCardCell.reuseID)
            cell.collectionView.reloadData()
            return cell

        case .stats:
            guard let cell = tableView.dequeueReusableCell(
                withIdentifier: StatsCell.reuseID, for: indexPath) as? StatsCell else {
                return UITableViewCell()
            }
            cell.configure(scores: scoreDistribution, statuses: statusDistribution)
            return cell

        case .none:
            return UITableViewCell()
        }
    }
}

// MARK: - UITableViewDelegate

extension AnimeDetailViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        // Seg control is embedded in tableHeaderView (not a section header) so it scrolls
        // with content — matches Hayase where Tabs.Root is inside the scrollable div.
        return nil
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return 0
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        switch Section(rawValue: indexPath.section) {
        case .relations, .characters, .staff: return 160
        default: return UITableView.automaticDimension
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if Section(rawValue: indexPath.section) == .episodes {
            let epNumber = indexPath.row + 1
            openExtensionSearch(episode: epNumber)
        }
    }
}

// MARK: - UICollectionViewDataSource (embedded in HorizontalCardsCells)

extension AnimeDetailViewController: UICollectionViewDataSource {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        switch collectionView.tag {
        case 100: return relations.count
        case 200: return characters.count
        case 300: return staff.count
        default:  return 0
        }
    }

    func collectionView(_ collectionView: UICollectionView,
                        cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        switch collectionView.tag {
        case 100:
            guard let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: RelationCardCell.reuseID, for: indexPath) as? RelationCardCell
            else { return UICollectionViewCell() }
            cell.configure(with: relations[indexPath.item])
            return cell
        case 200:
            guard let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: CharacterCardCell.reuseID, for: indexPath) as? CharacterCardCell
            else { return UICollectionViewCell() }
            cell.configure(with: characters[indexPath.item])
            return cell
        case 300:
            guard let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: StaffCardCell.reuseID, for: indexPath) as? StaffCardCell
            else { return UICollectionViewCell() }
            cell.configure(with: staff[indexPath.item])
            return cell
        default:
            return UICollectionViewCell()
        }
    }
}

// MARK: - UICollectionViewDelegate (embedded)

extension AnimeDetailViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard collectionView.tag == 100 else { return }  // only relations are tappable
        let relation = relations[indexPath.item]
        guard let detailVC = storyboard?.instantiateViewController(
            withIdentifier: "AnimeDetailVC") as? AnimeDetailViewController else { return }
        detailVC.animeItem = relation.media
        navigationController?.pushViewController(detailVC, animated: true)
    }
}
