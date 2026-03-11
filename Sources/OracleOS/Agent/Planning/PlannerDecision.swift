import Foundation

public enum PlannerSource: String, Codable, Sendable {
    case stableGraph = "stable_graph"
    case exploration
    case recovery
}

public enum PlannerExecutionMode: String, Codable, Sendable {
    case direct
    case experiment
}

public struct PlannerDecision: Sendable {
    public let agentKind: AgentKind
    public let skillName: String
    public let plannerFamily: PlannerFamily
    public let stepPhase: TaskStepPhase
    public let executionMode: PlannerExecutionMode
    public let actionContract: ActionContract
    public let source: PlannerSource
    public let pathEdgeIDs: [String]
    public let currentEdgeID: String?
    public let semanticQuery: ElementQuery?
    public let projectMemoryRefs: [ProjectMemoryRef]
    public let architectureFindings: [ArchitectureFinding]
    public let refactorProposalID: String?
    public let experimentSpec: ExperimentSpec?
    public let experimentCandidateID: String?
    public let experimentSandboxPath: String?
    public let selectedExperimentCandidate: Bool?
    public let experimentOutcome: String?
    public let knowledgeTier: KnowledgeTier
    public let notes: [String]
    public let recoveryTagged: Bool
    public let recoveryStrategy: String?
    public let recoverySource: String?

    public init(
        agentKind: AgentKind = .os,
        skillName: String? = nil,
        plannerFamily: PlannerFamily = .os,
        stepPhase: TaskStepPhase = .operatingSystem,
        executionMode: PlannerExecutionMode = .direct,
        actionContract: ActionContract,
        source: PlannerSource,
        pathEdgeIDs: [String] = [],
        currentEdgeID: String? = nil,
        semanticQuery: ElementQuery? = nil,
        projectMemoryRefs: [ProjectMemoryRef] = [],
        architectureFindings: [ArchitectureFinding] = [],
        refactorProposalID: String? = nil,
        experimentSpec: ExperimentSpec? = nil,
        experimentCandidateID: String? = nil,
        experimentSandboxPath: String? = nil,
        selectedExperimentCandidate: Bool? = nil,
        experimentOutcome: String? = nil,
        knowledgeTier: KnowledgeTier? = nil,
        notes: [String] = [],
        recoveryTagged: Bool = false,
        recoveryStrategy: String? = nil,
        recoverySource: String? = nil
    ) {
        self.agentKind = agentKind
        self.skillName = skillName ?? actionContract.skillName
        self.plannerFamily = plannerFamily
        self.stepPhase = stepPhase
        self.executionMode = executionMode
        self.actionContract = actionContract
        self.source = source
        self.pathEdgeIDs = pathEdgeIDs
        self.currentEdgeID = currentEdgeID
        self.semanticQuery = semanticQuery
        self.projectMemoryRefs = projectMemoryRefs
        self.architectureFindings = architectureFindings
        self.refactorProposalID = refactorProposalID
        self.experimentSpec = experimentSpec
        self.experimentCandidateID = experimentCandidateID
        self.experimentSandboxPath = experimentSandboxPath
        self.selectedExperimentCandidate = selectedExperimentCandidate
        self.experimentOutcome = experimentOutcome
        self.knowledgeTier = knowledgeTier ?? (recoveryTagged ? .recovery : (source == .exploration ? .exploration : .candidate))
        self.notes = notes
        self.recoveryTagged = recoveryTagged
        self.recoveryStrategy = recoveryStrategy
        self.recoverySource = recoverySource
    }
}
