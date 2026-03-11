import Foundation

enum EvalRunner {
    @MainActor
    static func run(task: EvalTask) async -> EvalMetrics {
        var successes = 0
        var totalSteps = 0
        var recoveries = 0
        var graphReuseCount = 0
        var ambiguityFailures = 0
        var patchSelections = 0

        for index in 0..<task.runs {
            let snapshot = await task.executeRun(index)
            if snapshot.outcome.reason == .goalAchieved {
                successes += 1
            }
            totalSteps += snapshot.outcome.steps
            recoveries += snapshot.outcome.recoveries
            if snapshot.usedStableGraph {
                graphReuseCount += 1
            }
            if snapshot.outcome.lastFailure == .elementAmbiguous {
                ambiguityFailures += 1
            }
            if snapshot.patchSelectionSucceeded {
                patchSelections += 1
            }
        }

        return EvalMetrics(
            successRate: Double(successes) / Double(max(task.runs, 1)),
            averageSteps: Double(totalSteps) / Double(max(task.runs, 1)),
            recoveryRate: Double(recoveries) / Double(max(task.runs, 1)),
            graphReuseRatio: Double(graphReuseCount) / Double(max(task.runs, 1)),
            ambiguityFailureCount: ambiguityFailures,
            patchSelectionSuccessRate: Double(patchSelections) / Double(max(task.runs, 1))
        )
    }
}
