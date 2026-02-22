//
//  SearchViewController.swift
//  TheAnimeTool
//
//  Hayase-style AniList anime search tab.
//  Matches src/routes/app/search/+page.svelte:
//  - UISearchController for title input (debounced 0.5 s)
//  - Horizontal filter chip bar: Genre, Format, Status, Sort
//  - 3-column UICollectionView of AnimeCollectionViewCell cards
//  - Infinite scroll (page-based)
//  - Tap → AnimeDetailViewController
//  - On first open, loads "Trending" anime so the screen is never empty.
//

import UIKit

// MARK: - FilterType

private enum FilterType: CaseIterable {
    case genre, format, status, sort

    var label: String {
        switch self {
        case .genre:  return "Genre"
        case .format: return "Format"
        case .status: return "Status"
        case .sort:   return "Sort"
        }
    }

    struct Option {
        let displayName: String
        let apiValue: String
    }

    var options: [Option] {
        switch self {
        case .genre:
            return [
                .init(displayName: "Action",        apiValue: "Action"),
                .init(displayName: "Adventure",     apiValue: "Adventure"),
                .init(displayName: "Comedy",        apiValue: "Comedy"),
                .init(displayName: "Drama",         apiValue: "Drama"),
                .init(displayName: "Fantasy",       apiValue: "Fantasy"),
                .init(displayName: "Horror",        apiValue: "Horror"),
                .init(displayName: "Mecha",         apiValue: "Mecha"),
                .init(displayName: "Music",         apiValue: "Music"),
                .init(displayName: "Mystery",       apiValue: "Mystery"),
                .init(displayName: "Psychological", apiValue: "Psychological"),
                .init(displayName: "Romance",       apiValue: "Romance"),
                .init(displayName: "Sci-Fi",        apiValue: "Sci-Fi"),
                .init(displayName: "Slice of Life", apiValue: "Slice of Life"),
                .init(displayName: "Sports",        apiValue: "Sports"),
                .init(displayName: "Supernatural",  apiValue: "Supernatural"),
                .init(displayName: "Thriller",      apiValue: "Thriller"),
            ]
        case .format:
            return [
                .init(displayName: "TV",      apiValue: "TV"),
                .init(displayName: "Movie",   apiValue: "MOVIE"),
                .init(displayName: "OVA",     apiValue: "OVA"),
                .init(displayName: "ONA",     apiValue: "ONA"),
                .init(displayName: "Special", apiValue: "SPECIAL"),
            ]
        case .status:
            return [
                .init(displayName: "Airing",       apiValue: "RELEASING"),
                .init(displayName: "Finished",     apiValue: "FINISHED"),
                .init(displayName: "Not Yet Aired", apiValue: "NOT_YET_RELEASED"),
            ]
        case .sort:
            return [
                .init(displayName: "Trending",  apiValue: "TRENDING_DESC"),
                .init(displayName: "Popular",   apiValue: "POPULARITY_DESC"),
                .init(displayName: "Score",     apiValue: "SCORE_DESC"),
                .init(displayName: "Newest",    apiValue: "START_DATE_DESC"),
            ]
        }
    }
}

// MARK: - SearchViewController

class SearchViewController: UIViewController {

    // MARK: - Filter state

    private var selectedGenre: String?
    private var selectedFormat: String?
    private var selectedStatus: String?
    private var selectedSort = "TRENDING_DESC"

    // MARK: - Results state

    private var animeResults: [AnimeItem] = []
    private var currentPage = 1
    private var hasNextPage = true
    private var isFetching = false
    private var currentTitle = ""
    private var searchDebounceTimer: Timer?

    // MARK: - Views

    private var searchController: UISearchController!
    private var filterScrollView: UIScrollView!
    private var filterStackView: UIStackView!
    private var collectionView: UICollectionView!
    private var emptyLabel: UILabel!
    private var loadingIndicator: UIActivityIndicatorView!

    /// Chip button for each filter type (to update title/appearance on selection)
    private var filterButtons: [FilterType: UIButton] = [:]

    // MARK: - Init

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        tabBarItem = UITabBarItem(
            title: "Search",
            image: UIImage(systemName: "magnifyingglass"),
            selectedImage: UIImage(systemName: "magnifyingglass.circle.fill"))
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        setupNavigationBar()
        setupSearchController()
        setupFilterBar()
        setupCollectionView()
        setupOverlays()
        // Load trending by default so the screen is never empty
        fetchResults(reset: true)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        collectionView.indexPathsForSelectedItems?.forEach {
            collectionView.deselectItem(at: $0, animated: animated)
        }
    }

    // MARK: - Setup

    private func setupNavigationBar() {
        title = "Search"
        navigationController?.navigationBar.prefersLargeTitles = true
        navigationItem.largeTitleDisplayMode = .always
    }

    private func setupSearchController() {
        searchController = UISearchController(searchResultsController: nil)
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = "Search anime on AniList…"
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
        definesPresentationContext = true
    }

    private func setupFilterBar() {
        filterScrollView = UIScrollView()
        filterScrollView.translatesAutoresizingMaskIntoConstraints = false
        filterScrollView.showsHorizontalScrollIndicator = false
        filterScrollView.alwaysBounceHorizontal = true
        filterScrollView.contentInset = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)

        filterStackView = UIStackView()
        filterStackView.translatesAutoresizingMaskIntoConstraints = false
        filterStackView.axis = .horizontal
        filterStackView.spacing = 8
        filterStackView.alignment = .center
        filterScrollView.addSubview(filterStackView)

        NSLayoutConstraint.activate([
            filterStackView.topAnchor.constraint(equalTo: filterScrollView.topAnchor, constant: 6),
            filterStackView.bottomAnchor.constraint(equalTo: filterScrollView.bottomAnchor, constant: -6),
            filterStackView.leadingAnchor.constraint(equalTo: filterScrollView.leadingAnchor),
            filterStackView.trailingAnchor.constraint(equalTo: filterScrollView.trailingAnchor),
            filterStackView.heightAnchor.constraint(equalTo: filterScrollView.heightAnchor, constant: -12),
        ])

        view.addSubview(filterScrollView)
        NSLayoutConstraint.activate([
            filterScrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            filterScrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            filterScrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            filterScrollView.heightAnchor.constraint(equalToConstant: 44),
        ])

        for type in FilterType.allCases {
            let chip = makeFilterChip(for: type)
            filterButtons[type] = chip
            filterStackView.addArrangedSubview(chip)
        }
    }

    private func makeFilterChip(for type: FilterType) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(type.label, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
        button.layer.cornerRadius = 16
        button.layer.masksToBounds = true
        button.contentEdgeInsets = UIEdgeInsets(top: 6, left: 14, bottom: 6, right: 14)
        applyChipStyle(button, active: false)
        button.addTarget(self, action: #selector(filterChipTapped(_:)), for: .touchUpInside)
        button.tag = FilterType.allCases.firstIndex(of: type) ?? 0
        return button
    }

    private func applyChipStyle(_ button: UIButton, active: Bool) {
        if active {
            button.backgroundColor = .systemIndigo
            button.setTitleColor(.white, for: .normal)
            button.layer.borderWidth = 0
        } else {
            button.backgroundColor = .secondarySystemBackground
            button.setTitleColor(.label, for: .normal)
            button.layer.borderWidth = 1
            button.layer.borderColor = UIColor.separator.cgColor
        }
    }

    @objc private func filterChipTapped(_ sender: UIButton) {
        let type = FilterType.allCases[sender.tag]
        showFilterPicker(for: type, sourceButton: sender)
    }

    private func showFilterPicker(for type: FilterType, sourceButton: UIButton) {
        let alert = UIAlertController(title: type.label, message: nil, preferredStyle: .actionSheet)

        // "Any" / clear option
        alert.addAction(UIAlertAction(title: "Any \(type.label)", style: .default) { [weak self] _ in
            guard let self = self else { return }
            switch type {
            case .genre:  self.selectedGenre  = nil
            case .format: self.selectedFormat = nil
            case .status: self.selectedStatus = nil
            case .sort:   self.selectedSort   = "TRENDING_DESC"
            }
            sourceButton.setTitle(type.label, for: .normal)
            self.applyChipStyle(sourceButton, active: false)
            self.fetchResults(reset: true)
        })

        let currentAPIValue: String? = {
            switch type {
            case .genre:  return selectedGenre
            case .format: return selectedFormat
            case .status: return selectedStatus
            case .sort:   return selectedSort == "TRENDING_DESC" ? nil : selectedSort
            }
        }()

        for option in type.options {
            let isSelected = option.apiValue == currentAPIValue
            let title = isSelected ? "✓ \(option.displayName)" : option.displayName
            alert.addAction(UIAlertAction(title: title, style: .default) { [weak self] _ in
                guard let self = self else { return }
                switch type {
                case .genre:  self.selectedGenre  = option.apiValue
                case .format: self.selectedFormat = option.apiValue
                case .status: self.selectedStatus = option.apiValue
                case .sort:   self.selectedSort   = option.apiValue
                }
                let chipTitle = "\(type.label): \(option.displayName)"
                sourceButton.setTitle(chipTitle, for: .normal)
                self.applyChipStyle(sourceButton, active: true)
                self.fetchResults(reset: true)
            })
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))

        if let popover = alert.popoverPresentationController {
            popover.sourceView = sourceButton
            popover.sourceRect = sourceButton.bounds
        }
        present(alert, animated: true)
    }

    private func setupCollectionView() {
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeLayout())
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .systemBackground
        collectionView.delegate = self
        collectionView.dataSource = self
        collectionView.register(AnimeCollectionViewCell.self,
                                forCellWithReuseIdentifier: AnimeCollectionViewCell.reuseID)
        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: filterScrollView.bottomAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func makeLayout() -> UICollectionViewLayout {
        let item = NSCollectionLayoutItem(
            layoutSize: .init(widthDimension: .fractionalWidth(1/3),
                              heightDimension: .fractionalHeight(1)))
        item.contentInsets = .init(top: 4, leading: 4, bottom: 4, trailing: 4)

        let group = NSCollectionLayoutGroup.horizontal(
            layoutSize: .init(widthDimension: .fractionalWidth(1),
                              heightDimension: .fractionalWidth(1.0/3.0 * 1.65)),
            subitems: [item])

        let section = NSCollectionLayoutSection(group: group)
        section.contentInsets = .init(top: 8, leading: 8, bottom: 8, trailing: 8)
        return UICollectionViewCompositionalLayout(section: section)
    }

    private func setupOverlays() {
        loadingIndicator = UIActivityIndicatorView(style: .large)
        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
        loadingIndicator.hidesWhenStopped = true
        view.addSubview(loadingIndicator)

        emptyLabel = UILabel()
        emptyLabel.textColor = .secondaryLabel
        emptyLabel.font = .systemFont(ofSize: 16)
        emptyLabel.textAlignment = .center
        emptyLabel.numberOfLines = 0
        emptyLabel.isHidden = true
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            loadingIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: 44),
            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: 44),
            emptyLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 32),
            emptyLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -32),
        ])
    }

    // MARK: - Fetch

    private func fetchResults(reset: Bool) {
        if reset {
            currentPage = 1
            hasNextPage = true
        }
        guard !isFetching, hasNextPage else { return }
        isFetching = true
        if reset { loadingIndicator.startAnimating() }

        AnimeService.sharedAnimeService.searchAnimeItems(
            title: currentTitle.isEmpty ? nil : currentTitle,
            genre: selectedGenre,
            format: selectedFormat,
            status: selectedStatus,
            sort: selectedSort,
            page: currentPage
        ) { [weak self] items, hasNext in
            guard let self = self else { return }
            if reset {
                self.animeResults = items
            } else {
                self.animeResults.append(contentsOf: items)
            }
            self.hasNextPage = hasNext
            self.currentPage += 1
            self.isFetching = false
            self.loadingIndicator.stopAnimating()
            self.collectionView.reloadData()
            self.emptyLabel.isHidden = !self.animeResults.isEmpty
            if self.animeResults.isEmpty {
                self.emptyLabel.text = self.currentTitle.isEmpty
                    ? "No results found"
                    : "No results for \"\(self.currentTitle)\""
            }
        }
    }
}

// MARK: - UICollectionViewDataSource

extension SearchViewController: UICollectionViewDataSource {
    func collectionView(_ collectionView: UICollectionView,
                        numberOfItemsInSection section: Int) -> Int {
        return animeResults.count
    }

    func collectionView(_ collectionView: UICollectionView,
                        cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: AnimeCollectionViewCell.reuseID,
            for: indexPath) as? AnimeCollectionViewCell else {
            return UICollectionViewCell()
        }
        cell.configure(with: animeResults[indexPath.item])
        return cell
    }
}

// MARK: - UICollectionViewDelegate

extension SearchViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView,
                        didSelectItemAt indexPath: IndexPath) {
        let item = animeResults[indexPath.item]
        guard let vc = storyboard?.instantiateViewController(withIdentifier: "AnimeDetailVC")
                as? AnimeDetailViewController else { return }
        vc.animeItem = item
        navigationController?.pushViewController(vc, animated: true)
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let offsetY       = scrollView.contentOffset.y
        let contentHeight = scrollView.contentSize.height
        let frameHeight   = scrollView.frame.height
        guard contentHeight > frameHeight else { return }
        if offsetY > contentHeight - frameHeight - 300 {
            fetchResults(reset: false)
        }
    }
}

// MARK: - UISearchResultsUpdating

extension SearchViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        let query = (searchController.searchBar.text ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        searchDebounceTimer?.invalidate()
        searchDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            guard let self = self, query != self.currentTitle else { return }
            self.currentTitle = query
            self.fetchResults(reset: true)
        }
    }
}
