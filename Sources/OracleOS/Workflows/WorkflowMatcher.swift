import Foundation

/// Matches workflow patterns to the current task-graph node and proposes edges.
///
/// When the planner reaches a graph node whose ``AbstractTaskState`` matches
/// the start of a known workflow pattern, the matcher proposes the subsequent
/// edges automatically. This converts learned workflows into reusable subgraph
/// templates.
public struct WorkflowMatcher: Sendable {
    public init() {}

    /// A matched workflow with the proposed next actions.
    public struct Match: Sendable {
        public let workflowID: String
        public let goalPattern: String
        public let proposedActions: [String]
        public let confidence: Double
    }

    /// Find workflows whose opening abstract state matches the current node.
    public func match(
        currentState: AbstractTaskState,
        workflowIndex: WorkflowIndex
    ) -> [Match] {
        let allPlans = workflowIndex.allPlans()
        return allPlans.compactMap { plan -> Match? in
            guard plan.promotionStatus == .promoted else { return nil }
            guard let firstStep = plan.steps.first else { return nil }

            let stepState = abstractStateForStep(firstStep)
            guard stepState == currentState else { return nil }

            let proposedActions = plan.steps.dropFirst().prefix(5).map {
                $0.actionContract.skillName
            }
            guard !proposedActions.isEmpty else { return nil }

            return Match(
                workflowID: plan.id,
                goalPattern: plan.goalPattern,
                proposedActions: Array(proposedActions),
                confidence: plan.successRate * plan.replayValidationSuccess
            )
        }
        .sorted { $0.confidence > $1.confidence }
    }

    /// Propose candidate edges from the current node based on matched workflows.
    public func proposeEdges(
        currentNode: TaskNode,
        workflowIndex: WorkflowIndex,
        taskGraphStore: TaskGraphStore
    ) -> [TaskEdge] {
        let matches = match(
            currentState: currentNode.abstractState,
            workflowIndex: workflowIndex
        )
        var proposedEdges: [TaskEdge] = []
        for match in matches {
            var matchUsed = false
            for action in match.proposedActions {
                if let edge = taskGraphStore.addCandidateEdge(
                    action: action,
                    toAbstractState: projectedState(for: action, from: currentNode.abstractState),
                    toPlanningStateID: PlanningStateID(rawValue: "workflow-\(match.workflowID)-\(action)")
                ) {
                    matchUsed = true
                    proposedEdges.append(edge)
                }
            }
            if matchUsed {
                currentNode.attachWorkflowMatch(match.workflowID)
            }
        }
        return proposedEdges
    }

    // MARK: - Private

    private func abstractStateForStep(_ step: WorkflowStep) -> AbstractTaskState {
        let skill = step.actionContract.skillName.lowercased()
        if skill.contains("test") && skill.contains("run") { return .testsRunning }
        if skill.contains("test") && skill.contains("fail") { return .failingTestIdentified }
        if skill.contains("build") && skill.contains("run") { return .buildRunning }
        if skill.contains("build") && skill.contains("fail") { return .buildFailed }
        if skill.contains("patch") && skill.contains("apply") { return .candidatePatchApplied }
        if skill.contains("patch") && skill.contains("generate") { return .candidatePatchGenerated }
        if skill.contains("repo") || skill.contains("clone") { return .repoLoaded }
        if skill.contains("login") { return .loginPageDetected }
        if skill.contains("navigate") { return .navigationCompleted }
        return .taskStarted
    }

    private func projectedState(for action: String, from current: AbstractTaskState) -> AbstractTaskState {
        let lowered = action.lowercased()
        if lowered.contains("test") && lowered.contains("run") { return .testsRunning }
        if lowered.contains("test") && lowered.contains("pass") { return .testsPassed }
        if lowered.contains("build") { return .buildRunning }
        if lowered.contains("patch") { return .candidatePatchApplied }
        if lowered.contains("fail") { return .failingTestIdentified }
        if lowered.contains("navigate") { return .navigationCompleted }
        return current
    }
}
