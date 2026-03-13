import Foundation

public final class PlanGenerator: @unchecked Sendable {
    private let reasoningEngine: ReasoningEngine
    private let planEvaluator: PlanEvaluator
    private let operatorRegistry: OperatorRegistry

    public init(
        reasoningEngine: ReasoningEngine = ReasoningEngine(),
        planEvaluator: PlanEvaluator,
        operatorRegistry: OperatorRegistry = .shared
    ) {
        self.reasoningEngine = reasoningEngine
        self.planEvaluator = planEvaluator
        self.operatorRegistry = operatorRegistry
    }

    public func generate(
        state: ReasoningPlanningState,
        taskContext: TaskContext,
        goal: Goal,
        worldState: WorldState,
        graphStore: GraphStore,
        workflowIndex: WorkflowIndex,
        memoryStore: AppMemoryStore
    ) -> [PlanCandidate] {
        var allPlans: [PlanCandidate] = []

        // Source 1: Workflow-backed plans from promoted workflows
        let workflowPlans = workflowBacked(
            goal: goal,
            state: state,
            workflowIndex: workflowIndex
        )
        allPlans.append(contentsOf: workflowPlans)

        // Source 2: Graph-backed plans from stable edges
        let graphPlans = graphBacked(
            state: state,
            worldState: worldState,
            graphStore: graphStore
        )
        allPlans.append(contentsOf: graphPlans)

        // Source 3: Reasoning-generated plans using operator expansion
        let reasoningPlans = reasoningEngine.generatePlans(from: state)
        allPlans.append(contentsOf: reasoningPlans)

        let scored = planEvaluator.evaluate(
            plans: allPlans,
            taskContext: taskContext,
            goal: goal,
            worldState: worldState,
            graphStore: graphStore,
            workflowIndex: workflowIndex,
            memoryStore: memoryStore
        )
        return scored
    }

    public func bestPlan(
        state: ReasoningPlanningState,
        taskContext: TaskContext,
        goal: Goal,
        worldState: WorldState,
        graphStore: GraphStore,
        workflowIndex: WorkflowIndex,
        memoryStore: AppMemoryStore,
        minimumScore: Double = 0.6
    ) -> PlanCandidate? {
        let scored = generate(
            state: state,
            taskContext: taskContext,
            goal: goal,
            worldState: worldState,
            graphStore: graphStore,
            workflowIndex: workflowIndex,
            memoryStore: memoryStore
        )
        return planEvaluator.chooseBestPlan(scored, minimumScore: minimumScore)
    }

    // MARK: - Multi-source plan generation

    private func workflowBacked(
        goal: Goal,
        state: ReasoningPlanningState,
        workflowIndex: WorkflowIndex
    ) -> [PlanCandidate] {
        let matches = workflowIndex.matching(goal: goal.description)
        return matches.compactMap { plan -> PlanCandidate? in
            let ops = plan.steps.compactMap { step -> Operator? in
                operatorRegistry.available(for: state)
                    .first { $0.actionContract(for: state, goal: goal)?.skillName == step.actionContract.skillName }
            }
            guard !ops.isEmpty else { return nil }
            var projected = state
            for op in ops { projected = op.effect(projected) }
            return PlanCandidate(
                operators: ops,
                projectedState: projected,
                reasons: ["workflow-backed plan from \(plan.goalPattern)"],
                sourceType: .workflow
            )
        }
    }

    private func graphBacked(
        state: ReasoningPlanningState,
        worldState: WorldState,
        graphStore: GraphStore
    ) -> [PlanCandidate] {
        let stableEdges = graphStore.outgoingStableEdges(from: worldState.planningState.id)
        return stableEdges.compactMap { edge -> PlanCandidate? in
            guard let contract = graphStore.actionContract(for: edge.actionContractID) else {
                return nil
            }
            let matchingOp = operatorRegistry.available(for: state)
                .first { op in
                    op.actionContract(for: state, goal: Goal(description: ""))?.skillName == contract.skillName
                }
            guard let op = matchingOp else { return nil }
            let projected = op.effect(state)
            return PlanCandidate(
                operators: [op],
                projectedState: projected,
                reasons: ["graph-backed plan from stable edge \(edge.actionContractID)"],
                sourceType: .stableGraph
            )
        }
    }
}
