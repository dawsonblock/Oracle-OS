import Foundation

public final class LLMPlanGenerator: @unchecked Sendable {
    private let llmClient: LLMClient
    private let reasoningEngine: ReasoningEngine
    private let planEvaluator: PlanEvaluator

    public init(
        llmClient: LLMClient,
        reasoningEngine: ReasoningEngine = ReasoningEngine(),
        planEvaluator: PlanEvaluator
    ) {
        self.llmClient = llmClient
        self.reasoningEngine = reasoningEngine
        self.planEvaluator = planEvaluator
    }

    public func generate(
        state: ReasoningPlanningState,
        taskContext: TaskContext,
        goal: Goal,
        worldState: WorldState,
        graphStore: GraphStore,
        workflowIndex: WorkflowIndex,
        memoryStore: AppMemoryStore,
        selectedStrategy: SelectedStrategy
    ) async -> [PlanCandidate] {
        let deterministicPlans = reasoningEngine.generatePlans(from: state)

        let llmPlans = await requestLLMPlans(state: state, goal: goal, selectedStrategy: selectedStrategy)

        var combined = deterministicPlans + llmPlans

        // ── Strategy filter: drop plans outside allowed operator families ──
        combined = combined.filter { $0.isAllowed(by: selectedStrategy) }

        return planEvaluator.evaluate(
            plans: combined,
            taskContext: taskContext,
            goal: goal,
            worldState: worldState,
            graphStore: graphStore,
            workflowIndex: workflowIndex,
            memoryStore: memoryStore
        )
    }

    public func bestPlan(
        state: ReasoningPlanningState,
        taskContext: TaskContext,
        goal: Goal,
        worldState: WorldState,
        graphStore: GraphStore,
        workflowIndex: WorkflowIndex,
        memoryStore: AppMemoryStore,
        minimumScore: Double = 0.6,
        selectedStrategy: SelectedStrategy
    ) async -> PlanCandidate? {
        let scored = await generate(
            state: state,
            taskContext: taskContext,
            goal: goal,
            worldState: worldState,
            graphStore: graphStore,
            workflowIndex: workflowIndex,
            memoryStore: memoryStore,
            selectedStrategy: selectedStrategy
        )
        return planEvaluator.chooseBestPlan(scored, minimumScore: minimumScore)
    }

    private func requestLLMPlans(
        state: ReasoningPlanningState,
        goal: Goal,
        selectedStrategy: SelectedStrategy
    ) async -> [PlanCandidate] {
        let prompt = buildPrompt(state: state, goal: goal, selectedStrategy: selectedStrategy)
        let request = LLMRequest(
            prompt: prompt,
            modelTier: .planning,
            maxTokens: 1024
        )

        do {
            let response = try await llmClient.complete(request)
            let parsed = ReasoningParser.parsePlans(from: response.text)
            return ReasoningParser.toPlanCandidates(parsedPlans: parsed, state: state)
        } catch {
            return []
        }
    }

    private func buildPrompt(state: ReasoningPlanningState, goal: Goal, selectedStrategy: SelectedStrategy) -> String {
        var lines: [String] = []
        lines.append("You are controlling a computer operator.")
        lines.append("")

        // ── Strategy context ──
        lines.append("Current strategy: \(selectedStrategy.kind.rawValue)")
        lines.append("Allowed operator families: \(selectedStrategy.allowedOperatorFamilies.map(\.rawValue).joined(separator: ", "))")
        lines.append("IMPORTANT: Only generate plans using operators from the allowed families.")
        lines.append("")

        lines.append("Current state:")
        lines.append("- agent kind: \(state.agentKind.rawValue)")
        lines.append("- repo open: \(state.repoOpen)")
        lines.append("- modal present: \(state.modalPresent)")
        lines.append("- patch applied: \(state.patchApplied)")
        lines.append("- tests observed: \(state.testsObserved)")
        lines.append("")
        lines.append("Goal: \(goal.description)")
        lines.append("")
        lines.append("Available operators:")
        for kind in ReasoningOperatorKind.allCases {
            let op = Operator(kind: kind)
            if op.precondition(state) {
                lines.append("- \(kind.rawValue)")
            }
        }
        lines.append("")
        lines.append("Generate 3 candidate plans with steps, risk, and confidence.")
        return lines.joined(separator: "\n")
    }
}
