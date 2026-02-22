//
//  AnimeCollectionViewCell.swift
//  TheAnimeTool
//
//  Matches Hayase's small.svelte exactly:
//    • w-[9.5rem] = 152pt card width, aspect-ratio 152:290
//    • Cover image fills top h-[13.5rem] = 216pt (74.5% of 290)
//    • Below cover: title (font-black, 12.8pt, white, 2 lines), pt-3 top spacing
//    • Meta row: year left (calendar icon) + format right (tv icon), text-neutral-500
//    • No separate info-bar background; no score badge overlay
//

import UIKit

// MARK: - Shared Image Cache (internal so BrowseAnimeViewController can use it)

enum SharedImageCache {
    static let shared = NSCache<NSString, UIImage>()
}

// MARK: - AnimeCollectionViewCell

class AnimeCollectionViewCell: UICollectionViewCell {
    static let reuseID = "AnimeCell"

    // Aspect ratio from small.svelte: 152 × 290
    // Cover occupies 216/290 of total height
    static let coverRatio: CGFloat = 216.0 / 290.0

    // MARK: Views

    /// Cover image — fills top 74.5% of cell (matches h-[13.5rem] on a 152:290 card)
    private let coverImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.backgroundColor = UIColor(white: 0.16, alpha: 1) // --muted in dark mode
        iv.layer.cornerRadius = 4
        return iv
    }()

    // Title — font-black, .8rem (12.8pt), white, 2 lines, pt-3 top spacing
    private let titleLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 12, weight: .heavy)
        l.textColor = .white
        l.numberOfLines = 2
        return l
    }()

    // Year label (left side of meta row) — text-neutral-500, xs/medium
    private let yearLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 11, weight: .medium)
        l.textColor = UIColor(white: 0.45, alpha: 1) // neutral-500
        return l
    }()

    // Format label (right side of meta row) — same style as yearLabel
    private let formatLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 11, weight: .medium)
        l.textColor = UIColor(white: 0.45, alpha: 1)
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
        // Transparent background to match Hayase's dark page bg
        backgroundColor = .clear
        contentView.backgroundColor = .clear

        // Calendar icon for year
        let calIcon = UIImageView(image: UIImage(systemName: "calendar"))
        calIcon.tintColor = UIColor(white: 0.45, alpha: 1)
        calIcon.contentMode = .scaleAspectFit
        calIcon.translatesAutoresizingMaskIntoConstraints = false

        // TV icon for format
        let tvIcon = UIImageView(image: UIImage(systemName: "tv"))
        tvIcon.tintColor = UIColor(white: 0.45, alpha: 1)
        tvIcon.contentMode = .scaleAspectFit
        tvIcon.translatesAutoresizingMaskIntoConstraints = false

        // Meta row: [calIcon  yearLabel  SPACER  formatLabel  tvIcon]
        let metaRow = UIStackView(arrangedSubviews: [calIcon, yearLabel, UIView(), formatLabel, tvIcon])
        metaRow.axis = .horizontal
        metaRow.spacing = 4
        metaRow.alignment = .center

        // Full card stack: [cover  title  metaRow]
        let cardStack = UIStackView(arrangedSubviews: [coverImageView, titleLabel, metaRow])
        cardStack.axis = .vertical
        cardStack.spacing = 0
        cardStack.setCustomSpacing(12, after: coverImageView) // pt-3 = 12pt
        cardStack.setCustomSpacing(8, after: titleLabel)
        cardStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(cardStack)

        NSLayoutConstraint.activate([
            cardStack.topAnchor.constraint(equalTo: contentView.topAnchor),
            cardStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            cardStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            cardStack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor),

            // Cover fills top 74.5% of cell width converted to height via aspect ratio
            // (cell height is set by the layout to match 152:290 ratio)
            coverImageView.heightAnchor.constraint(equalTo: contentView.widthAnchor,
                                                   multiplier: 216.0 / 152.0),

            calIcon.widthAnchor.constraint(equalToConstant: 12),
            calIcon.heightAnchor.constraint(equalToConstant: 12),
            tvIcon.widthAnchor.constraint(equalToConstant: 12),
            tvIcon.heightAnchor.constraint(equalToConstant: 12),
        ])
    }

    // MARK: - Configuration

    func configure(with anime: Animes) {
        titleLabel.text = anime.animeTitleEnglish ?? anime.animeTitleJapanese ?? "Unknown"
        yearLabel.text = "TBA"   // Animes entity has no year field
        formatLabel.text = "TV"  // Animes entity has no format field
        loadCover(urlString: anime.animeImgL ?? anime.animeImgM ?? "")
    }

    func configure(with item: AnimeItem) {
        titleLabel.text = item.titleEnglish ?? item.titleRomaji ?? "Unknown"
        // Matches small.svelte: media.seasonYear ?? media.startDate?.year ?? 'TBA'
        let displayYear = item.year ?? item.startYear
        yearLabel.text = displayYear.flatMap { $0 > 0 ? "\($0)" : nil } ?? "TBA"
        formatLabel.text = formatString(item.format)
        loadCover(urlString: item.coverURL ?? "")
    }

    private func formatString(_ raw: String?) -> String {
        // Matches Hayase's FORMAT_MAP in anilist/util.ts exactly
        guard let raw = raw else { return "TV Series" }
        switch raw {
        case "TV":       return "TV Series"
        case "TV_SHORT": return "TV Short"
        case "OVA":      return "OVA"
        case "ONA":      return "ONA"
        case "MOVIE":    return "Movie"
        case "SPECIAL":  return "Special"
        case "MUSIC":    return "Music"
        default:         return raw.replacingOccurrences(of: "_", with: " ").capitalized
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

    override func prepareForReuse() {
        super.prepareForReuse()
        imageTask?.cancel()
        imageTask = nil
        currentURLString = nil
        coverImageView.image = nil
        titleLabel.text = nil
        yearLabel.text = nil
        formatLabel.text = nil
    }
}
