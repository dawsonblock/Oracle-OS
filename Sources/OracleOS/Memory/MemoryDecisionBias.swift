import Foundation

public struct MemoryDecisionBias: Sendable {
    public let successPatternBias: Double
    public let failurePatternPenalty: Double
    public let projectSpecificBias: Double
    public let recentTraceBias: Double
    public let totalBias: Double
    public let notes: [String]

    public init(
        successPatternBias: Double = 0,
        failurePatternPenalty: Double = 0,
        projectSpecificBias: Double = 0,
        recentTraceBias: Double = 0,
        notes: [String] = []
    ) {
        self.successPatternBias = successPatternBias
        self.failurePatternPenalty = failurePatternPenalty
        self.projectSpecificBias = projectSpecificBias
        self.recentTraceBias = recentTraceBias
        self.totalBias = successPatternBias - failurePatternPenalty + projectSpecificBias + recentTraceBias
        self.notes = notes
    }
}

public final class MemoryDecisionBiasCalculator: @unchecked Sendable {
    private let memoryRouter: MemoryRouter

    public init(memoryStore: AppMemoryStore) {
        self.memoryRouter = MemoryRouter(memoryStore: memoryStore)
    }

    public func bias(
        plan: PlanCandidate,
        goal: Goal,
        worldState: WorldState,
        taskContext: TaskContext
    ) -> MemoryDecisionBias {
        guard let firstOperator = plan.operators.first else {
            return MemoryDecisionBias()
        }

        let memoryInfluence = memoryRouter.influence(
            for: MemoryQueryContext(
                taskContext: taskContext,
                worldState: worldState,
                errorSignature: goal.description
            )
        )

        var notes: [String] = []

        let successBias = memoryInfluence.executionRankingBias
        if successBias > 0 {
            notes.append("successful pattern bias \(String(format: "%.2f", successBias))")
        }

        let failurePenalty = memoryInfluence.riskPenalty
        if failurePenalty > 0 {
            notes.append("failure pattern penalty \(String(format: "%.2f", failurePenalty))")
        }

        let projectBias = memoryInfluence.projectMemorySignals.refs.isEmpty ? 0.0 : min(Double(memoryInfluence.projectMemorySignals.refs.count) * 0.03, 0.15)
        if projectBias > 0 {
            notes.append("project-specific bias \(String(format: "%.2f", projectBias))")
        }

        let commandBias = memoryInfluence.commandBias
        if commandBias > 0 {
            notes.append("recent trace bias \(String(format: "%.2f", commandBias))")
        }

        let preferredPathMatch: Double
        if let preferredPath = memoryInfluence.preferredFixPath,
           let contract = firstOperator.actionContract(
               for: plan.projectedState,
               goal: goal
           ),
           contract.workspaceRelativePath == preferredPath {
            preferredPathMatch = 0.08
            notes.append("preferred fix path match")
        } else {
            preferredPathMatch = 0
        }

        return MemoryDecisionBias(
            successPatternBias: successBias + preferredPathMatch,
            failurePatternPenalty: failurePenalty,
            projectSpecificBias: projectBias,
            recentTraceBias: commandBias,
            notes: notes
        )
    }

    public func biasScore(
        plan: PlanCandidate,
        goal: Goal,
        worldState: WorldState,
        taskContext: TaskContext
    ) -> Double {
        bias(
            plan: plan,
            goal: goal,
            worldState: worldState,
            taskContext: taskContext
        ).totalBias
    }
}
