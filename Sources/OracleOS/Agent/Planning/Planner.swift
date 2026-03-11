import Foundation

public final class Planner {
    private var currentGoal: Goal?

    public init() {}

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

        if let targetApp = currentGoal.targetApp, state.appID != targetApp {
            return false
        }
        if let targetDomain = currentGoal.targetDomain, state.domain != targetDomain {
            return false
        }
        if let targetTaskPhase = currentGoal.targetTaskPhase, state.taskPhase != targetTaskPhase {
            return false
        }

        return true
    }

    public func nextAction(
        worldState: WorldState,
        graphStore: GraphStore
    ) -> ActionContract? {
        let candidateEdges = graphStore.outgoingEdges(from: worldState.planningState.id)
        for edge in candidateEdges {
            if let contract = graphStore.actionContract(for: edge.actionContractID) {
                return contract
            }
        }

        return fallbackAction(for: worldState)
    }

    public func plan(goal: String) -> Plan {
        let interpretedGoal = interpretGoal(goal)
        setGoal(interpretedGoal)
        return Plan(goal: goal, steps: ["state-driven"])
    }

    private func fallbackAction(for worldState: WorldState) -> ActionContract? {
        let planningState = worldState.planningState
        let targetLabel = planningState.controlContext ?? planningState.windowClass

        return ActionContract(
            id: [
                planningState.appID,
                planningState.taskPhase ?? "explore",
                targetLabel ?? "fallback",
            ].joined(separator: "|"),
            skillName: "explore",
            targetRole: planningState.focusedRole,
            targetLabel: targetLabel,
            locatorStrategy: "exploration"
        )
    }
}
