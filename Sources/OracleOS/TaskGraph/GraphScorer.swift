import Foundation

/// Scores task-graph edges and paths using multiple signals.
///
/// Scoring combines:
/// - Edge success probability (from evidence)
/// - Workflow similarity (pattern reuse)
/// - Memory bias (attached to nodes/edges)
/// - Goal alignment (does the target state match the goal?)
/// - Cost penalty
/// - Risk penalty
public struct GraphScorer: Sendable {
    public let successWeight: Double
    public let workflowWeight: Double
    public let memoryWeight: Double
    public let goalAlignmentWeight: Double
    public let costPenaltyWeight: Double
    public let riskPenaltyWeight: Double

    public init(
        successWeight: Double = 0.30,
        workflowWeight: Double = 0.15,
        memoryWeight: Double = 0.15,
        goalAlignmentWeight: Double = 0.25,
        costPenaltyWeight: Double = 0.08,
        riskPenaltyWeight: Double = 0.07
    ) {
        self.successWeight = successWeight
        self.workflowWeight = workflowWeight
        self.memoryWeight = memoryWeight
        self.goalAlignmentWeight = goalAlignmentWeight
        self.costPenaltyWeight = costPenaltyWeight
        self.riskPenaltyWeight = riskPenaltyWeight
    }

    // MARK: - Edge Scoring

    /// Score a single edge, optionally incorporating goal-alignment when
    /// ``goalState`` and ``targetState`` are known.
    public func scoreEdge(
        _ edge: TaskEdge,
        goalState: AbstractTaskState? = nil,
        targetState: AbstractTaskState? = nil,
        workflowBias: Double = 0,
        memoryBias: Double = 0
    ) -> Double {
        let success = edge.successProbability
        let noveltyBonus: Double = edge.attempts < 3 ? 0.1 : 0
        let goalAlignment = goalAlignmentScore(targetState: targetState, goalState: goalState)
        let costPenalty = normalizedCost(edge.averageCost)
        let riskPenalty = edge.risk

        return (successWeight * success)
            + (workflowWeight * min(1, max(0, workflowBias)))
            + (memoryWeight * min(1, max(0, memoryBias)))
            + (goalAlignmentWeight * goalAlignment)
            - (costPenaltyWeight * costPenalty)
            - (riskPenaltyWeight * riskPenalty)
            + noveltyBonus
    }

    /// Score an array of edges as a path (cumulative).
    public func scorePath(_ edges: [TaskEdge], goal: Goal? = nil) -> Double {
        guard !edges.isEmpty else { return 0 }
        return edges.reduce(0.0) { total, edge in
            total + scoreEdge(edge)
        }
    }

    // MARK: - Goal Alignment

    private func goalAlignmentScore(
        targetState: AbstractTaskState?,
        goalState: AbstractTaskState?
    ) -> Double {
        guard let target = targetState, let goal = goalState else { return 0 }
        if target == goal { return 1.0 }
        // Partial credit for related states
        if Self.relatedStates(target, goal) { return 0.4 }
        return 0
    }

    private static func relatedStates(_ a: AbstractTaskState, _ b: AbstractTaskState) -> Bool {
        let groups: [[AbstractTaskState]] = [
            [.buildRunning, .buildSucceeded, .buildFailed],
            [.testsRunning, .testsPassed, .failingTestIdentified],
            [.candidatePatchGenerated, .candidatePatchApplied, .patchVerified, .patchRejected],
            [.loginPageDetected, .formVisible, .navigationCompleted],
            [.repoLoaded, .repoIndexed],
        ]
        return groups.contains { group in group.contains(a) && group.contains(b) }
    }

    /// Derive a goal ``AbstractTaskState`` from a ``Goal`` description.
    public static func goalAbstractState(from goal: Goal) -> AbstractTaskState? {
        let desc = goal.description.lowercased()
        if desc.contains("test") && desc.contains("pass") { return .testsPassed }
        if desc.contains("test") && desc.contains("fix") { return .testsPassed }
        if desc.contains("test") && desc.contains("run") { return .testsRunning }
        if desc.contains("build") && desc.contains("fix") { return .buildSucceeded }
        if desc.contains("build") { return .buildSucceeded }
        if desc.contains("patch") { return .patchVerified }
        if desc.contains("login") { return .loginPageDetected }
        if desc.contains("navigate") { return .navigationCompleted }
        if desc.contains("complete") || desc.contains("done") { return .goalReached }
        return nil
    }

    // MARK: - Helpers

    private func normalizedCost(_ cost: Double) -> Double {
        min(max(cost / 10.0, 0), 1)
    }
}
