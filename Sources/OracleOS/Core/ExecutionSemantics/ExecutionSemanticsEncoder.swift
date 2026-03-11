import Foundation

public enum ExecutionSemanticsEncoder {
    public static func encode(
        actionContract: ActionContract,
        transition: VerifiedTransition
    ) -> [String: Any] {
        [
            "action_contract": actionContract.toDict(),
            "verified_transition": transition.toDict(),
        ]
    }

    public static func decodeActionContract(from dictionary: [String: Any]) -> ActionContract? {
        guard let id = dictionary["id"] as? String,
              let skillName = dictionary["skill_name"] as? String,
              let locatorStrategy = dictionary["locator_strategy"] as? String
        else {
            return nil
        }

        return ActionContract(
            id: id,
            skillName: skillName,
            targetRole: dictionary["target_role"] as? String,
            targetLabel: dictionary["target_label"] as? String,
            locatorStrategy: locatorStrategy
        )
    }

    public static func decodeTransition(from dictionary: [String: Any]) -> VerifiedTransition? {
        guard let from = dictionary["from_planning_state_id"] as? String,
              let to = dictionary["to_planning_state_id"] as? String,
              let actionContractID = dictionary["action_contract_id"] as? String,
              let postconditionRaw = dictionary["postcondition_class"] as? String,
              let postconditionClass = PostconditionClass(rawValue: postconditionRaw),
              let verified = dictionary["verified"] as? Bool
        else {
            return nil
        }

        let latencyMs = (dictionary["latency_ms"] as? Int) ?? Int(dictionary["latency_ms"] as? Double ?? 0)
        let timestamp = dictionary["timestamp"] as? TimeInterval ?? Date().timeIntervalSince1970

        return VerifiedTransition(
            fromPlanningStateID: PlanningStateID(rawValue: from),
            toPlanningStateID: PlanningStateID(rawValue: to),
            actionContractID: actionContractID,
            postconditionClass: postconditionClass,
            verified: verified,
            failureClass: dictionary["failure_class"] as? String,
            latencyMs: latencyMs,
            timestamp: timestamp
        )
    }
}
