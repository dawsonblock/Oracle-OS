import Foundation

/// A high-level approach the agent can adopt for a task. The strategy layer
/// sits above the planner and constrains which planning operators are considered.
///
///     goal → strategy selection → planning → execution
///
/// By selecting a strategy first, the planner avoids mixing unrelated operators
/// and produces more focused plans.
public struct TaskStrategy: Sendable {
    public let kind: TaskStrategyKind
    public let description: String
    public let applicableAgentKinds: [AgentKind]
    public let requiredConditions: [StrategyCondition]
    public let priorityScore: Double
    public let notes: [String]

    public init(
        kind: TaskStrategyKind,
        description: String,
        applicableAgentKinds: [AgentKind] = AgentKind.allCases,
        requiredConditions: [StrategyCondition] = [],
        priorityScore: Double = 0.5,
        notes: [String] = []
    ) {
        self.kind = kind
        self.description = description
        self.applicableAgentKinds = applicableAgentKinds
        self.requiredConditions = requiredConditions
        self.priorityScore = priorityScore
        self.notes = notes
    }
}

public enum TaskStrategyKind: String, Sendable, CaseIterable {
    case workflowReuse = "workflow_reuse"
    case codeRepair = "code_repair"
    case uiExploration = "ui_exploration"
    case configurationDiagnosis = "configuration_diagnosis"
    case dependencyRepair = "dependency_repair"
    case buildFix = "build_fix"
    case testFix = "test_fix"
    case navigation = "navigation"
    case recovery = "recovery"
}

public enum StrategyCondition: String, Sendable {
    case repositoryOpen = "repository_open"
    case buildFailing = "build_failing"
    case testsFailing = "tests_failing"
    case modalPresent = "modal_present"
    case wrongApplication = "wrong_application"
    case workflowAvailable = "workflow_available"
    case gitDirty = "git_dirty"
    case patchApplied = "patch_applied"
}
