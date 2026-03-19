import Foundation

public struct SystemRouter: @unchecked Sendable {
    private let dispatcher: ToolDispatcher

    init(dispatcher: ToolDispatcher) {
        self.dispatcher = dispatcher
    }

    public func execute(
        _ command: Command,
        policyDecision: PolicyDecision
    ) async throws -> ExecutionOutcome {
        do {
            let (observations, artifacts) = try await dispatcher.dispatch(command, capabilities: [command.kind])
            return CommandRouter.successOutcome(
                command: command,
                observations: observations,
                artifacts: artifacts,
                policyDecision: policyDecision,
                router: "system"
            )
        } catch {
            return CommandRouter.failureOutcome(
                command: command,
                reason: error.localizedDescription,
                policyDecision: policyDecision,
                router: "system"
            )
        }
    }
}
