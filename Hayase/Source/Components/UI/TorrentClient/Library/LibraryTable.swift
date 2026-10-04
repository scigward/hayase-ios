// Mirrors: ui/torrentclient/library/table.svelte and cells.

import CoreData
import Foundation
import UIKit

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
        onDPadClick = { [weak self] in self?.onOpen?() }
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
        sizeLabel.text = entry.size == 0 ? "?" : TorrentFormat.fastPrettyBytes(entry.size)
        configureDate(entry.date)
        configureText(torrentNameLabel, text: entry.name, lineHeight: 16)
        configureStatus(progress: entry.progress)
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

// MARK: - TorrentLibraryDeleteDialog

// Mirrors: interface/ui/torrentclient/library/table.svelte's delete confirmation.

final class TorrentLibraryDeleteDialog: SettingsDialogViewController {
    private let names: [String]
    private let onDelete: () -> Void
    private let header = UIStackView()
    private let footer = UIStackView()
    private let footerContainer = UIView()
    private let titleLabel = TorrentClientLabel()
    private let descriptionLabel = UILabel()
    private let list = UIScrollView()
    private let rows = UIStackView()
    private var listHeight: NSLayoutConstraint?
    private var footerLeading: NSLayoutConstraint?
    private var confirmed = false

    init(names: [String], onDelete: @escaping () -> Void) {
        self.names = names
        self.onDelete = onDelete
        super.init(title: "", maximumWidth: 1024)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        titleLabel.font = .nunito(ofSize: 18, weight: .semibold)
        titleLabel.textColor = UIColor.HayaseTheme.foreground
        titleLabel.lineHeight = 18
        titleLabel.letterSpacing = -0.45
        titleLabel.text = "Are you absolutely sure?"
        descriptionLabel.font = .nunito(ofSize: 14)
        descriptionLabel.textColor = UIColor.HayaseTheme.mutedForeground
        descriptionLabel.numberOfLines = 0
        configureDescription(alignment: .left)
        header.axis = .vertical
        header.spacing = 6
        header.addArrangedSubview(titleLabel)
        header.addArrangedSubview(descriptionLabel)
        header.addArrangedSubview(list)
        list.translatesAutoresizingMaskIntoConstraints = false
        list.showsHorizontalScrollIndicator = false
        rows.axis = .vertical
        rows.spacing = 8
        rows.translatesAutoresizingMaskIntoConstraints = false
        list.addSubview(rows)
        for name in names {
            let row = UIView()
            let label = TorrentClientLabel()
            label.lineHeight = 16
            label.font = .nunito(ofSize: 12)
            label.textColor = UIColor.HayaseTheme.mutedForeground
            label.text = name
            label.lineBreakMode = .byTruncatingTail
            let bullet = TorrentClientLabel()
            bullet.lineHeight = 16
            bullet.font = .nunito(ofSize: 12)
            bullet.textColor = UIColor.HayaseTheme.mutedForeground
            bullet.text = "•"
            [label, bullet].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; row.addSubview($0) }
            NSLayoutConstraint.activate([
                row.heightAnchor.constraint(equalToConstant: 16),
                label.topAnchor.constraint(equalTo: row.topAnchor),
                label.bottomAnchor.constraint(equalTo: row.bottomAnchor),
                label.leadingAnchor.constraint(equalTo: row.leadingAnchor),
                label.trailingAnchor.constraint(equalTo: row.trailingAnchor),
                bullet.topAnchor.constraint(equalTo: row.topAnchor),
                bullet.bottomAnchor.constraint(equalTo: row.bottomAnchor),
                bullet.trailingAnchor.constraint(equalTo: row.leadingAnchor, constant: -5),
            ])
            rows.addArrangedSubview(row)
        }
        let listHeight = list.heightAnchor.constraint(equalToConstant: 32)
        self.listHeight = listHeight
        NSLayoutConstraint.activate([
            rows.topAnchor.constraint(equalTo: list.contentLayoutGuide.topAnchor, constant: 16),
            rows.leadingAnchor.constraint(equalTo: list.contentLayoutGuide.leadingAnchor, constant: 20),
            rows.trailingAnchor.constraint(equalTo: list.contentLayoutGuide.trailingAnchor),
            rows.bottomAnchor.constraint(equalTo: list.contentLayoutGuide.bottomAnchor, constant: -16),
            rows.widthAnchor.constraint(equalTo: list.frameLayoutGuide.widthAnchor, constant: -20),
            listHeight,
        ])
        let delete = SelectButton()
        delete.restingBackground = UIColor.HayaseTheme.destructive
        delete.selectedBackground = UIColor.HayaseTheme.destructive.withAlphaComponent(0.9)
        delete.restingTint = UIColor.HayaseTheme.destructiveForeground
        delete.selectedTint = UIColor.HayaseTheme.destructiveForeground
        configure(delete, title: "Delete")
        delete.applyShadowSm()
        delete.addTarget(self, action: #selector(confirm), for: .touchUpInside)
        let cancel = SelectButton()
        cancel.applySecondaryVariant()
        configure(cancel, title: "Cancel")
        cancel.addTarget(self, action: #selector(close), for: .touchUpInside)
        footer.addArrangedSubview(delete)
        footer.addArrangedSubview(cancel)
        content.addArrangedSubview(header)
        footer.translatesAutoresizingMaskIntoConstraints = false
        footerContainer.addSubview(footer)
        footerLeading = footer.leadingAnchor.constraint(equalTo: footerContainer.leadingAnchor)
        NSLayoutConstraint.activate([
            footer.topAnchor.constraint(equalTo: footerContainer.topAnchor),
            footer.bottomAnchor.constraint(equalTo: footerContainer.bottomAnchor),
            footer.trailingAnchor.constraint(equalTo: footerContainer.trailingAnchor),
            footer.leadingAnchor.constraint(greaterThanOrEqualTo: footerContainer.leadingAnchor),
        ])
        content.addArrangedSubview(footerContainer)
    }

    private func configure(_ button: SelectButton, title: String) {
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = .nunito(ofSize: 14, weight: .medium)
        button.contentEdgeInsets = UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
        button.heightAnchor.constraint(equalToConstant: 36).isActive = true
        button.setContentHuggingPriority(.required, for: .horizontal)
    }

    private func configureDescription(alignment: NSTextAlignment) {
        let font = UIFont.nunito(ofSize: 14)
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = 20
        paragraph.maximumLineHeight = 20
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byWordWrapping
        descriptionLabel.textAlignment = alignment
        descriptionLabel.attributedText = NSAttributedString(
            string: "You are about to permanently delete \(names.count) torrent(s) from your library. This action cannot be undone.",
            attributes: [
                .font: font, .foregroundColor: UIColor.HayaseTheme.mutedForeground,
                .paragraphStyle: paragraph, .baselineOffset: (20 - font.lineHeight) / 2,
            ])
    }

    override func viewDidLayoutSubviews() {
        let viewport = view.window?.rootViewController?.view.bounds.width ?? view.bounds.width
        let compact = viewport < 640
        // Dialog.Header: text-center sm:text-left. Dialog.Footer:
        // flex-col-reverse sm:flex-row sm:justify-end sm:space-x-2.
        titleLabel.textAlignment = compact ? .center : .left
        let descriptionAlignment: NSTextAlignment = compact ? .center : .left
        if descriptionLabel.textAlignment != descriptionAlignment {
            configureDescription(alignment: descriptionAlignment)
        }
        footer.axis = compact ? .vertical : .horizontal
        footer.alignment = compact ? .fill : .trailing
        footerLeading?.isActive = compact
        footer.spacing = compact ? 0 : 8
        if footer.arrangedSubviews.count == 2 {
            let desiredFirst = compact ? "Cancel" : "Delete"
            if (footer.arrangedSubviews.first as? UIButton)?.currentTitle != desiredFirst {
                let first = footer.arrangedSubviews[0]
                footer.removeArrangedSubview(first)
                first.removeFromSuperview()
                footer.addArrangedSubview(first)
            }
        }
        // A horizontal footer should keep its two intrinsic buttons at the
        // right, not distribute their titles across the whole dialog.
        footer.distribution = compact ? .fillEqually : .fill
        if !compact {
            footer.setContentHuggingPriority(.required, for: .horizontal)
        }
        let listContentHeight = 32 + CGFloat(names.count) * 16 + CGFloat(max(0, names.count - 1)) * 8
        listHeight?.constant = min(listContentHeight, view.bounds.height * 0.5)
        let titleWidth = titleLabel.intrinsicContentSize.width
        let descriptionWidth = ((descriptionLabel.text ?? "") as NSString).size(withAttributes: [.font: UIFont.nunito(ofSize: 14)]).width
        let nameWidth = names.map { ($0 as NSString).size(withAttributes: [.font: UIFont.nunito(ofSize: 12)]).width + 20 }.max() ?? 0
        preferredPanelWidth = max(max(titleWidth, descriptionWidth), nameWidth) + 48
        super.viewDidLayoutSubviews()
    }

    @objc private func confirm() {
        guard !confirmed else { return }
        confirmed = true
        onDelete()
        close()
    }
}

// MARK: - TorrentLibrarySort

// Mirrors: ui/torrentclient/library/table.svelte column accessors.

enum TorrentLibrarySort {
    static func less(_ lhs: WebTorrentLibraryEntry, _ rhs: WebTorrentLibraryEntry,
                     column: Int, ascending: Bool) -> Bool {
        func ordered<T: Comparable>(_ a: T, _ b: T) -> Bool {
            if a == b { return lhs.hash < rhs.hash }
            return ascending ? a < b : a > b
        }
        switch column {
        case 0: return ordered(lhs.mediaID ?? 0, rhs.mediaID ?? 0)
        case 1: return ordered(lhs.episode ?? 0, rhs.episode ?? 0)
        case 2: return ordered(lhs.files, rhs.files)
        case 3: return ordered(lhs.size, rhs.size)
        // library/table.svelte sorts the numeric progress accessor, not its
        // rendered Completed / In Progress status.
        case 4: return ordered(lhs.progress, rhs.progress)
        case 5: return ordered(lhs.date ?? 0, rhs.date ?? 0)
        default: return ordered(lhs.name, rhs.name)
        }
    }
}

// MARK: - The library page (library/table.svelte): the list, the search, the selection and what opening an entry does

extension DownloadsViewController {
    func buildLibraryUI() {
        TorrentClientStyle.configurePlainContentView(libraryView)

        librarySearchField.translatesAutoresizingMaskIntoConstraints = false
        librarySearchField.addTarget(self, action: #selector(librarySearchChanged), for: .editingChanged)
        libraryView.addSubview(librarySearchField)

        let rescanConfig = UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)
        libraryRescanButton.setImage(UIImage.hayaseIcon("folder-sync", withConfiguration: rescanConfig), for: .normal)
        TorrentClientStyle.configureIconButton(libraryRescanButton, variant: .secondary)
        libraryRescanButton.applySecondaryVariant()
        libraryRescanButton.accessibilityLabel = "Rescan torrents"
        libraryRescanButton.addTarget(self, action: #selector(rescanLibrary), for: .touchUpInside)
        libraryRescanButton.translatesAutoresizingMaskIntoConstraints = false

        TorrentClientStyle.configureIconButton(libraryDeleteButton, variant: .destructive)
        libraryDeleteButton.restingBackground = UIColor.HayaseTheme.destructive
        libraryDeleteButton.selectedBackground = UIColor.HayaseTheme.destructive.withAlphaComponent(0.9)
        libraryDeleteButton.restingTint = UIColor.HayaseTheme.destructiveForeground
        libraryDeleteButton.selectedTint = UIColor.HayaseTheme.destructiveForeground
        libraryDeleteButton.setLayeredIcon(.trash, size: 16)
        libraryDeleteButton.applyShadowSm()
        libraryDeleteButton.accessibilityLabel = "Delete torrents"
        libraryDeleteButton.addTarget(self, action: #selector(deleteSelectedLibraryEntries), for: .touchUpInside)
        libraryDeleteButton.translatesAutoresizingMaskIntoConstraints = false

        let buttonRow = UIStackView(arrangedSubviews: [libraryRescanButton, libraryDeleteButton])
        buttonRow.axis = .horizontal
        buttonRow.spacing = 8
        buttonRow.translatesAutoresizingMaskIntoConstraints = false
        libraryView.addSubview(buttonRow)

        librarySelectionLabel.translatesAutoresizingMaskIntoConstraints = false
        libraryView.addSubview(librarySelectionLabel)

        let borderContainer = UIView()
        TorrentClientStyle.configureTableShell(borderContainer)
        borderContainer.translatesAutoresizingMaskIntoConstraints = false
        libraryView.addSubview(borderContainer)

        libraryTableView = UITableView(frame: .zero, style: .plain)
        libraryTableView.translatesAutoresizingMaskIntoConstraints = false
        libraryTableView.delegate = self
        libraryTableView.dataSource = self
        libraryTableView.register(LibraryColumnCell.self, forCellReuseIdentifier: LibraryColumnCell.reuseID)
        libraryTableView.rowHeight = 56
        libraryTableView.estimatedRowHeight = 56
        TorrentClientStyle.configureTableView(libraryTableView)
        libraryMinimumWidth = TorrentClientStyle.installScrollableTable(libraryTableView, in: borderContainer,
            minimumWidth: TorrentClientColumnWidths.minimumTableWidth(libraryColumnWidths,
                flexibleMinimums: [6: TorrentClientColumnWidths.libraryNameMinimum], hasSelectionColumn: true))

        NSLayoutConstraint.activate([
            libraryRescanButton.widthAnchor.constraint(equalToConstant: 36),
            libraryRescanButton.heightAnchor.constraint(equalToConstant: 36),
            libraryDeleteButton.widthAnchor.constraint(equalToConstant: 36),
            libraryDeleteButton.heightAnchor.constraint(equalToConstant: 36),

            librarySearchField.topAnchor.constraint(equalTo: libraryView.topAnchor),
            librarySearchField.leadingAnchor.constraint(equalTo: libraryView.leadingAnchor),
            librarySearchField.trailingAnchor.constraint(equalTo: buttonRow.leadingAnchor, constant: -8),
            librarySearchField.heightAnchor.constraint(equalToConstant: 36),

            buttonRow.topAnchor.constraint(equalTo: libraryView.topAnchor),
            buttonRow.trailingAnchor.constraint(equalTo: libraryView.trailingAnchor),

            librarySelectionLabel.topAnchor.constraint(equalTo: librarySearchField.bottomAnchor, constant: 8),
            librarySelectionLabel.leadingAnchor.constraint(equalTo: libraryView.leadingAnchor),
            librarySelectionLabel.trailingAnchor.constraint(equalTo: libraryView.trailingAnchor),

            borderContainer.topAnchor.constraint(equalTo: librarySelectionLabel.bottomAnchor, constant: 4),
            borderContainer.leadingAnchor.constraint(equalTo: libraryView.leadingAnchor),
            borderContainer.trailingAnchor.constraint(equalTo: libraryView.trailingAnchor),
            borderContainer.bottomAnchor.constraint(equalTo: libraryView.bottomAnchor),

        ])
    }

    @objc func librarySearchChanged() {
        refreshLibrary()
    }

    @objc func rescanLibrary() {
        let hashes = Array(selectedLibraryHashes)
        guard !hashes.isEmpty, !libraryActionInFlight else { return }

        libraryActionInFlight = true
        updateLibrarySelectionLabel()
        let toast = AppErrorToast.startPromise(title: "Rescanning torrents...",
            description: "This may take a VERY long while depending on the number of torrents.")
        TorrentBackendManager.shared.rescanWebTorrents(hashes: hashes) { [weak self] result in
            DispatchQueue.main.async {
                if case .failure(let error) = result {
                    NSLog("[Torrent Library] %@", error.localizedDescription)
                    AppErrorToast.resolvePromise(toast, title: "Failed to rescan torrents\n" + error.localizedDescription, failed: true)
                } else { AppErrorToast.resolvePromise(toast, title: "Rescan complete") }
                guard let self else { return }
                self.libraryActionInFlight = false
                self.updateLibrarySelectionLabel()
                self.update()
            }
        }
    }

    func refreshLibrary() {
        let query = librarySearchField.text?.lowercased() ?? ""
        webFilteredLibraryEntries = query.isEmpty
            ? webLibraryEntries
            : webLibraryEntries.filter { ($0.name.isEmpty ? $0.hash : $0.name).lowercased().contains(query) }
        if let column = librarySortColumn {
            webFilteredLibraryEntries.sort {
                TorrentLibrarySort.less($0, $1, column: column, ascending: librarySortAscending)
            }
        }
        let currentHashes = Set(webLibraryEntries.map { $0.hash })
        selectedLibraryHashes.formIntersection(currentHashes)
        updateLibrarySelectionLabel()
        libraryColumnWidths = TorrentClientColumnWidths.library(entries: webFilteredLibraryEntries)
        libraryMinimumWidth?.constant = TorrentClientColumnWidths.minimumTableWidth(libraryColumnWidths,
            flexibleMinimums: [6: TorrentClientColumnWidths.libraryNameMinimum], hasSelectionColumn: true)
        libraryTableView?.reloadData()
    }

    func librarySeriesTitle(for entry: WebTorrentLibraryEntry) -> String {
        guard let mediaID = entry.mediaID, mediaID > 0 else { return "?" }
        if let cached = animeTitleCache[mediaID] { return cached }
        if failedAnimeTitles.contains(mediaID) { return "?" }

        let context = CoreDataService.sharedCoreDataService.mainQueueContext
        let request = NSFetchRequest<Animes>(entityName: Animes.entityName)
        request.predicate = NSPredicate(format: "animeAnilistId == %@", NSNumber(value: mediaID))
        request.fetchLimit = 1

        if let anime = (try? context.fetch(request))?.first {
            let title = AniListUtil.title(for: anime)
            if title != "TBA" {
                animeTitleCache[mediaID] = title
                return title
            }
        }

        if pendingAnimeTitles.insert(mediaID).inserted {
            AniListClient.shared.singleTitleResult(id: mediaID) { [weak self] result in
                guard let self else { return }
                self.pendingAnimeTitles.remove(mediaID)
                switch result {
                case .success(let title):
                    if let name = title?.userPreferred {
                        self.animeTitleCache[mediaID] = name
                    } else {
                        self.failedAnimeTitles.insert(mediaID)
                    }
                case .failure: self.failedAnimeTitles.insert(mediaID)
                }
                self.libraryTableView?.reloadData()
            }
        }
        return "..."
    }

    func updateLibrarySelectionLabel() {
        let rowCount = webFilteredLibraryEntries.count
        librarySelectionLabel.text = "\(selectedLibraryHashes.count) of \(rowCount) row(s) selected."
        let hasSelection = !selectedLibraryHashes.isEmpty && !libraryActionInFlight
        TorrentClientStyle.setIconButtonEnabled(libraryRescanButton, enabled: hasSelection, variant: .secondary)
        TorrentClientStyle.setIconButtonEnabled(libraryDeleteButton, enabled: hasSelection, variant: .destructive)
    }

    var allVisibleLibraryRowsSelected: Bool {
        let hashes = Set(webFilteredLibraryEntries.map { $0.hash })
        return !hashes.isEmpty && hashes.isSubset(of: selectedLibraryHashes)
    }

    func toggleLibrarySelection(hash: String, tableView: UITableView?, indexPath: IndexPath) {
        if selectedLibraryHashes.contains(hash) {
            selectedLibraryHashes.remove(hash)
        } else {
            selectedLibraryHashes.insert(hash)
        }
        updateLibrarySelectionLabel()
        tableView?.reloadData() // refresh the select-all header too
    }

    func openWebTorrentLibraryEntry(_ entry: WebTorrentLibraryEntry) {
        guard let sourceMediaID = entry.mediaID, sourceMediaID > 0, !entry.hash.isEmpty else { return }
        if restoreMiniPlayerIfAlreadyPlaying(hash: entry.hash, episode: entry.episode) { return }
        guard openingLibraryPlaybackHash != entry.hash else { return }
        guard let torrentEntity = torrentEntityForLibraryEntry(entry) else { return }

        cancelPendingLibraryPlayback()
        openingLibraryPlaybackHash = entry.hash
        selectedHex = entry.hash

        let episode = entry.episode ?? 0
        let mediaID = entry.mediaID ?? torrentEntity.animes?.animeAnilistId?.intValue ?? 0
        let videoService = VideoService(torrentEntity: torrentEntity, episode: episode)
        pendingLibraryPlaybackService = videoService

        MiniPlayerManager.shared.close()
        let player = VideoPlayerViewController()
        pendingLibraryPlayer = player
        player.beginMetadataLoading(owner: self)
        player.onCancelMetadataLoading = { [weak self] in self?.cancelPendingLibraryPlayback() }
        Router.shared.navigateToPlayer(player, hostTabIndex: hayaseTabIndex)

        pendingLibraryPlaybackObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name(VideoService.LocalVideosDidUpdateNotification),
            object: nil,
            queue: .main
        ) { [weak self, weak videoService] _ in
            guard let self, let videoService else { return }
            self.finishWebTorrentLibraryPlayback(videoService: videoService,
                                                 torrentEntity: torrentEntity,
                                                 mediaID: mediaID,
                                                 episode: episode)
        }

        let timeout = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let player = self.pendingLibraryPlayer
            self.openingLibraryPlaybackHash = nil
            self.cancelPendingLibraryPlayback()
            player?.finishMetadataLoading(error: NSError(domain: "TorrentLibraryPlayback", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Timed out while preparing this torrent."]))
        }
        pendingLibraryPlaybackTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.libraryPlaybackTimeout, execute: timeout)

        videoService.UpdateLocalVideo()
    }

    func torrentEntityForLibraryEntry(_ entry: WebTorrentLibraryEntry) -> Torrents? {
        let context = CoreDataService.sharedCoreDataService.mainQueueContext
        let request = NSFetchRequest<Torrents>(entityName: Torrents.entityName)
        request.predicate = NSPredicate(format: "torrentHashString == %@", entry.hash)
        request.fetchLimit = 1

        let torrentEntity = (try? context.fetch(request).first)
            ?? NSEntityDescription.insertNewObject(forEntityName: Torrents.entityName, into: context) as? Torrents

        guard let torrentEntity else { return nil }
        torrentEntity.torrentHashString = entry.hash
        torrentEntity.torrentName = entry.name.isEmpty ? entry.hash : entry.name
        if torrentEntity.torrentDownloadURL?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
            torrentEntity.torrentDownloadURL = "magnet:?xt=urn:btih:\(entry.hash)"
        }
        torrentEntity.torrentSize = NSNumber(value: Double(entry.size) / 1024.0 / 1024.0)

        if let mediaID = entry.mediaID, mediaID > 0 {
            VideoService.linkAnime(mediaID: mediaID, to: torrentEntity, fallbackTitle: animeTitleCache[mediaID])
        }

        try? context.save()
        return torrentEntity
    }

    func finishWebTorrentLibraryPlayback(videoService: VideoService,
                                                 torrentEntity: Torrents,
                                                 mediaID: Int,
                                                 episode: Int) {
        // Other playback services also emit this notification. Wait for this
        // request's fresh metadata instead of reopening cached video URLs.
        guard pendingLibraryPlaybackService === videoService,
              videoService.hasFinishedUpdatingLocalVideos else { return }
        let context = CoreDataService.sharedCoreDataService.mainQueueContext
        let fetch = NSFetchRequest<Videos>(entityName: Videos.entityName)
        fetch.predicate = NSPredicate(format: "torrents == %@", torrentEntity)
        fetch.sortDescriptors = [NSSortDescriptor(key: "videoIndex", ascending: true),
                                 NSSortDescriptor(key: "videoName", ascending: true)]
        let videos = (try? context.fetch(fetch)) ?? []

        if videos.isEmpty && videoService.lastError == nil { return }

        guard let player = pendingLibraryPlayer else { cancelPendingLibraryPlayback(); return }
        cancelPendingLibraryPlayback(clearService: false)

        guard videoService.lastError == nil, !videos.isEmpty else {
            let message = videoService.lastError?.localizedDescription ?? "No playable video files were found."
            openingLibraryPlaybackHash = nil
            pendingLibraryPlaybackService = nil
            player.finishMetadataLoading(error: videoService.lastError ?? NSError(domain: "TorrentLibraryPlayback", code: 2,
                userInfo: [NSLocalizedDescriptionKey: message]))
            return
        }

        guard let selectedVideo = bestVideoForLibraryPlayback(videos: videos, episode: episode) else {
            openingLibraryPlaybackHash = nil
            pendingLibraryPlaybackService = nil
            player.finishMetadataLoading(error: NSError(domain: "TorrentLibraryPlayback", code: 2,
                userInfo: [NSLocalizedDescriptionKey: "No playable video files were found."]))
            return
        }
        let selectedIndex = selectedVideo.videoIndex?.uintValue ?? 0
        let resolvedPath = videoService.UpdateFilePathForFileIndex(selectedIndex)
        if !resolvedPath.isEmpty, selectedVideo.videoPath != resolvedPath {
            selectedVideo.videoPath = resolvedPath
            try? context.save()
        }

        player.videoEntity = selectedVideo
        player.videoService = videoService
        player.fileIndex = selectedIndex
        player.anilistID = mediaID
        player.episodeNumber = episode > 0 ? episode : (TorrentBatchResolver.extractEpisodeNumber(from: selectedVideo.videoName ?? "") ?? 0)
        player.totalEpisodes = torrentEntity.animes?.animeTotalEps?.intValue ?? 0
        player.allVideos = videos
        player.currentVideoIndex = videos.firstIndex(of: selectedVideo) ?? 0
        player.onEpisodeChange = { [weak self] episode, media in
            self?.handleEpisodeChangeFromTorrentClient(episode: episode,
                                                       media: media,
                                                       fallbackMediaID: mediaID)
        }
        openingLibraryPlaybackHash = nil
        pendingLibraryPlaybackService = nil
        player.finishMetadataLoading()
    }

    func handleEpisodeChangeFromTorrentClient(episode: Int,
                                                      media: AnimeItem?,
                                                      fallbackMediaID: Int) {
        if let media {
            presentEpisodeSearch(media: media, episode: episode)
            return
        }

        guard fallbackMediaID > 0 else { return }
        AniListClient.shared.singleMediaResult(id: fallbackMediaID) { [weak self] result in
            switch result {
            case .success(let items):
                guard let media = items.first else { return }
                DispatchQueue.main.async {
                    self?.presentEpisodeSearch(media: media, episode: episode)
                }
            case .failure(let error):
                NSLog("[Downloads] AniList lookup failed for episode change: %@", error.description)
            }
        }
    }

    func presentEpisodeSearch(media: AnimeItem, episode: Int) {
        MiniPlayerManager.shared.close()

        let searchVC = ExtensionSearchViewController()
        searchVC.animeItem = media
        searchVC.initialEpisode = episode
        searchVC.shouldAutoSelectOnSearch = true

        let presenter = Self.topViewController() ?? self
        searchVC.prepareOverlayPresentation(from: presenter)
        presenter.present(searchVC, animated: true)
    }

    static func topViewController() -> UIViewController? {
        guard let appDelegate = UIApplication.shared.delegate as? AppDelegate,
              let window = appDelegate.window else { return nil }
        var viewController = window.rootViewController
        while let presented = viewController?.presentedViewController,
              !presented.isBeingDismissed {
            viewController = presented
        }
        return viewController
    }

    func restoreMiniPlayerIfAlreadyPlaying(hash: String, episode: Int?) -> Bool {
        guard MiniPlayerManager.shared.isActive,
              let player = MiniPlayerManager.shared.activePlayer else { return false }

        guard player.videoEntity?.torrents?.torrentHashString == hash else { return false }

        if let episode, episode > 0, player.episodeNumber > 0, player.episodeNumber != episode {
            return false
        }

        Router.shared.navigate(.player, hostTabIndex: hayaseTabIndex)
        return true
    }

    func bestVideoForLibraryPlayback(videos: [Videos], episode: Int) -> Videos? {
        guard episode > 0 else { return videos.first }

        if let exact = videos.first(where: { TorrentBatchResolver.extractEpisodeNumber(from: $0.videoName ?? "") == episode }) {
            return exact
        }

        let parsed = videos.compactMap { video -> (video: Videos, episode: Int)? in
            guard let ep = TorrentBatchResolver.extractEpisodeNumber(from: video.videoName ?? "") else { return nil }
            return (video, ep)
        }.sorted { $0.episode < $1.episode }

        if let match = parsed.first(where: { $0.episode == episode })?.video { return match }
        if let first = parsed.first, let last = parsed.last, episode >= first.episode, episode <= last.episode {
            return parsed.min { abs($0.episode - episode) < abs($1.episode - episode) }?.video ?? videos.first
        }
        if episode <= videos.count {
            let sorted = videos.sorted { ($0.videoName ?? "").localizedStandardCompare($1.videoName ?? "") == .orderedAscending }
            return sorted[safe: episode - 1] ?? videos.first
        }
        return videos.first
    }

    func cancelPendingLibraryPlayback(clearService: Bool = true) {
        if let observer = pendingLibraryPlaybackObserver {
            NotificationCenter.default.removeObserver(observer)
            pendingLibraryPlaybackObserver = nil
        }
        pendingLibraryPlaybackTimeout?.cancel()
        pendingLibraryPlaybackTimeout = nil
        openingLibraryPlaybackHash = nil
        pendingLibraryPlayer = nil
        if clearService { pendingLibraryPlaybackService = nil }
    }

    @objc func deleteSelectedLibraryEntries() {
        guard !selectedLibraryHashes.isEmpty, !libraryActionInFlight else { return }

        let hashes = Array(selectedLibraryHashes)
        let names = webLibraryEntries.filter { hashes.contains($0.hash) }.map { $0.name.isEmpty ? $0.hash : $0.name }
        let dialog = TorrentLibraryDeleteDialog(names: names) { [weak self] in
            guard let self = self else { return }

            self.libraryActionInFlight = true
            self.updateLibrarySelectionLabel()
            let toast = AppErrorToast.startPromise(title: "Deleting torrents...",
                description: "This may take a while depending on the library size.")
            // torrent-client keeps what is being played, so the result is only known once the
            // library has been read again, as `server.updateLibrary()` does for interface.
            let manager = TorrentBackendManager.shared
            manager.deleteWebTorrents(hashes: hashes) { deleteResult in
                let reload = { (result: Result<[WebTorrentLibraryEntry], Error>) in
                    DispatchQueue.main.async { [weak self] in
                        let failure: Error?
                        switch result {
                        case .success(let entries):
                            self?.webLibraryEntries = entries
                            WebTorrentDownloaded.shared.replace(with: entries.map { $0.hash })
                            failure = nil
                        case .failure(let error):
                            failure = error
                        }
                        if let failure {
                            NSLog("[Torrent Library] %@", failure.localizedDescription)
                            AppErrorToast.resolvePromise(toast,
                                title: "Failed to delete torrents\n" + failure.localizedDescription, failed: true)
                        } else {
                            AppErrorToast.resolvePromise(toast, title: "Torrents deleted")
                        }
                        guard let self else { return }
                        self.libraryActionInFlight = false
                        if failure == nil { self.selectedLibraryHashes.removeAll() }
                        self.refreshLibrary()
                        self.update()
                    }
                }
                switch deleteResult {
                case .success:
                    manager.webTorrentLibrary(completion: reload)
                case .failure(let error):
                    reload(.failure(error))
                }
            }
        }
        present(dialog, animated: false)
    }

    @objc func libraryHeaderTapped(_ sender: UIButton) {
        if sender.tag == 7 {
            let hashes = Set(webFilteredLibraryEntries.map { $0.hash })
            if hashes.isSubset(of: selectedLibraryHashes) {
                selectedLibraryHashes.subtract(hashes)
            } else {
                selectedLibraryHashes.formUnion(hashes)
            }
        } else if librarySortColumn == sender.tag {
            librarySortAscending.toggle()
        } else {
            librarySortColumn = sender.tag
            librarySortAscending = true
        }
        refreshLibrary()
    }
}
