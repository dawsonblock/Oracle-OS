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
}
