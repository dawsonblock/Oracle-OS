import Foundation

// AgentLoop is now a compatibility wrapper around the IntentAPI runtime spine.
// It accepts legacy construction parameters so older call sites still compile,
// but it no longer owns planning, execution, recovery, or state mutation.
@MainActor
public final class AgentLoop {
    private let orchestrator: any IntentAPI
    private var running = true

    public init(
        orchestrator: any IntentAPI,
        observationProvider: any ObservationProvider,
        executionDriver: any AgentExecutionDriver,
        stateAbstraction: StateAbstraction = StateAbstraction(),
        planner: MainPlanner = MainPlanner(),
        graphStore: GraphStore = GraphStore(),
        policyEngine: PolicyEngine = PolicyEngine(),
        recoveryEngine: RecoveryEngine = RecoveryEngine(),
        memoryStore: UnifiedMemoryStore = UnifiedMemoryStore(),
        skillRegistry: SkillRegistry = .live(),
        repositoryIndexer: RepositoryIndexer = RepositoryIndexer(),
        experimentManager: ExperimentManager = ExperimentManager(),
        automationHost: AutomationHost = .live(),
        browserPageStateBuilder: BrowserPageStateBuilder = BrowserPageStateBuilder(),
        stateMemoryIndex: StateMemoryIndex? = nil,
        worldModel: WorldStateModel = WorldStateModel()
    ) {
        _ = observationProvider
        _ = executionDriver
        _ = stateAbstraction
        _ = planner
        _ = graphStore
        _ = policyEngine
        _ = recoveryEngine
        _ = memoryStore
        _ = skillRegistry
        _ = repositoryIndexer
        _ = experimentManager
        _ = automationHost
        _ = browserPageStateBuilder
        _ = stateMemoryIndex
        _ = worldModel
        self.orchestrator = orchestrator
    }

    public func stop() {
        running = false
    }

    fileprivate func makeIntent(for goal: Goal, surface: RuntimeSurface) -> Intent {
        var metadata: [String: String] = [
            "source": "agent-loop.\(surface.rawValue)",
        ]
        if let app = goal.targetApp {
            metadata["app"] = app
        }
        if let domain = goal.targetDomain {
            metadata["targetDomain"] = domain
            metadata["url"] = domain.hasPrefix("http") ? domain : "https://\(domain)"
        }
        if let taskPhase = goal.targetTaskPhase {
            metadata["targetTaskPhase"] = taskPhase
        }
        if let workspaceRoot = goal.workspaceRoot {
            metadata["workspacePath"] = workspaceRoot
        }

        let domain: IntentDomain = switch goal.preferredAgentKind {
        case .some(.code):
            .code
        case .some(.mixed):
            .mixed
        case .some(.os), .none:
            goal.workspaceRoot == nil ? .ui : .mixed
        }

        return Intent(
            domain: domain,
            objective: goal.description,
            metadata: metadata
        )
    }

    fileprivate func makeOutcome(from response: IntentResponse) -> LoopOutcome {
        let reason: LoopTerminationReason
        switch response.outcome {
        case .success:
            reason = .goalAchieved
        case .partialSuccess:
            reason = .unrecoverableFailure
        case .failed:
            let lowered = response.summary.lowercased()
            if lowered.contains("approval") {
                reason = .approvalTimeout
            } else if lowered.contains("policy") {
                reason = .policyBlocked
            } else if lowered.contains("planning failed") {
                reason = .noViablePlan
            } else {
                reason = .unrecoverableFailure
            }
        case .skipped:
            reason = .noViablePlan
        }

        return LoopOutcome(
            reason: reason,
            finalWorldState: nil,
            steps: response.outcome == .skipped ? 0 : 1,
            recoveries: 0,
            lastFailure: reason == .goalAchieved ? nil : .actionFailed
        )
    }
}
