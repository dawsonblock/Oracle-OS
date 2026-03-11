import Foundation

public struct WorkflowMatch: Sendable {
    public let plan: WorkflowPlan
    public let stepIndex: Int
    public let score: Double

    public init(plan: WorkflowPlan, stepIndex: Int, score: Double) {
        self.plan = plan
        self.stepIndex = stepIndex
        self.score = score
    }
}

public struct WorkflowRetriever: Sendable {
    public init() {}

    public func retrieve(
        goal: Goal,
        taskContext: TaskContext,
        worldState: WorldState,
        workflowIndex: WorkflowIndex
    ) -> WorkflowMatch? {
        workflowIndex.promotedPlans(for: taskContext.agentKind)
            .compactMap { plan in
                guard let stepIndex = matchingStepIndex(plan: plan, planningStateID: worldState.planningState.id.rawValue) else {
                    return nil
                }
                let score = planScore(plan: plan, goal: goal, stepIndex: stepIndex)
                guard score > 0 else {
                    return nil
                }
                return WorkflowMatch(plan: plan, stepIndex: stepIndex, score: score)
            }
            .sorted { lhs, rhs in
                if lhs.score == rhs.score {
                    return lhs.plan.successRate > rhs.plan.successRate
                }
                return lhs.score > rhs.score
            }
            .first
    }

    private func matchingStepIndex(plan: WorkflowPlan, planningStateID: String) -> Int? {
        if let index = plan.steps.firstIndex(where: { $0.fromPlanningStateID == planningStateID }) {
            return index
        }
        if let firstIndex = plan.steps.firstIndex(where: { $0.fromPlanningStateID == nil }) {
            return firstIndex
        }
        return nil
    }

    private func planScore(plan: WorkflowPlan, goal: Goal, stepIndex: Int) -> Double {
        let normalizedGoal = goal.description.lowercased()
        let normalizedPattern = plan.goalPattern.lowercased()
        let tokens = Set(normalizedPattern.split(separator: " ").map(String.init))
        let overlap = tokens.isEmpty ? 0 : tokens.filter { normalizedGoal.contains($0) }.count
        let matchRatio = tokens.isEmpty ? 0 : Double(overlap) / Double(tokens.count)
        let stepPenalty = Double(stepIndex) * 0.05
        return max(0, (0.6 * matchRatio) + (0.4 * plan.successRate) - stepPenalty)
    }
}
