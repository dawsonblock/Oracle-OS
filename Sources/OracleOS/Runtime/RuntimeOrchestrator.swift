import Foundation

/// The single entry point for runtime cycle execution.
/// Coordinates: decide → execute → commit → evaluate
public actor RuntimeOrchestrator: IntentAPI {
    private let eventStore: EventStore
    private let commitCoordinator: CommitCoordinator
    // LEGACY: remove when performAction is eliminated
    private let preconditionsValidator: PreconditionsValidator
    // LEGACY: remove when performAction is eliminated
    private let safetyValidator: SafetyValidator
    // LEGACY: remove when performAction is eliminated
    private let toolDispatcher: ToolDispatcher
    // LEGACY: remove when performAction is eliminated
    private let postconditionsValidator: PostconditionsValidator
    // LEGACY: remove when performAction is eliminated
    private let capabilityBinder: CapabilityBinder
    nonisolated(unsafe) public var _legacyContext: RuntimeContext?

    /// The authoritative execution delegate — only layer allowed to produce side effects.
    private let verifiedExecutor: VerifiedExecutor

    public init(
        eventStore: EventStore,
        commitCoordinator: CommitCoordinator,
        preconditionsValidator: PreconditionsValidator = PreconditionsValidator(),
        safetyValidator: SafetyValidator = SafetyValidator(),
        toolDispatcher: ToolDispatcher = ToolDispatcher(),
        postconditionsValidator: PostconditionsValidator = PostconditionsValidator(),
        capabilityBinder: CapabilityBinder = CapabilityBinder(),
        context: RuntimeContext? = nil
    ) {
        self.eventStore = eventStore
        self.commitCoordinator = commitCoordinator
        self.preconditionsValidator = preconditionsValidator
        self.safetyValidator = safetyValidator
        self.toolDispatcher = toolDispatcher
        self.postconditionsValidator = postconditionsValidator
        self.capabilityBinder = capabilityBinder
        self._legacyContext = context
        self.verifiedExecutor = VerifiedExecutor(
            preconditionsValidator: preconditionsValidator,
            safetyValidator: safetyValidator,
            capabilityBinder: capabilityBinder,
            toolDispatcher: toolDispatcher,
            postconditionsValidator: postconditionsValidator
        )
    }

    /// Backward-compatibility initializer for callers that only have a RuntimeContext.
    public init(context: RuntimeContext) {
        self.eventStore = EventStore()
        self.commitCoordinator = CommitCoordinator(eventStore: self.eventStore, reducers: [])
        self.preconditionsValidator = PreconditionsValidator()
        self.safetyValidator = SafetyValidator()
        self.toolDispatcher = ToolDispatcher()
        self.postconditionsValidator = PostconditionsValidator()
        self.capabilityBinder = CapabilityBinder()
        self._legacyContext = context
        self.verifiedExecutor = VerifiedExecutor()
    }

    /// PHASE 1: Decide — invoke planner to produce a Command
    public func decide(intent: Intent, planner: any Planner) async throws -> any Command {
        let context = PlannerContext(state: WorldStateModel())
        return try await planner.plan(intent: intent, context: context)
    }

    /// PHASE 2: Execute — delegates to VerifiedExecutor (the single side-effect layer)
    public func execute(_ command: any Command, state: WorldStateModel) async throws -> ExecutionOutcome {
        // Delegate the full validation + dispatch pipeline to VerifiedExecutor
        let rawOutcome = try await verifiedExecutor.execute(command, state: state)

        // Build event envelopes from the outcome
        let events = buildEvents(
            from: command,
            observations: rawOutcome.observations,
            artifacts: rawOutcome.artifacts,
            status: rawOutcome.status
        )

        // Return a new outcome with events attached
        return ExecutionOutcome(
            commandID: rawOutcome.commandID,
            status: rawOutcome.status,
            observations: rawOutcome.observations,
            artifacts: rawOutcome.artifacts,
            events: events,
            verifierReport: rawOutcome.verifierReport
        )
    }
    
    /// Build event envelopes from execution results
    private func buildEvents(from command: any Command, observations: [ObservationPayload], artifacts: [ArtifactPayload], status: ExecutionStatus) -> [EventEnvelope] {
        var events: [EventEnvelope] = []
        
        // Encode payload to Data
        func encodePayload(_ dict: [String: String]) -> Data {
            try! JSONSerialization.data(withJSONObject: dict)
        }
        
        // Action started event
        let startPayload = encodePayload([
            "commandKind": command.kind,
            "intentID": command.metadata.intentID.uuidString
        ])
        
        events.append(EventEnvelope(
            id: UUID(),
            sequenceNumber: 0, // Will be assigned by EventStore
            commandID: command.id,
            intentID: command.metadata.intentID,
            timestamp: Date(),
            eventType: "actionStarted",
            payload: startPayload
        ))
        
        // Action completed/failed event
        let eventType = status == .success ? "actionCompleted" : "actionFailed"
        var payloadDict: [String: String] = [
            "commandKind": command.kind,
            "status": status.rawValue
        ]
        
        if status == .success && !observations.isEmpty {
            payloadDict["observationCount"] = String(observations.count)
        }
        
        let endPayload = encodePayload(payloadDict)
        
        events.append(EventEnvelope(
            id: UUID(),
            sequenceNumber: 0, // Will be assigned by EventStore
            commandID: command.id,
            intentID: command.metadata.intentID,
            timestamp: Date(),
            eventType: eventType,
            payload: endPayload
        ))
        
        return events
    }

    /// PHASE 3: Commit — event-sourced state mutation
    public func commit(_ outcome: ExecutionOutcome) async throws {
        try await commitCoordinator.commit(outcome.events)
    }

    /// PHASE 4: Evaluate — critic review (stub)
    public func evaluate(_ outcome: ExecutionOutcome) async { /* critic loop stub */ }
}

// MARK: - IntentAPI Conformance

extension RuntimeOrchestrator {
    /// Submit a user or system intent for execution.
    public func submitIntent(_ intent: Intent) async throws -> IntentResponse {
        // Full implementation requires planner and executor integration
        return IntentResponse(
            intentID: intent.id,
            outcome: .skipped,
            summary: "Intent submitted: \(intent.objective)",
            cycleID: UUID()
        )
    }

    /// Read current committed world state as a snapshot (read-only).
    public func queryState() async throws -> RuntimeSnapshot {
        return RuntimeSnapshot(
            timestamp: Date(),
            status: .idle,
            summary: "Runtime ready"
        )
    }
}
