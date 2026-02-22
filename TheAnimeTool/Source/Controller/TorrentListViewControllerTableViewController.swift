//
//  TorrentListViewControllerTableViewController.swift
//  TheAnimeTool
//

import UIKit
import CoreData

// MARK: - TorrentTableViewCell

final class TorrentTableViewCell: UITableViewCell {
    static let reuseID = "TorrentCell"

    private let nameLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 14, weight: .medium)
        l.textColor = .label
        l.numberOfLines = 2
        return l
    }()

    private let seedersLabel = TorrentTableViewCell.makeBadge(color: .systemGreen)
    private let leechersLabel = TorrentTableViewCell.makeBadge(color: .systemRed)

    private let sizeLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 12)
        l.textColor = .secondaryLabel
        return l
    }()

    private static func makeBadge(color: UIColor) -> UILabel {
        let l = UILabel()
        l.font = .systemFont(ofSize: 11, weight: .semibold)
        l.textColor = .white
        l.textAlignment = .center
        l.backgroundColor = color
        l.layer.cornerRadius = 8
        l.clipsToBounds = true
        return l
    }

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        accessoryType = .disclosureIndicator
        [nameLabel, seedersLabel, leechersLabel, sizeLabel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview($0)
        }
        NSLayoutConstraint.activate([
            nameLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            nameLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            nameLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),

            seedersLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 6),
            seedersLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            seedersLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),
            seedersLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 48),
            seedersLabel.heightAnchor.constraint(equalToConstant: 20),

            leechersLabel.leadingAnchor.constraint(equalTo: seedersLabel.trailingAnchor, constant: 6),
            leechersLabel.centerYAnchor.constraint(equalTo: seedersLabel.centerYAnchor),
            leechersLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 48),
            leechersLabel.heightAnchor.constraint(equalToConstant: 20),

            sizeLabel.leadingAnchor.constraint(equalTo: leechersLabel.trailingAnchor, constant: 10),
            sizeLabel.centerYAnchor.constraint(equalTo: seedersLabel.centerYAnchor),
        ])
    }

    func configure(with torrent: Torrents) {
        nameLabel.text = torrent.torrentName
        let s = torrent.torrentSeeders?.intValue ?? 0
        let l = torrent.torrentLeechers?.intValue ?? 0
        let mb = torrent.torrentSize?.floatValue ?? 0
        seedersLabel.text = "  ▲ \(s)  "
        leechersLabel.text = "  ▼ \(l)  "
        sizeLabel.text = mb >= 1024 ? String(format: "%.1f GB", mb / 1024) : String(format: "%.0f MB", mb)
    }
}

// MARK: - TorrentListViewController

class TorrentListViewController: UIViewController {

    // MARK: - Properties

    var animeEntity: Animes?
    var animeTitleOverride: String?

    private let defaultPredicate = NSPredicate(format: "torrentFlagTemp == YES")
    private let defaultSort = NSSortDescriptor(key: "torrentOrder", ascending: true)
    private var torrentResultsController: NSFetchedResultsController<Torrents>?
    private var tableView: UITableView!
    private var searchController: UISearchController!
    private var loadingIndicator: UIActivityIndicatorView!
    private var emptyLabel: UILabel!

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupNavigationBar()
        setupTableView()
        setupSearchController()
        setupOverlays()
        setupFetchedResultsController()
        setupNotifications()
        startSearch()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        tableView.indexPathsForSelectedRows?.forEach {
            tableView.deselectRow(at: $0, animated: animated)
        }
    }

    // MARK: - Setup

    private func setupNavigationBar() {
        title = animeTitleOverride ?? animeEntity?.animeTitleEnglish ?? animeEntity?.animeTitleJapanese ?? "Torrents"
        navigationItem.largeTitleDisplayMode = .never
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
        searchController.searchBar.placeholder = "Filter torrents…"
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = true
        definesPresentationContext = true
    }

    private func setupOverlays() {
        loadingIndicator = UIActivityIndicatorView(style: .large)
        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
        loadingIndicator.hidesWhenStopped = true
        view.addSubview(loadingIndicator)

        emptyLabel = UILabel()
        emptyLabel.text = "No torrents found"
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
        let req = NSFetchRequest<Torrents>(entityName: Torrents.entityName)
        req.predicate = defaultPredicate
        req.sortDescriptors = [defaultSort]
        torrentResultsController = NSFetchedResultsController(fetchRequest: req,
                                                              managedObjectContext: context,
                                                              sectionNameKeyPath: nil,
                                                              cacheName: nil)
        performFetch()
    }

    private func setupNotifications() {
        NotificationCenter.default.addObserver(self,
            selector: #selector(handleDidUpdate),
            name: NSNotification.Name(TorrentService.LocalTorrentsDidUpdateNotification), object: nil)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    private func startSearch() {
        loadingIndicator.startAnimating()
        emptyLabel.isHidden = true
        let name = animeTitleOverride ?? animeEntity?.animeTitleEnglish ?? animeEntity?.animeTitleJapanese ?? ""
        TorrentService.sharedTorrentService.UpdateTempTorrentsWith(
            TorrentService.UtilMakeShortSearchString(name), sortBy: .Seeders)
    }

    private func performFetch() {
        try? torrentResultsController?.performFetch()
    }

    private func reloadUI() {
        performFetch()
        tableView.reloadData()
        let count = torrentResultsController?.sections?.first?.objects?.count ?? 0
        emptyLabel.isHidden = count > 0
    }

    // MARK: - Notifications

    @objc private func handleDidUpdate() {
        loadingIndicator.stopAnimating()
        reloadUI()
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

extension TorrentListViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return torrentResultsController?.sections?.first?.objects?.count ?? 0
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(
            withIdentifier: TorrentTableViewCell.reuseID, for: indexPath) as? TorrentTableViewCell else {
            return UITableViewCell()
        }
        if let torrent = torrentResultsController?.object(at: indexPath) {
            cell.configure(with: torrent)
        }
        return cell
    }
}

// MARK: - UITableViewDelegate

extension TorrentListViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let torrent = torrentResultsController?.object(at: indexPath) else { return }

        let name = torrent.torrentName ?? "Unknown torrent"
        let sizeMB = torrent.torrentSize?.floatValue ?? 0
        let sizeStr = sizeMB >= 1024
            ? String(format: "%.1f GB", sizeMB / 1024)
            : String(format: "%.0f MB", sizeMB)
        let seeders = torrent.torrentSeeders?.intValue ?? 0

        let alert = UIAlertController(
            title: "Download Torrent?",
            message: "\(name)\n\nSize: \(sizeStr)  ·  ▲ \(seeders) seeders",
            preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "Download", style: .default) { [weak self] _ in
            guard let self = self,
                  let cell = tableView.cellForRow(at: indexPath) as? TorrentTableViewCell else { return }
            self.performSegue(withIdentifier: "showVideoList", sender: cell)
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }
}

// MARK: - UISearchResultsUpdating

extension TorrentListViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        let text = (searchController.searchBar.text ?? "").trimmingCharacters(in: .whitespaces)
        if text.isEmpty {
            torrentResultsController?.fetchRequest.predicate = defaultPredicate
        } else {
            let terms = text.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            let subs = terms.map {
                NSPredicate(format: "torrentName CONTAINS[cd] %@ AND torrentFlagTemp == YES", $0)
            }
            torrentResultsController?.fetchRequest.predicate =
                NSCompoundPredicate(andPredicateWithSubpredicates: subs)
        }
        performFetch()
        tableView.reloadData()
    }
}
