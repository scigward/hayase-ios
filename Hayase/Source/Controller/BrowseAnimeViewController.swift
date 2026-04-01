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
    private let gradient = CAGradientLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        // Matches Hayase's banner-image.svelte radial-gradient for mobile:
        //   radial-gradient(75% 65% at 50% 34.97%, rgba(0,0,0,0.16) 30.56%, rgba(0,0,0,1) 100%)
        // Approximated as a linear gradient: light in the center-upper area, darkening at bottom.
        // Bottom stop uses --background (white: 0.04) instead of pure black so the banner edge
        // blends invisibly into the app background and no cut-off seam is visible.
        let bgColor = UIColor(white: 0.04, alpha: 1) // --background dark, same as app bg
        gradient.colors = [
            UIColor.black.withAlphaComponent(0.40).cgColor, // top edge
            UIColor.black.withAlphaComponent(0.16).cgColor, // ~25% — center of radial (light)
            UIColor.black.withAlphaComponent(0.16).cgColor, // ~40% — still light center
            UIColor.black.withAlphaComponent(0.50).cgColor, // ~65% — starts darkening
            bgColor.cgColor,                                 // bottom — blends into app bg
        ]
        gradient.locations = [0.0, 0.25, 0.40, 0.65, 1.0]
        layer.addSublayer(gradient)
    }

    required init?(coder: NSCoder) { super.init(coder: coder) }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradient.frame = bounds
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
    // Banner height: 70% of screen height — matches Hayase's banner-image.svelte
    // `h-[70vh] md:h-[80vh]` (70vh on mobile). Content sits at bottom of the tall banner.
    static let bannerHeight: CGFloat = UIScreen.main.bounds.height * 0.70

    var currentItem: AnimeItem? { items.isEmpty ? nil : items[currentIndex] }

    /// Exposes the background image view so the parent VC can apply scroll-driven zoom.
    var bannerImageView: UIImageView { backgroundImageView }

    /// Callback fired when the user taps the "Watch Now" / "Continue" play button.
    var onPlayTapped: ((AnimeItem) -> Void)?

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

    // Title: font-black text-3xl line-clamp-2 text-white text-shadow-lg text-center (mobile)
    private let titleLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 28, weight: .black)
        l.textColor = .white
        l.numberOfLines = 2
        l.textAlignment = .center  // Hayase mobile: text-center items-center
        l.shadowColor = UIColor.black.withAlphaComponent(0.5)
        l.shadowOffset = CGSize(width: 0, height: 2)
        return l
    }()

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

    // Badge row: hidden on mobile (Hayase: `hidden sm:flex`) — only shown on ≥640px screens.
    // On iPhone this is always hidden. Kept for iPad or larger screens.
    private let badgeStack: UIStackView = {
        let sv = UIStackView()
        sv.axis = .horizontal
        sv.spacing = 6
        sv.alignment = .center
        sv.isHidden = true // hidden on mobile — matches Hayase `hidden sm:flex`
        return sv
    }()

    // Description: text-white/70 text-xs line-clamp-2 text-center text-shadow-lg (centered on mobile)
    private let descriptionLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 11)
        l.textColor = UIColor.white.withAlphaComponent(0.7)
        l.numberOfLines = 2
        l.textAlignment = .center  // Hayase mobile: text-center
        l.shadowColor = UIColor.black.withAlphaComponent(0.5) // text-shadow-lg
        l.shadowOffset = CGSize(width: 0, height: 2)
        return l
    }()

    // Play button: bg-custom text-contrast — matches Hayase PlayButton
    // Shows "Watch Now" / "Continue" / "Rewatch" based on status (defaults to "Watch Now")
    // Hayase: size='default' (h-9 px-4 py-2), rounded-md (6pt), font-bold
    private let playButton: UIButton = {
        let b = UIButton(type: .system)
        let iconCfg = UIImage.SymbolConfiguration(pointSize: 13, weight: .bold)
        b.setTitle("  Watch Now", for: .normal)
        b.setImage(UIImage(systemName: "play.fill")?.withConfiguration(iconCfg), for: .normal)
        b.tintColor = .black
        b.setTitleColor(.black, for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: 15, weight: .bold)
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
        b.setImage(UIImage(systemName: "heart")?.withConfiguration(cfg), for: .normal)
        b.tintColor = .white
        b.layer.cornerRadius = 6  // rounded-md
        return b
    }()

    // Bookmark button: ghost variant, size='icon' (h-9 w-9 = 36pt) — bookmark icon
    // Same styling as favorite: transparent bg, rounded-md, 16pt icon, white tint
    private let bookmarkButton: UIButton = {
        let b = UIButton(type: .system)
        let cfg = UIImage.SymbolConfiguration(pointSize: 16, weight: .regular)
        b.setImage(UIImage(systemName: "bookmark")?.withConfiguration(cfg), for: .normal)
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

        // Button row: [Play (grow)  Favorite  Bookmark] — matches Hayase PlayButton/FavoriteButton/BookmarkButton
        // Hayase: flex flex-row w-[280px] max-w-full
        // Play: mr-2 (8pt), Fav: ml-2 (8pt) → 16pt gap between Play and Fav
        // Bookmark: ml-2 (8pt) → 8pt gap between Fav and Bookmark
        let buttonRow = UIStackView(arrangedSubviews: [playButton, favoriteButton, bookmarkButton])
        buttonRow.axis = .horizontal
        buttonRow.spacing = 8  // base spacing: ml-2 between Fav and Bookmark
        buttonRow.alignment = .center
        buttonRow.distribution = .fill
        buttonRow.setCustomSpacing(16, after: playButton)  // Play mr-2 + Fav ml-2 = 16pt
        // Play button grows to fill remaining space (Hayase: grow class)
        playButton.setContentHuggingPriority(.defaultLow, for: .horizontal)
        favoriteButton.setContentHuggingPriority(.required, for: .horizontal)
        bookmarkButton.setContentHuggingPriority(.required, for: .horizontal)
        favoriteButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        bookmarkButton.setContentCompressionResistancePriority(.required, for: .horizontal)

        // Wire play button tap → callback to parent VC for navigation
        playButton.addTarget(self, action: #selector(playButtonTapped), for: .touchUpInside)

        // Text stack: [clearlogoImageView, titleLabel, badgeStack, buttonRow, descriptionLabel]
        // Clearlogo replaces title visually — only one is visible at a time.
        // Hayase mobile: items-center text-center (centered on mobile)
        // Hayase gap-4 = 16pt between items in content column
        let textStack = UIStackView(arrangedSubviews: [clearlogoImageView, titleLabel, badgeStack, buttonRow, descriptionLabel])
        textStack.axis = .vertical
        textStack.spacing = 16  // Hayase: gap-4 = 1rem = 16pt
        textStack.alignment = .center  // Hayase mobile: items-center
        // Description has pt-3 (12pt) top padding in Hayase (separate column stacks below)
        textStack.setCustomSpacing(12, after: buttonRow)
        textStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(textStack)

        dotsStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(dotsStack)

        NSLayoutConstraint.activate([
            backgroundImageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            backgroundImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            backgroundImageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            backgroundImageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            gradientView.topAnchor.constraint(equalTo: contentView.topAnchor),
            gradientView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            gradientView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            gradientView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            // Dots centered at bottom — Hayase: each dot has pb-4 (16pt bottom padding)
            dotsStack.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            dotsStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),

            // Text stack centered above dots — Hayase: each dot has pt-2 (8pt top padding)
            textStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            textStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            textStack.bottomAnchor.constraint(equalTo: dotsStack.topAnchor, constant: -8),

            // Clearlogo: max height 60pt (scaled from Hayase's w-[30rem] for mobile),
            // natural aspect ratio preserved via .scaleAspectFit
            clearlogoImageView.heightAnchor.constraint(lessThanOrEqualToConstant: 60),

            // Play button row: w-[280px] max-w-full (Hayase)
            buttonRow.widthAnchor.constraint(equalToConstant: 280),
            playButton.heightAnchor.constraint(equalToConstant: 36),
            favoriteButton.widthAnchor.constraint(equalToConstant: 36),
            favoriteButton.heightAnchor.constraint(equalToConstant: 36),
            bookmarkButton.widthAnchor.constraint(equalToConstant: 36),
            bookmarkButton.heightAnchor.constraint(equalToConstant: 36),
        ])
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
            // Reset title/clearlogo — will be resolved by loadClearlogo
            self.titleLabel.text = item.titleEnglish ?? item.titleRomaji
            self.titleLabel.isHidden = false
            self.clearlogoImageView.isHidden = true
            self.clearlogoImageView.image = nil
            self.descriptionLabel.text = item.description
            self.descriptionLabel.isHidden = item.description?.isEmpty ?? true
            self.updateBadges(for: item)
            self.updateDots()
            // Play button bg-custom: use coverImage.color as background (Hayase --custom var)
            let customColor = Self.uiColor(fromHex: item.coverColor) ?? .white
            self.playButton.backgroundColor = customColor
            // Determine text contrast (Hayase: text-contrast — black or white based on luminance)
            let textColor = Self.contrastColor(for: customColor)
            self.playButton.tintColor = textColor
            self.playButton.setTitleColor(textColor, for: .normal)
            // Favorite/Bookmark: white icon in normal state (Hayase ghost variant inherits white text)
            // On Hayase the select:!text-custom only activates on press — iOS system highlight suffices
            self.favoriteButton.tintColor = .white
            self.bookmarkButton.tintColor = .white
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
        AnimeService.fetchFanartURL(anilistID: item.id) { [weak self] fanartURL in
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
        AnimeService.fetchClearlogoURL(anilistID: itemID) { [weak self] clearlogoURL in
            guard let self = self else { return }
            // Make sure we're still displaying the same item (rotation may have advanced)
            guard self.currentIndex < self.items.count, self.items[self.currentIndex].id == itemID else { return }
            guard let urlStr = clearlogoURL, let url = URL(string: urlStr) else {
                // No clearlogo — keep text title visible (already the default)
                return
            }
            // Check image cache first
            if let cached = SharedImageCache.shared.object(forKey: urlStr as NSString) {
                self.showClearlogo(cached, forItemID: itemID)
                return
            }
            let captured = urlStr
            self.clearlogoTask = URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
                guard let data, let image = UIImage(data: data) else { return }
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

    private func updateBadges(for item: AnimeItem) {
        badgeStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        var texts: [String] = []
        // full-banner.svelte: of(current) ?? duration(current) ?? 'N/A', format, status, score
        if let eps = item.episodes, eps > 0 { texts.append("\(eps) eps") }
        if let fmt = item.format { texts.append(fmt.capitalized) }
        if let st = item.status {
            switch st {
            case "RELEASING": texts.append("Airing")
            case "FINISHED": texts.append("Finished")
            case "NOT_YET_RELEASED": texts.append("Upcoming")
            default: texts.append(st.replacingOccurrences(of: "_", with: " ").capitalized)
            }
        }
        if let score = item.score, score > 0 { texts.append(String(format: "%.0f%%", score)) }
        for text in texts.prefix(4) {
            let l = UILabel()
            l.text = "  \(text)  "
            l.font = .systemFont(ofSize: 11, weight: .bold)
            // bg-primary/10 in dark = white/10%
            l.backgroundColor = UIColor.white.withAlphaComponent(0.10)
            l.textColor = .white
            l.layer.cornerRadius = 4
            l.clipsToBounds = true
            badgeStack.addArrangedSubview(l)
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
        let scale = 1.0 + overscroll / FeaturedBannerCell.bannerHeight
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

// MARK: - SectionHeaderView
// Matches Hayase home page: font-semibold text-lg text-muted-foreground + "View More" text-xs

private final class SectionHeaderView: UICollectionReusableView {
    static let reuseID = "SectionHeader"

    var onViewMore: (() -> Void)?

    private let titleLabel: UILabel = {
        let l = UILabel()
        // Hayase: font-semibold text-lg leading-none
        l.font = .systemFont(ofSize: 18, weight: .semibold)
        l.textColor = UIColor(white: 0.65, alpha: 1) // text-muted-foreground dark
        return l
    }()

    private lazy var viewMoreButton: UIButton = {
        let b = UIButton(type: .system)
        b.setTitle("View More", for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: 12) // text-xs
        b.setTitleColor(UIColor(white: 0.65, alpha: 1), for: .normal)
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

    // MARK: - Init (set tabBarItem before viewDidLoad so tab bar reads it at launch)

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        tabBarItem = UITabBarItem(
            title: "Home",
            image: UIImage(systemName: "house"),
            selectedImage: UIImage(systemName: "house.fill"))
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

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        // With contentInsetAdjustmentBehavior = .never, manually account for the tab bar
        // so the last section's content isn't hidden under it
        collectionView.contentInset.bottom = view.safeAreaInsets.bottom
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        searchDebounceTimer?.invalidate()
    }

    // MARK: - Setup

    private func setupNavigationBar() {
        // Hayase home/+page.svelte has no title — just content starting from the top
        title = nil
    }

    private func setupCollectionView() {
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeHomeLayout())
        collectionView.backgroundColor = UIColor(white: 0.04, alpha: 1) // --background dark: hsl(240,10%,3.9%)
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
        return UICollectionViewCompositionalLayout { sectionIndex, _ -> NSCollectionLayoutSection? in
            if sectionIndex == 0 {
                // Featured hero banner — full-width, bannerHeight tall, no orthogonal scroll
                let item = NSCollectionLayoutItem(
                    layoutSize: .init(widthDimension: .fractionalWidth(1.0),
                                      heightDimension: .fractionalHeight(1.0)))
                let group = NSCollectionLayoutGroup.vertical(
                    layoutSize: .init(widthDimension: .fractionalWidth(1.0),
                                      heightDimension: .absolute(FeaturedBannerCell.bannerHeight)),
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
            let item = NSCollectionLayoutItem(
                layoutSize: .init(widthDimension: .absolute(PosterLayout.width),
                                  heightDimension: .absolute(PosterLayout.height)))
            // 16pt trailing gap between cards (matches Hayase small.svelte p-4 outer padding)
            item.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 16)
            let group = NSCollectionLayoutGroup.horizontal(
                layoutSize: .init(widthDimension: .estimated(PosterLayout.width),
                                  heightDimension: .absolute(PosterLayout.height)),
                subitems: [item])
            let section = NSCollectionLayoutSection(group: group)
            section.orthogonalScrollingBehavior = .continuous
            // px-4 = 16pt leading, pt-5 top handled in header height, bottom 24pt breathing room
            section.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 16, bottom: 24, trailing: 0)
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
        emptyLabel.font = .systemFont(ofSize: 17)
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
            name: NSNotification.Name(AnimeService.LocalAnimeDidUpdateNotification), object: nil)
        NotificationCenter.default.addObserver(self,
            selector: #selector(handleUpdateFailed),
            name: NSNotification.Name(AnimeService.LocalAnimeUpdateFailedNotification), object: nil)
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
        AnimeService.sharedAnimeService.fetchBannerItems { [weak self] bannerResults in
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

        AnimeService.sharedAnimeService.fetchHomeSections { [weak self] fetchedSections in
            guard let self = self else { return }

            // If banner didn't load from the separate SCORE_DESC query, fall back to first section
            if self.bannerItems.isEmpty {
                self.bannerItems = fetchedSections.first?.items ?? []
            }

            // Fetch personalized sections from AniList user lists
            // (matches desktop home/+page.svelte: continueIDs, planningIDs, sequelIDs)
            AniListTracking.shared.fetchUserLists { [weak self] userListIDs in
                guard let self = self else { return }

                guard let ids = userListIDs,
                      (!ids.continueIDs.isEmpty || !ids.planningIDs.isEmpty || !ids.sequelIDs.isEmpty) else {
                    // No AniList user lists — fall back to local "Continue Watching" only
                    self.finishLoadSections(fetchedSections: fetchedSections, personalSections: [])
                    return
                }

                let group = DispatchGroup()
                let syncQueue = DispatchQueue(label: "com.hayase.personalSections")
                var personalSections: [(index: Int, section: HomeSectionData)] = []

                // "Continue Watching" — CURRENT/REPEATING with unwatched episodes
                // Desktop: client.search({ ids: continueIDs.slice(0, 50), sort: ['UPDATED_AT_DESC'] })
                if !ids.continueIDs.isEmpty {
                    group.enter()
                    let cappedIDs = Array(ids.continueIDs.prefix(50))
                    AnimeService.sharedAnimeService.fetchSectionByIDs(cappedIDs) { items in
                        if !items.isEmpty {
                            syncQueue.sync {
                                personalSections.append((index: 0,
                                                         section: HomeSectionData(title: "Continue Watching", items: items)))
                            }
                        }
                        group.leave()
                    }
                }

                // "Your List" — PLANNING entries, filtered to FINISHED/RELEASING
                // Desktop: client.search({ ids: planningIDs, status: ['FINISHED', 'RELEASING'], sort: ['START_DATE_DESC'] })
                if !ids.planningIDs.isEmpty {
                    group.enter()
                    AnimeService.sharedAnimeService.fetchSectionByIDsFiltered(
                        ids.planningIDs,
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

                // "Sequels You Missed" — SEQUEL relations from COMPLETED, not on user's list
                // Desktop: client.search({ ids: sequelIDs, status: ['FINISHED', 'RELEASING'], onList: false })
                if !ids.sequelIDs.isEmpty {
                    group.enter()
                    AnimeService.sharedAnimeService.fetchSectionByIDsFiltered(
                        ids.sequelIDs,
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
                    // Sort personal sections by their intended order and prepend
                    let sorted = personalSections.sorted { $0.index < $1.index }.map { $0.section }
                    self.finishLoadSections(fetchedSections: fetchedSections, personalSections: sorted)
                }
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
}

// MARK: - UISearchResultsUpdating

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
            AnimeService.sharedAnimeService.UpdateTempAnimesWithSearchString(text)
        }
    }
}