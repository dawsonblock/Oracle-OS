// PlanningGraphEngine.swift — Deterministic planning graph for action selection.
//
// The planner operates over a finite action graph instead of generating
// arbitrary step sequences. Each edge represents a valid state transition
// with an associated ``ActionSchema``.
//
// Core algorithm:
//   current_state → query graph edges → rank edges → execute best edge
//
// Edge scoring:
//   score = success_rate − cost_penalty − latency_penalty

import Foundation

// MARK: - Planning edge

/// A directed edge in the planning graph connecting two ``AbstractTaskState``
/// nodes via a concrete ``ActionSchema``.
public struct PlanningEdge: Sendable, Codable, Identifiable {
    public let id: String
    public let fromState: AbstractTaskState
    public let toState: AbstractTaskState
    public let schema: ActionSchema

    /// Running average success rate (0–1).
    public private(set) var successRate: Double
    /// Cumulative execution count.
    public private(set) var attempts: Int
    /// Cumulative success count.
    public private(set) var successes: Int
    /// Mean latency in milliseconds.
    public private(set) var meanLatencyMs: Double

    public init(
        id: String = UUID().uuidString,
        fromState: AbstractTaskState,
        toState: AbstractTaskState,
        schema: ActionSchema,
        successRate: Double = 0.5,
        attempts: Int = 0,
        successes: Int = 0,
        meanLatencyMs: Double = 0
    ) {
        self.id = id
        self.fromState = fromState
        self.toState = toState
        self.schema = schema
        self.successRate = successRate
        self.attempts = attempts
        self.successes = successes
        self.meanLatencyMs = meanLatencyMs
    }

    /// Record a successful traversal.
    public mutating func recordSuccess(latencyMs: Double) {
        successes += 1
        attempts += 1
        successRate = Double(successes) / Double(attempts)
        meanLatencyMs = (meanLatencyMs * Double(attempts - 1) + latencyMs) / Double(attempts)
    }

    /// Record a failed traversal.
    public mutating func recordFailure(latencyMs: Double) {
        attempts += 1
        successRate = Double(successes) / Double(attempts)
        meanLatencyMs = (meanLatencyMs * Double(attempts - 1) + latencyMs) / Double(attempts)
    }

    /// Composite score used for ranking.
    ///
    /// Higher is better.
    public var score: Double {
        let costPenalty = meanLatencyMs / 10_000.0 // normalise to seconds
        return successRate - costPenalty
    }
}

// MARK: - Planning graph engine

/// Stores the set of allowed state transitions and ranks candidate
/// actions for a given abstract state.
///
/// The engine deliberately restricts the planner to edges that appear
/// in the graph, preventing unconstrained action generation.
public struct PlanningGraphEngine: Sendable {
    /// All known edges keyed by source state.
    private var edgesBySource: [AbstractTaskState: [PlanningEdge]]

    public init(edges: [PlanningEdge] = []) {
        var map: [AbstractTaskState: [PlanningEdge]] = [:]
        for edge in edges {
            map[edge.fromState, default: []].append(edge)
        }
        self.edgesBySource = map
    }

    // MARK: - Query

    /// Return all edges originating from the given state, ranked by score
    /// (best first).
    public func candidateEdges(from state: AbstractTaskState) -> [PlanningEdge] {
        (edgesBySource[state] ?? []).sorted { $0.score > $1.score }
    }

    /// Return the single best edge from the given state, if any.
    public func bestEdge(from state: AbstractTaskState) -> PlanningEdge? {
        candidateEdges(from: state).first
    }

    /// Return all edges that lead to the given goal state.
    public func edgesLeadingTo(_ goal: AbstractTaskState) -> [PlanningEdge] {
        edgesBySource.values.flatMap { $0 }.filter { $0.toState == goal }
    }

    /// Total number of edges in the graph.
    public var edgeCount: Int {
        edgesBySource.values.reduce(0) { $0 + $1.count }
    }

    /// All unique states that appear as source or destination.
    public var allStates: Set<AbstractTaskState> {
        var states = Set(edgesBySource.keys)
        for edges in edgesBySource.values {
            for edge in edges {
                states.insert(edge.toState)
            }
        }
        return states
    }

    // MARK: - Mutation

    /// Add or update an edge in the graph.
    public mutating func addEdge(_ edge: PlanningEdge) {
        edgesBySource[edge.fromState, default: []].append(edge)
    }

    /// Record a traversal outcome on an existing edge.
    public mutating func recordOutcome(
        edgeID: String,
        success: Bool,
        latencyMs: Double
    ) {
        for state in edgesBySource.keys {
            if let idx = edgesBySource[state]?.firstIndex(where: { $0.id == edgeID }) {
                if success {
                    edgesBySource[state]![idx].recordSuccess(latencyMs: latencyMs)
                } else {
                    edgesBySource[state]![idx].recordFailure(latencyMs: latencyMs)
                }
                return
            }
        }
    }

    /// Record a traversal outcome by source state, destination state, and schema.
    ///
    /// If an edge matching `fromState`/`toState`/`schema.name` exists it is
    /// updated. Otherwise a new edge is added so the planning graph grows
    /// organically from execution experience.
    public mutating func recordOutcome(
        fromState: String,
        toState: String,
        schema: ActionSchema,
        success: Bool
    ) {
        guard let fromAbstract = AbstractTaskState(rawValue: fromState),
              let toAbstract = AbstractTaskState(rawValue: toState)
        else { return }

        // Try to find an existing edge for this transition.
        if let idx = edgesBySource[fromAbstract]?.firstIndex(where: {
            $0.toState == toAbstract && $0.schema.name == schema.name
        }) {
            if success {
                edgesBySource[fromAbstract]![idx].recordSuccess(latencyMs: 0)
            } else {
                edgesBySource[fromAbstract]![idx].recordFailure(latencyMs: 0)
            }
            return
        }

        // No existing edge — create one seeded with the outcome.
        let edge = PlanningEdge(
            fromState: fromAbstract,
            toState: toAbstract,
            schema: schema,
            successRate: success ? 1.0 : 0.0,
            attempts: 1,
            successes: success ? 1 : 0
        )
        addEdge(edge)
    }

    /// Remove edges whose success rate has dropped below a threshold
    /// and that have been attempted at least `minAttempts` times.
    public mutating func pruneWeakEdges(
        belowRate: Double = 0.1,
        minAttempts: Int = 5
    ) {
        for state in edgesBySource.keys {
            edgesBySource[state]?.removeAll { edge in
                edge.attempts >= minAttempts && edge.successRate < belowRate
            }
        }
    }
}
