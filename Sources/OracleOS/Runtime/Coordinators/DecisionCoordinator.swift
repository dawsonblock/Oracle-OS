import Foundation

@MainActor
public final class DecisionCoordinator {
    private static let defaultExplorationFallbackReason = "planner returned bounded exploration after stronger workflow and graph options were unavailable"

    private let planner: Planner
    private let graphStore: GraphStore
    private let memoryStore: AppMemoryStore

    public init(
        planner: Planner = Planner(),
        graphStore: GraphStore = GraphStore(),
        memoryStore: AppMemoryStore = AppMemoryStore()
    ) {
        self.planner = planner
        self.graphStore = graphStore
        self.memoryStore = memoryStore
    }

    public func setGoal(_ goal: Goal) {
        planner.setGoal(goal)
    }

    public func goalReached(in stateBundle: LoopStateBundle) -> Bool {
        planner.goalReached(state: stateBundle.worldState.planningState)
    }

    public func decide(from stateBundle: LoopStateBundle) -> PlannerDecision? {
        guard let decision = planner.nextStep(
            worldState: stateBundle.worldState,
            graphStore: graphStore,
            memoryStore: memoryStore
        ) else {
            return nil
        }

        let hardened = Self.harden(decision: decision, taskContext: stateBundle.taskContext)
        guard let result = hardened else { return nil }

        let memoryInfluence = MemoryRouter(memoryStore: memoryStore).influence(
            for: MemoryQueryContext(
                taskContext: stateBundle.taskContext,
                worldState: stateBundle.worldState
            )
        )

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
