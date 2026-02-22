//
//  AnimeDetailViewController.swift
//  TheAnimeTool
//
//  Shows full anime details (banner, cover, synopsis, badges) fetched from AniList via CoreData,
//  plus a per-episode list from the ani.zip API. Tapping "Find Torrents" pushes
//  TorrentListViewController with a pre-populated nyaa.si search for this anime.
//

import UIKit

// MARK: - AniZip episode model

struct AniZipEpisode {
    let number: Int
    let title: String       // English title, or "Episode N" fallback
    let overview: String
    let imageURL: String?
    let airDate: String?
    let runtime: Int        // minutes; 0 if unknown
}

// MARK: - EpisodeCell

private final class EpisodeCell: UITableViewCell {
    static let reuseID = "AniDetailEpCell"

    private let thumbImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.backgroundColor = .systemGray5
        iv.layer.cornerRadius = 6
        return iv
    }()

    private let numberLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 11, weight: .semibold)
        l.textColor = .secondaryLabel
        return l
    }()

    private let titleLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 14, weight: .medium)
        l.textColor = .label
        l.numberOfLines = 1
        return l
    }()

    private let overviewLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 12)
        l.textColor = .secondaryLabel
        l.numberOfLines = 2
        return l
    }()

    private let metaLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 11)
        l.textColor = .tertiaryLabel
        return l
    }()

    private var currentImageURL: String?
    private var imageTask: URLSessionDataTask?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        let textStack = UIStackView(arrangedSubviews: [numberLabel, titleLabel, overviewLabel, metaLabel])
        textStack.axis = .vertical
        textStack.spacing = 2

        [thumbImageView, textStack].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview($0)
        }

        NSLayoutConstraint.activate([
            thumbImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            thumbImageView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            thumbImageView.widthAnchor.constraint(equalToConstant: 100),
            thumbImageView.heightAnchor.constraint(equalToConstant: 60),
            thumbImageView.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -10),

            textStack.leadingAnchor.constraint(equalTo: thumbImageView.trailingAnchor, constant: 12),
            textStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            textStack.topAnchor.constraint(equalTo: thumbImageView.topAnchor),
            textStack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -10),
        ])
    }

    func configure(with episode: AniZipEpisode) {
        numberLabel.text = "Episode \(episode.number)"
        titleLabel.text = episode.title.isEmpty ? "Episode \(episode.number)" : episode.title
        overviewLabel.text = episode.overview
        overviewLabel.isHidden = episode.overview.isEmpty

        var meta: [String] = []
        if let date = episode.airDate { meta.append(date) }
        if episode.runtime > 0 { meta.append("\(episode.runtime) min") }
        metaLabel.text = meta.joined(separator: " · ")
        metaLabel.isHidden = meta.isEmpty

        currentImageURL = episode.imageURL
        thumbImageView.image = nil
        imageTask?.cancel()
        imageTask = nil

        if let urlStr = episode.imageURL, let url = URL(string: urlStr) {
            let captured = urlStr
            imageTask = URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
                guard let data = data, let img = UIImage(data: data) else { return }
                DispatchQueue.main.async {
                    if self?.currentImageURL == captured {
                        self?.thumbImageView.image = img
                    }
                }
            }
            imageTask?.resume()
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageTask?.cancel()
        imageTask = nil
        currentImageURL = nil
        thumbImageView.image = nil
        numberLabel.text = nil
        titleLabel.text = nil
        overviewLabel.text = nil
        metaLabel.text = nil
    }
}

// MARK: - AnimeInfoHeaderView

private final class AnimeInfoHeaderView: UIView {
    var onFindTorrents: (() -> Void)?

    // Banner / cover images
    private let bannerImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.backgroundColor = .systemIndigo.withAlphaComponent(0.25)
        return iv
    }()

    private let bannerDimView: UIView = {
        // Simple dark overlay for readability instead of a gradient that needs
        // special handling for light/dark mode. Black at 45% works in both modes.
        let v = UIView()
        v.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        return v
    }()

    private let coverImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.backgroundColor = .systemGray5
        iv.layer.cornerRadius = 8
        iv.layer.borderColor = UIColor.systemBackground.cgColor
        iv.layer.borderWidth = 3
        return iv
    }()

    // Text labels
    private let titleLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 18, weight: .bold)
        l.textColor = .label
        l.numberOfLines = 3
        return l
    }()

    private let romajiLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 13)
        l.textColor = .secondaryLabel
        l.numberOfLines = 1
        return l
    }()

    private let badgesStack: UIStackView = {
        let sv = UIStackView()
        sv.axis = .horizontal
        sv.spacing = 6
        sv.alignment = .center
        return sv
    }()

    private let descriptionLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 14)
        l.textColor = .secondaryLabel
        l.numberOfLines = 0
        return l
    }()

    private let findTorrentsButton: UIButton = {
        var config = UIButton.Configuration.filled()
        config.title = "Find Torrents on nyaa.si"
        config.image = UIImage(systemName: "arrow.down.circle.fill")
        config.imagePadding = 6
        config.background.backgroundColor = .systemIndigo
        config.cornerStyle = .medium
        config.contentInsets = NSDirectionalEdgeInsets(top: 14, leading: 20, bottom: 14, trailing: 20)
        let b = UIButton(configuration: config)
        return b
    }()

    private var bannerImageTask: URLSessionDataTask?
    private var coverImageTask: URLSessionDataTask?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        findTorrentsButton.addTarget(self, action: #selector(findTorrentsTapped), for: .touchUpInside)

        // Outer stack: desc + button with margins
        let bottomStack = UIStackView(arrangedSubviews: [descriptionLabel, findTorrentsButton])
        bottomStack.axis = .vertical
        bottomStack.spacing = 16
        bottomStack.isLayoutMarginsRelativeArrangement = true
        bottomStack.layoutMargins = UIEdgeInsets(top: 16, left: 16, bottom: 24, right: 16)

        [bannerImageView, bannerDimView, coverImageView,
         titleLabel, romajiLabel, badgesStack, bottomStack].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }

        NSLayoutConstraint.activate([
            // Banner: full width, fixed height
            bannerImageView.topAnchor.constraint(equalTo: topAnchor),
            bannerImageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            bannerImageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            bannerImageView.heightAnchor.constraint(equalToConstant: 180),

            // Dim overlay covers the banner
            bannerDimView.topAnchor.constraint(equalTo: bannerImageView.topAnchor),
            bannerDimView.leadingAnchor.constraint(equalTo: bannerImageView.leadingAnchor),
            bannerDimView.trailingAnchor.constraint(equalTo: bannerImageView.trailingAnchor),
            bannerDimView.bottomAnchor.constraint(equalTo: bannerImageView.bottomAnchor),

            // Cover art: floats over the banner bottom edge (−60pt overlap)
            coverImageView.topAnchor.constraint(equalTo: bannerImageView.bottomAnchor, constant: -60),
            coverImageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            coverImageView.widthAnchor.constraint(equalToConstant: 90),
            coverImageView.heightAnchor.constraint(equalToConstant: 128),

            // Title: to the right of the cover image, just below banner
            titleLabel.topAnchor.constraint(equalTo: bannerImageView.bottomAnchor, constant: 10),
            titleLabel.leadingAnchor.constraint(equalTo: coverImageView.trailingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),

            // Romaji label
            romajiLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            romajiLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            romajiLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),

            // Badges row
            badgesStack.topAnchor.constraint(equalTo: romajiLabel.bottomAnchor, constant: 8),
            badgesStack.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            badgesStack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -16),
            badgesStack.bottomAnchor.constraint(lessThanOrEqualTo: coverImageView.bottomAnchor),

            // Bottom section (description + button): starts below cover image
            bottomStack.topAnchor.constraint(equalTo: coverImageView.bottomAnchor, constant: 12),
            bottomStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            bottomStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            bottomStack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @objc private func findTorrentsTapped() {
        onFindTorrents?()
    }

    func configure(with anime: Animes?) {
        guard let anime = anime else { return }

        let english = anime.animeTitleEnglish
        let romaji = anime.animeTitleJapanese
        titleLabel.text = english ?? romaji ?? "Unknown"

        if let eng = english, let rom = romaji, eng != rom {
            romajiLabel.text = rom
            romajiLabel.isHidden = false
        } else {
            romajiLabel.isHidden = true
        }

        // Populate badges
        badgesStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        if let score = anime.animeScore?.floatValue, score > 0 {
            badgesStack.addArrangedSubview(makeBadge(
                text: String(format: "★ %.0f%%", score),
                bg: .systemYellow, fg: .black))
        }
        if let status = anime.animeStatus {
            let text = status.replacingOccurrences(of: "_", with: " ").capitalized
            badgesStack.addArrangedSubview(makeBadge(text: text, bg: .systemGreen, fg: .white))
        }
        if let total = anime.animeTotalEps?.intValue, total > 0 {
            badgesStack.addArrangedSubview(makeBadge(text: "\(total) eps", bg: .systemIndigo, fg: .white))
        } else if let next = anime.animeNextEps?.intValue, next > 0 {
            badgesStack.addArrangedSubview(makeBadge(text: "Ep \(next) airing", bg: .systemBlue, fg: .white))
        }
        // Flexible spacer to left-align badges
        let spacer = UIView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        badgesStack.addArrangedSubview(spacer)

        // Synopsis
        let desc = anime.animeDescription?.trimmingCharacters(in: .whitespacesAndNewlines)
        descriptionLabel.text = (desc?.isEmpty ?? true) ? "No synopsis available." : desc

        // Load images
        // animeImgS is repurposed to store the banner image URL; fall back to large cover
        loadImage(from: anime.animeImgS ?? anime.animeImgL ?? anime.animeImgM,
                  into: bannerImageView, task: &bannerImageTask)
        loadImage(from: anime.animeImgL ?? anime.animeImgM,
                  into: coverImageView, task: &coverImageTask)
    }

    func configure(with item: AnimeItem) {
        titleLabel.text = item.titleEnglish ?? item.titleRomaji ?? "Unknown"

        if let eng = item.titleEnglish, let rom = item.titleRomaji, eng != rom {
            romajiLabel.text = rom
            romajiLabel.isHidden = false
        } else {
            romajiLabel.isHidden = true
        }

        badgesStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        if let score = item.score, score > 0 {
            badgesStack.addArrangedSubview(makeBadge(
                text: String(format: "★ %.0f%%", score), bg: .systemYellow, fg: .black))
        }
        if let status = item.status {
            let text = status.replacingOccurrences(of: "_", with: " ").capitalized
            badgesStack.addArrangedSubview(makeBadge(text: text, bg: .systemGreen, fg: .white))
        }
        if let eps = item.episodes, eps > 0 {
            badgesStack.addArrangedSubview(makeBadge(text: "\(eps) eps", bg: .systemIndigo, fg: .white))
        }
        let spacer = UIView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        badgesStack.addArrangedSubview(spacer)

        // AnimeItem is fetched for home-screen sections which don't include description
        // (synopsis is omitted from section queries to reduce payload size).
        // The full synopsis is available on the CoreData entity for search/airing results.
        descriptionLabel.text = "No synopsis available."
        loadImage(from: item.bannerURL ?? item.coverURL, into: bannerImageView, task: &bannerImageTask)
        loadImage(from: item.coverURL, into: coverImageView, task: &coverImageTask)
    }

    private func makeBadge(text: String, bg: UIColor, fg: UIColor) -> UILabel {
        let l = UILabel()
        l.text = "  \(text)  "
        l.font = .systemFont(ofSize: 11, weight: .semibold)
        l.textColor = fg
        l.backgroundColor = bg
        l.layer.cornerRadius = 8
        l.clipsToBounds = true
        l.setContentHuggingPriority(.required, for: .horizontal)
        return l
    }

    private func loadImage(from urlString: String?,
                           into imageView: UIImageView,
                           task: inout URLSessionDataTask?) {
        task?.cancel()
        task = nil
        guard let urlString = urlString, let url = URL(string: urlString) else { return }
        task = URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data = data, let img = UIImage(data: data) else { return }
            DispatchQueue.main.async {
                UIView.transition(with: imageView, duration: 0.3,
                                  options: .transitionCrossDissolve,
                                  animations: { imageView.image = img })
            }
        }
        task?.resume()
    }
}

// MARK: - AnimeDetailViewController

class AnimeDetailViewController: UIViewController {

    var animeEntity: Animes?
    var animeItem: AnimeItem?

    private var tableView: UITableView!
    private var headerView: AnimeInfoHeaderView!
    private var episodes: [AniZipEpisode] = []
    private var episodeFetchTask: URLSessionDataTask?

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = animeItem?.titleEnglish ?? animeItem?.titleRomaji
            ?? animeEntity?.animeTitleEnglish ?? animeEntity?.animeTitleJapanese
        navigationItem.largeTitleDisplayMode = .never
        view.backgroundColor = .systemBackground

        setupTableView()
        setupHeaderView()
        fetchEpisodes()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        sizeHeaderView()
    }

    // MARK: - Setup

    private func setupTableView() {
        tableView = UITableView(frame: view.bounds, style: .plain)
        tableView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(EpisodeCell.self, forCellReuseIdentifier: EpisodeCell.reuseID)
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 80
        tableView.separatorInset = UIEdgeInsets(top: 0, left: 128, bottom: 0, right: 0)
        view.addSubview(tableView)
    }

    private func setupHeaderView() {
        headerView = AnimeInfoHeaderView()
        if let item = animeItem {
            headerView.configure(with: item)
        } else {
            headerView.configure(with: animeEntity)
        }
        headerView.onFindTorrents = { [weak self] in
            self?.performSegue(withIdentifier: "showTorrentList", sender: nil)
        }
        // Initial frame: width known, height 0 — sizeHeaderView() will correct it.
        headerView.frame = CGRect(x: 0, y: 0, width: tableView.frame.width, height: 600)
        tableView.tableHeaderView = headerView
    }

    /// Correctly size the tableHeaderView using Auto Layout.
    /// Called from viewDidLayoutSubviews. The > 1pt guard avoids infinite loops
    /// caused by repeatedly setting tableHeaderView which triggers another layout.
    private func sizeHeaderView() {
        guard let header = tableView.tableHeaderView, tableView.frame.width > 0 else { return }
        let targetSize = CGSize(width: tableView.frame.width,
                                height: UIView.layoutFittingCompressedSize.height)
        let height = header.systemLayoutSizeFitting(
            targetSize,
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel).height
        if abs(header.frame.height - height) > 1 {
            header.frame.size.height = height
            tableView.tableHeaderView = header
        }
    }

    // MARK: - Ani.zip episode fetch

    private func fetchEpisodes() {
        let anilistId: Int?
        if let entity = animeEntity {
            anilistId = entity.animeAnilistId?.intValue
        } else {
            anilistId = animeItem?.id
        }
        guard let id = anilistId else { return }
        var comps = URLComponents(string: "https://api.ani.zip/mappings")
        comps?.queryItems = [URLQueryItem(name: "anilist_id", value: String(id))]
        guard let url = comps?.url else { return }

        episodeFetchTask?.cancel()
        episodeFetchTask = URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let episodesDict = json["episodes"] as? [String: Any] else { return }

            var parsed: [AniZipEpisode] = []
            for (key, val) in episodesDict {
                guard let num = Int(key),
                      num > 0,            // skip episode 0 (specials/PV) and any negative keys
                      let info = val as? [String: Any] else { continue }

                let titles = info["title"] as? [String: String] ?? [:]
                // Prefer English, then romaji (x-jat), then Japanese
                let title = titles["en"] ?? titles["x-jat"] ?? titles["ja"] ?? ""
                let overview = (info["overview"] as? String
                    ?? info["summary"] as? String ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let imageURL = info["image"] as? String
                let airDate = info["airdate"] as? String ?? info["airDate"] as? String
                let runtime = info["length"] as? Int ?? info["runtime"] as? Int ?? 0

                parsed.append(AniZipEpisode(
                    number: num,
                    title: title,
                    overview: overview,
                    imageURL: imageURL,
                    airDate: airDate,
                    runtime: runtime))
            }

            parsed.sort { $0.number < $1.number }

            DispatchQueue.main.async { [weak self] in
                self?.episodes = parsed
                self?.tableView.reloadData()
            }
        }
        episodeFetchTask?.resume()
    }

    // MARK: - Navigation

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        guard segue.identifier == "showTorrentList",
              let dest = segue.destination as? TorrentListViewController else { return }
        dest.animeEntity = animeEntity
        if animeEntity == nil, let item = animeItem {
            dest.animeTitleOverride = item.titleEnglish ?? item.titleRomaji
        }
    }
}

// MARK: - UITableViewDataSource

extension AnimeDetailViewController: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        return episodes.isEmpty ? 0 : 1
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return episodes.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(
            withIdentifier: EpisodeCell.reuseID, for: indexPath) as? EpisodeCell else {
            return UITableViewCell()
        }
        cell.configure(with: episodes[indexPath.row])
        return cell
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return episodes.isEmpty ? nil : "Episodes · \(episodes.count)"
    }
}

// MARK: - UITableViewDelegate

extension AnimeDetailViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        // Tapping an episode navigates to the torrent search for this anime.
        performSegue(withIdentifier: "showTorrentList", sender: nil)
    }
}
