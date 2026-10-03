//
//  FullBanner.swift
//  Hayase
//
//  Mirrors: interface components/ui/banner/full-banner.svelte
//
//  The featured media of Home, one at a time:
//  • the media are the ones with a banner or a trailer, in a fixed order of their ids, the first five
//  • the title (or the logo of the show), the badges, the buttons and the description; the
//    description and the genres move to a second column from `lg`
//  • the progress badges at the bottom, which also rotate the media every 15 seconds
//  • the image behind all of this is not drawn here but by `BannerImageView`, behind the route
//
//  The code is in pieces, as the markup is: `FullBannerTitle`, `FullBannerBadges`,
//  `FullBannerFollowing`, `FullBannerProgress`, and in extensions the layout and the artwork.
//

import UIKit

final class FullBannerCell: UICollectionViewCell {
    static let reuseID = "FullBannerCell"

    /// play.svelte: "Rewatch", "Continue" or "Watch Now".
    static func playButtonTitle(status: String?) -> String {
        switch status {
        case "COMPLETED": return "Rewatch"
        case "CURRENT", "REPEATING", "PAUSED": return "Continue"
        default: return "Watch Now"
        }
    }

    // MARK: Callbacks

    /// The title or the logo was clicked: `href='/#/app/anime/{current.id}'`.
    var onTitleTapped: ((AnimeItem) -> Void)?
    /// The play button (`playEp`).
    var onPlayTapped: ((AnimeItem) -> Void)?
    var onFavorite: ((AnimeItem) -> Void)?
    var onBookmark: ((AnimeItem) -> Void)?
    /// A badge or a genre was clicked.
    var onFilter: ((BannerFilter) -> Void)?
    /// Supplies the resolved BannerImage source to the route-level backdrop.
    var onBackdropImageChanged: ((_ urlString: String?, _ image: UIImage?) -> Void)?
    var onFeaturedChanged: ((Int) -> Void)?

    // MARK: State

    var items: [AnimeItem] = []
    var currentIndex = 0
    var currentItem: AnimeItem? { items[safe: currentIndex] }

    var bannerTask: URLSessionDataTask?
    var fanartTask: URLSessionDataTask?
    var clearlogoTask: URLSessionDataTask?
    /// Counts the media shown; the answer to a clearlogo request for another one is dropped.
    var artworkGeneration = 0
    /// Counts banner loads; a superseded load, even one for the same item, is dropped.
    var bannerGeneration = 0
    /// Whether the artwork on screen was chosen for a viewport of `md` or wider.
    var loadedBackdropArtwork: Bool?
    /// The banner load waiting for the cell to reach a window.
    var artworkPending = false
    var currentSidebarBackdropURL: String?
    /// Whether the banner is faded out (`hideBanner`).
    var bannerHidden = false
    var followingUsersByMediaID: [Int: [AniListUserSummary]] = [:]
    var featuredLayoutKey: Int?
    var lastViewportWidth: CGFloat?

    // MARK: Views

    let followingView = FullBannerFollowingView()
    let titleLink = FullBannerTitleLink()

    /// Description: text-foreground/70 text-xs lg:text-sm text-center lg:text-right text-shadow-lg
    /// line-clamp-2 lg:line-clamp-3 text-balance max-w-[90%] lg:max-w-[75%] pt-3
    let descriptionLabel: TextShadowLabel = {
        let l = TextShadowLabel()
        // text-xs = 12pt on 16pt lines (lg: text-sm, 14pt on 20pt lines)
        l.lineHeight = 16
        l.font = .nunito(ofSize: 12)
        l.textColor = UIColor.HayaseTheme.foreground.withAlphaComponent(0.7)   // text-foreground/70
        l.numberOfLines = 2
        l.textAlignment = .center
        l.balancesText = true   // text-balance
        return l
    }()
    var descriptionMaxWidthConstraint: NSLayoutConstraint!

    /// Badge row: `hidden sm:flex gap-2`
    let badgeStack: UIStackView = {
        let sv = UIStackView()
        sv.axis = .horizontal
        sv.spacing = 8
        sv.alignment = .center
        return sv
    }()

    /// Genre buttons: `hidden lg:flex gap-2`, at the bottom right of the grid.
    let genresStack: UIStackView = {
        let sv = UIStackView()
        sv.axis = .horizontal
        sv.spacing = 8
        sv.alignment = .center
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()
    // `max-w-full lg:place-content-end` without wrapping: a long row overflows the column to
    // its left rather than squeezing, so the stack is pinned by its trailing edge alone.
    let genresContainer = UIView()

    /// PlayButton, size='default': h-9 px-4 text-sm font-bold, `bg-custom select:!bg-custom-600
    /// text-contrast`, in the default variant and so with its `shadow`.
    let playButton: SelectButton = {
        let b = SelectButton()
        b.applyPrimaryVariant()
        b.setTitle(FullBannerCell.playButtonTitle(status: nil), for: .normal)
        // Play fill='currentColor' class='mr-2' size={iconSizes.default}: 0.8rem and 8pt before the text
        b.setImage(UIImage.hayaseFilledIcon("play", pointSize: 12.8), for: .normal)
        b.imageEdgeInsets = UIEdgeInsets(top: 0, left: -4, bottom: 0, right: 4)
        b.titleEdgeInsets = UIEdgeInsets(top: 0, left: 4, bottom: 0, right: -4)
        b.titleLabel?.font = .nunito(ofSize: 14, weight: .bold)
        return b
    }()

    /// FavoriteButton and BookmarkButton, variant='ghost' size='icon' (size-9), icon 1rem. A ghost button's
    /// `select:bg-secondary-foreground/20 select:text-accent-foreground`, and the banner adds `select:!text-custom`.
    let favoriteButton = FullBannerCell.makeIconButton(animation: .heartBeat)
    let bookmarkButton = FullBannerCell.makeIconButton(animation: .wobble)

    private static func makeIconButton(animation: SelectButton.IconAnimation) -> SelectButton {
        let b = SelectButton()
        b.applyGhostVariant()
        b.iconAnimation = animation
        return b
    }

    let progressView = FullBannerProgressView()

    // MARK: Layout

    /// The grid: `grid grid-cols-1 lg:grid-cols-2`, with the left column (title, badges, buttons) and the
    /// right one (description, genres).
    let columnsStack = UIStackView()
    let leftColumn = UIStackView()
    let rightColumn = UIStackView()

    var followingTopConstraint: NSLayoutConstraint!
    var followingLeadingConstraint: NSLayoutConstraint!
    var columnsLeadingConstraint: NSLayoutConstraint!
    var clearlogoAspectConstraint: NSLayoutConstraint?

    // MARK: Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        for name in [AniListViewerState.didChange, LocalTracking.didChange] {
            NotificationCenter.default.addObserver(self, selector: #selector(viewerStateChanged), name: name, object: nil)
        }
        // The image lives behind the route and runs past the hero into the first row's fade.
        clipsToBounds = false
        contentView.clipsToBounds = false
        contentView.backgroundColor = .clear

        // group/banner: the pointer over the banner holds the rotation
        contentView.addGestureRecognizer(UIHoverGestureRecognizer(target: self, action: #selector(bannerHoverChanged(_:))))

        followingView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(followingView)

        // Button row: [Play (grow)  Favorite  Bookmark], `flex flex-row w-[280px] max-w-full`
        let buttonRow = UIStackView(arrangedSubviews: [playButton, favoriteButton, bookmarkButton])
        buttonRow.axis = .horizontal
        buttonRow.spacing = 8                               // ml-2 on the two icon buttons
        buttonRow.alignment = .center
        buttonRow.distribution = .fill
        buttonRow.setCustomSpacing(16, after: playButton)  // Play mr-2 + Favorite ml-2
        playButton.setContentHuggingPriority(.defaultLow, for: .horizontal)
        favoriteButton.setContentHuggingPriority(.required, for: .horizontal)
        bookmarkButton.setContentHuggingPriority(.required, for: .horizontal)
        favoriteButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        bookmarkButton.setContentCompressionResistancePriority(.required, for: .horizontal)

        playButton.addTarget(self, action: #selector(playButtonTapped), for: .touchUpInside)
        favoriteButton.addTarget(self, action: #selector(favoriteTapped), for: .touchUpInside)
        bookmarkButton.addTarget(self, action: #selector(bookmarkTapped), for: .touchUpInside)

        titleLink.onTap = { [weak self] in
            guard let self, let item = self.currentItem else { return }
            self.onTitleTapped?(item)
        }

        // Left column: `w-full flex flex-col items-center text-center lg:items-start lg:text-left
        // justify-end gap-4`. The description comes below the buttons; from `lg` it moves right.
        leftColumn.axis = .vertical
        leftColumn.spacing = 16  // gap-4
        leftColumn.alignment = .center
        leftColumn.addArrangedSubview(titleLink)
        leftColumn.addArrangedSubview(badgeStack)
        leftColumn.addArrangedSubview(buttonRow)
        leftColumn.addArrangedSubview(descriptionLabel)
        leftColumn.setCustomSpacing(12, after: buttonRow) // pt-3 before the description

        // Right column: `flex flex-col self-end lg:items-end items-center lg:pr-5 w-full min-w-0`; the
        // description has pt-3 and the genres pt-4, each on itself, so there is no gap.
        rightColumn.axis = .vertical
        rightColumn.spacing = 0
        rightColumn.alignment = .trailing
        rightColumn.isHidden = true

        genresContainer.addSubview(genresStack)
        rightColumn.addArrangedSubview(genresContainer)
        NSLayoutConstraint.activate([
            genresContainer.widthAnchor.constraint(equalTo: rightColumn.widthAnchor, constant: -20),   // lg:pr-5
            genresContainer.heightAnchor.constraint(equalTo: genresStack.heightAnchor),
            genresStack.topAnchor.constraint(equalTo: genresContainer.topAnchor),
            genresStack.trailingAnchor.constraint(equalTo: genresContainer.trailingAnchor),
        ])

        // `grid grid-cols-1 lg:grid-cols-2 mt-auto w-full max-h-full`
        columnsStack.axis = .vertical
        columnsStack.spacing = 0
        columnsStack.alignment = .fill
        columnsStack.distribution = .fillEqually
        columnsStack.addArrangedSubview(leftColumn)
        columnsStack.addArrangedSubview(rightColumn)
        columnsStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(columnsStack)

        progressView.translatesAutoresizingMaskIntoConstraints = false
        progressView.onSelect = { [weak self] index in
            guard let self, index >= 0, index < self.items.count, index != self.currentIndex else { return }
            self.currentIndex = index
            self.displayItem(fadeIn: false)
        }
        progressView.onFinished = { [weak self] in
            guard let self, self.items.count > 1 else { return }
            self.currentIndex = (self.currentIndex + 1) % self.items.count
            self.displayItem(fadeIn: false)
        }
        contentView.addSubview(progressView)

        followingTopConstraint = followingView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16)
        followingLeadingConstraint = followingView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16)
        columnsLeadingConstraint = columnsStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor)

        // The logo is `w-[30rem]` and no wider than the link that holds it.
        let logoWidth = titleLink.logoView.widthAnchor.constraint(equalToConstant: 480)
        logoWidth.priority = .defaultHigh
        let logoMaxWidth = titleLink.logoView.widthAnchor.constraint(lessThanOrEqualTo: leftColumn.widthAnchor,
                                                                     multiplier: FullBannerTitleLink.maxWidthFraction)
        // The description is at most 90% of the grid; from `lg` 75% of the right column (layout).
        descriptionMaxWidthConstraint = descriptionLabel.widthAnchor.constraint(
            lessThanOrEqualTo: columnsStack.widthAnchor, multiplier: 0.90)

        titleLink.constrainWidth(to: leftColumn)

        NSLayoutConstraint.activate([
            followingTopConstraint,
            followingLeadingConstraint,

            // `pt-2 pb-4` is inside the progress badges, which end at the bottom of the banner
            progressView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            progressView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            columnsLeadingConstraint,
            columnsStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            // grid pb-2
            columnsStack.bottomAnchor.constraint(equalTo: progressView.topAnchor, constant: -8),

            descriptionMaxWidthConstraint,
            logoWidth,
            logoMaxWidth,

            buttonRow.widthAnchor.constraint(equalToConstant: 280),
            playButton.heightAnchor.constraint(equalToConstant: 36),
            favoriteButton.widthAnchor.constraint(equalToConstant: 36),
            favoriteButton.heightAnchor.constraint(equalToConstant: 36),
            bookmarkButton.widthAnchor.constraint(equalToConstant: 36),
            bookmarkButton.heightAnchor.constraint(equalToConstant: 36),
        ])

        applyLayout(forWidth: 0)
    }

    // MARK: Configuration

    func configure(with items: [AnimeItem], selectedID: Int? = nil) {
        // full-banner.svelte shuffleAndFilter: those with a banner or trailer, in a fixed
        // id-hash order, first 5.
        let nextItems = Array(items
            .filter { $0.bannerURL != nil || $0.trailerYouTubeID != nil }
            .sorted { Self.featuredOrder($0.id) < Self.featuredOrder($1.id) }
            .prefix(5))
        if self.items.map(\.id) == nextItems.map(\.id), !nextItems.isEmpty {
            self.items = nextItems
            return
        }
        let keepID = currentItem?.id ?? selectedID
        self.items = nextItems
        followingUsersByMediaID = [:]
        currentIndex = nextItems.firstIndex { $0.id == keepID } ?? 0
        rebuildProgress()
        // The interface's `fade-in` plays when the banner mounts, not on every rotation.
        displayItem(fadeIn: selectedID == nil)
        if !self.items.isEmpty { loadFollowingUsers(for: self.items) }
    }

    /// The interface builds Home again on every visit: the banner starts over at its first
    /// item, plays its fade-in and loads its artwork in afresh.
    func remount() {
        guard !items.isEmpty else { return }
        currentIndex = 0
        // A fresh banner comes with its badges in place; nothing slides.
        rebuildProgress()
        followingView.reset()
        displayItem(fadeIn: true)
    }

    /// Reflect saved state: the icon is filled if already favourited/bookmarked, as FavoriteButton and
    /// BookmarkButton do with `fill='currentColor'`, and play.svelte's label follows the status of the
    /// media's list entry. They read stores, so they follow the viewer's lists and the media's own
    /// `isFavourite` whenever those change; none of them asks AniList.
    private func updateViewerButtons(for item: AnimeItem) {
        let entry = item.listEntry
        favoriteButton.setImage(item.isFavouriteForViewer
            ? UIImage.hayaseFilledIcon("heart", pointSize: 16)
            : UIImage.hayaseIcon("heart", pointSize: 16), for: .normal)
        bookmarkButton.setImage(entry != nil
            ? UIImage.hayaseFilledIcon("bookmark", pointSize: 16)
            : UIImage.hayaseIcon("bookmark", pointSize: 16), for: .normal)
        playButton.setTitle(Self.playButtonTitle(status: entry?.status), for: .normal)
    }

    @objc private func viewerStateChanged() {
        guard let item = currentItem else { return }
        updateViewerButtons(for: item)
    }

    private func rebuildProgress() {
        let color = Self.uiColor(fromHex: currentItem?.coverColor) ?? .white
        progressView.configure(count: items.count, activeIndex: currentIndex, color: color)
    }

    func displayItem(fadeIn: Bool) {
        guard currentIndex < items.count else { return }
        artworkGeneration += 1
        let item = items[currentIndex]
        onFeaturedChanged?(item.id)

        // `bg-custom` and `!text-custom` are the cover's colour (`--custom`, white without one)
        let customColor = Self.uiColor(fromHex: item.coverColor) ?? .white

        // The new media replaces the old one at once, never sliding: this can run inside an animation
        // (the badges of the progress row are one), which would carry the title, the badges and the
        // buttons along with it.
        UIView.performWithoutAnimation {
            // Hide both title and clearlogo initially — the ani.zip request resolves which to show.
            // `{#await episodesCached()}` shows nothing while loading, then the logo or the text.
            titleLink.titleLabel.content = AniListUtil.title(for: item)
            titleLink.titleLabel.isHidden = true
            titleLink.logoView.isHidden = true
            titleLink.logoView.image = nil
            // desc(): "No description available." only where AniList has none; the element's white space
            // collapses, so a paragraph break does not break the line.
            descriptionLabel.content = item.description.map(CSSText.collapsingWhitespace) ?? "No description available."
            descriptionLabel.isHidden = false

            updateBadges(for: item, customColor: customColor)
            // text-contrast: black or white by luminance. select:!bg-custom-600 darkens the play button.
            let textColor = Self.contrastColor(for: customColor)
            playButton.restingBackground = customColor
            playButton.selectedBackground = customColor.withHSLLightness(0.4)
            playButton.restingTint = textColor
            playButton.selectedTint = textColor
            // The icon buttons are currentColor, filled or not, and only turn custom while selected.
            favoriteButton.selectedTint = customColor
            bookmarkButton.selectedTint = customColor
            updateViewerButtons(for: item)
            updateFollowing(for: item)
            layoutIfNeeded()
        }
        progressView.setActive(currentIndex, color: customColor)

        if fadeIn && !UIAccessibility.isReduceMotionEnabled {
            // The title link (text or logo) and the description carry `fade-in`. A layer
            // animation keeps running while its view is hidden, so a logo that arrives
            // later appears part-way through the fade, as it does in the interface.
            titleLink.layer.add(FullBannerFollowingView.mountFade(), forKey: "featured-fade-in")
            descriptionLabel.layer.add(FullBannerFollowingView.mountFade(), forKey: "featured-fade-in")
        }
        // Which artwork applies depends on the viewport, known once the cell is on screen.
        if window != nil {
            loadBanner(for: item)
        } else {
            artworkPending = true
        }
        loadClearlogo(for: item)
    }

    // MARK: Following

    private func loadFollowingUsers(for items: [AnimeItem]) {
        let ids = items.map(\.id)
        AniListClient.shared.fetchFollowingManyResult(animeIDs: ids) { [weak self] result in
            guard let self = self else { return }
            let currentIDs = self.items.map(\.id).sorted()
            guard currentIDs == ids.sorted() else { return }
            switch result {
            case .success(let usersByMediaID):
                self.followingUsersByMediaID = usersByMediaID
            case .failure(let error):
                NSLog("[Home] followingMany failed: %@", error.description)
                self.followingUsersByMediaID = [:]
            }
            if let current = self.currentItem {
                self.updateFollowing(for: current)
            }
        }
    }

    private func updateFollowing(for item: AnimeItem) {
        followingView.configure(users: followingUsersByMediaID[item.id] ?? [])
    }

    // MARK: Badges

    private func updateBadges(for item: AnimeItem, customColor: UIColor) {
        badgeStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let onFilter: (BannerFilter) -> Void = { [weak self] filter in self?.onFilter?(filter) }
        FullBannerBadges.badgeViews(for: item, color: customColor, onFilter: onFilter)
            .forEach { badgeStack.addArrangedSubview($0) }
        updateGenres(for: item, customColor: customColor)
    }

    /// The genre buttons of the two-column layout: every genre, unwrapped (`flex-nowrap`).
    func updateGenres(for item: AnimeItem, customColor: UIColor) {
        genresStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        guard viewportWidth >= 1024 else {
            genresContainer.isHidden = true
            return
        }
        genresContainer.isHidden = false
        let onFilter: (BannerFilter) -> Void = { [weak self] filter in self?.onFilter?(filter) }
        FullBannerBadges.genreViews(for: item, color: customColor, onFilter: onFilter)
            .forEach { genresStack.addArrangedSubview($0) }
    }

    // MARK: Actions

    @objc private func playButtonTapped() {
        guard let item = currentItem else { return }
        onPlayTapped?(item)
    }

    @objc private func favoriteTapped() {
        guard let item = currentItem else { return }
        onFavorite?(item)
    }

    @objc private func bookmarkTapped() {
        guard let item = currentItem else { return }
        onBookmark?(item)
    }

    @objc private func bannerHoverChanged(_ recognizer: UIHoverGestureRecognizer) {
        switch recognizer.state {
        case .began:
            progressView.setPointerOver(true)
        case .ended, .cancelled:
            progressView.setPointerOver(false)
        default:
            break
        }
    }

    // MARK: Lifecycle

    override func layoutSubviews() {
        super.layoutSubviews()
        applyLayout(forWidth: viewportWidth)
        updateBalancedWidths()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        applyLayout(forWidth: viewportWidth)
        if artworkPending, let item = currentItem {
            artworkPending = false
            loadBanner(for: item)
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        progressView.reset()
        artworkGeneration += 1
        bannerGeneration += 1
        loadedBackdropArtwork = nil
        artworkPending = false
        bannerTask?.cancel()
        bannerTask = nil
        fanartTask?.cancel()
        fanartTask = nil
        clearlogoTask?.cancel()
        clearlogoTask = nil
        items = []
        followingUsersByMediaID = [:]
        titleLink.logoView.image = nil
        titleLink.logoView.isHidden = true
        titleLink.titleLabel.isHidden = false
        followingView.reset()
        bannerHidden = false
    }

    // MARK: Colours

    /// `((id * 2654435761) >>> 0)`: the id hashed into 32 bits.
    private static func featuredOrder(_ id: Int) -> UInt32 {
        UInt32(truncatingIfNeeded: UInt64(truncatingIfNeeded: id) &* 2_654_435_761)
    }

    /// Parse hex color string (e.g. "#e3566b") to UIColor
    static func uiColor(fromHex hex: String?) -> UIColor? {
        guard let hex = hex?.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: ""),
              hex.count == 6,
              let rgb = UInt32(hex, radix: 16) else { return nil }
        return UIColor(red: CGFloat((rgb >> 16) & 0xFF) / 255.0,
                       green: CGFloat((rgb >> 8) & 0xFF) / 255.0,
                       blue: CGFloat(rgb & 0xFF) / 255.0,
                       alpha: 1.0)
    }

    /// app.css `.text-contrast`: `((red * 299 + green * 587 + blue * 114) / 1000 - 128) * -1000` is the
    /// level of all three channels, clamped to 0...255, so a colour at 128 or above gets black text
    /// and anything below it white.
    static func contrastColor(for color: UIColor) -> UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: nil)
        let luminance = (r * 255 * 299 + g * 255 * 587 + b * 255 * 114) / 1000
        return luminance >= 128 ? .black : .white
    }
}
