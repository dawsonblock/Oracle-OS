import Foundation

public struct SystemRouter: @unchecked Sendable {
    private let workspaceRunner: WorkspaceRunner?

    init(workspaceRunner: WorkspaceRunner?) {
        self.workspaceRunner = workspaceRunner
    }

    public func execute(
        _ command: Command,
        policyDecision: PolicyDecision
    ) async throws -> ExecutionOutcome {
        switch command.payload {
        case .shell(let spec):
            guard let workspaceRunner else {
                return CommandRouter.failureOutcome(
                    command: command,
                    reason: "Workspace runner unavailable",
                    policyDecision: policyDecision,
                    router: "system"
                )
            }

            let result = try workspaceRunner.execute(spec: spec)
            let observations = [
                ObservationPayload(
                    kind: "system.shell",
                    content: "\(result.summary)\nstdout:\n\(result.stdout)\nstderr:\n\(result.stderr)"
                ),
            ]
            if result.succeeded {
                return CommandRouter.successOutcome(
                    command: command,
                    observations: observations,
                    artifacts: [],
                    policyDecision: policyDecision,
                    router: "system"
                )
            }

            return CommandRouter.failureOutcome(
                command: command,
                reason: result.stderr.isEmpty ? result.stdout : result.stderr,
                policyDecision: policyDecision,
                router: "system"
            )

        case .ui:
            return CommandRouter.failureOutcome(
                command: command,
                reason: "Invalid system payload: received UI action for system command",
                policyDecision: policyDecision,
                router: "system"
            )

        case .code:
            return CommandRouter.failureOutcome(
                command: command,
                reason: "Invalid system payload",
                policyDecision: policyDecision,
                router: "system"
            )
        }
    }
}
