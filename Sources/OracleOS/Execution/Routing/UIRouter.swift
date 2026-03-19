import Foundation

public struct UIRouter: @unchecked Sendable {
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
                router: "ui"
            )
        } catch {
            return CommandRouter.failureOutcome(
                command: command,
                reason: error.localizedDescription,
                policyDecision: policyDecision,
                router: "ui"
            )
        }
    }
}
