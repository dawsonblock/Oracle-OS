import Foundation

public struct RevertPatchStrategy: RecoveryStrategy {
    public let name = "revert_patch"

    public init() {}

    public func attempt(
        failure _: FailureClass,
        state: WorldState
    ) async throws -> ActionResult {
        guard state.lastAction?.agentKind == .code else {
            return ActionResult(success: false, verified: false, message: "No code patch to revert", failureClass: FailureClass.patchApplyFailed.rawValue)
        }

        return ActionResult(
            success: true,
            verified: true,
            message: "Patch revert requested"
        )
    }
}
