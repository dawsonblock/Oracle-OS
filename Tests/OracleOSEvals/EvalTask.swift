import Foundation
@testable import OracleOS

enum EvalTaskFamily: String {
    case operatorTask = "operator"
    case codingTask = "coding"
    case hybridTask = "hybrid"
}

@MainActor
struct EvalTask {
    let name: String
    let family: EvalTaskFamily
    let runs: Int
    let executeRun: (Int) async -> EvalRunSnapshot
}

struct EvalRunSnapshot {
    let outcome: LoopOutcome
    let usedStableGraph: Bool
    let usedWorkflow: Bool
    let recoveryAttempted: Bool
    let patchSelectionSucceeded: Bool

    init(
        outcome: LoopOutcome,
        usedStableGraph: Bool,
        usedWorkflow: Bool = false,
        recoveryAttempted: Bool? = nil,
        patchSelectionSucceeded: Bool = false
    ) {
        self.outcome = outcome
        self.usedStableGraph = usedStableGraph
        self.usedWorkflow = usedWorkflow
        self.recoveryAttempted = recoveryAttempted ?? (outcome.recoveries > 0)
        self.patchSelectionSucceeded = patchSelectionSucceeded
    }

    var recoverySucceeded: Bool {
        recoveryAttempted && outcome.reason == .goalAchieved
    }

    var firstPassSucceeded: Bool {
        outcome.reason == .goalAchieved && !recoveryAttempted
    }
}
