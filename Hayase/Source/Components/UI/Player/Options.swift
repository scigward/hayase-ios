/// Hayase options.svelte — tree-style player options menu.
///
/// Ports the web interface's `options.svelte` Tree component UI to iOS.
/// The menu is presented as a centered overlay with a dark rounded container,
/// matching the web's `w-64 bg-black rounded-md border` styling.
///
/// Track grouping mirrors `util.ts → normalizeTracks() / normalizeSubs()`:
/// audio and subtitle tracks are grouped by language code, with an "unk"
/// fallback when no language tag is set.

import UIKit
import UniformTypeIdentifiers

// MARK: - Data model

/// Represents a single item in the tree menu.
/// Mirrors the web interface's `<Tree.Item>` component.
private enum OptionItem {
    /// An item with children (opens an adjacent Tree.Sub panel).
    case expandable(title: String, children: [OptionItem])
    /// A selectable leaf item (primary background when active).
    case selectable(title: String, isActive: Bool, action: () -> Void)
    /// A plain action item (no active state).
    case action(title: String, action: () -> Void)
    case chapter(title: String, time: String, action: () -> Void)
    case playlist(title: String, action: () -> Void)
    /// A toggle item (primary background when active).
    case toggle(title: String, isActive: Bool, action: () -> Void)
    /// Inline subtitle delay input row.
    case subtitleDelay
}

// MARK: - Language helpers

/// Mirrors Svelte's `class='capitalize'` for language group labels.
/// The menu displays stable language keys, not localized language names.
private func languageName(for code: String) -> String {
    let normalized = interfaceLanguageKey(code)
    guard let first = normalized.first else { return normalized }
    return first.uppercased() + normalized.dropFirst()
}

/// MPV may expose BCP-47 language tags such as `es-419`, while Hayase's
/// interface menu normally receives the shorter language keys used by its
/// player settings (`spa`, `eng`, `jpn`, ...). Normalize only the known player
/// languages so menu grouping/labels stay stable without localizing them.
private func interfaceLanguageKey(_ code: String) -> String {
    let value = code.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !value.isEmpty else { return value }

    let base = value.split(separator: "-").first.map(String.init) ?? value
    switch base {
    case "en": return "eng"
    case "ja", "jp": return "jpn"
    case "zh": return "chi"
    case "pt": return "por"
    case "es": return "spa"
    case "de": return "ger"
    case "fr": return "fre"
    case "ko": return "kor"
    case "pl": return "pol"
    case "it": return "ita"
    case "ru": return "rus"
    case "sk": return "slo"
    case "sv": return "swe"
    case "ar": return "ara"
    case "hi": return "hin"
    case "bn": return "ben"
    case "th": return "tha"
    case "tr": return "tur"
    case "vi": return "vie"
    case "da": return "dan"
    case "fi": return "fin"
    case "hu": return "hun"
    case "nl": return "dut"
    case "no", "nb", "nn": return "nor"
    case "ro": return "rum"
    case "cs": return "cze"
    case "el": return "gre"
    case "fa": return "per"
    case "id": return "idn"
    case "he", "iw": return "heb"
    case "ms", "ml": return "mal"
    default: break
    }

    let aliases: [String: String] = [
        "jpn": "jpn", "japanese": "jpn",
        "eng": "eng", "english": "eng",
        "chi": "chi", "zho": "chi", "chinese": "chi",
        "por": "por", "portuguese": "por", "brazilian": "por",
        "spa": "spa", "esp": "spa", "spanish": "spa", "espanol": "spa", "español": "spa",
        "ger": "ger", "deu": "ger", "german": "ger",
        "pol": "pol", "polish": "pol",
        "dan": "dan", "danish": "dan",
        "fin": "fin", "finnish": "fin",
        "hun": "hun", "hungarian": "hun",
        "ita": "ita", "italian": "ita",
        "kor": "kor", "korean": "kor",
        "rus": "rus", "russian": "rus",
        "slo": "slo", "slk": "slo", "slovak": "slo",
        "swe": "swe", "swedish": "swe",
        "ara": "ara", "arabic": "ara",
        "hin": "hin", "hindi": "hin",
        "ben": "ben", "bengali": "ben",
        "tha": "tha", "thai": "tha",
        "tur": "tur", "turkish": "tur",
        "vie": "vie", "vietnamese": "vie",
        "fre": "fre", "fra": "fre", "french": "fre",
        "dut": "dut", "nld": "dut", "dutch": "dut",
        "rum": "rum", "ron": "rum", "romanian": "rum",
        "cze": "cze", "ces": "cze", "czech": "cze",
        "gre": "gre", "ell": "gre", "greek": "gre",
        "per": "per", "fas": "per", "persian": "per",
        "idn": "idn", "ind": "idn", "indonesian": "idn",
        "heb": "heb", "hebrew": "heb",
        "mal": "mal", "may": "mal", "msa": "mal", "malay": "mal", "malayalam": "mal",
    ]
    return aliases[value] ?? value
}

private func defaultTrackLabel(_ track: MPVTrack) -> String {
    if let title = track.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
        return title
    }
    return "Default"
}

private func defaultSubtitleLabel(_ track: MPVTrack, fallbackLanguage: String) -> String {
    if let title = track.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
        return title
    }
    if let lang = track.lang?.trimmingCharacters(in: .whitespacesAndNewlines), !lang.isEmpty {
        return interfaceLanguageKey(lang)
    }
    return fallbackLanguage
}

/// Groups tracks by language, mirroring `util.ts → normalizeTracks()`.
/// If no track has language "eng"/"en", untagged tracks default to "eng";
/// otherwise they default to "unk".
private func groupByLanguage(_ tracks: [MPVTrack]) -> [(lang: String, tracks: [MPVTrack])] {
    let hasEng = tracks.contains { track in
        guard let lang = track.lang, !lang.isEmpty else { return false }
        return interfaceLanguageKey(lang) == "eng"
    }
    var groups: [(key: String, values: [MPVTrack])] = []
    var dict: [String: Int] = [:]  // lang → index in groups
    for track in tracks {
        let lang = track.lang.flatMap({ $0.isEmpty ? nil : interfaceLanguageKey($0) })
            ?? (hasEng ? "unk" : "eng")
        if let idx = dict[lang] {
            groups[idx].values.append(track)
        } else {
            dict[lang] = groups.count
            groups.append((key: lang, values: [track]))
        }
    }
    return groups.map { (lang: $0.key, tracks: $0.values) }
}

// MARK: - PlayerOptionsController

/// Player-scoped overlay presenting a tree-style options menu.
/// The visual design matches Hayase's `options.svelte` + Tree components:
/// - Dark rounded bordered container (w-64 → 256pt)
/// - Items: `py-2.5 pl-4 font-bold text-sm rounded-sm`
/// - Active item: primary bg / background text
/// - Expandable items show a chevron on the right
/// - Tapping outside the container dismisses the menu
final class PlayerOptionsController: UIViewController, KeyboardEventListener {

    // MARK: - Configuration callbacks

    var onSelectAudioTrack: ((Int) -> Void)?
    var onSelectVideoTrack: ((Int) -> Void)?
    var onSelectSubtitleTrack: ((Int) -> Void)?
    var onSetSpeed: ((Double) -> Void)?
    var onSeekTo: ((Double) -> Void)?
    var onSwitchVideo: ((Videos) -> Void)?
    var onToggleDeband: (() -> Void)?
    var onTogglePiP: (() -> Void)?
    var onToggleFullscreen: (() -> Void)?
    var onScreenshot: (() -> Void)?
    var onAddSubtitleFile: (() -> Void)?
    var onSubtitleDelayChanged: ((Double) -> Void)?
    var onSelectDisplay: ((WebTorrentDisplay) -> Void)?
    var onDismiss: (() -> Void)?
    var onKeybindAction: ((String, Bool) -> Void)?

    // MARK: - Input data

    var audioTracks: [MPVTrack] = []
    var videoTracks: [MPVTrack] = []
    var subtitleTracks: [MPVTrack] = []
    var chapters: [MPVChapter] = []
    var currentSpeed: Double = 1.0
    var subtitleDelay: Double = 0.0
    var isDebandActive: Bool = false
    var isPiPActive: Bool = false
    var isFullscreenActive: Bool = false
    var allVideos: [Videos] = []
    var currentVideoEntity: Videos?
    /// Cast/DLNA displays discovered via the WebTorrent bridge.
    /// Mirrors options.svelte: `{#if $displays.length}` — the "Cast" item
    /// only appears at all once at least one display has been found.
    var displays: [WebTorrentDisplay] = []

    // MARK: - Tree presentation: Tree.Root / Menu / Sub at every viewport width.

    private let treeScrollView = UIScrollView()
    private let treeCanvas = UIView()
    private let optionsContentView = UIView()
    private let stripedBackdropView = HayaseStripedBackdropView()
    private let closeButton = HayaseCloseButton()
    private let keybindsView = PlayerKeybindsView()
    private var showKeybinds = false
    private var navigationStack: [(title: String?, items: [OptionItem])] = []
    private var activeIndices: [Int] = []
    private var menuViews: [UIView] = []
    private var menuTables: [UITableView] = []
    private var tableLevels: [ObjectIdentifier: Int] = [:]
    private var treeAnimator: UIViewPropertyAnimator?
    private let menuWidth: CGFloat = 256
    private var lastLayoutSize: CGSize = .zero

    func preparePresentation() {
        modalPresentationStyle = .custom
        transitioningDelegate = self
    }

    func openRootMenu(named title: String) {
        loadViewIfNeeded()
        guard let rootItems = navigationStack.first?.items,
              let row = rootItems.firstIndex(where: {
                  if case .expandable(let name, _) = $0 { return name == title }
                  return false
              }), case .expandable(_, let children) = rootItems[row] else { return }
        showKeybinds = false
        openLevel(from: 0, row: row, title: title, children: children)
    }

    func setTransitionProgress(_ shown: Bool) {
        // The source Dialog.Content contains both the tree and its close button;
        // flyAndScale moves them together around the full viewport's centre.
        optionsContentView.alpha = shown ? 1 : 0
        optionsContentView.transform = shown ? .identity
            : CGAffineTransform(translationX: 0, y: 5).scaledBy(x: 0.95, y: 0.95)
    }

    func setBackdropVisible(_ shown: Bool) { stripedBackdropView.alpha = shown ? 1 : 0 }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        stripedBackdropView.frame = view.bounds
        stripedBackdropView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        stripedBackdropView.isUserInteractionEnabled = false
        view.addSubview(stripedBackdropView)
        optionsContentView.frame = view.bounds
        optionsContentView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(optionsContentView)
        treeScrollView.frame = view.bounds
        treeScrollView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        treeScrollView.showsVerticalScrollIndicator = false
        treeScrollView.contentInsetAdjustmentBehavior = .never
        optionsContentView.addSubview(treeScrollView)
        treeScrollView.addSubview(treeCanvas)
        keybindsView.frame = treeScrollView.bounds
        keybindsView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        keybindsView.isHidden = true
        keybindsView.onAction = { [weak self] id, shift in self?.onKeybindAction?(id, shift) }
        treeScrollView.addSubview(keybindsView)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.addTarget(self, action: #selector(dismissSelf), for: .touchUpInside)
        optionsContentView.addSubview(closeButton)
        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: optionsContentView.topAnchor, constant: 16),
            closeButton.trailingAnchor.constraint(equalTo: optionsContentView.trailingAnchor, constant: -16),
            closeButton.widthAnchor.constraint(equalToConstant: 16),
            closeButton.heightAnchor.constraint(equalToConstant: 16),
        ])
        let tap = UITapGestureRecognizer(target: self, action: #selector(closeOutside))
        tap.cancelsTouchesInView = false
        tap.delegate = self
        view.addGestureRecognizer(tap)
        navigationStack = [(title: nil, items: buildRootMenu())]
        reloadTree(animated: false)
    }

    override var prefersStatusBarHidden: Bool { true }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        presentingViewController?.supportedInterfaceOrientations ?? .allButUpsideDown
    }
    override var shouldAutorotate: Bool { presentingViewController?.shouldAutorotate ?? true }
    override var canBecomeFirstResponder: Bool { true }
    override var keyCommands: [UIKeyCommand]? {
        PlayerKeyBindings.isEditing(in: viewIfLoaded) ? nil : PlayerKeyBindings.commands()
    }
    /// The binds of the player work over the options too, which are not in the player's own part of the page
    func keyDown(_ event: KeyboardEvent) {
        guard !PlayerKeyBindings.isEditing(in: viewIfLoaded) else { return }
        PlayerKeyBindings.run(event) { [weak self] id, shift in self?.onKeybindAction?(id, shift) }
    }
    override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); becomeFirstResponder() }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard lastLayoutSize != view.bounds.size else { return }
        lastLayoutSize = view.bounds.size
        layoutTree(animated: false)
    }

    private func items(for table: UITableView) -> [OptionItem] {
        guard let level = tableLevels[ObjectIdentifier(table)],
              navigationStack.indices.contains(level) else { return [] }
        return navigationStack[level].items
    }

    private func makeMenu() -> UIView {
        let menu = UIView()
        menu.backgroundColor = UIColor.HayaseTheme.background
        menu.layer.cornerRadius = 6
        menu.layer.borderWidth = 1
        menu.layer.borderColor = UIColor.HayaseTheme.border.cgColor
        menu.layer.shadowColor = UIColor.black.cgColor
        menu.layer.shadowOpacity = 0.1
        menu.layer.shadowRadius = 6
        menu.layer.shadowOffset = CGSize(width: 0, height: 4)
        return menu
    }

    private func reloadTree(animated: Bool) {
        while menuViews.count > navigationStack.count {
            menuViews.removeLast().removeFromSuperview()
            tableLevels.removeValue(forKey: ObjectIdentifier(menuTables.removeLast()))
        }
        while menuViews.count < navigationStack.count {
            let menu = makeMenu()
            let table = UITableView(frame: .zero, style: .plain)
            table.backgroundColor = .clear
            table.separatorStyle = .none
            table.showsVerticalScrollIndicator = false
            table.contentInsetAdjustmentBehavior = .never
            table.dataSource = self
            table.delegate = self
            table.isScrollEnabled = false
            table.estimatedRowHeight = 0
            table.register(PlayerOptionCell.self, forCellReuseIdentifier: PlayerOptionCell.reuseID)
            table.register(PlayerSubtitleDelayCell.self, forCellReuseIdentifier: PlayerSubtitleDelayCell.reuseID)
            menu.addSubview(table)
            treeCanvas.addSubview(menu)
            tableLevels[ObjectIdentifier(table)] = menuTables.count
            menuViews.append(menu)
            menuTables.append(table)
        }
        for (level, table) in menuTables.enumerated() {
            // Tree.Item wraps its data-open button in a div. Consequently the
            // source Menu's direct-child :has(>[data-open=true]) does not match;
            // its background stays opaque while the buttons themselves dim.
            menuViews[level].backgroundColor = UIColor.HayaseTheme.background
            table.reloadData()
        }
        layoutTree(animated: animated)
    }

    private func layoutTree(animated: Bool) {
        guard !menuViews.isEmpty, menuViews.count == navigationStack.count, view.bounds.width > 0 else { return }
        if let treeAnimator {
            treeAnimator.stopAnimation(false)
            treeAnimator.finishAnimation(at: .current)
            self.treeAnimator = nil
        }
        if showKeybinds {
            treeCanvas.isHidden = true
            keybindsView.isHidden = false
            keybindsView.frame = CGRect(origin: .zero, size: treeScrollView.bounds.size)
            treeScrollView.contentSize = treeScrollView.bounds.size
            treeScrollView.contentOffset = .zero
            return
        }
        treeCanvas.isHidden = false
        keybindsView.isHidden = true
        let gap: CGFloat = 8
        let widths = navigationStack.map { menuWidth(for: $0.items) }
        let rows = navigationStack.enumerated().map { level, menu in
            menu.items.map { rowHeight(for: $0, width: widths[level]) }
        }
        // The button's my-0.5 margins collapse through Tree.Item's relative div.
        // Adjacent buttons therefore have a 2pt gap, with 2pt at each outer end;
        // border + p-1 adds another 5pt at the top and bottom.
        let heights = rows.map { $0.reduce(0, +) + ($0.isEmpty ? 10 : 12) }
        var offsets = Array(repeating: CGFloat(0), count: navigationStack.count)
        for level in navigationStack.indices.dropFirst() {
            // The first relative wrapper starts at 5 + its collapsed 2pt margin.
            // Tree.Sub top=-5 leaves 2pt, plus each preceding row's advance.
            offsets[level] = offsets[level - 1] + 2 + rows[level - 1].prefix(max(0, activeIndices[safe: level - 1] ?? 0)).reduce(0, +)
        }
        let extent = zip(offsets, heights).map { $0.0 + $0.1 }.max() ?? heights[0]
        // Absolutely positioned Tree.Sub panels do not change the centred root's
        // vertical position. Grow the scrollable extent instead of moving it up.
        let originY = max(0, (view.bounds.height - heights[0]) / 2)
        let canvasHeight = max(view.bounds.height, originY + extent)
        treeCanvas.frame = CGRect(x: 0, y: 0, width: view.bounds.width, height: canvasHeight)
        treeScrollView.contentSize = treeCanvas.bounds.size
        // Tree.Root margin-left=-state.length*528 in a centered flex row:
        // root moves left by 264 per level.
        let rootX = (view.bounds.width - menuWidth) / 2 - CGFloat(activeIndices.count) * (menuWidth + gap)
        var frames: [CGRect] = []
        var x = rootX
        for level in menuViews.indices {
            frames.append(CGRect(x: x, y: originY + offsets[level], width: widths[level], height: heights[level]))
            // Tree.Sub's 100% is the inner Tree.Item wrapper, not the outer
            // bordered menu: 5 + (width - 10) + 8 = width + 3.
            x += widths[level] + gap - 5
        }
        // Tree.Sub appears at its full size immediately; only the existing root's
        // margin-left transitions. Do not grow a new panel from CGRect.zero.
        for level in menuViews.indices where menuViews[level].bounds.isEmpty {
            menuViews[level].frame = frames[level].offsetBy(dx: animated ? menuWidth + gap : 0, dy: 0)
            menuTables[level].frame = tableFrame(in: menuViews[level].bounds)
        }
        let changes = {
            for level in self.menuViews.indices {
                self.menuViews[level].frame = frames[level]
                self.menuTables[level].frame = self.tableFrame(in: self.menuViews[level].bounds)
            }
        }
        if animated {
            // Tailwind transition-[margin-left] uses 150ms cubic-bezier(.4,0,.2,1).
            let timing = UICubicTimingParameters(controlPoint1: CGPoint(x: 0.4, y: 0),
                                                controlPoint2: CGPoint(x: 0.2, y: 1))
            let animator = UIViewPropertyAnimator(duration: 0.15, timingParameters: timing)
            animator.addAnimations(changes)
            animator.addCompletion { [weak self] _ in self?.treeAnimator = nil }
            treeAnimator = animator
            animator.startAnimation()
        } else { changes() }
    }

    private func tableFrame(in bounds: CGRect) -> CGRect {
        CGRect(x: 5, y: 7, width: max(0, bounds.width - 10), height: max(0, bounds.height - 12))
    }

    private func menuWidth(for items: [OptionItem]) -> CGFloat {
        guard let first = items.first, case .playlist = first else { return menuWidth }
        // Tree.Sub w-auto max-w-xl: nowrap filenames set the intrinsic width.
        let font = UIFont.nunito(ofSize: 12, weight: .bold)
        let widest = items.compactMap { item -> CGFloat? in
            guard case .playlist(let title, _) = item else { return nil }
            return ceil((title as NSString).size(withAttributes: [.font: font]).width)
        }.max() ?? 0
        return min(576, max(26, widest + 26)) // menu border/padding 10 + item pl-4 16
    }

    private func rowHeight(for item: OptionItem, width: CGFloat) -> CGFloat {
        let title: String
        var trailing: CGFloat = 0
        var minimumLineHeight: CGFloat = 14
        switch item {
        case .subtitleDelay: return 36
        case .playlist: return 38 // leading-4 + py-2.5 + collapsed 2pt row margin
        case .expandable(let text, _): title = text; trailing = 32; minimumLineHeight = 16
        case .chapter(let text, let time, _):
            title = text
            trailing = ceil((time as NSString).size(withAttributes: [.font: UIFont.nunito(ofSize: 14, weight: .bold)]).width) + 16
        case .action(let text, _), .selectable(let text, _, _), .toggle(let text, _, _): title = text
        }
        let font = UIFont.nunito(ofSize: 14, weight: .bold)
        let textHeight = (title as NSString).boundingRect(
            with: CGSize(width: max(1, width - 26 - trailing), height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin], attributes: [.font: font], context: nil).height
        let lines = max(1, ceil(textHeight / font.lineHeight))
        return max(minimumLineHeight, lines * 14) + 22
    }

    private func openLevel(from level: Int, row: Int, title: String, children: [OptionItem]) {
        navigationStack = Array(navigationStack.prefix(level + 1))
        activeIndices = Array(activeIndices.prefix(level))
        activeIndices.append(row)
        navigationStack.append((title: title, items: children))
        reloadTree(animated: true)
    }

    private func collapseLevel(_ level: Int) {
        navigationStack = Array(navigationStack.prefix(level + 1))
        activeIndices = Array(activeIndices.prefix(level))
        reloadTree(animated: true)
    }

    private func rebuildAndReload() {
        guard !navigationStack.isEmpty else { return }
        navigationStack[0] = (title: nil, items: buildRootMenu())
        reloadTree(animated: false)
    }

    @objc private func dismissSelf() { dismissWithCompletion(nil) }
    @objc private func closeOutside() {
        if showKeybinds { showKeybinds = false; layoutTree(animated: false) }
        else { dismissSelf() }
    }

    private func dismissWithCompletion(_ completion: (() -> Void)?) {
        let dismissed = onDismiss
        dismiss(animated: true) {
            dismissed?()
            completion?()
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        let total = max(0, Int(safe: seconds))
        return total >= 3600
            ? String(format: "%d:%02d:%02d", total / 3600, (total / 60) % 60, total % 60)
            : String(format: "%d:%02d", total / 60, total % 60)
    }

    // MARK: - Menu building

    /// Builds the root-level menu items matching options.svelte Tree.Root.
    private func buildRootMenu() -> [OptionItem] {
        var items: [OptionItem] = []

        // Audio — grouped by language (options.svelte: normalizeTracks)
        // Web always nests: Audio > language > tracks (never flattens single-track groups)
        let audioGroups = groupByLanguage(audioTracks)
        if !audioGroups.isEmpty {
            let audioChildren: [OptionItem] = audioGroups.map { group in
                let langTitle = languageName(for: group.lang)
                let trackItems: [OptionItem] = group.tracks.map { track in
                    .selectable(title: defaultTrackLabel(track),
                                isActive: track.isSelected) { [weak self] in
                        self?.onSelectAudioTrack?(track.id)
                        self?.dismissSelf()
                    }
                }
                return .expandable(title: langTitle, children: trackItems)
            }
            items.append(.expandable(title: "Audio", children: audioChildren))
        }

        // Video — same nested language structure as options.svelte.
        let videoGroups = groupByLanguage(videoTracks)
        if !videoGroups.isEmpty {
            let videoChildren: [OptionItem] = videoGroups.map { group in
                let langTitle = languageName(for: group.lang)
                let trackItems: [OptionItem] = group.tracks.map { track in
                    .selectable(title: defaultTrackLabel(track),
                                isActive: track.isSelected) { [weak self] in
                        self?.onSelectVideoTrack?(track.id)
                        self?.dismissSelf()
                    }
                }
                return .expandable(title: langTitle, children: trackItems)
            }
            items.append(.expandable(title: "Video", children: videoChildren))
        }

        // Subtitles — interface keeps OFF + grouped tracks + Delay in the submenu.
        if onSelectSubtitleTrack != nil || onSubtitleDelayChanged != nil || !subtitleTracks.isEmpty {
            var subChildren: [OptionItem] = []
            let currentSid = subtitleTracks.first(where: { $0.isSelected })?.id
            subChildren.append(.selectable(title: "OFF", isActive: currentSid == nil) { [weak self] in
                self?.onSelectSubtitleTrack?(-1)
                self?.dismissSelf()
            })

            for group in groupByLanguage(subtitleTracks) {
                let langTitle = languageName(for: group.lang)
                let trackItems: [OptionItem] = group.tracks.map { track in
                    .selectable(title: defaultSubtitleLabel(track, fallbackLanguage: group.lang),
                                isActive: track.isSelected) { [weak self] in
                        self?.onSelectSubtitleTrack?(track.id)
                        self?.dismissSelf()
                    }
                }
                subChildren.append(.expandable(title: langTitle, children: trackItems))
            }

            if onAddSubtitleFile != nil {
                subChildren.append(.action(title: "Add Subtitle File") { [weak self] in
                    self?.dismissWithCompletion(self?.onAddSubtitleFile)
                })
            }
            if onSubtitleDelayChanged != nil {
                subChildren.append(.subtitleDelay)
            }
            items.append(.expandable(title: "Subtitles", children: subChildren))
        }

        // Chapters (options.svelte: chapters section)
        if !chapters.isEmpty {
            let chapterItems: [OptionItem] = chapters.map { ch in
                let ts = formatTime(ch.time)
                let title = ch.title.isEmpty ? "?" : ch.title
                return .chapter(title: title.capitalized, time: ts) { [weak self] in
                    self?.onSeekTo?(ch.time)
                    self?.dismissSelf()
                }
            }
            items.append(.expandable(title: "Chapters", children: chapterItems))
        }

        // Playback Rate (options.svelte: 0.5x..2x including 1.75x)
        let speeds: [(String, Double)] = [
            ("0.5x", 0.5), ("0.75x", 0.75), ("1x", 1.0),
            ("1.25x", 1.25), ("1.5x", 1.5), ("1.75x", 1.75), ("2x", 2.0),
        ]
        let speedItems: [OptionItem] = speeds.map { (label, rate) in
            .selectable(title: label, isActive: rate == currentSpeed) { [weak self] in
                self?.onSetSpeed?(rate)
                self?.dismissSelf()
            }
        }
        items.append(.expandable(title: "Playback Rate", children: speedItems))

        // Playlist (options.svelte: videoFiles — no active highlight in web)
        do {
            let playlistItems: [OptionItem] = allVideos.map { video in
                let name = video.videoName
                    ?? video.videoPath?.components(separatedBy: "/").last
                    ?? "Video"
                return .playlist(title: name) { [weak self] in
                    self?.onSwitchVideo?(video)
                }
            }
            items.append(.expandable(title: "Playlist", children: playlistItems))
        }

        // Cast (options.svelte: `{#if $displays.length}` Cast tree item, listing
        // each discovered display by friendlyName — no active/selected state
        // shown for the list items on web either).
        if !displays.isEmpty {
            let castItems: [OptionItem] = displays.map { display in
                .action(title: display.friendlyName) { [weak self] in
                    self?.onSelectDisplay?(display)
                    self?.dismissSelf()
                }
            }
            items.append(.expandable(title: "Cast", children: castItems))
        }

        // Screenshot (options.svelte: plain action item, does not close menu)
        if onScreenshot != nil {
            items.append(.action(title: "Screenshot") { [weak self] in
                self?.onScreenshot?()
            })
        }

        // Fullscreen (options.svelte: Fullscreen tree item)
        items.append(.toggle(title: "Fullscreen", isActive: isFullscreenActive) { [weak self] in
            self?.onToggleFullscreen?()
            self?.isFullscreenActive.toggle()
            self?.rebuildAndReload()
        })

        // Picture in Picture (options.svelte: toggle)
        items.append(.toggle(title: "Picture in Picture", isActive: isPiPActive) { [weak self] in
            self?.onTogglePiP?()
            self?.dismissSelf()
        })

        // Deband (options.svelte: toggle — web does NOT dismiss, state updates in-place)
        items.append(.toggle(title: "Deband", isActive: isDebandActive) { [weak self] in
            self?.onToggleDeband?()
            self?.isDebandActive.toggle()
            self?.rebuildAndReload()
        })

        items.append(.action(title: "Keybinds") { [weak self] in
            self?.showKeybinds = true
            self?.keybindsView.refresh()
            self?.layoutTree(animated: false)
        })

        return items
    }

}

extension PlayerOptionsController: UITableViewDataSource, UITableViewDelegate, UIGestureRecognizerDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { items(for: tableView).count }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        let rows = items(for: tableView)
        guard let item = rows[safe: indexPath.row] else { return 0 }
        return rowHeight(for: item, width: menuWidth(for: rows))
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let level = tableLevels[ObjectIdentifier(tableView)] ?? 0
        guard let item = items(for: tableView)[safe: indexPath.row] else { return UITableViewCell() }
        let activeRow = activeIndices[safe: level]
        if case .subtitleDelay = item {
            guard let cell = tableView.dequeueReusableCell(withIdentifier: PlayerSubtitleDelayCell.reuseID, for: indexPath) as? PlayerSubtitleDelayCell
            else { return UITableViewCell() }
            cell.configure(value: subtitleDelay)
            cell.onValueChanged = { [weak self] value in
                self?.subtitleDelay = value
                self?.onSubtitleDelayChanged?(value)
            }
            return cell
        }
        guard let cell = tableView.dequeueReusableCell(withIdentifier: PlayerOptionCell.reuseID, for: indexPath) as? PlayerOptionCell
        else { return UITableViewCell() }
        switch item {
        case .expandable(let title, _):
            cell.configure(title: title, isActive: activeRow == indexPath.row, hasChevron: true, isBackRow: false,
                           isDimmed: activeRow != nil)
        case .selectable(let title, let active, _), .toggle(let title, let active, _):
            cell.configure(title: title, isActive: active, hasChevron: false, isBackRow: false,
                           isDimmed: activeRow != nil)
        case .action(let title, _):
            cell.configure(title: title, isActive: false, hasChevron: false, isBackRow: false,
                           isDimmed: activeRow != nil)
        case .chapter(let title, let time, _):
            cell.configure(title: title, isActive: false, hasChevron: false, isBackRow: false,
                           isDimmed: activeRow != nil, detail: time)
        case .playlist(let title, _):
            cell.configure(title: title, isActive: false, hasChevron: false, isBackRow: false,
                           isDimmed: activeRow != nil, textSize: 12)
        case .subtitleDelay: break
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let level = tableLevels[ObjectIdentifier(tableView)] ?? 0
        tableView.deselectRow(at: indexPath, animated: false)
        guard let item = items(for: tableView)[safe: indexPath.row] else { return }
        switch item {
        case .expandable(let title, let children):
            if activeIndices[safe: level] == indexPath.row { collapseLevel(level) }
            else { openLevel(from: level, row: indexPath.row, title: title, children: children) }
        case .selectable(_, _, let action), .toggle(_, _, let action), .action(_, let action),
             .chapter(_, _, let action), .playlist(_, let action):
            collapseLevel(level)
            action()
        case .subtitleDelay: break
        }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        if showKeybinds && keybindsView.containsContent(at: touch.location(in: keybindsView)) { return false }
        var target = touch.view
        while let current = target {
            if current === closeButton || menuViews.contains(where: { $0 === current }) { return false }
            target = current.superview
        }
        return true
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - PlayerOptionCell

// Mirrors interface Tree.Item and options.svelte's inline subtitle delay.

final class PlayerOptionCell: UITableViewCell {
    static let reuseID = "PlayerOptionCell"
    private let rowBackground = UIView()
    private let titleLabel = UILabel()
    private let detailLabel = UILabel()
    private let chevronImage = UIImageView()
    private var active = false
    private var dimmed = false
    private var titleTrailing: NSLayoutConstraint?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .none
        rowBackground.layer.cornerRadius = 4 // rounded-sm: --radius (8pt) - 4pt
        rowBackground.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(rowBackground)
        for label in [titleLabel, detailLabel] {
            label.translatesAutoresizingMaskIntoConstraints = false
            label.numberOfLines = 1
            label.lineBreakMode = .byTruncatingTail
            rowBackground.addSubview(label)
        }
        detailLabel.font = .nunito(ofSize: 14, weight: .bold)
        detailLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        chevronImage.image = UIImage.hayaseIcon("chevron-right", pointSize: 16)
        chevronImage.translatesAutoresizingMaskIntoConstraints = false
        rowBackground.addSubview(chevronImage)
        NSLayoutConstraint.activate([
            rowBackground.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            rowBackground.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            rowBackground.topAnchor.constraint(equalTo: contentView.topAnchor),
            rowBackground.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -2),
            titleLabel.leadingAnchor.constraint(equalTo: rowBackground.leadingAnchor, constant: 16),
            titleLabel.centerYAnchor.constraint(equalTo: rowBackground.centerYAnchor),
            detailLabel.trailingAnchor.constraint(equalTo: rowBackground.trailingAnchor, constant: -8),
            detailLabel.centerYAnchor.constraint(equalTo: rowBackground.centerYAnchor),
            chevronImage.trailingAnchor.constraint(equalTo: rowBackground.trailingAnchor, constant: -8),
            chevronImage.centerYAnchor.constraint(equalTo: rowBackground.centerYAnchor),
            chevronImage.widthAnchor.constraint(equalToConstant: 16),
            chevronImage.heightAnchor.constraint(equalToConstant: 16),
        ])
        addGestureRecognizer(UIHoverGestureRecognizer(target: self, action: #selector(hover(_:))))
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(title: String, isActive: Bool, hasChevron: Bool, isBackRow: Bool,
                   isDimmed: Bool = false, detail: String? = nil, textSize: CGFloat = 14) {
        active = isActive
        dimmed = isDimmed
        titleLabel.text = title
        titleLabel.font = .nunito(ofSize: textSize, weight: .bold)
        titleLabel.numberOfLines = textSize == 12 ? 1 : 0
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = textSize == 12 ? 16 : 14
        paragraph.maximumLineHeight = paragraph.minimumLineHeight
        paragraph.lineBreakMode = textSize == 12 ? .byTruncatingTail : .byWordWrapping
        titleLabel.lineBreakMode = paragraph.lineBreakMode
        titleLabel.attributedText = NSAttributedString(string: title, attributes: [
            .font: titleLabel.font as Any, .paragraphStyle: paragraph,
            .baselineOffset: (paragraph.minimumLineHeight - titleLabel.font.lineHeight) / 2,
        ])
        detailLabel.text = detail
        if let detail {
            // Chapter timestamps inherit Tree.Item's text-sm leading-none,
            // so their baseline must match the title rather than natural leading.
            let detailParagraph = NSMutableParagraphStyle()
            detailParagraph.minimumLineHeight = 14
            detailParagraph.maximumLineHeight = 14
            detailParagraph.lineBreakMode = .byTruncatingTail
            detailLabel.attributedText = NSAttributedString(string: detail, attributes: [
                .font: detailLabel.font as Any, .paragraphStyle: detailParagraph,
                .baselineOffset: (14 - detailLabel.font.lineHeight) / 2,
            ])
        }
        detailLabel.isHidden = detail == nil
        chevronImage.isHidden = !hasChevron
        titleTrailing?.isActive = false
        if hasChevron {
            titleTrailing = titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: chevronImage.leadingAnchor, constant: -8)
        } else if detail != nil {
            titleTrailing = titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: detailLabel.leadingAnchor, constant: -8)
        } else {
            titleTrailing = titleLabel.trailingAnchor.constraint(equalTo: rowBackground.trailingAnchor)
        }
        titleTrailing?.isActive = true
        rowBackground.alpha = dimmed ? 0.3 : 1
        updateBackground(hovering: false)
        accessibilityLabel = detail.map { title + ", " + $0 } ?? title
        accessibilityTraits = isActive ? [.button, .selected] : .button
    }

    private func updateBackground(hovering: Bool) {
        rowBackground.backgroundColor = active ? UIColor.HayaseTheme.primary
            : hovering ? UIColor.HayaseTheme.accent : .clear
        titleLabel.textColor = active ? UIColor.HayaseTheme.background
            : hovering ? UIColor.HayaseTheme.accentForeground : UIColor.HayaseTheme.foreground
        detailLabel.textColor = active ? UIColor.HayaseTheme.background : UIColor.HayaseTheme.mutedForeground
        chevronImage.tintColor = titleLabel.textColor
    }

    override func setHighlighted(_ highlighted: Bool, animated: Bool) {
        super.setHighlighted(highlighted, animated: animated)
        updateBackground(hovering: highlighted)
    }
    @objc private func hover(_ gesture: UIHoverGestureRecognizer) {
        updateBackground(hovering: gesture.state == .began || gesture.state == .changed)
    }
}

final class PlayerSubtitleDelayCell: UITableViewCell {
    static let reuseID = "PlayerSubtitleDelayCell"
    var onValueChanged: ((Double) -> Void)?
    private let inputField = Input(placeholder: "")
    private let delayLabel = UILabel()
    private let secLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .none
        delayLabel.text = "Delay"
        secLabel.text = "sec"
        for label in [delayLabel, secLabel] {
            label.font = .nunito(ofSize: 14, weight: .bold)
            label.textColor = UIColor.HayaseTheme.foreground
            label.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(label)
        }
        inputField.keyboardType = .numbersAndPunctuation // Includes minus for negative delay.
        inputField.borderStyle = .none
        inputField.showsFocusRing = false // options.svelte border-0 !ring-0
        inputField.backgroundColor = UIColor.HayaseTheme.muted
        inputField.font = .nunito(ofSize: 14, weight: .bold)
        inputField.layer.cornerRadius = 4
        inputField.textAlignment = .right
        inputField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 48, height: 36))
        inputField.rightView = UIView(frame: CGRect(x: 0, y: 0, width: 48, height: 36))
        inputField.rightViewMode = .always
        inputField.addTarget(self, action: #selector(valueChanged), for: .editingChanged)
        contentView.addSubview(inputField)
        contentView.bringSubviewToFront(delayLabel)
        contentView.bringSubviewToFront(secLabel)
        let toolbar = UIToolbar()
        toolbar.sizeToFit()
        toolbar.items = [UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil),
                         UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(finishEditing))]
        inputField.inputAccessoryView = toolbar
        NSLayoutConstraint.activate([
            inputField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            inputField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            inputField.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            inputField.heightAnchor.constraint(equalToConstant: 36),
            delayLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            delayLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            secLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            secLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func prepareForReuse() { super.prepareForReuse(); onValueChanged = nil }
    func configure(value: Double) { inputField.text = String(format: "%.1f", value) }
    @objc private func finishEditing() { inputField.resignFirstResponder() }
    @objc private func valueChanged() {
        guard let text = inputField.text,
              let value = Double(text.replacingOccurrences(of: ",", with: ".")), value.isFinite else { return }
        onValueChanged?(value)
    }
}

// MARK: - PlayerOptionsTransition

// Mirrors Dialog.Overlay fade (150ms) and Dialog.Content flyAndScale (200ms, cubicOut).

extension PlayerOptionsController: UIViewControllerTransitioningDelegate {
    func animationController(forPresented presented: UIViewController,
                             presenting: UIViewController, source: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        PlayerOptionsAnimator(presenting: true)
    }

    func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        PlayerOptionsAnimator(presenting: false)
    }

    func presentationController(forPresented presented: UIViewController, presenting: UIViewController?,
                                source: UIViewController) -> UIPresentationController? {
        PlayerOptionsPresentationController(presentedViewController: presented, presenting: presenting)
    }
}

private final class PlayerOptionsPresentationController: UIPresentationController {
    override var shouldRemovePresentersView: Bool { false }
    override var frameOfPresentedViewInContainerView: CGRect { containerView?.bounds ?? .zero }
    override func containerViewWillLayoutSubviews() {
        super.containerViewWillLayoutSubviews()
        presentedView?.frame = frameOfPresentedViewInContainerView
    }
}

private final class PlayerOptionsAnimator: NSObject, UIViewControllerAnimatedTransitioning {
    private let presenting: Bool
    init(presenting: Bool) { self.presenting = presenting }
    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval { 0.2 }
    func animateTransition(using context: UIViewControllerContextTransitioning) {
        guard let controller = context.viewController(forKey: presenting ? .to : .from) as? PlayerOptionsController else {
            context.completeTransition(false)
            return
        }
        if presenting {
            controller.view.frame = context.finalFrame(for: controller)
            context.containerView.addSubview(controller.view)
            controller.view.layoutIfNeeded()
            controller.setTransitionProgress(false)
            controller.setBackdropVisible(false)
        }
        let timing = UICubicTimingParameters(controlPoint1: CGPoint(x: 1.0 / 3.0, y: 1),
                                            controlPoint2: CGPoint(x: 2.0 / 3.0, y: 1))
        let animator = UIViewPropertyAnimator(duration: 0.2, timingParameters: timing)
        animator.addAnimations { controller.setTransitionProgress(self.presenting) }
        UIView.animate(withDuration: 0.15, delay: 0, options: [.curveLinear, .beginFromCurrentState]) {
            controller.setBackdropVisible(self.presenting)
        }
        animator.addCompletion { _ in
            let completed = !context.transitionWasCancelled
            if !completed {
                controller.setTransitionProgress(!self.presenting)
                controller.setBackdropVisible(!self.presenting)
            }
            context.completeTransition(completed)
        }
        animator.startAnimation()
    }
}

// MARK: - The player's side of options.svelte (the button, the sheet and the speed)

extension VideoPlayerViewController {
    func showOptionsSheet(openMenu: String? = nil) {
        guard presentedViewController == nil else { return }
        // Keep this synchronous path cheap so the menu appears immediately.
        // MKV language parsing can touch disk and is done from track readiness instead.
        let freshTracks = currentTracksForOptions()
        self.tracks = freshTracks

        let optionsVC = PlayerOptionsController()
        optionsVC.preparePresentation()

        // Populate data
        optionsVC.audioTracks = freshTracks.filter { $0.type == "audio" }
        optionsVC.videoTracks = freshTracks.filter { $0.type == "video" }
        optionsVC.subtitleTracks = freshTracks.filter { $0.type == "sub" }
        optionsVC.chapters = chapters
        optionsVC.currentSpeed = playbackRate
        optionsVC.subtitleDelay = subtitleDelay
        optionsVC.isDebandActive = Settings.deband
        optionsVC.isFullscreenActive = isFullscreenPresentation
        optionsVC.allVideos = playlistVideos
        optionsVC.currentVideoEntity = videoEntity
        optionsVC.displays = webTorrentDisplays

        if #available(iOS 15.0, *) {
            optionsVC.isPiPActive = pipController?.isPictureInPictureActive ?? false
        }

        // Wire callbacks
        optionsVC.onSelectAudioTrack = { [weak self] trackId in
            self?.surface.mpv.setAudioTrack(trackId)
            self?.showPlayerTextAnimation(freshTracks.first { $0.type == "audio" && $0.id == trackId }?.title ?? "Default")
        }

        optionsVC.onSelectVideoTrack = { [weak self] trackId in
            self?.surface.mpv.setVideoTrack(trackId)
            self?.showPlayerTextAnimation(freshTracks.first { $0.type == "video" && $0.id == trackId }?.title ?? "Default")
        }

        optionsVC.onSelectSubtitleTrack = { [weak self] trackId in
            self?.selectSubtitleTrack(trackId)
        }

        optionsVC.onSetSpeed = { [weak self] rate in
            guard let self else { return }
            self.playbackRate = rate
            self.surface.mpv.setSpeed(rate)
            self.updateSpeedLabel()
        }

        optionsVC.onSeekTo = { [weak self] time in
            self?.surface.mpv.seek(to: time)
        }

        optionsVC.onSwitchVideo = { [weak self] video in
            self?.selectPlaylistVideo(video)
        }

        optionsVC.onToggleDeband = {
            Settings.deband.toggle()
        }

        optionsVC.onTogglePiP = { [weak self] in
            guard let self else { return }
            if #available(iOS 15.0, *) {
                if self.pipController?.isPictureInPictureActive ?? false {
                    self.pipController?.stopPictureInPicture()
                } else {
                    self.pipController?.startPictureInPicture()
                }
            }
        }

        optionsVC.onToggleFullscreen = { [weak self] in
            self?.toggleFullscreenPresentation()
        }

        optionsVC.onScreenshot = { [weak self] in
            self?.captureScreenshot()
        }

        optionsVC.onSubtitleDelayChanged = { [weak self] delay in
            self?.subtitleDelay = delay
            self?.surface.mpv.setSubtitleDelay(delay)
        }
        optionsVC.onAddSubtitleFile = { [weak self] in
            let types = ["ass", "ssa", "srt", "vtt", "sub"].map { UTType(filenameExtension: $0) ?? .data }
            let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
            picker.delegate = self
            self?.present(picker, animated: true)
        }

        optionsVC.onSelectDisplay = { [weak self] display in
            self?.startCasting(to: display)
        }

        optionsVC.onDismiss = { [weak self] in
            self?.scheduleHide()
        }
        optionsVC.onKeybindAction = { [weak self] id, shift in self?.runPlayerKeybind(id, shift: shift) }
        if let openMenu { optionsVC.openRootMenu(named: openMenu) }

        present(optionsVC, animated: true)
    }

    @objc func optionsTapped() {
        hideWork?.cancel()
        showOptionsSheet()
    }

    /// Updates the speed label text. Hayase shows "x1.5" only when rate ≠ 1.
    func updateSpeedLabel() {
        if playbackRate != 1.0 && playbackRate != 0.0 {
            speedLabel.text = "x\(String(format: "%g", playbackRate))"
        } else {
            speedLabel.text = ""
        }
    }

    @objc func speedLabelTapped() {
        hideWork?.cancel()
        showOptionsSheet()
    }
}
