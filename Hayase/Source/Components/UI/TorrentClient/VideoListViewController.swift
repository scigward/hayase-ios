//
//  VideoListViewController.swift
//  Hayase
//

import UIKit
import CoreData

// MARK: - VideoTableViewCell

final class VideoTableViewCell: UITableViewCell {
    static let reuseID = "VideoCell"

    private let iconView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFit
        iv.tintColor = .systemIndigo
        return iv
    }()

    private let nameLabel: UILabel = {
        let l = UILabel()
        l.font = .nunito(ofSize: 15, weight: .medium)
        l.textColor = .label
        l.numberOfLines = 2
        return l
    }()

    private let sizeLabel: UILabel = {
        let l = UILabel()
        l.font = .nunito(ofSize: 12)
        l.textColor = .secondaryLabel
        return l
    }()

    private let statusLabel: UILabel = {
        let l = UILabel()
        l.font = .nunito(ofSize: 12, weight: .semibold)
        l.textAlignment = .right
        l.setContentHuggingPriority(.required, for: .horizontal)
        return l
    }()

    private let progressView: UIProgressView = {
        let p = UIProgressView(progressViewStyle: .bar)
        p.progressTintColor = .white
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
        [iconView, nameLabel, sizeLabel, statusLabel, progressView].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview($0)
        }
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            iconView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            iconView.widthAnchor.constraint(equalToConstant: 28),
            iconView.heightAnchor.constraint(equalToConstant: 28),

            nameLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            nameLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
            nameLabel.trailingAnchor.constraint(equalTo: statusLabel.leadingAnchor, constant: -8),

            statusLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            statusLabel.centerYAnchor.constraint(equalTo: nameLabel.centerYAnchor),

            sizeLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 4),
            sizeLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),

            progressView.topAnchor.constraint(equalTo: sizeLabel.bottomAnchor, constant: 6),
            progressView.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            progressView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            progressView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),
            progressView.heightAnchor.constraint(equalToConstant: 4),
        ])
    }

    func configure(with video: Videos, downloadedBytes: UInt64, totalBytes: UInt64, isDoNotDownload: Bool) {
        nameLabel.text = video.videoName ?? "Unknown"

        // Show "downloaded / total" matching Hayase files/table.svelte size column.
        if totalBytes > 0 {
            let dl = TorrentDetailViewController.fastPrettyBytes(downloadedBytes)
            let tot = TorrentDetailViewController.fastPrettyBytes(totalBytes)
            sizeLabel.text = downloadedBytes >= totalBytes ? tot : "\(dl) / \(tot)"
        } else {
            let mb = video.videoSize?.floatValue ?? 0
            sizeLabel.text = mb >= 1024 ? String(format: "%.1f GB", mb / 1024) : String(format: "%.0f MB", mb)
        }

        let progress: Float = totalBytes > 0 ? Float(Double(downloadedBytes) / Double(totalBytes)) : 0

        if isDoNotDownload {
            progressView.isHidden = true
            statusLabel.text = "Skipped"
            statusLabel.textColor = .secondaryLabel
            iconView.image = UIImage.hayaseIcon("circle-minus")
            iconView.tintColor = .secondaryLabel
        } else if downloadedBytes >= totalBytes && totalBytes > 0 {
            progressView.isHidden = true
            statusLabel.text = "Play"
            statusLabel.textColor = .systemGreen
            iconView.image = UIImage.hayaseIcon("circle-play")
            iconView.tintColor = .systemGreen
        } else {
            progressView.isHidden = false
            progressView.progress = progress
            statusLabel.text = String(format: "%.0f%%", progress * 100)
            statusLabel.textColor = .systemOrange
            iconView.image = UIImage.hayaseIcon("download")
            iconView.tintColor = .systemOrange
        }
    }
}

// MARK: - VideoListViewController

class VideoListViewController: UIViewController {

    // MARK: - Properties

    var torrentEntity: Torrents?
    /// The episode number the user searched for. When set, the resolver
    /// automatically picks the matching file from a batch torrent so only
    /// that episode is downloaded.
    var targetEpisode: Int?

    private var videoResultsController: NSFetchedResultsController<Videos>?
    private var videoService: VideoService?
    private var tableView: UITableView!
    private var loadingIndicator: UIActivityIndicatorView!
    private var emptyLabel: UILabel!
    private var stopUpdating = false
    private var updateTimer: Timer?
    private var pendingAutoOpenIndexPath: IndexPath?
    private var didAutoResolve = false
    private var batchFiles: [TorrentBatchResolver.ResolvedFile] = []

    deinit {
        NotificationCenter.default.removeObserver(self)
        updateTimer?.invalidate()
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupNavigationBar()
        setupTableView()
        setupLoadingIndicator()
        setupFetchedResultsController()
        setupNotifications()

        if let entity = torrentEntity {
            videoService = VideoService(torrentEntity: entity)
            loadingIndicator.startAnimating()
            emptyLabel.text = "Connecting to peers…"
            emptyLabel.isHidden = false
            videoService?.UpdateLocalVideo()
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        stopUpdating = false
        startPeriodicRefresh()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopUpdating = true
        updateTimer?.invalidate()
        updateTimer = nil
        // Do NOT call ClearCurrentTorrentEntityAndVideos() here.
        // The download continues in the background while the user navigates away,
        // so killing the torrent session entry would break in-progress downloads.
    }

    // MARK: - Setup

    private func setupNavigationBar() {
        title = torrentEntity?.torrentName ?? "Videos"
        navigationItem.largeTitleDisplayMode = .never
    }

    private func setupTableView() {
        view.backgroundColor = .systemBackground
        tableView = UITableView(frame: .zero, style: .insetGrouped)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(VideoTableViewCell.self, forCellReuseIdentifier: VideoTableViewCell.reuseID)
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

    private func setupLoadingIndicator() {
        loadingIndicator = UIActivityIndicatorView(style: .large)
        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
        loadingIndicator.hidesWhenStopped = true
        view.addSubview(loadingIndicator)

        emptyLabel = UILabel()
        emptyLabel.text = "Fetching metadata from peers…"
        emptyLabel.textColor = .secondaryLabel
        emptyLabel.font = .nunito(ofSize: 15)
        emptyLabel.textAlignment = .center
        emptyLabel.numberOfLines = 0
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.isHidden = true
        view.addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            loadingIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -24),
            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.topAnchor.constraint(equalTo: loadingIndicator.bottomAnchor, constant: 16),
            emptyLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 32),
            emptyLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -32),
        ])
    }

    private func setupFetchedResultsController() {
        let context = CoreDataService.sharedCoreDataService.mainQueueContext
        let req = NSFetchRequest<Videos>(entityName: Videos.entityName)
        req.sortDescriptors = [NSSortDescriptor(key: "videoIndex", ascending: true),
                               NSSortDescriptor(key: "videoName", ascending: true)]
        // Only show videos belonging to this specific torrent entity so stale
        // rows from other torrents (or previous sessions) never appear.
        if let entity = torrentEntity {
            req.predicate = NSPredicate(format: "torrents == %@", entity)
        }
        videoResultsController = NSFetchedResultsController(fetchRequest: req,
                                                            managedObjectContext: context,
                                                            sectionNameKeyPath: nil,
                                                            cacheName: nil)
        performFetch()
    }

    private func setupNotifications() {
        NotificationCenter.default.addObserver(self,
            selector: #selector(handleVideosDidUpdate),
            name: NSNotification.Name(VideoService.LocalVideosDidUpdateNotification), object: nil)
    }

    private func performFetch() {
        try? videoResultsController?.performFetch()
    }

    private func video(at indexPath: IndexPath) -> Videos? {
        guard indexPath.section >= 0,
              let sections = videoResultsController?.sections,
              indexPath.section < sections.count,
              indexPath.row >= 0,
              indexPath.row < sections[indexPath.section].numberOfObjects else { return nil }
        return videoResultsController?.object(at: indexPath)
    }

    private func fileIndex<T: BinaryInteger>(from value: T?) -> UInt? {
        guard let value else { return nil }
        return UInt(exactly: value)
    }

    private func fileIndex<T: BinaryInteger>(from value: T) -> UInt? {
        fileIndex(from: Optional(value))
    }

    private func startPeriodicRefresh() {
        updateTimer?.invalidate()
        updateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self, !self.stopUpdating else { return }
            self.tableView.reloadData()
            let count = self.videoResultsController?.sections?.first?.objects?.count ?? 0
            // While the spinner is animating (loading phase), show live torrent state.
            if self.loadingIndicator.isAnimating {
                if let handle = self.videoService?.torrentHandle,
                   let snap = TorrentService.sharedTorrentService.withActiveHandle(handle, default: nil, { activeHandle in
                       activeHandle.snapshot
                   }) {
                    let peers = snap.numberOfPeers
                    switch snap.state {
                    case .downloadingMetadata:
                        self.emptyLabel.text = peers > 0
                            ? "Fetching metadata… (\(peers) peer\(peers == 1 ? "" : "s") connected)"
                            : "Connecting to DHT and trackers…"
                    case .downloading, .finished, .seeding:
                        // Metadata arrived; CoreData will be populated by VideoService soon.
                        self.emptyLabel.text = "Preparing file list…"
                    default:
                        self.emptyLabel.text = "Connecting to peers…"
                    }
                    self.emptyLabel.isHidden = false
                }
            } else if count == 0 {
                self.emptyLabel.text = "No video files found"
                self.emptyLabel.isHidden = false
            }
        }
    }

    @objc private func handleVideosDidUpdate() {
        loadingIndicator.stopAnimating()

        // Show error alert if the torrent download or session-add failed.
        if let error = videoService?.lastError {
            videoService?.lastError = nil
            showErrorAlert(error)
            emptyLabel.text = "Failed to load torrent"
            emptyLabel.isHidden = false
            return
        }

        performFetch()
        tableView.reloadData()
        let count = videoResultsController?.sections?.first?.objects?.count ?? 0
        emptyLabel.text = count == 0 ? "No video files found" : ""
        emptyLabel.isHidden = count > 0

        // Auto-resolve: when files arrive for the first time and we have a target
        // episode, use TorrentBatchResolver to pick the correct file and start
        // streaming it immediately (skip the manual file-selection step).
        if !didAutoResolve, count > 1, let ep = targetEpisode {
            if let vs = videoService,
               let handle = vs.torrentHandle,
               let snap = TorrentService.sharedTorrentService.withActiveHandle(handle, default: nil, { activeHandle in
                   activeHandle.snapshot
               }),
               snap.hasMetadata {
                didAutoResolve = true
                let resolver = TorrentBatchResolver()
                let files = snap.files
                if let targetMedia = resolverTargetMedia() {
                    resolver.resolve(files: files, targetEpisode: ep, targetMedia: targetMedia) { [weak self] result in
                        guard let self, let match = result.target else { return }
                        self.selectAndOpenResolvedMatch(match, videoService: vs, batchFiles: result.resolvedFiles)
                    }
                } else {
                    let result = resolver.resolveByFilename(files: files, targetEpisode: ep)
                    if let match = result.target {
                        selectAndOpenResolvedMatch(match, videoService: vs, batchFiles: result.resolvedFiles)
                    }
                }
            }
        }

        if let pending = pendingAutoOpenIndexPath,
           let video = video(at: pending),
           let vs = videoService,
           let indexNum = video.videoIndex,
           let index = fileIndex(from: indexNum.intValue),
           vs.downloadedBytesForFileIndex(index) > 0 {
            pendingAutoOpenIndexPath = nil
            presentPlayer(at: pending)
        }
    }

    private func selectAndOpenResolvedMatch(_ match: TorrentBatchResolver.ResolvedFile,
                                            videoService vs: VideoService,
                                            batchFiles: [TorrentBatchResolver.ResolvedFile]) {
        guard let fileIdx = fileIndex(from: match.entry.index) else { return }
        self.batchFiles = batchFiles
        vs.selectFileForStreaming(fileIdx)
        tableView.reloadData()

        // Find the matching IndexPath so we can auto-open the player.
        if let allVids = videoResultsController?.fetchedObjects {
            for (row, vid) in allVids.enumerated() {
                if let vidIdx = vid.videoIndex?.intValue, vidIdx == Int(match.entry.index) {
                    let ip = IndexPath(row: row, section: 0)
                    if vs.downloadedBytesForFileIndex(fileIdx) > 0 {
                        presentPlayer(at: ip)
                    } else {
                        pendingAutoOpenIndexPath = ip
                    }
                    break
                }
            }
        }
    }

    private func resolverTargetMedia() -> AnimeItem? {
        guard let anime = torrentEntity?.animes,
              let id = anime.animeAnilistId?.intValue,
              id > 0 else { return nil }
        return AniListUtil.animeItem(from: anime)
    }

    private func showErrorAlert(_ error: Error) {
        let alert = UIAlertController(
            title: "Failed to Load Torrent",
            message: error.localizedDescription,
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Retry", style: .default) { [weak self] _ in
            guard let self = self, let vs = self.videoService else { return }
            self.emptyLabel.text = "Connecting to peers…"
            self.emptyLabel.isHidden = false
            self.loadingIndicator.startAnimating()
            vs.UpdateLocalVideo()
        })
        alert.addAction(UIAlertAction(title: "Dismiss", style: .cancel))
        present(alert, animated: true)
    }

    // MARK: - Navigation

    private func presentPlayer(at indexPath: IndexPath) {
        guard let video = video(at: indexPath),
              let vs = videoService,
              let indexNum = video.videoIndex else { return }
        guard let fileIdx = fileIndex(from: indexNum.intValue) else { return }
        vs.UpdateFilePathForFileIndex(fileIdx)

        let allVids = (videoResultsController?.sections?.first?.objects as? [Videos]) ?? [video]
        // Close any existing mini-player before starting a new one.
        MiniPlayerManager.shared.close()
        let player = VideoPlayerViewController()
        player.videoEntity       = video
        player.torrentHandle     = vs.torrentHandle
        player.videoService      = vs
        let activeFile = batchFiles.first { UInt(exactly: $0.entry.index) == Optional(fileIdx) }
        let activeMedia = activeFile?.media

        player.fileIndex         = fileIdx
        player.anilistID         = activeMedia?.id ?? Int(vs.torrentEntity.animes?.animeAnilistId ?? 0)
        player.episodeNumber     = activeFile?.episodeReference.intValue ?? Int(indexNum.intValue) + 1
        player.totalEpisodes     = activeMedia.map { TorrentBatchResolver.episodeCount(for: $0) } ?? vs.torrentEntity.animes?.animeTotalEps?.intValue ?? 0
        player.allVideos         = allVids
        player.currentVideoIndex = allVids.firstIndex(of: video) ?? 0
        player.batchFiles        = batchFiles
        Router.shared.navigateToPlayer(player, hostTabIndex: tabBarController?.selectedIndex)
    }
}

// MARK: - UITableViewDataSource

extension VideoListViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return videoResultsController?.sections?.first?.objects?.count ?? 0
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(
            withIdentifier: VideoTableViewCell.reuseID, for: indexPath) as? VideoTableViewCell else { return UITableViewCell() }
        guard let video = video(at: indexPath),
              let vs = videoService,
              let indexNum = video.videoIndex else { return cell }
        guard let index = fileIndex(from: indexNum.intValue) else { return cell }
        let isDoNotDownload = vs.CheckIsDoNotDownloadForFileIndex(index) ?? true
        let downloaded = isDoNotDownload ? 0 : vs.downloadedBytesForFileIndex(index)
        let total = vs.totalBytesForFileIndex(index)
        cell.configure(with: video, downloadedBytes: downloaded, totalBytes: total, isDoNotDownload: isDoNotDownload)
        return cell
    }
}

// MARK: - UITableViewDelegate

extension VideoListViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        defer { tableView.deselectRow(at: indexPath, animated: true) }
        guard let video = video(at: indexPath),
              let vs = videoService,
              let indexNum = video.videoIndex else { return }
        guard let index = fileIndex(from: indexNum.intValue),
              vs.totalBytesForFileIndex(index) > 0 else { return }  // metadata not yet ready

        // Hayase: focus all download bandwidth on this one episode
        vs.selectFileForStreaming(index)
        tableView.reloadData()

        if vs.downloadedBytesForFileIndex(index) > 0 {
            pendingAutoOpenIndexPath = nil
            presentPlayer(at: indexPath)
        } else {
            // No bytes yet — queue for auto-open once libtorrent delivers the first pieces
            pendingAutoOpenIndexPath = indexPath
        }
    }

    func tableView(_ tableView: UITableView,
                   trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath)
        -> UISwipeActionsConfiguration? {
        guard let video = video(at: indexPath),
              let vs = videoService,
              let indexNum = video.videoIndex,
              let index = fileIndex(from: indexNum.intValue) else { return nil }
        let isSkipped = vs.CheckIsDoNotDownloadForFileIndex(index) ?? false

        let title = isSkipped ? "Prioritize" : "Skip"
        let color: UIColor = isSkipped ? .systemGreen : .systemGray
        let icon = isSkipped ? "download" : "ban"
        let action = UIContextualAction(style: .normal, title: title) { [weak self] _, _, done in
            if isSkipped {
                vs.selectFileForStreaming(index)  // Hayase: prioritize this, deprioritize others
                self?.tableView.reloadData()
            } else {
                vs.SetDoNotDownloadForFileIndex(index, flag: true)
                self?.tableView.reloadData()
            }
            done(true)
        }
        action.backgroundColor = color
        action.image = UIImage.hayaseIcon(icon)
        return UISwipeActionsConfiguration(actions: [action])
    }
}
