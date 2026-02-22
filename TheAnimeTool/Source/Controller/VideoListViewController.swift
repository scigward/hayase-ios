//
//  VideoListViewController.swift
//  TheAnimeTool
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
        l.font = .systemFont(ofSize: 15, weight: .medium)
        l.textColor = .label
        l.numberOfLines = 2
        return l
    }()

    private let sizeLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 12)
        l.textColor = .secondaryLabel
        return l
    }()

    private let statusLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 12, weight: .semibold)
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

    func configure(with video: Videos, progress: Float?, isDoNotDownload: Bool) {
        nameLabel.text = video.videoName ?? "Unknown"
        let mb = video.videoSize?.floatValue ?? 0
        sizeLabel.text = mb >= 1024 ? String(format: "%.1f GB", mb / 1024) : String(format: "%.0f MB", mb)

        if isDoNotDownload {
            progressView.isHidden = true
            statusLabel.text = "Download"
            statusLabel.textColor = .systemIndigo
            iconView.image = UIImage(systemName: "arrow.down.circle")
            iconView.tintColor = .systemIndigo
        } else if let p = progress, p >= 1.0 {
            progressView.isHidden = true
            statusLabel.text = "Play"
            statusLabel.textColor = .systemGreen
            iconView.image = UIImage(systemName: "play.circle.fill")
            iconView.tintColor = .systemGreen
        } else {
            let p = progress ?? 0
            progressView.isHidden = false
            progressView.progress = p
            statusLabel.text = String(format: "%.0f%%", p * 100)
            statusLabel.textColor = .systemOrange
            iconView.image = UIImage(systemName: "arrow.down.circle.fill")
            iconView.tintColor = .systemOrange
        }
    }
}

// MARK: - VideoListViewController

class VideoListViewController: UIViewController {

    // MARK: - Properties

    var torrentEntity: Torrents?

    private var videoResultsController: NSFetchedResultsController<Videos>?
    private var videoService: VideoService?
    private var tableView: UITableView!
    private var loadingIndicator: UIActivityIndicatorView!
    private var emptyLabel: UILabel!
    private var stopUpdating = false
    private var updateTimer: Timer?

    private var loadingTimeout: DispatchWorkItem?

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
            emptyLabel.text = "Fetching metadata from peers…"
            emptyLabel.isHidden = false
            startLoadingTimeout()
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
        if isMovingFromParent {
            videoService?.ClearCurrentTorrentEntityAndVideos()
        }
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
        emptyLabel.font = .systemFont(ofSize: 15)
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
        req.sortDescriptors = [NSSortDescriptor(key: "videoName", ascending: true)]
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

    private func startPeriodicRefresh() {
        updateTimer?.invalidate()
        updateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self, !self.stopUpdating else { return }
            // Only reload cells to refresh live progress from handle.snapshot.
            self.tableView.reloadData()
            let count = self.videoResultsController?.sections?.first?.objects?.count ?? 0
            if !self.loadingIndicator.isAnimating && count == 0 {
                self.emptyLabel.text = "No video files found"
                self.emptyLabel.isHidden = false
            }
        }
    }

    @objc private func handleVideosDidUpdate() {
        loadingTimeout?.cancel()
        loadingTimeout = nil
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
    }

    private func showErrorAlert(_ error: Error) {
        let alert = UIAlertController(
            title: "Failed to Load Torrent",
            message: error.localizedDescription,
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Retry", style: .default) { [weak self] _ in
            guard let self = self, let vs = self.videoService else { return }
            self.emptyLabel.isHidden = true
            self.loadingIndicator.startAnimating()
            self.startLoadingTimeout()
            vs.UpdateLocalVideo()
        })
        alert.addAction(UIAlertAction(title: "Dismiss", style: .cancel))
        present(alert, animated: true)
    }

    private func startLoadingTimeout() {
        loadingTimeout?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.loadingIndicator.stopAnimating()
            self.emptyLabel.text = "Timed out fetching metadata"
            self.emptyLabel.isHidden = false
            let alert = UIAlertController(title: "Timed Out",
                message: "Could not fetch torrent metadata after 90 seconds. Check your internet connection or try a different torrent.",
                preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Retry", style: .default) { [weak self] _ in
                guard let self = self, let vs = self.videoService else { return }
                self.emptyLabel.text = "Fetching metadata from peers…"
                self.emptyLabel.isHidden = false
                self.loadingIndicator.startAnimating()
                self.startLoadingTimeout()
                vs.UpdateLocalVideo()
            })
            alert.addAction(UIAlertAction(title: "Dismiss", style: .cancel) { [weak self] _ in
                self?.emptyLabel.text = "Timed out"
                self?.emptyLabel.isHidden = false
            })
            self.present(alert, animated: true)
        }
        loadingTimeout = item
        // 90 seconds — magnets need DHT/peer negotiation to fetch metadata.
        DispatchQueue.main.asyncAfter(deadline: .now() + 90, execute: item)
    }

    // MARK: - Navigation

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        super.prepare(for: segue, sender: sender)
        guard segue.identifier == "showVideoPlayer",
              let cell = sender as? VideoTableViewCell,
              let indexPath = tableView.indexPath(for: cell),
              let video = videoResultsController?.object(at: indexPath),
              let indexNum = video.videoIndex else { return }
        videoService?.UpdateFilePathForFileIndex(UInt(indexNum.intValue))
        let destination = segue.destination as! VideoPlayerController
        destination.videoEntity = video
    }
}

// MARK: - UITableViewDataSource

extension VideoListViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return videoResultsController?.sections?.first?.objects?.count ?? 0
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(
            withIdentifier: VideoTableViewCell.reuseID, for: indexPath) as! VideoTableViewCell
        guard let video = videoResultsController?.object(at: indexPath),
              let vs = videoService,
              let indexNum = video.videoIndex else { return cell }
        let index = UInt(indexNum.intValue)
        let isDoNotDownload = vs.CheckIsDoNotDownloadForFileIndex(index) ?? true
        let progress: Float? = isDoNotDownload ? nil : vs.UpdateProgressForFileIndex(index)
        cell.configure(with: video, progress: progress, isDoNotDownload: isDoNotDownload)
        return cell
    }
}

// MARK: - UITableViewDelegate

extension VideoListViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        defer { tableView.deselectRow(at: indexPath, animated: true) }
        guard let video = videoResultsController?.object(at: indexPath),
              let vs = videoService,
              let indexNum = video.videoIndex else { return }
        let index = UInt(indexNum.intValue)

        if vs.CheckIsDoNotDownloadForFileIndex(index) ?? false {
            vs.SetDoNotDownloadForFileIndex(index, flag: false)
            tableView.reloadRows(at: [indexPath], with: .none)
        } else if video.videoDownloadPercent?.floatValue == 1.0 {
            guard let cell = tableView.cellForRow(at: indexPath) as? VideoTableViewCell else { return }
            performSegue(withIdentifier: "showVideoPlayer", sender: cell)
        }
    }
}
