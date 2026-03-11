import Foundation

public final class StableGraph: @unchecked Sendable {
    public private(set) var nodes: [PlanningStateID: StateNode]
    public private(set) var edges: [String: EdgeTransition]

    public init(
        nodes: [PlanningStateID: StateNode] = [:],
        edges: [String: EdgeTransition] = [:]
    ) {
        self.nodes = nodes
        self.edges = edges
    }

    public func promote(from candidateGraph: CandidateGraph) {
        for (key, node) in candidateGraph.nodes {
            nodes[key] = StateNode(id: node.id, visitCount: node.visitCount)
        }

        for (key, edge) in candidateGraph.edges {
            if edge.attempts >= 5, edge.successRate >= 0.8 {
                edges[key] = EdgeTransition(
                    edgeID: edge.edgeID,
                    fromPlanningStateID: edge.fromPlanningStateID,
                    toPlanningStateID: edge.toPlanningStateID,
                    actionContractID: edge.actionContractID,
                    postconditionClass: edge.postconditionClass,
                    attempts: edge.attempts,
                    successes: edge.successes,
                    latencyTotalMs: edge.latencyTotalMs,
                    failureHistogram: edge.failureHistogram
                )
            }
        }
    }

    public func outgoing(from planningStateID: PlanningStateID) -> [EdgeTransition] {
        edges.values
            .filter { $0.fromPlanningStateID == planningStateID }
            .sorted { $0.cost < $1.cost }
    }
}
