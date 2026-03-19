import Foundation

/// The single entry point for runtime cycle execution.
/// Coordinates: decide → execute → commit → evaluate
public actor RuntimeOrchestrator: IntentAPI {
    private let eventStore: EventStore
    private let commitCoordinator: CommitCoordinator
    private let planner: any Planner
    private let verifiedExecutor: VerifiedExecutor

    public init(
        eventStore: EventStore,
        commitCoordinator: CommitCoordinator,
        planner: any Planner = MainPlanner(),
        policyEngine: PolicyEngine = .shared,
        automationHost: AutomationHost? = nil,
        workspaceRunner: WorkspaceRunner? = nil,
        repositoryIndexer: RepositoryIndexer = RepositoryIndexer(),
        postconditionsValidator: PostconditionsValidator = PostconditionsValidator(),
    ) {
        self.eventStore = eventStore
        self.commitCoordinator = commitCoordinator
        self.planner = planner
        self.verifiedExecutor = VerifiedExecutor(
            policyEngine: policyEngine,
            commandRouter: CommandRouter(
                automationHost: automationHost,
                workspaceRunner: workspaceRunner,
                repositoryIndexer: repositoryIndexer
            ),
            postconditionsValidator: postconditionsValidator
        )
    }

    public init(
        eventStore: EventStore,
        commitCoordinator: CommitCoordinator
    ) {
        self.init(
            eventStore: eventStore,
            commitCoordinator: commitCoordinator,
            planner: MainPlanner()
        )
    }

    public func decide(intent: Intent, planner: any Planner) async throws -> Command {
        let context = PlannerContext(
            state: WorldStateModel(snapshot: await commitCoordinator.snapshot())
        )
        return try await planner.plan(intent: intent, context: context)
    }

    public func execute(_ command: Command, state: WorldStateModel) async throws -> ExecutionOutcome {
        _ = state
        return try await verifiedExecutor.execute(command)
    }

    public func commit(_ outcome: ExecutionOutcome) async throws {
        try await commitCoordinator.commit(outcome.events)
    }

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

extension RuntimeOrchestrator {
    public func submitIntent(_ intent: Intent) async throws -> IntentResponse {
        let cycleID = UUID()

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

        let executionOutcome: ExecutionOutcome
        do {
            executionOutcome = try await verifiedExecutor.execute(command)
        } catch {
            executionOutcome = ExecutionOutcome.failure(from: error, command: command)
        }

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

        _ = await commitCoordinator.snapshot()
        let evaluation = await evaluate(executionOutcome)

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
            snapshotID: nil,
            timestamp: Date()
        )
    }

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
