import Foundation

/// The single entry point for runtime cycle execution.
/// Coordinates: Intent → Decide → Execute → Commit → Evaluate → Learn
public actor RuntimeOrchestrator: IntentAPI {
    private let eventStore: EventStore
    private let commitCoordinator: CommitCoordinator
    private let decisionCoordinator: DecisionCoordinator
    private let verifiedExecutor: VerifiedExecutor
    private let critic: Critic
    private let learningCoordinator: LearningCoordinator

    /// The canonical initializer - all dependencies injected explicitly
    public init(
        eventStore: EventStore,
        commitCoordinator: CommitCoordinator,
        decisionCoordinator: DecisionCoordinator,
        verifiedExecutor: VerifiedExecutor,
        critic: Critic,
        learningCoordinator: LearningCoordinator
    ) {
        self.eventStore = eventStore
        self.commitCoordinator = commitCoordinator
        self.decisionCoordinator = decisionCoordinator
        self.verifiedExecutor = verifiedExecutor
        self.critic = critic
        self.learningCoordinator = learningCoordinator
    }

    /// Convenience initializer with default implementations
    public init(
        eventStore: EventStore = EventStore(),
        commitCoordinator: CommitCoordinator? = nil,
        stateAbstraction: StateAbstraction = StateAbstraction()
    ) {
        self.eventStore = eventStore
        
        // Create default coordinators
        let memoryStore = UnifiedMemoryStore()
        let projectMemoryCoordinator = LoopProjectMemoryCoordinator(memoryStore: memoryStore)
        let learningCoordinator = LearningCoordinator(
            memoryStore: memoryStore,
            projectMemoryCoordinator: projectMemoryCoordinator
        )
        self.learningCoordinator = learningCoordinator
        
        let planner = MainPlanner()
        let graphStore = GraphStore()
        self.decisionCoordinator = DecisionCoordinator(
            planner: planner,
            graphStore: graphStore,
            memoryStore: memoryStore
        )
        
        let commit = commitCoordinator ?? CommitCoordinator(
            eventStore: eventStore,
            reducers: [],
            initialState: WorldStateModel()
        )
        self.commitCoordinator = commit
        
        let executor = VerifiedExecutor()
        self.verifiedExecutor = executor
        
        let critic = CriticLoop(
            observationProvider: stateAbstraction,
            learningCoordinator: learningCoordinator
        )
        self.critic = critic
    }

    // MARK: - Unified Pipeline: submitIntent

    /// Submit a user or system intent for execution.
    /// Full pipeline: Intent → Decide → Execute → Commit → Evaluate → Learn
    public func submitIntent(_ intent: Intent) async throws -> IntentResponse {
        let cycleID = UUID()
        
        do {
            // ---- PLAN ----
            let command = await decisionCoordinator.decide(intent: intent)

            // ---- EXECUTE ----
            let outcome: ExecutionOutcome
            do {
                outcome = try await verifiedExecutor.execute(command, state: WorldStateModel())
            } catch {
                outcome = ExecutionOutcome.failure(error, commandID: command.id)
            }

            // ---- COMMIT ----
            await commitCoordinator.commit(outcome.events)

            // ---- EVALUATE ----
            let evaluation = critic.evaluate(outcome)

            // ---- LEARN ----
            learningCoordinator.update(evaluation)

            // Determine outcome based on execution status
            let outcomeStatus: IntentResponse.Outcome
            switch outcome.status {
            case .success:
                outcomeStatus = .success
            case .failed, .preconditionFailed, .postconditionFailed:
                outcomeStatus = .failed
            case .policyBlocked:
                outcomeStatus = .failed
            case .partialSuccess:
                outcomeStatus = .partialSuccess
            }
            
            return IntentResponse(
                intentID: intent.id,
                outcome: outcomeStatus,
                summary: "Intent completed: \(intent.objective) - \(outcome.status.rawValue)",
                cycleID: cycleID,
                snapshotID: UUID(),
                timestamp: Date()
            )
            
        } catch {
            return IntentResponse(
                intentID: intent.id,
                outcome: .failed,
                summary: "Pipeline failed: \(error.localizedDescription)",
                cycleID: cycleID,
                snapshotID: nil,
                timestamp: Date()
            )
        }
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
            summary: "Runtime state"
        )
    }
}

// MARK: - DecisionCoordinator Extension for Command Output

extension DecisionCoordinator {
    /// Decide on a command from an intent
    /// Returns a canonical Command for execution
    func decide(intent: Intent) async -> any Command {
        // Convert Intent to PlannerDecision via the existing decide method
        // This is a temporary bridge - full implementation would use DecisionCoordinator directly
        let context = PlannerContext(state: WorldStateModel())
        let taskContext = TaskContext(
            goal: Goal(objective: intent.objective, metadata: intent.metadata),
            agentKind: intent.domain == .code ? .code : (intent.domain == .system ? .system : .os),
            workspaceRoot: "."
        )
        let stateBundle = LoopStateBundle(
            taskContext: taskContext,
            worldState: WorldStateModel(),
            recentFailureCount: 0
        )
        
        guard let decision = self.decide(from: stateBundle) else {
            // Return a default command if decision fails
            return SimpleCommand(id: UUID(), kind: "noop", metadata: CommandMetadata(intentID: intent.id))
        }
        
    // Convert PlannerDecision to Command
        return decision.toCommand()
    }
}

// MARK: - Removed APIs - Use IntentAPI instead

extension RuntimeOrchestrator {
    @available(*, unavailable, message: "Direct action execution removed. Use submitIntent.")
    public nonisolated func performAction(
        surface: RuntimeSurface,
        taskID: String?,
        toolName: String?,
        approvalRequestID: String?,
        intent: ActionIntent,
        action: @MainActor @Sendable () -> ToolResult
    ) -> ToolResult {
        fatalError("Removed")
    }
}

// MARK: - PlannerDecision to Command Conversion
    func toCommand() -> any Command {
        return SimpleCommand(
            id: UUID(),
            kind: self.actionContract.skillName,
            metadata: CommandMetadata(intentID: UUID())
        )
    }
}

/// Simple command implementation for the unified pipeline
public struct SimpleCommand: Command {
    public let id: UUID
    public let kind: String
    public let metadata: CommandMetadata
    
    public init(id: UUID, kind: String, metadata: CommandMetadata) {
        self.id = id
        self.kind = kind
        self.metadata = metadata
    }
}
