//
//  DownloadsViewController.swift
//  TheAnimeTool
//

import UIKit
import CoreData
import LibTorrent

// MARK: - DownloadCell

final class DownloadCell: UITableViewCell {
    static let reuseID = "DownloadCell"

    private let nameLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 14, weight: .medium)
        l.textColor = .label
        l.numberOfLines = 2
        return l
    }()

    private let stateLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 12)
        l.textColor = .secondaryLabel
        return l
    }()

    private let percentLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 12, weight: .semibold)
        l.textColor = .systemIndigo
        l.textAlignment = .right
        l.setContentHuggingPriority(.required, for: .horizontal)
        return l
    }()

    private let progressView: UIProgressView = {
        let p = UIProgressView(progressViewStyle: .bar)
        p.progressTintColor = .systemIndigo
        p.trackTintColor = .systemGray5
        p.layer.cornerRadius = 2
        p.clipsToBounds = true
        return p
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
        [nameLabel, stateLabel, percentLabel, progressView].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview($0)
        }
        NSLayoutConstraint.activate([
            nameLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            nameLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            nameLabel.trailingAnchor.constraint(equalTo: percentLabel.leadingAnchor, constant: -8),

            percentLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            percentLabel.centerYAnchor.constraint(equalTo: nameLabel.centerYAnchor),

            stateLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 4),
            stateLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            stateLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),

            progressView.topAnchor.constraint(equalTo: stateLabel.bottomAnchor, constant: 6),
            progressView.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            progressView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            progressView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),
            progressView.heightAnchor.constraint(equalToConstant: 4),
        ])
    }

    func configure(name: String, stateText: String, progress: Float) {
        nameLabel.text = name.isEmpty ? "Unknown torrent" : name
        stateLabel.text = stateText
        progressView.progress = progress
        if progress >= 1.0 {
            percentLabel.text = "Complete"
            percentLabel.textColor = .systemGreen
            progressView.progressTintColor = .systemGreen
        } else {
            percentLabel.text = String(format: "%.0f%%", progress * 100)
            percentLabel.textColor = .systemIndigo
            progressView.progressTintColor = .systemIndigo
        }
    }
}

// MARK: - DownloadsViewController

/// Shows all torrents currently tracked in the LibTorrent session (TorrentService.handles).
/// Updates every second with live download progress from handle.snapshot.
/// Tapping a row pushes VideoListViewController for that torrent.
class DownloadsViewController: UIViewController {

    // MARK: - Properties

    private var tableView: UITableView!
    private var emptyLabel: UILabel!
    private var updateTimer: Timer?

    /// Ordered snapshot of active handles for stable table rows.
    /// Sorted by torrent name for consistent ordering.
    private var activeHandles: [(hex: String, handle: TorrentHandle)] = []

    // MARK: - Lifecycle

    /// Set tabBarItem here (before viewDidLoad) so the tab bar shows icons/titles at launch.
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        tabBarItem = UITabBarItem(title: "Downloads",
                                  image: UIImage(systemName: "arrow.down.circle"),
                                  selectedImage: UIImage(systemName: "arrow.down.circle.fill"))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupNavigationBar()
        setupTableView()
        setupEmptyLabel()
        setupNotifications()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refreshHandles()
        startTimer()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        updateTimer?.invalidate()
        updateTimer = nil
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        updateTimer?.invalidate()
    }

    // MARK: - Setup

    private func setupNavigationBar() {
        title = "Downloads"
        navigationController?.navigationBar.prefersLargeTitles = true
        navigationItem.largeTitleDisplayMode = .always
    }

    private func setupTableView() {
        view.backgroundColor = .systemGroupedBackground
        tableView = UITableView(frame: .zero, style: .insetGrouped)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(DownloadCell.self, forCellReuseIdentifier: DownloadCell.reuseID)
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 90
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func setupEmptyLabel() {
        emptyLabel = UILabel()
        emptyLabel.text = "No active downloads"
        emptyLabel.textColor = .secondaryLabel
        emptyLabel.font = .systemFont(ofSize: 17)
        emptyLabel.textAlignment = .center
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(emptyLabel)
        NSLayoutConstraint.activate([
            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    private func setupNotifications() {
        NotificationCenter.default.addObserver(self,
            selector: #selector(handleTorrentUpdate),
            name: NSNotification.Name(TorrentService.TorrentInControllerDidUpdateNotification), object: nil)
    }

    // MARK: - Data refresh

    private func refreshHandles() {
        activeHandles = TorrentService.sharedTorrentService.handles
            .map { (hex: $0.key, handle: $0.value) }
            .sorted { ($0.handle.snapshot.name) < ($1.handle.snapshot.name) }
        tableView.reloadData()
        emptyLabel.isHidden = !activeHandles.isEmpty
    }

    private func startTimer() {
        updateTimer?.invalidate()
        updateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.refreshHandles()
        }
    }

    @objc private func handleTorrentUpdate() {
        refreshHandles()
    }

    // MARK: - Helpers

    private func stateText(for snapshot: TorrentHandle.Snapshot) -> String {
        let peers = snapshot.numberOfPeers
        switch snapshot.state {
        case .downloadingMetadata:
            return peers > 0 ? "Fetching metadata… (\(peers) peer\(peers == 1 ? "" : "s"))" : "Connecting to peers…"
        case .downloading:
            return peers > 0 ? "Downloading • \(peers) peer\(peers == 1 ? "" : "s")" : "Downloading"
        case .finished, .seeding:
            return "Complete — Seeding"
        case .checkingFiles, .checkingResumeData:
            return "Checking files…"
        default:
            return "Connecting…"
        }
    }

    // MARK: - Navigation

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        super.prepare(for: segue, sender: sender)
        guard segue.identifier == "showVideoList",
              let indexPath = sender as? IndexPath,
              indexPath.row < activeHandles.count,
              let destination = segue.destination as? VideoListViewController else { return }
        let hex = activeHandles[indexPath.row].hex
        // Look up the CoreData entity for this torrent hash.
        destination.torrentEntity = TorrentService.sharedTorrentService
            .GetTorrentEntitiesFromHash(hex).first
    }
}

// MARK: - UITableViewDataSource

extension DownloadsViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return activeHandles.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(
            withIdentifier: DownloadCell.reuseID, for: indexPath) as! DownloadCell
        let entry = activeHandles[indexPath.row]
        let snap = entry.handle.snapshot
        cell.configure(name: snap.name,
                       stateText: stateText(for: snap),
                       progress: snap.progress)
        return cell
    }
}

// MARK: - UITableViewDelegate

extension DownloadsViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard indexPath.row < activeHandles.count else { return }
        let hex = activeHandles[indexPath.row].hex
        let entity = TorrentService.sharedTorrentService.GetTorrentEntitiesFromHash(hex).first
        guard let entity = entity else {
            let alert = UIAlertController(
                title: "Torrent Not Found",
                message: "This torrent's file list was cleared. Go to Search and re-add it.",
                preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
            return
        }
        guard let vc = storyboard?.instantiateViewController(withIdentifier: "VideoListVC")
                as? VideoListViewController else { return }
        vc.torrentEntity = entity
        navigationController?.pushViewController(vc, animated: true)
    }

    func tableView(_ tableView: UITableView,
                   trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath)
        -> UISwipeActionsConfiguration? {
        guard indexPath.row < activeHandles.count else { return nil }
        let entry = activeHandles[indexPath.row]
        let handle = entry.handle
        let snap = handle.snapshot

        // Pause/Resume: infer paused when not actively downloading/seeding/metadata
        let isActiveState = (snap.state == .downloading ||
                             snap.state == .downloadingMetadata ||
                             snap.state == .seeding ||
                             snap.state == .finished)
        let pauseTitle = isActiveState ? "Pause" : "Resume"
        let pauseAction = UIContextualAction(style: .normal, title: pauseTitle) { _, _, done in
            if isActiveState { handle.pause() } else { handle.resume() }
            done(true)
        }
        pauseAction.backgroundColor = .systemOrange
        pauseAction.image = UIImage(systemName: isActiveState ? "pause.fill" : "play.fill")

        // Delete
        let deleteAction = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, done in
            guard let self = self else { done(false); return }
            let sheet = UIAlertController(title: "Delete Download",
                                          message: "Do you also want to delete the downloaded files?",
                                          preferredStyle: .actionSheet)
            sheet.addAction(UIAlertAction(title: "Keep Files", style: .default) { _ in
                TorrentService.sharedTorrentService.session.removeTorrent(handle, deleteData: false)
                done(true)
            })
            sheet.addAction(UIAlertAction(title: "Delete Files", style: .destructive) { _ in
                TorrentService.sharedTorrentService.session.removeTorrent(handle, deleteData: true)
                done(true)
            })
            sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in done(false) })
            self.present(sheet, animated: true)
        }
        deleteAction.image = UIImage(systemName: "trash.fill")

        return UISwipeActionsConfiguration(actions: [deleteAction, pauseAction])
    }
}
