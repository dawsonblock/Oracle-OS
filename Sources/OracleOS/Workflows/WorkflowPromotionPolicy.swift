import Foundation

public struct WorkflowPromotionPolicy: Sendable {
    public let minimumTraceSegmentCount: Int
    public let minimumSuccessRate: Double
    public let minimumReplayValidationSuccess: Double

    public init(
        minimumTraceSegmentCount: Int = 3,
        minimumSuccessRate: Double = 0.8,
        minimumReplayValidationSuccess: Double = 0.66
    ) {
        self.minimumTraceSegmentCount = minimumTraceSegmentCount
        self.minimumSuccessRate = minimumSuccessRate
        self.minimumReplayValidationSuccess = minimumReplayValidationSuccess
    }

    public func shouldPromote(_ plan: WorkflowPlan) -> Bool {
        guard plan.repeatedTraceSegmentCount >= minimumTraceSegmentCount else {
            return false
        }
        guard plan.successRate >= minimumSuccessRate else {
            return false
        }
        guard plan.replayValidationSuccess >= minimumReplayValidationSuccess else {
            return false
        }
        guard !plan.evidenceTiers.contains(.recovery), !plan.evidenceTiers.contains(.experiment) else {
            return false
        }
        return true
    }
}
