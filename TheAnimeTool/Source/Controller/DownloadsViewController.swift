//
//  DownloadsViewController.swift
//  TheAnimeTool
//

import UIKit
import CoreData
import LibTorrent

// MARK: - DownloadCell

/// Matches Hayase's overview.svelte: torrent name + status badge + progress bar +
/// 4-column stats grid (↓ speed / ↑ speed / ETA / Seeders·Leechers).
final class DownloadCell: UITableViewCell {
    static let reuseID = "DownloadCell"

    private let nameLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 14, weight: .semibold)
        l.textColor = .label
        l.numberOfLines = 2
        return l
    }()

    private let statusBadge: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 10, weight: .bold)
        l.textColor = .white
        l.textAlignment = .center
        l.layer.cornerRadius = 6
        l.clipsToBounds = true
        l.setContentHuggingPriority(.required, for: .horizontal)
        l.setContentCompressionResistancePriority(.required, for: .horizontal)
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

    // Stats row — matches overview.svelte "Speed & Transfer" + "Peers & Connections"
    private let downSpeedLabel  = DownloadCell.makeStatLabel(tint: .systemGreen)
    private let upSpeedLabel    = DownloadCell.makeStatLabel(tint: .systemBlue)
    private let etaLabel        = DownloadCell.makeStatLabel(tint: .systemOrange)
    private let peersLabel      = DownloadCell.makeStatLabel(tint: .systemPurple)

    private static func makeStatLabel(tint: UIColor) -> UILabel {
        let l = UILabel()
        l.font = .systemFont(ofSize: 11)
        l.textColor = tint
        l.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return l
    }

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setup()
    }
    required init?(coder: NSCoder) { super.init(coder: coder); setup() }

    private func setup() {
        accessoryType = .disclosureIndicator
        let statsStack = UIStackView(arrangedSubviews: [downSpeedLabel, upSpeedLabel, etaLabel, peersLabel])
        statsStack.axis = .horizontal
        statsStack.distribution = .fillEqually
        statsStack.spacing = 4

        [nameLabel, statusBadge, percentLabel, progressView, statsStack].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview($0)
        }
        NSLayoutConstraint.activate([
            nameLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            nameLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            nameLabel.trailingAnchor.constraint(equalTo: percentLabel.leadingAnchor, constant: -8),

            percentLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            percentLabel.centerYAnchor.constraint(equalTo: nameLabel.centerYAnchor),

            statusBadge.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 6),
            statusBadge.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            statusBadge.heightAnchor.constraint(equalToConstant: 18),

            progressView.topAnchor.constraint(equalTo: statusBadge.bottomAnchor, constant: 8),
            progressView.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            progressView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            progressView.heightAnchor.constraint(equalToConstant: 4),

            statsStack.topAnchor.constraint(equalTo: progressView.bottomAnchor, constant: 8),
            statsStack.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            statsStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            statsStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),
        ])
    }

    /// Format bytes/sec into a compact human-readable string: "3.2 MB/s", "512 KB/s", etc.
    private static func formatSpeed(_ bytesPerSec: UInt64) -> String {
        if bytesPerSec == 0 { return "0 B/s" }
        if bytesPerSec >= 1_073_741_824 { return String(format: "%.1f GB/s", Double(bytesPerSec) / 1_073_741_824) }
        if bytesPerSec >= 1_048_576    { return String(format: "%.1f MB/s", Double(bytesPerSec) / 1_048_576) }
        if bytesPerSec >= 1_024        { return String(format: "%.0f KB/s", Double(bytesPerSec) / 1_024) }
        return "\(bytesPerSec) B/s"
    }

    /// Format bytes into a compact size string: "3.2 GB", "512 MB", etc.
    static func formatSize(_ bytes: UInt64) -> String {
        if bytes == 0 { return "0 B" }
        if bytes >= 1_073_741_824 { return String(format: "%.1f GB", Double(bytes) / 1_073_741_824) }
        if bytes >= 1_048_576    { return String(format: "%.1f MB", Double(bytes) / 1_048_576) }
        if bytes >= 1_024        { return String(format: "%.0f KB", Double(bytes) / 1_024) }
        return "\(bytes) B"
    }

    /// ETA string — matches Hayase's `eta()` util: "2h 15m", "45s", "∞".
    private static func formatETA(remaining: UInt64, rate: UInt64) -> String {
        guard rate > 0, remaining > 0 else { return "∞" }
        let s = remaining / rate
        if s < 60    { return "\(s)s" }
        if s < 3600  { return "\(s/60)m \(s%60)s" }
        return "\(s/3600)h \(s%3600/60)m"
    }

    func configure(snap: TorrentHandle.Snapshot) {
        let name = snap.name
        nameLabel.text = name.isEmpty ? "Unknown torrent" : name

        let progress = Float(snap.progress)
        progressView.progress = progress

        let isComplete = snap.isFinished || snap.isSeed || progress >= 1.0
        if isComplete {
            percentLabel.text = "100%"
            percentLabel.textColor = .systemGreen
            progressView.progressTintColor = .systemGreen
            statusBadge.text = " Seeding "
            statusBadge.backgroundColor = .systemBlue
        } else if snap.isPaused {
            percentLabel.text = String(format: "%.0f%%", progress * 100)
            percentLabel.textColor = .secondaryLabel
            progressView.progressTintColor = .systemGray
            statusBadge.text = " Paused "
            statusBadge.backgroundColor = .systemGray
        } else {
            percentLabel.text = String(format: "%.0f%%", progress * 100)
            percentLabel.textColor = .systemIndigo
            progressView.progressTintColor = .systemIndigo
            statusBadge.text = " Downloading "
            statusBadge.backgroundColor = .systemGreen
        }

        // Stats grid
        downSpeedLabel.text = "↓ " + DownloadCell.formatSpeed(snap.downloadRate)
        upSpeedLabel.text   = "↑ " + DownloadCell.formatSpeed(snap.uploadRate)

        let remaining = snap.totalWanted > snap.totalWantedDone ? snap.totalWanted - snap.totalWantedDone : 0
        etaLabel.text = "⏱ " + DownloadCell.formatETA(remaining: remaining, rate: snap.downloadRate)

        let s = snap.numberOfSeeds
        let l = snap.numberOfLeechers
        peersLabel.text = "👥 \(s)S/\(l)L"
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
        let newHandles = TorrentService.sharedTorrentService.handles
            .map { (hex: $0.key, handle: $0.value) }
            .sorted { $0.handle.snapshot.name < $1.handle.snapshot.name }

        // Full reload only when rows are added or removed — reloadData() collapses any
        // open swipe actions, so we avoid it when only the cell content (speed/progress)
        // has changed and the row count is the same.
        if newHandles.count != activeHandles.count {
            activeHandles = newHandles
            tableView.reloadData()
        } else {
            activeHandles = newHandles
            for cell in tableView.visibleCells {
                guard let ip = tableView.indexPath(for: cell),
                      let dlCell = cell as? DownloadCell,
                      ip.row < activeHandles.count else { continue }
                dlCell.configure(snap: activeHandles[ip.row].handle.snapshot)
            }
        }
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
        cell.configure(snap: entry.handle.snapshot)
        return cell
    }
}

// MARK: - UITableViewDelegate

extension DownloadsViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard indexPath.row < activeHandles.count else { return }
        let entry = activeHandles[indexPath.row]
        let entity = TorrentService.sharedTorrentService.GetTorrentEntitiesFromHash(entry.hex).first

        let vc = TorrentDetailViewController()
        vc.handle = entry.handle
        vc.hexHash = entry.hex
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

        // Pause/Resume: infer paused when not actively downloading/seeding/fetching metadata.
        // .finished is excluded — a completed torrent cannot be paused.
        let isActiveState = (snap.state == .downloading ||
                             snap.state == .downloadingMetadata ||
                             snap.state == .seeding)
        let pauseTitle = isActiveState ? "Pause" : "Resume"
        let pauseAction = UIContextualAction(style: .normal, title: pauseTitle) { [weak self] _, _, done in
            let currentlyActive = { () -> Bool in
                let s = handle.snapshot.state
                return s == .downloading || s == .downloadingMetadata || s == .seeding
            }()
            if currentlyActive { handle.pause() } else { handle.resume() }
            // Refresh row immediately so icon/title reflects new state.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self?.tableView.reloadRows(at: [indexPath], with: .automatic)
            }
            done(true)
        }
        pauseAction.backgroundColor = .systemOrange
        pauseAction.image = UIImage(systemName: isActiveState ? "pause.fill" : "play.fill")

        // Delete
        let deleteAction = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, done in
            done(true)
            guard let self = self else { return }
            let sheet = UIAlertController(title: "Delete Download",
                                          message: "Do you also want to delete the downloaded files?",
                                          preferredStyle: .actionSheet)
            sheet.addAction(UIAlertAction(title: "Keep Files", style: .default) { [weak self] _ in
                TorrentService.sharedTorrentService.session.removeTorrent(handle, deleteFiles: false)
                self?.refreshHandles()
            })
            sheet.addAction(UIAlertAction(title: "Delete Files", style: .destructive) { [weak self] _ in
                TorrentService.sharedTorrentService.session.removeTorrent(handle, deleteFiles: true)
                self?.refreshHandles()
            })
            sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            self.present(sheet, animated: true)
        }
        deleteAction.image = UIImage(systemName: "trash.fill")

        return UISwipeActionsConfiguration(actions: [deleteAction, pauseAction])
    }
}
