//
//  TrackersTable.swift
//  Hayase
//
//  Created by scigward.
//

import UIKit

enum TrackerTableLayout {
    static let defaultWidths: [CGFloat] = [160, 86, 96, 76, 86]
    static let titles = ["Tracker", "Status", "Downloaded", "Seeders", "Leechers"]

    static func widths(for rows: [(announce: String, info: WebTorrentTrackerInfo)]) -> [CGFloat] {
        let font = UIFont.nunito(ofSize: 14)
        let headerFont = UIFont.nunito(ofSize: 14, weight: .medium)
        func width(_ text: String, font: UIFont) -> CGFloat {
            ceil((text as NSString).size(withAttributes: [.font: font]).width)
        }
        var result = titles.map { width($0, font: headerFont) }
        for row in rows {
            let values = [row.announce, row.info.failed ? "Failed" : "Working",
                          "\(row.info.downloaded)", "\(row.info.complete)", "\(row.info.incomplete)"]
            for index in result.indices { result[index] = max(result[index], width(values[index], font: font)) }
        }
        return result
    }

    static func columns(widths: [CGFloat]) -> [(String, CGFloat?)] {
        let widths = widths.count == titles.count ? widths : defaultWidths
        return titles.enumerated().map { index, title in (title, index == 0 ? nil : widths[index]) }
    }

    static func minimumContentWidth(widths: [CGFloat]) -> CGFloat {
        widths.reduce(48, +) + TorrentClientStyle.columnSpacing * CGFloat(max(0, widths.count - 1))
    }
}

final class TrackerStatusCell: UITableViewCell {
    static let reuseID = "TrackerStatusCell"

    private let announceLabel: UILabel = {
        let label = TorrentClientLabel()
        label.font = .nunito(ofSize: 14)
        label.textColor = TorrentClientStyle.foreground
        label.numberOfLines = 1
        label.lineBreakMode = .byClipping // text-nowrap: preserve the complete URL.
        return label
    }()

    private let statusLabel = TrackerStatusCell.makeValueLabel()
    private let downloadedLabel = TrackerStatusCell.makeValueLabel()
    private let seedersLabel = TrackerStatusCell.makeValueLabel()
    private let leechersLabel = TrackerStatusCell.makeValueLabel()
    private var columnWidthConstraints: [NSLayoutConstraint] = []

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private static func makeValueLabel() -> UILabel {
        let label = TorrentClientLabel()
        label.font = .nunito(ofSize: 14)
        label.textColor = TorrentClientStyle.foreground
        label.numberOfLines = 1
        label.lineBreakMode = .byClipping
        return label
    }

    private func setup() {
        selectionStyle = .none
        TorrentClientStyle.configureTableCell(self)
        addGestureRecognizer(UIHoverGestureRecognizer(target: self, action: #selector(hover(_:))))

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
        ])
        columnWidthConstraints = [
            announceLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: TrackerTableLayout.defaultWidths[0]),
            statusLabel.widthAnchor.constraint(equalToConstant: 86),
            downloadedLabel.widthAnchor.constraint(equalToConstant: 96),
            seedersLabel.widthAnchor.constraint(equalToConstant: 76),
            leechersLabel.widthAnchor.constraint(equalToConstant: 86),
        ]
        NSLayoutConstraint.activate(columnWidthConstraints)

        for label in [statusLabel, downloadedLabel, seedersLabel, leechersLabel] {
            label.setContentHuggingPriority(.required, for: .horizontal)
            label.setContentCompressionResistancePriority(.required, for: .horizontal)
        }
    }

    func configure(announce: String, info: WebTorrentTrackerInfo, columnWidths: [CGFloat]? = nil) {
        if let columnWidths, columnWidths.count == columnWidthConstraints.count {
            for (constraint, width) in zip(columnWidthConstraints, columnWidths) { constraint.constant = width }
        }
        announceLabel.text = announce
        statusLabel.text = info.failed ? "Failed" : "Working"
        statusLabel.textColor = TorrentClientStyle.foreground
        downloadedLabel.text = "\(info.downloaded)"
        seedersLabel.text = "\(info.complete)"
        leechersLabel.text = "\(info.incomplete)"
    }

    @objc private func hover(_ gesture: UIHoverGestureRecognizer) {
        let hovering = gesture.state == .began || gesture.state == .changed
        UIView.animate(withDuration: 0.15, delay: 0,
                       options: [.curveEaseInOut, .beginFromCurrentState, .allowUserInteraction]) {
            self.contentView.backgroundColor = hovering
                ? TorrentClientStyle.accent.withAlphaComponent(0.5) : .clear
        }
    }
}
