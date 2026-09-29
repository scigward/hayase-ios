// Mirrors: ui/torrentclient/library/table.svelte and cells.
import UIKit
import LibTorrent

// MARK: - LibraryColumnCell

/// Library cell matching Hayase's library/table.svelte data model.
/// All columns remain visible inside the horizontally scrolling table.
final class LibraryColumnCell: UITableViewCell {
    static let reuseID = "LibraryColumnCell"

    var onOpen: (() -> Void)?
    var onSelectionToggle: (() -> Void)?

    private let seriesLabel = LibraryColumnCell.makeLabel(size: 14, weight: .regular, color: TorrentClientStyle.foreground, lines: 0)
    private let torrentNameLabel = LibraryColumnCell.makeLabel(size: 12, weight: .regular, color: TorrentClientStyle.foreground, lines: 0)
    private let episodeLabel = LibraryColumnCell.makeLabel(size: 14, weight: .regular, color: TorrentClientStyle.mutedForeground)
    private let filesLabel = LibraryColumnCell.makeLabel(size: 14, weight: .regular, color: TorrentClientStyle.foreground)
    private let sizeLabel = LibraryColumnCell.makeLabel(size: 14, weight: .regular, color: TorrentClientStyle.foreground)
    private let statusLabel: UILabel = {
        let label = LibraryColumnCell.makeLabel(size: 14, weight: .regular, color: TorrentClientStyle.foreground)
        label.textAlignment = .left
        return label
    }()
    private let statusDot: UIView = {
        let view = UIView()
        view.layer.cornerRadius = 4
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    private lazy var statusStack: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [statusDot, statusLabel])
        stack.axis = .horizontal
        stack.spacing = 8
        stack.alignment = .center
        return stack
    }()
    private let dateLabel = LibraryColumnCell.makeLabel(size: 14, weight: .regular, color: TorrentClientStyle.foreground)
    private let selectButton: UIButton = {
        let button = UIButton(type: .system)
        button.tintColor = TorrentClientStyle.foreground
        button.accessibilityLabel = "Select torrent"
        return button
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupCellUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupCellUI()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        onOpen = nil
        onSelectionToggle = nil
    }

    private static func makeLabel(size: CGFloat, weight: UIFont.Weight, color: UIColor, lines: Int = 1) -> UILabel {
        let label = UILabel()
        label.font = .nunito(ofSize: size, weight: weight)
        label.textColor = color
        label.numberOfLines = lines
        label.lineBreakMode = lines == 0 ? .byCharWrapping : .byTruncatingTail
        label.adjustsFontSizeToFitWidth = lines == 1
        label.minimumScaleFactor = 0.7
        return label
    }

    private func setupCellUI() {
        selectionStyle = .default
        TorrentClientStyle.configureTableCell(self)
        selectedBackgroundView = UIView()
        selectedBackgroundView?.backgroundColor = TorrentClientStyle.accent

        let tap = UITapGestureRecognizer(target: self, action: #selector(rowTapped))
        tap.cancelsTouchesInView = true
        tap.delegate = self
        contentView.addGestureRecognizer(tap)

        selectButton.addTarget(self, action: #selector(selectionButtonTapped), for: .touchUpInside)
        selectButton.setContentHuggingPriority(.required, for: .horizontal)
        selectButton.setContentCompressionResistancePriority(.required, for: .horizontal)

        torrentNameLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        torrentNameLabel.textColor = TorrentClientStyle.foreground
        torrentNameLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        torrentNameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let stack = UIStackView(arrangedSubviews: [seriesLabel, episodeLabel, filesLabel, sizeLabel, statusStack, dateLabel, torrentNameLabel, selectButton])
        stack.axis = .horizontal
        stack.spacing = TorrentClientStyle.columnSpacing
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 56),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),

            seriesLabel.widthAnchor.constraint(equalToConstant: 288),
            torrentNameLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 288),
            episodeLabel.widthAnchor.constraint(equalToConstant: 60),
            filesLabel.widthAnchor.constraint(equalToConstant: 45),
            sizeLabel.widthAnchor.constraint(equalToConstant: 76),
            statusStack.widthAnchor.constraint(equalToConstant: 110),
            dateLabel.widthAnchor.constraint(equalToConstant: 96),
            statusDot.widthAnchor.constraint(equalToConstant: 8),
            statusDot.heightAnchor.constraint(equalToConstant: 8),
            selectButton.widthAnchor.constraint(equalToConstant: 32),
            selectButton.heightAnchor.constraint(equalToConstant: 24),
        ])

        for view in [seriesLabel, episodeLabel, filesLabel, sizeLabel, statusStack, dateLabel, selectButton] {
            view.setContentHuggingPriority(.required, for: .horizontal)
            view.setContentCompressionResistancePriority(.required, for: .horizontal)
        }
    }

    @objc private func rowTapped() {
        onOpen?()
    }

    @objc private func selectionButtonTapped() {
        onSelectionToggle?()
    }

    override func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        var view = touch.view
        while let current = view {
            if current === selectButton { return false }
            view = current.superview
        }
        return true
    }

    func configure(entry: WebTorrentLibraryEntry, seriesTitle: String, isSelected: Bool, compact: Bool) {
        applyLayout(compact: compact)
        seriesLabel.text = seriesTitle
        episodeLabel.text = entry.episode.map { String($0) } ?? "?"
        filesLabel.text = "\(entry.files)"
        sizeLabel.text = TorrentDetailViewController.fastPrettyBytes(entry.size)
        dateLabel.text = formattedDate(entry.date)
        torrentNameLabel.text = entry.name.isEmpty ? entry.hash : entry.name
        configureStatus(progress: entry.progress)
        configureSelection(isSelected)
    }

    func configure(handle: TorrentHandle, entity: Torrents?, isSelected: Bool, compact: Bool) {
        applyLayout(compact: compact)
        let snap = TorrentService.sharedTorrentService.withActiveHandle(handle, default: nil) { activeHandle -> TorrentHandle.Snapshot? in
            activeHandle.snapshot
        }

        seriesLabel.text = entity?.animes.map { AniListUtil.title(for: $0) } ?? "?"
        let episodeCount = entity?.videos?.count ?? 0
        episodeLabel.text = episodeCount > 0 ? "\(episodeCount)" : "?"
        torrentNameLabel.text = entity?.torrentName ?? snap?.name ?? handle.infoHashes.best.hex
        filesLabel.text = "\(snap?.files.count ?? 0)"
        sizeLabel.text = TorrentDetailViewController.fastPrettyBytes(snap?.total ?? 0)
        dateLabel.text = "—"

        let progress: Double
        if let snap, snap.total > 0 {
            progress = Double(snap.totalDone) / Double(snap.total)
        } else {
            progress = 0
        }
        configureStatus(progress: progress)
        configureSelection(isSelected)
    }

    private func applyLayout(compact: Bool) {
        dateLabel.isHidden = false
        filesLabel.isHidden = false
        sizeLabel.isHidden = false
    }

    private func configureSelection(_ isSelected: Bool) {
        let icon = isSelected ? "square-check" : "square"
        selectButton.setImage(UIImage.hayaseIcon(icon, withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)), for: .normal)
        selectButton.accessibilityValue = isSelected ? "Selected" : "Not selected"
    }

    private func configureStatus(progress: Double) {
        let clamped = max(0, min(progress, 1))
        if clamped == 1 {
            statusLabel.text = "Completed"
            statusDot.backgroundColor = TorrentClientStyle.green500
        } else {
            statusLabel.text = "In Progress"
            statusDot.backgroundColor = TorrentClientStyle.blue500
        }
        statusLabel.textColor = TorrentClientStyle.foreground
    }

    private func formattedDate(_ timestamp: TimeInterval?) -> String {
        guard let timestamp, timestamp > 0 else { return "—" }
        let date = Date(timeIntervalSince1970: timestamp / (timestamp > 10_000_000_000 ? 1000 : 1))
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}
