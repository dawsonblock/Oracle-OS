import Foundation

public enum ControllerHostCommand: String, Codable, Sendable {
    case bootstrap
    case refreshSnapshot
    case performAction
    case listApprovalRequests
    case approveApprovalRequest
    case rejectApprovalRequest
    case listRecipes
    case loadRecipe
    case saveRecipe
    case deleteRecipe
    case runRecipe
    case resumeRecipeRun
    case listTraceSessions
    case loadTraceSession
    case getHealth
    case setMonitoring
    case ping
}

public struct MonitoringConfiguration: Codable, Sendable, Equatable {
    public var enabled: Bool
    public var appName: String?
    public var intervalMs: Int

    public init(enabled: Bool, appName: String? = nil, intervalMs: Int = 1000) {
        self.enabled = enabled
        self.appName = appName
        self.intervalMs = intervalMs
    }
}

public struct ControllerHostRequest: Codable, Sendable, Identifiable {
    public let id: String
    public let command: ControllerHostCommand
    public let appName: String?
    public let action: ActionRequest?
    public let recipeName: String?
    public let recipe: RecipeDocument?
    public let recipeParams: [String: String]?
    public let traceSessionID: String?
    public let monitoring: MonitoringConfiguration?
    public let approvalRequestID: String?
    public let resumeToken: String?

    public init(
        id: String = UUID().uuidString,
        command: ControllerHostCommand,
        appName: String? = nil,
        action: ActionRequest? = nil,
        recipeName: String? = nil,
        recipe: RecipeDocument? = nil,
        recipeParams: [String: String]? = nil,
        traceSessionID: String? = nil,
        monitoring: MonitoringConfiguration? = nil,
        approvalRequestID: String? = nil,
        resumeToken: String? = nil
    ) {
        self.id = id
        self.command = command
        self.appName = appName
        self.action = action
        self.recipeName = recipeName
        self.recipe = recipe
        self.recipeParams = recipeParams
        self.traceSessionID = traceSessionID
        self.monitoring = monitoring
        self.approvalRequestID = approvalRequestID
        self.resumeToken = resumeToken
    }
}

public enum ControllerHostEnvelopeKind: String, Codable, Sendable {
    case response
    case event
}

public struct ControllerHostEnvelope: Codable, Sendable {
    public let kind: ControllerHostEnvelopeKind
    public let response: ControllerHostResponse?
    public let event: ControllerHostEvent?

    public init(response: ControllerHostResponse) {
        self.kind = .response
        self.response = response
        self.event = nil
    }

    public init(event: ControllerHostEvent) {
        self.kind = .event
        self.response = nil
        self.event = event
    }
}

public struct ControllerHostResponse: Codable, Sendable {
    public let requestID: String
    public let command: ControllerHostCommand
    public let acknowledged: Bool
    public let bootstrap: DashboardBootstrap?
    public let snapshot: ControlSnapshot?
    public let actionResult: ActionRunResult?
    public let recipes: [RecipeDocument]?
    public let recipe: RecipeDocument?
    public let recipeRun: RecipeRunResultDocument?
    public let approvals: [ApprovalRequestDocument]?
    public let traceSessions: [TraceSessionSummary]?
    public let traceDetail: TraceSessionDetail?
    public let health: HealthStatus?
    public let errorMessage: String?

    public init(
        requestID: String,
        command: ControllerHostCommand,
        acknowledged: Bool = true,
        bootstrap: DashboardBootstrap? = nil,
        snapshot: ControlSnapshot? = nil,
        actionResult: ActionRunResult? = nil,
        recipes: [RecipeDocument]? = nil,
        recipe: RecipeDocument? = nil,
        recipeRun: RecipeRunResultDocument? = nil,
        approvals: [ApprovalRequestDocument]? = nil,
        traceSessions: [TraceSessionSummary]? = nil,
        traceDetail: TraceSessionDetail? = nil,
        health: HealthStatus? = nil,
        errorMessage: String? = nil
    ) {
        self.requestID = requestID
        self.command = command
        self.acknowledged = acknowledged
        self.bootstrap = bootstrap
        self.snapshot = snapshot
        self.actionResult = actionResult
        self.recipes = recipes
        self.recipe = recipe
        self.recipeRun = recipeRun
        self.approvals = approvals
        self.traceSessions = traceSessions
        self.traceDetail = traceDetail
        self.health = health
        self.errorMessage = errorMessage
    }
}

public enum ControllerHostEventKind: String, Codable, Sendable {
    case actionStarted
    case actionCompleted
    case observationUpdated
    case traceStepAppended
    case healthChanged
    case recipesChanged
    case approvalsChanged
}

public struct ControllerHostEvent: Codable, Sendable {
    public let kind: ControllerHostEventKind
    public let session: ControllerSession?
    public let snapshot: ControlSnapshot?
    public let action: ActionRunResult?
    public let traceStep: TraceStepViewModel?
    public let health: HealthStatus?
    public let recipes: [RecipeDocument]?
    public let approvals: [ApprovalRequestDocument]?
    public let message: String?

    public init(
        kind: ControllerHostEventKind,
        session: ControllerSession? = nil,
        snapshot: ControlSnapshot? = nil,
        action: ActionRunResult? = nil,
        traceStep: TraceStepViewModel? = nil,
        health: HealthStatus? = nil,
        recipes: [RecipeDocument]? = nil,
        approvals: [ApprovalRequestDocument]? = nil,
        message: String? = nil
    ) {
        self.kind = kind
        self.session = session
        self.snapshot = snapshot
        self.action = action
        self.traceStep = traceStep
        self.health = health
        self.recipes = recipes
        self.approvals = approvals
        self.message = message
    }
}
