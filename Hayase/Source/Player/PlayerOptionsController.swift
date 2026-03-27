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
}

// MARK: - Language helpers

/// Maps ISO 639-2/3 language codes to human-readable names.
/// Mirrors the web interface's `capitalize` display of language groups.
private func languageName(for code: String) -> String {
    let locale = Locale.current
    if let name = locale.localizedString(forLanguageCode: code) {
        return name.prefix(1).uppercased() + name.dropFirst()
    }
    return code.uppercased()
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

/// Fullscreen transparent overlay presenting a tree-style options menu.
/// The visual design matches Hayase's `options.svelte` + Tree components:
/// - Dark rounded bordered container (w-64 → 256pt)
/// - Items: `py-2.5 pl-4 font-bold text-sm rounded-sm`
/// - Active item: white bg / black text
/// - Expandable items show a chevron on the right
/// - Tapping outside the container dismisses the menu
final class PlayerOptionsController: UIViewController {

    // MARK: - Configuration callbacks

    var onSelectAudioTrack: ((Int) -> Void)?
    var onSelectSubtitleTrack: ((Int) -> Void)?
    var onSetSpeed: ((Double) -> Void)?
    var onSeekTo: ((Double) -> Void)?
    var onSwitchVideo: ((Videos) -> Void)?
    var onToggleDeband: (() -> Void)?
    var onTogglePiP: (() -> Void)?
    var onSubtitleDelayChanged: ((Double) -> Void)?
    var onDismiss: (() -> Void)?

    // MARK: - Input data

    var audioTracks: [MPVTrack] = []
    var subtitleTracks: [MPVTrack] = []
    var chapters: [MPVChapter] = []
    var currentSpeed: Double = 1.0
    var subtitleDelay: Double = 0.0
    var isDebandActive: Bool = false
    var isPiPActive: Bool = false
    var allVideos: [Videos] = []
    var currentVideoEntity: Videos?

    // MARK: - UI

    /// The dark rounded menu container — matches `menu.svelte`:
    /// `w-64 bg-black rounded-md border p-1 shadow-md`
    private let containerView = UIView()
    private let tableView = UITableView(frame: .zero, style: .plain)

    /// Navigation stack for drill-down. Each entry is (title, items).
    private var navigationStack: [(title: String?, items: [OptionItem])] = []

    /// Width of the menu container (web: w-64 = 16rem ≈ 256px).
    private let menuWidth: CGFloat = 264

    /// Dynamic height constraint — updated whenever menu content changes.
    private var containerHeightConstraint: NSLayoutConstraint?
    /// Maximum height for the menu container.
    private var maxMenuHeight: CGFloat = 500

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.5)

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
        tableView.reloadData()
        updateContainerHeight()
    }

    override var prefersStatusBarHidden: Bool { true }

    // MARK: - Container setup

    private func setupContainer() {
        // menu.svelte: bg-black rounded-md border p-1 shadow-md
        containerView.backgroundColor = .black
        containerView.layer.cornerRadius = 6
        containerView.layer.borderWidth = 1
        containerView.layer.borderColor = UIColor(white: 0.2, alpha: 1).cgColor
        containerView.layer.shadowColor = UIColor.black.cgColor
        containerView.layer.shadowOpacity = 0.5
        containerView.layer.shadowRadius = 12
        containerView.clipsToBounds = true
        containerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(containerView)

        maxMenuHeight = min(view.bounds.height * 0.75, 500)
        let heightConstraint = containerView.heightAnchor.constraint(equalToConstant: maxMenuHeight)
        containerHeightConstraint = heightConstraint

        NSLayoutConstraint.activate([
            containerView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            containerView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            containerView.widthAnchor.constraint(equalToConstant: menuWidth),
            heightConstraint,
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
        let audioGroups = groupByLanguage(audioTracks)
        if !audioGroups.isEmpty {
            let audioChildren: [OptionItem] = audioGroups.map { group in
                let langTitle = languageName(for: group.lang)
                let trackItems: [OptionItem] = group.tracks.map { track in
                    .selectable(title: track.title ?? track.displayName,
                                isActive: track.isSelected) { [weak self] in
                        self?.onSelectAudioTrack?(track.id)
                        self?.dismissSelf()
                    }
                }
                if trackItems.count == 1 {
                    // Single track in this language — show directly under language
                    return trackItems[0]
                }
                return .expandable(title: langTitle, children: trackItems)
            }
            if audioChildren.count == 1, case .expandable = audioChildren[0] {
                // Single language group — flatten
                items.append(.expandable(title: "Audio", children: audioChildren))
            } else {
                items.append(.expandable(title: "Audio", children: audioChildren))
            }
        }

        // Subtitles — grouped by language (options.svelte: normalizeSubs)
        if !subtitleTracks.isEmpty {
            var subChildren: [OptionItem] = []
            // OFF option
            let currentSid = subtitleTracks.first(where: { $0.isSelected })?.id
            subChildren.append(.selectable(title: "OFF", isActive: currentSid == nil) { [weak self] in
                self?.onSelectSubtitleTrack?(0)
                self?.dismissSelf()
            })
            let subGroups = groupByLanguage(subtitleTracks)
            for group in subGroups {
                let langTitle = languageName(for: group.lang)
                let trackItems: [OptionItem] = group.tracks.map { track in
                    .selectable(title: track.title ?? track.displayName,
                                isActive: track.isSelected) { [weak self] in
                        self?.onSelectSubtitleTrack?(track.id)
                        self?.dismissSelf()
                    }
                }
                if trackItems.count == 1 {
                    // Single track in this language — show directly
                    subChildren.append(.selectable(
                        title: langTitle,
                        isActive: group.tracks[0].isSelected) { [weak self] in
                            self?.onSelectSubtitleTrack?(group.tracks[0].id)
                            self?.dismissSelf()
                        })
                } else {
                    subChildren.append(.expandable(title: langTitle, children: trackItems))
                }
            }
            items.append(.expandable(title: "Subtitles", children: subChildren))
        }

        // Chapters (options.svelte: chapters section)
        if !chapters.isEmpty {
            let chapterItems: [OptionItem] = chapters.map { ch in
                let ts = formatTime(ch.time)
                return .action(title: "\(ch.title)  \(ts)") { [weak self] in
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

        // Playlist (options.svelte: videoFiles)
        if allVideos.count > 1 {
            let playlistItems: [OptionItem] = allVideos.map { video in
                let name = video.videoName
                    ?? video.videoPath?.components(separatedBy: "/").last
                    ?? "Video"
                let isActive = video == currentVideoEntity
                return .selectable(title: name, isActive: isActive) { [weak self] in
                    self?.onSwitchVideo?(video)
                    self?.dismissSelf()
                }
            }
            items.append(.expandable(title: "Playlist", children: playlistItems))
        }

        // Picture in Picture (options.svelte: toggle)
        items.append(.toggle(title: "Picture in Picture", isActive: isPiPActive) { [weak self] in
            self?.onTogglePiP?()
            self?.dismissSelf()
        })

        // Deband (options.svelte: toggle)
        items.append(.toggle(title: "Deband", isActive: isDebandActive) { [weak self] in
            self?.onToggleDeband?()
            self?.dismissSelf()
        })

        return items
    }

    // MARK: - Navigation

    private var currentItems: [OptionItem] {
        navigationStack.last?.items ?? []
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

    /// Recalculates the container height to fit the table content,
    /// capped at `maxMenuHeight`. Called after every table reload.
    private func updateContainerHeight() {
        tableView.layoutIfNeeded()
        let contentH = tableView.contentSize.height + 8 // 4pt padding top + bottom
        let clamped = min(contentH, maxMenuHeight)
        containerHeightConstraint?.constant = max(clamped, 48) // minimum reasonable height
    }

    // MARK: - Helpers

    @objc private func dismissSelf() {
        dismiss(animated: true) { [weak self] in
            self?.onDismiss?()
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
        // +1 for back button when in a sub-level
        let extra = navigationStack.count > 1 ? 1 : 0
        return currentItems.count + extra
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        // Back button row
        if navigationStack.count > 1 && indexPath.row == 0 {
            guard let cell = tableView.dequeueReusableCell(withIdentifier: TreeItemCell.reuseID, for: indexPath) as? TreeItemCell else { return UITableViewCell() }
            let title = navigationStack.last?.title ?? "Back"
            cell.configure(title: "← \(title)", isActive: false, hasChevron: false, isBackRow: true)
            return cell
        }

        let itemIndex = navigationStack.count > 1 ? indexPath.row - 1 : indexPath.row
        guard itemIndex >= 0, itemIndex < currentItems.count else { return UITableViewCell() }
        let item = currentItems[itemIndex]

        switch item {
        case .expandable(let title, _):
            guard let cell = tableView.dequeueReusableCell(withIdentifier: TreeItemCell.reuseID, for: indexPath) as? TreeItemCell else { return UITableViewCell() }
            cell.configure(title: title, isActive: false, hasChevron: true, isBackRow: false)
            return cell

        case .selectable(let title, let isActive, _):
            guard let cell = tableView.dequeueReusableCell(withIdentifier: TreeItemCell.reuseID, for: indexPath) as? TreeItemCell else { return UITableViewCell() }
            cell.configure(title: title, isActive: isActive, hasChevron: false, isBackRow: false)
            return cell

        case .action(let title, _):
            guard let cell = tableView.dequeueReusableCell(withIdentifier: TreeItemCell.reuseID, for: indexPath) as? TreeItemCell else { return UITableViewCell() }
            cell.configure(title: title, isActive: false, hasChevron: false, isBackRow: false)
            return cell

        case .toggle(let title, let isActive, _):
            guard let cell = tableView.dequeueReusableCell(withIdentifier: TreeItemCell.reuseID, for: indexPath) as? TreeItemCell else { return UITableViewCell() }
            cell.configure(title: title, isActive: isActive, hasChevron: false, isBackRow: false)
            return cell
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: false)

        // Back row
        if navigationStack.count > 1 && indexPath.row == 0 {
            popLevel()
            return
        }

        let itemIndex = navigationStack.count > 1 ? indexPath.row - 1 : indexPath.row
        guard itemIndex >= 0, itemIndex < currentItems.count else { return }
        let item = currentItems[itemIndex]

        switch item {
        case .expandable(let title, let children):
            pushLevel(title: title, items: children)
        case .selectable(_, _, let action):
            action()
        case .action(_, let action):
            action()
        case .toggle(_, _, let action):
            action()
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

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .none

        let bg = UIView()
        bg.layer.cornerRadius = 3
        selectedBackgroundView = bg

        contentView.addSubview(titleLabel)
        contentView.addSubview(chevronImage)

        titleLabel.font = .systemFont(ofSize: 14, weight: .bold)
        titleLabel.textColor = .white
        titleLabel.numberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let chevronConfig = UIImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        chevronImage.image = UIImage(systemName: "chevron.right", withConfiguration: chevronConfig)
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

    func configure(title: String, isActive: Bool, hasChevron: Bool, isBackRow: Bool) {
        titleLabel.text = title
        chevronImage.isHidden = !hasChevron

        if isActive {
            // item.svelte: class:!bg-white={active} class:!text-black={active}
            contentView.backgroundColor = .white
            contentView.layer.cornerRadius = 3
            titleLabel.textColor = .black
            chevronImage.tintColor = .black
        } else {
            contentView.backgroundColor = .clear
            contentView.layer.cornerRadius = 0
            titleLabel.textColor = isBackRow ? UIColor(white: 0.6, alpha: 1) : .white
            chevronImage.tintColor = .white
        }
    }

    override func setHighlighted(_ highlighted: Bool, animated: Bool) {
        super.setHighlighted(highlighted, animated: animated)
        if highlighted && contentView.backgroundColor != .white {
            // hover:bg-accent
            contentView.backgroundColor = UIColor(white: 0.15, alpha: 1)
            contentView.layer.cornerRadius = 3
        } else if !highlighted && contentView.backgroundColor != .white {
            contentView.backgroundColor = .clear
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
        delayLabel.font = .systemFont(ofSize: 14, weight: .bold)
        delayLabel.textColor = .white
        delayLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(delayLabel)

        secLabel.text = "sec"
        secLabel.font = .systemFont(ofSize: 14, weight: .regular)
        secLabel.textColor = .white
        secLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(secLabel)

        inputField.keyboardType = .decimalPad
        inputField.textColor = .white
        inputField.textAlignment = .right
        inputField.font = .systemFont(ofSize: 14, weight: .regular)
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

    func configure(value: Double) {
        inputField.text = String(format: "%.1f", value)
    }

    @objc private func valueChanged() {
        if let text = inputField.text, let val = Double(text) {
            onValueChanged?(val)
        }
    }
}
