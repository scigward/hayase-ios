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
