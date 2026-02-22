//
//  AnimeDetailViewController.swift
//  TheAnimeTool
//
//  Shows full anime details (banner, cover, synopsis, badges) fetched from AniList via CoreData,
//  plus a per-episode list from the ani.zip API. Tapping "Find Torrents" pushes
//  TorrentListViewController with a pre-populated nyaa.si search for this anime.
//

import UIKit

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
// Matches Hayase's EpisodesList.svelte:
// thumbnail fills ~38% of cell width at 16:9 aspect ratio, dark card background,
// episode number + title in bold, summary text smaller, runtime + airdate meta.

private final class EpisodeCell: UITableViewCell {
    static let reuseID = "AniDetailEpCell"

    private let cardView: UIView = {
        let v = UIView()
        v.backgroundColor = .secondarySystemBackground
        v.layer.cornerRadius = 8
        v.clipsToBounds = true
        return v
    }()

    private let thumbImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.backgroundColor = .systemGray5
        return iv
    }()

    private let runtimeBadge: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 10, weight: .regular)
        l.textColor = .white
        l.backgroundColor = UIColor.black.withAlphaComponent(0.8)
        l.layer.cornerRadius = 3
        l.clipsToBounds = true
        l.isHidden = true
        return l
    }()

    private let numberLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 13, weight: .bold)
        l.textColor = .label
        l.numberOfLines = 1
        return l
    }()

    private let overviewLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 10)
        l.textColor = .secondaryLabel
        l.numberOfLines = 3
        return l
    }()

    private let metaLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 10)
        l.textColor = .tertiaryLabel
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

        [cardView].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview($0)
        }
        [thumbImageView, runtimeBadge].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            cardView.addSubview($0)
        }

        let textStack = UIStackView(arrangedSubviews: [numberLabel, overviewLabel, metaLabel])
        textStack.axis = .vertical
        textStack.spacing = 4
        textStack.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(textStack)

        NSLayoutConstraint.activate([
            // Card fills content view with 8pt margin
            cardView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 6),
            cardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            cardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            cardView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6),

            // Thumbnail: 38% width, 16:9 aspect ratio
            thumbImageView.topAnchor.constraint(equalTo: cardView.topAnchor),
            thumbImageView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),
            thumbImageView.bottomAnchor.constraint(equalTo: cardView.bottomAnchor),
            thumbImageView.widthAnchor.constraint(equalTo: cardView.widthAnchor, multiplier: 0.38),
            thumbImageView.heightAnchor.constraint(equalTo: thumbImageView.widthAnchor,
                                                    multiplier: 9.0 / 16.0),

            // Runtime badge: bottom-left of thumb
            runtimeBadge.leadingAnchor.constraint(equalTo: thumbImageView.leadingAnchor, constant: 4),
            runtimeBadge.bottomAnchor.constraint(equalTo: thumbImageView.bottomAnchor, constant: -4),

            // Text stack to the right of thumbnail
            textStack.leadingAnchor.constraint(equalTo: thumbImageView.trailingAnchor, constant: 12),
            textStack.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -12),
            textStack.centerYAnchor.constraint(equalTo: cardView.centerYAnchor),
            textStack.topAnchor.constraint(greaterThanOrEqualTo: cardView.topAnchor, constant: 10),
            textStack.bottomAnchor.constraint(lessThanOrEqualTo: cardView.bottomAnchor, constant: -10),
        ])
    }

    func configure(with episode: AniZipEpisode) {
        numberLabel.text = "\(episode.number). \(episode.title.isEmpty ? "Episode \(episode.number)" : episode.title)"
        overviewLabel.text = episode.overview
        overviewLabel.isHidden = episode.overview.isEmpty

        var meta: [String] = []
        if let date = episode.airDate { meta.append(date) }
        metaLabel.text = meta.joined(separator: " · ")
        metaLabel.isHidden = meta.isEmpty

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
    }
}

// MARK: - HorizontalCardsCell
// A UITableViewCell containing a horizontal UICollectionView.
// tag 100 → Relations, tag 200 → Characters.

private final class HorizontalCardsCell: UITableViewCell {
    static let relationsReuseID  = "HorizontalRelationsCell"
    static let charactersReuseID = "HorizontalCharactersCell"

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



private final class AnimeInfoHeaderView: UIView {
    var onFindTorrents: (() -> Void)?

    // Banner / cover images
    private let bannerImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.backgroundColor = .systemIndigo.withAlphaComponent(0.25)
        return iv
    }()

    private let bannerDimView: UIView = {
        // Simple dark overlay for readability instead of a gradient that needs
        // special handling for light/dark mode. Black at 45% works in both modes.
        let v = UIView()
        v.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        return v
    }()

    private let coverImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.backgroundColor = .systemGray5
        iv.layer.cornerRadius = 8
        iv.layer.borderColor = UIColor.systemBackground.cgColor
        iv.layer.borderWidth = 3
        return iv
    }()

    // Text labels
    private let titleLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 18, weight: .bold)
        l.textColor = .label
        l.numberOfLines = 3
        return l
    }()

    private let romajiLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 13)
        l.textColor = .secondaryLabel
        l.numberOfLines = 1
        return l
    }()

    private let badgesStack: UIStackView = {
        let sv = UIStackView()
        sv.axis = .horizontal
        sv.spacing = 6
        sv.alignment = .center
        return sv
    }()

    // Genre chips row — horizontal, scrollable
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
        sv.alwaysBounceHorizontal = true
        return sv
    }()

    private let descriptionLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 14)
        l.textColor = .secondaryLabel
        l.numberOfLines = 0
        return l
    }()

    private let findTorrentsButton: UIButton = {
        let b = UIButton(type: .system)
        b.setTitle("  Find Torrents on nyaa.si", for: .normal)
        b.setImage(UIImage(systemName: "arrow.down.circle.fill"), for: .normal)
        b.tintColor = .white
        b.backgroundColor = .systemIndigo
        b.titleLabel?.font = .boldSystemFont(ofSize: 16)
        b.contentEdgeInsets = UIEdgeInsets(top: 14, left: 20, bottom: 14, right: 20)
        b.layer.cornerRadius = 12
        b.layer.masksToBounds = true
        return b
    }()

    private var bannerImageTask: URLSessionDataTask?
    private var coverImageTask: URLSessionDataTask?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        findTorrentsButton.addTarget(self, action: #selector(findTorrentsTapped), for: .touchUpInside)

        // Genre scroll view contains genresStack
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

        // Outer stack: genres + desc + button with margins
        let bottomStack = UIStackView(arrangedSubviews: [genresScrollView, descriptionLabel, findTorrentsButton])
        bottomStack.axis = .vertical
        bottomStack.spacing = 16
        bottomStack.isLayoutMarginsRelativeArrangement = true
        bottomStack.layoutMargins = UIEdgeInsets(top: 16, left: 16, bottom: 24, right: 16)

        [bannerImageView, bannerDimView, coverImageView,
         titleLabel, romajiLabel, badgesStack, bottomStack].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }

        NSLayoutConstraint.activate([
            // Banner: full width, fixed height
            bannerImageView.topAnchor.constraint(equalTo: topAnchor),
            bannerImageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            bannerImageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            bannerImageView.heightAnchor.constraint(equalToConstant: 180),

            // Dim overlay covers the banner
            bannerDimView.topAnchor.constraint(equalTo: bannerImageView.topAnchor),
            bannerDimView.leadingAnchor.constraint(equalTo: bannerImageView.leadingAnchor),
            bannerDimView.trailingAnchor.constraint(equalTo: bannerImageView.trailingAnchor),
            bannerDimView.bottomAnchor.constraint(equalTo: bannerImageView.bottomAnchor),

            // Cover art: floats over the banner bottom edge (−60pt overlap)
            coverImageView.topAnchor.constraint(equalTo: bannerImageView.bottomAnchor, constant: -60),
            coverImageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            coverImageView.widthAnchor.constraint(equalToConstant: 90),
            coverImageView.heightAnchor.constraint(equalToConstant: 128),

            // Title: to the right of the cover image, just below banner
            titleLabel.topAnchor.constraint(equalTo: bannerImageView.bottomAnchor, constant: 10),
            titleLabel.leadingAnchor.constraint(equalTo: coverImageView.trailingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),

            // Romaji label
            romajiLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            romajiLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            romajiLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),

            // Badges row
            badgesStack.topAnchor.constraint(equalTo: romajiLabel.bottomAnchor, constant: 8),
            badgesStack.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            badgesStack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -16),
            badgesStack.bottomAnchor.constraint(lessThanOrEqualTo: coverImageView.bottomAnchor),

            // Genre scroll view: full-width, fixed 32pt height (chip height)
            genresScrollView.heightAnchor.constraint(equalToConstant: 32),

            // Bottom section (description + button): starts below cover image
            bottomStack.topAnchor.constraint(equalTo: coverImageView.bottomAnchor, constant: 12),
            bottomStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            bottomStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            bottomStack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @objc private func findTorrentsTapped() {
        onFindTorrents?()
    }

    func configure(with anime: Animes?) {
        guard let anime = anime else { return }

        let english = anime.animeTitleEnglish
        let romaji = anime.animeTitleJapanese
        titleLabel.text = english ?? romaji ?? "Unknown"

        if let eng = english, let rom = romaji, eng != rom {
            romajiLabel.text = rom
            romajiLabel.isHidden = false
        } else {
            romajiLabel.isHidden = true
        }

        // Populate badges
        badgesStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        if let score = anime.animeScore?.floatValue, score > 0 {
            badgesStack.addArrangedSubview(makeBadge(
                text: String(format: "★ %.0f%%", score),
                bg: .systemYellow, fg: .black))
        }
        if let status = anime.animeStatus {
            let text = status.replacingOccurrences(of: "_", with: " ").capitalized
            badgesStack.addArrangedSubview(makeBadge(text: text, bg: .systemGreen, fg: .white))
        }
        if let total = anime.animeTotalEps?.intValue, total > 0 {
            badgesStack.addArrangedSubview(makeBadge(text: "\(total) eps", bg: .systemIndigo, fg: .white))
        } else if let next = anime.animeNextEps?.intValue, next > 0 {
            badgesStack.addArrangedSubview(makeBadge(text: "Ep \(next) airing", bg: .systemBlue, fg: .white))
        }
        // Flexible spacer to left-align badges
        let spacer = UIView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        badgesStack.addArrangedSubview(spacer)

        // Genre chips (CoreData entities don't store genres, so hide the row)
        genresStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        genresScrollView.isHidden = true

        // Synopsis
        let desc = anime.animeDescription?.trimmingCharacters(in: .whitespacesAndNewlines)
        descriptionLabel.text = (desc?.isEmpty ?? true) ? "No synopsis available." : desc

        // Load images
        // animeImgS is repurposed to store the banner image URL; fall back to large cover
        loadImage(from: anime.animeImgS ?? anime.animeImgL ?? anime.animeImgM,
                  into: bannerImageView, task: &bannerImageTask)
        loadImage(from: anime.animeImgL ?? anime.animeImgM,
                  into: coverImageView, task: &coverImageTask)
    }

    func configure(with item: AnimeItem) {
        titleLabel.text = item.titleEnglish ?? item.titleRomaji ?? "Unknown"

        if let eng = item.titleEnglish, let rom = item.titleRomaji, eng != rom {
            romajiLabel.text = rom
            romajiLabel.isHidden = false
        } else {
            romajiLabel.isHidden = true
        }

        badgesStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        if let score = item.score, score > 0 {
            badgesStack.addArrangedSubview(makeBadge(
                text: String(format: "★ %.0f%%", score), bg: .systemYellow, fg: .black))
        }
        if let status = item.status {
            let text = status.replacingOccurrences(of: "_", with: " ").capitalized
            badgesStack.addArrangedSubview(makeBadge(text: text, bg: .systemGreen, fg: .white))
        }
        if let eps = item.episodes, eps > 0 {
            badgesStack.addArrangedSubview(makeBadge(text: "\(eps) eps", bg: .systemIndigo, fg: .white))
        }
        let spacer = UIView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        badgesStack.addArrangedSubview(spacer)

        // Genre chips
        genresStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for genre in item.genres.prefix(6) {
            genresStack.addArrangedSubview(makeGenreChip(text: genre))
        }
        genresScrollView.isHidden = item.genres.isEmpty

        // Synopsis from the section query (now included)
        let desc = item.description?.trimmingCharacters(in: .whitespacesAndNewlines)
        descriptionLabel.text = (desc?.isEmpty ?? true) ? "No synopsis available." : desc

        loadImage(from: item.bannerURL ?? item.coverURL, into: bannerImageView, task: &bannerImageTask)
        loadImage(from: item.coverURL, into: coverImageView, task: &coverImageTask)
    }

    private func makeBadge(text: String, bg: UIColor, fg: UIColor) -> UILabel {
        let l = UILabel()
        l.text = "  \(text)  "
        l.font = .systemFont(ofSize: 11, weight: .semibold)
        l.textColor = fg
        l.backgroundColor = bg
        l.layer.cornerRadius = 8
        l.clipsToBounds = true
        l.setContentHuggingPriority(.required, for: .horizontal)
        return l
    }

    private func makeGenreChip(text: String) -> UIView {
        let container = UIView()
        container.backgroundColor = .secondarySystemBackground
        container.layer.cornerRadius = 12
        container.layer.borderWidth = 1
        container.layer.borderColor = UIColor.separator.cgColor
        container.clipsToBounds = true

        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .label
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 6),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -6),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),
        ])
        container.setContentHuggingPriority(.required, for: .horizontal)
        return container
    }

    private func loadImage(from urlString: String?,
                           into imageView: UIImageView,
                           task: inout URLSessionDataTask?) {
        task?.cancel()
        task = nil
        guard let urlString = urlString, let url = URL(string: urlString) else { return }
        task = URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data = data, let img = UIImage(data: data) else { return }
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
    private var episodeFetchTask: URLSessionDataTask?

    // Section indices
    private enum Section: Int, CaseIterable {
        case episodes = 0, relations, characters
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = animeItem?.titleEnglish ?? animeItem?.titleRomaji
            ?? animeEntity?.animeTitleEnglish ?? animeEntity?.animeTitleJapanese
        navigationItem.largeTitleDisplayMode = .never
        view.backgroundColor = .systemBackground

        setupTableView()
        setupHeaderView()
        fetchEpisodes()
        fetchRelationsAndCharacters()
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
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 100
        tableView.separatorStyle = .none
        tableView.backgroundColor = .systemBackground
        view.addSubview(tableView)
    }

    private func setupHeaderView() {
        headerView = AnimeInfoHeaderView()
        if let item = animeItem {
            headerView.configure(with: item)
        } else {
            headerView.configure(with: animeEntity)
        }
        headerView.onFindTorrents = { [weak self] in
            self?.performSegue(withIdentifier: "showTorrentList", sender: nil)
        }
        headerView.frame = CGRect(x: 0, y: 0, width: tableView.frame.width, height: 600)
        tableView.tableHeaderView = headerView
    }

    private func sizeHeaderView() {
        guard let header = tableView.tableHeaderView, tableView.frame.width > 0 else { return }
        let targetSize = CGSize(width: tableView.frame.width,
                                height: UIView.layoutFittingCompressedSize.height)
        let height = header.systemLayoutSizeFitting(
            targetSize,
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel).height
        if abs(header.frame.height - height) > 1 {
            header.frame.size.height = height
            tableView.tableHeaderView = header
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

    // MARK: - Navigation

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        guard segue.identifier == "showTorrentList",
              let dest = segue.destination as? TorrentListViewController else { return }
        dest.animeEntity = animeEntity
        if animeEntity == nil, let item = animeItem {
            dest.animeTitleOverride = item.titleEnglish ?? item.titleRomaji
        }
    }
}

// MARK: - UITableViewDataSource

extension AnimeDetailViewController: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        return Section.allCases.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section) {
        case .episodes:  return episodes.count
        case .relations: return relations.isEmpty ? 0 : 1
        case .characters: return characters.isEmpty ? 0 : 1
        case .none: return 0
        }
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section) {
        case .episodes:  return episodes.isEmpty ? nil : "Episodes · \(episodes.count)"
        case .relations: return relations.isEmpty ? nil : "Relations"
        case .characters: return characters.isEmpty ? nil : "Characters"
        case .none: return nil
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch Section(rawValue: indexPath.section) {
        case .episodes:
            guard let cell = tableView.dequeueReusableCell(
                withIdentifier: EpisodeCell.reuseID, for: indexPath) as? EpisodeCell else {
                return UITableViewCell()
            }
            cell.configure(with: episodes[indexPath.row])
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

        case .none:
            return UITableViewCell()
        }
    }
}

// MARK: - UITableViewDelegate

extension AnimeDetailViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        switch Section(rawValue: indexPath.section) {
        case .relations, .characters: return 160
        default: return UITableView.automaticDimension
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if Section(rawValue: indexPath.section) == .episodes {
            performSegue(withIdentifier: "showTorrentList", sender: nil)
        }
    }
}

// MARK: - UICollectionViewDataSource (embedded in HorizontalCardsCells)

extension AnimeDetailViewController: UICollectionViewDataSource {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return collectionView.tag == 100 ? relations.count : characters.count
    }

    func collectionView(_ collectionView: UICollectionView,
                        cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        if collectionView.tag == 100 {
            guard let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: RelationCardCell.reuseID, for: indexPath) as? RelationCardCell
            else { return UICollectionViewCell() }
            cell.configure(with: relations[indexPath.item])
            return cell
        } else {
            guard let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: CharacterCardCell.reuseID, for: indexPath) as? CharacterCardCell
            else { return UICollectionViewCell() }
            cell.configure(with: characters[indexPath.item])
            return cell
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
