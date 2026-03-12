// ExtensionSearchViewController.swift
// Torrent search sheet powered by Hayase-compatible extensions.
// Replaces TorrentListViewControllerTableViewController.swift (which hit nyaa.si directly).
// Mirrors the behaviour of SearchModal.svelte from scigward/interface.
//
// Flow:
//   1. Presented (push) from AnimeDetailViewController when user taps "Watch Now" on an episode.
//   2. Shows episode/resolution pickers; calls ExtensionService.shared.search(query:).
//   3. Displays deduplicated TorrentResult list with accuracy badge, seeders, size.
//   4. Tapping a result confirms download → adds magnet/torrent to LibTorrent session.

import UIKit

// MARK: - ExtensionSearchViewController

final class ExtensionSearchViewController: UIViewController {

    // MARK: - Input

    var animeItem: AnimeItem?
    var initialEpisode: Int = 1

    // MARK: - Private state

    private var results: [TorrentResult] = []
    private var isSearching = false
    private var currentEpisode: Int = 1
    private var currentResolution = "1080"

    // MARK: - UI

    private var tableView: UITableView!
    private var loadingIndicator: UIActivityIndicatorView!
    private var emptyLabel: UILabel!
    private var errorLabel: UILabel!
    private var searchTask: Task<Void, Never>?

    // Controls bar (episode + resolution)
    private var controlsBar: UIView!
    private var episodeStepper: UIStepper!
    private var episodeLabel: UILabel!
    private var resolutionButton: UIButton!

    // MARK: - Resolutions (mirrors values.ts videoResolutions)
    private let resolutions = ["2160", "1080", "720", "540", "480"]
    private let resolutionLabels = ["4K (2160p)", "1080p", "720p", "540p", "480p"]

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        currentEpisode = initialEpisode
        title = animeItem?.titleEnglish ?? animeItem?.titleRomaji ?? "Find Episode"
        view.backgroundColor = .black
        navigationItem.largeTitleDisplayMode = .never

        setupControlsBar()
        setupTableView()
        setupOverlays()
        triggerSearch()
    }

    // MARK: - Setup

    private func setupControlsBar() {
        let bar = UIView()
        bar.backgroundColor = UIColor(white: 0.08, alpha: 1)
        bar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bar)
        self.controlsBar = bar

        // Episode label + stepper
        episodeLabel = UILabel()
        episodeLabel.text = "Episode \(currentEpisode)"
        episodeLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        episodeLabel.textColor = .white

        episodeStepper = UIStepper()
        episodeStepper.minimumValue = 1
        episodeStepper.maximumValue = Double(animeItem?.episodes ?? 9999)
        episodeStepper.value = Double(currentEpisode)
        episodeStepper.addTarget(self, action: #selector(episodeStepperChanged), for: .valueChanged)
        episodeStepper.tintColor = UIColor(red: 0.239, green: 0.706, blue: 0.949, alpha: 1) // rgb(61,180,242)

        let epStack = UIStackView(arrangedSubviews: [episodeLabel, episodeStepper])
        epStack.axis = .horizontal
        epStack.spacing = 10
        epStack.alignment = .center

        // Resolution button
        resolutionButton = UIButton(type: .system)
        resolutionButton.setTitle("1080p ▾", for: .normal)
        resolutionButton.setTitleColor(.white, for: .normal)
        resolutionButton.titleLabel?.font = .systemFont(ofSize: 13, weight: .medium)
        resolutionButton.backgroundColor = UIColor(white: 0.15, alpha: 1)
        resolutionButton.layer.cornerRadius = 6
        resolutionButton.contentEdgeInsets = UIEdgeInsets(top: 5, left: 10, bottom: 5, right: 10)
        resolutionButton.addTarget(self, action: #selector(resolutionTapped), for: .touchUpInside)

        [epStack, resolutionButton].forEach {
            ($0 as UIView).translatesAutoresizingMaskIntoConstraints = false
            bar.addSubview($0)
        }

        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            bar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bar.heightAnchor.constraint(equalToConstant: 52),

            epStack.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 16),
            epStack.centerYAnchor.constraint(equalTo: bar.centerYAnchor),

            resolutionButton.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -16),
            resolutionButton.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
        ])
    }

    private func setupTableView() {
        tableView = UITableView(frame: .zero, style: .plain)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = .black
        tableView.separatorColor = UIColor(white: 0.15, alpha: 1)
        tableView.delegate   = self
        tableView.dataSource = self
        tableView.register(TorrentResultCell.self, forCellReuseIdentifier: TorrentResultCell.reuseID)
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 72
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: controlsBar.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func setupOverlays() {
        loadingIndicator = UIActivityIndicatorView(style: .large)
        loadingIndicator.color = .white
        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
        loadingIndicator.hidesWhenStopped = true
        view.addSubview(loadingIndicator)

        emptyLabel = makeStatusLabel("No results found")
        errorLabel = makeStatusLabel("")
        errorLabel.textColor = UIColor(red: 1, green: 0.4, blue: 0.4, alpha: 1)
        errorLabel.numberOfLines = 4

        NSLayoutConstraint.activate([
            loadingIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            emptyLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            emptyLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            errorLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            errorLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            errorLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            errorLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
        ])
    }

    private func makeStatusLabel(_ text: String) -> UILabel {
        let l = UILabel()
        l.text = text
        l.textColor = UIColor(white: 0.5, alpha: 1)
        l.font = .systemFont(ofSize: 15)
        l.textAlignment = .center
        l.isHidden = true
        l.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(l)
        return l
    }

    // MARK: - Search

    private func triggerSearch() {
        searchTask?.cancel()
        guard let item = animeItem else { return }

        results = []
        tableView.reloadData()
        emptyLabel.isHidden = true
        errorLabel.isHidden = true
        loadingIndicator.startAnimating()
        isSearching = true

        let episode = currentEpisode
        let resolution = currentResolution

        searchTask = Task { @MainActor in
            do {
                // Use the high-level search(for:episode:resolution:) which fetches
                // AniDB IDs from api.ani.zip — matches Hayase's getResultsFromExtensions.
                let found = try await ExtensionService.shared.search(for: item, episode: episode, resolution: resolution)
                guard !Task.isCancelled else { return }
                self.results = found
                self.tableView.reloadData()
                self.emptyLabel.isHidden = !found.isEmpty
                self.errorLabel.isHidden = true
            } catch {
                guard !Task.isCancelled else { return }
                self.errorLabel.text = error.localizedDescription
                self.errorLabel.isHidden = false
                self.emptyLabel.isHidden = true
            }
            self.loadingIndicator.stopAnimating()
            self.isSearching = false
        }
    }

    // MARK: - Actions

    @objc private func episodeStepperChanged() {
        currentEpisode = Int(episodeStepper.value)
        episodeLabel.text = "Episode \(currentEpisode)"
        triggerSearch()
    }

    @objc private func resolutionTapped() {
        let sheet = UIAlertController(title: "Resolution", message: nil, preferredStyle: .actionSheet)
        for (i, label) in resolutionLabels.enumerated() {
            let res = resolutions[i]
            sheet.addAction(UIAlertAction(title: label, style: .default) { [weak self] _ in
                guard let self else { return }
                self.currentResolution = res
                self.resolutionButton.setTitle("\(res == "2160" ? "4K " : "")\(res)p ▾", for: .normal)
                self.triggerSearch()
            })
        }
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        sheet.popoverPresentationController?.sourceView = resolutionButton
        present(sheet, animated: true)
    }

    // MARK: - Download confirmation

    private func confirmDownload(_ result: TorrentResult) {
        let sizeStr = formatBytes(result.size)
        let msg = "\(result.title)\n\nSize: \(sizeStr)  ·  ▲ \(result.seeders) seeders"
        let alert = UIAlertController(title: "Download?", message: msg, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "Download", style: .default) { [weak self] _ in
            self?.startDownload(result)
        })
        alert.addAction(UIAlertAction(title: "Copy Link", style: .default) { _ in
            UIPasteboard.general.string = result.link
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.popoverPresentationController?.sourceView = view
        present(alert, animated: true)
    }

    private func startDownload(_ result: TorrentResult) {
        // Create a temporary CoreData Torrents entity to pass into TorrentService
        let context = CoreDataService.sharedCoreDataService.mainQueueContext
        let entity  = Torrents(context: context)
        entity.torrentName        = result.title
        entity.torrentHashString  = result.hash
        entity.torrentDownloadURL = result.link
        entity.torrentSeeders     = NSNumber(value: result.seeders)
        entity.torrentLeechers    = NSNumber(value: result.leechers)
        entity.torrentSize        = NSNumber(value: Double(result.size) / 1_048_576) // bytes → MB
        entity.torrentFlagTemp    = false
        // Link to anime if available
        if let animeItem {
            let req = Animes.fetchRequest()
            req.predicate = NSPredicate(format: "animeAnilistId == %d", animeItem.id)
            entity.animes = (try? context.fetch(req))?.first as? Animes
        }
        try? context.save()

        let hud = UIAlertController(title: "Adding…", message: nil, preferredStyle: .alert)
        present(hud, animated: true)

        TorrentService.sharedTorrentService.UpdateTorrentEntityInController(entity) { [weak self] res in
            DispatchQueue.main.async {
                hud.dismiss(animated: false) {
                    switch res {
                    case .success:
                        self?.navigationController?.popViewController(animated: true)
                    case .failure(let err):
                        let errAlert = UIAlertController(title: "Error", message: err.localizedDescription,
                                                         preferredStyle: .alert)
                        errAlert.addAction(UIAlertAction(title: "OK", style: .cancel))
                        self?.present(errAlert, animated: true)
                    }
                }
            }
        }
    }
}

// MARK: - UITableViewDataSource + Delegate

extension ExtensionSearchViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        results.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: TorrentResultCell.reuseID,
                                                  for: indexPath) as! TorrentResultCell
        cell.configure(with: results[indexPath.row])
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        confirmDownload(results[indexPath.row])
    }
}

// MARK: - TorrentResultCell

private final class TorrentResultCell: UITableViewCell {
    static let reuseID = "TorrentResultCell"

    private let accuracyBadge: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 10, weight: .bold)
        l.textColor = .white
        l.textAlignment = .center
        l.layer.cornerRadius = 5
        l.clipsToBounds = true
        return l
    }()

    private let typeBadge: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 10, weight: .semibold)
        l.textColor = UIColor(white: 0.7, alpha: 1)
        l.backgroundColor = UIColor(white: 0.15, alpha: 1)
        l.textAlignment = .center
        l.layer.cornerRadius = 4
        l.clipsToBounds = true
        return l
    }()

    private let titleLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 13, weight: .medium)
        l.textColor = .white
        l.numberOfLines = 2
        return l
    }()

    private let seedersLabel = TorrentResultCell.makeStat(color: .systemGreen)
    private let leechersLabel = TorrentResultCell.makeStat(color: .systemRed)
    private let sizeLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 11)
        l.textColor = UIColor(white: 0.5, alpha: 1)
        return l
    }()

    private static func makeStat(color: UIColor) -> UILabel {
        let l = UILabel()
        l.font = .systemFont(ofSize: 11, weight: .semibold)
        l.textColor = color
        return l
    }

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .black
        selectedBackgroundView = {
            let v = UIView(); v.backgroundColor = UIColor(white: 0.1, alpha: 1); return v
        }()
        accessoryType = .none

        let topRow = UIStackView(arrangedSubviews: [accuracyBadge, typeBadge])
        topRow.axis = .horizontal
        topRow.spacing = 6
        topRow.alignment = .center

        let bottomRow = UIStackView(arrangedSubviews: [seedersLabel, leechersLabel, sizeLabel])
        bottomRow.axis = .horizontal
        bottomRow.spacing = 12
        bottomRow.alignment = .center

        let stack = UIStackView(arrangedSubviews: [topRow, titleLabel, bottomRow])
        stack.axis = .vertical
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10),
            accuracyBadge.widthAnchor.constraint(greaterThanOrEqualToConstant: 40),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(with result: TorrentResult) {
        titleLabel.text = result.title
        seedersLabel.text = "▲ \(result.seeders)"
        leechersLabel.text = "▼ \(result.leechers)"
        sizeLabel.text = formatBytes(result.size)

        // Accuracy badge colour
        let (accText, accColor): (String, UIColor) = switch result.accuracy {
        case "high":   ("HIGH",   UIColor(red: 0.2, green: 0.7, blue: 0.3, alpha: 1))
        case "medium": ("MED",    UIColor(red: 0.9, green: 0.7, blue: 0.1, alpha: 1))
        default:       ("LOW",    UIColor(red: 0.7, green: 0.3, blue: 0.3, alpha: 1))
        }
        accuracyBadge.text = "  \(accText)  "
        accuracyBadge.backgroundColor = accColor

        // Type badge
        typeBadge.text = result.type.map { "  \($0.uppercased())  " }
        typeBadge.isHidden = result.type == nil
    }
}

// MARK: - Byte formatter

private func formatBytes(_ bytes: Int64) -> String {
    let gb: Double = 1_073_741_824
    let mb: Double = 1_048_576
    let d = Double(bytes)
    if d >= gb { return String(format: "%.2f GB", d / gb) }
    if d >= mb { return String(format: "%.0f MB", d / mb) }
    return String(format: "%.0f KB", d / 1024)
}
