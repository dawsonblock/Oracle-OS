import Foundation

struct AgentLoopRunState {
    var latestWorldState: WorldState?
    var lastAction: ActionIntent?
    var lastDecisionContract: ActionContract?
    var diagnostics = LoopDiagnostics.empty
    var budgetState = LoopBudgetState()
    var recentFailureCount: Int = 0
    var consecutiveStallCount: Int = 0
}
