//
//  PeersTable.swift
//  Hayase
//
//  Created by scigward.
//

import UIKit

enum PeerTableLayout {
    static let contentPadding: CGFloat = 48
    static let columnSpacing = TorrentClientStyle.columnSpacing
    static let ipWidth: CGFloat = 190
    static let clientWidth: CGFloat = 160
    static let progressWidth: CGFloat = 64 // progress.svelte min-w-16.
    static let downloadWidth: CGFloat = 110
    static let uploadWidth: CGFloat = 100
    static let downloadedWidth: CGFloat = 96
    static let uploadedWidth: CGFloat = 96
    static let countryWidth: CGFloat = 86
    static let flagsWidth: CGFloat = 112

    static let columns: [(String, CGFloat?)] = [
        ("IP Address", ipWidth),
        ("Client", clientWidth),
        ("Progress", nil),
        ("Download", downloadWidth),
        ("Upload", uploadWidth),
        ("Downloaded", downloadedWidth),
        ("Uploaded", uploadedWidth),
        ("Country", countryWidth),
        ("Flags", flagsWidth),
    ]

    static var minimumContentWidth: CGFloat {
        contentPadding
            + ipWidth
            + clientWidth
            + progressWidth
            + downloadWidth
            + uploadWidth
            + downloadedWidth
            + uploadedWidth
            + countryWidth
            + flagsWidth
            + columnSpacing * CGFloat(columns.count - 1)
    }

    /// HTML tables size nowrap columns from their header and rendered values;
    /// only Progress takes the remaining width. Keep header and body in sync.
    static func widths(for rows: [TorrentClientPeerRow]) -> [CGFloat] {
        let font = UIFont.nunito(ofSize: 14)
        let headerFont = UIFont.nunito(ofSize: 14, weight: .medium)
        let ipFont = UIFont.geistMono(ofSize: 12)
        func width(_ text: String, font: UIFont) -> CGFloat {
            ceil((text as NSString).size(withAttributes: [.font: font]).width)
        }
        var result = columns.map { width($0.0, font: headerFont) }
        result[2] = max(result[2], progressWidth)
        // country.svelte: 20px Twemoji, gap-2, two-letter code.
        result[7] = max(result[7], 28 + width("WW", font: font))
        for row in rows {
            let values: [CGFloat] = [
                16 + width(row.ip, font: ipFont),
                width(String(row.client.prefix(21)), font: font),
                progressWidth,
                22 + width(TorrentFormat.fastPrettyBits(row.downloadSpeed * 8) + "/s", font: font),
                22 + width(TorrentFormat.fastPrettyBits(row.uploadSpeed * 8) + "/s", font: font),
                width(TorrentFormat.fastPrettyBytes(row.downloaded), font: font),
                width(TorrentFormat.fastPrettyBytes(row.uploaded), font: font),
                result[7],
                CGFloat(row.flags.count) * 22 + CGFloat(max(0, row.flags.count - 1)) * 8,
            ]
            for index in result.indices { result[index] = max(result[index], values[index]) }
        }
        return result
    }

    static func columns(widths: [CGFloat]) -> [(String, CGFloat?)] {
        guard widths.count == columns.count else { return columns }
        return columns.enumerated().map { index, column in
            (column.0, index == 2 ? nil : widths[index])
        }
    }

    static func minimumContentWidth(widths: [CGFloat]) -> CGFloat {
        widths.reduce(contentPadding, +) + columnSpacing * CGFloat(max(0, widths.count - 1))
    }
}

final class PeerInfoCell: UITableViewCell {
    static let reuseID = "PeerInfoCell"

    private let ipView = PeerIpCellContent()
    private let clientLabel: UILabel = {
        let label = TorrentClientLabel()
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
    private var representedIP: String?
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
        stack.spacing = PeerTableLayout.columnSpacing
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
            ipView.widthAnchor.constraint(equalToConstant: PeerTableLayout.ipWidth),
            clientLabel.widthAnchor.constraint(equalToConstant: PeerTableLayout.clientWidth),
            progressView.widthAnchor.constraint(greaterThanOrEqualToConstant: PeerTableLayout.progressWidth),
            downloadSpeedView.widthAnchor.constraint(equalToConstant: PeerTableLayout.downloadWidth),
            uploadSpeedView.widthAnchor.constraint(equalToConstant: PeerTableLayout.uploadWidth),
            downloadedLabel.widthAnchor.constraint(equalToConstant: PeerTableLayout.downloadedWidth),
            uploadedLabel.widthAnchor.constraint(equalToConstant: PeerTableLayout.uploadedWidth),
            countryView.widthAnchor.constraint(equalToConstant: PeerTableLayout.countryWidth),
            flagsView.widthAnchor.constraint(equalToConstant: PeerTableLayout.flagsWidth),
        ]
        NSLayoutConstraint.activate(columnWidthConstraints)

        for view in [ipView, clientLabel, downloadSpeedView, uploadSpeedView,
                     downloadedLabel, uploadedLabel, countryView, flagsView] {
            view.setContentHuggingPriority(.required, for: .horizontal)
            view.setContentCompressionResistancePriority(.required, for: .horizontal)
        }
        progressView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        progressView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    func configure(row: TorrentClientPeerRow, columnWidths: [CGFloat]? = nil) {
        if let columnWidths, columnWidths.count == columnWidthConstraints.count {
            for (constraint, width) in zip(columnWidthConstraints, columnWidths) {
                constraint.constant = width
            }
        }
        ipView.configure(ip: row.ip, isSeeder: row.isSeeder)
        clientLabel.text = String(row.client.prefix(21))
        progressView.configure(progress: row.progress, animated: representedIP == row.ip)
        downloadSpeedView.configure(bytesPerSecond: row.downloadSpeed, kind: .download)
        uploadSpeedView.configure(bytesPerSecond: row.uploadSpeed, kind: .upload)
        downloadedLabel.text = TorrentFormat.fastPrettyBytes(row.downloaded)
        uploadedLabel.text = TorrentFormat.fastPrettyBytes(row.uploaded)
        countryView.configure(ip: row.ip)
        flagsView.configure(flags: row.flags)
        representedIP = row.ip
    }

    @objc private func hover(_ gesture: UIHoverGestureRecognizer) {
        let hovering = gesture.state == .began || gesture.state == .changed
        UIView.animate(withDuration: 0.15, delay: 0,
                       options: [.curveEaseInOut, .beginFromCurrentState, .allowUserInteraction]) {
            self.contentView.backgroundColor = hovering
                ? TorrentClientStyle.accent.withAlphaComponent(0.5) : .clear
        }
    }

    func configure(peer: WebTorrentPeerInfo) {
        configure(row: TorrentClientPeerRow(peer: peer))
    }
}

// MARK: - The peers page (peers/table.svelte)

extension DownloadsViewController {
    func buildPeersUI() {
        TorrentClientStyle.configurePlainContentView(peersView)

        let borderContainer = UIView()
        TorrentClientStyle.configureTableShell(borderContainer)
        borderContainer.translatesAutoresizingMaskIntoConstraints = false
        peersView.addSubview(borderContainer)

        peersHorizontalScrollView = UIScrollView()
        peersHorizontalScrollView.translatesAutoresizingMaskIntoConstraints = false
        peersHorizontalScrollView.showsHorizontalScrollIndicator = true
        peersHorizontalScrollView.showsVerticalScrollIndicator = false
        peersHorizontalScrollView.alwaysBounceHorizontal = false
        peersHorizontalScrollView.alwaysBounceVertical = false
        peersHorizontalScrollView.backgroundColor = .clear
        borderContainer.addSubview(peersHorizontalScrollView)

        peersTableView = UITableView(frame: .zero, style: .plain)
        peersTableView.translatesAutoresizingMaskIntoConstraints = false
        peersTableView.delegate = self
        peersTableView.dataSource = self
        peersTableView.register(PeerInfoCell.self, forCellReuseIdentifier: PeerInfoCell.reuseID)
        peersTableView.rowHeight = 56
        peersTableView.estimatedRowHeight = 56
        TorrentClientStyle.configureTableView(peersTableView)
        peersTableView.allowsSelection = false
        peersHorizontalScrollView.addSubview(peersTableView)

        let peersMinimumWidth = peersTableView.widthAnchor.constraint(greaterThanOrEqualToConstant:
            PeerTableLayout.minimumContentWidth(widths: peerColumnWidths))
        self.peersMinimumWidth = peersMinimumWidth
        let preferredWidth = peersTableView.widthAnchor.constraint(equalTo: peersHorizontalScrollView.frameLayoutGuide.widthAnchor)
        preferredWidth.priority = .defaultHigh

        NSLayoutConstraint.activate([
            borderContainer.topAnchor.constraint(equalTo: peersView.topAnchor),
            borderContainer.leadingAnchor.constraint(equalTo: peersView.leadingAnchor),
            borderContainer.trailingAnchor.constraint(equalTo: peersView.trailingAnchor),
            borderContainer.bottomAnchor.constraint(equalTo: peersView.bottomAnchor),

            peersHorizontalScrollView.topAnchor.constraint(equalTo: borderContainer.topAnchor),
            peersHorizontalScrollView.leadingAnchor.constraint(equalTo: borderContainer.leadingAnchor),
            peersHorizontalScrollView.trailingAnchor.constraint(equalTo: borderContainer.trailingAnchor),
            peersHorizontalScrollView.bottomAnchor.constraint(equalTo: borderContainer.bottomAnchor),

            peersTableView.topAnchor.constraint(equalTo: peersHorizontalScrollView.contentLayoutGuide.topAnchor),
            peersTableView.leadingAnchor.constraint(equalTo: peersHorizontalScrollView.contentLayoutGuide.leadingAnchor),
            peersTableView.trailingAnchor.constraint(equalTo: peersHorizontalScrollView.contentLayoutGuide.trailingAnchor),
            peersTableView.bottomAnchor.constraint(equalTo: peersHorizontalScrollView.contentLayoutGuide.bottomAnchor),
            peersTableView.heightAnchor.constraint(equalTo: peersHorizontalScrollView.frameLayoutGuide.heightAnchor),
            peersTableView.widthAnchor.constraint(greaterThanOrEqualTo: peersHorizontalScrollView.frameLayoutGuide.widthAnchor),
            peersMinimumWidth,
            preferredWidth,
        ])
    }

    func refreshPeers() {
        let rows = currentPeerRows()
        peerColumnWidths = PeerTableLayout.widths(for: rows)
        peersMinimumWidth?.constant = PeerTableLayout.minimumContentWidth(widths: peerColumnWidths)
        globeView.setPeers(rows)
        peersTableView?.reloadData()
    }

    func currentPeerRows() -> [TorrentClientPeerRow] {
        var rows = webPeerInfos.map(TorrentClientPeerRow.init(peer:))

        guard let sortColumn = peersSortColumn else { return rows }
        let ascending = peersSortAscending
        rows.sort { lhs, rhs in
            let result: ComparisonResult
            switch sortColumn {
            case .ip:
                result = lhs.ip.localizedStandardCompare(rhs.ip)
            case .client:
                result = lhs.client.localizedCaseInsensitiveCompare(rhs.client)
            case .progress:
                result = lhs.progress == rhs.progress ? .orderedSame : (lhs.progress < rhs.progress ? .orderedAscending : .orderedDescending)
            case .download:
                result = lhs.downloadSpeed == rhs.downloadSpeed ? .orderedSame : (lhs.downloadSpeed < rhs.downloadSpeed ? .orderedAscending : .orderedDescending)
            case .upload:
                result = lhs.uploadSpeed == rhs.uploadSpeed ? .orderedSame : (lhs.uploadSpeed < rhs.uploadSpeed ? .orderedAscending : .orderedDescending)
            case .downloaded:
                result = lhs.downloaded == rhs.downloaded ? .orderedSame : (lhs.downloaded < rhs.downloaded ? .orderedAscending : .orderedDescending)
            case .uploaded:
                result = lhs.uploaded == rhs.uploaded ? .orderedSame : (lhs.uploaded < rhs.uploaded ? .orderedAscending : .orderedDescending)
            case .country:
                result = lhs.ip.localizedStandardCompare(rhs.ip) // source accessor is the IP
            }
            return ascending ? result == .orderedAscending : result == .orderedDescending
        }
        return rows
    }

    @objc func handlePeerHeaderTap(_ sender: UIButton) {
        guard let column = PeerSortColumn(rawValue: sender.tag) else { return }
        if peersSortColumn == column {
            peersSortAscending.toggle()
        } else {
            peersSortColumn = column
            peersSortAscending = true
        }
        peersTableView?.reloadData()
    }
}
