//
//  Relations.swift
//  Hayase
//

import UIKit

// MARK: - HorizontalCardsCell

final class HorizontalCardsCell: UITableViewCell {
    static let relationsReuseID  = "HorizontalRelationsCell"
    static let staffReuseID      = "HorizontalStaffCell"

    let collectionView: UICollectionView

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.itemSize = CGSize(width: 90, height: 140)
        layout.minimumInteritemSpacing = 10
        layout.minimumLineSpacing = 10
        layout.sectionInset = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .clear
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.backgroundColor = .clear
        contentView.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            collectionView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    func applyPaddingForSizeClass(isRegular: Bool) {
        if let layout = collectionView.collectionViewLayout as? UICollectionViewFlowLayout {
            let sidePad: CGFloat = isRegular ? 56 : 16
            layout.sectionInset = UIEdgeInsets(top: 0, left: sidePad, bottom: 0, right: sidePad)
        }
    }
}

// MARK: - RelationCardCell

final class RelationCardCell: UICollectionViewCell {
    static let reuseID = "RelationCardCell"

    private let imageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.backgroundColor = .systemGray5
        iv.layer.cornerRadius = 6
        return iv
    }()

    private let titleLabel: UILabel = {
        let l = UILabel()
        l.font = .nunito(ofSize: 9, weight: .semibold)
        l.textColor = .label
        l.numberOfLines = 2
        return l
    }()

    private let typeLabel: UILabel = {
        let l = UILabel()
        l.font = .nunito(ofSize: 8, weight: .medium)
        l.textColor = .white
        l.backgroundColor = UIColor.systemIndigo.withAlphaComponent(0.85)
        l.layer.cornerRadius = 3
        l.clipsToBounds = true
        return l
    }()

    private var imageTask: URLSessionDataTask?
    private var currentURL: String?

    override init(frame: CGRect) {
        super.init(frame: frame)
        [imageView, titleLabel, typeLabel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview($0)
        }
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            imageView.heightAnchor.constraint(equalTo: contentView.widthAnchor, multiplier: 1.35),

            typeLabel.leadingAnchor.constraint(equalTo: imageView.leadingAnchor, constant: 4),
            typeLabel.bottomAnchor.constraint(equalTo: imageView.bottomAnchor, constant: -4),

            titleLabel.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 4),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            titleLabel.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(with relation: AnimeRelation) {
        let displayType = relation.relationType
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
        typeLabel.text = " \(displayType) "
        titleLabel.text = AniListUtil.title(for: relation.media)
        loadImage(from: relation.media.coverURL)
    }

    private func loadImage(from urlString: String?) {
        imageTask?.cancel()
        imageTask = nil
        currentURL = urlString
        imageView.image = nil
        guard let urlString = urlString, let url = URL(string: urlString) else { return }
        let captured = urlString
        imageTask = URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data = data, let img = UIImage(data: data) else { return }
            DispatchQueue.main.async {
                if self?.currentURL == captured {
                    UIView.transition(with: self?.imageView ?? UIImageView(),
                                      duration: 0.2, options: .transitionCrossDissolve,
                                      animations: { self?.imageView.image = img })
                }
            }
        }
        imageTask?.resume()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageTask?.cancel(); imageTask = nil; currentURL = nil
        imageView.image = nil; titleLabel.text = nil; typeLabel.text = nil
    }
}

// MARK: - StaffCardCell

final class StaffCardCell: UICollectionViewCell {
    static let reuseID = "StaffCardCell"

    private let imageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.backgroundColor = .systemGray5
        iv.layer.cornerRadius = 6
        return iv
    }()

    private let nameLabel: UILabel = {
        let l = UILabel()
        l.font = .nunito(ofSize: 9, weight: .semibold)
        l.textColor = .label
        l.numberOfLines = 2
        return l
    }()

    private let roleLabel: UILabel = {
        let l = UILabel()
        l.font = .nunito(ofSize: 8)
        l.textColor = .secondaryLabel
        l.numberOfLines = 1
        return l
    }()

    private var imageTask: URLSessionDataTask?
    private var currentURL: String?

    override init(frame: CGRect) {
        super.init(frame: frame)
        let stack = UIStackView(arrangedSubviews: [nameLabel, roleLabel])
        stack.axis = .vertical
        stack.spacing = 2
        [imageView, stack].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview($0)
        }
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            imageView.heightAnchor.constraint(equalTo: contentView.widthAnchor, multiplier: 1.35),

            stack.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 4),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(with member: AnimeStaffMember) {
        nameLabel.text = member.name
        roleLabel.text = member.role
        imageTask?.cancel(); imageTask = nil
        currentURL = member.imageURL
        imageView.image = nil
        guard let urlStr = member.imageURL, let url = URL(string: urlStr) else { return }
        let captured = urlStr
        imageTask = URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data = data, let img = UIImage(data: data) else { return }
            DispatchQueue.main.async {
                if self?.currentURL == captured {
                    UIView.transition(with: self?.imageView ?? UIImageView(),
                                      duration: 0.2, options: .transitionCrossDissolve,
                                      animations: { self?.imageView.image = img })
                }
            }
        }
        imageTask?.resume()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageTask?.cancel(); imageTask = nil; currentURL = nil
        imageView.image = nil; nameLabel.text = nil; roleLabel.text = nil
    }
}


// MARK: - RelationGraphCell

private extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xff) / 255,
                  green: CGFloat((hex >> 8) & 0xff) / 255,
                  blue: CGFloat(hex & 0xff) / 255,
                  alpha: alpha)
    }
}

private final class RelationGraphNodeView: UIControl {
    static let width: CGFloat = 150
    private static let titleLineHeight: CGFloat = 19.2
    private static let baseHeight: CGFloat = 48.6

    private let titleContainer = UIView()
    private let titleLabel = UILabel()
    private let metaContainer = UIView()
    private let formatLabel = UILabel()
    private let statusLabel = UILabel()

    var mediaID: Int = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        backgroundColor = UIColor(hex: 0x111111)
        layer.cornerRadius = 2
        layer.borderWidth = 1
        clipsToBounds = true

        titleContainer.backgroundColor = UIColor(hex: 0x1e1e1e)
        titleContainer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleContainer)

        titleLabel.font = .nunito(ofSize: 12, weight: .bold)
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0
        titleLabel.lineBreakMode = .byWordWrapping
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleContainer.addSubview(titleLabel)

        metaContainer.backgroundColor = UIColor(hex: 0x111111)
        metaContainer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(metaContainer)

        formatLabel.font = .nunito(ofSize: 8.5, weight: .medium)
        formatLabel.textAlignment = .left
        formatLabel.textColor = .white
        formatLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        formatLabel.translatesAutoresizingMaskIntoConstraints = false
        metaContainer.addSubview(formatLabel)

        statusLabel.font = .nunito(ofSize: 8.5, weight: .medium)
        statusLabel.textAlignment = .right
        statusLabel.textColor = .white
        statusLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        metaContainer.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            titleContainer.topAnchor.constraint(equalTo: topAnchor),
            titleContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
            titleContainer.trailingAnchor.constraint(equalTo: trailingAnchor),

            titleLabel.topAnchor.constraint(equalTo: titleContainer.topAnchor, constant: 10),
            titleLabel.leadingAnchor.constraint(equalTo: titleContainer.leadingAnchor, constant: 10),
            titleLabel.trailingAnchor.constraint(equalTo: titleContainer.trailingAnchor, constant: -10),
            titleLabel.bottomAnchor.constraint(equalTo: titleContainer.bottomAnchor, constant: -8),

            metaContainer.topAnchor.constraint(equalTo: titleContainer.bottomAnchor),
            metaContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
            metaContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
            metaContainer.bottomAnchor.constraint(equalTo: bottomAnchor),
            metaContainer.heightAnchor.constraint(equalToConstant: 20.6),

            formatLabel.topAnchor.constraint(equalTo: metaContainer.topAnchor, constant: 6),
            formatLabel.leadingAnchor.constraint(equalTo: metaContainer.leadingAnchor, constant: 8),
            formatLabel.bottomAnchor.constraint(equalTo: metaContainer.bottomAnchor, constant: -6),

            statusLabel.topAnchor.constraint(equalTo: metaContainer.topAnchor, constant: 6),
            statusLabel.leadingAnchor.constraint(greaterThanOrEqualTo: formatLabel.trailingAnchor, constant: 8),
            statusLabel.trailingAnchor.constraint(equalTo: metaContainer.trailingAnchor, constant: -8),
            statusLabel.bottomAnchor.constraint(equalTo: metaContainer.bottomAnchor, constant: -6),
        ])
    }

    func configure(media: AnimeItem, isCurrent: Bool, accentColor: UIColor) {
        mediaID = media.id
        let foreground = isCurrent ? accentColor : UIColor.white
        titleLabel.text = AniListUtil.title(for: media).isEmpty ? "TBA" : AniListUtil.title(for: media)
        titleLabel.textColor = foreground
        formatLabel.text = Self.displayFormat(media.format)
        statusLabel.text = media.episodes.map { "\($0) Episodes" } ?? Self.displayStatus(media.status)
        formatLabel.textColor = foreground
        statusLabel.textColor = foreground
        layer.borderColor = (isCurrent ? accentColor : UIColor(hex: 0x111111)).cgColor
    }

    static func preferredHeight(for media: AnimeItem) -> CGFloat {
        let title = AniListUtil.title(for: media).isEmpty ? "TBA" : AniListUtil.title(for: media)
        let lineCount = max(1, Int(ceil(Double(title.count) / 20.0)))
        return baseHeight + CGFloat(lineCount) * titleLineHeight
    }

    private static func displayFormat(_ value: String?) -> String {
        guard let value else { return "N/A" }
        switch value {
        case "TV": return "TV"
        case "TV_SHORT": return "TV Short"
        default: return value.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    private static func displayStatus(_ value: String?) -> String {
        guard let value else { return "TBA" }
        return value.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

final class RelationGraphCell: UITableViewCell, UIScrollViewDelegate {
    static let reuseID = "RelationGraphCell"

    private let scrollView = UIScrollView()
    private let content = UIView()
    private let controlsStack = UIStackView()
    private let zoomInButton = UIButton(type: .system)
    private let zoomOutButton = UIButton(type: .system)
    private let fitButton = UIButton(type: .system)
    private let expandButton = UIButton(type: .system)
    private let refreshButton = UIButton(type: .system)
    private let emptyLabel = UILabel()

    private var backgroundLayers: [CAShapeLayer] = []
    private var edgeLayers: [CAShapeLayer] = []
    private var graph: AnimeRelationGraph?
    private var currentID: Int?
    private var accentColor: UIColor = .white
    private var isExpanded = false
    private var didInitialFit = false
    private var lastLayoutSize: CGSize = .zero
    private var nodeViews: [Int: RelationGraphNodeView] = [:]

    var onSelectMedia: ((Int) -> Void)?
    var onRefreshGraph: (() -> Void)?
    var onToggleExpanded: ((Bool) -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setup()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        selectionStyle = .none

        scrollView.delegate = self
        scrollView.minimumZoomScale = 0.05
        scrollView.maximumZoomScale = 1.2
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.backgroundColor = .black
        scrollView.layer.borderColor = UIColor(white: 0.22, alpha: 1).cgColor
        scrollView.layer.borderWidth = 1
        scrollView.layer.cornerRadius = 4
        scrollView.clipsToBounds = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(scrollView)
        scrollView.addSubview(content)

        emptyLabel.text = "No relations yet."
        emptyLabel.font = .nunito(ofSize: 12, weight: .semibold)
        emptyLabel.textColor = UIColor(white: 0.72, alpha: 1)
        emptyLabel.textAlignment = .center
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(emptyLabel)

        controlsStack.axis = .horizontal
        controlsStack.spacing = 0
        controlsStack.alignment = .center
        controlsStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(controlsStack)

        configureControlButton(zoomInButton, title: "+")
        configureControlButton(zoomOutButton, title: "−")
        configureControlButton(fitButton, title: "⌖")
        configureControlButton(expandButton, title: "⛶")
        configureControlButton(refreshButton, title: "↻")

        zoomInButton.addTarget(self, action: #selector(zoomInTapped), for: .touchUpInside)
        zoomOutButton.addTarget(self, action: #selector(zoomOutTapped), for: .touchUpInside)
        fitButton.addTarget(self, action: #selector(fitTapped), for: .touchUpInside)
        expandButton.addTarget(self, action: #selector(toggleExpanded), for: .touchUpInside)
        refreshButton.addTarget(self, action: #selector(refreshTapped), for: .touchUpInside)
        [zoomInButton, zoomOutButton, fitButton, expandButton, refreshButton].forEach { controlsStack.addArrangedSubview($0) }

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 56),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -56),
            scrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),

            controlsStack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 10),
            controlsStack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -10),
        ])
    }

    private func configureControlButton(_ button: UIButton, title: String) {
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        button.setTitleColor(UIColor(white: 0.08, alpha: 1), for: .normal)
        button.backgroundColor = UIColor(white: 0.96, alpha: 1)
        button.layer.borderColor = UIColor(white: 0.78, alpha: 1).cgColor
        button.layer.borderWidth = 1 / UIScreen.main.scale
        button.widthAnchor.constraint(equalToConstant: 26).isActive = true
        button.heightAnchor.constraint(equalToConstant: 26).isActive = true
    }

    func configure(graph: AnimeRelationGraph, currentID: Int?, accentColor: UIColor, expanded: Bool) {
        self.graph = graph
        self.currentID = currentID
        self.accentColor = accentColor
        self.isExpanded = expanded
        self.didInitialFit = false
        expandButton.setTitle(expanded ? "▣" : "⛶", for: .normal)
        setNeedsLayout()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        graph = nil
        currentID = nil
        didInitialFit = false
        lastLayoutSize = .zero
        clearGraph()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard scrollView.bounds.size != .zero else { return }
        if scrollView.bounds.size != lastLayoutSize {
            lastLayoutSize = scrollView.bounds.size
            didInitialFit = false
            rebuildGraph()
        } else if !didInitialFit {
            fitGraph(animated: false)
        }
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { content }

    private func clearGraph() {
        content.subviews.forEach { $0.removeFromSuperview() }
        backgroundLayers.forEach { $0.removeFromSuperlayer() }
        backgroundLayers.removeAll()
        edgeLayers.forEach { $0.removeFromSuperlayer() }
        edgeLayers.removeAll()
        nodeViews.removeAll()
    }

    private func rebuildGraph() {
        clearGraph()
        guard let graph else { return }

        let nodes = graph.nodes
        emptyLabel.isHidden = !nodes.isEmpty
        scrollView.zoomScale = 1

        let nodeWidth = RelationGraphNodeView.width
        let columnGap: CGFloat = 120
        let rowGap: CGFloat = 50
        let inset: CGFloat = 48

        let depths = relationDepths(for: graph)
        let grouped = Dictionary(grouping: nodes.keys) { depths[$0] ?? 0 }
        let sortedDepths = grouped.keys.sorted()
        var columnHeights: [Int: CGFloat] = [:]
        for depth in sortedDepths {
            let ids = sortedNodeIDs(grouped[depth] ?? [], graph: graph)
            let height = ids.reduce(CGFloat(0)) { total, id in
                guard let media = nodes[id] else { return total }
                return total + RelationGraphNodeView.preferredHeight(for: media)
            } + CGFloat(max(ids.count - 1, 0)) * rowGap
            columnHeights[depth] = height
        }

        let maxColumnHeight = max(columnHeights.values.max() ?? 0, 1)
        let contentWidth = max(scrollView.bounds.width + 1,
                               inset * 2 + CGFloat(max(sortedDepths.count, 1)) * nodeWidth + CGFloat(max(sortedDepths.count - 1, 0)) * columnGap)
        let contentHeight = max(scrollView.bounds.height + 1, inset * 2 + maxColumnHeight)
        content.frame = CGRect(origin: .zero, size: CGSize(width: contentWidth, height: contentHeight))
        scrollView.contentSize = content.bounds.size
        drawBackground(in: content.bounds)

        for (columnIndex, depth) in sortedDepths.enumerated() {
            let ids = sortedNodeIDs(grouped[depth] ?? [], graph: graph)
            let columnHeight = columnHeights[depth] ?? 0
            var y = max(inset, (contentHeight - columnHeight) / 2)
            let x = inset + CGFloat(columnIndex) * (nodeWidth + columnGap)
            for id in ids {
                guard let media = nodes[id] else { continue }
                let height = RelationGraphNodeView.preferredHeight(for: media)
                let node = RelationGraphNodeView(frame: CGRect(x: x, y: y, width: nodeWidth, height: height))
                node.configure(media: media, isCurrent: id == currentID, accentColor: accentColor)
                node.addTarget(self, action: #selector(nodeTapped(_:)), for: .touchUpInside)
                content.addSubview(node)
                nodeViews[id] = node
                y += height + rowGap
            }
        }

        drawEdges(graph)
        fitGraph(animated: false)
    }

    private func drawBackground(in rect: CGRect) {
        let spacing: CGFloat = 24
        let dotRadius: CGFloat = 0.7
        let path = UIBezierPath()
        var y: CGFloat = 0
        while y <= rect.height {
            var x: CGFloat = 0
            while x <= rect.width {
                path.append(UIBezierPath(ovalIn: CGRect(x: x, y: y, width: dotRadius * 2, height: dotRadius * 2)))
                x += spacing
            }
            y += spacing
        }
        let layer = CAShapeLayer()
        layer.path = path.cgPath
        layer.fillColor = UIColor(white: 0.24, alpha: 0.38).cgColor
        content.layer.insertSublayer(layer, at: 0)
        backgroundLayers.append(layer)
    }

    private func sortedNodeIDs(_ ids: [Int], graph: AnimeRelationGraph) -> [Int] {
        ids.sorted { lhs, rhs in
            if lhs == currentID { return true }
            if rhs == currentID { return false }
            let leftTitle = graph.nodes[lhs].map { AniListUtil.title(for: $0) } ?? ""
            let rightTitle = graph.nodes[rhs].map { AniListUtil.title(for: $0) } ?? ""
            if leftTitle != rightTitle { return leftTitle < rightTitle }
            return lhs < rhs
        }
    }

    private func relationDepths(for graph: AnimeRelationGraph) -> [Int: Int] {
        guard let currentID, graph.nodes[currentID] != nil else {
            return Dictionary(uniqueKeysWithValues: graph.nodes.keys.map { ($0, 0) })
        }

        var depths: [Int: Int] = [currentID: 0]
        var queue: [Int] = [currentID]
        while let id = queue.first {
            queue.removeFirst()
            let depth = depths[id] ?? 0
            for edge in graph.edges.values {
                if edge.sourceID == id, depths[edge.targetID] == nil {
                    depths[edge.targetID] = depth + 1
                    queue.append(edge.targetID)
                } else if edge.targetID == id, depths[edge.sourceID] == nil {
                    depths[edge.sourceID] = depth - 1
                    queue.append(edge.sourceID)
                }
            }
        }

        let maxDepth = (depths.values.max() ?? 0) + 1
        for id in graph.nodes.keys where depths[id] == nil {
            depths[id] = maxDepth
        }
        let offset = -(depths.values.min() ?? 0)
        return depths.mapValues { $0 + offset }
    }

    private func drawEdges(_ graph: AnimeRelationGraph) {
        for edge in graph.edges.values.sorted(by: { $0.id < $1.id }) {
            guard let source = nodeViews[edge.sourceID],
                  let target = nodeViews[edge.targetID] else { continue }
            let start = CGPoint(x: source.frame.maxX, y: source.frame.midY)
            let end = CGPoint(x: target.frame.minX, y: target.frame.midY)
            let midX = (start.x + end.x) / 2

            let path = UIBezierPath()
            path.move(to: start)
            path.addCurve(to: end,
                          controlPoint1: CGPoint(x: midX, y: start.y),
                          controlPoint2: CGPoint(x: midX, y: end.y))

            let isCurrentEdge = [edge.sourceID, edge.targetID].contains(currentID ?? -1)
            let layer = CAShapeLayer()
            layer.path = path.cgPath
            layer.strokeColor = (isCurrentEdge ? accentColor : UIColor(white: 0.62, alpha: 1)).cgColor
            layer.fillColor = UIColor.clear.cgColor
            layer.lineWidth = isCurrentEdge ? 2 : 1.5
            content.layer.insertSublayer(layer, above: backgroundLayers.last)
            edgeLayers.append(layer)

            addEdgeLabel(edge.relationType.replacingOccurrences(of: "_", with: " "),
                         at: CGPoint(x: midX, y: (start.y + end.y) / 2),
                         highlighted: isCurrentEdge)
        }
    }

    private func addEdgeLabel(_ text: String, at center: CGPoint, highlighted: Bool) {
        let label = UILabel()
        label.text = text
        label.font = .nunito(ofSize: 9, weight: .semibold)
        label.textColor = highlighted ? accentColor : UIColor(white: 0.84, alpha: 1)
        label.backgroundColor = .black
        label.textAlignment = .center
        label.sizeToFit()
        let width = max(52, label.bounds.width + 12)
        label.frame = CGRect(x: center.x - width / 2, y: center.y - 11, width: width, height: 22)
        content.addSubview(label)
    }

    private func fitGraph(animated: Bool) {
        guard content.bounds.width > 0, content.bounds.height > 0 else { return }
        let viewport = scrollView.bounds.insetBy(dx: 18, dy: 18).size
        guard viewport.width > 0, viewport.height > 0 else { return }
        let scale = min(1.2, max(0.05, min(viewport.width / content.bounds.width,
                                           viewport.height / content.bounds.height)))
        scrollView.setZoomScale(scale, animated: animated)
        centerCurrentNode(animated: animated)
        didInitialFit = true
    }

    private func centerCurrentNode(animated: Bool) {
        guard let currentID, let node = nodeViews[currentID] else { return }
        let visibleWidth = scrollView.bounds.width / max(scrollView.zoomScale, 0.05)
        let visibleHeight = scrollView.bounds.height / max(scrollView.zoomScale, 0.05)
        var rect = CGRect(x: node.frame.midX - visibleWidth / 2,
                          y: node.frame.midY - visibleHeight / 2,
                          width: visibleWidth,
                          height: visibleHeight)
        rect.origin.x = max(0, min(rect.origin.x, max(0, content.bounds.width - rect.width)))
        rect.origin.y = max(0, min(rect.origin.y, max(0, content.bounds.height - rect.height)))
        scrollView.scrollRectToVisible(rect, animated: animated)
    }

    @objc private func zoomInTapped() {
        scrollView.setZoomScale(min(scrollView.maximumZoomScale, scrollView.zoomScale * 1.2), animated: true)
    }

    @objc private func zoomOutTapped() {
        scrollView.setZoomScale(max(scrollView.minimumZoomScale, scrollView.zoomScale / 1.2), animated: true)
    }

    @objc private func fitTapped() {
        fitGraph(animated: true)
    }

    @objc private func toggleExpanded() {
        isExpanded.toggle()
        expandButton.setTitle(isExpanded ? "▣" : "⛶", for: .normal)
        onToggleExpanded?(isExpanded)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { [weak self] in
            self?.fitGraph(animated: true)
        }
    }

    @objc private func refreshTapped() {
        onRefreshGraph?()
    }

    @objc private func nodeTapped(_ sender: RelationGraphNodeView) {
        guard sender.mediaID != currentID else { return }
        onSelectMedia?(sender.mediaID)
    }
}

// MARK: - ScoreBarChartView + StatsCell

final class ScoreBarChartView: UIView {
    private var arrangedStack: UIStackView?

    func configure(with points: [AnimeScorePoint]) {
        arrangedStack?.removeFromSuperview()
        arrangedStack = nil
        guard !points.isEmpty else { return }
        let maxAmount = points.map { $0.amount }.max() ?? 1
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.alignment = .bottom
        stack.spacing = 3
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        arrangedStack = stack
        for point in points {
            let col = UIView()
            let bar = UIView()
            let alpha = 0.4 + 0.6 * CGFloat(point.score) / 100.0
            bar.backgroundColor = UIColor.systemIndigo.withAlphaComponent(alpha)
            bar.layer.cornerRadius = 2
            bar.translatesAutoresizingMaskIntoConstraints = false
            let lbl = UILabel()
            lbl.text = "\(point.score)"
            lbl.font = .nunito(ofSize: 7)
            lbl.textColor = .tertiaryLabel
            lbl.textAlignment = .center
            lbl.translatesAutoresizingMaskIntoConstraints = false
            col.addSubview(bar)
            col.addSubview(lbl)
            let fraction = max(0.04, CGFloat(point.amount) / CGFloat(maxAmount))
            NSLayoutConstraint.activate([
                lbl.bottomAnchor.constraint(equalTo: col.bottomAnchor),
                lbl.leadingAnchor.constraint(equalTo: col.leadingAnchor),
                lbl.trailingAnchor.constraint(equalTo: col.trailingAnchor),
                lbl.heightAnchor.constraint(equalToConstant: 14),
                bar.leadingAnchor.constraint(equalTo: col.leadingAnchor),
                bar.trailingAnchor.constraint(equalTo: col.trailingAnchor),
                bar.bottomAnchor.constraint(equalTo: lbl.topAnchor, constant: -2),
                bar.heightAnchor.constraint(equalTo: col.heightAnchor, multiplier: fraction * 0.85),
            ])
            stack.addArrangedSubview(col)
        }
    }
}

final class StatsCell: UITableViewCell {
    static let reuseID = "AniDetailStatsCell"

    private let chartView = ScoreBarChartView()
    private let statusStack = UIStackView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setup()
    }
    required init?(coder: NSCoder) { super.init(coder: coder); setup() }

    private func makeTitle(_ text: String) -> UILabel {
        let l = UILabel()
        l.text = text
        l.font = .nunito(ofSize: 14, weight: .semibold)
        l.textColor = .label
        return l
    }

    private func setup() {
        backgroundColor = .clear
        selectionStyle = .none
        chartView.translatesAutoresizingMaskIntoConstraints = false
        statusStack.axis = .vertical
        statusStack.spacing = 10
        let mainStack = UIStackView(arrangedSubviews: [
            makeTitle("Score Distribution"), chartView,
            makeTitle("Watching Status"), statusStack,
        ])
        mainStack.axis = .vertical
        mainStack.spacing = 14
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(mainStack)
        NSLayoutConstraint.activate([
            chartView.heightAnchor.constraint(equalToConstant: 90),
            mainStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            mainStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            mainStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            mainStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),
        ])
    }

    func configure(scores: [AnimeScorePoint], statuses: [AnimeStatusCount]) {
        chartView.configure(with: scores)
        statusStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let total = statuses.reduce(0) { $0 + $1.amount }
        for status in statuses {
            let fraction = total > 0 ? Float(status.amount) / Float(total) : 0
            let name = status.status.replacingOccurrences(of: "_", with: " ").capitalized
            let nameLabel = UILabel()
            nameLabel.text = name
            nameLabel.font = .nunito(ofSize: 11)
            nameLabel.textColor = .label
            nameLabel.widthAnchor.constraint(equalToConstant: 80).isActive = true
            let progress = UIProgressView(progressViewStyle: .default)
            progress.setProgress(fraction, animated: false)
            progress.progressTintColor = Self.statusColor(for: status.status)
            progress.trackTintColor = .systemGray5
            let countLabel = UILabel()
            countLabel.text = "\(status.amount)"
            countLabel.font = .nunito(ofSize: 11)
            countLabel.textColor = .secondaryLabel
            countLabel.textAlignment = .right
            countLabel.widthAnchor.constraint(equalToConstant: 52).isActive = true
            let row = UIStackView(arrangedSubviews: [nameLabel, progress, countLabel])
            row.axis = .horizontal
            row.spacing = 8
            row.alignment = .center
            statusStack.addArrangedSubview(row)
        }
    }

    private static func statusColor(for status: String) -> UIColor {
        switch status {
        case "CURRENT":   return UIColor(red: 61/255,  green: 180/255, blue: 242/255, alpha: 1)
        case "PLANNING":  return UIColor(red: 247/255, green: 154/255, blue: 99/255,  alpha: 1)
        case "COMPLETED": return UIColor(red: 123/255, green: 213/255, blue: 85/255,  alpha: 1)
        case "PAUSED":    return UIColor(red: 250/255, green: 122/255, blue: 122/255, alpha: 1)
        case "REPEATING": return UIColor(red: 59/255,  green: 174/255, blue: 234/255, alpha: 1)
        default:          return UIColor(red: 200/255, green: 80/255,  blue: 80/255,  alpha: 1)
        }
    }
}

// MARK: - Relations fetching

extension AnimeDetailViewController {

    func fetchLegacyAnimeDetailsIfNeeded() {
        let needsRelations = relations.isEmpty && relationGraph == nil && animeItem?.relations.isEmpty != false
        let needsTrailer = animeItem == nil || animeItem?.trailerYouTubeID == nil
        let needsMAL = animeItem == nil || animeItem?.malId == nil
        let needsGenres = animeItem == nil || animeItem?.genres.isEmpty == true
        guard needsRelations || needsTrailer || needsMAL || needsGenres else { return }
        fetchRelationsAndCharacters()
    }


    var hasRelationsContent: Bool {
        relationGraph != nil || animeItem != nil || !relations.isEmpty
    }

    func applyRelationGraph(_ graph: AnimeRelationGraph) {
        relationGraph = graph.nodes.isEmpty ? fallbackRelationGraph() : graph
    }

    func fallbackRelationGraph() -> AnimeRelationGraph? {
        guard let current = animeItem else { return nil }
        var graph = AnimeRelationGraph(nodes: [current.id: current], edges: [:])
        for relation in current.relations {
            graph.nodes[relation.media.id] = relation.media
            let sourceID = relation.sourceID ?? current.id
            let targetID = relation.media.id
            let relationType = relation.relationType
            let isPrequel = relationType == "PREQUEL"
            let lhs = min(sourceID, targetID)
            let rhs = max(sourceID, targetID)
            graph.edges["\(lhs)-\(rhs)"] = AnimeRelationGraphEdge(
                id: "e\(lhs)-\(rhs)",
                sourceID: isPrequel ? targetID : sourceID,
                targetID: isPrequel ? sourceID : targetID,
                relationType: isPrequel ? "SEQUEL" : relationType)
        }
        return graph
    }

    func expandRelationGraphIfNeeded(_ graph: AnimeRelationGraph, reload: Bool = false) {
        guard reload || !graph.boundaryIDs.isEmpty else { return }
        AniListClient.shared.expandRelationGraph(graph, reload: reload) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let expandedGraph):
                self.relationGraph = expandedGraph
                if self.activeSection == .relations {
                    self.tableView.reloadSections(IndexSet(integer: Section.relations.rawValue), with: .fade)
                }
            case .failure(let error):
                NSLog("[AnimeDetail] Relations tree expansion failed: %@", error.description)
            }
        }
    }

    func makeRelationsCell(for indexPath: IndexPath) -> UITableViewCell {
        if let graph = relationGraph ?? fallbackRelationGraph(),
           let cell = tableView.dequeueReusableCell(
            withIdentifier: RelationGraphCell.reuseID,
            for: indexPath) as? RelationGraphCell {
            if relationGraph == nil { relationGraph = graph }
            cell.configure(graph: graph,
                           currentID: routeAnimeID,
                           accentColor: currentAnimeAccent,
                           expanded: relationGraphExpanded)
            cell.onSelectMedia = { [weak self] id in
                Router.shared.navigate(.anime(id: id), hostTabIndex: self?.tabBarController?.selectedIndex)
            }
            cell.onToggleExpanded = { [weak self] expanded in
                guard let self else { return }
                self.relationGraphExpanded = expanded
                self.tableView.performBatchUpdates(nil)
            }
            cell.onRefreshGraph = { [weak self] in
                guard let self, let graph = self.relationGraph else { return }
                self.expandRelationGraphIfNeeded(graph, reload: true)
            }
            return cell
        }

        guard let cell = tableView.dequeueReusableCell(
            withIdentifier: HorizontalCardsCell.relationsReuseID,
            for: indexPath) as? HorizontalCardsCell else { return UITableViewCell() }
        cell.collectionView.tag = 100
        cell.collectionView.dataSource = self
        cell.collectionView.delegate = self
        cell.collectionView.register(RelationCardCell.self,
                                     forCellWithReuseIdentifier: RelationCardCell.reuseID)
        cell.applyPaddingForSizeClass(isRegular: traitCollection.horizontalSizeClass == .regular)
        cell.collectionView.reloadData()
        return cell
    }

    func fetchRelationsAndCharacters() {
        guard let anilistId = routeAnimeID else { return }

        if relations.isEmpty && animeItem?.relations.isEmpty != false {
            AniListClient.shared.fetchDetailForItemResult(id: anilistId) { [weak self] result in
                guard let self, self.routeAnimeID == anilistId else { return }
                switch result {
                case .success(let rels) where !rels.isEmpty:
                    self.relations = rels
                    self.tableView.reloadSections(IndexSet(integer: Section.relations.rawValue), with: .fade)
                case .success:
                    break
                case .failure(let error):
                    NSLog("[AnimeDetail] Relation fallback failed: %@", error.description)
                }
            }
        }

        let needsTrailer = animeItem == nil || animeItem?.trailerYouTubeID == nil
        let needsMAL = animeItem == nil || animeItem?.malId == nil
        let needsGenres = animeItem == nil || animeItem?.genres.isEmpty == true
        guard needsTrailer || needsMAL || needsGenres else { return }

        AniListClient.shared.fetchTrailerAndGenresResult(id: anilistId) { [weak self] result in
            guard let self, self.routeAnimeID == anilistId else { return }
            switch result {
            case .success(let payload):
                if needsGenres {
                    self.headerView?.updateGenresAndTrailer(genres: payload.genres, trailerYouTubeID: payload.trailerYouTubeID)
                } else if let trailerID = payload.trailerYouTubeID {
                    self.headerView?.updateTrailerButton(trailerYouTubeID: trailerID)
                }
                if self.animeItem?.trailerYouTubeID == nil {
                    self.animeItem?.trailerYouTubeID = payload.trailerYouTubeID
                }

                if let malId = payload.malId, self.headerView?.malId == nil {
                    self.headerView?.malId = malId
                    self.animeItem?.malId = malId
                    self.headerView?.updateMALButtonVisibility()
                }
            case .failure(let error):
                NSLog("[AnimeDetail] Trailer/genres failed: %@", error.description)
            }
        }
    }
}
