//
//  DagreLayout.swift
//  Hayase
//
//  The layout of the relations graph: a port of dagre 3.0.0 (https://github.com/dagrejs/dagre, MIT, Copyright
//  (c) 2012-2014 Chris Pettitt), which is what the interface lays the graph out with. It covers what that
//  graph needs, and does all of it as dagre does: graphs without clusters and without edge labels, laid out
//  with the `tight-tree` or the `longest-path` ranker. The nodes come back where dagre puts them.
//

import Foundation

// MARK: - Labels

enum DagreDummy {
    case root
    case edge
    case border
    case selfEdge
}

final class DagreGraphLabel {
    var ranksep: Double = 50
    var edgesep: Double = 20
    var nodesep: Double = 50
    var marginx: Double = 0
    var marginy: Double = 0
    var rankdir = "TB"
    var rankalign = "center"
    var align: String?
    var ranker: DagreRanker = .tightTree
    var nestingRoot: String?
    var nodeRankFactor = 1
    var dummyChains: [String] = []
    /// The root of a layer graph, which the nodes of the layer are children of.
    var root: String?
}

final class DagreNodeLabel {
    var width: Double = 0
    var height: Double = 0
    var rank: Int?
    var order: Int?
    var x: Double?
    var y: Double?
    var dummy: DagreDummy?
    /// What the dummy nodes of a long edge stand for.
    var edgeLabel: DagreEdgeLabel?
    var edgeObj: DagreEdge?
    var selfEdges: [(edge: DagreEdge, label: DagreEdgeLabel)] = []
    var selfEdge: (edge: DagreEdge, label: DagreEdgeLabel)?

    init(width: Double = 0, height: Double = 0) {
        self.width = width
        self.height = height
    }
}

final class DagreEdgeLabel {
    var minlen = 1
    var weight: Double = 1
    var reversed = false
    var forwardName: String?
    /// The size of the label of the edge, which is none, but the space for it: see `makeSpaceForEdgeLabels`.
    var width: Double = 0
    var height: Double = 0
    var labeloffset: Double = 10
    var labelpos = "r"

    init(minlen: Int = 1, weight: Double = 1) {
        self.minlen = minlen
        self.weight = weight
    }
}

enum DagreRanker {
    case tightTree
    case longestPath
}

typealias DagreLayoutGraph = DagreGraph<DagreGraphLabel, DagreNodeLabel, DagreEdgeLabel>

private func makeLayoutGraph(compound: Bool, multigraph: Bool, root: DagreLayoutGraph? = nil) -> DagreLayoutGraph {
    DagreLayoutGraph(
        directed: true,
        multigraph: multigraph,
        compound: compound,
        defaultNode: { id in
            // a layer graph has the labels of the graph it is made from
            if let root, root.hasNode(id) { return root.node(id) }
            return DagreNodeLabel()
        },
        defaultEdge: { _, _, _ in DagreEdgeLabel() })
}

// MARK: - Public

enum Dagre {
    enum RankDirection: String {
        case topToBottom = "TB"
        case bottomToTop = "BT"
        case leftToRight = "LR"
        case rightToLeft = "RL"
    }

    struct Options {
        var rankdir: RankDirection = .topToBottom
        var nodesep: Double = 50
        var edgesep: Double = 20
        var ranksep: Double = 50
        var ranker: DagreRanker = .tightTree

        init(
            rankdir: RankDirection = .topToBottom,
            nodesep: Double = 50,
            edgesep: Double = 20,
            ranksep: Double = 50,
            ranker: DagreRanker = .tightTree
        ) {
            self.rankdir = rankdir
            self.nodesep = nodesep
            self.edgesep = edgesep
            self.ranksep = ranksep
            self.ranker = ranker
        }
    }

    struct Node {
        var id: String
        var width: Double
        var height: Double
    }

    struct Edge {
        var source: String
        var target: String
    }

    /// Where dagre puts a node: its center, and its place in the layers.
    struct Position {
        var x: Double
        var y: Double
        var rank: Int
        var order: Int
    }

    /// Lays out a graph. The edges are added in the order they are given, which decides ties in the layout.
    static func layout(nodes: [Node], edges: [Edge], options: Options = Options()) -> [String: Position] {
        // the graph of the caller: its edges are added first, and its nodes then get their size
        let input = makeLayoutGraph(compound: false, multigraph: false)
        let label = DagreGraphLabel()
        label.rankdir = options.rankdir.rawValue
        label.nodesep = options.nodesep
        label.edgesep = options.edgesep
        label.ranksep = options.ranksep
        label.ranker = options.ranker
        input.setGraph(label)

        for edge in edges {
            input.setEdge(edge.source, edge.target)
        }

        for node in nodes {
            input.setNode(node.id, DagreNodeLabel(width: node.width, height: node.height))
        }

        let layoutGraph = buildLayoutGraph(input)
        runLayout(layoutGraph)

        var result: [String: Position] = [:]
        for v in input.nodes() {
            let layoutLabel = layoutGraph.node(v)
            result[v] = Position(
                x: layoutLabel.x ?? 0,
                y: layoutLabel.y ?? 0,
                rank: layoutLabel.rank ?? 0,
                order: layoutLabel.order ?? 0)
        }
        return result
    }
}

// MARK: - Layout

private func buildLayoutGraph(_ input: DagreLayoutGraph) -> DagreLayoutGraph {
    let g = makeLayoutGraph(compound: true, multigraph: true)

    let source = input.graph()
    let label = DagreGraphLabel()
    label.ranksep = source.ranksep
    label.edgesep = source.edgesep
    label.nodesep = source.nodesep
    label.marginx = source.marginx
    label.marginy = source.marginy
    label.rankdir = source.rankdir
    label.rankalign = source.rankalign
    label.align = source.align
    label.ranker = source.ranker
    g.setGraph(label)

    for v in input.nodes() {
        let node = input.node(v)
        g.setNode(v, DagreNodeLabel(width: node.width, height: node.height))
    }

    for e in input.edges() {
        // minlen and weight are 1 unless the edge says otherwise
        g.setEdge(e, DagreEdgeLabel())
    }

    return g
}

private func runLayout(_ g: DagreLayoutGraph) {
    makeSpaceForEdgeLabels(g)
    removeSelfEdges(g)
    dagreAcyclicRun(g)
    dagreNestingRun(g)
    dagreRank(dagreAsNonCompoundGraph(g))
    dagreRemoveEmptyRanks(g)
    dagreNestingCleanup(g)
    dagreNormalizeRanks(g)
    dagreNormalizeRun(g)
    dagreOrder(g)
    insertSelfEdges(g)
    dagreCoordinateSystemAdjust(g)
    dagrePosition(g)
    positionSelfEdges(g)
    dagreNormalizeUndo(g)
    dagreCoordinateSystemUndo(g)
    translateGraph(g)
}

/// To account for edge labels each rank is split in half by doubling minlen and halving ranksep. The label of an
/// edge is pushed away from it a little by `labeloffset`, which is what gives a self edge its size.
private func makeSpaceForEdgeLabels(_ g: DagreLayoutGraph) {
    let graph = g.graph()
    graph.ranksep /= 2

    for e in g.edges() {
        guard let edge = g.edge(e) else { continue }

        edge.minlen *= 2

        if edge.labelpos.lowercased() != "c" {
            if graph.rankdir == "TB" || graph.rankdir == "BT" {
                edge.width += edge.labeloffset
            } else {
                edge.height += edge.labeloffset
            }
        }
    }
}

private func removeSelfEdges(_ g: DagreLayoutGraph) {
    for e in g.edges() where e.v == e.w {
        let node = g.node(e.v)
        if let label = g.edge(e) {
            node.selfEdges.append((e, label))
        }
        g.removeEdge(e)
    }
}

private func insertSelfEdges(_ g: DagreLayoutGraph) {
    for layer in dagreBuildLayerMatrix(g) {
        var orderShift = 0

        for (i, v) in layer.enumerated() {
            let node = g.node(v)
            node.order = i + orderShift

            for selfEdge in node.selfEdges {
                orderShift += 1

                let dummy = DagreNodeLabel(width: selfEdge.label.width, height: selfEdge.label.height)
                dummy.rank = node.rank
                dummy.order = i + orderShift
                dummy.selfEdge = selfEdge
                dagreAddDummyNode(g, .selfEdge, dummy, "_se")
            }

            node.selfEdges = []
        }
    }
}

private func positionSelfEdges(_ g: DagreLayoutGraph) {
    for v in g.nodes() {
        let node = g.node(v)

        if node.dummy == .selfEdge, let selfEdge = node.selfEdge {
            g.setEdge(selfEdge.edge, selfEdge.label)
            g.removeNode(v)
        }
    }
}

/// Moves the graph so that its top left corner is at the origin.
private func translateGraph(_ g: DagreLayoutGraph) {
    var minX = Double.infinity
    var minY = Double.infinity
    let label = g.graph()
    let marginX = label.marginx
    let marginY = label.marginy

    for v in g.nodes() {
        let node = g.node(v)
        let x = node.x ?? 0
        let y = node.y ?? 0

        minX = Swift.min(minX, x - node.width / 2)
        minY = Swift.min(minY, y - node.height / 2)
    }

    minX -= marginX
    minY -= marginY

    for v in g.nodes() {
        let node = g.node(v)
        node.x = (node.x ?? 0) - minX
        node.y = (node.y ?? 0) - minY
    }
}

// MARK: - Util

private var dagreIdCounter = 0

private func dagreUniqueId(_ prefix: String) -> String {
    dagreIdCounter += 1
    return prefix + String(dagreIdCounter)
}

@discardableResult
private func dagreAddDummyNode(_ g: DagreLayoutGraph, _ type: DagreDummy, _ label: DagreNodeLabel, _ name: String) -> String {
    var v = name
    while g.hasNode(v) {
        v = dagreUniqueId(name)
    }

    label.dummy = type
    g.setNode(v, label)
    return v
}

/// The graph without the nodes that have children, which is the graph itself when it has no clusters. The
/// labels are shared with the graph it is made from.
private func dagreAsNonCompoundGraph(_ g: DagreLayoutGraph) -> DagreLayoutGraph {
    let simplified = makeLayoutGraph(compound: false, multigraph: g.isMultigraph)
    simplified.setGraph(g.graph())

    for v in g.nodes() where g.children(v).isEmpty {
        simplified.setNode(v, g.node(v))
    }

    for e in g.edges() {
        simplified.setEdge(e, g.edge(e))
    }

    return simplified
}

/// A matrix of the ids of the nodes, by rank and order.
private func dagreBuildLayerMatrix(_ g: DagreLayoutGraph) -> [[String]] {
    var layering: [[String?]] = Array(repeating: [], count: dagreMaxRank(g) + 1)

    for v in g.nodes() {
        let node = g.node(v)

        if let rank = node.rank, let order = node.order, rank >= 0 {
            while layering[rank].count <= order {
                layering[rank].append(nil)
            }
            layering[rank][order] = v
        }
    }

    return layering.map { $0.compactMap { $0 } }
}

private func dagreMaxRank(_ g: DagreLayoutGraph) -> Int {
    var result = 0

    for v in g.nodes() {
        if let rank = g.node(v).rank {
            result = Swift.max(result, rank)
        }
    }

    return result
}

private func dagreNormalizeRanks(_ g: DagreLayoutGraph) {
    let ranks = g.nodes().compactMap { g.node($0).rank }
    guard let minimum = ranks.min() else { return }

    for v in g.nodes() {
        let node = g.node(v)
        if let rank = node.rank {
            node.rank = rank - minimum
        }
    }
}

/// Empty ranks that are not on a multiple of the rank factor are taken out, which is what nested graphs leave.
private func dagreRemoveEmptyRanks(_ g: DagreLayoutGraph) {
    let ranks = g.nodes().compactMap { g.node($0).rank }
    guard let offset = ranks.min() else { return }

    var layers: [[String]?] = []
    for v in g.nodes() {
        guard let rank = g.node(v).rank else { continue }

        let index = rank - offset
        while layers.count <= index {
            layers.append(nil)
        }

        if layers[index] == nil {
            layers[index] = []
        }
        layers[index]?.append(v)
    }

    var delta = 0
    let nodeRankFactor = g.graph().nodeRankFactor

    for (i, vs) in layers.enumerated() {
        if vs == nil && i % nodeRankFactor != 0 {
            delta -= 1
        } else if let vs, delta != 0 {
            for v in vs {
                g.node(v).rank! += delta
            }
        }
    }
}

// MARK: - Acyclic

/// Reverses the edges that make the graph cyclic, found with a depth first search.
private func dagreAcyclicRun(_ g: DagreLayoutGraph) {
    var fas: [DagreEdge] = []
    var stack = Set<String>()
    var visited = Set<String>()

    func dfs(_ v: String) {
        if visited.contains(v) { return }

        visited.insert(v)
        stack.insert(v)

        for e in g.outEdges(v) ?? [] {
            if stack.contains(e.w) {
                fas.append(e)
            } else {
                dfs(e.w)
            }
        }

        stack.remove(v)
    }

    for v in g.nodes() {
        dfs(v)
    }

    for e in fas {
        guard let label = g.edge(e) else { continue }

        g.removeEdge(e)
        label.forwardName = e.name
        label.reversed = true
        g.setEdge(e.w, e.v, label, name: dagreUniqueId("rev"))
    }
}

// MARK: - Nesting

/// A root that is connected to every node makes the graph connected. Without clusters there are no borders to
/// make, and the ranks are not spread out.
private func dagreNestingRun(_ g: DagreLayoutGraph) {
    let root = dagreAddDummyNode(g, .root, DagreNodeLabel(), "_root")
    g.graph().nestingRoot = root

    // every node is at the top, so the tree is one level deep and the nodes are on the ranks of their edges
    let nodeSep = 1

    for e in g.edges() {
        g.edge(e)?.minlen *= nodeSep
    }

    for child in g.children(nil) where child != root {
        g.setEdge(root, child, DagreEdgeLabel(minlen: nodeSep, weight: 0))
    }

    g.graph().nodeRankFactor = nodeSep
}

private func dagreNestingCleanup(_ g: DagreLayoutGraph) {
    if let root = g.graph().nestingRoot {
        g.removeNode(root)
    }
    g.graph().nestingRoot = nil
}

// MARK: - Rank

private func dagreSlack(_ g: DagreLayoutGraph, _ e: DagreEdge) -> Int {
    g.node(e.w).rank! - g.node(e.v).rank! - g.edge(e)!.minlen
}

/// Pushes the nodes to the lowest rank that the minimum length of the edges allows.
private func dagreLongestPath(_ g: DagreLayoutGraph) {
    var visited = Set<String>()

    func dfs(_ v: String) -> Int {
        let label = g.node(v)

        if visited.contains(v) {
            return label.rank!
        }
        visited.insert(v)

        var rank = Double.infinity
        for e in g.outEdges(v) ?? [] {
            rank = Swift.min(rank, Double(dfs(e.w) - g.edge(e)!.minlen))
        }

        if rank == .infinity {
            rank = 0
        }

        label.rank = Int(rank)
        return Int(rank)
    }

    for v in g.sources() {
        _ = dfs(v)
    }
}

/// Moves the nodes so that a spanning tree of the graph only has tight edges, the ones that are as short as
/// they can be.
private func dagreFeasibleTree(_ g: DagreLayoutGraph) {
    let tree = DagreGraph<Void, Void, Void>(
        directed: false,
        defaultNode: { _ in Void() },
        defaultEdge: { _, _, _ in Void() })

    guard let start = g.nodes().first else { return }

    let size = g.nodeCount
    tree.setNode(start)

    func tightTree() -> Int {
        func dfs(_ v: String) {
            for e in g.nodeEdges(v) ?? [] {
                let w = v == e.v ? e.w : e.v

                if !tree.hasNode(w) && dagreSlack(g, e) == 0 {
                    tree.setNode(w)
                    tree.setEdge(v, w)
                    dfs(w)
                }
            }
        }

        for v in tree.nodes() {
            dfs(v)
        }

        return tree.nodeCount
    }

    func findMinSlackEdge() -> DagreEdge? {
        var best: DagreEdge?
        var bestSlack = Double.infinity

        for edge in g.edges() {
            var edgeSlack = Double.infinity
            if tree.hasNode(edge.v) != tree.hasNode(edge.w) {
                edgeSlack = Double(dagreSlack(g, edge))
            }

            if edgeSlack < bestSlack {
                bestSlack = edgeSlack
                best = edge
            }
        }

        return best
    }

    while tightTree() < size {
        guard let edge = findMinSlackEdge() else { break }

        let delta = tree.hasNode(edge.v) ? dagreSlack(g, edge) : -dagreSlack(g, edge)

        for v in tree.nodes() {
            g.node(v).rank! += delta
        }
    }
}

private func dagreRank(_ g: DagreLayoutGraph) {
    switch g.graph().ranker {
    case .tightTree:
        dagreLongestPath(g)
        dagreFeasibleTree(g)
    case .longestPath:
        dagreLongestPath(g)
    }
}

// MARK: - Normalize

/// Breaks the edges that are longer than one rank into pieces of one rank, with a dummy node between them.
private func dagreNormalizeRun(_ g: DagreLayoutGraph) {
    g.graph().dummyChains = []

    for e in g.edges() {
        var v = e.v
        var vRank = g.node(v).rank!
        let w = e.w
        let wRank = g.node(w).rank!
        let name = e.name

        guard let edgeLabel = g.edge(e), wRank != vRank + 1 else { continue }

        g.removeEdge(e)

        var i = 0
        vRank += 1

        while vRank < wRank {
            let attrs = DagreNodeLabel(width: 0, height: 0)
            attrs.edgeLabel = edgeLabel
            attrs.edgeObj = e
            attrs.rank = vRank

            let dummy = dagreAddDummyNode(g, .edge, attrs, "_d")
            g.setEdge(v, dummy, DagreEdgeLabel(weight: edgeLabel.weight), name: name)

            if i == 0 {
                g.graph().dummyChains.append(dummy)
            }

            v = dummy
            i += 1
            vRank += 1
        }

        g.setEdge(v, w, DagreEdgeLabel(weight: edgeLabel.weight), name: name)
    }
}

/// Puts the edges that were broken up back together.
private func dagreNormalizeUndo(_ g: DagreLayoutGraph) {
    for chainStart in g.graph().dummyChains {
        var v = chainStart
        var node = g.node(v)

        guard let original = node.edgeLabel, let edgeObj = node.edgeObj else { continue }

        g.setEdge(edgeObj, original)

        while node.dummy != nil {
            guard let w = g.successors(v)?.first else { break }

            g.removeNode(v)
            v = w
            node = g.node(v)
        }
    }
}

// MARK: - Coordinate system

private func dagreCoordinateSystemAdjust(_ g: DagreLayoutGraph) {
    let rankDir = g.graph().rankdir.lowercased()

    if rankDir == "lr" || rankDir == "rl" {
        for v in g.nodes() {
            let node = g.node(v)
            swap(&node.width, &node.height)
        }

        for e in g.edges() {
            if let label = g.edge(e) {
                swap(&label.width, &label.height)
            }
        }
    }
}

private func dagreCoordinateSystemUndo(_ g: DagreLayoutGraph) {
    let rankDir = g.graph().rankdir.lowercased()

    if rankDir == "bt" || rankDir == "rl" {
        for v in g.nodes() {
            let node = g.node(v)
            node.y = -(node.y ?? 0)
        }
    }

    if rankDir == "lr" || rankDir == "rl" {
        for v in g.nodes() {
            let node = g.node(v)
            let x = node.x
            node.x = node.y
            node.y = x
            swap(&node.width, &node.height)
        }

        for e in g.edges() {
            if let label = g.edge(e) {
                swap(&label.width, &label.height)
            }
        }
    }
}

// MARK: - Order

private struct BarycenterEntry {
    var v: String
    var barycenter: Double?
    var weight: Double?
}

private struct ResolvedEntry {
    var vs: [String]
    var i: Int
    var barycenter: Double?
    var weight: Double?
}

private func dagreSortStable<T>(_ array: [T], by areInIncreasingOrder: (T, T) -> Bool) -> [T] {
    array.enumerated()
        .sorted { first, second in
            if areInIncreasingOrder(first.element, second.element) { return true }
            if areInIncreasingOrder(second.element, first.element) { return false }
            return first.offset < second.offset
        }
        .map { $0.element }
}

/// Applies heuristics that reduce the crossings of the edges, and puts the best order that is found on the nodes.
private func dagreOrder(_ g: DagreLayoutGraph) {
    let maxRank = dagreMaxRank(g)

    let downLayerGraphs = buildLayerGraphs(g, ranks: maxRank >= 1 ? Array(1...maxRank) : [], incoming: true)
    let upLayerGraphs = buildLayerGraphs(g, ranks: maxRank >= 1 ? Array((0...(maxRank - 1)).reversed()) : [], incoming: false)

    var layering = dagreInitOrder(g)
    assignOrder(g, layering)

    var bestCrossCount = Double.infinity
    var best: [[String]] = layering

    var i = 0
    var lastBest = 0

    while lastBest < 4 {
        sweepLayerGraphs(i % 2 == 1 ? downLayerGraphs : upLayerGraphs, biasRight: i % 4 >= 2)

        layering = dagreBuildLayerMatrix(g)
        let crossings = dagreCrossCount(g, layering)

        if crossings < bestCrossCount {
            lastBest = 0
            best = layering
            bestCrossCount = crossings
        } else if crossings == bestCrossCount {
            best = layering
        }

        i += 1
        lastBest += 1
    }

    assignOrder(g, best)
}

private func assignOrder(_ g: DagreLayoutGraph, _ layering: [[String]]) {
    for layer in layering {
        for (i, v) in layer.enumerated() {
            g.node(v).order = i
        }
    }
}

/// A DFS from the nodes of the first rank gives the nodes their first order: they are ordered as they are visited.
private func dagreInitOrder(_ g: DagreLayoutGraph) -> [[String]] {
    var visited = Set<String>()
    let simpleNodes = g.nodes().filter { g.children($0).isEmpty }
    let maxRank = simpleNodes.compactMap { g.node($0).rank }.max() ?? -1
    var layers: [[String]] = Array(repeating: [], count: Swift.max(0, maxRank + 1))

    func dfs(_ v: String) {
        if visited.contains(v) { return }

        visited.insert(v)
        let node = g.node(v)
        layers[node.rank!].append(v)

        for w in g.successors(v) ?? [] {
            dfs(w)
        }
    }

    let ordered = dagreSortStable(simpleNodes) { g.node($0).rank! < g.node($1).rank! }
    for v in ordered {
        dfs(v)
    }

    return layers
}

/// The graphs that are used to sort a layer: the nodes of the rank with the edges that come in, or go out.
private func buildLayerGraphs(_ g: DagreLayoutGraph, ranks: [Int], incoming: Bool) -> [DagreLayoutGraph] {
    var nodesByRank: [Int: [String]] = [:]

    for v in g.nodes() {
        if let rank = g.node(v).rank {
            nodesByRank[rank, default: []].append(v)
        }
    }

    return ranks.map { rank in
        buildLayerGraph(g, rank: rank, incoming: incoming, nodesWithRank: nodesByRank[rank] ?? [])
    }
}

private func buildLayerGraph(
    _ g: DagreLayoutGraph,
    rank: Int,
    incoming: Bool,
    nodesWithRank: [String]
) -> DagreLayoutGraph {
    var root = dagreUniqueId("_root")
    while g.hasNode(root) {
        root = dagreUniqueId("_root")
    }

    let result = makeLayoutGraph(compound: true, multigraph: false, root: g)
    let label = DagreGraphLabel()
    label.root = root
    result.setGraph(label)

    for v in nodesWithRank {
        let node = g.node(v)

        if node.rank == rank {
            result.setNode(v)
            result.setParent(v, g.parent(v) ?? root)

            // this assumes there are only short edges
            let edges = (incoming ? g.inEdges(v) : g.outEdges(v)) ?? []
            for e in edges {
                let u = e.v == v ? e.w : e.v
                let weight = result.edge(u, v)?.weight ?? 0
                result.setEdge(u, v, DagreEdgeLabel(weight: (g.edge(e)?.weight ?? 0) + weight))
            }
        }
    }

    return result
}

private func sweepLayerGraphs(_ layerGraphs: [DagreLayoutGraph], biasRight: Bool) {
    for layerGraph in layerGraphs {
        guard let root = layerGraph.graph().root else { continue }

        let sorted = sortSubgraph(layerGraph, root, biasRight: biasRight)
        for (i, v) in sorted.enumerated() {
            layerGraph.node(v).order = i
        }
    }
}

/// Orders the movable nodes of a layer, by the average order of the nodes their edges lead to.
private func sortSubgraph(_ g: DagreLayoutGraph, _ v: String, biasRight: Bool) -> [String] {
    let movable = g.children(v)

    // the nodes that have an edge to a node of the other layer, with the average order of those
    let barycenters: [BarycenterEntry] = movable.map { w in
        guard let inEdges = g.inEdges(w), !inEdges.isEmpty else {
            return BarycenterEntry(v: w)
        }

        var sum = 0.0
        var weight = 0.0
        for e in inEdges {
            let edgeWeight = g.edge(e)?.weight ?? 0
            sum += edgeWeight * Double(g.node(e.v).order ?? 0)
            weight += edgeWeight
        }

        return BarycenterEntry(v: w, barycenter: sum / weight, weight: weight)
    }

    // there are no constraints between the nodes of a flat graph, so nothing is merged: the entries come out
    // of the resolution of conflicts the other way round
    let entries = barycenters.enumerated().reversed().map { index, entry in
        ResolvedEntry(vs: [entry.v], i: index, barycenter: entry.barycenter, weight: entry.weight)
    }

    return sortEntries(entries, biasRight: biasRight)
}

private func sortEntries(_ entries: [ResolvedEntry], biasRight: Bool) -> [String] {
    let sortable = entries.filter { $0.barycenter != nil }
    var unsortable = entries.filter { $0.barycenter == nil }.sorted { $0.i > $1.i }

    let sorted = sortable.sorted { first, second in
        if first.barycenter! < second.barycenter! { return true }
        if first.barycenter! > second.barycenter! { return false }
        return biasRight ? second.i < first.i : first.i < second.i
    }

    var vs: [String] = []
    var index = 0

    func consumeUnsortable() {
        while let last = unsortable.last, last.i <= index {
            unsortable.removeLast()
            vs.append(contentsOf: last.vs)
            index += 1
        }
    }

    consumeUnsortable()

    for entry in sorted {
        index += entry.vs.count
        vs.append(contentsOf: entry.vs)
        consumeUnsortable()
    }

    return vs
}

/// The weighted number of crossings of the edges between the layers (Barth et al., "Bilayer Cross Counting").
private func dagreCrossCount(_ g: DagreLayoutGraph, _ layering: [[String]]) -> Double {
    var crossings = 0.0

    if layering.count > 1 {
        for i in 1..<layering.count {
            crossings += twoLayerCrossCount(g, layering[i - 1], layering[i])
        }
    }

    return crossings
}

private func twoLayerCrossCount(_ g: DagreLayoutGraph, _ northLayer: [String], _ southLayer: [String]) -> Double {
    // the edges between the layers, by the position of their end in the south layer
    var southPositions: [String: Int] = [:]
    for (i, v) in southLayer.enumerated() {
        southPositions[v] = i
    }

    var southEntries: [(pos: Int, weight: Double)] = []
    for v in northLayer {
        let edges = (g.outEdges(v) ?? []).compactMap { e -> (pos: Int, weight: Double)? in
            guard let position = southPositions[e.w] else { return nil }
            return (position, g.edge(e)?.weight ?? 0)
        }

        southEntries.append(contentsOf: dagreSortStable(edges) { $0.pos < $1.pos })
    }

    // the accumulator tree
    var firstIndex = 1
    while firstIndex < southLayer.count {
        firstIndex <<= 1
    }

    let treeSize = 2 * firstIndex - 1
    firstIndex -= 1
    var tree = [Double](repeating: 0, count: treeSize)

    var crossings = 0.0

    for entry in southEntries {
        var index = entry.pos + firstIndex
        tree[index] += entry.weight

        var weightSum = 0.0
        while index > 0 {
            if index % 2 == 1 {
                weightSum += tree[index + 1]
            }

            index = (index - 1) >> 1
            tree[index] += entry.weight
        }

        crossings += entry.weight * weightSum
    }

    return crossings
}

// MARK: - Position

private func dagrePosition(_ g: DagreLayoutGraph) {
    let flat = dagreAsNonCompoundGraph(g)

    positionY(flat)

    for (v, x) in positionX(flat) {
        flat.node(v).x = x
    }
}

private func positionY(_ g: DagreLayoutGraph) {
    let layering = dagreBuildLayerMatrix(g)
    let label = g.graph()
    let rankSep = label.ranksep
    let rankAlign = label.rankalign
    var prevY = 0.0

    for layer in layering {
        var maxHeight = 0.0
        for v in layer {
            maxHeight = Swift.max(maxHeight, g.node(v).height)
        }

        for v in layer {
            let node = g.node(v)

            if rankAlign == "top" {
                node.y = prevY + node.height / 2
            } else if rankAlign == "bottom" {
                node.y = prevY + maxHeight - node.height / 2
            } else {
                node.y = prevY + maxHeight / 2
            }
        }

        prevY += maxHeight + rankSep
    }
}

// MARK: Brandes and Köpf

private typealias Conflicts = [String: Set<String>]

private func addConflict(_ conflicts: inout Conflicts, _ v: String, _ w: String) {
    var first = v
    var second = w

    if first > second {
        swap(&first, &second)
    }

    conflicts[first, default: []].insert(second)
}

private func hasConflict(_ conflicts: Conflicts, _ v: String, _ w: String) -> Bool {
    var first = v
    var second = w

    if first > second {
        swap(&first, &second)
    }

    return conflicts[first]?.contains(second) ?? false
}

private func findOtherInnerSegmentNode(_ g: DagreLayoutGraph, _ v: String) -> String? {
    if g.node(v).dummy != nil {
        return g.predecessors(v)?.first { g.node($0).dummy != nil }
    }

    return nil
}

/// Marks the edges where a segment that is not between two dummy nodes crosses one that is.
private func findType1Conflicts(_ g: DagreLayoutGraph, _ layering: [[String]]) -> Conflicts {
    var conflicts: Conflicts = [:]

    func visitLayer(_ prevLayer: [String], _ layer: [String]) {
        // the last node of the layer before that is on an inner segment, and the last node of this layer that
        // was scanned
        var k0 = 0
        var scanPos = 0
        let prevLayerLength = prevLayer.count
        let lastNode = layer.last

        for (i, v) in layer.enumerated() {
            let w = findOtherInnerSegmentNode(g, v)
            let k1 = w.map { g.node($0).order ?? 0 } ?? prevLayerLength

            if w != nil || v == lastNode {
                for scanNode in layer[scanPos..<(i + 1)] {
                    for u in g.predecessors(scanNode) ?? [] {
                        let uLabel = g.node(u)
                        let uPos = uLabel.order ?? 0

                        if (uPos < k0 || k1 < uPos) && !(uLabel.dummy != nil && g.node(scanNode).dummy != nil) {
                            addConflict(&conflicts, u, scanNode)
                        }
                    }
                }

                scanPos = i + 1
                k0 = k1
            }
        }
    }

    if layering.count > 1 {
        for i in 1..<layering.count {
            visitLayer(layering[i - 1], layering[i])
        }
    }

    return conflicts
}

private func findType2Conflicts(_ g: DagreLayoutGraph, _ layering: [[String]]) -> Conflicts {
    var conflicts: Conflicts = [:]

    func scan(_ south: [String], _ southPos: Int, _ southEnd: Int, _ prevNorthBorder: Int, _ nextNorthBorder: Int) {
        guard southPos < southEnd else { return }

        for i in southPos..<southEnd {
            let v = south[i]

            if g.node(v).dummy != nil {
                for u in g.predecessors(v) ?? [] {
                    let uNode = g.node(u)
                    let order = uNode.order ?? 0

                    if uNode.dummy != nil && (order < prevNorthBorder || order > nextNorthBorder) {
                        addConflict(&conflicts, u, v)
                    }
                }
            }
        }
    }

    func visitLayer(_ north: [String], _ south: [String]) {
        var prevNorthPos = -1
        var nextNorthPos = -1
        var southPos = 0

        for (southLookahead, v) in south.enumerated() {
            if g.node(v).dummy == .border {
                if let predecessors = g.predecessors(v), let first = predecessors.first {
                    nextNorthPos = g.node(first).order ?? 0
                    scan(south, southPos, southLookahead, prevNorthPos, nextNorthPos)
                    southPos = southLookahead
                    prevNorthPos = nextNorthPos
                }
            }

            scan(south, southPos, south.count, nextNorthPos, north.count)
        }
    }

    if layering.count > 1 {
        for i in 1..<layering.count {
            visitLayer(layering[i - 1], layering[i])
        }
    }

    return conflicts
}

/// Tries to put nodes in vertical blocks: a node is aligned with one of its median neighbors, unless that
/// would be a conflict or would split a block.
private func verticalAlignment(
    _ g: DagreLayoutGraph,
    _ layering: [[String]],
    _ conflicts: Conflicts,
    _ neighborFn: (String) -> [String]
) -> (root: [String: String], align: [String: String]) {
    var root: [String: String] = [:]
    var align: [String: String] = [:]
    var pos: [String: Int] = [:]

    // the position is taken from the layering, which is changed to get the different extreme alignments
    for layer in layering {
        for (order, v) in layer.enumerated() {
            root[v] = v
            align[v] = v
            pos[v] = order
        }
    }

    for layer in layering {
        var prevIdx = -1

        for v in layer {
            var ws = neighborFn(v)

            if !ws.isEmpty {
                ws.sort { (pos[$0] ?? 0) < (pos[$1] ?? 0) }

                let mp = Double(ws.count - 1) / 2
                var i = Int(mp.rounded(.down))
                let il = Int(mp.rounded(.up))

                while i <= il {
                    let w = ws[i]

                    if let posW = pos[w], align[v] == v, prevIdx < posW, !hasConflict(conflicts, v, w),
                       let rootW = root[w] {
                        align[w] = v
                        root[v] = rootW
                        align[v] = rootW
                        prevIdx = posW
                    }

                    i += 1
                }
            }
        }
    }

    return (root, align)
}

private func sep(_ g: DagreLayoutGraph, _ v: String, _ w: String, nodeSep: Double, edgeSep: Double) -> Double {
    let vLabel = g.node(v)
    let wLabel = g.node(w)
    var sum = 0.0

    sum += vLabel.width / 2
    sum += (vLabel.dummy != nil ? edgeSep : nodeSep) / 2
    sum += (wLabel.dummy != nil ? edgeSep : nodeSep) / 2
    sum += wLabel.width / 2

    return sum
}

private func buildBlockGraph(
    _ g: DagreLayoutGraph,
    _ layering: [[String]],
    _ root: [String: String]
) -> DagreGraph<Void, Void, Double> {
    let blockGraph = DagreGraph<Void, Void, Double>(defaultNode: { _ in Void() }, defaultEdge: { _, _, _ in 0 })
    let label = g.graph()

    for layer in layering {
        var u: String?

        for v in layer {
            guard let vRoot = root[v] else { continue }

            blockGraph.setNode(vRoot)

            if let u, let uRoot = root[u] {
                let previousMax = blockGraph.edge(uRoot, vRoot)
                blockGraph.setEdge(
                    uRoot, vRoot,
                    Swift.max(sep(g, v, u, nodeSep: label.nodesep, edgeSep: label.edgesep), previousMax ?? 0))
            }

            u = v
        }
    }

    return blockGraph
}

/// Places the blocks in two sweeps. The first puts them at the smallest coordinates, the second moves them to
/// the largest ones that do not break the separation, which takes away the space that is not used.
private func horizontalCompaction(
    _ g: DagreLayoutGraph,
    _ layering: [[String]],
    _ root: [String: String],
    _ align: [String: String]
) -> [String: Double] {
    var xs: [String: Double] = [:]
    let blockGraph = buildBlockGraph(g, layering, root)

    func iterate(_ setXs: (String) -> Void, _ nextNodes: (String) -> [String]) {
        var stack = blockGraph.nodes()
        var visited = Set<String>()

        while let elem = stack.popLast() {
            if visited.contains(elem) {
                setXs(elem)
            } else {
                visited.insert(elem)

                // the element is processed again once the nodes after it are
                stack.append(elem)
                stack.append(contentsOf: nextNodes(elem))
            }
        }
    }

    func pass1(_ elem: String) {
        if let inEdges = blockGraph.inEdges(elem) {
            var value = 0.0
            for e in inEdges {
                value = Swift.max(value, (xs[e.v] ?? 0) + (blockGraph.edge(e) ?? 0))
            }
            xs[elem] = value
        } else {
            xs[elem] = 0
        }
    }

    func pass2(_ elem: String) {
        var minimum = Double.infinity

        for e in blockGraph.outEdges(elem) ?? [] {
            minimum = Swift.min(minimum, (xs[e.w] ?? 0) - (blockGraph.edge(e) ?? 0))
        }

        if minimum != .infinity {
            xs[elem] = Swift.max(xs[elem] ?? 0, minimum)
        }
    }

    iterate(pass1) { blockGraph.predecessors($0) ?? [] }
    iterate(pass2) { blockGraph.successors($0) ?? [] }

    // every node gets the coordinate of its block
    for v in align.keys {
        if let rootV = root[v] {
            xs[v] = xs[rootV] ?? 0
        }
    }

    return xs
}

private func positionX(_ g: DagreLayoutGraph) -> [String: Double] {
    let layering = dagreBuildLayerMatrix(g)

    // the conflicts of the second kind replace the ones of the first kind for the nodes they have in common
    var conflicts = findType1Conflicts(g, layering)
    for (v, set) in findType2Conflicts(g, layering) {
        conflicts[v] = set
    }

    var xss: [(key: String, xs: [String: Double])] = []
    var adjustedLayering: [[String]] = layering

    for vert in ["u", "d"] {
        adjustedLayering = vert == "u" ? layering : layering.reversed()

        for horiz in ["l", "r"] {
            if horiz == "r" {
                adjustedLayering = adjustedLayering.map { Array($0.reversed()) }
            }

            let neighborFn: (String) -> [String] = { v in
                (vert == "u" ? g.predecessors(v) : g.successors(v)) ?? []
            }

            let alignment = verticalAlignment(g, adjustedLayering, conflicts, neighborFn)
            var xs = horizontalCompaction(g, adjustedLayering, alignment.root, alignment.align)

            if horiz == "r" {
                xs = xs.mapValues { -$0 }
            }

            xss.append((vert + horiz, xs))
        }
    }

    // the alignment with the smallest width, which the others are aligned to
    var smallestKey: String?
    var smallestWidth = Double.infinity

    for entry in xss {
        var maximum = -Double.infinity
        var minimum = Double.infinity

        for (v, x) in entry.xs {
            let halfWidth = g.node(v).width / 2
            maximum = Swift.max(x + halfWidth, maximum)
            minimum = Swift.min(x - halfWidth, minimum)
        }

        if maximum - minimum < smallestWidth {
            smallestWidth = maximum - minimum
            smallestKey = entry.key
        }
    }

    guard let smallestKey, let alignTo = xss.first(where: { $0.key == smallestKey })?.xs else {
        return [:]
    }

    // left biased alignments get the minimum of the smallest one, right biased alignments its maximum
    let alignToValues = Array(alignTo.values)
    let alignToMin = alignToValues.min() ?? 0
    let alignToMax = alignToValues.max() ?? 0

    for index in xss.indices where xss[index].key != smallestKey {
        let key = xss[index].key
        let values = Array(xss[index].xs.values)
        guard !values.isEmpty else { continue }

        var delta = alignToMin - (values.min() ?? 0)
        if !key.hasSuffix("l") {
            delta = alignToMax - (values.max() ?? 0)
        }

        if delta != 0 {
            xss[index].xs = xss[index].xs.mapValues { $0 + delta }
        }
    }

    // balance: the average of the two median alignments
    guard let upLeft = xss.first(where: { $0.key == "ul" })?.xs else { return [:] }

    var result: [String: Double] = [:]
    for v in upLeft.keys {
        let sorted = xss.map { $0.xs[v] ?? 0 }.sorted()
        let first = sorted.count > 1 ? sorted[1] : 0
        let second = sorted.count > 2 ? sorted[2] : 0
        result[v] = (first + second) / 2
    }

    return result
}
