import Foundation

public enum LoopTerminationReason: String, Codable, Sendable {
    case goalAchieved
    case maxSteps
    case policyBlocked
    case approvalTimeout
    case noViablePlan
    case unrecoverableFailure
    case explorationBudgetExceeded
    case lowConfidenceRepeatedFailure
}

public struct LoopOutcome: Sendable {
    public let reason: LoopTerminationReason
    public let finalWorldState: WorldState?
    public let steps: Int
    public let recoveries: Int
    /// Number of recovery attempts that successfully resumed execution.
    public let recoverySuccesses: Int
    /// Number of recovery attempts that did not resume execution.
    public let recoveryFailures: Int
    public let lastFailure: FailureClass?
    public let diagnostics: LoopDiagnostics

    public init(
        reason: LoopTerminationReason,
        finalWorldState: WorldState?,
        steps: Int,
        recoveries: Int,
        recoverySuccesses: Int = 0,
        recoveryFailures: Int = 0,
        lastFailure: FailureClass? = nil,
        diagnostics: LoopDiagnostics = .empty
    ) {
        self.reason = reason
        self.finalWorldState = finalWorldState
        self.steps = steps
        self.recoveries = recoveries
        self.recoverySuccesses = recoverySuccesses
        self.recoveryFailures = recoveryFailures
        self.lastFailure = lastFailure
        self.diagnostics = diagnostics
    }
}
