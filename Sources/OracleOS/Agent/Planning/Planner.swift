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

public final class Planner {

    private let planGenerator: PlanGenerator
    public let taskGraphStore: TaskGraphStore

    public init(
        workflowIndex: WorkflowIndex? = nil,
        osPlanner: OSPlanner? = nil,
        codePlanner: CodePlanner? = nil,
        mixedTaskPlanner: MixedTaskPlanner? = nil,
        reasoningEngine: ReasoningEngine? = nil,
        planEvaluator: PlanEvaluator? = nil,
        promptEngine: PromptEngine = PromptEngine(),
        reasoningThreshold: Double = 0.6,
        taskGraphStore: TaskGraphStore? = nil
    ) {
        self.workflowIndex = workflowIndex ?? WorkflowIndex()
        let sharedWorkflowRetriever = WorkflowRetriever()
        let sharedPlanEvaluator = planEvaluator ?? PlanEvaluator(workflowRetriever: sharedWorkflowRetriever)
        
        self.planGenerator = PlanGenerator(
            reasoningEngine: reasoningEngine ?? ReasoningEngine(),
            planEvaluator: sharedPlanEvaluator,
            osPlanner: osPlanner,
            codePlanner: codePlanner,
            mixedTaskPlanner: mixedTaskPlanner
        )
        self.workflowRetriever = sharedWorkflowRetriever
        self.osPlanner = osPlanner ?? OSPlanner()
        self.codePlanner = codePlanner ?? CodePlanner()
        self.mixedTaskPlanner = mixedTaskPlanner ?? MixedTaskPlanner(osPlanner: self.osPlanner, codePlanner: self.codePlanner)
        self.reasoningEngine = reasoningEngine ?? ReasoningEngine()
        self.planEvaluator = sharedPlanEvaluator
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
        Goal.interpret(description)
    }


    public func goalReached(state: PlanningState) -> Bool {
        guard let currentGoal else { return false }
        return currentGoal.matchScore(state: state) >= 1
    }


    public func nextStep(
        worldState: WorldState,
        graphStore: GraphStore,
        memoryStore: UnifiedMemoryStore = UnifiedMemoryStore(),
        selectedStrategy: SelectedStrategy
    ) -> PlannerDecision? {
        guard let currentGoal else { return nil }

        let workspaceRoot = currentGoal.workspaceRoot.map { URL(fileURLWithPath: $0, isDirectory: true) }
        let taskContext = TaskContext.from(goal: currentGoal, workspaceRoot: workspaceRoot)
        
        let memoryInfluence = MemoryRouter(memoryStore: memoryStore).influence(
            for: MemoryQueryContext(taskContext: taskContext, worldState: worldState)
        )
        let reasoningState = ReasoningPlanningState(
            taskContext: taskContext,
            worldState: worldState,
            memoryInfluence: memoryInfluence
        )

        let bestCandidate = planGenerator.bestPlan(
            state: reasoningState,
            taskContext: taskContext,
            goal: currentGoal,
            worldState: worldState,
            graphStore: graphStore,
            workflowIndex: workflowIndex,
            memoryStore: memoryStore,
            minimumScore: reasoningThreshold,
            selectedStrategy: selectedStrategy
        )

        guard let selectedPlan = bestCandidate,
              let selectedOperator = selectedPlan.operators.first,
              let actionContract = selectedOperator.actionContract(for: reasoningState, goal: currentGoal)
        else {
            return nil
        }

        return PlannerDecision(
            agentKind: selectedOperator.agentKind,
            plannerFamily: plannerFamily(for: taskContext.agentKind),
            stepPhase: selectedOperator.stepPhase,
            actionContract: actionContract,
            source: selectedPlan.sourceType ?? .exploration,
            fallbackReason: selectedPlan.reasons.first ?? "Reasoning-selected plan",
            semanticQuery: selectedOperator.semanticQuery(for: reasoningState, goal: currentGoal),
            projectMemoryRefs: memoryInfluence.projectMemoryRefs,
            notes: selectedPlan.reasons
        )
    }


    // Removed conservative fallback to favor GraphNavigator-backed version.


    private func selectBestDecision(
        familyDecision: PlannerDecision?,
        reasoningDecision: PlannerDecision?,
        taskGraphDecision: PlannerDecision? = nil,
        taskContext: TaskContext,
        worldState: WorldState,
        memoryStore: UnifiedMemoryStore
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

        var scoredDecisions: [(decision: PlannerDecision, score: Double)] = []

        if let decision = taskGraphDecision, let score = taskGraphScore {
            scoredDecisions.append((decision: decision, score: score))
        }

        if let decision = familyDecision {
            let score = sourceConfidence(decision.source) + memoryBias
            scoredDecisions.append((decision: decision, score: score))
        }

        if let decision = reasoningDecision {
            let score = sourceConfidence(decision.source) + memoryBias
            scoredDecisions.append((decision: decision, score: score))
        }

        guard !scoredDecisions.isEmpty else {
            return nil
        }

        // Select the decision with the highest score.
        return scoredDecisions.max(by: { $0.score < $1.score })?.decision
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
        graphStore: GraphStore,
        selectedStrategy: SelectedStrategy
    ) -> ActionContract? {
        nextStep(worldState: worldState, graphStore: graphStore, selectedStrategy: selectedStrategy)?.actionContract
    }

    public func plan(goal: String) -> Plan {
        let interpretedGoal = interpretGoal(goal)
        setGoal(interpretedGoal)
        return Plan(goal: goal, steps: ["graph-aware"])
    }
}

