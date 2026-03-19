import Foundation

/// The single entry point for runtime cycle execution.
/// Coordinates: decide → execute → commit → evaluate
public actor RuntimeOrchestrator: IntentAPI {
    private let eventStore: EventStore
    private let commitCoordinator: CommitCoordinator
    // The planner used for intent processing in submitIntent
    private let planner: any Planner
    private let preconditionsValidator: PreconditionsValidator
    private let safetyValidator: SafetyValidator
    private let toolDispatcher: ToolDispatcher
    private let postconditionsValidator: PostconditionsValidator
    private let capabilityBinder: CapabilityBinder

    /// The authoritative execution delegate — only layer allowed to produce side effects.
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
    private func buildEvents(from command: any Command, observations: [ObservationPayload], artifacts: [ArtifactPayload], status: ExecutionStatus, reason: String? = nil) -> [EventEnvelope] {
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
        
        if !observations.isEmpty {
            payloadDict["observationCount"] = String(observations.count)
        }
        if !artifacts.isEmpty {
            payloadDict["artifactCount"] = String(artifacts.count)
        }
        if let reason, !reason.isEmpty {
            payloadDict["reason"] = reason
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

    /// PHASE 4: Evaluate — critic review of execution outcome.
    /// Classifies outcome status and returns an evaluation summary.
    /// Used to drive learning, recovery, and metrics recording.
    public func evaluate(_ outcome: ExecutionOutcome) async -> EvaluationResult {
        let criticOutcome: CriticOutcome
        switch outcome.status {
        case .success:
            criticOutcome = .success
        case .partialSuccess:
            criticOutcome = .partialSuccess
        case .failed, .preconditionFailed, .postconditionFailed, .policyBlocked:
            criticOutcome = .failure
        }

        let needsRecovery = criticOutcome == .failure

        return EvaluationResult(
            commandID: outcome.commandID,
            criticOutcome: criticOutcome,
            needsRecovery: needsRecovery,
            notes: outcome.verifierReport.notes
        )
    }
}

// MARK: - IntentAPI Conformance

extension RuntimeOrchestrator {
    /// Submit a user or system intent for execution.
    /// Full pipeline: Plan → Validate → Execute → Emit Events → Commit → Snapshot
    public func submitIntent(_ intent: Intent) async throws -> IntentResponse {
        let cycleID = UUID()
        let context = PlannerContext(state: WorldStateModel())
        let command: any Command
        do {
            command = try await planner.plan(intent: intent, context: context)
        } catch {
            return IntentResponse(
                intentID: intent.id,
                outcome: .failed,
                summary: "Planning failed: \(error.localizedDescription)",
                cycleID: cycleID,
                snapshotID: nil,
                timestamp: Date()
            )
        }

        let actionIntent = ActionIntent(
            agentKind: .os,
            app: "unknown",
            name: command.kind,
            action: command.kind,
            query: nil,
            text: nil,
            role: nil,
            domID: nil,
            x: nil,
            y: nil,
            button: nil,
            count: nil,
            workspaceRoot: ".",
            workspaceRelativePath: nil,
            codeCommand: nil,
            postconditions: []
        )
        let policyDecision = PolicyEngine.shared.evaluate(intent: actionIntent)

        guard policyDecision.allowed else {
            let outcome = failureOutcome(
                for: command,
                status: .policyBlocked,
                reason: policyDecision.reason ?? "Action not allowed"
            )
            try await commitCoordinator.commit(outcome.events)
            return IntentResponse(
                intentID: intent.id,
                outcome: .failed,
                summary: "Policy blocked: \(policyDecision.reason ?? "Action not allowed")",
                cycleID: cycleID,
                snapshotID: nil,
                timestamp: Date()
            )
        }

        let executionOutcome: ExecutionOutcome
        do {
            executionOutcome = try await verifiedExecutor.execute(command, state: context.state)
        } catch {
            let failedOutcome = failureOutcome(for: command, status: .failed, reason: error.localizedDescription)
            try await commitCoordinator.commit(failedOutcome.events)
            return response(for: intent, cycleID: cycleID, executionOutcome: failedOutcome, snapshotID: nil)
        }

        let events = buildEvents(
            from: command,
            observations: executionOutcome.observations,
            artifacts: executionOutcome.artifacts,
            status: executionOutcome.status
        )

        do {
            try await commitCoordinator.commit(events)
        } catch {
            return IntentResponse(
                intentID: intent.id,
                outcome: .partialSuccess,
                summary: "Execution succeeded but commit failed: \(error.localizedDescription)",
                cycleID: cycleID,
                snapshotID: nil,
                timestamp: Date()
            )
        }

        let snapshotID = UUID()
        _ = await commitCoordinator.snapshot()

        let committedOutcome = ExecutionOutcome(
            commandID: executionOutcome.commandID,
            status: executionOutcome.status,
            observations: executionOutcome.observations,
            artifacts: executionOutcome.artifacts,
            events: events,
            verifierReport: executionOutcome.verifierReport
        )
        return response(for: intent, cycleID: cycleID, executionOutcome: committedOutcome, snapshotID: snapshotID)
    }

    private func failureOutcome(
        for command: any Command,
        status: ExecutionStatus,
        reason: String
    ) -> ExecutionOutcome {
        let report = VerifierReport(
            commandID: command.id,
            preconditionsPassed: status != .preconditionFailed,
            policyDecision: status == .policyBlocked ? reason : "approved",
            postconditionsPassed: status != .postconditionFailed,
            notes: [reason]
        )
        return ExecutionOutcome(
            commandID: command.id,
            status: status,
            events: buildEvents(
                from: command,
                observations: [],
                artifacts: [],
                status: status,
                reason: reason
            ),
            verifierReport: report
        )
    }

    private func response(
        for intent: Intent,
        cycleID: UUID,
        executionOutcome: ExecutionOutcome,
        snapshotID: UUID?
    ) -> IntentResponse {
        let outcome: IntentResponse.Outcome
        switch executionOutcome.status {
        case .success:
            outcome = .success
        case .failed, .preconditionFailed, .postconditionFailed:
            outcome = .failed
        case .policyBlocked:
            outcome = .failed
        case .partialSuccess:
            outcome = .partialSuccess
        }

        return IntentResponse(
            intentID: intent.id,
            outcome: outcome,
            summary: "Intent completed: \(intent.objective) - \(executionOutcome.status.rawValue)",
            cycleID: cycleID,
            snapshotID: snapshotID,
            timestamp: Date()
        )
    }

    /// Read current committed world state as a snapshot (read-only).
    public func queryState() async throws -> RuntimeSnapshot {
        let snapshot = await commitCoordinator.snapshot()
        return RuntimeSnapshot(
            id: UUID(),
            timestamp: Date(),
            cycleCount: 0,
            lastIntentID: nil,
            lastCommandKind: nil,
            status: .idle,
            summary: "Runtime state: \(snapshot.visibleElementCount) visible elements, app: \(snapshot.activeApplication ?? "none")"
        )
    }
}
