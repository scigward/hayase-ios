//
//  TrackersTable.swift
//  Hayase
//
//  Created by scigward.
//

import UIKit

final class TrackerStatusCell: UITableViewCell {
    static let reuseID = "TrackerStatusCell"

    private let announceLabel: UILabel = {
        let label = UILabel()
        label.font = .nunito(ofSize: 14)
        label.textColor = TorrentClientStyle.foreground
        label.numberOfLines = 1
        label.lineBreakMode = .byTruncatingMiddle
        return label
    }()

    private let statusLabel = TrackerStatusCell.makeValueLabel()
    private let downloadedLabel = TrackerStatusCell.makeValueLabel()
    private let seedersLabel = TrackerStatusCell.makeValueLabel()
    private let leechersLabel = TrackerStatusCell.makeValueLabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private static func makeValueLabel() -> UILabel {
        let label = UILabel()
        label.font = .nunito(ofSize: 14)
        label.textColor = TorrentClientStyle.foreground
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.75
        return label
    }

    private func setup() {
        selectionStyle = .none
        TorrentClientStyle.configureTableCell(self)

        let stack = UIStackView(arrangedSubviews: [
            announceLabel,
            statusLabel,
            downloadedLabel,
            seedersLabel,
            leechersLabel,
        ])
        stack.axis = .horizontal
        stack.spacing = TorrentClientStyle.columnSpacing
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            statusLabel.widthAnchor.constraint(equalToConstant: 86),
            downloadedLabel.widthAnchor.constraint(equalToConstant: 96),
            seedersLabel.widthAnchor.constraint(equalToConstant: 76),
            leechersLabel.widthAnchor.constraint(equalToConstant: 86),
        ])

        for label in [statusLabel, downloadedLabel, seedersLabel, leechersLabel] {
            label.setContentHuggingPriority(.required, for: .horizontal)
            label.setContentCompressionResistancePriority(.required, for: .horizontal)
        }
    }

    func configure(announce: String, info: WebTorrentTrackerInfo) {
        announceLabel.text = announce
        statusLabel.text = info.failed ? "Failed" : "Working"
        statusLabel.textColor = TorrentClientStyle.foreground
        downloadedLabel.text = "\(info.downloaded)"
        seedersLabel.text = "\(info.complete)"
        leechersLabel.text = "\(info.incomplete)"
    }
}
