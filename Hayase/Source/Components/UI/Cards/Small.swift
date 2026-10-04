//
//  Small.swift
//  Hayase
//
//  Mirrors: src/lib/components/ui/cards/small.svelte and episode.svelte, and src/app.css
//  (@keyframes load-in, global :active scale)
//
//  The card of an episode (`episode.svelte`) and the card of a trace.moe result (`trace.svelte`) are this cell with
//  `episodeStyle` or a `trace` given to `configure`: a collection view reuses one cell class for all its cards, so
//  the three looks are one class and not three. Their skeletons (`skeleton.svelte`, `skeletontrace.svelte`) are
//  in Skeleton.swift, the status dot of the title (`StatusDot.svelte`) is in Components/StatusDot.swift, and the
//  collection view that mounts the cards as `SmallCard` is at the end of this file.
//
//  small.svelte, laid out as the browser does:
//    • outer item w-[11.5rem] h-[323px] with p-4, so the cover is 152×216pt at (16, 16)
//    • below the cover `pt-3`, then the title (font-black text-[.8rem], line-height 1.5, line-clamp-2)
//      with the status dot inline before it, on the baseline
//    • the year and format row is `mt-auto pt-2`: text-xs font-medium text-muted-foreground, with
//      16×16 icons that stick out 2pt past the padding (`-ml-0.5`, `-mr-0.5`)
//

import UIKit

// MARK: - Shared Image Cache (internal so the pages that show banners can use it)

enum SharedImageCache {
    static let shared = NSCache<NSString, UIImage>()
}

// MARK: - AnimeCollectionViewCell

class AnimeCollectionViewCell: UICollectionViewCell, InterfaceMountAnimating {
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

    /// `text-[.8rem] font-black`, on a line of `1.5` (Tailwind's preflight sets `line-height: 1.5`)
    static let titleFont = UIFont.nunito(ofSize: 12.8, weight: .black)
    static let titleLineHeight: CGFloat = 19.2

    /// The title of a card, with the viewer's list status as the dot in front of it. The dot is
    /// inline, so it sits on the baseline of the first line only, and the text wraps beneath it.
    /// Svelte keeps the space between `{/if}` and the title, so there is one after `me-1`.
    static func titleText(_ title: String, status: String?) -> NSAttributedString {
        let attributes = CSSText.attributes(font: titleFont, color: UIColor.HayaseTheme.foreground,
                                            lineHeight: titleLineHeight)
        let result = NSMutableAttributedString()
        if let status {
            result.append(StatusDot.prefix(for: status, attributes: attributes))
        }
        result.append(NSAttributedString(string: title, attributes: attributes))
        return result
    }

    // MARK: Views

    /// small.svelte `.item`: mount animation lives here so the outer press transform can compose with it.
    private let itemView = UIView()

    private static let placeholderCoverColor = UIColor(red: 24/255, green: 144/255, blue: 255/255, alpha: 1)   // web default: #1890ff

    private let coverImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.backgroundColor = AnimeCollectionViewCell.placeholderCoverColor
        iv.layer.cornerRadius = 4
        return iv
    }()

    // `pt-3 font-black text-[.8rem] line-clamp-2`, in `text-foreground`
    private let titleLabel: UILabel = {
        let l = UILabel()
        l.numberOfLines = 2
        l.lineBreakMode = .byTruncatingTail
        l.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return l
    }()

    // `text-xs font-medium` in `text-muted-foreground`: line-height 1rem
    private let yearLabel = AnimeCollectionViewCell.makeMetaLabel()
    private let formatLabel = AnimeCollectionViewCell.makeMetaLabel()

    private static func makeMetaLabel() -> UILabel {
        let l = UILabel()
        l.numberOfLines = 1
        l.setContentHuggingPriority(.required, for: .horizontal)
        l.setContentCompressionResistancePriority(.required, for: .horizontal)
        return l
    }

    private static func metaText(_ text: String) -> NSAttributedString {
        CSSText.string(text, font: .nunito(ofSize: 12, weight: .medium),
                       color: UIColor.HayaseTheme.mutedForeground, lineHeight: 16)
    }

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

    // MARK: State

    private var currentURLString: String?
    private var imageTask: URLSessionDataTask?
    private var coverConfiguredAt: CFTimeInterval = 0
    private var pressAnimator: UIViewPropertyAnimator?
    private(set) var configuredAnimeItem: AnimeItem?
    var hoverProvider: (() -> Void)?
    var unhoverProvider: (() -> Void)?
    private var hoverGesture: UIHoverGestureRecognizer?
    private var viewerStateObservers: [NSObjectProtocol] = []

    override var isHighlighted: Bool {
        didSet { updateInterfacePressedState() }
    }

    // MARK: Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
        observeViewerState()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
        observeViewerState()
    }

    deinit {
        viewerStateObservers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    /// AniList's lists and every other tracker's: the dot follows whichever answers for the media.
    private func observeViewerState() {
        for name in [AniListViewerState.didChange, LocalTracking.didChange] {
            viewerStateObservers.append(NotificationCenter.default.addObserver(forName: name, object: nil,
                                                                               queue: .main) { [weak self] _ in
                self?.updateStatusDot()
            })
        }
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

        // `CalendarDays` / `Tv`: `w-[1rem] h-[1rem]`, in the colour of the text
        let calIcon = Self.makeMetaIcon("calendar-days")
        let tvIcon = Self.makeMetaIcon("tv")

        // `flex text-muted-foreground mt-auto pt-2 justify-between`: [calendar year] ... [format tv]
        // `mr-1 -ml-0.5` and `ml-1 -mr-0.5`: the icons stick out 2pt past the card's padding.
        let spacer = UIView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let metaRow = UIStackView(arrangedSubviews: [calIcon, yearLabel, spacer, formatLabel, tvIcon])
        metaRow.axis = .horizontal
        metaRow.spacing = 4
        metaRow.alignment = .fill
        metaRow.translatesAutoresizingMaskIntoConstraints = false

        // `flex justify-between pt-3 gap-2`: the title, and beside it the match of a trace result
        let titleRow = UIStackView(arrangedSubviews: [titleLabel, traceInfoColumn])
        titleRow.axis = .horizontal
        titleRow.spacing = 8   // gap-2
        titleRow.alignment = .top
        titleRow.translatesAutoresizingMaskIntoConstraints = false

        coverImageView.translatesAutoresizingMaskIntoConstraints = false
        itemView.addSubview(coverImageView)
        itemView.addSubview(titleRow)
        itemView.addSubview(metaRow)

        let posterHeight = coverImageView.heightAnchor.constraint(equalTo: coverImageView.widthAnchor,
                                                                  multiplier: Self.coverHeight / Self.coverWidth)
        let pictureHeight = coverImageView.heightAnchor.constraint(equalToConstant: Self.traceCoverHeight)
        posterCoverHeight = posterHeight
        traceCoverHeightConstraint = pictureHeight
        pictureHeight.isActive = false
        NSLayoutConstraint.activate([
            coverImageView.topAnchor.constraint(equalTo: itemView.topAnchor, constant: Self.contentPadding),
            coverImageView.leadingAnchor.constraint(equalTo: itemView.leadingAnchor, constant: Self.contentPadding),
            coverImageView.trailingAnchor.constraint(equalTo: itemView.trailingAnchor, constant: -Self.contentPadding),
            posterHeight,

            titleRow.topAnchor.constraint(equalTo: coverImageView.bottomAnchor, constant: 12),   // pt-3
            titleRow.leadingAnchor.constraint(equalTo: itemView.leadingAnchor, constant: Self.contentPadding),
            titleRow.trailingAnchor.constraint(equalTo: itemView.trailingAnchor, constant: -Self.contentPadding),

            metaRow.leadingAnchor.constraint(equalTo: itemView.leadingAnchor, constant: Self.contentPadding - 2),
            metaRow.trailingAnchor.constraint(equalTo: itemView.trailingAnchor, constant: -(Self.contentPadding - 2)),
            metaRow.bottomAnchor.constraint(equalTo: itemView.bottomAnchor, constant: -Self.contentPadding),
            metaRow.heightAnchor.constraint(equalToConstant: 16),
            titleRow.bottomAnchor.constraint(lessThanOrEqualTo: metaRow.topAnchor, constant: -8),   // pt-2

            calIcon.widthAnchor.constraint(equalToConstant: 16),
            tvIcon.widthAnchor.constraint(equalToConstant: 16),
        ])
    }

    private static func makeMetaIcon(_ name: String) -> UIImageView {
        let icon = UIImageView(image: UIImage.hayaseIcon(name, pointSize: 16))
        icon.tintColor = UIColor.HayaseTheme.mutedForeground
        icon.contentMode = .center
        icon.setContentHuggingPriority(.required, for: .horizontal)
        icon.setContentCompressionResistancePriority(.required, for: .horizontal)
        return icon
    }

    // MARK: - Interface mount animation

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        requestInterfaceMountAnimation()
    }

    func requestInterfaceMountAnimation() {
        guard let mediaID = configuredAnimeItem?.id,
              let collectionView = CardLoadIn.enclosingCollectionView(of: self) else { return }
        collectionView.requestMountAnimation(for: self, mediaID: mediaID)
    }

    func playInterfaceLoadInAnimation(startedAt: CFTimeInterval) {
        CardLoadIn.play(on: itemView, startedAt: startedAt)
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
            let percent = (trace.similarity * 100).rounded()
            traceSimilarityLabel.text = "\(Int(exactly: percent) ?? 0)%"
        }
        // Matches small.svelte: media.seasonYear ?? media.startDate?.year ?? 'TBA'
        // episode.svelte has no `startDate` fallback: `media.seasonYear ?? 'TBA'`
        let displayYear = isTrace ? item.year : (item.year ?? item.startYear)
        yearLabel.attributedText = Self.metaText(displayYear.flatMap { $0 > 0 ? "\($0)" : nil } ?? "TBA")
        formatLabel.attributedText = Self.metaText(AniListUtil.format(item.format))
        // Set cover color placeholder matching web's load.svelte: style:background={color ?? '#1890ff'}
        coverImageView.backgroundColor = UIColor(hexString: item.coverColor) ?? Self.placeholderCoverColor
        // small.svelte: `coverMedium(media)`, which falls back to `banner(media)`
        // small.svelte `coverMedium(media)`; episode.svelte `trace?.image ?? coverMedium(media)`
        loadCover(urlString: trace?.image ?? item.coverMediumURL ?? item.bannerURL
                  ?? item.trailerYouTubeID.map { "https://i.ytimg.com/vi/\($0)/maxresdefault.jpg" }
                  ?? item.coverURL ?? "")
        updateTitle()
    }

    /// small.svelte `{#if status} <StatusDot>`: the viewer's list status, drawn again whenever the
    /// lists change, as the interface's store tells every card at once.
    private func updateStatusDot() {
        updateTitle()
    }

    private func updateTitle() {
        guard let item = configuredAnimeItem else { return }
        titleLabel.attributedText = Self.titleText(AniListUtil.title(for: item), status: item.listEntry?.status)
    }

    private func loadCover(urlString: String) {
        currentURLString = urlString
        coverConfiguredAt = CACurrentMediaTime()
        resetCoverImage()
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
                guard let self, self.currentURLString == captured else { return }
                // load.svelte: the image fades in over 300ms, and blurred if it came in right away
                LoadIn.show(image, in: self.coverImageView,
                            blurred: CACurrentMediaTime() - self.coverConfiguredAt < LoadIn.blurWindow)
            }
        }
        imageTask?.resume()
    }

    private func resetCoverImage() {
        coverImageView.layer.removeAllAnimations()
        coverImageView.subviews.forEach { $0.removeFromSuperview() }
        coverImageView.image = nil
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        CardLoadIn.cancel(on: itemView)
        pressAnimator?.stopAnimation(true)
        pressAnimator = nil
        contentView.transform = .identity
        imageTask?.cancel()
        imageTask = nil
        currentURLString = nil
        resetCoverImage()
        coverImageView.backgroundColor = Self.placeholderCoverColor
        titleLabel.attributedText = nil
        yearLabel.attributedText = nil
        formatLabel.attributedText = nil
        traceInfoColumn.isHidden = true
        traceEpisodeLabel.text = nil
        traceSimilarityLabel.text = nil
        posterCoverHeight?.isActive = true
        traceCoverHeightConstraint?.isActive = false
        configuredAnimeItem = nil
        hoverTimer?.invalidate()
        hoverTimer = nil
        hoverProvider = nil
        unhoverProvider = nil
    }

    /// navigate.ts `hover`: a pointer has to rest on the card for `HOVER_TIME` (30ms) before the
    /// preview opens, and moving restarts the wait.
    private var hoverTimer: Timer?

    private func scheduleHover() {
        hoverTimer?.invalidate()
        hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: false) { [weak self] _ in
            self?.hoverTimer = nil
            self?.hoverProvider?()
        }
    }

    @objc private func handleHover(_ gesture: UIHoverGestureRecognizer) {
        switch gesture.state {
        case .began:
            scheduleHover()
        case .changed:
            if hoverTimer != nil { scheduleHover() }
        case .ended, .cancelled, .failed:
            hoverTimer?.invalidate()
            hoverTimer = nil
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

// MARK: - AnimeCardCollectionView

//  Mirrors: src/lib/components/ui/cards/small.svelte (component mount animation),
//           src/lib/components/ui/cards/query.svelte and recommendation.svelte (keyed card identity)

/// Gives reusable UIKit cells the same mount semantics as keyed `SmallCard` components.
/// Re-entry starts a fresh component tree; data reloads only mount media IDs that were not
/// already present in the current tree. Scrolling alone never creates a new mount cycle.
final class AnimeCardCollectionView: UICollectionView {
    private static let mountDuration: CFTimeInterval = 0.3  // small.svelte: animation 0.3s

    private var mountedMediaIDsBySection: [Int: Set<Int>] = [:]
    private var componentMountGeneration: UInt?
    private var globalMountStartedAt: CFTimeInterval?
    private var sectionMountStartedAt: [Int: CFTimeInterval] = [:]
    private var wasAttachedToWindow = false
    private var phaseInspectionScheduled = false

    override init(frame: CGRect, collectionViewLayout layout: UICollectionViewLayout) {
        super.init(frame: frame, collectionViewLayout: layout)
        configureInterfaceInteraction()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureInterfaceInteraction()
    }

    private func configureInterfaceInteraction() {
        // Browser :active begins on pointer-down. UIScrollView defaults to delaying touch-down
        // while it decides whether the gesture is a scroll, so disable that delay for cards.
        delaysContentTouches = false
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()

        let isAttached = window != nil
        if isAttached && !wasAttachedToWindow {
            beginFreshComponentTree()
        }
        wasAttachedToWindow = isAttached
    }


    /// Identifies a logical component mount when UIKit reuses the same collection view object.
    /// A new generation is equivalent to Svelte destroying and recreating the card subtree.
    func setComponentMountGeneration(_ generation: UInt) {
        guard componentMountGeneration != generation else { return }
        componentMountGeneration = generation
        beginFreshComponentTree()
    }

    override func reloadData() {
        globalMountStartedAt = CACurrentMediaTime()
        sectionMountStartedAt.removeAll()
        super.reloadData()
        schedulePhaseInspection()
    }

    override func reloadSections(_ sections: IndexSet) {
        let now = CACurrentMediaTime()
        for section in sections {
            sectionMountStartedAt[section] = now
        }
        super.reloadSections(sections)
        schedulePhaseInspection()
    }

    override func reloadItems(at indexPaths: [IndexPath]) {
        let now = CACurrentMediaTime()
        for section in Set(indexPaths.map(\.section)) {
            sectionMountStartedAt[section] = now
        }
        super.reloadItems(at: indexPaths)
        schedulePhaseInspection()
    }

    override func insertItems(at indexPaths: [IndexPath]) {
        let now = CACurrentMediaTime()
        for section in Set(indexPaths.map(\.section)) {
            sectionMountStartedAt[section] = now
        }
        super.insertItems(at: indexPaths)
    }

    override func insertSections(_ sections: IndexSet) {
        let now = CACurrentMediaTime()
        for section in sections {
            sectionMountStartedAt[section] = now
        }
        super.insertSections(sections)
    }

    /// `mediaID` is the key of the card within its section: the media of a `SmallCard`, or any number
    /// that is not shared by two cards of the section (a skeleton uses its position, below zero).
    func requestMountAnimation(for cell: InterfaceMountAnimating, mediaID: Int) {
        guard window != nil,
              let indexPath = indexPath(for: cell) else { return }

        let section = indexPath.section
        var mounted = mountedMediaIDsBySection[section] ?? []
        guard !mounted.contains(mediaID) else { return }
        mounted.insert(mediaID)
        mountedMediaIDsBySection[section] = mounted

        let startedAt = sectionMountStartedAt[section] ?? globalMountStartedAt
        guard let startedAt,
              CACurrentMediaTime() - startedAt < Self.mountDuration else { return }
        cell.playInterfaceLoadInAnimation(startedAt: startedAt)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        inspectVisibleContentPhases()
    }


    private func beginFreshComponentTree() {
        mountedMediaIDsBySection.removeAll()
        sectionMountStartedAt.removeAll()
        globalMountStartedAt = CACurrentMediaTime()
        requestMountForVisibleCardsOnNextRunLoop()
    }

    private func schedulePhaseInspection() {
        guard !phaseInspectionScheduled else { return }
        phaseInspectionScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.phaseInspectionScheduled = false
            self.inspectVisibleContentPhases()
        }
    }

    private func inspectVisibleContentPhases() {
        let visibleIndexPaths = indexPathsForVisibleItems
        guard !visibleIndexPaths.isEmpty else { return }

        let visibleSections = Set(visibleIndexPaths.map(\.section))
        for section in visibleSections {
            let cells = visibleIndexPaths
                .filter { $0.section == section }
                .compactMap { cellForItem(at: $0) }
            guard !cells.isEmpty else { continue }

            // Skeleton/error/empty branches destroy SmallCard components on the web.
            // Clear only that section so the same media IDs mount again when cards return.
            if !cells.contains(where: { $0 is AnimeCollectionViewCell }) {
                mountedMediaIDsBySection[section] = nil
            }
        }
    }

    private func requestMountForVisibleCardsOnNextRunLoop() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            for case let cell as InterfaceMountAnimating in self.visibleCells {
                cell.requestInterfaceMountAnimation()
            }
        }
    }
}

// MARK: - CardLoadIn

//  Mirrors: src/app.css `@keyframes load-in`, which small.svelte, episode.svelte and skeleton.svelte
//  run on their `.item` when they mount: `animation: 0.3s ease 0s 1 load-in`.

/// A card cell that plays the mount animation of its `.item`.
protocol InterfaceMountAnimating: UICollectionViewCell {
    /// Asks the collection view whether this cell is mounting, and plays the animation if so.
    func requestInterfaceMountAnimation()
    func playInterfaceLoadInAnimation(startedAt: CFTimeInterval)
}

enum CardLoadIn {
    static let animationKey = "interfaceLoadIn"
    static let duration: TimeInterval = 0.3
    /// 1.2rem at the 16px root size
    static let offsetY: CGFloat = 19.2
    static let scale: CGFloat = 0.95

    /// `translate3d(0, 1.2rem, 0) scale(0.95)` to none, with CSS `ease`.
    static func play(on view: UIView, startedAt: CFTimeInterval) {
        view.layer.removeAnimation(forKey: animationKey)
        view.transform = .identity

        let animation = CABasicAnimation(keyPath: "transform")
        animation.fromValue = CATransform3DMakeAffineTransform(
            CGAffineTransform(a: scale, b: 0, c: 0, d: scale, tx: 0, ty: offsetY))
        animation.toValue = CATransform3DIdentity
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(controlPoints: 0.25, 0.1, 0.25, 1)
        animation.beginTime = view.layer.convertTime(startedAt, from: nil)
        view.layer.add(animation, forKey: animationKey)
    }

    static func cancel(on view: UIView) {
        view.layer.removeAnimation(forKey: animationKey)
        view.transform = .identity
    }

    /// The collection view an `InterfaceMountAnimating` cell is in, if it is an `AnimeCardCollectionView`.
    static func enclosingCollectionView(of cell: UIView) -> AnimeCardCollectionView? {
        var candidate = cell.superview
        while let view = candidate {
            if let collectionView = view as? AnimeCardCollectionView { return collectionView }
            candidate = view.superview
        }
        return nil
    }
}
