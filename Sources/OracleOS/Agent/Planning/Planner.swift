import Foundation

// Planner chooses execution structure only: workflow, graph path, graph edge,
// or bounded exploration. It must not resolve exact UI targets, mutate files,
// execute commands, or inline recovery mechanics.
//
// The planner navigates the live TaskGraph as its primary control substrate.
// Each planning cycle:
//   1. Updates the current task-graph node from world state
//   2. Expands candidate edges from the current node
//   3. Evaluates future paths via GraphNavigator
//   4. Selects the best edge
// The task graph is the canonical representation of task position — not
// a post-hoc log.
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
    public let taskGraphStore: TaskGraphStore
    private let graphNavigator: GraphNavigator
    private let graphScorer: GraphScorer

    public init(
        workflowIndex: WorkflowIndex? = nil,
        osPlanner: OSPlanner? = nil,
        codePlanner: CodePlanner? = nil,
        mixedTaskPlanner: MixedTaskPlanner? = nil,
        reasoningEngine: ReasoningEngine? = nil,
        promptEngine: PromptEngine = PromptEngine(),
        reasoningThreshold: Double = 0.6,
        taskGraphStore: TaskGraphStore? = nil
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
        self.taskGraphStore = taskGraphStore ?? TaskGraphStore()
        self.graphNavigator = GraphNavigator()
        self.graphScorer = GraphScorer()
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
        memoryStore: AppMemoryStore = AppMemoryStore(),
        selectedStrategy: SelectedStrategy? = nil
    ) -> PlannerDecision? {
        guard let currentGoal else { return nil }

        // Hard gate: strategy selection must occur before plan generation.
        // When no strategy is provided, we create a permissive default to
        // preserve backward compatibility with callers that haven't been
        // updated yet. New code paths always provide a strategy.
        let strategy = selectedStrategy ?? SelectedStrategy(
            kind: .graphNavigation,
            confidence: 0.3,
            rationale: "fallback: no strategy provided to planner",
            allowedOperatorFamilies: OperatorFamily.allCases.map { $0 }
        )
        precondition(!strategy.allowedOperatorFamilies.isEmpty,
                     "SelectedStrategy must have at least one allowed operator family")

        let workspaceRoot = currentGoal.workspaceRoot.map { URL(fileURLWithPath: $0, isDirectory: true) }
        let taskContext = TaskContext.from(goal: currentGoal, workspaceRoot: workspaceRoot)

        // ── Task-graph substrate: update the current node from world state ──
        // The graph is the canonical representation of task position.
        let currentTaskNode = taskGraphStore.updateCurrentNode(
            worldState: worldState
        )

        // ── Task-graph substrate: try graph-navigated decision first ──
        // Expand candidate edges from the current node and evaluate paths.
        let taskGraphDecision = taskGraphNavigatedDecision(
            taskNode: currentTaskNode,
            taskContext: taskContext,
            worldState: worldState,
            graphStore: graphStore,
            memoryStore: memoryStore,
            selectedStrategy: strategy
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
            fallbackDecision: familyDecision,
            selectedStrategy: strategy
        )

        let decision = selectBestDecision(
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

    private func selectBestDecision(
        familyDecision: PlannerDecision?,
        reasoningDecision: PlannerDecision?,
        taskGraphDecision: PlannerDecision? = nil,
        taskContext: TaskContext,
        worldState: WorldState,
        memoryStore: AppMemoryStore
    ) -> PlannerDecision? {
        let memoryInfluence = MemoryRouter(memoryStore: memoryStore).influence(
            for: MemoryQueryContext(taskContext: taskContext, worldState: worldState)
        )
        let memoryBias = MemoryScorer.planBias(influence: memoryInfluence)

        // Task-graph navigated decisions get a confidence boost because they
        // represent path-expanded, evidence-backed selections from the live
        // graph substrate rather than isolated one-shot decisions.
        let taskGraphScore = taskGraphDecision.map { decision -> Double in
            let baseScore = sourceConfidence(decision.source) + memoryBias
            // Boost for task-graph navigation: the decision was scored via
            // multi-step path expansion.
            return baseScore + 0.1
        }

        switch (familyDecision, reasoningDecision) {
        case let (family?, reasoning?):
            // Memory bias applies only to the family score — it reflects historical
            // confidence in familiar sources (graph, workflow). Reasoning scores
            // are already memory-aware via the ReasoningPlanningState input.
            let familyScore = sourceConfidence(family.source) + memoryBias
            // When reasoning has no plan diagnostics (e.g. no viable plans generated),
            // score defaults to 0 so the family decision is preferred.
            let reasoningScore = reasoning.planDiagnostics?.candidatePlans.first?.score ?? 0

            // If the task-graph path decision outscores both, prefer it.
            if let tgScore = taskGraphScore, let tgDecision = taskGraphDecision,
               tgScore >= familyScore && tgScore >= reasoningScore {
                return tgDecision
            }

            if family.source == .workflow || family.source == .stableGraph {
                return familyScore >= reasoningScore ? family : reasoning
            }
            return reasoningScore > familyScore ? reasoning : family
        case let (family?, nil):
            if let tgScore = taskGraphScore, let tgDecision = taskGraphDecision {
                let familyScore = sourceConfidence(family.source) + memoryBias
                return tgScore >= familyScore ? tgDecision : family
            }
            return family
        case let (nil, reasoning?):
            if let tgScore = taskGraphScore, let tgDecision = taskGraphDecision {
                let reasoningScore = reasoning.planDiagnostics?.candidatePlans.first?.score ?? 0
                return tgScore >= reasoningScore ? tgDecision : reasoning
            }
            return reasoning
        case (nil, nil):
            return taskGraphDecision
        }
    }

    // Confidence values represent how reliable each planner source is based on
    // validation level: workflows are fully validated replay sequences (0.9),
    // stable graph edges are promoted from multiple observed transitions (0.75),
    // candidate edges have fewer observations (0.5), recovery is contextual (0.4),
    // and exploration is unbacked by prior evidence (0.3).
    private func sourceConfidence(_ source: PlannerSource) -> Double {
        switch source {
        case .workflow: return 0.9
        case .stableGraph: return 0.75
        case .candidateGraph: return 0.5
        case .exploration: return 0.3
        case .recovery: return 0.4
        }
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
        taskNode: TaskNode,
        taskContext: TaskContext,
        worldState: WorldState,
        graphStore: GraphStore,
        memoryStore: AppMemoryStore,
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
        let goalState = currentGoal.flatMap { GraphScorer.goalAbstractState(from: $0) }
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
    /// Delegates to ``GraphNavigator.operatorFamilyForAction`` for consistency.
    private func operatorFamilyForSkill(_ skillName: String) -> OperatorFamily {
        GraphNavigator.operatorFamilyForAction(skillName)
    }
}
