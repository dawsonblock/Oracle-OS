import Foundation

public struct MemoryQueryContext: Sendable {
    public let agentKind: AgentKind?
    public let goalDescription: String
    public let app: String?
    public let label: String?
    public let workspaceRoot: String?
    public let commandCategory: String?
    public let errorSignature: String?
    public let failureClass: FailureClass?
    public let repositorySnapshot: RepositorySnapshot?
    public let planningState: PlanningState?

    public init(
        agentKind: AgentKind? = nil,
        goalDescription: String = "",
        app: String? = nil,
        label: String? = nil,
        workspaceRoot: String? = nil,
        commandCategory: String? = nil,
        errorSignature: String? = nil,
        failureClass: FailureClass? = nil,
        repositorySnapshot: RepositorySnapshot? = nil,
        planningState: PlanningState? = nil
    ) {
        self.agentKind = agentKind
        self.goalDescription = goalDescription
        self.app = app
        self.label = label
        self.workspaceRoot = workspaceRoot
        self.commandCategory = commandCategory
        self.errorSignature = errorSignature
        self.failureClass = failureClass
        self.repositorySnapshot = repositorySnapshot
        self.planningState = planningState
    }

    public init(
        taskContext: TaskContext,
        worldState: WorldState,
        label: String? = nil,
        commandCategory: String? = nil,
        errorSignature: String? = nil,
        failureClass: FailureClass? = nil
    ) {
        self.init(
            agentKind: taskContext.agentKind,
            goalDescription: taskContext.goal.description,
            app: worldState.observation.app,
            label: label,
            workspaceRoot: taskContext.workspaceRoot,
            commandCategory: commandCategory,
            errorSignature: errorSignature,
            failureClass: failureClass,
            repositorySnapshot: worldState.repositorySnapshot,
            planningState: worldState.planningState
        )
    }
}
