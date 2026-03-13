import Foundation

public enum LLMDecisionKind: String, Sendable {
    case goalInterpretation = "goal_interpretation"
    case reasoningPlan = "reasoning_plan"
    case patchAssistance = "patch_assistance"
    case recoveryAssistance = "recovery_assistance"
    case actionRanking = "action_ranking"
}

public struct LLMDecisionRequest: Sendable {
    public let kind: LLMDecisionKind
    public let goalDescription: String
    public let contextHints: [String]
    public let memoryHints: [String]
    public let workflowHints: [String]
    public let graphHints: [String]
    /// The selected strategy that bounds this LLM decision, if any.
    public let selectedStrategy: SelectedStrategy?

    public init(
        kind: LLMDecisionKind,
        goalDescription: String,
        contextHints: [String] = [],
        memoryHints: [String] = [],
        workflowHints: [String] = [],
        graphHints: [String] = [],
        selectedStrategy: SelectedStrategy? = nil
    ) {
        self.kind = kind
        self.goalDescription = goalDescription
        self.contextHints = contextHints
        self.memoryHints = memoryHints
        self.workflowHints = workflowHints
        self.graphHints = graphHints
        self.selectedStrategy = selectedStrategy
    }
}

public struct LLMDecisionResponse: Sendable {
    public let kind: LLMDecisionKind
    public let recommendation: String
    public let confidence: Double
    public let rankedActions: [String]
    public let notes: [String]
    public let promptDiagnostics: PromptDiagnostics?

    public init(
        kind: LLMDecisionKind,
        recommendation: String,
        confidence: Double,
        rankedActions: [String] = [],
        notes: [String] = [],
        promptDiagnostics: PromptDiagnostics? = nil
    ) {
        self.kind = kind
        self.recommendation = recommendation
        self.confidence = confidence
        self.rankedActions = rankedActions
        self.notes = notes
        self.promptDiagnostics = promptDiagnostics
    }
}

public final class LLMDecisionEngine: @unchecked Sendable {
    private let promptEngine: PromptEngine

    public init(promptEngine: PromptEngine = PromptEngine()) {
        self.promptEngine = promptEngine
    }

    public func assistGoalInterpretation(
        goalDescription: String,
        worldState: WorldState,
        memoryInfluence: MemoryInfluence
    ) -> LLMDecisionResponse {
        let hints = assembleContextHints(worldState: worldState, memoryInfluence: memoryInfluence)
        return LLMDecisionResponse(
            kind: .goalInterpretation,
            recommendation: goalDescription,
            confidence: 0.8,
            rankedActions: [],
            notes: ["goal interpreted with context: \(hints.count) hints"]
        )
    }

    public func assistReasoningPlan(
        plans: [PlanCandidate],
        goal: Goal,
        worldState: WorldState,
        memoryInfluence: MemoryInfluence
    ) -> LLMDecisionResponse {
        let rankedNames = plans.prefix(5).flatMap { $0.operators.map(\.name) }
        let topScore = plans.first?.score ?? 0
        return LLMDecisionResponse(
            kind: .reasoningPlan,
            recommendation: "select highest-scored plan",
            confidence: min(topScore, 0.95),
            rankedActions: rankedNames,
            notes: ["evaluated \(plans.count) candidate plans"]
        )
    }

    public func assistPatchGeneration(
        errorSignature: String,
        snapshot: RepositorySnapshot?,
        memoryInfluence: MemoryInfluence
    ) -> LLMDecisionResponse {
        var notes: [String] = []
        if let preferred = memoryInfluence.preferredFixPath {
            notes.append("memory prefers path: \(preferred)")
        }
        if !memoryInfluence.avoidedPaths.isEmpty {
            notes.append("memory avoids \(memoryInfluence.avoidedPaths.count) paths")
        }
        return LLMDecisionResponse(
            kind: .patchAssistance,
            recommendation: "generate patches informed by memory and graph",
            confidence: 0.6,
            rankedActions: [],
            notes: notes
        )
    }

    public func assistRecoveryReasoning(
        failure: FailureClass,
        state: ReasoningPlanningState,
        memoryInfluence: MemoryInfluence
    ) -> LLMDecisionResponse {
        let preferredStrategy = memoryInfluence.preferredRecoveryStrategy
        return LLMDecisionResponse(
            kind: .recoveryAssistance,
            recommendation: preferredStrategy ?? "evaluate available recovery strategies",
            confidence: preferredStrategy != nil ? 0.7 : 0.5,
            rankedActions: preferredStrategy.map { [$0] } ?? [],
            notes: ["failure class: \(failure.rawValue)"]
        )
    }

    public func rankActionCandidates(
        candidates: [ActionContract],
        goal: Goal,
        worldState: WorldState,
        memoryInfluence: MemoryInfluence
    ) -> LLMDecisionResponse {
        let rankedNames = candidates.map(\.skillName)
        return LLMDecisionResponse(
            kind: .actionRanking,
            recommendation: "ranked \(candidates.count) action candidates",
            confidence: 0.65,
            rankedActions: rankedNames,
            notes: ["LLM ranking applied with memory and graph hints"]
        )
    }

    private func assembleContextHints(
        worldState: WorldState,
        memoryInfluence: MemoryInfluence
    ) -> [String] {
        var hints: [String] = []
        if let app = worldState.observation.app {
            hints.append("active app: \(app)")
        }
        if !memoryInfluence.notes.isEmpty {
            hints.append(contentsOf: memoryInfluence.notes)
        }
        if !memoryInfluence.evidence.isEmpty {
            hints.append("memory evidence: \(memoryInfluence.evidence.count) items")
        }
        return hints
    }
}
