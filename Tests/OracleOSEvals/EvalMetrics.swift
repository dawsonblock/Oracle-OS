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
        ]
    }

    func summary(taskName: String) -> String {
        let fields = comparisonFields
            .map { "\($0.0)=\($0.1)" }
            .joined(separator: " ")
        return "\(taskName): \(fields)"
    }

    private func percent(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}
