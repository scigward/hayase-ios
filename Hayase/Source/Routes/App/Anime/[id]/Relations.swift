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

final class RelationGraphCell: UITableViewCell, UIScrollViewDelegate {
    static let reuseID = "RelationGraphCell"

    private let scrollView = UIScrollView()
    private let content = UIView()
    private let controlsStack = UIStackView()
    private let expandButton = UIButton(type: .system)
    private let refreshButton = UIButton(type: .system)

    private var edgeLayers: [CAShapeLayer] = []
    private var graph: AnimeRelationGraph?
    private var currentID: Int?
    private var accentColor: UIColor = .white
    private var isExpanded = false
    private var nodeButtons: [Int: UIButton] = [:]

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
        scrollView.minimumZoomScale = 0.35
        scrollView.maximumZoomScale = 1.2
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.backgroundColor = UIColor(white: 0.02, alpha: 1)
        scrollView.layer.borderColor = UIColor(white: 0.16, alpha: 1).cgColor
        scrollView.layer.borderWidth = 1
        scrollView.layer.cornerRadius = 8
        scrollView.clipsToBounds = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(scrollView)
        scrollView.addSubview(content)

        controlsStack.axis = .horizontal
        controlsStack.spacing = 8
        controlsStack.alignment = .center
        controlsStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(controlsStack)

        configureControlButton(expandButton, title: "⛶")
        configureControlButton(refreshButton, title: "↻")
        expandButton.addTarget(self, action: #selector(toggleExpanded), for: .touchUpInside)
        refreshButton.addTarget(self, action: #selector(refreshTapped), for: .touchUpInside)
        controlsStack.addArrangedSubview(expandButton)
        controlsStack.addArrangedSubview(refreshButton)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 56),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -56),
            scrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),

            controlsStack.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 10),
            controlsStack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -10),
        ])
    }

    private func configureControlButton(_ button: UIButton, title: String) {
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 18, weight: .semibold)
        button.setTitleColor(.white, for: .normal)
        button.backgroundColor = UIColor(white: 0.09, alpha: 0.92)
        button.layer.cornerRadius = 6
        button.layer.borderColor = UIColor(white: 0.22, alpha: 1).cgColor
        button.layer.borderWidth = 1
        button.widthAnchor.constraint(equalToConstant: 36).isActive = true
        button.heightAnchor.constraint(equalToConstant: 32).isActive = true
    }

    func configure(graph: AnimeRelationGraph, currentID: Int?, accentColor: UIColor, expanded: Bool) {
        self.graph = graph
        self.currentID = currentID
        self.accentColor = accentColor
        self.isExpanded = expanded
        expandButton.setTitle(expanded ? "⛶" : "⛶", for: .normal)
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        rebuildGraph()
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { content }

    private func rebuildGraph() {
        guard let graph, !graph.nodes.isEmpty else { return }
        content.subviews.forEach { $0.removeFromSuperview() }
        edgeLayers.forEach { $0.removeFromSuperlayer() }
        edgeLayers.removeAll()
        nodeButtons.removeAll()
        scrollView.zoomScale = 1

        let nodeWidth: CGFloat = 150
        let baseNodeHeight: CGFloat = 56
        let columnGap: CGFloat = 120
        let rowGap: CGFloat = 50
        let inset: CGFloat = 36

        let depths = relationDepths(for: graph)
        let grouped = Dictionary(grouping: graph.nodes.keys) { depths[$0] ?? 0 }
        let sortedDepths = grouped.keys.sorted()
        let maxRows = grouped.values.map(\.count).max() ?? 1
        let contentWidth = max(scrollView.bounds.width + 1,
                               inset * 2 + CGFloat(max(sortedDepths.count, 1)) * nodeWidth + CGFloat(max(sortedDepths.count - 1, 0)) * columnGap)
        let contentHeight = max(scrollView.bounds.height + 1,
                                inset * 2 + CGFloat(maxRows) * baseNodeHeight + CGFloat(max(maxRows - 1, 0)) * rowGap)
        content.frame = CGRect(origin: .zero, size: CGSize(width: contentWidth, height: contentHeight))
        scrollView.contentSize = content.bounds.size

        for (columnIndex, depth) in sortedDepths.enumerated() {
            let ids = sortedNodeIDs(grouped[depth] ?? [], graph: graph)
            let columnHeight = CGFloat(ids.count) * baseNodeHeight + CGFloat(max(ids.count - 1, 0)) * rowGap
            let startY = max(inset, (contentHeight - columnHeight) / 2)
            let x = inset + CGFloat(columnIndex) * (nodeWidth + columnGap)
            for (rowIndex, id) in ids.enumerated() {
                guard let media = graph.nodes[id] else { continue }
                let y = startY + CGFloat(rowIndex) * (baseNodeHeight + rowGap)
                let button = makeNodeButton(media: media, isCurrent: id == currentID)
                button.tag = id
                button.frame = CGRect(x: x, y: y, width: nodeWidth, height: baseNodeHeight)
                button.addTarget(self, action: #selector(nodeTapped(_:)), for: .touchUpInside)
                content.addSubview(button)
                nodeButtons[id] = button
            }
        }

        drawEdges(graph)
        centerCurrentNodeIfNeeded()
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

    private func makeNodeButton(media: AnimeItem, isCurrent: Bool) -> UIButton {
        let button = UIButton(type: .custom)
        button.backgroundColor = UIColor(white: 0.07, alpha: 1)
        button.layer.cornerRadius = 4
        button.layer.borderWidth = isCurrent ? 1.5 : 1
        button.layer.borderColor = (isCurrent ? accentColor : UIColor(white: 0.18, alpha: 1)).cgColor
        button.titleLabel?.numberOfLines = 3
        button.titleLabel?.textAlignment = .center
        button.titleLabel?.font = .nunito(ofSize: 11, weight: .semibold)
        button.setTitleColor(isCurrent ? accentColor : .white, for: .normal)

        let title = AniListUtil.title(for: media)
        let meta = media.episodes.map { "\($0) Episodes" } ?? displayStatus(media.status)
        button.setTitle("\(title)\n\(displayFormat(media.format)) · \(meta)", for: .normal)
        return button
    }

    private func displayFormat(_ value: String?) -> String {
        guard let value else { return "N/A" }
        switch value {
        case "TV": return "TV"
        case "TV_SHORT": return "TV Short"
        default: return value.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    private func displayStatus(_ value: String?) -> String {
        guard let value else { return "TBA" }
        return value.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private func drawEdges(_ graph: AnimeRelationGraph) {
        for edge in graph.edges.values.sorted(by: { $0.id < $1.id }) {
            guard let source = nodeButtons[edge.sourceID],
                  let target = nodeButtons[edge.targetID] else { continue }
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
            layer.strokeColor = (isCurrentEdge ? accentColor : UIColor(white: 0.45, alpha: 1)).withAlphaComponent(isCurrentEdge ? 0.9 : 0.55).cgColor
            layer.fillColor = UIColor.clear.cgColor
            layer.lineWidth = isCurrentEdge ? 1.6 : 1.1
            content.layer.insertSublayer(layer, at: 0)
            edgeLayers.append(layer)

            let label = UILabel()
            label.text = edge.relationType.replacingOccurrences(of: "_", with: " ")
            label.font = .nunito(ofSize: 9, weight: .semibold)
            label.textColor = isCurrentEdge ? accentColor : UIColor(white: 0.78, alpha: 1)
            label.backgroundColor = UIColor(white: 0.02, alpha: 0.92)
            label.textAlignment = .center
            label.sizeToFit()
            let width = max(52, label.bounds.width + 12)
            label.frame = CGRect(x: midX - width / 2, y: (start.y + end.y) / 2 - 11, width: width, height: 22)
            label.layer.cornerRadius = 4
            label.clipsToBounds = true
            content.addSubview(label)
        }
    }

    private func centerCurrentNodeIfNeeded() {
        guard let currentID, let button = nodeButtons[currentID] else { return }
        let visibleSize = scrollView.bounds.size
        var target = button.frame.insetBy(dx: -visibleSize.width / 2 + button.bounds.width / 2,
                                          dy: -visibleSize.height / 2 + button.bounds.height / 2)
        target.origin.x = max(0, target.origin.x)
        target.origin.y = max(0, target.origin.y)
        scrollView.scrollRectToVisible(target, animated: false)
    }

    @objc private func toggleExpanded() {
        isExpanded.toggle()
        onToggleExpanded?(isExpanded)
    }

    @objc private func refreshTapped() {
        onRefreshGraph?()
    }

    @objc private func nodeTapped(_ sender: UIButton) {
        guard sender.tag != currentID else { return }
        onSelectMedia?(sender.tag)
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


    func applyRelationGraph(_ graph: AnimeRelationGraph) {
        relationGraph = graph
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
        if let graph = relationGraph,
           let cell = tableView.dequeueReusableCell(
            withIdentifier: RelationGraphCell.reuseID,
            for: indexPath) as? RelationGraphCell {
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
