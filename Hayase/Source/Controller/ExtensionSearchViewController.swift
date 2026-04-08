// ExtensionSearchViewController.swift
// Ports SearchModal.svelte from hayase-app/interface exactly to native UIKit.
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
import CoreData

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
        return "No Group"
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
    /// When set to true before the VC is presented, the first search will
    /// automatically select the best torrent result and start playback.
    /// Used by MiniPlayerManager's restored `onEpisodeChange` to mirror the
    /// Hayase web interface's seamless episode transition.
    var shouldAutoSelectOnSearch = false

    // MARK: State
    private var results: [TorrentResult] = []
    private var filteredResults: [TorrentResult] = []
    private var filterText: String = ""
    private var isSearching = false
    private var currentEpisode: Int = 1
    private var currentResolution = "1080"
    private var searchTask: Task<Void, Never>?

    /// When true, `triggerSearch()` will auto-select the best result after
    /// the search completes — used by `handleEpisodeChangeFromPlayer()` to
    /// seamlessly transition to the next/prev episode without requiring the
    /// user to manually pick a torrent. Mirrors the Hayase web interface's
    /// automatic resolver in `mediahandler.svelte → playEpisode()`.
    private var autoSelectAfterSearch = false

    // MARK: Direct-to-player state (skip VideoListViewController)
    private var pendingVideoService: VideoService?
    private var pendingEntity: Torrents?
    private var pendingHud: UIAlertController?
    private var metadataObserver: NSObjectProtocol?
    private var metadataStatusTimer: Timer?

    // MARK: UI
    private var tableView: UITableView!
    private var loadingIndicator: UIActivityIndicatorView!
    private var headerView: UIView!

    // Banner
    private var bannerImageView: UIImageView!
    private var bannerGradientLayer: CAGradientLayer!

    // Controls
    private var filterField: UITextField!
    private var episodeField: UITextField!
    private var resolutionButton: UIButton!
    private var autoSelectButton: UIButton!
    /// Progress overlay on Auto Select button (mirrors web ProgressButton animation)
    private var progressOverlay: UIView!

    // Close button (mirrors web Dialog close X button)
    private var closeButton: UIButton!

    // State overlays
    private var emptyView: UIView!
    private var errorView: UIView!
    private var errorLabel: UILabel!
    private var skeletonView: UIStackView!

    private let resolutions = ["2160", "1080", "720", "540", "480"]

    /// Whether this VC is presented modally (formSheet on iPad, fullScreen on iPhone).
    /// When true, a close button is shown and dismiss() is used instead of pop.
    private var isPresentedModally: Bool {
        return navigationController == nil
    }

    // MARK: Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        currentEpisode = initialEpisode
        if shouldAutoSelectOnSearch {
            autoSelectAfterSearch = true
        }
        view.backgroundColor = .black
        navigationItem.largeTitleDisplayMode = .never

        // Round top corners only on iPad formSheet (matches web lg:rounded-t-xl = 12px).
        // On iPhone .fullScreen, no rounding (web has no rounding on mobile).
        if modalPresentationStyle == .formSheet
            && traitCollection.horizontalSizeClass == .regular {
            view.layer.cornerRadius = 12
            view.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
            view.clipsToBounds = true
        }

        setupHeader()
        setupTableView()
        setupStateViews()
        // Bring close button to front so it's not covered by controlsView/tableView
        if let cb = closeButton { view.bringSubviewToFront(cb) }
        triggerSearch()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Transparent nav bar so banner can extend to the very top of the screen
        if let nav = navigationController {
            nav.navigationBar.setBackgroundImage(UIImage(), for: .default)
            nav.navigationBar.shadowImage = UIImage()
            nav.navigationBar.isTranslucent = true
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // Restore opaque nav bar for the previous screen
        if let nav = navigationController {
            nav.navigationBar.setBackgroundImage(nil, for: .default)
            nav.navigationBar.shadowImage = nil
            nav.navigationBar.isTranslucent = true
        }
        // Clean up any pending direct-to-player state
        cleanupPendingState()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // bannerImageView fills its parent bannerView (160pt, full width).
        // The gradient must match the image view's bounds, updated each layout pass.
        if let iv = bannerImageView { bannerGradientLayer?.frame = iv.bounds }
        // Keep close button above all sibling views (state views, skeleton, etc.)
        if let cb = closeButton { view.bringSubviewToFront(cb) }
    }

    private func setupHeader() {
        // ── Root cause of previous banner-not-showing bug: ──────────────────────────────
        // A single headerView with translatesAutoresizingMaskIntoConstraints=false whose
        // height was determined only by inner-constraint chains can silently collapse to
        // height 0 when Auto Layout can't resolve the circular dependency.
        // Fix: TWO separate views, each with an explicit heightAnchor constant.
        //   bannerView  → 144pt (max-h-36, always visible, never 0)
        //   controlsView → 220pt (32+28+16+36+16+36+16+36+4)
        // tableView.top = controlsView.bottom → always correct.
        // ─────────────────────────────────────────────────────────────────────────────────

        // ── 1. BANNER VIEW — fixed 144pt (max-h-36), sticks at top ──────────────────────────────
        let bannerView = UIView()
        bannerView.clipsToBounds = true
        bannerView.backgroundColor = UIColor(white: 0.08, alpha: 1)
        bannerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bannerView)

        bannerImageView = UIImageView()
        bannerImageView.contentMode = .scaleAspectFill
        bannerImageView.clipsToBounds = true
        bannerImageView.alpha = 0.4          // Hayase: class='opacity-40'
        bannerImageView.translatesAutoresizingMaskIntoConstraints = false
        bannerView.addSubview(bannerImageView)

        // Gradient: bottom 70% fade to black/80 → transparent at top
        // Matches web: bg-gradient-to-t from-black/80 to-transparent, h-[70%]
        bannerGradientLayer = CAGradientLayer()
        bannerGradientLayer.colors = [UIColor.clear.cgColor,
                                       UIColor.black.withAlphaComponent(0.80).cgColor]
        bannerGradientLayer.locations = [0.3, 1.0]
        bannerImageView.layer.addSublayer(bannerGradientLayer)

        // Anime title — shown via the titleLabel in controlsView (not navigation bar)
        // Sits on the dark gradient zone → always readable. One line, truncated.

        // Fanart-first: fetch ani.zip Fanart (cached/deduped). Only if not found,
        // fall back to AniList banner. Single image load = no visible flicker/swap.
        let bannerFallback = animeItem?.bannerURL ?? animeItem?.coverURL
        if let anilistID = animeItem?.id {
            AnimeService.fetchFanartURL(anilistID: anilistID) { [weak self] fanartURL in
                let urlStr = fanartURL ?? bannerFallback
                guard let urlStr, let url = URL(string: urlStr) else { return }
                if let cached = SharedImageCache.shared.object(forKey: urlStr as NSString) {
                    DispatchQueue.main.async { self?.bannerImageView.image = cached }
                    return
                }
                URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
                    if let data, let img = UIImage(data: data) {
                        SharedImageCache.shared.setObject(img, forKey: urlStr as NSString)
                        DispatchQueue.main.async { self?.bannerImageView.image = img }
                    }
                }.resume()
            }
        } else if let urlStr = bannerFallback, let url = URL(string: urlStr) {
            URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
                if let data, let img = UIImage(data: data) {
                    DispatchQueue.main.async { self?.bannerImageView.image = img }
                }
            }.resume()
        }

        NSLayoutConstraint.activate([
            // bannerView: from very top of screen (under transparent nav bar)
            bannerView.topAnchor.constraint(equalTo: view.topAnchor),
            bannerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bannerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bannerView.heightAnchor.constraint(equalToConstant: 144),  // max-h-36 = 9rem = 144px

            // bannerImageView fills the bannerView entirely
            bannerImageView.topAnchor.constraint(equalTo: bannerView.topAnchor),
            bannerImageView.leadingAnchor.constraint(equalTo: bannerView.leadingAnchor),
            bannerImageView.trailingAnchor.constraint(equalTo: bannerView.trailingAnchor),
            bannerImageView.bottomAnchor.constraint(equalTo: bannerView.bottomAnchor),
        ])

        // Close button (X) — mirrors web Dialog close button (absolute right-4 top-4)
        // Shown when presented modally; dismisses the modal on tap.
        if isPresentedModally {
            closeButton = UIButton(type: .system)
            // Web: Cross2 size-4 (16px), data-[state=open]:text-muted-foreground, rounded-sm (2px)
            // data-[state=open]:bg-accent/70 → dark accent bg at 70% opacity
            let xCfg = UIImage.SymbolConfiguration(pointSize: 12, weight: .medium)
            closeButton.setImage(UIImage(systemName: "xmark", withConfiguration: xCfg), for: .normal)
            closeButton.tintColor = UIColor(white: 0.64, alpha: 1)  // text-muted-foreground
            // Web: bg-accent/70 — dark theme accent HSL(240, 3.7%, 15.9%) at 70% opacity
            closeButton.backgroundColor = UIColor(red: 0.153, green: 0.153, blue: 0.165, alpha: 0.7)
            closeButton.layer.cornerRadius = 4  // rounded-sm (web 2px, but 4px looks better at 36pt)
            closeButton.clipsToBounds = true
            closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
            closeButton.translatesAutoresizingMaskIntoConstraints = false
            // Ensure touches always reach the button
            closeButton.isExclusiveTouch = true
            view.addSubview(closeButton)

            // Web: absolute right-4 top-4 = 16px from dialog top/right.
            // On .formSheet (iPad), view.topAnchor IS the dialog top.
            // On .fullScreen (iPhone), we must use safeAreaLayoutGuide so the
            // button sits below the status bar / Dynamic Island.
            // Size: 36×36 ensures reliable touch target while keeping visual compact.
            let closeTopAnchor: NSLayoutConstraint
            if modalPresentationStyle == .formSheet {
                closeTopAnchor = closeButton.topAnchor.constraint(equalTo: view.topAnchor, constant: 16)
            } else {
                closeTopAnchor = closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8)
            }
            NSLayoutConstraint.activate([
                closeTopAnchor,
                closeButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
                closeButton.widthAnchor.constraint(equalToConstant: 36),
                closeButton.heightAnchor.constraint(equalToConstant: 36),
            ])
        }

        // ── 2. CONTROLS VIEW — EXPLICIT height 220pt, pinned to bannerView.bottom ───
        // height = 32 (top, web pt-8) + 28 (title) + 16 (space-y-4) + 36 (filter h-9) + 16 (space-y-4) + 36 (row h-9) + 16 (space-y-4) + 36 (button h-9) + 4 (bottom buffer) = 220
        // Matches web: pt-8 (32px) + space-y-4 (16px gaps) + title + filter + row + button
        let accentColor = Self.uiColor(fromHex: animeItem?.coverColor) ?? .white
        let contrastColor = Self.luminanceContrastColor(for: accentColor)

        // Web: px-4 sm:px-6 → 16px on mobile (<640px), 24px on ≥640px (iPad formSheet)
        let hPad: CGFloat = traitCollection.horizontalSizeClass == .regular ? 24 : 16

        let controlsView = UIView()
        controlsView.backgroundColor = .clear     // transparent — banner visible behind controls
        controlsView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(controlsView)

        // Anime title — matches web: text-2xl font-bold (1.5rem = 24px)
        let titleLabel = UILabel()
        titleLabel.text = animeItem?.titleEnglish ?? animeItem?.titleRomaji ?? ""
        titleLabel.font = .nunito(ofSize: 24, weight: .bold)
        titleLabel.textColor = .white
        titleLabel.numberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        controlsView.addSubview(titleLabel)

        // Filter field
        filterField = UITextField()
        filterField.placeholder = "Filter by text, or paste a magnet link or torrent file here to specify a torrent manually"
        filterField.attributedPlaceholder = NSAttributedString(
            string: filterField.placeholder ?? "",
            attributes: [.foregroundColor: UIColor(white: 0.45, alpha: 1)])
        filterField.backgroundColor = UIColor(white: 0.04, alpha: 1) // bg-background (nearly black)
        filterField.textColor = .white
        filterField.tintColor = .white
        filterField.font = .nunito(ofSize: 14)  // text-sm = 0.875rem = 14px
        filterField.autocorrectionType = .no
        filterField.autocapitalizationType = .none
        filterField.returnKeyType = .done
        filterField.layer.cornerRadius = 6  // rounded-md
        filterField.layer.borderWidth = 1
        filterField.layer.borderColor = UIColor(white: 0.16, alpha: 1).cgColor // border-input
        filterField.leftViewMode = .always
        let magIcon = UIImageView(image: UIImage(systemName: "magnifyingglass"))
        magIcon.tintColor = UIColor(white: 0.5, alpha: 1)
        magIcon.contentMode = .scaleAspectFit
        magIcon.frame = CGRect(x: 0, y: 0, width: 36, height: 16)  // pl-9 = 2.25rem = 36pt left padding for icon area
        filterField.leftView = magIcon
        filterField.delegate = self
        filterField.addTarget(self, action: #selector(filterChanged), for: .editingChanged)
        filterField.translatesAutoresizingMaskIntoConstraints = false
        controlsView.addSubview(filterField)

        // Episode field
        let epLabel = UILabel()
        epLabel.text = "Episode"
        epLabel.textColor = .white
        epLabel.font = .nunito(ofSize: 14)

        episodeField = UITextField()
        episodeField.text = "\(currentEpisode)"
        episodeField.keyboardType = .numberPad
        episodeField.backgroundColor = UIColor(white: 0.04, alpha: 1) // bg-background
        episodeField.textColor = .white
        episodeField.tintColor = .white
        episodeField.font = .nunito(ofSize: 14)  // text-sm = 14px
        episodeField.textAlignment = .center
        // Add left/right padding (web Input: px-3 = 12pt)
        episodeField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 1))
        episodeField.leftViewMode = .always
        episodeField.rightView = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 1))
        episodeField.rightViewMode = .always
        episodeField.layer.cornerRadius = 6  // rounded-md
        episodeField.layer.borderWidth = 1
        episodeField.layer.borderColor = UIColor(white: 0.16, alpha: 1).cgColor // border-input
        episodeField.delegate = self
        episodeField.translatesAutoresizingMaskIntoConstraints = false
        let toolbar = UIToolbar(); toolbar.sizeToFit()
        let decBtn = UIBarButtonItem(title: "−", style: .plain, target: self, action: #selector(decrementEpisode))
        let incBtn = UIBarButtonItem(title: "+", style: .plain, target: self, action: #selector(incrementEpisode))
        decBtn.tintColor = .white; incBtn.tintColor = .white
        let flex = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        let done = UIBarButtonItem(title: "Done", style: .done, target: self, action: #selector(episodeFieldDone))
        toolbar.items = [decBtn, incBtn, flex, done]
        toolbar.barStyle = .black; toolbar.tintColor = .white
        episodeField.inputAccessoryView = toolbar

        let epStack = UIStackView(arrangedSubviews: [epLabel, episodeField])
        epStack.axis = .horizontal; epStack.spacing = 8; epStack.alignment = .center

        // Resolution button
        let resLabel = UILabel()
        resLabel.text = "Resolution"; resLabel.textColor = .white
        resLabel.font = .nunito(ofSize: 14)

        resolutionButton = UIButton(type: .system)
        resolutionButton.setTitle("1080p ▾", for: .normal)
        resolutionButton.setTitleColor(.white, for: .normal)
        resolutionButton.titleLabel?.font = .nunito(ofSize: 14, weight: .medium)  // text-sm
        resolutionButton.backgroundColor = UIColor(white: 0.04, alpha: 1) // bg-background
        resolutionButton.layer.cornerRadius = 6  // rounded-md
        resolutionButton.layer.borderWidth = 1
        resolutionButton.layer.borderColor = UIColor(white: 0.16, alpha: 1).cgColor // border-border
        resolutionButton.contentEdgeInsets = UIEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)
        resolutionButton.addTarget(self, action: #selector(resolutionTapped), for: .touchUpInside)

        let resStack = UIStackView(arrangedSubviews: [resLabel, resolutionButton])
        resStack.axis = .horizontal; resStack.spacing = 8; resStack.alignment = .center

        let controlsRow = UIStackView(arrangedSubviews: [epStack, resStack])
        controlsRow.axis = .horizontal; controlsRow.distribution = .fillEqually
        controlsRow.spacing = 16; controlsRow.alignment = .center
        controlsRow.translatesAutoresizingMaskIntoConstraints = false
        controlsView.addSubview(controlsRow)

        // Auto Select button — matches web ProgressButton
        autoSelectButton = UIButton(type: .system)
        autoSelectButton.setTitle("Auto Select Torrent", for: .normal)
        autoSelectButton.setTitleColor(contrastColor, for: .normal)
        autoSelectButton.titleLabel?.font = .nunito(ofSize: 14, weight: .bold)  // text-sm font-bold
        autoSelectButton.backgroundColor = accentColor
        autoSelectButton.layer.cornerRadius = 6  // rounded-md
        autoSelectButton.clipsToBounds = true
        autoSelectButton.addTarget(self, action: #selector(autoSelectTapped), for: .touchUpInside)
        autoSelectButton.translatesAutoresizingMaskIntoConstraints = false
        controlsView.addSubview(autoSelectButton)

        // Progress overlay — mirrors web ProgressButton (bg-black/20, slides right over 5s)
        progressOverlay = UIView()
        progressOverlay.backgroundColor = UIColor.black.withAlphaComponent(0.2)
        progressOverlay.isUserInteractionEnabled = false
        progressOverlay.translatesAutoresizingMaskIntoConstraints = false
        autoSelectButton.addSubview(progressOverlay)
        NSLayoutConstraint.activate([
            progressOverlay.topAnchor.constraint(equalTo: autoSelectButton.topAnchor),
            progressOverlay.bottomAnchor.constraint(equalTo: autoSelectButton.bottomAnchor),
            progressOverlay.leadingAnchor.constraint(equalTo: autoSelectButton.leadingAnchor),
            progressOverlay.widthAnchor.constraint(equalTo: autoSelectButton.widthAnchor),
        ])
        // Initially hidden. At rest the overlay sits at .identity (covering the button);
        // the animation slides it right to reveal the accent colour underneath.
        progressOverlay.isHidden = true

        NSLayoutConstraint.activate([
            // controlsView: starts at safe area top (below status bar on fullScreen, top of sheet on formSheet), EXPLICIT height
            controlsView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            controlsView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            controlsView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            controlsView.heightAnchor.constraint(equalToConstant: 220),

            // Anime title (web: text-2xl font-bold, first child of pt-8 + space-y-4 container)
            titleLabel.topAnchor.constraint(equalTo: controlsView.topAnchor, constant: 32),
            titleLabel.leadingAnchor.constraint(equalTo: controlsView.leadingAnchor, constant: hPad),
            titleLabel.trailingAnchor.constraint(equalTo: controlsView.trailingAnchor, constant: -hPad),

            filterField.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 16),
            filterField.leadingAnchor.constraint(equalTo: controlsView.leadingAnchor, constant: hPad),
            filterField.trailingAnchor.constraint(equalTo: controlsView.trailingAnchor, constant: -hPad),
            filterField.heightAnchor.constraint(equalToConstant: 36),  // h-9 = 2.25rem = 36px

            controlsRow.topAnchor.constraint(equalTo: filterField.bottomAnchor, constant: 16),
            controlsRow.leadingAnchor.constraint(equalTo: controlsView.leadingAnchor, constant: hPad),
            controlsRow.trailingAnchor.constraint(equalTo: controlsView.trailingAnchor, constant: -hPad),
            controlsRow.heightAnchor.constraint(equalToConstant: 36),  // h-9 = 2.25rem = 36px

            episodeField.widthAnchor.constraint(greaterThanOrEqualToConstant: 80),  // flexible width, grows to fill
            episodeField.heightAnchor.constraint(equalToConstant: 36),  // h-9

            autoSelectButton.topAnchor.constraint(equalTo: controlsRow.bottomAnchor, constant: 16),
            autoSelectButton.leadingAnchor.constraint(equalTo: controlsView.leadingAnchor, constant: hPad),
            autoSelectButton.trailingAnchor.constraint(equalTo: controlsView.trailingAnchor, constant: -hPad),
            autoSelectButton.heightAnchor.constraint(equalToConstant: 36),  // h-9 = 2.25rem = 36px (web size='default')
        ])

        // headerView is the bottom edge that tableView.topAnchor pins to
        self.headerView = controlsView
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

    /// Compute perceived brightness and return dark or white for best contrast.
    /// Mirrors web's text-contrast CSS class: (R*299 + G*587 + B*114) / 1000, threshold 128.
    static func luminanceContrastColor(for color: UIColor) -> UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: nil)
        // Web formula: ((R*299 + G*587 + B*114) / 1000 - 128) * -1000
        // Simplified: brightness = R*0.299 + G*0.587 + B*0.114, threshold ≈ 0.502
        let brightness = r * 0.299 + g * 0.587 + b * 0.114
        return brightness > 0.502 ? UIColor(white: 0.07, alpha: 1) : .white
    }

    private func setupTableView() {
        tableView = UITableView(frame: .zero, style: .plain)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = .black
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
        // Loading spinner (shown during search alongside skeleton)
        loadingIndicator = UIActivityIndicatorView(style: .large)
        loadingIndicator.color = .white
        loadingIndicator.hidesWhenStopped = true
        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(loadingIndicator)

        // Skeleton loading cards (web shows 12 shimmer placeholders during search)
        skeletonView = UIStackView()
        skeletonView.axis = .vertical
        skeletonView.spacing = 8
        skeletonView.isHidden = true
        skeletonView.translatesAutoresizingMaskIntoConstraints = false
        let cardBg = UIColor(red: 0.067, green: 0.067, blue: 0.067, alpha: 1) // bg-neutral-950
        let shimmerColor = UIColor.white.withAlphaComponent(0.05)             // bg-primary/5
        for _ in 0..<12 {
            let card = UIView()
            card.backgroundColor = cardBg
            card.layer.cornerRadius = 6
            card.clipsToBounds = true
            card.translatesAutoresizingMaskIntoConstraints = false
            card.heightAnchor.constraint(equalToConstant: 106).isActive = true

            // Shimmer bars matching web skeleton: title bar, filename bar, two bottom bars
            let bar1 = UIView(); bar1.backgroundColor = shimmerColor; bar1.layer.cornerRadius = 4
            bar1.translatesAutoresizingMaskIntoConstraints = false
            card.addSubview(bar1)
            let bar2 = UIView(); bar2.backgroundColor = shimmerColor; bar2.layer.cornerRadius = 4
            bar2.translatesAutoresizingMaskIntoConstraints = false
            card.addSubview(bar2)
            let bar3 = UIView(); bar3.backgroundColor = shimmerColor; bar3.layer.cornerRadius = 4
            bar3.translatesAutoresizingMaskIntoConstraints = false
            card.addSubview(bar3)
            let bar4 = UIView(); bar4.backgroundColor = shimmerColor; bar4.layer.cornerRadius = 4
            bar4.translatesAutoresizingMaskIntoConstraints = false
            card.addSubview(bar4)

            NSLayoutConstraint.activate([
                // h-4 w-40 mt-2
                bar1.topAnchor.constraint(equalTo: card.topAnchor, constant: 20),
                bar1.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
                bar1.heightAnchor.constraint(equalToConstant: 16),
                bar1.widthAnchor.constraint(equalToConstant: 160),
                // h-2 w-28 mt-1
                bar2.topAnchor.constraint(equalTo: bar1.bottomAnchor, constant: 4),
                bar2.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
                bar2.heightAnchor.constraint(equalToConstant: 8),
                bar2.widthAnchor.constraint(equalToConstant: 112),
                // bottom left h-2 w-20
                bar3.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16),
                bar3.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
                bar3.heightAnchor.constraint(equalToConstant: 8),
                bar3.widthAnchor.constraint(equalToConstant: 80),
                // bottom right h-2 w-20
                bar4.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16),
                bar4.leadingAnchor.constraint(equalTo: bar3.trailingAnchor, constant: 8),
                bar4.heightAnchor.constraint(equalToConstant: 8),
                bar4.widthAnchor.constraint(equalToConstant: 80),
            ])

            skeletonView.addArrangedSubview(card)
        }

        let skeletonScroll = UIScrollView()
        skeletonScroll.translatesAutoresizingMaskIntoConstraints = false
        skeletonScroll.isUserInteractionEnabled = false
        skeletonScroll.addSubview(skeletonView)
        view.addSubview(skeletonScroll)

        // Empty view — "Ooops!" (mirrors {:else} case)
        // Web: text-4xl = 2.25rem = 36px, text-lg = 1.125rem = 18px
        emptyView = UIView()
        emptyView.isHidden = true
        emptyView.translatesAutoresizingMaskIntoConstraints = false
        let oopsLabel = UILabel()
        oopsLabel.text = "Ooops!"
        oopsLabel.font = .nunito(ofSize: 36, weight: .bold) // text-4xl
        oopsLabel.textColor = .white
        oopsLabel.textAlignment = .center
        let noResultLabel = UILabel()
        noResultLabel.text = "No results found.\nTry specifying a torrent manually by pasting a magnet link or torrent file into the filter bar."
        noResultLabel.font = .nunito(ofSize: 18) // text-lg
        noResultLabel.textColor = UIColor(white: 0.45, alpha: 1) // text-muted-foreground
        noResultLabel.textAlignment = .center
        noResultLabel.numberOfLines = 0
        let emptyStack = UIStackView(arrangedSubviews: [oopsLabel, noResultLabel])
        emptyStack.axis = .vertical
        emptyStack.spacing = 12 // mb-3 = 12px
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
        errTitle.font = .nunito(ofSize: 36, weight: .bold) // text-4xl
        errTitle.textColor = .white
        errTitle.textAlignment = .center
        errorLabel = UILabel()
        errorLabel.textColor = UIColor(white: 0.45, alpha: 1) // text-muted-foreground
        errorLabel.font = .nunito(ofSize: 18) // text-lg
        errorLabel.textAlignment = .center
        errorLabel.numberOfLines = 0
        let errStack = UIStackView(arrangedSubviews: [errTitle, errorLabel])
        errStack.axis = .vertical
        errStack.spacing = 12 // mb-3 = 12px
        errStack.translatesAutoresizingMaskIntoConstraints = false
        errorView.addSubview(errStack)
        NSLayoutConstraint.activate([
            errStack.topAnchor.constraint(equalTo: errorView.topAnchor),
            errStack.bottomAnchor.constraint(equalTo: errorView.bottomAnchor),
            errStack.leadingAnchor.constraint(equalTo: errorView.leadingAnchor),
            errStack.trailingAnchor.constraint(equalTo: errorView.trailingAnchor),
        ])
        view.addSubview(errorView)

        // Web: px-4 sm:px-6 → responsive horizontal padding for skeleton/state views
        let skelPad: CGFloat = traitCollection.horizontalSizeClass == .regular ? 24 : 16

        NSLayoutConstraint.activate([
            loadingIndicator.centerXAnchor.constraint(equalTo: tableView.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: tableView.centerYAnchor),

            // Skeleton fills the tableView area
            skeletonScroll.topAnchor.constraint(equalTo: tableView.topAnchor, constant: 8),
            skeletonScroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            skeletonScroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            skeletonScroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            skeletonView.topAnchor.constraint(equalTo: skeletonScroll.topAnchor),
            skeletonView.leadingAnchor.constraint(equalTo: skeletonScroll.leadingAnchor, constant: skelPad),
            skeletonView.trailingAnchor.constraint(equalTo: skeletonScroll.trailingAnchor, constant: -skelPad),
            skeletonView.widthAnchor.constraint(equalTo: skeletonScroll.widthAnchor, constant: -skelPad * 2),

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
        stopProgressAnimation()
        guard let item = animeItem else { return }

        results = []
        filteredResults = []
        tableView.reloadData()
        emptyView.isHidden  = true
        errorView.isHidden  = true
        // Show skeleton loading placeholders (matching web's 12 shimmer cards)
        skeletonView.isHidden = false
        skeletonView.superview?.isHidden = false
        startSkeletonPulse()

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
            self.skeletonView.isHidden = true
            self.skeletonView.superview?.isHidden = true
            self.stopSkeletonPulse()
            // If auto-select was requested (episode change from player),
            // automatically pick the best result and start playback.
            if self.autoSelectAfterSearch {
                self.autoSelectAfterSearch = false
                self.autoSelectTapped()
            } else if !self.filteredResults.isEmpty {
                // Start the 5-second progress bar animation
                // (mirrors web searchAutoSelect + startAnimation)
                self.startProgressAnimation()
            }
        }
    }

    private func applyFilter() {
        let query = filterText.lowercased()
        let filtered: [TorrentResult]
        if query.isEmpty {
            filtered = results
        } else {
            filtered = results.filter { $0.title.lowercased().contains(query) }
        }
        filteredResults = filterAndSortResults(filtered)
        tableView.reloadData()
        emptyView.isHidden = !filteredResults.isEmpty || !skeletonView.isHidden
    }

    /// Mirrors web filterAndSortResults() from SearchModal.svelte exactly.
    /// Ranks: low accuracy → 3, low seeders → 2, quality(best/alt with pref) → 0, normal → 1.
    /// Within rank 1: accuracy (high first), then by preference (size or seeders).
    private func filterAndSortResults(_ results: [TorrentResult]) -> [TorrentResult] {
        let preference = UserDefaults.standard.string(forKey: "pref_lookupPreference") ?? "quality"
        return results.sorted { a, b in
            func getRank(_ res: TorrentResult) -> Int {
                if res.accuracy == "low" { return 3 }
                // Web: if (downloaded.has(res.hash)) return 0
                // iOS doesn't track downloaded torrents yet — skip this rank
                if res.seeders <= 15 { return 2 }
                if (res.type == "best" || res.type == "alt") && preference == "quality" { return 0 }
                return 1
            }
            let rankA = getRank(a)
            let rankB = getRank(b)
            if rankA != rankB { return rankA < rankB }
            if rankA == 1 {
                let scoreA = a.accuracy == "high" ? 1 : 0
                let scoreB = b.accuracy == "high" ? 1 : 0
                if scoreA != scoreB { return scoreA > scoreB }
                // Sort by preference: size ascending or seeders descending
                if preference == "size" { return a.size < b.size }
                return b.seeders < a.seeders  // more seeders first
            }
            return false
        }
    }

    // MARK: - Skeleton pulse animation (mirrors web animate-pulse)

    private func startSkeletonPulse() {
        for card in skeletonView.arrangedSubviews {
            for bar in card.subviews {
                let anim = CABasicAnimation(keyPath: "opacity")
                anim.fromValue = 1.0
                anim.toValue = 0.5
                anim.duration = 2.0
                anim.autoreverses = true
                anim.repeatCount = .infinity
                anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                bar.layer.add(anim, forKey: "pulse")
            }
        }
    }

    private func stopSkeletonPulse() {
        for card in skeletonView.arrangedSubviews {
            for bar in card.subviews {
                bar.layer.removeAnimation(forKey: "pulse")
            }
        }
    }

    // MARK: - Actions

    @objc private func filterChanged() {
        stopProgressAnimation()
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
        stopProgressAnimation()
        guard !filteredResults.isEmpty else { return }
        // filteredResults is already sorted by filterAndSortResults() (matching web's
        // playBest which takes filterAndSortResults(...)[0])
        confirmDownload(filteredResults[0])
    }

    @objc private func closeTapped() {
        if isPresentedModally {
            // Dismiss any presented VC on top of us first (e.g. resolution picker),
            // then dismiss ourselves.
            if let presented = presentedViewController {
                presented.dismiss(animated: false) { [weak self] in
                    self?.dismiss(animated: true)
                }
            } else {
                dismiss(animated: true)
            }
        } else {
            navigationController?.popViewController(animated: true)
        }
    }

    // MARK: - Progress animation (mirrors web ProgressButton — 5s auto-fill bar)

    private var progressTimer: Timer?

    /// Start the 5-second progress bar animation on Auto Select button.
    /// When the animation completes, auto-selects the best result.
    /// Mirrors web `autoStart` + `animating` on ProgressButton.
    /// Only runs if pref_searchAutoSelect is enabled (matches web $settings.searchAutoSelect).
    private func startProgressAnimation() {
        guard !filteredResults.isEmpty else { return }
        // Check the searchAutoSelect setting (default true, matches web)
        let autoSelectEnabled = UserDefaults.standard.object(forKey: "pref_searchAutoSelect") as? Bool ?? true
        guard autoSelectEnabled else { return }
        progressOverlay.isHidden = false
        // Web: overlay starts at translateX(0%) covering the button, slides to translateX(100%) off-right.
        // The dark overlay progressively slides off, revealing the bright accent button from left to right.
        progressOverlay.transform = .identity
        UIView.animate(withDuration: 5.0, delay: 0, options: [.curveLinear]) { [weak self] in
            guard let self else { return }
            self.progressOverlay.transform = CGAffineTransform(translationX: self.autoSelectButton.bounds.width, y: 0)
        } completion: { [weak self] finished in
            guard let self, finished else { return }
            self.progressOverlay.isHidden = true
            self.progressOverlay.transform = .identity
            // Auto-select best result when animation completes (mirrors web animationend → onclick)
            if !self.filteredResults.isEmpty {
                self.confirmDownload(self.filteredResults[0])
            }
        }
    }

    private func stopProgressAnimation() {
        progressOverlay.layer.removeAllAnimations()
        progressOverlay.isHidden = true
        progressOverlay.transform = .identity
    }

    // MARK: - Download

    private func confirmDownload(_ result: TorrentResult) {
        // Skip confirmation — start streaming immediately.
        startDownload(result)
    }

    private func startDownload(_ result: TorrentResult) {
        let context = CoreDataService.sharedCoreDataService.mainQueueContext

        // Re-use an existing Torrents entity with the same info-hash so that
        // the linked Videos (and their videoPath keys) are preserved. This
        // keeps WatchProgressService lookups working across re-opens.
        let entity: Torrents
        if !result.hash.isEmpty {
            let existReq = NSFetchRequest<Torrents>(entityName: Torrents.entityName)
            existReq.predicate = NSPredicate(format: "torrentHashString == %@", result.hash)
            existReq.fetchLimit = 1
            if let existing = (try? context.fetch(existReq))?.first {
                entity = existing
            } else {
                entity = Torrents(context: context)
            }
        } else {
            entity = Torrents(context: context)
        }

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
            if let existing = (try? context.fetch(req))?.first as? Animes {
                entity.animes = existing
            } else {
                // Animes entity doesn't exist yet — create it from the
                // AnimeItem so the player can show the anime title and
                // episode count instead of falling back to the torrent name.
                let anime = Animes(context: context)
                anime.animeAnilistId      = NSNumber(value: animeItem.id)
                anime.animeTitleEnglish   = animeItem.titleEnglish
                anime.animeTitleJapanese  = animeItem.titleRomaji
                anime.animeTotalEps       = animeItem.episodes.map { NSNumber(value: $0) }
                anime.animeScore          = animeItem.score.map { NSNumber(value: $0) }
                anime.animeStatus         = animeItem.status
                anime.animeDescription    = animeItem.description
                anime.animeImgL           = animeItem.coverURL
                anime.animeImgM           = animeItem.coverURL
                entity.animes = anime
            }
        }
        try? context.save()

        let hud = UIAlertController(title: "Preparing playback…", message: "Adding torrent…", preferredStyle: .alert)
        hud.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in
            self?.cancelPendingPlayback()
        })
        present(hud, animated: true)

        // Go directly to the video player — skip the file list page.
        // waitForMetadataAndPlay creates a VideoService which internally calls
        // UpdateTorrentEntityInController — a single call is sufficient.
        // Calling it here first would cause a redundant double call that
        // triggers removeOtherTorrents twice, increasing the risk of
        // accidentally deleting the torrent's downloaded pieces.
        waitForMetadataAndPlay(entity: entity, hud: hud)
    }

    // MARK: - Direct-to-player flow

    /// Creates a VideoService, listens for metadata, and presents the player
    /// as soon as the target file is resolved — skipping VideoListViewController.
    private func waitForMetadataAndPlay(entity: Torrents, hud: UIAlertController) {
        let vs = VideoService(torrentEntity: entity)
        pendingVideoService = vs
        pendingEntity = entity
        pendingHud = hud

        // Listen for the notification that video CoreData entries are ready.
        metadataObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name(VideoService.LocalVideosDidUpdateNotification),
            object: nil, queue: .main) { [weak self] _ in
                self?.handlePendingMetadata()
        }

        // Update the HUD with live torrent status while waiting.
        metadataStatusTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self, let vs = self.pendingVideoService, let hud = self.pendingHud else { return }
            guard let snap = vs.torrentHandle?.snapshot else {
                hud.message = "Connecting to peers…"
                return
            }
            let peers = snap.numberOfPeers
            switch snap.state {
            case .downloadingMetadata:
                hud.message = peers > 0
                    ? "Fetching metadata… (\(peers) peer\(peers == 1 ? "" : "s"))"
                    : "Connecting to DHT and trackers…"
            case .downloading, .finished, .seeding:
                hud.message = "Preparing file list…"
            default:
                hud.message = "Connecting to peers…"
            }
        }

        // Kick off the torrent add + metadata fetch.
        vs.UpdateLocalVideo()
    }

    /// Called when VideoService posts LocalVideosDidUpdateNotification.
    /// Auto-resolves the target episode and presents the player directly.
    private func handlePendingMetadata() {
        guard let vs = pendingVideoService, let entity = pendingEntity else { return }

        // Check for errors.
        if let error = vs.lastError {
            let hud = pendingHud
            cleanupPendingState()
            hud?.dismiss(animated: false) { [weak self] in
                let alert = UIAlertController(title: "Error", message: error.localizedDescription, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "OK", style: .cancel))
                self?.present(alert, animated: true)
            }
            return
        }

        // Fetch video entities for this torrent.
        let context = CoreDataService.sharedCoreDataService.mainQueueContext
        let req = NSFetchRequest<Videos>(entityName: Videos.entityName)
        req.predicate = NSPredicate(format: "torrents == %@", entity)
        req.sortDescriptors = [NSSortDescriptor(key: "videoIndex", ascending: true),
                               NSSortDescriptor(key: "videoName", ascending: true)]
        let videos = (try? context.fetch(req)) ?? []
        guard !videos.isEmpty else { return } // Still waiting for metadata; will be called again.

        // Auto-resolve the target file.
        var targetVideo: Videos?
        var targetIndex: UInt = 0

        if videos.count == 1 {
            targetVideo = videos[0]
            targetIndex = UInt(targetVideo?.videoIndex?.intValue ?? 0)
        } else if let handle = vs.torrentHandle {
            let resolver = TorrentBatchResolver()
            if let match = resolver.resolve(files: handle.snapshot.files, targetEpisode: currentEpisode) {
                targetIndex = UInt(match.entry.index)
                targetVideo = videos.first { ($0.videoIndex?.intValue ?? -1) == Int(match.entry.index) }
            }
        }

        // Fallback to first video if no match found.
        if targetVideo == nil {
            targetVideo = videos.first
            targetIndex = UInt(targetVideo?.videoIndex?.intValue ?? 0)
        }

        guard let video = targetVideo else { return }

        // Select file for streaming and update path.
        vs.selectFileForStreaming(targetIndex)
        _ = vs.UpdateFilePathForFileIndex(targetIndex)

        // Clean up pending state before presenting.
        let hud = pendingHud
        cleanupPendingState()

        hud?.dismiss(animated: false) { [weak self] in
            guard let self else { return }
            // Close any existing mini-player before starting a new one.
            MiniPlayerManager.shared.close()
            let player = VideoPlayerViewController()
            player.videoEntity       = video
            player.torrentHandle     = vs.torrentHandle
            player.videoService      = vs
            player.fileIndex         = targetIndex
            player.anilistID         = Int(entity.animes?.animeAnilistId ?? 0)
            player.episodeNumber     = self.currentEpisode
            player.totalEpisodes     = self.animeItem?.episodes ?? 0
            player.allVideos         = videos
            player.currentVideoIndex = videos.firstIndex(of: video) ?? 0
            // Hayase web mediahandler.svelte playEpisode(): when the target
            // episode is not in the current batch, initiate a new search.
            player.onEpisodeChange   = { [weak self] episode in
                self?.handleEpisodeChangeFromPlayer(episode)
            }
            player.modalPresentationStyle = .fullScreen
            player.modalTransitionStyle   = .crossDissolve
            self.present(player, animated: true)
        }
    }

    private func cleanupPendingState() {
        if let observer = metadataObserver {
            NotificationCenter.default.removeObserver(observer)
            metadataObserver = nil
        }
        metadataStatusTimer?.invalidate()
        metadataStatusTimer = nil
        pendingVideoService = nil
        pendingEntity = nil
        pendingHud = nil
    }

    /// Cancels the in-progress direct-to-player flow and removes the
    /// torrent that was being prepared. Called when the user taps "Cancel"
    /// on the preparing-playback HUD.
    private func cancelPendingPlayback() {
        // Grab the pending torrent handle before cleanup nils the service.
        let handle = pendingVideoService?.torrentHandle
        cleanupPendingState()
        // Remove the torrent so it doesn't linger in the session (the user
        // explicitly cancelled, so the download is unwanted).
        if let handle {
            TorrentService.sharedTorrentService.safeRemoveTorrent(handle, deleteFiles: true)
        }
    }

    /// Called from the VideoPlayerViewController's `onEpisodeChange` callback
    /// when the user taps next/prev and the target episode is NOT in the
    /// current torrent batch. Dismisses the player, updates the episode, and
    /// triggers a new extension search — mirroring the Hayase web interface's
    /// `searchStore.set({ media, episode })` flow from mediahandler.svelte.
    private func handleEpisodeChangeFromPlayer(_ episode: Int) {
        // Close the mini-player if active (the old torrent's player).
        MiniPlayerManager.shared.close()
        // Dismiss the fullscreen player to return to this search screen.
        dismiss(animated: true) { [weak self] in
            guard let self else { return }
            // Update episode and trigger a fresh search with auto-select.
            self.currentEpisode = episode
            self.episodeField.text = "\(episode)"
            self.autoSelectAfterSearch = true
            self.triggerSearch()
        }
    }
}

// MARK: - UITableViewDataSource + Delegate

extension ExtensionSearchViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { filteredResults.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: TorrentResultCell.reuseID,
                                                   for: indexPath) as? TorrentResultCell else { return UITableViewCell() }
        guard indexPath.row < filteredResults.count else { return cell }
        let result = filteredResults[indexPath.row]
        let configs = ExtensionService.shared.configs
        let accent = Self.uiColor(fromHex: animeItem?.coverColor) ?? .white
        cell.configure(with: result, configs: configs, accent: accent)
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        stopProgressAnimation()
        guard indexPath.row < filteredResults.count else { return }
        confirmDownload(filteredResults[indexPath.row])
    }

    // Stop progress animation when user scrolls results (mirrors web on:pointermove/on:pointerenter)
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        stopProgressAnimation()
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

    /// Stored constraints for responsive horizontal padding (px-4 sm:px-6)
    private var cardLeadingConstraint: NSLayoutConstraint!
    private var cardTrailingConstraint: NSLayoutConstraint!
    /// Stored constraints for BadgeCheck responsive position (top-4 left-4 mobile, md:top-3 md:left-3 iPad)
    private var badgeTopConstraint: NSLayoutConstraint!
    private var badgeLeadingConstraint: NSLayoutConstraint!

    /// Card container — stored for highlight effects
    private let cardView: UIView = {
        let v = UIView()
        v.backgroundColor = UIColor(red: 0.067, green: 0.067, blue: 0.067, alpha: 1) // bg-neutral-950
        v.layer.cornerRadius = 6  // rounded-md (0.375rem = 6px)
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

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
        l.font = .nunito(ofSize: 20, weight: .bold) // text-xl font-bold (1.25rem = 20px)
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
        l.font = .nunito(ofSize: 11)
        l.textColor = UIColor(white: 0.64, alpha: 1) // text-muted-foreground HSL(240,5%,64.9%) ≈ #a1a1aa
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
    private let dateLabel = UILabel()
    // Dot separators between detail items (mirrors web .details span+span::before { content: '•' })
    private let dot1 = TorrentResultCell.makeDotSeparator()
    private let dot2 = TorrentResultCell.makeDotSeparator()
    private let dot3 = TorrentResultCell.makeDotSeparator()

    // Tech terms stack (right side of bottom, web: ml-2 = 8px between badges)
    private let termsStack: UIStackView = {
        let sv = UIStackView()
        sv.axis = .horizontal
        sv.spacing = 8  // ml-2 = 0.5rem = 8px
        sv.alignment = .center
        return sv
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .black // page bg
        selectionStyle = .none

        // Card: bg-neutral-950 (#111111), 6px radius, mb-2 p-3
        // Hayase px-4 sm:px-6 on the container → we use 16px card inset
        contentView.addSubview(cardView)

        // BadgeCheck absolute top-left (mirrors absolute top-4 left-4)
        cardView.addSubview(badgeCheckView)

        // NOTE: Hayase shows the left Folder/File icon only on {#if $breakpoints.md} (≥768pt).
        // iOS phones are always <768pt wide, so we hide the left icon — matching Hayase mobile.
        // fileIconView is kept on the model for accuracy-badge toggle but not added to layout.

        // Group row: [groupLabel ········· extIconsStack]
        // Web: group label has pl-6 (24px) on mobile to clear the BadgeCheck icon.
        // Use layoutMargins to indent group row content without affecting trailing position.
        let spacer = UIView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let groupRow = UIStackView(arrangedSubviews: [groupLabel, spacer, extIconsStack])
        groupRow.axis = .horizontal
        groupRow.spacing = 8
        groupRow.alignment = .center
        groupRow.layoutMargins = UIEdgeInsets(top: 0, left: 24, bottom: 0, right: 0) // pl-6 = 24px
        groupRow.isLayoutMarginsRelativeArrangement = true

        // Bottom-left: type badge + seeders + size + date (mirrors web details row)
        // Web: text-[.7rem] = 11.2px ≈ 11pt, normal weight. .details span+span::before for dots.
        seedersLabel.font = .nunito(ofSize: 11)  // normal weight (web inherits from parent)
        sizeLabel.font = .nunito(ofSize: 11)
        sizeLabel.textColor = UIColor.white.withAlphaComponent(0.8) // text-white/80
        dateLabel.font = .nunito(ofSize: 11)
        dateLabel.textColor = UIColor.white.withAlphaComponent(0.8) // text-white/80

        // [typeBadge • seeders • size • date] with dot separators
        let leftBottom = UIStackView(arrangedSubviews: [typeBadgeLabel, dot1, seedersLabel, dot2, sizeLabel, dot3, dateLabel])
        leftBottom.axis = .horizontal
        leftBottom.spacing = 0
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
        contentCol.distribution = .equalSpacing  // justify-between (web h-20 flex-col justify-between)
        contentCol.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(contentCol)

        // Card margins: responsive px-4 (16pt) on mobile, sm:px-6 (24pt) on iPad
        cardLeadingConstraint = cardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16)
        cardTrailingConstraint = cardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16)

        // BadgeCheck position: 16px on mobile (top-4 left-4), 12px on iPad (md:top-3 md:left-3)
        badgeTopConstraint = badgeCheckView.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 16)
        badgeLeadingConstraint = badgeCheckView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 16)

        NSLayoutConstraint.activate([
            // Card: mb-2 (4pt top/bottom gap) + responsive side inset
            cardView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            cardLeadingConstraint,
            cardTrailingConstraint,
            cardView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),

            // BadgeCheck — absolute top-left (mobile: top-4 left-4 = 16px, iPad md: top-3 left-3 = 12px)
            // size 1.2rem ≈ 19px. Position updated in configure() for responsive sizing.
            badgeTopConstraint,
            badgeLeadingConstraint,
            badgeCheckView.widthAnchor.constraint(equalToConstant: 19),
            badgeCheckView.heightAnchor.constraint(equalToConstant: 19),

            // Content column: p-3 (12pt) + pl-2 (8pt) = 20pt from card left
            // Group row uses layoutMargins.left=24 for the pl-6 indent to clear BadgeCheck
            contentCol.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 20),
            contentCol.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -12),
            contentCol.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 12),
            contentCol.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -12),
            contentCol.heightAnchor.constraint(greaterThanOrEqualToConstant: 80),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: Card press highlight (mirrors web select:ring-1 select:ring-custom select:bg-neutral-900 select:scale-[1.02])

    /// Accent color for ring highlight — set from coverColor in configure()
    private var accentColor: UIColor = .white

    override func setHighlighted(_ highlighted: Bool, animated: Bool) {
        super.setHighlighted(highlighted, animated: animated)
        applyHighlight(highlighted)
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)
        applyHighlight(selected)
    }

    private func applyHighlight(_ active: Bool) {
        let duration = active ? 0.1 : 0.25
        UIView.animate(withDuration: duration, delay: 0, options: [.allowUserInteraction, .beginFromCurrentState]) {
            if active {
                // ring-1 ring-custom
                self.cardView.layer.borderWidth = 1
                self.cardView.layer.borderColor = self.accentColor.cgColor
                // bg-neutral-900
                self.cardView.backgroundColor = UIColor(white: 0.1, alpha: 1)
                // scale-[1.02]
                self.cardView.transform = CGAffineTransform(scaleX: 1.02, y: 1.02)
                // shadow-lg
                self.cardView.layer.shadowColor = UIColor.black.cgColor
                self.cardView.layer.shadowOpacity = 0.4
                self.cardView.layer.shadowOffset = CGSize(width: 0, height: 4)
                self.cardView.layer.shadowRadius = 8
                // group-select/card:text-custom (group label turns accent color)
                self.groupLabel.textColor = self.accentColor
            } else {
                self.cardView.layer.borderWidth = 0
                self.cardView.layer.borderColor = nil
                self.cardView.backgroundColor = UIColor(red: 0.067, green: 0.067, blue: 0.067, alpha: 1)
                self.cardView.transform = .identity
                self.cardView.layer.shadowOpacity = 0
                self.groupLabel.textColor = .white
            }
        }
    }

    /// Creates a type badge label (Best Release / Alt Release / Batch).
    /// Web: rounded px-3 py-1 border text-[.7rem] — proper 12px/4px insets, 4px radius, 1px border.
    private static func makeBadgeLabel() -> PaddedLabel {
        let l = PaddedLabel()
        l.textInsets = UIEdgeInsets(top: 4, left: 12, bottom: 4, right: 12) // py-1 px-3
        l.font = .nunito(ofSize: 11)  // text-[.7rem] = 11.2px ≈ 11pt, normal weight
        l.layer.cornerRadius = 4      // rounded (0.25rem = 4px)
        l.clipsToBounds = true
        l.layer.borderWidth = 1
        return l
    }

    /// Creates a dot separator label matching web `.details span+span::before { content: '•' }`
    private static func makeDotSeparator() -> UILabel {
        let l = UILabel()
        l.text = " • "
        l.font = .nunito(ofSize: 6.4) // font-size: .4rem = 6.4px
        l.textColor = UIColor(red: 0.451, green: 0.451, blue: 0.451, alpha: 1) // #737373
        l.setContentHuggingPriority(.required, for: .horizontal)
        l.setContentCompressionResistancePriority(.required, for: .horizontal)
        return l
    }

    func configure(with result: TorrentResult, configs: [String: ExtensionConfig], accent: UIColor = .white) {
        let title = result.title
        accentColor = accent

        // Responsive card margins: px-4 (16pt) mobile, sm:px-6 (24pt) iPad
        let hPad: CGFloat = traitCollection.horizontalSizeClass == .regular ? 24 : 16
        cardLeadingConstraint.constant = hPad
        cardTrailingConstraint.constant = -hPad

        // Responsive BadgeCheck position: top-4 left-4 (16px) mobile, md:top-3 md:left-3 (12px) iPad
        let badgeInset: CGFloat = traitCollection.horizontalSizeClass == .regular ? 12 : 16
        badgeTopConstraint.constant = badgeInset
        badgeLeadingConstraint.constant = badgeInset

        // ── BadgeCheck (mirrors accuracy === 'high' → green, 'medium' → muted, else hidden)
        switch result.accuracy {
        case "high":
            let cfg = UIImage.SymbolConfiguration(pointSize: 19, weight: .regular) // size='1.2rem'
            let green = UIColor(red: 0.325, green: 0.855, blue: 0.200, alpha: 1) // #53da33
            badgeCheckView.image = UIImage(systemName: "checkmark.seal.fill", withConfiguration: cfg)?
                .withTintColor(green, renderingMode: .alwaysOriginal)
            badgeCheckView.isHidden = false
        case "medium":
            let cfg = UIImage.SymbolConfiguration(pointSize: 19, weight: .regular) // size='1.2rem'
            // Web: text-muted-foreground/20 — muted foreground (≈ white 0.65) at 20% opacity
            badgeCheckView.image = UIImage(systemName: "checkmark.seal.fill", withConfiguration: cfg)?
                .withTintColor(UIColor(white: 0.65, alpha: 0.2), renderingMode: .alwaysOriginal)
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
        // Web: rounded px-3 py-1 mr-0.5 border — PaddedLabel handles px-3 py-1 insets
        if let rtype = result.type, !rtype.isEmpty {
            switch rtype.lowercased() {
            case "best":
                // background: #1d2d1e; border: #53da33; color: #53da33
                typeBadgeLabel.text = "Best Release"
                typeBadgeLabel.textColor = UIColor(red: 0.325, green: 0.855, blue: 0.200, alpha: 1)
                typeBadgeLabel.backgroundColor = UIColor(red: 0.114, green: 0.176, blue: 0.118, alpha: 1)
                typeBadgeLabel.layer.borderColor = UIColor(red: 0.325, green: 0.855, blue: 0.200, alpha: 1).cgColor
            case "alt":
                // background: #391d20; border: #c52d2d; color: #c52d2d
                typeBadgeLabel.text = "Alt Release"
                typeBadgeLabel.textColor = UIColor(red: 0.773, green: 0.176, blue: 0.176, alpha: 1)
                typeBadgeLabel.backgroundColor = UIColor(red: 0.220, green: 0.114, blue: 0.125, alpha: 1)
                typeBadgeLabel.layer.borderColor = UIColor(red: 0.773, green: 0.176, blue: 0.176, alpha: 1).cgColor
            default: // "batch"
                // background: #1d2031; border: #2d5ec5; color: #2d5ec5
                typeBadgeLabel.text = "Batch"
                typeBadgeLabel.textColor = UIColor(red: 0.176, green: 0.369, blue: 0.773, alpha: 1)
                typeBadgeLabel.backgroundColor = UIColor(red: 0.114, green: 0.125, blue: 0.192, alpha: 1)
                typeBadgeLabel.layer.borderColor = UIColor(red: 0.176, green: 0.369, blue: 0.773, alpha: 1).cgColor
            }
            typeBadgeLabel.isHidden = false
        } else {
            typeBadgeLabel.isHidden = true
        }

        // ── Seeders colour (green >20, yellow 5-20, red <5) — exact Tailwind CSS v3 colours
        let green600 = UIColor(red: 0.086, green: 0.639, blue: 0.290, alpha: 1)  // text-green-600 #16a34a
        let red600   = UIColor(red: 0.863, green: 0.149, blue: 0.149, alpha: 1)  // text-red-600 #dc2626
        let yellow600 = UIColor(red: 0.792, green: 0.541, blue: 0.016, alpha: 1) // text-yellow-600 #ca8a04
        seedersLabel.text = "\(result.seeders) Seeders"
        seedersLabel.textColor = result.seeders > 20 ? green600 : (result.seeders < 5 ? red600 : yellow600)

        // ── Size (web: fastPrettyBytes uses base-1000 SI units)
        sizeLabel.text = result.size > 0 ? fastPrettyBytes(result.size) : ""

        // ── Date (web: since(new Date(result.date)) — relative time like "2 days ago")
        if let date = result.date {
            dateLabel.text = sinceDate(date)
            dateLabel.isHidden = false
        } else {
            dateLabel.text = ""
            dateLabel.isHidden = true
        }

        // ── Dot separator visibility: dot appears before a visible item when a prior item is also visible
        // Web: .details span+span::before means dots only appear between adjacent visible spans
        // UIStackView automatically skips hidden views, so dots naturally bridge visible neighbours
        let sizeVisible = result.size > 0
        sizeLabel.isHidden = !sizeVisible
        dot1.isHidden = typeBadgeLabel.isHidden  // dot between type badge and seeders
        dot2.isHidden = !sizeVisible              // dot between seeders and size
        dot3.isHidden = dateLabel.isHidden         // dot between size/seeders and date

        // ── Tech term badges (right side, reversed to match web flex-row-reverse)
        // Web: rounded px-3 py-1 ml-2 font-bold text-contrast-filter
        termsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for term in TitleUtils.sanitise(title).reversed() {
            let l = PaddedLabel()
            l.textInsets = UIEdgeInsets(top: 4, left: 12, bottom: 4, right: 12) // py-1 px-3
            l.text = term.text
            l.font = .nunito(ofSize: 11, weight: .bold)  // text-[.7rem] font-bold
            // Use Rec.601 brightness to pick contrasting text colour (mirrors web text-contrast-filter)
            l.textColor = term.color.isLight ? UIColor(white: 0.05, alpha: 1) : .white
            l.backgroundColor = term.color
            l.layer.cornerRadius = 4  // rounded
            l.clipsToBounds = true
            termsStack.addArrangedSubview(l)
        }
    }
}

// MARK: - Byte formatter (mirrors web fastPrettyBytes — base-1000 SI units)

private func fastPrettyBytes(_ bytes: Int64) -> String {
    let d = Double(bytes)
    let units = [" B", " kB", " MB", " GB", " TB"]
    if d.isNaN { return "0 B" }
    if d < 1 { return "\(d) B" }
    let exponent = min(Int(log(d) / log(1000)), units.count - 1)
    let value = d / pow(1000, Double(exponent))
    // Match web: Number(value.toFixed(1)) — drops trailing ".0"
    let formatted = (value.truncatingRemainder(dividingBy: 1) == 0)
        ? String(format: "%.0f", value)
        : String(format: "%.1f", value)
    return formatted + units[exponent]
}

// MARK: - Relative date (mirrors web since() from utils.ts)

private let sharedRelativeDateFormatter: RelativeDateTimeFormatter = {
    let f = RelativeDateTimeFormatter()
    f.unitsStyle = .full
    return f
}()

private func sinceDate(_ date: Date) -> String {
    return sharedRelativeDateFormatter.localizedString(for: date, relativeTo: Date())
}

// MARK: - UIColor luminance helper (mirrors web text-contrast-filter)

private extension UIColor {
    /// True when the colour is light enough that dark text is more readable.
    /// Mirrors web `.text-contrast-filter` which uses CSS `filter: invert(1) grayscale(1)
    /// brightness(1.2) contrast(9000)` — equivalent to the Rec.601 perceived-brightness
    /// formula: (R*299 + G*587 + B*114) / 1000, threshold 128 (i.e. 0.502 in 0–1).
    var isLight: Bool {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        let brightness = r * 0.299 + g * 0.587 + b * 0.114
        return brightness > 0.502
    }
}

// MARK: - PaddedLabel (proper px-3 py-1 insets matching web badge padding)

/// UILabel subclass that adds internal padding (web px-3 py-1) instead of space-character hacks.
private final class PaddedLabel: UILabel {
    var textInsets = UIEdgeInsets.zero

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: textInsets))
    }

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(width: size.width + textInsets.left + textInsets.right,
                      height: size.height + textInsets.top + textInsets.bottom)
    }

    override func textRect(forBounds bounds: CGRect, limitedToNumberOfLines numberOfLines: Int) -> CGRect {
        let insetBounds = bounds.inset(by: textInsets)
        return super.textRect(forBounds: insetBounds, limitedToNumberOfLines: numberOfLines)
    }
}
