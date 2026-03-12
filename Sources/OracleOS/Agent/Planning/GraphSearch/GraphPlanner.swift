import Foundation

public struct GraphSearchResult: Sendable {
    public let edges: [EdgeTransition]
    public let reachedGoal: Bool
    public let exploredEdgeIDs: [String]
    public let diagnostics: GraphSearchDiagnostics

    public init(
        edges: [EdgeTransition],
        reachedGoal: Bool,
        exploredEdgeIDs: [String],
        diagnostics: GraphSearchDiagnostics
    ) {
        self.edges = edges
        self.reachedGoal = reachedGoal
        self.exploredEdgeIDs = exploredEdgeIDs
        self.diagnostics = diagnostics
    }
}

public final class GraphPlanner: @unchecked Sendable {
    public let maxDepth: Int
    public let beamWidth: Int
    private let pathSearch: PathSearch

    public init(maxDepth: Int = 4, beamWidth: Int = 5) {
        self.maxDepth = maxDepth
        self.beamWidth = beamWidth
        self.pathSearch = PathSearch(maxDepth: maxDepth, beamWidth: beamWidth)
    }

    public func search(
        from startState: PlanningState,
        goal: Goal,
        graphStore: GraphStore,
        memoryStore: AppMemoryStore? = nil,
        worldState: WorldState? = nil
    ) -> GraphSearchResult? {
        pathSearch.search(
            from: startState,
            goal: goal,
            graphStore: graphStore
        ) { edge, actionContract in
            if let commandCategory = edge.commandCategory,
               let workspaceRoot = worldState?.repositorySnapshot?.workspaceRoot,
               let memoryStore
            {
                return MemoryQuery.commandBias(
                    category: commandCategory,
                    workspaceRoot: workspaceRoot,
                    store: memoryStore
                )
            }

            guard let memoryStore else {
                return 0
            }
            return MemoryQuery.rankingBias(
                label: actionContract?.targetLabel,
                app: worldState?.observation.app,
                store: memoryStore
            )
        }
    }

    public func bestCandidateEdge(
        from startState: PlanningState,
        goal: Goal,
        graphStore: GraphStore,
        memoryStore: AppMemoryStore? = nil,
        worldState: WorldState? = nil
    ) -> GraphEdgeSelection? {
        let candidateEdges = graphStore.outgoingCandidateEdges(from: startState.id)
            .filter { edge in
                guard let preferredAgentKind = goal.preferredAgentKind else {
                    return true
                }
                return edge.agentKind == preferredAgentKind
            }

        guard !candidateEdges.isEmpty else {
            return nil
        }

        let scored = candidateEdges.map { edge -> GraphEdgeSelection in
            let actionContract = graphStore.actionContract(for: edge.actionContractID)
            let memoryBias: Double
            if let commandCategory = edge.commandCategory,
               let workspaceRoot = worldState?.repositorySnapshot?.workspaceRoot,
               let memoryStore
            {
                memoryBias = MemoryQuery.commandBias(
                    category: commandCategory,
                    workspaceRoot: workspaceRoot,
                    store: memoryStore
                )
            } else if let memoryStore {
                memoryBias = MemoryQuery.rankingBias(
                    label: actionContract?.targetLabel,
                    app: worldState?.observation.app,
                    store: memoryStore
                )
            } else {
                memoryBias = 0
            }

            return GraphEdgeSelection(
                edge: edge,
                actionContract: actionContract,
                source: .candidateGraph,
                score: PathScorer().score(
                    edge: edge,
                    actionContract: actionContract,
                    goal: goal,
                    memoryBias: memoryBias
                ),
                diagnostics: GraphSearchDiagnostics(
                    exploredStateIDs: [startState.id.rawValue],
                    exploredEdgeIDs: candidateEdges.map(\.edgeID),
                    chosenPathEdgeIDs: [edge.edgeID]
                )
            )
        }
        .sorted { lhs, rhs in
            if lhs.score == rhs.score {
                return lhs.edge.cost < rhs.edge.cost
            }
            return lhs.score > rhs.score
        }

        guard let best = scored.first else {
            return nil
        }

        let rejected = scored.dropFirst().map(\.edge.edgeID)
        return GraphEdgeSelection(
            edge: best.edge,
            actionContract: best.actionContract,
            source: best.source,
            score: best.score,
            diagnostics: GraphSearchDiagnostics(
                exploredStateIDs: best.diagnostics.exploredStateIDs,
                exploredEdgeIDs: best.diagnostics.exploredEdgeIDs,
                chosenPathEdgeIDs: best.diagnostics.chosenPathEdgeIDs,
                rejectedEdgeIDs: rejected
            )
        )
    }
}
