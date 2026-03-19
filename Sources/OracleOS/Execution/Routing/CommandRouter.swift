import Foundation

public struct CommandRouter: @unchecked Sendable {
    private let systemRouter: SystemRouter
    private let uiRouter: UIRouter
    private let codeRouter: CodeRouter

    public init(
        automationHost: AutomationHost? = nil,
        workspaceRunner: WorkspaceRunner? = nil,
        context: RuntimeContext? = nil
    ) {
        let dispatcher = ToolDispatcher(
            automationHost: automationHost,
            workspaceRunner: workspaceRunner,
            context: context
        )
        self.systemRouter = SystemRouter(dispatcher: dispatcher)
        self.uiRouter = UIRouter(dispatcher: dispatcher)
        self.codeRouter = CodeRouter(dispatcher: dispatcher)
    }

    public func execute(
        _ command: Command,
        policyDecision: PolicyDecision
    ) async throws -> ExecutionOutcome {
        switch command.type {
        case .system:
            return try await systemRouter.execute(command, policyDecision: policyDecision)
        case .ui:
            return try await uiRouter.execute(command, policyDecision: policyDecision)
        case .code:
            return try await codeRouter.execute(command, policyDecision: policyDecision)
        }
    }

    static func successOutcome(
        command: Command,
        observations: [ObservationPayload],
        artifacts: [ArtifactPayload],
        policyDecision: PolicyDecision,
        router: String
    ) -> ExecutionOutcome {
        let events = [
            makeEvent(command: command, eventType: "CommandStarted", payload: ["router": router]),
            makeEvent(command: command, eventType: "CommandSucceeded", payload: ["router": router]),
        ]
        return ExecutionOutcome(
            commandID: command.id,
            status: .success,
            observations: observations,
            artifacts: artifacts,
            events: events,
            verifierReport: VerifierReport(
                commandID: command.id,
                preconditionsPassed: true,
                policyDecision: policyDecision.allowed ? "approved" : "blocked",
                postconditionsPassed: true
            )
        )
    }

    static func failureOutcome(
        command: Command,
        reason: String,
        policyDecision: PolicyDecision,
        router: String,
        status: ExecutionStatus = .failed
    ) -> ExecutionOutcome {
        let events = [
            makeEvent(command: command, eventType: "CommandStarted", payload: ["router": router]),
            makeEvent(command: command, eventType: "CommandFailed", payload: ["reason": reason, "router": router]),
        ]
        return ExecutionOutcome(
            commandID: command.id,
            status: status,
            observations: [],
            artifacts: [],
            events: events,
            verifierReport: VerifierReport(
                commandID: command.id,
                preconditionsPassed: true,
                policyDecision: policyDecision.allowed ? "approved" : "blocked",
                postconditionsPassed: false,
                notes: [reason]
            )
        )
    }

    static func makeEvent(
        command: Command,
        eventType: String,
        payload: [String: String]
    ) -> EventEnvelope {
        let encodedPayload = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
        return EventEnvelope(
            sequenceNumber: 0,
            commandID: command.id,
            intentID: command.metadata.intentID,
            timestamp: Date(),
            eventType: eventType,
            payload: encodedPayload
        )
    }
}
