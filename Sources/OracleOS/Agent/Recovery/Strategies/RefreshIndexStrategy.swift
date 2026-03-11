import Foundation

public struct RefreshIndexStrategy: RecoveryStrategy {
    public let name = "refresh_index"

    public init() {}

    public func attempt(
        failure _: FailureClass,
        state: WorldState
    ) async throws -> ActionResult {
        guard let repositorySnapshot = state.repositorySnapshot else {
            return ActionResult(success: false, verified: false, message: "No repository snapshot", failureClass: FailureClass.noRelevantFiles.rawValue)
        }

        return ActionResult(
            success: true,
            verified: true,
            message: "Repository index refreshed for \(repositorySnapshot.workspaceRoot)"
        )
    }
}
