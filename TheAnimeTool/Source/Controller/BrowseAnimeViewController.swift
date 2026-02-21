//
//  BrowseAnimeViewController.swift
//  TheAnimeTool
//

import UIKit
import CoreData

class BrowseAnimeViewController: UIViewController {

    // MARK: - Properties

    private var animeResultsController: NSFetchedResultsController<Animes>?
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
        loadAiring()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        collectionView.indexPathsForSelectedItems?.forEach {
            collectionView.deselectItem(at: $0, animated: animated)
        }
    }

    // MARK: - Setup

    private func setupNavigationBar() {
        title = "Anime"
        navigationController?.navigationBar.prefersLargeTitles = true
        navigationItem.largeTitleDisplayMode = .always
    }

    private func setupCollectionView() {
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeLayout())
        collectionView.backgroundColor = .systemGroupedBackground
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.delegate = self
        collectionView.dataSource = self
        collectionView.register(AnimeCollectionViewCell.self,
                                forCellWithReuseIdentifier: AnimeCollectionViewCell.reuseID)
        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func makeLayout() -> UICollectionViewLayout {
        let item = NSCollectionLayoutItem(
            layoutSize: .init(widthDimension: .fractionalWidth(0.5),
                              heightDimension: .fractionalHeight(1)))
        item.contentInsets = .init(top: 6, leading: 6, bottom: 6, trailing: 6)

        let group = NSCollectionLayoutGroup.horizontal(
            layoutSize: .init(widthDimension: .fractionalWidth(1),
                              heightDimension: .fractionalWidth(0.75)),
            subitems: [item])

        let section = NSCollectionLayoutSection(group: group)
        section.contentInsets = .init(top: 8, leading: 8, bottom: 8, trailing: 8)
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

    private func loadAiring() {
        loadingIndicator.startAnimating()
        emptyLabel.isHidden = true
        AnimeService.sharedAnimeService.UpdateTempWithAiringAnimes()
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

    // MARK: - Notifications

    @objc private func handleDidUpdate() {
        loadingIndicator.stopAnimating()
        reloadUI()
    }

    @objc private func handleUpdateFailed() {
        loadingIndicator.stopAnimating()
        reloadUI()
    }

    // MARK: - Navigation

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        super.prepare(for: segue, sender: sender)
        guard segue.identifier == "showTorrentList",
              let cell = sender as? AnimeCollectionViewCell,
              let indexPath = collectionView.indexPath(for: cell),
              let destination = segue.destination as? TorrentListViewController else { return }
        destination.animeEntity = animeResultsController?.object(at: indexPath)
    }
}

// MARK: - UICollectionViewDataSource

extension BrowseAnimeViewController: UICollectionViewDataSource {
    func collectionView(_ collectionView: UICollectionView,
                        numberOfItemsInSection section: Int) -> Int {
        return animeResultsController?.sections?.first?.objects?.count ?? 0
    }

    func collectionView(_ collectionView: UICollectionView,
                        cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: AnimeCollectionViewCell.reuseID, for: indexPath) as! AnimeCollectionViewCell
        if let anime = animeResultsController?.object(at: indexPath) {
            cell.configure(with: anime)
        }
        return cell
    }
}

// MARK: - UICollectionViewDelegate

extension BrowseAnimeViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView,
                        didSelectItemAt indexPath: IndexPath) {
        guard let cell = collectionView.cellForItem(at: indexPath) as? AnimeCollectionViewCell else { return }
        performSegue(withIdentifier: "showTorrentList", sender: cell)
    }
}

// MARK: - UISearchResultsUpdating

extension BrowseAnimeViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        let text = searchController.searchBar.text ?? ""
        searchDebounceTimer?.invalidate()
        searchDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            guard let self = self, text != self.lastSearchString else { return }
            self.lastSearchString = text
            self.loadingIndicator.startAnimating()
            self.emptyLabel.isHidden = true
            if text.isEmpty {
                AnimeService.sharedAnimeService.UpdateTempWithAiringAnimes()
            } else {
                AnimeService.sharedAnimeService.UpdateTempAnimesWithSearchString(text)
            }
        }
    }
}
