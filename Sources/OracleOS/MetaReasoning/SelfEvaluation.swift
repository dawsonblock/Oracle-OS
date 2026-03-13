import Foundation

public struct SelfEvaluationMetrics: Sendable {
    public let taskSuccessRate: Double
    public let averagePlanDepth: Double
    public let workflowReuseRate: Double
    public let recoveryFrequency: Double
    public let patchSuccessRate: Double
    public let averageExecutionSteps: Double
    public let totalTasks: Int
    public let notes: [String]

    public init(
        taskSuccessRate: Double = 0,
        averagePlanDepth: Double = 0,
        workflowReuseRate: Double = 0,
        recoveryFrequency: Double = 0,
        patchSuccessRate: Double = 0,
        averageExecutionSteps: Double = 0,
        totalTasks: Int = 0,
        notes: [String] = []
    ) {
        self.taskSuccessRate = taskSuccessRate
        self.averagePlanDepth = averagePlanDepth
        self.workflowReuseRate = workflowReuseRate
        self.recoveryFrequency = recoveryFrequency
        self.patchSuccessRate = patchSuccessRate
        self.averageExecutionSteps = averageExecutionSteps
        self.totalTasks = totalTasks
        self.notes = notes
    }
}

public final class SelfEvaluation: @unchecked Sendable {
    private let lock = NSLock()
    private var reports: [PerformanceReport] = []

    public init() {}

    public func record(_ report: PerformanceReport) {
        lock.lock()
        defer { lock.unlock() }
        reports.append(report)
    }

    public var metrics: SelfEvaluationMetrics {
        lock.lock()
        defer { lock.unlock() }

        guard !reports.isEmpty else {
            return SelfEvaluationMetrics()
        }

        let total = reports.count
        let successes = reports.filter { $0.outcome == .success }.count
        let taskSuccessRate = Double(successes) / Double(total)

        let allStrategies = reports.flatMap(\.strategyEffectiveness)
        let avgPlanDepth = allStrategies.isEmpty
            ? 0
            : Double(allStrategies.count) / Double(total)

        let workflowRelated = allStrategies.filter {
            $0.strategyName.contains("workflow") || $0.strategyName.contains("recipe")
        }
        let workflowReuseRate = allStrategies.isEmpty
            ? 0
            : Double(workflowRelated.count) / Double(max(allStrategies.count, 1))

        let totalRecoveries = reports.reduce(0) { $0 + $1.recoveryCount }
        let recoveryFrequency = Double(totalRecoveries) / Double(total)

        let patchStrategies = allStrategies.filter {
            $0.strategyName.contains("patch") || $0.strategyName.contains("edit")
        }
        let patchSuccesses = patchStrategies.filter(\.wasEffective).count
        let patchSuccessRate = patchStrategies.isEmpty
            ? 0
            : Double(patchSuccesses) / Double(patchStrategies.count)

        let avgSteps = allStrategies.isEmpty
            ? 0
            : Double(allStrategies.count) / Double(total)

        return SelfEvaluationMetrics(
            taskSuccessRate: taskSuccessRate,
            averagePlanDepth: avgPlanDepth,
            workflowReuseRate: workflowReuseRate,
            recoveryFrequency: recoveryFrequency,
            patchSuccessRate: patchSuccessRate,
            averageExecutionSteps: avgSteps,
            totalTasks: total,
            notes: [
                "evaluated \(total) task(s)",
                "success rate: \(String(format: "%.0f", taskSuccessRate * 100))%",
            ]
        )
    }

    public func recentReports(limit: Int = 10) -> [PerformanceReport] {
        lock.lock()
        defer { lock.unlock() }
        return Array(reports.suffix(limit))
    }
}
