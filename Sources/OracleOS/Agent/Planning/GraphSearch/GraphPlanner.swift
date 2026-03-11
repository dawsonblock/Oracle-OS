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
}
