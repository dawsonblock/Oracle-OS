import Foundation

public struct PerformanceReport: Sendable {
    public let taskID: String
    public let outcome: TaskOutcome
    public let bottlenecks: [String]
    public let failureCauses: [String]
    public let strategyEffectiveness: [StrategyEffectiveness]
    public let redundantSteps: [String]
    public let totalDuration: Double
    public let recoveryCount: Int
    public let plannerRevisitCount: Int
    public let notes: [String]

    public init(
        taskID: String,
        outcome: TaskOutcome,
        bottlenecks: [String] = [],
        failureCauses: [String] = [],
        strategyEffectiveness: [StrategyEffectiveness] = [],
        redundantSteps: [String] = [],
        totalDuration: Double = 0,
        recoveryCount: Int = 0,
        plannerRevisitCount: Int = 0,
        notes: [String] = []
    ) {
        self.taskID = taskID
        self.outcome = outcome
        self.bottlenecks = bottlenecks
        self.failureCauses = failureCauses
        self.strategyEffectiveness = strategyEffectiveness
        self.redundantSteps = redundantSteps
        self.totalDuration = totalDuration
        self.recoveryCount = recoveryCount
        self.plannerRevisitCount = plannerRevisitCount
        self.notes = notes
    }
}

public enum TaskOutcome: String, Sendable {
    case success
    case partialSuccess = "partial_success"
    case failure
    case timeout
    case aborted
}

public struct StrategyEffectiveness: Sendable {
    public let strategyName: String
    public let wasEffective: Bool
    public let contributionScore: Double
    public let notes: [String]

    public init(
        strategyName: String,
        wasEffective: Bool,
        contributionScore: Double = 0,
        notes: [String] = []
    ) {
        self.strategyName = strategyName
        self.wasEffective = wasEffective
        self.contributionScore = contributionScore
        self.notes = notes
    }
}

public final class PerformanceAnalyzer: @unchecked Sendable {

    public init() {}

    public func analyze(
        taskID: String,
        events: [TraceEvent],
        outcome: TaskOutcome
    ) -> PerformanceReport {
        let bottlenecks = detectBottlenecks(events: events)
        let failureCauses = extractFailureCauses(events: events)
        let strategies = assessStrategyEffectiveness(events: events)
        let redundant = detectRedundantSteps(events: events)
        let recoveryCount = events.filter { $0.recoveryTagged == true }.count
        let plannerRevisits = countPlannerRevisits(events: events)

        return PerformanceReport(
            taskID: taskID,
            outcome: outcome,
            bottlenecks: bottlenecks,
            failureCauses: failureCauses,
            strategyEffectiveness: strategies,
            redundantSteps: redundant,
            recoveryCount: recoveryCount,
            plannerRevisitCount: plannerRevisits,
            notes: generateNotes(
                outcome: outcome,
                recoveryCount: recoveryCount,
                bottleneckCount: bottlenecks.count
            )
        )
    }

    private func detectBottlenecks(events: [TraceEvent]) -> [String] {
        var bottlenecks: [String] = []

        let actionCounts = Dictionary(grouping: events, by: \.actionName)
        for (action, occurrences) in actionCounts where occurrences.count > 3 {
            bottlenecks.append("repeated action: \(action) (\(occurrences.count) times)")
        }

        let failedEvents = events.filter { !$0.success }
        if failedEvents.count > events.count / 3 && events.count > 3 {
            bottlenecks.append("high failure rate: \(failedEvents.count)/\(events.count) steps failed")
        }

        let recoveryEvents = events.filter { $0.recoveryTagged == true }
        if recoveryEvents.count > 3 {
            bottlenecks.append("excessive recovery attempts: \(recoveryEvents.count)")
        }

        return bottlenecks
    }

    private func extractFailureCauses(events: [TraceEvent]) -> [String] {
        var causes: [String] = []
        let failedEvents = events.filter { !$0.success }
        let failureActions = Set(failedEvents.map(\.actionName))
        for action in failureActions.sorted() {
            let count = failedEvents.filter { $0.actionName == action }.count
            causes.append("\(action) failed \(count) time(s)")
        }
        return causes
    }

    private func assessStrategyEffectiveness(events: [TraceEvent]) -> [StrategyEffectiveness] {
        var strategies: [String: (success: Int, total: Int)] = [:]
        for event in events {
            let key = event.actionName
            var entry = strategies[key, default: (success: 0, total: 0)]
            entry.total += 1
            if event.success { entry.success += 1 }
            strategies[key] = entry
        }

        return strategies.map { action, counts in
            let rate = counts.total > 0 ? Double(counts.success) / Double(counts.total) : 0
            return StrategyEffectiveness(
                strategyName: action,
                wasEffective: rate > 0.5,
                contributionScore: rate,
                notes: ["\(counts.success)/\(counts.total) succeeded"]
            )
        }
        .sorted { $0.contributionScore > $1.contributionScore }
    }

    private func detectRedundantSteps(events: [TraceEvent]) -> [String] {
        var redundant: [String] = []
        var previousAction: String?

        for event in events {
            if event.actionName == previousAction && event.success {
                redundant.append("consecutive duplicate: \(event.actionName)")
            }
            previousAction = event.actionName
        }

        return redundant
    }

    private func countPlannerRevisits(events: [TraceEvent]) -> Int {
        var seen = Set<String>()
        var revisits = 0
        for event in events {
            if let stateID = event.planningStateID {
                if seen.contains(stateID) {
                    revisits += 1
                }
                seen.insert(stateID)
            }
        }
        return revisits
    }

    private func generateNotes(outcome: TaskOutcome, recoveryCount: Int, bottleneckCount: Int) -> [String] {
        var notes: [String] = []
        if outcome == .success && recoveryCount == 0 {
            notes.append("clean execution with no recovery needed")
        }
        if outcome == .success && recoveryCount > 0 {
            notes.append("succeeded after \(recoveryCount) recovery attempt(s)")
        }
        if bottleneckCount > 0 {
            notes.append("\(bottleneckCount) bottleneck(s) detected")
        }
        return notes
    }
}
