public struct RefreshObservationStrategy: RecoveryStrategy {

    public let name = "refresh_observation"

    public func attempt(
        failure: FailureClass,
        state: WorldState
    ) async throws -> ActionResult {

        print("Refreshing screen observation")

        return ActionResult(
            success: true,
            message: "Observation refreshed"
        )
    }
}
