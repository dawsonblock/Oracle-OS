public protocol RecoveryStrategy {

    var name: String { get }

    func attempt(
        failure: FailureClass,
        state: WorldState
    ) async throws -> ActionResult
}
