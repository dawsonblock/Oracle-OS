import Foundation

/// The single entry point for runtime cycle execution.
/// Linear pipeline: Intent → Plan → Validate → Execute → Commit → Evaluate
///
/// INVARIANTS:
///   - Only VerifiedExecutor.execute may produce side effects
///   - Only CommitCoordinator.commit may write state
///   - Every success and failure emits domain events
public actor RuntimeOrchestrator: IntentAPI {
    private let eventStore: EventStore
    private let commitCoordinator: CommitCoordinator
    private let planner: any Planner
    private let preconditionsValidator: PreconditionsValidator
    private let safetyValidator: SafetyValidator
    private let toolDispatcher: ToolDispatcher
    private let postconditionsValidator: PostconditionsValidator
    private let capabilityBinder: CapabilityBinder
    private let verifiedExecutor: VerifiedExecutor

    public init(
        eventStore: EventStore,
        commitCoordinator: CommitCoordinator,
        planner: any Planner,
        preconditionsValidator: PreconditionsValidator = PreconditionsValidator(),
        safetyValidator: SafetyValidator = SafetyValidator(),
        toolDispatcher: ToolDispatcher = ToolDispatcher(),
        postconditionsValidator: PostconditionsValidator = PostconditionsValidator(),
        capabilityBinder: CapabilityBinder = CapabilityBinder()
    ) {
        self.eventStore = eventStore
        self.commitCoordinator = commitCoordinator
        self.planner = planner
        self.preconditionsValidator = preconditionsValidator
        self.safetyValidator = safetyValidator
        self.toolDispatcher = toolDispatcher
        self.postconditionsValidator = postconditionsValidator
        self.capabilityBinder = capabilityBinder
        self.verifiedExecutor = VerifiedExecutor(
            preconditionsValidator: preconditionsValidator,
            safetyValidator: safetyValidator,
            capabilityBinder: capabilityBinder,
            toolDispatcher: toolDispatcher,
            postconditionsValidator: postconditionsValidator
        )
    }

    public init(
        eventStore: EventStore,
        commitCoordinator: CommitCoordinator
    ) {
        self.eventStore = eventStore
        self.commitCoordinator = commitCoordinator
        self.planner = MainPlanner()
        self.preconditionsValidator = PreconditionsValidator()
        self.safetyValidator = SafetyValidator()
        self.toolDispatcher = ToolDispatcher()
        self.postconditionsValidator = PostconditionsValidator()
        self.capabilityBinder = CapabilityBinder()
        self.verifiedExecutor = VerifiedExecutor(
            preconditionsValidator: self.preconditionsValidator,
            safetyValidator: self.safetyValidator,
            capabilityBinder: self.capabilityBinder,
            toolDispatcher: self.toolDispatcher,
            postconditionsValidator: self.postconditionsValidator
        )
    }

    // MARK: - IntentAPI

    /// Submit a user or system intent for execution.
    /// Full linear pipeline: Plan → Validate → Execute → Events → Commit → Evaluate
    public func submitIntent(_ intent: Intent) async throws -> IntentResponse {
        let cycleID = UUID()

        // 1. Plan
        let command = await plan(intent: intent, cycleID: cycleID)
        guard let command else {
            let events = buildEventEnvelopes(
                intentID: intent.id, commandID: nil,
                eventType: "CommandFailed",
                status: "planningFailed",
                detail: "Planner could not produce a command"
            )
            try? await commitCoordinator.commit(events)
            return IntentResponse(
                intentID: intent.id, outcome: .failed,
                summary: "Planning failed",
                cycleID: cycleID, snapshotID: nil, timestamp: Date()
            )
        }

        // 2. Policy validation
        let actionIntent = ActionIntent(
            agentKind: .os, app: "unknown", name: command.kind, action: command.kind,
            query: nil, text: nil, role: nil, domID: nil, x: nil, y: nil,
            button: nil, count: nil, workspaceRoot: ".", workspaceRelativePath: nil,
            codeCommand: nil, postconditions: []
        )
        let policyDecision = PolicyEngine.shared.evaluate(intent: actionIntent)

        guard policyDecision.allowed else {
            let events = buildEventEnvelopes(
                intentID: intent.id, commandID: command.id,
                eventType: "PolicyRejected",
                status: "policyBlocked",
                detail: policyDecision.reason ?? "Action not allowed"
            )
            try? await commitCoordinator.commit(events)
            return IntentResponse(
                intentID: intent.id, outcome: .failed,
                summary: "Policy blocked: \(policyDecision.reason ?? "Action not allowed")",
                cycleID: cycleID, snapshotID: nil, timestamp: Date()
            )
        }

        // 3. Execute via VerifiedExecutor
        let outcome: ExecutionOutcome
        do {
            outcome = try await execute(command, state: WorldStateModel())
        } catch {
            let failureOutcome = ExecutionOutcome.failure(from: error, command: command)
            let events = buildEvents(
                from: command,
                observations: [], artifacts: [],
                status: .failed
            )
            try? await commitCoordinator.commit(events)
            return IntentResponse(
                intentID: intent.id, outcome: .failed,
                summary: "Execution failed: \(error.localizedDescription)",
                cycleID: cycleID, snapshotID: nil, timestamp: Date()
            )
        }

        // 4. Commit events
        let events = buildEvents(
            from: command,
            observations: outcome.observations,
            artifacts: outcome.artifacts,
            status: outcome.status
        )
        do {
            try await commitCoordinator.commit(events)
        } catch {
            return IntentResponse(
                intentID: intent.id, outcome: .partialSuccess,
                summary: "Execution succeeded but commit failed: \(error.localizedDescription)",
                cycleID: cycleID, snapshotID: nil, timestamp: Date()
            )
        }

        // 5. Evaluate
        let evaluation = await evaluate(outcome)

        // 6. Snapshot
        let snapshotID = UUID()
        _ = await commitCoordinator.snapshot()

        let responseOutcome: IntentResponse.Outcome
        switch outcome.status {
        case .success: responseOutcome = .success
        case .partialSuccess: responseOutcome = .partialSuccess
        case .failed, .preconditionFailed, .postconditionFailed, .policyBlocked: responseOutcome = .failed
        }

        return IntentResponse(
            intentID: intent.id,
            outcome: responseOutcome,
            summary: "Intent completed: \(intent.objective) - \(outcome.status.rawValue)",
            cycleID: cycleID, snapshotID: snapshotID, timestamp: Date()
        )
    }

    public func queryState() async throws -> RuntimeSnapshot {
        let snapshot = await commitCoordinator.snapshot()
        return RuntimeSnapshot(
            id: UUID(), timestamp: Date(), cycleCount: 0,
            lastIntentID: nil, lastCommandKind: nil, status: .idle,
            summary: "Runtime state: \(snapshot.visibleElementCount) visible elements, app: \(snapshot.activeApplication ?? "none")"
        )
    }

    // MARK: - Pipeline Stages

    private func plan(intent: Intent, cycleID: UUID) async -> (any Command)? {
        let context = PlannerContext(state: WorldStateModel())
        do {
            return try await planner.plan(intent: intent, context: context)
        } catch {
            return nil
        }
    }

    /// Execute a command through VerifiedExecutor and attach events.
    public func execute(_ command: any Command, state: WorldStateModel) async throws -> ExecutionOutcome {
        let rawOutcome = try await verifiedExecutor.execute(command, state: state)
        let events = buildEvents(
            from: command,
            observations: rawOutcome.observations,
            artifacts: rawOutcome.artifacts,
            status: rawOutcome.status
        )
        return ExecutionOutcome(
            commandID: rawOutcome.commandID,
            status: rawOutcome.status,
            observations: rawOutcome.observations,
            artifacts: rawOutcome.artifacts,
            events: events,
            verifierReport: rawOutcome.verifierReport
        )
    }

    /// Commit execution outcome events to state.
    public func commit(_ outcome: ExecutionOutcome) async throws {
        try await commitCoordinator.commit(outcome.events)
    }

    /// Evaluate the execution outcome for recovery signals.
    public func evaluate(_ outcome: ExecutionOutcome) async -> EvaluationResult {
        let criticOutcome: CriticOutcome
        switch outcome.status {
        case .success: criticOutcome = .success
        case .partialSuccess: criticOutcome = .partialSuccess
        case .failed, .preconditionFailed, .postconditionFailed, .policyBlocked: criticOutcome = .failure
        }
        return EvaluationResult(
            commandID: outcome.commandID,
            criticOutcome: criticOutcome,
            needsRecovery: criticOutcome == .failure,
            notes: outcome.verifierReport.notes
        )
    }

    // MARK: - Event Building

    private func buildEvents(from command: any Command, observations: [ObservationPayload], artifacts: [ArtifactPayload], status: ExecutionStatus) -> [EventEnvelope] {
        var events: [EventEnvelope] = []

        func encodePayload(_ dict: [String: String]) -> Data {
            (try? JSONSerialization.data(withJSONObject: dict)) ?? Data()
        }

        events.append(EventEnvelope(
            id: UUID(), sequenceNumber: 0,
            commandID: command.id, intentID: command.metadata.intentID,
            timestamp: Date(), eventType: "CommandStarted",
            payload: encodePayload([
                "commandKind": command.kind,
                "commandType": command.commandType.rawValue,
                "intentID": command.metadata.intentID.uuidString
            ])
        ))

        let endType = status == .success ? "CommandSucceeded" : "CommandFailed"
        var payloadDict: [String: String] = [
            "commandKind": command.kind,
            "status": status.rawValue
        ]
        if !observations.isEmpty {
            payloadDict["observationCount"] = String(observations.count)
        }

        events.append(EventEnvelope(
            id: UUID(), sequenceNumber: 0,
            commandID: command.id, intentID: command.metadata.intentID,
            timestamp: Date(), eventType: endType,
            payload: encodePayload(payloadDict)
        ))

        return events
    }

    private func buildEventEnvelopes(intentID: UUID, commandID: CommandID?, eventType: String, status: String, detail: String) -> [EventEnvelope] {
        func encodePayload(_ dict: [String: String]) -> Data {
            (try? JSONSerialization.data(withJSONObject: dict)) ?? Data()
        }
        return [EventEnvelope(
            id: UUID(), sequenceNumber: 0,
            commandID: commandID, intentID: intentID,
            timestamp: Date(), eventType: eventType,
            payload: encodePayload(["status": status, "detail": detail])
        )]
    }
}
