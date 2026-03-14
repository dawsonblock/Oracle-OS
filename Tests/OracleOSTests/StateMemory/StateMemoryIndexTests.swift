import Foundation
import Testing
@testable import OracleOS

@Suite("State Memory Index")
struct StateMemoryIndexTests {

    // MARK: - Lookup

    @Test("Empty index returns nil for any state")
    func emptyIndexReturnsNil() {
        let index = StateMemoryIndex()
        let state = CompressedUIState(app: "Finder", elements: [])
        #expect(index.lookup(state) == nil)
        #expect(index.bestAction(for: state) == nil)
    }

    @Test("Recording an action makes it retrievable")
    func recordMakesRetrievable() {
        let index = StateMemoryIndex()
        let state = CompressedUIState(
            app: "Slack",
            elements: [
                SemanticElement(id: "btn-1", kind: .button, label: "Send"),
            ]
        )
        index.record(state: state, actionName: "click_Send", success: true)
        let entry = index.lookup(state)
        #expect(entry != nil)
        #expect(entry?.actionStats["click_Send"]?.attempts == 1)
        #expect(entry?.actionStats["click_Send"]?.successes == 1)
    }

    @Test("bestAction returns highest success rate action")
    func bestActionReturnsHighestRate() {
        let index = StateMemoryIndex()
        let state = CompressedUIState(
            app: "Mail",
            elements: [
                SemanticElement(id: "btn-send", kind: .button, label: "Send"),
                SemanticElement(id: "btn-save", kind: .button, label: "Save"),
            ]
        )
        // Record send with 100% success
        index.record(state: state, actionName: "click_Send", success: true)
        index.record(state: state, actionName: "click_Send", success: true)
        // Record save with 50% success
        index.record(state: state, actionName: "click_Save", success: true)
        index.record(state: state, actionName: "click_Save", success: false)

        #expect(index.bestAction(for: state) == "click_Send")
    }

    // MARK: - State signature

    @Test("Same elements produce same signature")
    func sameElementsSameSignature() {
        let state1 = CompressedUIState(
            app: "Finder",
            elements: [
                SemanticElement(id: "a", kind: .button, label: "Open"),
                SemanticElement(id: "b", kind: .input, label: "Search"),
            ]
        )
        let state2 = CompressedUIState(
            app: "Finder",
            elements: [
                SemanticElement(id: "a", kind: .button, label: "Open"),
                SemanticElement(id: "b", kind: .input, label: "Search"),
            ]
        )
        let sig1 = StateSignature(from: state1)
        let sig2 = StateSignature(from: state2)
        #expect(sig1 == sig2)
    }

    @Test("Different elements produce different signatures")
    func differentElementsDifferentSignature() {
        let state1 = CompressedUIState(
            app: "Finder",
            elements: [
                SemanticElement(id: "a", kind: .button, label: "Open"),
            ]
        )
        let state2 = CompressedUIState(
            app: "Finder",
            elements: [
                SemanticElement(id: "a", kind: .button, label: "Close"),
            ]
        )
        let sig1 = StateSignature(from: state1)
        let sig2 = StateSignature(from: state2)
        #expect(sig1 != sig2)
    }

    // MARK: - Eviction

    @Test("Index evicts oldest entries when capacity exceeded")
    func evictsOldestEntries() {
        let index = StateMemoryIndex(maxEntries: 2)
        let state1 = CompressedUIState(app: "App1", elements: [])
        let state2 = CompressedUIState(app: "App2", elements: [])
        let state3 = CompressedUIState(app: "App3", elements: [])

        index.record(state: state1, actionName: "a", success: true)
        index.record(state: state2, actionName: "b", success: true)
        #expect(index.count == 2)

        index.record(state: state3, actionName: "c", success: true)
        #expect(index.count == 2)
        // state1 was the oldest and should have been evicted
        #expect(index.lookup(state1) == nil)
        #expect(index.lookup(state3) != nil)
    }

    // MARK: - ActionStats

    @Test("ActionStats computes correct success rate")
    func actionStatsSuccessRate() {
        var stats = ActionStats(attempts: 4, successes: 3)
        #expect(stats.successRate == 0.75)
        stats.attempts += 1
        #expect(stats.successRate == 0.6)
    }

    @Test("ActionStats with zero attempts returns zero rate")
    func actionStatsZeroAttempts() {
        let stats = ActionStats()
        #expect(stats.successRate == 0)
    }
}
