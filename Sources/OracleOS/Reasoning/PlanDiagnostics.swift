import Foundation

public struct ScoredPlanSummary: Sendable, Equatable {
    public let operatorNames: [String]
    public let score: Double
    public let reasons: [String]

    public init(
        operatorNames: [String],
        score: Double,
        reasons: [String] = []
    ) {
        self.operatorNames = operatorNames
        self.score = score
        self.reasons = reasons
    }
}

public struct PlanDiagnostics: Sendable, Equatable {
    public let selectedOperatorNames: [String]
    public let candidatePlans: [ScoredPlanSummary]
    public let fallbackReason: String?

    public init(
        selectedOperatorNames: [String] = [],
        candidatePlans: [ScoredPlanSummary] = [],
        fallbackReason: String? = nil
    ) {
        self.selectedOperatorNames = selectedOperatorNames
        self.candidatePlans = candidatePlans
        self.fallbackReason = fallbackReason
    }
}
