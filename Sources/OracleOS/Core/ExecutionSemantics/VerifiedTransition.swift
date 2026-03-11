import Foundation

public struct VerifiedTransition: Codable, Sendable {
    public let fromPlanningStateID: PlanningStateID
    public let toPlanningStateID: PlanningStateID
    public let actionContractID: String
    public let postconditionClass: PostconditionClass
    public let verified: Bool
    public let failureClass: String?
    public let latencyMs: Int
    public let timestamp: TimeInterval

    public init(
        fromPlanningStateID: PlanningStateID,
        toPlanningStateID: PlanningStateID,
        actionContractID: String,
        postconditionClass: PostconditionClass,
        verified: Bool,
        failureClass: String?,
        latencyMs: Int,
        timestamp: TimeInterval = Date().timeIntervalSince1970
    ) {
        self.fromPlanningStateID = fromPlanningStateID
        self.toPlanningStateID = toPlanningStateID
        self.actionContractID = actionContractID
        self.postconditionClass = postconditionClass
        self.verified = verified
        self.failureClass = failureClass
        self.latencyMs = latencyMs
        self.timestamp = timestamp
    }

    public func toDict() -> [String: Any] {
        [
            "from_planning_state_id": fromPlanningStateID.rawValue,
            "to_planning_state_id": toPlanningStateID.rawValue,
            "action_contract_id": actionContractID,
            "postcondition_class": postconditionClass.rawValue,
            "verified": verified,
            "failure_class": failureClass as Any,
            "latency_ms": latencyMs,
            "timestamp": timestamp,
        ]
    }
}
