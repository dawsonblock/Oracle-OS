import Foundation

// AgentLoop is the authoritative runtime spine for orchestration only.
// It may request state, decision, execution, learning, and recovery stages,
// then terminate or continue. It must not absorb ranking, graph scoring,
// experiment comparison, or direct world mutation logic.
@MainActor
public final class AgentLoop {
    let planner: Planner
    let graphStore: GraphStore
    let experimentCoordinator: LoopExperimentCoordinator
    let learningCoordinator: LearningCoordinator
    let stateCoordinator: StateCoordinator
    let decisionCoordinator: DecisionCoordinator
    let executionCoordinator: ExecutionCoordinator
    let recoveryCoordinator: RecoveryCoordinator

    /// Committed world model — the single authority the planner reads from.
    ///
    /// Updated incrementally via `StateDiffEngine` after every perception cycle
    /// to prevent the planner from reasoning over raw, un-abstracted perception
    /// data. See ``WorldStateModel`` for the three-layer state design.
    public let worldModel: WorldStateModel

    public init(
        observationProvider: any ObservationProvider,
        executionDriver: any AgentExecutionDriver,
        stateAbstraction: StateAbstraction = StateAbstraction(),
        planner: Planner = Planner(),
        graphStore: GraphStore = GraphStore(),
        policyEngine: PolicyEngine = PolicyEngine(),
        recoveryEngine: RecoveryEngine = RecoveryEngine(),
        memoryStore: UnifiedMemoryStore = UnifiedMemoryStore(),
        skillRegistry: SkillRegistry = .live(),
        repositoryIndexer: RepositoryIndexer = RepositoryIndexer(),
        experimentManager: ExperimentManager = ExperimentManager(),
        automationHost: AutomationHost = .live(),
        browserPageStateBuilder: BrowserPageStateBuilder = BrowserPageStateBuilder(),
        stateMemoryIndex: StateMemoryIndex? = nil,
        planningGraphStore: PlanningGraphStore? = nil
    ) {
        self.planner = planner
        self.graphStore = graphStore
        self.worldModel = WorldStateModel()

        let projectMemoryCoordinator = LoopProjectMemoryCoordinator(memoryStore: memoryStore)
        let learningCoordinator = LearningCoordinator(
            memoryStore: memoryStore,
            projectMemoryCoordinator: projectMemoryCoordinator
        )
        self.learningCoordinator = learningCoordinator

        self.stateCoordinator = StateCoordinator(
            observationProvider: observationProvider,
            stateAbstraction: stateAbstraction,
            repositoryIndexer: repositoryIndexer,
            automationHost: automationHost,
            browserPageStateBuilder: browserPageStateBuilder
        )
        self.decisionCoordinator = DecisionCoordinator(
            planner: planner,
            graphStore: graphStore,
            memoryStore: memoryStore,
            stateMemoryIndex: stateMemoryIndex,
            planningGraphStore: planningGraphStore
        )
        self.executionCoordinator = ExecutionCoordinator(
            executionDriver: executionDriver,
            skillRegistry: skillRegistry,
            policyEngine: policyEngine,
            memoryStore: memoryStore
        )
        self.recoveryCoordinator = RecoveryCoordinator(
            observationProvider: observationProvider,
            stateAbstraction: stateAbstraction,
            recoveryEngine: recoveryEngine,
            executionCoordinator: self.executionCoordinator,
            learningCoordinator: learningCoordinator,
            repositoryIndexer: repositoryIndexer,
            automationHost: automationHost,
            browserPageStateBuilder: browserPageStateBuilder
        )
        self.experimentCoordinator = LoopExperimentCoordinator(
            experimentManager: experimentManager,
            executionCoordinator: self.executionCoordinator,
            observationProvider: observationProvider,
            stateAbstraction: stateAbstraction,
            recoveryEngine: recoveryEngine,
            memoryStore: memoryStore,
            repositoryIndexer: repositoryIndexer,
            projectMemoryCoordinator: projectMemoryCoordinator
        )
    }
}
