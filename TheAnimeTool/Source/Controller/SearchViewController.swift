//
//  SearchViewController.swift
//  TheAnimeTool
//

import UIKit
import CoreData

/// Direct nyaa.si torrent search tab.
/// Users type a query → results are fetched from the nyaa.si RSS feed via
/// TorrentService.UpdateTempTorrentsWith → displayed using TorrentTableViewCell →
/// tapping a result pushes VideoListViewController.
class SearchViewController: UIViewController {

    // MARK: - Properties

    private let defaultPredicate = NSPredicate(format: "torrentFlagTemp == YES")
    private var torrentResultsController: NSFetchedResultsController<Torrents>?
    private var tableView: UITableView!
    private var searchController: UISearchController!
    private var loadingIndicator: UIActivityIndicatorView!
    private var emptyLabel: UILabel!
    private var searchDebounceTimer: Timer?
    private var lastQuery = ""

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        tabBarItem.title = "Search"
        tabBarItem.image = UIImage(systemName: "magnifyingglass")
        setupNavigationBar()
        setupTableView()
        setupSearchController()
        setupOverlays()
        setupFetchedResultsController()
        setupNotifications()
        showEmptyState("Search for anime torrents on nyaa.si")
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        tableView.indexPathsForSelectedRows?.forEach {
            tableView.deselectRow(at: $0, animated: animated)
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Setup

    private func setupNavigationBar() {
        title = "Search"
        navigationController?.navigationBar.prefersLargeTitles = true
        navigationItem.largeTitleDisplayMode = .always
    }

    private func setupTableView() {
        tableView = UITableView(frame: .zero, style: .insetGrouped)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(TorrentTableViewCell.self, forCellReuseIdentifier: TorrentTableViewCell.reuseID)
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 80
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func setupSearchController() {
        searchController = UISearchController(searchResultsController: nil)
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = "Search anime torrents on nyaa.si…"
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
        emptyLabel.textColor = .secondaryLabel
        emptyLabel.font = .systemFont(ofSize: 17)
        emptyLabel.textAlignment = .center
        emptyLabel.numberOfLines = 0
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            loadingIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            emptyLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 32),
            emptyLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -32),
        ])
    }

    private func setupFetchedResultsController() {
        let context = CoreDataService.sharedCoreDataService.mainQueueContext
        let req = NSFetchRequest<Torrents>(entityName: Torrents.entityName)
        req.predicate = defaultPredicate
        req.sortDescriptors = [NSSortDescriptor(key: "torrentOrder", ascending: true)]
        torrentResultsController = NSFetchedResultsController(fetchRequest: req,
                                                              managedObjectContext: context,
                                                              sectionNameKeyPath: nil,
                                                              cacheName: nil)
        try? torrentResultsController?.performFetch()
    }

    private func setupNotifications() {
        NotificationCenter.default.addObserver(self,
            selector: #selector(handleDidUpdate),
            name: NSNotification.Name(TorrentService.LocalTorrentsDidUpdateNotification), object: nil)
    }

    private func showEmptyState(_ text: String) {
        emptyLabel.text = text
        emptyLabel.isHidden = false
    }

    // MARK: - Notifications

    @objc private func handleDidUpdate() {
        loadingIndicator.stopAnimating()
        try? torrentResultsController?.performFetch()
        tableView.reloadData()
        let count = torrentResultsController?.sections?.first?.objects?.count ?? 0
        if count == 0 {
            let msg = lastQuery.isEmpty
                ? "Search for anime torrents on nyaa.si"
                : "No results for \"\(lastQuery)\""
            showEmptyState(msg)
        } else {
            emptyLabel.isHidden = true
        }
    }

    // MARK: - Navigation

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        super.prepare(for: segue, sender: sender)
        guard segue.identifier == "showVideoList",
              let cell = sender as? TorrentTableViewCell,
              let indexPath = tableView.indexPath(for: cell),
              let destination = segue.destination as? VideoListViewController else { return }
        destination.torrentEntity = torrentResultsController?.object(at: indexPath)
    }
}

// MARK: - UITableViewDataSource

extension SearchViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return torrentResultsController?.sections?.first?.objects?.count ?? 0
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(
            withIdentifier: TorrentTableViewCell.reuseID, for: indexPath) as! TorrentTableViewCell
        if let torrent = torrentResultsController?.object(at: indexPath) {
            cell.configure(with: torrent)
        }
        return cell
    }
}

// MARK: - UITableViewDelegate

extension SearchViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard let cell = tableView.cellForRow(at: indexPath) as? TorrentTableViewCell else { return }
        performSegue(withIdentifier: "showVideoList", sender: cell)
    }
}

// MARK: - UISearchResultsUpdating

extension SearchViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        let query = (searchController.searchBar.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        searchDebounceTimer?.invalidate()
        searchDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: false) { [weak self] _ in
            guard let self = self, query != self.lastQuery else { return }
            self.lastQuery = query
            if query.isEmpty {
                // Clear results when search bar is emptied.
                TorrentService.sharedTorrentService.ClearTempTorrents()
                try? self.torrentResultsController?.performFetch()
                self.tableView.reloadData()
                self.showEmptyState("Search for anime torrents on nyaa.si")
            } else {
                self.loadingIndicator.startAnimating()
                self.emptyLabel.isHidden = true
                TorrentService.sharedTorrentService.UpdateTempTorrentsWith(query, sortBy: .Seeders)
            }
        }
    }
}
