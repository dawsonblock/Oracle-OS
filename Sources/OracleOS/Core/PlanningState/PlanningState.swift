import Foundation

public struct PlanningState: Hashable, Codable, Sendable {
    public let id: PlanningStateID
    public let clusterKey: StateClusterKey
    public let appID: String
    public let domain: String?
    public let windowClass: String?
    public let taskPhase: String?
    public let focusedRole: String?
    public let modalClass: String?
    public let navigationClass: String?
    public let controlContext: String?

    public init(
        id: PlanningStateID,
        clusterKey: StateClusterKey,
        appID: String,
        domain: String?,
        windowClass: String?,
        taskPhase: String?,
        focusedRole: String?,
        modalClass: String?,
        navigationClass: String?,
        controlContext: String?
    ) {
        self.id = id
        self.clusterKey = clusterKey
        self.appID = appID
        self.domain = domain
        self.windowClass = windowClass
        self.taskPhase = taskPhase
        self.focusedRole = focusedRole
        self.modalClass = modalClass
        self.navigationClass = navigationClass
        self.controlContext = controlContext
    }
}
