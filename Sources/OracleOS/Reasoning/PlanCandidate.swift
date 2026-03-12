import Foundation

public struct PlanCandidate: Sendable {
    public let operators: [Operator]
    public let projectedState: ReasoningPlanningState
    public let score: Double
    public let reasons: [String]
    public let simulatedOutcome: SimulatedOutcome?

    public init(
        operators: [Operator],
        projectedState: ReasoningPlanningState,
        score: Double = 0,
        reasons: [String] = [],
        simulatedOutcome: SimulatedOutcome? = nil
    ) {
        self.operators = operators
        self.projectedState = projectedState
        self.score = score
        self.reasons = reasons
        self.simulatedOutcome = simulatedOutcome
    }
}
