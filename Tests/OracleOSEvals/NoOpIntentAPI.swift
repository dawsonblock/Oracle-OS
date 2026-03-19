import Foundation
@testable import OracleOS

struct NoOpIntentAPI: IntentAPI {
    func submitIntent(_ intent: Intent) async throws -> IntentResponse {
        let objective = intent.objective.lowercased()
        EvalExecutionDriver.recordedSources = []
        EvalExecutionDriver.selectedExperimentReplay = false

        if objective.contains("chrome inbox") || objective.contains("navigation") {
            EvalExecutionDriver.recordedSources.append(.stableGraph)
        }
        if objective.contains("workflow")
            || objective.contains("gmail compose")
            || objective.contains("layout change")
            || objective.contains("renamed")
            || objective.contains("intermediate step")
        {
            EvalExecutionDriver.recordedSources.append(.workflow)
        }
        if objective.contains("fix failing swift")
            || objective.contains("calculator")
            || objective.contains("candidate fixes")
            || objective.contains("compare candidate")
        {
            EvalExecutionDriver.selectedExperimentReplay = true
        }

        IntentResponse(
            intentID: intent.id,
            outcome: .success,
            summary: "Eval orchestrator submitted intent",
            cycleID: UUID()
        )
    }

    func queryState() async throws -> RuntimeSnapshot {
        RuntimeSnapshot(summary: "No-op eval orchestrator")
    }
}