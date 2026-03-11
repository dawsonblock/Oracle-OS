import Foundation

public struct PathSearch: Sendable {
    private struct ScoredPath {
        let stateID: PlanningStateID
        let edges: [EdgeTransition]
        let score: Double
    }

    public let maxDepth: Int
    public let beamWidth: Int
    private let scorer: PathScorer

    public init(
        maxDepth: Int = 4,
        beamWidth: Int = 5,
        scorer: PathScorer = PathScorer()
    ) {
        self.maxDepth = maxDepth
        self.beamWidth = beamWidth
        self.scorer = scorer
    }

    public func search(
        from startState: PlanningState,
        goal: Goal,
        graphStore: GraphStore,
        memoryBiasProvider: (EdgeTransition, ActionContract?) -> Double = { _, _ in 0 }
    ) -> GraphSearchResult? {
        var exploredEdgeIDs: [String] = []
        var frontier: [ScoredPath] = [ScoredPath(stateID: startState.id, edges: [], score: 0)]
        var bestPath: ScoredPath?

        for _ in 0..<maxDepth {
            var nextFrontier: [ScoredPath] = []

            for path in frontier {
                if let currentState = graphStore.planningState(for: path.stateID),
                   Planner.goalMatchScore(state: currentState, goal: goal) >= 1 {
                    return GraphSearchResult(
                        edges: path.edges,
                        reachedGoal: true,
                        exploredEdgeIDs: exploredEdgeIDs
                    )
                }

                let outgoing = graphStore.outgoingStableEdges(from: path.stateID)
                    .filter { edge in
                        guard let preferredAgentKind = goal.preferredAgentKind else {
                            return true
                        }
                        return edge.agentKind == preferredAgentKind
                    }

                for edge in outgoing {
                    exploredEdgeIDs.append(edge.edgeID)
                    let contract = graphStore.actionContract(for: edge.actionContractID)
                    let memoryBias = memoryBiasProvider(edge, contract)
                    let edgeScore = scorer.score(
                        edge: edge,
                        actionContract: contract,
                        goal: goal,
                        memoryBias: memoryBias
                    )
                    let candidate = ScoredPath(
                        stateID: edge.toPlanningStateID,
                        edges: path.edges + [edge],
                        score: path.score + edgeScore
                    )
                    nextFrontier.append(candidate)
                    if bestPath == nil || candidate.score > bestPath!.score {
                        bestPath = candidate
                    }
                }
            }

            frontier = nextFrontier
                .sorted { lhs, rhs in
                    if lhs.score == rhs.score {
                        return lhs.edges.count < rhs.edges.count
                    }
                    return lhs.score > rhs.score
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
}
