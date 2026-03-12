import Foundation

public struct WorkflowConfidence: Sendable {
    public let score: Double
    public let successRate: Double
    public let executionCount: Int
    public let lastSuccessAge: TimeInterval?
    public let notes: [String]

    public init(
        score: Double,
        successRate: Double,
        executionCount: Int,
        lastSuccessAge: TimeInterval? = nil,
        notes: [String] = []
    ) {
        self.score = score
        self.successRate = successRate
        self.executionCount = executionCount
        self.lastSuccessAge = lastSuccessAge
        self.notes = notes
    }
}

public struct WorkflowConfidenceModel: Sendable {
    public let successRateWeight: Double
    public let executionCountWeight: Double
    public let recencyWeight: Double
    public let replayValidationWeight: Double

    public init(
        successRateWeight: Double = 0.40,
        executionCountWeight: Double = 0.25,
        recencyWeight: Double = 0.20,
        replayValidationWeight: Double = 0.15
    ) {
        self.successRateWeight = successRateWeight
        self.executionCountWeight = executionCountWeight
        self.recencyWeight = recencyWeight
        self.replayValidationWeight = replayValidationWeight
    }

    public func confidence(for workflow: WorkflowPlan) -> WorkflowConfidence {
        var notes: [String] = []

        let successComponent = workflow.successRate * successRateWeight
        notes.append("success rate \(String(format: "%.2f", workflow.successRate))")

        let countNormalized = min(Double(workflow.repeatedTraceSegmentCount) / 10.0, 1.0)
        let countComponent = countNormalized * executionCountWeight
        notes.append("execution count \(workflow.repeatedTraceSegmentCount)")

        let recencyComponent: Double
        let lastSuccessAge: TimeInterval?
        if let lastSuccess = workflow.lastSucceededAt {
            let age = Date().timeIntervalSince(lastSuccess)
            lastSuccessAge = age
            let ageDays = age / 86400
            let recencyScore = max(0, 1.0 - (ageDays / 30.0))
            recencyComponent = recencyScore * recencyWeight
            notes.append("last success \(String(format: "%.1f", ageDays)) days ago")
        } else {
            lastSuccessAge = nil
            recencyComponent = 0
        }

        let replayComponent = workflow.replayValidationSuccess * replayValidationWeight
        notes.append("replay validation \(String(format: "%.2f", workflow.replayValidationSuccess))")

        let totalScore = successComponent + countComponent + recencyComponent + replayComponent

        return WorkflowConfidence(
            score: min(max(totalScore, 0), 1.0),
            successRate: workflow.successRate,
            executionCount: workflow.repeatedTraceSegmentCount,
            lastSuccessAge: lastSuccessAge,
            notes: notes
        )
    }

    public func isReliable(_ workflow: WorkflowPlan, threshold: Double = 0.5) -> Bool {
        confidence(for: workflow).score >= threshold
    }
}
