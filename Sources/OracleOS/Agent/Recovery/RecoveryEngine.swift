public final class RecoveryEngine {

    private let registry: RecoveryRegistry

    public init(registry: RecoveryRegistry) {
        self.registry = registry
    }

    public func recover(
        failure: FailureClass,
        state: WorldState
    ) async -> ActionResult {

        guard let strategy = registry.strategy(for: failure) else {

            return ActionResult(
                success: false,
                message: "No recovery strategy"
            )
        }

        do {

            return try await strategy.attempt(
                failure: failure,
                state: state
            )

        } catch {

            return ActionResult(
                success: false,
                message: error.localizedDescription
            )
        }
    }
}
