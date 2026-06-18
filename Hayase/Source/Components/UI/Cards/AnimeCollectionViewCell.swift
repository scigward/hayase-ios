//
//  AnimeCollectionViewCell.swift
//  Hayase
//
//  Matches Hayase's small.svelte exactly:
//    • w-[9.5rem] = 152pt card width, aspect-ratio 152:290
//    • Cover image fixed height h-[13.5rem] = 216pt (matches CSS fixed height, not proportional)
//    • Below cover: pt-3 (12pt) gap → title row [statusDot? + title, line-clamp-2] → pt-2 (8pt) gap → meta row
//    • StatusDot: size-[0.55rem] ≈ 8.8pt circle, inline before title, hidden when no list entry
//      Colors from StatusDot.svelte: CURRENT=rgb(61,180,242), PLANNING=rgb(247,154,99),
//      COMPLETED=rgb(123,213,85), PAUSED=rgb(250,122,122), REPEATING=#3baeea, DROPPED=rgb(200,80,80)
//    • Meta row: year left (calendar icon) + format right (tv icon), text-neutral-500
//    •   placed directly below the 2-line title reserve with pt-2 (8pt) gap — static position
//    • No growing spacer / no bottom-anchor — meta is never pushed to the card bottom
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
        iv.backgroundColor = UIColor(red: 24/255, green: 144/255, blue: 255/255, alpha: 1) // web default: #1890ff
        iv.layer.cornerRadius = 4
        return iv
    }()

    // Title — font-black text-[.8rem] (12.8pt), white, 2 lines, pt-3 top spacing
    private let titleLabel: UILabel = {
        let l = UILabel()
        l.font = .nunito(ofSize: 13, weight: .black)  // text-[.8rem] = 12.8pt ≈ 13pt, font-black = 900
        l.textColor = .white
        l.numberOfLines = 2
        return l
    }()

    // Year label (left side of meta row) — text-xs font-medium, text-neutral-500
    private let yearLabel: UILabel = {
        let l = UILabel()
        l.font = .nunito(ofSize: 12, weight: .medium)  // text-xs = 0.75rem = 12pt
        l.textColor = UIColor(white: 0.45, alpha: 1) // neutral-500
        return l
    }()

    // Format label (right side of meta row) — same style as yearLabel
    private let formatLabel: UILabel = {
        let l = UILabel()
        l.font = .nunito(ofSize: 12, weight: .medium)  // text-xs = 12pt
        l.textColor = UIColor(white: 0.45, alpha: 1)
        return l
    }()

    // Status dot — inline circle before the title text, matching interface StatusDot.svelte.
    // size-[0.55rem] ≈ 8.8pt; no border; hidden when user has no AniList list entry.
    // Colors from StatusDot.svelte (not system colors):
    //   CURRENT=rgb(61,180,242)  PLANNING=rgb(247,154,99)  COMPLETED=rgb(123,213,85)
    //   PAUSED=rgb(250,122,122)  REPEATING=#3baeea  DROPPED=rgb(200,80,80)
    private let statusDotView: UIView = {
        let v = UIView()
        v.layer.cornerRadius = 4.4   // half of 8.8pt → perfect circle
        v.isHidden = true
        return v
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
        let calIcon = UIImageView(image: UIImage.hayaseIcon("calendar-days"))
        calIcon.tintColor = UIColor(white: 0.45, alpha: 1)
        calIcon.contentMode = .scaleAspectFit
        calIcon.translatesAutoresizingMaskIntoConstraints = false

        // TV icon for format
        let tvIcon = UIImageView(image: UIImage.hayaseIcon("tv"))
        tvIcon.tintColor = UIColor(white: 0.45, alpha: 1)
        tvIcon.contentMode = .scaleAspectFit
        tvIcon.translatesAutoresizingMaskIntoConstraints = false

        // Meta row: [calIcon  yearLabel  SPACER  formatLabel  tvIcon]
        let metaRow = UIStackView(arrangedSubviews: [calIcon, yearLabel, UIView(), formatLabel, tvIcon])
        metaRow.axis = .horizontal
        metaRow.spacing = 4
        metaRow.alignment = .center

        // Title row: [statusDotView  titleLabel]
        // Matches small.svelte: StatusDot is an inline <span> placed before the title text
        // inside the same pt-3 / font-black / line-clamp-2 div.
        // spacing = me-1 (4pt) from StatusDot.svelte.
        let titleRow = UIStackView(arrangedSubviews: [statusDotView, titleLabel])
        titleRow.axis = .horizontal
        titleRow.spacing = 4   // me-1 = 4pt
        titleRow.alignment = .top

        // Full card stack: [cover  titleRow  metaRow]
        // Matches small.svelte layout:
        //   cover (h-[13.5rem] fixed) → pt-3 gap → title row (line-clamp-2) → pt-2 gap → meta row
        // No growing spacer — the title always reserves exactly 2-line height so the
        // meta row has a static position regardless of whether the title is 1 or 2 lines,
        // matching interface's static placement just below the 2-line title text area.
        let cardStack = UIStackView(arrangedSubviews: [coverImageView, titleRow, metaRow])
        cardStack.axis = .vertical
        cardStack.spacing = 0
        cardStack.setCustomSpacing(12, after: coverImageView) // pt-3 = 12pt
        cardStack.setCustomSpacing(8, after: titleRow)        // pt-2 = 8pt
        cardStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(cardStack)

        // Title always occupies exactly 2 lines of height so the meta row sits at a
        // static position for all titles (1-line titles get a blank second-line reserve).
        let twoLineHeight = ceil(titleLabel.font.lineHeight * CGFloat(titleLabel.numberOfLines))

        NSLayoutConstraint.activate([
            cardStack.topAnchor.constraint(equalTo: contentView.topAnchor),
            cardStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            cardStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),

            // Cover height proportional to cell width — matches small.svelte aspect ratio
            // h-[13.5rem] on a w-[9.5rem] card = 216/152 ≈ 1.421. Using a multiplier (not
            // a constant) keeps the ratio correct for any cell width (home 152pt, search ~175pt).
            coverImageView.heightAnchor.constraint(equalTo: contentView.widthAnchor, multiplier: 216.0 / 152.0),

            // Title row always reserves 2-line height for the static meta-row position.
            titleRow.heightAnchor.constraint(equalToConstant: twoLineHeight),

            calIcon.widthAnchor.constraint(equalToConstant: 12),
            calIcon.heightAnchor.constraint(equalToConstant: 12),
            tvIcon.widthAnchor.constraint(equalToConstant: 12),
            tvIcon.heightAnchor.constraint(equalToConstant: 12),

            // Status dot: size-[0.55rem] = 8.8pt circle, aligned to first line of title
            statusDotView.widthAnchor.constraint(equalToConstant: 8.8),
            statusDotView.heightAnchor.constraint(equalToConstant: 8.8),
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
        // Set cover color placeholder matching web's load.svelte: style:background={color ?? '#1890ff'}
        coverImageView.backgroundColor = UIColor(hexString: item.coverColor) ?? UIColor(red: 24/255, green: 144/255, blue: 255/255, alpha: 1)
        loadCover(urlString: item.coverURL ?? "")
        // Status dot — show user's AniList list status when logged in (matches small.svelte: {#if status} <StatusDot>)
        if let status = item.mediaListEntry?.status {
            statusDotView.backgroundColor = statusDotColor(for: status)
            statusDotView.isHidden = false
        } else {
            statusDotView.isHidden = true
        }
    }

    /// Returns the dot fill color matching StatusDot.svelte's exact RGB values.
    private func statusDotColor(for status: String) -> UIColor {
        switch status {
        case "CURRENT":   return UIColor(red: 61/255,  green: 180/255, blue: 242/255, alpha: 1) // rgb(61,180,242)
        case "PLANNING":  return UIColor(red: 247/255, green: 154/255, blue: 99/255,  alpha: 1) // rgb(247,154,99)
        case "COMPLETED": return UIColor(red: 123/255, green: 213/255, blue: 85/255,  alpha: 1) // rgb(123,213,85)
        case "PAUSED":    return UIColor(red: 250/255, green: 122/255, blue: 122/255, alpha: 1) // rgb(250,122,122)
        case "REPEATING": return UIColor(red: 59/255,  green: 174/255, blue: 234/255, alpha: 1) // #3baeea
        default:          return UIColor(red: 200/255, green: 80/255,  blue: 80/255,  alpha: 1) // rgb(200,80,80) DROPPED
        }
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
        coverImageView.backgroundColor = UIColor(red: 24/255, green: 144/255, blue: 255/255, alpha: 1) // default #1890ff
        titleLabel.text = nil
        yearLabel.text = nil
        formatLabel.text = nil
        statusDotView.isHidden = true
        statusDotView.backgroundColor = nil
    }
}

// MARK: - UIColor hex initializer (matches web coverImage.color "#e3566b" format)

private extension UIColor {
    convenience init?(hexString: String?) {
        guard let hex = hexString?.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        var cleanHex = hex
        if cleanHex.hasPrefix("#") { cleanHex = String(cleanHex.dropFirst()) }
        guard cleanHex.count == 6, let rgb = UInt64(cleanHex, radix: 16) else { return nil }
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}

