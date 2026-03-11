public struct RetryStrategy: RecoveryStrategy {

    public let name = "retry"

    public func attempt(
        failure: FailureClass,
        state: WorldState
    ) async throws -> ActionResult {

        guard let last = state.lastAction else {

            return ActionResult(
                success: false,
                message: "No previous action"
            )
        }

        print("Retrying:", last.action)

        return ActionResult(
            success: true,
            message: "Retry attempted"
        )
    }
}
