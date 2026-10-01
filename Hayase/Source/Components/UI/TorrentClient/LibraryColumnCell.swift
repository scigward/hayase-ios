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
    var columnWidths: [CGFloat?] = [248, 60, 45, 76, 110, 96, nil, 18] { didSet { updateColumnWidths() } }
    private var widthConstraints: [Int: NSLayoutConstraint] = [:]
    private var dateTooltip: TorrentClientDateTooltip?
    private var dateWarning: String?
    private var rowSelected = false

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
    private let dateIcon = UIImageView(image: UIImage.hayaseIcon("clock-fading", pointSize: 16))
    private lazy var dateStack: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [dateIcon, dateLabel])
        stack.axis = .horizontal
        stack.spacing = 4
        stack.alignment = .center
        return stack
    }()
    private let selectButton: TorrentClientCheckbox = {
        let button = TorrentClientCheckbox()
        button.accessibilityLabel = "Select row"
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
        dateTooltip?.close()
        dateTooltip = nil
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { dateTooltip?.close(); dateTooltip = nil }
    }

    private static func makeLabel(size: CGFloat, weight: UIFont.Weight, color: UIColor, lines: Int = 1) -> UILabel {
        let label: UILabel = lines == 1 ? TorrentClientLabel() : UILabel()
        label.font = .nunito(ofSize: size, weight: weight)
        label.textColor = color
        label.numberOfLines = lines
        label.lineBreakMode = lines == 0 ? .byCharWrapping : .byTruncatingTail
        return label
    }

    private func setupCellUI() {
        selectionStyle = .none
        TorrentClientStyle.configureTableCell(self)
        let tap = UITapGestureRecognizer(target: self, action: #selector(rowTapped))
        tap.cancelsTouchesInView = true
        tap.delegate = self
        contentView.addGestureRecognizer(tap)
        contentView.addGestureRecognizer(UIHoverGestureRecognizer(target: self, action: #selector(rowHovered(_:))))
        dateStack.addGestureRecognizer(UIHoverGestureRecognizer(target: self, action: #selector(dateHovered(_:))))
        let dateHold = UILongPressGestureRecognizer(target: self, action: #selector(dateHeld(_:)))
        dateStack.addGestureRecognizer(dateHold)

        selectButton.addTarget(self, action: #selector(selectionButtonTapped), for: .touchUpInside)
        selectButton.setContentHuggingPriority(.required, for: .horizontal)
        selectButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        torrentNameLabel.font = .geistMono(ofSize: 12)
        torrentNameLabel.textColor = TorrentClientStyle.foreground
        torrentNameLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        torrentNameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let columnViews: [UIView] = [seriesLabel, episodeLabel, filesLabel, sizeLabel, statusStack, dateStack, torrentNameLabel, selectButton]
        let stack = UIStackView(arrangedSubviews: columnViews)
        stack.axis = .horizontal
        stack.spacing = TorrentClientStyle.columnSpacing
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            // Last CheckboxCell has zero td padding, with its 18pt glyph and
            // mx-4 creating a 50pt column. This keeps it centred like the header.
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 56),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),

            torrentNameLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 256),
            statusDot.widthAnchor.constraint(equalToConstant: 8),
            statusDot.heightAnchor.constraint(equalToConstant: 8),
            dateIcon.widthAnchor.constraint(equalToConstant: 16),
            dateIcon.heightAnchor.constraint(equalToConstant: 16),
            selectButton.heightAnchor.constraint(equalToConstant: 24),
        ])
        for (index, view) in columnViews.enumerated() {
            guard let width = columnWidths[index] else { continue }
            let constraint = view.widthAnchor.constraint(equalToConstant: width)
            constraint.isActive = true
            widthConstraints[index] = constraint
        }

        for view in [seriesLabel, episodeLabel, filesLabel, sizeLabel, statusStack, dateStack, selectButton] {
            view.setContentHuggingPriority(.required, for: .horizontal)
            view.setContentCompressionResistancePriority(.required, for: .horizontal)
        }
    }

    private func updateColumnWidths() {
        for (index, constraint) in widthConstraints where columnWidths.indices.contains(index) {
            constraint.constant = columnWidths[index] ?? constraint.constant
        }
    }

    @objc private func rowTapped(_ recognizer: UITapGestureRecognizer) {
        let selectionStart = contentView.bounds.width - (columnWidths.last.flatMap { $0 } ?? 18) - 32
        if recognizer.location(in: contentView).x >= selectionStart { onSelectionToggle?() }
        else { onOpen?() }
    }

    @objc private func selectionButtonTapped() {
        onSelectionToggle?()
    }

    @objc private func rowHovered(_ gesture: UIHoverGestureRecognizer) {
        let hovering = gesture.state == .began || gesture.state == .changed
        UIView.animate(withDuration: 0.15, delay: 0,
                       options: [.beginFromCurrentState, .allowUserInteraction]) {
            self.contentView.backgroundColor = self.rowSelected ? TorrentClientStyle.muted
                : hovering ? TorrentClientStyle.accent.withAlphaComponent(0.5) : .clear
        }
    }

    @objc private func dateHovered(_ gesture: UIHoverGestureRecognizer) {
        showDateTooltip(gesture.state == .began || gesture.state == .changed)
    }
    @objc private func dateHeld(_ gesture: UILongPressGestureRecognizer) {
        showDateTooltip(gesture.state == .began || gesture.state == .changed)
    }
    private func showDateTooltip(_ shown: Bool) {
        guard shown, let dateWarning else { dateTooltip?.close(); dateTooltip = nil; return }
        guard dateTooltip == nil else { return }
        let tooltip = TorrentClientDateTooltip(text: dateWarning, sourceView: dateStack)
        dateTooltip = tooltip
        tooltip.show()
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
        configureText(seriesLabel, text: seriesTitle, lineHeight: 20)
        episodeLabel.text = entry.episode.map { String($0) } ?? "?"
        filesLabel.text = "\(entry.files)"
        sizeLabel.text = entry.size == 0 ? "?" : TorrentDetailViewController.fastPrettyBytes(entry.size)
        configureDate(entry.date)
        configureText(torrentNameLabel, text: entry.name, lineHeight: 16)
        configureStatus(progress: entry.progress)
        configureSelection(isSelected)
    }

    func configure(handle: TorrentHandle, entity: Torrents?, isSelected: Bool, compact: Bool) {
        applyLayout(compact: compact)
        let snap = TorrentService.sharedTorrentService.withActiveHandle(handle, default: nil) { activeHandle -> TorrentHandle.Snapshot? in
            activeHandle.snapshot
        }

        configureText(seriesLabel, text: entity?.animes.map { AniListUtil.title(for: $0) } ?? "?", lineHeight: 20)
        let episodeCount = entity?.videos?.count ?? 0
        episodeLabel.text = episodeCount > 0 ? "\(episodeCount)" : "?"
        configureText(torrentNameLabel, text: entity?.torrentName ?? snap?.name ?? handle.infoHashes.best.hex, lineHeight: 16)
        filesLabel.text = "\(snap?.files.count ?? 0)"
        let size = snap?.total ?? 0
        sizeLabel.text = size == 0 ? "?" : TorrentDetailViewController.fastPrettyBytes(size)
        configureDate(nil)

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
        dateStack.isHidden = false
        filesLabel.isHidden = false
        sizeLabel.isHidden = false
    }

    private func configureText(_ label: UILabel, text: String, lineHeight: CGFloat) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = lineHeight
        paragraph.maximumLineHeight = lineHeight
        paragraph.lineBreakMode = .byCharWrapping
        label.attributedText = NSAttributedString(string: text, attributes: [
            .font: label.font as Any,
            .foregroundColor: label.textColor as Any,
            .paragraphStyle: paragraph,
            .baselineOffset: (lineHeight - label.font.lineHeight) / 2,
        ])
    }

    private func configureSelection(_ isSelected: Bool) {
        rowSelected = isSelected
        selectButton.isSelected = isSelected
        contentView.backgroundColor = isSelected ? TorrentClientStyle.muted : .clear
    }

    private func configureStatus(progress: Double) {
        statusDot.isHidden = progress == 0
        if progress == 0 {
            statusLabel.text = "?"
        } else if progress == 1 {
            statusLabel.text = "Completed"
            statusDot.backgroundColor = TorrentClientStyle.green500
        } else {
            statusLabel.text = "In Progress"
            statusDot.backgroundColor = TorrentClientStyle.blue500
        }
        statusLabel.textColor = TorrentClientStyle.foreground
    }

    private func configureDate(_ timestamp: TimeInterval?) {
        dateTooltip?.close()
        dateTooltip = nil
        let state = TorrentClientLibraryDate(timestamp)
        dateLabel.text = state.text
        dateLabel.textColor = state.color
        dateIcon.tintColor = state.color
        dateIcon.isHidden = state.warning == nil
        dateWarning = state.warning
        dateStack.accessibilityLabel = state.text
        dateStack.accessibilityHint = state.warning
    }
}
