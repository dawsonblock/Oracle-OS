import Foundation

public struct LoopBudget: Sendable {
    public let maxSteps: Int
    public let maxRecoveries: Int
    public let maxConsecutiveExplorationSteps: Int
    public let maxPatchIterations: Int
    public let maxBuildAttempts: Int
    public let maxTestAttempts: Int

    public init(
        maxSteps: Int = 25,
        maxRecoveries: Int = 5,
        maxConsecutiveExplorationSteps: Int = 3,
        maxPatchIterations: Int = 5,
        maxBuildAttempts: Int = 5,
        maxTestAttempts: Int = 5
    ) {
        self.maxSteps = maxSteps
        self.maxRecoveries = maxRecoveries
        self.maxConsecutiveExplorationSteps = maxConsecutiveExplorationSteps
        self.maxPatchIterations = maxPatchIterations
        self.maxBuildAttempts = maxBuildAttempts
        self.maxTestAttempts = maxTestAttempts
    }
}
