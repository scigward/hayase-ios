//
//  Relations.swift
//  Hayase
//
//  The relations graph of an anime. It is the Relations.svelte of the interface: a flow (Xyflow) with the
//  nodes of TextNode.svelte, laid out with dagre, with a background and the controls of the interface.
//

import UIKit
import Xyflow
import XYSystem

// MARK: - Icons

private extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xff) / 255,
                  green: CGFloat((hex >> 8) & 0xff) / 255,
                  blue: CGFloat(hex & 0xff) / 255,
                  alpha: alpha)
    }
}

/// The icons of the buttons of the controls. They are the ones of lucide, which the interface uses, drawn the way
/// the stylesheet of the controls draws them: `fill: currentColor` fills their paths as well.
private extension FlowIcon {
    static let maximize2 = FlowIcon(
        viewBox: CGSize(width: 24, height: 24),
        paths: ["M15 3h6v6", "m21 3-7 7", "m3 21 7-7", "M9 21H3v-6"],
        fills: true,
        strokeWidth: 2)

    static let minimize2 = FlowIcon(
        viewBox: CGSize(width: 24, height: 24),
        paths: ["m14 10 7-7", "M20 10h-6V4", "m3 21 7-7", "M4 14h6v6"],
        fills: true,
        strokeWidth: 2)

    /// The refresh icon of the interface sets `fill: none` on its paths itself.
    static let refresh = FlowIcon(
        viewBox: CGSize(width: 24, height: 24),
        paths: [
            "M3 12a9 9 0 0 1 9-9 9.75 9.75 0 0 1 6.74 2.74L21 8",
            "M21 3v5h-5",
            "M21 12a9 9 0 0 1-9 9 9.75 9.75 0 0 1-6.74-2.74L3 16",
            "M8 16H3v5"
        ],
        fills: false,
        strokeWidth: 2)
}

// MARK: - Node

/// `TextNode.svelte`: a box of 150 points with the title of the anime, its format and its episodes or its status.
/// The box of the current anime has the color of the page.
private final class RelationTextNodeView: UIView, FlowNodeComponent {
    private static let width: CGFloat = 150
    private static let titleLineHeight: CGFloat = 16
    private static let metaHeight: CGFloat = 20.5
    private static let background = UIColor(hex: 0x111111)
    private static let titleBackground = UIColor(hex: 0x1e1e1e)
    private static let foreground = UIColor(white: 0.92, alpha: 1)

    /// The `<a>`: the border, the corners, the background, and everything that is clipped by them.
    private let card = UIView()
    private let titleBackground = UIView()
    private let titleLabel = UILabel()
    private let formatLabel = UILabel()
    private let statusLabel = UILabel()

    /// The `div.relative` of the node, inside of the border: the handles sit on its sides.
    private let handleBox = UIView()
    private let targetHandle = HandleView(type: .target, position: .left)
    private let sourceHandle = HandleView(type: .source, position: .right)

    private var hasMedia = false

    init() {
        super.init(frame: .zero)

        clipsToBounds = false

        card.backgroundColor = Self.background
        card.layer.cornerRadius = 2
        card.layer.borderWidth = 1
        card.layer.borderColor = Self.background.cgColor
        card.clipsToBounds = true
        addSubview(card)

        titleBackground.backgroundColor = Self.titleBackground
        card.addSubview(titleBackground)

        titleLabel.numberOfLines = 0
        titleLabel.lineBreakMode = .byWordWrapping
        titleLabel.textAlignment = .center
        card.addSubview(titleLabel)

        formatLabel.font = .nunito(ofSize: 8.5, weight: .semibold)
        formatLabel.textAlignment = .left
        card.addSubview(formatLabel)

        statusLabel.font = .nunito(ofSize: 8.5, weight: .semibold)
        statusLabel.textAlignment = .right
        card.addSubview(statusLabel)

        // `.node { --xy-handle-background-color: none; --xy-handle-border-color: none }`
        let handleStyle = "--xy-handle-background-color: none; --xy-handle-border-color: none"
        targetHandle.style = handleStyle
        sourceHandle.style = handleStyle

        handleBox.isUserInteractionEnabled = false
        addSubview(handleBox)
        handleBox.addSubview(targetHandle)
        handleBox.addSubview(sourceHandle)
    }

    required init?(coder: NSCoder) { fatalError() }

    func update(props: NodeProps) {
        targetHandle.position = props.targetPosition ?? .left
        sourceHandle.position = props.sourcePosition ?? .right

        let media = props.data["media"] as? AnimeItem
        let isCurrent = props.data["current"] as? Bool ?? false
        let accent = props.data["accent"] as? UIColor ?? Self.foreground

        hasMedia = media != nil
        titleBackground.isHidden = media == nil
        titleLabel.isHidden = media == nil
        formatLabel.isHidden = media == nil
        statusLabel.isHidden = media == nil

        // `border-custom text-custom` for the current anime, `border-[#111] text-foreground` for the others
        let foreground = isCurrent ? accent : Self.foreground
        card.layer.borderColor = (isCurrent ? accent : Self.background).cgColor

        if let media {
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            paragraph.lineBreakMode = .byWordWrapping
            paragraph.minimumLineHeight = Self.titleLineHeight
            paragraph.maximumLineHeight = Self.titleLineHeight

            titleLabel.attributedText = NSAttributedString(
                string: media.titleUserPreferred ?? "TBA",
                attributes: [
                    .font: UIFont.nunito(ofSize: 12, weight: .bold),
                    .foregroundColor: foreground,
                    .paragraphStyle: paragraph
                ])

            formatLabel.text = AniListUtil.format(media.format)
            formatLabel.textColor = foreground
            statusLabel.text = media.episodes.flatMap { $0 != 0 ? "\($0) Episodes" : nil } ?? AniListUtil.status(media.status)
            statusLabel.textColor = foreground
        }

        setNeedsLayout()
    }

    // MARK: Size

    /// The title block: `p-2.5 pb-2` around the lines of the title.
    private func titleBlockHeight(forWidth width: CGFloat) -> CGFloat {
        let text = titleLabel.sizeThatFits(CGSize(width: max(0, width - 20), height: .greatestFiniteMagnitude))
        return 10 + text.height + 8
    }

    func preferredSize(width: Double?, height: Double?) -> CGSize? {
        // one point of border on each side
        let inner = Self.width - 2
        let content = hasMedia ? titleBlockHeight(forWidth: inner) + Self.metaHeight : 0

        return CGSize(width: Self.width, height: 2 + content)
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        card.frame = bounds

        let inner = bounds.insetBy(dx: 1, dy: 1)
        handleBox.frame = inner

        guard hasMedia else { return }

        let titleBlock = titleBlockHeight(forWidth: inner.width)
        titleBackground.frame = CGRect(x: 1, y: 1, width: inner.width, height: titleBlock)

        let textHeight = titleBlock - 18
        titleLabel.frame = CGRect(x: 1 + 10, y: 1 + 10, width: max(0, inner.width - 20), height: textHeight)

        // `flex justify-between px-2 py-1.5`
        let metaTop = 1 + titleBlock
        let format = formatLabel.sizeThatFits(CGSize(width: inner.width, height: .greatestFiniteMagnitude))
        let status = statusLabel.sizeThatFits(CGSize(width: inner.width, height: .greatestFiniteMagnitude))

        formatLabel.frame = CGRect(
            x: 1 + 8,
            y: metaTop + (Self.metaHeight - format.height) / 2,
            width: min(format.width, inner.width - 16),
            height: format.height)
        statusLabel.frame = CGRect(
            x: bounds.width - 1 - 8 - status.width,
            y: metaTop + (Self.metaHeight - status.height) / 2,
            width: status.width,
            height: status.height)
    }
}

// MARK: - RelationGraphCell

final class RelationGraphCell: UITableViewCell {
    static let reuseID = "RelationGraphCell"

    /// `border border-border rounded overflow-clip`
    private let container = UIView()
    private let flow = SwiftFlow(nodes: Writable<[Node]>([]), edges: Writable<[Edge]>([]))
    private let controls = ControlsView(position: .bottomLeft, orientation: .horizontal)
    private let expandButton = ControlButton()
    private let refreshButton = ControlButton()
    private let refreshIcon = FlowIconView(icon: .refresh)

    private var graphLeadingConstraint: NSLayoutConstraint?
    private var graphTrailingConstraint: NSLayoutConstraint?

    private var graph: AnimeRelationGraph?
    private var currentID: Int?
    private var accentColor: UIColor = .white
    private var isExpanded = false
    private var graphSignature: String?
    private var needsMount = true
    private var fitLoopId: Int?
    private var fitTimeoutId: Int?
    private var lastNodeSelection: (id: Int, time: CFTimeInterval)?

    var onSelectMedia: ((Int) -> Void)?
    var onRefreshGraph: (() -> Void)?
    var onToggleExpanded: ((Bool) -> Void)?
    /// Asked for once the graph is as big as it gets: the page shows it in the middle of the screen.
    var onScrollIntoView: (() -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setup()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        selectionStyle = .none

        container.translatesAutoresizingMaskIntoConstraints = false
        container.layer.borderColor = UIColor(white: 0.19, alpha: 1).cgColor
        container.layer.borderWidth = 1
        container.layer.cornerRadius = 4
        container.clipsToBounds = true
        contentView.addSubview(container)

        flow.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(flow)

        configureFlow()
        configureControls()

        let leading = container.leadingAnchor.constraint(equalTo: contentView.leadingAnchor)
        let trailing = container.trailingAnchor.constraint(equalTo: contentView.trailingAnchor)
        graphLeadingConstraint = leading
        graphTrailingConstraint = trailing

        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            leading,
            trailing,
            container.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            flow.topAnchor.constraint(equalTo: container.topAnchor),
            flow.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            flow.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            flow.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
    }

    /// The props of `<SvelteFlow>` in Relations.svelte.
    private func configureFlow() {
        flow.colorMode = .dark
        flow.proOptions = ProOptions(hideAttribution: true)
        flow.nodesConnectable = false
        flow.nodesDraggable = false
        flow.panOnScroll = false
        flow.zoomOnScroll = false
        flow.preventScrolling = false
        flow.zoomActivationKey = ["Control", "Meta", "Ctrl", "Shift", "ShiftLeft"]
        flow.onlyRenderVisibleElements = true
        flow.minZoom = 0
        flow.maxZoom = 1.2
        flow.nodeTypes = ["customText": { RelationTextNodeView() }]
        flow.elementsSelectable = false
        flow.fontProvider = { size, weight in .nunito(ofSize: size, weight: weight) }

        // `<Background bgColor='black' />`
        flow.add(BackgroundView(bgColor: "black"))

        flow.onNodeClick = { [weak self] event in
            guard let id = Int(event.node.id) else { return }
            self?.selectMedia(id)
        }
    }

    /// `<Controls showLock={false} orientation='horizontal'>` with the two buttons of the interface.
    private func configureControls() {
        controls.showLock = false

        expandButton.setContent(FlowIconView(icon: .maximize2))
        expandButton.accessibilityLabel = "Expand"
        expandButton.onClick = { [weak self] in self?.expand() }

        refreshButton.setContent(refreshIcon)
        refreshButton.accessibilityLabel = "Refresh"
        refreshButton.onClick = { [weak self] in self?.onRefreshGraph?() }

        // the icon turns while the pointer is over the button, or the button is pressed
        refreshButton.onHover = { [weak self] hovering in self?.setRefreshIconTurned(hovering) }
        refreshButton.addTarget(self, action: #selector(refreshPressed), for: .touchDown)
        refreshButton.addTarget(self, action: #selector(refreshReleased), for: [.touchUpInside, .touchUpOutside, .touchCancel])

        controls.addButton(expandButton)
        controls.addButton(refreshButton)
        flow.add(controls)
    }

    @objc private func refreshPressed() {
        setRefreshIconTurned(true)
    }

    @objc private func refreshReleased() {
        setRefreshIconTurned(false)
    }

    /// `.target-animated-icon { transition: transform 0.4s cubic-bezier(0.175, 0.885, 0.32, 1.275); rotate(50deg) }`
    private func setRefreshIconTurned(_ turned: Bool) {
        let animator = UIViewPropertyAnimator(
            duration: 0.4,
            controlPoint1: CGPoint(x: 0.175, y: 0.885),
            controlPoint2: CGPoint(x: 0.32, y: 1.275)
        ) { [weak self] in
            self?.refreshIcon.transform = turned ? CGAffineTransform(rotationAngle: 50 * .pi / 180) : .identity
        }
        animator.startAnimation()
    }

    /// `contentWidth` is the width of the page, `viewportWidth` the one of the window, which is what the
    /// padding of the page (`2xs:px-3 xl:px-14`) is asked.
    func applyWindowInset(for contentWidth: CGFloat, viewportWidth: CGFloat) {
        let pageMaxWidth: CGFloat = 1600
        let outerInset = max((contentWidth - pageMaxWidth) / 2, 0)
        let innerInset = AnimeDetailViewController.interfacePageSideInset(for: viewportWidth)
        let inset = outerInset + innerInset
        graphLeadingConstraint?.constant = inset
        graphTrailingConstraint?.constant = -inset
    }

    // MARK: Configuring

    func configure(graph: AnimeRelationGraph, currentID: Int?, accentColor: UIColor, expanded: Bool) {
        let signature = Self.signature(of: graph, currentID: currentID)
        let changed = signature != graphSignature || accentColor != self.accentColor

        self.graph = graph
        self.currentID = currentID
        self.accentColor = accentColor
        self.graphSignature = signature

        // the color of the page: `--custom`
        flow.styleVariables = ["--custom": FlowColor(accentColor).cssHex]

        setExpanded(expanded)

        if changed {
            applyGraph()
        }

        if needsMount && window != nil {
            mount()
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()

        if window != nil && needsMount && graph != nil {
            mount()
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()

        if let fitLoopId { cancelAnimationFrame(fitLoopId) }
        clearTimeout(fitTimeoutId)
        fitLoopId = nil
        fitTimeoutId = nil

        graph = nil
        currentID = nil
        graphSignature = nil
        needsMount = true
        lastNodeSelection = nil

        flow.nodes.set([])
        flow.edges.set([])
    }

    private static func signature(of graph: AnimeRelationGraph, currentID: Int?) -> String {
        let nodes = graph.orderedNodes.map { String($0.id) }.joined(separator: ",")
        let edges = graph.orderedEdges.map { "\($0.id):\($0.sourceID):\($0.targetID):\($0.relationType)" }.joined(separator: ",")
        return "\(currentID ?? -1)|\(nodes)|\(edges)"
    }

    private func setExpanded(_ expanded: Bool) {
        isExpanded = expanded

        // `zoomOnScroll={expanded}` and `preventScrolling={expanded}`
        flow.zoomOnScroll = expanded
        flow.preventScrolling = expanded

        expandButton.setContent(FlowIconView(icon: expanded ? .minimize2 : .maximize2))
    }

    // MARK: The graph

    /// `$: $nodes = [...$nodesStore.nodes.values()]`, `$: $edges = [...]`, `$: media && onLayout()` and
    /// `$: $nodesStore && fitAndLayout()`.
    private func applyGraph() {
        guard let graph else { return }

        flow.nodes.set(graph.orderedNodes.map { item in
            Node(id: String(item.id), position: XYPosition(x: 0, y: 0), data: ["id": item.id, "media": item], type: "customText")
        })

        flow.edges.set(graph.orderedEdges.map { edge in
            Edge(
                id: edge.id,
                source: String(edge.sourceID),
                target: String(edge.targetID),
                animated: true,
                data: ["ids": [edge.sourceID, edge.targetID]],
                label: edge.relationType.replacingOccurrences(of: "_", with: " "))
        })

        onLayout()
        fitAndLayout()
    }

    /// `onMount(() => { fitAndLayout(); setTimeout(fitAndLayout) })`
    private func mount() {
        needsMount = false

        fitAndLayout()
        _ = setTimeout(0) { [weak self] in
            self?.fitAndLayout()
        }
    }

    /// `getLayoutedElements`: the nodes are laid out with dagre, from left to right.
    private func layoutedElements(
        nodes: [Node],
        edges: [Edge]
    ) -> (nodes: [Node], edges: [Edge]) {
        let mediaID = currentID ?? -1

        let layoutNodes = nodes.map { node -> Dagre.Node in
            let titleLength = (node.data["media"] as? AnimeItem)?.titleUserPreferred.map { $0.utf16.count } ?? 1

            return Dagre.Node(
                id: node.id,
                width: node.measured?.width ?? 180,
                height: node.measured?.height ?? 48.6 + (Double(titleLength) / 20).rounded(.up) * 19.2)
        }

        let positions = Dagre.layout(
            nodes: layoutNodes,
            edges: edges.map { Dagre.Edge(source: $0.source, target: $0.target) },
            options: Dagre.Options(rankdir: .leftToRight, nodesep: 50, edgesep: 50, ranksep: 120, ranker: .tightTree))

        let layoutedNodes = nodes.map { node -> Node in
            let position = positions[node.id] ?? Dagre.Position(x: 0, y: 0, rank: 0, order: 0)

            // the position of dagre is the center of the node, the one of the flow is its top left corner
            let x = position.x - (node.measured?.width ?? 0) / 2
            let y = position.y - (node.measured?.height ?? 0) / 2

            var data = node.data
            data["current"] = (node.data["id"] as? Int) == mediaID
            data["accent"] = accentColor

            let copy = node.copy()
            copy.data = data
            copy.type = "customText"
            copy.position = XYPosition(x: x, y: y)
            copy.sourcePosition = .right
            copy.targetPosition = .left
            return copy
        }

        let layoutedEdges = edges.map { edge -> Edge in
            let touchesMedia = (edge.data?["ids"] as? [Int])?.contains(mediaID) ?? false

            let copy = edge.copy()
            copy.style = touchesMedia ? "--xy-edge-stroke: var(--custom)" : ""
            copy.labelStyle = touchesMedia ? "--xy-edge-label-color: var(--custom)" : ""
            return copy
        }

        return (layoutedNodes, layoutedEdges)
    }

    private func onLayout() {
        let result = layoutedElements(nodes: flow.nodes.get(), edges: flow.edges.get())

        flow.nodes.set(result.nodes)
        flow.edges.set(result.edges)
    }

    private func fitAndLayout() {
        onLayout()
        flow.instance.fitView()
    }

    // MARK: Expanding

    /// The graph is fitted on every frame while it changes its size, and once more when that is done.
    private func loopFitView() {
        if let fitLoopId { cancelAnimationFrame(fitLoopId) }

        flow.instance.fitView()
        fitLoopId = requestAnimationFrame { [weak self] in
            self?.loopFitView()
        }
    }

    private func expand() {
        setExpanded(!isExpanded)
        onToggleExpanded?(isExpanded)

        loopFitView()
        clearTimeout(fitTimeoutId)

        fitTimeoutId = setTimeout(150) { [weak self] in
            guard let self else { return }

            if let fitLoopId = self.fitLoopId { cancelAnimationFrame(fitLoopId) }
            self.fitLoopId = nil

            if self.isExpanded { self.onScrollIntoView?() }
            self.flow.instance.fitView()
        }
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

// MARK: - Relations fetching

extension AnimeDetailViewController {

    var hasRelationsContent: Bool {
        relationGraph != nil || animeItem != nil
    }

    func applyRelationGraph(_ graph: AnimeRelationGraph) {
        relationGraph = graph.nodes.isEmpty ? fallbackRelationGraph() : graph
    }

    func fallbackRelationGraph() -> AnimeRelationGraph? {
        guard let current = animeItem else { return nil }
        var graph = AnimeRelationGraph(nodes: [:], edges: [:])
        graph.setNode(current)
        for relation in current.relations {
            graph.setNode(relation.media)
            let sourceID = relation.sourceID ?? current.id
            let targetID = relation.media.id
            let relationType = relation.relationType
            let isPrequel = relationType == "PREQUEL"
            let lhs = min(sourceID, targetID)
            let rhs = max(sourceID, targetID)
            graph.setEdge("\(lhs)-\(rhs)", AnimeRelationGraphEdge(
                id: "e\(lhs)-\(rhs)",
                sourceID: isPrequel ? targetID : sourceID,
                targetID: isPrequel ? sourceID : targetID,
                relationType: isPrequel ? "SEQUEL" : relationType))
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
            cell.applyWindowInset(for: tableView.frame.width, viewportWidth: viewportWidth)
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
            cell.onScrollIntoView = { [weak self] in
                // `scrollIntoView({ behavior: 'smooth', block: 'center' })`
                self?.tableView.scrollToRow(at: indexPath, at: .middle, animated: true)
            }
            return cell
        }

        return UITableViewCell()
    }
}
