import Foundation

public actor VerifiedExecutor {
    private let preconditionsValidator: PreconditionsValidator
    private let safetyValidator: SafetyValidator
    private let capabilityBinder: CapabilityBinder
    private let commandRouter: CommandRouter
    private let postconditionsValidator: PostconditionsValidator

    public init(
        preconditionsValidator: PreconditionsValidator = PreconditionsValidator(),
        safetyValidator: SafetyValidator = SafetyValidator(),
        capabilityBinder: CapabilityBinder = CapabilityBinder(),
        commandRouter: CommandRouter = CommandRouterImpl(),
        postconditionsValidator: PostconditionsValidator = PostconditionsValidator()
    ) {
        self.preconditionsValidator = preconditionsValidator
        self.safetyValidator = safetyValidator
        self.capabilityBinder = capabilityBinder
        self.commandRouter = commandRouter
        self.postconditionsValidator = postconditionsValidator
    }

    public func execute(_ command: any Command, state: WorldStateModel) async throws -> ExecutionOutcome {
        guard try preconditionsValidator.validate(command, state: state) else {
            return failOutcome(command: command, status: .preconditionFailed, reason: "Preconditions failed")
        }

        let safety = safetyValidator.isSafe(command, state: state)
        guard safety.safe else {
            return failOutcome(command: command, status: .policyBlocked, reason: safety.reason)
        }

        let capabilities = try capabilityBinder.bind(command)

        let outcome: ExecutionOutcome
        do {
            outcome = try await commandRouter.route(command, capabilities: capabilities)
        } catch {
            return failOutcome(command: command, status: .failed, reason: error.localizedDescription)
        }

        guard try postconditionsValidator.validate(command, outcome: outcome) else {
            return failOutcome(command: command, status: .postconditionFailed, reason: "Postconditions failed")
        }

        return outcome
    }

    private func failOutcome(command: any Command, status: ExecutionStatus, reason: String) -> ExecutionOutcome {
        let report = VerifierReport(
            commandID: command.id,
            preconditionsPassed: status != .preconditionFailed,
            policyDecision: status == .policyBlocked ? reason : "approved",
            postconditionsPassed: status != .postconditionFailed,
            notes: [reason]
        )
        
        let payload = try! JSONSerialization.data(withJSONObject: ["error": reason])
        
        let event = EventEnvelope(
            id: UUID(),
            sequenceNumber: 0,
            commandID: command.id,
            intentID: UUID(),
            timestamp: Date(),
            eventType: "commandFailed",
            payload: payload
        )
        
        return ExecutionOutcome(
            commandID: command.id,
            status: status,
            observations: [],
            artifacts: [],
            events: [event],
            verifierReport: report
        )
    }
}
