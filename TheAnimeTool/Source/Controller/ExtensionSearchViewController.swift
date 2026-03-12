// ExtensionSearchViewController.swift
// Ports SearchModal.svelte from scigward/interface exactly to native UIKit.
//
// Layout (matches SearchModal.svelte):
//   [Banner image header with gradient + title]
//   [Filter textfield (with magnifying glass icon)]
//   [Episode number field]  [Resolution picker]
//   [Auto Select button — accent color]
//   [Scrollable card list]
//     Each card: dark bg #0a0a0a, release group xl bold, simplified filename,
//     type badge (Best/Alt/Batch), seeders (coloured), size, date, tech term badges
//     BadgeCheck top-left (green=high, muted=medium, hidden=low, 40% opacity=low)

import UIKit

// MARK: - TitleExtraction helpers (mirrors getGroup / simplifyFilename / sanitiseTerms)

private enum TitleUtils {

    // MARK: Term colours (mirror termMapping in SearchModal.svelte)
    static let lime     = UIColor(red: 0.776, green: 0.925, blue: 0.345, alpha: 1) // #c6ec58
    static let blue     = UIColor(red: 0.047, green: 0.549, blue: 0.914, alpha: 1) // #0c8ce9
    static let orange   = UIColor(red: 0.965, green: 0.447, blue: 0.333, alpha: 1) // #f67255
    static let darkRed  = UIColor(red: 0.671, green: 0.106, blue: 0.192, alpha: 1) // #ab1b31
    static let yellow   = UIColor(red: 1.000, green: 0.796, blue: 0.231, alpha: 1) // #ffcb3b

    struct Term { let text: String; let color: UIColor }

    // Ordered — first match wins per category
    static let termPatterns: [(pattern: NSRegularExpression, term: Term)] = build()

    private static func build() -> [(pattern: NSRegularExpression, term: Term)] {
        let pairs: [(String, Term)] = [
            // Resolution (lime)
            (#"\b2160p\b"#,              Term(text: "4K",       color: lime)),
            (#"\b4K\b"#,                 Term(text: "4K",       color: lime)),
            (#"\b1080p\b"#,              Term(text: "1080p",    color: lime)),
            (#"\b720p\b"#,               Term(text: "720p",     color: lime)),
            (#"\b480p\b"#,               Term(text: "480p",     color: lime)),
            // Video codec (blue)
            (#"\b(?:HEVC|H\.265|x265|H265)\b"#, Term(text: "HEVC",     color: blue)),
            (#"\b(?:AVC|H\.264|x264|H264)\b"#,  Term(text: "AVC",      color: blue)),
            (#"\bAV1\b"#,                        Term(text: "AV1",      color: blue)),
            (#"\b(?:10[- ]?[Bb]it|HI10P?|Hi10P?)\b"#, Term(text: "10 Bit", color: blue)),
            (#"\bHI444P{1,2}\b"#,        Term(text: "HI444",    color: blue)),
            // Source (dark red)
            (#"\b(?:BD|BDRip|BluRay|Blu-Ray|Blu_Ray)\b"#, Term(text: "BD",   color: darkRed)),
            (#"\b(?:DVD|DVDRip|DVD-RIP)\b"#,               Term(text: "DVD",  color: darkRed)),
            (#"\bWEB(?:RIP|-RIP)?\b"#,                     Term(text: "WEB",  color: darkRed)),
            // Audio (orange)
            (#"\bFLAC(?:X[234])?\b"#,   Term(text: "FLAC",      color: orange)),
            (#"\bTrueHD5\.1\b"#,        Term(text: "TrueHD 5.1",color: orange)),
            (#"\bEAC3|E-AC-3\b"#,       Term(text: "EAC3",       color: orange)),
            (#"\bAAC(?:X[234])?\b"#,    Term(text: "AAC",         color: orange)),
            (#"\bAC3\b"#,               Term(text: "AC3",         color: orange)),
            (#"\b5\.1(?:CH)?\b"#,       Term(text: "5.1",         color: orange)),
            // Multi-sub (yellow)
            (#"\b(?:MULTI.?SUBS?)\b"#,  Term(text: "Multi Sub",  color: yellow)),
            (#"\b(?:DUAL.?AUDIO)\b"#,   Term(text: "Dual Audio", color: yellow)),
        ]
        return pairs.compactMap { (pat, term) in
            guard let rx = try? NSRegularExpression(pattern: pat, options: .caseInsensitive)
            else { return nil }
            return (rx, term)
        }
    }

    /// Extract tech terms from torrent title — mirrors sanitiseTerms()
    static func sanitise(_ title: String) -> [Term] {
        let ns = title as NSString
        let range = NSRange(location: 0, length: ns.length)
        var seen = Set<String>()
        var result: [Term] = []
        for (rx, term) in termPatterns {
            if rx.firstMatch(in: title, range: range) != nil {
                if !seen.contains(term.text) {
                    seen.insert(term.text)
                    result.append(term)
                }
            }
        }
        return result
    }

    /// Extract release group — mirrors getGroup()
    static func getGroup(from title: String) -> String {
        // Try [Group] at start
        if let m = title.range(of: #"^\[([^\]]{1,19})\]"#, options: .regularExpression) {
            let inner = title[title.index(after: m.lowerBound)..<title.index(before: m.upperBound)]
            return String(inner)
        }
        // Try (Group) in the title — common for SubsPlease, Erai-raws etc.
        if let m = title.range(of: #"\(([A-Za-z0-9_\-]{2,18})\)"#, options: .regularExpression) {
            let inner = title[title.index(after: m.lowerBound)..<title.index(before: m.upperBound)]
            return String(inner)
        }
        // Try -Group at end (before extension or space+paren)
        let nsTitle = title as NSString
        let rx = try? NSRegularExpression(pattern: #"-([A-Za-z0-9_]{2,18})(?:\s*[\(\[]|\.\w+$|$)"#)
        if let m = rx?.firstMatch(in: title, range: NSRange(location: 0, length: nsTitle.length)),
           m.range(at: 1).location != NSNotFound {
            return nsTitle.substring(with: m.range(at: 1))
        }
        return "Unknown"
    }

    /// Simplified filename — mirrors simplifyFilename()
    static func simplify(_ title: String) -> String {
        var s = title
        // Remove [Group] and (Group) brackets
        s = s.replacingOccurrences(of: #"\[[^\]]*\]"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\([^\)]*\)"#, with: "", options: .regularExpression)
        // Remove resolution, codecs
        let junk = [#"\b(?:2160p|1080p|720p|480p|4K|HEVC|x265|x264|H\.265|H\.264|AV1|BD|BDRip|BluRay|Blu-Ray|FLAC|AAC|AC3|EAC3|10bit|HI10P?|WEB-DL|WEBRip)\b"#]
        for pattern in junk {
            s = s.replacingOccurrences(of: pattern, with: "", options: [.regularExpression, .caseInsensitive])
        }
        // Remove empty brackets and extra spaces
        s = s.replacingOccurrences(of: #"[\[\(\{\}\)\]]\s*[\[\(\{\}\)\]]"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        // Remove file extension
        s = s.replacingOccurrences(of: #"\.\w{2,4}$"#, with: "", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - ExtensionSearchViewController

final class ExtensionSearchViewController: UIViewController {

    // MARK: Input
    var animeItem: AnimeItem?
    var initialEpisode: Int = 1

    // MARK: State
    private var results: [TorrentResult] = []
    private var filteredResults: [TorrentResult] = []
    private var filterText: String = ""
    private var isSearching = false
    private var currentEpisode: Int = 1
    private var currentResolution = "1080"
    private var searchTask: Task<Void, Never>?

    // MARK: UI
    private var tableView: UITableView!
    private var loadingIndicator: UIActivityIndicatorView!
    private var headerView: UIView!

    // Banner
    private var bannerImageView: UIImageView!
    private var bannerGradientLayer: CAGradientLayer!
    private var animeTitleLabel: UILabel!

    // Controls
    private var filterField: UITextField!
    private var episodeField: UITextField!
    private var resolutionButton: UIButton!
    private var autoSelectButton: UIButton!

    // State overlays
    private var emptyView: UIView!
    private var errorView: UIView!
    private var errorLabel: UILabel!

    private let resolutions = ["2160", "1080", "720", "540", "480"]

    // MARK: Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        currentEpisode = initialEpisode
        view.backgroundColor = UIColor(white: 0.04, alpha: 1)
        navigationItem.largeTitleDisplayMode = .never
        // Hide nav bar title since we show the anime title in the banner area
        navigationItem.title = nil

        setupHeader()
        setupTableView()
        setupStateViews()
        triggerSearch()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        bannerGradientLayer?.frame = bannerImageView?.bounds ?? .zero
    }

    // MARK: - Setup: header (mirrors SearchModal.svelte layout exactly)
    // Layout top-to-bottom:
    //   [144pt banner: cover image @ 40% opacity + gradient fade to black]
    //   [Anime title — text-2xl font-bold, truncated]
    //   [Filter textfield with magnifying glass icon]
    //   [Episode field  |  Resolution button] (equal halves)
    //   [Auto Select Torrent button — full width, accent blue]

    private func setupHeader() {
        let header = UIView()
        self.headerView = header
        header.backgroundColor = UIColor(white: 0.04, alpha: 1)
        header.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(header)

        // ── Banner image (mirrors SearchModal.svelte: <Banner class='opacity-40' />)
        // The banner is positioned ABSOLUTE at top-0, h=144pt (max-h-36), behind all content.
        // Content starts at top+32pt (pt-8) and overlaps the banner — the gradient makes
        // the lower banner area dark so overlapping text is readable. This matches exactly
        // how Hayase's modal layout works: the absolute banner div does NOT take flow space.
        bannerImageView = UIImageView()
        bannerImageView.contentMode = .scaleAspectFill
        bannerImageView.clipsToBounds = true
        bannerImageView.alpha = 0.4 // matches opacity-40
        bannerImageView.backgroundColor = UIColor(white: 0.08, alpha: 1)
        bannerImageView.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(bannerImageView)

        // Gradient: transparent (top 30%) → black/80 (bottom), mirrors:
        // <div class='w-full h-[70%] bg-gradient-to-t from-black/80 to-transparent' />
        // The gradient div covers the lower 70% (not full height), hence locations [0.3, 1.0]
        bannerGradientLayer = CAGradientLayer()
        bannerGradientLayer.colors = [UIColor.clear.cgColor, UIColor.black.withAlphaComponent(0.8).cgColor]
        bannerGradientLayer.locations = [0.3, 1.0]
        bannerImageView.layer.addSublayer(bannerGradientLayer)

        // Banner: AniList bannerImage first → coverURL fallback.
        // (Hayase SearchModal uses <Banner> which on mobile uses coverImage.extraLarge,
        //  but since iOS 18+ layout may show the banner in a wide viewport at times,
        //  prefer the landscape bannerImage when available for best visual.)
        let imageURLStr = animeItem?.bannerURL ?? animeItem?.coverURL
        if let urlStr = imageURLStr, let url = URL(string: urlStr) {
            URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
                if let data, let img = UIImage(data: data) {
                    DispatchQueue.main.async { self?.bannerImageView.image = img }
                }
            }.resume()
        }

        // ── Compute accent colour from AniList coverImage.color (mirrors --custom in Hayase)
        // Hayase: style:--custom={media.coverImage?.color ?? '#fff'}
        // bg-custom = background in the anime's dominant color; text-contrast = black or white
        let accentColor = Self.uiColor(fromHex: animeItem?.coverColor) ?? .white
        let contrastColor = Self.luminanceContrastColor(for: accentColor)

        // ── Anime title (mirrors <div class='text-2xl font-bold text-ellipsis text-nowrap'>)
        // Positioned at top+32pt (pt-8), overlapping the banner's lower portion.
        animeTitleLabel = UILabel()
        animeTitleLabel.text = animeItem?.titleEnglish ?? animeItem?.titleRomaji ?? "Torrent Search"
        animeTitleLabel.font = .systemFont(ofSize: 22, weight: .bold)
        animeTitleLabel.textColor = .white
        animeTitleLabel.numberOfLines = 1
        animeTitleLabel.lineBreakMode = .byTruncatingTail
        animeTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(animeTitleLabel)

        // ── Filter field (mirrors <Input placeholder="Filter by text..." /> with MagnifyingGlass icon)
        filterField = UITextField()
        filterField.placeholder = "Filter by text, or paste a magnet / torrent link"
        filterField.attributedPlaceholder = NSAttributedString(
            string: filterField.placeholder ?? "",
            attributes: [.foregroundColor: UIColor(white: 0.45, alpha: 1)])
        filterField.backgroundColor = UIColor(white: 0.1, alpha: 1)
        filterField.textColor = .white
        filterField.tintColor = .white
        filterField.font = .systemFont(ofSize: 13)
        filterField.autocorrectionType = .no
        filterField.autocapitalizationType = .none
        filterField.returnKeyType = .done
        filterField.layer.cornerRadius = 8
        filterField.leftViewMode = .always
        let magIcon = UIImageView(image: UIImage(systemName: "magnifyingglass"))
        magIcon.tintColor = UIColor(white: 0.5, alpha: 1)
        magIcon.contentMode = .scaleAspectFit
        magIcon.frame = CGRect(x: 0, y: 0, width: 32, height: 18)
        filterField.leftView = magIcon
        filterField.delegate = self
        filterField.addTarget(self, action: #selector(filterChanged), for: .editingChanged)
        filterField.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(filterField)

        // ── Episode row (mirrors <div>Episode <Input type='number' /></div>)
        let epLabel = UILabel()
        epLabel.text = "Episode"
        epLabel.textColor = .white
        epLabel.font = .systemFont(ofSize: 14)

        episodeField = UITextField()
        episodeField.text = "\(currentEpisode)"
        episodeField.keyboardType = .numberPad
        episodeField.backgroundColor = UIColor(white: 0.1, alpha: 1)
        episodeField.textColor = .white
        episodeField.tintColor = .white
        episodeField.font = .systemFont(ofSize: 14)
        episodeField.textAlignment = .center
        episodeField.layer.cornerRadius = 8
        episodeField.delegate = self
        episodeField.translatesAutoresizingMaskIntoConstraints = false
        let toolbar = UIToolbar()
        toolbar.sizeToFit()
        let decBtn = UIBarButtonItem(title: "−", style: .plain, target: self, action: #selector(decrementEpisode))
        let incBtn = UIBarButtonItem(title: "+", style: .plain, target: self, action: #selector(incrementEpisode))
        decBtn.tintColor = .white; incBtn.tintColor = .white
        let flex = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        let done = UIBarButtonItem(title: "Done", style: .done, target: self, action: #selector(episodeFieldDone))
        toolbar.items = [decBtn, incBtn, flex, done]
        toolbar.barStyle = .black
        toolbar.tintColor = .white
        episodeField.inputAccessoryView = toolbar

        let epStack = UIStackView(arrangedSubviews: [epLabel, episodeField])
        epStack.axis = .horizontal
        epStack.spacing = 8
        epStack.alignment = .center

        // ── Resolution row (mirrors <div>Resolution <SingleCombo /></div>)
        let resLabel = UILabel()
        resLabel.text = "Resolution"
        resLabel.textColor = .white
        resLabel.font = .systemFont(ofSize: 14)

        resolutionButton = UIButton(type: .system)
        resolutionButton.setTitle("1080p ▾", for: .normal)
        resolutionButton.setTitleColor(.white, for: .normal)
        resolutionButton.titleLabel?.font = .systemFont(ofSize: 13, weight: .medium)
        resolutionButton.backgroundColor = UIColor(white: 0.1, alpha: 1)
        resolutionButton.layer.cornerRadius = 8
        resolutionButton.contentEdgeInsets = UIEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)
        resolutionButton.addTarget(self, action: #selector(resolutionTapped), for: .touchUpInside)
        resolutionButton.translatesAutoresizingMaskIntoConstraints = false

        let resStack = UIStackView(arrangedSubviews: [resLabel, resolutionButton])
        resStack.axis = .horizontal
        resStack.spacing = 8
        resStack.alignment = .center

        // Episode + Resolution in equal-halves horizontal stack (mirrors justify-around flex-wrap)
        let controlsRow = UIStackView(arrangedSubviews: [epStack, resStack])
        controlsRow.axis = .horizontal
        controlsRow.distribution = .fillEqually
        controlsRow.spacing = 16
        controlsRow.alignment = .center
        controlsRow.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(controlsRow)

        // ── Auto Select button (mirrors <ProgressButton class='w-full font-bold bg-custom text-contrast'>)
        // bg-custom = anime's coverImage.color; text-contrast = black or white based on luminance
        autoSelectButton = UIButton(type: .system)
        autoSelectButton.setTitle("Auto Select Torrent", for: .normal)
        autoSelectButton.setTitleColor(contrastColor, for: .normal)
        autoSelectButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .bold)
        autoSelectButton.backgroundColor = accentColor
        autoSelectButton.layer.cornerRadius = 8
        autoSelectButton.addTarget(self, action: #selector(autoSelectTapped), for: .touchUpInside)
        autoSelectButton.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(autoSelectButton)

        // Send banner to back so all content renders on top of it
        header.sendSubviewToBack(bannerImageView)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            // Banner: absolute at top-0, h=144pt (max-h-36 = 9rem = 144pt)
            // Sent to back above — content overlaps from top+32pt onward
            bannerImageView.topAnchor.constraint(equalTo: header.topAnchor),
            bannerImageView.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            bannerImageView.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            bannerImageView.heightAnchor.constraint(equalToConstant: 144),

            // Content column starts at top+32pt (pt-8), overlapping the banner.
            // The banner gradient fades to black/85 so text is readable.
            animeTitleLabel.topAnchor.constraint(equalTo: header.topAnchor, constant: 32),
            animeTitleLabel.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 16),
            animeTitleLabel.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -16),

            // Filter field — space-y-4 = 16pt below title
            filterField.topAnchor.constraint(equalTo: animeTitleLabel.bottomAnchor, constant: 16),
            filterField.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 16),
            filterField.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -16),
            filterField.heightAnchor.constraint(equalToConstant: 38),

            // Episode + resolution controls row — space-y-4 = 16pt below filter
            controlsRow.topAnchor.constraint(equalTo: filterField.bottomAnchor, constant: 16),
            controlsRow.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 16),
            controlsRow.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -16),
            controlsRow.heightAnchor.constraint(equalToConstant: 34),

            episodeField.widthAnchor.constraint(equalToConstant: 80),
            episodeField.heightAnchor.constraint(equalToConstant: 34),

            // Auto Select button — space-y-4 = 16pt below controls
            autoSelectButton.topAnchor.constraint(equalTo: controlsRow.bottomAnchor, constant: 16),
            autoSelectButton.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 16),
            autoSelectButton.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -16),
            autoSelectButton.heightAnchor.constraint(equalToConstant: 40),
            autoSelectButton.bottomAnchor.constraint(equalTo: header.bottomAnchor, constant: -16),
        ])
    }

    // MARK: - Colour helpers (mirror Hayase's colors() utility + text-contrast logic)

    /// Parse a CSS hex colour string (#rrggbb or #rgb) → UIColor. Returns nil on failure.
    static func uiColor(fromHex hex: String?) -> UIColor? {
        guard var h = hex, h.hasPrefix("#") else { return nil }
        h.removeFirst()
        if h.count == 3 { h = h.map { "\($0)\($0)" }.joined() }
        guard h.count == 6, let bigint = UInt64(h, radix: 16) else { return nil }
        let r = CGFloat((bigint >> 16) & 0xff) / 255
        let g = CGFloat((bigint >>  8) & 0xff) / 255
        let b = CGFloat( bigint        & 0xff) / 255
        return UIColor(red: r, green: g, blue: b, alpha: 1)
    }

    /// Compute WCAG luminance and return black or white for best contrast.
    /// Mirrors Hayase's text-contrast CSS class (luminance > 0.5 → dark text).
    static func luminanceContrastColor(for color: UIColor) -> UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: nil)
        let luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
        return luminance > 0.5 ? UIColor(white: 0.07, alpha: 1) : .white
    }

    private func setupTableView() {
        tableView = UITableView(frame: .zero, style: .plain)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = UIColor(white: 0.04, alpha: 1)
        tableView.separatorStyle = .none
        tableView.contentInset = UIEdgeInsets(top: 8, left: 0, bottom: 16, right: 0)
        tableView.delegate   = self
        tableView.dataSource = self
        tableView.register(TorrentResultCell.self, forCellReuseIdentifier: TorrentResultCell.reuseID)
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 106
        tableView.keyboardDismissMode = .onDrag
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func setupStateViews() {
        // Loading
        loadingIndicator = UIActivityIndicatorView(style: .large)
        loadingIndicator.color = .white
        loadingIndicator.hidesWhenStopped = true
        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(loadingIndicator)

        // Empty view — "Ooops!" (mirrors {:else} case)
        emptyView = UIView()
        emptyView.isHidden = true
        emptyView.translatesAutoresizingMaskIntoConstraints = false
        let oopsLabel = UILabel()
        oopsLabel.text = "Ooops!"
        oopsLabel.font = .systemFont(ofSize: 30, weight: .bold)
        oopsLabel.textColor = .white
        oopsLabel.textAlignment = .center
        let noResultLabel = UILabel()
        noResultLabel.text = "No results found.\nTry specifying a torrent manually by pasting a magnet link into the filter bar."
        noResultLabel.font = .systemFont(ofSize: 14)
        noResultLabel.textColor = UIColor(white: 0.45, alpha: 1)
        noResultLabel.textAlignment = .center
        noResultLabel.numberOfLines = 0
        let emptyStack = UIStackView(arrangedSubviews: [oopsLabel, noResultLabel])
        emptyStack.axis = .vertical
        emptyStack.spacing = 8
        emptyStack.translatesAutoresizingMaskIntoConstraints = false
        emptyView.addSubview(emptyStack)
        NSLayoutConstraint.activate([
            emptyStack.topAnchor.constraint(equalTo: emptyView.topAnchor),
            emptyStack.bottomAnchor.constraint(equalTo: emptyView.bottomAnchor),
            emptyStack.leadingAnchor.constraint(equalTo: emptyView.leadingAnchor),
            emptyStack.trailingAnchor.constraint(equalTo: emptyView.trailingAnchor),
        ])
        view.addSubview(emptyView)

        // Error view
        errorView = UIView()
        errorView.isHidden = true
        errorView.translatesAutoresizingMaskIntoConstraints = false
        let errTitle = UILabel()
        errTitle.text = "Ooops!"
        errTitle.font = .systemFont(ofSize: 30, weight: .bold)
        errTitle.textColor = .white
        errTitle.textAlignment = .center
        errorLabel = UILabel()
        errorLabel.textColor = UIColor(white: 0.5, alpha: 1)
        errorLabel.font = .systemFont(ofSize: 13)
        errorLabel.textAlignment = .center
        errorLabel.numberOfLines = 0
        let errStack = UIStackView(arrangedSubviews: [errTitle, errorLabel])
        errStack.axis = .vertical
        errStack.spacing = 8
        errStack.translatesAutoresizingMaskIntoConstraints = false
        errorView.addSubview(errStack)
        NSLayoutConstraint.activate([
            errStack.topAnchor.constraint(equalTo: errorView.topAnchor),
            errStack.bottomAnchor.constraint(equalTo: errorView.bottomAnchor),
            errStack.leadingAnchor.constraint(equalTo: errorView.leadingAnchor),
            errStack.trailingAnchor.constraint(equalTo: errorView.trailingAnchor),
        ])
        view.addSubview(errorView)

        NSLayoutConstraint.activate([
            loadingIndicator.centerXAnchor.constraint(equalTo: tableView.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: tableView.centerYAnchor),
            emptyView.centerXAnchor.constraint(equalTo: tableView.centerXAnchor),
            emptyView.centerYAnchor.constraint(equalTo: tableView.centerYAnchor),
            emptyView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            emptyView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
            errorView.centerXAnchor.constraint(equalTo: tableView.centerXAnchor),
            errorView.centerYAnchor.constraint(equalTo: tableView.centerYAnchor),
            errorView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            errorView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
        ])
    }

    // MARK: - Search

    private func triggerSearch() {
        searchTask?.cancel()
        guard let item = animeItem else { return }

        results = []
        filteredResults = []
        tableView.reloadData()
        emptyView.isHidden  = true
        errorView.isHidden  = true
        loadingIndicator.startAnimating()

        let ep  = currentEpisode
        let res = currentResolution

        searchTask = Task { @MainActor in
            do {
                let found = try await ExtensionService.shared.search(for: item, episode: ep, resolution: res)
                guard !Task.isCancelled else { return }
                self.results = found
                self.applyFilter()
                self.emptyView.isHidden = !self.filteredResults.isEmpty
            } catch {
                guard !Task.isCancelled else { return }
                self.errorLabel.text = error.localizedDescription
                self.errorView.isHidden  = false
                self.emptyView.isHidden  = true
                self.tableView.reloadData()
            }
            self.loadingIndicator.stopAnimating()
        }
    }

    private func applyFilter() {
        let query = filterText.lowercased()
        if query.isEmpty {
            filteredResults = results
        } else {
            filteredResults = results.filter { $0.title.lowercased().contains(query) }
        }
        tableView.reloadData()
        emptyView.isHidden = !filteredResults.isEmpty || loadingIndicator.isAnimating
    }

    // MARK: - Actions

    @objc private func filterChanged() {
        filterText = filterField.text ?? ""
        // Detect magnet link
        let text = filterText
        if text.lowercased().hasPrefix("magnet:") {
            let magnetResult = TorrentResult(title: "Magnet Link", link: text, hash: text,
                                             seeders: 0, leechers: 0,
                                             accuracy: "high", size: 0)
            confirmDownload(magnetResult)
            return
        }
        applyFilter()
    }

    @objc private func decrementEpisode() {
        let v = max(1, currentEpisode - 1)
        currentEpisode = v
        episodeField.text = "\(v)"
        triggerSearch()
    }

    @objc private func incrementEpisode() {
        let max = animeItem?.episodes ?? 9999
        let v = min(max, currentEpisode + 1)
        currentEpisode = v
        episodeField.text = "\(v)"
        triggerSearch()
    }

    @objc private func episodeFieldDone() {
        episodeField.resignFirstResponder()
        let v = max(1, Int(episodeField.text ?? "1") ?? 1)
        currentEpisode = v
        episodeField.text = "\(v)"
        triggerSearch()
    }

    @objc private func resolutionTapped() {
        let sheet = UIAlertController(title: "Resolution", message: nil, preferredStyle: .actionSheet)
        let labels = ["4K (2160p)", "1080p", "720p", "540p", "480p"]
        for (i, label) in labels.enumerated() {
            let res = resolutions[i]
            sheet.addAction(UIAlertAction(title: label, style: .default) { [weak self] _ in
                guard let self else { return }
                self.currentResolution = res
                let display = res == "2160" ? "4K" : "\(res)p"
                self.resolutionButton.setTitle("\(display) ▾", for: .normal)
                self.triggerSearch()
            })
        }
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        sheet.popoverPresentationController?.sourceView = resolutionButton
        present(sheet, animated: true)
    }

    @objc private func autoSelectTapped() {
        guard !filteredResults.isEmpty else { return }
        // Best: high accuracy first, then most seeders (mirrors filterAndSortResults)
        let best = filteredResults.sorted { a, b in
            let scoreA = a.accuracy == "high" ? 2 : a.accuracy == "medium" ? 1 : 0
            let scoreB = b.accuracy == "high" ? 2 : b.accuracy == "medium" ? 1 : 0
            if scoreA != scoreB { return scoreA > scoreB }
            return a.seeders > b.seeders
        }.first!
        confirmDownload(best)
    }

    // MARK: - Download

    private func confirmDownload(_ result: TorrentResult) {
        let sizeStr = formatBytes(result.size)
        let detail  = result.size > 0 ? "\nSize: \(sizeStr)  ·  ▲ \(result.seeders) seeders" : ""
        let alert = UIAlertController(title: "Download?",
                                       message: result.title + detail,
                                       preferredStyle: .actionSheet)
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
        let context = CoreDataService.sharedCoreDataService.mainQueueContext
        let entity  = Torrents(context: context)
        entity.torrentName        = result.title
        entity.torrentHashString  = result.hash
        entity.torrentDownloadURL = result.link
        entity.torrentSeeders     = NSNumber(value: result.seeders)
        entity.torrentLeechers    = NSNumber(value: result.leechers)
        entity.torrentSize        = NSNumber(value: Double(result.size) / 1_048_576)
        entity.torrentFlagTemp    = false
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
                        let e = UIAlertController(title: "Error", message: err.localizedDescription, preferredStyle: .alert)
                        e.addAction(UIAlertAction(title: "OK", style: .cancel))
                        self?.present(e, animated: true)
                    }
                }
            }
        }
    }
}

// MARK: - UITableViewDataSource + Delegate

extension ExtensionSearchViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { filteredResults.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: TorrentResultCell.reuseID,
                                                   for: indexPath) as! TorrentResultCell
        let result = filteredResults[indexPath.row]
        let configs = ExtensionService.shared.configs
        cell.configure(with: result, configs: configs)
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        confirmDownload(filteredResults[indexPath.row])
    }
}

// MARK: - UITextFieldDelegate

extension ExtensionSearchViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        if textField == episodeField { episodeFieldDone() }
        return true
    }
}

// MARK: - TorrentResultCell (mirrors each result card in SearchModal.svelte)

final class TorrentResultCell: UITableViewCell {
    static let reuseID = "TorrentResultCell"

    // BadgeCheck icon — top-left, mirrors <BadgeCheck /> absolute position
    private let badgeCheckView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFit
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    // Left icon area (80×80) — folder for batch/best/alt, file for single
    private let fileIconView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFit
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    // Right column
    private let groupLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 17, weight: .bold) // text-xl font-bold
        l.textColor = .white
        l.numberOfLines = 1
        return l
    }()

    // Extension icons (small, top-right of group row)
    private let extIconsStack: UIStackView = {
        let sv = UIStackView()
        sv.axis = .horizontal
        sv.spacing = 4
        sv.alignment = .center
        return sv
    }()

    // Simplified filename
    private let filenameLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 11)
        l.textColor = UIColor(white: 0.45, alpha: 1) // text-muted-foreground
        l.numberOfLines = 1
        l.lineBreakMode = .byTruncatingTail
        return l
    }()

    // Bottom row: type badge + seeders + size + date | tech terms
    private let bottomStack: UIStackView = {
        let sv = UIStackView()
        sv.axis = .horizontal
        sv.spacing = 6
        sv.alignment = .center
        return sv
    }()

    private let typeBadgeLabel = TorrentResultCell.makeBadgeLabel()
    private let seedersLabel = UILabel()
    private let sizeLabel = UILabel()

    // Tech terms stack (right side of bottom)
    private let termsStack: UIStackView = {
        let sv = UIStackView()
        sv.axis = .horizontal
        sv.spacing = 4
        sv.alignment = .center
        return sv
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = UIColor(white: 0.04, alpha: 1) // page bg
        selectionStyle = .none

        // Card: bg-neutral-950 (#111111), 8px radius, mb-2 p-3
        // Hayase px-4 sm:px-6 on the container → we use 16px card inset
        let card = UIView()
        card.backgroundColor = UIColor(red: 0.067, green: 0.067, blue: 0.067, alpha: 1)
        card.layer.cornerRadius = 8
        card.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(card)

        // BadgeCheck absolute top-left (mirrors absolute top-4 left-4)
        card.addSubview(badgeCheckView)

        // NOTE: Hayase shows the left Folder/File icon only on {#if $breakpoints.md} (≥768pt).
        // iOS phones are always <768pt wide, so we hide the left icon — matching Hayase mobile.
        // fileIconView is kept on the model for accuracy-badge toggle but not added to layout.

        // Group row: [groupLabel ········· extIconsStack]
        let spacer = UIView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let groupRow = UIStackView(arrangedSubviews: [groupLabel, spacer, extIconsStack])
        groupRow.axis = .horizontal
        groupRow.spacing = 8
        groupRow.alignment = .center

        // Bottom-left: type badge + seeders + size
        seedersLabel.font = .systemFont(ofSize: 11, weight: .medium)
        sizeLabel.font = .systemFont(ofSize: 11)
        sizeLabel.textColor = UIColor(white: 0.65, alpha: 1)

        let leftBottom = UIStackView(arrangedSubviews: [typeBadgeLabel, seedersLabel, sizeLabel])
        leftBottom.axis = .horizontal
        leftBottom.spacing = 6
        leftBottom.alignment = .center

        // Bottom-right: tech term badges
        let bottomSpacer = UIView()
        bottomSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let bottomRow = UIStackView(arrangedSubviews: [leftBottom, bottomSpacer, termsStack])
        bottomRow.axis = .horizontal
        bottomRow.spacing = 6
        bottomRow.alignment = .center

        // Content column (no left icon on mobile — matches Hayase mobile layout)
        let contentCol = UIStackView(arrangedSubviews: [groupRow, filenameLabel, bottomRow])
        contentCol.axis = .vertical
        contentCol.spacing = 4
        contentCol.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(contentCol)

        NSLayoutConstraint.activate([
            // Card: mb-2 (4pt top/bottom gap) + px-4 (16pt side inset matching Hayase container)
            card.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            card.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            card.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            card.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),

            // BadgeCheck — absolute top-left (mirrors top-4 left-4)
            badgeCheckView.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
            badgeCheckView.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
            badgeCheckView.widthAnchor.constraint(equalToConstant: 16),
            badgeCheckView.heightAnchor.constraint(equalToConstant: 16),

            // Content column: p-3 (12pt), pl-6 to clear the BadgeCheck (mirrors pl-6 md:pl-0)
            contentCol.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 36),
            contentCol.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
            contentCol.topAnchor.constraint(equalTo: card.topAnchor, constant: 10),
            contentCol.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -10),
            contentCol.heightAnchor.constraint(greaterThanOrEqualToConstant: 72),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    private static func makeBadgeLabel() -> UILabel {
        let l = UILabel()
        l.font = .systemFont(ofSize: 10, weight: .semibold)
        l.layer.cornerRadius = 4
        l.clipsToBounds = true
        l.layer.borderWidth = 1
        return l
    }

    func configure(with result: TorrentResult, configs: [String: ExtensionConfig]) {
        let title = result.title

        // ── BadgeCheck (mirrors accuracy === 'high' → green, 'medium' → muted, else hidden)
        switch result.accuracy {
        case "high":
            let cfg = UIImage.SymbolConfiguration(pointSize: 16, weight: .regular)
            let green = UIColor(red: 0.325, green: 0.855, blue: 0.200, alpha: 1) // #53da33
            badgeCheckView.image = UIImage(systemName: "checkmark.seal.fill", withConfiguration: cfg)?
                .withTintColor(green, renderingMode: .alwaysOriginal)
            badgeCheckView.isHidden = false
        case "medium":
            let cfg = UIImage.SymbolConfiguration(pointSize: 16, weight: .regular)
            badgeCheckView.image = UIImage(systemName: "checkmark.seal.fill", withConfiguration: cfg)?
                .withTintColor(UIColor(white: 0.2, alpha: 1), renderingMode: .alwaysOriginal)
            badgeCheckView.isHidden = false
        default:
            badgeCheckView.isHidden = true
        }

        // ── Card opacity for low accuracy (mirrors class:opacity-40={result.accuracy === 'low'})
        contentView.alpha = result.accuracy == "low" ? 0.4 : 1.0

        // ── File icon (folder=batch/best/alt, file=single, mirrors Folder/File icons)
        let yellow = UIColor(red: 1.0, green: 0.796, blue: 0.231, alpha: 1) // text-yellow-300
        let cfg = UIImage.SymbolConfiguration(pointSize: 40, weight: .regular)
        if let rtype = result.type, !rtype.isEmpty {
            // batch / best / alt → folder icon (yellow)
            fileIconView.image = UIImage(systemName: "folder.fill", withConfiguration: cfg)?
                .withTintColor(yellow.withAlphaComponent(0.8), renderingMode: .alwaysOriginal)
        } else {
            // single episode → file icon (muted)
            fileIconView.image = UIImage(systemName: "doc.fill", withConfiguration: cfg)?
                .withTintColor(UIColor(white: 0.4, alpha: 0.8), renderingMode: .alwaysOriginal)
        }

        // ── Release group
        groupLabel.text = TitleUtils.getGroup(from: title)

        // ── Extension icons (mirrors config.icon <img> top-right)
        extIconsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for extId in result.extensionIds.sorted() {
            if let config = configs[extId], let url = URL(string: config.icon) {
                let iv = UIImageView()
                iv.contentMode = .scaleAspectFit
                iv.widthAnchor.constraint(equalToConstant: 16).isActive = true
                iv.heightAnchor.constraint(equalToConstant: 16).isActive = true
                iv.layer.cornerRadius = 2
                iv.clipsToBounds = true
                iv.backgroundColor = UIColor(white: 0.15, alpha: 1)
                extIconsStack.addArrangedSubview(iv)
                URLSession.shared.dataTask(with: url) { data, _, _ in
                    if let data, let img = UIImage(data: data) {
                        DispatchQueue.main.async { iv.image = img }
                    }
                }.resume()
            }
        }

        // ── Simplified filename
        filenameLabel.text = TitleUtils.simplify(title)

        // ── Type badge (mirrors Best Release/Alt Release/Batch spans)
        if let rtype = result.type, !rtype.isEmpty {
            switch rtype.lowercased() {
            case "best":
                // background: #1d2d1e; border: #53da33; color: #53da33
                typeBadgeLabel.text = "  Best Release  "
                typeBadgeLabel.textColor = UIColor(red: 0.325, green: 0.855, blue: 0.200, alpha: 1)
                typeBadgeLabel.backgroundColor = UIColor(red: 0.114, green: 0.176, blue: 0.118, alpha: 1)
                typeBadgeLabel.layer.borderColor = UIColor(red: 0.325, green: 0.855, blue: 0.200, alpha: 1).cgColor
            case "alt":
                // background: #391d20; border: #c52d2d; color: #c52d2d
                typeBadgeLabel.text = "  Alt Release  "
                typeBadgeLabel.textColor = UIColor(red: 0.773, green: 0.176, blue: 0.176, alpha: 1)
                typeBadgeLabel.backgroundColor = UIColor(red: 0.220, green: 0.114, blue: 0.125, alpha: 1)
                typeBadgeLabel.layer.borderColor = UIColor(red: 0.773, green: 0.176, blue: 0.176, alpha: 1).cgColor
            default: // "batch"
                // background: #1d2031; border: #2d5ec5; color: #2d5ec5
                typeBadgeLabel.text = "  Batch  "
                typeBadgeLabel.textColor = UIColor(red: 0.176, green: 0.369, blue: 0.773, alpha: 1)
                typeBadgeLabel.backgroundColor = UIColor(red: 0.114, green: 0.125, blue: 0.192, alpha: 1)
                typeBadgeLabel.layer.borderColor = UIColor(red: 0.176, green: 0.369, blue: 0.773, alpha: 1).cgColor
            }
            typeBadgeLabel.isHidden = false
        } else {
            typeBadgeLabel.isHidden = true
        }

        // ── Seeders colour (green >20, yellow 5-20, red <5) — mirrors Hayase exactly
        let green20 = UIColor(red: 0.220, green: 0.600, blue: 0.200, alpha: 1) // text-green-600
        let red5    = UIColor(red: 0.700, green: 0.200, blue: 0.200, alpha: 1) // text-red-600
        let yellow5 = UIColor(red: 0.800, green: 0.600, blue: 0.100, alpha: 1) // text-yellow-600
        seedersLabel.text = "\(result.seeders) Seeders"
        seedersLabel.textColor = result.seeders > 20 ? green20 : (result.seeders < 5 ? red5 : yellow5)

        // ── Size
        sizeLabel.text = result.size > 0 ? formatBytes(result.size) : ""

        // ── Tech term badges (right side)
        termsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for term in TitleUtils.sanitise(title) {
            let l = UILabel()
            l.text = "  \(term.text)  "
            l.font = .systemFont(ofSize: 10, weight: .bold)
            // Use WCAG luminance to pick contrasting text colour (mirrors text-contrast-filter)
            l.textColor = term.color.isLight ? UIColor(white: 0.05, alpha: 1) : .white
            l.backgroundColor = term.color
            l.layer.cornerRadius = 4
            l.clipsToBounds = true
            termsStack.addArrangedSubview(l)
        }
    }
}

// MARK: - Byte formatter

private func formatBytes(_ bytes: Int64) -> String {
    let gb = 1_073_741_824.0; let mb = 1_048_576.0; let d = Double(bytes)
    if d >= gb { return String(format: "%.2f GB", d / gb) }
    if d >= mb { return String(format: "%.0f MB", d / mb) }
    if d > 0   { return String(format: "%.0f KB", d / 1024) }
    return ""
}

// MARK: - UIColor luminance helper (WCAG relative luminance for text contrast)

private extension UIColor {
    /// True when the colour is light enough that dark text is more readable.
    var isLight: Bool {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        // Linearise sRGB components
        func lin(_ c: CGFloat) -> CGFloat { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        let L = 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
        return L > 0.35
    }
}
