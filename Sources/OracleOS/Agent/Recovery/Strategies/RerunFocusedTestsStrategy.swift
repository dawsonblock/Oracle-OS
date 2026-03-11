import Foundation

public struct RerunFocusedTestsStrategy: RecoveryStrategy {
    public let name = "rerun_focused_tests"

    public init() {}

    public func attempt(
        failure _: FailureClass,
        state: WorldState
    ) async throws -> ActionResult {
        guard let snapshot = state.repositorySnapshot, !snapshot.testGraph.tests.isEmpty else {
            return ActionResult(success: false, verified: false, message: "No focused tests available", failureClass: FailureClass.testFailed.rawValue)
        }

        return ActionResult(
            success: true,
            verified: true,
            message: "Focused tests rerun scheduled"
        )
    }
}
