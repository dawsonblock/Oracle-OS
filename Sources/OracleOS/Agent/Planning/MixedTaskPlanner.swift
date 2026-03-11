import Foundation

public final class MixedTaskPlanner: @unchecked Sendable {
    private let osPlanner: OSPlanner
    private let codePlanner: CodePlanner

    public init(
        osPlanner: OSPlanner = OSPlanner(),
        codePlanner: CodePlanner = CodePlanner()
    ) {
        self.osPlanner = osPlanner
        self.codePlanner = codePlanner
    }

    public func nextStep(
        taskContext: TaskContext,
        worldState: WorldState,
        graphStore: GraphStore,
        memoryStore: AppMemoryStore
    ) -> PlannerDecision? {
        let description = taskContext.goal.description.lowercased()
        let needsFinder = description.contains("finder") || description.contains("open repo")

        if needsFinder, (worldState.observation.app ?? "").localizedCaseInsensitiveContains("finder") == false {
            let goal = Goal(
                description: taskContext.goal.description,
                targetApp: "Finder",
                targetDomain: nil,
                targetTaskPhase: taskContext.goal.targetTaskPhase,
                workspaceRoot: taskContext.workspaceRoot,
                preferredAgentKind: .os
            )
            guard let step = osPlanner.nextStep(goal: goal, worldState: worldState, graphStore: graphStore) else {
                return nil
            }
            return PlannerDecision(
                agentKind: .os,
                skillName: step.skillName,
                plannerFamily: .mixed,
                stepPhase: .handoff,
                actionContract: step.actionContract,
                source: step.source,
                pathEdgeIDs: step.pathEdgeIDs,
                currentEdgeID: step.currentEdgeID,
                semanticQuery: step.semanticQuery,
                notes: ["mixed-task OS handoff"] + step.notes,
                recoveryTagged: step.recoveryTagged,
                recoveryStrategy: step.recoveryStrategy,
                recoverySource: step.recoverySource
            )
        }

        guard let codeStep = codePlanner.nextStep(
            taskContext: taskContext,
            worldState: worldState,
            graphStore: graphStore,
            memoryStore: memoryStore
        ) else {
            return nil
        }

        return PlannerDecision(
            agentKind: .code,
            skillName: codeStep.skillName,
            plannerFamily: .mixed,
            stepPhase: .engineering,
            actionContract: codeStep.actionContract,
            source: codeStep.source,
            pathEdgeIDs: codeStep.pathEdgeIDs,
            currentEdgeID: codeStep.currentEdgeID,
            semanticQuery: codeStep.semanticQuery,
            notes: ["mixed-task code handoff"] + codeStep.notes,
            recoveryTagged: codeStep.recoveryTagged,
            recoveryStrategy: codeStep.recoveryStrategy,
            recoverySource: codeStep.recoverySource
        )
    }
}
