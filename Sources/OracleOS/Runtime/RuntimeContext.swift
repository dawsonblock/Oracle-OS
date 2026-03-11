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
        stateAbstraction: StateAbstraction = StateAbstraction()
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
    }

    public static func live(
        config: RuntimeConfig = .live(),
        traceRecorder: TraceRecorder,
        traceStore: TraceStore,
        artifactWriter: FailureArtifactWriter
    ) -> RuntimeContext {
        let policyEngine = PolicyEngine(mode: config.policyMode)
        let approvalStore = ApprovalStore(rootDirectory: config.approvalsDirectory)
        let verifiedExecutor = VerifiedActionExecutor(
            traceRecorder: traceRecorder,
            traceStore: traceStore,
            artifactWriter: artifactWriter
        )

        return RuntimeContext(
            config: config,
            traceRecorder: traceRecorder,
            traceStore: traceStore,
            artifactWriter: artifactWriter,
            verifiedExecutor: verifiedExecutor,
            policyEngine: policyEngine,
            approvalStore: approvalStore
        )
    }
}
