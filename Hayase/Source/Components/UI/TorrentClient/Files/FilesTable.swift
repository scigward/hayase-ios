// Mirrors: ui/torrentclient/files/table.svelte and cells.
import UIKit

// MARK: - FileEntryTableCell

final class FileEntryTableCell: UITableViewCell {
    static let reuseID = "FileEntryTableCell"
    var columnWidths: [CGFloat?] = [nil, 80, 128, 70] { didSet { updateColumnWidths() } }
    private var widthConstraints: [Int: NSLayoutConstraint] = [:]
    private var lastFileName: String?

    private let nameLabel: UILabel = {
        let l = UILabel()
        l.font = .geistMono(ofSize: 12)
        l.textColor = TorrentClientStyle.foreground
        l.numberOfLines = 0
        l.lineBreakMode = .byCharWrapping
        l.setContentHuggingPriority(.defaultLow, for: .horizontal)
        l.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return l
    }()

    private let sizeLabel: UILabel = {
        let l = TorrentClientLabel()
        l.font = .nunito(ofSize: 14)
        l.textColor = TorrentClientStyle.foreground
        l.textAlignment = .left
        return l
    }()

    private let progressBar = TorrentClientProgressBar()

    private let progressLabel: UILabel = {
        let l = TorrentClientLabel()
        l.lineHeight = 16
        l.font = .nunito(ofSize: 12)
        l.textColor = TorrentClientStyle.mutedForeground
        l.textAlignment = .left
        return l
    }()

    private let streamsLabel: UILabel = {
        let l = TorrentClientLabel()
        l.font = .nunito(ofSize: 14)
        l.textColor = TorrentClientStyle.foreground
        l.textAlignment = .left
        return l
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupCellUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupCellUI()
    }

    private func setupCellUI() {
        selectionStyle = .none
        TorrentClientStyle.configureTableCell(self)
        addGestureRecognizer(UIHoverGestureRecognizer(target: self, action: #selector(hover(_:))))

        // Progress: bar on top, label below
        let progressStack = UIStackView(arrangedSubviews: [progressBar, progressLabel])
        progressStack.axis = .vertical
        progressStack.spacing = 4
        progressStack.isLayoutMarginsRelativeArrangement = true
        progressStack.layoutMargins = UIEdgeInsets(top: 6, left: 0, bottom: 0, right: 0)
        progressStack.alignment = .fill

        // Horizontal stack matching column header widths:
        // File Name (flex) | Size (content) | Progress (128) | Streams (content)
        let stack = UIStackView(arrangedSubviews: [nameLabel, sizeLabel, progressStack, streamsLabel])
        stack.axis = .horizontal
        stack.spacing = TorrentClientStyle.columnSpacing
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 56),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),

            progressBar.heightAnchor.constraint(equalToConstant: 6),

        ])
        for (index, view) in [sizeLabel as UIView, progressStack, streamsLabel].enumerated() {
            let column = index + 1
            let constraint = view.widthAnchor.constraint(equalToConstant: columnWidths[column] ?? 0)
            constraint.isActive = true
            widthConstraints[column] = constraint
        }

        sizeLabel.setContentHuggingPriority(.required, for: .horizontal)
        sizeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        streamsLabel.setContentHuggingPriority(.required, for: .horizontal)
        streamsLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    private func updateColumnWidths() {
        for (index, constraint) in widthConstraints where columnWidths.indices.contains(index) {
            constraint.constant = columnWidths[index] ?? constraint.constant
        }
    }

    @objc private func hover(_ gesture: UIHoverGestureRecognizer) {
        let hovering = gesture.state == .began || gesture.state == .changed
        UIView.animate(withDuration: 0.15, delay: 0,
                       options: [.beginFromCurrentState, .allowUserInteraction]) {
            self.contentView.backgroundColor = hovering
                ? TorrentClientStyle.accent.withAlphaComponent(0.5) : .clear
        }
    }

    func configure(entry: WebTorrentFileInfo) {
        configureName(entry.name)
        sizeLabel.text = TorrentFormat.fastPrettyBytes(entry.size)
        let progress = Float(max(0, min(entry.progress, 1)))
        progressBar.progress = progress
        progressLabel.text = String(format: "%.1f%%", progress * 100)
        streamsLabel.text = "\(entry.selections)"
    }

    private func configureName(_ name: String) {
        // A reused cell represents a new row, not a progress update of the old file.
        progressBar.animatesUpdates = lastFileName == name
        lastFileName = name
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = 16
        paragraph.maximumLineHeight = 16
        paragraph.lineBreakMode = .byCharWrapping
        nameLabel.attributedText = NSAttributedString(string: name, attributes: [
            .font: nameLabel.font as Any,
            .foregroundColor: TorrentClientStyle.foreground,
            .paragraphStyle: paragraph,
            .baselineOffset: (16 - nameLabel.font.lineHeight) / 2,
        ])
    }
}

// MARK: - The files page (files/table.svelte)

extension DownloadsViewController {
    func buildFilesUI() {
        TorrentClientStyle.configurePlainContentView(filesView)

        filesSearchField.translatesAutoresizingMaskIntoConstraints = false
        filesSearchField.addTarget(self, action: #selector(filesSearchChanged), for: .editingChanged)
        filesView.addSubview(filesSearchField)

        let borderContainer = UIView()
        TorrentClientStyle.configureTableShell(borderContainer)
        borderContainer.translatesAutoresizingMaskIntoConstraints = false
        filesView.addSubview(borderContainer)

        filesTableView = UITableView(frame: .zero, style: .plain)
        filesTableView.translatesAutoresizingMaskIntoConstraints = false
        filesTableView.delegate = self
        filesTableView.dataSource = self
        filesTableView.register(FileEntryTableCell.self, forCellReuseIdentifier: FileEntryTableCell.reuseID)
        filesTableView.rowHeight = Self.filesRowHeight
        filesTableView.estimatedRowHeight = Self.filesRowHeight
        TorrentClientStyle.configureTableView(filesTableView)
        filesMinimumWidth = TorrentClientStyle.installScrollableTable(filesTableView, in: borderContainer,
            minimumWidth: TorrentClientColumnWidths.minimumTableWidth(filesColumnWidths,
                flexibleMinimums: [0: TorrentClientColumnWidths.filesNameMinimum]))

        NSLayoutConstraint.activate([
            filesSearchField.topAnchor.constraint(equalTo: filesView.topAnchor),
            filesSearchField.leadingAnchor.constraint(equalTo: filesView.leadingAnchor),
            filesSearchField.trailingAnchor.constraint(equalTo: filesView.trailingAnchor),
            filesSearchField.heightAnchor.constraint(equalToConstant: 36),

            borderContainer.topAnchor.constraint(equalTo: filesSearchField.bottomAnchor, constant: 8),
            borderContainer.leadingAnchor.constraint(equalTo: filesView.leadingAnchor),
            borderContainer.trailingAnchor.constraint(equalTo: filesView.trailingAnchor),
            borderContainer.bottomAnchor.constraint(equalTo: filesView.bottomAnchor),

        ])
    }

    @objc func filesSearchChanged() {
        refreshFiles()
    }

    func refreshFiles() {
        let query = filesSearchField.text?.lowercased() ?? ""
        webFilteredFileInfos = query.isEmpty
            ? webFileInfos
            : webFileInfos.filter { $0.name.lowercased().contains(query) }

        if let sortCol = filesSortColumn {
            let ascending = filesSortAscending
            webFilteredFileInfos.sort { a, b in
                switch sortCol {
                case .name:
                    return ascending ? a.name < b.name : a.name > b.name
                case .size:
                    return ascending ? a.size < b.size : a.size > b.size
                case .progress:
                    return ascending ? a.progress < b.progress : a.progress > b.progress
                case .streams:
                    return ascending ? a.selections < b.selections : a.selections > b.selections
                }
            }
        }
        filesColumnWidths = TorrentClientColumnWidths.files(entries: webFilteredFileInfos)
        updateFileColumnLayout()
    }

    func updateFileColumnLayout() {
        filesMinimumWidth?.constant = TorrentClientColumnWidths.minimumTableWidth(filesColumnWidths,
            flexibleMinimums: [0: TorrentClientColumnWidths.filesNameMinimum])
        filesTableView?.reloadData()
    }

    /// Uses the same Asc/Desc menu and shared header as peers and library.
    func makeFileColumnHeader() -> UIView {
        makeColumnHeader(columns: [("File Name", filesColumnWidths[0]), ("Size", filesColumnWidths[1]),
                                  ("Progress", filesColumnWidths[2]), ("Streams", filesColumnWidths[3])],
                         sortableColumnIndices: Set(0...3), activeColumnIndex: filesSortColumn?.rawValue,
                         sortAscending: filesSortAscending, target: self, action: #selector(fileColumnHeaderTapped(_:)),
                         onSort: { [weak self] index, ascending in
                             self?.filesSortColumn = FileSortColumn(rawValue: index)
                             self?.filesSortAscending = ascending
                             self?.refreshFiles()
                         })
    }

    /// Handles tap on a Files column header button.
    /// Matches Hayase's column sort dropdown with Asc/Desc options.
    @objc func fileColumnHeaderTapped(_ sender: UIButton) {
        guard let col = FileSortColumn(rawValue: sender.tag) else { return }
        if filesSortColumn == col {
            filesSortAscending.toggle()
        } else {
            filesSortColumn = col
            filesSortAscending = true
        }
        refreshFiles()
    }
}
