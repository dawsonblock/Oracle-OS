import Foundation

@MainActor
extension AgentLoop {
    @discardableResult
    public func run(
        goal: Goal,
        budget: LoopBudget = LoopBudget(),
        surface: RuntimeSurface = .recipe
    ) async -> LoopOutcome {
        guard running, budget.maxSteps > 0 else {
            return LoopOutcome(
                reason: .maxSteps,
                finalWorldState: nil,
                steps: 0,
                recoveries: 0
            )
        }

        do {
            let response = try await orchestrator.submitIntent(makeIntent(for: goal, surface: surface))
            return makeOutcome(from: response)
        } catch {
            return LoopOutcome(
                reason: .unrecoverableFailure,
                finalWorldState: nil,
                steps: 1,
                recoveries: 0,
                lastFailure: .actionFailed
            )
        }
    }
}
