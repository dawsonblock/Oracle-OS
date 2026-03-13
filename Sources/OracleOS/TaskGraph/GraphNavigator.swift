import Foundation

/// Expands candidate paths from the current task-graph node.
///
/// ``GraphNavigator`` is the component the planner calls to obtain ranked
/// future paths. It combines existing edges with freshly generated
/// candidate edges, then expands them to a bounded depth.
public struct GraphNavigator: Sendable {
    public let maxDepth: Int
    public let maxBranching: Int

    public init(maxDepth: Int = 3, maxBranching: Int = 5) {
        self.maxDepth = maxDepth
        self.maxBranching = maxBranching
    }

    /// A single scored path through the task graph.
    public struct ScoredPath: Sendable {
        public let edges: [TaskEdge]
        public let nodes: [TaskNode]
        public let cumulativeScore: Double
        public let terminalState: AbstractTaskState?
    }

    /// Expand outgoing edges from the current node and return scored paths
    /// up to ``maxDepth`` hops.
    public func expand(
        from nodeID: String,
        in graph: TaskGraph,
        scorer: GraphScorer,
        goal: Goal? = nil
    ) -> [ScoredPath] {
        guard let startNode = graph.node(for: nodeID) else { return [] }

        var results: [ScoredPath] = []
        var visited: Set<String> = [nodeID]

        expandRecursive(
            currentNode: startNode,
            currentEdges: [],
            currentNodes: [startNode],
            cumulativeScore: 0,
            depth: 0,
            visited: &visited,
            graph: graph,
            scorer: scorer,
            goal: goal,
            results: &results
        )

        return results.sorted { $0.cumulativeScore > $1.cumulativeScore }
    }

    /// Return the best single next edge from the current node.
    public func bestNextEdge(
        from nodeID: String,
        in graph: TaskGraph,
        scorer: GraphScorer,
        goal: Goal? = nil
    ) -> TaskEdge? {
        let paths = expand(from: nodeID, in: graph, scorer: scorer, goal: goal)
        return paths.first?.edges.first
    }

    // MARK: - Private

    private func expandRecursive(
        currentNode: TaskNode,
        currentEdges: [TaskEdge],
        currentNodes: [TaskNode],
        cumulativeScore: Double,
        depth: Int,
        visited: inout Set<String>,
        graph: TaskGraph,
        scorer: GraphScorer,
        goal: Goal?,
        results: inout [ScoredPath]
    ) {
        // Record the path ending here when depth > 0
        if !currentEdges.isEmpty {
            results.append(ScoredPath(
                edges: currentEdges,
                nodes: currentNodes,
                cumulativeScore: cumulativeScore,
                terminalState: currentNode.abstractState
            ))
        }

        guard depth < maxDepth else { return }

        let outgoing = graph.viableEdges(from: currentNode.id)
            .sorted { scorer.scoreEdge($0) > scorer.scoreEdge($1) }
            .prefix(maxBranching)

        for edge in outgoing {
            let toID = edge.toNodeID
            guard !visited.contains(toID) else { continue }
            guard let toNode = graph.node(for: toID) else { continue }

            let edgeScore = scorer.scoreEdge(edge, goalState: goal.flatMap {
                GraphScorer.goalAbstractState(from: $0)
            }, targetState: toNode.abstractState)

            visited.insert(toID)
            expandRecursive(
                currentNode: toNode,
                currentEdges: currentEdges + [edge],
                currentNodes: currentNodes + [toNode],
                cumulativeScore: cumulativeScore + edgeScore,
                depth: depth + 1,
                visited: &visited,
                graph: graph,
                scorer: scorer,
                goal: goal,
                results: &results
            )
            visited.remove(toID)
        }
    }
}
