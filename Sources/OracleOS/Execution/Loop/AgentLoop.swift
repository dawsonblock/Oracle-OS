import Foundation

// AgentLoop is the authoritative runtime spine for orchestration only.
// It may request state, decision, execution, learning, and recovery stages,
// then terminate or continue. It must not absorb ranking, graph scoring,
// experiment comparison, or direct world mutation logic.
@MainActor
public final class AgentLoop {
    private let planner: MainPlanner
    private let graphStore: GraphStore
    private let experimentCoordinator: LoopExperimentCoordinator
    private let learningCoordinator: LearningCoordinator
    private let stateCoordinator: StateCoordinator
    private let decisionCoordinator: DecisionCoordinator
    private let executionCoordinator: ExecutionCoordinator
    private let recoveryCoordinator: RecoveryCoordinator
    private let stateMemoryIndex: StateMemoryIndex?

    public init(
        observationProvider: any ObservationProvider,
        executionDriver: any AgentExecutionDriver,
        stateAbstraction: StateAbstraction = StateAbstraction(),
        planner: MainPlanner = MainPlanner(),
        graphStore: GraphStore = GraphStore(),
        policyEngine: PolicyEngine = PolicyEngine(),
        recoveryEngine: RecoveryEngine = RecoveryEngine(),
        memoryStore: StrategyMemory = StrategyMemory(),
        skillRegistry: SkillRegistry = .live(),
        repositoryIndexer: RepositoryIndexer = RepositoryIndexer(),
        experimentManager: ExperimentManager = ExperimentManager(),
        automationHost: AutomationHost = .live(),
        browserPageStateBuilder: BrowserPageStateBuilder = BrowserPageStateBuilder(),
        stateMemoryIndex: StateMemoryIndex? = nil
    ) {
        self.planner = planner
        self.graphStore = graphStore
        self.stateMemoryIndex = stateMemoryIndex

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
            stateMemoryIndex: stateMemoryIndex
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
