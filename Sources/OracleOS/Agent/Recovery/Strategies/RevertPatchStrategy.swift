import Foundation

public struct RevertPatchStrategy: RecoveryStrategy {
    public let name = "revert_patch"

    public init() {}

    public func prepare(
        failure _: FailureClass,
        state: WorldState,
        memoryStore _: AppMemoryStore
    ) async throws -> RecoveryPreparation? {
        guard state.lastAction?.agentKind == .code else {
            return nil
        }

        return nil
    }
}
