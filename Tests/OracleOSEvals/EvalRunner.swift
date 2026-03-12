import Foundation

enum EvalRunner {
    @MainActor
    static func run(task: EvalTask) async -> EvalReport {
        var successes = 0
        var firstPassSuccesses = 0
        var totalSteps = 0
        var recoveryAttempts = 0
        var successfulRecoveries = 0
        var graphReuseCount = 0
        var workflowReuseCount = 0
        var ambiguityFailures = 0
        var patchSelections = 0
        var recoveryReuseCount = 0
        var plannerReasoningCount = 0

        for index in 0..<task.runs {
            let snapshot = await task.executeRun(index)
            if snapshot.outcome.reason == .goalAchieved {
                successes += 1
            }
            if snapshot.firstPassSucceeded {
                firstPassSuccesses += 1
            }
            totalSteps += snapshot.outcome.steps
            if snapshot.recoveryAttempted {
                recoveryAttempts += 1
            }
            if snapshot.recoverySucceeded {
                successfulRecoveries += 1
            }
            if snapshot.usedStableGraph {
                graphReuseCount += 1
            }
            if snapshot.usedWorkflow {
                workflowReuseCount += 1
            }
            if snapshot.outcome.lastFailure == .elementAmbiguous {
                ambiguityFailures += 1
            }
            if snapshot.patchSelectionSucceeded {
                patchSelections += 1
            }
            if snapshot.recoveryReused {
                recoveryReuseCount += 1
            }
            if snapshot.usedPlannerReasoning {
                plannerReasoningCount += 1
            }
        }

        let runs = max(task.runs, 1)
        let metrics = EvalMetrics(
            successRate: Double(successes) / Double(runs),
            firstPassSuccessRate: Double(firstPassSuccesses) / Double(runs),
            averageSteps: Double(totalSteps) / Double(runs),
            recoverySuccessRate: recoveryAttempts == 0 ? 0 : Double(successfulRecoveries) / Double(recoveryAttempts),
            graphReuseRatio: Double(graphReuseCount) / Double(runs),
            workflowReuseRatio: Double(workflowReuseCount) / Double(runs),
            ambiguityFailureCount: ambiguityFailures,
            patchSelectionSuccessRate: Double(patchSelections) / Double(runs),
            recoveryReuseRatio: Double(recoveryReuseCount) / Double(runs),
            plannerReasoningRatio: Double(plannerReasoningCount) / Double(runs)
        )
        return EvalReport(taskName: task.name, family: task.family, runs: task.runs, metrics: metrics)
    }
}
