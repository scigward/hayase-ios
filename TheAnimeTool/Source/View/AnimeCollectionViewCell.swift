//
//  AnimeCollectionViewCell.swift
//  TheAnimeTool
//
//  Hayase-style poster card: cover image fills top, info bar below with title + meta.
//  Matches small.svelte (9.5rem × 13.5rem poster, title below, year+format metadata).
//

import UIKit

// MARK: - Shared Image Cache (internal so BrowseAnimeViewController can use it)

enum SharedImageCache {
    static let shared = NSCache<NSString, UIImage>()
}

// MARK: - AnimeCollectionViewCell

class AnimeCollectionViewCell: UICollectionViewCell {
    static let reuseID = "AnimeCell"

    private static let infoBarHeight: CGFloat = 50

    // MARK: Views

    /// Cover image fills the top ~76% of the cell (152:216 poster ratio → ~76%)
    private let coverImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.backgroundColor = UIColor.systemGray5
        return iv
    }()

    /// Dark info bar below cover — title + meta line
    private let infoView: UIView = {
        let v = UIView()
        v.backgroundColor = UIColor.secondarySystemBackground
        return v
    }()

    private let titleLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 11, weight: .bold)
        l.textColor = .label
        l.numberOfLines = 2
        return l
    }()

    private let metaLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 9, weight: .medium)
        l.textColor = .secondaryLabel
        l.numberOfLines = 1
        return l
    }()

    /// Score badge overlaid in the top-right corner of the cover
    private let scoreBadge: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 9, weight: .bold)
        l.textColor = .white
        l.textAlignment = .center
        l.backgroundColor = UIColor.black.withAlphaComponent(0.65)
        l.layer.cornerRadius = 7
        l.clipsToBounds = true
        return l
    }()

    // MARK: State

    private var currentURLString: String?
    private var imageTask: URLSessionDataTask?

    // MARK: Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    // MARK: Layout

    private func setup() {
        contentView.layer.cornerRadius = 8
        contentView.clipsToBounds = true
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.2
        layer.shadowRadius = 4
        layer.shadowOffset = CGSize(width: 0, height: 2)
        layer.masksToBounds = false

        [coverImageView, infoView, scoreBadge].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview($0)
        }
        [titleLabel, metaLabel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            infoView.addSubview($0)
        }

        NSLayoutConstraint.activate([
            // Cover fills top portion; info bar is pinned to bottom at 48pt
            coverImageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            coverImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            coverImageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            coverImageView.bottomAnchor.constraint(equalTo: infoView.topAnchor),

            infoView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            infoView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            infoView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            infoView.heightAnchor.constraint(equalToConstant: AnimeCollectionViewCell.infoBarHeight),

            // Title inside info view
            titleLabel.leadingAnchor.constraint(equalTo: infoView.leadingAnchor, constant: 7),
            titleLabel.trailingAnchor.constraint(equalTo: infoView.trailingAnchor, constant: -4),
            titleLabel.topAnchor.constraint(equalTo: infoView.topAnchor, constant: 5),

            // Meta line below title
            metaLabel.leadingAnchor.constraint(equalTo: infoView.leadingAnchor, constant: 7),
            metaLabel.trailingAnchor.constraint(equalTo: infoView.trailingAnchor, constant: -4),
            metaLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            metaLabel.bottomAnchor.constraint(lessThanOrEqualTo: infoView.bottomAnchor, constant: -4),

            // Score badge: top-right of cover
            scoreBadge.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 6),
            scoreBadge.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -6),
            scoreBadge.widthAnchor.constraint(greaterThanOrEqualToConstant: 30),
            scoreBadge.heightAnchor.constraint(equalToConstant: 16),
        ])
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: 8).cgPath
    }

    // MARK: - Helpers

    private func applyScore(_ score: Float) {
        if score > 0 {
            scoreBadge.text = String(format: " %.0f%% ", score)
            scoreBadge.isHidden = false
        } else {
            scoreBadge.isHidden = true
        }
    }

    private func loadCover(urlString: String) {
        currentURLString = urlString
        coverImageView.image = nil
        imageTask?.cancel()
        guard !urlString.isEmpty, let url = URL(string: urlString) else { return }
        if let cached = SharedImageCache.shared.object(forKey: urlString as NSString) {
            coverImageView.image = cached
            return
        }
        let captured = urlString
        imageTask = URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data = data, let image = UIImage(data: data) else { return }
            SharedImageCache.shared.setObject(image, forKey: captured as NSString)
            DispatchQueue.main.async {
                guard self?.currentURLString == captured else { return }
                UIView.transition(with: self?.coverImageView ?? UIImageView(),
                                  duration: 0.25, options: .transitionCrossDissolve,
                                  animations: { self?.coverImageView.image = image })
            }
        }
        imageTask?.resume()
    }

    private static func metaString(status: String?, episodes: Int?) -> String {
        var parts: [String] = []
        if let s = status {
            switch s {
            case "RELEASING": parts.append("Airing")
            case "FINISHED": parts.append("Finished")
            case "NOT_YET_RELEASED": parts.append("Upcoming")
            default: parts.append(s.capitalized)
            }
        }
        if let e = episodes, e > 0 { parts.append("\(e) eps") }
        return parts.joined(separator: " · ")
    }

    // MARK: Configuration

    func configure(with anime: Animes) {
        titleLabel.text = anime.animeTitleEnglish ?? anime.animeTitleJapanese ?? "Unknown"
        applyScore(anime.animeScore?.floatValue ?? 0)
        let status = anime.animeStatus
        let eps = anime.animeTotalEps?.intValue
        metaLabel.text = AnimeCollectionViewCell.metaString(status: status, episodes: eps)
        loadCover(urlString: anime.animeImgL ?? anime.animeImgM ?? "")
    }

    func configure(with item: AnimeItem) {
        titleLabel.text = item.titleEnglish ?? item.titleRomaji ?? "Unknown"
        applyScore(item.score ?? 0)
        metaLabel.text = AnimeCollectionViewCell.metaString(status: item.status, episodes: item.episodes)
        loadCover(urlString: item.coverURL ?? "")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageTask?.cancel()
        imageTask = nil
        currentURLString = nil
        coverImageView.image = nil
        scoreBadge.isHidden = true
        titleLabel.text = nil
        metaLabel.text = nil
    }
}
