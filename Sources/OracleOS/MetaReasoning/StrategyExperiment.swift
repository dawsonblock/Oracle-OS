import Foundation

/// Runs controlled experiments to validate ``ImprovementCandidate``s before
/// they are promoted into the system's active strategies.
///
/// The flow is:
///
///     candidate strategy → run controlled tasks → compare metrics → promote if better
///
/// This prevents untested improvements from degrading system behavior.
public final class StrategyExperiment: @unchecked Sendable {
    private let lock = NSLock()
    private var results: [ExperimentResult] = []
    private let minimumTrials: Int
    private let minimumImprovement: Double

    public init(
        minimumTrials: Int = 3,
        minimumImprovement: Double = 0.1
    ) {
        self.minimumTrials = minimumTrials
        self.minimumImprovement = minimumImprovement
    }

    /// Record the outcome of running a task with an experimental strategy.
    public func recordTrial(_ trial: ExperimentTrial) {
        lock.lock()
        defer { lock.unlock() }
        results.append(ExperimentResult(trial: trial))
    }

    /// Evaluate whether an improvement candidate should be promoted based on
    /// accumulated trial data.
    public func evaluate(candidateID: String) -> ExperimentVerdict {
        lock.lock()
        defer { lock.unlock() }

        let relevant = results.filter { $0.trial.candidateID == candidateID }
        guard relevant.count >= minimumTrials else {
            return ExperimentVerdict(
                candidateID: candidateID,
                verdict: .insufficientData,
                trialCount: relevant.count,
                successRate: 0,
                improvementOverBaseline: 0,
                notes: ["need \(minimumTrials - relevant.count) more trial(s)"]
            )
        }

        let successes = relevant.filter { $0.trial.succeeded }.count
        let successRate = Double(successes) / Double(relevant.count)
        let baselineRate = relevant.reduce(0.0) { $0 + $1.trial.baselineSuccessRate } / Double(relevant.count)
        let improvement = successRate - baselineRate

        let verdict: ExperimentVerdictKind
        if improvement >= minimumImprovement && successRate > baselineRate {
            verdict = .promote
        } else if improvement < -minimumImprovement {
            verdict = .reject
        } else {
            verdict = .inconclusive
        }

        return ExperimentVerdict(
            candidateID: candidateID,
            verdict: verdict,
            trialCount: relevant.count,
            successRate: successRate,
            improvementOverBaseline: improvement,
            notes: []
        )
    }

    /// Returns all recorded results for a candidate.
    public func trials(for candidateID: String) -> [ExperimentTrial] {
        lock.lock()
        defer { lock.unlock() }
        return results
            .filter { $0.trial.candidateID == candidateID }
            .map(\.trial)
    }
}

/// A single trial of an experimental strategy.
public struct ExperimentTrial: Sendable {
    public let candidateID: String
    public let taskID: String
    public let succeeded: Bool
    public let durationSeconds: Double
    public let baselineSuccessRate: Double
    public let notes: [String]

    public init(
        candidateID: String,
        taskID: String,
        succeeded: Bool,
        durationSeconds: Double = 0,
        baselineSuccessRate: Double = 0.5,
        notes: [String] = []
    ) {
        self.candidateID = candidateID
        self.taskID = taskID
        self.succeeded = succeeded
        self.durationSeconds = durationSeconds
        self.baselineSuccessRate = baselineSuccessRate
        self.notes = notes
    }
}

/// The result of evaluating a strategy experiment.
public struct ExperimentVerdict: Sendable {
    public let candidateID: String
    public let verdict: ExperimentVerdictKind
    public let trialCount: Int
    public let successRate: Double
    public let improvementOverBaseline: Double
    public let notes: [String]

    public init(
        candidateID: String,
        verdict: ExperimentVerdictKind,
        trialCount: Int,
        successRate: Double,
        improvementOverBaseline: Double,
        notes: [String] = []
    ) {
        self.candidateID = candidateID
        self.verdict = verdict
        self.trialCount = trialCount
        self.successRate = successRate
        self.improvementOverBaseline = improvementOverBaseline
        self.notes = notes
    }
}

public enum ExperimentVerdictKind: String, Sendable {
    case promote
    case reject
    case inconclusive
    case insufficientData = "insufficient_data"
}
