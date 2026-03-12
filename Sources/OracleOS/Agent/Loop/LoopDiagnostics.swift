import Foundation

public struct LoopStepSummary: Sendable, Equatable, Identifiable {
    public let id: String
    public let stepIndex: Int
    public let source: PlannerSource
    public let skillName: String
    public let workflowID: String?
    public let experimentID: String?
    public let success: Bool
    public let failure: FailureClass?
    public let recoveryStrategy: String?
    public let notes: [String]

    public init(
        id: String = UUID().uuidString,
        stepIndex: Int,
        source: PlannerSource,
        skillName: String,
        workflowID: String? = nil,
        experimentID: String? = nil,
        success: Bool,
        failure: FailureClass? = nil,
        recoveryStrategy: String? = nil,
        notes: [String] = []
    ) {
        self.id = id
        self.stepIndex = stepIndex
        self.source = source
        self.skillName = skillName
        self.workflowID = workflowID
        self.experimentID = experimentID
        self.success = success
        self.failure = failure
        self.recoveryStrategy = recoveryStrategy
        self.notes = notes
    }
}

public struct LoopDiagnostics: Sendable, Equatable {
    public var stepSummaries: [LoopStepSummary]

    public init(stepSummaries: [LoopStepSummary] = []) {
        self.stepSummaries = stepSummaries
    }

    public mutating func append(_ summary: LoopStepSummary) {
        stepSummaries.append(summary)
    }

    public mutating func recordDecision(
        stepIndex: Int,
        decision: PlannerDecision,
        success: Bool,
        failure: FailureClass? = nil,
        recoveryStrategy: String? = nil,
        notes: [String] = []
    ) {
        append(
            LoopStepSummary(
                stepIndex: stepIndex,
                source: decision.source,
                skillName: decision.skillName,
                workflowID: decision.workflowID,
                experimentID: decision.experimentSpec?.id,
                success: success,
                failure: failure,
                recoveryStrategy: recoveryStrategy,
                notes: notes
            )
        )
    }

    public mutating func recordRecovery(
        stepIndex: Int,
        strategyName: String?,
        success: Bool,
        failure: FailureClass? = nil,
        notes: [String] = []
    ) {
        append(
            LoopStepSummary(
                stepIndex: stepIndex,
                source: .recovery,
                skillName: strategyName ?? "recovery",
                success: success,
                failure: failure,
                recoveryStrategy: strategyName,
                notes: notes
            )
        )
    }

    public static let empty = LoopDiagnostics()
}
