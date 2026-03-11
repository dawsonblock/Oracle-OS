import Foundation

public final class EdgeTransition: @unchecked Sendable {
    public let edgeID: String
    public let fromPlanningStateID: PlanningStateID
    public var toPlanningStateID: PlanningStateID
    public let actionContractID: String
    public let postconditionClass: PostconditionClass
    public var attempts: Int
    public var successes: Int
    public var latencyTotalMs: Int
    public var failureHistogram: [String: Int]

    public init(
        edgeID: String,
        fromPlanningStateID: PlanningStateID,
        toPlanningStateID: PlanningStateID,
        actionContractID: String,
        postconditionClass: PostconditionClass,
        attempts: Int = 0,
        successes: Int = 0,
        latencyTotalMs: Int = 0,
        failureHistogram: [String: Int] = [:]
    ) {
        self.edgeID = edgeID
        self.fromPlanningStateID = fromPlanningStateID
        self.toPlanningStateID = toPlanningStateID
        self.actionContractID = actionContractID
        self.postconditionClass = postconditionClass
        self.attempts = attempts
        self.successes = successes
        self.latencyTotalMs = latencyTotalMs
        self.failureHistogram = failureHistogram
    }

    public var successRate: Double {
        guard attempts > 0 else { return 0 }
        return Double(successes) / Double(attempts)
    }

    public var averageLatencyMs: Double {
        guard attempts > 0 else { return 0 }
        return Double(latencyTotalMs) / Double(attempts)
    }

    public var confidence: Double {
        let attemptsFactor = min(Double(attempts) / 10.0, 1.0)
        return successRate * attemptsFactor
    }

    public var cost: Double {
        let failureRate = 1.0 - successRate
        let normalizedLatency = min(averageLatencyMs / 2_000.0, 1.0)
        let uncertainty = 1.0 - confidence
        let noveltyBonus = attempts < 3 ? -0.05 : 0
        return failureRate + (0.35 * normalizedLatency) + (0.5 * uncertainty) + noveltyBonus
    }

    public func record(_ transition: VerifiedTransition) {
        attempts += 1
        if transition.verified {
            successes += 1
            toPlanningStateID = transition.toPlanningStateID
        } else if let failureClass = transition.failureClass {
            failureHistogram[failureClass, default: 0] += 1
        }
        latencyTotalMs += transition.latencyMs
    }
}
