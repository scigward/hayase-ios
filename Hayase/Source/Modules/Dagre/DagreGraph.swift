//
//  DagreGraph.swift
//  Hayase
//
//  The graph the layout of the relations works on. It keeps the semantics of the graphlib graph that dagre
//  is built on, which are not obvious: the nodes of that graph are the keys of an object, so ids that look
//  like array indices (every media id does) come first, in numeric order, and any other id follows in the
//  order it was added. The order of the nodes decides ties in the layout, so it is kept as it is.
//

import Foundation

// MARK: - Key order of an object

/// Whether a key is an array index of JavaScript: an integer from 0 to 2^32 - 2 without leading zeros.
private func dagreArrayIndex(_ key: String) -> UInt32? {
    let bytes = Array(key.utf8)
    guard !bytes.isEmpty, bytes.count <= 10 else { return nil }
    if bytes.count > 1 && bytes[0] == 48 { return nil }

    var value: UInt64 = 0
    for byte in bytes {
        guard byte >= 48 && byte <= 57 else { return nil }
        value = value * 10 + UInt64(byte - 48)
    }

    return value < 4_294_967_295 ? UInt32(value) : nil
}

/// The keys of an object as `Object.keys` lists them: the array indices ascending, then the other keys in the
/// order they were added.
private func dagreKeyOrder(_ insertion: [String]) -> [String] {
    var indices: [(index: UInt32, key: String)] = []
    var others: [String] = []

    for key in insertion {
        if let index = dagreArrayIndex(key) {
            indices.append((index, key))
        } else {
            others.append(key)
        }
    }

    indices.sort { $0.index < $1.index }
    return indices.map { $0.key } + others
}

/// A JavaScript object used as a map: setting a key that is there keeps its place, removing it and setting
/// it again puts it at the end, and the keys are listed in the order of `Object.keys`.
final class DagreObject<Value> {
    private var storage: [String: Value] = [:]
    private var insertion: [String] = []
    private var cachedKeys: [String]?

    var count: Int { storage.count }
    var isEmpty: Bool { storage.isEmpty }

    var keys: [String] {
        if let cachedKeys { return cachedKeys }

        let ordered = dagreKeyOrder(insertion)
        cachedKeys = ordered
        return ordered
    }

    var values: [Value] {
        keys.compactMap { storage[$0] }
    }

    func has(_ key: String) -> Bool {
        storage[key] != nil
    }

    func get(_ key: String) -> Value? {
        storage[key]
    }

    func set(_ key: String, _ value: Value) {
        if storage.updateValue(value, forKey: key) == nil {
            insertion.append(key)
            cachedKeys = nil
        }
    }

    @discardableResult
    func remove(_ key: String) -> Value? {
        guard let old = storage.removeValue(forKey: key) else { return nil }

        if let index = insertion.firstIndex(of: key) {
            insertion.remove(at: index)
        }
        cachedKeys = nil
        return old
    }
}

// MARK: - Graph

/// The identity of an edge: its two ends and, in a multigraph, its name.
struct DagreEdge: Hashable {
    var v: String
    var w: String
    var name: String?
}

private let defaultEdgeName = "\u{0}"
private let rootNode = "\u{0}"
private let edgeKeyDelimiter = "\u{1}"

/// `Graph` of graphlib. `G` is the type of the label of the graph, `N` the one of its nodes and `E` the one
/// of its edges.
final class DagreGraph<G, N, E> {
    let isDirected: Bool
    let isMultigraph: Bool
    let isCompound: Bool

    private var graphLabel: G?
    private let defaultNodeLabel: (String) -> N
    private let defaultEdgeLabel: (String, String, String?) -> E

    private let nodeLabels = DagreObject<N>()
    private var incoming: [String: DagreObject<DagreEdge>] = [:]
    private var predecessorCounts: [String: DagreObject<Int>] = [:]
    private var outgoing: [String: DagreObject<DagreEdge>] = [:]
    private var successorCounts: [String: DagreObject<Int>] = [:]
    private let edgeObjects = DagreObject<DagreEdge>()
    private let edgeLabels = DagreObject<E>()
    private var parents: [String: String] = [:]
    private var childLists: [String: DagreObject<Bool>] = [:]

    private(set) var nodeCount = 0
    private(set) var edgeCount = 0

    init(
        directed: Bool = true,
        multigraph: Bool = false,
        compound: Bool = false,
        defaultNode: @escaping (String) -> N,
        defaultEdge: @escaping (String, String, String?) -> E
    ) {
        isDirected = directed
        isMultigraph = multigraph
        isCompound = compound
        defaultNodeLabel = defaultNode
        defaultEdgeLabel = defaultEdge

        if compound {
            childLists[rootNode] = DagreObject<Bool>()
        }
    }

    // MARK: Graph

    @discardableResult
    func setGraph(_ label: G) -> DagreGraph {
        graphLabel = label
        return self
    }

    func graph() -> G {
        graphLabel!
    }

    // MARK: Nodes

    func nodes() -> [String] {
        nodeLabels.keys
    }

    func sources() -> [String] {
        nodes().filter { incoming[$0]?.isEmpty ?? true }
    }

    func sinks() -> [String] {
        nodes().filter { outgoing[$0]?.isEmpty ?? true }
    }

    func hasNode(_ name: String) -> Bool {
        nodeLabels.has(name)
    }

    func node(_ name: String) -> N {
        nodeLabels.get(name)!
    }

    @discardableResult
    func setNode(_ name: String, _ label: N? = nil) -> DagreGraph {
        if nodeLabels.has(name) {
            if let label {
                nodeLabels.set(name, label)
            }
            return self
        }

        nodeLabels.set(name, label ?? defaultNodeLabel(name))

        if isCompound {
            parents[name] = rootNode
            childLists[name] = DagreObject<Bool>()
            childLists[rootNode]?.set(name, true)
        }

        incoming[name] = DagreObject<DagreEdge>()
        predecessorCounts[name] = DagreObject<Int>()
        outgoing[name] = DagreObject<DagreEdge>()
        successorCounts[name] = DagreObject<Int>()
        nodeCount += 1
        return self
    }

    @discardableResult
    func removeNode(_ name: String) -> DagreGraph {
        guard nodeLabels.has(name) else { return self }

        nodeLabels.remove(name)

        if isCompound {
            removeFromParentsChildList(name)
            parents[name] = nil

            for child in children(name) {
                setParent(child, nil)
            }
            childLists[name] = nil
        }

        for edgeId in (incoming[name]?.keys ?? []) {
            if let edge = edgeObjects.get(edgeId) { removeEdge(edge) }
        }
        incoming[name] = nil
        predecessorCounts[name] = nil

        for edgeId in (outgoing[name]?.keys ?? []) {
            if let edge = edgeObjects.get(edgeId) { removeEdge(edge) }
        }
        outgoing[name] = nil
        successorCounts[name] = nil

        nodeCount -= 1
        return self
    }

    // MARK: Compound

    /// The parent of a node, `nil` for the nodes that are at the top.
    func parent(_ v: String) -> String? {
        guard isCompound, let parent = parents[v], parent != rootNode else { return nil }
        return parent
    }

    /// Makes `parent` the parent of `v`. Without a parent `v` goes to the top.
    func setParent(_ v: String, _ parent: String?) {
        precondition(isCompound, "Cannot set parent in a non-compound graph")

        let newParent: String
        if let parent {
            newParent = parent

            var ancestor: String? = parent
            while let current = ancestor {
                precondition(current != v, "Setting \(parent) as parent of \(v) would create a cycle")
                ancestor = self.parent(current)
            }

            setNode(parent)
        } else {
            newParent = rootNode
        }

        setNode(v)
        removeFromParentsChildList(v)
        parents[v] = newParent
        childLists[newParent]?.set(v, true)
    }

    /// The children of a node, or the nodes at the top for `nil`.
    func children(_ v: String? = nil) -> [String] {
        let key = v ?? rootNode

        if isCompound {
            return childLists[key]?.keys ?? []
        }

        return key == rootNode ? nodes() : []
    }

    private func removeFromParentsChildList(_ v: String) {
        if let parent = parents[v] {
            childLists[parent]?.remove(v)
        }
    }

    // MARK: Neighbors

    func predecessors(_ v: String) -> [String]? {
        predecessorCounts[v]?.keys
    }

    func successors(_ v: String) -> [String]? {
        successorCounts[v]?.keys
    }

    func neighbors(_ v: String) -> [String]? {
        guard let predecessors = predecessors(v) else { return nil }

        var seen = Set(predecessors)
        var union = predecessors
        for successor in successors(v) ?? [] where seen.insert(successor).inserted {
            union.append(successor)
        }
        return union
    }

    // MARK: Edges

    func edges() -> [DagreEdge] {
        edgeObjects.values
    }

    private func edgeId(_ v: String, _ w: String, _ name: String?) -> String {
        var first = v
        var second = w

        if !isDirected && first > second {
            swap(&first, &second)
        }

        return first + edgeKeyDelimiter + second + edgeKeyDelimiter + (name ?? defaultEdgeName)
    }

    private func edgeId(_ edge: DagreEdge) -> String {
        edgeId(edge.v, edge.w, edge.name)
    }

    func hasEdge(_ v: String, _ w: String, _ name: String? = nil) -> Bool {
        edgeLabels.has(edgeId(v, w, name))
    }

    func hasEdge(_ edge: DagreEdge) -> Bool {
        edgeLabels.has(edgeId(edge))
    }

    func edge(_ v: String, _ w: String, _ name: String? = nil) -> E? {
        edgeLabels.get(edgeId(v, w, name))
    }

    func edge(_ edge: DagreEdge) -> E? {
        edgeLabels.get(edgeId(edge))
    }

    @discardableResult
    func setEdge(_ v: String, _ w: String, _ label: E? = nil, name: String? = nil) -> DagreGraph {
        let id = edgeId(v, w, name)

        if edgeLabels.has(id) {
            if let label {
                edgeLabels.set(id, label)
            }
            return self
        }

        precondition(name == nil || isMultigraph, "Cannot set a named edge when isMultigraph = false")

        // the nodes of the edge are there before the edge is
        setNode(v)
        setNode(w)

        edgeLabels.set(id, label ?? defaultEdgeLabel(v, w, name))

        // undirected edges are added with their ends in a consistent order
        var start = v
        var end = w
        if !isDirected && start > end {
            swap(&start, &end)
        }

        let object = DagreEdge(v: start, w: end, name: (name?.isEmpty ?? true) ? nil : name)
        edgeObjects.set(id, object)

        increment(predecessorCounts[end], start)
        increment(successorCounts[start], end)
        incoming[end]?.set(id, object)
        outgoing[start]?.set(id, object)
        edgeCount += 1
        return self
    }

    @discardableResult
    func setEdge(_ edge: DagreEdge, _ label: E? = nil) -> DagreGraph {
        setEdge(edge.v, edge.w, label, name: edge.name)
    }

    @discardableResult
    func removeEdge(_ edge: DagreEdge) -> DagreGraph {
        let id = edgeId(edge)

        guard let object = edgeObjects.get(id) else { return self }

        edgeLabels.remove(id)
        edgeObjects.remove(id)
        decrement(predecessorCounts[object.w], object.v)
        decrement(successorCounts[object.v], object.w)
        incoming[object.w]?.remove(id)
        outgoing[object.v]?.remove(id)
        edgeCount -= 1
        return self
    }

    @discardableResult
    func removeEdge(_ v: String, _ w: String, _ name: String? = nil) -> DagreGraph {
        removeEdge(DagreEdge(v: v, w: w, name: name))
    }

    func inEdges(_ v: String, _ w: String? = nil) -> [DagreEdge]? {
        guard let edges = incoming[v] else { return nil }

        if isDirected {
            return filterEdges(edges.values, v, w)
        }
        return nodeEdges(v, w)
    }

    func outEdges(_ v: String, _ w: String? = nil) -> [DagreEdge]? {
        guard let edges = outgoing[v] else { return nil }

        if isDirected {
            return filterEdges(edges.values, v, w)
        }
        return nodeEdges(v, w)
    }

    /// Every edge of a node: the ones that come in and then the ones that go out.
    func nodeEdges(_ v: String, _ w: String? = nil) -> [DagreEdge]? {
        guard nodeLabels.has(v) else { return nil }

        var merged: [DagreEdge] = []
        var seen = Set<DagreEdge>()
        for edge in (incoming[v]?.values ?? []) + (outgoing[v]?.values ?? []) where seen.insert(edge).inserted {
            merged.append(edge)
        }

        return filterEdges(merged, v, w)
    }

    private func filterEdges(_ edges: [DagreEdge], _ local: String, _ remote: String?) -> [DagreEdge] {
        guard let remote, !remote.isEmpty else { return edges }

        return edges.filter { edge in
            (edge.v == local && edge.w == remote) || (edge.v == remote && edge.w == local)
        }
    }

    private func increment(_ counts: DagreObject<Int>?, _ key: String) {
        guard let counts else { return }

        if let current = counts.get(key), current != 0 {
            counts.set(key, current + 1)
        } else {
            counts.set(key, 1)
        }
    }

    private func decrement(_ counts: DagreObject<Int>?, _ key: String) {
        guard let counts, let current = counts.get(key) else { return }

        if current - 1 == 0 {
            counts.remove(key)
        } else {
            counts.set(key, current - 1)
        }
    }
}
