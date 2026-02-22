//
//  BrowseAnimeViewController.swift
//  TheAnimeTool
//

import UIKit
import CoreData

// MARK: - FeaturedGradientView

private final class FeaturedGradientView: UIView {
    private let gradient = CAGradientLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        gradient.colors = [UIColor.clear.cgColor,
                           UIColor.black.withAlphaComponent(0.75).cgColor]
        gradient.locations = [0, 1]
        layer.addSublayer(gradient)
    }

    required init?(coder: NSCoder) { super.init(coder: coder) }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradient.frame = bounds
    }
}

// MARK: - SectionHeaderView

private final class SectionHeaderView: UICollectionReusableView {
    static let reuseID = "SectionHeader"

    var onViewMore: (() -> Void)?

    private let titleLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 17, weight: .bold)
        l.textColor = .label
        return l
    }()

    private lazy var viewMoreButton: UIButton = {
        let b = UIButton(type: .system)
        b.setTitle("View More", for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: 13)
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

    func configure(title: String) {
        titleLabel.text = title
    }
}

// MARK: - AnimeFeaturedCell

private final class AnimeFeaturedCell: UICollectionViewCell {
    static let reuseID = "FeaturedCell"

    private let bannerImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.backgroundColor = .systemGray5
        return iv
    }()

    private let gradientOverlay = FeaturedGradientView()

    private let titleLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 22, weight: .bold)
        l.textColor = .white
        l.numberOfLines = 2
        return l
    }()

    private let airBadge: UILabel = {
        let l = UILabel()
        l.text = "  Currently Airing  "
        l.font = .systemFont(ofSize: 10, weight: .bold)
        l.textColor = .white
        l.backgroundColor = .systemIndigo
        l.layer.cornerRadius = 8
        l.clipsToBounds = true
        return l
    }()

    private let scoreBadge: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 10, weight: .bold)
        l.textColor = .black
        l.backgroundColor = .systemYellow
        l.layer.cornerRadius = 9
        l.clipsToBounds = true
        l.textAlignment = .center
        return l
    }()

    private var currentURLString: String?
    private var imageTask: URLSessionDataTask?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        contentView.clipsToBounds = true
        [bannerImageView, gradientOverlay, airBadge, scoreBadge, titleLabel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview($0)
        }
        NSLayoutConstraint.activate([
            bannerImageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            bannerImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            bannerImageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            bannerImageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            gradientOverlay.topAnchor.constraint(equalTo: contentView.topAnchor),
            gradientOverlay.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            gradientOverlay.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            gradientOverlay.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            airBadge.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            airBadge.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),

            scoreBadge.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            scoreBadge.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            scoreBadge.widthAnchor.constraint(greaterThanOrEqualToConstant: 36),
            scoreBadge.heightAnchor.constraint(equalToConstant: 18),

            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            titleLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),
        ])
    }

    func configure(with item: AnimeItem) {
        titleLabel.text = item.titleEnglish ?? item.titleRomaji ?? "Unknown"
        if let score = item.score, score > 0 {
            scoreBadge.text = String(format: " %.0f%% ", score)
            scoreBadge.isHidden = false
        } else {
            scoreBadge.isHidden = true
        }

        let urlString = item.bannerURL ?? item.coverURL ?? ""
        currentURLString = urlString
        bannerImageView.image = nil
        imageTask?.cancel()
        guard !urlString.isEmpty, let url = URL(string: urlString) else { return }

        let captured = urlString
        imageTask = URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data = data, let image = UIImage(data: data) else { return }
            DispatchQueue.main.async {
                guard self?.currentURLString == captured else { return }
                UIView.transition(with: self?.bannerImageView ?? UIImageView(),
                                  duration: 0.3,
                                  options: .transitionCrossDissolve,
                                  animations: { self?.bannerImageView.image = image })
            }
        }
        imageTask?.resume()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageTask?.cancel()
        imageTask = nil
        currentURLString = nil
        bannerImageView.image = nil
        scoreBadge.isHidden = true
    }
}

// MARK: - BrowseAnimeViewController

class BrowseAnimeViewController: UIViewController {

    // MARK: - Properties

    private var sections: [HomeSectionData] = []
    private var isSearching: Bool = false
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
        collectionView.register(AnimeCollectionViewCell.self,
                                forCellWithReuseIdentifier: AnimeCollectionViewCell.reuseID)
        collectionView.register(AnimeFeaturedCell.self,
                                forCellWithReuseIdentifier: AnimeFeaturedCell.reuseID)
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
                // Featured hero card — full width, 220pt tall
                let item = NSCollectionLayoutItem(
                    layoutSize: .init(widthDimension: .fractionalWidth(1.0),
                                      heightDimension: .fractionalHeight(1.0)))
                let group = NSCollectionLayoutGroup.horizontal(
                    layoutSize: .init(widthDimension: .fractionalWidth(1.0),
                                      heightDimension: .absolute(220)),
                    subitems: [item])
                let section = NSCollectionLayoutSection(group: group)
                section.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 0, bottom: 16, trailing: 0)
                return section
            } else {
                // Horizontal scrolling row — 110×165pt cards
                let item = NSCollectionLayoutItem(
                    layoutSize: .init(widthDimension: .absolute(110),
                                      heightDimension: .absolute(165)))
                item.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 8)
                let group = NSCollectionLayoutGroup.horizontal(
                    layoutSize: .init(widthDimension: .estimated(110),
                                      heightDimension: .absolute(165)),
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
    }

    private func makeSearchLayout() -> UICollectionViewLayout {
        // 3-column portrait grid
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
        collectionView.setCollectionViewLayout(makeHomeLayout(), animated: false)
        collectionView.reloadData()
        loadingIndicator.startAnimating()
        emptyLabel.isHidden = true
        AnimeService.sharedAnimeService.fetchHomeSections { [weak self] fetchedSections in
            guard let self = self else { return }
            self.sections = fetchedSections
            self.collectionView.reloadData()
            self.loadingIndicator.stopAnimating()
            self.emptyLabel.isHidden = !fetchedSections.isEmpty
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
        return sections.isEmpty ? 0 : 1 + sections.count
    }

    func collectionView(_ collectionView: UICollectionView,
                        numberOfItemsInSection section: Int) -> Int {
        if isSearching {
            return animeResultsController?.sections?.first?.objects?.count ?? 0
        }
        if section == 0 {
            return sections.isEmpty ? 0 : min(1, sections[0].items.count)
        }
        return sections[section - 1].items.count
    }

    func collectionView(_ collectionView: UICollectionView,
                        cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        if isSearching {
            guard let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: AnimeCollectionViewCell.reuseID,
                for: indexPath) as? AnimeCollectionViewCell else { return UICollectionViewCell() }
            if let anime = animeResultsController?.object(at: indexPath) {
                cell.configure(with: anime)
            }
            return cell
        }

        if indexPath.section == 0 {
            guard let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: AnimeFeaturedCell.reuseID,
                for: indexPath) as? AnimeFeaturedCell else { return UICollectionViewCell() }
            if !sections.isEmpty && !sections[0].items.isEmpty {
                cell.configure(with: sections[0].items[0])
            }
            return cell
        }

        guard let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: AnimeCollectionViewCell.reuseID,
            for: indexPath) as? AnimeCollectionViewCell else { return UICollectionViewCell() }
        let item = sections[indexPath.section - 1].items[indexPath.item]
        cell.configure(with: item)
        return cell
    }

    func collectionView(_ collectionView: UICollectionView,
                        viewForSupplementaryElementOfKind kind: String,
                        at indexPath: IndexPath) -> UICollectionReusableView {
        let header = collectionView.dequeueReusableSupplementaryView(
            ofKind: kind,
            withReuseIdentifier: SectionHeaderView.reuseID,
            for: indexPath) as? SectionHeaderView ?? SectionHeaderView(frame: .zero)
        if !isSearching, indexPath.section > 0, indexPath.section - 1 < sections.count {
            header.configure(title: sections[indexPath.section - 1].title)
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
        if indexPath.section == 0 {
            guard !sections.isEmpty, !sections[0].items.isEmpty else { return }
            pendingAnimeItem = sections[0].items[0]
        } else {
            let item = sections[indexPath.section - 1].items[indexPath.item]
            pendingAnimeItem = item
        }
        // sender is nil because the item is passed via pendingAnimeItem, not an FRC index path
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

