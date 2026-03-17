import Foundation

/// The single entry point for runtime cycle execution.
/// Coordinates: decide → execute → commit → evaluate
public actor RuntimeOrchestrator: IntentAPI {
    private let eventStore: EventStore
    private let commitCoordinator: CommitCoordinator
    private let preconditionsValidator: PreconditionsValidator
    private let safetyValidator: SafetyValidator
    private let toolDispatcher: ToolDispatcher
    private let postconditionsValidator: PostconditionsValidator
    private let capabilityBinder: CapabilityBinder

    public init(
        eventStore: EventStore,
        commitCoordinator: CommitCoordinator,
        preconditionsValidator: PreconditionsValidator = PreconditionsValidator(),
        safetyValidator: SafetyValidator = SafetyValidator(),
        toolDispatcher: ToolDispatcher = ToolDispatcher(),
        postconditionsValidator: PostconditionsValidator = PostconditionsValidator(),
        capabilityBinder: CapabilityBinder = CapabilityBinder()
    ) {
        self.eventStore = eventStore
        self.commitCoordinator = commitCoordinator
        self.preconditionsValidator = preconditionsValidator
        self.safetyValidator = safetyValidator
        self.toolDispatcher = toolDispatcher
        self.postconditionsValidator = postconditionsValidator
        self.capabilityBinder = capabilityBinder
    }

    /// PHASE 1: Decide — invoke planner to produce a Command
    public func decide(intent: Intent, planner: any Planner) async throws -> any Command {
        let context = PlannerContext(state: WorldStateModel())
        return try await planner.plan(intent: intent, context: context)
    }

    /// PHASE 2: Execute — VerifiedExecutor pipeline
    public func execute(_ command: any Command, state: WorldStateModel) async throws -> ExecutionOutcome {
        // Phase 1: Preconditions
        do {
            guard try preconditionsValidator.validate(command, state: state) else {
                return ExecutionOutcome(
                    commandID: command.id,
                    status: .preconditionFailed,
                    events: [],
                    verifierReport: VerifierReport(
                        commandID: command.id,
                        preconditionsPassed: false,
                        policyDecision: "blocked",
                        postconditionsPassed: false
                    )
                )
            }
        } catch {
            return ExecutionOutcome(
                commandID: command.id,
                status: .preconditionFailed,
                events: [],
                verifierReport: VerifierReport(
                    commandID: command.id,
                    preconditionsPassed: false,
                    policyDecision: error.localizedDescription,
                    postconditionsPassed: false,
                    notes: [error.localizedDescription]
                )
            )
        }
        
        // Phase 2: Safety check
        let safety = safetyValidator.isSafe(command, state: state)
        guard safety.safe else {
            return ExecutionOutcome(
                commandID: command.id,
                status: .policyBlocked,
                events: [],
                verifierReport: VerifierReport(
                    commandID: command.id,
                    preconditionsPassed: true,
                    policyDecision: safety.reason,
                    postconditionsPassed: false,
                    notes: [safety.reason]
                )
            )
        }
        
        // Phase 3: Bind capabilities and dispatch
        let capabilities = try capabilityBinder.bind(command)
        let (observations, artifacts) = try await toolDispatcher.dispatch(command, capabilities: capabilities)
        
        // Phase 4: Determine actual execution status based on results
        let executionStatus: ExecutionStatus
        let postconditionsPassed: Bool
        
        // Check if actual execution occurred
        if observations.isEmpty && artifacts.isEmpty {
            // No execution results - command was not actually run
            executionStatus = .failed
            postconditionsPassed = false
        } else {
            // Execution occurred - check postconditions
            let initialOutcome = ExecutionOutcome(
                commandID: command.id,
                status: .success,
                observations: observations,
                artifacts: artifacts,
                events: [],
                verifierReport: VerifierReport(
                    commandID: command.id,
                    preconditionsPassed: true,
                    policyDecision: "approved",
                    postconditionsPassed: true
                )
            )
            
            // Validate postconditions
            do {
                guard try postconditionsValidator.validate(command, outcome: initialOutcome) else {
                    executionStatus = .postconditionFailed
                    postconditionsPassed = false
                }
                executionStatus = .success
                postconditionsPassed = true
            } catch {
                executionStatus = .postconditionFailed
                postconditionsPassed = false
            }
        }
        
        // Build events from completed action
        let events: [EventEnvelope] = buildEvents(from: command, observations: observations, artifacts: artifacts, status: executionStatus)
        
        return ExecutionOutcome(
            commandID: command.id,
            status: executionStatus,
            observations: observations,
            artifacts: artifacts,
            events: events,
            verifierReport: VerifierReport(
                commandID: command.id,
                preconditionsPassed: true,
                policyDecision: "approved",
                postconditionsPassed: postconditionsPassed
            )
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
