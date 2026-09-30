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
            let width = collectionView.superview?.bounds.width ?? collectionView.bounds.width
            let sidePad = isRegular
                ? AnimeDetailViewController.interfacePageSideInset(for: width)
                : CGFloat(16)
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
        iv.backgroundColor = UIColor.HayaseTheme.muted
        iv.layer.cornerRadius = 6
        return iv
    }()

    private let titleLabel: UILabel = {
        let l = UILabel()
        l.font = .nunito(ofSize: 9, weight: .semibold)
        l.textColor = UIColor.HayaseTheme.foreground
        l.numberOfLines = 2
        return l
    }()

    private let typeLabel: UILabel = {
        let l = UILabel()
        l.font = .nunito(ofSize: 8, weight: .medium)
        l.textColor = .white
        l.backgroundColor = UIColor.HayaseTheme.secondary.withAlphaComponent(0.85)
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
        iv.backgroundColor = UIColor.HayaseTheme.muted
        iv.layer.cornerRadius = 6
        return iv
    }()

    private let nameLabel: UILabel = {
        let l = UILabel()
        l.font = .nunito(ofSize: 9, weight: .semibold)
        l.textColor = UIColor.HayaseTheme.foreground
        l.numberOfLines = 2
        return l
    }()

    private let roleLabel: UILabel = {
        let l = UILabel()
        l.font = .nunito(ofSize: 8)
        l.textColor = UIColor.HayaseTheme.mutedForeground
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

private final class RelationGraphBackgroundView: UIView {
    var dotSpacing: CGFloat = 20 { didSet { setNeedsDisplay() } }
    var dotRadius: CGFloat = 0.65 { didSet { setNeedsDisplay() } }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = true
        backgroundColor = .black
        contentMode = .redraw
    }

    required init?(coder: NSCoder) { fatalError() }

    func updateViewport(offset: CGPoint, zoomScale: CGFloat) {
        // Svelte Flow's background stays visually screen-spaced while the graph
        // zooms/pans above it. Do not couple the dot grid to graph transform.
    }

    override func draw(_ rect: CGRect) {
        UIColor.black.setFill()
        UIRectFill(rect)

        guard let context = UIGraphicsGetCurrentContext() else { return }
        let spacing = max(dotSpacing, 1)
        let radius = max(dotRadius, 0.1)
        let diameter = radius * 2
        let path = CGMutablePath()

        var y = rect.minY - rect.minY.truncatingRemainder(dividingBy: spacing)
        while y < rect.minY - spacing { y += spacing }
        while y <= rect.maxY + spacing {
            var x = rect.minX - rect.minX.truncatingRemainder(dividingBy: spacing)
            while x < rect.minX - spacing { x += spacing }
            while x <= rect.maxX + spacing {
                path.addEllipse(in: CGRect(x: x - radius, y: y - radius, width: diameter, height: diameter))
                x += spacing
            }
            y += spacing
        }

        context.setFillColor(UIColor(hex: 0x81818a, alpha: 0.86).cgColor)
        context.addPath(path)
        context.fillPath()
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
        layer.borderColor = UIColor(hex: 0x111111).cgColor
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

        formatLabel.font = .nunito(ofSize: 8.5, weight: .semibold)
        formatLabel.textAlignment = .left
        formatLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        formatLabel.translatesAutoresizingMaskIntoConstraints = false
        metaContainer.addSubview(formatLabel)

        statusLabel.font = .nunito(ofSize: 8.5, weight: .semibold)
        statusLabel.textAlignment = .right
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

            formatLabel.leadingAnchor.constraint(equalTo: metaContainer.leadingAnchor, constant: 8),
            formatLabel.centerYAnchor.constraint(equalTo: metaContainer.centerYAnchor),

            statusLabel.leadingAnchor.constraint(greaterThanOrEqualTo: formatLabel.trailingAnchor, constant: 8),
            statusLabel.trailingAnchor.constraint(equalTo: metaContainer.trailingAnchor, constant: -8),
            statusLabel.centerYAnchor.constraint(equalTo: metaContainer.centerYAnchor),
        ])
    }

    func configure(media: AnimeItem, isCurrent: Bool, accentColor: UIColor) {
        mediaID = media.id
        let title = AniListUtil.title(for: media)
        let foreground = isCurrent ? accentColor : UIColor(white: 0.92, alpha: 1)
        titleLabel.text = title.isEmpty ? "TBA" : title
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

    private struct LayoutResult {
        let frames: [Int: CGRect]
        let contentSize: CGSize
        let nodeBounds: CGRect
    }

    private let backgroundGrid = RelationGraphBackgroundView()
    private let scrollView = UIScrollView()
    private let content = UIView()
    private let controlsStack = UIStackView()
    private let zoomInButton = UIButton(type: .system)
    private let zoomOutButton = UIButton(type: .system)
    private let fitButton = UIButton(type: .system)
    private let expandButton = UIButton(type: .system)
    private let refreshButton = UIButton(type: .system)
    private lazy var nodeTapRecognizer = UITapGestureRecognizer(target: self, action: #selector(graphTapped(_:)))

    private var graphLeadingConstraint: NSLayoutConstraint?
    private var graphTrailingConstraint: NSLayoutConstraint?
    private var edgeLayers: [CAShapeLayer] = []
    private var edgeLabels: [UILabel] = []
    private var graph: AnimeRelationGraph?
    private var currentID: Int?
    private var accentColor: UIColor = .white
    private var isExpanded = false
    private var didInitialFit = false
    private var lastLayoutSize: CGSize = .zero
    private var nodeViews: [Int: RelationGraphNodeView] = [:]
    private var graphNodeBounds: CGRect = .null
    private var lastNodeSelection: (id: Int, time: CFTimeInterval)?

    private let nodeWidth = RelationGraphNodeView.width
    private let rankSeparation: CGFloat = 120
    private let nodeSeparation: CGFloat = 50
    private let canvasPadding: CGFloat = 40
    private let edgeSeparation: CGFloat = 50

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

        backgroundGrid.translatesAutoresizingMaskIntoConstraints = false
        backgroundGrid.layer.borderColor = UIColor(white: 0.19, alpha: 1).cgColor
        backgroundGrid.layer.borderWidth = 1
        backgroundGrid.layer.cornerRadius = 4
        backgroundGrid.clipsToBounds = true
        contentView.addSubview(backgroundGrid)

        scrollView.delegate = self
        scrollView.minimumZoomScale = 0.01
        scrollView.maximumZoomScale = 1.2
        scrollView.bouncesZoom = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.backgroundColor = .clear
        scrollView.layer.borderColor = UIColor.clear.cgColor
        scrollView.layer.borderWidth = 0
        scrollView.clipsToBounds = true
        scrollView.delaysContentTouches = false
        scrollView.canCancelContentTouches = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(scrollView)
        scrollView.addSubview(content)
        nodeTapRecognizer.cancelsTouchesInView = false
        scrollView.addGestureRecognizer(nodeTapRecognizer)

        controlsStack.axis = .horizontal
        controlsStack.spacing = 0
        controlsStack.alignment = .center
        controlsStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(controlsStack)

        configureControlButton(zoomInButton, lucideName: "plus", fallback: "+")
        configureControlButton(zoomOutButton, lucideName: "minus", fallback: "−")
        configureControlButton(fitButton, lucideName: "scan", fallback: "⌖")
        configureControlButton(expandButton, lucideName: "maximize-2", fallback: "⛶")
        configureControlButton(refreshButton, lucideName: "refresh-cw", fallback: "↻")

        zoomInButton.addTarget(self, action: #selector(zoomInTapped), for: .touchUpInside)
        zoomOutButton.addTarget(self, action: #selector(zoomOutTapped), for: .touchUpInside)
        fitButton.addTarget(self, action: #selector(fitTapped), for: .touchUpInside)
        expandButton.addTarget(self, action: #selector(toggleExpanded), for: .touchUpInside)
        refreshButton.addTarget(self, action: #selector(refreshTapped), for: .touchUpInside)
        [zoomInButton, zoomOutButton, fitButton, expandButton, refreshButton].forEach { controlsStack.addArrangedSubview($0) }

        let graphLeading = backgroundGrid.leadingAnchor.constraint(equalTo: contentView.leadingAnchor)
        let graphTrailing = backgroundGrid.trailingAnchor.constraint(equalTo: contentView.trailingAnchor)
        graphLeadingConstraint = graphLeading
        graphTrailingConstraint = graphTrailing

        NSLayoutConstraint.activate([
            backgroundGrid.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            graphLeading,
            graphTrailing,
            backgroundGrid.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            scrollView.topAnchor.constraint(equalTo: backgroundGrid.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: backgroundGrid.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: backgroundGrid.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: backgroundGrid.bottomAnchor),

            controlsStack.leadingAnchor.constraint(equalTo: backgroundGrid.leadingAnchor, constant: 10),
            controlsStack.bottomAnchor.constraint(equalTo: backgroundGrid.bottomAnchor, constant: -10),
        ])
    }

    func applyWindowInset(for viewportWidth: CGFloat) {
        let pageMaxWidth: CGFloat = 1600
        let outerInset = max((viewportWidth - pageMaxWidth) / 2, 0)
        let innerInset = AnimeDetailViewController.interfacePageSideInset(for: viewportWidth)
        let inset = outerInset + innerInset
        graphLeadingConstraint?.constant = inset
        graphTrailingConstraint?.constant = -inset
    }

    private func configureControlButton(_ button: UIButton, lucideName: String, fallback: String) {
        let config = UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        if let image = UIImage.hayaseIcon(lucideName, withConfiguration: config) {
            button.setImage(image, for: .normal)
            button.setTitle(nil, for: .normal)
        } else {
            button.setImage(nil, for: .normal)
            button.setTitle(fallback, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        }
        button.tintColor = UIColor(white: 0.92, alpha: 1)
        button.setTitleColor(UIColor(white: 0.92, alpha: 1), for: .normal)
        button.backgroundColor = UIColor(hex: 0x1f1f1f)
        button.layer.borderColor = UIColor(hex: 0x373737).cgColor
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
        updateExpandIcon()
        setNeedsLayout()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        graph = nil
        currentID = nil
        didInitialFit = false
        lastLayoutSize = .zero
        graphNodeBounds = .null
        clearGraph()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard scrollView.bounds.size != .zero else { return }
        backgroundGrid.setNeedsDisplay()
        if scrollView.bounds.size != lastLayoutSize {
            lastLayoutSize = scrollView.bounds.size
            didInitialFit = false
            rebuildGraph()
        } else if !didInitialFit {
            fitGraph(animated: false)
        }
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { content }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerZoomedContent()
        updateBackgroundViewport()
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        updateBackgroundViewport()
    }

    private func updateBackgroundViewport() {
        backgroundGrid.updateViewport(offset: scrollView.contentOffset, zoomScale: scrollView.zoomScale)
    }

    private func clearGraph() {
        content.subviews.forEach { $0.removeFromSuperview() }
        edgeLayers.forEach { $0.removeFromSuperlayer() }
        edgeLayers.removeAll()
        edgeLabels.removeAll()
        nodeViews.removeAll()
        graphNodeBounds = .null
        scrollView.contentInset = .zero
    }

    private func rebuildGraph() {
        clearGraph()
        guard let graph else { return }

        scrollView.zoomScale = 1
        scrollView.contentOffset = .zero
        content.backgroundColor = .clear

        let layout = layoutGraph(graph)
        graphNodeBounds = layout.nodeBounds
        content.frame = CGRect(origin: .zero, size: layout.contentSize)
        scrollView.contentSize = layout.contentSize

        for (id, frame) in layout.frames {
            guard let media = graph.nodes[id] else { continue }
            let node = RelationGraphNodeView(frame: frame)
            node.configure(media: media, isCurrent: id == currentID, accentColor: accentColor)
            node.addTarget(self, action: #selector(nodeTapped(_:)), for: .touchUpInside)
            content.addSubview(node)
            nodeViews[id] = node
        }

        drawEdges(graph)
        fitGraph(animated: false)
        updateBackgroundViewport()
    }

    private func layoutGraph(_ graph: AnimeRelationGraph) -> LayoutResult {
        guard !graph.nodes.isEmpty else {
            let size = CGSize(width: max(scrollView.bounds.width, 1), height: max(scrollView.bounds.height, 1))
            return LayoutResult(frames: [:], contentSize: size, nodeBounds: .null)
        }

        let ranks = graphRanks(for: graph)
        var grouped = Dictionary(grouping: graph.nodes.keys) { ranks[$0] ?? 0 }
        optimizeRankOrdering(&grouped, graph: graph, ranks: ranks)
        let yPositions = assignYPositions(grouped: grouped, graph: graph, ranks: ranks)

        let sortedRanks = grouped.keys.sorted()
        let firstRank = sortedRanks.first ?? 0
        var frames: [Int: CGRect] = [:]
        var nodeBounds = CGRect.null

        for rank in sortedRanks {
            for id in grouped[rank] ?? [] {
                guard let media = graph.nodes[id] else { continue }
                let height = RelationGraphNodeView.preferredHeight(for: media)
                let x = CGFloat(rank - firstRank) * (nodeWidth + rankSeparation) + canvasPadding
                let y = (yPositions[id] ?? 0) + canvasPadding
                let frame = CGRect(x: x, y: y, width: nodeWidth, height: height).integral
                frames[id] = frame
                nodeBounds = nodeBounds.union(frame)
            }
        }

        let bounds = nodeBounds.insetBy(dx: -canvasPadding, dy: -canvasPadding)
        let contentSize = CGSize(width: max(bounds.maxX, 1), height: max(bounds.maxY, 1))
        return LayoutResult(frames: frames, contentSize: contentSize, nodeBounds: nodeBounds)
    }

    private func graphRanks(for graph: AnimeRelationGraph) -> [Int: Int] {
        let ids = Array(graph.nodes.keys)
        guard !ids.isEmpty else { return [:] }

        var incomingCount = Dictionary(uniqueKeysWithValues: ids.map { ($0, 0) })
        var outgoing: [Int: [Int]] = [:]
        var incoming: [Int: [Int]] = [:]

        for edge in graph.edges.values {
            guard graph.nodes[edge.sourceID] != nil, graph.nodes[edge.targetID] != nil else { continue }
            outgoing[edge.sourceID, default: []].append(edge.targetID)
            incoming[edge.targetID, default: []].append(edge.sourceID)
            incomingCount[edge.targetID, default: 0] += 1
        }

        var ranks = Dictionary(uniqueKeysWithValues: ids.map { ($0, 0) })
        var queue = ids.filter { incomingCount[$0, default: 0] == 0 }.sorted(by: relationSort(graph: graph))
        if queue.isEmpty, let currentID, graph.nodes[currentID] != nil { queue = [currentID] }

        var processed = Set<Int>()
        while let id = queue.first {
            queue.removeFirst()
            guard processed.insert(id).inserted else { continue }
            for target in outgoing[id, default: []].sorted(by: relationSort(graph: graph)) {
                ranks[target] = max(ranks[target, default: 0], ranks[id, default: 0] + 1)
                incomingCount[target, default: 0] -= 1
                if incomingCount[target, default: 0] <= 0 {
                    queue.append(target)
                    queue.sort(by: relationSort(graph: graph))
                }
            }
        }

        for id in ids where !processed.contains(id) {
            let parentRank = incoming[id, default: []].compactMap { ranks[$0] }.max()
            ranks[id] = (parentRank ?? (ranks.values.max() ?? 0)) + (parentRank == nil ? 0 : 1)
        }
        return compactRanks(ranks)
    }

    private func compactRanks(_ ranks: [Int: Int]) -> [Int: Int] {
        let sorted = Array(Set(ranks.values)).sorted()
        let map = Dictionary(uniqueKeysWithValues: sorted.enumerated().map { ($0.element, $0.offset) })
        return ranks.mapValues { map[$0] ?? 0 }
    }

    private func optimizeRankOrdering(_ grouped: inout [Int: [Int]], graph: AnimeRelationGraph, ranks: [Int: Int]) {
        for rank in grouped.keys {
            grouped[rank] = (grouped[rank] ?? []).sorted(by: relationSort(graph: graph))
        }

        let sortedRanks = grouped.keys.sorted()
        guard sortedRanks.count > 1 else { return }

        func neighborAverage(id: Int, targetRank: Int, positions: [Int: CGFloat]) -> CGFloat? {
            let values = graph.edges.values.compactMap { edge -> CGFloat? in
                if edge.targetID == id, ranks[edge.sourceID] == targetRank { return positions[edge.sourceID] }
                if edge.sourceID == id, ranks[edge.targetID] == targetRank { return positions[edge.targetID] }
                return nil
            }
            guard !values.isEmpty else { return nil }
            return values.reduce(0, +) / CGFloat(values.count)
        }

        for _ in 0..<8 {
            var positions = rankPositions(grouped)
            for rank in sortedRanks.dropFirst() {
                grouped[rank] = (grouped[rank] ?? []).sorted { lhs, rhs in
                    let left = neighborAverage(id: lhs, targetRank: rank - 1, positions: positions)
                    let right = neighborAverage(id: rhs, targetRank: rank - 1, positions: positions)
                    if let left, let right, left != right { return left < right }
                    if left != nil { return true }
                    if right != nil { return false }
                    return relationSort(graph: graph)(lhs, rhs)
                }
            }

            positions = rankPositions(grouped)
            for rank in sortedRanks.dropLast().reversed() {
                grouped[rank] = (grouped[rank] ?? []).sorted { lhs, rhs in
                    let left = neighborAverage(id: lhs, targetRank: rank + 1, positions: positions)
                    let right = neighborAverage(id: rhs, targetRank: rank + 1, positions: positions)
                    if let left, let right, left != right { return left < right }
                    if left != nil { return true }
                    if right != nil { return false }
                    return relationSort(graph: graph)(lhs, rhs)
                }
            }
        }
    }

    private func assignYPositions(grouped: [Int: [Int]], graph: AnimeRelationGraph, ranks: [Int: Int]) -> [Int: CGFloat] {
        let sortedRanks = grouped.keys.sorted()
        var positions = initialYPositions(grouped: grouped, graph: graph)
        guard sortedRanks.count > 1 else { return normalizedYPositions(positions, graph: graph) }

        for _ in 0..<6 {
            for rank in sortedRanks.dropFirst() {
                alignRank(rank, toward: rank - 1, grouped: grouped, graph: graph, ranks: ranks, positions: &positions)
            }
            for rank in sortedRanks.dropLast().reversed() {
                alignRank(rank, toward: rank + 1, grouped: grouped, graph: graph, ranks: ranks, positions: &positions)
            }
        }
        return normalizedYPositions(positions, graph: graph)
    }

    private func initialYPositions(grouped: [Int: [Int]], graph: AnimeRelationGraph) -> [Int: CGFloat] {
        var positions: [Int: CGFloat] = [:]
        for rank in grouped.keys {
            let ids = grouped[rank] ?? []
            let heights = ids.compactMap { graph.nodes[$0].map(RelationGraphNodeView.preferredHeight) }
            let totalHeight = heights.reduce(CGFloat(0), +) + CGFloat(max(heights.count - 1, 0)) * nodeSeparation
            var y = -totalHeight / 2
            for id in ids {
                guard let media = graph.nodes[id] else { continue }
                positions[id] = y
                y += RelationGraphNodeView.preferredHeight(for: media) + nodeSeparation
            }
        }
        return positions
    }

    private func alignRank(_ rank: Int,
                           toward targetRank: Int,
                           grouped: [Int: [Int]],
                           graph: AnimeRelationGraph,
                           ranks: [Int: Int],
                           positions: inout [Int: CGFloat]) {
        guard let ids = grouped[rank], !ids.isEmpty else { return }
        var desired: [Int: CGFloat] = [:]
        for id in ids {
            let neighbors = graph.edges.values.compactMap { edge -> Int? in
                if edge.targetID == id, ranks[edge.sourceID] == targetRank { return edge.sourceID }
                if edge.sourceID == id, ranks[edge.targetID] == targetRank { return edge.targetID }
                return nil
            }
            guard !neighbors.isEmpty else { continue }
            let centers = neighbors.compactMap { neighbor -> CGFloat? in
                guard let y = positions[neighbor], let media = graph.nodes[neighbor] else { return nil }
                return y + RelationGraphNodeView.preferredHeight(for: media) / 2
            }
            guard !centers.isEmpty, let media = graph.nodes[id] else { continue }
            desired[id] = centers.reduce(0, +) / CGFloat(centers.count) - RelationGraphNodeView.preferredHeight(for: media) / 2
        }

        for id in ids where desired[id] != nil { positions[id] = desired[id] }
        resolveOverlaps(ids: ids, graph: graph, positions: &positions, desired: desired)
    }

    private func resolveOverlaps(ids: [Int], graph: AnimeRelationGraph, positions: inout [Int: CGFloat], desired: [Int: CGFloat]) {
        guard !ids.isEmpty else { return }
        var cursor = -CGFloat.greatestFiniteMagnitude
        for id in ids {
            guard let media = graph.nodes[id] else { continue }
            let y = max(positions[id] ?? 0, cursor)
            positions[id] = y
            cursor = y + RelationGraphNodeView.preferredHeight(for: media) + nodeSeparation
        }

        var reverseCursor = CGFloat.greatestFiniteMagnitude
        for id in ids.reversed() {
            guard let media = graph.nodes[id] else { continue }
            let height = RelationGraphNodeView.preferredHeight(for: media)
            let y = min(positions[id] ?? 0, reverseCursor - height)
            positions[id] = y
            reverseCursor = y - nodeSeparation
        }

        let desiredValues = desired.values
        guard !desiredValues.isEmpty,
              let first = ids.first,
              let last = ids.last,
              let firstY = positions[first],
              let lastY = positions[last],
              let lastMedia = graph.nodes[last] else { return }
        let blockCenter = (firstY + lastY + RelationGraphNodeView.preferredHeight(for: lastMedia)) / 2
        let desiredCenter = desiredValues.reduce(0, +) / CGFloat(desiredValues.count)
        let shift = desiredCenter - blockCenter
        for id in ids { positions[id, default: 0] += shift }
    }

    private func normalizedYPositions(_ positions: [Int: CGFloat], graph: AnimeRelationGraph) -> [Int: CGFloat] {
        let minY = positions.values.min() ?? 0
        return positions.mapValues { $0 - minY }
    }

    private func rankPositions(_ grouped: [Int: [Int]]) -> [Int: CGFloat] {
        var positions: [Int: CGFloat] = [:]
        for ids in grouped.values {
            for (index, id) in ids.enumerated() { positions[id] = CGFloat(index) }
        }
        return positions
    }

    private func relationSort(graph: AnimeRelationGraph) -> (Int, Int) -> Bool {
        { lhs, rhs in
            let leftTitle = graph.nodes[lhs].map { AniListUtil.title(for: $0) } ?? ""
            let rightTitle = graph.nodes[rhs].map { AniListUtil.title(for: $0) } ?? ""
            if leftTitle != rightTitle { return leftTitle < rightTitle }
            return lhs < rhs
        }
    }

    private func drawEdges(_ graph: AnimeRelationGraph) {
        for edge in graph.edges.values.sorted(by: { $0.id < $1.id }) {
            guard let source = nodeViews[edge.sourceID],
                  let target = nodeViews[edge.targetID] else { continue }
            let sourceIsLeft = source.frame.midX <= target.frame.midX
            let start = CGPoint(x: sourceIsLeft ? source.frame.maxX : source.frame.minX,
                                y: source.frame.midY)
            let end = CGPoint(x: sourceIsLeft ? target.frame.minX : target.frame.maxX,
                              y: target.frame.midY)
            let distance = max(abs(end.x - start.x), edgeSeparation)
            let controlOffset = distance * 0.5

            let path = UIBezierPath()
            path.move(to: start)
            path.addCurve(to: end,
                          controlPoint1: CGPoint(x: start.x + (sourceIsLeft ? controlOffset : -controlOffset), y: start.y),
                          controlPoint2: CGPoint(x: end.x - (sourceIsLeft ? controlOffset : -controlOffset), y: end.y))

            let isCurrentEdge = [edge.sourceID, edge.targetID].contains(currentID ?? -1)
            let layer = CAShapeLayer()
            layer.path = path.cgPath
            layer.strokeColor = (isCurrentEdge ? accentColor : UIColor(white: 0.67, alpha: 0.72)).cgColor
            layer.fillColor = UIColor.clear.cgColor
            layer.lineWidth = 1
            layer.lineCap = .round
            layer.lineJoin = .round
            layer.lineDashPattern = [5, 5]
            content.layer.insertSublayer(layer, at: 0)
            edgeLayers.append(layer)

            let animation = CABasicAnimation(keyPath: "lineDashPhase")
            animation.fromValue = 10
            animation.toValue = 0
            animation.duration = 0.9
            animation.repeatCount = .infinity
            layer.add(animation, forKey: "relationEdgeFlow")

            addEdgeLabel(edge.relationType.replacingOccurrences(of: "_", with: " "),
                         at: CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2),
                         highlighted: isCurrentEdge)
        }
    }

    private func addEdgeLabel(_ text: String, at center: CGPoint, highlighted: Bool) {
        let label = UILabel()
        label.text = text
        label.font = .nunito(ofSize: 10, weight: .semibold)
        label.textColor = highlighted ? accentColor : UIColor(white: 0.74, alpha: 0.96)
        label.backgroundColor = UIColor.black.withAlphaComponent(0.88)
        label.textAlignment = .center
        label.layer.cornerRadius = 2
        label.clipsToBounds = true
        label.sizeToFit()
        let width = max(32, label.bounds.width + 8)
        label.frame = CGRect(x: center.x - width / 2, y: center.y - 9, width: width, height: 18)
        content.addSubview(label)
        edgeLabels.append(label)
    }

    private func fitGraph(animated: Bool) {
        let targetBounds = graphNodeBounds.isNull ? CGRect(origin: .zero, size: content.bounds.size) : graphNodeBounds.insetBy(dx: -canvasPadding, dy: -canvasPadding)
        guard targetBounds.width > 0, targetBounds.height > 0 else { return }
        let viewport = scrollView.bounds.insetBy(dx: 20, dy: 20).size
        guard viewport.width > 0, viewport.height > 0 else { return }
        let scale = min(scrollView.maximumZoomScale,
                        max(scrollView.minimumZoomScale,
                            min(viewport.width / targetBounds.width,
                                viewport.height / targetBounds.height)))
        scrollView.setZoomScale(scale, animated: animated)
        centerZoomedContent()
        centerGraphBounds(targetBounds, animated: animated)
        didInitialFit = true
    }

    private func centerGraphBounds(_ bounds: CGRect, animated: Bool) {
        let scale = scrollView.zoomScale
        let visibleSize = scrollView.bounds.size
        let target = CGPoint(x: bounds.midX * scale - visibleSize.width / 2,
                             y: bounds.midY * scale - visibleSize.height / 2)
        scrollView.setContentOffset(clampedContentOffset(target), animated: animated)
    }

    private func clampedContentOffset(_ offset: CGPoint) -> CGPoint {
        let inset = scrollView.contentInset
        let minX = -inset.left
        let minY = -inset.top
        let maxX = max(minX, scrollView.contentSize.width + inset.right - scrollView.bounds.width)
        let maxY = max(minY, scrollView.contentSize.height + inset.bottom - scrollView.bounds.height)
        return CGPoint(x: min(max(offset.x, minX), maxX),
                       y: min(max(offset.y, minY), maxY))
    }

    private func centerZoomedContent() {
        let insetX = max((scrollView.bounds.width - scrollView.contentSize.width) / 2, 0)
        let insetY = max((scrollView.bounds.height - scrollView.contentSize.height) / 2, 0)
        scrollView.contentInset = UIEdgeInsets(top: insetY, left: insetX, bottom: insetY, right: insetX)
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
        updateExpandIcon()
        onToggleExpanded?(isExpanded)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { [weak self] in
            self?.fitGraph(animated: true)
        }
    }

    private func updateExpandIcon() {
        let name = isExpanded ? "minimize-2" : "maximize-2"
        if let image = UIImage.hayaseIcon(name, withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)) {
            expandButton.setImage(image, for: .normal)
            expandButton.setTitle(nil, for: .normal)
        } else {
            expandButton.setImage(nil, for: .normal)
            expandButton.setTitle(isExpanded ? "▣" : "⛶", for: .normal)
        }
    }

    @objc private func refreshTapped() {
        onRefreshGraph?()
    }

    @objc private func nodeTapped(_ sender: RelationGraphNodeView) {
        selectMedia(sender.mediaID)
    }

    @objc private func graphTapped(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended else { return }
        let point = recognizer.location(in: content)
        let hitSlop: CGFloat = 8
        let orderedNodes = nodeViews.values.sorted { $0.frame.minX < $1.frame.minX }
        guard let node = orderedNodes.first(where: { $0.frame.insetBy(dx: -hitSlop, dy: -hitSlop).contains(point) }) else {
            return
        }
        selectMedia(node.mediaID)
    }

    private func selectMedia(_ id: Int) {
        let now = CACurrentMediaTime()
        if let lastNodeSelection,
           lastNodeSelection.id == id,
           now - lastNodeSelection.time < 0.25 {
            return
        }
        lastNodeSelection = (id, now)
        onSelectMedia?(id)
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
            bar.backgroundColor = UIColor.HayaseTheme.foreground.withAlphaComponent(alpha)
            bar.layer.cornerRadius = 2
            bar.translatesAutoresizingMaskIntoConstraints = false
            let lbl = UILabel()
            lbl.text = "\(point.score)"
            lbl.font = .nunito(ofSize: 7)
            lbl.textColor = UIColor.HayaseTheme.mutedForeground.withAlphaComponent(0.7)
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
        l.textColor = UIColor.HayaseTheme.foreground
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
            nameLabel.textColor = UIColor.HayaseTheme.foreground
            nameLabel.widthAnchor.constraint(equalToConstant: 80).isActive = true
            let progress = UIProgressView(progressViewStyle: .default)
            progress.setProgress(fraction, animated: false)
            progress.progressTintColor = Self.statusColor(for: status.status)
            progress.trackTintColor = UIColor.HayaseTheme.muted
            let countLabel = UILabel()
            countLabel.text = "\(status.amount)"
            countLabel.font = .nunito(ofSize: 11)
            countLabel.textColor = UIColor.HayaseTheme.mutedForeground
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
                    self.reloadSectionsWithoutAnimation([.relations])
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
            cell.applyWindowInset(for: tableView.frame.width)
            cell.configure(graph: graph,
                           currentID: routeAnimeID,
                           accentColor: currentAnimeAccent,
                           expanded: relationGraphExpanded)
            cell.onSelectMedia = { [weak self] id in
                Router.shared.navigate(.anime(id: id), hostTabIndex: self?.hayaseTabIndex)
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
                    self.reloadSectionsWithoutAnimation([.relations])
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
