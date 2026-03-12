import Foundation

public enum RecipeValidator {
    public static func validate(
        recipe: Recipe,
        state _: WorldState
    ) -> Bool {
        guard !recipe.steps.isEmpty else {
            return false
        }

        let declaredParameters = Set(recipe.params?.map(\.key) ?? [])
        for step in recipe.steps {
            guard !step.action.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return false
            }
            let referencedParameters = Set(step.params?.map(\.key) ?? [])
            guard referencedParameters.isSubset(of: declaredParameters) else {
                return false
            }
            if let timeout = step.waitAfter?.timeout, timeout < 0 {
                return false
            }
        }

        return true
    }

    public static func validateWorkflow(
        _ plan: WorkflowPlan,
        against segments: [TraceSegment],
        replayValidator: WorkflowReplayValidator = WorkflowReplayValidator(),
        promotionPolicy: WorkflowPromotionPolicy = WorkflowPromotionPolicy(),
        decayPolicy: WorkflowDecayPolicy = WorkflowDecayPolicy()
    ) -> Bool {
        guard !plan.steps.isEmpty else {
            return false
        }
        guard decayPolicy.isStale(plan) == false else {
            return false
        }

        let replayScore = replayValidator.validate(plan: plan, against: segments)
        let candidate = WorkflowPlan(
            id: plan.id,
            agentKind: plan.agentKind,
            goalPattern: plan.goalPattern,
            steps: plan.steps,
            parameterSlots: plan.parameterSlots,
            successRate: plan.successRate,
            sourceTraceRefs: plan.sourceTraceRefs,
            sourceGraphEdgeRefs: plan.sourceGraphEdgeRefs,
            evidenceTiers: plan.evidenceTiers,
            repeatedTraceSegmentCount: plan.repeatedTraceSegmentCount,
            replayValidationSuccess: replayScore,
            promotionStatus: plan.promotionStatus,
            lastValidatedAt: plan.lastValidatedAt,
            lastSucceededAt: plan.lastSucceededAt
        )
        return promotionPolicy.shouldPromote(candidate)
    }
}
