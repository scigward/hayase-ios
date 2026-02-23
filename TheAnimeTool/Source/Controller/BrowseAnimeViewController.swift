//
//  BrowseAnimeViewController.swift
//  TheAnimeTool
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
        // Approximate Hayase's radial-gradient:
        //   radial-gradient(75% 65% at 59% 35%, rgba(0,0,0,0.16) 30%, rgba(0,0,0,1) 100%)
        // Top darkens for status-bar readability; center is light; bottom is very dark for text.
        gradient.colors = [
            UIColor.black.withAlphaComponent(0.55).cgColor, // top  — status bar legible
            UIColor.black.withAlphaComponent(0.05).cgColor, // ~12% — image shows through
            UIColor.clear.cgColor,                           // ~50% — clear image centre
            UIColor.black.withAlphaComponent(0.88).cgColor, // bottom — text area
        ]
        gradient.locations = [0.0, 0.12, 0.50, 1.0]
        layer.addSublayer(gradient)
    }

    required init?(coder: NSCoder) { super.init(coder: coder) }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradient.frame = bounds
    }
}

// MARK: - FeaturedBannerCell
// Matches Hayase's full-banner.svelte exactly:
// • Full-bleed background image (banner or cover) — NO separate cover thumbnail
// • Black gradient overlay from ~15% to bottom (0.82 alpha)
// • Title: font-black, text-3xl (28pt on mobile), white, text-shadow, 2 lines
// • Badges row: bg-primary/10 (white/10%) pills — duration, format, status, score
// • Description: text-white/70, 2 lines, text-xs (11pt)
// • Dot progress indicators at bottom: inactive = white/20%, active animates to fill (bg-custom)
// • 15-second auto-rotation

private final class FeaturedBannerCell: UICollectionViewCell {
    static let reuseID = "FeaturedBannerCell"
    private static let rotationInterval: TimeInterval = 15
    // Banner height: UIScreen.main.bounds.height * 0.50 (50% of screen).
    // 80vh (like Hayase desktop) zooms landscape banner images too aggressively on narrow
    // iPhone viewports (the 1900×400 banner would show only ~15% of its width).
    // 50% shows ~27% of the banner width — a more balanced crop.
    static let bannerHeight: CGFloat = UIScreen.main.bounds.height * 0.50

    var currentItem: AnimeItem? { items.isEmpty ? nil : items[currentIndex] }

    private var items: [AnimeItem] = []
    private var currentIndex = 0
    private var rotationTimer: Timer?
    private var bannerTask: URLSessionDataTask?
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

    // Title: font-black text-3xl line-clamp-2 text-white text-shadow-lg
    private let titleLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 28, weight: .black)
        l.textColor = .white
        l.numberOfLines = 2
        l.shadowColor = UIColor.black.withAlphaComponent(0.5)
        l.shadowOffset = CGSize(width: 0, height: 2)
        return l
    }()

    // Badge row: bg-primary/10 pills (duration, format, status, score)
    private let badgeStack: UIStackView = {
        let sv = UIStackView()
        sv.axis = .horizontal
        sv.spacing = 6
        sv.alignment = .center
        return sv
    }()

    // Description: text-white/70 text-xs line-clamp-2
    private let descriptionLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 11)
        l.textColor = UIColor.white.withAlphaComponent(0.7)
        l.numberOfLines = 2
        return l
    }()

    // Progress dots row — animated fill for active dot
    private let dotsStack: UIStackView = {
        let sv = UIStackView()
        sv.axis = .horizontal
        sv.spacing = 6
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
        clipsToBounds = true

        [backgroundImageView, gradientView].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview($0)
        }

        // Text stack: [title, badgeStack, descriptionLabel]
        let textStack = UIStackView(arrangedSubviews: [titleLabel, badgeStack, descriptionLabel])
        textStack.axis = .vertical
        textStack.spacing = 8
        textStack.alignment = .leading
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

            // Dots at very bottom
            dotsStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            dotsStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),

            // Text stack just above dots, left + right margins
            textStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            textStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            textStack.bottomAnchor.constraint(equalTo: dotsStack.topAnchor, constant: -10),
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
            self.titleLabel.text = item.titleEnglish ?? item.titleRomaji
            self.descriptionLabel.text = item.description
            self.descriptionLabel.isHidden = item.description?.isEmpty ?? true
            self.updateBadges(for: item)
            self.updateDots()
        }
        if animated {
            UIView.transition(with: contentView, duration: 0.4, options: .transitionCrossDissolve, animations: block)
        } else {
            block()
        }
        loadBanner(for: item)
    }

    private func loadBanner(for item: AnimeItem) {
        bannerTask?.cancel()
        bannerTask = nil
        let urlStr = item.bannerURL ?? item.coverURL
        guard let urlStr = urlStr, let url = URL(string: urlStr) else {
            backgroundImageView.image = nil
            return
        }
        if let cached = SharedImageCache.shared.object(forKey: urlStr as NSString) {
            backgroundImageView.image = cached
            applyContentMode(for: cached)
            return
        }
        let captured = urlStr
        let biv = backgroundImageView
        bannerTask = URLSession.shared.dataTask(with: url) { [weak self, weak biv] data, _, _ in
            guard let data = data, let image = UIImage(data: data) else { return }
            SharedImageCache.shared.setObject(image, forKey: captured as NSString)
            DispatchQueue.main.async {
                self?.applyContentMode(for: image)
                UIView.transition(with: biv ?? UIImageView(), duration: 0.3,
                                  options: .transitionCrossDissolve,
                                  animations: { biv?.image = image })
            }
        }
        bannerTask?.resume()
    }

    /// Use .scaleAspectFit for landscape banner images (AniList banners ≈ 1900×400, ratio > 2:1)
    /// so the full image is visible without severe cropping.
    /// Use .scaleAspectFill for portrait/square cover fallbacks so they fill the cell nicely.
    private func applyContentMode(for image: UIImage) {
        let ratio = image.size.width / max(image.size.height, 1)
        backgroundImageView.contentMode = ratio > 1.5 ? .scaleAspectFit : .scaleAspectFill
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
            let dot = UIView()
            dot.layer.cornerRadius = 2
            dot.translatesAutoresizingMaskIntoConstraints = false
            dot.heightAnchor.constraint(equalToConstant: 4).isActive = true
            // Store width constraint keyed by index for efficient in-place updates
            let wc = dot.widthAnchor.constraint(equalToConstant: i == 0 ? 40 : 20)
            wc.isActive = true
            dotWidthConstraints[i] = wc
            dotsStack.addArrangedSubview(dot)
        }
        updateDots()
    }

    private func updateDots() {
        // full-banner.svelte: inactive bg-white/20 width 1.5rem (24pt), active bg-custom width 3rem (48pt)
        for (i, dot) in dotsStack.arrangedSubviews.enumerated() {
            let active = i == currentIndex
            // Update stored constraint constant directly — no remove/recreate cycle
            dotWidthConstraints[i]?.constant = active ? 40 : 20
            UIView.animate(withDuration: 0.3) {
                dot.backgroundColor = active
                    ? UIColor.white.withAlphaComponent(0.9)
                    : UIColor.white.withAlphaComponent(0.2)
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
        items = []
        backgroundImageView.image = nil
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
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // Restore nav bar when pushing child VCs (detail, etc.)
        navigationController?.setNavigationBarHidden(false, animated: animated)
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
        // On iPhone (375-430pt wide), minmax(184px) fits 2 columns
        let cols: CGFloat = 2
        let totalPad: CGFloat = 16 + 16 + 8 // leading + trailing + inter-column gap
        let itemWidth = floor((UIScreen.main.bounds.width - totalPad) / cols)
        let itemHeight = floor(itemWidth * 290.0 / 152.0)
        let item = NSCollectionLayoutItem(
            layoutSize: .init(widthDimension: .absolute(itemWidth),
                              heightDimension: .absolute(itemHeight)))
        item.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 0, bottom: 0, trailing: 8)
        let group = NSCollectionLayoutGroup.horizontal(
            layoutSize: .init(widthDimension: .fractionalWidth(1.0),
                              heightDimension: .absolute(itemHeight + 8)),
            subitems: [item, item])
        let section = NSCollectionLayoutSection(group: group)
        section.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 8)
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
        isLoadingSections = true
        collectionView.setCollectionViewLayout(makeHomeLayout(), animated: false)
        collectionView.reloadData()
        loadingIndicator.isHidden = true
        emptyLabel.isHidden = true
        AnimeService.sharedAnimeService.fetchHomeSections { [weak self] fetchedSections in
            guard let self = self else { return }

            // Prepend "Continue Watching" section from WatchProgressService (Hayase continueIDs)
            let continueIDs = WatchProgressService.shared.continueWatchingAnilistIDs()
            if continueIDs.isEmpty {
                self.isLoadingSections = false
                self.sections = fetchedSections
                self.collectionView.reloadData()
                self.loadingIndicator.stopAnimating()
                self.emptyLabel.isHidden = !fetchedSections.isEmpty
            } else {
                AnimeService.sharedAnimeService.fetchSectionByIDs(continueIDs) { [weak self] continueItems in
                    guard let self = self else { return }
                    self.isLoadingSections = false
                    var allSections = fetchedSections
                    if !continueItems.isEmpty {
                        allSections.insert(HomeSectionData(title: "Continue Watching",
                                                           items: continueItems), at: 0)
                    }
                    self.sections = allSections
                    self.collectionView.reloadData()
                    self.loadingIndicator.stopAnimating()
                    self.emptyLabel.isHidden = !allSections.isEmpty
                }
            }
        }
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

        // Section 0: hero banner (uses items from the first section as rotation pool)
        if indexPath.section == 0 {
            guard let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: FeaturedBannerCell.reuseID,
                for: indexPath) as? FeaturedBannerCell else { return UICollectionViewCell() }
            if !sections.isEmpty {
                cell.configure(with: sections[0].items)
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
                if let navController = self.tabBarController?.viewControllers?[1] as? UINavigationController,
                   let searchVC = navController.viewControllers.first as? SearchViewController {
                    searchVC.prefillSearch(genre: section.filterGenre, sort: section.filterSort)
                }
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

