import Foundation

public final class OSPlanner: @unchecked Sendable {
    private let graphPlanner: GraphPlanner
    private let explorationPolicy: ExplorationPolicy

    public init(
        graphPlanner: GraphPlanner = GraphPlanner(),
        explorationPolicy: ExplorationPolicy = ExplorationPolicy()
    ) {
        self.graphPlanner = graphPlanner
        self.explorationPolicy = explorationPolicy
    }

    public func nextStep(
        goal: Goal,
        worldState: WorldState,
        graphStore: GraphStore
    ) -> PlannerDecision? {
        if let searchResult = graphPlanner.search(
            from: worldState.planningState,
            goal: goal,
            graphStore: graphStore
        ),
           let currentEdge = searchResult.edges.first,
           let contract = graphStore.actionContract(for: currentEdge.actionContractID)
        {
            return PlannerDecision(
                agentKind: .os,
                plannerFamily: .os,
                stepPhase: .operatingSystem,
                actionContract: contract,
                source: .stableGraph,
                pathEdgeIDs: searchResult.edges.map(\.edgeID),
                currentEdgeID: currentEdge.edgeID,
                semanticQuery: semanticQuery(for: contract, worldState: worldState),
                notes: searchResult.reachedGoal ? ["graph path reaches goal"] : ["graph path improves goal fit"]
            )
        }

        guard let fallback = explorationPolicy.choose(goal: goal, worldState: worldState) else {
            return nil
        }
        return PlannerDecision(
            agentKind: .os,
            skillName: fallback.skillName,
            plannerFamily: .os,
            stepPhase: .operatingSystem,
            actionContract: fallback.actionContract,
            source: fallback.source,
            pathEdgeIDs: fallback.pathEdgeIDs,
            currentEdgeID: fallback.currentEdgeID,
            semanticQuery: fallback.semanticQuery,
            notes: fallback.notes,
            recoveryTagged: fallback.recoveryTagged,
            recoveryStrategy: fallback.recoveryStrategy,
            recoverySource: fallback.recoverySource
        )
    }

    private func semanticQuery(
        for contract: ActionContract,
        worldState: WorldState
    ) -> ElementQuery? {
        guard contract.skillName == "click" || contract.skillName == "type" else {
            return nil
        }

        return ElementQuery(
            text: contract.targetLabel,
            role: contract.targetRole,
            editable: contract.skillName == "type",
            clickable: contract.skillName == "click",
            visibleOnly: true,
            app: worldState.observation.app
        )
    }
}
