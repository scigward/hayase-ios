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
        gradient.colors = [UIColor.clear.cgColor,
                           UIColor.black.withAlphaComponent(0.82).cgColor]
        gradient.locations = [0.15, 1.0]
        layer.addSublayer(gradient)
    }

    required init?(coder: NSCoder) { super.init(coder: coder) }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradient.frame = bounds
    }
}

// MARK: - FeaturedBannerCell
// Matches Hayase's full-banner.svelte: blurred background image, cover art on the left,
// title/badges/description on the right, dot indicators at the bottom, 15-second auto-rotation.

private final class FeaturedBannerCell: UICollectionViewCell {
    static let reuseID = "FeaturedBannerCell"
    private static let rotationInterval: TimeInterval = 15
    private static let bannerHeight: CGFloat = 260

    // Exposed so BrowseAnimeViewController can navigate to the currently-shown anime on tap
    var currentItem: AnimeItem? { items.isEmpty ? nil : items[currentIndex] }

    private var items: [AnimeItem] = []
    private var currentIndex = 0
    private var rotationTimer: Timer?
    private var bannerTask: URLSessionDataTask?
    private var coverTask: URLSessionDataTask?

    // MARK: Views

    private let backgroundImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.backgroundColor = .systemGray5
        return iv
    }()

    /// Dark translucent dim on top of background for text readability
    private let dimView: UIView = {
        let v = UIView()
        v.backgroundColor = UIColor.black.withAlphaComponent(0.52)
        return v
    }()

    private let gradientView = BannerGradientView()

    private let coverImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.backgroundColor = .systemGray4
        iv.layer.cornerRadius = 6
        return iv
    }()

    private let titleLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 18, weight: .black)
        l.textColor = .white
        l.numberOfLines = 2
        l.shadowColor = UIColor.black.withAlphaComponent(0.5)
        l.shadowOffset = CGSize(width: 0, height: 1)
        return l
    }()

    private let romajiLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 11)
        l.textColor = UIColor.white.withAlphaComponent(0.7)
        l.numberOfLines = 1
        return l
    }()

    private let badgeStack: UIStackView = {
        let sv = UIStackView()
        sv.axis = .horizontal
        sv.spacing = 5
        sv.alignment = .center
        return sv
    }()

    private let descriptionLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 11)
        l.textColor = UIColor.white.withAlphaComponent(0.7)
        l.numberOfLines = 2
        return l
    }()

    private let dotsStack: UIStackView = {
        let sv = UIStackView()
        sv.axis = .horizontal
        sv.spacing = 5
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

        [backgroundImageView, dimView, gradientView, coverImageView].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview($0)
        }

        let textStack = UIStackView(arrangedSubviews: [titleLabel, romajiLabel, badgeStack, descriptionLabel])
        textStack.axis = .vertical
        textStack.spacing = 4
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

            dimView.topAnchor.constraint(equalTo: contentView.topAnchor),
            dimView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            dimView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            dimView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            gradientView.topAnchor.constraint(equalTo: contentView.topAnchor),
            gradientView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            gradientView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            gradientView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            dotsStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            dotsStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),

            coverImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            coverImageView.bottomAnchor.constraint(equalTo: dotsStack.topAnchor, constant: -10),
            coverImageView.widthAnchor.constraint(equalToConstant: 78),
            coverImageView.heightAnchor.constraint(equalToConstant: 110),

            textStack.leadingAnchor.constraint(equalTo: coverImageView.trailingAnchor, constant: 12),
            textStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            textStack.bottomAnchor.constraint(equalTo: dotsStack.topAnchor, constant: -8),
        ])
    }

    // MARK: Configuration

    func configure(with items: [AnimeItem]) {
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
            let showRomaji = item.titleRomaji != nil && item.titleRomaji != item.titleEnglish
            self.romajiLabel.text = showRomaji ? item.titleRomaji : nil
            self.romajiLabel.isHidden = !showRomaji
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
        loadImages(for: item)
    }

    private func loadImages(for item: AnimeItem) {
        bannerTask?.cancel()
        coverTask?.cancel()
        bannerTask = nil
        coverTask = nil

        // Background: prefer banner image, fallback to cover
        if let urlStr = (item.bannerURL ?? item.coverURL), !urlStr.isEmpty, let url = URL(string: urlStr) {
            if let cached = SharedImageCache.shared.object(forKey: urlStr as NSString) {
                backgroundImageView.image = cached
            } else {
                let captured = urlStr
                let biv = backgroundImageView
                bannerTask = URLSession.shared.dataTask(with: url) { [weak biv] data, _, _ in
                    guard let data = data, let image = UIImage(data: data) else { return }
                    SharedImageCache.shared.setObject(image, forKey: captured as NSString)
                    DispatchQueue.main.async {
                        UIView.transition(with: biv ?? UIImageView(), duration: 0.3,
                                          options: .transitionCrossDissolve,
                                          animations: { biv?.image = image })
                    }
                }
                bannerTask?.resume()
            }
        } else {
            backgroundImageView.image = nil
        }

        // Cover art
        if let urlStr = item.coverURL, !urlStr.isEmpty, let url = URL(string: urlStr) {
            if let cached = SharedImageCache.shared.object(forKey: urlStr as NSString) {
                coverImageView.image = cached
            } else {
                let captured = urlStr
                let civ = coverImageView
                coverTask = URLSession.shared.dataTask(with: url) { [weak civ] data, _, _ in
                    guard let data = data, let image = UIImage(data: data) else { return }
                    SharedImageCache.shared.setObject(image, forKey: captured as NSString)
                    DispatchQueue.main.async {
                        UIView.transition(with: civ ?? UIImageView(), duration: 0.3,
                                          options: .transitionCrossDissolve,
                                          animations: { civ?.image = image })
                    }
                }
                coverTask?.resume()
            }
        } else {
            coverImageView.image = nil
        }
    }

    private func updateBadges(for item: AnimeItem) {
        badgeStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        var texts: [String] = []
        if let s = item.status {
            switch s {
            case "RELEASING": texts.append("Airing")
            case "FINISHED": texts.append("Finished")
            case "NOT_YET_RELEASED": texts.append("Upcoming")
            default: texts.append(s.capitalized)
            }
        }
        if let e = item.episodes, e > 0 { texts.append("\(e) eps") }
        if let score = item.score, score > 0 { texts.append(String(format: "%.0f%%", score)) }
        for text in texts.prefix(3) {
            let l = UILabel()
            l.text = "  \(text)  "
            l.font = .systemFont(ofSize: 10, weight: .semibold)
            l.textColor = .white
            l.backgroundColor = UIColor.white.withAlphaComponent(0.18)
            l.layer.cornerRadius = 6
            l.layer.borderWidth = 0.5
            l.layer.borderColor = UIColor.white.withAlphaComponent(0.3).cgColor
            l.clipsToBounds = true
            badgeStack.addArrangedSubview(l)
        }
    }

    private func rebuildDots() {
        dotsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for _ in items {
            let dot = UIView()
            dot.layer.cornerRadius = 2
            dot.translatesAutoresizingMaskIntoConstraints = false
            dot.heightAnchor.constraint(equalToConstant: 4).isActive = true
            dot.widthAnchor.constraint(equalToConstant: 16).isActive = true
            dotsStack.addArrangedSubview(dot)
        }
        updateDots()
    }

    private func updateDots() {
        for (i, dot) in dotsStack.arrangedSubviews.enumerated() {
            dot.backgroundColor = (i == currentIndex) ? .white : UIColor.white.withAlphaComponent(0.3)
        }
    }

    private func startTimer() {
        rotationTimer?.invalidate()
        guard items.count > 1 else { return }
        rotationTimer = Timer.scheduledTimer(withTimeInterval: FeaturedBannerCell.rotationInterval, repeats: true) { [weak self] _ in
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
        coverTask?.cancel()
        coverTask = nil
        items = []
        backgroundImageView.image = nil
        coverImageView.image = nil
    }
}

// MARK: - SkeletonPosterCell
// Matches Hayase's cards/skeleton.svelte — a shimmer placeholder shown while home sections load.

private final class SkeletonPosterCell: UICollectionViewCell {
    static let reuseID = "SkeletonPosterCell"

    private let baseView: UIView = {
        let v = UIView()
        v.backgroundColor = .secondarySystemBackground
        v.layer.cornerRadius = 8
        v.clipsToBounds = true
        return v
    }()

    private let shimmerLayer: CAGradientLayer = {
        let g = CAGradientLayer()
        g.startPoint = CGPoint(x: 0, y: 0.5)
        g.endPoint = CGPoint(x: 1, y: 0.5)
        g.locations = [0, 0.5, 1]
        return g
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        baseView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(baseView)
        NSLayoutConstraint.activate([
            baseView.topAnchor.constraint(equalTo: contentView.topAnchor),
            baseView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            baseView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            baseView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
        baseView.layer.addSublayer(shimmerLayer)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        shimmerLayer.frame = baseView.bounds
        updateShimmerColors()
        if shimmerLayer.animation(forKey: "shimmer") == nil {
            startShimmer()
        }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        updateShimmerColors()
    }

    private func updateShimmerColors() {
        let base  = UIColor.secondarySystemBackground.cgColor
        let light = UIColor.tertiarySystemBackground.cgColor
        shimmerLayer.colors = [base, light, base]
    }

    private func startShimmer() {
        let anim = CABasicAnimation(keyPath: "locations")
        anim.fromValue = [-1.0, -0.5, 0.0]
        anim.toValue   = [1.0, 1.5, 2.0]
        anim.duration  = 1.4
        anim.repeatCount = .infinity
        shimmerLayer.add(anim, forKey: "shimmer")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        shimmerLayer.removeAllAnimations()
    }
}

// MARK: - SectionHeaderView
// Matches Hayase's section title + "View More" inline layout

private final class SectionHeaderView: UICollectionReusableView {
    static let reuseID = "SectionHeader"

    var onViewMore: (() -> Void)?

    private let titleLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 16, weight: .semibold)
        l.textColor = .label
        return l
    }()

    private lazy var viewMoreButton: UIButton = {
        let b = UIButton(type: .system)
        b.setTitle("View More", for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: 12)
        b.setTitleColor(.secondaryLabel, for: .normal)
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
        [titleLabel, viewMoreButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            viewMoreButton.trailingAnchor.constraint(equalTo: trailingAnchor),
            viewMoreButton.centerYAnchor.constraint(equalTo: centerYAnchor),
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
        static let width: CGFloat = 115
        static let height: CGFloat = 200
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

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupNavigationBar()
        setupCollectionView()
        setupSearchController()
        setupOverlays()
        setupFetchedResultsController()
        setupNotifications()
        loadSections()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        collectionView.indexPathsForSelectedItems?.forEach {
            collectionView.deselectItem(at: $0, animated: animated)
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        searchDebounceTimer?.invalidate()
    }

    // MARK: - Setup

    private func setupNavigationBar() {
        title = "Anime"
        navigationController?.navigationBar.prefersLargeTitles = true
        navigationItem.largeTitleDisplayMode = .always
        tabBarItem.title = "Home"
        tabBarItem.image = UIImage(systemName: "house")
        tabBarItem.selectedImage = UIImage(systemName: "house.fill")
    }

    private func setupCollectionView() {
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeHomeLayout())
        collectionView.backgroundColor = .systemBackground
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
                return NSCollectionLayoutSection(group: group)
                // No header supplementary for section 0
            }
            // Sections 1..n: horizontal-scroll poster rows (Hayase small.svelte card ratio)
            let item = NSCollectionLayoutItem(
                layoutSize: .init(widthDimension: .absolute(PosterLayout.width),
                                  heightDimension: .absolute(PosterLayout.height)))
            item.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 8)
            let group = NSCollectionLayoutGroup.horizontal(
                layoutSize: .init(widthDimension: .estimated(PosterLayout.width),
                                  heightDimension: .absolute(PosterLayout.height)),
                subitems: [item])
            let section = NSCollectionLayoutSection(group: group)
            section.orthogonalScrollingBehavior = .continuous
            section.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 16, bottom: 20, trailing: 16)
            let headerSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0),
                                                    heightDimension: .absolute(44))
            let header = NSCollectionLayoutBoundarySupplementaryItem(
                layoutSize: headerSize,
                elementKind: UICollectionView.elementKindSectionHeader,
                alignment: .top)
            section.boundarySupplementaryItems = [header]
            return section
        }
    }

    private func makeSearchLayout() -> UICollectionViewLayout {
        // 3-column portrait grid (same as before)
        let item = NSCollectionLayoutItem(
            layoutSize: .init(widthDimension: .fractionalWidth(1.0 / 3.0),
                              heightDimension: .fractionalHeight(1.0)))
        item.contentInsets = NSDirectionalEdgeInsets(top: 5, leading: 5, bottom: 5, trailing: 5)
        let group = NSCollectionLayoutGroup.horizontal(
            layoutSize: .init(widthDimension: .fractionalWidth(1.0),
                              heightDimension: .fractionalWidth(0.5)),
            subitems: [item])
        let section = NSCollectionLayoutSection(group: group)
        section.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8)
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
            // "Airing Today" is always sections[0]; "View More" pushes ScheduleViewController
            if rowSection == 0 {
                header.onViewMore = { [weak self] in
                    let vc = ScheduleViewController()
                    vc.title = "Schedule"
                    self?.navigationController?.pushViewController(vc, animated: true)
                }
            } else {
                header.onViewMore = nil
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

