import Foundation

// Planner chooses execution structure only: workflow, graph path, graph edge,
// or bounded exploration. It must not resolve exact UI targets, mutate files,
// execute commands, or inline recovery mechanics.
//
// The planner navigates the live TaskLedger as its primary control substrate.
// Each planning cycle:
//   1. Updates the current task-graph node from world state
//   2. Expands candidate edges from the current node
//   3. Evaluates future paths via LedgerNavigator
//   4. Selects the best edge
// The task graph is the canonical representation of task position — not
// a post-hoc log.
public final class MainPlanner: @unchecked Sendable {
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
    public let taskGraphStore: TaskLedgerStore
    private let graphNavigator: LedgerNavigator
    private let graphScorer: LedgerScorer

    public init(
        workflowIndex: WorkflowIndex? = nil,
        osPlanner: OSPlanner? = nil,
        codePlanner: CodePlanner? = nil,
        mixedTaskPlanner: MixedTaskPlanner? = nil,
        reasoningEngine: ReasoningEngine? = nil,
        promptEngine: PromptEngine = PromptEngine(),
        reasoningThreshold: Double = 0.6,
        taskGraphStore: TaskLedgerStore? = nil
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
        self.taskGraphStore = taskGraphStore ?? TaskLedgerStore()
        self.graphNavigator = LedgerNavigator()
        self.graphScorer = LedgerScorer()
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
        memoryStore: StrategyMemory = StrategyMemory(),
        selectedStrategy: SelectedStrategy
    ) -> PlannerDecision? {
        guard let currentGoal else { return nil }

        // Hard gate: strategy selection must occur before plan generation.
        precondition(!selectedStrategy.allowedOperatorFamilies.isEmpty,
                     "SelectedStrategy must have at least one allowed operator family")
        let strategy = selectedStrategy

        let workspaceRoot = currentGoal.workspaceRoot.map { URL(fileURLWithPath: $0, isDirectory: true) }
        let taskContext = TaskContext.from(goal: currentGoal, workspaceRoot: workspaceRoot)

        // ── Task-graph substrate: update the current node from world state ──
        // The graph is the canonical representation of task position.
        let currentTaskRecord = taskGraphStore.updateCurrentNode(
            worldState: worldState
        )

        // ── Task-graph substrate: try graph-navigated decision first ──
        // Expand candidate edges from the current node and evaluate paths.
        let taskGraphDecision = taskGraphNavigatedDecision(
            taskNode: currentTaskRecord,
            taskContext: taskContext,
            worldState: worldState,
            graphStore: graphStore,
            memoryStore: memoryStore
        )

        // Deliberate plan comparison:
        // 1. Gather candidates from family planner (workflow, graph, exploration)
        // 2. Gather candidates from reasoning engine
        // 3. Score all candidates and pick the best deliberate plan
        // 4. Escalate to experiment when confidence is low
        let familyDecision = familyPlannerDecision(
            taskContext: taskContext,
            worldState: worldState,
            graphStore: graphStore,
            memoryStore: memoryStore
        )

        // Reasoning runs sequentially after the family planner to allow
        // deliberate comparison rather than blind fallthrough.
        let reasoning = reasoningDecision(
            taskContext: taskContext,
            worldState: worldState,
            graphStore: graphStore,
            memoryStore: memoryStore,
            fallbackDecision: familyDecision
        )

        let decision = PlanSelection.selectBest(
            familyDecision: familyDecision,
            reasoningDecision: reasoning,
            taskGraphDecision: taskGraphDecision,
            taskContext: taskContext,
            worldState: worldState,
            memoryStore: memoryStore
        )

        // ── Safety net: drop any decision whose operator family violates the strategy ──
        if let decision {
            let skillName = decision.actionContract.skillName
            let family = operatorFamilyForSkill(skillName)
            if !strategy.allows(family) {
                // Strategy violation — suppress this decision.
                return nil
            }
        }

        return decision
    }

    /// Derive an operator family for a given skill name.
    ///
    /// Note: without access to the full action-contract type hierarchy here,
    /// we conservatively fall back to the first available operator family.
    /// This relies on `OperatorFamily` being `CaseIterable` and non-empty,
    /// which is already assumed elsewhere in this planner.
    private func operatorFamilyForSkill(_ skillName: String) -> OperatorFamily {
        // Fallback: use the first defined operator family as a deterministic default.
        // If more precise mapping is needed, this function can be extended to
        // inspect the skill name or associated contract metadata.
        precondition(!OperatorFamily.allCases.isEmpty,
                     "OperatorFamily must have at least one case")
        // Force unwrap is safe due to the precondition above.
        return OperatorFamily.allCases.first!
    }



    private func familyPlannerDecision(
        taskContext: TaskContext,
        worldState: WorldState,
        graphStore: GraphStore,
        memoryStore: StrategyMemory
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
        memoryStore: StrategyMemory,
        fallbackDecision: PlannerDecision?,
        selectedStrategy: SelectedStrategy? = nil
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
        let allPlans = reasoningEngine.generatePlans(from: reasoningState)

        // ── Strategy filter: drop plans whose operators are outside the allowed families ──
        let plans: [PlanCandidate]
        if let strategy = selectedStrategy {
            plans = allPlans.filter { candidate in
                candidate.operators.allSatisfy { op in
                    strategy.allows(op.kind.operatorFamily)
                }
            }
        } else {
            plans = allPlans
        }

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

    /// Use the task graph as the live planning substrate: expand paths from
    /// the current node, score them, and return the best edge as a decision.
    private func taskGraphNavigatedDecision(
        taskNode: TaskRecord,
        taskContext: TaskContext,
        worldState: WorldState,
        graphStore: GraphStore,
        memoryStore: StrategyMemory,
        selectedStrategy: SelectedStrategy? = nil
    ) -> PlannerDecision? {
        let graph = taskGraphStore.graph
        let nodeID = taskNode.id
        var outgoing = graph.viableEdges(from: nodeID)

        // ── Strategy filter: only expand edges whose operator family is strategy-allowed ──
        if let strategy = selectedStrategy {
            outgoing = outgoing.filter { edge in
                let family = operatorFamilyForSkill(edge.action)
                return strategy.allows(family)
            }
        }

        guard !outgoing.isEmpty else { return nil }

        // Compute memory bias for graph scoring.
        let memoryInfluence = MemoryRouter(memoryStore: memoryStore).influence(
            for: MemoryQueryContext(taskContext: taskContext, worldState: worldState)
        )
        let memoryBias = MemoryScorer.planBias(influence: memoryInfluence)

        // Expand paths from the current node and score them.
        let paths = graphNavigator.expand(
            from: nodeID,
            in: graph,
            scorer: graphScorer,
            goal: currentGoal,
            allowedFamilies: selectedStrategy?.allowedOperatorFamilies
        )

        guard let bestPath = paths.first,
              let bestEdge = bestPath.edges.first,
              let contractID = bestEdge.actionContractID else {
            return nil
        }

        let actionContract = graphStore.actionContract(for: contractID)
        guard let actionContract else { return nil }

        // Compute score breakdown for the selected edge to expose memory bias.
        let goalState = currentGoal.flatMap { LedgerScorer.goalAbstractState(from: $0) }
        let targetNode = graph.node(for: bestEdge.toNodeID)
        let breakdown = graphScorer.scoreEdgeWithBreakdown(
            bestEdge,
            goalState: goalState,
            targetState: targetNode?.abstractState,
            memoryBias: memoryBias
        )

        return PlannerDecision(
            agentKind: actionContract.agentKind,
            plannerFamily: plannerFamily(for: taskContext.agentKind),
            stepPhase: stepPhase(for: actionContract.agentKind),
            actionContract: actionContract,
            source: .stableGraph,
            fallbackReason: "task-graph path expansion selected edge",
            notes: [
                "task-graph navigated decision",
                "path depth: \(bestPath.edges.count)",
                "path score: \(String(format: "%.3f", bestPath.cumulativeScore))",
                "terminal state: \(bestPath.terminalState?.rawValue ?? "unknown")",
                "memory_bias_contribution: \(String(format: "%.3f", breakdown.memoryBias))",
                "candidate_paths: \(paths.count)",
            ]
        )
    }

    private func stepPhase(for agentKind: AgentKind) -> TaskPhase {
        switch agentKind {
        case .os:
            return .operatingSystem
        case .code:
            return .engineering
        case .mixed:
            // Default to operating system phase for mixed tasks to preserve existing behavior.
            return .operatingSystem
        }
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

    // MARK: - Operator family classification

    /// Infer the ``OperatorFamily`` for a skill or action name.
    ///
    /// Delegates to ``LedgerNavigator.operatorFamilyForAction`` for consistency.
    private func operatorFamilyForSkill(_ skillName: String) -> OperatorFamily {
        LedgerNavigator.operatorFamilyForAction(skillName)
    }
}
