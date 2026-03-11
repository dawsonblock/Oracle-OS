import Foundation

public struct PathScorer: Sendable {
    public init() {}

    public func score(
        edge: EdgeTransition,
        actionContract: ActionContract?,
        goal: Goal,
        memoryBias: Double = 0
    ) -> Double {
        let successScore = edge.successRate
        let recencyScore = normalizedRecency(edge.lastSuccessTimestamp ?? edge.lastAttemptTimestamp)
        let boundedMemoryBias = max(0, min(1, memoryBias))
        let latencyScore = max(0, 1 - min(edge.averageLatencyMs / 2_000.0, 1))
        let relevanceBonus = goalRelevance(edge: edge, actionContract: actionContract, goal: goal)

        return (0.4 * successScore)
            + (0.3 * recencyScore)
            + (0.2 * boundedMemoryBias)
            + (0.1 * latencyScore)
            + relevanceBonus
    }

    private func normalizedRecency(_ timestamp: TimeInterval?) -> Double {
        guard let timestamp else { return 0 }
        let age = max(Date().timeIntervalSince1970 - timestamp, 0)
        let sevenDays: Double = 7 * 24 * 60 * 60
        return max(0, 1 - min(age / sevenDays, 1))
    }

    private func goalRelevance(
        edge: EdgeTransition,
        actionContract: ActionContract?,
        goal: Goal
    ) -> Double {
        let description = goal.description.lowercased()
        var relevance = 0.0

        if let commandCategory = edge.commandCategory {
            if description.contains("test"), commandCategory == CodeCommandCategory.test.rawValue {
                relevance += 0.12
            }
            if (description.contains("build") || description.contains("compile")),
               commandCategory == CodeCommandCategory.build.rawValue {
                relevance += 0.12
            }
            if description.contains("commit"), commandCategory == CodeCommandCategory.gitCommit.rawValue {
                relevance += 0.12
            }
            if description.contains("branch"), commandCategory == CodeCommandCategory.gitBranch.rawValue {
                relevance += 0.12
            }
            if description.contains("push"), commandCategory == CodeCommandCategory.gitPush.rawValue {
                relevance += 0.12
            }
        }

        if let label = actionContract?.targetLabel?.lowercased(), !label.isEmpty, description.contains(label) {
            relevance += 0.1
        }
        if let role = actionContract?.targetRole?.lowercased(), !role.isEmpty, description.contains(role) {
            relevance += 0.05
        }
        if let preferredAgentKind = goal.preferredAgentKind, edge.agentKind == preferredAgentKind {
            relevance += 0.05
        }

        return min(relevance, 0.2)
    }
}
