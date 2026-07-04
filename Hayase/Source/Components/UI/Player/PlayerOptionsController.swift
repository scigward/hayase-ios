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

// MARK: - Data model

/// Represents a single item in the tree menu.
/// Mirrors the web interface's `<Tree.Item>` component.
private enum OptionItem {
    /// An item with children (shows chevron, drills down on tap).
    case expandable(title: String, children: [OptionItem])
    /// A selectable leaf item (shows active dot, fires action).
    case selectable(title: String, isActive: Bool, action: () -> Void)
    /// A plain action item (no active state).
    case action(title: String, action: () -> Void)
    /// A toggle item (shows active dot, toggles on tap).
    case toggle(title: String, isActive: Bool, action: () -> Void)
    /// Inline subtitle delay input row.
    case subtitleDelay
}

// MARK: - Language helpers

/// Mirrors Svelte's `class='capitalize'` for language group labels.
/// The interface displays raw track language keys, not localized names.
private func languageName(for code: String) -> String {
    guard let first = code.first else { return code }
    return first.uppercased() + code.dropFirst()
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
        return lang
    }
    return fallbackLanguage
}

/// Groups tracks by language, mirroring `util.ts → normalizeTracks()`.
/// If no track has language "eng"/"en", untagged tracks default to "eng";
/// otherwise they default to "unk".
private func groupByLanguage(_ tracks: [MPVTrack]) -> [(lang: String, tracks: [MPVTrack])] {
    let hasEng = tracks.contains { $0.lang == "eng" || $0.lang == "en" }
    var groups: [(key: String, values: [MPVTrack])] = []
    var dict: [String: Int] = [:]  // lang → index in groups
    for track in tracks {
        let lang = track.lang.flatMap({ $0.isEmpty ? nil : $0 })
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
/// - Active item: white bg / black text
/// - Expandable items show a chevron on the right
/// - Tapping outside the container dismisses the menu
final class PlayerOptionsController: UIViewController {

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
    var onSubtitleDelayChanged: ((Double) -> Void)?
    var onDismiss: (() -> Void)?

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

    // MARK: - UI

    /// The dark rounded menu container — matches `menu.svelte`:
    /// `w-64 bg-black rounded-md border p-1 shadow-md`
    private let containerView = UIView()
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let wideTreeView = UIView()
    private let stripedLayer = HayaseStripePattern.customBackground.makeLayer()

    /// Navigation stack for drill-down. Each entry is (title, items).
    private var navigationStack: [(title: String?, items: [OptionItem])] = []

    /// Width of the menu container (web: w-64 = 16rem ≈ 256px).
    private let menuWidth: CGFloat = 256

    /// Dynamic height constraint — updated whenever menu content changes.
    private var containerHeightConstraint: NSLayoutConstraint?
    private var wideTreeWidthConstraint: NSLayoutConstraint?
    private var wideTreeHeightConstraint: NSLayoutConstraint?
    private var wideTableLevels: [ObjectIdentifier: Int] = [:]
    private var activeIndices: [Int] = []
    private var isUsingWideTree = false
    /// Maximum height for the menu container.
    private var maxMenuHeight: CGFloat = 500

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        stripedLayer.frame = view.bounds
        view.layer.addSublayer(stripedLayer)

        // Tap-to-dismiss background (matches options.svelte on:pointerdown|self={close})
        let tapBG = UITapGestureRecognizer(target: self, action: #selector(dismissSelf))
        tapBG.cancelsTouchesInView = false
        tapBG.delegate = self
        view.addGestureRecognizer(tapBG)

        setupContainer()
        setupTableView()

        // Build root menu and push it
        let root = buildRootMenu()
        navigationStack = [(title: nil, items: root)]
        reloadCurrentPresentation()
    }

    override var prefersStatusBarHidden: Bool { true }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard stripedLayer.frame != view.bounds else { return }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        stripedLayer.frame = view.bounds
        CATransaction.commit()
        stripedLayer.setNeedsDisplay()
        if isUsingWideTree != shouldUseWideTree {
            reloadCurrentPresentation()
        }
    }

    // MARK: - Container setup

    private func setupContainer() {
        // menu.svelte: bg-black rounded-md border p-1 shadow-md
        containerView.backgroundColor = UIColor.HayaseTheme.background
        containerView.layer.cornerRadius = 6
        containerView.layer.borderWidth = 1
        containerView.layer.borderColor = UIColor.HayaseTheme.border.cgColor
        containerView.layer.shadowColor = UIColor.black.cgColor
        containerView.layer.shadowOpacity = 0.22
        containerView.layer.shadowRadius = 6
        containerView.layer.shadowOffset = CGSize(width: 0, height: 4)
        containerView.clipsToBounds = false
        containerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(containerView)

        wideTreeView.backgroundColor = .clear
        wideTreeView.clipsToBounds = false
        wideTreeView.translatesAutoresizingMaskIntoConstraints = false
        wideTreeView.isHidden = true
        view.addSubview(wideTreeView)

        maxMenuHeight = min(view.bounds.height * 0.75, 500)
        let heightConstraint = containerView.heightAnchor.constraint(equalToConstant: maxMenuHeight)
        let wideWidthConstraint = wideTreeView.widthAnchor.constraint(equalToConstant: menuWidth)
        let wideHeightConstraint = wideTreeView.heightAnchor.constraint(equalToConstant: maxMenuHeight)
        containerHeightConstraint = heightConstraint
        wideTreeWidthConstraint = wideWidthConstraint
        wideTreeHeightConstraint = wideHeightConstraint

        NSLayoutConstraint.activate([
            containerView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            containerView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            containerView.widthAnchor.constraint(equalToConstant: menuWidth),
            heightConstraint,

            wideTreeView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            wideTreeView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            wideWidthConstraint,
            wideHeightConstraint,
        ])
    }

    private func setupTableView() {
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.showsVerticalScrollIndicator = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(TreeItemCell.self, forCellReuseIdentifier: TreeItemCell.reuseID)
        tableView.register(SubtitleDelayCell.self, forCellReuseIdentifier: SubtitleDelayCell.reuseID)
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 40
        tableView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 4),
            tableView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 4),
            tableView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -4),
            tableView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -4),
        ])
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
                return .action(title: "\(title)  \(ts)") { [weak self] in
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
        if !allVideos.isEmpty {
            let playlistItems: [OptionItem] = allVideos.map { video in
                let name = video.videoName
                    ?? video.videoPath?.components(separatedBy: "/").last
                    ?? "Video"
                return .action(title: name) { [weak self] in
                    self?.onSwitchVideo?(video)
                }
            }
            items.append(.expandable(title: "Playlist", children: playlistItems))
        }

        // Fullscreen (options.svelte: Fullscreen tree item)
        items.append(.toggle(title: "Fullscreen", isActive: isFullscreenActive) { [weak self] in
            self?.dismissWithCompletion { [weak self] in
                self?.onToggleFullscreen?()
            }
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

        return items
    }

    // MARK: - Navigation

    private var shouldUseWideTree: Bool {
        view.bounds.width >= 700 || traitCollection.horizontalSizeClass == .regular
    }

    private var currentItems: [OptionItem] {
        navigationStack.last?.items ?? []
    }

    private func items(for tableView: UITableView) -> [OptionItem] {
        if tableView === self.tableView { return currentItems }
        let level = wideTableLevels[ObjectIdentifier(tableView)] ?? 0
        guard navigationStack.indices.contains(level) else { return [] }
        return navigationStack[level].items
    }

    private func reloadCurrentPresentation() {
        isUsingWideTree = shouldUseWideTree
        containerView.isHidden = isUsingWideTree
        wideTreeView.isHidden = !isUsingWideTree
        if isUsingWideTree {
            reloadWideTree()
        } else {
            tableView.reloadData()
            updateContainerHeight()
        }
    }

    private func pushLevel(title: String, items: [OptionItem]) {
        navigationStack.append((title: title, items: items))
        animateTransition(forward: true)
    }

    private func popLevel() {
        guard navigationStack.count > 1 else { return }
        navigationStack.removeLast()
        animateTransition(forward: false)
    }

    private func openWideLevel(from level: Int, row: Int, title: String, items: [OptionItem]) {
        navigationStack = Array(navigationStack.prefix(level + 1))
        navigationStack.append((title: title, items: items))
        activeIndices = Array(activeIndices.prefix(level))
        activeIndices.append(row)
        reloadWideTree()
    }

    private func collapseWideLevel(_ level: Int) {
        navigationStack = Array(navigationStack.prefix(level + 1))
        activeIndices = Array(activeIndices.prefix(level))
        reloadWideTree()
    }

    private func animateTransition(forward: Bool) {
        let direction: CGFloat = forward ? -1 : 1
        let snapshot = tableView.snapshotView(afterScreenUpdates: false)
        if let snap = snapshot {
            snap.frame = tableView.frame
            containerView.addSubview(snap)
        }
        tableView.reloadData()
        updateContainerHeight()
        tableView.transform = CGAffineTransform(translationX: -direction * menuWidth, y: 0)
        UIView.animate(withDuration: 0.25, delay: 0, options: .curveEaseInOut) {
            self.tableView.transform = .identity
            snapshot?.transform = CGAffineTransform(translationX: direction * self.menuWidth, y: 0)
            snapshot?.alpha = 0
            self.view.layoutIfNeeded()
        } completion: { _ in
            snapshot?.removeFromSuperview()
        }
    }

    /// Recalculates the compact menu height to fit the table content,
    /// capped at `maxMenuHeight`. Called after every table reload.
    private func updateContainerHeight() {
        tableView.layoutIfNeeded()
        let contentH = tableView.contentSize.height + 8 // 4pt padding top + bottom
        let clamped = min(contentH, maxMenuHeight)
        containerHeightConstraint?.constant = max(clamped, 48) // minimum reasonable height
    }

    private func reloadWideTree() {
        wideTreeView.subviews.forEach { $0.removeFromSuperview() }
        wideTableLevels.removeAll()

        let columnGap: CGFloat = 8
        let rowHeight: CGFloat = 40
        let submenuYOffset: CGFloat = -5

        let columnHeights = navigationStack.map { columnHeight(for: $0.items) }
        var yOffsets = Array(repeating: CGFloat.zero, count: navigationStack.count)
        if navigationStack.count > 1 {
            for level in 1..<navigationStack.count {
                let parentRow = CGFloat(activeIndices[safe: level - 1] ?? 0)
                yOffsets[level] = yOffsets[level - 1] + parentRow * rowHeight + submenuYOffset
            }
        }

        let minY = yOffsets.min() ?? 0
        let normalizedY = yOffsets.map { $0 - minY }
        let totalWidth = CGFloat(navigationStack.count) * menuWidth + CGFloat(max(0, navigationStack.count - 1)) * columnGap
        let totalHeight = zip(normalizedY, columnHeights).map { $0 + $1 }.max() ?? 48
        wideTreeWidthConstraint?.constant = totalWidth
        wideTreeHeightConstraint?.constant = totalHeight

        for level in navigationStack.indices {
            let menu = makeMenuContainer(dimmed: activeIndices.indices.contains(level))
            let table = makeColumnTableView(level: level)
            menu.addSubview(table)
            wideTreeView.addSubview(menu)

            let x = CGFloat(level) * (menuWidth + columnGap)
            NSLayoutConstraint.activate([
                menu.leadingAnchor.constraint(equalTo: wideTreeView.leadingAnchor, constant: x),
                menu.topAnchor.constraint(equalTo: wideTreeView.topAnchor, constant: normalizedY[level]),
                menu.widthAnchor.constraint(equalToConstant: menuWidth),
                menu.heightAnchor.constraint(equalToConstant: columnHeights[level]),

                table.topAnchor.constraint(equalTo: menu.topAnchor, constant: 4),
                table.leadingAnchor.constraint(equalTo: menu.leadingAnchor, constant: 4),
                table.trailingAnchor.constraint(equalTo: menu.trailingAnchor, constant: -4),
                table.bottomAnchor.constraint(equalTo: menu.bottomAnchor, constant: -4),
            ])
        }

        view.layoutIfNeeded()
    }

    private func columnHeight(for items: [OptionItem]) -> CGFloat {
        min(max(CGFloat(items.count) * 40 + 8, 48), maxMenuHeight)
    }

    private func makeMenuContainer(dimmed: Bool) -> UIView {
        let menu = UIView()
        menu.backgroundColor = UIColor.HayaseTheme.background.withAlphaComponent(dimmed ? 0.30 : 1)
        menu.layer.cornerRadius = 6
        menu.layer.borderWidth = 1
        menu.layer.borderColor = UIColor.HayaseTheme.border.cgColor
        menu.layer.shadowColor = UIColor.black.cgColor
        menu.layer.shadowOpacity = 0.22
        menu.layer.shadowRadius = 6
        menu.layer.shadowOffset = CGSize(width: 0, height: 4)
        menu.clipsToBounds = false
        menu.translatesAutoresizingMaskIntoConstraints = false
        return menu
    }

    private func makeColumnTableView(level: Int) -> UITableView {
        let table = UITableView(frame: .zero, style: .plain)
        table.backgroundColor = .clear
        table.separatorStyle = .none
        table.showsVerticalScrollIndicator = false
        table.dataSource = self
        table.delegate = self
        table.register(TreeItemCell.self, forCellReuseIdentifier: TreeItemCell.reuseID)
        table.register(SubtitleDelayCell.self, forCellReuseIdentifier: SubtitleDelayCell.reuseID)
        table.rowHeight = UITableView.automaticDimension
        table.estimatedRowHeight = 40
        table.translatesAutoresizingMaskIntoConstraints = false
        wideTableLevels[ObjectIdentifier(table)] = level
        return table
    }

    /// Rebuilds the root menu and reloads the current presentation.
    /// Used for in-place state updates (e.g., Deband toggle) without dismissing.
    private func rebuildAndReload() {
        let root = buildRootMenu()
        if !navigationStack.isEmpty {
            navigationStack[0] = (title: nil, items: root)
        }
        reloadCurrentPresentation()
    }

    // MARK: - Helpers

    @objc private func dismissSelf() {
        dismissWithCompletion(nil)
    }

    private func dismissWithCompletion(_ completion: (() -> Void)?) {
        dismiss(animated: true) { [weak self] in
            self?.onDismiss?()
            completion?()
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        let total = Int(max(0, seconds))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - UITableViewDataSource / UITableViewDelegate

extension PlayerOptionsController: UITableViewDataSource, UITableViewDelegate {

    func numberOfSections(in tableView: UITableView) -> Int { 1 }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if tableView === self.tableView {
            // +1 for back button when compact navigation is in a sub-level.
            let extra = navigationStack.count > 1 ? 1 : 0
            return currentItems.count + extra
        }
        return items(for: tableView).count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let isCompactTable = tableView === self.tableView
        let level = wideTableLevels[ObjectIdentifier(tableView)] ?? navigationStack.count - 1

        // Back button row in compact mode only. Wide mode mirrors Tree.Sub panels.
        if isCompactTable && navigationStack.count > 1 && indexPath.row == 0 {
            guard let cell = tableView.dequeueReusableCell(withIdentifier: TreeItemCell.reuseID, for: indexPath) as? TreeItemCell else { return UITableViewCell() }
            let title = navigationStack.last?.title ?? "Back"
            cell.configure(title: "← \(title)", isActive: false, hasChevron: false, isBackRow: true)
            return cell
        }

        let itemIndex = isCompactTable && navigationStack.count > 1 ? indexPath.row - 1 : indexPath.row
        let tableItems = items(for: tableView)
        guard itemIndex >= 0, itemIndex < tableItems.count else { return UITableViewCell() }
        let item = tableItems[itemIndex]
        let activeRow = isCompactTable ? nil : activeIndices[safe: level]
        let hasOpenChild = activeRow != nil

        switch item {
        case .expandable(let title, _):
            guard let cell = tableView.dequeueReusableCell(withIdentifier: TreeItemCell.reuseID, for: indexPath) as? TreeItemCell else { return UITableViewCell() }
            cell.configure(title: title, isActive: activeRow == itemIndex, hasChevron: true, isBackRow: false, isDimmed: hasOpenChild && activeRow != itemIndex)
            return cell

        case .selectable(let title, let isActive, _):
            guard let cell = tableView.dequeueReusableCell(withIdentifier: TreeItemCell.reuseID, for: indexPath) as? TreeItemCell else { return UITableViewCell() }
            cell.configure(title: title, isActive: isActive, hasChevron: false, isBackRow: false, isDimmed: hasOpenChild)
            return cell

        case .action(let title, _):
            guard let cell = tableView.dequeueReusableCell(withIdentifier: TreeItemCell.reuseID, for: indexPath) as? TreeItemCell else { return UITableViewCell() }
            cell.configure(title: title, isActive: false, hasChevron: false, isBackRow: false, isDimmed: hasOpenChild)
            return cell

        case .toggle(let title, let isActive, _):
            guard let cell = tableView.dequeueReusableCell(withIdentifier: TreeItemCell.reuseID, for: indexPath) as? TreeItemCell else { return UITableViewCell() }
            cell.configure(title: title, isActive: isActive, hasChevron: false, isBackRow: false, isDimmed: hasOpenChild)
            return cell

        case .subtitleDelay:
            guard let cell = tableView.dequeueReusableCell(withIdentifier: SubtitleDelayCell.reuseID, for: indexPath) as? SubtitleDelayCell else { return UITableViewCell() }
            cell.configure(value: subtitleDelay)
            cell.onValueChanged = { [weak self] value in
                self?.subtitleDelay = value
                self?.onSubtitleDelayChanged?(value)
            }
            return cell
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: false)

        let isCompactTable = tableView === self.tableView
        let level = wideTableLevels[ObjectIdentifier(tableView)] ?? navigationStack.count - 1

        // Back row in compact mode only.
        if isCompactTable && navigationStack.count > 1 && indexPath.row == 0 {
            popLevel()
            return
        }

        let itemIndex = isCompactTable && navigationStack.count > 1 ? indexPath.row - 1 : indexPath.row
        let tableItems = items(for: tableView)
        guard itemIndex >= 0, itemIndex < tableItems.count else { return }
        let item = tableItems[itemIndex]

        switch item {
        case .expandable(let title, let children):
            if isCompactTable {
                pushLevel(title: title, items: children)
            } else if activeIndices[safe: level] == itemIndex {
                collapseWideLevel(level)
            } else {
                openWideLevel(from: level, row: itemIndex, title: title, items: children)
            }
        case .selectable(_, _, let action):
            if !isCompactTable && level == 0 { collapseWideLevel(0) }
            action()
        case .action(_, let action):
            if !isCompactTable && level == 0 { collapseWideLevel(0) }
            action()
        case .toggle(_, _, let action):
            if !isCompactTable && level == 0 { collapseWideLevel(0) }
            action()
        case .subtitleDelay:
            break
        }
    }
}

// MARK: - UIGestureRecognizerDelegate

extension PlayerOptionsController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        // Only dismiss when tapping the background, not the container
        let location = touch.location(in: view)
        return !containerView.frame.contains(location)
    }
}

// MARK: - TreeItemCell

/// A single row in the tree menu.
/// Matches item.svelte: `w-full hover:bg-accent flex items-center rounded-sm
/// py-2.5 font-bold text-sm pl-4` with active = `!bg-white !text-black`.
private final class TreeItemCell: UITableViewCell {

    static let reuseID = "TreeItemCell"

    private let titleLabel = UILabel()
    private let chevronImage = UIImageView()
    private var showsActiveState = false
    private var isDimmed = false

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .none

        let bg = UIView()
        bg.layer.cornerRadius = 3
        selectedBackgroundView = bg

        contentView.addSubview(titleLabel)
        contentView.addSubview(chevronImage)

        titleLabel.font = .nunito(ofSize: 14, weight: .bold)
        titleLabel.textColor = .white
        titleLabel.numberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        chevronImage.image = UIImage.hayaseIcon("chevron-right", pointSize: 16)
        chevronImage.tintColor = .white
        chevronImage.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            titleLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: chevronImage.leadingAnchor, constant: -8),

            chevronImage.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            chevronImage.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            chevronImage.widthAnchor.constraint(equalToConstant: 16),
            chevronImage.heightAnchor.constraint(equalToConstant: 16),

            contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 40),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(title: String, isActive: Bool, hasChevron: Bool, isBackRow: Bool, isDimmed: Bool = false) {
        showsActiveState = isActive
        self.isDimmed = isDimmed
        titleLabel.text = title
        chevronImage.isHidden = !hasChevron
        contentView.alpha = isDimmed ? 0.30 : 1

        if isActive {
            // item.svelte: class:!bg-primary={active} class:!text-background={active}
            contentView.backgroundColor = UIColor.HayaseTheme.primary
            contentView.layer.cornerRadius = 3
            titleLabel.textColor = UIColor.HayaseTheme.background
            chevronImage.tintColor = UIColor.HayaseTheme.background
        } else {
            contentView.backgroundColor = .clear
            contentView.layer.cornerRadius = 0
            titleLabel.textColor = isBackRow ? UIColor.HayaseTheme.mutedForeground : UIColor.HayaseTheme.foreground
            chevronImage.tintColor = UIColor.HayaseTheme.foreground
        }
    }

    override func setHighlighted(_ highlighted: Bool, animated: Bool) {
        super.setHighlighted(highlighted, animated: animated)
        guard !showsActiveState else { return }
        if highlighted {
            // hover:bg-accent
            contentView.backgroundColor = UIColor.HayaseTheme.accent
            contentView.layer.cornerRadius = 3
        } else {
            contentView.backgroundColor = .clear
            contentView.alpha = isDimmed ? 0.30 : 1
        }
    }
}

// MARK: - SubtitleDelayCell

/// Inline numeric input for subtitle delay, matching options.svelte:
/// `<Input type='number' step='0.1' bind:value={subtitleDelay} />`
private final class SubtitleDelayCell: UITableViewCell {

    static let reuseID = "SubtitleDelayCell"

    var onValueChanged: ((Double) -> Void)?
    private let inputField = UITextField()
    private let delayLabel = UILabel()
    private let secLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .none

        delayLabel.text = "Delay"
        delayLabel.font = .nunito(ofSize: 14, weight: .bold)
        delayLabel.textColor = UIColor.HayaseTheme.foreground
        delayLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(delayLabel)

        secLabel.text = "sec"
        secLabel.font = .nunito(ofSize: 14, weight: .regular)
        secLabel.textColor = UIColor.HayaseTheme.foreground
        secLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(secLabel)

        inputField.keyboardType = .decimalPad
        inputField.borderStyle = .none
        inputField.backgroundColor = .clear
        inputField.textColor = UIColor.HayaseTheme.foreground
        inputField.textAlignment = .right
        inputField.font = .nunito(ofSize: 14, weight: .regular)
        inputField.translatesAutoresizingMaskIntoConstraints = false
        inputField.addTarget(self, action: #selector(valueChanged), for: .editingChanged)
        contentView.addSubview(inputField)

        NSLayoutConstraint.activate([
            delayLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            delayLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

            secLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            secLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

            inputField.trailingAnchor.constraint(equalTo: secLabel.leadingAnchor, constant: -4),
            inputField.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            inputField.widthAnchor.constraint(equalToConstant: 60),

            contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 40),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override func prepareForReuse() {
        super.prepareForReuse()
        onValueChanged = nil
    }

    func configure(value: Double) {
        inputField.text = String(format: "%.1f", value)
    }

    @objc private func valueChanged() {
        if let text = inputField.text, let val = Double(text) {
            onValueChanged?(val)
        }
    }
}


private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
