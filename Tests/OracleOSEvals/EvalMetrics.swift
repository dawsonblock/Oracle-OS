import Foundation

struct EvalMetrics {
    let successRate: Double
    let firstPassSuccessRate: Double
    let averageSteps: Double
    let recoverySuccessRate: Double
    let graphReuseRatio: Double
    let workflowReuseRatio: Double
    let ambiguityFailureCount: Int
    let patchSelectionSuccessRate: Double
    let recoveryReuseRatio: Double
    let plannerReasoningRatio: Double

    init(
        successRate: Double,
        firstPassSuccessRate: Double,
        averageSteps: Double,
        recoverySuccessRate: Double,
        graphReuseRatio: Double,
        workflowReuseRatio: Double,
        ambiguityFailureCount: Int,
        patchSelectionSuccessRate: Double,
        recoveryReuseRatio: Double = 0,
        plannerReasoningRatio: Double = 0
    ) {
        self.successRate = successRate
        self.firstPassSuccessRate = firstPassSuccessRate
        self.averageSteps = averageSteps
        self.recoverySuccessRate = recoverySuccessRate
        self.graphReuseRatio = graphReuseRatio
        self.workflowReuseRatio = workflowReuseRatio
        self.ambiguityFailureCount = ambiguityFailureCount
        self.patchSelectionSuccessRate = patchSelectionSuccessRate
        self.recoveryReuseRatio = recoveryReuseRatio
        self.plannerReasoningRatio = plannerReasoningRatio
    }

    var comparisonFields: [(String, String)] {
        [
            ("success_rate", percent(successRate)),
            ("first_pass_success_rate", percent(firstPassSuccessRate)),
            ("average_steps", String(format: "%.2f", averageSteps)),
            ("recovery_success_rate", percent(recoverySuccessRate)),
            ("graph_reuse_ratio", percent(graphReuseRatio)),
            ("workflow_reuse_ratio", percent(workflowReuseRatio)),
            ("ambiguity_failure_count", "\(ambiguityFailureCount)"),
            ("patch_selection_success_rate", percent(patchSelectionSuccessRate)),
            ("recovery_reuse_ratio", percent(recoveryReuseRatio)),
            ("planner_reasoning_ratio", percent(plannerReasoningRatio)),
        ]
    }

    func summary(taskName: String) -> String {
        let fields = comparisonFields
            .map { "\($0.0)=\($0.1)" }
            .joined(separator: " ")
        return "\(taskName): \(fields)"
    }

    func regressions(against baseline: EvalMetrics, thresholds: RegressionThresholds = RegressionThresholds()) -> [String] {
        var regressions: [String] = []
        if successRate < baseline.successRate - thresholds.successRateDrop {
            regressions.append("success_rate regressed from \(percent(baseline.successRate)) to \(percent(successRate))")
        }
        if recoverySuccessRate < baseline.recoverySuccessRate - thresholds.recoveryRateDrop {
            regressions.append("recovery_success_rate regressed from \(percent(baseline.recoverySuccessRate)) to \(percent(recoverySuccessRate))")
        }
        if workflowReuseRatio < baseline.workflowReuseRatio - thresholds.workflowReuseDrop {
            regressions.append("workflow_reuse_ratio regressed from \(percent(baseline.workflowReuseRatio)) to \(percent(workflowReuseRatio))")
        }
        if ambiguityFailureCount > baseline.ambiguityFailureCount + thresholds.ambiguityFailureIncrease {
            regressions.append("ambiguity_failure_count increased from \(baseline.ambiguityFailureCount) to \(ambiguityFailureCount)")
        }
        return regressions
    }

    private func percent(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}

struct RegressionThresholds {
    let successRateDrop: Double
    let recoveryRateDrop: Double
    let workflowReuseDrop: Double
    let ambiguityFailureIncrease: Int

    init(
        successRateDrop: Double = 0.05,
        recoveryRateDrop: Double = 0.1,
        workflowReuseDrop: Double = 0.1,
        ambiguityFailureIncrease: Int = 2
    ) {
        self.successRateDrop = successRateDrop
        self.recoveryRateDrop = recoveryRateDrop
        self.workflowReuseDrop = workflowReuseDrop
        self.ambiguityFailureIncrease = ambiguityFailureIncrease
    }
}
