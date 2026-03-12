import Foundation

public struct PlanCandidate: Sendable {
    public let operators: [Operator]
    public let projectedState: ReasoningPlanningState
    public let score: Double
    public let reasons: [String]

    public init(
        operators: [Operator],
        projectedState: ReasoningPlanningState,
        score: Double = 0,
        reasons: [String] = []
    ) {
        self.operators = operators
        self.projectedState = projectedState
        self.score = score
        self.reasons = reasons
    }
}
