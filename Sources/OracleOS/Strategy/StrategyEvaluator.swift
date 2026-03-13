import Foundation

/// Evaluates the effectiveness of a ``TaskStrategy`` after execution by
/// comparing predicted outcomes to actual results. Feeds data back into
/// the meta-reasoning improvement loop.
public final class StrategyEvaluator: @unchecked Sendable {
    private let lock = NSLock()
    private var evaluations: [StrategyEvaluation] = []

    public init() {}

    /// Record the result of executing a strategy for later analysis.
    public func record(_ evaluation: StrategyEvaluation) {
        lock.lock()
        defer { lock.unlock() }
        evaluations.append(evaluation)
    }

    /// Compute an effectiveness score for a strategy kind based on recorded history.
    public func effectiveness(for kind: TaskStrategyKind) -> StrategyEffectivenessScore {
        lock.lock()
        defer { lock.unlock() }

        let relevant = evaluations.filter { $0.strategyKind == kind }
        guard !relevant.isEmpty else {
            return StrategyEffectivenessScore(
                strategyKind: kind,
                sampleCount: 0,
                successRate: 0,
                averageDuration: 0,
                averageRecoveryCount: 0,
                confidenceLevel: 0
            )
        }

        let successes = relevant.filter { $0.succeeded }.count
        let successRate = Double(successes) / Double(relevant.count)
        let avgDuration = relevant.reduce(0.0) { $0 + $1.durationSeconds } / Double(relevant.count)
        let avgRecovery = Double(relevant.reduce(0) { $0 + $1.recoveryCount }) / Double(relevant.count)

        let confidence = min(1.0, Double(relevant.count) * 0.15)

        return StrategyEffectivenessScore(
            strategyKind: kind,
            sampleCount: relevant.count,
            successRate: successRate,
            averageDuration: avgDuration,
            averageRecoveryCount: avgRecovery,
            confidenceLevel: confidence
        )
    }

    /// Returns all recorded evaluations (limited to most recent).
    public func recentEvaluations(limit: Int = 50) -> [StrategyEvaluation] {
        lock.lock()
        defer { lock.unlock() }
        return Array(evaluations.suffix(limit))
    }

    /// Returns strategy kinds sorted by effectiveness (best first).
    public func rankedStrategies() -> [StrategyEffectivenessScore] {
        TaskStrategyKind.allCases
            .map { effectiveness(for: $0) }
            .filter { $0.sampleCount > 0 }
            .sorted { $0.successRate > $1.successRate }
    }
}

/// A record of how a strategy performed during a task.
public struct StrategyEvaluation: Sendable {
    public let taskID: String
    public let strategyKind: TaskStrategyKind
    public let succeeded: Bool
    public let durationSeconds: Double
    public let recoveryCount: Int
    public let stepCount: Int
    public let notes: [String]

    public init(
        taskID: String,
        strategyKind: TaskStrategyKind,
        succeeded: Bool,
        durationSeconds: Double = 0,
        recoveryCount: Int = 0,
        stepCount: Int = 0,
        notes: [String] = []
    ) {
        self.taskID = taskID
        self.strategyKind = strategyKind
        self.succeeded = succeeded
        self.durationSeconds = durationSeconds
        self.recoveryCount = recoveryCount
        self.stepCount = stepCount
        self.notes = notes
    }
}

/// Summary of how effective a strategy kind is across observed executions.
public struct StrategyEffectivenessScore: Sendable {
    public let strategyKind: TaskStrategyKind
    public let sampleCount: Int
    public let successRate: Double
    public let averageDuration: Double
    public let averageRecoveryCount: Double
    public let confidenceLevel: Double

    public init(
        strategyKind: TaskStrategyKind,
        sampleCount: Int,
        successRate: Double,
        averageDuration: Double,
        averageRecoveryCount: Double,
        confidenceLevel: Double
    ) {
        self.strategyKind = strategyKind
        self.sampleCount = sampleCount
        self.successRate = successRate
        self.averageDuration = averageDuration
        self.averageRecoveryCount = averageRecoveryCount
        self.confidenceLevel = confidenceLevel
    }
}
