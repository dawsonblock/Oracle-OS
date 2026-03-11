import Foundation

public final class WorkflowIndex: @unchecked Sendable {
    private var plans: [String: WorkflowPlan]

    public init(plans: [String: WorkflowPlan] = [:]) {
        self.plans = plans
    }

    public func add(_ plan: WorkflowPlan) {
        plans[plan.id] = plan
    }

    public func remove(id: String) {
        plans.removeValue(forKey: id)
    }

    public func allPlans() -> [WorkflowPlan] {
        plans.values.sorted { lhs, rhs in
            if lhs.successRate == rhs.successRate {
                return lhs.goalPattern < rhs.goalPattern
            }
            return lhs.successRate > rhs.successRate
        }
    }

    public func promotedPlans(for agentKind: AgentKind? = nil) -> [WorkflowPlan] {
        allPlans().filter { plan in
            plan.promotionStatus == .promoted && (
                agentKind == nil
                    || agentKind == .mixed
                    || plan.agentKind == agentKind
            )
        }
    }
}
