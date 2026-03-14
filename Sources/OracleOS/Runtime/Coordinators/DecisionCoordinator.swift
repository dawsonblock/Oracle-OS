import Foundation

/// The sole planner façade for the runtime loop.
///
/// `DecisionCoordinator` is the **only** path from runtime into the planning
/// subsystem.  It routes each decision through strategy selection
/// (``StrategySelector``/``StrategyEvaluator``) and planner evaluation
/// (``Planner``), then hardens the result before returning it to the loop.
///
/// - Important: This coordinator **plans** but never **executes**.  Action
///   execution is the responsibility of `VerifiedActionExecutor`.
@MainActor
public final class DecisionCoordinator {
    private static let defaultExplorationFallbackReason = "planner returned bounded exploration after stronger workflow and graph options were unavailable"

    private let planner: Planner
    private let graphStore: GraphStore
    private let memoryStore: AppMemoryStore
    private let strategySelector: StrategySelector
    private let strategyEvaluator: StrategyEvaluator
    private let stateMemoryIndex: StateMemoryIndex?
    private let planningGraphStore: PlanningGraphStore?

    /// The currently active strategy. Persists across steps to prevent thrashing.
    private var activeStrategy: SelectedStrategy?

    public init(
        planner: Planner = Planner(),
        graphStore: GraphStore = GraphStore(),
        memoryStore: AppMemoryStore = AppMemoryStore(),
        strategySelector: StrategySelector = StrategySelector(),
        strategyEvaluator: StrategyEvaluator = StrategyEvaluator(),
        stateMemoryIndex: StateMemoryIndex? = nil,
        planningGraphStore: PlanningGraphStore? = nil
    ) {
        self.planner = planner
        self.graphStore = graphStore
        self.memoryStore = memoryStore
        self.strategySelector = strategySelector
        self.strategyEvaluator = strategyEvaluator
        self.stateMemoryIndex = stateMemoryIndex
        self.planningGraphStore = planningGraphStore
    }

    public func setGoal(_ goal: Goal) {
        planner.setGoal(goal)
    }

    public func goalReached(in stateBundle: LoopStateBundle) -> Bool {
        planner.goalReached(state: stateBundle.worldState.planningState)
    }

    /// The selected strategy for the most recent planning cycle, if any.
    public var selectedStrategy: SelectedStrategy? {
        activeStrategy
    }

    public func decide(from stateBundle: LoopStateBundle) -> PlannerDecision? {
        // ── Step 1: Build strategy context ──
        let memoryInfluence = MemoryRouter(memoryStore: memoryStore).influence(
            for: MemoryQueryContext(
                taskContext: stateBundle.taskContext,
                worldState: stateBundle.worldState
            )
        )

        // ── Step 2: Reevaluate strategy if needed ──
        let reevalCause = strategyEvaluator.shouldReevaluate()
        let strategy: SelectedStrategy
        if let active = activeStrategy, reevalCause == nil {
            strategy = active
            strategyEvaluator.recordStep()
        } else {
            strategy = strategySelector.selectStrategy(
                goal: stateBundle.taskContext.goal,
                worldState: stateBundle.worldState,
                memoryInfluence: memoryInfluence,
                workflowIndex: planner.workflowIndex,
                agentKind: stateBundle.taskContext.agentKind,
                recentFailureCount: stateBundle.recentFailureCount
            )
            activeStrategy = strategy
            strategyEvaluator.setCurrentStrategy(strategy)
        }

        // ── Step 3: Call planner with selected strategy ──
        guard let decision = planner.nextStep(
            worldState: stateBundle.worldState,
            graphStore: graphStore,
            memoryStore: memoryStore,
            selectedStrategy: strategy
        ) else {
            return nil
        }

        let hardened = Self.harden(decision: decision, taskContext: stateBundle.taskContext)
        guard let result = hardened else { return nil }

        if memoryInfluence.avoidedPaths.contains(where: {
            result.actionContract.workspaceRelativePath == $0
        }) {
            let notes = result.notes + ["memory avoids this path; decision retained with warning"]
            return result.normalized(
                fallbackReason: result.fallbackReason,
                notes: notes
            )
        }

        return result
    }

    static func harden(
        decision: PlannerDecision,
        taskContext: TaskContext
    ) -> PlannerDecision? {
        guard decision.actionContract.skillName.isEmpty == false else {
            return nil
        }

        if decision.executionMode == .experiment, decision.experimentSpec == nil {
            return nil
        }

        switch decision.source {
        case .workflow:
            guard decision.workflowID != nil, decision.workflowStepID != nil else {
                return nil
            }
        case .stableGraph:
            guard decision.currentEdgeID != nil || decision.pathEdgeIDs.isEmpty == false else {
                return nil
            }
        case .candidateGraph:
            guard decision.currentEdgeID != nil || decision.pathEdgeIDs.isEmpty == false else {
                return nil
            }
        case .exploration:
            let fallbackReason = decision.fallbackReason?.trimmingCharacters(in: .whitespacesAndNewlines)
            if fallbackReason?.isEmpty != false {
                return decision.normalized(
                    fallbackReason: defaultExplorationFallbackReason,
                    notes: decision.notes + ["decision coordinator added explicit exploration fallback reason"]
                )
            }
        case .recovery:
            break
        }

        if taskContext.agentKind != .mixed,
           decision.source != .recovery,
           decision.agentKind != taskContext.agentKind
        {
            return nil
        }

        return decision
    }
}
