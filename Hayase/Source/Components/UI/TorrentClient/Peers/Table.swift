//
//  Table.swift
//  Hayase
//
//  Created by scigward.
//

import UIKit

final class PeerInfoCell: UITableViewCell {
    static let reuseID = "PeerInfoCell"

    private let ipView = PeerIpCellContent()
    private let clientLabel: UILabel = {
        let label = UILabel()
        label.font = .nunito(ofSize: 14)
        label.textColor = TorrentClientStyle.foreground
        label.lineBreakMode = .byTruncatingTail
        return label
    }()
    private let progressView = PeerProgressCellContent()
    private let downloadSpeedView = PeerSpeedCellContent()
    private let uploadSpeedView = PeerSpeedCellContent()
    private let downloadedLabel = PeerInfoCell.makeValueLabel()
    private let uploadedLabel = PeerInfoCell.makeValueLabel()
    private let countryView = PeerCountryCellContent()
    private let flagsView = PeerFlagsCellContent()

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
            ipView,
            clientLabel,
            progressView,
            downloadSpeedView,
            uploadSpeedView,
            downloadedLabel,
            uploadedLabel,
            countryView,
            flagsView,
        ])
        stack.axis = .horizontal
        stack.spacing = 8
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            ipView.widthAnchor.constraint(equalToConstant: 170),
            clientLabel.widthAnchor.constraint(equalToConstant: 92),
            progressView.widthAnchor.constraint(greaterThanOrEqualToConstant: 90),
            downloadSpeedView.widthAnchor.constraint(equalToConstant: 102),
            uploadSpeedView.widthAnchor.constraint(equalToConstant: 92),
            downloadedLabel.widthAnchor.constraint(equalToConstant: 78),
            uploadedLabel.widthAnchor.constraint(equalToConstant: 78),
            countryView.widthAnchor.constraint(equalToConstant: 86),
            flagsView.widthAnchor.constraint(equalToConstant: 112),
        ])

        for view in [ipView, clientLabel, downloadSpeedView, uploadSpeedView,
                     downloadedLabel, uploadedLabel, countryView, flagsView] {
            view.setContentHuggingPriority(.required, for: .horizontal)
            view.setContentCompressionResistancePriority(.required, for: .horizontal)
        }
        progressView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        progressView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    func configure(row: TorrentClientPeerRow) {
        ipView.configure(ip: row.ip, isSeeder: row.isSeeder)
        clientLabel.text = String(row.client.prefix(21))
        progressView.configure(progress: row.progress)
        downloadSpeedView.configure(bytesPerSecond: row.downloadSpeed, kind: .download)
        uploadSpeedView.configure(bytesPerSecond: row.uploadSpeed, kind: .upload)
        downloadedLabel.text = TorrentDetailViewController.fastPrettyBytes(row.downloaded)
        uploadedLabel.text = TorrentDetailViewController.fastPrettyBytes(row.uploaded)
        countryView.configure(ip: row.ip)
        flagsView.configure(flags: row.flags)
    }

    func configure(peer: WebTorrentPeerInfo) {
        configure(row: TorrentClientPeerRow(peer: peer))
    }
}
