import Foundation

public final class PlanGenerator: @unchecked Sendable {
    private let reasoningEngine: ReasoningEngine
    private let planEvaluator: PlanEvaluator

    public init(
        reasoningEngine: ReasoningEngine = ReasoningEngine(),
        planEvaluator: PlanEvaluator
    ) {
        self.reasoningEngine = reasoningEngine
        self.planEvaluator = planEvaluator
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
        let rawPlans = reasoningEngine.generatePlans(from: state)
        let scored = planEvaluator.evaluate(
            plans: rawPlans,
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
}
