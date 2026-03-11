import Foundation
@testable import OracleOS

@MainActor
struct EvalTask {
    let name: String
    let runs: Int
    let executeRun: (Int) async -> EvalRunSnapshot
}

struct EvalRunSnapshot {
    let outcome: LoopOutcome
    let usedStableGraph: Bool
    let patchSelectionSucceeded: Bool

    init(
        outcome: LoopOutcome,
        usedStableGraph: Bool,
        patchSelectionSucceeded: Bool = false
    ) {
        self.outcome = outcome
        self.usedStableGraph = usedStableGraph
        self.patchSelectionSucceeded = patchSelectionSucceeded
    }
}
