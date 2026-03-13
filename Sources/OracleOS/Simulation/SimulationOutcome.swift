import Foundation

public struct SimulationStepOutcome: Sendable {
    public let operatorKind: ReasoningOperatorKind
    public let inputStateID: String
    public let outputStateID: String
    public let transitionProbability: Double
    public let notes: [String]

    public init(
        operatorKind: ReasoningOperatorKind,
        inputStateID: String,
        outputStateID: String,
        transitionProbability: Double,
        notes: [String] = []
    ) {
        self.operatorKind = operatorKind
        self.inputStateID = inputStateID
        self.outputStateID = outputStateID
        self.transitionProbability = transitionProbability
        self.notes = notes
    }
}

public struct SimulationOutcome: Sendable {
    public let steps: [SimulationStepOutcome]
    public let finalStateID: String
    public let cumulativeProbability: Double
    public let cumulativeRisk: Double
    public let expectedFailureMode: String?
    public let expectedCompletionLikelihood: Double
    public let latencyEstimate: Double
    public let costEstimate: Double
    public let notes: [String]

    public init(
        steps: [SimulationStepOutcome],
        finalStateID: String,
        cumulativeProbability: Double,
        cumulativeRisk: Double,
        expectedFailureMode: String? = nil,
        expectedCompletionLikelihood: Double = 0,
        latencyEstimate: Double = 0,
        costEstimate: Double = 0,
        notes: [String] = []
    ) {
        self.steps = steps
        self.finalStateID = finalStateID
        self.cumulativeProbability = cumulativeProbability
        self.cumulativeRisk = cumulativeRisk
        self.expectedFailureMode = expectedFailureMode
        self.expectedCompletionLikelihood = expectedCompletionLikelihood
        self.latencyEstimate = latencyEstimate
        self.costEstimate = costEstimate
        self.notes = notes
    }
}
