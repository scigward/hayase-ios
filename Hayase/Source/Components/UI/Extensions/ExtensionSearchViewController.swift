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
import UniformTypeIdentifiers

private func torrentFileIndex<T: BinaryInteger>(from value: T?) -> UInt? {
    guard let value else { return nil }
    return UInt(exactly: value)
}

private func torrentFileIndex<T: BinaryInteger>(from value: T) -> UInt? {
    torrentFileIndex(from: Optional(value))
}

// MARK: - TitleExtraction helpers (mirrors getGroup / simplifyFilename / sanitiseTerms)

private enum TitleUtils {

    // MARK: Term colours (mirror termMapping in SearchModal.svelte)
    static let lime     = UIColor(red: 0.776, green: 0.925, blue: 0.345, alpha: 1) // #c6ec58
    static let blue     = UIColor(red: 0.047, green: 0.549, blue: 0.914, alpha: 1) // #0c8ce9
    static let orange   = UIColor(red: 0.965, green: 0.447, blue: 0.333, alpha: 1) // #f67255
    static let darkRed  = UIColor(red: 0.671, green: 0.106, blue: 0.192, alpha: 1) // #ab1b31
    static let yellow   = UIColor(red: 1.000, green: 0.796, blue: 0.231, alpha: 1) // #ffcb3b

    struct Term { let text: String; let color: UIColor }

    private static let termMapping: [String: Term] = {
        var mapping: [String: Term] = [:]
        func add(_ names: [String], _ text: String, _ color: UIColor) {
            for name in names { mapping[name] = Term(text: text, color: color) }
        }
        add(["5.1", "5.1CH"], "5.1", orange)
        add(["TRUEHD5.1"], "TrueHD 5.1", orange)
        add(["AAC", "AACX2", "AACX3", "AACX4"], "AAC", orange)
        add(["AC3"], "AC3", orange)
        add(["EAC3", "E-AC-3"], "EAC3", orange)
        add(["FLAC", "FLACX2", "FLACX3", "FLACX4"], "FLAC", orange)
        add(["VORBIS"], "Vorbis", orange)
        add(["DUALAUDIO", "DUAL AUDIO"], "Dual Audio", yellow)
        add(["10BIT", "10BITS", "10-BIT", "10-BITS", "HI10", "HI10P"], "10 Bit", blue)
        add(["HI444", "HI444P", "HI444PP"], "HI444", blue)
        add(["HEVC", "H265", "H.265", "X265"], "HEVC", blue)
        add(["AV1"], "AV1", blue)
        add(["BD", "BDRIP", "BLURAY", "BLU-RAY"], "BD", darkRed)
        add(["DVD5", "DVD9", "DVD-R2J", "DVDRIP", "DVD", "DVD-RIP", "R2DVD", "R2J", "R2JDVD", "R2JDVDRIP"], "DVD", darkRed)
        add(["MULTISUB", "MULTI-SUB", "MULTI SUB", "MULTISUBS", "MULTI-SUBS", "MULTI SUBS"], "Multi Sub", yellow)
        return mapping
    }()

    /// Match SearchModal.svelte's Anitomy categories, ordering, aliases and deduplication.
    static func sanitise(_ title: String) -> [Term] {
        let parser = Anitomy()
        parser.parse(title)
        var seen = Set<String>()
        var result: [Term] = []
        let resolution = parser.get(.videoResolution)
        if !resolution.isEmpty {
            result.append(Term(text: resolution, color: lime))
        }
        let categories: [ElementCategory] = [.videoTerm, .audioTerm, .source, .subtitles]
        for category in categories {
            for rawTerm in parser.getAll(category) {
                guard let term = termMapping[rawTerm.uppercased()], seen.insert(term.text).inserted else { continue }
                result.append(term)
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
    private var pendingPlayer: VideoPlayerViewController?
    private var isOpeningPlayer = false
    private var isDismissingForPlayback = false
    private var metadataObserver: NSObjectProtocol?
    private var isResolvingPendingMetadata = false

    // MARK: UI
    private var tableView: UITableView!
    private var loadingIndicator: UIActivityIndicatorView!
    private var headerView: UIView!

    // Banner
    private var bannerContainerView: UIView!
    private var bannerImageView: UIImageView!
    private var bannerGradientLayer: CAGradientLayer!

    // Controls
    private var filterField: UITextField!
    private var episodeField: UITextField!
    private var resolutionComboBox: ComboBox!
    private var autoSelectButton: UIButton!
    private var controlsRow: UIStackView!
    private var controlsHeightConstraint: NSLayoutConstraint!
    private var controlsRowHeightConstraint: NSLayoutConstraint!
    private var controlLeadingConstraints: [NSLayoutConstraint] = []
    private var controlTrailingConstraints: [NSLayoutConstraint] = []
    private var controlsAreWrapped = false
    private var minimumUnwrappedControlsWidth: CGFloat = 0
    private var equalInputWidths: NSLayoutConstraint!
    private var bannerUsesWideArtwork: Bool?
    private var bannerRequestGeneration = 0

    private func updateBanner(for width: CGFloat) {
        guard width > 0, bannerImageView != nil else { return }
        let wide = width >= 768
        guard bannerUsesWideArtwork != wide else { return }
        bannerUsesWideArtwork = wide
        bannerRequestGeneration += 1
        let generation = bannerRequestGeneration
        bannerImageView.image = nil
        let load: (String?) -> Void = { [weak self] source in
            guard let self, self.bannerRequestGeneration == generation,
                  let source, let url = URL(string: source) else { return }
            if let cached = SharedImageCache.shared.object(forKey: source as NSString) {
                self.bannerImageView.image = cached
                return
            }
            URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
                guard let data, let image = UIImage(data: data) else { return }
                SharedImageCache.shared.setObject(image, forKey: source as NSString)
                DispatchQueue.main.async {
                    guard let self, self.bannerRequestGeneration == generation else { return }
                    self.bannerImageView.image = image
                }
            }.resume()
        }
        if wide, let id = animeItem?.id {
            let fallback = resolvedBannerFallback()
            AniListClient.fetchFanartURL(anilistID: id) { source in
                DispatchQueue.main.async { load(source ?? fallback) }
            }
        } else {
            load(resolvedCoverFallback())
        }
    }
    /// Progress overlay on Auto Select button (mirrors web ProgressButton animation)
    private var progressOverlay: UIView!

    // Close button (mirrors web Dialog close X button)
    private var closeButton: UIButton!

    // State overlays
    private var emptyView: UIView!
    private var errorView: UIView!
    private var errorLabel: UILabel!
    private var skeletonView: UIStackView!
    private var skeletonLeadingConstraint: NSLayoutConstraint!
    private var skeletonTrailingConstraint: NSLayoutConstraint!
    private var skeletonWidthConstraint: NSLayoutConstraint!
    private var stateLeadingConstraints: [NSLayoutConstraint] = []
    private var stateTrailingConstraints: [NSLayoutConstraint] = []

    private let resolutionOptions: [(value: String, label: String)] = [
        ("2160", "2160p"),
        ("1080", "1080p"),
        ("720", "720p"),
        ("480", "480p"),
        ("", "Any"),
    ]

    /// Whether this VC is presented modally (custom dialog on iPad, fullScreen on iPhone).
    /// When true, a close button is shown and dismiss() is used instead of pop.
    private var isPresentedModally: Bool {
        return navigationController == nil
    }

    /// Presents over the current screen with the same dialog shell as the interface search modal.
    func prepareOverlayPresentation(from presenter: UIViewController?) {
        presenter?.definesPresentationContext = true
        modalPresentationStyle = .custom
        modalTransitionStyle = .crossDissolve
        transitioningDelegate = self
    }

    // MARK: Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        // `<svelte:window on:drop={handleTransfer} on:paste={handleTransfer}>`: a torrent file or its name dropped on the dialog
        view.addInteraction(UIDropInteraction(delegate: self))
        // server.downloaded is a store: results re-rank and re-mark as it changes.
        NotificationCenter.default.addObserver(self, selector: #selector(downloadedDidChange),
                                               name: WebTorrentDownloaded.didChange, object: nil)
        // The backend starts on demand here, so what it has cached is read before it is needed.
        WebTorrentDownloaded.shared.refresh()
        currentEpisode = initialEpisode
        if shouldAutoSelectOnSearch {
            autoSelectAfterSearch = true
        }
        let savedResolution = UserDefaults.standard.string(forKey: "pref_searchQuality") ?? currentResolution
        if resolutionOptions.contains(where: { $0.value == savedResolution }) {
            currentResolution = savedResolution
        }
        view.backgroundColor = UIColor.HayaseTheme.background
        navigationItem.largeTitleDisplayMode = .never

        // Corner rounding is handled by BottomDialogPresentationController on iPad
        // (.custom presentation) and not needed on iPhone (.fullScreen).

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

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // The search starts in viewDidLoad, before the view is on screen, and an animation
        // added to layers that are not in a window never runs.
        if !skeletonView.isHidden { startSkeletonPulse() }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // Restore opaque nav bar for the previous screen
        if let nav = navigationController {
            nav.navigationBar.setBackgroundImage(nil, for: .default)
            nav.navigationBar.shadowImage = nil
            nav.navigationBar.isTranslucent = true
        }
        // Route navigation removes this search view while metadata is still loading.
        // The pending player owns the coordinator until resolution or teardown.
        if pendingPlayer == nil { cleanupPendingState() }
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        // Switch the constraints before Auto Layout solves a newly compact width.
        updateControlsLayout(for: view.bounds.width)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateControlsLayout(for: view.bounds.width)
        updateBanner(for: view.bounds.width)
        updateSkeletonPadding(for: view.bounds.width)
        updateStatePadding(for: view.bounds.width)
        // Interface keeps the dark gradient as a sibling overlay, not inside the 40% image layer.
        if let container = bannerContainerView { bannerGradientLayer?.frame = container.bounds }
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
        //   controlsView → 236pt, or 288pt when the two inputs wrap.
        // tableView.top = controlsView.bottom → always correct.
        // ─────────────────────────────────────────────────────────────────────────────────

        // ── 1. BANNER VIEW — fixed 144pt (max-h-36), sticks at top ──────────────────────────────
        let bannerView = UIView()
        bannerView.clipsToBounds = true
        bannerContainerView = bannerView
        bannerView.backgroundColor = UIColor.HayaseTheme.background
        bannerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bannerView)

        bannerImageView = UIImageView()
        bannerImageView.contentMode = .scaleAspectFill
        bannerImageView.clipsToBounds = true
        // Banner passes its class through Load to both wrapper and image:
        // opacity-40 × opacity-40 = 0.16 effective image opacity.
        bannerImageView.alpha = 0.16
        bannerImageView.translatesAutoresizingMaskIntoConstraints = false
        bannerView.addSubview(bannerImageView)

        // Gradient: separate overlay over the 40% banner image, matching SearchModal.svelte.
        // The gradient itself must not inherit bannerImageView.alpha.
        bannerGradientLayer = CAGradientLayer()
        bannerGradientLayer.colors = [UIColor.clear.cgColor,
                                       UIColor.HayaseTheme.background.withAlphaComponent(0.80).cgColor]
        bannerGradientLayer.locations = [0.3, 1.0]
        bannerView.layer.addSublayer(bannerGradientLayer)

        // Anime title — shown via the titleLabel in controlsView (not navigation bar)
        // Sits on the dark gradient zone → always readable. One line, truncated.

        updateBanner(for: view.bounds.width)
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
            closeButton = HayaseCloseButton()
            closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
            closeButton.translatesAutoresizingMaskIntoConstraints = false
            // Ensure touches always reach the button
            closeButton.isExclusiveTouch = true
            view.addSubview(closeButton)

            // Web: absolute right-4 top-4, Cross2 size-4.
            NSLayoutConstraint.activate([
                closeButton.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),
                closeButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
                closeButton.widthAnchor.constraint(equalToConstant: 16),
                closeButton.heightAnchor.constraint(equalToConstant: 16),
            ])
        }

        // Controls overlay the banner: 32pt top + 32pt title + three 36pt
        // controls + three 16pt gaps + 16pt gap before the result viewport.
        // Matches web: pt-8 (32px) + space-y-4 (16px gaps) + title + filter + row + button
        let accentColor = Self.uiColor(fromHex: animeItem?.coverColor) ?? .white
        let contrastColor = Self.luminanceContrastColor(for: accentColor)

        // The web breakpoint follows the dialog viewport, not the device's full screen.
        let hPad: CGFloat = view.bounds.width >= 640 ? 24 : 16

        let controlsView = UIView()
        controlsView.backgroundColor = .clear     // transparent — banner visible behind controls
        controlsView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(controlsView)

        // Anime title — matches web: text-2xl font-bold (1.5rem = 24px)
        let titleLabel = UILabel()
        titleLabel.text = animeItem.map { AniListUtil.title(for: $0) } ?? ""
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
            attributes: [.foregroundColor: UIColor.HayaseTheme.mutedForeground.withAlphaComponent(0.5)])
        filterField.backgroundColor = UIColor.HayaseTheme.muted
        filterField.textColor = UIColor.HayaseTheme.foreground
        filterField.tintColor = UIColor.HayaseTheme.foreground
        filterField.font = .nunito(ofSize: 14)  // text-sm = 0.875rem = 14px
        filterField.autocorrectionType = .no
        filterField.autocapitalizationType = .none
        filterField.returnKeyType = .done
        filterField.layer.cornerRadius = 6  // rounded-md
        filterField.layer.borderWidth = 1
        filterField.layer.borderColor = UIColor.HayaseTheme.input.cgColor
        // Web: input pl-9, search glyph absolute left-3. Keep the text inset
        // and icon position independent of UITextField's leftView layout.
        filterField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 36, height: 36))
        filterField.leftViewMode = .always
        filterField.delegate = self
        filterField.addTarget(self, action: #selector(filterChanged), for: .editingChanged)
        filterField.translatesAutoresizingMaskIntoConstraints = false
        controlsView.addSubview(filterField)
        let magIcon = UIImageView(image: UIImage.hayaseIcon("search", pointSize: 16))
        magIcon.tintColor = UIColor.HayaseTheme.mutedForeground.withAlphaComponent(0.5)
        magIcon.contentMode = .scaleAspectFit
        magIcon.isUserInteractionEnabled = false
        magIcon.translatesAutoresizingMaskIntoConstraints = false
        controlsView.addSubview(magIcon)
        NSLayoutConstraint.activate([
            magIcon.leadingAnchor.constraint(equalTo: filterField.leadingAnchor, constant: 12),
            magIcon.centerYAnchor.constraint(equalTo: filterField.centerYAnchor),
            magIcon.widthAnchor.constraint(equalToConstant: 16),
            magIcon.heightAnchor.constraint(equalToConstant: 16),
        ])

        // Episode field
        let epLabel = UILabel()
        epLabel.text = "Episode"
        epLabel.textColor = .white
        epLabel.font = .nunito(ofSize: 14)

        episodeField = UITextField()
        episodeField.text = "\(currentEpisode)"
        episodeField.keyboardType = .numberPad
        episodeField.backgroundColor = UIColor(white: 0.04, alpha: 1) // bg-background
        episodeField.textColor = UIColor.HayaseTheme.foreground
        episodeField.tintColor = UIColor.HayaseTheme.foreground
        episodeField.font = .nunito(ofSize: 14)  // text-sm = 14px
        episodeField.textAlignment = .left
        // Add left/right padding (web Input: px-3 = 12pt)
        episodeField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 1))
        episodeField.leftViewMode = .always
        episodeField.rightView = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 1))
        episodeField.rightViewMode = .always
        episodeField.layer.cornerRadius = 6  // rounded-md
        episodeField.layer.borderWidth = 1
        episodeField.layer.borderColor = UIColor.HayaseTheme.input.cgColor
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

        resolutionComboBox = ComboBox()
        resolutionComboBox.layer.borderWidth = 1
        resolutionComboBox.layer.borderColor = UIColor.HayaseTheme.border.cgColor
        resolutionComboBox.configure(text: labelForResolution(currentResolution),
                                    placeholder: false)
        resolutionComboBox.addTarget(self, action: #selector(showResolutionPicker), for: .touchUpInside)
        resolutionComboBox.setContentHuggingPriority(.defaultLow, for: .horizontal)
        resolutionComboBox.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let resStack = UIStackView(arrangedSubviews: [resLabel, resolutionComboBox])
        resStack.axis = .horizontal; resStack.spacing = 8; resStack.alignment = .center

        let episodeWidth = epLabel.intrinsicContentSize.width + 8 + 128
        let resolutionWidth = resLabel.intrinsicContentSize.width + 8 + 128
        minimumUnwrappedControlsWidth = episodeWidth + resolutionWidth + 16

        controlsRow = UIStackView(arrangedSubviews: [epStack, resStack])
        controlsRow.axis = .horizontal; controlsRow.distribution = .fill
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
        controlsHeightConstraint = controlsView.heightAnchor.constraint(equalToConstant: 236)
        equalInputWidths = episodeField.widthAnchor.constraint(equalTo: resolutionComboBox.widthAnchor)
        controlsRowHeightConstraint = controlsRow.heightAnchor.constraint(equalToConstant: 36)
        controlLeadingConstraints = [
            titleLabel.leadingAnchor.constraint(equalTo: controlsView.leadingAnchor, constant: hPad),
            filterField.leadingAnchor.constraint(equalTo: controlsView.leadingAnchor, constant: hPad),
            controlsRow.leadingAnchor.constraint(equalTo: controlsView.leadingAnchor, constant: hPad),
            autoSelectButton.leadingAnchor.constraint(equalTo: controlsView.leadingAnchor, constant: hPad),
        ]
        controlTrailingConstraints = [
            titleLabel.trailingAnchor.constraint(equalTo: controlsView.trailingAnchor, constant: -hPad),
            filterField.trailingAnchor.constraint(equalTo: controlsView.trailingAnchor, constant: -hPad),
            controlsRow.trailingAnchor.constraint(equalTo: controlsView.trailingAnchor, constant: -hPad),
            autoSelectButton.trailingAnchor.constraint(equalTo: controlsView.trailingAnchor, constant: -hPad),
        ]
        NSLayoutConstraint.activate(controlLeadingConstraints + controlTrailingConstraints)
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
            // Presented as an overlay, so keep controls below the current safe area.
            controlsView.topAnchor.constraint(equalTo: view.topAnchor),
            controlsView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            controlsView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            controlsHeightConstraint,

            // Anime title (web: text-2xl font-bold, first child of pt-8 + space-y-4 container)
            titleLabel.topAnchor.constraint(equalTo: controlsView.topAnchor, constant: 32),
            titleLabel.heightAnchor.constraint(equalToConstant: 32), // text-2xl line-height

            filterField.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 16),
            filterField.heightAnchor.constraint(equalToConstant: 36),  // h-9 = 2.25rem = 36px

            controlsRow.topAnchor.constraint(equalTo: filterField.bottomAnchor, constant: 16),
            controlsRowHeightConstraint,

            episodeField.widthAnchor.constraint(greaterThanOrEqualToConstant: 128),  // web w-32 grow
            episodeField.heightAnchor.constraint(equalToConstant: 36),  // h-9
            resolutionComboBox.widthAnchor.constraint(greaterThanOrEqualToConstant: 128),
            resolutionComboBox.heightAnchor.constraint(equalToConstant: 36),
            // Both web inputs start at w-32 and receive the same flex-grow space.
            equalInputWidths,

            autoSelectButton.topAnchor.constraint(equalTo: controlsRow.bottomAnchor, constant: 16),
            autoSelectButton.heightAnchor.constraint(equalToConstant: 36),  // h-9 = 2.25rem = 36px (web size='default')
        ])

        // headerView is the bottom edge that tableView.topAnchor pins to
        self.headerView = controlsView
    }

    private func updateControlsLayout(for width: CGFloat) {
        guard width > 0, let controlsRow else { return }
        let padding: CGFloat = width >= 640 ? 24 : 16
        for constraint in controlLeadingConstraints where constraint.constant != padding {
            constraint.constant = padding
        }
        for constraint in controlTrailingConstraints where constraint.constant != -padding {
            constraint.constant = -padding
        }

        // SearchModal.svelte uses flex-wrap. Each control has a 128px input,
        // so a narrow dialog needs two 36px rows with the same 16px gap.
        let wrapped = width - 2 * padding < minimumUnwrappedControlsWidth
        guard wrapped != controlsAreWrapped else { return }
        controlsAreWrapped = wrapped
        equalInputWidths.isActive = !wrapped
        controlsRow.axis = wrapped ? .vertical : .horizontal
        controlsRow.alignment = wrapped ? .fill : .center
        controlsRowHeightConstraint.constant = wrapped ? 88 : 36
        controlsHeightConstraint.constant = wrapped ? 288 : 236
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

    private func resolvedBannerFallback() -> String? {
        animeItem?.bannerURL ?? youtubeThumbnailURL(for: animeItem?.trailerYouTubeID) ?? animeItem?.coverURL
    }

    private func resolvedCoverFallback() -> String? {
        animeItem?.coverURL ?? resolvedBannerFallback()
    }

    private func youtubeThumbnailURL(for id: String?) -> String? {
        guard let id, !id.isEmpty else { return nil }
        return "https://i.ytimg.com/vi/\(id)/maxresdefault.jpg"
    }

    private func setupTableView() {
        tableView = UITableView(frame: .zero, style: .plain)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = UIColor.HayaseTheme.background
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
        let cardBg = UIColor.HayaseTheme.card
        let shimmerColor = HayaseSkeleton.color
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
            let bar5 = UIView(); bar5.backgroundColor = shimmerColor; bar5.layer.cornerRadius = 4
            bar5.translatesAutoresizingMaskIntoConstraints = false
            card.addSubview(bar5)

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
                bar5.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16),
                bar5.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
                bar5.heightAnchor.constraint(equalToConstant: 8),
                bar5.widthAnchor.constraint(equalToConstant: 80),
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
        noResultLabel.textColor = UIColor.HayaseTheme.mutedForeground
        noResultLabel.textAlignment = .center
        noResultLabel.numberOfLines = 0
        let emptyStack = UIStackView(arrangedSubviews: [oopsLabel, noResultLabel])
        emptyStack.axis = .vertical
        emptyStack.spacing = 12 // mb-3 = 12px
        emptyStack.translatesAutoresizingMaskIntoConstraints = false
        emptyView.addSubview(emptyStack)
        NSLayoutConstraint.activate([
            emptyStack.centerYAnchor.constraint(equalTo: emptyView.centerYAnchor),
            emptyStack.leadingAnchor.constraint(equalTo: emptyView.leadingAnchor, constant: 20),
            emptyStack.trailingAnchor.constraint(equalTo: emptyView.trailingAnchor, constant: -20),
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
        errorLabel.textColor = UIColor.HayaseTheme.mutedForeground
        errorLabel.font = .nunito(ofSize: 18) // text-lg
        errorLabel.textAlignment = .center
        errorLabel.numberOfLines = 0
        let errStack = UIStackView(arrangedSubviews: [errTitle, errorLabel])
        errStack.axis = .vertical
        errStack.spacing = 12 // mb-3 = 12px
        errStack.translatesAutoresizingMaskIntoConstraints = false
        errorView.addSubview(errStack)
        NSLayoutConstraint.activate([
            errStack.centerYAnchor.constraint(equalTo: errorView.centerYAnchor),
            errStack.leadingAnchor.constraint(equalTo: errorView.leadingAnchor, constant: 20),
            errStack.trailingAnchor.constraint(equalTo: errorView.trailingAnchor, constant: -20),
        ])
        view.addSubview(errorView)

        // Web: px-4 sm:px-6 → responsive horizontal padding for skeleton/state views
        let skelPad: CGFloat = (view.window?.bounds.width ?? UIScreen.main.bounds.width) >= 640 ? 24 : 16
        skeletonLeadingConstraint = skeletonView.leadingAnchor.constraint(equalTo: skeletonScroll.leadingAnchor, constant: skelPad)
        skeletonTrailingConstraint = skeletonView.trailingAnchor.constraint(equalTo: skeletonScroll.trailingAnchor, constant: -skelPad)
        skeletonWidthConstraint = skeletonView.widthAnchor.constraint(equalTo: skeletonScroll.widthAnchor, constant: -skelPad * 2)
        stateLeadingConstraints = [
            emptyView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: skelPad),
            errorView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: skelPad),
        ]
        stateTrailingConstraints = [
            emptyView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -skelPad),
            errorView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -skelPad),
        ]
        NSLayoutConstraint.activate(stateLeadingConstraints + stateTrailingConstraints)

        NSLayoutConstraint.activate([
            loadingIndicator.centerXAnchor.constraint(equalTo: tableView.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: tableView.centerYAnchor),

            // Skeleton fills the tableView area
            skeletonScroll.topAnchor.constraint(equalTo: tableView.topAnchor, constant: 8),
            skeletonScroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            skeletonScroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            skeletonScroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            skeletonView.topAnchor.constraint(equalTo: skeletonScroll.topAnchor),
            skeletonLeadingConstraint,
            skeletonTrailingConstraint,
            skeletonWidthConstraint,

            emptyView.topAnchor.constraint(equalTo: tableView.topAnchor, constant: 8),
            emptyView.heightAnchor.constraint(equalToConstant: 320),
            errorView.topAnchor.constraint(equalTo: tableView.topAnchor, constant: 8),
            errorView.heightAnchor.constraint(equalToConstant: 320),
        ])
    }

    private func updateSkeletonPadding(for width: CGFloat) {
        guard width > 0, skeletonLeadingConstraint != nil else { return }
        let padding: CGFloat = width >= 640 ? 24 : 16
        if skeletonLeadingConstraint.constant != padding {
            skeletonLeadingConstraint.constant = padding
            skeletonTrailingConstraint.constant = -padding
            skeletonWidthConstraint.constant = -padding * 2
        }
    }

    private func updateStatePadding(for width: CGFloat) {
        guard width > 0 else { return }
        let padding: CGFloat = width >= 640 ? 24 : 16
        for constraint in stateLeadingConstraints where constraint.constant != padding {
            constraint.constant = padding
        }
        for constraint in stateTrailingConstraints where constraint.constant != -padding {
            constraint.constant = -padding
        }
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
            var hasStreamedResults = false
            do {
                let found = try await ExtensionService.shared.search(for: item, episode: ep, resolution: res) { [weak self] partial in
                    guard let self, !Task.isCancelled else { return }
                    hasStreamedResults = true
                    self.results = partial
                    self.applyFilter()
                    self.finishSearchLoading()
                }
                guard !Task.isCancelled else { return }
                self.results = found
                self.applyFilter()
                self.emptyView.isHidden = !self.filteredResults.isEmpty
            } catch {
                guard !Task.isCancelled else { return }
                if hasStreamedResults, !self.results.isEmpty {
                    print("ExtensionSearchViewController: partial search completed with error: \(error)")
                } else {
                    self.errorLabel.text = error.localizedDescription
                    self.errorView.isHidden  = false
                    self.emptyView.isHidden  = true
                    self.tableView.reloadData()
                }
            }
            self.finishSearchLoading()
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

    @objc private func downloadedDidChange() {
        guard isViewLoaded, !results.isEmpty else { return }
        applyFilter()
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

    private func finishSearchLoading() {
        skeletonView.isHidden = true
        skeletonView.superview?.isHidden = true
        stopSkeletonPulse()
    }

    /// Mirrors web filterAndSortResults() from SearchModal.svelte exactly.
    /// Ranks: low accuracy → 3, downloaded → 0, low seeders → 2, quality(best/alt with pref) → 0, normal → 1.
    /// Within rank 1: accuracy (high first), then by preference (size or seeders).
    private func filterAndSortResults(_ results: [TorrentResult]) -> [TorrentResult] {
        let preference = Settings.lookupPreference
        return results.sorted { a, b in
            func getRank(_ res: TorrentResult) -> Int {
                if res.accuracy == "low" { return 3 }
                if WebTorrentDownloaded.shared.contains(res.hash) { return 0 }
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
                HayaseSkeleton.startPulse(on: bar)
            }
        }
    }

    private func stopSkeletonPulse() {
        for card in skeletonView.arrangedSubviews {
            for bar in card.subviews {
                HayaseSkeleton.stopPulse(on: bar)
            }
        }
    }

    // MARK: - Actions

    @objc private func filterChanged() {
        stopProgressAnimation()
        filterText = filterField.text ?? ""
        // `$: findTorrentIdentifiers(inputText)`: a magnet link, an info hash or a .torrent address names the torrent
        if ParseTorrent.isIdentifier(filterText), playIdentifier(filterText) { return }
        applyFilter()
    }

    @objc private func decrementEpisode() {
        let v = max(0, currentEpisode - 1)
        currentEpisode = v
        episodeField.text = "\(v)"
        triggerSearch()
    }

    @objc private func incrementEpisode() {
        let v = min(65536, currentEpisode + 1)
        currentEpisode = v
        episodeField.text = "\(v)"
        triggerSearch()
    }

    @objc private func episodeFieldDone() {
        episodeField.resignFirstResponder()
        let v = max(0, Int(episodeField.text ?? "") ?? currentEpisode)
        currentEpisode = v
        episodeField.text = "\(v)"
        triggerSearch()
    }

    private func labelForResolution(_ value: String) -> String {
        resolutionOptions.first(where: { $0.value == value })?.label ?? "Any"
    }

    @objc private func showResolutionPicker() {
        let picker = CommandPopoverViewController(
            title: "Resolution",
            placeholder: "Any",
            groups: [CommandGroup(options: resolutionOptions.map {
                CommandOption(value: $0.value, label: $0.label)
            })],
            selectedValues: [currentResolution],
            allowsMultiple: false,
            sourceView: resolutionComboBox
        )
        picker.onSelectionChanged = { [weak self] values in
            guard let self, let value = values.first else { return }
            guard value != self.currentResolution else { return }
            self.currentResolution = value
            Settings.searchQuality = value
            self.resolutionComboBox.configure(text: self.labelForResolution(value),
                                              placeholder: false)
            self.triggerSearch()
        }
        present(picker, animated: true)
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
        let autoSelectEnabled = Settings.searchAutoSelect
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

    // MARK: - server.playIdentifier

    /// `findTorrentIdentifiers`: plays the torrent a magnet link, an info hash or the address of a .torrent
    /// file names. False when the text does not name one.
    @discardableResult
    private func playIdentifier(_ identifier: String) -> Bool {
        guard animeItem != nil, !isOpeningPlayer else { return false }
        let lowered = identifier.lowercased()
        if lowered.hasPrefix("magnet:") {
            guard let hash = ParseTorrent.infoHash(magnet: identifier) else { return false }
            confirmDownload(TorrentResult(title: hash, link: identifier, hash: hash))
            return true
        }
        if let hash = ParseTorrent.infoHash(hash: identifier) {
            confirmDownload(TorrentResult(title: hash, link: "magnet:?xt=urn:btih:" + hash, hash: hash))
            return true
        }
        guard lowered.hasSuffix(".torrent"), let url = URL(string: identifier) else { return false }
        // parse-torrent reads the file for its hash
        if url.isFileURL {
            guard let data = try? Data(contentsOf: url) else { return false }
            playTorrentFile(data, name: url.lastPathComponent)
            return true
        }
        guard url.scheme?.lowercased() == "http" || url.scheme?.lowercased() == "https" else { return false }
        URLSession.shared.dataTask(with: url) { [weak self] data, response, _ in
            guard let data, !data.isEmpty,
                  (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true else { return }
            DispatchQueue.main.async { self?.playTorrentFile(data, name: url.lastPathComponent) }
        }.resume()
        return true
    }

    /// `server.playIdentifier(new Uint8Array(await file.arrayBuffer()), media, episode)`
    private func playTorrentFile(_ data: Data, name: String?) {
        guard animeItem != nil, !isOpeningPlayer, let hash = ParseTorrent.infoHash(file: data) else { return }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("HayaseTorrents", isDirectory: true)
        guard (try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)) != nil else { return }
        let file = folder.appendingPathComponent(hash + ".torrent")
        guard (try? data.write(to: file)) != nil else { return }
        confirmDownload(TorrentResult(title: name ?? hash, link: file.absoluteString, hash: hash))
    }

    private func confirmDownload(_ result: TorrentResult) {
        guard !isOpeningPlayer else { return }
        isOpeningPlayer = true
        // Skip confirmation — start streaming immediately.
        startDownload(result)
    }

    private func startDownload(_ result: TorrentResult) {
        let context = CoreDataService.sharedCoreDataService.mainQueueContext

        // Re-use an existing Torrents entity with the same info-hash so that
        // the linked Videos are preserved across re-opens.
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

        MiniPlayerManager.shared.close()
        let player = VideoPlayerViewController()
        pendingPlayer = player
        player.beginMetadataLoading(owner: self)
        player.onCancelMetadataLoading = { [weak self] in self?.cleanupPendingState() }
        let host = hayaseTabIndex
        let openPlayer = { [self, player] in
            isOpeningPlayer = false
            Router.shared.navigateToPlayer(player, hostTabIndex: host)
        }
        // SearchModal.svelte starts metadata immediately, closes with flyAndScale,
        // then awaits sleep(300) before goto('/app/player').
        waitForMetadataAndPlay(entity: entity)
        dismissSearchForPlayback(completion: openPlayer)
    }

    private func dismissSearchForPlayback(completion: @escaping () -> Void) {
        view.endEditing(true)
        view.isUserInteractionEnabled = false
        isDismissingForPlayback = true
        let began = CACurrentMediaTime()
        let completeAfterWebDelay = { [weak self] in
            self?.isDismissingForPlayback = false
            let remaining = max(0, 0.3 - (CACurrentMediaTime() - began))
            DispatchQueue.main.asyncAfter(deadline: .now() + remaining, execute: completion)
        }

        guard presentingViewController != nil else {
            completeAfterWebDelay()
            return
        }
        dismiss(animated: !UIAccessibility.isReduceMotionEnabled, completion: completeAfterWebDelay)
    }

    // The route changes once, before fetching. The same player is hydrated on completion.
    private func waitForMetadataAndPlay(entity: Torrents) {
        let vs = VideoService(torrentEntity: entity, episode: currentEpisode)
        vs.media = animeItem
        pendingVideoService = vs
        pendingEntity = entity
        metadataObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name(VideoService.LocalVideosDidUpdateNotification),
            object: nil, queue: .main) { [weak self] _ in
                self?.handlePendingMetadata()
        }
        vs.UpdateLocalVideo()
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) { [weak self, weak vs] in
            guard let self, let vs, self.pendingVideoService === vs else { return }
            let player = self.pendingPlayer
            self.cleanupPendingState()
            let error = vs.lastError ?? NSError(domain: "Hayase.Metadata", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Could not fetch torrent metadata from peers."])
            player?.finishMetadataLoading(error: error)
        }
    }


    /// Called when VideoService posts LocalVideosDidUpdateNotification.
    /// Auto-resolves the target episode and presents the player directly.
    private func handlePendingMetadata() {
        guard let vs = pendingVideoService, let entity = pendingEntity else { return }
        guard !isResolvingPendingMetadata else { return }

        // Check for errors.
        if let error = vs.lastError {
            let player = pendingPlayer
            cleanupPendingState()
            player?.finishMetadataLoading(error: error)
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
            targetIndex = torrentFileIndex(from: targetVideo?.videoIndex?.intValue) ?? 0
        } else {
            let resolver = TorrentBatchResolver()
            if let animeItem {
                isResolvingPendingMetadata = true
                resolver.resolveItemsByAnime(from: videos,
                                             targetEpisode: currentEpisode,
                                             targetMedia: animeItem,
                                             name: { $0.videoName }) { [weak self] result in
                    guard let self else { return }
                    self.isResolvingPendingMetadata = false
                    let resolvedVideo = result.target?.item
                    let resolvedIndex = torrentFileIndex(from: resolvedVideo?.videoIndex?.intValue) ?? 0
                    self.presentPendingVideo(vs: vs,
                                             entity: entity,
                                             targetVideo: resolvedVideo,
                                             targetIndex: resolvedIndex,
                                             videos: videos,
                                             resolvedVideoFiles: result.resolvedFiles)
                }
                return
            }

            targetVideo = TorrentBatchResolver.selectByFilename(from: videos, targetEpisode: currentEpisode) { $0.videoName }
            targetIndex = torrentFileIndex(from: targetVideo?.videoIndex?.intValue) ?? 0
        }

        presentPendingVideo(vs: vs,
                             entity: entity,
                             targetVideo: targetVideo,
                             targetIndex: targetIndex,
                             videos: videos,
                             resolvedVideoFiles: [])
    }

    private func presentPendingVideo(vs: VideoService,
                                     entity: Torrents,
                                     targetVideo: Videos?,
                                     targetIndex: UInt,
                                     videos: [Videos],
                                     resolvedVideoFiles: [TorrentBatchResolver.ResolvedItem<Videos>] = []) {
        guard pendingVideoService === vs else { return }
        var targetVideo = targetVideo
        var targetIndex = targetIndex

        // Fallback to first video if no match found.
        if targetVideo == nil {
            targetVideo = videos.first
            if let value = targetVideo?.videoIndex?.intValue, value >= 0 {
                targetIndex = UInt(value)
            } else {
                targetIndex = 0
            }
        }

        guard let video = targetVideo else { return }

        // Update the path of the file.
        _ = vs.UpdateFilePathForFileIndex(targetIndex)

        // Clean up pending state before presenting.
        guard let player = pendingPlayer else { return }
        cleanupPendingState()
        let activeVideoFile = resolvedVideoFiles.first { $0.item.videoIndex?.uintValue == targetIndex }
        let activeMedia = activeVideoFile?.media ?? self.animeItem
        let activeEpisode = activeVideoFile?.episodeReference.intValue ?? self.currentEpisode

        player.videoEntity       = video
        player.videoService      = vs
        player.fileIndex         = targetIndex
        player.anilistID         = activeMedia?.id ?? Int(entity.animes?.animeAnilistId ?? 0)
        player.episodeNumber     = activeEpisode
        player.totalEpisodes     = activeMedia.map { TorrentBatchResolver.episodes(for: $0) } ?? self.animeItem?.episodes ?? 0
        player.allVideos         = videos
        player.currentVideoIndex = videos.firstIndex(of: video) ?? 0
        player.resolvedVideoFiles = resolvedVideoFiles
        // Hayase web mediahandler.svelte playEpisode(): when the target
        // episode is not in the current batch, initiate a new search.
        player.onEpisodeChange   = { [self] episode, media in
            handleEpisodeChangeFromPlayer(episode, media: media)
        }
        player.finishMetadataLoading()
    }

    private func cleanupPendingState() {
        isResolvingPendingMetadata = false
        if let observer = metadataObserver {
            NotificationCenter.default.removeObserver(observer)
            metadataObserver = nil
        }
        pendingVideoService = nil
        pendingEntity = nil
        pendingPlayer = nil
    }


    /// Called from the VideoPlayerViewController's `onEpisodeChange` callback
    /// when the user taps next/prev and the target episode is NOT in the
    /// current torrent batch. Updates the search episode and
    /// triggers a new extension search — mirroring the Hayase web interface's
    /// `searchStore.set({ media, episode })` flow from mediahandler.svelte.
    private func handleEpisodeChangeFromPlayer(_ episode: Int, media: AnimeItem?) {
        // Close the mini-player if active (the old torrent's player).
        MiniPlayerManager.shared.close()
        // The search coordinator is retained by the player, not presented again.
        if let media { animeItem = media }
        currentEpisode = episode
        episodeField.text = String(episode)
        autoSelectAfterSearch = true
        triggerSearch()
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
        cell.configure(with: result, configs: configs, accent: accent,
                       isDownloaded: WebTorrentDownloaded.shared.contains(result.hash))
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

// MARK: - UIViewControllerTransitioningDelegate (provides custom bottom-dialog on iPad)

extension ExtensionSearchViewController: UIViewControllerTransitioningDelegate {
    /// Called by UIKit when `modalPresentationStyle == .custom`. Returns the custom
    /// `BottomDialogPresentationController` that positions the dialog as a bottom-anchored
    /// sheet matching the web interface's Dialog.Content (max-w-5xl, rounded-t-xl, bottom-flush).
    func presentationController(forPresented presented: UIViewController,
                                presenting: UIViewController?,
                                source: UIViewController) -> UIPresentationController? {
        return BottomDialogPresentationController(presentedViewController: presented, presenting: presenting)
    }

    func animationController(forPresented presented: UIViewController,
                             presenting: UIViewController,
                             source: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        ExtensionSearchDialogAnimator(presenting: true)
    }

    func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        ExtensionSearchDialogAnimator(presenting: false)
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
    private var contentLeadingConstraint: NSLayoutConstraint!

    private let leftIconContainer: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    /// Card container — stored for highlight effects
    private let cardView: UIView = {
        let v = UIView()
        v.backgroundColor = UIColor.HayaseTheme.muted
        v.layer.cornerRadius = 6  // rounded-md (0.375rem = 6px)
        v.clipsToBounds = true  // web card has overflow-hidden
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
        sv.spacing = 8  // gap-2
        sv.alignment = .center
        return sv
    }()

    private let groupRow: UIStackView = {
        let spacer = UIView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let sv = UIStackView(arrangedSubviews: [spacer])
        sv.axis = .horizontal
        sv.spacing = 8
        sv.alignment = .top // extension icons use self-start in SearchModal.svelte
        sv.layoutMargins = UIEdgeInsets(top: 0, left: 24, bottom: 0, right: 0)
        sv.isLayoutMarginsRelativeArrangement = true
        return sv
    }()

    // Simplified filename
    private let filenameLabel: UILabel = {
        let l = UILabel()
        l.font = .nunito(ofSize: 11.2)
        l.textColor = UIColor.HayaseTheme.mutedForeground
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
        sv.layoutMargins = UIEdgeInsets(top: 0, left: 8, bottom: 0, right: 0)
        sv.isLayoutMarginsRelativeArrangement = true
        return sv
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = UIColor.HayaseTheme.background
        selectionStyle = .none

        // Card: bg-muted, 6px radius, mb-2 p-3
        // Hayase px-4 sm:px-6 on the container → we use 16px card inset
        contentView.addSubview(cardView)

        // BadgeCheck absolute top-left (mirrors absolute top-4 left-4)
        cardView.addSubview(badgeCheckView)

        // Hayase shows the 80px Folder/File icon only at the md breakpoint.
        cardView.addSubview(leftIconContainer)
        leftIconContainer.addSubview(fileIconView)

        // Group row: [groupLabel ········· extIconsStack]
        // Web: pl-6 on compact cards, md:pl-0 when the 80px file icon is visible.
        groupRow.insertArrangedSubview(groupLabel, at: 0)
        groupRow.addArrangedSubview(extIconsStack)
        groupLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        extIconsStack.setContentCompressionResistancePriority(.required, for: .horizontal)

        // Bottom-left: type badge + seeders + size + date (mirrors web details row)
        // Web: text-[.7rem] = 11.2px ≈ 11pt, normal weight. .details span+span::before for dots.
        seedersLabel.font = .nunito(ofSize: 11.2)
        sizeLabel.font = .nunito(ofSize: 11.2)
        sizeLabel.textColor = UIColor.white.withAlphaComponent(0.8) // text-white/80
        dateLabel.font = .nunito(ofSize: 11.2)
        dateLabel.textColor = UIColor.white.withAlphaComponent(0.8) // text-white/80

        // [typeBadge • seeders • size • date] with dot separators
        let leftBottom = UIStackView(arrangedSubviews: [typeBadgeLabel, dot1, seedersLabel, dot2, sizeLabel, dot3, dateLabel])
        leftBottom.axis = .horizontal
        leftBottom.spacing = 0
        leftBottom.alignment = .center
        leftBottom.setCustomSpacing(2, after: typeBadgeLabel) // mr-0.5

        // Bottom-right: tech term badges
        let bottomSpacer = UIView()
        bottomSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        bottomSpacer.widthAnchor.constraint(greaterThanOrEqualToConstant: 0).isActive = true
        for label in [typeBadgeLabel, seedersLabel, sizeLabel, dateLabel, dot1, dot2, dot3] {
            label.setContentCompressionResistancePriority(.required, for: .horizontal)
        }
        let bottomRow = UIStackView(arrangedSubviews: [leftBottom, bottomSpacer, termsStack])
        bottomRow.axis = .horizontal
        bottomRow.spacing = 0
        bottomRow.alignment = .center

        // Content column (no left icon on mobile — matches Hayase mobile layout)
        // Web text-nowrap never squeezes badges/details to fit. The card clips
        // horizontal overflow instead; only the filename has an ellipsis.
        let contentCol = UIStackView(arrangedSubviews: [
            Self.clippedRow(groupRow), filenameLabel, Self.clippedRow(bottomRow),
        ])
        contentCol.axis = .vertical
        contentCol.distribution = .equalSpacing  // justify-between (web h-20 flex-col justify-between)
        contentCol.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(contentCol)

        // Card margins: responsive px-4 (16pt) on mobile, sm:px-6 (24pt) on iPad
        cardLeadingConstraint = cardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16)
        cardTrailingConstraint = cardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16)
        contentLeadingConstraint = contentCol.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 20)

        // BadgeCheck position: 16px on mobile (top-4 left-4), 12px on iPad (md:top-3 md:left-3)
        badgeTopConstraint = badgeCheckView.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 16)
        badgeLeadingConstraint = badgeCheckView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 16)

        NSLayoutConstraint.activate([
            // Card: mb-2 (8pt below, no leading gap) + responsive side inset
            cardView.topAnchor.constraint(equalTo: contentView.topAnchor),
            cardLeadingConstraint,
            cardTrailingConstraint,
            cardView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),

            // BadgeCheck — absolute top-left (mobile: top-4 left-4 = 16px, iPad md: top-3 left-3 = 12px)
            // size 1.2rem ≈ 19px. Position updated in configure() for responsive sizing.
            badgeTopConstraint,
            badgeLeadingConstraint,
            badgeCheckView.widthAnchor.constraint(equalToConstant: 19.2),
            badgeCheckView.heightAnchor.constraint(equalToConstant: 19.2),

            leftIconContainer.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 12),
            leftIconContainer.centerYAnchor.constraint(equalTo: cardView.centerYAnchor),
            leftIconContainer.widthAnchor.constraint(equalToConstant: 80),
            leftIconContainer.heightAnchor.constraint(equalToConstant: 80),
            fileIconView.centerXAnchor.constraint(equalTo: leftIconContainer.centerXAnchor),
            fileIconView.centerYAnchor.constraint(equalTo: leftIconContainer.centerYAnchor),
            fileIconView.widthAnchor.constraint(equalToConstant: 48),
            fileIconView.heightAnchor.constraint(equalToConstant: 48),

            // Content column: p-3 (12pt) + pl-2 (8pt) on compact, md icon width + pl-2 on wide.
            contentLeadingConstraint,
            contentCol.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -12),
            contentCol.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 12),
            contentCol.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -12),
            contentCol.heightAnchor.constraint(equalToConstant: 80),
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
                self.cardView.backgroundColor = UIColor.HayaseTheme.muted
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
        // The web border adds 1px outside each side of px-3 py-1.
        l.contentInsets = UIEdgeInsets(top: 5, left: 13, bottom: 5, right: 13)
        l.font = .nunito(ofSize: 11.2)
        l.layer.cornerRadius = 4      // rounded (0.25rem = 4px)
        l.clipsToBounds = true
        l.layer.borderWidth = 1
        return l
    }

    /// A CSS nowrap flex row may exceed min-w-0's available width. Preserve its
    /// intrinsic content and let overflow-hidden clip it, rather than shrinking text.
    private static func clippedRow(_ row: UIView) -> UIView {
        let viewport = UIView()
        viewport.clipsToBounds = true
        row.translatesAutoresizingMaskIntoConstraints = false
        viewport.addSubview(row)
        let preferredWidth = row.widthAnchor.constraint(equalTo: viewport.widthAnchor)
        preferredWidth.priority = .defaultLow
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: viewport.leadingAnchor),
            row.topAnchor.constraint(equalTo: viewport.topAnchor),
            row.bottomAnchor.constraint(equalTo: viewport.bottomAnchor),
            row.widthAnchor.constraint(greaterThanOrEqualTo: viewport.widthAnchor),
            preferredWidth,
        ])
        return viewport
    }

    /// Renders the exact Lucide BadgeCheck outline with the interface fill and stroke.
    private static func makeBadgeCheckImage(fill: UIColor, size: CGFloat) -> UIImage? {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        return renderer.image { _ in
            let rect = CGRect(x: 0, y: 0, width: size, height: size)
            let outline = UIBezierPath()
            outline.move(to: CGPoint(x: 3.85, y: 8.62))
            var start = CGPoint(x: 3.85, y: 8.62)
            for end in [
                CGPoint(x: 8.63, y: 3.85), CGPoint(x: 15.37, y: 3.85),
                CGPoint(x: 20.15, y: 8.63), CGPoint(x: 20.15, y: 15.37),
                CGPoint(x: 15.38, y: 20.15), CGPoint(x: 8.63, y: 20.15),
                CGPoint(x: 3.85, y: 15.38), CGPoint(x: 3.85, y: 8.62),
            ] {
                // SVG's eight clockwise radius-4 arcs (icons/badge-check.svg).
                let dx = end.x - start.x, dy = end.y - start.y
                let chord: CGFloat = sqrt(dx * dx + dy * dy)
                let height: CGFloat = sqrt(max(0, 16 - chord * chord / 4))
                let center = CGPoint(x: (start.x + end.x) / 2 - dy / chord * height,
                                     y: (start.y + end.y) / 2 + dx / chord * height)
                let a0 = atan2(start.y - center.y, start.x - center.x)
                let a1 = atan2(end.y - center.y, end.x - center.x)
                let angle = (a1 - a0 + 2 * .pi).truncatingRemainder(dividingBy: 2 * .pi)
                let tangent: CGFloat = (4.0 / 3.0) * tan(angle / 4) * 4
                outline.addCurve(to: end,
                                 controlPoint1: CGPoint(x: start.x - sin(a0) * tangent, y: start.y + cos(a0) * tangent),
                                 controlPoint2: CGPoint(x: end.x + sin(a1) * tangent, y: end.y - cos(a1) * tangent))
                start = end
            }
            outline.close()
            let context = UIGraphicsGetCurrentContext()
            context?.saveGState()
            context?.scaleBy(x: size / 24, y: size / 24)
            fill.setFill()
            outline.fill()
            context?.restoreGState()
            UIImage.hayaseIcon("badge-check", pointSize: size)?
                .withTintColor(.black, renderingMode: .alwaysOriginal)
                .draw(in: rect)
        }.withRenderingMode(.alwaysOriginal)
    }

    private static let highBadgeImage = makeBadgeCheckImage(
        fill: UIColor(red: 83.0 / 255.0, green: 218.0 / 255.0, blue: 51.0 / 255.0, alpha: 1), size: 19.2)
    private static let mediumBadgeImage = makeBadgeCheckImage(
        fill: UIColor.HayaseTheme.mutedForeground.withAlphaComponent(0.2), size: 19.2)

    private static func setBadgeText(_ text: String, on label: PaddedLabel, color: UIColor, weight: UIFont.Weight) {
        // The result row has leading-none: 11.2px line box plus py-1, rather
        // than UIKit's taller default label line box plus the same padding.
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = 11.2
        paragraph.maximumLineHeight = 11.2
        paragraph.alignment = .center
        label.textAlignment = .center
        label.attributedText = NSAttributedString(string: text, attributes: [
            .font: UIFont.nunito(ofSize: 11.2, weight: weight),
            .foregroundColor: color,
            .paragraphStyle: paragraph,
            .baselineOffset: -1.5,
        ])
    }

    /// Creates a dot separator label matching web `.details span+span::before { content: '•' }`
    private static func makeDotSeparator() -> PaddedLabel {
        let l = PaddedLabel()
        l.text = "•"
        l.font = .nunito(ofSize: 6.4) // font-size: .4rem = 6.4px
        l.contentInsets = UIEdgeInsets(top: 0, left: 4.8, bottom: 0, right: 4.8)
        l.textColor = UIColor(red: 0.451, green: 0.451, blue: 0.451, alpha: 1) // #737373
        l.setContentHuggingPriority(.required, for: .horizontal)
        l.setContentCompressionResistancePriority(.required, for: .horizontal)
        return l
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let viewportWidth = contentView.bounds.width
        guard viewportWidth > 0 else { return }
        let hPad: CGFloat = viewportWidth >= 640 ? 24 : 16
        cardLeadingConstraint.constant = hPad
        cardTrailingConstraint.constant = -hPad

        let usesWideCard = viewportWidth >= 768
        leftIconContainer.isHidden = !usesWideCard
        contentLeadingConstraint.constant = usesWideCard ? 100 : 20
        groupRow.layoutMargins.left = usesWideCard ? 0 : 24
        let badgeInset: CGFloat = usesWideCard ? 12 : 16
        badgeTopConstraint.constant = badgeInset
        badgeLeadingConstraint.constant = badgeInset
    }

    /// svelte-radix `Download` at `size-12`, with `stroke-width='0.5' stroke='currentColor'`:
    /// `text-[#53da33] opacity-80`.
    private static let downloadedIcon: UIImage = RadixIcons.download(size: 48, strokeWidth: 0.5)
        .withTintColor(UIColor(red: 0.325, green: 0.855, blue: 0.200, alpha: 0.8), renderingMode: .alwaysOriginal)

    func configure(with result: TorrentResult, configs: [String: ExtensionConfig], accent: UIColor = .white,
                   isDownloaded: Bool = false) {
        let title = result.title
        accentColor = accent

        // ── BadgeCheck (mirrors accuracy === 'high' → green, 'medium' → muted, else hidden)
        switch result.accuracy {
        case "high":
            badgeCheckView.image = Self.highBadgeImage
            badgeCheckView.isHidden = false
        case "medium":
            badgeCheckView.image = Self.mediumBadgeImage
            badgeCheckView.isHidden = false
        default:
            badgeCheckView.isHidden = true
        }

        // ── Card opacity for low accuracy (mirrors class:opacity-40={result.accuracy === 'low'})
        contentView.alpha = result.accuracy == "low" ? 0.4 : 1.0

        // ── File icon (download=cached, folder=batch/best/alt, file=single, mirrors Download/Folder/File icons)
        let yellow = UIColor(red: 1.0, green: 0.796, blue: 0.231, alpha: 1) // text-yellow-300
        if isDownloaded {
            fileIconView.image = Self.downloadedIcon
        } else if let rtype = result.type, !rtype.isEmpty {
            // batch / best / alt → folder icon (yellow)
            fileIconView.image = UIImage.hayaseFilledIcon("folder", pointSize: 48)?
                .withTintColor(yellow.withAlphaComponent(0.8), renderingMode: .alwaysOriginal)
        } else {
            // single episode → svelte-radix `File` (muted)
            fileIconView.image = RadixIcons.file(size: 48)
                .withTintColor(UIColor.HayaseTheme.mutedForeground.withAlphaComponent(0.8), renderingMode: .alwaysOriginal)
        }

        // ── Release group
        groupLabel.text = TitleUtils.getGroup(from: title)

        // ── Extension icons (mirrors config.icon <img> top-right)
        extIconsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let orderedExtensions = result.extensionOrder + result.extensionIds.subtracting(Set(result.extensionOrder)).sorted()
        for extId in orderedExtensions {
            if let config = configs[extId], let url = URL(string: config.icon) {
                let iv = UIImageView()
                iv.contentMode = .scaleToFill
                iv.widthAnchor.constraint(equalToConstant: 16).isActive = true
                iv.heightAnchor.constraint(equalToConstant: 16).isActive = true
                iv.layer.cornerRadius = 0
                iv.clipsToBounds = true
                iv.backgroundColor = .clear
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
        if let rtype = result.type, ["best", "alt", "batch"].contains(rtype) {
            switch rtype {
            case "best":
                // background: #1d2d1e; border: #53da33; color: #53da33
                let color = UIColor(red: 0.325, green: 0.855, blue: 0.200, alpha: 1)
                Self.setBadgeText("Best Release", on: typeBadgeLabel, color: color, weight: .regular)
                typeBadgeLabel.backgroundColor = UIColor(red: 0.114, green: 0.176, blue: 0.118, alpha: 1)
                typeBadgeLabel.layer.borderColor = color.cgColor
            case "alt":
                // background: #391d20; border: #c52d2d; color: #c52d2d
                let color = UIColor(red: 0.773, green: 0.176, blue: 0.176, alpha: 1)
                Self.setBadgeText("Alt Release", on: typeBadgeLabel, color: color, weight: .regular)
                typeBadgeLabel.backgroundColor = UIColor(red: 0.220, green: 0.114, blue: 0.125, alpha: 1)
                typeBadgeLabel.layer.borderColor = color.cgColor
            default: // "batch"
                // background: #1d2031; border: #2d5ec5; color: #2d5ec5
                let color = UIColor(red: 0.176, green: 0.369, blue: 0.773, alpha: 1)
                Self.setBadgeText("Batch", on: typeBadgeLabel, color: color, weight: .regular)
                typeBadgeLabel.backgroundColor = UIColor(red: 0.114, green: 0.125, blue: 0.192, alpha: 1)
                typeBadgeLabel.layer.borderColor = color.cgColor
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
        sizeLabel.text = result.size > 0 ? TorrentFormat.fastPrettyBytes(UInt64(result.size)) : ""

        // ── Date (web: since(new Date(result.date)) — relative time like "2 days ago")
        if let date = result.date {
            dateLabel.text = AniListUtil.since(date)
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
            l.contentInsets = UIEdgeInsets(top: 4, left: 12, bottom: 4, right: 12) // py-1 px-3
            // Use Rec.601 brightness to pick contrasting text colour (mirrors web text-contrast-filter)
            let textColor = term.color.isLight ? UIColor.black : .white
            Self.setBadgeText(term.text, on: l, color: textColor, weight: .bold)
            l.backgroundColor = term.color
            l.layer.cornerRadius = 4  // rounded
            l.clipsToBounds = true
            l.setContentCompressionResistancePriority(.required, for: .horizontal)
            termsStack.addArrangedSubview(l)
        }
    }
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

// MARK: - Bottom-anchored dialog presentation (mirrors web Dialog.Content on iPad)
//
// Web Dialog.Content class:
//   bg-black h-full max-w-5xl w-full max-h-[calc(100%-1rem)] border-b-0
//   !rounded-b-none mt-2 lg:rounded-t-xl overflow-clip
//
// Position: centered via translate(-50%,-50%), mt-2 shifts down 8px.
// Effective: top=16px from viewport, bottom flush with viewport bottom.
// Top corners 12px, bottom corners square. Border on top/left/right (not bottom).
// Max width 1024px (max-w-5xl).

/// Matches Dialog.Content's 200ms flyAndScale in both directions.
private final class ExtensionSearchDialogAnimator: NSObject, UIViewControllerAnimatedTransitioning {
    private let duration: TimeInterval = 0.2
    private let presenting: Bool

    init(presenting: Bool) { self.presenting = presenting }

    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
        duration
    }

    func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
        let key: UITransitionContextViewKey = presenting ? .to : .from
        guard let animatedView = transitionContext.view(forKey: key) else {
            transitionContext.completeTransition(!transitionContext.transitionWasCancelled)
            return
        }

        if presenting {
            guard let toViewController = transitionContext.viewController(forKey: .to) else {
                transitionContext.completeTransition(false)
                return
            }
            animatedView.frame = transitionContext.finalFrame(for: toViewController)
            transitionContext.containerView.addSubview(animatedView)
            animatedView.alpha = 0
            animatedView.transform = CGAffineTransform(translationX: 0, y: 5).scaledBy(x: 0.95, y: 0.95)
        }

        let timing = UICubicTimingParameters(
            controlPoint1: CGPoint(x: 1.0 / 3.0, y: 1),
            controlPoint2: CGPoint(x: 2.0 / 3.0, y: 1)
        )
        let animator = UIViewPropertyAnimator(duration: duration, timingParameters: timing)
        animator.addAnimations {
            animatedView.alpha = self.presenting ? 1 : 0
            animatedView.transform = self.presenting
                ? .identity
                : CGAffineTransform(translationX: 0, y: 5).scaledBy(x: 0.95, y: 0.95)
        }
        animator.addCompletion { position in
            let completed = position == .end && !transitionContext.transitionWasCancelled
            if !completed {
                animatedView.alpha = self.presenting ? 0 : 1
                animatedView.transform = self.presenting
                    ? CGAffineTransform(translationX: 0, y: 5).scaledBy(x: 0.95, y: 0.95)
                    : .identity
            }
            transitionContext.completeTransition(completed)
        }
        animator.startAnimation()
    }
}

/// Custom presentation controller that positions the dialog as a bottom-anchored
/// sheet matching the web interface's Dialog.Content exactly.
final class BottomDialogPresentationController: UIPresentationController {

    /// Dimming overlay behind the dialog (mirrors web Dialog.Overlay custom-bg + backdrop blur).
    private let dimmingView = HayaseStripedBackdropView()

    // MARK: Frame

    override var frameOfPresentedViewInContainerView: CGRect {
        guard let containerView = containerView else { return .zero }
        // max-w-5xl = 1024px, centered horizontally
        let maxWidth: CGFloat = 1024
        let width = min(maxWidth, containerView.bounds.width)
        let x = (containerView.bounds.width - width) / 2
        // top = 16px from viewport top (web: centered + mt-2 + max-h-[calc(100%-1rem)])
        // bottom = flush with viewport bottom (web: extends to 100vh)
        let topInset: CGFloat = containerView.safeAreaInsets.top + 16
        let height = containerView.bounds.height - topInset
        return CGRect(x: x, y: topInset, width: width, height: height)
    }

    // MARK: Transitions

    override func presentationTransitionWillBegin() {
        guard let containerView = containerView else { return }
        dimmingView.frame = containerView.bounds
        dimmingView.alpha = 0
        containerView.insertSubview(dimmingView, at: 0)

        // Tap outside → dismiss (matches web Dialog.Overlay click-to-close)
        let tap = UITapGestureRecognizer(target: self, action: #selector(dimmingTapped))
        dimmingView.addGestureRecognizer(tap)

        presentedViewController.transitionCoordinator?.animate(alongsideTransition: { _ in
            self.dimmingView.alpha = 1
        })
    }

    override func dismissalTransitionWillBegin() {
        presentedViewController.transitionCoordinator?.animate(alongsideTransition: { _ in
            self.dimmingView.alpha = 0
        })
    }

    override func dismissalTransitionDidEnd(_ completed: Bool) {
        if completed {
            dimmingView.removeFromSuperview()
        }
    }

    // MARK: Layout

    override func containerViewDidLayoutSubviews() {
        super.containerViewDidLayoutSubviews()
        let bounds = containerView?.bounds ?? .zero
        dimmingView.frame = bounds
        presentedView?.frame = frameOfPresentedViewInContainerView

        // lg:rounded-t-xl (12px top corners) + !rounded-b-none (square bottom)
        presentedView?.layer.cornerRadius = bounds.width >= 1024 ? 12 : (bounds.width >= 640 ? 8 : 0)
        presentedView?.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        presentedView?.clipsToBounds = true

        // Border on top, left, right (web: border + border-b-0)
        // Dark theme border-input ≈ HSL(240, 3.7%, 15.9%) ≈ #27272a
        if let pv = presentedView, pv.layer.sublayers?.contains(where: { $0.name == "dialogBorder" }) != true {
            let border = CAShapeLayer()
            border.name = "dialogBorder"
            updateBorderPath(border, in: pv.bounds)
            border.strokeColor = UIColor(white: 0.16, alpha: 1).cgColor
            border.fillColor = nil
            border.lineWidth = 1
            pv.layer.addSublayer(border)
        } else if let border = presentedView?.layer.sublayers?.first(where: { $0.name == "dialogBorder" }) as? CAShapeLayer {
            updateBorderPath(border, in: presentedView?.bounds ?? .zero)
        }
    }

    /// Draw border path on top + left + right edges only (no bottom).
    private func updateBorderPath(_ layer: CAShapeLayer, in bounds: CGRect) {
        let viewportWidth = containerView?.bounds.width ?? bounds.width
        let r: CGFloat = viewportWidth >= 1024 ? 12 : (viewportWidth >= 640 ? 8 : 0)
        let path = UIBezierPath()
        // Start at bottom-left, go up to top-left corner, arc, go right to top-right corner, arc, go down to bottom-right
        path.move(to: CGPoint(x: 0, y: bounds.height))
        path.addLine(to: CGPoint(x: 0, y: r))
        path.addArc(withCenter: CGPoint(x: r, y: r), radius: r, startAngle: .pi, endAngle: 3 * .pi / 2, clockwise: true)
        path.addLine(to: CGPoint(x: bounds.width - r, y: 0))
        path.addArc(withCenter: CGPoint(x: bounds.width - r, y: r), radius: r, startAngle: 3 * .pi / 2, endAngle: 0, clockwise: true)
        path.addLine(to: CGPoint(x: bounds.width, y: bounds.height))
        layer.path = path.cgPath
    }

    @objc private func dimmingTapped() {
        presentedViewController.dismiss(animated: true)
    }
}

// MARK: - Torrents dropped on the dialog (SearchModal.svelte handleTransfer)

extension ExtensionSearchViewController: UIDropInteractionDelegate {
    func dropInteraction(_ interaction: UIDropInteraction, canHandle session: UIDropSession) -> Bool {
        animeItem != nil && session.hasItemsConforming(toTypeIdentifiers: [UTType.data.identifier, UTType.plainText.identifier, UTType.url.identifier])
    }

    func dropInteraction(_ interaction: UIDropInteraction, sessionDidUpdate session: UIDropSession) -> UIDropProposal {
        UIDropProposal(operation: .copy)
    }

    func dropInteraction(_ interaction: UIDropInteraction, performDrop session: UIDropSession) {
        for item in session.items {
            let provider = item.itemProvider
            if provider.suggestedName?.lowercased().hasSuffix(".torrent") == true
                || provider.hasItemConformingToTypeIdentifier("org.bittorrent.torrent") {
                // `file.type === 'application/x-bittorrent' || file.name.endsWith('.torrent')`
                provider.loadDataRepresentation(forTypeIdentifier: UTType.data.identifier) { [weak self] data, _ in
                    guard let data else { return }
                    DispatchQueue.main.async { self?.playTorrentFile(data, name: provider.suggestedName) }
                }
            } else if provider.canLoadObject(ofClass: NSString.self) {
                // `file.type === 'text/plain'` → findTorrentIdentifiers
                _ = provider.loadObject(ofClass: NSString.self) { [weak self] text, _ in
                    guard let text = text as? String else { return }
                    DispatchQueue.main.async {
                        if ParseTorrent.isIdentifier(text) { self?.playIdentifier(text) }
                    }
                }
            }
        }
    }
}
