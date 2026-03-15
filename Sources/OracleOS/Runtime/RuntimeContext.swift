import Foundation

@MainActor
public final class RuntimeContext {
    public let config: RuntimeConfig
    public let traceRecorder: TraceRecorder
    public let traceStore: TraceStore
    public let artifactWriter: FailureArtifactWriter
    public let verifiedExecutor: VerifiedActionExecutor
    public let policyEngine: PolicyEngine
    public let approvalStore: ApprovalStore
    public let graphStore: GraphStore
    public let memoryStore: UnifiedMemoryStore
    public let stateAbstraction: StateAbstraction
    public let recoveryEngine: RecoveryEngine
    public let workspaceRunner: WorkspaceRunner
    public let repositoryIndexer: RepositoryIndexer
    public let architectureEngine: ArchitectureEngine
    public let experimentManager: ExperimentManager
    public let automationHost: AutomationHost
    public let browserController: BrowserController
    public let browserPageStateBuilder: BrowserPageStateBuilder
    public let stateMemoryIndex: StateMemoryIndex
    public let planningGraphStore: PlanningGraphStore
    public let searchController: SearchController
    public let metricsRecorder: MetricsRecorder

    public init(
        config: RuntimeConfig = .live(),
        traceRecorder: TraceRecorder,
        traceStore: TraceStore,
        artifactWriter: FailureArtifactWriter,
        verifiedExecutor: VerifiedActionExecutor,
        policyEngine: PolicyEngine,
        approvalStore: ApprovalStore,
        graphStore: GraphStore = GraphStore(),
        memoryStore: UnifiedMemoryStore = UnifiedMemoryStore(),
        stateAbstraction: StateAbstraction = StateAbstraction(),
        recoveryEngine: RecoveryEngine = RecoveryEngine(),
        workspaceRunner: WorkspaceRunner = WorkspaceRunner(),
        repositoryIndexer: RepositoryIndexer = RepositoryIndexer(),
        architectureEngine: ArchitectureEngine = ArchitectureEngine(),
        experimentManager: ExperimentManager = ExperimentManager(),
        automationHost: AutomationHost = .live(),
        browserController: BrowserController = BrowserController(),
        browserPageStateBuilder: BrowserPageStateBuilder = BrowserPageStateBuilder(),
        stateMemoryIndex: StateMemoryIndex = StateMemoryIndex(),
        planningGraphStore: PlanningGraphStore = PlanningGraphStore(),
        searchController: SearchController? = nil,
        metricsRecorder: MetricsRecorder = MetricsRecorder()
    ) {
        self.config = config
        self.traceRecorder = traceRecorder
        self.traceStore = traceStore
        self.artifactWriter = artifactWriter
        self.verifiedExecutor = verifiedExecutor
        self.policyEngine = policyEngine
        self.approvalStore = approvalStore
        self.graphStore = graphStore
        self.memoryStore = memoryStore
        self.stateAbstraction = stateAbstraction
        self.recoveryEngine = recoveryEngine
        self.workspaceRunner = workspaceRunner
        self.repositoryIndexer = repositoryIndexer
        self.architectureEngine = architectureEngine
        self.experimentManager = experimentManager
        self.automationHost = automationHost
        self.browserController = browserController
        self.browserPageStateBuilder = browserPageStateBuilder
        self.stateMemoryIndex = stateMemoryIndex
        self.planningGraphStore = planningGraphStore
        self.searchController = searchController ?? SearchController(
            generator: CandidateGenerator(
                stateMemoryIndex: stateMemoryIndex,
                planningGraphStore: planningGraphStore
            )
        )
        self.metricsRecorder = metricsRecorder
    }

    public static func live(
        config: RuntimeConfig = .live(),
        traceRecorder: TraceRecorder,
        traceStore: TraceStore,
        artifactWriter: FailureArtifactWriter
    ) -> RuntimeContext {
        let policyEngine = PolicyEngine(mode: config.policyMode)
        let approvalStore = ApprovalStore(rootDirectory: config.approvalsDirectory)
        let graphStore = GraphStore()
        let stateMemoryIndex = StateMemoryIndex()
        let planningGraphStore = PlanningGraphStore()
        let verifiedExecutor = VerifiedActionExecutor(
            traceRecorder: traceRecorder,
            traceStore: traceStore,
            artifactWriter: artifactWriter,
            graphStore: graphStore,
            stateMemoryIndex: stateMemoryIndex,
            planningGraphStore: planningGraphStore
        )

        return RuntimeContext(
            config: config,
            traceRecorder: traceRecorder,
            traceStore: traceStore,
            artifactWriter: artifactWriter,
            verifiedExecutor: verifiedExecutor,
            policyEngine: policyEngine,
            approvalStore: approvalStore,
            graphStore: graphStore,
            recoveryEngine: RecoveryEngine(),
            workspaceRunner: WorkspaceRunner(),
            repositoryIndexer: RepositoryIndexer(),
            architectureEngine: ArchitectureEngine(),
            experimentManager: ExperimentManager(),
            automationHost: .live(),
            browserController: BrowserController(),
            browserPageStateBuilder: BrowserPageStateBuilder(),
            stateMemoryIndex: stateMemoryIndex,
            planningGraphStore: planningGraphStore,
            searchController: SearchController(
                generator: CandidateGenerator(
                    stateMemoryIndex: stateMemoryIndex,
                    planningGraphStore: planningGraphStore
                )
            ),
            metricsRecorder: MetricsRecorder()
        )
    }
}
