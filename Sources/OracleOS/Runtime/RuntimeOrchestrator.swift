import Foundation

/// The single entry point for runtime cycle execution.
/// Coordinates: decide → execute → commit → evaluate
public actor RuntimeOrchestrator: IntentAPI {
    private let eventStore: EventStore
    private let commitCoordinator: CommitCoordinator
    // The planner used for intent processing in submitIntent
    private let planner: any Planner
    // Backing storage for legacy context access. Not deprecated so internal use doesn't trigger warnings.
    nonisolated(unsafe) private var _legacyContextStorage: RuntimeContext?
    /// **DEPRECATED** — Direct context access bypasses the Intent pipeline.
    @available(*, deprecated, message: "Use IntentAPI.submitIntent instead of accessing _legacyContext directly.")
    nonisolated(unsafe) public var _legacyContext: RuntimeContext? {
        get { _legacyContextStorage }
        set { _legacyContextStorage = newValue }
    }

    /// The authoritative execution delegate — only layer allowed to produce side effects.
    private let verifiedExecutor: VerifiedExecutor

    public init(
        eventStore: EventStore,
        commitCoordinator: CommitCoordinator,
        planner: any Planner,
        postconditionsValidator: PostconditionsValidator = PostconditionsValidator(),
        context: RuntimeContext? = nil
    ) {
        self.eventStore = eventStore
        self.commitCoordinator = commitCoordinator
        self.planner = planner
        self._legacyContextStorage = context
        self.verifiedExecutor = VerifiedExecutor(
            policyEngine: context?.policyEngine ?? .shared,
            commandRouter: CommandRouter(
                automationHost: context?.automationHost,
                workspaceRunner: context?.workspaceRunner,
                context: context
            ),
            postconditionsValidator: postconditionsValidator
        )
    }

    public init(
        eventStore: EventStore,
        commitCoordinator: CommitCoordinator,
        context: RuntimeContext? = nil
    ) {
        let postconditionsValidator = PostconditionsValidator()
        self.eventStore = eventStore
        self.commitCoordinator = commitCoordinator
        self.planner = MainPlanner()
        self._legacyContextStorage = context
        self.verifiedExecutor = VerifiedExecutor(
            policyEngine: context?.policyEngine ?? .shared,
            commandRouter: CommandRouter(
                automationHost: context?.automationHost,
                workspaceRunner: context?.workspaceRunner,
                context: context
            ),
            postconditionsValidator: postconditionsValidator
        )
    }

    /// **DEPRECATED** — Backward-compatibility initializer for callers that only have a RuntimeContext.
    /// Migrate to the primary init(eventStore:commitCoordinator:planner:) and use IntentAPI.
    @available(*, deprecated, message: "Use init(eventStore:commitCoordinator:planner:) — RuntimeContext path bypasses typed execution.")
    public init(context: RuntimeContext, planner: any Planner) {
        let postconditionsValidator = PostconditionsValidator()
        self.eventStore = EventStore()
        self.commitCoordinator = CommitCoordinator(eventStore: self.eventStore, reducers: [])
        self.planner = planner
        self._legacyContext = context
        self.verifiedExecutor = VerifiedExecutor(
            policyEngine: context.policyEngine,
            commandRouter: CommandRouter(
                automationHost: context.automationHost,
                workspaceRunner: context.workspaceRunner,
                context: context
            ),
            postconditionsValidator: postconditionsValidator
        )
    }

    /// **DEPRECATED** — Legacy initializer - creates default MainPlanner internally for backward compatibility.
    /// Migrate to the primary init(eventStore:commitCoordinator:planner:) and use IntentAPI.
    @available(*, deprecated, message: "Use init(eventStore:commitCoordinator:planner:) — RuntimeContext path bypasses typed execution.")
    public init(context: RuntimeContext) {
        let postconditionsValidator = PostconditionsValidator()
        self.eventStore = EventStore()
        self.commitCoordinator = CommitCoordinator(eventStore: self.eventStore, reducers: [])
        self.planner = MainPlanner()
        self._legacyContext = context
        self.verifiedExecutor = VerifiedExecutor(
            policyEngine: context.policyEngine,
            commandRouter: CommandRouter(
                automationHost: context.automationHost,
                workspaceRunner: context.workspaceRunner,
                context: context
            ),
            postconditionsValidator: postconditionsValidator
        )
    }

    /// PHASE 1: Decide — invoke planner to produce a Command
    public func decide(intent: Intent, planner: any Planner) async throws -> Command {
        let context = PlannerContext(state: WorldStateModel())
        return try await planner.plan(intent: intent, context: context)
    }

    /// PHASE 2: Execute — delegates to VerifiedExecutor (the single side-effect layer)
    public func execute(_ command: Command, state: WorldStateModel) async throws -> ExecutionOutcome {
        _ = state
        // VerifiedExecutor is the only side-effect boundary and returns canonical events.
        return try await verifiedExecutor.execute(command)
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
        
        // 1. Plan - invoke planner to produce a Command
        let command: Command
        do {
            command = try await decide(intent: intent, planner: planner)
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
        
        // 2. Execute - delegate to VerifiedExecutor
        let executionOutcome: ExecutionOutcome
        do {
            executionOutcome = try await verifiedExecutor.execute(command)
        } catch {
            executionOutcome = ExecutionOutcome.failure(from: error, command: command)
        }

        // 3. Commit - event-sourced state mutation
        do {
            try await commitCoordinator.commit(executionOutcome.events)
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
        
        // 4. Snapshot - get current state snapshot
        let snapshotID = UUID()
        _ = await commitCoordinator.snapshot()
        let evaluation = await evaluate(executionOutcome)
        
        // Determine outcome based on execution status
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
            summary: "Intent completed: \(intent.objective) - \(executionOutcome.status.rawValue), critic=\(evaluation.criticOutcome.rawValue)",
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
