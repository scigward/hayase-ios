//
//  AnimeCollectionViewCell.swift
//  Hayase
//
//  Mirrors: src/lib/components/ui/cards/small.svelte and src/app.css (@keyframes load-in, global :active scale)
//
//  Matches Hayase's small.svelte exactly:
//    • Outer item w-[11.5rem] h-[323px] with p-4, matching small.svelte
//    • Inner cover area w-[9.5rem] h-[13.5rem] = 152×216pt
//    • Below cover: pt-3 (12pt) gap → title row [statusDot? + title, line-clamp-2] → mt-auto/pt-2 → meta row
//    • StatusDot: size-[0.55rem] ≈ 8.8pt circle, inline before title, hidden when no list entry
//      Colors from StatusDot.svelte: CURRENT=rgb(61,180,242), PLANNING=rgb(247,154,99),
//      COMPLETED=rgb(123,213,85), PAUSED=rgb(250,122,122), REPEATING=#3baeea, DROPPED=rgb(200,80,80)
//    • Meta row: year left (calendar icon) + format right (tv icon), text-neutral-500
//    •   pushed to the bottom by mt-auto, just like small.svelte
//

import UIKit

// MARK: - Interface card mount animation

// small.svelte: .item { animation: 0.3s ease 0s 1 load-in; }
// app.css load-in: translate3d(0, 1.2rem, 0) scale(0.95) -> none.
private enum InterfaceAnimeCardLoadAnimation {
    static let animationKey = "interfaceLoadIn"
    static let duration: TimeInterval = 0.3
    static let offsetY: CGFloat = 19.2  // 1.2rem = 19.2px at the 16px root size
    static let scale: CGFloat = 0.95
    static let controlPoint1 = CGPoint(x: 0.25, y: 0.1)  // CSS ease
    static let controlPoint2 = CGPoint(x: 0.25, y: 1)

    static var initialTransform: CGAffineTransform {
        CGAffineTransform(a: scale, b: 0, c: 0, d: scale, tx: 0, ty: offsetY)
    }
}

// MARK: - Shared Image Cache (internal so BrowseAnimeViewController can use it)

enum SharedImageCache {
    static let shared = NSCache<NSString, UIImage>()
}

// MARK: - AnimeCollectionViewCell

class AnimeCollectionViewCell: UICollectionViewCell {
    static let reuseID = "AnimeCell"

    // small.svelte: outer item w-[11.5rem] h-[323px] p-4, inner cover w-[9.5rem] h-[13.5rem].
    static let outerWidth: CGFloat = 184
    static let outerHeight: CGFloat = 323
    static let contentPadding: CGFloat = 16
    static let coverWidth: CGFloat = 152
    static let coverHeight: CGFloat = 216
    // episode.svelte: `w-[16rem]` item with `p-4`, and a `h-[9rem]` picture
    static let traceOuterWidth: CGFloat = 288
    static let traceCoverHeight: CGFloat = 144

    // MARK: Views

    /// small.svelte `.item`: mount animation lives here so the outer press transform can compose with it.
    private let itemView = UIView()

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

    // episode.svelte, on a trace result: `Episode N` over the match, `text-xs font-medium text-right`
    private let traceEpisodeLabel: UILabel = {
        let l = UILabel()
        l.font = .nunito(ofSize: 12, weight: .medium)
        l.textColor = UIColor.HayaseTheme.foreground
        l.textAlignment = .right
        return l
    }()

    private let traceSimilarityLabel: UILabel = {
        let l = UILabel()
        l.font = .nunito(ofSize: 12, weight: .medium)
        l.textColor = UIColor.HayaseTheme.mutedForeground
        l.textAlignment = .right
        return l
    }()

    private lazy var traceInfoColumn: UIStackView = {
        let column = UIStackView(arrangedSubviews: [traceEpisodeLabel, traceSimilarityLabel])
        column.axis = .vertical
        column.alignment = .trailing
        column.spacing = 2   // mt-0.5
        column.isLayoutMarginsRelativeArrangement = true
        column.layoutMargins = UIEdgeInsets(top: 1, left: 0, bottom: 0, right: 0)   // pt-[1px]
        column.isHidden = true
        column.setContentHuggingPriority(.required, for: .horizontal)
        column.setContentCompressionResistancePriority(.required, for: .horizontal)
        return column
    }()

    /// The cover is a 152x216 poster, or the 9rem tall picture of a trace result.
    private var posterCoverHeight: NSLayoutConstraint?
    private var traceCoverHeightConstraint: NSLayoutConstraint?

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
    private var pressAnimator: UIViewPropertyAnimator?
    private(set) var configuredAnimeItem: AnimeItem?
    var hoverProvider: (() -> Void)?
    var unhoverProvider: (() -> Void)?
    private var hoverGesture: UIHoverGestureRecognizer?

    override var isHighlighted: Bool {
        didSet { updateInterfacePressedState() }
    }

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
        clipsToBounds = false
        layer.masksToBounds = false
        contentView.clipsToBounds = false
        contentView.layer.masksToBounds = false

        itemView.backgroundColor = .clear
        itemView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(itemView)
        NSLayoutConstraint.activate([
            itemView.topAnchor.constraint(equalTo: contentView.topAnchor),
            itemView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            itemView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            itemView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])

        if #available(iOS 13.0, *) {
            let hover = UIHoverGestureRecognizer(target: self, action: #selector(handleHover(_:)))
            addGestureRecognizer(hover)
            hoverGesture = hover
        }

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
        let titleRow = UIStackView(arrangedSubviews: [statusDotView, titleLabel, traceInfoColumn])
        titleRow.axis = .horizontal
        titleRow.spacing = 4   // me-1 = 4pt
        titleRow.alignment = .top
        titleRow.setCustomSpacing(8, after: titleLabel)   // gap-2 before the trace column

        // Full card stack: [cover  titleRow  flexible spacer  metaRow]
        // Web small.svelte uses an outer w-[11.5rem] h-[323px] item with p-4.
        // The row itself has no top padding; this 16pt card padding is what places
        // the visible cover below the section title.
        let spacer = UIView()
        spacer.setContentHuggingPriority(.defaultLow, for: .vertical)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .vertical)

        let cardStack = UIStackView(arrangedSubviews: [coverImageView, titleRow, spacer, metaRow])
        cardStack.axis = .vertical
        cardStack.spacing = 0
        cardStack.setCustomSpacing(12, after: coverImageView) // pt-3 = 12pt
        cardStack.setCustomSpacing(8, after: titleRow)        // meta pt-2 = 8pt minimum
        cardStack.translatesAutoresizingMaskIntoConstraints = false
        itemView.addSubview(cardStack)

        let posterHeight = coverImageView.heightAnchor.constraint(equalTo: coverImageView.widthAnchor,
                                                                  multiplier: Self.coverHeight / Self.coverWidth)
        let pictureHeight = coverImageView.heightAnchor.constraint(equalToConstant: Self.traceCoverHeight)
        posterCoverHeight = posterHeight
        traceCoverHeightConstraint = pictureHeight
        pictureHeight.isActive = false
        NSLayoutConstraint.activate([
            posterHeight,
            cardStack.topAnchor.constraint(equalTo: itemView.topAnchor, constant: Self.contentPadding),
            cardStack.leadingAnchor.constraint(equalTo: itemView.leadingAnchor, constant: Self.contentPadding),
            cardStack.trailingAnchor.constraint(equalTo: itemView.trailingAnchor, constant: -Self.contentPadding),
            cardStack.bottomAnchor.constraint(equalTo: itemView.bottomAnchor, constant: -Self.contentPadding),

            // h-[13.5rem] over w-[9.5rem].  Tie it to the inner card width so the same
            // cell still scales correctly if reused in grids with different item widths.

            calIcon.widthAnchor.constraint(equalToConstant: 12),
            calIcon.heightAnchor.constraint(equalToConstant: 12),
            tvIcon.widthAnchor.constraint(equalToConstant: 12),
            tvIcon.heightAnchor.constraint(equalToConstant: 12),

            // Status dot: size-[0.55rem] = 8.8pt circle, aligned to first line of title
            statusDotView.widthAnchor.constraint(equalToConstant: 8.8),
            statusDotView.heightAnchor.constraint(equalToConstant: 8.8),
        ])
    }


    // MARK: - Interface mount animation

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        requestInterfaceMountAnimation()
    }

    func requestInterfaceMountAnimation() {
        guard let mediaID = configuredAnimeItem?.id,
              let collectionView = enclosingAnimeCardCollectionView() else { return }
        collectionView.requestMountAnimation(for: self, mediaID: mediaID)
    }

    func playInterfaceLoadInAnimation(startedAt: CFTimeInterval) {
        itemView.layer.removeAnimation(forKey: InterfaceAnimeCardLoadAnimation.animationKey)
        itemView.transform = .identity

        let animation = CABasicAnimation(keyPath: "transform")
        animation.fromValue = CATransform3DMakeAffineTransform(InterfaceAnimeCardLoadAnimation.initialTransform)
        animation.toValue = CATransform3DIdentity
        animation.duration = InterfaceAnimeCardLoadAnimation.duration
        animation.timingFunction = CAMediaTimingFunction(
            controlPoints: Float(InterfaceAnimeCardLoadAnimation.controlPoint1.x),
            Float(InterfaceAnimeCardLoadAnimation.controlPoint1.y),
            Float(InterfaceAnimeCardLoadAnimation.controlPoint2.x),
            Float(InterfaceAnimeCardLoadAnimation.controlPoint2.y)
        )
        animation.beginTime = itemView.layer.convertTime(startedAt, from: nil)
        itemView.layer.add(animation, forKey: InterfaceAnimeCardLoadAnimation.animationKey)
    }

    private func enclosingAnimeCardCollectionView() -> AnimeCardCollectionView? {
        var candidate = superview
        while let view = candidate {
            if let collectionView = view as? AnimeCardCollectionView { return collectionView }
            candidate = view.superview
        }
        return nil
    }

    // app.css: :active { transition: all 0.1s ease-in-out; transform: scale(0.98); }
    private func updateInterfacePressedState() {
        pressAnimator?.stopAnimation(true)
        pressAnimator = nil

        guard isHighlighted else {
            contentView.transform = .identity
            return
        }

        let animator = UIViewPropertyAnimator(
            duration: 0.1,
            controlPoint1: CGPoint(x: 0.42, y: 0),
            controlPoint2: CGPoint(x: 0.58, y: 1)
        ) { [weak self] in
            self?.contentView.transform = CGAffineTransform(scaleX: 0.98, y: 0.98)
        }
        pressAnimator = animator
        animator.startAnimation()
    }

    // MARK: - Configuration

    /// `episodeStyle` is episode.svelte's card: the wide one the trace page draws, with or without a
    /// frame matched to it.
    func configure(with item: AnimeItem, trace: TraceAnime? = nil, episodeStyle: Bool = false) {
        configuredAnimeItem = item
        let isTrace = episodeStyle
        posterCoverHeight?.isActive = !isTrace
        traceCoverHeightConstraint?.isActive = isTrace
        traceInfoColumn.isHidden = trace == nil   // the match goes beside the title only when there is one
        if let trace {
            traceEpisodeLabel.text = "Episode \(trace.episode)"
            traceSimilarityLabel.text = "\(Int((trace.similarity * 100).rounded()))%"
        }
        titleLabel.text = AniListUtil.title(for: item)
        // Matches small.svelte: media.seasonYear ?? media.startDate?.year ?? 'TBA'
        // episode.svelte has no `startDate` fallback: `media.seasonYear ?? 'TBA'`
        let displayYear = isTrace ? item.year : (item.year ?? item.startYear)
        yearLabel.text = displayYear.flatMap { $0 > 0 ? "\($0)" : nil } ?? "TBA"
        formatLabel.text = formatString(item.format)
        // Set cover color placeholder matching web's load.svelte: style:background={color ?? '#1890ff'}
        coverImageView.backgroundColor = UIColor(hexString: item.coverColor) ?? UIColor(red: 24/255, green: 144/255, blue: 255/255, alpha: 1)
        // small.svelte: `coverMedium(media)`, which falls back to `banner(media)`
        // small.svelte `coverMedium(media)`; episode.svelte `trace?.image ?? coverMedium(media)`
        loadCover(urlString: trace?.image ?? item.coverMediumURL ?? item.bannerURL
                  ?? item.trailerYouTubeID.map { "https://i.ytimg.com/vi/\($0)/maxresdefault.jpg" }
                  ?? item.coverURL ?? "")
        // Status dot — show user's AniList list status when logged in (matches small.svelte: {#if status} <StatusDot>)
        if let status = (item.mediaListEntry ?? TrackerAggregator.externalEntry(for: item.id))?.status {
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
        AniListUtil.format(raw)
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
        itemView.layer.removeAnimation(forKey: InterfaceAnimeCardLoadAnimation.animationKey)
        pressAnimator?.stopAnimation(true)
        pressAnimator = nil
        itemView.transform = .identity
        contentView.transform = .identity
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
        traceInfoColumn.isHidden = true
        traceEpisodeLabel.text = nil
        traceSimilarityLabel.text = nil
        posterCoverHeight?.isActive = true
        traceCoverHeightConstraint?.isActive = false
        configuredAnimeItem = nil
        hoverProvider = nil
        unhoverProvider = nil
    }

    @objc private func handleHover(_ gesture: UIHoverGestureRecognizer) {
        switch gesture.state {
        case .began, .changed:
            hoverProvider?()
        case .ended, .cancelled, .failed:
            unhoverProvider?()
        default:
            break
        }
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

