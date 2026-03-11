import Foundation

public struct GraphSearchResult: Sendable {
    public let edges: [EdgeTransition]
    public let reachedGoal: Bool
    public let exploredEdgeIDs: [String]

    public init(edges: [EdgeTransition], reachedGoal: Bool, exploredEdgeIDs: [String]) {
        self.edges = edges
        self.reachedGoal = reachedGoal
        self.exploredEdgeIDs = exploredEdgeIDs
    }
}

public final class GraphPlanner: @unchecked Sendable {
    private struct Path {
        let currentStateID: PlanningStateID
        let edges: [EdgeTransition]
        let cumulativeCost: Double
        let goalScore: Double
    }

    public let maxDepth: Int
    public let beamWidth: Int

    public init(maxDepth: Int = 4, beamWidth: Int = 5) {
        self.maxDepth = maxDepth
        self.beamWidth = beamWidth
    }

    public func search(
        from startState: PlanningState,
        goal: Goal,
        graphStore: GraphStore
    ) -> GraphSearchResult? {
        var exploredEdgeIDs: [String] = []
        var frontier: [Path] = [
            Path(
                currentStateID: startState.id,
                edges: [],
                cumulativeCost: 0,
                goalScore: Planner.goalMatchScore(state: startState, goal: goal)
            ),
        ]
        var bestPath: Path?

        for _ in 0..<maxDepth {
            var nextFrontier: [Path] = []

            for path in frontier {
                if let currentState = graphStore.planningState(for: path.currentStateID),
                   Planner.goalMatchScore(state: currentState, goal: goal) >= 1 {
                    return GraphSearchResult(
                        edges: path.edges,
                        reachedGoal: true,
                        exploredEdgeIDs: exploredEdgeIDs
                    )
                }

                let outgoing = graphStore.outgoingStableEdges(from: path.currentStateID)
                for edge in outgoing.prefix(beamWidth) {
                    exploredEdgeIDs.append(edge.edgeID)
                    let state = graphStore.planningState(for: edge.toPlanningStateID)
                    let goalScore = state.map { Planner.goalMatchScore(state: $0, goal: goal) } ?? 0
                    let candidate = Path(
                        currentStateID: edge.toPlanningStateID,
                        edges: path.edges + [edge],
                        cumulativeCost: path.cumulativeCost + edge.cost,
                        goalScore: goalScore
                    )
                    if bestPath == nil || compare(lhs: candidate, rhs: bestPath!) {
                        bestPath = candidate
                    }
                    nextFrontier.append(candidate)
                }
            }

            frontier = nextFrontier
                .sorted { lhs, rhs in
                    if lhs.goalScore == rhs.goalScore {
                        if lhs.cumulativeCost == rhs.cumulativeCost {
                            let lhsConfidence = lhs.edges.last?.confidence ?? 0
                            let rhsConfidence = rhs.edges.last?.confidence ?? 0
                            return lhsConfidence > rhsConfidence
                        }
                        return lhs.cumulativeCost < rhs.cumulativeCost
                    }
                    return lhs.goalScore > rhs.goalScore
                }
                .prefix(beamWidth)
                .map { $0 }

            if frontier.isEmpty {
                break
            }
        }

        guard let bestPath, !bestPath.edges.isEmpty else {
            return nil
        }

        return GraphSearchResult(
            edges: bestPath.edges,
            reachedGoal: false,
            exploredEdgeIDs: exploredEdgeIDs
        )
    }

    private func compare(lhs: Path, rhs: Path) -> Bool {
        if lhs.goalScore == rhs.goalScore {
            return lhs.cumulativeCost < rhs.cumulativeCost
        }
        return lhs.goalScore > rhs.goalScore
    }
}
