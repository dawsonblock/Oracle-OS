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
    public let memoryStore: AppMemoryStore
    public let stateAbstraction: StateAbstraction
    public let recoveryEngine: RecoveryEngine
    public let workspaceRunner: WorkspaceRunner
    public let repositoryIndexer: RepositoryIndexer
    public let architectureEngine: ArchitectureEngine
    public let experimentManager: ExperimentManager
    public let automationHost: AutomationHost
    public let browserController: BrowserController
    public let browserPageStateBuilder: BrowserPageStateBuilder

    public init(
        config: RuntimeConfig = .live(),
        traceRecorder: TraceRecorder,
        traceStore: TraceStore,
        artifactWriter: FailureArtifactWriter,
        verifiedExecutor: VerifiedActionExecutor,
        policyEngine: PolicyEngine,
        approvalStore: ApprovalStore,
        graphStore: GraphStore = GraphStore(),
        memoryStore: AppMemoryStore = AppMemoryStore(),
        stateAbstraction: StateAbstraction = StateAbstraction(),
        recoveryEngine: RecoveryEngine = RecoveryEngine(),
        workspaceRunner: WorkspaceRunner = WorkspaceRunner(),
        repositoryIndexer: RepositoryIndexer = RepositoryIndexer(),
        architectureEngine: ArchitectureEngine = ArchitectureEngine(),
        experimentManager: ExperimentManager = ExperimentManager(),
        automationHost: AutomationHost = .live(),
        browserController: BrowserController = BrowserController(),
        browserPageStateBuilder: BrowserPageStateBuilder = BrowserPageStateBuilder()
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
        let verifiedExecutor = VerifiedActionExecutor(
            traceRecorder: traceRecorder,
            traceStore: traceStore,
            artifactWriter: artifactWriter,
            graphStore: graphStore
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
            browserPageStateBuilder: BrowserPageStateBuilder()
        )
    }
}
