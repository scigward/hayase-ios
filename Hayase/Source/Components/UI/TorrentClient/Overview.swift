// Mirrors: ui/torrentclient/overview.svelte responsive CSS grids.
import UIKit

final class TorrentResponsiveGrid: UIStackView {
    private let cells: [UIView]
    private let gap: CGFloat
    private var columns = 0

    init(cells: [UIView], gap: CGFloat) {
        self.cells = cells
        self.gap = gap
        super.init(frame: .zero)
        axis = .vertical
        spacing = gap
        setColumns(1)
    }

    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setColumns(_ count: Int) {
        guard count > 0, count != columns else { return }
        columns = count
        cells.forEach { $0.removeFromSuperview() }
        arrangedSubviews.forEach { removeArrangedSubview($0); $0.removeFromSuperview() }
        for start in stride(from: 0, to: cells.count, by: count) {
            let row = UIStackView()
            row.axis = .horizontal
            row.alignment = .top
            row.distribution = .fillEqually
            row.spacing = gap
            for index in start..<(start + count) {
                row.addArrangedSubview(index < cells.count ? cells[index] : UIView())
            }
            addArrangedSubview(row)
        }
    }
}

// MARK: - The overview page (overview.svelte): what is built and shown for the active torrent

extension DownloadsViewController {
    func buildOverviewUI() {
        overviewScrollView.backgroundColor = .clear
        overviewScrollView.isOpaque = false
        overviewScrollView.translatesAutoresizingMaskIntoConstraints = false
        [downloadedValue, uploadedValue, totalSizeValue, piecesValue,
         downSpeedValue, upSpeedValue, etaValue, elapsedValue,
         seedersValue, leechersValue, wiresValue].forEach {
            $0.textColor = TorrentClientStyle.foreground
        }

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 48
        stack.translatesAutoresizingMaskIntoConstraints = false
        overviewScrollView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: overviewScrollView.contentLayoutGuide.topAnchor),
            stack.leadingAnchor.constraint(equalTo: overviewScrollView.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: overviewScrollView.contentLayoutGuide.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: overviewScrollView.contentLayoutGuide.bottomAnchor),
            stack.widthAnchor.constraint(equalTo: overviewScrollView.frameLayoutGuide.widthAnchor),
        ])

        // 1. Header
        stack.addArrangedSubview(makeHeader())

        // 2. Progress
        stack.addArrangedSubview(makeProgressSection())

        // 3. Three-column grid: Speed & Transfer | Time Information | Peers & Connections
        stack.addArrangedSubview(makeThreeColumnGrid())

        // 4. Protocol Status
        stack.addArrangedSubview(makeProtocolStatusSection())
    }

    func makeHeader() -> UIView {
        statusBadge.setContentHuggingPriority(.required, for: .horizontal)
        statusBadge.setContentCompressionResistancePriority(.required, for: .horizontal)
        statusBadge.heightAnchor.constraint(equalToConstant: 20).isActive = true
        let badgeRow = UIStackView(arrangedSubviews: [statusBadge, hashLabel])
        badgeRow.axis = .horizontal
        badgeRow.spacing = 8
        badgeRow.alignment = .center

        let wrapper = UIStackView(arrangedSubviews: [nameLabel, badgeRow])
        wrapper.axis = .vertical
        wrapper.spacing = 8
        return wrapper
    }

    func makeProgressSection() -> UIView {
        let container = UIStackView()
        container.axis = .vertical
        container.spacing = 16

        // Title row: icon + "Progress" ... percentage
        let titleRow = UIStackView()
        titleRow.axis = .horizontal
        titleRow.alignment = .center
        titleRow.spacing = 14 // gap-2 plus the heading icon's mr-1.5.

        let dlIcon = makeIcon("hard-drive-download", tint: TorrentClientStyle.foreground, size: 20)
        let progressTitle = TorrentClientLabel()
        progressTitle.lineHeight = 32
        progressTitle.font = .nunito(ofSize: 24, weight: .bold)
        progressTitle.text = "Progress"
        progressTitle.textColor = TorrentClientStyle.foreground

        let spacer = UIView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        titleRow.addArrangedSubview(dlIcon)
        titleRow.addArrangedSubview(progressTitle)
        titleRow.addArrangedSubview(spacer)
        titleRow.addArrangedSubview(bigPercentLabel)
        container.addArrangedSubview(titleRow)

        // Progress bar
        progressBar.heightAnchor.constraint(equalToConstant: 12).isActive = true
        container.addArrangedSubview(progressBar)

        // 4-column stat grid: Downloaded, Uploaded, Total Size, Pieces
        let grid = makeProgressStatRow([
            StatItem(label: downloadedValue, title: "Downloaded", icon: "download",   color: TorrentClientStyle.green500),
            StatItem(label: uploadedValue,   title: "Uploaded",   icon: "upload",     color: TorrentClientStyle.blue500),
            StatItem(label: totalSizeValue,  title: "Total Size", icon: "hard-drive", color: TorrentClientStyle.mutedForeground),
            StatItem(label: piecesValue,     title: "Pieces",     icon: "puzzle",     color: TorrentClientStyle.mutedForeground),
        ])
        container.addArrangedSubview(grid)

        return container
    }

    func makeThreeColumnGrid() -> UIView {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 0
        overviewStatsStack = stack

        // Speed & Transfer
        stack.addArrangedSubview(makeFlatSection(
            title: "Speed & Transfer",
            icon: "wifi",
            items: [
                StatItem(label: downSpeedValue, title: "Download", icon: "download", color: TorrentClientStyle.green500),
                StatItem(label: upSpeedValue,   title: "Upload",   icon: "upload",   color: TorrentClientStyle.blue500),
            ]
        ))

        // Time Information
        stack.addArrangedSubview(makeFlatSection(
            title: "Time Information",
            icon: "clock",
            items: [
                StatItem(label: etaValue,     title: "Remaining", icon: "clock-fading", color: TorrentClientStyle.orange500),
                StatItem(label: elapsedValue, title: "Elapsed",   icon: "timer",        color: TorrentClientStyle.purple500),
            ]
        ))

        // Peers & Connections
        stack.addArrangedSubview(makeFlatSection(
            title: "Peers & Connections",
            icon: "users",
            items: [
                StatItem(label: seedersValue,  title: "Seeders",  icon: "user-round-plus",  color: TorrentClientStyle.green500),
                StatItem(label: leechersValue, title: "Leechers", icon: "user-round-minus", color: TorrentClientStyle.blue500),
                StatItem(label: wiresValue,    title: "Wires",    icon: "link",             color: TorrentClientStyle.purple500),
            ]
        ))

        return stack
    }

    func makeProtocolStatusSection() -> UIView {
        let container = UIStackView()
        container.axis = .vertical
        container.spacing = 24
        container.isLayoutMarginsRelativeArrangement = true
        container.layoutMargins = UIEdgeInsets(top: 24, left: 0, bottom: 24, right: 0)

        let iconView = makeIcon("network", tint: TorrentClientStyle.foreground, size: 20)
        let title = TorrentClientLabel()
        title.lineHeight = 24
        title.text = "Protocol Status"
        title.font = .nunito(ofSize: 24, weight: .bold)
        title.textColor = TorrentClientStyle.foreground
        let titleRow = UIStackView(arrangedSubviews: [iconView, title])
        titleRow.axis = .horizontal
        titleRow.spacing = 14
        titleRow.alignment = .center
        container.addArrangedSubview(titleRow)

        let columns = TorrentResponsiveGrid(cells: [makeProtocolColumn("Network Discovery", [
            ("DHT", "Distributed Hash Table for peer discovery", dhtDot),
            ("LSD", "Local Service Discovery on network", lsdDot),
            ("PEX", "Peer Exchange with other clients", pexDot),
        ]), makeProtocolColumn("Connection", [
            ("NAT", "NAT-PMP/UPnP automatic forwarding", natDot),
            ("Forwarding", "Accepting inbound connections", forwardDot),
        ]), makeProtocolColumn("Storage", [
            ("Persisting", "Storing all torrents", persistDot),
            ("Streaming", "Downloading only required pieces", streamingDot),
        ])], gap: 48)
        protocolColumnsStack = columns
        container.addArrangedSubview(columns)
        return container
    }

    func makeProtocolColumn(_ header: String, _ rows: [(String, String, UIView)]) -> UIView {
        let col = UIStackView()
        col.axis = .vertical
        col.spacing = 12

        let headerLabel = TorrentClientLabel()
        headerLabel.lineHeight = 24
        headerLabel.text = header
        headerLabel.font = .nunito(ofSize: 16, weight: .medium)
        headerLabel.textColor = TorrentClientStyle.foreground
        col.addArrangedSubview(headerLabel)
        col.setCustomSpacing(16, after: headerLabel)

        for (name, desc, dot) in rows {
            let nameLabel = TorrentClientLabel()
            nameLabel.text = name
            nameLabel.font = .nunito(ofSize: 14, weight: .regular)
            nameLabel.textColor = TorrentClientStyle.foreground

            let descLabel = TorrentClientLabel()
            descLabel.lineHeight = 16
            descLabel.text = desc
            descLabel.font = .nunito(ofSize: 12, weight: .regular)
            descLabel.textColor = TorrentClientStyle.mutedForeground
            descLabel.numberOfLines = 0

            let textStack = UIStackView(arrangedSubviews: [nameLabel, descLabel])
            textStack.axis = .vertical
            textStack.spacing = 0
            textStack.isLayoutMarginsRelativeArrangement = true
            textStack.layoutMargins = UIEdgeInsets(top: 0, left: 4, bottom: 0, right: 4)

            let row = UIStackView(arrangedSubviews: [dot, textStack])
            row.axis = .horizontal
            row.spacing = 8
            row.alignment = .center
            col.addArrangedSubview(row)
        }

        return col
    }

    func renderWebOverview() {
        guard !selectedHex.isEmpty else {
            clearWebTorrentOverview(error: webLastError)
            return
        }
        let resolvedStatus = webStatus
        let resolvedInfo = webInfo
        let resolvedProtocol = webProtocol

        let torrentName = resolvedInfo?.name ?? ""
        nameLabel.text = torrentName.isEmpty ? "No Name Provided" : torrentName
        hashLabel.text = selectedHex

        let progress = resolvedInfo?.progress ?? resolvedStatus?.progress ?? 0
        let completed = progress == 1
        statusBadge.text = completed ? "Seeding" : "Downloading"
        statusBadge.backgroundColor = completed ? TorrentClientStyle.blue500 : TorrentClientStyle.green500
        bigPercentLabel.text = String(format: "%.1f%%", progress * 100)
        progressBar.progress = Float(max(0, min(progress, 1)))

        let downloaded = resolvedInfo?.size.downloaded ?? resolvedStatus?.downloaded ?? 0
        let uploaded = resolvedInfo?.size.uploaded ?? resolvedStatus?.uploaded ?? 0
        let total = resolvedInfo?.size.total ?? resolvedStatus?.total ?? 0
        downloadedValue.text = TorrentFormat.fastPrettyBytes(downloaded)
        uploadedValue.text = TorrentFormat.fastPrettyBytes(uploaded)
        totalSizeValue.text = TorrentFormat.fastPrettyBytes(total)

        setPiecesValue(total: resolvedInfo?.pieces.total ?? 0, size: resolvedInfo?.pieces.size ?? 0)

        let down = resolvedInfo?.speed.down ?? resolvedStatus?.downloadSpeed ?? 0
        let up = resolvedInfo?.speed.up ?? resolvedStatus?.uploadSpeed ?? 0
        downSpeedValue.text = TorrentFormat.fastPrettyBits(down * 8) + "/s"
        upSpeedValue.text = TorrentFormat.fastPrettyBits(up * 8) + "/s"
        if resolvedProtocol?.streaming == true {
            etaValue.text = "Streaming"
        } else {
            etaValue.text = webTorrentETA(fromMilliseconds: resolvedInfo?.time.remaining)
                ?? TorrentFormat.eta(remaining: total > downloaded ? total - downloaded : 0, rate: down)
        }
        let elapsed = resolvedInfo?.time.elapsed ?? 0 // elapsed is seconds, unlike remaining.
        elapsedValue.text = TorrentFormat.eta(seconds: Int(elapsed.isFinite ? max(0, min(elapsed, Double(Int.max / 2))) : 0))

        seedersValue.text = "\(resolvedInfo?.peers.seeders ?? 0)"
        leechersValue.text = "\(resolvedInfo?.peers.leechers ?? 0)"
        wiresValue.text = "\(resolvedInfo?.peers.wires ?? 0)"

        setDot(dhtDot, enabled: resolvedProtocol?.dht ?? resolvedStatus?.dht ?? false)
        setDot(lsdDot, enabled: resolvedProtocol?.lsd ?? false)
        setDot(pexDot, enabled: resolvedProtocol?.pex ?? resolvedStatus?.pex ?? false)
        setDot(natDot, enabled: resolvedProtocol?.nat ?? false)
        setDot(forwardDot, enabled: resolvedProtocol?.forwarding ?? false)
        setDot(persistDot, enabled: resolvedProtocol?.persisting ?? Settings.persistFiles)
        setDot(streamingDot, enabled: resolvedProtocol?.streaming ?? false)
    }

    func webTorrentETA(fromMilliseconds value: Double?) -> String? {
        guard let value else { return nil }
        let seconds = value.isFinite ? max(0, min(value / 1000, Double(Int.max / 2))) : 0
        return TorrentFormat.eta(seconds: Int(seconds))
    }

    func clearWebTorrentOverview(error: Error?) {
        if let error { NSLog("[Torrent Client] %@", error.localizedDescription) }
        nameLabel.text = "No Name Provided"
        hashLabel.text = ""
        statusBadge.text = "Downloading"
        statusBadge.backgroundColor = TorrentClientStyle.green500
        bigPercentLabel.text = "0.0%"
        progressBar.progress = 0
        [downloadedValue, uploadedValue, totalSizeValue].forEach { $0.text = TorrentFormat.fastPrettyBytes(0) }
        setPiecesValue(total: 0, size: 0)
        [downSpeedValue, upSpeedValue].forEach { $0.text = TorrentFormat.fastPrettyBits(0) + "/s" }
        [etaValue, elapsedValue].forEach { $0.text = "0s" }
        [seedersValue, leechersValue, wiresValue].forEach { $0.text = "0" }
        for dot in [dhtDot, lsdDot, pexDot, natDot, forwardDot, persistDot, streamingDot] {
            setDot(dot, enabled: false)
        }
    }

    func setDot(_ dot: UIView, enabled: Bool) {
        dot.backgroundColor = enabled ? TorrentClientStyle.green500 : TorrentClientStyle.red500
    }

    func setPiecesValue(total: Int, size: UInt64) {
        piecesValue.mutedText = "×"
        piecesValue.text = "\(total) × \(TorrentFormat.fastPrettyBytes(size))"
    }

    struct StatItem {
        let label: UILabel
        let title: String
        let icon: String
        let color: UIColor
    }

    func makeIcon(_ name: String, tint: UIColor, size: CGFloat) -> UIImageView {
        let config = UIImage.SymbolConfiguration(pointSize: size, weight: .medium)
        let iv = UIImageView(image: UIImage.hayaseIcon(name, withConfiguration: config))
        iv.tintColor = tint
        iv.contentMode = .scaleAspectFit
        iv.setContentHuggingPriority(.required, for: .horizontal)
        iv.setContentCompressionResistancePriority(.required, for: .horizontal)
        iv.widthAnchor.constraint(equalToConstant: size).isActive = true
        iv.heightAnchor.constraint(equalToConstant: size).isActive = true
        return iv
    }

    func makeFlatSection(title: String, icon: String, items: [StatItem]) -> UIView {
        let container = UIStackView()
        container.axis = .vertical
        container.spacing = 0

        let iconView = makeIcon(icon, tint: TorrentClientStyle.foreground, size: 20)
        let titleLabel = TorrentClientLabel()
        titleLabel.lineHeight = 24
        titleLabel.text = title
        titleLabel.font = .nunito(ofSize: 24, weight: .bold)
        titleLabel.textColor = TorrentClientStyle.foreground

        let titleRow = UIStackView(arrangedSubviews: [iconView, titleLabel])
        titleRow.axis = .horizontal
        titleRow.spacing = 14
        titleRow.alignment = .center

        let paddedTitle = UIStackView(arrangedSubviews: [titleRow])
        paddedTitle.axis = .vertical
        paddedTitle.layoutMargins = UIEdgeInsets(top: 24, left: 0, bottom: 24, right: 0)
        paddedTitle.isLayoutMarginsRelativeArrangement = true

        container.addArrangedSubview(paddedTitle)

        let grid = makeFlatStatRow(items)
        container.addArrangedSubview(grid)

        return container
    }

    func makeFlatStatRow(_ items: [StatItem]) -> UIView {
        let row = UIStackView(arrangedSubviews: items.map { makeFlatStatCell($0) })
        row.axis = .horizontal
        row.distribution = .fillEqually
        row.spacing = 16
        return row
    }

    func makeFlatStatCell(_ item: StatItem) -> UIView {
        let iconView = makeIcon(item.icon, tint: item.color, size: 16)
        let titleLabel = TorrentClientLabel()
        titleLabel.text = item.title
        titleLabel.font = .nunito(ofSize: 14, weight: .medium)
        titleLabel.textColor = TorrentClientStyle.mutedForeground

        let topRow = UIStackView(arrangedSubviews: [iconView, titleLabel])
        topRow.axis = .horizontal
        topRow.spacing = 8
        topRow.alignment = .center

        item.label.font = .nunito(ofSize: 24, weight: .bold)
        (item.label as? TorrentClientLabel)?.lineHeight = 32

        let stack = UIStackView(arrangedSubviews: [topRow, item.label])
        stack.axis = .vertical
        stack.spacing = 8
        return stack
    }

    func makeProgressStatRow(_ items: [StatItem]) -> UIView {
        let row = TorrentResponsiveGrid(cells: items.map { makeProgressStatCell($0) }, gap: 16)
        progressStatsGrid = row
        return row
    }

    func makeProgressStatCell(_ item: StatItem) -> UIView {
        let iconView = makeIcon(item.icon, tint: item.color, size: 16)

        let titleLabel = TorrentClientLabel()
        titleLabel.text = item.title
        titleLabel.font = .nunito(ofSize: 14, weight: .regular)
        titleLabel.textColor = TorrentClientStyle.mutedForeground

        item.label.font = .nunito(ofSize: 14, weight: .medium)

        let text = UIStackView(arrangedSubviews: [titleLabel, item.label])
        text.axis = .vertical
        let iconMargin = UIView()
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconMargin.addSubview(iconView)
        NSLayoutConstraint.activate([
            iconMargin.widthAnchor.constraint(equalToConstant: 24),
            iconMargin.heightAnchor.constraint(equalToConstant: 16),
            iconView.centerXAnchor.constraint(equalTo: iconMargin.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconMargin.centerYAnchor),
        ])
        let stack = UIStackView(arrangedSubviews: [iconMargin, text])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 8
        return stack
    }
}
