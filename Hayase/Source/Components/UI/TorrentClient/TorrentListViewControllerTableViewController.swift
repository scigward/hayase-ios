//
//  TorrentListViewControllerTableViewController.swift
//  Hayase
//

import UIKit
import CoreData

// MARK: - TorrentCountBadgeView

final class TorrentCountBadgeView: UIView {
    private let imageView = UIImageView()
    private let label = UILabel()

    init(icon: String, color: UIColor) {
        super.init(frame: .zero)
        setup(icon: icon, color: color)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup(icon: "users", color: .systemGray)
    }

    private func setup(icon: String, color: UIColor) {
        backgroundColor = color
        layer.cornerRadius = 8
        clipsToBounds = true

        imageView.image = UIImage.hayaseIcon(icon, withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold))
        imageView.tintColor = .white
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalToConstant: 12),
            imageView.heightAnchor.constraint(equalToConstant: 12),
        ])

        label.font = .nunito(ofSize: 11, weight: .semibold)
        label.textColor = .white
        label.textAlignment = .center
        label.setContentHuggingPriority(.required, for: .horizontal)

        let stack = UIStackView(arrangedSubviews: [imageView, label])
        stack.axis = .horizontal
        stack.spacing = 4
        stack.alignment = .center
        stack.layoutMargins = UIEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
        stack.isLayoutMarginsRelativeArrangement = true
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    func setCount(_ count: Int) {
        label.text = "\(count)"
    }
}

// MARK: - TorrentTableViewCell

final class TorrentTableViewCell: UITableViewCell {
    static let reuseID = "TorrentCell"

    private let nameLabel: UILabel = {
        let l = UILabel()
        l.font = .nunito(ofSize: 14, weight: .medium)
        l.textColor = .label
        l.numberOfLines = 2
        return l
    }()

    private let seedersBadge = TorrentCountBadgeView(icon: "user-round-plus", color: .systemGreen)
    private let leechersBadge = TorrentCountBadgeView(icon: "user-round-minus", color: .systemRed)

    private let sizeLabel: UILabel = {
        let l = UILabel()
        l.font = .nunito(ofSize: 12)
        l.textColor = .secondaryLabel
        return l
    }()

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
        [nameLabel, seedersBadge, leechersBadge, sizeLabel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview($0)
        }
        NSLayoutConstraint.activate([
            nameLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            nameLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            nameLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),

            seedersBadge.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 6),
            seedersBadge.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            seedersBadge.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),
            seedersBadge.widthAnchor.constraint(greaterThanOrEqualToConstant: 48),
            seedersBadge.heightAnchor.constraint(equalToConstant: 20),

            leechersBadge.leadingAnchor.constraint(equalTo: seedersBadge.trailingAnchor, constant: 6),
            leechersBadge.centerYAnchor.constraint(equalTo: seedersBadge.centerYAnchor),
            leechersBadge.widthAnchor.constraint(greaterThanOrEqualToConstant: 48),
            leechersBadge.heightAnchor.constraint(equalToConstant: 20),

            sizeLabel.leadingAnchor.constraint(equalTo: leechersBadge.trailingAnchor, constant: 10),
            sizeLabel.centerYAnchor.constraint(equalTo: seedersBadge.centerYAnchor),
        ])
    }

    func configure(with torrent: Torrents) {
        nameLabel.text = torrent.torrentName
        let s = torrent.torrentSeeders?.intValue ?? 0
        let l = torrent.torrentLeechers?.intValue ?? 0
        let mb = torrent.torrentSize?.floatValue ?? 0
        seedersBadge.setCount(s)
        leechersBadge.setCount(l)
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
            name: NSNotification.Name(TorrentService.TorrentInControllerDidUpdateNotification), object: nil)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    private func startSearch() {
        // Torrent list search is now handled by ExtensionSearchViewController.
        // This VC is kept for storyboard compatibility only; show empty state immediately.
        loadingIndicator.stopAnimating()
        emptyLabel.isHidden = false
        emptyLabel.text = "Use Extensions to search for torrents"
    }

    private func performFetch() {
        try? torrentResultsController?.performFetch()
    }

    private func torrent(at indexPath: IndexPath) -> Torrents? {
        guard indexPath.section >= 0,
              let sections = torrentResultsController?.sections,
              indexPath.section < sections.count,
              indexPath.row >= 0,
              indexPath.row < sections[indexPath.section].numberOfObjects else { return nil }
        return torrentResultsController?.object(at: indexPath)
    }

    private func configurePopover(_ alert: UIAlertController,
                                  from tableView: UITableView,
                                  at indexPath: IndexPath) {
        guard let popover = alert.popoverPresentationController else { return }
        if let cell = tableView.cellForRow(at: indexPath) {
            popover.sourceView = cell
            popover.sourceRect = cell.bounds
        } else {
            popover.sourceView = tableView
            popover.sourceRect = tableView.rectForRow(at: indexPath)
        }
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
        destination.torrentEntity = torrent(at: indexPath)
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
        if let torrent = torrent(at: indexPath) {
            cell.configure(with: torrent)
        }
        return cell
    }
}

// MARK: - UITableViewDelegate

extension TorrentListViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let torrent = torrent(at: indexPath) else { return }

        let name = torrent.torrentName ?? "Unknown torrent"
        let sizeMB = torrent.torrentSize?.floatValue ?? 0
        let sizeStr = sizeMB >= 1024
            ? String(format: "%.1f GB", sizeMB / 1024)
            : String(format: "%.0f MB", sizeMB)
        let seeders = torrent.torrentSeeders?.intValue ?? 0

        let alert = UIAlertController(
            title: "Download Torrent?",
            message: "\(name)\n\nSize: \(sizeStr)  ·  \(seeders) seeders",
            preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "Download", style: .default) { [weak self] _ in
            guard let self = self,
                  let cell = tableView.cellForRow(at: indexPath) as? TorrentTableViewCell else { return }
            self.performSegue(withIdentifier: "showVideoList", sender: cell)
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        configurePopover(alert, from: tableView, at: indexPath)
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
