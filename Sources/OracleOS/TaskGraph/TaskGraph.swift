import Foundation

/// The live task graph that the planner navigates.
///
/// ``TaskGraph`` is the canonical representation of the current task. It
/// maintains a *current node* pointer and provides operations for edge
/// expansion, execution recording, and graph update. The planner operates
/// on this graph directly — it is **not** a post-hoc log.
///
/// ## Ownership
///
/// The graph owns:
/// 1. Current task position (``currentNodeID``)
/// 2. Known local branches (outgoing edges from a node)
/// 3. Candidate future expansions (candidate edges)
/// 4. Edge evidence (success/failure counts)
/// 5. Recovery alternatives (alternate edges after failure)
public final class TaskGraph: @unchecked Sendable {
    private let lock = NSRecursiveLock()
    private var nodes: [String: TaskNode] = [:]
    private var edges: [String: TaskEdge] = [:]
    public private(set) var currentNodeID: String?

    // Growth limits
    public let maxNodesPerTask: Int
    public let maxEdgesPerNode: Int
    public let nodeMergeSimilarityThreshold: Double

    public init(
        maxNodesPerTask: Int = 200,
        maxEdgesPerNode: Int = 10,
        nodeMergeSimilarityThreshold: Double = 0.9
    ) {
        self.maxNodesPerTask = maxNodesPerTask
        self.maxEdgesPerNode = maxEdgesPerNode
        self.nodeMergeSimilarityThreshold = nodeMergeSimilarityThreshold
    }

    // MARK: - Node Operations

    /// Add or update a node. If a node with the same abstract state and
    /// planning-state ID already exists it is returned instead.
    @discardableResult
    public func addOrMergeNode(_ node: TaskNode) -> TaskNode {
        lock.lock()
        defer { lock.unlock() }

        if let existing = findMergeCandidate(for: node) {
            existing.recordVisit()
            return existing
        }

        guard nodes.count < maxNodesPerTask else {
            pruneOldestNodes()
            guard nodes.count < maxNodesPerTask else {
                // Cannot grow further; return the node without storing.
                return node
            }
        }

        nodes[node.id] = node
        return node
    }

    public func node(for id: String) -> TaskNode? {
        lock.lock()
        defer { lock.unlock() }
        return nodes[id]
    }

    public func currentNode() -> TaskNode? {
        lock.lock()
        defer { lock.unlock() }
        guard let id = currentNodeID else { return nil }
        return nodes[id]
    }

    /// Move the graph's current position to a node.
    public func setCurrent(_ nodeID: String) {
        lock.lock()
        defer { lock.unlock() }
        if nodes[nodeID] != nil {
            currentNodeID = nodeID
        }
    }

    public var nodeCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return nodes.count
    }

    public func allNodes() -> [TaskNode] {
        lock.lock()
        defer { lock.unlock() }
        return Array(nodes.values)
    }

    // MARK: - Edge Operations

    /// Add a candidate or executed edge.
    @discardableResult
    public func addEdge(_ edge: TaskEdge) -> TaskEdge {
        lock.lock()
        defer { lock.unlock() }

        let fromEdges = outgoingEdges(from: edge.fromNodeID)
        if fromEdges.count >= maxEdgesPerNode {
            pruneWeakestEdges(from: edge.fromNodeID)
        }

        edges[edge.id] = edge
        return edge
    }

    public func edge(for id: String) -> TaskEdge? {
        lock.lock()
        defer { lock.unlock() }
        return edges[id]
    }

    /// All outgoing edges from a given node.
    public func outgoingEdges(from nodeID: String) -> [TaskEdge] {
        lock.lock()
        defer { lock.unlock() }
        return edges.values.filter { $0.fromNodeID == nodeID }
    }

    /// Outgoing edges filtered to non-failed status.
    public func viableEdges(from nodeID: String) -> [TaskEdge] {
        outgoingEdges(from: nodeID).filter { $0.status != .executedFailure && $0.status != .abandoned }
    }

    /// Alternate edges from the same source node, excluding a specific edge.
    /// Used for recovery branching.
    public func alternateEdges(from nodeID: String, excluding edgeID: String) -> [TaskEdge] {
        outgoingEdges(from: nodeID).filter { $0.id != edgeID && $0.status != .abandoned }
    }

    public var edgeCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return edges.count
    }

    public func allEdges() -> [TaskEdge] {
        lock.lock()
        defer { lock.unlock() }
        return Array(edges.values)
    }

    // MARK: - Graph Update Cycle

    /// Record a successful execution: update edge evidence, create the
    /// destination node if needed, and advance the current pointer.
    @discardableResult
    public func recordExecution(
        edgeID: String,
        resultNode: TaskNode,
        latencyMs: Int = 0,
        cost: Double = 0
    ) -> TaskNode {
        lock.lock()
        defer { lock.unlock() }

        let destination = addOrMergeNode(resultNode)

        if let edge = edges[edgeID] {
            edge.recordSuccess(latencyMs: latencyMs, cost: cost)
        }

        currentNodeID = destination.id
        return destination
    }

    /// Record a failed execution: mark the edge, do **not** advance the
    /// current pointer. The planner can then select an alternate edge.
    public func recordFailure(edgeID: String, latencyMs: Int = 0, cost: Double = 0) {
        lock.lock()
        defer { lock.unlock() }

        if let edge = edges[edgeID] {
            edge.recordFailure(latencyMs: latencyMs, cost: cost)
        }
    }

    // MARK: - Merge / Prune Helpers

    private func findMergeCandidate(for node: TaskNode) -> TaskNode? {
        for existing in nodes.values {
            if existing.abstractState == node.abstractState
                && existing.planningStateID == node.planningStateID {
                return existing
            }
        }
        return nil
    }

    private func pruneOldestNodes() {
        let sorted = nodes.values.sorted { $0.timestamp < $1.timestamp }
        let toRemove = sorted.prefix(max(1, nodes.count / 10))
        for node in toRemove {
            guard node.id != currentNodeID else { continue }
            removeNode(node.id)
        }
    }

    private func pruneWeakestEdges(from nodeID: String) {
        let fromEdges = edges.values
            .filter { $0.fromNodeID == nodeID }
            .sorted { $0.successProbability < $1.successProbability }
        let toRemove = fromEdges.prefix(max(1, fromEdges.count / 4))
        for edge in toRemove {
            edges.removeValue(forKey: edge.id)
        }
    }

    private func removeNode(_ nodeID: String) {
        nodes.removeValue(forKey: nodeID)
        // Remove orphaned edges
        let orphaned = edges.values.filter {
            $0.fromNodeID == nodeID || $0.toNodeID == nodeID
        }
        for edge in orphaned {
            edges.removeValue(forKey: edge.id)
        }
    }
}
