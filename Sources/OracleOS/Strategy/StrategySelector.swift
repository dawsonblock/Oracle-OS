import Foundation

/// Chooses a high-level ``TaskStrategy`` based on the current goal, world state,
/// memory, and workflow availability. The planner then generates plans within
/// the scope of the selected strategy.
public final class StrategySelector: @unchecked Sendable {
    private let library: [TaskStrategy]
    private let llmClient: LLMClient?

    public init(
        library: [TaskStrategy]? = nil,
        llmClient: LLMClient? = nil
    ) {
        self.library = library ?? Self.defaultLibrary()
        self.llmClient = llmClient
    }

    /// Select the best strategy for the current situation.
    public func select(
        goal: Goal,
        worldState: WorldState,
        memoryInfluence: MemoryInfluence,
        workflowIndex: WorkflowIndex,
        agentKind: AgentKind
    ) -> StrategySelection {
        let conditions = activeConditions(
            worldState: worldState,
            goal: goal,
            workflowIndex: workflowIndex
        )

        var scored: [(TaskStrategy, Double)] = []
        for strategy in library {
            guard strategy.applicableAgentKinds.contains(agentKind) else { continue }
            let conditionMatch = conditionScore(
                strategy: strategy,
                activeConditions: conditions
            )
            guard conditionMatch > 0 || strategy.requiredConditions.isEmpty else { continue }

            let memoryBoost = memoryBoost(
                strategy: strategy,
                influence: memoryInfluence
            )
            let total = strategy.priorityScore + conditionMatch + memoryBoost
            scored.append((strategy, total))
        }

        scored.sort { $0.1 > $1.1 }

        guard let best = scored.first else {
            let fallback = TaskStrategy(
                kind: .uiExploration,
                description: "Default exploration when no strategy matches",
                priorityScore: 0.1
            )
            return StrategySelection(
                selected: fallback,
                score: 0.1,
                alternatives: [],
                conditions: conditions,
                notes: ["no strategy matched; falling back to exploration"]
            )
        }

        return StrategySelection(
            selected: best.0,
            score: best.1,
            alternatives: scored.dropFirst().prefix(3).map { $0.0 },
            conditions: conditions,
            notes: []
        )
    }

    private func activeConditions(
        worldState: WorldState,
        goal: Goal,
        workflowIndex: WorkflowIndex
    ) -> Set<StrategyCondition> {
        var conditions = Set<StrategyCondition>()

        if worldState.repositorySnapshot != nil {
            conditions.insert(.repositoryOpen)
        }
        if worldState.repositorySnapshot?.isGitDirty == true {
            conditions.insert(.gitDirty)
        }
        if worldState.planningState.modalClass != nil {
            conditions.insert(.modalPresent)
        }

        let goalLower = goal.description.lowercased()
        if goalLower.contains("test") || goalLower.contains("failing") {
            conditions.insert(.testsFailing)
        }
        if goalLower.contains("build") || goalLower.contains("compile") {
            conditions.insert(.buildFailing)
        }

        let workflows = workflowIndex.matching(goal: goal)
        if !workflows.isEmpty {
            conditions.insert(.workflowAvailable)
        }

        return conditions
    }

    private func conditionScore(
        strategy: TaskStrategy,
        activeConditions: Set<StrategyCondition>
    ) -> Double {
        guard !strategy.requiredConditions.isEmpty else { return 0.1 }
        let matched = strategy.requiredConditions.filter { activeConditions.contains($0) }
        return Double(matched.count) / Double(strategy.requiredConditions.count)
    }

    private func memoryBoost(
        strategy: TaskStrategy,
        influence: MemoryInfluence
    ) -> Double {
        var boost = 0.0
        if strategy.kind == .codeRepair && influence.preferredFixPath != nil {
            boost += 0.15
        }
        if strategy.kind == .recovery && influence.preferredRecoveryStrategy != nil {
            boost += 0.1
        }
        if strategy.kind == .workflowReuse && influence.executionRankingBias > 0 {
            boost += 0.1
        }
        return boost
    }

    private static func defaultLibrary() -> [TaskStrategy] {
        [
            TaskStrategy(
                kind: .workflowReuse,
                description: "Reuse a validated workflow for the current goal",
                requiredConditions: [.workflowAvailable],
                priorityScore: 0.8,
                notes: ["Highest priority when a matching promoted workflow exists"]
            ),
            TaskStrategy(
                kind: .codeRepair,
                description: "Repair failing code using fault localization and patching",
                applicableAgentKinds: [.code, .mixed],
                requiredConditions: [.repositoryOpen],
                priorityScore: 0.7
            ),
            TaskStrategy(
                kind: .testFix,
                description: "Fix failing tests by analyzing stack traces and applying targeted patches",
                applicableAgentKinds: [.code, .mixed],
                requiredConditions: [.repositoryOpen, .testsFailing],
                priorityScore: 0.75
            ),
            TaskStrategy(
                kind: .buildFix,
                description: "Fix build failures by analyzing compiler errors",
                applicableAgentKinds: [.code, .mixed],
                requiredConditions: [.repositoryOpen, .buildFailing],
                priorityScore: 0.75
            ),
            TaskStrategy(
                kind: .dependencyRepair,
                description: "Repair dependency issues in the project",
                applicableAgentKinds: [.code, .mixed],
                requiredConditions: [.repositoryOpen],
                priorityScore: 0.6
            ),
            TaskStrategy(
                kind: .recovery,
                description: "Recover from blocking conditions (modals, wrong focus)",
                requiredConditions: [.modalPresent],
                priorityScore: 0.9,
                notes: ["Highest urgency — must resolve before other strategies"]
            ),
            TaskStrategy(
                kind: .navigation,
                description: "Navigate to a target application or page",
                applicableAgentKinds: [.os, .mixed],
                priorityScore: 0.5
            ),
            TaskStrategy(
                kind: .uiExploration,
                description: "Explore the UI to discover available actions",
                applicableAgentKinds: [.os, .mixed],
                priorityScore: 0.3,
                notes: ["Lowest priority — used when other strategies don't apply"]
            ),
            TaskStrategy(
                kind: .configurationDiagnosis,
                description: "Diagnose system or environment configuration issues",
                priorityScore: 0.4
            ),
        ]
    }
}

/// The result of strategy selection including the chosen strategy and metadata.
public struct StrategySelection: Sendable {
    public let selected: TaskStrategy
    public let score: Double
    public let alternatives: [TaskStrategy]
    public let conditions: Set<StrategyCondition>
    public let notes: [String]

    public init(
        selected: TaskStrategy,
        score: Double,
        alternatives: [TaskStrategy] = [],
        conditions: Set<StrategyCondition> = [],
        notes: [String] = []
    ) {
        self.selected = selected
        self.score = score
        self.alternatives = alternatives
        self.conditions = conditions
        self.notes = notes
    }
}
