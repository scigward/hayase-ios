// Mirrors: ui/torrentclient/files/table.svelte and cells.
import UIKit
import LibTorrent

// MARK: - FileEntryTableCell

final class FileEntryTableCell: UITableViewCell {
    static let reuseID = "FileEntryTableCell"

    private let nameLabel: UILabel = {
        let l = UILabel()
        l.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        l.textColor = TorrentClientStyle.foreground
        l.numberOfLines = 0
        l.lineBreakMode = .byCharWrapping
        l.setContentHuggingPriority(.defaultLow, for: .horizontal)
        l.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return l
    }()

    private let sizeLabel: UILabel = {
        let l = UILabel()
        l.font = .nunito(ofSize: 14)
        l.textColor = TorrentClientStyle.foreground
        l.textAlignment = .left
        return l
    }()

    private let progressBar: UIProgressView = {
        let pv = UIProgressView(progressViewStyle: .bar)
        pv.layer.cornerRadius = 3
        pv.clipsToBounds = true
        pv.trackTintColor = UIColor.HayaseTheme.secondary
        pv.progressTintColor = TorrentClientStyle.primary
        return pv
    }()

    private let progressLabel: UILabel = {
        let l = UILabel()
        l.font = .nunito(ofSize: 12)
        l.textColor = TorrentClientStyle.mutedForeground
        l.textAlignment = .left
        return l
    }()

    private let streamsLabel: UILabel = {
        let l = UILabel()
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

        // Progress: bar on top, label below
        let progressStack = UIStackView(arrangedSubviews: [progressBar, progressLabel])
        progressStack.axis = .vertical
        progressStack.spacing = 4
        progressStack.isLayoutMarginsRelativeArrangement = true
        progressStack.layoutMargins = UIEdgeInsets(top: 6, left: 0, bottom: 0, right: 0)
        progressStack.alignment = .fill

        // Horizontal stack matching column header widths:
        // File Name (flex) | Size (80) | Progress (128) | Streams (70)
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

            // Match column header widths
            sizeLabel.widthAnchor.constraint(equalToConstant: 80),
            progressStack.widthAnchor.constraint(equalToConstant: 128),
            streamsLabel.widthAnchor.constraint(equalToConstant: 70),
        ])

        sizeLabel.setContentHuggingPriority(.required, for: .horizontal)
        sizeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        streamsLabel.setContentHuggingPriority(.required, for: .horizontal)
        streamsLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    func configure(entry: FileEntry, streamCount: Int) {
        nameLabel.text = entry.name
        sizeLabel.text = TorrentDetailViewController.fastPrettyBytes(entry.size)
        let progress = Float(entry.progress)
        progressBar.progress = progress
        progressLabel.text = String(format: "%.1f%%", progress * 100)
        streamsLabel.text = "\(streamCount)"
    }

    func configure(entry: WebTorrentFileInfo) {
        nameLabel.text = entry.name
        sizeLabel.text = TorrentDetailViewController.fastPrettyBytes(entry.size)
        let progress = Float(max(0, min(entry.progress, 1)))
        progressBar.progress = progress
        progressLabel.text = String(format: "%.1f%%", progress * 100)
        streamsLabel.text = "\(entry.selections)"
    }
}
