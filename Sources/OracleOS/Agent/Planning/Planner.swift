import Foundation

public final class Planner: @unchecked Sendable {
    private var currentGoal: Goal?
    public let workflowIndex: WorkflowIndex
    private let osPlanner: OSPlanner
    private let codePlanner: CodePlanner
    private let mixedTaskPlanner: MixedTaskPlanner

    public init(
        workflowIndex: WorkflowIndex? = nil,
        osPlanner: OSPlanner? = nil,
        codePlanner: CodePlanner? = nil,
        mixedTaskPlanner: MixedTaskPlanner? = nil
    ) {
        let sharedWorkflowIndex = workflowIndex ?? WorkflowIndex()
        let sharedGraphPlanner = GraphPlanner(maxDepth: 6, beamWidth: 5)
        let sharedWorkflowRetriever = WorkflowRetriever()
        let sharedWorkflowExecutor = WorkflowExecutor()
        let resolvedOSPlanner = osPlanner ?? OSPlanner(
            graphPlanner: sharedGraphPlanner,
            workflowIndex: sharedWorkflowIndex,
            workflowRetriever: sharedWorkflowRetriever,
            workflowExecutor: sharedWorkflowExecutor
        )
        let resolvedCodePlanner = codePlanner ?? CodePlanner(
            graphPlanner: sharedGraphPlanner,
            workflowIndex: sharedWorkflowIndex,
            workflowRetriever: sharedWorkflowRetriever,
            workflowExecutor: sharedWorkflowExecutor
        )
        self.workflowIndex = sharedWorkflowIndex
        self.osPlanner = resolvedOSPlanner
        self.codePlanner = resolvedCodePlanner
        self.mixedTaskPlanner = mixedTaskPlanner ?? MixedTaskPlanner(
            osPlanner: resolvedOSPlanner,
            codePlanner: resolvedCodePlanner
        )
    }

    public func setGoal(_ goal: Goal) {
        currentGoal = goal
    }

    public func interpretGoal(_ description: String) -> Goal {
        let lowercased = description.lowercased()
        let targetApp: String?
        if lowercased.contains("gmail") || lowercased.contains("browser") || lowercased.contains("chrome") {
            targetApp = "Google Chrome"
        } else if lowercased.contains("finder") {
            targetApp = "Finder"
        } else {
            targetApp = nil
        }

        let targetDomain: String?
        if lowercased.contains("gmail") {
            targetDomain = "mail.google.com"
        } else if lowercased.contains("slack") {
            targetDomain = "slack.com"
        } else {
            targetDomain = nil
        }

        let targetTaskPhase: String?
        if lowercased.contains("compose") {
            targetTaskPhase = "compose"
        } else if lowercased.contains("inbox") {
            targetTaskPhase = "browse"
        } else if lowercased.contains("save") {
            targetTaskPhase = "save"
        } else if lowercased.contains("rename") {
            targetTaskPhase = "rename"
        } else {
            targetTaskPhase = nil
        }

        return Goal(
            description: description,
            targetApp: targetApp,
            targetDomain: targetDomain,
            targetTaskPhase: targetTaskPhase
        )
    }

    public func goalReached(state: PlanningState) -> Bool {
        guard let currentGoal else { return false }
        return Self.goalMatchScore(state: state, goal: currentGoal) >= 1
    }

    public func nextStep(
        worldState: WorldState,
        graphStore: GraphStore,
        memoryStore: AppMemoryStore = AppMemoryStore()
    ) -> PlannerDecision? {
        guard let currentGoal else { return nil }
        let workspaceRoot = currentGoal.workspaceRoot.map { URL(fileURLWithPath: $0, isDirectory: true) }
        let taskContext = TaskContext.from(goal: currentGoal, workspaceRoot: workspaceRoot)

        switch taskContext.agentKind {
        case .os:
            return osPlanner.nextStep(
                taskContext: taskContext,
                worldState: worldState,
                graphStore: graphStore,
                memoryStore: memoryStore
            )
        case .code:
            return codePlanner.nextStep(
                taskContext: taskContext,
                worldState: worldState,
                graphStore: graphStore,
                memoryStore: memoryStore
            )
        case .mixed:
            return mixedTaskPlanner.nextStep(
                taskContext: taskContext,
                worldState: worldState,
                graphStore: graphStore,
                memoryStore: memoryStore
            )
        }
    }

    public func nextAction(
        worldState: WorldState,
        graphStore: GraphStore
    ) -> ActionContract? {
        nextStep(worldState: worldState, graphStore: graphStore)?.actionContract
    }

    public func plan(goal: String) -> Plan {
        let interpretedGoal = interpretGoal(goal)
        setGoal(interpretedGoal)
        return Plan(goal: goal, steps: ["graph-aware"])
    }

    public static func goalMatchScore(state: PlanningState, goal: Goal) -> Double {
        var matched = 0.0
        var possible = 0.0

        if let targetApp = goal.targetApp {
            possible += 1
            if state.appID == targetApp { matched += 1 }
        }
        if let targetDomain = goal.targetDomain {
            possible += 1
            if state.domain == targetDomain { matched += 1 }
        }
        if let targetTaskPhase = goal.targetTaskPhase {
            possible += 1
            if state.taskPhase == targetTaskPhase { matched += 1 }
        }

        guard possible > 0 else { return 0 }
        return matched / possible
    }
}
