import Foundation

/// AgentLoop is the runtime scheduler.
///
/// TARGET ARCHITECTURE:
///   AgentLoop only forwards intents to RuntimeOrchestrator.
///   It does not plan, execute, coordinate recovery, or mutate state.
///
///   IntentSource → AgentLoop → IntentAPI.submitIntent
///
/// CURRENT STATE:
///   The existing `run(goal:)` method in AgentLoop+Run.swift still
///   contains legacy coordination logic for backward compatibility
///   with the eval harness. Migration to pure scheduler mode is in progress.
@MainActor
public final class AgentLoop {
    let planner: MainPlanner
    let graphStore: GraphStore
    let experimentCoordinator: LoopExperimentCoordinator
    let learningCoordinator: LearningCoordinator
    let stateCoordinator: StateCoordinator
    let decisionCoordinator: DecisionCoordinator
    let executionCoordinator: ExecutionCoordinator
    let recoveryCoordinator: RecoveryCoordinator
    private let stateMemoryIndex: StateMemoryIndex?
    let worldModel: WorldStateModel

    /// The IntentAPI orchestrator — all execution flows through this.
    public private(set) var orchestrator: (any IntentAPI)?

    private var running = true

    /// Required init — all AgentLoop instances must have an IntentAPI orchestrator.
    public init(
        orchestrator: any IntentAPI,
        observationProvider: any ObservationProvider,
        executionDriver: any AgentExecutionDriver,
        stateAbstraction: StateAbstraction = StateAbstraction(),
        planner: MainPlanner = MainPlanner(),
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
        worldModel: WorldStateModel = WorldStateModel()
    ) {
        self.orchestrator = orchestrator
        self.planner = planner
        self.graphStore = graphStore
        self.stateMemoryIndex = stateMemoryIndex
        self.worldModel = worldModel

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

    // MARK: - Scheduler Mode (Target Architecture)

    /// Run as a pure scheduler: pull intents from source, forward to orchestrator.
    /// This is the target architecture where AgentLoop has no runtime logic.
    public func runAsScheduler(intake: any IntentSource) async {
        guard let orchestrator else { return }
        running = true
        while running {
            guard let intent = await intake.next() else {
                running = false
                break
            }
            _ = try? await orchestrator.submitIntent(intent)
        }
    }

    /// Stop the scheduler loop.
    public func stop() {
        running = false
    }
}
