//
//  AnimeDetailViewController.swift
//  Hayase
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
    let airDate: Date?
    let runtime: Int        // minutes; 0 if unknown
    let rating: Double?     // from ani.zip "rating" field (e.g. "8.9256") — shown as ★ badge
    let isFiller: Bool      // from ani.zip "filler" field — yellow ring + Filler badge
}

// MARK: - PaddedLabel
/// UILabel subclass that supports content edge insets (mirrors CSS padding).
private final class PaddedLabel: UILabel {
    var contentInsets = UIEdgeInsets.zero
    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: contentInsets))
    }
    override var intrinsicContentSize: CGSize {
        let s = super.intrinsicContentSize
        return CGSize(width: s.width + contentInsets.left + contentInsets.right,
                      height: s.height + contentInsets.top + contentInsets.bottom)
    }
    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let s = super.sizeThatFits(size)
        return CGSize(width: s.width + contentInsets.left + contentInsets.right,
                      height: s.height + contentInsets.top + contentInsets.bottom)
    }
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
        v.layer.cornerRadius = 6  // rounded-md = 0.375rem = 6pt
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

    // Runtime badge: absolute bottom-left, bg-neutral-900/80, px-1 py-0.5 rounded
    // Mirrors web: <div class='… text-[9.6px] px-1 py-0.5 rounded'>
    private let runtimeBadge: PaddedLabel = {
        let l = PaddedLabel()
        l.font = .nunito(ofSize: 9.6)
        l.textColor = UIColor(white: 0.98, alpha: 1) // text-secondary-foreground
        l.backgroundColor = UIColor(white: 0.09, alpha: 0.8) // bg-neutral-900/80
        l.contentInsets = UIEdgeInsets(top: 2, left: 4, bottom: 2, right: 4) // py-0.5 px-1
        l.layer.cornerRadius = 4 // rounded = 0.25rem = 4pt
        l.clipsToBounds = true
        l.isHidden = true
        return l
    }()

    // Rating badge: absolute bottom-right of thumb, ★ + rating value, px-1 py-0.5 rounded
    // Mirrors web: <Star class='size-2.5 … text-yellow-400' fill='currentColor' /> {rating}
    private let ratingBadge: PaddedLabel = {
        let l = PaddedLabel()
        l.font = .nunito(ofSize: 9.6)
        l.textColor = UIColor(white: 0.98, alpha: 1)
        l.backgroundColor = UIColor(white: 0.09, alpha: 0.8) // bg-neutral-900/80
        l.contentInsets = UIEdgeInsets(top: 2, left: 4, bottom: 2, right: 4) // py-0.5 px-1
        l.layer.cornerRadius = 4 // rounded = 4pt
        l.clipsToBounds = true
        l.isHidden = true
        return l
    }()

    // Filler badge: absolute bottom-right of card content, bg-yellow-400, rounded-tl
    // Mirrors Hayase: <div class='rounded-tl bg-yellow-400 py-1 px-2 absolute bottom-0 right-0'>Filler</div>
    private let fillerBadge: PaddedLabel = {
        let l = PaddedLabel()
        l.text = "Filler"
        l.font = .nunito(ofSize: 9.6, weight: .bold)
        l.textColor = UIColor(white: 0.04, alpha: 1)  // text-primary-foreground (dark)
        l.backgroundColor = UIColor(red: 0.97, green: 0.81, blue: 0.00, alpha: 1) // yellow-400
        // py-1 (4pt top/bottom) px-2 (8pt left/right) — exact Tailwind spacing
        l.contentInsets = UIEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
        l.layer.cornerRadius = 4
        l.layer.maskedCorners = [.layerMinXMinYCorner] // rounded-tl only
        l.clipsToBounds = true
        l.isHidden = true
        return l
    }()

    // Title: font-bold text-[12.8px] line-clamp-1
    private let numberLabel: UILabel = {
        let l = UILabel()
        l.font = .nunito(ofSize: 12.8, weight: .bold)
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
        l.font = .nunito(ofSize: 9.6)
        l.textColor = UIColor(white: 0.649, alpha: 1.0) // --muted-foreground
        l.numberOfLines = 3
        return l
    }()

    // Airdate: text-[9.6px]
    private let metaLabel: UILabel = {
        let l = UILabel()
        l.font = .nunito(ofSize: 9.6)
        l.textColor = UIColor(white: 0.649, alpha: 1.0)
        return l
    }()

    // Mirrors web `since()` — Intl.RelativeTimeFormat('en', { numeric: 'always' })
    private static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        f.dateTimeStyle = .numeric
        f.locale = Locale(identifier: "en")
        return f
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

        // Spacer pushes metaLabel to bottom of text column (web: `mt-auto` on date row)
        let spacer = UIView()
        spacer.setContentHuggingPriority(.defaultLow - 1, for: .vertical)
        spacer.setContentCompressionResistancePriority(.defaultLow - 1, for: .vertical)

        let textStack = UIStackView(arrangedSubviews: [numberLabel, progressBar, overviewLabel, spacer, metaLabel])
        textStack.axis = .vertical
        textStack.spacing = 4
        // Title has mb-2 (8pt) before the progress bar / overview — web: `font-bold mb-2`
        textStack.setCustomSpacing(8, after: numberLabel)
        textStack.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(textStack)

        // Thumbnail width: w-1/2 (50%) + shrink-0.
        // Priority 999 (below required) lets the max-w-52 cap win on iPad without a
        // constraint conflict (required == 50% vs required <= 208 when card > 416pt).
        // On iPhone the 50% value (≈183pt) satisfies both constraints; no collapse risk
        // because top/bottom/leading constraints are explicit and drive the layout.
        let thumbWidthPreferred = thumbImageView.widthAnchor.constraint(equalTo: cardView.widthAnchor, multiplier: 0.5)
        thumbWidthPreferred.priority = UILayoutPriority(999)
        let episodeThumbnailMaxWidth: CGFloat = 208  // Hayase EpisodesList.svelte: max-w-52 = 208pt

        NSLayoutConstraint.activate([
            // Card: gap-y-7 = 28pt gap between cards → 14pt top + 14pt bottom per cell
            cardView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 14),
            cardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            cardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            cardView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -14),
            // max-h-28 = 112pt — fixed height for consistent thumbnail sizes across all episode cards
            cardView.heightAnchor.constraint(equalToConstant: 112),

            // Thumbnail: left side, w-1/2 shrink-0 — always 50% wide even without an image loaded.
            thumbImageView.topAnchor.constraint(equalTo: cardView.topAnchor),
            thumbImageView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),
            thumbImageView.bottomAnchor.constraint(equalTo: cardView.bottomAnchor),
            thumbWidthPreferred,
            thumbImageView.widthAnchor.constraint(lessThanOrEqualToConstant: episodeThumbnailMaxWidth),

            // Runtime badge: bottom-left of thumb
            runtimeBadge.leadingAnchor.constraint(equalTo: thumbImageView.leadingAnchor, constant: 4),
            runtimeBadge.bottomAnchor.constraint(equalTo: thumbImageView.bottomAnchor, constant: -4),

            // Rating badge: bottom-right of thumb (Hayase: absolute bottom-1 right-1)
            ratingBadge.trailingAnchor.constraint(equalTo: thumbImageView.trailingAnchor, constant: -4),
            ratingBadge.bottomAnchor.constraint(equalTo: thumbImageView.bottomAnchor, constant: -4),

            // Text stack: py-3 (12pt top/bottom) px-4 (16pt left/right) matching web flex-col container
            textStack.leadingAnchor.constraint(equalTo: thumbImageView.trailingAnchor, constant: 16),
            textStack.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -16),
            textStack.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 12),
            textStack.bottomAnchor.constraint(lessThanOrEqualTo: cardView.bottomAnchor, constant: -12),

            // Progress bar height: h-0.5 = 2pt
            progressBar.heightAnchor.constraint(equalToConstant: 2),

            // Filler badge: absolute bottom-right of card (rounded-tl only — set via maskedCorners)
            fillerBadge.trailingAnchor.constraint(equalTo: cardView.trailingAnchor),
            fillerBadge.bottomAnchor.constraint(equalTo: cardView.bottomAnchor),
        ])
    }

    func configure(with episode: AniZipEpisode, anilistID: Int = 0, anilistProgress: Int = 0,
                   accentColor: UIColor = .white, isListCompleted: Bool = false) {
        numberLabel.text = "\(episode.number). \(episode.title.isEmpty ? "Episode \(episode.number)" : episode.title)"
        overviewLabel.text = episode.overview
        overviewLabel.isHidden = episode.overview.isEmpty

        // Web: `watched = _progress >= episode && !completed`
        // When list is COMPLETED, no thumbnail dimming (web shows full opacity for all episodes).
        let isWatchedOnAniList = anilistProgress > 0 && episode.number <= anilistProgress && !isListCompleted
        thumbImageView.alpha = isWatchedOnAniList ? 0.2 : 1.0
        cardView.alpha = 1.0

        // Progress fill uses the anime's accent color (bg-custom)
        progressFill.backgroundColor = accentColor

        // Progress bar — mirrors web logic:
        // • watched OR completed: full-width solid bg-custom bar, NO neutral track
        // • in-progress (WatchProgressService has partial fraction): neutral-800 track + partial fill
        // • otherwise: hidden
        let showFullBar = isWatchedOnAniList || isListCompleted
        if showFullBar {
            // No track — match web `<div class='mb-2 h-0.5 overflow-hidden w-full bg-custom shrink-0' />`
            progressBar.backgroundColor = accentColor
            progressBar.isHidden = false
            savedProgressFraction = 1.0
            setNeedsLayout()
        } else if anilistID > 0,
           let saved = WatchProgressService.shared.getProgress(anilistID: anilistID, episode: episode.number),
           saved.isInProgress {
            progressBar.backgroundColor = UIColor(white: 0.16, alpha: 1) // neutral-800 track
            progressBar.isHidden = false
            savedProgressFraction = saved.fraction
            setNeedsLayout()
        } else {
            progressBar.isHidden = true
            savedProgressFraction = 0
        }

        if let date = episode.airDate {
            metaLabel.text = EpisodeCell.relativeDateFormatter.localizedString(for: date, relativeTo: Date())
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

        // Rating badge: SF Symbol star.fill (yellow) + rating value — matches web <Star fill='currentColor' />
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

        // Border: filler overrides target (web: `!ring-yellow-400` uses !important)
        // target = anilistProgress + 1 → ring-custom accent border (ring-1 = 1pt)
        let isTarget = !isListCompleted && episode.number == anilistProgress + 1
        if episode.isFiller {
            cardView.layer.borderWidth = 1
            cardView.layer.borderColor = UIColor(red: 0.97, green: 0.81, blue: 0.00, alpha: 1).cgColor // yellow-400
            fillerBadge.isHidden = false
        } else if isTarget {
            cardView.layer.borderWidth = 1
            cardView.layer.borderColor = accentColor.cgColor // ring-custom
            fillerBadge.isHidden = true
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
        cardView.alpha = 1.0
        thumbImageView.alpha = 1.0
        progressBar.isHidden = true
        progressBar.backgroundColor = UIColor(white: 0.16, alpha: 1) // reset to neutral-800 track
        savedProgressFraction = 0
        progressFillWidthConstraint?.constant = 0
    }
}

// MARK: - PaginationBarView
// Matches Hayase's Pagination.svelte + EpisodesList.svelte pagination bar exactly:
// • "Showing X to Y of Z episodes" label (desktop-only on web, always shown here)
// • Chevron left/right buttons (ghost variant)
// • Numbered page buttons with ellipsis (outline for active, ghost for others)
// • siblingCount = 1, edgeSize = 4

private final class PaginationBarView: UIView {

    var onPageChange: ((Int) -> Void)?

    private(set) var currentPage: Int = 1
    private(set) var totalPages: Int = 1
    private var totalCount: Int = 0
    private var perPage: Int = 16

    private let infoLabel: UILabel = {
        let l = UILabel()
        l.font = .nunito(ofSize: 13)
        l.textColor = UIColor(white: 0.63, alpha: 1) // text-muted-foreground
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

        NSLayoutConstraint.activate([
            infoLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            infoLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            controlsStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            controlsStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            controlsStack.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: 8),
            controlsStack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -8),

            heightAnchor.constraint(greaterThanOrEqualToConstant: 52),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(currentPage: Int, totalCount: Int, perPage: Int) {
        self.currentPage = currentPage
        self.totalCount = totalCount
        self.perPage = perPage
        self.totalPages = max(1, Int(ceil(Double(totalCount) / Double(perPage))))
        rebuild()
    }

    // MARK: - Pagination algorithm (matches Pagination.svelte)

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
        // Update info label: "Showing X to Y of Z episodes"
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

        // Update buttons
        prevButton.isEnabled = currentPage > 1
        prevButton.alpha = currentPage > 1 ? 1.0 : 0.35
        nextButton.isEnabled = currentPage < totalPages
        nextButton.alpha = currentPage < totalPages ? 1.0 : 0.35

        // Rebuild page number buttons
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
                    // variant='outline' — border with transparent bg
                    btn.layer.borderWidth = 1
                    btn.layer.borderColor = UIColor(white: 0.27, alpha: 1).cgColor // border color
                    btn.setTitleColor(.white, for: .normal)
                    btn.backgroundColor = .clear
                } else {
                    // variant='ghost'
                    btn.layer.borderWidth = 0
                    btn.setTitleColor(UIColor(white: 0.63, alpha: 1), for: .normal)
                    btn.backgroundColor = .clear
                }

                pageStack.addArrangedSubview(btn)
            }
        }

        // On narrow screens (iPhone), hide page numbers, show info in center
        // Web hides page numbers on mobile and shows info text between chevrons
        let isNarrow = (superview?.frame.width ?? UIScreen.main.bounds.width) < 600
        pageStack.isHidden = isNarrow
        infoLabel.isHidden = isNarrow

        // On narrow: insert info label between chevrons if not already
        if isNarrow {
            // Add a compact info label in the controls stack
            if controlsStack.arrangedSubviews.count == 3 {
                let compactInfo = UILabel()
                compactInfo.font = .nunito(ofSize: 13)
                compactInfo.textColor = UIColor(white: 0.63, alpha: 1)
                compactInfo.textAlignment = .center
                compactInfo.attributedText = str
                compactInfo.tag = 999
                compactInfo.translatesAutoresizingMaskIntoConstraints = false
                controlsStack.insertArrangedSubview(compactInfo, at: 2) // between pageStack and nextButton
            } else if let compact = controlsStack.arrangedSubviews.first(where: { $0.tag == 999 }) as? UILabel {
                compact.attributedText = str
            }
        } else {
            // Remove compact info if switching to wide
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

// MARK: - HorizontalCardsCell
// A UITableViewCell containing a horizontal UICollectionView.
// tag 100 → Relations, tag 300 → Staff.

private final class HorizontalCardsCell: UITableViewCell {
    static let relationsReuseID  = "HorizontalRelationsCell"
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
        l.font = .nunito(ofSize: 9, weight: .semibold)
        l.textColor = .label
        l.numberOfLines = 2
        return l
    }()

    private let typeLabel: UILabel = {
        let l = UILabel()
        l.font = .nunito(ofSize: 8, weight: .medium)
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
        l.font = .nunito(ofSize: 9, weight: .semibold)
        l.textColor = .label
        l.numberOfLines = 2
        return l
    }()

    private let roleLabel: UILabel = {
        let l = UILabel()
        l.font = .nunito(ofSize: 8)
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
            lbl.font = .nunito(ofSize: 7)
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
        l.font = .nunito(ofSize: 14, weight: .semibold)
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
            nameLabel.font = .nunito(ofSize: 11)
            nameLabel.textColor = .label
            nameLabel.widthAnchor.constraint(equalToConstant: 80).isActive = true
            let progress = UIProgressView(progressViewStyle: .default)
            progress.setProgress(fraction, animated: false)
            progress.progressTintColor = Self.statusColor(for: status.status)
            progress.trackTintColor = .systemGray5
            let countLabel = UILabel()
            countLabel.text = "\(status.amount)"
            countLabel.font = .nunito(ofSize: 11)
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
        // Matches StatusDot.svelte exact RGB values
        switch status {
        case "CURRENT":   return UIColor(red: 61/255,  green: 180/255, blue: 242/255, alpha: 1) // rgb(61,180,242)
        case "PLANNING":  return UIColor(red: 247/255, green: 154/255, blue: 99/255,  alpha: 1) // rgb(247,154,99)
        case "COMPLETED": return UIColor(red: 123/255, green: 213/255, blue: 85/255,  alpha: 1) // rgb(123,213,85)
        case "PAUSED":    return UIColor(red: 250/255, green: 122/255, blue: 122/255, alpha: 1) // rgb(250,122,122)
        case "REPEATING": return UIColor(red: 59/255,  green: 174/255, blue: 234/255, alpha: 1) // #3baeea
        default:          return UIColor(red: 200/255, green: 80/255,  blue: 80/255,  alpha: 1) // rgb(200,80,80) DROPPED
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

// MARK: - ChipWrapView
// Used on iPad (regular horizontal size class) to replicate the web's
// `md:flex-wrap md:justify-start` genre layout — chips wrap to new rows
// when they exceed the container width.  On iPhone the existing horizontal
// scroll view is used instead.
private final class ChipWrapView: UIView {
    let interItemSpacing: CGFloat = 8
    let lineSpacing: CGFloat = 8
    let chipHeight: CGFloat = 28

    private var chipWidths: [CGFloat] = []

    func setChips(_ newChips: [UIView]) {
        subviews.forEach { $0.removeFromSuperview() }
        chipWidths = newChips.map { widthForChip($0) }
        newChips.forEach {
            $0.translatesAutoresizingMaskIntoConstraints = true
            addSubview($0)
        }
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }

    private func widthForChip(_ chip: UIView) -> CGFloat {
        if let btn = chip as? UIButton {
            let text = btn.title(for: .normal) ?? btn.titleLabel?.text ?? ""
            let font = btn.titleLabel?.font ?? .systemFont(ofSize: 13)
            let textW = ceil((text as NSString).size(withAttributes: [.font: font]).width)
            return textW + 24  // px-3 = 12pt each side
        }
        return chip.intrinsicContentSize.width
    }

    private func computeHeight(for width: CGFloat) -> CGFloat {
        guard !chipWidths.isEmpty, width > 0 else { return chipWidths.isEmpty ? 0 : chipHeight }
        var x: CGFloat = 0, y: CGFloat = 0
        for w in chipWidths {
            if x > 0 && x + w > width { x = 0; y += chipHeight + lineSpacing }
            x += w + interItemSpacing
        }
        return y + chipHeight
    }

    override var intrinsicContentSize: CGSize {
        let h = bounds.width > 0
            ? computeHeight(for: bounds.width)
            : (chipWidths.isEmpty ? 0 : chipHeight)
        return CGSize(width: UIView.noIntrinsicMetric, height: max(h, chipWidths.isEmpty ? 0 : chipHeight))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let chips = subviews
        guard !chips.isEmpty, bounds.width > 0 else { return }
        var x: CGFloat = 0, y: CGFloat = 0
        for (i, chip) in chips.enumerated() {
            let w = i < chipWidths.count ? chipWidths[i] : widthForChip(chip)
            if x > 0 && x + w > bounds.width { x = 0; y += chipHeight + lineSpacing }
            chip.frame = CGRect(x: x, y: y, width: w, height: chipHeight)
            x += w + interItemSpacing
        }
        let newH = y + chipHeight
        if abs(newH - intrinsicContentSize.height) > 0.5 {
            invalidateIntrinsicContentSize()
            superview?.setNeedsLayout()
        }
    }
}

private final class AnimeInfoHeaderView: UIView {
    // Callbacks
    var onShare: (() -> Void)?
    var onPlayTrailer: (() -> Void)?
    var onWatch: (() -> Void)?
    var onEntryEditor: (() -> Void)?
    var onFavorite: (() -> Void)?
    var onBookmark: (() -> Void)?

    /// Accent colour from the current anime's coverImage — used to tint active fav/bookmark icons.
    /// Mirrors Hayase's `select:!text-custom` on FavoriteButton / BookmarkButton.
    private var storedAccentColor: UIColor = .white

    private var anilistId: Int?
    /// The banner URL currently displayed (fanart > AniList banner > cover).
    private(set) var displayedBannerURL: String?

    // MARK: - Color constants matching Hayase dark theme
    private static let mutedFg      = UIColor(white: 0.649, alpha: 1.0) // --muted-foreground
    private static let secondary     = UIColor(red: 0.153, green: 0.153, blue: 0.165, alpha: 1) // --secondary #27272a

    // Banner height: slightly beyond Hayase's h-[23rem] (≈368pt) for a more vertical appearance.
    // With the -200pt content overlap the cover/text starts at 200pt from the top, leaving
    // ~112pt of visible banner above the cover art (below the ~88pt transparent nav bar).
    private static let bannerHeight: CGFloat = 400

    // MARK: - Banner (full-width — approximates global BannerImage in Hayase)
    private let bannerImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.backgroundColor = UIColor(white: 0.08, alpha: 1)
        return iv
    }()
    // Linear gradient overlay matching homepage BannerGradientView (5-point linear,
    // approximating Hayase's banner-image.svelte radial-gradient for mobile).
    // The bottom stop matches --background (white: 0.04) so the banner edge is
    // invisible against the app background (pure black would leave a visible seam).
    private let bannerGradientView: UIView = {
        let v = UIView()
        v.isUserInteractionEnabled = false
        let gradient = CAGradientLayer()
        let bgColor = UIColor(white: 0.04, alpha: 1)   // --background dark, same as app bg
        gradient.colors = [
            UIColor.black.withAlphaComponent(0.40).cgColor, // top edge
            UIColor.black.withAlphaComponent(0.16).cgColor, // ~25% — center of radial (light)
            UIColor.black.withAlphaComponent(0.16).cgColor, // ~40% — still light center
            UIColor.black.withAlphaComponent(0.50).cgColor, // ~65% — starts darkening
            bgColor.cgColor,                                 // bottom — blends into app bg
        ]
        gradient.locations = [0.0, 0.25, 0.40, 0.65, 1.0]
        v.layer.addSublayer(gradient)
        return v
    }()

    // MARK: - Cover (w-[180px] h-[256px] rounded  → proportional 100×142 on iPhone)
    private let coverImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.backgroundColor = UIColor(white: 0.16, alpha: 1)
        iv.layer.cornerRadius = 4   // rounded = 0.25rem = 4pt (default Tailwind)
        return iv
    }()

    // MARK: - Text labels
    // h2: font-light text-muted-foreground text-base (mobile) line-clamp-1 — ABOVE h1
    private let romajiLabel: UILabel = {
        let l = UILabel()
        l.font = .nunito(ofSize: 16, weight: .light)  // text-base = 16px on mobile
        l.textColor = UIColor(white: 0.649, alpha: 1.0)
        l.numberOfLines = 1
        // Resist vertical compression above autoresizing-mask priority (750)
        // so the label never gets squashed by the table-header container.
        l.setContentCompressionResistancePriority(.init(760), for: .vertical)
        return l
    }()

    // h1: font-black text-3xl text-white line-clamp-2
    private let titleLabel: UILabel = {
        let l = UILabel()
        l.font = .nunito(ofSize: 30, weight: .black)
        l.textColor = .white
        l.numberOfLines = 2
        // Resist vertical compression above autoresizing-mask priority (750)
        // so the label never gets squashed by the table-header container.
        l.setContentCompressionResistancePriority(.init(760), for: .vertical)
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
        l.font = .nunito(ofSize: 14, weight: .light)
        l.textColor = UIColor(white: 0.649, alpha: 1.0)
        l.numberOfLines = 4
        return l
    }()

    // MARK: - Action buttons
    // Hayase +layout.svelte: PlayButton + EntryEditor combo, FavoriteButton, BookmarkButton, Share, Trailer
    // Mobile order (≥380px): BookmarkButton(-order-2) → FavoriteButton(-order-1) → Play+Editor → Share → Trailer
    // AniList/MAL buttons: hidden md:flex (desktop only — hidden on iOS)

    // Play button: bg-custom text-contrast, rounded-r-none (right side is EntryEditor)
    private let playButton: UIButton = {
        let b = UIButton(type: .system)
        let iconCfg = UIImage.SymbolConfiguration(pointSize: 13, weight: .bold)
        b.setImage(UIImage(systemName: "play.fill")?.withConfiguration(iconCfg), for: .normal)
        b.setTitle("  Watch Now", for: .normal)
        b.tintColor = .black
        b.setTitleColor(.black, for: .normal)
        b.backgroundColor = .white
        b.titleLabel?.font = .nunito(ofSize: 15, weight: .bold)
        b.layer.cornerRadius = 6  // rounded-md = 0.375rem = 6pt
        b.layer.maskedCorners = [.layerMinXMinYCorner, .layerMinXMaxYCorner] // rounded-r-none
        b.layer.masksToBounds = true
        return b
    }()

    // EntryEditor button: rounded-l-none, bg-custom-400, pencil icon
    // Matches Hayase EntryEditor.svelte trigger: rounded-l-none bg-custom-400 select:!bg-custom-700
    private let entryEditorButton: UIButton = {
        let b = UIButton(type: .system)
        let iconCfg = UIImage.SymbolConfiguration(pointSize: 16, weight: .regular)
        b.setImage(UIImage(systemName: "pencil.line")?.withConfiguration(iconCfg), for: .normal)
        b.tintColor = .black
        b.backgroundColor = UIColor(white: 0.75, alpha: 1) // lighter variant of accent (custom-400)
        b.layer.cornerRadius = 6  // rounded-md = 0.375rem = 6pt
        b.layer.maskedCorners = [.layerMaxXMinYCorner, .layerMaxXMaxYCorner] // rounded-l-none
        b.layer.masksToBounds = true
        return b
    }()

    // FavoriteButton: variant='secondary' size='icon' — Heart icon, bg-secondary, h-9 w-9
    // Hayase: <FavoriteButton {media} variant='secondary' size='icon' class='select:!text-custom' />
    private let favoriteButton: UIButton = {
        let b = UIButton(type: .system)
        let iconCfg = UIImage.SymbolConfiguration(pointSize: 16, weight: .regular)
        b.setImage(UIImage(systemName: "heart")?.withConfiguration(iconCfg), for: .normal)
        b.tintColor = .white
        b.backgroundColor = UIColor(red: 0.153, green: 0.153, blue: 0.165, alpha: 1) // --secondary #27272a
        b.layer.cornerRadius = 6  // rounded-md = 0.375rem = 6pt
        b.layer.masksToBounds = true
        return b
    }()

    // BookmarkButton: variant='secondary' size='icon' — Bookmark icon, bg-secondary, h-9 w-9
    // Hayase: <BookmarkButton {media} variant='secondary' size='icon' class='select:!text-custom' />
    private let bookmarkButton: UIButton = {
        let b = UIButton(type: .system)
        let iconCfg = UIImage.SymbolConfiguration(pointSize: 16, weight: .regular)
        b.setImage(UIImage(systemName: "bookmark")?.withConfiguration(iconCfg), for: .normal)
        b.tintColor = .white
        b.backgroundColor = UIColor(red: 0.153, green: 0.153, blue: 0.165, alpha: 1) // --secondary #27272a
        b.layer.cornerRadius = 6  // rounded-md = 0.375rem = 6pt
        b.layer.masksToBounds = true
        return b
    }()

    // Share button: variant='secondary' size='icon', hidden min-[380px]:flex
    // TransitionButton: shows Share2 (Lucide) normally, flashes a checkmark briefly after tap.
    // arrowshape.turn.up.right is the closest SF Symbol to Lucide's Share2 fork icon.
    private let shareButton: UIButton = {
        let b = UIButton(type: .system)
        let iconCfg = UIImage.SymbolConfiguration(pointSize: 16, weight: .regular)
        b.setImage(UIImage(systemName: "arrowshape.turn.up.right")?.withConfiguration(iconCfg), for: .normal)
        b.tintColor = .white
        b.backgroundColor = UIColor(red: 0.153, green: 0.153, blue: 0.165, alpha: 1)
        b.layer.cornerRadius = 6  // rounded-md = 0.375rem = 6pt
        b.layer.masksToBounds = true
        return b
    }()

    // Trailer button: hidden min-[380px]:flex (shown only when trailer available)
    private let trailerButton: UIButton = {
        let b = UIButton(type: .custom)
        let iconCfg = UIImage.SymbolConfiguration(pointSize: 16, weight: .regular)
        // Use UIButton(type: .custom) + alwaysOriginal to avoid tintColor rendering issues
        // that affect .system buttons which start as isHidden = true.
        let iconName = "clapperboard.fill"  // available iOS 16+; "film" used as safe fallback
        let symName: String
        if #available(iOS 16.0, *) {
            symName = iconName
        } else {
            symName = "film"
        }
        let img = UIImage(systemName: symName, withConfiguration: iconCfg)?
            .withTintColor(.white, renderingMode: .alwaysOriginal)
        b.setImage(img, for: .normal)
        b.backgroundColor = UIColor(red: 0.153, green: 0.153, blue: 0.165, alpha: 1)
        b.layer.cornerRadius = 6  // rounded-md = 0.375rem = 6pt
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

    // Genres container — holds either genresScrollView (compact) or chipWrapView (regular)
    private let genresContainer = UIView()
    // ChipWrapView: used on iPad (regular horizontal size class) — wraps chips across rows
    private let chipWrapView = ChipWrapView()
    // Constraints toggled by applyGenresLayout() — created once in setup()
    private var genresContainerHeightConstraint: NSLayoutConstraint?
    private var chipWrapBottomConstraint: NSLayoutConstraint?

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
    // Matches Hayase +layout.svelte mobile layout exactly:
    // • flex-col items-center (vertical, centered)
    // • Cover 180×256 on top
    // • Text centered below: romaji (h2), title (h1)
    // • Badges: hidden on mobile (hidden md:flex)
    // • Description: hidden on mobile (md:block hidden)
    // • Buttons: Bookmark → Favorite → [Play + EntryEditor] → Share → Trailer
    // • Genres centered

    private func setup() {
        backgroundColor = UIColor(white: 0.04, alpha: 1) // --background dark

        // Badges & description HIDDEN on mobile — Hayase: hidden md:flex / md:block hidden
        badgesScrollView.isHidden = true
        descriptionLabel.isHidden = true

        // Genres scrollview (centered on mobile)
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

        // Text labels: centered on mobile (Hayase: text-center md:text-start)
        romajiLabel.textAlignment = .center
        titleLabel.textAlignment = .center

        // Text column: [romajiLabel, titleLabel] — gap-1.5 (6pt)
        // Hayase: flex flex-col gap-1.5 text-center
        let textColumn = UIStackView(arrangedSubviews: [romajiLabel, titleLabel])
        textColumn.axis = .vertical
        textColumn.spacing = 6
        textColumn.alignment = .fill  // fill so labels can center their text

        // Cover + text: VERTICAL on mobile (Hayase: flex-col items-center)
        // gap-4 (16pt) between items in the text section, gap-5 (20pt) between cover and text
        let coverAndTextColumn = UIStackView(arrangedSubviews: [coverImageView, textColumn])
        coverAndTextColumn.axis = .vertical
        coverAndTextColumn.spacing = 16  // gap-4 (items-center flex-col gap-4)
        coverAndTextColumn.alignment = .center  // items-center

        // Action buttons: Hayase mobile order (≥380px):
        // BookmarkButton(-order-2) → FavoriteButton(-order-1) → [Play + EntryEditor] → Share → Trailer
        shareButton.addTarget(self, action: #selector(shareTapped), for: .touchUpInside)
        trailerButton.addTarget(self, action: #selector(trailerTapped), for: .touchUpInside)
        playButton.addTarget(self, action: #selector(playTapped), for: .touchUpInside)
        entryEditorButton.addTarget(self, action: #selector(entryEditorTapped), for: .touchUpInside)
        favoriteButton.addTarget(self, action: #selector(favoriteTapped), for: .touchUpInside)
        bookmarkButton.addTarget(self, action: #selector(bookmarkTapped), for: .touchUpInside)

        // Play + EntryEditor combo (Hayase: flex w-[180px], play rounded-r-none + editor rounded-l-none)
        let playCombo = UIStackView(arrangedSubviews: [playButton, entryEditorButton])
        playCombo.axis = .horizontal
        playCombo.spacing = 0  // flush — play rounded-r-none, editor rounded-l-none
        playCombo.alignment = .fill
        // Low hugging so playCombo fills available space; low compression so it can shrink
        // when the trailer button is also visible on narrow iPhones (SE = 375pt).
        playCombo.setContentHuggingPriority(.defaultLow, for: .horizontal)
        playCombo.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        // Hayase mobile: gap-2 (8pt), items-center, justify-center, overflow-x-clip, [&>*]:flex-shrink-0
        let actionsRow = UIStackView(arrangedSubviews: [bookmarkButton, favoriteButton, playCombo, shareButton, trailerButton])
        actionsRow.axis = .horizontal
        actionsRow.spacing = 8  // gap-2
        actionsRow.alignment = .fill

        // Genres: gap-2, items-center, justify-center (centered on mobile)
        // Compact (iPhone): centered horizontal scroll — genresScrollView
        // Regular (iPad):   left-aligned wrapping   — chipWrapView
        genresContainer.addSubview(genresScrollView)
        chipWrapView.translatesAutoresizingMaskIntoConstraints = false
        genresContainer.addSubview(chipWrapView)
        NSLayoutConstraint.activate([
            // Scroll view (compact): centered, clips to container width
            genresScrollView.topAnchor.constraint(equalTo: genresContainer.topAnchor),
            genresScrollView.bottomAnchor.constraint(equalTo: genresContainer.bottomAnchor),
            genresScrollView.centerXAnchor.constraint(equalTo: genresContainer.centerXAnchor),
            genresScrollView.widthAnchor.constraint(equalTo: genresContainer.widthAnchor),
            // Wrap view (regular): left-aligned, full width
            chipWrapView.topAnchor.constraint(equalTo: genresContainer.topAnchor),
            chipWrapView.leadingAnchor.constraint(equalTo: genresContainer.leadingAnchor),
            chipWrapView.trailingAnchor.constraint(equalTo: genresContainer.trailingAnchor),
        ])
        // Create the two switchable constraints once; applyGenresLayout toggles isActive
        genresContainerHeightConstraint = genresContainer.heightAnchor.constraint(equalToConstant: 28)
        chipWrapBottomConstraint = chipWrapView.bottomAnchor.constraint(equalTo: genresContainer.bottomAnchor)

        // Main content: [coverAndTextColumn, actionsRow, genresContainer]
        // Hayase: gap-6 (24pt) between major sections, px-3 (12pt) horizontal padding
        let contentStack = UIStackView(arrangedSubviews: [coverAndTextColumn, actionsRow, genresContainer])
        contentStack.axis = .vertical
        contentStack.spacing = 24  // gap-6
        contentStack.isLayoutMarginsRelativeArrangement = true
        // Hayase: px-3 (12pt) horizontal padding, pt-4 (16pt) top, pb-0 bottom (tabBarContainer has own padding)
        contentStack.layoutMargins = UIEdgeInsets(top: 16, left: 12, bottom: 0, right: 12)

        [bannerImageView, bannerGradientView, contentStack].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }

        NSLayoutConstraint.activate([
            // Banner: full-width, matches bannerHeight
            bannerImageView.topAnchor.constraint(equalTo: topAnchor),
            bannerImageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            bannerImageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            bannerImageView.heightAnchor.constraint(equalToConstant: AnimeInfoHeaderView.bannerHeight),

            // Gradient overlay: same frame as banner
            bannerGradientView.topAnchor.constraint(equalTo: bannerImageView.topAnchor),
            bannerGradientView.leadingAnchor.constraint(equalTo: bannerImageView.leadingAnchor),
            bannerGradientView.trailingAnchor.constraint(equalTo: bannerImageView.trailingAnchor),
            bannerGradientView.bottomAnchor.constraint(equalTo: bannerImageView.bottomAnchor),

            // Cover: w-[180px] h-[256px] — exact Hayase dimensions
            coverImageView.widthAnchor.constraint(equalToConstant: 180),
            coverImageView.heightAnchor.constraint(equalToConstant: 256),

            // Actions row height = 36pt (h-9)
            actionsRow.heightAnchor.constraint(equalToConstant: 36),
            bookmarkButton.widthAnchor.constraint(equalToConstant: 36),
            favoriteButton.widthAnchor.constraint(equalToConstant: 36),
            entryEditorButton.widthAnchor.constraint(equalToConstant: 36),
            shareButton.widthAnchor.constraint(equalToConstant: 36),
            trailerButton.widthAnchor.constraint(equalToConstant: 36),

            // Play combo: max-w-[180px], flex-shrinks to fit on narrow iPhones (SE = 375pt).
            // Mirrors web `w-full min-[380px]:w-[180px] !shrink` — button fills available space
            // up to 180pt, compressing below 180pt when the trailer button is also visible.
            playCombo.widthAnchor.constraint(lessThanOrEqualToConstant: 180),

            // Hayase: text column has w-full so it fills the parent width even
            // though the parent (coverAndTextColumn) uses items-center (.center).
            // Without this, textColumn takes its intrinsic width (the text's
            // natural width), which may exceed the screen width for long titles.
            // The label then computes 1-line intrinsic height, the header is
            // sized too short, and the title gets clipped.
            textColumn.widthAnchor.constraint(equalTo: coverAndTextColumn.widthAnchor),

            // Content stack: overlaps banner so cover image sits within banner area.
            // Hayase: content starts at pt-4 + pt-12 = 64pt from scroll top, but on iOS we
            // need clearance below the nav bar (~88pt). Overlap -200 puts content at 100pt
            // from top, with 16pt margin → cover at 116pt (within the 300pt banner).
            contentStack.topAnchor.constraint(equalTo: bannerImageView.bottomAnchor, constant: -200),
            contentStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentStack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        // Apply initial genres layout based on current trait collection
        applyGenresLayout()
    }

    // Switch between compact (scroll) and regular (wrap) genres layout.
    // compact:  genresScrollView centered, genresContainer height fixed to 28pt (h-7)
    // regular:  chipWrapView left-aligned, genresContainer self-sizes via intrinsicContentSize
    private func applyGenresLayout() {
        let isRegular = traitCollection.horizontalSizeClass == .regular
        genresScrollView.isHidden = isRegular
        chipWrapView.isHidden = !isRegular
        genresContainerHeightConstraint?.isActive = !isRegular
        chipWrapBottomConstraint?.isActive = isRegular
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if previousTraitCollection?.horizontalSizeClass != traitCollection.horizontalSizeClass {
            applyGenresLayout()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Update the gradient sublayer frame within bannerGradientView
        if let gradientLayer = bannerGradientView.layer.sublayers?.first as? CAGradientLayer {
            gradientLayer.frame = bannerGradientView.bounds
        }

        // Tell multi-line labels the maximum width they may use when
        // computing their intrinsic content size.  This is needed because
        // coverAndTextColumn uses .center alignment, which does not impose
        // a width on arranged subviews the way .fill does.  The explicit
        // textColumn width constraint handles the *layout*, but
        // preferredMaxLayoutWidth is what UILabel reads when Auto Layout
        // calls intrinsicContentSize — without it the label can still
        // report a single-line height.
        let maxW = bounds.width - 24   // contentStack 12-pt left + right margins
        if maxW > 0 {
            titleLabel.preferredMaxLayoutWidth = maxW
            romajiLabel.preferredMaxLayoutWidth = maxW
        }
    }

    /// Pre-set preferredMaxLayoutWidth on title/romaji labels so that
    /// the constraint engine uses correct multi-line intrinsic heights
    /// on the very first layout pass.  Without this, the labels start
    /// with preferredMaxLayoutWidth = 0, which makes intrinsicContentSize
    /// return a single-line height; the header is then measured too short
    /// and the title text is clipped.
    func updateLabelWidths(forContainerWidth width: CGFloat) {
        let maxW = width - 24   // contentStack 12-pt left + right margins
        guard maxW > 0 else { return }
        titleLabel.preferredMaxLayoutWidth = maxW
        romajiLabel.preferredMaxLayoutWidth = maxW
        // Explicitly invalidate so the constraint engine picks up the
        // updated intrinsic sizes during the next layout pass.
        titleLabel.invalidateIntrinsicContentSize()
        romajiLabel.invalidateIntrinsicContentSize()
    }

    // MARK: - Actions

    /// Spring-bounce animation on icon buttons — matches Hayase's `animated-icon` press feedback.
    private func animateTap(_ button: UIButton) {
        UIView.animate(withDuration: 0.08, delay: 0, options: [.curveEaseIn], animations: {
            button.transform = CGAffineTransform(scaleX: 0.88, y: 0.88)
        }) { _ in
            UIView.animate(withDuration: 0.3, delay: 0,
                           usingSpringWithDamping: 0.5, initialSpringVelocity: 0.8,
                           options: [], animations: {
                button.transform = .identity
            })
        }
    }

    @objc private func shareTapped() {
        animateTap(shareButton)
        // TransitionButton: flash checkmark briefly after tap, then restore share icon.
        // Matches Hayase's TransitionButton (duration=300ms + 500ms = ~800ms total).
        let cfg = UIImage.SymbolConfiguration(pointSize: 16, weight: .regular)
        shareButton.setImage(UIImage(systemName: "checkmark")?.withConfiguration(cfg), for: .normal)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.shareButton.setImage(UIImage(systemName: "arrowshape.turn.up.right")?.withConfiguration(cfg), for: .normal)
        }
        onShare?()
    }
    @objc private func trailerTapped()     { animateTap(trailerButton);     onPlayTrailer?() }
    @objc private func playTapped()        { onWatch?() }
    @objc private func entryEditorTapped() { animateTap(entryEditorButton); onEntryEditor?() }
    @objc private func favoriteTapped()    { animateTap(favoriteButton);    onFavorite?() }
    @objc private func bookmarkTapped()    { animateTap(bookmarkButton);    onBookmark?() }

    /// Updates favorite/bookmark button icons to show filled/unfilled state.
    /// Mirrors interface: FavoriteButton fills heart + turns accent when fav(media) is true,
    /// BookmarkButton fills bookmark + turns accent when list(media) is truthy (`select:!text-custom`).
    func updateButtonStates(isFavorite: Bool, isOnList: Bool) {
        let cfg = UIImage.SymbolConfiguration(pointSize: 16, weight: .regular)
        let heartName = isFavorite ? "heart.fill" : "heart"
        favoriteButton.setImage(UIImage(systemName: heartName)?.withConfiguration(cfg), for: .normal)
        favoriteButton.tintColor = isFavorite ? storedAccentColor : .white

        let bookmarkName = isOnList ? "bookmark.fill" : "bookmark"
        bookmarkButton.setImage(UIImage(systemName: bookmarkName)?.withConfiguration(cfg), for: .normal)
        bookmarkButton.tintColor = isOnList ? storedAccentColor : .white
    }

    /// Updates play button label based on AniList watch status.
    /// Mirrors PlayButton.svelte: "Continue" (CURRENT/REPEATING/PAUSED), "Rewatch" (COMPLETED), "Watch Now" (else).
    func updatePlayButtonTitle(listStatus: String?) {
        let text: String
        switch listStatus {
        case "CURRENT", "REPEATING", "PAUSED": text = "  Continue"
        case "COMPLETED":                       text = "  Rewatch"
        default:                                text = "  Watch Now"
        }
        playButton.setTitle(text, for: .normal)
    }



    /// Applies pull-down zoom effect on the banner, identical to the homepage banner.
    func applyOverscrollZoom(_ overscroll: CGFloat) {
        guard overscroll > 0 else {
            // Only reset if not already at identity — avoids unnecessary layout invalidation.
            if bannerImageView.transform != .identity {
                bannerImageView.transform = .identity
                bannerGradientView.transform = .identity
            }
            return
        }
        let scale = 1.0 + overscroll / AnimeInfoHeaderView.bannerHeight
        let yShift = -overscroll / 2.0
        bannerImageView.transform = CGAffineTransform(translationX: 0, y: yShift).scaledBy(x: scale, y: scale)
        bannerGradientView.transform = CGAffineTransform(translationX: 0, y: yShift).scaledBy(x: scale, y: scale)
    }

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
        genresContainer.isHidden = true

        // Description: font-light text-sm text-muted-foreground
        let desc = anime.animeDescription?.trimmingCharacters(in: .whitespacesAndNewlines)
        descriptionLabel.text = (desc?.isEmpty ?? true) ? nil : desc

        trailerButton.isHidden = true

        displayedBannerURL = anime.animeImgS ?? anime.animeImgL ?? anime.animeImgM
        loadImage(from: displayedBannerURL,
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
        storedAccentColor = accent
        playButton.backgroundColor = accent
        playButton.tintColor = contrast
        playButton.setTitleColor(contrast, for: .normal)
        // EntryEditor: bg-custom-400 = hsl(from var(--custom) h s 60%)
        // Keep the accent's hue + saturation, but force lightness to 60%.
        // Convert HSB → HSL, set L=0.6, convert HSL → HSB for UIColor.
        var hue: CGFloat = 0, satHSB: CGFloat = 0, briHSB: CGFloat = 0
        accent.getHue(&hue, saturation: &satHSB, brightness: &briHSB, alpha: nil)
        let l = (2.0 - satHSB) * briHSB / 2.0
        let s = l == 0 || l == 1 ? 0 : satHSB * briHSB / (l < 0.5 ? 2.0 * l : 2.0 - 2.0 * l)
        let targetL: CGFloat = 0.6
        let bNew = targetL + s * min(targetL, 1.0 - targetL)
        let sNew: CGFloat = bNew > 0 ? 2.0 * (bNew - targetL) / bNew : 0
        let lighter = UIColor(hue: hue, saturation: sNew, brightness: bNew, alpha: 1)
        entryEditorButton.backgroundColor = lighter
        entryEditorButton.tintColor = contrast

        rebuildBadges(score:    item.score,
                      status:   item.status,
                      episodes: item.episodes,
                      nextEp:   nil,
                      format:   item.format,
                      season:   nil,
                      accent:   accent,
                      contrastColor: contrast)

        setGenres(item.genres.prefix(8).map { String($0) })

        let desc = item.description?.trimmingCharacters(in: .whitespacesAndNewlines)
        descriptionLabel.text = (desc?.isEmpty ?? true) ? nil : desc

        // Trailer button: show when YouTube trailer ID available
        trailerButton.isHidden = item.trailerYouTubeID == nil

        // Fetch fanart first (no flicker). AnimeService.fetchFanartURL is cached — if
        // fetchEpisodes() calls it concurrently it gets a cache hit instantly.
        // Fallback order: ani.zip Fanart → AniList bannerURL → coverURL.
        let bannerFallback = item.bannerURL ?? item.coverURL
        AnimeService.fetchFanartURL(anilistID: item.id) { [weak self] fanartURL in
            guard let self else { return }
            let urlStr = fanartURL ?? bannerFallback
            self.displayedBannerURL = urlStr
            self.bannerImageTask?.cancel()
            self.bannerImageTask = nil
            guard let urlStr, let url = URL(string: urlStr) else { return }
            if let cached = SharedImageCache.shared.object(forKey: urlStr as NSString) {
                self.bannerImageView.image = cached
                return
            }
            let biv = self.bannerImageView
            self.bannerImageTask = URLSession.shared.dataTask(with: url) { [weak biv] data, _, _ in
                guard let data, let img = UIImage(data: data) else { return }
                SharedImageCache.shared.setObject(img, forKey: urlStr as NSString)
                DispatchQueue.main.async {
                    UIView.transition(with: biv ?? UIImageView(), duration: 0.3,
                                      options: .transitionCrossDissolve,
                                      animations: { biv?.image = img })
                }
            }
            self.bannerImageTask?.resume()
        }
        loadImage(from: item.coverURL, into: coverImageView, task: &coverImageTask)
    }

    /// Called after ani.zip episodes fetch if a Fanart/Poster image is found.
    /// Matches Hayase banner.svelte: `metadata?.images?.find(i => i.coverType === 'Fanart')?.url`
    func updateBanner(from urlString: String) {
        displayedBannerURL = urlString
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
        l.font = .nunito(ofSize: 12, weight: .bold)
        l.textColor = contrast
        l.backgroundColor = accent
        l.layer.cornerRadius = 4   // rounded
        l.clipsToBounds = true
        l.setContentHuggingPriority(.required, for: .horizontal)
        return l
    }

    // Populate both genresStack (compact scroll) and chipWrapView (regular wrap).
    private func setGenres(_ genres: [String]) {
        genresStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        // chipWrapView uses frame-based layout — give it plain UIButtons without AL constraints
        let wrapChips: [UIView] = genres.map { genre in
            let btn = UIButton(type: .system)
            btn.setTitle(genre, for: .normal)
            btn.titleLabel?.font = .nunito(ofSize: 14, weight: .medium)
            btn.setTitleColor(.white, for: .normal)
            btn.backgroundColor = UIColor(red: 0.153, green: 0.153, blue: 0.165, alpha: 1)
            btn.contentEdgeInsets = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
            btn.layer.cornerRadius = 6
            btn.layer.masksToBounds = true
            return btn
        }
        for genre in genres {
            genresStack.addArrangedSubview(makeGenreChip(text: genre))
        }
        chipWrapView.setChips(wrapChips)
        genresContainer.isHidden = genres.isEmpty
    }

    /// Called by the VC when AniList data is fetched for a CoreData-opened anime.
    /// Shows the trailer button and genre chips that weren't available from CoreData.
    func updateGenresAndTrailer(genres: [String], trailerYouTubeID: String?) {
        setGenres(genres)
        trailerButton.isHidden = trailerYouTubeID == nil
    }

    /// Genre chip: variant='secondary' h-7 (28pt) text-nowrap rounded-md
    /// bg-secondary (#27272a), text-secondary-foreground (white), px-4 (16pt) — matches interface
    private func makeGenreChip(text: String) -> UIView {
        let btn = UIButton(type: .system)
        btn.setTitle(text, for: .normal)
        btn.titleLabel?.font = .nunito(ofSize: 14, weight: .medium)
        btn.setTitleColor(.white, for: .normal)
        btn.backgroundColor = UIColor(red: 0.153, green: 0.153, blue: 0.165, alpha: 1) // --secondary
        btn.contentEdgeInsets = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
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
            btn.titleLabel?.font = .nunito(ofSize: 13, weight: .medium)
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

    /// Natural width = sum of all button intrinsic widths + inter-button spacing + 8pt
    /// scrollView insets (4pt each side).  This lets Auto Layout size the muted container
    /// to fit its content rather than stretching it to the full available width, so the
    /// dark bg ends right after the last tab button on both iPhone and iPad.
    override var intrinsicContentSize: CGSize {
        let totalButtonWidth = buttons.reduce(0) { $0 + $1.intrinsicContentSize.width }
        let totalSpacing = CGFloat(max(buttons.count - 1, 0)) * stack.spacing
        let width = totalButtonWidth + totalSpacing + 8   // 8 = 2 × 4pt scrollView insets
        return CGSize(width: width, height: UIView.noIntrinsicMetric)
    }

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
                btn.setTitleColor(UIColor(white: 0.649, alpha: 1), for: .normal) // text-muted-foreground
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
    private var isFavorite = false
    private var isOnList = false
    private var episodes: [AniZipEpisode] = []
    private var anilistProgress: Int = 0  // mediaListEntry.progress from AniList
    private var currentListStatus: String?             // mediaListEntry.status from AniList
    private var currentAnimeAccent: UIColor = .white  // cached accent for episode progress bars
    private var relations: [AnimeRelation] = []
    private var staff: [AnimeStaffMember] = []
    private var scoreDistribution: [AnimeScorePoint] = []
    private var statusDistribution: [AnimeStatusCount] = []
    private var episodeFetchTask: URLSessionDataTask?

    // Episode pagination — matches Hayase's EpisodesList.svelte (perPage = 16)
    private let episodesPerPage = 16
    private var currentEpisodePage: Int = 1
    private var paginatedEpisodes: [AniZipEpisode] {
        let start = (currentEpisodePage - 1) * episodesPerPage
        let end = min(start + episodesPerPage, episodes.count)
        guard start < episodes.count else { return [] }
        return Array(episodes[start..<end])
    }
    private var totalEpisodePages: Int {
        max(1, Int(ceil(Double(episodes.count) / Double(episodesPerPage))))
    }
    private lazy var paginationBar: PaginationBarView = {
        let bar = PaginationBarView()
        bar.onPageChange = { [weak self] page in
            self?.setEpisodePage(page)
        }
        return bar
    }()

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
        // tabBar is pinned to the leading edge and capped at the trailing edge.
        // intrinsicContentSize makes it shrink-to-fit the buttons; lessThanOrEqualTo
        // allows it to grow up to the full available width when tabs overflow (scrollable).
        NSLayoutConstraint.activate([
            tabBar.topAnchor.constraint(equalTo: v.topAnchor, constant: 8),
            tabBar.bottomAnchor.constraint(equalTo: v.bottomAnchor, constant: -8),
            tabBar.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 16),
            // lessThanOrEqualTo: lets tabBar shrink to its intrinsicContentSize (buttons only),
            // while still allowing it to grow up to the full width when tabs overflow (scrollable).
            tabBar.trailingAnchor.constraint(lessThanOrEqualTo: v.trailingAnchor, constant: -16),
            tabBar.heightAnchor.constraint(equalToConstant: 36), // h-9 = 36pt
        ])
        return v
    }()

    // Section indices — section 0 holds the header (banner + cover + text + tab bar);
    // sections 1–4 match Hayase +page.svelte tabs: Episodes | Relations | Threads | Themes.
    private enum Section: Int, CaseIterable {
        case header = 0, episodes, episodePagination, relations, threads, themes
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
        fetchAniListProgress()
        refreshButtonStates()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Make the nav bar transparent so only the back chevron floats over the content.
        // This removes the black bar that appeared when title = nil left an empty nav bar.
        let nb = navigationController?.navigationBar
        nb?.setBackgroundImage(UIImage(), for: .default)
        nb?.shadowImage = UIImage()
        nb?.tintColor = .white  // back chevron visible over dark banner

        // Refresh AniList progress when returning from the player
        fetchAniListProgress()
        refreshButtonStates()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // Restore the standard nav bar appearance for other view controllers
        let nb = navigationController?.navigationBar
        nb?.setBackgroundImage(nil, for: .default)
        nb?.shadowImage = nil
        nb?.tintColor = nil
    }


    // MARK: - Setup

    private func setupTableView() {
        tableView = UITableView(frame: view.bounds, style: .plain)
        tableView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(EpisodeCell.self, forCellReuseIdentifier: EpisodeCell.reuseID)
        tableView.register(HorizontalCardsCell.self, forCellReuseIdentifier: HorizontalCardsCell.relationsReuseID)
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "HeaderCell")
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "PaginationCell")
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 100
        tableView.separatorStyle = .none
        tableView.backgroundColor = UIColor(white: 0.04, alpha: 1) // --background dark
        // Eliminate automatic section header/footer spacing that causes expanding gaps
        // between the tab bar and content cells (iOS 15+ adds ~22pt per section by default).
        if #available(iOS 15.0, *) {
            tableView.sectionHeaderTopPadding = 0
        }
        tableView.estimatedSectionHeaderHeight = 0
        tableView.estimatedSectionFooterHeight = 0
        // Remove the automatic nav-bar/status-bar content inset so the header banner
        // extends behind the transparent nav bar (no black gap), matching Hayase where
        // the banner-image div is `absolute top-0` behind the sidebar/browser chrome.
        tableView.contentInsetAdjustmentBehavior = .never
        // With .never, iOS doesn't add tab-bar inset automatically.
        // Set bottom inset = tab bar height so the last row isn't clipped.
        let tabBarH = tabBarController?.tabBar.frame.height ?? 83
        tableView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: tabBarH, right: 0)
        tableView.scrollIndicatorInsets = tableView.contentInset
        // Allow the banner to extend beyond the table view bounds during overscroll zoom
        tableView.clipsToBounds = false
        view.clipsToBounds = true
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
                currentAnimeAccent = accent
            }
        } else {
            headerView.configure(with: animeEntity)
        }
        headerView.onFavorite = { [weak self] in
            guard let self, let item = self.animeItem else { return }
            AniListTracking.shared.toggleFavourite(mediaID: item.id) { [weak self] _ in
                self?.refreshButtonStates()
            }
        }

        headerView.onBookmark = { [weak self] in
            guard let self, let item = self.animeItem else { return }
            if self.isOnList {
                AniListTracking.shared.fetchMediaWithEntry(anilistID: item.id) { [weak self] entry, _, _, _, _ in
                    if let listID = entry?.listID {
                        AniListTracking.shared.deleteEntry(listID: listID) { [weak self] _ in
                            self?.refreshButtonStates()
                        }
                    }
                }
            } else {
                AniListTracking.shared.entry(mediaID: item.id, status: "PLANNING") { [weak self] _ in
                    self?.refreshButtonStates()
                }
            }
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
        headerView.onEntryEditor = { [weak self] in
            self?.showEntryEditor()
        }

        // Header view + tab bar are embedded in a regular table cell (section 0)
        // instead of tableHeaderView.  This eliminates the TAMIC conflict that
        // caused endless sizing bugs: table header views always have TAMIC=true,
        // generating autoresizing constraints that fight constraint-based sizing.
        // As a cell, the contentView's auto layout chain (top→header→tabBar→bottom)
        // drives the cell height naturally.
    }


    // MARK: - AniList Entry Editor

    private func showEntryEditor() {
        guard let item = animeItem else { return }

        AniListTracking.shared.fetchMediaWithEntry(anilistID: item.id) { [weak self] entry, _, _, _, _ in
            DispatchQueue.main.async {
                self?.presentEntryEditorSheet(mediaID: item.id, currentEntry: entry, totalEpisodes: item.episodes)
            }
        }
    }

    private func presentEntryEditorSheet(mediaID: Int, currentEntry: AnimeItem.MediaListEntry?, totalEpisodes: Int?) {
        let editorVC = EntryEditorViewController()
        editorVC.mediaID = mediaID
        editorVC.totalEpisodes = totalEpisodes
        editorVC.currentEntry = currentEntry
        editorVC.animeTitle = animeItem?.titleEnglish ?? animeItem?.titleRomaji ?? "Unknown"
        editorVC.coverURL = animeItem?.coverURL
        editorVC.bannerURL = headerView?.displayedBannerURL ?? animeItem?.bannerURL

        editorVC.onSave = { [weak self] in
            self?.fetchAniListProgress()
            self?.refreshButtonStates()
        }
        editorVC.onDelete = { [weak self] in
            self?.anilistProgress = 0
            self?.currentListStatus = nil
            self?.isOnList = false
            self?.tableView.reloadData()
            self?.headerView?.updateButtonStates(isFavorite: self?.isFavorite ?? false, isOnList: false)
            self?.headerView?.updatePlayButtonTitle(listStatus: nil)
        }

        editorVC.modalPresentationStyle = .pageSheet
        if #available(iOS 15.0, *) {
            if let sheet = editorVC.sheetPresentationController {
                sheet.detents = [.medium(), .large()]
                sheet.prefersGrabberVisible = true
            }
        }
        present(editorVC, animated: true)
    }

    // MARK: - Fetch episodes (ani.zip)

    // MARK: - Hayase makeEpisodeList equivalent
    // Mirrors extensions.ts makeEpisodeList(media, episodesRes) exactly:
    //   const count = episodes(media) ?? episodesRes?.episodeCount ?? 0
    //   for (let episode = 1; episode <= count; episode++) { ... }
    //
    // The key difference from the old approach: we loop from 1 to `count`
    // (AniList episode count, or ani.zip episodeCount fallback) instead of
    // iterating ALL entries from the ani.zip episodes dict. This prevents
    // TVDB-split sub-episodes from appearing (e.g. Spirited Away showing
    // 3+4 parts instead of 1 complete movie).

    /// Mirrors Hayase util.ts `isMovie(media)` — checks format, title, duration.
    private func isMovie(format: String?, titles: [String], synonyms: [String], duration: Int?, episodes: Int?) -> Bool {
        if format == "MOVIE" { return true }
        let allNames = titles + synonyms
        if allNames.contains(where: { $0.lowercased().contains("movie") }) { return true }
        return (duration ?? 0) > 80 && episodes == 1
    }

    /// Mirrors Hayase util.ts `isSingleEpisode(media)`.
    private func isSingleEpisode(format: String?, titles: [String], synonyms: [String], duration: Int?, episodes: Int?) -> Bool {
        let movie = isMovie(format: format, titles: titles, synonyms: synonyms, duration: duration, episodes: episodes)
        return episodes == 1 || (movie && episodes == nil)
    }

    /// Mirrors Hayase extensions.ts `episodeByAirDate(alDate, episodes, episode)`.
    /// When alDate is nil, falls back to direct key lookup — matches Hayase:
    ///   `if (!alDate || !+alDate) return episodes.get('' + episode)`
    private struct FilteredEpisode {
        let key: String
        let info: [String: Any]
        let airdatems: Double?
        let anidbEid: Int?
    }

    private func episodeByAirDate(
        alDate: Date?,
        filtered: [String: FilteredEpisode],
        episode: Int
    ) -> FilteredEpisode? {
        // Hayase: if (!alDate || !+alDate) return episodes.get('' + episode)
        guard let alDate = alDate else {
            return filtered["\(episode)"]
        }
        let alMs = alDate.timeIntervalSince1970 * 1000

        // Find closest episodes by air date
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

        // If multiple episodes have the same air date, pick the one closest to requested episode number
        return closest.min(by: {
            abs(Int($0.key) ?? 0 - episode) < abs(Int($1.key) ?? 0 - episode)
        })
    }

    /// Fetches the user's AniList progress for this anime and refreshes episode cells.
    /// Mirrors desktop's mediaListEntry.progress used to dim watched episodes.
    private func fetchAniListProgress() {
        guard let id = animeItem?.id ?? animeEntity?.animeAnilistId?.intValue, id > 0 else { return }
        AniListTracking.shared.fetchProgress(anilistID: id) { [weak self] progress in
            guard let self = self else { return }
            let newProgress = progress ?? 0
            DispatchQueue.main.async {
                guard self.anilistProgress != newProgress else { return }
                self.anilistProgress = newProgress
                // Auto-navigate to the page containing the user's current episode (matches web)
                // Web: Math.floor(progress / perPage) + 1
                if newProgress > 0 {
                    let desiredPage = newProgress / self.episodesPerPage + 1
                    self.currentEpisodePage = min(max(1, desiredPage), self.totalEpisodePages)
                }
                self.tableView.reloadData()
            }
        }
    }

    /// Refreshes the favorite/bookmark button states from AniList.
    private func refreshButtonStates() {
        guard let id = animeItem?.id ?? animeEntity?.animeAnilistId?.intValue, id > 0 else { return }
        AniListTracking.shared.checkIsFavourite(mediaID: id) { [weak self] isFav in
            DispatchQueue.main.async {
                self?.isFavorite = isFav
                self?.headerView?.updateButtonStates(isFavorite: self?.isFavorite ?? false,
                                                     isOnList: self?.isOnList ?? false)
            }
        }
        AniListTracking.shared.fetchMediaWithEntry(anilistID: id) { [weak self] entry, _, _, _, _ in
            DispatchQueue.main.async {
                self?.isOnList = entry != nil
                self?.currentListStatus = entry?.status
                self?.headerView?.updateButtonStates(isFavorite: self?.isFavorite ?? false,
                                                     isOnList: self?.isOnList ?? false)
                self?.headerView?.updatePlayButtonTitle(listStatus: entry?.status)
            }
        }
    }

    private func fetchEpisodes() {
        let anilistId: Int?
        if let entity = animeEntity {
            anilistId = entity.animeAnilistId?.intValue
        } else {
            anilistId = animeItem?.id
        }
        guard let id = anilistId else { return }

        // AniList episode count — matches Hayase util.ts episodes(media).
        // Hayase also checks aired/notaired/progress, but we only have the
        // AniList total from the media object; ani.zip episodeCount is the fallback.
        let anilistEpisodes: Int?
        if let entity = animeEntity {
            anilistEpisodes = entity.animeTotalEps?.intValue
        } else {
            anilistEpisodes = animeItem?.episodes
        }

        let format = animeItem?.format

        // Same endpoint Hayase uses: /v1/episodes (not /mappings)
        guard let url = URL(string: "https://api.ani.zip/v1/episodes?anilist_id=\(id)") else { return }

        episodeFetchTask?.cancel()
        episodeFetchTask = URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let self = self,
                  let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

            // ── Hayase +layout.ts parent fallback ──────────────────────────────
            // Desktop: let eps = await episodes(id)
            //          if (!eps?.mappings?.anidb_id) {
            //            const parentID = getParentForSpecial(media)
            //            if (parentID) eps = await episodes(parentID)
            //          }
            let mappings = json["mappings"] as? [String: Any]
            let hasAnidbId = (mappings?["anidb_id"] as? NSNumber)?.intValue != nil

            if !hasAnidbId, let fmt = format, ["SPECIAL", "OVA", "ONA"].contains(fmt) {
                // ── Hayase +layout.ts parent fallback ──
                // Desktop: if (!eps?.mappings?.anidb_id) { parentID = getParentForSpecial(media); eps = await episodes(parentID) }
                // Desktop makeEpisodeList: alSchedule built from dedupeAiring(media) — AniList's airingSchedule
                // Then episodeByAirDate(alSchedule[ep], parentFiltered, ep) finds the correct special episode.

                // Need parent ID — try animeItem.relations first; if empty,
                // fetch relations from AniList before looking up the parent.
                self.resolveParentID(format: fmt) { [weak self] parentID in
                    guard let self = self else { return }
                    if let parentID = parentID {
                        // ── Fetch OVA's AniList airing schedule (mirrors dedupeAiring(media)) ──
                        // The desktop gets this from FullMedia fragment's aired/notaired fields.
                        // We fetch it separately since our AnimeItem doesn't carry airingSchedule.
                        AnimeService.sharedAnimeService.fetchMediaAiringSchedule(anilistID: id) { [weak self] schedResult in
                            guard let self = self else { return }

                            // Build alSchedule: episode number → air date
                            var alSchedule: [Int: Date] = schedResult?.schedule ?? [:]

                            // Hayase makeEpisodeList Step 2 fallback for single-episode media:
                            //   if (!alSchedule[1] && isSingleEpisode(media) && media.startDate)
                            //     alSchedule[1] = new Date(year, month-1, day)
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

                            // Re-fetch ani.zip with parent's ID
                            self.fetchAniZipEpisodeJSON(anilistID: parentID) { [weak self] parentJSON in
                                guard let self = self else { return }
                                let finalJSON = parentJSON ?? json
                                self.processEpisodeJSON(finalJSON, anilistEpisodes: anilistEpisodes,
                                                        anilistId: id, alSchedule: alSchedule)
                            }
                        }
                    } else {
                        // No parent found — use own data as-is
                        self.processEpisodeJSON(json, anilistEpisodes: anilistEpisodes, anilistId: id)
                    }
                }
                return
            }

            // Normal path (non-special or has anidb_id): process directly
            self.processEpisodeJSON(json, anilistEpisodes: anilistEpisodes, anilistId: id)
        }
        episodeFetchTask?.resume()
    }

    /// Hayase getParentForSpecial: find PARENT → PREQUEL → SEQUEL relation ID.
    /// If animeItem.relations is empty (not yet fetched), fetches them from AniList first.
    private func resolveParentID(format: String, completion: @escaping (Int?) -> Void) {
        // Try already-loaded relations first
        if let item = animeItem, !item.relations.isEmpty {
            let parentID = ["PARENT", "PREQUEL", "SEQUEL"].lazy.compactMap { relType -> Int? in
                item.relations.first { $0.relationType == relType }?.media.id
            }.first
            completion(parentID)
            return
        }

        // Relations not yet loaded — fetch them inline
        guard let id = animeItem?.id ?? animeEntity?.animeAnilistId?.intValue else {
            completion(nil)
            return
        }
        AnimeService.sharedAnimeService.fetchDetailForItem(id: id) { [weak self] relations in
            // fetchDetailForItem calls back on main queue
            self?.animeItem?.relations = relations
            self?.relations = relations
            let parentID = ["PARENT", "PREQUEL", "SEQUEL"].lazy.compactMap { relType -> Int? in
                relations.first { $0.relationType == relType }?.media.id
            }.first
            completion(parentID)
        }
    }

    /// Fetch ani.zip episode JSON for a given AniList ID (callback-based for use in fetchEpisodes).
    private func fetchAniZipEpisodeJSON(anilistID: Int, completion: @escaping ([String: Any]?) -> Void) {
        guard let url = URL(string: "https://api.ani.zip/v1/episodes?anilist_id=\(anilistID)") else {
            completion(nil)
            return
        }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                completion(nil)
                return
            }
            completion(json)
        }.resume()
    }

    /// Process the ani.zip episode JSON into AniZipEpisode models and update the UI.
    /// Extracted from fetchEpisodes() so it can be called for both the primary response
    /// and the parent fallback response.
    /// Mirrors Hayase makeEpisodeList(media, episodesRes) in extensions.ts.
    ///
    /// - Parameter alSchedule: When processing parent's ani.zip data for an OVA/SPECIAL,
    ///   this is the OVA's own per-episode airing schedule from AniList's airingSchedule
    ///   (the equivalent of Hayase's `alSchedule` built from `dedupeAiring(media)`).
    ///   Used as the `alDate` parameter in episodeByAirDate to correctly match OVA episodes
    ///   to the parent's episodes (typically specials like S1, S2, S3) by air date proximity.
    private func processEpisodeJSON(_ json: [String: Any], anilistEpisodes: Int?, anilistId: Int,
                                    alSchedule: [Int: Date]? = nil) {
        let episodesDict = json["episodes"] as? [String: Any] ?? [:]
        let episodesResCount = (json["episodeCount"] as? NSNumber)?.intValue
        let specialCount = (json["specialCount"] as? NSNumber)?.intValue ?? 0

        // ── Hayase: const count = episodes(media) ?? episodesRes?.episodeCount ?? 0 ──
        let count = anilistEpisodes ?? episodesResCount ?? 0

        // ── Build filtered map with airdate timestamps ──
        // Mirrors Hayase: const filtered = new Map<string, Episode & { airdatems? }>()
        var filtered: [String: FilteredEpisode] = [:]
        for (key, val) in episodesDict {
            guard let info = val as? [String: Any] else { continue }
            let airdate = info["airdate"] as? String
            var airdatems: Double? = nil
            if let airdate = airdate {
                // Try ISO 8601, then yyyy-MM-dd
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
            let anidbEid = (info["anidbEid"] as? NSNumber)?.intValue
            filtered[key] = FilteredEpisode(key: key, info: info, airdatems: airdatems, anidbEid: anidbEid)
        }

        // ── Hayase: const hasSpecial = !!episodesRes?.specialCount ──
        let hasSpecial = specialCount > 0
        // ── Hayase: const hasCountMatch = (episodes(media) ?? 0) === (episodesRes?.episodeCount ?? 0) ──
        let hasCountMatch = (anilistEpisodes ?? 0) == (episodesResCount ?? 0)

        let now = Date().timeIntervalSince1970 * 1000

        // Hayase banner.svelte (desktop): episodesCached(id) → images.find(Fanart)?.url
        // If ani.zip provides a Fanart (TVDB-sourced landscape) or Poster image,
        // use it as the banner instead of AniList's bannerImage.
        var anizipBannerURL: String? = nil
        if let imagesArray = json["images"] as? [[String: Any]] {
            let fanart = imagesArray.first(where: { ($0["coverType"] as? String) == "Fanart" })?["url"] as? String
            let poster  = imagesArray.first(where: { ($0["coverType"] as? String) == "Poster"  })?["url"] as? String
            anizipBannerURL = fanart ?? poster
        }

        var parsed: [AniZipEpisode] = []
        guard count > 0 else {
            // count == 0 → empty episode list (same as Hayase loop not executing)
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
            // Hayase: const hasEpisode = episodesRes?.episodes?.[Number(episode)]
            let hasEpisode = episodesDict["\(episode)"] != nil

            // Hayase: const needsValidation = !(!hasSpecial || (hasEpisode && hasCountMatch))
            let needsValidation = !(!hasSpecial || (hasEpisode && hasCountMatch))

            let resolvedEntry: FilteredEpisode?
            if needsValidation {
                // Hayase makeEpisodeList: const airingAt = alSchedule.get(episode)
                // Use the OVA's AniList airing schedule date for this episode,
                // matching Hayase's alSchedule built from dedupeAiring(media).
                // This enables episodeByAirDate to find the correct episode
                // (e.g., special S1) in the parent's filtered map by air-date proximity.
                let alDate = alSchedule?[episode]
                resolvedEntry = self.episodeByAirDate(alDate: alDate, filtered: filtered, episode: episode)

                // Hayase: remove consumed episodes (matching anidbEid or earlier dates)
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
                // Simple case: direct key lookup — filtered.get('' + episode)
                resolvedEntry = filtered["\(episode)"]
            }

            // Parse episode data from resolved entry (or empty fallback)
            let info = resolvedEntry?.info ?? [:]
            let titles = info["title"] as? [String: String] ?? [:]
            let title = titles["en"] ?? titles["x-jat"] ?? titles["ja"] ?? ""
            let overview = (info["overview"] as? String ?? info["summary"] as? String ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let imageURL = info["image"] as? String
            let airDateRaw = info["airdate"] as? String ?? info["airDate"] as? String
            let airDate: Date? = airDateRaw.flatMap { raw in
                if let d = ISO8601DateFormatter().date(from: raw) { return d }
                let fmt = DateFormatter()
                fmt.dateFormat = "yyyy-MM-dd"
                fmt.locale = Locale(identifier: "en_US_POSIX")
                return fmt.date(from: raw)
            }
            let runtime = (info["length"] as? NSNumber)?.intValue ?? (info["runtime"] as? NSNumber)?.intValue ?? 0
            let ratingRaw = info["rating"]
            let rating: Double? = (ratingRaw as? NSNumber)?.doubleValue
                ?? (ratingRaw as? String).flatMap(Double.init)

            parsed.append(AniZipEpisode(
                number: episode,
                title: title.isEmpty ? "Episode \(episode)" : title,
                overview: overview, imageURL: imageURL, airDate: airDate,
                runtime: runtime, rating: rating, isFiller: false))
        }

        // Fetch filler data from ThaUnknown/filler-scrape (exact Hayase match):
        // extensions.ts: fetch('https://raw.githubusercontent.com/ThaUnknown/filler-scrape/master/filler.json')
        //                filler: !!fillerEpisodes[media.id]?.includes(episode)
        AnimeDetailViewController.loadFillerSet(for: anilistId) { fillerSet in
            let finalEpisodes = parsed.map { ep in
                AniZipEpisode(number: ep.number, title: ep.title, overview: ep.overview,
                              imageURL: ep.imageURL, airDate: ep.airDate, runtime: ep.runtime,
                              rating: ep.rating, isFiller: fillerSet.contains(ep.number))
            }
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.episodes = finalEpisodes
                // Clamp page to new total to avoid stale page index crash
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

        AnimeService.sharedAnimeService.fetchDetailForItem(id: anilistId) { [weak self] relations in
            guard let self = self else { return }
            self.relations = relations
            if !relations.isEmpty {
                self.tableView.reloadSections(IndexSet(integer: Section.relations.rawValue), with: .fade)
            }
        }

        // When opened from CoreData, animeItem is nil so trailer + genres were hidden.
        // Fetch them from AniList now and update the header.
        if animeItem == nil {
            AnimeService.sharedAnimeService.fetchTrailerAndGenres(id: anilistId) { [weak self] trailerID, genres in
                self?.headerView?.updateGenresAndTrailer(genres: genres, trailerYouTubeID: trailerID)
            }
        }
    }

    // MARK: - Tab bar

    private func tabChanged(to index: Int) {
        // Tab bar indices: 0=Episodes 1=Relations 2=Threads 3=Themes
        // Section enum:    header=0, episodes=1, episodePagination=2, relations=3, threads=4, themes=5
        let sectionMap: [Int: Section] = [0: .episodes, 1: .relations, 2: .threads, 3: .themes]
        guard let sec = sectionMap[index] else { return }
        activeSection = sec
        // Only reload content sections — header (section 0) never changes.
        let contentRange = Section.episodes.rawValue..<Section.allCases.count
        tableView.reloadSections(IndexSet(integersIn: contentRange), with: .automatic)
        // Lazy-fetch threads/themes on first tap
        if sec == .threads && threads.isEmpty && !threadsLoading { fetchThreads() }
        if sec == .themes  && themes.isEmpty  && !themesLoading  { fetchThemes()  }
    }

    private func setEpisodePage(_ page: Int) {
        let clamped = min(max(1, page), totalEpisodePages)
        guard clamped != currentEpisodePage else { return }
        currentEpisodePage = clamped
        let sectionsToReload = IndexSet([Section.episodes.rawValue, Section.episodePagination.rawValue])
        tableView.reloadSections(sectionsToReload, with: .automatic)
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

        // Exact Hayase URL (src/lib/modules/animethemes/index.ts):
        //   https://api.animethemes.moe/anime/?
        //     fields[audio]=id,basename,link,size
        //     &fields[video]=id,basename,link,tags
        //     &filter[external_id]=${id}
        //     &filter[has]=resources        ← CRITICAL: without this the API ignores external_id
        //     &filter[site]=AniList
        //     &include=animethemes.animethemeentries.videos,animethemes.song,animethemes.song.artists
        // percentEncodedQuery: brackets → %5B/%5D, commas in include stay literal (server expects them).
        var comps = URLComponents(string: "https://api.animethemes.moe/anime/")!
        comps.percentEncodedQuery = "fields%5Baudio%5D=id,basename,link,size&fields%5Bvideo%5D=id,basename,link,tags&filter%5Bexternal_id%5D=\(id)&filter%5Bhas%5D=resources&filter%5Bsite%5D=AniList&include=animethemes.animethemeentries.videos,animethemes.song,animethemes.song.artists"
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
        case .header:    return 1
        case .episodes:  return activeSection == .episodes  ? paginatedEpisodes.count : 0
        case .episodePagination:
            // Show pagination bar when episodes tab is active and there are more than 1 page
            return (activeSection == .episodes && totalEpisodePages > 1) ? 1 : 0
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
        case .header:
            let cell = tableView.dequeueReusableCell(withIdentifier: "HeaderCell", for: indexPath)
            cell.backgroundColor = .clear
            cell.contentView.backgroundColor = .clear
            cell.selectionStyle = .none
            // Allow banner overflow for overscroll zoom effect
            cell.clipsToBounds = false
            cell.contentView.clipsToBounds = false
            if headerView.superview !== cell.contentView {
                headerView.clipsToBounds = false
                headerView.translatesAutoresizingMaskIntoConstraints = false
                tabBarContainer.translatesAutoresizingMaskIntoConstraints = false
                cell.contentView.addSubview(headerView)
                cell.contentView.addSubview(tabBarContainer)
                NSLayoutConstraint.activate([
                    headerView.topAnchor.constraint(equalTo: cell.contentView.topAnchor),
                    headerView.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor),
                    headerView.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor),
                    tabBarContainer.topAnchor.constraint(equalTo: headerView.bottomAnchor),
                    tabBarContainer.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor),
                    tabBarContainer.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor),
                    tabBarContainer.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor),
                ])
            }
            // Pre-set label widths so auto layout computes correct multi-line heights
            headerView.updateLabelWidths(forContainerWidth: tableView.frame.width)
            return cell

        case .episodes:
            guard let cell = tableView.dequeueReusableCell(
                withIdentifier: EpisodeCell.reuseID, for: indexPath) as? EpisodeCell else {
                return UITableViewCell()
            }
            let currentAnilistID = animeItem?.id ?? (animeEntity?.animeAnilistId?.intValue ?? 0)
            let ep = paginatedEpisodes[indexPath.row]
            cell.configure(with: ep, anilistID: currentAnilistID, anilistProgress: anilistProgress,
                           accentColor: currentAnimeAccent, isListCompleted: currentListStatus == "COMPLETED")
            return cell

        case .episodePagination:
            let cell = tableView.dequeueReusableCell(withIdentifier: "PaginationCell", for: indexPath)
            cell.backgroundColor = .clear
            cell.contentView.backgroundColor = .clear
            cell.selectionStyle = .none
            if paginationBar.superview !== cell.contentView {
                paginationBar.translatesAutoresizingMaskIntoConstraints = false
                cell.contentView.addSubview(paginationBar)
                NSLayoutConstraint.activate([
                    paginationBar.topAnchor.constraint(equalTo: cell.contentView.topAnchor),
                    paginationBar.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor),
                    paginationBar.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor),
                    paginationBar.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor),
                ])
            }
            paginationBar.configure(currentPage: currentEpisodePage, totalCount: episodes.count, perPage: episodesPerPage)
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

    // MARK: - Scroll-driven overscroll zoom (matches homepage banner)

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let offsetY = scrollView.contentOffset.y
        if offsetY < 0 {
            headerView.applyOverscrollZoom(-offsetY)
        } else {
            headerView.applyOverscrollZoom(0)
        }
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        // Tab bar lives inside the header cell (section 0) so it scrolls with content —
        // matches Hayase where Tabs.Root is inside the scrollable div, not sticky.
        return nil
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return 0
    }

    func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        return nil
    }

    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        return 0
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        switch Section(rawValue: indexPath.section) {
        case .relations:          return 160
        default:                  return UITableView.automaticDimension
        }
    }

    func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat {
        // Give the header cell a realistic estimate so the table view's initial
        // content-size calculation doesn't cause visual jumping.
        if Section(rawValue: indexPath.section) == .header { return 600 }
        return 100
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch Section(rawValue: indexPath.section) {
        case .episodes:
            let ep = paginatedEpisodes[indexPath.row]
            openExtensionSearch(episode: ep.number)
        case .threads:
            guard !threadsLoading, !threads.isEmpty else { return }
            let thread = threads[indexPath.row]
            let threadVC = ThreadDetailViewController(threadID: thread.id, title: thread.title)
            navigationController?.pushViewController(threadVC, animated: true)
        case .themes:
            break  // Play buttons in cells handle theme playback
        default: break
        }
    }
}

// MARK: - UICollectionViewDataSource (embedded in HorizontalCardsCells)

extension AnimeDetailViewController: UICollectionViewDataSource {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        switch collectionView.tag {
        case 100: return relations.count
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
        label.font = .nunito(ofSize: 14)
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
        titleLabel.font = .nunito(ofSize: 12.8, weight: .bold)
        titleLabel.textColor = .white
        titleLabel.numberOfLines = 1
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        // Stats row: ♥ likes  👁 views  💬 replies
        let statsLabel = UILabel()
        statsLabel.text = "♥ \(thread.likeCount)  👁 \(thread.viewCount)  💬 \(thread.replyCount)\(thread.isLocked ? "  🔒" : "")"
        statsLabel.font = .nunito(ofSize: 9.6)
        statsLabel.textColor = UIColor(white: 0.6, alpha: 1)
        statsLabel.translatesAutoresizingMaskIntoConstraints = false

        // Footer: time + categories
        let footerLabel = UILabel()
        var footerParts = [thread.sinceString]
        if let name = thread.userName { footerParts.append("by \(name)") }
        footerLabel.text = footerParts.joined(separator: " · ")
        footerLabel.font = .nunito(ofSize: 9.6)
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
            let badge = ThreadBadgeLabel()
            badge.text = cat
            badge.font = .nunito(ofSize: 9.6, weight: .bold)
            badge.textColor = ExtensionSearchViewController.luminanceContrastColor(for: accentColor)
            badge.backgroundColor = accentColor
            badge.layer.cornerRadius = 4
            badge.clipsToBounds = true
            badge.textAlignment = .center
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

    /// Builds a theme card matching web interface Themes.svelte:
    /// One card per AnimeTheme containing a header row (type + song + artist)
    /// and one version row per entry (vN · Episodes X-Y + play button).
    func makeThemeCell(for indexPath: IndexPath) -> UITableViewCell {
        if themesLoading || themes.isEmpty {
            return makeEmptyStateCell(
                text: "No themes found.",
                loading: themesLoading)
        }
        let theme = themes[indexPath.row]
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.backgroundColor = .clear
        cell.selectionStyle = .none

        // bg-neutral-950 card
        let card = UIView()
        card.backgroundColor = UIColor(white: 0.039, alpha: 1)
        card.layer.cornerRadius = 8
        card.translatesAutoresizingMaskIntoConstraints = false
        cell.contentView.addSubview(card)

        // Vertical stack inside card: header row + entry rows
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)

        // -- Header row: [type 48pt] [song title  by artists] --
        let headerRow = UIView()
        headerRow.translatesAutoresizingMaskIntoConstraints = false

        let typeLabel = UILabel()
        typeLabel.text = theme.type
        typeLabel.font = .nunito(ofSize: 11, weight: .bold)
        typeLabel.textColor = UIColor(white: 0.7, alpha: 1)
        typeLabel.translatesAutoresizingMaskIntoConstraints = false
        headerRow.addSubview(typeLabel)

        let songLabel = UILabel()
        let songTitle = NSMutableAttributedString(
            string: theme.songTitle,
            attributes: [.font: UIFont.nunito(ofSize: 14, weight: .bold), .foregroundColor: UIColor.white])
        if !theme.artists.isEmpty {
            songTitle.append(NSAttributedString(
                string: " by ",
                attributes: [.font: UIFont.nunito(ofSize: 10), .foregroundColor: UIColor(white: 0.5, alpha: 1)]))
            songTitle.append(NSAttributedString(
                string: theme.artists,
                attributes: [.font: UIFont.nunito(ofSize: 14, weight: .bold), .foregroundColor: UIColor.white]))
        }
        songLabel.attributedText = songTitle
        songLabel.numberOfLines = 1
        songLabel.translatesAutoresizingMaskIntoConstraints = false
        headerRow.addSubview(songLabel)

        NSLayoutConstraint.activate([
            headerRow.heightAnchor.constraint(greaterThanOrEqualToConstant: 24),
            typeLabel.leadingAnchor.constraint(equalTo: headerRow.leadingAnchor),
            typeLabel.centerYAnchor.constraint(equalTo: headerRow.centerYAnchor),
            typeLabel.widthAnchor.constraint(equalToConstant: 48),
            songLabel.leadingAnchor.constraint(equalTo: typeLabel.trailingAnchor),
            songLabel.centerYAnchor.constraint(equalTo: headerRow.centerYAnchor),
            songLabel.trailingAnchor.constraint(equalTo: headerRow.trailingAnchor),
        ])
        stack.addArrangedSubview(headerRow)

        // -- Version rows --
        let accentColor = animeItem.flatMap { ExtensionSearchViewController.uiColor(fromHex: $0.coverColor ?? "") }
            ?? UIColor(red: 0.24, green: 0.71, blue: 0.95, alpha: 1)

        for entry in theme.entries {
            let row = UIView()
            row.translatesAutoresizingMaskIntoConstraints = false

            let verLabel = UILabel()
            verLabel.text = "v\(entry.version)"
            verLabel.font = .nunito(ofSize: 11)
            verLabel.textColor = UIColor(white: 0.5, alpha: 1)
            verLabel.translatesAutoresizingMaskIntoConstraints = false
            row.addSubview(verLabel)

            let epLabel = UILabel()
            epLabel.text = entry.episodes.isEmpty ? "" : "Episodes \(entry.episodes)"
            epLabel.font = .nunito(ofSize: 11)
            epLabel.textColor = UIColor(white: 0.5, alpha: 1)
            epLabel.translatesAutoresizingMaskIntoConstraints = false
            row.addSubview(epLabel)

            let playBtn = UIButton(type: .system)
            let playIconCfg = UIImage.SymbolConfiguration(pointSize: 9, weight: .bold)
            playBtn.setImage(UIImage(systemName: "play.fill")?.withConfiguration(playIconCfg), for: .normal)
            playBtn.tintColor = ExtensionSearchViewController.luminanceContrastColor(for: accentColor)
            playBtn.backgroundColor = accentColor
            playBtn.layer.cornerRadius = 10
            playBtn.translatesAutoresizingMaskIntoConstraints = false
            row.addSubview(playBtn)

            if let urlStr = entry.videoURL {
                playBtn.addTarget(self, action: #selector(themePlayTapped(_:)), for: .touchUpInside)
                objc_setAssociatedObject(playBtn, &themeURLKey, urlStr, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            } else {
                playBtn.isHidden = true
            }

            NSLayoutConstraint.activate([
                row.heightAnchor.constraint(greaterThanOrEqualToConstant: 24),
                verLabel.leadingAnchor.constraint(equalTo: row.leadingAnchor),
                verLabel.centerYAnchor.constraint(equalTo: row.centerYAnchor),
                verLabel.widthAnchor.constraint(equalToConstant: 48),
                epLabel.leadingAnchor.constraint(equalTo: verLabel.trailingAnchor),
                epLabel.centerYAnchor.constraint(equalTo: row.centerYAnchor),
                playBtn.leadingAnchor.constraint(greaterThanOrEqualTo: epLabel.trailingAnchor, constant: 8),
                playBtn.trailingAnchor.constraint(equalTo: row.trailingAnchor),
                playBtn.centerYAnchor.constraint(equalTo: row.centerYAnchor),
                playBtn.widthAnchor.constraint(equalToConstant: 20),
                playBtn.heightAnchor.constraint(equalToConstant: 20),
            ])
            stack.addArrangedSubview(row)
        }

        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 4),
            card.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -4),
            card.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: 16),
            card.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
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

/// Padded UILabel for thread category badges. UILabel's `layoutMargins` does NOT
/// add visual padding around text — we must override `drawText(in:)` and
/// `intrinsicContentSize` to properly inset badge text inside its background.
private final class ThreadBadgeLabel: UILabel {
    let hPad: CGFloat = 6   // horizontal padding
    let vPad: CGFloat = 2   // vertical padding

    override var intrinsicContentSize: CGSize {
        let base = super.intrinsicContentSize
        return CGSize(width: base.width + hPad * 2, height: base.height + vPad * 2)
    }

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.insetBy(dx: hPad, dy: vPad))
    }
}

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
