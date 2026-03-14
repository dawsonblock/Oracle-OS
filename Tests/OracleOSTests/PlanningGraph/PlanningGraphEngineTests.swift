import Foundation
import Testing
@testable import OracleOS

@Suite("Planning Graph Engine")
struct PlanningGraphEngineTests {

    // MARK: - Edge scoring

    @Test("New edge has default score of 0.5")
    func newEdgeDefaultScore() {
        let edge = PlanningEdge(
            fromState: .repo_loaded,
            toState: .tests_running,
            schema: ActionSchema(name: "run_tests", kind: .runTests)
        )
        #expect(edge.successRate == 0.5)
        #expect(edge.attempts == 0)
        #expect(edge.score == 0.5)
    }

    @Test("Recording success increases success rate")
    func recordSuccessIncreasesRate() {
        var edge = PlanningEdge(
            fromState: .repo_loaded,
            toState: .tests_running,
            schema: ActionSchema(name: "run_tests", kind: .runTests),
            successRate: 0,
            attempts: 0,
            successes: 0
        )
        edge.recordSuccess(latencyMs: 100)
        #expect(edge.successes == 1)
        #expect(edge.attempts == 1)
        #expect(edge.successRate == 1.0)
    }

    @Test("Recording failure decreases success rate")
    func recordFailureDecreasesRate() {
        var edge = PlanningEdge(
            fromState: .repo_loaded,
            toState: .build_failed,
            schema: ActionSchema(name: "build_project", kind: .buildProject),
            successRate: 1.0,
            attempts: 1,
            successes: 1
        )
        edge.recordFailure(latencyMs: 200)
        #expect(edge.successes == 1)
        #expect(edge.attempts == 2)
        #expect(edge.successRate == 0.5)
    }

    // MARK: - Graph queries

    @Test("candidateEdges returns edges sorted by score")
    func candidateEdgesSortedByScore() {
        let good = PlanningEdge(
            fromState: .repo_loaded,
            toState: .tests_running,
            schema: ActionSchema(name: "run_tests", kind: .runTests),
            successRate: 0.9,
            attempts: 10,
            successes: 9
        )
        let poor = PlanningEdge(
            fromState: .repo_loaded,
            toState: .build_failed,
            schema: ActionSchema(name: "build", kind: .buildProject),
            successRate: 0.3,
            attempts: 10,
            successes: 3
        )
        let engine = PlanningGraphEngine(edges: [poor, good])
        let candidates = engine.candidateEdges(from: .repo_loaded)
        #expect(candidates.count == 2)
        #expect(candidates[0].schema.name == "run_tests")
        #expect(candidates[1].schema.name == "build")
    }

    @Test("bestEdge returns highest scoring edge")
    func bestEdgeReturnsHighest() {
        let edge = PlanningEdge(
            fromState: .repo_loaded,
            toState: .tests_running,
            schema: ActionSchema(name: "run_tests", kind: .runTests),
            successRate: 0.9
        )
        let engine = PlanningGraphEngine(edges: [edge])
        let best = engine.bestEdge(from: .repo_loaded)
        #expect(best?.schema.name == "run_tests")
    }

    @Test("bestEdge returns nil for unknown state")
    func bestEdgeNilForUnknownState() {
        let engine = PlanningGraphEngine(edges: [])
        #expect(engine.bestEdge(from: .idle) == nil)
    }

    // MARK: - Mutation

    @Test("addEdge increases edge count")
    func addEdgeIncreasesCount() {
        var engine = PlanningGraphEngine()
        #expect(engine.edgeCount == 0)
        engine.addEdge(PlanningEdge(
            fromState: .idle,
            toState: .repo_loaded,
            schema: ActionSchema(name: "load", kind: .custom)
        ))
        #expect(engine.edgeCount == 1)
    }

    @Test("recordOutcome updates existing edge stats")
    func recordOutcomeUpdatesEdge() {
        let edge = PlanningEdge(
            id: "e1",
            fromState: .repo_loaded,
            toState: .tests_running,
            schema: ActionSchema(name: "run_tests", kind: .runTests),
            successRate: 0,
            attempts: 0,
            successes: 0
        )
        var engine = PlanningGraphEngine(edges: [edge])
        engine.recordOutcome(edgeID: "e1", success: true, latencyMs: 50)
        let candidates = engine.candidateEdges(from: .repo_loaded)
        #expect(candidates.first?.attempts == 1)
        #expect(candidates.first?.successes == 1)
    }

    @Test("pruneWeakEdges removes low-success edges")
    func pruneWeakEdges() {
        let weak = PlanningEdge(
            fromState: .repo_loaded,
            toState: .build_failed,
            schema: ActionSchema(name: "bad", kind: .custom),
            successRate: 0.05,
            attempts: 10,
            successes: 0
        )
        let strong = PlanningEdge(
            fromState: .repo_loaded,
            toState: .tests_running,
            schema: ActionSchema(name: "good", kind: .runTests),
            successRate: 0.9,
            attempts: 10,
            successes: 9
        )
        var engine = PlanningGraphEngine(edges: [weak, strong])
        engine.pruneWeakEdges(belowRate: 0.1, minAttempts: 5)
        let candidates = engine.candidateEdges(from: .repo_loaded)
        #expect(candidates.count == 1)
        #expect(candidates[0].schema.name == "good")
    }

    // MARK: - allStates

    @Test("allStates includes both source and destination states")
    func allStatesIncludesBothEnds() {
        let edge = PlanningEdge(
            fromState: .idle,
            toState: .repo_loaded,
            schema: ActionSchema(name: "load", kind: .custom)
        )
        let engine = PlanningGraphEngine(edges: [edge])
        let states = engine.allStates
        #expect(states.contains(.idle))
        #expect(states.contains(.repo_loaded))
    }
}
