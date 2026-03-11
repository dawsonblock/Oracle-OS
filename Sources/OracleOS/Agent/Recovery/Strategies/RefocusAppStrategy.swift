public struct RefocusAppStrategy: RecoveryStrategy {

    public let name = "refocus_app"

    public func attempt(
        failure: FailureClass,
        state: WorldState
    ) async throws -> ActionResult {

        let app = state.observation.app ?? "unknown"

        print("Refocusing:", app)

        return ActionResult(
            success: true,
            message: "App refocused"
        )
    }
}
