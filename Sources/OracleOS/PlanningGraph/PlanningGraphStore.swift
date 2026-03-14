// PlanningGraphStore.swift — Reference-type wrapper around PlanningGraphEngine.
//
// PlanningGraphEngine is a value type for clean, deterministic semantics.
// This store provides reference semantics so the same graph instance can
// be shared between VerifiedActionExecutor (writes) and the planner
// (reads) without value-copy divergence.

import Foundation

@MainActor
public final class PlanningGraphStore {
    private var engine: PlanningGraphEngine

    public init(engine: PlanningGraphEngine = PlanningGraphEngine()) {
        self.engine = engine
    }

    // MARK: - Query (forwarded to engine)

    /// Return all edges originating from the given state, ranked by score.
    public func candidateEdges(from state: AbstractTaskState) -> [PlanningEdge] {
        engine.candidateEdges(from: state)
    }

    /// Return the single best edge from the given state, if any.
    public func bestEdge(from state: AbstractTaskState) -> PlanningEdge? {
        engine.bestEdge(from: state)
    }

    /// Return all edges that lead to the given goal state.
    public func edgesLeadingTo(_ goal: AbstractTaskState) -> [PlanningEdge] {
        engine.edgesLeadingTo(goal)
    }

    /// Total number of edges in the graph.
    public var edgeCount: Int { engine.edgeCount }

    /// All unique states that appear as source or destination.
    public var allStates: Set<AbstractTaskState> { engine.allStates }

    // MARK: - Mutation (forwarded to engine)

    /// Add or update an edge in the graph.
    public func addEdge(_ edge: PlanningEdge) {
        engine.addEdge(edge)
    }

    /// Record a traversal outcome on an existing edge by ID.
    public func recordOutcome(edgeID: String, success: Bool, latencyMs: Double) {
        engine.recordOutcome(edgeID: edgeID, success: success, latencyMs: latencyMs)
    }

    /// Record a traversal outcome by source state, destination state, and schema.
    public func recordOutcome(
        fromState: String,
        toState: String,
        schema: ActionSchema,
        success: Bool,
        latencyMs: Double = 0
    ) {
        engine.recordOutcome(
            fromState: fromState,
            toState: toState,
            schema: schema,
            success: success,
            latencyMs: latencyMs
        )
    }

    /// Remove edges whose success rate has dropped below a threshold.
    public func pruneWeakEdges(belowRate: Double = 0.1, minAttempts: Int = 5) {
        engine.pruneWeakEdges(belowRate: belowRate, minAttempts: minAttempts)
    }
}
