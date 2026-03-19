import Foundation

/// The ONLY layer allowed to produce side effects in Oracle-OS.
///
/// INVARIANTS:
///   - Executor observes and acts, but does NOT commit state
///   - Executor returns ExecutionOutcome with events and artifacts only
///   - CommitCoordinator is the ONLY entity that writes committed state
public actor VerifiedExecutor {
    private let policyEngine: PolicyEngine
    private let commandRouter: CommandRouter
    private let postconditionsValidator: PostconditionsValidator

    public init(
        policyEngine: PolicyEngine = .shared,
        commandRouter: CommandRouter = CommandRouter(),
        postconditionsValidator: PostconditionsValidator = PostconditionsValidator()
    ) {
        self.policyEngine = policyEngine
        self.commandRouter = commandRouter
        self.postconditionsValidator = postconditionsValidator
    }

    /// Execute a validated command and return outcome with events.
    /// IMPORTANT: This does NOT commit state — only returns events for CommitCoordinator.
    public func execute(_ command: Command) async throws -> ExecutionOutcome {
        let started = makeEvent(command: command, eventType: "CommandStarted", payload: ["status": "started"])
        let policyDecision = try policyEngine.validate(command)
        guard policyDecision.allowed else {
            return failOutcome(
                command: command,
                status: .policyBlocked,
                reason: policyDecision.reason ?? "Policy rejected",
                extraEvents: [
                    started,
                    makeEvent(command: command, eventType: "PolicyRejected", payload: ["reason": policyDecision.reason ?? "blocked"]),
                ]
            )
        }

        do {
            var outcome = try await commandRouter.execute(command, policyDecision: policyDecision)

            guard try postconditionsValidator.validate(command, outcome: outcome) else {
                return failOutcome(
                    command: command,
                    status: .postconditionFailed,
                    reason: "Postconditions failed",
                    extraEvents: [started]
                )
            }

            if outcome.events.isEmpty {
                outcome = ExecutionOutcome(
                    commandID: outcome.commandID,
                    status: outcome.status,
                    observations: outcome.observations,
                    artifacts: outcome.artifacts,
                    events: [started, makeEvent(command: command, eventType: "CommandSucceeded", payload: ["status": "success"])],
                    verifierReport: outcome.verifierReport
                )
            }
            return outcome
        } catch {
            return failOutcome(
                command: command,
                status: .failed,
                reason: error.localizedDescription,
                extraEvents: [started]
            )
        }
    }

    private func failOutcome(
        command: Command,
        status: ExecutionStatus,
        reason: String,
        extraEvents: [EventEnvelope] = []
    ) -> ExecutionOutcome {
        let report = VerifierReport(
            commandID: command.id,
            preconditionsPassed: status != .preconditionFailed,
            policyDecision: status == .policyBlocked ? reason : "approved",
            postconditionsPassed: status != .postconditionFailed,
            notes: [reason]
        )
        var events = extraEvents
        events.append(makeEvent(command: command, eventType: "CommandFailed", payload: ["reason": reason]))
        return ExecutionOutcome(
            commandID: command.id,
            status: status,
            observations: [],
            artifacts: [],
            events: events,
            verifierReport: report
        )
    }

    private func makeEvent(
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
