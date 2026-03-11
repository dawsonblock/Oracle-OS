import Foundation

public final class OSPlanner: @unchecked Sendable {
    private let graphPlanner: GraphPlanner
    private let explorationPolicy: ExplorationPolicy
    private let workflowIndex: WorkflowIndex
    private let workflowRetriever: WorkflowRetriever
    private let workflowExecutor: WorkflowExecutor

    public init(
        graphPlanner: GraphPlanner = GraphPlanner(),
        explorationPolicy: ExplorationPolicy = ExplorationPolicy(),
        workflowIndex: WorkflowIndex = WorkflowIndex(),
        workflowRetriever: WorkflowRetriever = WorkflowRetriever(),
        workflowExecutor: WorkflowExecutor = WorkflowExecutor()
    ) {
        self.graphPlanner = graphPlanner
        self.explorationPolicy = explorationPolicy
        self.workflowIndex = workflowIndex
        self.workflowRetriever = workflowRetriever
        self.workflowExecutor = workflowExecutor
    }

    public func nextStep(
        taskContext: TaskContext,
        worldState: WorldState,
        graphStore: GraphStore,
        memoryStore: AppMemoryStore
    ) -> PlannerDecision? {
        if let workflowMatch = workflowRetriever.retrieve(
            goal: taskContext.goal,
            taskContext: taskContext,
            worldState: worldState,
            workflowIndex: workflowIndex
        ) {
            return workflowExecutor.nextDecision(
                match: workflowMatch,
                plannerFamily: .os,
                sourceNotes: ["workflow-first planner hit"]
            )
        }

        let graphGoal = Goal(
            description: taskContext.goal.description,
            targetApp: taskContext.goal.targetApp,
            targetDomain: taskContext.goal.targetDomain,
            targetTaskPhase: taskContext.goal.targetTaskPhase,
            workspaceRoot: taskContext.goal.workspaceRoot,
            preferredAgentKind: .os
        )
        if let searchResult = graphPlanner.search(
            from: worldState.planningState,
            goal: graphGoal,
            graphStore: graphStore,
            memoryStore: memoryStore,
            worldState: worldState
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

        guard let fallback = explorationPolicy.choose(goal: taskContext.goal, worldState: worldState) else {
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
        guard contract.skillName == "click" || contract.skillName == "type" || contract.skillName == "fill_form" || contract.skillName == "read_file" else {
            return nil
        }

        return ElementQuery(
            text: contract.targetLabel,
            role: contract.targetRole,
            editable: contract.skillName == "type" || contract.skillName == "fill_form",
            clickable: contract.skillName == "click" || contract.skillName == "read_file",
            visibleOnly: true,
            app: worldState.observation.app
        )
    }
}
