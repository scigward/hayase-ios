//
//  BrowseAnimeViewController.swift
//  Hayase
//
//  Hayase-inspired UI:
//  • Section 0 = rotating hero banner (full-banner.svelte replica, FeaturedBannerCell)
//  • Sections 1..n = horizontal-scroll poster rows (small.svelte cards, 115×200pt)
//

import UIKit
import CoreData

// MARK: - BannerGradientView

private final class BannerGradientView: UIView {
    private let radialGradient = CAGradientLayer()
    private let bottomGradient = CAGradientLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        // Web: radial-gradient(75% 65% at 59.18% 34.97%, rgba(0,0,0,0.16) 30.56%, rgba(0,0,0,1) 100%)
        // On mobile: centered at 50% 34.97%
        // Core Animation radial gradient: center at startPoint, edge at endPoint
        radialGradient.type = .radial
        radialGradient.colors = [
            UIColor.black.withAlphaComponent(0.16).cgColor, // center: rgba(0,0,0,0.16) at 30.56%
            UIColor.black.withAlphaComponent(0.16).cgColor,
            UIColor.black.withAlphaComponent(1.0).cgColor,  // edge: rgba(0,0,0,1) at 100%
        ]
        radialGradient.locations = [0.0, 0.3056, 1.0]
        // startPoint = center of radial (normalized) — ~55% x, 35% y
        radialGradient.startPoint = CGPoint(x: 0.55, y: 0.35)
        // endPoint defines the edge of the gradient ellipse — 75% width, 65% height
        radialGradient.endPoint = CGPoint(x: 0.55 + 0.75, y: 0.35 + 0.65)
        layer.addSublayer(radialGradient)

        // Additional bottom fade from black to --background so the banner edge
        // blends seamlessly into the app background.
        bottomGradient.colors = [
            UIColor.clear.cgColor,
            hayasePageBackground.cgColor,
        ]
        bottomGradient.locations = [0.0, 1.0]
        // Only covers the bottom 20% of the banner
        layer.addSublayer(bottomGradient)
    }

    required init?(coder: NSCoder) { super.init(coder: coder) }

    override func layoutSubviews() {
        super.layoutSubviews()
        radialGradient.frame = bounds
        // Bottom gradient: covers bottom 20% of the view
        let bottomH = bounds.height * 0.20
        bottomGradient.frame = CGRect(x: 0, y: bounds.height - bottomH, width: bounds.width, height: bottomH)
    }
}

// MARK: - FeaturedBannerCell
// Matches Hayase's full-banner.svelte identically:
// • Banner height = 70vh (70% of screen height) — matches banner.svelte h-[70vh]
// • Full-bleed background image (banner or cover) with Hayase radial gradient overlay
// • Title: font-black, text-3xl (28pt on mobile), white, text-shadow, 2 lines, text-center
// • Badges row: hidden on mobile (Hayase: `hidden sm:flex`) — bg-primary/10 pills
// • Play/Favorite/Bookmark buttons row: bg-custom text-contrast (Hayase PlayButton)
// • Description: text-white/70, 2 lines, text-xs (11pt), text-center on mobile
// • All content centered on mobile (Hayase: items-center text-center on mobile)
// • Dot progress indicators: centered, inactive = bg-white/20 width 1.5rem,
//   active = bg-custom width 3rem with 15s fill animation
// • 15-second auto-rotation
// • Banner query: SCORE_DESC, perPage: 5, current season, statusNot NOT_YET_RELEASED

private final class FeaturedBannerCell: UICollectionViewCell {
    static let reuseID = "FeaturedBannerCell"
    private static let rotationInterval: TimeInterval = 15
    // Banner height: 70% on iPhone, 80% on iPad — matches web h-[70vh] md:h-[80vh]
    // viewHeight should be the VC's view.bounds.height for multi-window correctness.
    static func bannerHeight(isRegular: Bool, viewHeight: CGFloat) -> CGFloat {
        return viewHeight * (isRegular ? 0.80 : 0.70)
    }

    var currentItem: AnimeItem? { items.isEmpty ? nil : items[currentIndex] }

    /// Exposes the background image view so the parent VC can apply scroll-driven zoom.
    var bannerImageView: UIImageView { backgroundImageView }

    /// Callback fired when the user taps the "Watch Now" / "Continue" play button.
    var onPlayTapped: ((AnimeItem) -> Void)?
    /// Callback fired when the user taps the favorite (heart) button.
    var onFavorite: ((AnimeItem) -> Void)?
    /// Callback fired when the user taps the bookmark button.
    var onBookmark: ((AnimeItem) -> Void)?
    /// Callback for badge tap: passes filter type and value for search navigation.
    /// Filter types: "format", "status", "season", "score"
    var onBadgeTapped: ((_ filterType: String, _ value: String, _ value2: String?) -> Void)?
    /// Callback for genre tap: passes the genre name for search navigation.
    var onGenreTapped: ((_ genre: String) -> Void)?

    private var items: [AnimeItem] = []
    private var currentIndex = 0
    private var rotationTimer: Timer?
    private var bannerTask: URLSessionDataTask?
    private var fanartTask: URLSessionDataTask?
    private var clearlogoTask: URLSessionDataTask?
    /// Tracks whether the banner is currently in the faded-out (5% opacity) state.
    private var bannerHidden = false
    /// Stored dot width constraints keyed by index — updated in-place instead of recreated.
    private var dotWidthConstraints: [Int: NSLayoutConstraint] = [:]

    // MARK: Views

    // Full-bleed background — banner preferred, fallback to cover
    private let backgroundImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.backgroundColor = UIColor(white: 0.08, alpha: 1)
        return iv
    }()

    // Gradient from transparent (top) to nearly-black (bottom) — matches Hayase gradient
    private let gradientView = BannerGradientView()

    // Title: font-black text-3xl lg:text-4xl line-clamp-2 text-white text-shadow-lg
    //   max-w-[85%] leading-tight text-balance text-center (mobile) lg:text-left
    private let titleLabel: UILabel = {
        let l = UILabel()
        // text-3xl = 1.875rem = 30pt on mobile (iPad uses 36pt set in applyLayoutForSizeClass)
        l.font = .nunito(ofSize: 30, weight: .black)
        l.textColor = .white
        l.numberOfLines = 2
        l.textAlignment = .center
        l.shadowColor = UIColor.black.withAlphaComponent(0.5)
        l.shadowOffset = CGSize(width: 0, height: 2)
        return l
    }()
    // max-w-[85%] constraint for title — activated in setup
    private var titleMaxWidthConstraint: NSLayoutConstraint!

    // Clearlogo: transparent title art from ani.zip (coverType == "Clearlogo").
    // Matches Hayase full-banner.svelte: displays logo image when available, hides titleLabel.
    // drop-shadow-lg w-[30rem] — scaled down for mobile to ~200pt width, aspect-fit.
    private let clearlogoImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFit
        iv.clipsToBounds = true
        iv.isHidden = true   // hidden by default; shown when Clearlogo is available
        iv.layer.shadowColor = UIColor.black.cgColor
        iv.layer.shadowOpacity = 0.6
        iv.layer.shadowRadius = 8
        iv.layer.shadowOffset = CGSize(width: 0, height: 4)
        return iv
    }()

    // Badge row: hidden on iPhone (web: `hidden sm:flex gap-2`), visible on iPad
    // Each badge: rounded px-3.5 h-7 text-sm !text-custom bg-primary/10 font-bold
    private let badgeStack: UIStackView = {
        let sv = UIStackView()
        sv.axis = .horizontal
        sv.spacing = 8  // gap-2 = 0.5rem = 8pt
        sv.alignment = .center
        // Will be toggled in applyLayoutForSizeClass
        return sv
    }()

    // Description: text-white/70 text-xs lg:text-sm
    //   text-center lg:text-right text-shadow-lg max-w-[90%] lg:max-w-[75%] pt-3
    //   line-clamp-2 (mobile) lg:line-clamp-3 (iPad)
    private let descriptionLabel: UILabel = {
        let l = UILabel()
        // text-xs = 0.75rem = 12pt (iPad uses 14pt set in applyLayoutForSizeClass)
        l.font = .nunito(ofSize: 12)
        l.textColor = UIColor.white.withAlphaComponent(0.7)
        l.numberOfLines = 2  // line-clamp-2 (mobile default; iPad overrides to 3)
        l.textAlignment = .center
        l.shadowColor = UIColor.black.withAlphaComponent(0.5)
        l.shadowOffset = CGSize(width: 0, height: 2)
        return l
    }()
    // max-w-[90%] mobile, max-w-[75%] iPad constraint for description
    private var descriptionMaxWidthConstraint: NSLayoutConstraint!

    // Play button: bg-custom text-contrast — matches web PlayButton in banner
    // Web: size='default' (h-9 px-4 py-2), base text-sm font-medium + class font-bold
    // So: h-9 = 36pt, text-sm = 14pt, font-bold override, rounded-md (6pt)
    private let playButton: UIButton = {
        let b = UIButton(type: .system)
        b.setTitle("  Watch Now", for: .normal)
        b.setImage(UIImage.hayaseFilledIcon("play", pointSize: 13), for: .normal)
        b.tintColor = .black
        b.setTitleColor(.black, for: .normal)
        b.titleLabel?.font = .nunito(ofSize: 14, weight: .bold) // text-sm font-bold
        b.layer.cornerRadius = 6  // rounded-md = 0.375rem ≈ 6pt
        b.clipsToBounds = true
        return b
    }()

    // Favorite button: ghost variant, size='icon' (h-9 w-9 = 36pt) — heart icon
    // Hayase: variant='ghost' (transparent bg, rounded-md), icon size = 1rem (16pt)
    // Normal state: white icon. Press state: subtle highlight.
    private let favoriteButton: UIButton = {
        let b = UIButton(type: .system)
        let cfg = UIImage.SymbolConfiguration(pointSize: 16, weight: .regular)
        b.setImage(UIImage.hayaseIcon("heart")?.withConfiguration(cfg), for: .normal)
        b.tintColor = .white
        b.layer.cornerRadius = 6  // rounded-md
        return b
    }()

    // Bookmark button: ghost variant, size='icon' (h-9 w-9 = 36pt) — bookmark icon
    // Same styling as favorite: transparent bg, rounded-md, 16pt icon, white tint
    private let bookmarkButton: UIButton = {
        let b = UIButton(type: .system)
        let cfg = UIImage.SymbolConfiguration(pointSize: 16, weight: .regular)
        b.setImage(UIImage.hayaseIcon("bookmark")?.withConfiguration(cfg), for: .normal)
        b.tintColor = .white
        b.layer.cornerRadius = 6  // rounded-md
        return b
    }()

    // Progress dots row — animated fill for active dot
    // Hayase: each dot has mr-2 (8pt) spacing
    private let dotsStack: UIStackView = {
        let sv = UIStackView()
        sv.axis = .horizontal
        sv.spacing = 8  // mr-2 = 0.5rem = 8pt between dots
        sv.alignment = .center
        return sv
    }()

    // Genre buttons row — iPad only (web: hidden lg:flex, bottom-right of banner)
    // Shows genre pill buttons matching web full-banner.svelte genres row
    private let genresStack: UIStackView = {
        let sv = UIStackView()
        sv.axis = .horizontal
        sv.spacing = 8  // gap-2 = 0.5rem = 8pt
        sv.alignment = .center
        sv.isHidden = true // shown on iPad only
        return sv
    }()

    // MARK: iPad two-column layout
    // Web: grid grid-cols-1 lg:grid-cols-2 — left column has title/badges/buttons,
    // right column has description/genres. On iPhone everything is single column centered.

    // The main content stack wrapping left + right columns (horizontal on iPad)
    private let columnsStack = UIStackView()
    // Left column: clearlogo/title, badges, buttons
    private let leftColumn = UIStackView()
    // Right column: description, genres (iPad only)
    private let rightColumn = UIStackView()

    // Stored constraints toggled between iPhone/iPad layouts
    // Clearlogo uses width constraints (web: w-[30rem] = 480pt on iPad, capped for mobile)
    private var clearlogoWidthCompact: NSLayoutConstraint!
    private var clearlogoWidthRegular: NSLayoutConstraint!

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
        // Don't clip — allows the banner image to extend upward for the zoom-on-overscroll effect
        clipsToBounds = false
        contentView.clipsToBounds = false

        // Swipe left/right to manually advance the banner carousel
        let swipeLeft = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipe(_:)))
        swipeLeft.direction = .left
        let swipeRight = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipe(_:)))
        swipeRight.direction = .right
        contentView.addGestureRecognizer(swipeLeft)
        contentView.addGestureRecognizer(swipeRight)

        [backgroundImageView, gradientView].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview($0)
        }

        // Button row: [Play (grow)  Favorite  Bookmark] — matches web PlayButton/FavoriteButton/BookmarkButton
        // Web: flex flex-row w-[280px] max-w-full
        let buttonRow = UIStackView(arrangedSubviews: [playButton, favoriteButton, bookmarkButton])
        buttonRow.axis = .horizontal
        buttonRow.spacing = 8
        buttonRow.alignment = .center
        buttonRow.distribution = .fill
        buttonRow.setCustomSpacing(16, after: playButton)  // Play mr-2 + Fav ml-2 = 16pt
        playButton.setContentHuggingPriority(.defaultLow, for: .horizontal)
        favoriteButton.setContentHuggingPriority(.required, for: .horizontal)
        bookmarkButton.setContentHuggingPriority(.required, for: .horizontal)
        favoriteButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        bookmarkButton.setContentCompressionResistancePriority(.required, for: .horizontal)

        playButton.addTarget(self, action: #selector(playButtonTapped), for: .touchUpInside)
        favoriteButton.addTarget(self, action: #selector(favoriteTapped), for: .touchUpInside)
        bookmarkButton.addTarget(self, action: #selector(bookmarkTapped), for: .touchUpInside)

        // Left column: clearlogo/title → badges → buttons
        // Web: w-full flex flex-col items-center text-center lg:items-start lg:text-left justify-end gap-4
        leftColumn.axis = .vertical
        leftColumn.spacing = 16  // gap-4
        leftColumn.alignment = .center  // will be .leading on iPad
        // Add a small spacer to push clearlogo/title slightly lower
        let logoTopSpacer = UIView()
        logoTopSpacer.translatesAutoresizingMaskIntoConstraints = false
        logoTopSpacer.heightAnchor.constraint(equalToConstant: 8).isActive = true
        leftColumn.addArrangedSubview(logoTopSpacer)
        leftColumn.setCustomSpacing(0, after: logoTopSpacer)
        leftColumn.addArrangedSubview(clearlogoImageView)
        leftColumn.addArrangedSubview(titleLabel)
        leftColumn.addArrangedSubview(badgeStack)
        leftColumn.addArrangedSubview(buttonRow)
        // On iPhone, description goes in the left column (below buttons)
        leftColumn.addArrangedSubview(descriptionLabel)
        leftColumn.setCustomSpacing(12, after: buttonRow) // pt-3 before description

        // Right column: description + genres (iPad only)
        // Web: flex flex-col self-end lg:items-end items-center lg:pr-5 w-full min-w-0
        // description has pt-3 (12pt top), genres have pt-4 (16pt top) — both are individual padding
        rightColumn.axis = .vertical
        rightColumn.spacing = 0  // no gap between children — pt-3/pt-4 are on elements themselves
        rightColumn.alignment = .trailing  // lg:items-end
        rightColumn.isHidden = true  // shown on iPad only

        // Genres go in the right column on iPad
        rightColumn.addArrangedSubview(genresStack)

        // Two-column wrapper: horizontal on iPad, vertical (single-col) on iPhone
        // Web: grid grid-cols-1 lg:grid-cols-2 mt-auto w-full max-h-full
        columnsStack.axis = .vertical  // will be .horizontal on iPad
        columnsStack.spacing = 0
        columnsStack.alignment = .fill
        columnsStack.distribution = .fillEqually
        columnsStack.addArrangedSubview(leftColumn)
        columnsStack.addArrangedSubview(rightColumn)
        columnsStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(columnsStack)

        dotsStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(dotsStack)

        // Clearlogo constraints: WIDTH-based like web w-[30rem] (480pt)
        // Web: image is inside a w-[900px] max-w-[85%] parent, so effectively limited to 85% of column
        // iPhone: capped at ~250pt width; iPad: up to 480pt (w-[30rem])
        clearlogoWidthCompact = clearlogoImageView.widthAnchor.constraint(lessThanOrEqualToConstant: 250)
        clearlogoWidthRegular = clearlogoImageView.widthAnchor.constraint(lessThanOrEqualToConstant: 480)

        // Also limit clearlogo to 85% of columnsStack width (matches web max-w-[85%] parent)
        let clearlogoMaxWidthPct = clearlogoImageView.widthAnchor.constraint(
            lessThanOrEqualTo: columnsStack.widthAnchor, multiplier: 0.85)

        // Title max-width: web max-w-[85%] — relative to columnsStack width
        titleMaxWidthConstraint = titleLabel.widthAnchor.constraint(
            lessThanOrEqualTo: columnsStack.widthAnchor, multiplier: 0.85)
        // Description max-width: web max-w-[90%] on mobile, max-w-[75%] on iPad
        // Start with 90% (iPhone), toggled in applyLayoutForSizeClass
        descriptionMaxWidthConstraint = descriptionLabel.widthAnchor.constraint(
            lessThanOrEqualTo: columnsStack.widthAnchor, multiplier: 0.90)

        NSLayoutConstraint.activate([
            backgroundImageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            backgroundImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            backgroundImageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            backgroundImageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            gradientView.topAnchor.constraint(equalTo: contentView.topAnchor),
            gradientView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            gradientView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            gradientView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            dotsStack.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            dotsStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),

            columnsStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            columnsStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            columnsStack.bottomAnchor.constraint(equalTo: dotsStack.topAnchor, constant: -8),

            titleMaxWidthConstraint,
            descriptionMaxWidthConstraint,
            clearlogoMaxWidthPct,

            buttonRow.widthAnchor.constraint(equalToConstant: 280),
            playButton.heightAnchor.constraint(equalToConstant: 36),
            favoriteButton.widthAnchor.constraint(equalToConstant: 36),
            favoriteButton.heightAnchor.constraint(equalToConstant: 36),
            bookmarkButton.widthAnchor.constraint(equalToConstant: 36),
            bookmarkButton.heightAnchor.constraint(equalToConstant: 36),
        ])

        // Apply initial layout (will be called again on trait changes via didMoveToWindow)
        applyLayoutForSizeClass(isRegular: false)
    }

    // MARK: - Adaptive Layout

    /// Switches between iPhone (compact) and iPad (regular) layouts.
    /// iPhone: single column, centered, badges hidden, description below buttons
    /// iPad: two columns, left-aligned left col, right-aligned right col, badges visible
    func applyLayoutForSizeClass(isRegular: Bool) {
        if isRegular {
            // iPad layout — web lg: breakpoint
            columnsStack.axis = .horizontal
            columnsStack.spacing = 0
            // Web: right column has self-end — aligns to bottom of the grid row
            columnsStack.alignment = .bottom
            leftColumn.alignment = .leading       // lg:items-start
            titleLabel.textAlignment = .left       // lg:text-left
            titleLabel.font = .nunito(ofSize: 36, weight: .black) // lg:text-4xl = 2.25rem = 36pt
            descriptionLabel.textAlignment = .right // lg:text-right
            badgeStack.isHidden = false            // sm:flex — visible on iPad
            // Move description to right column
            leftColumn.removeArrangedSubview(descriptionLabel)
            descriptionLabel.removeFromSuperview()
            rightColumn.insertArrangedSubview(descriptionLabel, at: 0)
            rightColumn.isHidden = false
            // pt-4 = 16pt spacing between description and genres in right column
            rightColumn.setCustomSpacing(16, after: descriptionLabel)
            // Clearlogo sizing: web w-[30rem] = 480pt
            clearlogoWidthCompact.isActive = false
            clearlogoWidthRegular.isActive = true
            // Description: lg:text-sm (0.875rem = 14pt), lg:line-clamp-3
            descriptionLabel.numberOfLines = 3
            descriptionLabel.font = .nunito(ofSize: 14)
            // Description max-width: lg:max-w-[75%] of right column
            descriptionMaxWidthConstraint.isActive = false
            descriptionMaxWidthConstraint = descriptionLabel.widthAnchor.constraint(
                lessThanOrEqualTo: columnsStack.widthAnchor, multiplier: 0.375) // 75% of right column (37.5% of full width, since columns are 50/50)
            descriptionMaxWidthConstraint.isActive = true
            // Column padding: lg:pl-5 = 20pt left, lg:pr-5 = 20pt right
            columnsStack.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20)
            columnsStack.isLayoutMarginsRelativeArrangement = true
        } else {
            // iPhone layout — web mobile
            columnsStack.axis = .vertical
            columnsStack.spacing = 0
            columnsStack.alignment = .fill
            leftColumn.alignment = .center         // items-center
            titleLabel.textAlignment = .center      // text-center
            titleLabel.font = .nunito(ofSize: 30, weight: .black) // text-3xl = 1.875rem = 30pt
            descriptionLabel.textAlignment = .center // text-center
            badgeStack.isHidden = true             // hidden on mobile
            // Move description back to left column (below buttons)
            rightColumn.removeArrangedSubview(descriptionLabel)
            descriptionLabel.removeFromSuperview()
            leftColumn.addArrangedSubview(descriptionLabel)
            rightColumn.isHidden = true
            genresStack.isHidden = true
            // Clearlogo sizing: smaller on iPhone
            clearlogoWidthRegular.isActive = false
            clearlogoWidthCompact.isActive = true
            // Description: text-xs (0.75rem = 12pt), line-clamp-2
            descriptionLabel.numberOfLines = 2
            descriptionLabel.font = .nunito(ofSize: 12)
            // Description max-width: max-w-[90%]
            descriptionMaxWidthConstraint.isActive = false
            descriptionMaxWidthConstraint = descriptionLabel.widthAnchor.constraint(
                lessThanOrEqualTo: columnsStack.widthAnchor, multiplier: 0.90)
            descriptionMaxWidthConstraint.isActive = true
            columnsStack.directionalLayoutMargins = .zero
            columnsStack.isLayoutMarginsRelativeArrangement = false
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        let isRegular = traitCollection.horizontalSizeClass == .regular
        applyLayoutForSizeClass(isRegular: isRegular)
    }

    // MARK: Configuration

    func configure(with items: [AnimeItem]) {
        // full-banner.svelte: shuffleAndFilter → media with bannerImage OR trailer
        let filtered = items.filter { $0.bannerURL != nil || $0.coverURL != nil }
        self.items = filtered.isEmpty ? Array(items.prefix(5)) : Array(filtered.prefix(5))
        currentIndex = 0
        rebuildDots()
        displayItem(animated: false)
        startTimer()
    }

    private func displayItem(animated: Bool) {
        guard currentIndex < items.count else { return }
        let item = items[currentIndex]
        let block = {
            // Hide both title and clearlogo initially — clearlogo fetch resolves which to show.
            // Web: {#await episodesCached()} shows nothing while loading, then clearlogo or text.
            self.titleLabel.text = item.titleEnglish ?? item.titleRomaji
            self.titleLabel.isHidden = true
            self.clearlogoImageView.isHidden = true
            self.clearlogoImageView.image = nil
            // Web desc(): defaults to "No description available." when empty/null
            let descText = item.description?.trimmingCharacters(in: .whitespacesAndNewlines)
            self.descriptionLabel.text = (descText?.isEmpty ?? true) ? "No description available." : descText
            self.descriptionLabel.isHidden = false
            // Play button bg-custom: use coverImage.color as background (Hayase --custom var)
            let customColor = Self.uiColor(fromHex: item.coverColor) ?? .white
            self.updateBadges(for: item, customColor: customColor)
            self.updateGenres(for: item, customColor: customColor)
            self.updateDots()
            self.playButton.backgroundColor = customColor
            // Determine text contrast (Hayase: text-contrast — black or white based on luminance)
            let textColor = Self.contrastColor(for: customColor)
            self.playButton.tintColor = textColor
            self.playButton.setTitleColor(textColor, for: .normal)
            // Favorite/Bookmark: start with white icon (ghost variant); async fill if already active
            self.favoriteButton.tintColor = .white
            self.bookmarkButton.tintColor = .white
            let cfg16 = UIImage.SymbolConfiguration(pointSize: 16, weight: .regular)
            self.favoriteButton.setImage(UIImage.hayaseIcon("heart")?.withConfiguration(cfg16), for: .normal)
            self.bookmarkButton.setImage(UIImage.hayaseIcon("bookmark")?.withConfiguration(cfg16), for: .normal)
            // Reflect saved state: fill icon + tint to accent if already favourited/bookmarked.
            // Mirrors Hayase full-banner.svelte FavoriteButton/BookmarkButton fill logic.
            let itemIDForState = item.id
            let accentForState = Self.uiColor(fromHex: item.coverColor) ?? .white
            AniListTracking.shared.checkIsFavourite(mediaID: itemIDForState) { [weak self] isFav in
                DispatchQueue.main.async {
                    guard let self,
                          self.currentIndex < self.items.count,
                          self.items[self.currentIndex].id == itemIDForState else { return }
                    self.favoriteButton.setImage(isFav ? UIImage.hayaseFilledIcon("heart", pointSize: 16) : UIImage.hayaseIcon("heart")?.withConfiguration(cfg16), for: .normal)
                    self.favoriteButton.tintColor = isFav ? accentForState : .white
                }
            }
            AniListTracking.shared.fetchMediaWithEntry(anilistID: itemIDForState) { [weak self] entry, _, _, _, _ in
                DispatchQueue.main.async {
                    guard let self,
                          self.currentIndex < self.items.count,
                          self.items[self.currentIndex].id == itemIDForState else { return }
                    let isOnList = entry != nil
                    self.bookmarkButton.setImage(isOnList ? UIImage.hayaseFilledIcon("bookmark", pointSize: 16) : UIImage.hayaseIcon("bookmark")?.withConfiguration(cfg16), for: .normal)
                    self.bookmarkButton.tintColor = isOnList ? accentForState : .white
                }
            }
            // Play button label: matches Hayase play.svelte — "Rewatch" / "Continue" / "Watch Now"
            let continueIDs = WatchProgressService.shared.continueWatchingAnilistIDs()
            if continueIDs.contains(item.id) {
                self.playButton.setTitle("  Continue", for: .normal)
            } else {
                self.playButton.setTitle("  Watch Now", for: .normal)
            }
        }
        if animated {
            UIView.transition(with: contentView, duration: 0.4, options: .transitionCrossDissolve, animations: block)
        } else {
            block()
        }
        loadBanner(for: item)
        loadClearlogo(for: item)
    }

    /// Parse hex color string (e.g. "#e3566b") to UIColor
    private static func uiColor(fromHex hex: String?) -> UIColor? {
        guard let hex = hex?.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: ""),
              hex.count == 6,
              let rgb = UInt32(hex, radix: 16) else { return nil }
        return UIColor(red: CGFloat((rgb >> 16) & 0xFF) / 255.0,
                       green: CGFloat((rgb >> 8) & 0xFF) / 255.0,
                       blue: CGFloat(rgb & 0xFF) / 255.0,
                       alpha: 1.0)
    }

    /// Returns black or white depending on luminance (Hayase text-contrast logic)
    private static func contrastColor(for color: UIColor) -> UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: nil)
        let luminance = 0.299 * r + 0.587 * g + 0.114 * b
        return luminance > 0.5 ? .black : .white
    }

    private func loadBanner(for item: AnimeItem) {
        bannerTask?.cancel()
        bannerTask = nil
        fanartTask?.cancel()
        fanartTask = nil
        let biv = backgroundImageView
        let bannerFallback = item.bannerURL ?? item.coverURL
        // Fanart-first: fetch ani.zip Fanart (cached/deduped). Only if not found,
        // fall back to AniList banner. Single image load = no visible flicker/swap.
        AniListClient.fetchFanartURL(anilistID: item.id) { [weak self] fanartURL in
            let urlStr = fanartURL ?? bannerFallback
            guard let urlStr, let url = URL(string: urlStr) else {
                DispatchQueue.main.async { biv.image = nil }
                return
            }
            if let cached = SharedImageCache.shared.object(forKey: urlStr as NSString) {
                DispatchQueue.main.async {
                    self?.applyContentMode(for: cached)
                    biv.image = cached
                }
                return
            }
            let captured = urlStr
            self?.fanartTask = URLSession.shared.dataTask(with: url) { [weak self, weak biv] data, _, _ in
                guard let data, let image = UIImage(data: data) else { return }
                SharedImageCache.shared.setObject(image, forKey: captured as NSString)
                DispatchQueue.main.async {
                    self?.applyContentMode(for: image)
                    UIView.transition(with: biv ?? UIImageView(), duration: 0.3,
                                      options: .transitionCrossDissolve,
                                      animations: { biv?.image = image })
                }
            }
            self?.fanartTask?.resume()
        }
    }

    /// Always use .scaleAspectFill — fills the cell without black bars.
    /// At bannerHeight = 240pt, a 1900×400 landscape banner shows ~34% of its width.
    private func applyContentMode(for image: UIImage) {
        backgroundImageView.contentMode = .scaleAspectFill
    }

    /// Fetches the Clearlogo (transparent title art) from ani.zip for the current item.
    /// If found, displays the logo image and hides the text title. Otherwise keeps text.
    /// Matches Hayase full-banner.svelte:
    ///   `{#await episodesCached(current.id) then metadata}`
    ///   `{@const src = metadata?.images?.find(i => i.coverType === 'Clearlogo')?.url}`
    private func loadClearlogo(for item: AnimeItem) {
        clearlogoTask?.cancel()
        clearlogoTask = nil
        let itemID = item.id
        AniListClient.fetchClearlogoURL(anilistID: itemID) { [weak self] clearlogoURL in
            guard let self = self else { return }
            // Make sure we're still displaying the same item (rotation may have advanced)
            guard self.currentIndex < self.items.count, self.items[self.currentIndex].id == itemID else { return }
            guard let urlStr = clearlogoURL, let url = URL(string: urlStr) else {
                // No clearlogo available — show text title as fallback
                DispatchQueue.main.async {
                    guard self.currentIndex < self.items.count, self.items[self.currentIndex].id == itemID else { return }
                    UIView.animate(withDuration: 0.3) {
                        self.titleLabel.isHidden = false
                    }
                }
                return
            }
            // Check image cache first
            if let cached = SharedImageCache.shared.object(forKey: urlStr as NSString) {
                self.showClearlogo(cached, forItemID: itemID)
                return
            }
            let captured = urlStr
            self.clearlogoTask = URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
                guard let data, let image = UIImage(data: data) else {
                    // Download failed — show text title as fallback
                    DispatchQueue.main.async {
                        guard let self,
                              self.currentIndex < self.items.count,
                              self.items[self.currentIndex].id == itemID else { return }
                        UIView.animate(withDuration: 0.3) {
                            self.titleLabel.isHidden = false
                        }
                    }
                    return
                }
                SharedImageCache.shared.setObject(image, forKey: captured as NSString)
                DispatchQueue.main.async {
                    self?.showClearlogo(image, forItemID: itemID)
                }
            }
            self.clearlogoTask?.resume()
        }
    }

    private func showClearlogo(_ image: UIImage, forItemID: Int) {
        // Verify we're still on the same item
        guard currentIndex < items.count, items[currentIndex].id == forItemID else { return }
        clearlogoImageView.image = image
        UIView.animate(withDuration: 0.3) {
            self.clearlogoImageView.isHidden = false
            self.titleLabel.isHidden = true
        }
    }

    private func updateBadges(for item: AnimeItem, customColor: UIColor) {
        badgeStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        // Prepare badge data: (text, textColor, filterType, filterValue, filterValue2)
        // Web: of(current) ?? duration(current) ?? 'N/A', format, status, season?, score?
        // filterType: nil = not tappable, "format"/"status"/"season"/"score" = tappable
        var badges: [(String, UIColor, String?, String?, String?)] = []

        // First badge: episode count or duration or 'N/A' — not tappable (web: plain div, no Button)
        if let eps = item.episodes, eps > 1 {
            badges.append(("\(eps) Episodes", customColor, nil, nil, nil))
        } else if let dur = item.duration, dur > 0 {
            badges.append(("\(dur) Minute\(dur > 1 ? "s" : "")", customColor, nil, nil, nil))
        } else {
            badges.append(("N/A", customColor, nil, nil, nil))
        }

        // Format badge: FORMAT_MAP matching web — tappable
        if let fmt = item.format {
            let fmtMap: [String: String] = [
                "TV": "TV Series", "TV_SHORT": "TV Short", "MOVIE": "Movie",
                "SPECIAL": "Special", "OVA": "OVA", "ONA": "ONA", "MUSIC": "Music"]
            badges.append((fmtMap[fmt] ?? fmt.capitalized, customColor, "format", fmt, nil))
        }

        // Status badge: STATUS_MAP matching web — tappable
        if let st = item.status {
            let stMap: [String: String] = [
                "RELEASING": "Releasing", "FINISHED": "Finished",
                "NOT_YET_RELEASED": "Not Yet Released",
                "CANCELLED": "Cancelled", "HIATUS": "Hiatus"]
            badges.append((stMap[st] ?? st.capitalized, customColor, "status", st, nil))
        }

        // Season badge (if available) — tappable, passes season + year
        if let season = item.season, let year = item.year {
            badges.append(("\(season.capitalized) \(year)", customColor, "season", season, String(year)))
        }

        // Score badge: color-coded text per getTextColorForRating — tappable (sorts by SCORE_DESC)
        if let score = item.score, score > 0 {
            let scoreColor: UIColor
            if score >= 75 {
                scoreColor = UIColor(red: 21/255.0, green: 128/255.0, blue: 61/255.0, alpha: 1) // text-green-700
            } else if score >= 65 {
                scoreColor = UIColor(red: 251/255.0, green: 146/255.0, blue: 60/255.0, alpha: 1) // text-orange-400
            } else {
                scoreColor = UIColor(red: 239/255.0, green: 68/255.0, blue: 68/255.0, alpha: 1) // text-red-500
            }
            badges.append((String(format: "%.0f%%", score), scoreColor, "score", "SCORE_DESC", nil))
        }

        for (text, textColor, filterType, filterValue, filterValue2) in badges {
            // Web: rounded px-3.5 h-7 text-sm !text-custom bg-primary/10 font-bold inline-flex items-center
            let pill = UIView()
            pill.backgroundColor = UIColor.white.withAlphaComponent(0.10) // bg-primary/10
            pill.layer.cornerRadius = 4  // rounded = 0.25rem = 4pt
            pill.clipsToBounds = true
            pill.translatesAutoresizingMaskIntoConstraints = false

            let l = UILabel()
            l.text = text
            l.font = .nunito(ofSize: 14, weight: .bold) // text-sm font-bold
            l.textColor = textColor
            l.translatesAutoresizingMaskIntoConstraints = false
            pill.addSubview(l)

            NSLayoutConstraint.activate([
                pill.heightAnchor.constraint(equalToConstant: 28), // h-7 = 1.75rem = 28pt
                l.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: 14), // px-3.5 = 0.875rem = 14pt
                l.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -14),
                l.centerYAnchor.constraint(equalTo: pill.centerYAnchor),
            ])
            // Make tappable badges respond to taps (format, status, season, score)
            if let filterType = filterType, let filterValue = filterValue {
                pill.isUserInteractionEnabled = true
                let tap = BadgeTapGesture(target: self, action: #selector(badgePillTapped(_:)))
                tap.filterType = filterType
                tap.filterValue = filterValue
                tap.filterValue2 = filterValue2
                pill.addGestureRecognizer(tap)
            }
            badgeStack.addArrangedSubview(pill)
        }
    }

    /// Custom UITapGestureRecognizer that carries badge filter metadata.
    private class BadgeTapGesture: UITapGestureRecognizer {
        var filterType: String = ""
        var filterValue: String = ""
        var filterValue2: String?
    }

    @objc private func badgePillTapped(_ gesture: BadgeTapGesture) {
        onBadgeTapped?(gesture.filterType, gesture.filterValue, gesture.filterValue2)
    }

    /// Custom UITapGestureRecognizer that carries genre name.
    private class GenreTapGesture: UITapGestureRecognizer {
        var genre: String = ""
    }

    @objc private func genrePillTapped(_ gesture: GenreTapGesture) {
        onGenreTapped?(gesture.genre)
    }

    /// Populates the genre pill buttons on iPad (web: hidden lg:flex, right column of banner).
    /// Each pill matches web: variant='ghost' !text-custom bg-primary/10 h-7 font-bold rounded
    private func updateGenres(for item: AnimeItem, customColor: UIColor) {
        genresStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        guard traitCollection.horizontalSizeClass == .regular else {
            genresStack.isHidden = true
            return
        }
        let genres = item.genres.prefix(5)
        guard !genres.isEmpty else {
            genresStack.isHidden = true
            return
        }
        genresStack.isHidden = false
        for genre in genres {
            // Web: variant='ghost' !text-custom h-7 text-nowrap bg-primary/10 font-bold rounded
            let pill = UIView()
            pill.backgroundColor = UIColor.white.withAlphaComponent(0.10) // bg-primary/10
            pill.layer.cornerRadius = 4  // rounded = 4pt
            pill.clipsToBounds = true
            pill.translatesAutoresizingMaskIntoConstraints = false

            let l = UILabel()
            l.text = genre
            l.font = .nunito(ofSize: 14, weight: .bold) // text-sm font-bold
            l.textColor = customColor  // !text-custom — cover color
            l.translatesAutoresizingMaskIntoConstraints = false
            pill.addSubview(l)

            NSLayoutConstraint.activate([
                pill.heightAnchor.constraint(equalToConstant: 28), // h-7 = 28pt
                l.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: 14), // px-3.5
                l.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -14),
                l.centerYAnchor.constraint(equalTo: pill.centerYAnchor),
            ])
            // Make genre pill tappable — navigates to search with genre filter
            pill.isUserInteractionEnabled = true
            let tap = GenreTapGesture(target: self, action: #selector(genrePillTapped(_:)))
            tap.genre = genre
            pill.addGestureRecognizer(tap)
            genresStack.addArrangedSubview(pill)
        }
    }

    private func rebuildDots() {
        dotsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        dotWidthConstraints.removeAll()
        for i in items.indices {
            // Outer dot: bg-white/20 rounded, overflow clip — matches Hayase's .progress-badge
            let dot = UIView()
            dot.layer.cornerRadius = 2
            dot.clipsToBounds = true
            dot.backgroundColor = UIColor.white.withAlphaComponent(0.2)
            dot.translatesAutoresizingMaskIntoConstraints = false
            dot.heightAnchor.constraint(equalToConstant: 4).isActive = true
            // Hayase: inactive width 1.5rem (24pt), active width 3rem (48pt)
            let wc = dot.widthAnchor.constraint(equalToConstant: i == 0 ? 48 : 24)
            wc.isActive = true
            dotWidthConstraints[i] = wc

            // Inner fill view — matches Hayase's .progress-content with fill animation
            let fill = UIView()
            fill.tag = 999
            fill.translatesAutoresizingMaskIntoConstraints = false
            dot.addSubview(fill)
            NSLayoutConstraint.activate([
                fill.topAnchor.constraint(equalTo: dot.topAnchor),
                fill.leadingAnchor.constraint(equalTo: dot.leadingAnchor),
                fill.trailingAnchor.constraint(equalTo: dot.trailingAnchor),
                fill.bottomAnchor.constraint(equalTo: dot.bottomAnchor),
            ])

            dotsStack.addArrangedSubview(dot)

            // Tap to manually switch to this item
            dot.isUserInteractionEnabled = true
            dot.tag = i
            dot.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(dotTapped(_:))))
        }
        updateDots()
    }

    @objc private func dotTapped(_ gesture: UITapGestureRecognizer) {
        guard let dot = gesture.view else { return }
        let index = dot.tag
        guard index >= 0, index < items.count, index != currentIndex else { return }
        currentIndex = index
        displayItem(animated: true)
        // Restart the timer so the next auto-advance is a full interval from now
        startTimer()
    }

    @objc private func handleSwipe(_ gesture: UISwipeGestureRecognizer) {
        guard items.count > 1 else { return }
        switch gesture.direction {
        case .left:
            currentIndex = (currentIndex + 1) % items.count
        case .right:
            currentIndex = (currentIndex - 1 + items.count) % items.count
        default: break
        }
        displayItem(animated: true)
        startTimer()
    }

    @objc private func playButtonTapped() {
        guard let item = currentItem else { return }
        onPlayTapped?(item)
    }

    @objc private func favoriteTapped() {
        guard let item = currentItem else { return }
        animateTap(favoriteButton)
        onFavorite?(item)
    }

    @objc private func bookmarkTapped() {
        guard let item = currentItem else { return }
        animateTap(bookmarkButton)
        onBookmark?(item)
    }

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

    private func updateDots() {
        // Matches Hayase full-banner.svelte dot behavior:
        //   inactive: bg-white/20, width 1.5rem (24pt)
        //   active:   bg-custom (coverImage.color), width 3rem (48pt), fill animation over 15s
        let item = items.isEmpty ? nil : items[currentIndex]
        let customColor = Self.uiColor(fromHex: item?.coverColor) ?? .white
        for (i, dot) in dotsStack.arrangedSubviews.enumerated() {
            let active = i == currentIndex
            dotWidthConstraints[i]?.constant = active ? 48 : 24

            // Find inner fill view
            let fill = dot.viewWithTag(999)

            // Remove any existing fill animation
            fill?.layer.removeAnimation(forKey: "fillProgress")

            if active {
                // Hayase: bg-custom on active dot fill
                fill?.backgroundColor = customColor
                // Hayase CSS: animation: fill 15s linear
                // Animates transform from translateX(-100%) to translateX(0%)
                let anim = CABasicAnimation(keyPath: "transform.translation.x")
                anim.fromValue = -48.0  // start fully off-screen left
                anim.toValue = 0.0
                anim.duration = FeaturedBannerCell.rotationInterval
                anim.timingFunction = CAMediaTimingFunction(name: .linear)
                anim.fillMode = .forwards
                anim.isRemovedOnCompletion = false
                fill?.layer.add(anim, forKey: "fillProgress")
            } else {
                fill?.backgroundColor = .clear
            }

            UIView.animate(withDuration: 0.7) {
                dot.superview?.layoutIfNeeded()
            }
        }
    }

    private func startTimer() {
        rotationTimer?.invalidate()
        guard items.count > 1 else { return }
        rotationTimer = Timer.scheduledTimer(withTimeInterval: FeaturedBannerCell.rotationInterval,
                                             repeats: true) { [weak self] _ in
            guard let self = self, !self.items.isEmpty else { return }
            self.currentIndex = (self.currentIndex + 1) % self.items.count
            self.displayItem(animated: true)
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        rotationTimer?.invalidate()
        rotationTimer = nil
        bannerTask?.cancel()
        bannerTask = nil
        fanartTask?.cancel()
        fanartTask = nil
        clearlogoTask?.cancel()
        clearlogoTask = nil
        items = []
        backgroundImageView.image = nil
        clearlogoImageView.image = nil
        clearlogoImageView.isHidden = true
        titleLabel.isHidden = false
        bannerHidden = false
        backgroundImageView.alpha = 1.0
        gradientView.alpha = 1.0
    }

    override func willMove(toWindow newWindow: UIWindow?) {
        super.willMove(toWindow: newWindow)
        if newWindow == nil {
            rotationTimer?.invalidate()
            rotationTimer = nil
        }
    }

    // MARK: - Scroll-driven effects (called by the parent VC)

    /// Applies the zoom effect when the user over-scrolls upward (negative contentOffset).
    /// `overscroll` is the magnitude of the overscroll in points (always ≥ 0).
    func applyOverscrollZoom(_ overscroll: CGFloat) {
        guard overscroll > 0 else {
            backgroundImageView.transform = .identity
            gradientView.transform = .identity
            return
        }
        let scale = 1.0 + overscroll / bounds.height
        // Scale up from center-top so the bottom stays anchored and the image grows upward
        let yShift = -overscroll / 2.0
        backgroundImageView.transform = CGAffineTransform(translationX: 0, y: yShift).scaledBy(x: scale, y: scale)
        gradientView.transform = CGAffineTransform(translationX: 0, y: yShift).scaledBy(x: scale, y: scale)
    }

    /// Applies the fade effect when the user scrolls down past the banner.
    /// `scrollOffset` is the raw contentOffset.y value.
    /// Matches interface: hideBanner = scrollTop > 100 → 5% opacity, else 100% opacity,
    /// with a 500ms animated transition.
    func applyScrollFade(_ scrollOffset: CGFloat) {
        // Interface: hideBanner.value = target.scrollTop > 100
        // Faded-out = 5% opacity (0.05), fully visible = 100% opacity (1.0).
        // transition-opacity duration-500 → UIView.animate withDuration: 0.5
        let shouldHide = scrollOffset > 100
        guard shouldHide != bannerHidden else { return }
        bannerHidden = shouldHide
        let targetAlpha: CGFloat = shouldHide ? 0.05 : 1.0
        // Only fade the image — keep gradientView at full opacity so its bottom stop
        // (UIColor(white: 0.04, alpha: 1) = --background) always covers the banner edge.
        // Fading the gradient out too exposes the raw image bottom against the background.
        UIView.animate(withDuration: 0.5) {
            self.backgroundImageView.alpha = targetAlpha
        }
    }
}

// MARK: - SkeletonPosterCell
// Matches Hayase's cards/skeleton.svelte exactly:
// • p-4 outer padding around item
// • w-[9.5rem] item (same as small.svelte), aspect-ratio 152/290
// • h-[13.5rem] cover placeholder: bg-black rounded + bg-primary/5 animate-pulse inside
// • mt-4 h-2 w-28 title bar: bg-black rounded + bg-primary/5 animate-pulse
// • mt-2 h-2 w-20 meta bar:  bg-black rounded + bg-primary/5 animate-pulse

private final class SkeletonPosterCell: UICollectionViewCell {
    static let reuseID = "SkeletonPosterCell"

    // bg-black cover placeholder (h-[13.5rem])
    private let coverPlaceholder: UIView = {
        let v = UIView()
        v.backgroundColor = .black
        v.layer.cornerRadius = 4 // rounded
        v.clipsToBounds = true
        return v
    }()
    private let coverShimmer: UIView = {
        let v = UIView()
        v.backgroundColor = UIColor.white.withAlphaComponent(0.05) // bg-primary/5
        return v
    }()

    // Title bar: bg-black h-2 w-28
    private let titleBar: UIView = {
        let v = UIView()
        v.backgroundColor = .black
        v.layer.cornerRadius = 2
        v.clipsToBounds = true
        return v
    }()
    private let titleShimmer: UIView = {
        let v = UIView()
        v.backgroundColor = UIColor.white.withAlphaComponent(0.05)
        return v
    }()

    // Meta bar: bg-black h-2 w-20
    private let metaBar: UIView = {
        let v = UIView()
        v.backgroundColor = .black
        v.layer.cornerRadius = 2
        v.clipsToBounds = true
        return v
    }()
    private let metaShimmer: UIView = {
        let v = UIView()
        v.backgroundColor = UIColor.white.withAlphaComponent(0.05)
        return v
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        contentView.backgroundColor = .clear

        // Cover shimmer fills cover placeholder
        coverShimmer.translatesAutoresizingMaskIntoConstraints = false
        coverPlaceholder.addSubview(coverShimmer)
        NSLayoutConstraint.activate([
            coverShimmer.topAnchor.constraint(equalTo: coverPlaceholder.topAnchor),
            coverShimmer.leadingAnchor.constraint(equalTo: coverPlaceholder.leadingAnchor),
            coverShimmer.trailingAnchor.constraint(equalTo: coverPlaceholder.trailingAnchor),
            coverShimmer.bottomAnchor.constraint(equalTo: coverPlaceholder.bottomAnchor),
        ])

        titleShimmer.translatesAutoresizingMaskIntoConstraints = false
        titleBar.addSubview(titleShimmer)
        NSLayoutConstraint.activate([
            titleShimmer.topAnchor.constraint(equalTo: titleBar.topAnchor),
            titleShimmer.leadingAnchor.constraint(equalTo: titleBar.leadingAnchor),
            titleShimmer.trailingAnchor.constraint(equalTo: titleBar.trailingAnchor),
            titleShimmer.bottomAnchor.constraint(equalTo: titleBar.bottomAnchor),
        ])

        metaShimmer.translatesAutoresizingMaskIntoConstraints = false
        metaBar.addSubview(metaShimmer)
        NSLayoutConstraint.activate([
            metaShimmer.topAnchor.constraint(equalTo: metaBar.topAnchor),
            metaShimmer.leadingAnchor.constraint(equalTo: metaBar.leadingAnchor),
            metaShimmer.trailingAnchor.constraint(equalTo: metaBar.trailingAnchor),
            metaShimmer.bottomAnchor.constraint(equalTo: metaBar.bottomAnchor),
        ])

        // Stack: [cover, titleBar, metaBar]
        let stack = UIStackView(arrangedSubviews: [coverPlaceholder, titleBar, metaBar])
        stack.axis = .vertical
        stack.spacing = 0
        stack.setCustomSpacing(16, after: coverPlaceholder) // mt-4
        stack.setCustomSpacing(8, after: titleBar)          // mt-2
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),

            // Cover: h-[13.5rem] relative to card width (matches 216/152 of small.svelte)
            coverPlaceholder.heightAnchor.constraint(equalTo: contentView.widthAnchor, multiplier: 216.0 / 152.0),

            // Title bar: h-2 (8pt), w-28 (112pt)
            titleBar.heightAnchor.constraint(equalToConstant: 8),
            titleBar.widthAnchor.constraint(equalToConstant: 112),

            // Meta bar: h-2 (8pt), w-20 (80pt)
            metaBar.heightAnchor.constraint(equalToConstant: 8),
            metaBar.widthAnchor.constraint(equalToConstant: 80),
        ])

        startPulse()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func startPulse() {
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 0.05
        pulse.toValue = 0.12
        pulse.duration = 1.0
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        [coverShimmer, titleShimmer, metaShimmer].forEach { $0.layer.add(pulse, forKey: "pulse") }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
    }
}

// MARK: - SkeletonBannerCell
// Matches Hayase's banner/skeleton-banner.svelte:
// Full-height cell with placeholder bars at bottom-left (pl-5 pb-5 justify-end flex-col)
// All bars: bg-primary/5 animate-pulse rounded

private final class SkeletonBannerCell: UICollectionViewCell {
    static let reuseID = "SkeletonBannerCell"

    private var shimmerViews: [UIView] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        contentView.backgroundColor = .clear

        // Web skeleton-banner.svelte layout (bottom-aligned, left-padded):
        // h-6 w-[500px]        – title bar
        // h-1.5 w-[250px] my-5 – spacer
        // h-2.5 w-[450px] mb-2 – description line 1
        // h-2.5 w-[350px] mb-2 – description line 2
        // h-2.5 w-[300px] mb-2 – description line 3
        // h-2.5 w-[250px] mb-2 – description line 4
        // h-1.5 w-[150px] my-3 – spacer
        // h-6 w-[160px] mb-4   – button placeholder

        let bars: [(height: CGFloat, width: CGFloat)] = [
            (24, 500),   // title: h-6 = 24pt, w-[500px] (capped by parent)
            (6, 250),    // spacer: h-1.5 = 6pt
            (10, 450),   // desc 1: h-2.5 = 10pt
            (10, 350),   // desc 2
            (10, 300),   // desc 3
            (10, 250),   // desc 4
            (6, 150),    // spacer: h-1.5 = 6pt
            (24, 160),   // button: h-6 = 24pt
        ]

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 0
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        for (i, bar) in bars.enumerated() {
            let container = UIView()
            container.backgroundColor = .black
            container.layer.cornerRadius = 4
            container.clipsToBounds = true

            let shimmer = UIView()
            shimmer.backgroundColor = UIColor.white.withAlphaComponent(0.05) // bg-primary/5
            shimmer.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(shimmer)

            container.translatesAutoresizingMaskIntoConstraints = false
            stack.addArrangedSubview(container)
            NSLayoutConstraint.activate([
                container.heightAnchor.constraint(equalToConstant: bar.height),
                container.widthAnchor.constraint(equalToConstant: bar.width),
                shimmer.topAnchor.constraint(equalTo: container.topAnchor),
                shimmer.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                shimmer.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                shimmer.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            ])

            shimmerViews.append(shimmer)

            // Spacing after each bar to match web CSS margins
            // Web: title(mb-1) → spacer1(my-5) → desc lines(mb-2) → spacer2(my-3) → button(mb-4)
            switch i {
            case 0: stack.setCustomSpacing(24, after: container) // title mb-1(4) + spacer my-5 top(20) = 24
            case 1: stack.setCustomSpacing(20, after: container) // spacer my-5 bottom = 20
            case 2, 3, 4: stack.setCustomSpacing(8, after: container) // desc lines mb-2 = 8
            case 5: stack.setCustomSpacing(20, after: container) // desc4 mb-2(8) + spacer2 my-3 top(12) = 20
            case 6: stack.setCustomSpacing(12, after: container) // spacer2 my-3 bottom = 12
            default: break // button: mb-4 + trailing empty div mb-3 = bottom padding
            }
        }

        // Pin stack to bottom-left with pl-5 (20pt) pb-5 (20pt) padding
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -20),
        ])

        startPulse()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func startPulse() {
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 0.05
        pulse.toValue = 0.12
        pulse.duration = 1.0
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        shimmerViews.forEach { $0.layer.add(pulse, forKey: "pulse") }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
    }
}

// MARK: - SectionHeaderView
// Matches Hayase home page: font-semibold text-lg text-muted-foreground + "View More" text-xs

private final class SectionHeaderView: UICollectionReusableView {
    static let reuseID = "SectionHeader"

    var onViewMore: (() -> Void)?

    private let titleLabel: UILabel = {
        let l = UILabel()
        // Web: font-semibold text-lg leading-none text-muted-foreground
        // text-lg = 1.125rem = 18pt, --muted-foreground dark: hsl(240 5% 64.9%) ≈ #a3a3ab
        l.font = .nunito(ofSize: 18, weight: .semibold)
        l.textColor = UIColor(red: 163/255.0, green: 163/255.0, blue: 171/255.0, alpha: 1) // hsl(240 5% 64.9%)
        return l
    }()

    private lazy var viewMoreButton: UIButton = {
        let b = UIButton(type: .system)
        b.setTitle("View More", for: .normal)
        // Web: ml-auto text-xs = 0.75rem = 12pt
        b.titleLabel?.font = .nunito(ofSize: 12)
        b.setTitleColor(UIColor(red: 163/255.0, green: 163/255.0, blue: 171/255.0, alpha: 1), for: .normal)
        b.addTarget(self, action: #selector(viewMoreTapped), for: .touchUpInside)
        return b
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        backgroundColor = .clear
        [titleLabel, viewMoreButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }
        NSLayoutConstraint.activate([
            // items-end: align text to bottom of header (Hayase uses items-end on section header div)
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            titleLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            viewMoreButton.trailingAnchor.constraint(equalTo: trailingAnchor),
            viewMoreButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            viewMoreButton.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 8),
        ])
    }

    @objc private func viewMoreTapped() { onViewMore?() }

    func configure(title: String) { titleLabel.text = title }
}

// MARK: - BrowseAnimeViewController

class BrowseAnimeViewController: UIViewController {

    // MARK: - Layout Constants

    private enum PosterLayout {
        // Matches Hayase small.svelte: w-[9.5rem] = 152px wide, aspect-ratio 152:290
        static let width: CGFloat = 152
        static let height: CGFloat = 290
    }

    // MARK: - Properties

    private var sections: [HomeSectionData] = []
    private var fetchedHomeSections: [HomeSectionData] = []
    /// Items used exclusively for the hero banner rotation.  Always sourced from
    /// the first *fetched* section (trending/popular) — never "Continue Watching".
    private var bannerItems: [AnimeItem] = []
    private var isSearching: Bool = false
    private var isLoadingSections: Bool = false
    private var animeResultsController: NSFetchedResultsController<Animes>?
    private var pendingAnimeItem: AnimeItem?

    private var collectionView: UICollectionView!
    private var searchController: UISearchController!
    private var loadingIndicator: UIActivityIndicatorView!
    private var emptyLabel: UILabel!
    private var lastSearchString = ""
    private var searchDebounceTimer: Timer?
    private var homeRefreshTimer: Timer?
    private var personalSectionsLoadID = 0
    private var lastLocalContinueIDs: [Int] = []

    // MARK: - Init (set tabBarItem before viewDidLoad so tab bar reads it at launch)

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        tabBarItem = UITabBarItem(
            title: "Home",
            image: UIImage.hayaseIcon("house"),
            selectedImage: UIImage.hayaseIcon("house"))
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        // Clip at the view level so the banner zoom doesn't overflow beyond the screen,
        // but the collection view itself doesn't clip (allows banner to extend upward during overscroll)
        view.clipsToBounds = true
        setupNavigationBar()
        setupCollectionView()
        setupOverlays()
        setupNotifications()
        loadSections()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Hide nav bar on home — Hayase has no top nav bar, content starts at top
        navigationController?.setNavigationBarHidden(true, animated: animated)
        collectionView.indexPathsForSelectedItems?.forEach {
            collectionView.deselectItem(at: $0, animated: animated)
        }
        // Re-sync banner fade with the current scroll position.
        // scrollViewDidScroll does NOT fire automatically when the view re-appears (e.g. popping
        // back from a detail VC), so the banner could be stuck in the wrong opacity state.
        // Matches the interface: hideBanner.value = false at component init, then re-evaluated.
        syncBannerToCurrentScrollPosition()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // Restore nav bar when pushing child VCs (detail, etc.)
        navigationController?.setNavigationBarHidden(false, animated: animated)
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        guard isViewLoaded else { return }
        coordinator.animate(alongsideTransition: { [weak self] _ in
            guard let self else { return }
            let layout = self.isSearching ? self.makeSearchLayout() : self.makeHomeLayout()
            self.collectionView.setCollectionViewLayout(layout, animated: false)
        })
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard traitCollection.horizontalSizeClass != previousTraitCollection?.horizontalSizeClass else { return }
        // Update banner cell layout for new size class
        let isRegular = traitCollection.horizontalSizeClass == .regular
        if let bannerCell = collectionView.cellForItem(at: IndexPath(item: 0, section: 0)) as? FeaturedBannerCell {
            bannerCell.applyLayoutForSizeClass(isRegular: isRegular)
        }
        // Refresh the home layout (banner height changes between iPhone 70% and iPad 80%)
        if !isSearching {
            collectionView.setCollectionViewLayout(makeHomeLayout(), animated: false)
        }
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        // With contentInsetAdjustmentBehavior = .never, manually account for the tab bar
        // so the last section's content isn't hidden under it
        collectionView.contentInset.bottom = view.safeAreaInsets.bottom
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        searchDebounceTimer?.invalidate()
        homeRefreshTimer?.invalidate()
    }

    // MARK: - Setup

    private func setupNavigationBar() {
        // Hayase home/+page.svelte has no title — just content starting from the top
        title = nil
    }

    private func setupCollectionView() {
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeHomeLayout())
        collectionView.backgroundColor = hayasePageBackground
        // .never so the banner extends behind the status bar — matching Hayase's
        // `position:absolute; top:0; left:0; h-[80vh]` banner image on home
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.delegate = self
        collectionView.dataSource = self
        // Poster row cells
        collectionView.register(AnimeCollectionViewCell.self,
                                forCellWithReuseIdentifier: AnimeCollectionViewCell.reuseID)
        // Hero banner (section 0 when home)
        collectionView.register(FeaturedBannerCell.self,
                                forCellWithReuseIdentifier: FeaturedBannerCell.reuseID)
        // Skeleton shimmer cells (shown while home sections are loading)
        collectionView.register(SkeletonPosterCell.self,
                                forCellWithReuseIdentifier: SkeletonPosterCell.reuseID)
        collectionView.register(SkeletonBannerCell.self,
                                forCellWithReuseIdentifier: SkeletonBannerCell.reuseID)
        // Section headers (sections 1..n when home)
        collectionView.register(SectionHeaderView.self,
                                forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
                                withReuseIdentifier: SectionHeaderView.reuseID)
        view.addSubview(collectionView)
        // Allow the banner to extend beyond the collection view bounds during overscroll zoom
        collectionView.clipsToBounds = false
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func makeHomeLayout() -> UICollectionViewLayout {
        let isRegular = traitCollection.horizontalSizeClass == .regular
        let viewH = view.bounds.height > 0 ? view.bounds.height : UIScreen.main.bounds.height
        let computedBannerHeight = FeaturedBannerCell.bannerHeight(isRegular: isRegular, viewHeight: viewH)
        return UICollectionViewCompositionalLayout { sectionIndex, _ -> NSCollectionLayoutSection? in
            if sectionIndex == 0 {
                // Featured hero banner — full-width, bannerHeight tall, no orthogonal scroll
                let item = NSCollectionLayoutItem(
                    layoutSize: .init(widthDimension: .fractionalWidth(1.0),
                                      heightDimension: .fractionalHeight(1.0)))
                let group = NSCollectionLayoutGroup.vertical(
                    layoutSize: .init(widthDimension: .fractionalWidth(1.0),
                                      heightDimension: .absolute(computedBannerHeight)),
                    subitems: [item])
                let bannerSection = NSCollectionLayoutSection(group: group)
                // Explicit .zero so no additional insets are added.
                // Full-width is ensured by collectionView.contentInsetAdjustmentBehavior = .never
                // (set in viewDidLoad) which disables system safe-area scroll-view adjustments.
                // contentInsetsReference is left at default (.automatic) because the type
                // changed between Xcode versions and .layoutContainer is not available on all.
                bannerSection.contentInsets = .zero
                return bannerSection
                // No header supplementary for section 0
            }
            // Sections 1..n: horizontal-scroll poster rows (Hayase small.svelte card ratio)
            // Web: each card has p-4 (16pt) all around. Card content is w-[9.5rem] (152pt).
            // So each card's outer slot = 152 + 32 = 184pt. Gap between covers = 32pt.
            let itemW = PosterLayout.width + 32  // 152 + 32 = 184pt total slot width
            let item = NSCollectionLayoutItem(
                layoutSize: .init(widthDimension: .absolute(itemW),
                                  heightDimension: .absolute(PosterLayout.height)))
            // 32pt trailing inset: content renders in left 152pt, gap on right
            item.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 32)
            let group = NSCollectionLayoutGroup.horizontal(
                layoutSize: .init(widthDimension: .estimated(itemW),
                                  heightDimension: .absolute(PosterLayout.height)),
                subitems: [item])
            let section = NSCollectionLayoutSection(group: group)
            section.orthogonalScrollingBehavior = .continuous
            // Section leading = web first card's p-4 left (16pt)
            // Section trailing = 0 (last card's 32pt trailing inset provides right padding)
            // pb-5 = 20pt bottom (web scroll container -mb-5 pb-5)
            section.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 16, bottom: 20, trailing: 0)
            // Header: pt-5 (20pt top) + text-lg (18pt) + 10pt bottom = 48pt total
            let headerSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0),
                                                    heightDimension: .absolute(48))
            let header = NSCollectionLayoutBoundarySupplementaryItem(
                layoutSize: headerSize,
                elementKind: UICollectionView.elementKindSectionHeader,
                alignment: .top)
            section.boundarySupplementaryItems = [header]
            return section
        }
    }

    private func makeSearchLayout() -> UICollectionViewLayout {
        // Hayase search: grid-cols-[repeat(auto-fill,minmax(184px,max-content))]
        // On iPhone (375-430pt wide), minmax(184px) fits 2 columns; on iPad use 4 columns.
        let isIPad = UIDevice.current.userInterfaceIdiom == .pad
        let cols: CGFloat = isIPad ? 4 : 2
        let interColumnGap: CGFloat = 8  // gap between adjacent items (item.contentInsets.trailing)
        let leadingPadding: CGFloat = 16
        let trailingPadding: CGFloat = 8
        // Each item contributes its trailing contentInset as the gap to its right neighbour (or section
        // trailing for the last item), so totalPad = section.leading + section.trailing + cols * gap.
        let totalPad: CGFloat = leadingPadding + trailingPadding + interColumnGap * cols
        // Use view bounds if already laid out, else fall back to screen width.
        // viewWillTransition recreates the layout after each rotation so this stays accurate.
        let containerW = view.bounds.width > 0 ? view.bounds.width : UIScreen.main.bounds.width
        let itemWidth = floor((containerW - totalPad) / cols)
        let itemHeight = floor(itemWidth * 290.0 / 152.0)
        let item = NSCollectionLayoutItem(
            layoutSize: .init(widthDimension: .absolute(itemWidth),
                              heightDimension: .absolute(itemHeight)))
        item.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 0, bottom: 0, trailing: interColumnGap)
        let group = NSCollectionLayoutGroup.horizontal(
            layoutSize: .init(widthDimension: .fractionalWidth(1.0),
                              heightDimension: .absolute(itemHeight + 8)),
            subitems: Array(repeating: item, count: Int(cols)))
        let section = NSCollectionLayoutSection(group: group)
        section.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: leadingPadding, bottom: 8, trailing: trailingPadding)
        return UICollectionViewCompositionalLayout(section: section)
    }

    private func setupSearchController() {
        searchController = UISearchController(searchResultsController: nil)
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = "Search anime…"
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
        definesPresentationContext = true
    }

    private func setupOverlays() {
        loadingIndicator = UIActivityIndicatorView(style: .large)
        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
        loadingIndicator.hidesWhenStopped = true
        view.addSubview(loadingIndicator)

        emptyLabel = UILabel()
        emptyLabel.text = "No anime found"
        emptyLabel.textColor = .secondaryLabel
        emptyLabel.font = .nunito(ofSize: 17)
        emptyLabel.textAlignment = .center
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.isHidden = true
        view.addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            loadingIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    private func setupFetchedResultsController() {
        let context = CoreDataService.sharedCoreDataService.mainQueueContext
        let req = NSFetchRequest<Animes>(entityName: Animes.entityName)
        req.predicate = NSPredicate(format: "animeFlagTemp == YES")
        req.sortDescriptors = [NSSortDescriptor(key: "animeOrder", ascending: true)]
        animeResultsController = NSFetchedResultsController(fetchRequest: req,
                                                            managedObjectContext: context,
                                                            sectionNameKeyPath: nil,
                                                            cacheName: nil)
        performFetch()
    }

    private func setupNotifications() {
        NotificationCenter.default.addObserver(self,
            selector: #selector(handleDidUpdate),
            name: NSNotification.Name(AniListClient.LocalAnimeDidUpdateNotification), object: nil)
        NotificationCenter.default.addObserver(self,
            selector: #selector(handleUpdateFailed),
            name: NSNotification.Name(AniListClient.LocalAnimeUpdateFailedNotification), object: nil)
        NotificationCenter.default.addObserver(self,
            selector: #selector(handleTrackingDidChange(_:)),
            name: LocalTracking.didChange, object: nil)
    }

    // MARK: - Data Loading

    private func loadSections() {
        isSearching = false
        sections = []
        bannerItems = []
        isLoadingSections = true
        collectionView.setCollectionViewLayout(makeHomeLayout(), animated: false)
        collectionView.reloadData()
        loadingIndicator.isHidden = true
        emptyLabel.isHidden = true

        // Fetch banner items separately with SCORE_DESC — matches Hayase banner.svelte:
        //   client.search({ sort: ['SCORE_DESC'], perPage: 5, season: currentSeason,
        //                   seasonYear: currentYear, statusNot: ['NOT_YET_RELEASED'] })
        AniListClient.shared.fetchBannerItems { [weak self] bannerResults in
            guard let self = self else { return }
            if !bannerResults.isEmpty {
                self.bannerItems = bannerResults
                // Reload banner cell if it already exists
                if self.collectionView.numberOfSections > 0 {
                    self.collectionView.reloadItems(at: [IndexPath(item: 0, section: 0)])
                    // prepareForReuse resets the banner cell's alpha; re-sync the fade state.
                    DispatchQueue.main.async { self.syncBannerToCurrentScrollPosition() }
                }
            }
        }

        AniListClient.shared.fetchHomeSections { [weak self] fetchedSections in
            guard let self = self else { return }
            self.fetchedHomeSections = fetchedSections

            // If banner didn't load from the separate SCORE_DESC query, fall back to first section
            if self.bannerItems.isEmpty {
                self.bannerItems = fetchedSections.first?.items ?? []
            }

            self.loadPersonalSections(fetchedSections: fetchedSections, fetchRemoteLists: true)
        }
    }

    private func loadPersonalSections(fetchedSections: [HomeSectionData], fetchRemoteLists: Bool) {
        // Fetch personalized sections from AniList user lists and local watch progress.
        // This mirrors desktop home/+page.svelte, with local progress merged into
        // Continue Watching so offline/local tracking updates the home page too.
        personalSectionsLoadID += 1
        let loadID = personalSectionsLoadID

        let applyLists: (AniListTracking.UserListIDs?) -> Void = { [weak self] userListIDs in
            guard let self = self else { return }

            let localContinueIDs = WatchProgressService.shared.continueWatchingAnilistIDs()
            self.lastLocalContinueIDs = localContinueIDs
            let remoteContinueIDs = userListIDs?.continueIDs ?? []
            let continueIDs = self.mergeIDs(localContinueIDs, remoteContinueIDs)

            let planningIDs = userListIDs?.planningIDs ?? []
            let sequelIDs = userListIDs?.sequelIDs ?? []

            let group = DispatchGroup()
            let syncQueue = DispatchQueue(label: "com.hayase.personalSections")
            var personalSections: [(index: Int, section: HomeSectionData)] = []

            if !continueIDs.isEmpty {
                group.enter()
                AniListClient.shared.fetchSectionByIDs(Array(continueIDs.prefix(50))) { items in
                    if !items.isEmpty {
                        syncQueue.sync {
                            personalSections.append((index: 0,
                                                     section: HomeSectionData(title: "Continue Watching", items: items)))
                        }
                    }
                    group.leave()
                }
            }

            if !planningIDs.isEmpty {
                group.enter()
                AniListClient.shared.fetchSectionByIDsFiltered(
                    planningIDs,
                    status: ["FINISHED", "RELEASING"]
                ) { items in
                    if !items.isEmpty {
                        syncQueue.sync {
                            personalSections.append((index: 1,
                                                     section: HomeSectionData(title: "Your List", items: items)))
                        }
                    }
                    group.leave()
                }
            }

            if !sequelIDs.isEmpty {
                group.enter()
                AniListClient.shared.fetchSectionByIDsFiltered(
                    sequelIDs,
                    status: ["FINISHED", "RELEASING"],
                    onList: false
                ) { items in
                    if !items.isEmpty {
                        syncQueue.sync {
                            personalSections.append((index: 2,
                                                     section: HomeSectionData(title: "Sequels You Missed", items: items)))
                        }
                    }
                    group.leave()
                }
            }

            group.notify(queue: .main) { [weak self] in
                guard let self = self else { return }
                guard loadID == self.personalSectionsLoadID else { return }
                let sorted = personalSections.sorted { $0.index < $1.index }.map { $0.section }
                self.finishLoadSections(fetchedSections: fetchedSections, personalSections: sorted)
            }
        }

        if fetchRemoteLists {
            AniListTracking.shared.fetchUserLists(completion: applyLists)
        } else {
            applyLists(AniListTracking.shared.cachedUserLists())
        }
    }

    private func mergeIDs(_ primary: [Int], _ secondary: [Int]) -> [Int] {
        var seen = Set<Int>()
        var result: [Int] = []
        for id in primary + secondary where seen.insert(id).inserted {
            result.append(id)
        }
        return result
    }

    @objc private func handleTrackingDidChange(_ notification: Notification) {
        guard !isSearching else { return }
        let currentLocalContinueIDs = WatchProgressService.shared.continueWatchingAnilistIDs()
        let remoteListChanged = notification.object is AniListTracking
        guard remoteListChanged || fetchedHomeSections.isEmpty || currentLocalContinueIDs != lastLocalContinueIDs else { return }
        homeRefreshTimer?.invalidate()
        homeRefreshTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: false) { [weak self] _ in
            guard let self else { return }
            if self.fetchedHomeSections.isEmpty {
                self.loadSections()
            } else {
                self.loadPersonalSections(fetchedSections: self.fetchedHomeSections, fetchRemoteLists: false)
            }
        }
    }

    /// Combines personal and fetched sections and reloads the collection view.
    private func finishLoadSections(fetchedSections: [HomeSectionData], personalSections: [HomeSectionData]) {
        self.isLoadingSections = false
        // Desktop order: Continue Watching, Your List, Sequels You Missed, then generic sections
        var allSections = personalSections
        allSections.append(contentsOf: fetchedSections)
        self.sections = allSections
        self.collectionView.reloadData()
        self.loadingIndicator.stopAnimating()
        self.emptyLabel.isHidden = !allSections.isEmpty
        // prepareForReuse resets the banner cell's alpha/state; re-sync the fade.
        // scrollViewDidScroll is not automatically re-fired after reloadData when the
        // contentOffset hasn't changed, so we have to call this explicitly.
        DispatchQueue.main.async { self.syncBannerToCurrentScrollPosition() }
    }

    private func performFetch() {
        try? animeResultsController?.performFetch()
    }

    private func reloadUI() {
        performFetch()
        collectionView.reloadData()
        let count = animeResultsController?.sections?.first?.objects?.count ?? 0
        emptyLabel.isHidden = count > 0
    }

    // MARK: - Notifications (search flow only)

    @objc private func handleDidUpdate() {
        guard isSearching else { return }
        loadingIndicator.stopAnimating()
        reloadUI()
    }

    @objc private func handleUpdateFailed() {
        guard isSearching else { return }
        loadingIndicator.stopAnimating()
        reloadUI()
    }

    // MARK: - Navigation

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        super.prepare(for: segue, sender: sender)
        guard segue.identifier == "showAnimeDetail",
              let destination = segue.destination as? AnimeDetailViewController else { return }
        if let item = pendingAnimeItem {
            destination.animeItem = item
            pendingAnimeItem = nil
        } else if let indexPath = sender as? IndexPath {
            destination.animeEntity = animeResultsController?.object(at: indexPath)
        }
    }
}

// MARK: - UICollectionViewDataSource

extension BrowseAnimeViewController: UICollectionViewDataSource {

    func numberOfSections(in collectionView: UICollectionView) -> Int {
        if isSearching { return 1 }
        // While loading, show 1 banner skeleton + 3 poster row skeletons
        if isLoadingSections { return 4 }
        // Section 0 = hero banner (only when we have data), sections 1..n = rows
        return sections.isEmpty ? 0 : sections.count + 1
    }

    func collectionView(_ collectionView: UICollectionView,
                        numberOfItemsInSection section: Int) -> Int {
        if isSearching {
            return animeResultsController?.sections?.first?.objects?.count ?? 0
        }
        if isLoadingSections {
            return section == 0 ? 1 : 10
        }
        if section == 0 { return sections.isEmpty ? 0 : 1 }      // banner = 1 item
        let rowSection = section - 1
        guard rowSection < sections.count else { return 0 }
        return sections[rowSection].items.count
    }

    func collectionView(_ collectionView: UICollectionView,
                        cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        // Search mode: plain poster grid
        if isSearching {
            guard let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: AnimeCollectionViewCell.reuseID,
                for: indexPath) as? AnimeCollectionViewCell else { return UICollectionViewCell() }
            if let anime = animeResultsController?.object(at: indexPath) {
                cell.configure(with: anime)
            }
            return cell
        }

        // Skeleton mode: shimmer placeholders while sections load
        if isLoadingSections {
            if indexPath.section == 0 {
                return collectionView.dequeueReusableCell(
                    withReuseIdentifier: SkeletonBannerCell.reuseID, for: indexPath)
            }
            return collectionView.dequeueReusableCell(
                withReuseIdentifier: SkeletonPosterCell.reuseID, for: indexPath)
        }

        // Section 0: hero banner (always uses the trending/popular items, never Continue Watching)
        if indexPath.section == 0 {
            guard let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: FeaturedBannerCell.reuseID,
                for: indexPath) as? FeaturedBannerCell else { return UICollectionViewCell() }
            if !bannerItems.isEmpty {
                cell.configure(with: bannerItems)
            }
            // Wire play button → navigate to anime detail
            cell.onPlayTapped = { [weak self] item in
                guard let self else { return }
                self.pendingAnimeItem = item
                self.performSegue(withIdentifier: "showAnimeDetail", sender: nil)
            }
            // Wire favorite/bookmark buttons to AniList tracking
            cell.onFavorite = { item in
                AniListTracking.shared.toggleFavourite(mediaID: item.id)
            }
            cell.onBookmark = { item in
                AniListTracking.shared.fetchMediaWithEntry(anilistID: item.id) { entry, _, _, _, _ in
                    if let listID = entry?.listID {
                        AniListTracking.shared.deleteEntry(listID: listID, mediaID: item.id)
                    } else {
                        AniListTracking.shared.entry(mediaID: item.id, status: "PLANNING")
                    }
                }
            }
            // Wire badge taps → navigate to Search tab with the appropriate filter
            cell.onBadgeTapped = { [weak self] filterType, value, value2 in
                guard let self else { return }
                self.navigateToSearch(filterType: filterType, value: value, value2: value2)
            }
            // Wire genre taps → navigate to Search tab with genre filter
            cell.onGenreTapped = { [weak self] genre in
                guard let self else { return }
                self.navigateToSearch(genre: genre)
            }
            return cell
        }

        // Sections 1..n: poster row
        guard let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: AnimeCollectionViewCell.reuseID,
            for: indexPath) as? AnimeCollectionViewCell else { return UICollectionViewCell() }
        let rowSection = indexPath.section - 1
        if rowSection < sections.count, indexPath.item < sections[rowSection].items.count {
            cell.configure(with: sections[rowSection].items[indexPath.item])
        }
        return cell
    }

    func collectionView(_ collectionView: UICollectionView,
                        viewForSupplementaryElementOfKind kind: String,
                        at indexPath: IndexPath) -> UICollectionReusableView {
        // Section 0 never has a supplementary header (not added to layout)
        let header = collectionView.dequeueReusableSupplementaryView(
            ofKind: kind,
            withReuseIdentifier: SectionHeaderView.reuseID,
            for: indexPath) as? SectionHeaderView ?? SectionHeaderView(frame: .zero)
        // indexPath.section here is 1..n → map to sections[section - 1]
        let rowSection = indexPath.section - 1
        if isLoadingSections {
            header.configure(title: "")
            header.onViewMore = nil
        } else if !isSearching, rowSection >= 0, rowSection < sections.count {
            header.configure(title: sections[rowSection].title)
            let section = sections[rowSection]
            // "View More" → switch to Search tab (Hayase: goto('/app/search', { state: { search: variables } }))
            // and pre-apply this section's genre + sort filter to SearchViewController
            header.onViewMore = { [weak self] in
                guard let self = self else { return }
                guard let controllers = self.tabBarController?.viewControllers,
                      controllers.count > 1,
                      let navController = controllers[1] as? UINavigationController,
                      let searchVC = navController.viewControllers.first as? SearchViewController else {
                    self.tabBarController?.selectedIndex = 1
                    return
                }
                searchVC.prefillSearch(genre: section.filterGenre, sort: section.filterSort)
                self.tabBarController?.selectedIndex = 1
            }
        }
        return header
    }
}

// MARK: - UICollectionViewDelegate

extension BrowseAnimeViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView,
                        didSelectItemAt indexPath: IndexPath) {
        if isSearching {
            pendingAnimeItem = nil
            performSegue(withIdentifier: "showAnimeDetail", sender: indexPath)
            return
        }
        // Ignore taps on skeleton placeholder cells
        if isLoadingSections { return }
        // Tap on hero banner → navigate to the currently-featured anime
        if indexPath.section == 0 {
            guard let cell = collectionView.cellForItem(at: indexPath) as? FeaturedBannerCell,
                  let item = cell.currentItem else { return }
            pendingAnimeItem = item
            performSegue(withIdentifier: "showAnimeDetail", sender: nil)
            return
        }
        // Tap on poster row
        let rowSection = indexPath.section - 1
        guard rowSection < sections.count,
              indexPath.item < sections[rowSection].items.count else { return }
        pendingAnimeItem = sections[rowSection].items[indexPath.item]
        performSegue(withIdentifier: "showAnimeDetail", sender: nil)
    }

    // MARK: - UIScrollViewDelegate (scroll-driven banner effects)

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard !isSearching else { return }
        syncBannerToCurrentScrollPosition()
    }

    /// Applies the banner scroll effects (zoom + fade) based on the current contentOffset.
    /// Must be called any time the scroll position or the banner cell could be stale:
    ///   • from scrollViewDidScroll (every scroll event)
    ///   • from viewWillAppear (returning from a child VC — scrollViewDidScroll won't re-fire)
    ///   • after reloadData() (prepareForReuse resets the cell; the scroll event won't re-fire)
    ///
    /// Matches the interface's pattern:
    ///   hideBanner.value = false        // at component init
    ///   hideBanner.value = scrollTop > 100  // in every scroll event
    private func syncBannerToCurrentScrollPosition() {
        let offsetY = collectionView.contentOffset.y
        let bannerIndexPath = IndexPath(item: 0, section: 0)
        guard let bannerCell = collectionView.cellForItem(at: bannerIndexPath) as? FeaturedBannerCell else { return }

        if offsetY < 0 {
            // User is pulling down past the top → zoom the banner image
            bannerCell.applyOverscrollZoom(-offsetY)
            bannerCell.applyScrollFade(0)  // fully visible when at top
        } else {
            // User scrolling down → reset zoom and apply fade
            bannerCell.applyOverscrollZoom(0)
            bannerCell.applyScrollFade(offsetY)
        }
    }

    // MARK: - Navigate to Search with filters

    /// Navigate to Search tab with a genre filter. Matches web: goto('/app/search', { state: { search: { genre: [genre] } } })
    private func navigateToSearch(genre: String) {
        guard let controllers = tabBarController?.viewControllers,
              controllers.count > 1,
              let navController = controllers[1] as? UINavigationController,
              let searchVC = navController.viewControllers.first as? SearchViewController else {
            tabBarController?.selectedIndex = 1
            return
        }
        searchVC.prefillSearchExtended(genre: genre)
        tabBarController?.selectedIndex = 1
    }

    /// Navigate to Search tab with a badge filter. filterType: "format", "status", "season", "score"
    private func navigateToSearch(filterType: String, value: String, value2: String?) {
        guard let controllers = tabBarController?.viewControllers,
              controllers.count > 1,
              let navController = controllers[1] as? UINavigationController,
              let searchVC = navController.viewControllers.first as? SearchViewController else {
            tabBarController?.selectedIndex = 1
            return
        }
        switch filterType {
        case "format":
            searchVC.prefillSearchExtended(format: value)
        case "status":
            searchVC.prefillSearchExtended(status: value)
        case "season":
            let year = value2.flatMap { Int($0) }
            searchVC.prefillSearchExtended(season: value, seasonYear: year)
        case "score":
            searchVC.prefillSearchExtended(sort: value)
        default:
            break
        }
        tabBarController?.selectedIndex = 1
    }
}

extension BrowseAnimeViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        let text = searchController.searchBar.text ?? ""
        searchDebounceTimer?.invalidate()

        let newIsSearching = !text.isEmpty
        if !newIsSearching {
            if isSearching {
                lastSearchString = ""
                loadSections()
            }
            return
        }

        if !isSearching {
            isSearching = true
            collectionView.setCollectionViewLayout(makeSearchLayout(), animated: false)
            collectionView.reloadData()
        }

        searchDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            guard let self = self, text != self.lastSearchString else { return }
            self.lastSearchString = text
            self.loadingIndicator.startAnimating()
            self.emptyLabel.isHidden = true
            AniListClient.shared.UpdateTempAnimesWithSearchString(text)
        }
    }
}
