import Foundation

// Planner chooses execution structure only: workflow, graph path, graph edge,
// or bounded exploration. It must not resolve exact UI targets, mutate files,
// execute commands, or inline recovery mechanics.
public final class Planner: @unchecked Sendable {
    private var currentGoal: Goal?
    public let workflowIndex: WorkflowIndex
    private let workflowRetriever: WorkflowRetriever
    private let osPlanner: OSPlanner
    private let codePlanner: CodePlanner
    private let mixedTaskPlanner: MixedTaskPlanner
    private let reasoningEngine: ReasoningEngine
    private let planEvaluator: PlanEvaluator
    private let promptEngine: PromptEngine
    private let reasoningThreshold: Double

    public init(
        workflowIndex: WorkflowIndex? = nil,
        osPlanner: OSPlanner? = nil,
        codePlanner: CodePlanner? = nil,
        mixedTaskPlanner: MixedTaskPlanner? = nil,
        reasoningEngine: ReasoningEngine? = nil,
        promptEngine: PromptEngine = PromptEngine(),
        reasoningThreshold: Double = 0.6
    ) {
        let sharedWorkflowIndex = workflowIndex ?? WorkflowIndex()
        let sharedGraphPlanner = GraphPlanner(maxDepth: 6, beamWidth: 5)
        let sharedWorkflowRetriever = WorkflowRetriever()
        let sharedWorkflowExecutor = WorkflowExecutor()
        let resolvedOSPlanner = osPlanner ?? OSPlanner(
            graphPlanner: sharedGraphPlanner,
            workflowIndex: sharedWorkflowIndex,
            workflowRetriever: sharedWorkflowRetriever,
            workflowExecutor: sharedWorkflowExecutor
        )
        let resolvedCodePlanner = codePlanner ?? CodePlanner(
            graphPlanner: sharedGraphPlanner,
            workflowIndex: sharedWorkflowIndex,
            workflowRetriever: sharedWorkflowRetriever,
            workflowExecutor: sharedWorkflowExecutor
        )
        self.workflowIndex = sharedWorkflowIndex
        self.workflowRetriever = sharedWorkflowRetriever
        self.osPlanner = resolvedOSPlanner
        self.codePlanner = resolvedCodePlanner
        self.mixedTaskPlanner = mixedTaskPlanner ?? MixedTaskPlanner(
            osPlanner: resolvedOSPlanner,
            codePlanner: resolvedCodePlanner
        )
        self.reasoningEngine = reasoningEngine ?? ReasoningEngine()
        self.planEvaluator = PlanEvaluator(workflowRetriever: sharedWorkflowRetriever)
        self.promptEngine = promptEngine
        self.reasoningThreshold = reasoningThreshold
    }

    public func setGoal(_ goal: Goal) {
        currentGoal = goal
    }

    public func interpretGoal(_ description: String) -> Goal {
        let lowercased = description.lowercased()
        let targetApp: String?
        if lowercased.contains("gmail") || lowercased.contains("browser") || lowercased.contains("chrome") {
            targetApp = "Google Chrome"
        } else if lowercased.contains("finder") {
            targetApp = "Finder"
        } else {
            targetApp = nil
        }

        let targetDomain: String?
        if lowercased.contains("gmail") {
            targetDomain = "mail.google.com"
        } else if lowercased.contains("slack") {
            targetDomain = "slack.com"
        } else {
            targetDomain = nil
        }

        let targetTaskPhase: String?
        if lowercased.contains("compose") {
            targetTaskPhase = "compose"
        } else if lowercased.contains("inbox") {
            targetTaskPhase = "browse"
        } else if lowercased.contains("save") {
            targetTaskPhase = "save"
        } else if lowercased.contains("rename") {
            targetTaskPhase = "rename"
        } else {
            targetTaskPhase = nil
        }

        return Goal(
            description: description,
            targetApp: targetApp,
            targetDomain: targetDomain,
            targetTaskPhase: targetTaskPhase
        )
    }

    public func goalReached(state: PlanningState) -> Bool {
        guard let currentGoal else { return false }
        return Self.goalMatchScore(state: state, goal: currentGoal) >= 1
    }

    public func nextStep(
        worldState: WorldState,
        graphStore: GraphStore,
        memoryStore: AppMemoryStore = AppMemoryStore()
    ) -> PlannerDecision? {
        guard let currentGoal else { return nil }
        let workspaceRoot = currentGoal.workspaceRoot.map { URL(fileURLWithPath: $0, isDirectory: true) }
        let taskContext = TaskContext.from(goal: currentGoal, workspaceRoot: workspaceRoot)

        // Decision hierarchy:
        // 1. Workflow plan (highest priority)
        // 2. Graph-familiar plan (stable or candidate graph)
        // 3. Reasoning-generated plan
        // 4. Experiment plan
        // 5. Exploration plan (fallback)
        let familyDecision = familyPlannerDecision(
            taskContext: taskContext,
            worldState: worldState,
            graphStore: graphStore,
            memoryStore: memoryStore
        )

        if let decision = familyDecision,
           decision.source == .workflow || decision.source == .stableGraph || decision.source == .candidateGraph {
            return decision
        }

        if let reasoningDecision = reasoningDecision(
            taskContext: taskContext,
            worldState: worldState,
            graphStore: graphStore,
            memoryStore: memoryStore,
            fallbackDecision: familyDecision
        ) {
            return reasoningDecision
        }

        return familyDecision
    }

    private func familyPlannerDecision(
        taskContext: TaskContext,
        worldState: WorldState,
        graphStore: GraphStore,
        memoryStore: AppMemoryStore
    ) -> PlannerDecision? {
        switch taskContext.agentKind {
        case .os:
            return osPlanner.nextStep(
                taskContext: taskContext,
                worldState: worldState,
                graphStore: graphStore,
                memoryStore: memoryStore
            )
        case .code:
            return codePlanner.nextStep(
                taskContext: taskContext,
                worldState: worldState,
                graphStore: graphStore,
                memoryStore: memoryStore
            )
        case .mixed:
            return mixedTaskPlanner.nextStep(
                taskContext: taskContext,
                worldState: worldState,
                graphStore: graphStore,
                memoryStore: memoryStore
            )
        }
    }

    private func reasoningDecision(
        taskContext: TaskContext,
        worldState: WorldState,
        graphStore: GraphStore,
        memoryStore: AppMemoryStore,
        fallbackDecision: PlannerDecision?
    ) -> PlannerDecision? {
        let memoryInfluence = MemoryRouter(memoryStore: memoryStore).influence(
            for: MemoryQueryContext(
                taskContext: taskContext,
                worldState: worldState,
                errorSignature: currentGoal?.description
            )
        )
        let reasoningState = ReasoningPlanningState(
            taskContext: taskContext,
            worldState: worldState,
            memoryInfluence: memoryInfluence
        )
        let plans = reasoningEngine.generatePlans(from: reasoningState)
        let scoredPlans = planEvaluator.evaluate(
            plans: plans,
            taskContext: taskContext,
            goal: taskContext.goal,
            worldState: worldState,
            graphStore: graphStore,
            workflowIndex: workflowIndex,
            memoryStore: memoryStore
        )
        guard let selectedPlan = planEvaluator.chooseBestPlan(
            scoredPlans,
            minimumScore: reasoningThreshold
        ),
        let selectedOperator = selectedPlan.operators.first,
        let actionContract = selectedOperator.actionContract(for: reasoningState, goal: taskContext.goal)
        else {
            return nil
        }

        let fallbackReason = fallbackDecision?.fallbackReason
            ?? "family planner had no viable workflow or graph-backed step"
        let selectedNames = selectedPlan.operators.map(\.name)
        let diagnostics = PlanDiagnostics(
            selectedOperatorNames: selectedNames,
            candidatePlans: scoredPlans.map {
                ScoredPlanSummary(
                    operatorNames: $0.operators.map(\.name),
                    score: $0.score,
                    reasons: $0.reasons,
                    simulatedSuccessProbability: $0.simulatedOutcome?.successProbability,
                    simulatedRiskScore: $0.simulatedOutcome?.riskScore,
                    simulatedFailureMode: $0.simulatedOutcome?.likelyFailureMode
                )
            },
            fallbackReason: fallbackReason
        )
        let promptDiagnostics = promptEngine.planning(
            goal: taskContext.goal,
            taskContext: taskContext,
            worldState: worldState,
            selectedOperators: selectedNames,
            candidatePlans: scoredPlans.map {
                ScoredPlanSummary(
                    operatorNames: $0.operators.map(\.name),
                    score: $0.score,
                    reasons: $0.reasons,
                    simulatedSuccessProbability: $0.simulatedOutcome?.successProbability,
                    simulatedRiskScore: $0.simulatedOutcome?.riskScore,
                    simulatedFailureMode: $0.simulatedOutcome?.likelyFailureMode
                )
            },
            fallbackReason: fallbackReason,
            projectMemoryRefs: memoryInfluence.projectMemoryRefs,
            notes: selectedPlan.reasons
        ).diagnostics

        return PlannerDecision(
            agentKind: selectedOperator.agentKind,
            plannerFamily: plannerFamily(for: taskContext.agentKind),
            stepPhase: selectedOperator.stepPhase,
            actionContract: actionContract,
            source: .exploration,
            fallbackReason: fallbackReason,
            semanticQuery: selectedOperator.semanticQuery(for: reasoningState, goal: taskContext.goal),
            projectMemoryRefs: memoryInfluence.projectMemoryRefs,
            notes: [
                "reasoning-selected short plan",
                "selected operators: \(selectedNames.joined(separator: " -> "))",
            ] + selectedPlan.reasons,
            planDiagnostics: diagnostics,
            promptDiagnostics: promptDiagnostics
        )
    }

    private func plannerFamily(for agentKind: AgentKind) -> PlannerFamily {
        switch agentKind {
        case .os:
            return .os
        case .code:
            return .code
        case .mixed:
            return .mixed
        }
    }

    public func nextAction(
        worldState: WorldState,
        graphStore: GraphStore
    ) -> ActionContract? {
        nextStep(worldState: worldState, graphStore: graphStore)?.actionContract
    }

    public func plan(goal: String) -> Plan {
        let interpretedGoal = interpretGoal(goal)
        setGoal(interpretedGoal)
        return Plan(goal: goal, steps: ["graph-aware"])
    }

    public static func goalMatchScore(state: PlanningState, goal: Goal) -> Double {
        var matched = 0.0
        var possible = 0.0

        if let targetApp = goal.targetApp {
            possible += 1
            if state.appID == targetApp { matched += 1 }
        }
        if let targetDomain = goal.targetDomain {
            possible += 1
            if state.domain == targetDomain { matched += 1 }
        }
        if let targetTaskPhase = goal.targetTaskPhase {
            possible += 1
            if state.taskPhase == targetTaskPhase { matched += 1 }
        }

        guard possible > 0 else { return 0 }
        return matched / possible
    }
}
