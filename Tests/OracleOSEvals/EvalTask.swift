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
}
