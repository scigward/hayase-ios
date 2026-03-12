//
//  AnimeDetailViewController.swift
//  TheAnimeTool
//
//  Shows full anime details (banner, cover, synopsis, badges) fetched from AniList,
//  plus a per-episode list from the ani.zip API. Matches Hayase's anime/[id]/+layout.svelte.
//

import UIKit
import SafariServices
import WebKit
import AVKit

// MARK: - AniZip episode model

struct AniZipEpisode {
    let number: Int
    let title: String       // English title, or "Episode N" fallback
    let overview: String
    let imageURL: String?
    let airDate: String?
    let runtime: Int        // minutes; 0 if unknown
    let rating: Double?     // from ani.zip "rating" field (e.g. "8.9256") — shown as ★ badge
    let isFiller: Bool      // from ani.zip "filler" field — yellow ring + Filler badge
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

    // Rating badge: absolute bottom-right of thumb, ★ + rating value
    // Mirrors Hayase EpisodesList: <Star class='text-yellow-400' />  {rating}
    private let ratingBadge: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 9.6)
        l.textColor = UIColor(white: 0.98, alpha: 1)
        l.backgroundColor = UIColor(white: 0.09, alpha: 0.8) // bg-neutral-900/80
        l.layer.cornerRadius = 3
        l.clipsToBounds = true
        l.isHidden = true
        return l
    }()

    // Filler badge: absolute bottom-right of card content, bg-yellow-400, rounded-tl
    // Mirrors Hayase: <div class='rounded-tl bg-yellow-400 absolute bottom-0 right-0'>Filler</div>
    private let fillerBadge: UILabel = {
        let l = UILabel()
        l.text = "  Filler  "
        l.font = .systemFont(ofSize: 9.6, weight: .bold)
        l.textColor = UIColor(white: 0.04, alpha: 1)  // text-primary-foreground (dark)
        l.backgroundColor = UIColor(red: 0.97, green: 0.81, blue: 0.00, alpha: 1) // yellow-400
        l.layer.cornerRadius = 4
        l.layer.maskedCorners = [.layerMinXMinYCorner] // rounded-tl only
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

        [thumbImageView, runtimeBadge, ratingBadge].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            cardView.addSubview($0)
        }
        fillerBadge.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(fillerBadge)

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

            // Rating badge: bottom-right of thumb (Hayase: absolute bottom-1 right-1)
            ratingBadge.trailingAnchor.constraint(equalTo: thumbImageView.trailingAnchor, constant: -4),
            ratingBadge.bottomAnchor.constraint(equalTo: thumbImageView.bottomAnchor, constant: -4),

            // Text stack: right of thumbnail, with 16pt padding
            textStack.leadingAnchor.constraint(equalTo: thumbImageView.trailingAnchor, constant: 16),
            textStack.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -8),
            textStack.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 12),
            textStack.bottomAnchor.constraint(lessThanOrEqualTo: cardView.bottomAnchor, constant: -8),

            // Progress bar height: h-0.5 = 2pt
            progressBar.heightAnchor.constraint(equalToConstant: 2),

            // Filler badge: absolute bottom-right of card (rounded-tl only — set via maskedCorners)
            fillerBadge.trailingAnchor.constraint(equalTo: cardView.trailingAnchor),
            fillerBadge.bottomAnchor.constraint(equalTo: cardView.bottomAnchor),
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

        // Rating badge: ★ icon (yellow) + rating value — Hayase EpisodesList.svelte
        if let rating = episode.rating {
            let ratingStr = String(format: "%.2f", rating)
            let padded = NSMutableAttributedString(string: " ", attributes: [.font: UIFont.systemFont(ofSize: 9.6)])
            padded.append(NSAttributedString(string: "★ ", attributes: [
                .foregroundColor: UIColor(red: 0.97, green: 0.81, blue: 0.00, alpha: 1), // yellow-400
                .font: UIFont.systemFont(ofSize: 9.6)
            ]))
            padded.append(NSAttributedString(string: "\(ratingStr) ", attributes: [
                .foregroundColor: UIColor(white: 0.98, alpha: 1),
                .font: UIFont.systemFont(ofSize: 9.6)
            ]))
            ratingBadge.attributedText = padded
            ratingBadge.isHidden = false
        } else {
            ratingBadge.isHidden = true
        }

        // Filler: yellow ring (ring-yellow-400 ring-1) + "Filler" badge
        // Mirrors Hayase: filler && '!ring-yellow-400 ring-1' on card + <div class='rounded-tl bg-yellow-400'>Filler</div>
        if episode.isFiller {
            cardView.layer.borderWidth = 1
            cardView.layer.borderColor = UIColor(red: 0.97, green: 0.81, blue: 0.00, alpha: 1).cgColor // yellow-400
            fillerBadge.isHidden = false
        } else {
            cardView.layer.borderWidth = 0
            cardView.layer.borderColor = UIColor.clear.cgColor
            fillerBadge.isHidden = true
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
        ratingBadge.isHidden = true
        fillerBadge.isHidden = true
        cardView.layer.borderWidth = 0
        cardView.layer.borderColor = UIColor.clear.cgColor
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

        // Banner gradient: transparent top-30% → black/0.85 at bottom (mirrors Hayase mobile banner-gr-sm)
        // Hayase: radial-gradient(75% 65% at 50% 34.97%, rgba(0,0,0,0.16) 30.56%, rgba(0,0,0,1) 100%)
        // Approximated as linear top→bottom starting clear at 30% → black/85 at 100%
        bannerGradientLayer.colors = [UIColor.clear.cgColor, UIColor.black.withAlphaComponent(0.85).cgColor]
        bannerGradientLayer.locations = [0.3, 1.0]

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

        // Banner image: AniList bannerImage → coverURL fallback.
        // ani.zip Fanart (TVDB-sourced) is fetched asynchronously in fetchEpisodes()
        // and applied via updateBanner(from:) — matching Hayase's banner.svelte desktop logic.
        loadImage(from: item.bannerURL ?? item.coverURL, into: bannerImageView, task: &bannerImageTask)
        loadImage(from: item.coverURL, into: coverImageView, task: &coverImageTask)
    }

    /// Called after ani.zip episodes fetch if a Fanart/Poster image is found.
    /// Matches Hayase banner.svelte: `metadata?.images?.find(i => i.coverType === 'Fanart')?.url`
    func updateBanner(from urlString: String) {
        loadImage(from: urlString, into: bannerImageView, task: &bannerImageTask)
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

// MARK: - HTabBar
// Custom horizontal tab bar matching Hayase's tabs-list.svelte shape exactly.
// Container: bg-muted (#27272a), rounded-lg (8pt), p-1 (4pt padding).
// Each tab: rounded-md (6pt), active = accent bg + contrast text, inactive = muted text.
// Shape is NOT a pill — iOS UISegmentedControl has cornerRadius = height/2 (pill).
// HTabBar uses cornerRadius = 8 (rounded-lg) on container, 6 (rounded-md) on tabs.

private final class HTabBar: UIView {
    var onChange: ((Int) -> Void)?
    var selectedIndex: Int = 0 { didSet { updateSelection() } }
    var accentColor: UIColor = UIColor(white: 0.98, alpha: 1) { didSet { updateSelection() } }

    private let scrollView: UIScrollView = {
        let sv = UIScrollView()
        sv.showsHorizontalScrollIndicator = false
        sv.bounces = false
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()
    private let stack: UIStackView = {
        let sv = UIStackView()
        sv.axis = .horizontal
        sv.spacing = 2
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()
    private var buttons: [UIButton] = []

    init(titles: [String]) {
        super.init(frame: .zero)
        // bg-muted = #27272a (neutral-800)
        backgroundColor = UIColor(red: 0.153, green: 0.153, blue: 0.165, alpha: 1)
        layer.cornerRadius = 8   // rounded-lg
        clipsToBounds = true

        addSubview(scrollView)
        scrollView.addSubview(stack)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor, constant: 4),       // p-1
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),

            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stack.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),
        ])

        for (i, title) in titles.enumerated() {
            let btn = UIButton(type: .system)
            btn.setTitle(title, for: .normal)
            btn.titleLabel?.font = .systemFont(ofSize: 13, weight: .medium)
            btn.contentEdgeInsets = UIEdgeInsets(top: 4, left: 12, bottom: 4, right: 12)
            btn.layer.cornerRadius = 6   // rounded-md
            btn.clipsToBounds = true
            btn.tag = i
            btn.addTarget(self, action: #selector(tabTapped(_:)), for: .touchUpInside)
            stack.addArrangedSubview(btn)
            buttons.append(btn)
        }
        updateSelection()
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func tabTapped(_ sender: UIButton) {
        selectedIndex = sender.tag
        onChange?(sender.tag)
    }

    private func updateSelection() {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
        accentColor.getRed(&r, green: &g, blue: &b, alpha: nil)
        let luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
        let contrastColor: UIColor = luminance > 0.5 ? UIColor(white: 0.04, alpha: 1) : .white
        for (i, btn) in buttons.enumerated() {
            if i == selectedIndex {
                btn.backgroundColor = accentColor
                btn.setTitleColor(contrastColor, for: .normal)
            } else {
                btn.backgroundColor = .clear
                btn.setTitleColor(UIColor(white: 0.55, alpha: 1), for: .normal) // text-muted-foreground
            }
        }
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

    // Threads (AniList forum) and Themes (animethemes.moe)
    private var threads: [AniListThread] = []
    private var themes: [AnimeTheme] = []
    private var threadsLoading = false
    private var themesLoading = false

    // Active tab for the segmented control (Episodes | Relations | Threads | Themes)
    private var activeSection: Section = .episodes

    // Custom HTabBar — replaces UISegmentedControl.
    // Shape: bg-muted container rounded-lg (8pt), tabs rounded-md (6pt). NOT a pill.
    // Position: full-width with 16pt horizontal inset (reverted from centered).
    private lazy var tabBar: HTabBar = {
        let bar = HTabBar(titles: ["Episodes", "Relations", "Threads", "Themes"])
        bar.onChange = { [weak self] index in
            self?.tabChanged(to: index)
        }
        bar.translatesAutoresizingMaskIntoConstraints = false
        return bar
    }()

    private lazy var tabBarContainer: UIView = {
        let v = UIView()
        v.backgroundColor = UIColor(white: 0.04, alpha: 1) // --background dark
        tabBar.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(tabBar)
        // Full-width tab bar with 16pt inset on each side.
        NSLayoutConstraint.activate([
            tabBar.topAnchor.constraint(equalTo: v.topAnchor, constant: 8),
            tabBar.bottomAnchor.constraint(equalTo: v.bottomAnchor, constant: -8),
            tabBar.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 16),
            tabBar.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -16),
            tabBar.heightAnchor.constraint(equalToConstant: 36), // h-9 = 36pt
        ])
        return v
    }()

    // Section indices — exactly mirrors Hayase +page.svelte tabs:
    // Episodes | Relations | Threads | Themes  (NO Characters, Staff, Stats)
    private enum Section: Int, CaseIterable {
        case episodes = 0, relations, threads, themes
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
            // Hayase +page.svelte: data-[state=active]:bg-custom data-[state=active]:text-contrast
            // Apply coverImage.color as the active tab tint color.
            if let accent = ExtensionSearchViewController.uiColor(fromHex: item.coverColor) {
                tabBar.accentColor = accent
            }
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

        // Wrap AnimeInfoHeaderView + tabBarContainer in one container so the tab bar
        // scrolls WITH the content (Hayase: Tabs.Root is inside the scrollable div, not sticky).
        let container = UIView()
        container.backgroundColor = .clear
        headerView.translatesAutoresizingMaskIntoConstraints = false
        tabBarContainer.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(headerView)
        container.addSubview(tabBarContainer)
        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: container.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            tabBarContainer.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            tabBarContainer.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            tabBarContainer.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            tabBarContainer.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        // 600 is a placeholder height — sizeHeaderView() corrects it in viewDidLayoutSubviews
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
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

            let episodesDict = json["episodes"] as? [String: Any] ?? [:]
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
                let runtime = (info["length"] as? NSNumber)?.intValue ?? (info["runtime"] as? NSNumber)?.intValue ?? 0
                // Rating: ani.zip returns it as a String ("8.9256") or Number
                let ratingRaw = info["rating"]
                let rating: Double? = (ratingRaw as? NSNumber)?.doubleValue
                    ?? (ratingRaw as? String).flatMap(Double.init)
                // isFiller is set after fetching ThaUnknown/filler-scrape/master/filler.json
                parsed.append(AniZipEpisode(number: num, title: title, overview: overview,
                                            imageURL: imageURL, airDate: airDate, runtime: runtime,
                                            rating: rating, isFiller: false))
            }
            parsed.sort { $0.number < $1.number }

            // Hayase banner.svelte (desktop): episodesCached(id) → images.find(Fanart)?.url
            // If ani.zip provides a Fanart (TVDB-sourced landscape) or Poster image,
            // use it as the banner instead of AniList's bannerImage.
            var anizipBannerURL: String? = nil
            if let imagesArray = json["images"] as? [[String: Any]] {
                let fanart = imagesArray.first(where: { ($0["coverType"] as? String) == "Fanart" })?["url"] as? String
                let poster  = imagesArray.first(where: { ($0["coverType"] as? String) == "Poster"  })?["url"] as? String
                anizipBannerURL = fanart ?? poster
            }

            // Fetch filler data from ThaUnknown/filler-scrape (exact Hayase match):
            // extensions.ts: fetch('https://raw.githubusercontent.com/ThaUnknown/filler-scrape/master/filler.json')
            //                filler: !!fillerEpisodes[media.id]?.includes(episode)
            AnimeDetailViewController.loadFillerSet(for: id) { fillerSet in
                let finalEpisodes = parsed.map { ep in
                    AniZipEpisode(number: ep.number, title: ep.title, overview: ep.overview,
                                  imageURL: ep.imageURL, airDate: ep.airDate, runtime: ep.runtime,
                                  rating: ep.rating, isFiller: fillerSet.contains(ep.number))
                }
                DispatchQueue.main.async { [weak self] in
                    self?.episodes = finalEpisodes
                    self?.tableView.reloadSections(IndexSet(integer: Section.episodes.rawValue), with: .fade)
                    if let bannerURL = anizipBannerURL {
                        self?.headerView.updateBanner(from: bannerURL)
                    }
                }
            }
        }
        episodeFetchTask?.resume()
    }

    // MARK: - Filler cache (ThaUnknown/filler-scrape)
    // Mirrors Hayase extensions.ts:
    //   fetch('https://raw.githubusercontent.com/ThaUnknown/filler-scrape/master/filler.json')
    //   fillerEpisodes[media.id]?.includes(episode)
    // The JSON is { "anilistId": [fillerEpNumber, ...] }

    private static var _fillerMap: [Int: Set<Int>] = [:]
    private static var _fillerMapLoaded = false
    private static var _fillerMapCallbacks: [([Int: Set<Int>]) -> Void] = []
    private static let _fillerQueue = DispatchQueue(label: "com.nyais.fillerCache")

    private static func loadFillerSet(for anilistId: Int, completion: @escaping (Set<Int>) -> Void) {
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

    // MARK: - Fetch relations (AniList detail query)

    private func fetchRelationsAndCharacters() {
        let id: Int?
        if let entity = animeEntity { id = entity.animeAnilistId?.intValue }
        else { id = animeItem?.id }
        guard let anilistId = id else { return }

        AnimeService.sharedAnimeService.fetchDetailForItem(id: anilistId) { [weak self] relations, _ in
            guard let self = self else { return }
            self.relations = relations
            if !relations.isEmpty {
                self.tableView.reloadSections(IndexSet(integer: Section.relations.rawValue), with: .fade)
            }
        }
    }

    // MARK: - Tab bar

    private func tabChanged(to index: Int) {
        guard let sec = Section(rawValue: index) else { return }
        activeSection = sec
        tableView.reloadSections(IndexSet(integersIn: 0..<Section.allCases.count), with: .automatic)
        // Lazy-fetch threads/themes on first tap
        if sec == .threads && threads.isEmpty && !threadsLoading { fetchThreads() }
        if sec == .themes  && themes.isEmpty  && !themesLoading  { fetchThemes()  }
    }

    // MARK: - Threads (AniList forum)

    private func fetchThreads() {
        guard let id = animeItem?.id else { return }
        threadsLoading = true
        tableView.reloadSections(IndexSet(integer: Section.threads.rawValue), with: .none)

        let query = """
        query($id:Int){Page(perPage:20){threads(mediaCategoryId:$id,sort:CREATED_AT_DESC){id title viewCount replyCount likeCount isLocked createdAt user{name avatar{large}} categories{id name}}}}
        """
        let body: [String: Any] = ["query": query, "variables": ["id": id]]
        guard let data = try? JSONSerialization.data(withJSONObject: body),
              let url = URL(string: "https://graphql.anilist.co") else { return }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = data
        URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
            guard let self, let data else { return }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let page = ((json["data"] as? [String: Any])?["Page"] as? [String: Any]),
               let rawThreads = page["threads"] as? [[String: Any]] {
                let parsed = rawThreads.compactMap { AniListThread(dict: $0) }
                DispatchQueue.main.async {
                    self.threads = parsed
                    self.threadsLoading = false
                    if self.activeSection == .threads {
                        self.tableView.reloadSections(IndexSet(integer: Section.threads.rawValue), with: .fade)
                    }
                }
            } else {
                DispatchQueue.main.async { self.threadsLoading = false }
            }
        }.resume()
    }

    // MARK: - Themes (animethemes.moe)

    private func fetchThemes() {
        guard let id = animeItem?.id else { return }
        themesLoading = true
        tableView.reloadSections(IndexSet(integer: Section.themes.rawValue), with: .none)

        // Build URL using URLComponents so [brackets] are percent-encoded correctly.
        // Hayase uses ky (fetch library) which encodes filter[external_id] → filter%5Bexternal_id%5D.
        // URL(string:) with literal brackets may produce a valid NSURL on iOS but the
        // server can silently ignore the unencoded filter params → same result for every anime.
        var comps = URLComponents(string: "https://api.animethemes.moe/anime")!
        comps.queryItems = [
            URLQueryItem(name: "filter[external_id]", value: "\(id)"),
            URLQueryItem(name: "filter[site]",        value: "AniList"),
            URLQueryItem(name: "include",             value: "animethemes.song.artists,animethemes.animethemeentries.videos"),
        ]
        // percentEncodedQuery: URLComponents encodes brackets as %5B / %5D automatically
        // via queryItems setter — exactly what the animethemes.moe API expects.
        guard let url = comps.url else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let self, let data else { return }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let animes = json["anime"] as? [[String: Any]],
               let first = animes.first,
               let rawThemes = first["animethemes"] as? [[String: Any]] {
                let parsed = rawThemes.compactMap { AnimeTheme(dict: $0) }
                DispatchQueue.main.async {
                    self.themes = parsed
                    self.themesLoading = false
                    if self.activeSection == .themes {
                        self.tableView.reloadSections(IndexSet(integer: Section.themes.rawValue), with: .fade)
                    }
                }
            } else {
                DispatchQueue.main.async { self.themesLoading = false }
            }
        }.resume()
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
        case .episodes:  return activeSection == .episodes  ? episodes.count : 0
        case .relations: return (activeSection == .relations && !relations.isEmpty) ? 1 : 0
        case .threads:
            if activeSection != .threads { return 0 }
            return threadsLoading ? 1 : max(threads.count, 1)  // 1 for loading/empty state
        case .themes:
            if activeSection != .themes { return 0 }
            return themesLoading ? 1 : max(themes.count, 1)
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

        case .threads:
            let cell = makeThreadCell(for: indexPath)
            return cell

        case .themes:
            let cell = makeThemeCell(for: indexPath)
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
        case .relations:          return 160
        case .threads, .themes:   return UITableView.automaticDimension
        default:                  return UITableView.automaticDimension
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch Section(rawValue: indexPath.section) {
        case .episodes:
            openExtensionSearch(episode: indexPath.row + 1)
        case .threads:
            guard !threadsLoading, !threads.isEmpty else { return }
            let thread = threads[indexPath.row]
            let threadVC = ThreadDetailViewController(threadID: thread.id, title: thread.title)
            navigationController?.pushViewController(threadVC, animated: true)
        case .themes:
            guard !themesLoading, !themes.isEmpty else { return }
            let theme = themes[indexPath.row]
            if let urlStr = theme.entries.first?.videoURL, let url = URL(string: urlStr) {
                present(SFSafariViewController(url: url), animated: true)
            }
        default: break
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

// MARK: - Thread & Theme data models

struct AniListThread {
    let id: Int
    let title: String
    let viewCount: Int
    let replyCount: Int
    let likeCount: Int
    let isLocked: Bool
    let createdAt: TimeInterval
    let userName: String?
    let avatarURL: String?
    let categories: [String]

    init?(dict: [String: Any]) {
        guard let id = dict["id"] as? Int else { return nil }
        self.id = id
        self.title = dict["title"] as? String ?? "Thread \(id)"
        self.viewCount = dict["viewCount"] as? Int ?? 0
        self.replyCount = dict["replyCount"] as? Int ?? 0
        self.likeCount = dict["likeCount"] as? Int ?? 0
        self.isLocked = dict["isLocked"] as? Bool ?? false
        self.createdAt = dict["createdAt"] as? TimeInterval ?? 0
        let user = dict["user"] as? [String: Any]
        self.userName = user?["name"] as? String
        let avatar = user?["avatar"] as? [String: Any]
        self.avatarURL = avatar?["large"] as? String
        let cats = dict["categories"] as? [[String: Any]] ?? []
        self.categories = cats.compactMap { $0["name"] as? String }.filter { $0 != "Anime" }
    }

    var sinceString: String {
        let diff = Date().timeIntervalSince1970 - createdAt
        switch diff {
        case ..<60:        return "just now"
        case ..<3600:      return "\(Int(diff/60))m ago"
        case ..<86400:     return "\(Int(diff/3600))h ago"
        case ..<2592000:   return "\(Int(diff/86400))d ago"
        default:           return "\(Int(diff/2592000))mo ago"
        }
    }
}

struct AnimeThemeEntry {
    let version: Int
    let episodes: String
    let videoURL: String?
}

struct AnimeTheme {
    let type: String    // "OP", "ED" + number e.g. "OP1", "ED2"
    let songTitle: String
    let artists: String
    let entries: [AnimeThemeEntry]

    init?(dict: [String: Any]) {
        guard let slug = dict["slug"] as? String else { return nil }
        self.type = slug.uppercased()
        let song = dict["song"] as? [String: Any]
        self.songTitle = song?["title"] as? String ?? "Unknown"
        let artistArr = song?["artists"] as? [[String: Any]] ?? []
        self.artists = artistArr.compactMap { $0["name"] as? String }.joined(separator: ", ")
        let rawEntries = dict["animethemeentries"] as? [[String: Any]] ?? []
        self.entries = rawEntries.compactMap { e -> AnimeThemeEntry? in
            let ver = e["version"] as? Int ?? 1
            let eps = e["episodes"] as? String ?? ""
            let videos = e["videos"] as? [[String: Any]] ?? []
            let link = videos.last?["link"] as? String
            return AnimeThemeEntry(version: ver, episodes: eps, videoURL: link)
        }
    }
}

// MARK: - Thread & Theme cell builders

extension AnimeDetailViewController {

    private func makeEmptyStateCell(text: String, loading: Bool) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.backgroundColor = .clear
        cell.selectionStyle = .none
        let label = UILabel()
        label.text = loading ? "Loading…" : text
        label.textColor = UIColor(white: loading ? 0.7 : 0.5, alpha: 1)
        label.font = .systemFont(ofSize: 14)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        cell.contentView.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: cell.contentView.centerXAnchor),
            label.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 40),
            label.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -40),
        ])
        return cell
    }

    func makeThreadCell(for indexPath: IndexPath) -> UITableViewCell {
        if threadsLoading || threads.isEmpty {
            return makeEmptyStateCell(
                text: "No threads found.",
                loading: threadsLoading)
        }
        let thread = threads[indexPath.row]
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.backgroundColor = .clear
        cell.selectionStyle = .default

        // bg-neutral-950 card
        let card = UIView()
        card.backgroundColor = UIColor(white: 0.039, alpha: 1)
        card.layer.cornerRadius = 8
        card.translatesAutoresizingMaskIntoConstraints = false
        cell.contentView.addSubview(card)

        // Title
        let titleLabel = UILabel()
        titleLabel.text = thread.title
        titleLabel.font = .systemFont(ofSize: 12.8, weight: .bold)
        titleLabel.textColor = .white
        titleLabel.numberOfLines = 1
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        // Stats row: ♥ likes  👁 views  💬 replies
        let statsLabel = UILabel()
        statsLabel.text = "♥ \(thread.likeCount)  👁 \(thread.viewCount)  💬 \(thread.replyCount)\(thread.isLocked ? "  🔒" : "")"
        statsLabel.font = .systemFont(ofSize: 9.6)
        statsLabel.textColor = UIColor(white: 0.6, alpha: 1)
        statsLabel.translatesAutoresizingMaskIntoConstraints = false

        // Footer: time + categories
        let footerLabel = UILabel()
        var footerParts = [thread.sinceString]
        if let name = thread.userName { footerParts.append("by \(name)") }
        footerLabel.text = footerParts.joined(separator: " · ")
        footerLabel.font = .systemFont(ofSize: 9.6)
        footerLabel.textColor = UIColor(white: 0.5, alpha: 1)
        footerLabel.translatesAutoresizingMaskIntoConstraints = false

        // Category badges
        let accentColor = animeItem.flatMap { item in
            ExtensionSearchViewController.uiColor(fromHex: item.coverColor ?? "") } ?? UIColor(white: 0.15, alpha: 1)
        let badgeStack = UIStackView()
        badgeStack.axis = .horizontal
        badgeStack.spacing = 4
        badgeStack.translatesAutoresizingMaskIntoConstraints = false
        for cat in thread.categories.prefix(3) {
            let badge = UILabel()
            badge.text = cat
            badge.font = .systemFont(ofSize: 9.6, weight: .bold)
            badge.textColor = ExtensionSearchViewController.luminanceContrastColor(for: accentColor)
            badge.backgroundColor = accentColor
            badge.layer.cornerRadius = 4
            badge.clipsToBounds = true
            badge.textAlignment = .center
            let pad: CGFloat = 4
            badge.layoutMargins = UIEdgeInsets(top: pad, left: pad*2, bottom: pad, right: pad*2)
            badge.translatesAutoresizingMaskIntoConstraints = false
            badgeStack.addArrangedSubview(badge)
        }

        card.addSubview(titleLabel)
        card.addSubview(statsLabel)
        card.addSubview(footerLabel)
        card.addSubview(badgeStack)
        statsLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 4),
            card.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -4),
            card.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: 16),
            card.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor, constant: -16),

            titleLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            titleLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: statsLabel.leadingAnchor, constant: -8),

            statsLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            statsLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),

            footerLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),
            footerLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
            footerLabel.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12),

            badgeStack.centerYAnchor.constraint(equalTo: footerLabel.centerYAnchor),
            badgeStack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
        ])
        return cell
    }

    func makeThemeCell(for indexPath: IndexPath) -> UITableViewCell {
        if themesLoading || themes.isEmpty {
            return makeEmptyStateCell(
                text: "No themes found.",
                loading: themesLoading)
        }
        let theme = themes[indexPath.row]
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.backgroundColor = .clear
        cell.selectionStyle = .default

        // bg-neutral-950 card
        let card = UIView()
        card.backgroundColor = UIColor(white: 0.039, alpha: 1)
        card.layer.cornerRadius = 8
        card.translatesAutoresizingMaskIntoConstraints = false
        cell.contentView.addSubview(card)

        // Type badge (OP1, ED2 …)
        let typeLabel = UILabel()
        typeLabel.text = theme.type
        typeLabel.font = .systemFont(ofSize: 11, weight: .bold)
        typeLabel.textColor = UIColor(white: 0.7, alpha: 1)
        typeLabel.translatesAutoresizingMaskIntoConstraints = false

        // Song title
        let songLabel = UILabel()
        songLabel.text = theme.songTitle
        songLabel.font = .systemFont(ofSize: 14, weight: .bold)
        songLabel.textColor = .white
        songLabel.numberOfLines = 1
        songLabel.translatesAutoresizingMaskIntoConstraints = false

        // Artists
        let artistLabel = UILabel()
        artistLabel.text = theme.artists.isEmpty ? "" : "by \(theme.artists)"
        artistLabel.font = .systemFont(ofSize: 11)
        artistLabel.textColor = UIColor(white: 0.6, alpha: 1)
        artistLabel.numberOfLines = 1
        artistLabel.translatesAutoresizingMaskIntoConstraints = false

        // Play button (▶ bg-custom)
        let accentColor = animeItem.flatMap { ExtensionSearchViewController.uiColor(fromHex: $0.coverColor ?? "") }
            ?? UIColor(red: 0.24, green: 0.71, blue: 0.95, alpha: 1)
        let playBtn = UIButton(type: .system)
        playBtn.setTitle("▶", for: .normal)
        playBtn.titleLabel?.font = .systemFont(ofSize: 13, weight: .bold)
        playBtn.setTitleColor(ExtensionSearchViewController.luminanceContrastColor(for: accentColor), for: .normal)
        playBtn.backgroundColor = accentColor
        playBtn.layer.cornerRadius = 14
        playBtn.translatesAutoresizingMaskIntoConstraints = false

        // Episodes line (e.g. "v1 · Episodes 1-12")
        let firstEntry = theme.entries.first
        let epLabel = UILabel()
        epLabel.text = firstEntry.map { "v\($0.version) · Episodes \($0.episodes)" } ?? ""
        epLabel.font = .systemFont(ofSize: 10)
        epLabel.textColor = UIColor(white: 0.5, alpha: 1)
        epLabel.translatesAutoresizingMaskIntoConstraints = false

        card.addSubview(typeLabel)
        card.addSubview(songLabel)
        card.addSubview(artistLabel)
        card.addSubview(epLabel)
        card.addSubview(playBtn)

        // Store videoURL tag via associated object — simpler: use a closure via objc
        if let urlStr = firstEntry?.videoURL {
            playBtn.addTarget(self, action: #selector(themePlayTapped(_:)), for: .touchUpInside)
            objc_setAssociatedObject(playBtn, &themeURLKey, urlStr, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }

        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 4),
            card.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -4),
            card.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: 16),
            card.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor, constant: -16),

            typeLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            typeLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
            typeLabel.widthAnchor.constraint(equalToConstant: 40),

            songLabel.leadingAnchor.constraint(equalTo: typeLabel.trailingAnchor, constant: 4),
            songLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
            songLabel.trailingAnchor.constraint(equalTo: playBtn.leadingAnchor, constant: -8),

            artistLabel.leadingAnchor.constraint(equalTo: typeLabel.trailingAnchor, constant: 4),
            artistLabel.topAnchor.constraint(equalTo: songLabel.bottomAnchor, constant: 4),
            artistLabel.trailingAnchor.constraint(equalTo: playBtn.leadingAnchor, constant: -8),

            epLabel.leadingAnchor.constraint(equalTo: typeLabel.trailingAnchor, constant: 4),
            epLabel.topAnchor.constraint(equalTo: artistLabel.bottomAnchor, constant: 6),
            epLabel.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14),

            playBtn.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            playBtn.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            playBtn.widthAnchor.constraint(equalToConstant: 28),
            playBtn.heightAnchor.constraint(equalToConstant: 28),
        ])
        return cell
    }

    @objc private func themePlayTapped(_ sender: UIButton) {
        guard let urlStr = objc_getAssociatedObject(sender, &themeURLKey) as? String,
              let url = URL(string: urlStr) else { return }
        // animethemes.moe videos are WebM (VP9). AVPlayer doesn't support WebM natively,
        // but WKWebView/WebKit on iOS 16+ does (VP9 support added in WebKit).
        // We load the video URL in a WKWebView with a minimal HTML5 <video> page.
        let player = ThemePlayerViewController(videoURL: url)
        present(player, animated: true)
    }
}

private var themeURLKey = "themeURL"

// MARK: - ThemePlayerViewController
// Plays animethemes.moe WebM/VP9 videos inside the app via WKWebView.
// WKWebView supports VP9/WebM on iOS 16+ (same engine as Safari).
// Displayed as a fullscreen modal with dark background and native controls.

final class ThemePlayerViewController: UIViewController {

    private let videoURL: URL
    private var webView: WKWebView!

    init(videoURL: URL) {
        self.videoURL = videoURL
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
        modalTransitionStyle = .crossDissolve
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        // Close button — top-left X
        let closeBtn = UIButton(type: .system)
        closeBtn.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        closeBtn.tintColor = .white
        closeBtn.contentVerticalAlignment = .fill
        closeBtn.contentHorizontalAlignment = .fill
        closeBtn.translatesAutoresizingMaskIntoConstraints = false
        closeBtn.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        view.addSubview(closeBtn)
        NSLayoutConstraint.activate([
            closeBtn.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            closeBtn.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            closeBtn.widthAnchor.constraint(equalToConstant: 32),
            closeBtn.heightAnchor.constraint(equalToConstant: 32),
        ])

        // WKWebView with media playback allowed
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []   // autoplay
        webView = WKWebView(frame: .zero, configuration: config)
        webView.backgroundColor = .black
        webView.isOpaque = false
        webView.scrollView.isScrollEnabled = false
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.insertSubview(webView, belowSubview: closeBtn)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 52),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
        ])

        // HTML page with full-width <video> element.
        // Uses controls + autoplay. Background black to match the sheet.
        // The src is injected as a JS string to avoid any URL-escaping issues.
        let escapedURL = videoURL.absoluteString
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
        <meta name='viewport' content='width=device-width, initial-scale=1'>
        <style>
          * { margin:0; padding:0; box-sizing:border-box; }
          html, body { background:#000; height:100%; }
          video {
            width:100%; height:100%; object-fit:contain;
            display:block; background:#000;
          }
        </style>
        </head>
        <body>
        <video controls autoplay playsinline
               src="\(escapedURL)">
          Your browser does not support this video format.
        </video>
        </body>
        </html>
        """
        webView.loadHTMLString(html, baseURL: URL(string: "https://animethemes.moe"))
    }

    @objc private func closeTapped() {
        dismiss(animated: true)
    }


}
